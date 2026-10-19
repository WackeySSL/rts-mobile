extends GdUnitTestSuite
## The INTEGRATE lockstep for FIELD units that stand outside the map (ADR 0013 section 4, plan
## P37n3), apart from test_integrate_lockstep_cases.gd, which is at gdlint's limit of 20 public
## methods. A FIELD unit looks its next tile up from the tile it stands on, clamped to the map:
## `clampi(y, 0, max_y) / tile * cols + clampi(x, 0, max_x) / tile`, where `max_x` is the smaller
## of the World's `map_w` and the grid's width, less 1 (`max_y` likewise). A position past either
## end of an axis is a position a push or a changed map leaves a unit at. Each case is built twice
## (the GDScript twin and the C++ kernel, through tests/sim/support/lockstep_rig.gd) and compared
## after one Movement.integrate: the state hash and the full state of StateDiff.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const FIELD: int = World.NavMode.FIELD
const BIG: int = 100000


## A 6 x 4 grid with a complete field keyed on tile 0 and five FIELD tanks that have no next tile
## yet, so that each looks one up on this tick: unit 0 stands past the right end of the map in x,
## unit 1 below 0 in x, unit 2 past the bottom end in y, unit 3 below 0 in y and unit 4 inside the
## map. The lookup is from the tile the position is clamped to, (3, 1), (0, 1), (1, 2), (1, 0) and
## (2, 1) in the first World, and the field names tiles 2, 0, 6, 0 and 1 from them. A lookup from
## the unclamped position names others (tile 5 for unit 1, because a division that truncates
## toward 0 puts x = -1500 in column -1), and so does a clamp that lacks one bound, which changes
## the unit that stands past that bound. The first World is 3500 x 2500 (the map ends inside the
## grid, so a bound that ignored `map_w` or `map_h` finds other tiles). In the second, 9000 x 7000,
## the grid ends first and units 0 and 2 are clamped to its last column and last row, (5, 1) and
## (1, 3), where the field names tiles 4 and 12.
func test_a_field_unit_off_the_map_looks_up_the_tile_it_is_clamped_to() -> void:
	var cases: Dictionary[Vector2i, Array] = {
		Vector2i(3500, 2500): [2, 0, 6, 0, 1], Vector2i(9000, 7000): [4, 0, 12, 0, 1]
	}
	for size: Vector2i in cases:
		var label: String = "map %d x %d" % [size.x, size.y]
		var problems: Array[String] = []
		var pair: Array[World] = LockstepRig.pair(_off_map_world.bind(size), false, problems)
		assert_array(problems).is_empty()
		for world: World in pair:
			Movement.integrate(world)
		var found: String = LockstepRig.difference(pair[0], pair[1])
		assert_str(found).override_failure_message(label).is_empty()
		for world: World in pair:
			var next: Array = Array(world.nav_next)
			assert_array(next).override_failure_message(label).is_equal(cases[size])


## The World of the case above, `size` being the World's `map_w` and `map_h`: a 6 x 4 all-grass
## grid with a field keyed on tile 0 and MOVE tanks, FIELD, on slot 0, with the goal in tile 0,
## at (size.x + 2000, 1500), (-1500, 1500), (1500, size.y + 1000), (1500, -1500) and (2500, 1500).
func _off_map_world(size: Vector2i) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(6, 4), [TRACKED])
	world.map_w = size.x
	world.map_h = size.y
	assert_int(world.flow.acquire(0, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var spots: Array[Vector2i] = [
		Vector2i(size.x + 2000, 1500),
		Vector2i(-1500, 1500),
		Vector2i(1500, size.y + 1000),
		Vector2i(1500, -1500),
		Vector2i(2500, 1500),
	]
	for spot: Vector2i in spots:
		var row: int = world.add_unit(1, 0, spot.x, spot.y) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 500
		world.goal_y[row] = 500
	FlowCache.run(world, 0)  # The references.
	world.tick = 9
	return world
