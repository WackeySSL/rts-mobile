extends GdUnitTestSuite
## Formation.assign and the tile grid (ADR 0008 section 2, P37a): a slot on a tile that a movement
## class of the group cannot enter is skipped, and a target on such a tile moves to the centre of
## the nearest tile that every class of the group can enter. Maps built in code (GridWorld): a
## unit has the formation spacing 1200 and radius 400, and the units start far from the target.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FormationV1: GDScript = preload("res://tests/sim/support/formation_v1.gd")
const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED


## Rock far from the group changes nothing: the same slots as on an open map, on a 40 x 40 map with
## rock in the top left corner and the group in the bottom right.
func test_rock_far_from_the_group_leaves_the_slots_as_phase_1s() -> void:
	var rock: Array[Vector2i] = []
	for x: int in 6:
		for y: int in 6:
			rock.append(Vector2i(x, y))
	var world: World = GridWorld.from_rows(GridWorld.grass(40, 40, rock))
	var twin: World = GridWorld.from_rows(GridWorld.grass(40, 40))
	var rows: PackedInt32Array = GridWorld.add_block(world, 75, 9, 30500, 30500, 700, 0)
	GridWorld.add_block(twin, 75, 9, 30500, 30500, 700, 0)
	Formation.assign(world, rows, 33000, 33000)
	FormationV1.assign(twin, rows, 33000, 33000)
	assert_array(world.goal_x).is_equal(twin.goal_x)
	assert_array(world.goal_y).is_equal(twin.goal_y)


## A target on a blocked tile moves to the centre of the first open tile in the rings around it:
## ring by ring, each ring row by row from the top, left to right. The target (3100, 3900) is in the
## bottom left of rock tile (3, 3): the first open tile is the top left neighbour (2, 2), though
## (3, 4) and (2, 3) are nearer to the target.
func test_a_target_on_rock_moves_to_the_first_open_tile_in_ring_row_order() -> void:
	var cases: Array[Array] = [
		# the rock tiles, the target, the goal of a lone unit
		[[[3, 3]], Vector2i(3100, 3900), Vector2i(2500, 2500)],
		[[[3, 3]], Vector2i(3400, 3600), Vector2i(2500, 2500)],
		# Ring 1, row -1 blocked: the left tile of row 0, then its right tile, then row +1.
		[[[3, 3], [2, 2], [3, 2], [4, 2]], Vector2i(3400, 3600), Vector2i(2500, 3500)],
		[[[3, 3], [2, 2], [3, 2], [4, 2], [2, 3]], Vector2i(3400, 3600), Vector2i(4500, 3500)],
		[
			[[3, 3], [2, 2], [3, 2], [4, 2], [2, 3], [4, 3]],
			Vector2i(3400, 3600),
			Vector2i(2500, 4500)
		],
		# The eight neighbours blocked as well: ring 2 starts at its top left tile.
		[
			[[2, 2], [3, 2], [4, 2], [2, 3], [3, 3], [4, 3], [2, 4], [3, 4], [4, 4]],
			Vector2i(3500, 3500),
			Vector2i(1500, 1500)
		],
		# At a map corner the rings skip the tiles outside the map. The target is clamped to
		# (400, 400) by the radius, its tile (0, 0) is rock, the first open tile is (1, 0).
		[[[0, 0]], Vector2i(200, 300), Vector2i(1500, 500)],
		# An open tile keeps the target where it is.
		[[[3, 3]], Vector2i(4200, 3300), Vector2i(4200, 3300)],
	]
	for case: Array in cases:
		var rock: Array[Vector2i] = GridWorld.tiles(case[0])
		var world: World = GridWorld.from_rows(GridWorld.grass(8, 8, rock))
		var rows: PackedInt32Array = GridWorld.add_block(world, 1, 1, 7500, 7500, 0, 0)
		var target: Vector2i = case[1]
		Formation.assign(world, rows, target.x, target.y)
		var goal: Vector2i = GridWorld.goals(world, rows)[0]
		assert_that(goal).override_failure_message(str(case)).is_equal(case[2])


