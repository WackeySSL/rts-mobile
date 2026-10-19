extends GdUnitTestSuite
## The INTEGRATE kernel on crafted states (ADR 0013 sections 2 and 4, plan P37n): the names it gets
## and sets, the write cases of the boundary (an in-place write seen through an alias, a held copy
## keeping its old values, the scalar that acquire() changes, a recycled slot, also on a worker
## Thread), and the cases for the rules of its core/ functions: isqrt, best_neighbour (the tie rule,
## the corner rule, opposite corners of the largest map) and acquire (the key held, a free slot, the
## least recently used slot, every slot referenced). Every case builds two identical Worlds, one
## running the GDScript phase and one the C++ kernel, and compares their full state (StateDiff) as
## well as the values that the rule gives. The 900-tick lockstep is test_integrate_lockstep.gd's.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const HEADER: String = "res://native/sim_kernels/src/bind/world_access.h"
const SOURCE: String = "res://native/sim_kernels/src/bind/kernel_integrate.cpp"
const INTEGRATE: int = SimProbe.Phase.INTEGRATE
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const NO_NEXT: int = -2
const UNREACHED: int = FlowField.UNREACHED
const BIG: int = 100000
## What the kernel gets or sets, in table order: the ints and arrays of the World that the pass
## reads or writes, the flow cache's columns and counters, and the served field of each slot.
const INTEGRATE_NAMES: Array[String] = [
	"WORLD.map_cols",
	"WORLD.map_rows",
	"WORLD.map_w",
	"WORLD.map_h",
	"WORLD.map_version",
	"WORLD.tick",
	"WORLD.line_check_period_ticks",
	"WORLD.stall_ticks",
	"WORLD.stall_range_spacings",
	"WORLD.attack_rekey_milli",
	"WORLD.unit_id",
	"WORLD.type_index",
	"WORLD.pos_x",
	"WORLD.pos_y",
	"WORLD.goal_x",
	"WORLD.goal_y",
	"WORLD.group_cell",
	"WORLD.order",
	"WORLD.nav_mode",
	"WORLD.field",
	"WORLD.nav_cell",
	"WORLD.nav_next",
	"WORLD.best_dist",
	"WORLD.stall",
	"WORLD.intent_x",
	"WORLD.intent_y",
	"WORLD.push_x",
	"WORLD.push_y",
	"WORLD.move_cost",
	"WORLD.type_speed",
	"WORLD.type_spacing",
	"WORLD.type_move_class",
	"FLOW.cols",
	"FLOW.rows",
	"FLOW.classes",
	"FLOW.requests",
	"FLOW.key_goal",
	"FLOW.key_class",
	"FLOW.key_version",
	"FLOW.last_used",
	"FLOW.ref_count",
	"FLOW.requested",
	"FLOW.status",
	"FLOW.fields",
	"SLOT.grid_cols",
	"SLOT.cell_count",
	"SLOT.stride",
	"SLOT.complete",
	"SLOT.cost"
]


## The list of the table is INTEGRATE_NAMES, and kernel_integrate.cpp names those and no other: a
## name it fetched outside the list would reach the engine without check_world's type test.
func test_integrate_gets_and_sets_exactly_the_names_of_its_list() -> void:
	var row: RegEx = RegEx.create_from_string("^\\s*X\\((\\w+), (\\w+), \\w+, \\w+, ([^)]+)\\)")
	var names: Array[String] = []
	for line: String in FileAccess.get_file_as_string(HEADER).split("\n"):
		var found: RegExMatch = row.search(line)
		if found == null:
			continue
		for token: String in found.get_string(3).split("|"):
			if token.strip_edges() in ["PH_I", "PH_ALL"]:
				names.append("%s.%s" % [found.get_string(1), found.get_string(2)])
	assert_array(names).contains_exactly(INTEGRATE_NAMES)
	var used: Array[String] = []
	var ids: RegEx = RegEx.create_from_string("\\bID_(WORLD|FLOW|SLOT)_(\\w+)")
	for found: RegExMatch in ids.search_all(FileAccess.get_file_as_string(SOURCE)):
		var name: String = "%s.%s" % [found.get_string(1), found.get_string(2)]
		if not used.has(name):
			used.append(name)
	assert_array(used).contains_exactly_in_any_order(INTEGRATE_NAMES)


## An array the call writes in place is seen through an alias taken before it, with no copy held
## and with one (a duplicate() keeps its old values; the member forks once and writes in place
## after that), the scalar that acquire() sets arrives (`requests`), the slot that takes a new key
## is cleared in place (`complete` false, `cost` all UNREACHED, seen through an alias too), and a
## pass with nothing to do changes no state.
func test_the_integrate_kernel_writes_in_place_and_sets_what_the_twin_sets() -> void:
	for hold: bool in [false, true]:
		var seen: Dictionary = _write_case(_attack_pair(), hold)
		assert_dict(seen).override_failure_message("hold %s" % hold).is_equal(_written(hold))


