extends GdUnitTestSuite
## Separation.run (P39, part 1; ADR 0008 section 4): the pushes of overlapping units. Single-tick
## cases rebuild the separation grid and call `Separation.run` once, then read `push_x` and
## `push_y`; multi-tick cases run `Movement.run`, the grid rebuild, `Separation.run` and
## `Movement.integrate` in pipeline order (SeparationRig), because `Sim.step` does not separate
## until P39b. Tanks have radius 400, so two of them overlap below a distance of 800 (R); the rules
## are the shipped ones: a pair closer than R / 4 = 200 gets the fixed push of min(200, 60) = 60,
## an idle unit takes 75% of a push against a moving one, a unit's push is at most 60 per axis, and
## a unit looks at 16 others and uses the first 8 that overlap. Maps are built in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const COLS: int = 20
const ROWS: int = 8
## The tick after which every near-coincident pair of the tests below stands at least 90% of the
## radii sum apart (720), measured in P39; the tick before it, one pair is short of it.
const APART_TICK: int = 9
const TRACKED: int = World.MoveClass.TRACKED


## A prepared map of COLS x ROWS tiles, open but for the `rock` tiles, with a tank (type 0, radius
## 400) at each point.
func _tanks(points: Array[Vector2i], rock: Array[Vector2i] = []) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS, rock))
	for point: Vector2i in points:
		world.add_unit(1, 0, point.x, point.y)
	return world


func _pushes(world: World) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		found.append(Vector2i(world.push_x[row], world.push_y[row]))
	return found


func _positions(world: World) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		found.append(Vector2i(world.pos_x[row], world.pos_y[row]))
	return found


## Six pairs, 3000 apart on the row y = 1500 (x = 2000, 5000, ...): 2, 1 and 3 milli along x, then
## (1, 1) and (3, 3) on a diagonal, then 2 milli along y.
func _pairs() -> Array[Vector2i]:
	return [
		Vector2i(2000, 1500),
		Vector2i(2002, 1500),
		Vector2i(5000, 1500),
		Vector2i(5001, 1500),
		Vector2i(8000, 1500),
		Vector2i(8003, 1500),
		Vector2i(11000, 1500),
		Vector2i(11001, 1501),
		Vector2i(14000, 1500),
		Vector2i(14003, 1503),
		Vector2i(17000, 1500),
		Vector2i(17000, 1502),
	]


## The least squared distance between the two units of a pair of `_pairs()`.
func _closest_pair2(world: World) -> int:
	var closest: int = 1 << 40
	for pair: int in 6:
		closest = mini(closest, Rig.distance2(world, 2 * pair, 2 * pair + 1))
	return closest


## Two tanks on one point are pushed along x only, the lower id towards -x: the pair push is
## min(R / 4, 60) = 60, 30 each. Both are idle, so the shares are equal. Each looked at the other.
func test_two_tanks_on_the_same_point_split_a_push_of_60_along_x() -> void:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5000, 4000)])
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-30, 0), Vector2i(30, 0)])
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(2)


## Pairs 1, 2 and 3 milli apart along x, a pair on a diagonal and a pair along y (the pairs far
## from each other, so each is alone) take the fixed push on every axis they differ in, signed away
## from each other: 30 each, the lower id towards the lower coordinate. After 4 ticks every pair is
## at least R / 4 = 200 apart (62, 122, 182 and 242 along x for the pair 2 milli apart).
func test_near_coincident_pairs_are_200_apart_after_4_ticks() -> void:
	var world: World = _tanks(_pairs())
	Rig.ticks(world, 1)
	(
		assert_array(_positions(world))
		. is_equal(
			[
				Vector2i(1970, 1500),
				Vector2i(2032, 1500),
				Vector2i(4970, 1500),
				Vector2i(5031, 1500),
				Vector2i(7970, 1500),
				Vector2i(8033, 1500),
				Vector2i(10970, 1470),
				Vector2i(11031, 1531),
				Vector2i(13970, 1470),
				Vector2i(14033, 1533),
				Vector2i(17000, 1470),
				Vector2i(17000, 1532),
			]
		)
	)
	Rig.ticks(world, 3)
	assert_int(world.pos_x[1] - world.pos_x[0]).is_equal(242)
	for pair: int in 6:
		(
			assert_int(Rig.distance2(world, 2 * pair, 2 * pair + 1))
			. override_failure_message("pair %d" % pair)
			. is_greater_equal(200 * 200)
		)


## The same pairs stand at least 90% of the radii sum (720, no visible overlap) apart after
## APART_TICK ticks, and not one tick before. The fixed push gets a pair to 200; the formula takes
## over there and its push falls off as the pair nears contact.
func test_near_coincident_pairs_reach_90_percent_of_the_radii_sum_at_the_measured_tick() -> void:
	var world: World = _tanks(_pairs())
	Rig.ticks(world, APART_TICK - 1)
	assert_bool(_closest_pair2(world) >= 720 * 720).is_false()
	Rig.tick(world)
	assert_bool(_closest_pair2(world) >= 720 * 720).is_true()