## The target moves for a class that cannot enter its tile: scrub is open to a foot unit and not to
## a tank, and a group is blocked when any of its units is.
func test_the_target_moves_only_for_a_class_that_cannot_enter_its_tile() -> void:
	var map: PackedStringArray = GridWorld.grass(8, 8)
	map[3] = "...^...."
	var target: Vector2i = Vector2i(3500, 3500)
	# the unit types of the group (0 = foot, 1 = tracked), the goal of its first unit
	var cases: Array[Array] = [
		[[0], target], [[1], Vector2i(2500, 2500)], [[0, 1], Vector2i(2500, 2500)]
	]
	for case: Array in cases:
		var world: World = GridWorld.from_rows(map, [FOOT, TRACKED])
		var group: PackedInt32Array = PackedInt32Array()
		for type: int in case[0]:
			world.add_unit(1, type, 7500, 7500)
			group.append(world.unit_count() - 1)
		Formation.assign(world, group, target.x, target.y)
		assert_that(GridWorld.goals(world, group)[0]).override_failure_message(str(case)).is_equal(
			case[1]
		)


## The search covers the whole map: on a 6 x 6 map of rock with one open tile in the far corner,
## a target on the opposite corner moves five rings out to it.
func test_the_search_reaches_the_far_corner_of_the_map() -> void:
	var map: PackedStringArray = PackedStringArray(
		["######", "######", "######", "######", "######", "#####."]
	)
	var world: World = GridWorld.from_rows(map)
	var rows: PackedInt32Array = GridWorld.add_block(world, 1, 1, 3500, 3500, 0, 0)
	Formation.assign(world, rows, 0, 0)
	assert_that(GridWorld.goals(world, rows)[0]).is_equal(Vector2i(5500, 5500))
	# And the other way round, from the bottom right to the open tile in the top left.
	var flipped: PackedStringArray = PackedStringArray(
		[".#####", "######", "######", "######", "######", "######"]
	)
	var other: World = GridWorld.from_rows(flipped)
	var group: PackedInt32Array = GridWorld.add_block(other, 1, 1, 3500, 3500, 0, 0)
	Formation.assign(other, group, 6000, 6000)
	assert_that(GridWorld.goals(other, group)[0]).is_equal(Vector2i(500, 500))


## No open tile on the map: no slot exists, so every unit gets the clamped target, and it ends.
func test_a_map_of_rock_gives_every_unit_the_clamped_target() -> void:
	var world: World = GridWorld.from_rows(PackedStringArray(["###", "###", "###"]))
	var rows: PackedInt32Array = GridWorld.add_block(world, 5, 5, 1000, 1000, 100, 0)
	Formation.assign(world, rows, 5000, -4000)
	for goal: Vector2i in GridWorld.goals(world, rows):
		assert_that(goal).is_equal(Vector2i(2600, 400))


## A rock block around the target: the group forms around the first open tile centre, and the
## slots that fall on the block are skipped. The unit nearest that centre takes it.
func test_a_group_forms_around_the_moved_target_and_off_the_rock() -> void:
	var rock: Array[Vector2i] = []
	for x: int in range(5, 8):
		for y: int in range(5, 8):
			rock.append(Vector2i(x, y))
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 12, rock))
	var rows: PackedInt32Array = GridWorld.add_block(world, 6, 6, 10500, 10500, 300, 0)
	world.pos_x[4] = 4500
	world.pos_y[4] = 4600
	Formation.assign(world, rows, 6500, 6500)
	var goals: Array[Vector2i] = GridWorld.goals(world, rows)
	assert_that(goals[4]).is_equal(Vector2i(4500, 4500))
	for goal: Vector2i in goals:
		var tile: Vector2i = goal / World.MILLI_PER_TILE
		(
			assert_bool(tile.x in range(5, 8) and tile.y in range(5, 8))
			. override_failure_message(str(goal))
			. is_false()
		)
	var distinct: Dictionary[Vector2i, bool] = {}
	for goal: Vector2i in goals:
		distinct[goal] = true
	assert_int(distinct.size()).is_equal(6)


## A slot on a blocked tile is skipped and the next slot in order takes its place: with the tile
## of the lattice point (1, 0) rock, five units fill (0, 0), (0, -1), (-1, 0), (0, 1) and then
## (-1, -1), the first point at squared distance 2.
func test_a_slot_on_a_blocked_tile_is_skipped() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 12, [Vector2i(5, 4)]))
	var rows: PackedInt32Array = GridWorld.add_block(world, 5, 5, 8500, 8500, 300, 0)
	Formation.assign(world, rows, 4500, 4500)
	var expected: Array[Vector2i] = [
		Vector2i(4500, 4500),
		Vector2i(4500, 3300),
		Vector2i(3300, 4500),
		Vector2i(4500, 5700),
		Vector2i(3300, 3300),
	]
	assert_array(GridWorld.goals(world, rows)).contains_exactly_in_any_order(expected)