func test_the_integrate_write_cases_give_the_same_observations_on_a_worker_thread() -> void:
	for hold: bool in [false, true]:
		var thread: Thread = Thread.new()
		assert_int(thread.start(_write_case.bind(_attack_pair(), hold))).is_equal(OK)
		assert_dict(thread.wait_to_finish()).is_equal(_written(hold))


## The stall takes isqrt of the squared distance to the goal: `best_dist` of a unit steering at its
## goal within range is that root, for 70 distances from a seeded stream (a root and its squares
## among them), against a floor square root found by search. A DIRECT unit with a checked line
## 121 to 2400 from its goal (speed 120, range 2 x 1200), on both implementations.
func test_the_stall_takes_the_floor_square_root_of_the_squared_distance(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 10)), impl)
	var rng: DetRandom = DetRandom.create(7, 3)
	var wanted: Array[int] = []
	var offsets: Array[Vector2i] = [Vector2i(121, 0), Vector2i(0, -2400), Vector2i(1697, 1697)]
	offsets.append_array([Vector2i(2399, 1), Vector2i(-1700, 1690), Vector2i(0, 121)])
	while offsets.size() < 70:
		var offset: Vector2i = Vector2i(rng.next_int(4801) - 2400, rng.next_int(4801) - 2400)
		var d2: int = offset.x * offset.x + offset.y * offset.y
		if d2 > 14400 and d2 <= 2400 * 2400:
			offsets.append(offset)
	for index: int in offsets.size():
		var row: int = world.add_unit(1, 0, 15000, 5000) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = DIRECT
		world.nav_cell[row] = 1
		world.goal_x[row] = 15000 + offsets[index].x
		world.goal_y[row] = 5000 + offsets[index].y
		wanted.append(
			_floor_sqrt(offsets[index].x * offsets[index].x + offsets[index].y * offsets[index].y)
		)
	Movement.integrate(world)
	assert_array(Array(world.best_dist.slice(0, offsets.size()))).is_equal(wanted)
	assert_int(world.stall.slice(0, offsets.size()).count(0)).is_equal(offsets.size())
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([15000, 5000])
	# A second look from the same place has not improved: every unit counts one tick of stall.
	Movement.integrate(world)
	assert_int(world.stall.slice(0, offsets.size()).count(1)).is_equal(offsets.size())


## best_neighbour on a field with the costs set by hand round a unit at the middle of a 5 x 5 map
## (cost 100): the neighbour that is strictly cheaper and first in the order NW, N, NE, W, E, SW,
## S, SE wins a tie, so the lower cell wins between N and S and between W and E, a diagonal comes
## before the orthogonal cell after it (NW before N), an orthogonal cell before the diagonal after
## it (W before SW), the first of two diagonals wins (NE before SE), a diagonal needs both its
## orthogonal cells reached, and a neighbour that costs as much as the unit's own tile is no step
## at all.
func test_best_neighbour_ties_go_to_the_first_neighbour_in_scan_order() -> void:
	# [name, the costs of the neighbours that are reached (the rest UNREACHED), the cell named]
	var cases: Array[Array] = [
		["N and S", {&"N": 50, &"S": 50}, 7],
		["W and E", {&"W": 50, &"E": 50}, 11],
		["NW before N", {&"NW": 50, &"N": 50, &"W": 80}, 6],
		["W before SW", {&"W": 50, &"SW": 50, &"S": 80}, 11],
		["NE before SE", {&"NE": 50, &"SE": 50, &"N": 80, &"E": 80, &"S": 80}, 8],
		["SW and SE", {&"SW": 50, &"SE": 50, &"W": 80, &"S": 80, &"E": 80}, 16],
		["a diagonal past an unreached cell", {&"NW": 10, &"N": 60}, 7],
		["a cell as dear as the unit's own", {&"N": 100, &"E": 100}, NO_NEXT],
		["a cell dearer than the unit's own", {&"W": 130, &"S": 100}, NO_NEXT],
		["the cheapest wins over the first", {&"N": 70, &"E": 40, &"S": 55}, 13],
		["the unit's own tile unreached", {&"HERE": UNREACHED, &"N": 50, &"E": 70}, NO_NEXT],
	]
	for case: Array in cases:
		var pair: Array[World] = _pair(_field_world.bind(case[1]))
		for world: World in pair:
			Movement.integrate(world)
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case[0]).is_empty()
		for world: World in pair:
			var label: String = "%s, native %s" % [case[0], world.native_phases != 0]
			assert_int(world.nav_next[0]).override_failure_message(label).is_equal(case[2])


