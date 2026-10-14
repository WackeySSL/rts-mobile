extends GdUnitTestSuite
## Movement.integrate on its own (P37a2; ADR 0008 section 4, "Integrate and slide"): the intents and
## pushes are written by hand, then one `integrate` call. The new point is intent plus push, clamped
## to the map; on a tile the unit's class cannot enter, the x move alone is tried, then the y move
## alone, else the unit stays. Maps are built in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
const TRACKED: int = World.MoveClass.TRACKED
## The index of rock in the terrain of GridWorld (its GROUND string: grass, scrub, rock).
const ROCK: int = 2
const HOLD: int = World.NavMode.HOLD
## Every map here is 12 x 8 tiles, so a mix-up of columns and rows shows.
const COLS: int = 12
const ROWS: int = 8


## A unit at (4900, 4900) on a 12 x 8 map steps (+100, +100) into tile (5, 5). With only that tile
## blocked the x move alone is taken (5000, 4900) though the y move alone is open too; with (5, 4)
## blocked as well the y move alone; with both blocked it stays; with the destination open it
## takes the whole step. Each case is a list of the rock tiles and the position that follows.
## Only the destination is tested (ADR 0008 section 4), so with both orthogonal neighbours of an
## open destination blocked the unit still takes the diagonal step between them: the flow field and
## `line_clear` call that corner cutting and forbid it. The last case pins the approximation (ADR
## 0008, Consequences), so a later change to the slide shows.
func test_the_slide_tries_the_x_move_then_the_y_move_then_stays() -> void:
	var cases: Array[Array] = [
		[[], Vector2i(5000, 5000)],
		[[[5, 5]], Vector2i(5000, 4900)],
		[[[5, 5], [5, 4]], Vector2i(4900, 5000)],
		[[[5, 5], [4, 5]], Vector2i(5000, 4900)],
		[[[5, 5], [5, 4], [4, 5]], Vector2i(4900, 4900)],
		# Rock beside the path, not on it, changes nothing.
		[[[6, 6], [3, 3]], Vector2i(5000, 5000)],
		# Rock on both sides of the corner and an open destination: the unit squeezes through.
		[[[5, 4], [4, 5]], Vector2i(5000, 5000)],
	]
	for case: Array in cases:
		var rock: Array[Vector2i] = GridWorld.tiles(case[0])
		var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS, rock))
		world.add_unit(1, 0, 4900, 4900)
		world.intent_x[0] = 100
		world.intent_y[0] = 100
		Movement.integrate(world)
		(
			assert_that(Vector2i(world.pos_x[0], world.pos_y[0]))
			. override_failure_message(str(case))
			. is_equal(case[1])
		)


## The push counts like the intent: it moves an idle unit, adds to the intent of a moving one, and
## the sum slides at rock. A unit with neither stays where it is.
func test_the_push_is_added_to_the_intent_and_slides_at_rock_too() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS, [Vector2i(5, 3)]))
	GridWorld.add_block(world, 4, 1, 2000, 1500, 2000, 0)
	# Row 0 is idle and pushed; row 1 steps 120 and is pushed back 30; row 2 has neither.
	world.push_x[0] = 40
	world.push_y[0] = -25
	world.intent_x[1] = 120
	world.push_x[1] = -30
	world.push_y[1] = 17
	# Row 3 stands at (4950, 3500) and is pushed (60, 10) towards rock tile (5, 3): only the y part
	# of the push is taken.
	world.pos_x[3] = 4950
	world.pos_y[3] = 3500
	world.push_x[3] = 60
	world.push_y[3] = 10
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2040, 1475])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([2090, 3517])
	assert_array([world.pos_x[2], world.pos_y[2]]).is_equal([2000, 5500])
	assert_array([world.pos_x[3], world.pos_y[3]]).is_equal([4950, 3510])


## A unit in HOLD or CHASE, the modes combat sets, is moved by its push like any other ("all units
## separate, including enemies and idle units", ADR 0008 section 4): HOLD has no intent, CHASE adds
## its own step. Neither is steering at its goal (here the point it stands on), so neither arrives
## and each keeps its order and its mode.
func test_a_hold_or_chase_unit_is_still_moved_by_its_push() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	GridWorld.add_block(world, 3, 1, 2000, 1500, 2000, 0)
	var orders: Array[int] = [World.Order.MOVE, World.Order.ATTACK_MOVE, World.Order.ATTACK]
	var modes: Array[int] = [HOLD, World.NavMode.CHASE, HOLD]
	for row: int in 3:
		world.order[row] = orders[row]
		world.nav_mode[row] = modes[row]
		world.push_x[row] = 30 - 10 * row
		world.push_y[row] = -20 + 15 * row
	world.intent_x[1] = 120
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2030, 1480])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([2140, 3495])
	assert_array([world.pos_x[2], world.pos_y[2]]).is_equal([2010, 5510])
	assert_array(world.order.slice(0, 3)).is_equal(orders)
	assert_array(world.nav_mode.slice(0, 3)).is_equal(modes)


