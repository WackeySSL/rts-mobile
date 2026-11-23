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
## - then, when the level has `medic_per_squads` and the roster the medic type (P283, ADR 0037
##   section 6), queues one medic squad per that many own armed infantry squads, counting the medics
##   alive and queued (at most one a think, no draw: it takes one place of its tab's queue).
## - then the minelayer (P295, ADR 0037 section 10): after the medic and before the research and the
##   held aircraft, one layer while fewer than the level's `mine_layers` live or wait (none with the
##   rules' mine cap at 0), queued like the medic and paid with one mine's price on top.
## - then the air and tech (ADR 0036 section 14, plan row P250), each at most one a think and none
##   while the scout waits for credits: the next upgrade in data order that changes a unit the
##   player owns (one at a time, while the credits left stay above `research_floor`), and one
##   aircraft of the tier's `air_weights` (fighters weighted up by the aircraft seen) while the
##   airfield has a free pad, from the controller's stream like the unit draw.
## The counter role is layer-aware (P250): the armour class is tallied per layer, and only a role
## whose weapon can hit the layer of the most seen class is a counter (`weapon_targets` against
## `type_layer_bit`), so bombers seen do not draw tanks.
## One pass over the own rows (the census), skipped when nothing could be queued.

## A type the roster lacks.
const _NONE: int = PlayerView.MISSING
const _ROLES: int = OpponentDef.ROLES
## The layers the armour tally keeps apart: ground, air, low air.
const _LAYERS: int = 3

## Passes over the view's own rows the last run made (`OpponentAi` adds it to `work`).
var passes: int = 0
## Units queued over the match, the scouts among them.
var queued: int = 0
var scouts_queued: int = 0
var medics_queued: int = 0
var layers_queued: int = 0
var air_queued: int = 0
var research_queued: int = 0
## The credits the QUEUEs of the last run cost (`AiEconomy.mend` measures the credits left by it).
var spent_credits: int = 0
## Units queued per role over the match (`OpponentDef.Role`).
var role_queued: PackedInt32Array = PackedInt32Array()

var _player: int = 0
## Credits left unspent (`spend_margin_credits`).
var _margin: int = 0
var _role_ids: Array[StringName] = []
var _vehicle_ids: Array[StringName] = []
var _weights: PackedInt32Array = PackedInt32Array()
var _queue_target: int = 0
var _counter_percent: int = 0
var _reaction_ticks: int = 0
var _hq_id: StringName = &""
var _medic_per: int = 0
var _bomber_id: StringName = &""
var _fighter_id: StringName = &""
## The aircraft draw's weights (bomber, fighter), the fighter's gain per aircraft seen, and the
## research floor (0 = no research).
var _bomber_weight: int = 0
var _fighter_weight: int = 0
var _fighter_seen: int = 0
var _research_floor: int = 0

## The types as indexes of the view's roster, found on the first run.
var _resolved: bool = false
var _role_types: PackedInt32Array = PackedInt32Array()
var _vehicle_types: PackedInt32Array = PackedInt32Array()
var _medic: int = _NONE
## The minelayer type (P295) and how many to keep: `AiMines` orders the layers this queues.
var _layer_id: StringName = &""
var _layer: int = _NONE
var _layers_wanted: int = 0
var _bomber: int = _NONE
var _fighter: int = _NONE
## The research items of the player's faction in data order, and the least a tech Command costs.
var _research: PackedInt32Array = PackedInt32Array()
var _cheapest_tech: int = 1 << 30

## Read off the view by each run, used only inside it.
var _owned: PackedInt32Array = PackedInt32Array()
var _producers: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
var _armour: PackedInt32Array = PackedInt32Array()
var _types: PackedInt32Array = PackedInt32Array()
var _shares: PackedInt32Array = PackedInt32Array()
var _units: int = 0
var _foot_squads: int = 0
var _aircraft: int = 0
var _pads: int = 0
var _room: int = 0
var _budget: int = 0
var _seen_class: int = -1
var _seen_layer: int = PlayerView.Layer.GROUND
var _closed_tab: int = -1
## The aircraft drawn and not yet queued (MISSING: none), kept between runs.
var _air_pick: int = _NONE