## The goal in one corner of the largest map (64 x 64) and the unit in the opposite one: the field
## names the diagonal neighbour towards the goal, at each of the four corners, and the unit at the
## goal's own corner names none (NO_NEXT, its own field).
func test_opposite_corners_of_the_largest_map_name_the_diagonal_neighbour() -> void:
	var corners: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(63, 0), Vector2i(0, 63), Vector2i(63, 63)
	]
	for goal: Vector2i in corners:
		var opposite: Vector2i = Vector2i(63 - goal.x, 63 - goal.y)
		var pair: Array[World] = _pair(_corner_world.bind(goal, opposite))
		for world: World in pair:
			Movement.integrate(world)
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
		var step: Vector2i = Vector2i(signi(goal.x - opposite.x), signi(goal.y - opposite.y))
		var named: int = (opposite.y + step.y) * 64 + opposite.x + step.x
		for world: World in pair:
			assert_array([world.nav_next[0], world.nav_next[1]]).is_equal([named, NO_NEXT])


## acquire() from the ATTACK re-key, on a cache of 3 slots: slot 0 holds tile (2, 2) and is
## complete, and four ATTACK tanks follow it. The goal of tank 1 is more than 4000 from that tile:
## it takes a new key, on the free slot 1 (requested, waiting, cleared). Tank 2's goal is in tile
## 175 as well: it holds the key, a reference more and the tick of its last use. Tank 3 asks for
## tile 50 on the free slot 2, and tank 4, for tile 217, finds every slot referenced and keeps
## slot 0. The rows are visited in order, so the tables come out in that order on both.
func test_the_attack_rekey_acquires_the_key_held_a_free_slot_or_nothing() -> void:
	var pair: Array[World] = _attack_pair()
	for world: World in pair:
		Movement.integrate(world)
		assert_array(Array(world.field.slice(0, 5))).is_equal([-1, 1, 1, 2, 0])
		assert_array(Array(world.flow.key_goal.slice(0, 3))).is_equal([42, 175, 50])
		assert_array(Array(world.flow.ref_count.slice(0, 3))).is_equal([4, 2, 1])
		assert_array(Array(world.flow.requested.slice(0, 3))).is_equal([1, 2, 3])
		assert_array(Array(world.flow.last_used.slice(0, 3))).is_equal([0, 9, 9])
		assert_array(Array(world.flow.status.slice(0, 3))).is_equal([2, 1, 1])
		assert_int(world.flow.requests).is_equal(3)
		assert_array([world.flow.field(1).complete, world.flow.field(2).complete]).is_equal(
			[false, false]
		)
		assert_int(world.flow.field(1).cost.count(UNREACHED)).is_equal(
			world.flow.field(1).cost.size()
		)
		assert_bool(world.flow.field(0).complete).is_true()
		assert_array(Array(world.nav_next.slice(1, 4))).is_equal([-1, -1, -1])
		assert_int(world.nav_next[4]).is_greater(-1)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## acquire() takes the least recently used slot that nothing references, a tie to the lower slot,
## and keeps a key's slot for the same goal on another map version out of it. Slots 0 to 2 hold
## keys that nobody references, last used at ticks 5, 3 and 3: tank 1 asks for a fourth key and
## recycles slot 1 (the older of the two at 3), tank 2's goal is a fifth key and recycles slot 2.
func test_acquire_recycles_the_least_recently_used_unreferenced_slot() -> void:
	var pair: Array[World] = _pair(_lru_world)
	for world: World in pair:
		Movement.integrate(world)
		assert_array(Array(world.field.slice(1, 3))).is_equal([1, 2])
		assert_array(Array(world.flow.key_goal.slice(0, 3))).is_equal([30, 130, 200])
		assert_array(Array(world.flow.last_used.slice(0, 3))).is_equal([5, 9, 9])
		assert_array(Array(world.flow.ref_count.slice(0, 3))).is_equal([0, 1, 1])
		assert_array(Array(world.flow.requested.slice(0, 3))).is_equal([1, 4, 5])
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A FIELD unit that is IDLE (a stale mode) is moved by its push and looked up never, and neither is
## a FIELD unit on a World with no map (no tile to be in). Each would have its `nav_next` set, from
## -1 to a tile or to NO_NEXT, if the lookup ran.
func test_an_idle_field_unit_and_a_field_unit_with_no_map_get_no_lookup() -> void:
	var idle: Array[World] = _pair(_field_world.bind({&"N": 50}))
	for world: World in idle:
		world.order[0] = IDLE
		world.push_x[0] = 40
		Movement.integrate(world)
		assert_array([world.nav_next[0], world.field[0], world.pos_x[0]]).is_equal([-1, 0, 2540])
	assert_str(StateDiff.first(idle[0], idle[1])).is_empty()
	var bare: Array[World] = _pair(_no_map_field_world)
	for world: World in bare:
		Movement.integrate(world)
		assert_array([world.nav_next[0], world.pos_x[0]]).is_equal([-1, 2620])
	assert_str(StateDiff.first(bare[0], bare[1])).is_empty()


