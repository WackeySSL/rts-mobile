class_name DummyAi
extends AiController
## The dummy opponent (ADR 0020 section 4, plan rows P83 and P83b): it builds its base from a build
## order, keeps its harvesters up and defends the base (`DummyDefence`), through the same Commands
## as a player. It reads the match only through the `PlayerView` of its think, uses no random number
## and no bonus, and sends only Commands the sim accepts: a QUEUE only for an item its queue has
## room for, its player can pay and its buildings let it build, a PLACE only on a slot that
## `placement` answers OK for, an ATTACK_MOVE only for units it has.
##
## One think (`think`):
## - a STRUCTURES head that is built is placed on the first slot of the spiral round the
##   Headquarters (`PlacementSpiral`, at most `place_tries` slots asked about) that `placement`
##   accepts, else it waits for the next think;
## - then it queues, while a queue has room (`queue_target` items) and the credits last, the next
##   wish: first a harvester when the player has fewer than `harvesters_wanted` per own refinery and
##   a vehicle producer to build it, then the first item of the build order that the player has
##   fewer of than the list calls for. A wish that cannot be queued yet (no producer, no room, its
##   requirement not owned) is waited for, not skipped, so the order holds, and one that costs more
##   than the credits left keeps them for it. An item counts as had once it is owned or queued, so a
##   lost building is wanted again at its place in the order;
## - last, its defence (`DummyDefence`, in its own file) orders its combat units: ATTACK_MOVE to an
##   enemy within `defend_radius_tiles` of its buildings, else to the guard point beside its
##   Headquarters.
## A player with no building that produces a tab (defeated, or never started) sends nothing.

## The defence: its memory of the units it ordered, and the work of its last run.
var defence: DummyDefence = null
## Slots asked about by the last think: at most `place_tries` (tests count the work, ADR 0020 §4).
var placement_tries: int = 0

var _build_ids: Array[StringName] = []
var _hq_id: StringName = &""
var _harvester_id: StringName = &""
var _queue_target: int = 0
var _harvesters_wanted: int = 0
var _place_tries: int = 0
var _stride: int = 1
var _spiral: PackedInt32Array = PackedInt32Array()

## Read off the view by each think and used only inside it: the build order and the two types as
## type indexes of the view's roster (-1: the roster lacks the id), the player's rows per type, its
## owned-and-queued items per type, its producers per tab, the items this think queued per tab and
## its refinery count.
var _order: PackedInt32Array = PackedInt32Array()
var _hq_type: int = -1
var _harvester_type: int = -1
var _owned: PackedInt32Array = PackedInt32Array()
var _have: PackedInt32Array = PackedInt32Array()
var _producers: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
var _refineries: int = 0

## A dummy for `player_id` driven by `def`, which it copies and does not keep. It thinks on the
## ticks with `tick % think_period == think_tick + player_id - 2`: player 2 on `think_tick`, each
## later player one tick after it (ADR 0020 section 2).
@warning_ignore("shadowed_variable")
static func create(def: AiDef, player_id: int, rng: DetRandom) -> DummyAi:
	var ai: DummyAi = DummyAi.new()
	ai.player_id = player_id
	ai.rng = rng
	ai.think_period = maxi(def.think_period, 1)
	ai.think_offset = posmod(-(def.think_tick + player_id - 2), ai.think_period)
	ai._build_ids = def.build_order.duplicate()
	ai._hq_id = def.hq_type
	ai._harvester_id = def.harvester_type
	ai._queue_target = def.queue_target
	ai._harvesters_wanted = def.harvesters_wanted
	ai._place_tries = def.place_tries
	ai._stride = maxi(def.place_stride_tiles, 1)
	ai._spiral = PlacementSpiral.cells(def.place_tries)
	ai.defence = DummyDefence.create(def, player_id)
	return ai


func think(view: PlayerView, out: Array[Command]) -> void:
	placement_tries = 0
	_resolve(view)
	if not _take_census(view):
		return
	if view.structure_ready():
		_place(view, out)
	_queue(view, out)
	defence.run(view, _hq_type, out)


