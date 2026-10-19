extends GdUnitTestSuite
## The INTEGRATE lockstep for a flow cache whose grid is not the map's (ADR 0013 section 4, plan
## P37n3), apart from test_integrate_lockstep_cases.gd, which is at gdlint's limit of 20 public
## methods (its case for a cache of fewer rows than the map is there). `FlowCache.configure` takes
## the grid's columns and rows from its caller; Movement works from the World's `map_cols` and
## `map_rows` (`World.cell_of`, `World.is_passable`, the key's tile in `_rekey`) and `acquire`
## from the cache's. The two are equal in a match, so the kernel has to take each number from the
## place the twin does: a later rule (a building that blocks a tile) edits exactly these lines. Each
## case is built twice (the GDScript twin and the C++ kernel, through
## tests/sim/support/lockstep_rig.gd) and compared after one Movement.integrate: the state hash and
## the full state of StateDiff.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const FIELD: int = World.NavMode.FIELD
const ROCK: int = 2  # GridWorld's terrain number for rock.
const BIG: int = 100000


## A 20 x 12 map and a cache configured for 13 rows, with a field keyed on tile 240, the first tile
## of the row past the map. Two foot (and then wheeled) units stand in the last row of the map, at
## (0, 11) and (1, 11), and one in the middle at (5, 5), all MOVE with the goal in the last row at
## (500, 11800). The field names tile 240 for the first two, a tile that is not the map's:
## `World.is_passable` is false for `cell >= map_cols * map_rows`, so the key counts as no next tile
## and each unit takes the field of its goal's tile (-1, pending). A bound of `>`, or a cell count
## taken from the cache (260), finds a tile of another class's table (cost above 0) and names 240.
## The unit in the middle has a next tile (124) either way. The tracked class is left out: its
## oversized field reaches past the cost table, nothing is integrated and no unit differs.
func test_a_key_past_the_map_in_a_taller_cache_is_blocked_for_the_unit() -> void:
	for move_class: int in [FOOT, WHEELED]:
		var label: String = "move class %d" % move_class
		var problems: Array[String] = []
		var pair: Array[World] = LockstepRig.pair(
			_tall_cache_world.bind(move_class), false, problems
		)
		assert_array(problems).is_empty()
		for world: World in pair:
			Movement.integrate(world)
		var found: String = LockstepRig.difference(pair[0], pair[1])
		assert_str(found).override_failure_message(label).is_empty()
		for world: World in pair:
			var next: Array = Array(world.nav_next)
			assert_array(next).override_failure_message(label).is_equal([-1, -1, 124])