## The stall counts a unit on a field that names no next tile only when the unit follows a slot
## (the cell is known): a FIELD unit whose slot is not there (the number is the slot count), and a
## DIRECT unit whose line is not checked yet, with a `nav_next` of NO_NEXT by hand, keep their best
## distance and stall count.
func test_no_stall_is_counted_for_a_slot_that_is_not_there_or_a_line_not_checked() -> void:
	for case: Array in [["no such slot", 8, 1], ["line not checked", -1, -1]]:
		var pair: Array[World] = _pair(_stall_world.bind(3))
		for world: World in pair:
			world.nav_next[0] = NO_NEXT
			world.field[0] = case[1]
			world.nav_mode[0] = FIELD if case[1] >= 0 else DIRECT
			world.nav_cell[0] = case[2]
			Movement.integrate(world)
			var label: String = case[0]
			(
				assert_array([world.best_dist[0], world.stall[0]])
				. override_failure_message(label)
				. is_equal([UNREACHED, 0])
			)
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## Rock that refuses both moves stops a unit, and only a DIRECT unit has its line marked unchecked
## for it (a FIELD unit keeps the cell of its last check). Two tanks 100 west of rock tile (5, 3)
## step 200 east: the DIRECT one ends with `nav_cell` -1, the FIELD one, on a pending field,
## keeps 7.
func test_rock_marks_the_line_of_a_direct_unit_unchecked_and_leaves_a_field_unit_alone() -> void:
	var pair: Array[World] = _pair(_rock_world)
	for world: World in pair:
		Movement.integrate(world)
		assert_array([world.pos_x[0], world.pos_x[1]]).is_equal([4900, 4900])
		assert_array([world.nav_cell[0], world.nav_cell[1]]).is_equal([-1, 7])
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The clamp takes the smaller of the map's size and its tiles' extent on each axis, and the two
## axes do not borrow from each other: a map of 5500 x 9500 milli-tiles (6 x 10 tiles) ends a step
## at 5499 and 9499, and one of 9500 x 2500 (10 x 3 tiles) at 9499 and 2499.
func test_a_map_that_is_not_whole_tiles_is_clamped_by_its_size_on_each_axis() -> void:
	for case: Array in [
		[Vector2i(5500, 9500), Vector2i(5490, 9490)], [Vector2i(9500, 2500), Vector2i(9490, 2490)]
	]:
		var pair: Array[World] = _pair(_ragged_world.bind(case[0], case[1]))
		for world: World in pair:
			Movement.integrate(world)
			var label: String = "map %s" % case[0]
			assert_array([world.pos_x[0], world.pos_y[0]]).override_failure_message(label).is_equal(
				[case[0].x - 1, case[0].y - 1]
			)
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## acquire() matches the whole key and takes a free slot before it evicts. Slot 0 holds the group's
## field (tile 84); slots 1 and 2 hold tile 130's field for the foot class and for the tank class;
## slot 3 is free. The tank on tile 84 has its own goal in tile 130. When slot 2's key is of
## another map version the key is not held: the free slot 3 takes it (not the foot field of the
## same tile, not the stale one, not an evicted slot). When slot 2 is current it is held: the
## unit takes it, it counts a reference and the tick of its last use, it is not recycled
## (still complete) and nothing is requested.
func test_acquire_matches_the_whole_key_and_takes_a_free_slot_before_evicting() -> void:
	var pair: Array[World] = _pair(_key_world.bind(false))
	for world: World in pair:
		Movement.integrate(world)
		var flow: FlowCache = world.flow
		assert_array([world.field[0], world.nav_next[0], flow.requests]).is_equal([3, -1, 4])
		assert_array([flow.key_goal[3], flow.key_class[3], flow.key_version[3]]).is_equal(
			[130, TRACKED, world.map_version]
		)
		assert_array([flow.requested[3], flow.status[3], flow.field(3).complete]).is_equal(
			[4, FlowCache.Status.WAITING, false]
		)
		assert_array(Array(flow.last_used.slice(0, 4))).is_equal([0, 0, 0, 9])
		assert_array(Array(flow.ref_count.slice(0, 4))).is_equal([1, 0, 0, 1])
		assert_bool(flow.field(1).complete and flow.field(2).complete).is_true()
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
	var held: Array[World] = _pair(_key_world.bind(true))
	for world: World in held:
		Movement.integrate(world)
		var flow: FlowCache = world.flow
		assert_array([world.field[0], world.nav_next[0], flow.requests]).is_equal([2, -1, 3])
		assert_array(Array(flow.last_used.slice(0, 4))).is_equal([0, 0, 9, 0])
		assert_array(Array(flow.ref_count.slice(0, 4))).is_equal([1, 0, 1, 0])
		assert_array([flow.status[3], flow.field(2).complete]).is_equal([0, true])
	assert_str(StateDiff.first(held[0], held[1])).is_empty()


