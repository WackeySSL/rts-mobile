class_name AiEconomy
extends RefCounted
## The opponent's economy manager (ADR 0030 sections 1, 4 and 6, plan row P176), slot ECONOMY. It
## reads the match only through the `PlayerView` and `AiMemory`, copies its def and level into ints,
## keeps no Resource and draws no random number (`run` keeps the managers' `rng` parameter). A run:
## `_take_census` (one pass over the rows; the AI places complete buildings through the queue),
## `_place` (a built head on a free slot of `PlacementSpiral`, a defence nearest the staging point),
## `_queue` (the next wish while a queue has room: a tanker, a step of the tier's order, then the
## loop; a consumer that would leave the surplus under `power_margin` gets a plant first).
## `AiMemory.reserve_credits` is what production must leave this think: what this run queued plus
## the price of the structure or tanker it keeps credits for (it waits for money, for room while the
## queue's head is still being built, or for its queued requirement). Production spends
## `maxi(view.credits - reserve_credits, 0)`. Every Command checks `can_send`, then `spent`.

## The faction index that matches no type (a roster without the Headquarters).
const _NO_FACTION: int = -2

## Passes over the view's own rows the last run made (`OpponentAi` adds it to `work`).
var passes: int = 0
## `placement` calls of the last run (at most `place_tries_per_think`), and PLACE Commands sent.
var placement_tries: int = 0
var placed: int = 0

var _player: int = 0
var _hq_id: StringName = &""
var _harvester_id: StringName = &""
var _defence_id: StringName = &""
var _steps: Array[StringName] = []
var _queue_target: int = 0
var _stride: int = 1
var _power_margin: int = 0
var _tries_max: int = 0
var _tankers_per_refinery: int = 0
var _refineries_max: int = 0
var _factories_max: int = 0
var _defences_max: int = 0
var _spiral: PackedInt32Array = PackedInt32Array()

## The types as indexes of the view's roster (MISSING: the roster lacks it), found on the first run
## (the rules never change in a match): the steps that a tab builds, the tanker, the defence and, of
## the player's own faction, the cheapest power plant, a refinery and a vehicle factory.
var _resolved: bool = false
var _order: PackedInt32Array = PackedInt32Array()
var _hq_type: int = PlayerView.MISSING
var _harvester_type: int = PlayerView.MISSING
var _defence_type: int = PlayerView.MISSING
var _power_type: int = PlayerView.MISSING
var _refinery_type: int = PlayerView.MISSING
var _factory_type: int = PlayerView.MISSING

## Read off the view by each run, used only inside it (`_have`: owned and queued per type).
var _owned: PackedInt32Array = PackedInt32Array()
var _have: PackedInt32Array = PackedInt32Array()
var _producers: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
var _refineries: int = 0
var _buildings: int = 0
var _units: int = 0
var _surplus: int = 0
var _anchor: Vector2i = Vector2i(-1, -1)
var _hold: int = 0
var _spent: int = 0
var _head_ready: bool = false


## An economy for `player_id` on `def` at `level`, which it copies and does not keep.
static func create(def: OpponentDef, level: AiDifficultyDef, player_id: int) -> AiEconomy:
	var economy: AiEconomy = AiEconomy.new()
	var tier: int = clampi(level.build_order_tier, 0, OpponentDef.TIERS - 1)
	economy._player = player_id
	economy._hq_id = def.hq_type
	economy._harvester_id = def.harvester_type
	economy._defence_id = def.defence_type
	if tier < def.build_orders.size() and def.build_orders[tier] != null:
		economy._steps = def.build_orders[tier].steps.duplicate()
	economy._queue_target = def.queue_target
	economy._stride = maxi(def.place_stride_tiles, 1)
	economy._power_margin = def.power_margin
	economy._tries_max = maxi(def.place_tries_per_think, 0)
	economy._tankers_per_refinery = level.harvesters_per_refinery
	economy._refineries_max = level.refineries_max
	economy._factories_max = level.factories_max
	economy._defences_max = level.defences_max
	economy._spiral = PlacementSpiral.cells(def.spiral_slots)
	return economy


func run(view: PlayerView, memory: AiMemory, _rng: DetRandom, out: Array[Command]) -> void:
	passes = 0
	placement_tries = 0
	_hold = 0
	_spent = 0
	_resolve(view)
	if not _take_census(view):
		memory.reserve_credits = 0
		return
	_head_ready = view.structure_ready()
	if _head_ready:
		_place(view, memory, out)
	_queue(view, memory, out)
	memory.reserve_credits = _spent + _hold


