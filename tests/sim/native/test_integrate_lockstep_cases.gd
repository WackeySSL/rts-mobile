extends GdUnitTestSuite
## The crafted cases of the INTEGRATE lockstep (ADR 0013 section 4, plan P37n3): small Worlds built
## to reach one rule of Movement.integrate, each built twice (the GDScript twin and the C++ kernel,
## through tests/sim/support/lockstep_rig.gd) and compared after every tick or call: the state hash
## and the full state of StateDiff. The long runs on the arena and the random states are in
## test_integrate_lockstep.gd. A case that runs ticks also counts what it reached on the twin's
## side (the rig's tally), so that it cannot pass by never meeting its rule; a case that builds a
## state by hand asserts the outcome that the twin's rule gives as well.
##
## The cases: walls with gaps, on a wide and a tall map; belts that tell the three move classes
## apart (scrub, wheeled-only, tracked-only); a group target that turns to rock (the blocked key); a
## closed room that the field cannot reach (unreachable goals); a cache of two slots shared by four
## groups; ATTACK units on moving targets (the re-key); opposite corners of the largest map; exact
## ties (the scan order of best_neighbour, the arrival range, the re-key distance); and the edges of
## the numbers (a negative tick and the remainder of a negative sum, an order none of the sim's, a
## field and a cache smaller than the map, a map with no width, positions at the top of the int32
## range, rule ints at their limits).

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TRACKED: int = World.MoveClass.TRACKED
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
const IDLE: int = World.Order.IDLE
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const NO_NEXT: int = -2
const BIG: int = 100000
const INT32_MAX: int = 2147483647
const INT32_MIN: int = -2147483648
## GridWorld's terrain numbers: rock, and the one (cost 20) that the tie sweep makes cost 14.
const ROCK: int = 2
const SLOW: int = 5
const TIE_COST: int = 14
## The offsets of the arrival sweep, "x,y" pairs: a step of 120 exactly on the axes and on the 3-4-5
## triples, one milli more, one milli less, the 84-84 and 85-85 diagonals (14112 and 14450) and a
## square of 14401 (120, 1), all against 14400.
const ARRIVAL_OFFSETS: String = "120,0 -120,0 0,120 0,-120 72,96 -72,96 72,-96 -96,-72 121,0 0,-121"
const ARRIVAL_NEAR: String = "73,96 96,73 119,0 71,96 84,84 85,85 120,1 -1,120"
## The corners of the largest map.
const CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(63, 0), Vector2i(0, 63), Vector2i(63, 63)
]


func test_walls_with_gaps_on_a_wide_map_and_on_a_tall_one() -> void:
	for size: Vector2i in [Vector2i(40, 20), Vector2i(20, 40)]:
		var rig: RefCounted = LockstepRig.new().setup(_walls_world.bind(size))
		var label: String = "map %s" % size
		assert_array(rig.problems).is_empty()
		assert_str(rig.run(520, _walls_orders)).override_failure_message(label).is_empty()
		_assert_reached(rig, {&"field": 2000, &"named": 1500, &"ended": 18}, label)
		# At the end all 18 units are at the south-west corner, back through both gaps.
		var west: int = 0
		for row: int in rig.worlds[0].unit_count():
			west += int(rig.worlds[0].pos_x[row] < size.x * 1000 / 3)
		assert_int(west).override_failure_message(label).is_equal(18)


func test_belts_of_scrub_wheel_only_and_track_only_ground_send_each_class_its_own_way() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_belts_world)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(640, _belts_orders)).is_empty()
	_assert_reached(rig, {&"field": 2000, &"named": 1500, &"ended": 15})
	# Fields are per (goal, class): the tanks and the wheeled units share a goal, not a slot, and
	# the foot units cross the scrub and need none.
	var classes: Dictionary[int, bool] = {}
	var flow: FlowCache = rig.worlds[0].flow
	for slot: int in flow.status.size():
		if flow.status[slot] != FlowCache.Status.FREE:
			classes[flow.key_class[slot]] = true
	assert_array(classes.keys()).contains_exactly_in_any_order([WHEELED, TRACKED])


## The target tile of a group is rock at tick 0, and later at tick 2 (the field keyed on it is
## re-integrated while the tanks follow it): six tanks stand round the key in FIELD with the lookup
## due, and the field's key now names rock, which counts as none (the field seeds its key at cost 0
## whatever the terrain), so each takes the field of its own goal's tile.
func test_a_group_target_that_turns_to_rock_gives_the_units_their_own_fields() -> void:
	for rock_tick: int in [0, 2]:
		var rig: RefCounted = LockstepRig.new().setup(_rockfall_world)
		var label: String = "rock at tick %d" % rock_tick
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(200, _rockfall_orders.bind(rock_tick))
		assert_str(found).override_failure_message(label).is_empty()
		_assert_reached(rig, {&"field": 6, &"own_fields": 3}, label)


## A goal inside a closed room of rock: nothing outside reaches it, so the field is UNREACHED
## outside, a tank's lookup names no tile (NO_NEXT) and the stall rule ends its order at any
## distance. Foot units can cross the room's one scrub tile, so they get in.
func test_a_goal_the_field_cannot_reach_ends_the_order_of_the_tanks_that_wait_for_it() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_room_world)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(400, _room_orders)).is_empty()
	_assert_reached(rig, {&"field": 1000, &"named": 200, &"no_next": 300, &"ended": 12})
	var twin: World = rig.worlds[0]
	for row: int in twin.unit_count():
		assert_int(twin.order[row]).is_equal(IDLE)
		# Only the foot units (type 1) are in the room; the tanks stopped short of its wall.
		assert_bool(twin.pos_x[row] > 14000).is_equal(twin.type_index[row] == 1)


