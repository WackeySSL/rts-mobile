class_name AiEconomy
extends RefCounted
## The opponent's economy manager (ADR 0030 sections 1, 4 and 6, plan row P176): the build order of
## its tier, the power upkeep, the tankers per refinery, the loop after the order (refineries,
## factories and defences up to the level's caps), where a structure goes, and the credits it keeps
## for the next structure. Slot ECONOMY runs it once a second. It reads the match only through the
## `PlayerView` and the shared `AiMemory`, writes Commands to the think's list, copies its def and
## level into ints when it is made and keeps no Resource, no Node and no random draw.
##
## One run (`run`):
## - one pass over the player's rows counts what it owns, its complete producers and refineries, the
##   power its unfinished and queued structures will add, and where its base is (the Headquarters'
##   top-left tile, else the first building's);
## - a STRUCTURES head that is built is placed on a free slot of `PlacementSpiral` round that tile
##   (`_place`): at most `place_tries_per_think` `placement` calls, resuming where the last think
##   stopped (`AiMemory.spiral_resume`), and the first slot that answers OK wins. A defence takes
##   the free slot nearest the staging point when `AiMemory` has one, else the first free slot;
## - then it queues, while a queue has room (`queue_target` items), the credits last and the
##   think's Command budget allows, the next wish (`_next`): first a tanker while there are fewer
##   than `harvesters_per_refinery` per complete refinery and a vehicle producer to build it, then
##   the first item of the tier's steps that the player has fewer of than the list calls for (an
##   item counts as had once it is owned or queued, so a lost building is wanted again at its
##   place), then the loop: power while the surplus is under `power_margin`, refineries, factories
##   and defences while the player has fewer than the level's caps. A consumer is never wanted
##   while it would leave the surplus (power made less used, with the queued and unfinished
##   structures counted) under `power_margin`: a power plant is wanted first. A wish that cannot be
##   queued yet (no producer, no room, its requirement not complete) is waited for, not skipped, so
##   the order holds;
## - `AiMemory.reserve_credits` is the price of the structure that waits only for money, for room
##   in the structure queue (its head is still being built) or for its requirement (queued or
##   under construction), 0 when nothing waits for that: AiProduction spends only what is above it.
## Every Command checks `AiMemory.can_send` first and then `spent`. A player with no building that
## produces a tab (defeated, or never started) sends nothing.

## Passes over the view's own rows the last run made (`OpponentAi` adds it to `work`).
var passes: int = 0
## `placement` calls of the last run (at most `place_tries_per_think`), and Commands sent so far.
var placement_tries: int = 0
var placed: int = 0
var queued: int = 0

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

## Read off the view by each run and used only inside it: the player's rows per type (a site
## included), complete rows per type, owned-and-queued items per type, complete producers per tab,
## items queued by this run per tab, complete refineries, buildings and units, the power surplus
## with the queued and unfinished structures counted, the base's top-left tile and the credits
## to keep.
var _owned: PackedInt32Array = PackedInt32Array()
var _done: PackedInt32Array = PackedInt32Array()
var _have: PackedInt32Array = PackedInt32Array()
var _producers: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
var _refineries: int = 0
var _buildings: int = 0
var _units: int = 0
var _surplus: int = 0
var _anchor: Vector2i = Vector2i(-1, -1)
var _hold: int = 0


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
	_resolve(view)
	if not _take_census(view):
		memory.reserve_credits = 0
		return
	if view.structure_ready():
		_place(view, memory, out)
	_queue(view, memory, out)
	memory.reserve_credits = _hold


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
	var faction: int = view.type_faction[_hq_type] if _hq_type != PlayerView.MISSING else -2
	var cheapest: int = 0
	for type: int in view.type_cost.size():
		if view.type_tab[type] != PlayerView.Tab.STRUCTURES or view.type_foot_w[type] <= 0:
			continue
		if view.type_faction[type] != faction:
			continue
		if view.type_power[type] > 0 and (_power_type < 0 or view.type_cost[type] < cheapest):
			_power_type = type
			cheapest = view.type_cost[type]
		if view.is_refinery(type) and _refinery_type < 0:
			_refinery_type = type
		if view.type_produces[type] == PlayerView.Tab.VEHICLES and _factory_type < 0:
			_factory_type = type


## One pass over the player's rows: the census of the header. False when there is nothing to do: the
## player has no queues in the view, or no complete building that produces a tab.
@warning_ignore("integer_division")
func _take_census(view: PlayerView) -> bool:
	var tabs: int = PlayerView.TABS
	if view.queue_count.size() < tabs:
		return false
	var types: int = view.type_cost.size()
	_owned = PackedInt32Array()
	_owned.resize(types)
	_done = PackedInt32Array()
	_done.resize(types)
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
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		_owned[type] += 1
		var wide: int = view.type_foot_w[type]
		if wide <= 0:
			_units += 1
			continue
		_buildings += 1
		var at: Vector2i = view.row_pos(row)
		if type == _hq_type or _anchor.x < 0:
			_anchor = Vector2i(
				(at.x - wide * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE,
				(at.y - view.type_foot_h[type] * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE
			)
		if view.row_build_left(row) != 0:
			_surplus += view.type_power[type]  # A site counts neither made nor used until done.
			continue
		_done[type] += 1
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
	if head == _defence_type and memory.has_staging():
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
	var keys: PackedInt32Array = PackedInt32Array()
	for slot: int in slots:
		var dx: int = _anchor.x + _spiral[slot * 2] * _stride - memory.staging_x
		var dy: int = _anchor.y + _spiral[slot * 2 + 1] * _stride - memory.staging_y
		keys.append((dx * dx + dy * dy) * slots + slot)
	keys.sort()
	for at: int in slots:
		keys[at] = keys[at] % slots
	return keys


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
		_added[view.type_tab[type]] += 1
		_have[type] += 1
		if view.type_tab[type] == PlayerView.Tab.STRUCTURES:
			_surplus += view.type_power[type]
		queued += 1
		out.append(Command.queue(_player, type))


## The type to queue next, or -1 for none now: a tanker while there are too few and one can be
## queued, else the wish (`_wanted`) if it can be queued. A wish that waits only for the structure
## queue's head to be built sets `_hold` to its price.
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
		if view.type_tab[wish] == PlayerView.Tab.STRUCTURES and not view.structure_ready():
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
	var power: int = _power_type
	if power != PlayerView.MISSING and _surplus < _power_margin:
		return power
	var needs: Array[int] = [_refinery_type, _factory_type, _defence_type]
	var caps: Array[int] = [_refineries_max, _factories_max, _defences_max]
	for at: int in needs.size():
		if needs[at] != PlayerView.MISSING and _have[needs[at]] < caps[at]:
			return needs[at]
	return -1


## Whether a QUEUE of `type` would be applied but for the credits and the queue's room: a complete
## producer of its tab, a complete row of its requirement, and the rules' building and unit caps.
func _buildable(view: PlayerView, type: int) -> bool:
	var tab: int = view.type_tab[type]
	if tab < 0 or tab >= PlayerView.TABS or _producers[tab] == 0:
		return false
	var need: int = view.type_requires[type]
	if need >= 0 and _done[need] == 0:
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
		and _done[need] == 0
		and _have[need] > 0
	)


## Whether the tab's queue has room for one more of `type`, counting what this run queued.
func _has_room(view: PlayerView, type: int, room: int) -> bool:
	var tab: int = view.type_tab[type]
	return view.queue_count[tab] + _added[tab] < room
