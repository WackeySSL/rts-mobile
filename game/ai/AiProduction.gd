class_name AiProduction
extends RefCounted
## The opponent's production manager (ADR 0030 sections 1, 4, 5 and 6, plan row P178), slot ECONOMY
## after the economy, on the same view. It keeps both unit queues (infantry and vehicles) at
## `queue_target` with units of the army's roles. It reads the match only through the `PlayerView`
## and `AiMemory`, copies its def and level into ints and keeps no Resource. A run:
## - counts this player's unit QUEUEs already in `out` (the economy's tankers of this think, which
##   the view does not show) toward the queue room and the unit cap;
## - spends at most `maxi(view.credits - memory.reserve_credits, 0)`: the economy already queued
##   and keeps credits for its next structure or tanker, and its QUEUEs apply first;
## - while `memory.scout_wanted` is set and no unit of that type waits in its queue or lives
##   (intel's field is from the INTEL slot before, so a scout that spawned since still shows),
##   queues one scout ahead of the draw (at most one a think, counted toward the queue's room); a
##   scout it cannot pay yet keeps its own tab (vehicles) closed to the draw, the infantry goes on;
## - then draws roles among those whose type can be queued now (a producer of its tab, its
##   requirement owned, room in the queue and under the unit cap, affordable), with the weights of
##   the level's tier, from the controller's stream: one draw for each unit queued.
## `counter_percent` of the weight moves to the role whose weapon does most against the armour
## class intel has seen most (units only, types first seen at least `reaction_ticks` ago; the class
## with the most units, the lowest class among equals). The role is chosen among those that can be
## queued now, by the percent of the type that would be queued; none, no shift. A level with 0
## (Easy) draws on the plain weights. Every Command checks `can_send`, then `spent`.
## One pass over the own rows (the census), skipped when nothing could be queued.

## A type the roster lacks.
const _NONE: int = PlayerView.MISSING
const _ROLES: int = OpponentDef.ROLES

## Passes over the view's own rows the last run made (`OpponentAi` adds it to `work`).
var passes: int = 0
## Units queued over the match, the scouts among them.
var queued: int = 0
var scouts_queued: int = 0
## The credits the QUEUEs of the last run cost (`AiEconomy.mend` measures the credits left by it).
var spent_credits: int = 0
## Units queued per role over the match (`OpponentDef.Role`).
var role_queued: PackedInt32Array = PackedInt32Array()

var _player: int = 0
var _role_ids: Array[StringName] = []
var _vehicle_ids: Array[StringName] = []
var _weights: PackedInt32Array = PackedInt32Array()
var _queue_target: int = 0
var _counter_percent: int = 0
var _reaction_ticks: int = 0

## The types as indexes of the view's roster, found on the first run.
var _resolved: bool = false
var _role_types: PackedInt32Array = PackedInt32Array()
var _vehicle_types: PackedInt32Array = PackedInt32Array()

## Read off the view by each run, used only inside it.
var _owned: PackedInt32Array = PackedInt32Array()
var _producers: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
var _armour: PackedInt32Array = PackedInt32Array()
var _types: PackedInt32Array = PackedInt32Array()
var _shares: PackedInt32Array = PackedInt32Array()
var _units: int = 0
var _room: int = 0
var _budget: int = 0
var _seen_class: int = -1
var _closed_tab: int = -1


## A production manager for `player_id` on `def` at `level`, which it copies and does not keep.
static func create(def: OpponentDef, level: AiDifficultyDef, player_id: int) -> AiProduction:
	var production: AiProduction = AiProduction.new()
	var tier: int = clampi(level.build_order_tier, 0, OpponentDef.TIERS - 1)
	production._player = player_id
	production._role_ids.resize(_ROLES)
	production._role_ids[OpponentDef.Role.ANTI_INFANTRY] = def.anti_infantry_type
	production._role_ids[OpponentDef.Role.ANTI_VEHICLE] = &""
	production._role_ids[OpponentDef.Role.TANK] = def.tank_type
	production._role_ids[OpponentDef.Role.ARTILLERY] = def.artillery_type
	production._vehicle_ids = def.anti_vehicle_types.duplicate()
	for role: int in _ROLES:
		production._weights.append(def.role_weight(tier, role))
	production.role_queued.resize(_ROLES)
	production._types.resize(_ROLES)
	production._shares.resize(_ROLES)
	production._queue_target = def.queue_target
	production._counter_percent = clampi(level.counter_percent, 0, 100)
	production._reaction_ticks = level.reaction_ticks
	return production