## Four groups ask for four fields on a cache of two slots: the first two take the slots, the others
## stay DIRECT and ask again every turn until a group lets one go, and when the groups swap targets
## at tick 200 the slots change hands. The slot tables (key, class, version, last use, references,
## request number, status) are compared after every tick on their own.
func test_a_cache_of_two_slots_shared_by_four_groups_gives_the_same_tables() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_slots_world.bind(2))
	assert_array(rig.problems).is_empty()
	for _tick: int in 520:
		assert_str(rig.step(_slots_orders)).is_empty()
		assert_array(_tables(rig.worlds[1])).is_equal(_tables(rig.worlds[0]))
	_assert_reached(rig, {&"field": 1000, &"contended": 100, &"fresh": 2, &"recycles": 2})


## Three groups of ATTACK units chase three enemy tanks that cross the gaps of two walls, on a cache
## of four slots: the goal of an ATTACK unit follows its target, so once it is more than
## `attack_rekey_milli` from the tile its field is keyed on the unit takes the field of its goal's
## tile (a free slot, else the least recently used one that no unit holds, else it keeps the old).
func test_attack_units_on_moving_targets_rekey_their_fields() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_chase_world)
	assert_array(rig.problems).is_empty()
	for _tick: int in 700:
		assert_str(rig.step(_chase_orders)).is_empty()
		assert_array(_tables(rig.worlds[1])).is_equal(_tables(rig.worlds[0]))
	_assert_reached(rig, {&"field": 1000, &"named": 800, &"rekeys": 6, &"recycles": 1})


## Units in the four corners of the largest map (64 x 64), each sent to the opposite corner. Open,
## they steer straight over the longest distance there is (the squares reach 8e9, past 32 bits).
## With a rock lid on every corner a goal cannot be reached, a unit's field names no tile and it
## takes the square root of that squared distance (89,095) for its stall rule. In the serpentine
## the field's costs run into the thousands.
func test_units_in_opposite_corners_of_the_largest_map() -> void:
	for kind: StringName in [&"open", &"lidded", &"serpentine"]:
		var rig: RefCounted = LockstepRig.new().setup(_corners_world.bind(kind))
		var label: String = String(kind)
		assert_array(rig.problems).is_empty()
		assert_str(rig.run(6, _corners_orders)).override_failure_message(label).is_empty()
		if kind == &"lidded":
			# The first look at the stall rule: the root of 2 x 63000 squared, floored.
			var squared: int = 2 * 63000 * 63000
			var expected: int = _floor_sqrt(squared)
			assert_int(rig.worlds[0].best_dist[0]).override_failure_message(label).is_equal(
				expected
			)
			assert_int(rig.worlds[1].best_dist[0]).override_failure_message(label).is_equal(
				expected
			)
		assert_str(rig.run(480, _corners_orders)).override_failure_message(label).is_empty()
		if kind == &"lidded":
			_assert_reached(rig, {&"field": 40, &"no_next": 40, &"ended": 4}, label)
		elif kind == &"serpentine":
			_assert_reached(rig, {&"field": 500, &"named": 400, &"ended": 4}, label)
		else:
			_assert_reached(rig, {&"ended": 4}, label)


## best_neighbour on a 9 x 9 map with a rock pillar on each diagonal neighbour of the goal (4, 4):
## a unit on every open tile looks up its next tile in one pass. A unit in a corner of the map has
## two neighbours of the same cost and the scan order NW, N, NE, W, E, SW, S, SE decides: (2, 2)
## takes (3, 2), the east one before the south one, (6, 2) takes (5, 2), (2, 6) takes (2, 5) and
## (6, 6) takes (6, 5).
func test_exact_ties_between_neighbours_go_by_the_scan_order_on_every_tile() -> void:
	var pair: Array[World] = _pair(_pillar_world)
	_integrate_all(pair)
	_assert_same(pair)
	for world: World in pair:
		for tile: Array in [[2, 2, 21], [6, 2, 23], [2, 6, 47], [6, 6, 51]]:
			var row: int = _row_at(world, Vector2i(tile[0], tile[1]))
			var label: String = "tile (%d, %d)" % [tile[0], tile[1]]
			assert_int(world.nav_next[row]).override_failure_message(label).is_equal(tile[2])
		# A next tile for every unit but the one on the goal, which has none.
		assert_int(world.nav_next.count(-1)).is_equal(0)
		assert_int(world.nav_next.count(NO_NEXT)).is_equal(1)


## The same sweep on a 7 x 7 map where the four orthogonal neighbours of the goal (3, 3) cost 14 and
## the rest 10: every neighbour of the goal then costs exactly 14, the diagonal onto grass
## (10 x 14 / 10) as much as the orthogonal onto the dear tile. The tile (3, 1) has three
## neighbours of that cost (SW, S, SE) and takes the first in the scan, (2, 2).
func test_exact_ties_between_a_diagonal_and_an_orthogonal_cost() -> void:
	var pair: Array[World] = _pair(_tie_cost_world)
	_integrate_all(pair)
	_assert_same(pair)
	for world: World in pair:
		assert_int(world.nav_next[_row_at(world, Vector2i(2, 2))]).is_equal(3 + 3 * 7)
		assert_int(world.nav_next[_row_at(world, Vector2i(3, 1))]).is_equal(2 + 2 * 7)
		assert_int(world.nav_next.count(NO_NEXT)).is_equal(1)


