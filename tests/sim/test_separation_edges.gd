extends GdUnitTestSuite
## Separation.run, the cases beside test_separation.gd (P39): units of different radii, the rule
## ints read from the World, the neighbour and scan caps in scan order (the first 8 overlapping
## units and the first 16 looked at, cell by cell and by id inside a cell), every row written, the
## work count, and the map corners. Single-tick cases rebuild the grid and call `Separation.run`
## (SeparationRig). Tanks have radius 400 and squads (type 1 here) 300.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const COLS: int = 20
const ROWS: int = 8


## A prepared open map of COLS x ROWS tiles with a tank (type 0, radius 400) at each point.
func _tanks(points: Array[Vector2i]) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	for point: Vector2i in points:
		world.add_unit(1, 0, point.x, point.y)
	return world


func _pushes(world: World) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		found.append(Vector2i(world.push_x[row], world.push_y[row]))
	return found


## The reach of a pair is the sum of the two radii: a tank and a squad (400 + 300 = 700) 600 apart
## push 79 (130000 / 980000 of 600), 39 each, whichever of the two comes first.
func test_the_reach_of_a_pair_is_the_sum_of_the_two_radii() -> void:
	for tank_first: bool in [true, false]:
		var world: World = GridWorld.from_rows(
			GridWorld.grass(COLS, ROWS), [World.MoveClass.TRACKED, World.MoveClass.FOOT]
		)
		world.type_radius[1] = 300
		world.add_unit(1, 0 if tank_first else 1, 5000, 4000)
		world.add_unit(1, 1 if tank_first else 0, 5600, 4000)
		Rig.separate(world)
		assert_array(_pushes(world)).is_equal([Vector2i(-39, 0), Vector2i(39, 0)])
		# At 700 they touch and nothing pushes.
		world.pos_x[1] = 5700
		Rig.separate(world)
		assert_array(_pushes(world)).is_equal([Vector2i.ZERO, Vector2i.ZERO])