## A move class that no cache has (3 and -1) gets no field from acquire(): the unit that asks for
## its own goal's tile keeps the group's field and its NO_NEXT, and nothing is requested.
func test_a_move_class_the_cache_does_not_have_gets_no_field() -> void:
	for move_class: int in [3, -1]:
		var pair: Array[World] = _pair(_key_world.bind(true))
		for world: World in pair:
			world.type_move_class[0] = move_class
			Movement.integrate(world)
			var label: String = "class %d" % move_class
			(
				assert_array([world.field[0], world.nav_next[0], world.flow.requests])
				. override_failure_message(label)
				. is_equal([0, NO_NEXT, 3])
			)
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A goal off the map has the tile of the nearest edge (World.cell_of clamps each axis to its own
## bound, the columns and the rows apart; the division of a negative number truncates towards 0, so
## -5000 and 999 are both column 0): a unit on the key of its group's field asks for the field of
## that tile, on a wide and a tall map, for a goal beyond each edge and each corner.
func test_a_goal_off_the_map_is_asked_for_at_the_tile_of_the_nearest_edge() -> void:
	var goals: Array[Vector2i] = [
		Vector2i(-5000, -5000),
		Vector2i(-5000, 99999),
		Vector2i(99999, -5000),
		Vector2i(99999, 99999),
		Vector2i(5500, 99999),
		Vector2i(99999, 5500),
		Vector2i(-999, 5500),
		Vector2i(5500, -999),
	]
	for size: Vector2i in [Vector2i(20, 12), Vector2i(12, 20)]:
		for goal: Vector2i in goals:
			var pair: Array[World] = _pair(_off_map_world.bind(size, goal))
			var column: int = clampi(goal.x / 1000, 0, size.x - 1)
			var line: int = clampi(goal.y / 1000, 0, size.y - 1)
			for world: World in pair:
				Movement.integrate(world)
				var label: String = "%s, goal %s" % [size, goal]
				assert_int(world.field[0]).override_failure_message(label).is_equal(1)
				assert_int(world.flow.key_goal[1]).override_failure_message(label).is_equal(
					line * size.x + column
				)
			assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A unit that stands on the key of a group's field takes the field of its own goal's tile (the
## field names no next tile there, NO_NEXT), with a fresh best distance and stall count; a unit
## whose own goal is in that tile keeps the field and NO_NEXT. A unit one tile from a key that
## turned to rock is told none either (the key counts as none when its tile is blocked now).
func test_a_unit_on_the_key_of_a_group_field_takes_its_own_goals_field() -> void:
	var pair: Array[World] = _pair(_own_field_world)
	for world: World in pair:
		Movement.integrate(world)
		assert_array(Array(world.field.slice(0, 3))).is_equal([1, 0, 2])
		assert_array(Array(world.nav_next.slice(0, 3))).is_equal([-1, NO_NEXT, -1])
		assert_array([world.best_dist[0], world.stall[0]]).is_equal([UNREACHED, 0])
		# Unit 2 found the field's key blocked: it counts as none, so it also asks for its own.
		assert_array([world.best_dist[1], world.stall[1]]).is_equal([565, 0])
		assert_array(Array(world.flow.key_goal.slice(0, 3))).is_equal([110, 115, 104])
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The line-check period decides which tick a FIELD unit with a lookup due looks up its next tile:
## `(tick + id) % period == 0`, a period below 1 read as 1. A unit with a `nav_next` of -3 (neither
## -1 nor a tile) has it replaced exactly on those ticks. Periods -3 to 7, ticks 0 to 11, ids 1 to
## 3 and a tick at the top of the int32 range, where the sum is still not negative.
func test_the_line_check_period_decides_the_lookup_ticks_and_below_1_is_1() -> void:
	for period: int in [-3, 0, 1, 2, 5, 7]:
		for tick: int in [0, 1, 2, 3, 4, 5, 6, 7, 11, 2147483640]:
			var pair: Array[World] = _pair(_field_world.bind({&"N": 50}))
			for world: World in pair:
				for extra: int in 2:
					var row: int = world.add_unit(1, 0, 2500, 2500) - 1
					world.order[row] = MOVE
					world.nav_mode[row] = FIELD
					world.field[row] = 0
					world.goal_x[row] = 2500
					world.goal_y[row] = 500
					world.nav_next[row] = -3
				world.nav_next[0] = -3
				world.line_check_period_ticks = period
				world.tick = tick
				Movement.integrate(world)
			assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
			for world: World in pair:
				for row: int in 3:
					var due: bool = (tick + row + 1) % maxi(period, 1) == 0
					var label: String = "period %d tick %d row %d" % [period, tick, row]
					assert_bool(world.nav_next[row] != -3).override_failure_message(label).is_equal(
						due
					)


## stall_ticks decides when a unit with no progress goes idle: the first look sets its best
## distance, each look after it that does not improve counts a tick, and the order ends at the
## count of stall_ticks (a value below 1 ends it at the first). stall_ticks -1 to 4.
func test_the_stall_ends_the_order_at_stall_ticks_looks_without_progress() -> void:
	for stall_ticks: int in [-1, 0, 1, 2, 3, 4]:
		var pair: Array[World] = _pair(_stall_world.bind(stall_ticks))
		for looks: int in 6:
			for world: World in pair:
				Movement.integrate(world)
			assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
			var ended: bool = looks >= maxi(stall_ticks, 1)
			for world: World in pair:
				var label: String = "stall_ticks %d, look %d" % [stall_ticks, looks + 1]
				assert_bool(world.order[0] == IDLE).override_failure_message(label).is_equal(ended)
				assert_array([world.goal_x[0], world.goal_y[0]]).is_equal(
					[world.pos_x[0], world.pos_y[0]] if ended else [6000, 5000]
				)


## The pairs: a builder gives the same World twice, the first running the GDScript phase and the
## second the C++ kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		pair.append(_in(build.call(), impl))
	return pair


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, INTEGRATE)).is_empty()
	return world