## A unit whose goal is within one step at the start of the tick arrives on that tick, whatever
## else moves it: a push (row 0, goal 100 east, pushed 30 further) or a slide that refuses the step
## (row 1, goal on rock tile (5, 4)) leaves it off its goal with the order gone, the mode NONE and
## the line unchecked. P39b's separation relies on this rule. Row 2, a step away, keeps its order.
func test_a_unit_arrives_on_its_snap_tick_though_a_push_or_slide_keeps_it_off() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS, [Vector2i(5, 4)]))
	world.add_unit(1, 0, 2000, 2000)
	world.add_unit(1, 0, 4900, 4900)
	world.add_unit(1, 0, 2000, 6000)
	var goals: Array[Vector2i] = [Vector2i(2100, 2000), Vector2i(5000, 4900), Vector2i(2200, 6000)]
	for row: int in 3:
		world.order[row] = World.Order.MOVE
		world.nav_mode[row] = World.NavMode.DIRECT
		world.nav_cell[row] = 17
		world.goal_x[row] = goals[row].x
		world.goal_y[row] = goals[row].y
	Movement.run(world)
	world.push_x[0] = 30
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2130, 2000])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([4900, 4900])
	assert_array([world.pos_x[2], world.pos_y[2]]).is_equal([2120, 6000])
	for row: int in 2:
		assert_array([world.order[row], world.nav_mode[row], world.nav_cell[row]]).is_equal(
			[World.Order.IDLE, World.NavMode.NONE, -1]
		)
	assert_array([world.order[2], world.nav_mode[2], world.nav_cell[2]]).is_equal(
		[World.Order.MOVE, World.NavMode.DIRECT, 17]
	)


## The new point is clamped to 0..map-1 on each axis (11999 and 7999 on this 12 x 8 map), also when
## the push adds to the intent, and a unit at the far edge is in the last tile (no index past the
## grid).
func test_the_new_point_is_clamped_to_the_map() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	GridWorld.add_block(world, 4, 1, 100, 100, 100, 0)
	var starts: Array[Vector2i] = [
		Vector2i(50, 50), Vector2i(11990, 7990), Vector2i(11950, 40), Vector2i(30, 7970)
	]
	# Half of the step comes from the intent and half from the push.
	var halves: Array[Vector2i] = [
		Vector2i(-60, -60), Vector2i(60, 60), Vector2i(60, -60), Vector2i(-60, 60)
	]
	for row: int in 4:
		world.pos_x[row] = starts[row].x
		world.pos_y[row] = starts[row].y
		world.intent_x[row] = halves[row].x
		world.intent_y[row] = halves[row].y
		world.push_x[row] = halves[row].x
		world.push_y[row] = halves[row].y
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([0, 0])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([11999, 7999])
	assert_array([world.pos_x[2], world.pos_y[2]]).is_equal([11999, 0])
	assert_array([world.pos_x[3], world.pos_y[3]]).is_equal([0, 7999])


## Every class is stopped by its own blocked ground only: scrub ('^') stops wheeled and tracked
## units and not foot units, 'w' stops tracked units only, 't' wheeled units only, rock all of
## them, and costlier ground ('2') nobody. Three units, of the types tracked, foot and wheeled (so
## a type's index is not its class), step 120 east from x 4900 towards a column of each ground at
## tile 5; a refused step leaves the unit at 4900.
func test_each_class_is_stopped_by_its_own_blocked_ground_only() -> void:
	var cases: Array[Array] = [
		# ground, then the x that the tracked, foot and wheeled unit end at (type 0, 1 and 2)
		["^", [4900, 5020, 4900]],
		["#", [4900, 4900, 4900]],
		["w", [4900, 5020, 5020]],
		["t", [5020, 5020, 4900]],
		["2", [5020, 5020, 5020]],
		[".", [5020, 5020, 5020]],
	]
	for case: Array in cases:
		var ground: String = case[0]
		var rows: PackedStringArray = GridWorld.grass(COLS, ROWS)
		for line: int in ROWS:
			rows[line] = rows[line].left(5) + ground + rows[line].substr(6)
		var world: World = GridWorld.from_rows(rows, [TRACKED, FOOT, WHEELED])
		for kind: int in 3:
			world.add_unit(1, kind, 4900, 1500 + kind * 2000)
			world.intent_x[kind] = 120
		Movement.integrate(world)
		var ended: Array[int] = []
		for kind: int in 3:
			ended.append(world.pos_x[kind])
		assert_array(ended).override_failure_message(ground).is_equal(case[1])


