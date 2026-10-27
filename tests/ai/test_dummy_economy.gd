extends GdUnitTestSuite
## The dummy's economy over a whole build (plan row P83, ADR 0020 section 4): one dummy as player 1
## of the skirmish-like start of `ai_rig.gd` (a Headquarters, two rifle squads, 2,000 credits, ore
## near, real fog), player 2 passive, run once for the suite through the headless loop. The build
## order is complete at tick 3,112 on the shipped def and rules (counted); the bound below leaves
## room for a rebalance of a few percent and nothing more, so a dummy that dithers fails it.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
## The ticks in which the whole build order must stand (measured 3,112).
const DONE_BOUND: int = 3300
const TICKS: int = 3600

var _world: World
var _def: AiDef
## The structure types queued in order, the tile and slot count of each PLACE, the tick at which
## the build order first stood, and the most slots one think asked about and items one queue held.
var _queued: Array[String] = []
var _harvesters_queued: int = 0
var _places: Array[Vector2i] = []
var _place_slots: Array[int] = []
var _done_tick: int = -1
var _max_tries: int = 0
var _max_queue: int = 0


func before() -> void:
	_world = Rig.start()
	_def = Rig.dummy_def()
	var loop: MatchLoop = Rig.loop_of(_world)
	var ai: DummyAi = Rig.dummy(1)
	for _step: int in TICKS:
		var sent: Array[Command] = Rig.tick(_world, loop, [ai])
		_max_tries = maxi(_max_tries, ai.placement_tries)
		for command: Command in sent:
			_note(command, ai.placement_tries)
		for queue: int in range(World.TABS, World.TABS * 2):
			_max_queue = maxi(_max_queue, _world.queue_count[queue])
		if _done_tick < 0 and _stands():
			_done_tick = _world.tick


func test_every_building_of_the_build_order_stands_within_the_bound() -> void:
	assert_int(_done_tick).is_greater(0)
	assert_int(_done_tick).is_less_equal(DONE_BOUND)
	# Exactly the build order: no building more.
	for id: String in _counts():
		assert_int(Rig.count_of(_world, 1, id)).is_equal(_counts()[id])


func test_it_never_sends_a_command_the_sim_drops() -> void:
	assert_int(_world.dropped_commands).is_equal(0)
	assert_int(_world.spawn_refused).is_equal(0)


func test_structures_are_queued_in_the_order_of_the_def() -> void:
	var expected: Array[String] = []
	expected.assign(_def.build_order)
	assert_array(_queued).is_equal(expected)


func test_a_think_asks_about_no_more_slots_than_place_tries() -> void:
	assert_int(_max_tries).is_greater(0)
	assert_int(_max_tries).is_less_equal(_def.place_tries)
	for slots: int in _place_slots:
		assert_int(slots).is_between(1, _def.place_tries)


func test_no_queue_holds_more_than_queue_target() -> void:
	assert_int(_max_queue).is_equal(_def.queue_target)


func test_it_keeps_two_harvesters_for_its_one_refinery() -> void:
	assert_int(Rig.count_of(_world, 1, "refinery")).is_equal(1)
	assert_int(Rig.count_of(_world, 1, "harvester")).is_equal(_def.harvesters_wanted)
	# The refinery brought one; the dummy asked for the other and for no more.
	assert_int(_harvesters_queued).is_equal(_def.harvesters_wanted - 1)


func test_the_first_slot_that_placement_accepts_is_used() -> void:
	# The Headquarters has its top-left tile at (6, 6). The first slot, (2, 2), is not explored yet
	# (the Headquarters sees 7 tiles from its centre), the second, (6, 2), is: two slots asked.
	assert_array(_places).is_not_empty()
	assert_object(_places[0]).is_equal(Vector2i(6, 2))
	assert_int(_place_slots[0]).is_equal(2)


func test_every_place_is_a_slot_of_the_lattice_round_the_headquarters() -> void:
	assert_int(_places.size()).is_equal(_def.build_order.size())
	for tile: Vector2i in _places:
		var from_hq: Vector2i = tile - Rig.HQ_1
		assert_int(from_hq.x % _def.place_stride_tiles).is_equal(0)
		assert_int(from_hq.y % _def.place_stride_tiles).is_equal(0)
		assert_bool(from_hq == Vector2i.ZERO).is_false()


func test_buildings_keep_a_free_tile_between_them() -> void:
	var rects: Array[Rect2i] = []
	for row: int in _world.unit_count():
		if _world.owner[row] == 1 and _world.type_foot_w[_world.type_index[row]] > 0:
			var size: Vector2i = Vector2i(
				_world.type_foot_w[_world.type_index[row]],
				_world.type_foot_h[_world.type_index[row]]
			)
			rects.append(Rect2i(_world.footprint_origin(row), size))
	assert_int(rects.size()).is_equal(1 + _def.build_order.size())
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			assert_bool(rects[first].grow(1).intersects(rects[second])).is_false()


## What one Command did: the structure types and the PLACE tiles in order, harvesters counted.
@warning_ignore("integer_division")
func _note(command: Command, slots: int) -> void:
	if command.type == Command.Type.PLACE:
		_places.append(Vector2i(command.target_x / 1000, command.target_y / 1000))
		_place_slots.append(slots)
	elif command.type == Command.Type.QUEUE:
		var id: String = String(_world.type_ids[command.payload[0]])
		if id == String(_def.harvester_type):
			_harvesters_queued += 1
		else:
			_queued.append(id)


## How many of each type id the build order lists.
func _counts() -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for id: StringName in _def.build_order:
		counts[String(id)] = counts.get(String(id), 0) + 1
	return counts


## Whether player 1 owns at least as many of each type as the build order lists.
func _stands() -> bool:
	for id: String in _counts():
		if Rig.count_of(_world, 1, id) < _counts()[id]:
			return false
	return true