## The types as indexes of the view's roster, once. A step the roster lacks, or no tab builds, is
## left out of the order.
func _resolve(view: PlayerView) -> void:
	if _resolved:
		return
	_resolved = true
	_hq_type = view.type_index_of(_hq_id)
	_harvester_type = view.type_index_of(_harvester_id)
	_defence_type = view.type_index_of(_defence_id)
	for id: StringName in _steps:
		var type: int = view.type_index_of(id)
		if type != PlayerView.MISSING and view.type_tab[type] >= 0:
			_order.append(type)
	var faction: int = (
		view.type_faction[_hq_type] if _hq_type != PlayerView.MISSING else _NO_FACTION
	)
	var cheapest: int = 0
	for type: int in view.type_cost.size():
		if view.type_tab[type] != PlayerView.Tab.STRUCTURES or view.type_foot_w[type] <= 0:
			continue
		if view.type_faction[type] != faction:
			continue
		if (
			view.type_power[type] > 0
			and (_power_type == PlayerView.MISSING or view.type_cost[type] < cheapest)
		):
			_power_type = type
			cheapest = view.type_cost[type]
		if view.is_refinery(type) and _refinery_type == PlayerView.MISSING:
			_refinery_type = type
		if (
			view.type_produces[type] == PlayerView.Tab.VEHICLES
			and _factory_type == PlayerView.MISSING
		):
			_factory_type = type