## Every tuning number comes from the World's rule ints, not from a literal: the idle share (60
## instead of 75), the push cap (20), the near-coincident divisor (2) and the caps on neighbours
## (1) and looks (2).
func test_the_rule_ints_of_the_world_decide() -> void:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5720, 4000)])
	world.intent_x[1] = 120
	world.separation_idle_share = 60
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-40, 0), Vector2i(27, 0)])
	world = _tanks([Vector2i(5000, 4000), Vector2i(5600, 4000)])
	world.separation_push_max = 20
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-20, 0), Vector2i(20, 0)])
	# With a divisor of 2 the fixed push covers pairs closer than 400 (the cap lifted so that it
	# shows): 399 apart, min(400, 1000) = 400 for the pair; 401 apart, the formula's 150.
	for distance: int in [399, 401]:
		world = _tanks([Vector2i(5000, 4000), Vector2i(5000 + distance, 4000)])
		world.separation_coincident_divisor = 2
		world.separation_push_max = 1000
		Rig.separate(world)
		var push: int = 200 if distance == 399 else 75
		assert_array(_pushes(world)).is_equal([Vector2i(-push, 0), Vector2i(push, 0)])
	# On the same point the fixed push is min(R / divisor, cap): 200 for two tanks, 150 for two
	# squads, 100 each and 75 each.
	world = _tanks([Vector2i(5000, 4000), Vector2i(5000, 4000)])
	world.separation_push_max = 1000
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-100, 0), Vector2i(100, 0)])
	world.type_radius[0] = 300
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-75, 0), Vector2i(75, 0)])
	# One neighbour is used, of three overlapping: the first in scan order, the one 700 east.
	world = _tanks([Vector2i(5000, 4000), Vector2i(5700, 4000), Vector2i(5000, 4700)])
	world.separation_neighbours = 1
	Rig.separate(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([-41, 0])
	# Two looks: a first unit that does not overlap uses one, the east neighbour the second.
	world = _tanks([Vector2i(5000, 4000), Vector2i(4000, 4000), Vector2i(5700, 4000)])
	world.separation_scan = 1
	Rig.separate(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([0, 0])
	world.separation_scan = 2
	Rig.separate(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([-41, 0])


## A unit uses the first 8 units that overlap it in scan order, and the nine units around it
## here each push it 4 (790 apart: 9 / 2, truncated). Eight east of it on one point and a ninth
## south of it in the same cell: the push is 8 times 4 along x and nothing along y. Then the scan
## order is by cell before id: eight on one point in the cell above (scanned first) and a unit
## with a lower id in its own cell, which is not used. Eight units that only touch it are not
## neighbours and leave room for the overlapping ninth.
func test_a_unit_uses_the_first_8_overlapping_units_in_scan_order() -> void:
	var points: Array[Vector2i] = [Vector2i(5000, 4000)]
	for _east: int in 8:
		points.append(Vector2i(5790, 4000))
	points.append(Vector2i(5000, 4790))
	var world: World = _tanks(points)
	Rig.separate(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([-32, 0])
	points = [Vector2i(5000, 4000), Vector2i(5000, 4790)]
	for _north: int in 8:
		points.append(Vector2i(5000, 3210))
	world = _tanks(points)
	Rig.separate(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([0, 32])
	# Units just touching (800 apart) do not overlap: they use none of the 8 and push nothing.
	points = [Vector2i(5000, 4000)]
	for _touching: int in 8:
		points.append(Vector2i(5800, 4000))
	points.append(Vector2i(5000, 4790))
	world = _tanks(points)
	Rig.separate(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([0, -4])


## A unit looks at no more than 16 others: with 15 units in the first cell it scans that do not
## overlap it, the overlapping unit in the last cell is the 16th and pushes it; with 16 it is the
## 17th and never looked at.
func test_a_unit_looks_at_no_more_than_16_others_in_scan_order() -> void:
	for fillers: int in [15, 16]:
		var points: Array[Vector2i] = [Vector2i(5950, 5950)]
		for _filler: int in fillers:
			points.append(Vector2i(4100, 4100))
		points.append(Vector2i(6100, 6100))
		var world: World = _tanks(points)
		Rig.separate(world)
		var push: int = -34 if fillers == 15 else 0
		(
			assert_array([world.push_x[0], world.push_y[0]])
			. override_failure_message("fillers %d" % fillers)
			. is_equal([push, push])
		)


## Every row is written, with 0 where nothing overlaps; nothing moves (the pushes are all made
## from the positions at the start of the tick, so a second run is the same); the work count is
## added to what the tick has counted so far.
func test_every_row_is_written_nothing_moves_and_the_pair_count_is_added() -> void:
	var world: World = _tanks(
		[Vector2i(2000, 4000), Vector2i(5000, 4000), Vector2i(5700, 4000), Vector2i(9000, 4000)]
	)
	world.push_x.fill(99)
	world.push_y.fill(-99)
	world.stats[World.Stat.SEP_PAIRS] = 7
	Rig.separate(world)
	var first: Array[Vector2i] = _pushes(world)
	assert_array(first).is_equal([Vector2i.ZERO, Vector2i(-41, 0), Vector2i(41, 0), Vector2i.ZERO])
	assert_int(world.push_x[world.max_rows - 1]).is_equal(0)
	assert_int(world.push_y[world.max_rows - 1]).is_equal(0)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(9)
	assert_array(world.pos_x.slice(0, 4)).is_equal([2000, 5000, 5700, 9000])
	Separation.run(world)
	assert_array(_pushes(world)).is_equal(first)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(11)


## No units, a World that was never prepared, and a prepared one with an empty map (no grid cells)
## are legal: nothing is counted, and a stale push is cleared.
func test_no_units_no_map_and_an_unprepared_world_leave_the_count_alone() -> void:
	var world: World = _tanks([])
	Rig.separate(world)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(0)
	var bare: World = World.new()
	Separation.run(bare)
	assert_int(bare.stats.size()).is_equal(0)
	assert_int(bare.push_x.size()).is_equal(0)
	bare.type_ids.append(&"tank")
	for table: PackedInt32Array in [
		bare.type_speed, bare.type_radius, bare.type_selection_radius, bare.type_spacing
	]:
		table.append(400)
	bare.player_count = 1
	bare.prepare()
	bare.add_unit(1, 0, 100, 100)
	bare.push_x.fill(99)
	bare.push_y.fill(-99)
	Rig.separate(bare)
	assert_array([bare.push_x[0], bare.push_y[0]]).is_equal([0, 0])
	assert_int(bare.stats[World.Stat.SEP_PAIRS]).is_equal(0)


## Units at the corners of the map: the 3x3 cells around them are cut at the map's edge. Two
## tanks 100 apart at the top left corner and at the far corner take the fixed push of 30 each
## way, and the clamp to the map keeps the outer ones where they stand.
func test_units_at_the_map_corners_are_separated_inside_the_map() -> void:
	var world: World = _tanks(
		[Vector2i(0, 0), Vector2i(100, 0), Vector2i(19899, 7999), Vector2i(19999, 7999)]
	)
	Rig.ticks(world, 1)
	assert_array(_pushes(world)).is_equal(
		[Vector2i(-30, 0), Vector2i(30, 0), Vector2i(-30, 0), Vector2i(30, 0)]
	)
	assert_array([world.pos_x[0], world.pos_x[1]]).is_equal([0, 130])
	assert_array([world.pos_x[2], world.pos_x[3]]).is_equal([19869, 19999])


## The cells are scanned row by row, left to right: with 16 units that do not overlap in the cell
## above and to the right, the looks are used up before the overlapping unit in its own cell (700
## below, pushing 41), which 15 of them leave room for.
func test_cells_are_scanned_row_by_row() -> void:
	for fillers: int in [15, 16]:
		var points: Array[Vector2i] = [Vector2i(5500, 4900), Vector2i(5500, 4200)]
		for _filler: int in fillers:
			points.append(Vector2i(6500, 3500))
		var world: World = _tanks(points)
		Rig.separate(world)
		var push: int = 41 if fillers == 15 else 0
		(
			assert_array([world.push_x[0], world.push_y[0]])
			. override_failure_message("fillers %d" % fillers)
			. is_equal([0, push])
		)


## The cells beyond the map's edge are skipped, not wrapped to the other side of the grid: units
## on the left edge and the right edge of the row above, and on the top row and the bottom row of
## one column, never look at each other.
func test_the_edges_of_the_map_do_not_wrap() -> void:
	var world: World = _tanks(
		[Vector2i(100, 4500), Vector2i(19900, 3500), Vector2i(9500, 500), Vector2i(9500, 7500)]
	)
	Rig.separate(world)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(0)


## The cell size is the grid's: on a grid of 2-tile cells, two tanks 200 apart across a cell border
## are each in the other's 3x3 cells.
func test_the_cell_size_comes_from_the_grid() -> void:
	var world: World = _tanks([Vector2i(1900, 4000), Vector2i(2100, 4000)])
	world.sep_grid.configure(world.map_w, world.map_h, 2 * World.MILLI_PER_TILE, world.max_rows)
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-46, 0), Vector2i(46, 0)])


## The formula's truncation is exact: 311 apart the pair push is 131 (131.9 before the cut, and
## 132 if the weight were one more), so a moving unit that takes 25% of it is pushed 32, not 33.
## The weight is R*R - d2, not one less: 400 apart the pair push is exactly 150 (the cap lifted so
## that it shows), 75 each, where a weight one less would give 149 and 74.
func test_the_formula_push_truncates_exactly() -> void:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5311, 4000)])
	world.intent_x[0] = 120
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-32, 0), Vector2i(60, 0)])
	world = _tanks([Vector2i(5000, 4000), Vector2i(5400, 4000)])
	world.separation_push_max = 1000
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-75, 0), Vector2i(75, 0)])