## The floor of the square root of `n` by search, from a float guess made exact (n is below 2^53).
func _floor_sqrt(n: int) -> int:
	var root: int = int(sqrt(float(n)))
	while root * root > n:
		root -= 1
	while (root + 1) * (root + 1) <= n:
		root += 1
	return root


## A 5 x 5 open map with a field keyed on tile (2, 0) (cell 2), integrated, whose cost is then
## replaced round tile (2, 2) (cell 12): 100 on the tile (`HERE` in `neighbours` sets another cost),
## `neighbours` on those named, and UNREACHED on the others. One tank stands on the tile in FIELD,
## its goal in the key's tile, with the lookup due.
func _field_world(neighbours: Dictionary) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(5, 5))
	assert_int(world.flow.acquire(2, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var cost: PackedInt32Array = world.flow.field(0).cost
	var stride: int = 7
	var here: int = 3 * stride + 3
	var steps: Dictionary[StringName, int] = {
		&"NW": -stride - 1,
		&"N": -stride,
		&"NE": -stride + 1,
		&"W": -1,
		&"E": 1,
		&"SW": stride - 1,
		&"S": stride,
		&"SE": stride + 1,
	}
	cost[here] = int(neighbours.get(&"HERE", 100))
	for name: StringName in steps:
		cost[here + steps[name]] = int(neighbours.get(name, UNREACHED))
	world.add_unit(1, 0, 2500, 2500)
	world.order[0] = MOVE
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.goal_x[0] = 2500
	world.goal_y[0] = 500
	return world


## A 64 x 64 open map with a field keyed on `goal`, and two tanks in FIELD: unit 1 at `opposite`
## and unit 2 at the goal's own tile.
func _corner_world(goal: Vector2i, opposite: Vector2i) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(64, 64))
	assert_int(world.flow.acquire(goal.y * 64 + goal.x, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for tile: Vector2i in [opposite, goal]:
		world.add_unit(1, 0, tile.x * 1000 + 500, tile.y * 1000 + 500)
		var row: int = world.unit_count() - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		# A point 300 below the centre of the goal's tile, so that the unit at it has not arrived.
		world.goal_x[row] = goal.x * 1000 + 500
		world.goal_y[row] = goal.y * 1000 + 800
	return world


## A 20 x 12 open map with a cache of 3 slots and slot 0 keyed on tile (2, 2), complete. Tank 0
## steps 120 east on its own. Tanks 1 to 4 are ATTACK units in FIELD on slot 0 with their lookup
## due, and goals in tiles 175, 175, 50 and 217. The tick is 9.
func _attack_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12))
	world.flow_cache_size = 3
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 3)
	assert_int(world.flow.acquire(42, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	world.add_unit(1, 0, 3500, 500)
	world.order[0] = MOVE
	world.goal_x[0] = 15500
	world.goal_y[0] = 500
	world.nav_mode[0] = DIRECT
	world.nav_cell[0] = 0
	world.intent_x[0] = 120
	var starts: Array[Vector2i] = [
		Vector2i(4500, 2500), Vector2i(6500, 2500), Vector2i(4500, 4500), Vector2i(8500, 4500)
	]
	var goals: Array[Vector2i] = [
		Vector2i(15500, 8500), Vector2i(15900, 8100), Vector2i(10500, 2500), Vector2i(17500, 10500)
	]
	for index: int in 4:
		var row: int = world.add_unit(1, 0, starts[index].x, starts[index].y) - 1
		world.order[row] = ATTACK
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = goals[index].x
		world.goal_y[row] = goals[index].y
	FlowCache.run(world, 0)  # The references: four rows on slot 0.
	assert_int(world.flow.refs(0)).is_equal(4)
	world.tick = 9
	return world


func _attack_pair() -> Array[World]:
	return _pair(_attack_world)


## A 20 x 12 map and a cache of 3 slots with keys 30, 31 and 32 that nobody references, last used
## at ticks 5, 3 and 3, all complete. Tank 0 has no order. Tanks 1 and 2 are ATTACK units on slot 0,
## in FIELD, whose goals are in tiles 130 and 200: far from tile 30, so they re-key. The tick is 9.
func _lru_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12))
	world.flow_cache_size = 3
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 3)
	for key: int in [30, 31, 32]:
		assert_int(world.flow.acquire(key, TRACKED, world.map_version, 0)).is_greater(-1)
	FlowCache.run(world, BIG)
	var ages: Array[int] = [5, 3, 3]
	for slot: int in 3:
		world.flow.last_used[slot] = ages[slot]
	var goals: Array[Vector2i] = [Vector2i(10500, 6500), Vector2i(500, 10500)]
	world.add_unit(1, 0, 9500, 5500)
	for index: int in 2:
		var row: int = world.add_unit(1, 0, 10500, 2500 + index * 1000) - 1
		world.order[row] = ATTACK
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = goals[index].x
		world.goal_y[row] = goals[index].y
	world.tick = 9
	return world