## At d = R / 4 = 200 the formula takes over from the fixed push: 200 * (R*R - 200*200) / (2 *
## R*R) = 93 for the pair, 46 each (the pair push and then the share truncate toward zero, for the
## negative side too). One milli closer the fixed push of 60 applies, 30 each.
func test_at_a_distance_of_r_over_4_the_formula_push_applies_not_the_fixed_one() -> void:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5200, 4000)])
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-46, 0), Vector2i(46, 0)])
	world = _tanks([Vector2i(5000, 4000), Vector2i(5199, 4000)])
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-30, 0), Vector2i(30, 0)])


## Two squads (radius 300, R = 600) overlapping by 200 stand 400 apart: the pair push is 111, and
## each unit moves half of it, 55 (truncated). On a diagonal, 300 along each axis, the pair push
## is 75 per axis and each takes 37 per axis.
func test_overlapping_units_in_the_same_state_each_move_half_the_push() -> void:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5400, 4000)])
	world.type_radius[0] = 300
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-55, 0), Vector2i(55, 0)])
	world = _tanks([Vector2i(5000, 4000), Vector2i(5300, 4300)])
	world.type_radius[0] = 300
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-37, -37), Vector2i(37, 37)])


## An idle unit next to a moving one takes 75% of the pair push (68 at a distance of 720) and the
## moving one the other 25%: -51 and 17 whichever of the two is first. Moving is a non-zero intent
## on either axis, and two moving units split the push 50/50 again. The shares apply on both axes:
## 150 apart each way (d2 = 45000, above the fixed push's limit of 40000) the pair push is 69 per
## axis, so the idle unit takes 51 and the moving one 17 along y as well as along x.
func test_an_idle_unit_takes_75_percent_against_a_moving_one() -> void:
	# The intent of the lower unit (x, y) and of the higher (x, y), then the pushes along x.
	var cases: Array = [
		[0, 0, 120, 0, -51, 17],
		[0, 0, 0, 0, -34, 34],
		[120, 0, 0, 0, -17, 51],
		[0, 0, 0, 120, -51, 17],
		[0, 0, 0, 1, -51, 17],
		[0, 1, 0, 0, -17, 51],
		[0, 120, 0, 120, -34, 34],
	]
	for case: Array in cases:
		var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5720, 4000)])
		world.intent_x[0] = case[0]
		world.intent_y[0] = case[1]
		world.intent_x[1] = case[2]
		world.intent_y[1] = case[3]
		Rig.separate(world)
		(
			assert_array([world.push_x[0], world.push_x[1], world.push_y[0], world.push_y[1]])
			. override_failure_message(str(case))
			. is_equal([case[4], case[5], 0, 0])
		)
	var diagonal: World = _tanks([Vector2i(5000, 4000), Vector2i(5150, 4150)])
	diagonal.intent_x[1] = 120
	Rig.separate(diagonal)
	assert_array(_pushes(diagonal)).is_equal([Vector2i(-51, -51), Vector2i(17, 17)])


## A unit's push is at most 60 per axis, summed over its neighbours: one pair 600 apart pushes 131,
## 65 each, cut to 60; two neighbours 700 away on the same point give 41 each, so 82 together, cut
## to 60 (their own push on each other, 30 along x, and the 41 of the first unit stay); the same
## on the y axis at the positive end (neighbours above) and at the negative end (neighbours below).
func test_the_push_is_clamped_to_60_per_axis() -> void:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5600, 4000)])
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(-60, 0), Vector2i(60, 0)])
	world = _tanks(
		[
			Vector2i(5000, 4000),
			Vector2i(5700, 4000),
			Vector2i(5700, 4000),
			Vector2i(9000, 4000),
			Vector2i(9000, 3300),
			Vector2i(9000, 3300),
			Vector2i(13000, 4000),
			Vector2i(13000, 4700),
			Vector2i(13000, 4700),
		]
	)
	Rig.separate(world)
	(
		assert_array(_pushes(world))
		. is_equal(
			[
				Vector2i(-60, 0),
				Vector2i(11, 0),
				Vector2i(60, 0),
				Vector2i(0, 60),
				Vector2i(-30, -41),
				Vector2i(30, -41),
				Vector2i(0, -60),
				Vector2i(-30, 41),
				Vector2i(30, 41),
			]
		)
	)