## The arrival range is closed: a unit exactly one step from its goal (to_goal == speed squared, on
## an axis and on the 3-4-5 offsets) arrives in the tick, one milli further does not, and so on at
## the 84-84 and 85-85 diagonals. Speed 120, so 72 and 96 make 120.
func test_a_unit_exactly_one_step_from_its_goal_arrives_and_one_milli_more_does_not() -> void:
	var offsets: Array[Vector2i] = _offsets(ARRIVAL_OFFSETS + " " + ARRIVAL_NEAR)
	var rig: RefCounted = LockstepRig.new().setup(_arrival_world.bind(offsets))
	assert_array(rig.problems).is_empty()
	assert_str(rig.step()).is_empty()
	var twin: World = rig.worlds[0]
	for index: int in offsets.size():
		var squared: int = offsets[index].x * offsets[index].x + offsets[index].y * offsets[index].y
		var label: String = "offset %s" % offsets[index]
		var arrived: bool = twin.order[index] == IDLE
		assert_bool(arrived).override_failure_message(label).is_equal(squared <= 120 * 120)
	assert_str(rig.run(3)).is_empty()
	assert_int(twin.order.count(IDLE)).is_equal(offsets.size())


## The stall range is closed: a DIRECT unit with a checked line counts its distance to the goal (its
## best distance) only within `stall_range_spacings` x the formation spacing of its type (2 x 1200,
## then 3 x 1200): a unit exactly on the range counts, one milli outside does not. 3-4-5 offsets of
## exactly the range, one milli more and one milli less.
func test_a_unit_exactly_the_stall_range_from_its_goal_counts_and_one_milli_more_does_not() -> void:
	for reach: int in [2, 3]:
		var span: int = 1200 * reach
		var offsets: Array[Vector2i] = _ring_offsets(span)
		var pair: Array[World] = _pair(_arrival_world.bind(offsets, reach))
		_integrate_all(pair)
		_assert_same(pair, "reach %d" % reach)
		for world: World in pair:
			for index: int in offsets.size():
				var squared: int = offsets[index].x * offsets[index].x
				squared += offsets[index].y * offsets[index].y
				var label: String = "reach %d, offset %s" % [reach, offsets[index]]
				var counted: bool = world.best_dist[index] != FlowField.UNREACHED
				assert_bool(counted).override_failure_message(label).is_equal(
					squared <= span * span
				)
				if counted:
					assert_int(world.best_dist[index]).is_equal(_floor_sqrt(squared))


## The re-key distance is closed too: an ATTACK unit whose goal is exactly `attack_rekey_milli` from
## the centre of its field's key tile keeps the field, one milli further takes the field of its
## goal's tile. 3-4-5 offsets of exactly the limit, on the default 4000 and on 2500.
func test_an_attack_goal_exactly_the_rekey_distance_from_its_key_keeps_the_field() -> void:
	for limit: int in [4000, 2500]:
		var offsets: Array[Vector2i] = _ring_offsets(limit)
		var pair: Array[World] = _pair(_rekey_world.bind(offsets, limit))
		_integrate_all(pair)
		_assert_same(pair, "limit %d" % limit)
		for world: World in pair:
			for index: int in offsets.size():
				var squared: int = offsets[index].x * offsets[index].x
				squared += offsets[index].y * offsets[index].y
				var label: String = "limit %d, offset %s" % [limit, offsets[index]]
				var kept: bool = world.field[index] == 0
				assert_bool(kept).override_failure_message(label).is_equal(squared <= limit * limit)


## The lookup turn is `(tick + id) % period == 0`, and a negative sum has a negative remainder in
## both GDScript and C++ (truncation toward zero), so it is never the turn. Ticks from -100 to 11
## and periods from -4 to 7 (below 1 reads as 1), three FIELD units whose `nav_next` is a stale -3
## that only a lookup replaces.
func test_the_lookup_turn_of_a_negative_tick_is_never_a_turn_unless_the_remainder_is_0() -> void:
	for period: int in [-4, 0, 1, 2, 3, 5, 7]:
		for tick: int in [-100, -11, -10, -7, -4, -3, -2, -1, 0, 4, 11]:
			var pair: Array[World] = _pair(_turn_world.bind(period, tick))
			var label: String = "period %d, tick %d" % [period, tick]
			_integrate_all(pair)
			_assert_same(pair, label)
			for world: World in pair:
				for row: int in 3:
					var due: bool = (tick + row + 1) % maxi(period, 1) == 0
					var looked_up: bool = world.nav_next[row] != -3
					assert_bool(looked_up).override_failure_message(label).is_equal(due)


## An order that is none of the sim's four (4, 5, 7, -1) is no ATTACK: its goal is 7000 from the
## key of its field, and it keeps the field (an ATTACK unit would take the field of its goal's
## tile), while an order of 4 within one step of its goal arrives like any move.
func test_an_order_that_is_none_of_the_known_ones_is_no_attack_and_arrives_like_a_move() -> void:
	var pair: Array[World] = _pair(_unknown_order_world)
	_integrate_all(pair)
	_assert_same(pair)
	for world: World in pair:
		assert_array(Array(world.field.slice(0, 5))).is_equal([0, 0, 0, 0, -1])
		assert_array(Array(world.order.slice(0, 5))).is_equal([4, 5, 7, -1, IDLE])
		assert_int(world.flow.requests).is_equal(1)


## A served field that covers fewer cells than the map has (`cell_count` 100 of a 20 x 12 map): the
## unit on tile 150 gets no next tile (NO_NEXT, the lookup is outside the field), the one on tile 99
## does (78, the diagonal). The guard is the twin's `cell >= cell_count`.
func test_a_field_that_serves_fewer_cells_than_the_map_names_no_tile_beyond_them() -> void:
	var pair: Array[World] = _pair(_short_field_world)
	_integrate_all(pair)
	_assert_same(pair)
	for world: World in pair:
		assert_array([world.nav_next[0], world.nav_next[1]]).is_equal([NO_NEXT, 78])