## A 20 x 12 map with a group field keyed on tile 110 (10, 5) whose tile has turned to rock, slot 0,
## complete and referenced by three MOVE tanks in FIELD with their lookup due. Tank 0 stands on the
## key, its own goal in tile 115; tank 1 stands on the key and its goal is in it; tank 2 stands in
## tile 109 beside the key, with its goal in tile 104. Tanks 0 and 1 carry a best distance of 777
## and a stall count of 4. The tick is 9.
func _own_field_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12))
	assert_int(world.flow.acquire(110, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var starts: Array[Vector2i] = [
		Vector2i(10500, 5500), Vector2i(10500, 5500), Vector2i(9500, 5500)
	]
	var goals: Array[Vector2i] = [
		Vector2i(15500, 5500), Vector2i(10900, 5100), Vector2i(4500, 5500)
	]
	for index: int in 3:
		var row: int = world.add_unit(1, 0, starts[index].x, starts[index].y) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.group_cell[row] = 110
		world.goal_x[row] = goals[index].x
		world.goal_y[row] = goals[index].y
		world.best_dist[row] = 777 if index < 2 else UNREACHED
		world.stall[row] = 4 if index < 2 else 0
	FlowCache.run(world, 0)  # The references: three rows on slot 0.
	world.set_terrain(110, 2)  # Rock: the cache re-integrates slot 0, which keeps serving.
	assert_bool(world.flow.field(0).complete).is_true()
	assert_bool(world.is_passable(110, TRACKED)).is_false()
	world.tick = 9
	return world


## A `size` map with a field keyed on tile (4, 4), complete, and a MOVE tank in FIELD on that tile
## with the lookup due and its goal at `goal` in milli-tiles, which may be off the map.
func _off_map_world(size: Vector2i, goal: Vector2i) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(size.x, size.y))
	assert_int(world.flow.acquire(4 * size.x + 4, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	world.add_unit(1, 0, 4500, 4500)
	world.order[0] = MOVE
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.goal_x[0] = goal.x
	world.goal_y[0] = goal.y
	world.tick = 9
	return world


## A World with no map (a size of 0) whose one tank is in FIELD on a complete field of the cache
## and steps 120 east.
func _no_map_field_world() -> World:
	var world: World = World.new()
	world.type_ids.append(&"tank")
	world.type_speed.append(120)
	world.type_radius.append(400)
	world.type_selection_radius.append(500)
	world.type_spacing.append(1200)
	world.add_unit(1, 0, 2500, 2500)
	world.prepare()
	assert_int(world.map_cols).is_equal(0)
	world.flow.field(0).complete = true
	world.order[0] = MOVE
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.goal_x[0] = 9000
	world.goal_y[0] = 2500
	world.intent_x[0] = 120
	return world


## A World of no map but a size of `size` milli-tiles (not whole tiles) with one tank at `start`
## that steps (60, 60), more than the 9 milli to the edge.
func _ragged_world(size: Vector2i, start: Vector2i) -> World:
	var world: World = World.new()
	world.type_ids.append(&"tank")
	world.type_speed.append(120)
	world.type_radius.append(400)
	world.type_selection_radius.append(500)
	world.type_spacing.append(1200)
	world.map_w = size.x
	world.map_h = size.y
	world.add_unit(1, 0, start.x, start.y)
	world.prepare()
	world.intent_x[0] = 60
	world.intent_y[0] = 60
	return world


## A 12 x 8 map with rock in tile (5, 3) and a pending field (slot 0); two tanks at (4900, 3500)
## with a checked line (cell 7) and an intent of 200 east: unit 0 DIRECT, unit 1 FIELD on slot 0.
func _rock_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 8, [Vector2i(5, 3)]))
	assert_int(world.flow.acquire(0, TRACKED, world.map_version, 0)).is_equal(0)
	for mode: int in [DIRECT, FIELD]:
		var row: int = world.add_unit(1, 0, 4900, 3500) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = mode
		world.nav_cell[row] = 7
		world.field[row] = 0 if mode == FIELD else -1
		world.goal_x[row] = 10500
		world.goal_y[row] = 3500
		world.intent_x[row] = 200
	return world


## A 20 x 12 map and a cache of 4 slots, all complete but the free slot 3: slot 0 holds tile 84
## (4, 4) for the tank class, slot 1 tile 130 for the foot class, slot 2 tile 130 for the tank
## class, and with `held` false slot 2's key is of the map version before this one. One MOVE tank
## in FIELD on slot 0, on tile 84 (so its field names no next tile) with its own goal in tile 130.
## The tick is 9.
func _key_world(held: bool) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12))
	world.flow_cache_size = 4
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 4)
	for key: Array in [[84, TRACKED], [130, World.MoveClass.FOOT], [130, TRACKED]]:
		assert_int(world.flow.acquire(key[0], key[1], world.map_version, 0)).is_greater(-1)
	FlowCache.run(world, BIG)
	if not held:
		world.flow.key_version[2] = world.map_version - 1
	world.add_unit(1, 0, 4500, 4500)
	world.order[0] = MOVE
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.group_cell[0] = 84
	world.goal_x[0] = 10500
	world.goal_y[0] = 6500
	FlowCache.run(world, 0)  # The references: the tank on slot 0.
	world.tick = 9
	return world