## The idle share is kept between 0 and 100 whatever the rule int says. 780 apart the pair push is
## 19, and the second unit is moving: with a share of 100 or more the idle unit takes all of it and
## the moving one nothing, with 0 or less the moving one takes all of it.
func test_the_idle_share_is_kept_between_0_and_100() -> void:
	# The rule int, then the pushes along x of the idle lower unit and of the moving higher one.
	var cases: Array = [[100, -19, 0], [0, 0, 19], [150, -19, 0], [-10, 0, 19]]
	for case: Array in cases:
		var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5780, 4000)])
		world.intent_x[1] = 120
		world.separation_idle_share = case[0]
		Rig.separate(world)
		assert_array(_pushes(world)).override_failure_message(str(case)).is_equal(
			[Vector2i(case[1], 0), Vector2i(case[2], 0)]
		)


## `run` reads the grid and the intents and writes the pushes and the pair count, nothing else: it
## does not rebuild the grid, it leaves the intents, the positions and every other work count as
## they were, and it writes every row's push. Unit 1 is moved next to the others after the rebuild,
## so the grid still lists it in its old cell: units 0 and 2 never find it, and it (scanning from
## where it stands) finds them. A rebuilt grid would give different pushes and a different grid.
func test_run_writes_only_the_pushes_and_the_pair_count() -> void:
	var world: World = _tanks(
		[Vector2i(5000, 4000), Vector2i(9400, 4000), Vector2i(5700, 4300), Vector2i(2000, 4000)]
	)
	world.intent_x[2] = 120
	world.intent_y[2] = -35
	world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	world.pos_x[1] = 5400
	world.push_x.fill(99)
	world.push_y.fill(-99)
	var heads: PackedInt32Array = world.sep_grid.head.duplicate()
	var links: PackedInt32Array = world.sep_grid.next.duplicate()
	var intent_x: PackedInt32Array = world.intent_x.duplicate()
	var intent_y: PackedInt32Array = world.intent_y.duplicate()
	var stats: PackedInt32Array = world.stats.duplicate()
	var hash_before: int = world.state_hash()
	Separation.run(world)
	# Unit 0 (idle) finds unit 2 (moving), 700 east and 300 south of it: the pair push (32, 14) is
	# shared 75/25. Unit 1 (idle) finds both: 75 from unit 0, and from unit 2 -80 along x and -80
	# along y, so its y push is cut to -60. Four pairs in all.
	assert_array(_pushes(world)).is_equal(
		[Vector2i(-24, -10), Vector2i(-5, -60), Vector2i(8, 3), Vector2i.ZERO]
	)
	stats[World.Stat.SEP_PAIRS] += 4
	assert_array(world.stats).is_equal(stats)
	assert_array(world.sep_grid.head).is_equal(heads)
	assert_array(world.sep_grid.next).is_equal(links)
	assert_array(world.intent_x).is_equal(intent_x)
	assert_array(world.intent_y).is_equal(intent_y)
	assert_int(world.state_hash()).is_equal(hash_before)