## Only the destination is tested. A unit that started on a blocked tile (the map changed under it)
## moves to a passable tile, and a step that ends on another blocked tile is refused as for any
## unit, so it stays put.
func test_a_unit_on_a_blocked_tile_may_move_to_a_passable_one() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	world.add_unit(1, 0, 4950, 4500)
	world.add_unit(1, 0, 4950, 6500)
	world.set_terrain(4 * COLS + 4, ROCK)  # Tile (4, 4), under unit 0.
	world.set_terrain(6 * COLS + 4, ROCK)  # Tile (4, 6), under unit 1.
	world.set_terrain(6 * COLS + 5, ROCK)  # Tile (5, 6), where unit 1 would step.
	assert_bool(world.is_passable(world.cell_of(4950, 4500), TRACKED)).is_false()
	assert_bool(world.is_passable(world.cell_of(4950, 6500), TRACKED)).is_false()
	# Unit 0 steps diagonally: the whole step is taken, not just its x part.
	world.intent_x[0] = 100
	world.intent_y[0] = 100
	world.intent_x[1] = 100
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([5050, 4600])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([4950, 6500])


## A world with no map (a hand-built one with a size of 0) has nothing to slide on and no upper
## bound: the unit takes its step, far past any map. The lower bound is 0 on every world, so a step
## below 0 ends at 0 on that axis only (the other axis keeps its step).
func test_a_world_with_no_map_has_no_upper_bound_and_is_clamped_at_zero() -> void:
	var world: World = _world_with_no_map()
	world.add_unit(1, 0, 90000, 70000)
	world.add_unit(1, 0, 50, 30)
	world.prepare()
	assert_int(world.map_cols).is_equal(0)
	world.intent_x[0] = 120
	world.intent_y[0] = -99
	world.intent_x[1] = -120
	world.intent_y[1] = 99
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([90120, 69901])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([0, 129])


## The upper bound of a world with no map is the largest int32 (what a position column can hold),
## not some smaller number: a unit far out takes a whole step, and a step past the bound ends on it
## (2147483647), on each axis alone.
func test_a_world_with_no_map_is_bounded_by_the_largest_int32() -> void:
	var world: World = _world_with_no_map()
	world.add_unit(1, 0, 2000000000, 1500000000)
	world.add_unit(1, 0, 2147483640, 2147483600)
	world.prepare()
	world.intent_x[0] = 120
	world.intent_y[0] = 77
	world.intent_x[1] = 120
	world.intent_y[1] = 120
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2000000120, 1500000077])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([2147483647, 2147483647])


## A hand-built world whose size is not whole tiles (5500 x 2500 milli-tiles: 6 x 3 tiles, the last
## column and row half tiles) keeps every position in 0..map-1, the range the World contract gives,
## not in the last whole tile (5999 and 2999). The clamp takes the smaller of the map's size and
## its tiles' extent, on each axis alone: a step that would end at 5550 and 2550 ends at 5499 and
## 2499, and a step inside the map is taken whole.
func test_a_map_that_is_not_whole_tiles_clamps_to_its_size_not_its_tiles() -> void:
	var world: World = _world_with_no_map()
	world.map_w = 5500
	world.map_h = 2500
	var starts: Array[Vector2i] = [
		Vector2i(5490, 2490), Vector2i(5490, 1000), Vector2i(1000, 2490), Vector2i(5400, 2400)
	]
	var steps: Array[Vector2i] = [
		Vector2i(60, 60), Vector2i(60, 20), Vector2i(20, 60), Vector2i(60, 60)
	]
	for row: int in 4:
		world.add_unit(1, 0, starts[row].x, starts[row].y)
	world.prepare()
	assert_array([world.map_cols, world.map_rows]).is_equal([6, 3])
	for row: int in 4:
		world.intent_x[row] = steps[row].x
		world.intent_y[row] = steps[row].y
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([5499, 2499])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([5499, 1020])
	assert_array([world.pos_x[2], world.pos_y[2]]).is_equal([1020, 2499])
	assert_array([world.pos_x[3], world.pos_y[3]]).is_equal([5460, 2460])


## A World with the one tank type table and no map yet: the test sets a size and adds the units
## before `prepare()` (a size of 0 on both axes leaves it with no map).
func _world_with_no_map() -> World:
	var world: World = World.new()
	world.type_ids.append(&"tank")
	world.type_speed.append(120)
	world.type_radius.append(400)
	world.type_selection_radius.append(500)
	world.type_spacing.append(1200)
	return world