## A cache that was sized for 10 rows of a 12-row map: `acquire` refuses a goal in the first cell
## past the cache (cell 200, `cols * rows`) and keeps the unit's slot, and the unit that stands in
## the rows past it gets no next tile. An ATTACK unit's goal in tile (0, 10) is 7000 from its key.
func test_a_cache_sized_for_fewer_rows_than_the_map_refuses_the_goal_past_it() -> void:
	var pair: Array[World] = _pair(_short_cache_world)
	_integrate_all(pair)
	_assert_same(pair)
	for world: World in pair:
		assert_array([world.field[0], world.flow.requests]).is_equal([0, 1])
		assert_int(world.nav_next[1]).is_equal(NO_NEXT)


## A map whose size is not positive (map_w and map_h of 0, -3, -998, 1 and 500 on a 6 x 4 tile grid)
## and units at 0 and 3 with steps of -2 to 600: the upper clamp bound is below the lower, or 0, and
## a step that goes below 0 is clamped to 0 by the lower bound first (GDScript's clampi tests the
## lower bound first). The divisions of negative numbers truncate toward 0 in both.
func test_a_map_with_no_width_or_a_negative_one_clamps_like_the_twin() -> void:
	var sizes: Array[int] = [0, -3, -998, 1, 500]
	for map_w: int in sizes:
		for map_h: int in sizes:
			var pair: Array[World] = _pair(_narrow_world.bind(map_w, map_h))
			_integrate_all(pair)
			_integrate_all(pair)
			_assert_same(pair, "map %d x %d" % [map_w, map_h])
	# The first unit is at (0, 0) and steps (-2, -2): below 0, so the lower bound wins and it stays
	# at 0, where a clamp that tested the upper bound first would give -4.
	var low: Array[World] = _pair(_narrow_world.bind(-3, -3))
	_integrate_all(low)
	for world: World in low:
		assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([0, 0])


## Positions at the top of the int32 range on a world with no map: a unit of speed 2^31 - 1 whose
## goal is 2^31 - 1 away on both axes (to_goal just under 2^63), a goal at INT32_MIN, a unit that
## stalls at a distance of 2.1e9 (a square of 4.5e18 and the root stored in an int32), steps of
## 2^32 - 2 and the clamp to the largest int32.
func test_positions_at_the_top_of_the_int32_range_on_a_world_with_no_map() -> void:
	var pair: Array[World] = _pair(_extreme_world)
	for call: int in 4:
		_integrate_all(pair)
		for world: World in pair:
			world.tick += 1
		_assert_same(pair, "call %d" % call)
	for world: World in pair:
		# Unit 0 stalls 2.12e9 from its goal: its best distance is that root, then it counts.
		assert_int(world.best_dist[0]).is_equal(_floor_sqrt(2 * 1500000000 * 1500000000))
		assert_int(world.stall[0]).is_equal(3)
		# Unit 1 steps by 2^32 - 2 and is clamped to the largest int32 on both axes.
		assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([INT32_MAX, INT32_MAX])
		# Unit 5 is on no tile of a world with no map, so the stall rule never looks at it.
		assert_array([world.best_dist[5], world.stall[5]]).is_equal([FlowField.UNREACHED, 0])


## Rule ints at their limits, each on a run of the walls map with tanks, foot and wheeled units for
## 140 ticks: a line-check period of 0, -5 and 2^31 - 1, a stall of 0, -1 and 2^31 - 1 ticks, a
## stall range of 0, -3 and 1,800,000 spacings (a square of 4.7e18), a re-key distance of -4000, 0
## and 2^31 - 1 (a square of 4.6e18).
func test_rule_ints_at_their_limits_give_the_same_runs() -> void:
	var edges: Dictionary[StringName, Array] = {
		&"line_check_period_ticks": [0, -5, INT32_MAX],
		&"stall_ticks": [0, -1, INT32_MAX],
		&"stall_range_spacings": [0, -3, 1800000],
		&"attack_rekey_milli": [-4000, 0, INT32_MAX],
	}
	for rule: StringName in edges:
		for value: int in edges[rule]:
			var rig: RefCounted = LockstepRig.new().setup(_walls_with.bind(rule, value))
			var label: String = "%s = %d" % [rule, value]
			assert_array(rig.problems).is_empty()
			assert_str(rig.run(140, _walls_orders)).override_failure_message(label).is_empty()
			if rule != &"line_check_period_ticks" or value != INT32_MAX:
				# With a period of 2^31 - 1 no line is ever checked, so no unit takes a field.
				_assert_reached(rig, {&"field": 100}, label)


## The recount of references stops at the shorter of the row count and the `field` column. The two
## cannot differ in a World that a kernel takes: check_world wants as many entries as rows, so a
## column with a tail of stale references is refused for FLOW and for INTEGRATE and neither kernel
## runs. That bound is therefore no behaviour a lockstep can reach, and a C++ recount that loops
## over the whole column instead is the same function on every state the kernels accept.
func test_a_field_column_longer_than_the_rows_is_refused_so_the_recount_has_no_tail() -> void:
	var kernels: Object = SimImpls.create_kernels()
	var world: World = _walls_world(Vector2i(40, 20))
	for phase: int in [SimProbe.Phase.FLOW, SimProbe.Phase.INTEGRATE]:
		assert_int(kernels.check_world(world, phase)).is_equal(0)
	var longer: PackedInt32Array = world.field.duplicate()
	longer.resize(world.unit_count() + 3)
	longer.fill(0)
	world.field = longer
	for phase: int in [SimProbe.Phase.FLOW, SimProbe.Phase.INTEGRATE]:
		assert_int(kernels.check_world(world, phase)).is_not_equal(0)


## Asserts that a run reached each rule at least as often as `least` (by tally name) says.
func _assert_reached(rig: RefCounted, least: Dictionary, label: String = "") -> void:
	for name: StringName in least:
		var found: int = rig.tally[name]
		var message: String = "%s: reached %s" % [label, name]
		assert_int(found).override_failure_message(message).is_greater(int(least[name]) - 1)