func run(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	passes = 0
	spent_credits = 0
	_resolve(view)
	if view.queue_count.size() < PlayerView.TABS:
		return
	_room = mini(_queue_target, view.queue_slots)
	_count_sent(view, out)
	var scout: int = _scout_wanted(view, memory)
	if scout == _NONE and not _has_room(view):
		return
	if not _take_census(view):
		return
	if scout != _NONE and _owned[scout] > 0:
		scout = _NONE
	_budget = maxi(view.credits - memory.reserve_credits, 0)
	_closed_tab = -1
	if scout != _NONE and _queue_scout(view, memory, out, scout):
		_closed_tab = view.type_tab[scout]
	_seen_class = _most_seen_class(view, memory)
	for _step: int in _room * PlayerView.TABS:
		if not _queue_drawn(view, memory, rng, out):
			return


## The types as indexes of the view's roster, once.
func _resolve(view: PlayerView) -> void:
	if _resolved:
		return
	_resolved = true
	for id: StringName in _role_ids:
		_role_types.append(view.type_index_of(id) if id != &"" else _NONE)
	for id: StringName in _vehicle_ids:
		_vehicle_types.append(view.type_index_of(id))


## `_added` from the unit QUEUEs of this player already in `out` (this think's, from the economy).
func _count_sent(view: PlayerView, out: Array[Command]) -> void:
	_added.resize(PlayerView.TABS)
	_added.fill(0)
	for command: Command in out:
		if command.type != Command.Type.QUEUE or command.player_id != _player:
			continue
		var type: int = command.payload[0]
		if type >= 0 and type < view.type_tab.size():
			var tab: int = view.type_tab[type]
			if tab == PlayerView.Tab.INFANTRY or tab == PlayerView.Tab.VEHICLES:
				_added[tab] += 1


## The scout's type index while intel wants one and none waits in a queue, else MISSING.
func _scout_wanted(view: PlayerView, memory: AiMemory) -> int:
	var type: int = memory.scout_wanted
	if type < 0 or type >= view.type_tab.size():
		return _NONE
	var tab: int = view.type_tab[type]
	if tab != PlayerView.Tab.INFANTRY and tab != PlayerView.Tab.VEHICLES:
		return _NONE
	for slot: int in view.queue_count[tab]:
		if view.queue_type[tab * view.queue_slots + slot] == type:
			return _NONE
	return type


## Whether either unit queue has room for one more.
func _has_room(view: PlayerView) -> bool:
	for tab: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES]:
		if view.queue_count[tab] + _added[tab] < _room:
			return true
	return false


## One pass over the player's rows: the unit count and the producers of each tab. False when the
## player has no producer of a unit tab.
func _take_census(view: PlayerView) -> bool:
	_owned.resize(view.type_cost.size())
	_owned.fill(0)
	_producers.resize(PlayerView.TABS)
	_producers.fill(0)
	_units = 0
	var columns: Array[PackedInt32Array] = view.columns()
	var types: PackedInt32Array = columns[PlayerView.Column.TYPE]
	var foot_w: PackedInt32Array = view.type_foot_w
	for row: int in view.own_rows:
		var type: int = types[row]
		_owned[type] += 1
		if foot_w[type] <= 0:
			_units += 1
			continue
		var tab: int = view.type_produces[type]
		if tab >= 0 and tab < PlayerView.TABS:
			_producers[tab] += 1
	passes = 1
	return _producers[PlayerView.Tab.INFANTRY] + _producers[PlayerView.Tab.VEHICLES] > 0


## Queues the scout when it can be queued. True when the scout is held back for credits or for
## the Command budget (its tab stays closed to the draw), false when it was sent or cannot be
## queued now (the draw goes on).
func _queue_scout(view: PlayerView, memory: AiMemory, out: Array[Command], type: int) -> bool:
	if not _queueable(view, type, false):
		return false
	if view.type_cost[type] > _budget or not memory.can_send():
		return true
	_send(view, memory, out, type)
	scouts_queued += 1
	return false