## The World of the case above, for units of class `move_class`.
func _tall_cache_world(move_class: int) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12), [move_class])
	world.flow_cache_size = 3
	world.flow.configure(20, 13, World.MoveClass.size(), 3)
	assert_int(world.flow.acquire(240, move_class, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	for tile: Vector2i in [Vector2i(0, 11), Vector2i(1, 11), Vector2i(5, 5)]:
		var row: int = world.add_unit(1, 0, tile.x * 1000 + 500, tile.y * 1000 + 500) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = 500
		world.goal_y[row] = 11800
	FlowCache.run(world, 0)  # The references.
	world.tick = 9
	return world


## A 20 x 12 map and a cache configured for 22 columns, with a field keyed on tile 70: tile (10, 3)
## by the map's columns, (4, 3) by the cache's. Five foot units in FIELD on it: three MOVE units
## and two ATTACK units. Unit 1, at (7500, 6500), has its goal (10600, 3600) 141 from the centre of
## the key's tile by the map's columns, within the re-key distance, so it keeps its field. By the
## cache's columns the goal is 6100 from the centre, and the unit would look for the field of its
## goal's tile (tile 70, found in slot 0, which moves the slot's last use to the tick). Unit 4, at
## (12500, 9500), has its goal in tile (0, 11), far from the key: it re-keys to the field of tile
## 220 (map columns) in the free slot 1, where the cache's columns name tile 242. The units look
## their next tile up from a tile counted by the map's columns, and `best_neighbour` reads it in the
## field's grid of 22 columns: the twin names 82, 104, 172 and 63, and a lookup counted by the
## cache's columns names others.
func test_a_cache_with_more_columns_than_the_map_still_keys_by_the_maps_columns() -> void:
	var problems: Array[String] = []
	var pair: Array[World] = LockstepRig.pair(_wide_cache_world, false, problems)
	assert_array(problems).is_empty()
	for world: World in pair:
		Movement.integrate(world)
	assert_str(LockstepRig.difference(pair[0], pair[1])).is_empty()
	for world: World in pair:
		assert_array(Array(world.nav_next)).is_equal([82, 104, 172, 63, -1])
		assert_array(Array(world.field)).is_equal([0, 0, 0, 0, 1])
		assert_array(Array(world.flow.key_goal)).is_equal([70, 220, 0, 0])
		assert_int(world.flow.last_used[0]).is_equal(0)


## The World of the case above: units 0 to 4 at (5500, 5500), (7500, 6500), (15500, 9500),
## (2500, 2500) and (12500, 9500), with the goals (500, 500), (10600, 3600), (500, 11500),
## (19500, 11500) and (500, 11500).
func _wide_cache_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12), [FOOT])
	world.flow_cache_size = 4
	world.flow.configure(22, 12, World.MoveClass.size(), 4)
	assert_int(world.flow.acquire(70, FOOT, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	# [x, y, order, goal_x, goal_y]
	var units: Array[Array] = [
		[5500, 5500, MOVE, 500, 500],
		[7500, 6500, ATTACK, 10600, 3600],
		[15500, 9500, MOVE, 500, 11500],
		[2500, 2500, MOVE, 19500, 11500],
		[12500, 9500, ATTACK, 500, 11500],
	]
	for unit: Array in units:
		var row: int = world.add_unit(1, 0, unit[0], unit[1]) - 1
		world.order[row] = unit[2]
		world.nav_mode[row] = FIELD
		world.field[row] = 0
		world.goal_x[row] = unit[3]
		world.goal_y[row] = unit[4]
	FlowCache.run(world, 0)  # The references.
	world.tick = 9
	return world


## A 20 x 12 map and a cache configured for 22 columns, for wheeled units (whose cost table starts
## at 240, so a table offset taken from the cache's columns, 264, reads other tiles), with a field
## keyed on tile 70 that turns to rock after the field is complete. Unit 0 stands in tile 69 in
## FIELD on it: the field names the key, which is blocked now (`World.is_passable`, from the map's
## cost table), so the unit has no next tile and takes the field of its goal's tile, slot 1 (-1,
## pending). Unit 1 is a MOVE tank in (9, 4) whose step (1000, -1000) lands on the rock of tile 70
## and slides along the tile it stands in: it keeps going east in (10, 4), the tile that the map's
## columns name, where a row stride of 22 reads tile 98, which is rock here, and it would stop.
func test_a_wider_cache_reads_the_cost_table_by_the_maps_columns() -> void:
	var problems: Array[String] = []
	var pair: Array[World] = LockstepRig.pair(_rock_key_world, false, problems)
	assert_array(problems).is_empty()
	for world: World in pair:
		Movement.integrate(world)
	assert_str(LockstepRig.difference(pair[0], pair[1])).is_empty()
	for world: World in pair:
		assert_array([world.nav_next[0], world.field[0]]).is_equal([-1, 1])
		assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([10500, 4500])


## The World of the case above: rock at (18, 4), the field of tile 70 complete, then rock on tile 70
## too (`set_terrain`, which asks for the field again and leaves the complete one served).
func _rock_key_world() -> World:
	var rock: Array[Vector2i] = [Vector2i(18, 4)]
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock), [WHEELED])
	world.flow_cache_size = 3
	world.flow.configure(22, 12, World.MoveClass.size(), 3)
	assert_int(world.flow.acquire(70, WHEELED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	var field_unit: int = world.add_unit(1, 0, 9500, 3500) - 1
	world.order[field_unit] = MOVE
	world.nav_mode[field_unit] = FIELD
	world.field[field_unit] = 0
	world.goal_x[field_unit] = 500
	world.goal_y[field_unit] = 500
	var slider: int = world.add_unit(1, 0, 9500, 4500) - 1
	world.order[slider] = MOVE
	world.goal_x[slider] = 500
	world.goal_y[slider] = 500
	world.intent_x[slider] = 1000
	world.intent_y[slider] = -1000
	FlowCache.run(world, 0)  # The references.
	world.set_terrain(70, ROCK)
	world.tick = 9
	return world