## Asserts that the two Worlds of a pair agree: the state hash and the full state.
func _assert_same(pair: Array[World], label: String = "") -> void:
	var found: String = LockstepRig.difference(pair[0], pair[1])
	assert_str(found).override_failure_message(label).is_empty()


## The pair of `build` (see LockstepRig.pair), with the check that the kernels really attached.
func _pair(build: Callable) -> Array[World]:
	var problems: Array[String] = []
	var found: Array[World] = LockstepRig.pair(build, false, problems)
	assert_array(problems).is_empty()
	return found


## Movement.integrate on every World of the pair.
func _integrate_all(pair: Array[World]) -> void:
	for world: World in pair:
		Movement.integrate(world)


## The slot tables of acquire, as arrays, with the request counter last.
func _tables(world: World) -> Array:
	var flow: FlowCache = world.flow
	return [
		Array(flow.key_goal),
		Array(flow.key_class),
		Array(flow.key_version),
		Array(flow.last_used),
		Array(flow.ref_count),
		Array(flow.requested),
		Array(flow.status),
		flow.requests,
	]


## The floor of the square root of `n` by search, from a float guess made exact (n is below 2^62).
func _floor_sqrt(n: int) -> int:
	var root: int = int(sqrt(float(n)))
	while root * root > n:
		root -= 1
	while (root + 1) * (root + 1) <= n:
		root += 1
	return root


## The offsets of "x,y x,y ..." as vectors.
func _offsets(text: String) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for pair: String in text.split(" "):
		var parts: PackedStringArray = pair.split(",")
		found.append(Vector2i(int(parts[0]), int(parts[1])))
	return found


## The row of the unit standing at the centre of `tile`, -1 if none does.
func _row_at(world: World, tile: Vector2i) -> int:
	for row: int in world.unit_count():
		if world.pos_x[row] == tile.x * 1000 + 500 and world.pos_y[row] == tile.y * 1000 + 500:
			return row
	return -1


## Offsets at exactly `limit` from a point (on an axis and on the 3-4-5 triple of it), one milli
## beyond it and one milli short of it.
func _ring_offsets(limit: int) -> Array[Vector2i]:
	var unit: int = limit / 5
	var found: Array[Vector2i] = [Vector2i(limit, 0), Vector2i(0, -limit)]
	found.append_array([Vector2i(-3 * unit, 4 * unit), Vector2i(4 * unit, -3 * unit)])
	found.append_array([Vector2i(limit + 1, 0), Vector2i(0, -limit - 1)])
	found.append_array([Vector2i(-3 * unit, 4 * unit + 1), Vector2i(4 * unit + 1, -3 * unit)])
	found.append_array([Vector2i(limit - 1, 0), Vector2i(3 * unit - 1, 4 * unit)])
	return found


## The rows of a `cols` x `rows` map with two walls of rock: column cols / 3 from the top down to
## four rows above the bottom (a gap at the bottom), and column 2 cols / 3 from four rows below the
## top down (a gap at the top).
@warning_ignore("integer_division")
func _wall_rows(cols: int, rows: int) -> PackedStringArray:
	var rock: Array[Vector2i] = []
	for row: int in rows:
		if row < rows - 4:
			rock.append(Vector2i(cols / 3, row))
		if row >= 4:
			rock.append(Vector2i(cols * 2 / 3, row))
	return GridWorld.grass(cols, rows, rock)


## The walls map with six units of each move class (tracked, foot, wheeled) in a block at the west.
func _walls_world(size: Vector2i) -> World:
	var world: World = GridWorld.from_rows(_wall_rows(size.x, size.y), [TRACKED, FOOT, WHEELED])
	for type: int in 3:
		GridWorld.add_block(world, 6, 3, 1000, 1500 + type * 3000, 1000, type)
	return world


## The 40 x 20 walls map with the rule int `rule` of the World set to `value`.
func _walls_with(rule: StringName, value: int) -> World:
	var world: World = _walls_world(Vector2i(40, 20))
	world.set(rule, value)
	return world


## Everyone to the north-east (past both walls) at tick 0, and to the south-west at tick 250.
func _walls_orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	var ids: PackedInt32Array = LockstepRig.ids_of(world, 1)
	if tick == 0:
		out.append(Command.move(1, ids, (world.map_cols - 3) * 1000 + 500, 2500))
	elif tick == 250:
		out.append(Command.move(1, ids, 2500, (world.map_rows - 2) * 1000 + 500))
	return out


## 32 x 12: a belt two tiles wide of 'w' (foot and wheeled cross it) at columns 8-9 with a gap at
## the bottom, one of 't' (foot and tracked) at 16-17 with a gap at the top, and one of scrub (foot
## only) at 24-25 with a gap in the middle. Five units of each class at the west.
func _belts_world() -> World:
	var lines: PackedStringArray = GridWorld.grass(32, 12)
	for row: int in 12:
		var line: String = lines[row]
		for column: int in 2:
			if row < 10:
				line[8 + column] = "w"
			if row > 1:
				line[16 + column] = "t"
			if row != 5 and row != 6:
				line[24 + column] = "^"
		lines[row] = line
	var world: World = GridWorld.from_rows(lines, [TRACKED, FOOT, WHEELED])
	for type: int in 3:
		GridWorld.add_block(world, 5, 5, 1000, 3500 + type * 2000, 1000, type)
	return world


func _belts_orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	var ids: PackedInt32Array = LockstepRig.ids_of(world, 1)
	if tick == 0:
		out.append(Command.move(1, ids, 30500, 5500))
	elif tick == 320:
		out.append(Command.move(1, ids, 1500, 5500))
	return out