## The build order and the two types as indexes of the view's roster. An id the roster lacks, or a
## type that no tab builds, is left out of the order.
func _resolve(view: PlayerView) -> void:
	_hq_type = view.type_index_of(_hq_id)
	_harvester_type = view.type_index_of(_harvester_id)
	_order = PackedInt32Array()
	for id: StringName in _build_ids:
		var type: int = view.type_index_of(id)
		if type != PlayerView.MISSING and view.type_tab[type] >= 0:
			_order.append(type)


## Counts the player's rows, producers and queued items. False when there is nothing to do: the
## player has no queues in the view, or no building that produces a tab.
func _take_census(view: PlayerView) -> bool:
	var tabs: int = PlayerView.TABS
	if view.queue_count.size() < tabs:
		return false
	_owned = PackedInt32Array()
	_owned.resize(view.type_cost.size())
	_producers = PackedInt32Array()
	_producers.resize(tabs)
	_added = PackedInt32Array()
	_added.resize(tabs)
	_refineries = 0
	var producing: int = 0
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		_owned[type] += 1
		var tab: int = view.type_produces[type]
		if tab >= 0 and tab < tabs:
			_producers[tab] += 1
			producing += 1
		if view.is_refinery(type):
			_refineries += 1
	_have = _owned.duplicate()
	for tab: int in tabs:
		for slot: int in view.queue_count[tab]:
			_have[view.queue_type[tab * view.queue_slots + slot]] += 1
	return producing > 0


## PLACE for the built STRUCTURES head on the first spiral slot that `placement` accepts.
func _place(view: PlayerView, out: Array[Command]) -> void:
	var head: int = view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots]
	var centre: Vector2i = _anchor(view)
	if centre.x < 0:
		return
	for step: int in mini(_spiral.size() / 2, _place_tries):
		var col: int = centre.x + _spiral[step * 2] * _stride
		var line: int = centre.y + _spiral[step * 2 + 1] * _stride
		placement_tries += 1
		if view.placement(head, col, line) == Placement.Reason.OK:
			out.append(
				Command.place(
					player_id,
					col * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
					line * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
				)
			)
			return


## The top-left tile of the player's Headquarters, else of its first building, else (-1, -1).
@warning_ignore("integer_division")
func _anchor(view: PlayerView) -> Vector2i:
	var found: Vector2i = Vector2i(-1, -1)
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		var wide: int = view.type_foot_w[type]
		if wide <= 0:
			continue
		var at: Vector2i = view.row_pos(row)
		var origin: Vector2i = Vector2i(
			(at.x - wide * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE,
			(at.y - view.type_foot_h[type] * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE
		)
		if type == _hq_type:
			return origin
		if found.x < 0:
			found = origin
	return found


## QUEUE for each wish in turn while one can be queued and paid.
func _queue(view: PlayerView, out: Array[Command]) -> void:
	var budget: int = view.credits
	var room: int = mini(_queue_target, view.queue_slots)
	for _step: int in room * PlayerView.TABS:
		var type: int = _next(view, room)
		if type < 0 or view.type_cost[type] > budget:
			return
		budget -= view.type_cost[type]
		_added[view.type_tab[type]] += 1
		_have[type] += 1
		out.append(Command.queue(player_id, type))


## The type to queue next, or -1 for none now: the harvester while there are too few and one can be
## queued, else the first item of the order that is not had yet, if it can be queued.
func _next(view: PlayerView, room: int) -> int:
	var wanted: int = _harvesters_wanted * _refineries
	if (
		_harvester_type != PlayerView.MISSING
		and _have[_harvester_type] < wanted
		and _can_queue(view, _harvester_type, room)
	):
		return _harvester_type
	var counted: PackedInt32Array = PackedInt32Array()
	counted.resize(_have.size())
	for type: int in _order:
		counted[type] += 1
		if _have[type] < counted[type]:
			return type if _can_queue(view, type, room) else -1
	return -1


## Whether a QUEUE of `type` would be applied but for the credits: its tab has a producer of the
## player's and room for `room` items counting the ones this think queued, and the type's
## requirement is owned.
func _can_queue(view: PlayerView, type: int, room: int) -> bool:
	var tab: int = view.type_tab[type]
	if tab < 0 or tab >= PlayerView.TABS or _producers[tab] == 0:
		return false
	if view.queue_count[tab] + _added[tab] >= room:
		return false
	var need: int = view.type_requires[type]
	return need < 0 or _owned[need] > 0