## A production manager for `player_id` on `def` at `level`, which it copies and does not keep.
static func create(def: OpponentDef, level: AiDifficultyDef, player_id: int) -> AiProduction:
	var production: AiProduction = AiProduction.new()
	var tier: int = clampi(level.build_order_tier, 0, OpponentDef.TIERS - 1)
	production._player = player_id
	production._margin = maxi(level.spend_margin_credits, 0)
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
	production._hq_id = def.hq_type
	production._medic_per = maxi(level.medic_per_squads, 0)
	if level.mine_target > 0:
		production._layer_id = def.mine_layer_type
		production._layers_wanted = maxi(level.mine_layers, 0)
	production._bomber_id = def.bomber_type
	production._fighter_id = def.fighter_type
	production._bomber_weight = def.air_weight(tier, false)
	production._fighter_weight = def.air_weight(tier, true)
	production._fighter_seen = maxi(def.fighter_seen_weight, 0)
	production._research_floor = maxi(level.research_floor, 0)
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
	if scout == _NONE and not _has_room(view) and not _tech_room(view, memory):
		return
	if not _take_census(view):
		return
	if scout != _NONE and _owned[scout] > 0:
		scout = _NONE
	_budget = maxi(view.credits - memory.reserve_credits - _margin, 0)
	_closed_tab = -1
	if scout != _NONE and _queue_scout(view, memory, out, scout):
		_closed_tab = view.type_tab[scout]
	_queue_medic(view, memory, out)
	_queue_layer(view, memory, out)
	if _closed_tab < 0:
		_queue_research(view, memory, out)
		_queue_air(view, memory, rng, out)
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
	if _medic_per > 0:
		var hq: int = view.type_index_of(_hq_id)
		var faction: int = view.type_faction[hq] if hq != _NONE else AiRepair.NO_FACTION
		_medic = AiRepair.role_type_of(view, faction, false)
	if _layers_wanted > 0:
		_layer = AiMines.layer_type(view, _layer_id)
	_resolve_tech(view)


## The aircraft and, with a research floor, the research items of the player's faction, and the
## least a tech Command costs (the cheap test of `_tech_room`).
func _resolve_tech(view: PlayerView) -> void:
	if _bomber_weight > 0 and _bomber_id != &"":
		_bomber = view.type_index_of(_bomber_id)
	if _fighter_weight > 0 and _fighter_id != &"":
		_fighter = view.type_index_of(_fighter_id)
	for type: int in [_bomber, _fighter]:
		if type != _NONE:
			_cheapest_tech = mini(_cheapest_tech, view.type_cost[type])
	if _research_floor <= 0:
		return
	var hq: int = view.type_index_of(_hq_id)
	var faction: int = view.type_faction[hq] if hq != _NONE else AiRepair.NO_FACTION
	for type: int in view.type_cost.size():
		if view.type_tab[type] == PlayerView.Tab.RESEARCH and view.type_faction[type] == faction:
			_research.append(type)
			_cheapest_tech = mini(_cheapest_tech, view.type_cost[type])


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


## Whether an aircraft or a research item could be queued: the credits above the economy's reserve
## cover the cheapest and its queue has room (the pads and the producers are the census's).
func _tech_room(view: PlayerView, memory: AiMemory) -> bool:
	if view.credits - memory.reserve_credits < _cheapest_tech:
		return false
	var air: bool = (
		(_bomber != _NONE or _fighter != _NONE) and view.queue_count[PlayerView.Tab.FLIGHT] < _room
	)
	return air or (not _research.is_empty() and view.queue_count[PlayerView.Tab.RESEARCH] == 0)


## One pass over the player's rows: the unit count and the producers of each tab. False when the
## player has no producer of a unit tab.
func _take_census(view: PlayerView) -> bool:
	_owned.resize(view.type_cost.size())
	_owned.fill(0)
	_producers.resize(PlayerView.TABS)
	_producers.fill(0)
	_units = 0
	_foot_squads = 0
	_aircraft = 0
	_pads = 0
	var layers: PackedInt32Array = view.type_layer_bit
	var pads: PackedInt32Array = view.type_pads
	var columns: Array[PackedInt32Array] = view.columns()
	var types: PackedInt32Array = columns[PlayerView.Column.TYPE]
	var foot_w: PackedInt32Array = view.type_foot_w
	var lefts: PackedInt32Array = columns[PlayerView.Column.BUILD_LEFT]
	for row: int in view.own_rows:
		var type: int = types[row]
		if foot_w[type] > 0 and lefts[row] != 0:
			continue  # A site: no producer, no pad and no requirement until it is finished.
		_owned[type] += 1
		if foot_w[type] <= 0:
			_units += 1
			if _medic != _NONE and _is_foot_squad(view, type):
				_foot_squads += 1
			if type < layers.size() and layers[type] == PlayerView.Layer.AIR:
				_aircraft += 1
			continue
		if type < pads.size():
			_pads += pads[type]
		var tab: int = view.type_produces[type]
		if tab >= 0 and tab < PlayerView.TABS:
			_producers[tab] += 1
	passes = 1
	return _producers[PlayerView.Tab.INFANTRY] + _producers[PlayerView.Tab.VEHICLES] > 0