## A tank at (5000, 5000) steering DIRECT at a goal 1000 east on a checked line, no intent, and the
## rule `stall_ticks`.
func _stall_world(stall_ticks: int) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 10))
	world.stall_ticks = stall_ticks
	world.add_unit(1, 0, 5000, 5000)
	world.order[0] = MOVE
	world.nav_mode[0] = DIRECT
	world.nav_cell[0] = 1
	world.goal_x[0] = 6000
	world.goal_y[0] = 5000
	return world


## What `_write_case` finds when the kernel writes in place: every observation true, and only a
## held copy keeps its old values.
func _written(hold: bool) -> Dictionary:
	var seen: Dictionary = {"alias": true, "member": true, "scalars": true, "cleared": true}
	seen.merge({"tables": true, "idle": true, "copy_kept": hold})
	return seen


## Movement.integrate on both Worlds of `_attack_pair` (the first runs the twin, the second the
## kernel), observed on the Thread that calls it. `hold` keeps a duplicate() of `pos_x` across the
## call.
static func _write_case(pair: Array[World], hold: bool) -> Dictionary:
	var twin: World = pair[0]
	var world: World = pair[1]
	var alias: PackedInt32Array = world.pos_x
	var alias_cost: PackedInt32Array = world.flow.field(1).cost
	var copy: PackedInt32Array = world.pos_x.duplicate() if hold else PackedInt32Array()
	# Own storage: a duplicate() shares its buffer with `copy` until one of them is written.
	var old_values: Array = Array(copy)
	var seen: Dictionary = {}
	Movement.integrate(twin)
	Movement.integrate(world)
	seen["alias"] = alias == twin.pos_x and alias[0] == 3620
	seen["member"] = world.pos_x == twin.pos_x and world.pos_y == twin.pos_y
	seen["scalars"] = world.flow.requests == twin.flow.requests and world.flow.requests == 3
	var cleared: bool = alias_cost.count(UNREACHED) == alias_cost.size()
	seen["cleared"] = cleared and not world.flow.field(1).complete
	seen["tables"] = StateDiff.first(world, twin) == ""
	# Kept only if the write forked: a write through the held buffer would change `copy` as well.
	seen["copy_kept"] = hold and Array(copy) == old_values and copy != world.pos_x
	# A second pass with the intent gone: no lookup is due and nothing moves, so no state changes.
	world.intent_x[0] = 0
	var before: PackedInt64Array = world.hash_parts()
	var requests: int = world.flow.requests
	Movement.integrate(world)
	seen["idle"] = world.hash_parts() == before and world.flow.requests == requests
	return seen
