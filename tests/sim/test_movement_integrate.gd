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
## Every map here is 12 x 8 tiles, so a mix-up of columns and rows shows.
const COLS: int = 12
const ROWS: int = 8


## A unit at (4900, 4900) on a 12 x 8 map steps (+100, +100) into tile (5, 5). With only that tile
## blocked the x move alone is taken (5000, 4900) though the y move alone is open too; with (5, 4)
## blocked as well the y move alone; with both blocked it stays; with the destination open it
## takes the whole step. Each case is a list of the rock tiles and the position that follows.
func test_the_slide_tries_the_x_move_then_the_y_move_then_stays() -> void:
	var cases: Array[Array] = [
		[[], Vector2i(5000, 5000)],
		[[[5, 5]], Vector2i(5000, 4900)],
		[[[5, 5], [5, 4]], Vector2i(4900, 5000)],
		[[[5, 5], [4, 5]], Vector2i(5000, 4900)],
		[[[5, 5], [5, 4], [4, 5]], Vector2i(4900, 4900)],
		# Rock beside the path, not on it, changes nothing.
		[[[6, 6], [3, 3]], Vector2i(5000, 5000)],
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


## A world with no map (a hand-built one with a size of 0) has nothing to clamp to or to slide on:
## the unit takes its step, far past any map.
func test_a_world_with_no_map_moves_by_the_step_unclamped() -> void:
	var world: World = World.new()
	world.type_ids.append(&"tank")
	world.type_speed.append(120)
	world.type_radius.append(400)
	world.type_selection_radius.append(500)
	world.type_spacing.append(1200)
	world.add_unit(1, 0, 90000, 70000)
	world.prepare()
	assert_int(world.map_cols).is_equal(0)
	world.intent_x[0] = 120
	world.intent_y[0] = -99
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([90120, 69901])