## Draws one role and queues its unit. False when nothing can be queued now (the run ends).
func _queue_drawn(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> bool:
	var total: int = 0
	for role: int in _ROLES:
		var type: int = _type_of(view, role)
		_types[role] = type
		_shares[role] = _weights[role] if type != _NONE else 0
		total += _shares[role]
	if total == 0 or not memory.can_send():
		return false
	var counter: int = _counter_role(view)
	# Scaled by 100: `counter_percent` of the total goes to the counter role, the rest keeps its
	# share, so the sum is `100 * total` (`(100 - percent) * total` with no counter) and no
	# division is needed.
	var shift: int = _counter_percent if counter >= 0 else 0
	var scaled: int = 0
	for role: int in _ROLES:
		_shares[role] *= 100 - shift
		if role == counter:
			_shares[role] += total * shift
		scaled += _shares[role]
	var pick: int = rng.next_int(scaled)
	for role: int in _ROLES:
		if pick < _shares[role]:
			role_queued[role] += 1
			_send(view, memory, out, _types[role])
			return true
		pick -= _shares[role]
	return false


## The unit type of `role` that can be queued now, or MISSING. The anti-vehicle role takes the
## first of its types that can be.
func _type_of(view: PlayerView, role: int) -> int:
	if role == OpponentDef.Role.ANTI_VEHICLE:
		for type: int in _vehicle_types:
			if type != _NONE and _queueable(view, type, true):
				return type
		return _NONE
	var type: int = _role_types[role]
	return type if type != _NONE and _queueable(view, type, true) else _NONE


## Whether a QUEUE of `type` would be applied and its unit placed: a unit tab with a producer that
## the scout's hold has not closed, its requirement owned, room in the queue (counting this
## think's) and under the cap, and with `priced` also within the budget.
func _queueable(view: PlayerView, type: int, priced: bool) -> bool:
	var tab: int = view.type_tab[type]
	if tab != PlayerView.Tab.INFANTRY and tab != PlayerView.Tab.VEHICLES:
		return false
	if _producers[tab] == 0 or (priced and tab == _closed_tab):
		return false
	var need: int = view.type_requires[type]
	if need >= 0 and _owned[need] == 0:
		return false
	var waiting: int = view.queue_count[tab] + _added[tab]
	if waiting >= _room:
		return false
	var other: int = (
		PlayerView.Tab.INFANTRY if tab == PlayerView.Tab.VEHICLES else PlayerView.Tab.VEHICLES
	)
	if _units + waiting + view.queue_count[other] + _added[other] >= view.unit_cap:
		return false
	return not priced or view.type_cost[type] <= _budget


## QUEUE of `type`, which the caller has checked with `_queueable` and the budget.
func _send(view: PlayerView, memory: AiMemory, out: Array[Command], type: int) -> void:
	memory.spent()
	_budget -= view.type_cost[type]
	spent_credits += view.type_cost[type]
	_added[view.type_tab[type]] += 1
	queued += 1
	out.append(Command.queue(_player, type))


## The armour class with the most seen units (units only, types first seen at least
## `reaction_ticks` ago), the lowest class among equals; -1 for none or no counter wanted.
func _most_seen_class(view: PlayerView, memory: AiMemory) -> int:
	if _counter_percent <= 0 or memory.seen_count.size() != view.type_cost.size():
		return -1
	_armour.resize(PlayerView.ARMOUR_CLASSES)
	_armour.fill(0)
	for type: int in memory.seen_count.size():
		var first: int = memory.seen_first_tick[type]
		if first == AiMemory.NONE or view.tick - first < _reaction_ticks:
			continue
		if view.type_foot_w[type] > 0:
			continue
		var class_at: int = view.type_armour[type]
		if class_at >= 0 and class_at < PlayerView.ARMOUR_CLASSES:
			_armour[class_at] += memory.seen_count[type]
	var most: int = 0
	var seen: int = -1
	for class_at: int in PlayerView.ARMOUR_CLASSES:
		if _armour[class_at] > most:
			most = _armour[class_at]
			seen = class_at
	return seen


## The role of the draw's `_types` (the unit that would be queued, MISSING for none) whose weapon
## does most against the class most seen, the lower role among equals; -1 for none. Only a role
## with weight counts.
func _counter_role(view: PlayerView) -> int:
	if _seen_class < 0:
		return -1
	var best: int = -1
	var best_percent: int = 0
	for role: int in _ROLES:
		if _types[role] == _NONE or _weights[role] <= 0:
			continue
		var percent: int = view.type_vs_armour[
			_types[role] * PlayerView.ARMOUR_CLASSES + _seen_class
		]
		if percent > best_percent:
			best_percent = percent
			best = role
	return best
