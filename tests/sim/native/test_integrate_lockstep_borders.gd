extends GdUnitTestSuite
## INTEGRATE for units that stand exactly on tile borders, twin against kernel (ADR 0033, P195d2):
## the next-tile look-up and the slide read the tile on the map centre's side
## (FixedMath.centre_side) in both. On the pillar map of test_integrate_lockstep_cases (9 x 9, the
## middle at 4500) a unit at (7000, 7000), a border past the middle, is in tile (6, 6) and names the
## tile that a unit at its centre (6500, 6500) names, one at (2000, 2000), before the middle, in
## tile (2, 2).

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const FIELD: int = World.NavMode.FIELD
const NO_NEXT: int = -2
const BIG: int = 100000


func test_units_on_tile_borders_look_up_the_tile_on_the_centre_side() -> void:
	var pair: Array[World] = _pair(_border_world)
	_integrate_all(pair)
	_assert_same(pair)
	for world: World in pair:
		var border: int = _row_at(world, Vector2i(7000, 7000))
		var centre: int = _row_at(world, Vector2i(6500, 6500))
		assert_int(world.nav_next[border]).is_not_equal(NO_NEXT)
		assert_int(world.nav_next[border]).is_equal(world.nav_next[centre])
		var early: int = _row_at(world, Vector2i(2000, 2000))
		var inside: int = _row_at(world, Vector2i(2500, 2500))
		assert_int(world.nav_next[early]).is_equal(world.nav_next[inside])


## A step that ends exactly on a border reads the destination tile on the centre's side. On a 12 x 8
## map (the middle at (6000, 4000)) the step from (6900, 6900) to (7000, 7000) ends in tile (6, 6),
## the one before both borders, so rock at (7, 7), which the floor would call the destination, does
## not stop it; the step from (2900, 2900) to (3000, 3000) ends before the middle, in tile (3, 3),
## so rock there is the destination and the unit slides by the x move alone, to (3000, 2900).
func test_a_step_onto_a_border_reads_the_centre_side_tile_in_both_versions() -> void:
	var cases: Array[Array] = [
		[[7, 7], Vector2i(6900, 6900), Vector2i(7000, 7000)],
		[[3, 3], Vector2i(2900, 2900), Vector2i(3000, 2900)],
	]
	for case: Array in cases:
		var pair: Array[World] = _pair(_step_world.bind(case[0], case[1]))
		_integrate_all(pair)
		_assert_same(pair)
		for world: World in pair:
			var at: Vector2i = Vector2i(world.pos_x[0], world.pos_y[0])
			assert_that(at).override_failure_message(str(case)).is_equal(case[2])


## The pillar map with the field of its goal and a unit in FIELD on every border point (x and y both
## multiples of 1000, 1 to 8) whose centre side tile is open, and one at the centre of the tiles
## (6, 6) and (2, 2). Tick 9.
func _border_world() -> World:
	var rock: Array[Vector2i] = [Vector2i(3, 3), Vector2i(5, 3), Vector2i(3, 5), Vector2i(5, 5)]
	var world: World = GridWorld.from_rows(GridWorld.grass(9, 9, rock), [TRACKED])
	assert_int(world.flow.acquire(4 + 4 * 9, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var points: Array[Vector2i] = [Vector2i(6500, 6500), Vector2i(2500, 2500)]
	for line: int in range(1, 9):
		for column: int in range(1, 9):
			points.append(Vector2i(column * 1000, line * 1000))
	for point: Vector2i in points:
		if not world.is_passable(world.cell_of(point.x, point.y), TRACKED):
			continue
		var row: int = world.add_unit(1, 0, point.x, point.y) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 4500
		world.goal_y[row] = 4800
	FlowCache.run(world, 0)  # The references.
	world.tick = 9
	return world


## A 12 x 8 map with the `rock` tile ([x, y]) and one unit at `start` whose intent is (+100, +100).
func _step_world(rock: Array, start: Vector2i) -> World:
	var tiles: Array[Vector2i] = GridWorld.tiles([rock])
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 8, tiles), [TRACKED])
	world.add_unit(1, 0, start.x, start.y)
	world.intent_x[0] = 100
	world.intent_y[0] = 100
	return world


## The row of the unit standing at `point`.
func _row_at(world: World, point: Vector2i) -> int:
	for row: int in world.unit_count():
		if world.pos_x[row] == point.x and world.pos_y[row] == point.y:
			return row
	return -1


func _assert_same(pair: Array[World]) -> void:
	assert_str(LockstepRig.difference(pair[0], pair[1])).is_empty()


func _pair(build: Callable) -> Array[World]:
	var problems: Array[String] = []
	var found: Array[World] = LockstepRig.pair(build, false, problems)
	assert_array(problems).is_empty()
	return found


func _integrate_all(pair: Array[World]) -> void:
	for world: World in pair:
		Movement.integrate(world)