## One pass over the player's rows: the census of the header. False when there is nothing to do: the
## player has no queues in the view, or no building that produces a tab.
@warning_ignore("integer_division")
func _take_census(view: PlayerView) -> bool:
	var tabs: int = PlayerView.TABS
	if view.queue_count.size() < tabs:
		return false
	var types: int = view.type_cost.size()
	_owned = PackedInt32Array()
	_owned.resize(types)
	_producers = PackedInt32Array()
	_producers.resize(tabs)
	_added = PackedInt32Array()
	_added.resize(tabs)
	_refineries = 0
	_buildings = 0
	_units = 0
	_anchor = Vector2i(-1, -1)
	_surplus = view.power_made - view.power_used
	var producing: int = 0
	var hq_seen: bool = false
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		_owned[type] += 1
		var wide: int = view.type_foot_w[type]
		if wide <= 0:
			_units += 1
			continue
		_buildings += 1
		var at: Vector2i = view.row_pos(row)
		if (type == _hq_type and not hq_seen) or _anchor.x < 0:
			hq_seen = hq_seen or type == _hq_type
			_anchor = Vector2i(
				(at.x - wide * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE,
				(at.y - view.type_foot_h[type] * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE
			)
		var tab: int = view.type_produces[type]
		if tab >= 0 and tab < tabs:
			_producers[tab] += 1
			producing += 1
		if view.is_refinery(type):
			_refineries += 1
	passes = 1
	_have = _owned.duplicate()
	for tab: int in tabs:
		for slot: int in view.queue_count[tab]:
			var type: int = view.queue_type[tab * view.queue_slots + slot]
			_have[type] += 1
			if tab == PlayerView.Tab.STRUCTURES:
				_surplus += view.type_power[type]
	return producing > 0


## PLACE for the built STRUCTURES head: at most `_tries_max` `placement` calls from the resume
## index of the memory, the first slot that answers OK wins and the next search starts at the
## first slot again; a search that finds none moves the resume index on by the calls made.
func _place(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	var slots: int = _spiral.size() / 2
	if _anchor.x < 0 or slots == 0 or not memory.can_send():
		return
	var head: int = view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots]
	var order: PackedInt32Array = PackedInt32Array()
	var near: bool = head == _defence_type and memory.has_staging()
	var aim: Vector2i = Vector2i(memory.staging_x, memory.staging_y) if near else Vector2i(-1, -1)
	if memory.spiral_for_x != aim.x or memory.spiral_for_y != aim.y:
		# The resume index belongs to one order of the slots; a new order starts at its first slot.
		memory.spiral_for_x = aim.x
		memory.spiral_for_y = aim.y
		memory.spiral_resume = 0
	if near:
		order = _nearest_first(memory, slots)
	var start: int = posmod(memory.spiral_resume, slots)
	var tries: int = mini(_tries_max, slots)
	for step: int in tries:
		var at: int = (start + step) % slots
		var slot: int = at if order.is_empty() else order[at]
		var col: int = _anchor.x + _spiral[slot * 2] * _stride
		var line: int = _anchor.y + _spiral[slot * 2 + 1] * _stride
		placement_tries += 1
		if view.placement(head, col, line) == Placement.Reason.OK:
			memory.spent()
			placed += 1
			memory.spiral_resume = 0
			_head_ready = false  # The view still shows the head; the next tick it is gone.
			out.append(
				Command.place(
					_player,
					col * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
					line * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
				)
			)
			return
	memory.spiral_resume = (start + tries) % slots


## The slot indexes by distance of their top-left tile from the staging point, nearest first (the
## lower index first among equals).
func _nearest_first(memory: AiMemory, slots: int) -> PackedInt32Array:
	var keys: PackedInt64Array = PackedInt64Array()
	for slot: int in slots:
		var dx: int = _anchor.x + _spiral[slot * 2] * _stride - memory.staging_x
		var dy: int = _anchor.y + _spiral[slot * 2 + 1] * _stride - memory.staging_y
		keys.append((dx * dx + dy * dy) * slots + slot)
	keys.sort()
	var order: PackedInt32Array = PackedInt32Array()
	for key: int in keys:
		order.append(key % slots)
	return order


## QUEUE for each wish in turn while one can be queued and paid.
func _queue(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	var budget: int = view.credits
	var room: int = mini(_queue_target, view.queue_slots)
	for _step: int in room * PlayerView.TABS:
		var type: int = _next(view, room)
		if type < 0:
			return
		if view.type_cost[type] > budget:
			_hold = view.type_cost[type]
			return
		if not memory.can_send():
			return
		memory.spent()
		budget -= view.type_cost[type]
		_spent += view.type_cost[type]
		_added[view.type_tab[type]] += 1
		_have[type] += 1
		if view.type_tab[type] == PlayerView.Tab.STRUCTURES:
			_surplus += view.type_power[type]
		out.append(Command.queue(_player, type))


## The type to queue next, or -1 for none now: a tanker while there are too few and one can be
## queued, else the wish (`_wanted`) if it can be queued. A structure that waits only for its queued
## requirement, or for room while the queue's head is still being built, sets `_hold` to its price
## (a head that is ready and cannot be placed keeps nothing: the credits would sit idle).
func _next(view: PlayerView, room: int) -> int:
	var tanker: int = _harvester_type
	if (
		tanker != PlayerView.MISSING
		and _have[tanker] < _tankers_per_refinery * _refineries
		and _buildable(view, tanker)
		and _has_room(view, tanker, room)
	):
		return tanker
	var wish: int = _wanted(view)
	if wish < 0:
		return -1
	if not _buildable(view, wish):
		if _waits_for_requirement(view, wish):
			_hold = view.type_cost[wish]
		return -1
	if not _has_room(view, wish, room):
		if view.type_tab[wish] == PlayerView.Tab.STRUCTURES and not _head_ready:
			_hold = view.type_cost[wish]
		return -1
	return wish


## The next structure the player wants, -1 for none: the first missing step of the order, else the
## first need of the loop, and a power plant instead of a consumer that would leave the surplus
## under the margin.
func _wanted(view: PlayerView) -> int:
	var wish: int = _first_missing()
	if wish < 0:
		wish = _loop_need()
	if wish < 0:
		return -1
	if (
		_power_type != PlayerView.MISSING
		and view.type_power[wish] < 0
		and _surplus + view.type_power[wish] < _power_margin
	):
		return _power_type
	return wish


## The first step of the order that the player has fewer of (owned or queued) than the list has.
func _first_missing() -> int:
	var counted: PackedInt32Array = PackedInt32Array()
	counted.resize(_have.size())
	for type: int in _order:
		counted[type] += 1
		if _have[type] < counted[type]:
			return type
	return -1


## What the loop after the order wants, -1 for nothing: power under the margin, then refineries,
## factories and defences up to the level's caps.
func _loop_need() -> int:
	if _power_type != PlayerView.MISSING and _surplus < _power_margin:
		return _power_type
	if _refinery_type != PlayerView.MISSING and _have[_refinery_type] < _refineries_max:
		return _refinery_type
	if _factory_type != PlayerView.MISSING and _have[_factory_type] < _factories_max:
		return _factory_type
	if _defence_type != PlayerView.MISSING and _have[_defence_type] < _defences_max:
		return _defence_type
	return -1


## Whether a QUEUE of `type` would be applied but for the credits and the queue's room: a producer
## of its tab and a row of its requirement. The rules' building and unit caps act at PLACE and at
## spawn, not at QUEUE; a wish that could never be placed or spawned is not queued either.
func _buildable(view: PlayerView, type: int) -> bool:
	var tab: int = view.type_tab[type]
	if tab < 0 or tab >= PlayerView.TABS or _producers[tab] == 0:
		return false
	var need: int = view.type_requires[type]
	if need >= 0 and _owned[need] == 0:
		return false
	var waiting: int = view.queue_count[tab] + _added[tab]
	if tab == PlayerView.Tab.STRUCTURES:
		return _buildings + waiting < view.building_cap
	var mobile: int = _units + waiting
	var other: int = (
		PlayerView.Tab.INFANTRY if tab == PlayerView.Tab.VEHICLES else PlayerView.Tab.VEHICLES
	)
	return mobile + view.queue_count[other] + _added[other] < view.unit_cap


## Whether `type` is a structure that waits only for its requirement, which is queued or still
## under construction (the player keeps its credits for it).
func _waits_for_requirement(view: PlayerView, type: int) -> bool:
	var need: int = view.type_requires[type]
	return (
		view.type_tab[type] == PlayerView.Tab.STRUCTURES
		and need >= 0
		and _owned[need] == 0
		and _have[need] > 0
	)


## Whether the tab's queue has room for one more of `type`, counting what this run queued.
func _has_room(view: PlayerView, type: int, room: int) -> bool:
	var tab: int = view.type_tab[type]
	return view.queue_count[tab] + _added[tab] < room