## Whether `type` is an armed infantry squad (the medics' count).
func _is_foot_squad(view: PlayerView, type: int) -> bool:
	return view.type_tab[type] == PlayerView.Tab.INFANTRY and view.type_weapon[type] >= 0


## One medic squad when the armed infantry squads outnumber the medics (alive and queued) by
## `medic_per_squads`, and the medic can be queued and paid now.
func _queue_medic(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if _medic == _NONE or _medic_per <= 0 or not memory.can_send():
		return
	@warning_ignore("integer_division")
	if _foot_squads / _medic_per <= _have(view, _medic) or not _queueable(view, _medic, true):
		return
	_send(view, memory, out, _medic)
	medics_queued += 1


## The own rows of `type` and the items of it in its queue.
func _have(view: PlayerView, type: int) -> int:
	var have: int = _owned[type]
	var tab: int = view.type_tab[type]
	for slot: int in view.queue_count[tab]:
		if view.queue_type[tab * view.queue_slots + slot] == type:
			have += 1
	return have


## One minelayer (P295, ADR 0037 section 10) while fewer than the level's `mine_layers` live or
## wait, queued like the medic: a producer, the requirement, queue room, the unit cap and the
## credits left (the layer and one mine) all as `_queueable` asks.
func _queue_layer(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if _layer == _NONE or _have(view, _layer) >= _layers_wanted or not memory.can_send():
		return
	if _budget < view.type_cost[_layer] + view.type_mine_cost[_layer]:
		return
	if not _queueable(view, _layer, true):
		return
	_send(view, memory, out, _layer)
	layers_queued += 1


## The next research item, in data order, whose upgrade is not researched and changes a unit the
## player owns: queued when the research queue is empty and the credits left stay above the floor.
## The first such item that cannot be paid yet waits (later ones do not jump it).
func _queue_research(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	var tab: int = PlayerView.Tab.RESEARCH
	if _research.is_empty() or _producers[tab] == 0 or not memory.can_send():
		return
	if view.queue_count[tab] + _added[tab] > 0:
		return
	for type: int in _research:
		var up: int = view.type_upgrade[type]
		if up < 0 or (view.upgrades >> up) & 1 == 1 or not _changes_owned(view, up):
			continue
		var need: int = view.type_requires[type]
		if (need < 0 or _owned[need] > 0) and _budget - view.type_cost[type] > _research_floor:
			_send(view, memory, out, type)
			research_queued += 1
		return


## Whether upgrade `up` changes a type the player owns a row of.
func _changes_owned(view: PlayerView, up: int) -> bool:
	var first: int = view.upgrade_type_first[up]
	for at: int in range(first, first + view.upgrade_type_count[up]):
		if _owned[view.upgrade_types[at]] > 0:
			return true
	return false


## One aircraft drawn from the bomber's and the fighter's weights (the fighter's grows with the
## most aircraft seen) while a pad is free: the aircraft and the queued ones are under the pads of
## the airfields, the FLIGHT queue has room and the unit cap allows it. The drawn pick is kept
## (`_air_pick`) until it is queued: while the credits fall short its price is held out of the
## ground draw's budget, so the dearer bomber is not crowded out by the cheaper fighter.
func _queue_air(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	var tab: int = PlayerView.Tab.FLIGHT
	var waiting: int = view.queue_count[tab] + _added[tab]
	if _pads == 0 or waiting >= _room or _aircraft + waiting >= _pads:
		_air_pick = _NONE
		return
	if not memory.can_send():
		return
	if _air_pick == _NONE or _air_share(view, _air_pick, 0) == 0:
		var bomber: int = _air_share(view, _bomber, 0)
		var fighter: int = _air_share(
			view, _fighter, _fighter_seen * memory.seen_air_peak if _fighter_weight > 0 else 0
		)
		if bomber + fighter == 0:
			_air_pick = _NONE
			return
		_air_pick = _bomber if rng.next_int(bomber + fighter) < bomber else _fighter
	var cost: int = view.type_cost[_air_pick]
	if cost <= _budget:
		_send(view, memory, out, _air_pick)
		air_queued += 1
		_air_pick = _NONE
	else:
		# Held until it is paid: its price stays out of the ground draw's budget, as the scout's.
		_budget = maxi(_budget - cost, 0)


## The draw weight of aircraft `type` (MISSING: none) with `extra` added: 0 unless a producer
## stands, its requirement is owned and the unit cap allows it (the price is the pick's, later).
func _air_share(view: PlayerView, type: int, extra: int) -> int:
	if (
		type == _NONE
		or view.type_tab[type] != PlayerView.Tab.FLIGHT
		or _producers[view.type_tab[type]] == 0
	):
		return 0
	var need: int = view.type_requires[type]
	if need >= 0 and _owned[need] == 0:
		return 0
	var queued_units: int = 0
	for other: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES, PlayerView.Tab.FLIGHT]:
		queued_units += view.queue_count[other] + _added[other]
	if _units + queued_units >= view.unit_cap:
		return 0
	return (_bomber_weight if type == _bomber else _fighter_weight) + extra


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
	var flight: int = PlayerView.Tab.FLIGHT
	var others: int = (
		view.queue_count[other] + _added[other] + view.queue_count[flight] + _added[flight]
	)
	if _units + waiting + others >= view.unit_cap:
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
## `reaction_ticks` ago), tallied per layer (P250: ground, air and low air each have their own
## classes, so aircraft never count toward a ground class), the lowest ground-first class among
## equals; -1 for none or no counter wanted. `_seen_layer` is the winner's layer bit.
@warning_ignore("integer_division")
func _most_seen_class(view: PlayerView, memory: AiMemory) -> int:
	if _counter_percent <= 0 or memory.seen_count.size() != view.type_cost.size():
		return -1
	_armour.resize(PlayerView.ARMOUR_CLASSES * _LAYERS)
	_armour.fill(0)
	for type: int in memory.seen_count.size():
		var first: int = memory.seen_first_tick[type]
		if first == AiMemory.NONE or view.tick - first < _reaction_ticks:
			continue
		if view.type_foot_w[type] > 0:
			continue
		var class_at: int = view.type_armour[type]
		if class_at >= 0 and class_at < PlayerView.ARMOUR_CLASSES:
			_armour[_layer_of(view, type) * PlayerView.ARMOUR_CLASSES + class_at] += (
				memory.seen_count[type]
			)
	var most: int = 0
	var seen: int = -1
	for bucket: int in _armour.size():
		if _armour[bucket] > most:
			most = _armour[bucket]
			seen = bucket
	_seen_layer = PlayerView.Layer.GROUND
	if seen < 0:
		return -1
	_seen_layer = 1 << (seen / PlayerView.ARMOUR_CLASSES)
	return seen % PlayerView.ARMOUR_CLASSES


## The layer index of `type` (0 ground, 1 air, 2 low air): a hand-built view without the table, or
## a bit it does not know, reads as ground.
func _layer_of(view: PlayerView, type: int) -> int:
	var bit: int = view.type_layer_bit[type] if type < view.type_layer_bit.size() else 0
	return 1 if bit == PlayerView.Layer.AIR else (2 if bit == PlayerView.Layer.LOW_AIR else 0)


## The role of the draw's `_types` (the unit that would be queued, MISSING for none) whose weapon
## does most against the class most seen and can hit its layer, the lower role among equals; -1 for
## none. Only a role with weight counts.
func _counter_role(view: PlayerView) -> int:
	if _seen_class < 0:
		return -1
	var best: int = -1
	var best_percent: int = 0
	for role: int in _ROLES:
		if (
			_types[role] == _NONE
			or _weights[role] <= 0
			or AiEnemyScan.hit_mask(view, _types[role]) & _seen_layer == 0
		):
			continue
		var percent: int = view.type_vs_armour[
			_types[role] * PlayerView.ARMOUR_CLASSES + _seen_class
		]
		if percent > best_percent:
			best_percent = percent
			best = role
	return best
