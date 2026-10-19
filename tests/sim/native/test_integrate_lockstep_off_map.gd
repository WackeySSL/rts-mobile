extends GdUnitTestSuite
## The INTEGRATE lockstep for units that stand or aim outside the map (ADR 0013 section 4, plan
## P37n3), apart from test_integrate_lockstep_cases.gd, which is at gdlint's limit of 20 public
## methods. A FIELD unit looks its next tile up from the tile it stands on, clamped to the map:
## `clampi(y, 0, max_y) / tile * cols + clampi(x, 0, max_x) / tile`, where `max_x` is the smaller
## of the World's `map_w` and the grid's width, less 1 (`max_y` likewise). A unit whose step lands
## on a blocked tile slides along the tile it stands in, clamped the same way. A goal off the map
## gives the field it asks for the tile it is clamped to (`World.cell_of`). A position past either
## end of an axis is a position a push or a changed map leaves a unit at. Each case is built twice
## (the GDScript twin and the C++ kernel, through tests/sim/support/lockstep_rig.gd) and compared
## after one Movement.integrate: the state hash and the full state of StateDiff.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
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


## A 6 x 4 grass grid of 3500 x 2500 with rock at (3, 1) (3, 2) (0, 1) (0, 2) (2, 2) (2, 0) and four
## MOVE tanks (mode NONE, so no field) whose one step lands on rock, so that each slides along the
## tile it stands in. The step is clamped to the map first (unit 0 to (3499, 2499)). Unit 0 stands
## past the right end of the map in x, unit 1 below 0 in x, unit 2 past the bottom end in y and
## unit 3 below 0 in y. The slide looks at the tile it stands in, clamped to the map as well:
## (3, 1), (0, 1), (1, 2) and (1, 0). From those, unit 0 and unit 1 find rock on both sides and
## stay, unit 2 and unit 3 keep their column and move to the clamped row. A tile taken from the
## unclamped position (column 5 for unit 0, column -1 for unit 1, row 3 for unit 2, row -1 for
## unit 3) reads other tiles, and so does a clamp that lacks one bound: each of those moves at
## least one unit.
func test_a_unit_off_the_map_that_steps_onto_rock_slides_along_the_tile_it_is_clamped_to() -> void:
	var problems: Array[String] = []
	var pair: Array[World] = LockstepRig.pair(_slide_world, false, problems)
	assert_array(problems).is_empty()
	for world: World in pair:
		Movement.integrate(world)
	assert_str(LockstepRig.difference(pair[0], pair[1])).is_empty()
	var expected: Array[Vector2i] = [
		Vector2i(5500, 1500), Vector2i(-1500, 1500), Vector2i(1500, 2499), Vector2i(1500, 0)
	]
	for world: World in pair:
		var found: Array[Vector2i] = []
		for row: int in 4:
			found.append(Vector2i(world.pos_x[row], world.pos_y[row]))
		assert_array(found).is_equal(expected)


## The World of the case above: units at (5500, 1500), (-1500, 1500), (1500, 3500) and (1500, -1500)
## with steps (0, 1000), (0, 1000), (1000, 0) and (1000, 0) and a goal at (3000, 3000).
func _slide_world() -> World:
	var rock: Array[Vector2i] = GridWorld.tiles([[3, 1], [3, 2], [0, 1], [0, 2], [2, 2], [2, 0]])
	var world: World = GridWorld.from_rows(GridWorld.grass(6, 4, rock), [TRACKED])
	world.map_w = 3500
	world.map_h = 2500
	var units: Array[Array] = [
		[5500, 1500, 0, 1000], [-1500, 1500, 0, 1000], [1500, 3500, 1000, 0], [1500, -1500, 1000, 0]
	]
	for unit: Array in units:
		var row: int = world.add_unit(1, 0, unit[0], unit[1]) - 1
		world.order[row] = MOVE
		world.goal_x[row] = 3000
		world.goal_y[row] = 3000
		world.intent_x[row] = unit[2]
		world.intent_y[row] = unit[3]
	world.tick = 9
	return world


## Four ATTACK tanks in FIELD on a field keyed on tile 23, the last tile of a 6 x 4 map, whose goals
## are off the map: above it (1500, -1500), below it (1500, 5500), left of it (-1500, 500) and right
## of it (9500, 500). Each goal is more than the re-key distance (4000) from the centre of the key's
## tile, so each unit re-keys, to the tile the goal is clamped to: 1, 19, 0 and 5, in the free slots
## 1, 2, 3 and 4 of a cache of five. A goal at -1500 divides to -1 (a division truncates toward 0),
## so a tile taken without the low bound is negative (-5 above the map, -1 to the left of it) and
## one taken without the high bound is outside the grid or another tile (31 below the map, 9 to
## the right of it); a goal that names such a tile is refused or gets another key, and the units'
## slots and the keys differ.
func test_an_attack_goal_off_the_map_asks_for_the_field_of_the_tile_it_is_clamped_to() -> void:
	var problems: Array[String] = []
	var pair: Array[World] = LockstepRig.pair(_off_map_goals_world, false, problems)
	assert_array(problems).is_empty()
	for world: World in pair:
		Movement.integrate(world)
	assert_str(LockstepRig.difference(pair[0], pair[1])).is_empty()
	for world: World in pair:
		assert_array(Array(world.field.slice(0, 4))).is_equal([1, 2, 3, 4])
		assert_array(Array(world.flow.key_goal)).is_equal([23, 1, 19, 0, 5])


## The World of the case above: a 6 x 4 grass grid, a cache of five slots and a complete field in
## slot 0 keyed on tile 23, and the four tanks at (2500, 2500).
func _off_map_goals_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(6, 4), [TRACKED])
	world.flow_cache_size = 5
	world.flow.configure(6, 4, World.MoveClass.size(), 5)
	assert_int(world.flow.acquire(23, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var goals: Array[Vector2i] = [
		Vector2i(1500, -1500), Vector2i(1500, 5500), Vector2i(-1500, 500), Vector2i(9500, 500)
	]
	for goal: Vector2i in goals:
		var row: int = world.add_unit(1, 0, 2500, 2500) - 1
		world.order[row] = ATTACK
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = goal.x
		world.goal_y[row] = goal.y
	FlowCache.run(world, 0)  # The references.
	world.tick = 9
	return world