## 24 x 12 with a wall in column 10 (rows 0 to 7), a complete field of the tank class keyed on tile
## (20, 2) (cell 68), and six tanks round the key in FIELD on it: MOVE, group target 68, `nav_next`
## -1 (the lookup is due), the line to the goal not checked again in their tile, and each with its
## own goal in a tile of its own, not the key.
func _rockfall_world() -> World:
	var rock: Array[Vector2i] = []
	for row: int in 8:
		rock.append(Vector2i(10, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(24, 12, rock), [TRACKED])
	assert_int(world.flow.acquire(68, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var tiles: Array[Vector2i] = [
		Vector2i(19, 2), Vector2i(21, 2), Vector2i(20, 1), Vector2i(20, 3), Vector2i(19, 3)
	]
	var goals: Array[Vector2i] = [
		Vector2i(16, 6), Vector2i(14, 9), Vector2i(22, 8), Vector2i(18, 10), Vector2i(23, 10)
	]
	tiles.append(Vector2i(21, 1))
	goals.append(Vector2i(15, 2))
	for index: int in tiles.size():
		var tile: Vector2i = tiles[index]
		var row: int = world.add_unit(1, 0, tile.x * 1000 + 500, tile.y * 1000 + 500) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.nav_cell[row] = tile.y * 24 + tile.x
		world.field[row] = 0
		world.group_cell[row] = 68
		world.goal_x[row] = goals[index].x * 1000 + 500
		world.goal_y[row] = goals[index].y * 1000 + 500
	FlowCache.run(world, 0)  # The references: six rows on slot 0.
	return world


## The key tile (20, 2) turns to rock at `rock_tick`, before that tick's step.
func _rockfall_orders(world: World, tick: int, rock_tick: int) -> Array[Command]:
	if tick == rock_tick:
		world.set_terrain(2 * 24 + 20, ROCK)
	return []


## 24 x 14: a room of rock, columns 14 to 19 and rows 3 to 10, closed but for one scrub tile at
## (14, 6) that foot units cross. Six tanks and six foot units at the west.
func _room_world() -> World:
	var lines: PackedStringArray = GridWorld.grass(24, 14)
	for row: int in range(3, 11):
		for column: int in range(14, 20):
			var edge: bool = row == 3 or row == 10 or column == 14 or column == 19
			if edge:
				lines[row][column] = "#"
	lines[6][14] = "^"
	var world: World = GridWorld.from_rows(lines, [TRACKED, FOOT])
	GridWorld.add_block(world, 6, 3, 2000, 2500, 1000, 0)
	GridWorld.add_block(world, 6, 3, 2000, 6500, 1000, 1)
	return world


func _room_orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		out.append(Command.move(1, LockstepRig.ids_of(world, 1), 16500, 6500))
	return out


## The walls map of 40 x 20 with a cache of `slots` slots and four groups of five tanks.
func _slots_world(slots: int) -> World:
	var world: World = GridWorld.from_rows(_wall_rows(40, 20), [TRACKED])
	world.flow_cache_size = slots
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), slots)
	for group: int in 4:
		GridWorld.add_block(world, 5, 5, 1000, 1500 + group * 4000, 1000, 0)
	return world


## Group g goes to its own tile on the east side at tick 0; at tick 200 each takes the next one's.
@warning_ignore("integer_division")
func _slots_orders(_world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0 or tick == 200:
		var turn: int = tick / 200
		for group: int in 4:
			var ids: PackedInt32Array = PackedInt32Array(range(group * 5 + 1, group * 5 + 6))
			var goal_y: int = 2500 + ((group + turn) % 4) * 4500
			out.append(Command.move(1, ids, 36500, goal_y))
	return out


## 30 x 16 with a wall in column 12 (down from the top to row 11) and one in column 20 (from row 4
## down), a cache of four slots, eight player 1 tanks at the west that hunt three player 2 tanks
## (ids 9 to 11) in the east: three, three and two of them on one target each.
func _chase_world() -> World:
	var rock: Array[Vector2i] = []
	for row: int in 16:
		if row < 12:
			rock.append(Vector2i(12, row))
		if row >= 4:
			rock.append(Vector2i(20, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(30, 16, rock), [TRACKED])
	world.player_count = 2
	world.flow_cache_size = 4
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 4)
	GridWorld.add_block(world, 8, 4, 1000, 1500, 1000, 0)
	for index: int in 3:
		world.add_unit(2, 0, 26500, 1500 + index * 2000)
	return world


## The enemy tanks cross to the south-west at tick 0 and back to the north-east at tick 330. At tick
## 0 the attackers take their targets by hand (the units here are unarmed, which an ATTACK command
## needs).
func _chase_orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	var enemies: PackedInt32Array = LockstepRig.ids_of(world, 2)
	if tick == 0:
		var groups: Array[PackedInt32Array] = [
			PackedInt32Array([0, 1, 2]), PackedInt32Array([3, 4, 5]), PackedInt32Array([6, 7])
		]
		for index: int in 3:
			var target_row: int = world.index_of(9 + index)
			for row: int in groups[index]:
				world.order[row] = ATTACK
				world.order_target[row] = 9 + index
				world.goal_x[row] = world.pos_x[target_row]
				world.goal_y[row] = world.pos_y[target_row]
			Movement.reset_nav(world, groups[index], DIRECT)
		out.append(Command.move(2, enemies, 2500, 14500))
	elif tick == 330:
		out.append(Command.move(2, enemies, 25500, 2500))
	return out


## The 64 x 64 map with a unit in each corner (units 1 to 4: top left, top right, bottom left,
## bottom right) at speed 900. `kind`: `open`; `lidded`, three rock tiles in each corner (a corner
## tile has three neighbours, so the unit and the goal there are walled in); `serpentine`, walls
## across the map at rows 15, 31 and 47 with the gap at the right, the left and the right.
func _corners_world(kind: StringName) -> World:
	var rock: Array[Vector2i] = []
	if kind == &"lidded":
		for corner: Vector2i in CORNERS:
			var inward: Vector2i = Vector2i(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
			rock.append(corner + Vector2i(inward.x, 0))
			rock.append(corner + Vector2i(0, inward.y))
			rock.append(corner + inward)
	elif kind == &"serpentine":
		for column: int in 64:
			if column < 60:
				rock.append(Vector2i(column, 15))
				rock.append(Vector2i(column, 47))
			if column > 3:
				rock.append(Vector2i(column, 31))
	var world: World = GridWorld.from_rows(GridWorld.grass(64, 64, rock), [TRACKED])
	world.type_speed[0] = 900
	for corner: Vector2i in CORNERS:
		world.add_unit(1, 0, corner.x * 1000 + 500, corner.y * 1000 + 500)
	return world


## At tick 0 each corner unit is ordered, by hand, to the centre of the opposite corner's tile (a
## command would move a goal on blocked ground to the nearest open tile, and a lidded corner is
## closed).
func _corners_orders(world: World, tick: int) -> Array[Command]:
	if tick == 0:
		for row: int in world.unit_count():
			world.order[row] = MOVE
			world.goal_x[row] = 63500 if world.pos_x[row] < 1000 else 500
			world.goal_y[row] = 63500 if world.pos_y[row] < 1000 else 500
			Movement.reset_nav(world, PackedInt32Array([row]), DIRECT)
	return []


## A 9 x 9 open map with pillars at (3, 3), (5, 3), (3, 5) and (5, 5) and a unit on every open tile
## following the field of the goal (4, 4).
func _pillar_world() -> World:
	var rock: Array[Vector2i] = [Vector2i(3, 3), Vector2i(5, 3), Vector2i(3, 5), Vector2i(5, 5)]
	var world: World = GridWorld.from_rows(GridWorld.grass(9, 9, rock), [TRACKED])
	return _with_field_units(world, 4 + 4 * 9)


## A 7 x 7 map with the four orthogonal neighbours of the goal (3, 3) made to cost 14 on every
## class.
func _tie_cost_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(7, 7), [TRACKED])
	for move_class: int in World.MoveClass.size():
		world.terrain_cost[SLOW * World.MoveClass.size() + move_class] = TIE_COST
	for cell: int in [2 * 7 + 3, 4 * 7 + 3, 3 * 7 + 2, 3 * 7 + 4]:
		world.set_terrain(cell, SLOW)
	return _with_field_units(world, 3 + 3 * 7)


## The field of `key` for the tank class, integrated, and a unit on every passable tile of the map
## following it: MOVE, FIELD, `nav_next` -1, the goal at the key tile 300 below its centre. Tick 9.
@warning_ignore("integer_division")
func _with_field_units(world: World, key: int) -> World:
	assert_int(world.flow.acquire(key, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for cell: int in world.map_cols * world.map_rows:
		if not world.is_passable(cell, TRACKED):
			continue
		var x: int = cell % world.map_cols * 1000 + 500
		var y: int = cell / world.map_cols * 1000 + 500
		var row: int = world.add_unit(1, 0, x, y) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = key % world.map_cols * 1000 + 500
		world.goal_y[row] = key / world.map_cols * 1000 + 800
	FlowCache.run(world, 0)  # The references.
	world.tick = 9
	return world


## One MOVE tank in DIRECT per offset with a checked line, each at its own goal plus the offset
## (goals 3.3 tiles apart on a 64 x 12 grass map); speed 120. With `reach` of 0 or more, the rule
## stall_range_spacings is set to it.
func _arrival_world(offsets: Array[Vector2i], reach: int = -1) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(64, 12), [TRACKED])
	if reach >= 0:
		world.stall_range_spacings = reach
	for index: int in offsets.size():
		var goal: Vector2i = Vector2i(4000 + index * 3300, 6000)
		var at: Vector2i = goal + offsets[index]
		var row: int = world.add_unit(1, 0, at.x, at.y) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = DIRECT
		world.nav_cell[row] = 0
		world.goal_x[row] = goal.x
		world.goal_y[row] = goal.y
	return world


## A 60 x 40 open map with twelve slots, a complete group field keyed on tile (30, 20) and one
## ATTACK unit per offset in FIELD on it, its goal at the centre of the key's tile plus the offset.
## `limit` is attack_rekey_milli.
func _rekey_world(offsets: Array[Vector2i], limit: int) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(60, 40), [TRACKED])
	world.flow_cache_size = 12
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 12)
	world.attack_rekey_milli = limit
	assert_int(world.flow.acquire(20 * 60 + 30, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for offset: Vector2i in offsets:
		var row: int = world.add_unit(1, 0, 25500, 18500) - 1
		world.order[row] = ATTACK
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 30500 + offset.x
		world.goal_y[row] = 20500 + offset.y
	FlowCache.run(world, 0)
	world.tick = 9
	return world


## A 12 x 6 map with a complete field keyed on tile 40 (4, 3) and three FIELD tanks whose
## `nav_next` is a stale -3, with tick `tick` and the line-check period `period`.
func _turn_world(period: int, tick: int) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 6), [TRACKED])
	assert_int(world.flow.acquire(40, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for index: int in 3:
		var row: int = world.add_unit(1, 0, 8500, 1500 + index * 1000) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 4500
		world.goal_y[row] = 3800
		world.nav_next[row] = -3
	FlowCache.run(world, 0)
	world.line_check_period_ticks = period
	world.tick = tick
	return world


## 20 x 12, three slots, slot 0 a complete field keyed on tile 42 (2, 2). Units 1 to 4 are in FIELD
## on it with the orders 4, 5, 7 and -1 and a goal in tile 175 (7000 from the key's centre, so an
## ATTACK unit would re-key); unit 5 has an order of 4 and a goal within one step (it arrives).
func _unknown_order_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12), [TRACKED])
	world.flow_cache_size = 3
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 3)
	assert_int(world.flow.acquire(42, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var orders: Array[int] = [4, 5, 7, -1, 4]
	for index: int in orders.size():
		var row: int = world.add_unit(1, 0, 4500 + index * 1000, 4500) - 1
		world.order[row] = orders[index]
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 15500
		world.goal_y[row] = 8500
	world.goal_x[4] = world.pos_x[4] + 50
	world.goal_y[4] = world.pos_y[4]
	FlowCache.run(world, 0)
	world.tick = 9
	return world


## 20 x 12 with a complete field keyed on tile 42, whose `cell_count` is then set to 100: a tank on
## tile 150 (10, 7), one on tile 99 (19, 4). Both MOVE, FIELD, `nav_next` -1.
func _short_field_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12), [TRACKED])
	assert_int(world.flow.acquire(42, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	world.flow.field(0).cell_count = 100
	for tile: Vector2i in [Vector2i(10, 7), Vector2i(19, 4)]:
		var row: int = world.add_unit(1, 0, tile.x * 1000 + 500, tile.y * 1000 + 500) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 2500
		world.goal_y[row] = 2800
	FlowCache.run(world, 0)
	world.tick = 9
	return world


## 20 x 12, a cache of four slots configured for 20 x 10 tiles, a complete field keyed on tile 105
## (5, 5). Unit 1 is an ATTACK tank in FIELD on it, its goal in tile (0, 10) (cell 200, the first
## past the cache); unit 2 is a MOVE tank in FIELD standing on tile 205 (5, 10), past the cache.
func _short_cache_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12), [TRACKED])
	world.flow_cache_size = 4
	world.flow.configure(20, 10, World.MoveClass.size(), 4)
	assert_int(world.flow.acquire(105, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for tile: Vector2i in [Vector2i(5, 6), Vector2i(5, 10)]:
		var row: int = world.add_unit(1, 0, tile.x * 1000 + 500, tile.y * 1000 + 500) - 1
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 5500
		world.goal_y[row] = 5800
	world.order[0] = ATTACK
	world.goal_x[0] = 500
	world.goal_y[0] = 10500
	world.order[1] = MOVE
	FlowCache.run(world, 0)
	world.tick = 9
	return world


## A 6 x 4 tile grid whose World size is `map_w` x `map_h` (not positive, or below its tiles),
## with 80 MOVE tanks at x in {0, 3} and y in {0, 3}, each stepping (ix, iy) with ix in -2, -1, 0,
## 3, 600 and iy in -2, 0, 3, 600.
func _narrow_world(map_w: int, map_h: int) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(6, 4), [TRACKED])
	world.map_w = map_w
	world.map_h = map_h
	for x: int in [0, 3]:
		for y: int in [0, 3]:
			for step_x: int in [-2, -1, 0, 3, 600]:
				for step_y: int in [-2, 0, 3, 600]:
					var row: int = world.add_unit(1, 0, x, y) - 1
					world.order[row] = MOVE
					world.goal_x[row] = 5000
					world.goal_y[row] = 3000
					world.intent_x[row] = step_x
					world.intent_y[row] = step_y
	return world


## A world with no map (a size of 0) and units at the top of the int32 range, in DIRECT with a
## checked line, a stall range of 1.8 million spacings (a span of 2.16e9) and 5 stall ticks. Unit 0
## is 2.12e9 from its goal with a best distance of the int32 maximum (it stalls on a root that
## fits). Unit 1 steps by 2^32 - 2 from the corner towards a goal 2^31 - 1 away on both axes. Unit 2
## has a speed of 2^31 - 1 and a goal at the other corner (not within one step). Unit 3's goal is
## INT32_MIN away on x. Unit 4 stands on its goal. Unit 5 is a FIELD unit with no next tile.
func _extreme_world() -> World:
	var world: World = World.new()
	for speed: int in [1, INT32_MAX]:
		world.type_ids.append(StringName("type%d" % speed))
		world.type_speed.append(speed)
		world.type_radius.append(400)
		world.type_selection_radius.append(500)
		world.type_spacing.append(1200)
	world.stall_range_spacings = 1800000
	world.stall_ticks = 5
	var units: Array[Array] = [
		[0, 1500000000, 1500000000, 0, 0],
		[0, 0, 0, INT32_MAX, INT32_MAX],
		[1, INT32_MAX, INT32_MAX, 0, 0],
		[0, 0, 0, INT32_MIN, 0],
		[0, INT32_MAX, INT32_MAX, INT32_MAX, INT32_MAX],
	]
	for unit: Array in units:
		var row: int = world.add_unit(1, unit[0], unit[1], unit[2]) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = DIRECT
		world.nav_cell[row] = 0
		world.goal_x[row] = unit[3]
		world.goal_y[row] = unit[4]
	world.prepare()
	world.best_dist[0] = INT32_MAX
	world.intent_x[1] = INT32_MAX
	world.push_x[1] = INT32_MAX
	world.intent_y[1] = INT32_MAX
	world.push_y[1] = INT32_MAX
	world.intent_x[2] = 1
	# Unit 5 follows a field on a world with no map: it has no tile, so it has no stall count.
	var field_unit: int = world.add_unit(1, 0, 1000, 1000) - 1
	world.order[field_unit] = MOVE
	world.nav_mode[field_unit] = FIELD
	world.field[field_unit] = 0
	world.nav_next[field_unit] = NO_NEXT
	world.goal_x[field_unit] = 900000
	world.goal_y[field_unit] = 1000
	return world