## Every tile of ring 1 is rock: the ring is still inside the map, so the search goes on to ring 2,
## and the nine units take the centre, the four axis points at distance 2 and the first four points
## at squared distance 5 in generation order.
func test_a_ring_of_blocked_slots_does_not_end_the_search() -> void:
	var rock: Array[Vector2i] = []
	for x: int in range(5, 8):
		for y: int in range(5, 8):
			if x != 6 or y != 6:
				rock.append(Vector2i(x, y))
	var world: World = GridWorld.from_rows(GridWorld.grass(14, 14, rock))
	var rows: PackedInt32Array = GridWorld.add_block(world, 9, 3, 11500, 11500, 300, 0)
	Formation.assign(world, rows, 6500, 6500)
	assert_array(GridWorld.goals(world, rows)).contains_exactly_in_any_order(_ring_two())


## Scrub around the target blocks the slots of a tank group and of a mixed group, not of a foot
## group, which takes the slots of an open map there.
@warning_ignore("integer_division")
func test_slots_on_scrub_are_skipped_for_the_classes_that_cannot_enter_it() -> void:
	var map: PackedStringArray = GridWorld.grass(14, 14)
	for y: int in range(5, 8):
		map[y] = ".....^^^......" if y != 6 else ".....^.^......"
	var ring_one: Array[Vector2i] = [Vector2i(6500, 6500)]
	for step: Vector2i in [
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1)
	]:
		ring_one.append(Vector2i(6500, 6500) + step * 1200)
	# the unit types of the group (0 = foot, 1 = tracked), the nine goals
	var cases: Array[Array] = [
		[[0, 0, 0, 0, 0, 0, 0, 0, 0], ring_one],
		[[1, 1, 1, 1, 1, 1, 1, 1, 1], _ring_two()],
		[[0, 0, 0, 0, 1, 1, 1, 1, 1], _ring_two()],
	]
	for case: Array in cases:
		var world: World = GridWorld.from_rows(map, [FOOT, TRACKED])
		var group: PackedInt32Array = PackedInt32Array()
		for k: int in 9:
			world.add_unit(1, int(case[0][k]), 11500 + (k % 3) * 300, 11500 + (k / 3) * 300)
			group.append(k)
		Formation.assign(world, group, 6500, 6500)
		var goals: Array[Vector2i] = GridWorld.goals(world, group)
		assert_array(goals).override_failure_message(str(case[0])).contains_exactly_in_any_order(
			case[1]
		)


## A point on the far edge of the map is in the last tile, not in the next row's first: with radius
## 0 the target (4000, 0) on a 4 x 4 map is on tile (3, 0), and the rock at (0, 1) is not its tile.
func test_a_point_on_the_far_edge_belongs_to_the_last_tile() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(4, 4, [Vector2i(0, 1)]))
	world.type_radius[0] = 0
	var rows: PackedInt32Array = GridWorld.add_block(world, 1, 1, 2500, 2500, 0, 0)
	Formation.assign(world, rows, 4000, 0)
	assert_that(GridWorld.goals(world, rows)[0]).is_equal(Vector2i(4000, 0))
	# The bottom edge: row 4 would be past the end of the grid.
	Formation.assign(world, rows, 3000, 4000)
	assert_that(GridWorld.goals(world, rows)[0]).is_equal(Vector2i(3000, 4000))
	# The slot on the far edge is read in the same tile: two units take (4000, 0) and the nearest
	# other slot (2800, 0), not the slot below, which would follow if (4000, 0) were read as rock.
	var pair: PackedInt32Array = GridWorld.add_block(world, 2, 2, 2500, 2500, 100, 0)
	Formation.assign(world, pair, 4000, 0)
	var expected: Array[Vector2i] = [Vector2i(4000, 0), Vector2i(2800, 0)]
	assert_array(GridWorld.goals(world, pair)).contains_exactly_in_any_order(expected)


## The nine slots around (6500, 6500) when ring 1 is out: the centre, the four axis points at
## distance 2 and the first four points at squared distance 5 in generation order.
func _ring_two() -> Array[Vector2i]:
	return [
		Vector2i(6500, 6500),
		Vector2i(6500, 4100),
		Vector2i(4100, 6500),
		Vector2i(8900, 6500),
		Vector2i(6500, 8900),
		Vector2i(5300, 4100),
		Vector2i(7700, 4100),
		Vector2i(4100, 5300),
		Vector2i(8900, 5300),
	]