## A packed 5x5 crowd, 100 apart, overlaps everywhere: each unit stops at its 8th neighbour, so 8
## pairs are looked at per unit, 200 in all (a ninth neighbour would give 225, and no cap on the
## neighbours 400, as the 16 looks cap them). A lattice 600 apart overlaps only along its rows and
## columns, so a unit finds fewer than 8 and stops at the 16th unit it looks at: the pairs counted
## are the units in its 3x3 cells up to 16, which the test counts by brute force.
func test_a_packed_crowd_uses_8_neighbours_and_16_looks() -> void:
	var points: Array[Vector2i] = []
	for row: int in 25:
		points.append(Vector2i(4800 + 100 * (row % 5), 4800 + 100 * (row / 5)))
	var world: World = _tanks(points)
	Rig.separate(world)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(25 * 8)
	points.clear()
	for row: int in 25:
		points.append(Vector2i(3000 + 600 * (row % 5), 3000 + 600 * (row / 5)))
	world = _tanks(points)
	Rig.separate(world)
	var capped: int = 0
	var uncapped: int = 0
	for row: int in 25:
		var near: int = 0
		for other: int in 25:
			var apart_x: int = absi(points[row].x / 1000 - points[other].x / 1000)
			var apart_y: int = absi(points[row].y / 1000 - points[other].y / 1000)
			if other != row and apart_x <= 1 and apart_y <= 1:
				near += 1
		capped += mini(near, 16)
		uncapped += near
	assert_int(capped).is_less(uncapped)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(capped)


## No push moves a centre onto rock: `Movement.integrate` slides the sum of intent and push. A
## tank 10 milli from a rock tile, pushed 60 towards it, stays; pushed (60, 34) it takes the y part
## only. A crowd pressed against a wall of rock for 40 ticks never has a centre on rock.
func test_no_push_moves_a_centre_onto_rock() -> void:
	var rock: Array[Vector2i] = [Vector2i(4, 3), Vector2i(4, 5)]
	var world: World = _tanks(
		[
			Vector2i(3990, 3500),
			Vector2i(3600, 3500),
			Vector2i(3990, 5500),
			Vector2i(3600, 5300),
		],
		rock
	)
	Rig.tick(world)
	assert_array([world.push_x[0], world.push_y[0]]).is_equal([60, 0])
	assert_array([world.push_x[2], world.push_y[2]]).is_equal([60, 34])
	assert_array(_positions(world)).is_equal(
		[Vector2i(3990, 3500), Vector2i(3540, 3500), Vector2i(3990, 5534), Vector2i(3540, 5266)]
	)
	var wall: Array[Vector2i] = [Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4)]
	var crowd: Array[Vector2i] = []
	for row: int in 12:
		crowd.append(Vector2i(5000 + 150 * (row % 4), 3000 + 150 * (row / 4)))
	world = _tanks(crowd, wall)
	var pressed: int = 0
	for tick: int in 40:
		Rig.tick(world)
		for row: int in 12:
			var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
			assert_bool(world.is_passable(cell, TRACKED)).is_true()
			pressed = maxi(pressed, world.pos_x[row])
	# The wall starts at x = 6000: the crowd did reach it.
	assert_int(pressed).is_greater(5900)


## Units resting 1200 apart (the Phase 1 slot spacing, more than the radii sum of 800) get no
## push and never move. A 3x3 block of them: each looks at the units in its 3x3 cells (3, 5 or 8
## others), 40 in all.
func test_units_resting_1200_apart_are_not_pushed_and_never_move() -> void:
	var points: Array[Vector2i] = []
	for row: int in 9:
		points.append(Vector2i(2000 + 1200 * (row % 3), 2000 + 1200 * (row / 3)))
	var world: World = _tanks(points)
	Rig.separate(world)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(40)
	assert_array(_pushes(world)).is_equal(
		(
			[Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
			+ [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
		)
	)
	Rig.ticks(world, 10)
	assert_array(_positions(world)).is_equal(points)


## Two runs of the same crowd (30 tanks, ten of them ordered across it) give the same state hashes
## at every 15th tick, and the state moves between them: the ordered tanks make headway through the
## crowd (the pushes are added to their intents, they do not replace them).
func test_two_runs_of_the_pipeline_give_the_same_hashes() -> void:
	var runs: Array[PackedInt64Array] = []
	for _run: int in 2:
		var points: Array[Vector2i] = []
		for row: int in 30:
			points.append(Vector2i(3000 + 400 * (row % 6), 2000 + 400 * (row / 6)))
		var world: World = _tanks(points)
		for row: int in 10:
			world.order[row] = World.Order.MOVE
			world.goal_x[row] = 12000
			world.goal_y[row] = 5000
		var start_x: int = 0
		for row: int in 10:
			start_x += world.pos_x[row]
		var hashes: PackedInt64Array = PackedInt64Array()
		hashes.append(world.state_hash())
		for _block: int in 4:
			Rig.ticks(world, 15)
			hashes.append(world.state_hash())
		assert_int(world.stats[World.Stat.SEP_PAIRS]).is_greater(0)
		var end_x: int = 0
		for row: int in 10:
			end_x += world.pos_x[row]
		# The ordered tanks (speed 120) have crossed most of the 7 tiles the 60 ticks allow.
		assert_int(end_x - start_x).is_greater(10 * 4000)
		runs.append(hashes)
	assert_array(runs[0]).is_equal(runs[1])
	assert_int(runs[0][1]).is_not_equal(runs[0][0])
	assert_int(runs[0][4]).is_not_equal(runs[0][3])
