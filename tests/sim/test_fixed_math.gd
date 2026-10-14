extends GdUnitTestSuite
## FixedMath (ADR 0003 sections 2 and 5, ADR 0008 section 2): isqrt, the exact floor square root
## (0 for n <= 0); step_toward, Phase 1's truncating movement step; line_clear, the supercover line
## test per movement class, on maps built in code. A tile is a half-open square, as World.cell_of
## reads a point (ADR 0008 section 1), and a crossing of a tile corner touches the tiles beside it.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
const TRACKED: int = World.MoveClass.TRACKED
const TILE: int = World.MILLI_PER_TILE
## The map of _map(): 5 x 5 tiles.
const SIDE: int = 5


func test_isqrt_known_values() -> void:
	var expected: Dictionary[int, int] = {
		0: 0,
		1: 1,
		2: 1,
		3: 1,
		4: 2,
		9: 3,
		15: 3,
		16: 4,
		14400: 120,
		99999999: 9999,
		2304000000: 48000,
		4611686018427387904: 2147483648,
		9223372036854775807: 3037000499,
	}
	for n: int in expected:
		assert_int(FixedMath.isqrt(n)).is_equal(expected[n])


func test_isqrt_negative_numbers_give_zero() -> void:
	for n: int in [-1, -2, -4, -100, -9223372036854775807 - 1]:
		assert_int(FixedMath.isqrt(n)).is_equal(0)


## r is the floor root exactly when r*r <= n < (r+1)*(r+1).
func test_isqrt_is_the_exact_floor_for_0_to_100000() -> void:
	var wrong: Array[int] = []
	for n: int in range(0, 100001):
		var r: int = FixedMath.isqrt(n)
		if r * r > n or (r + 1) * (r + 1) <= n:
			wrong.append(n)
	assert_array(wrong).is_empty()


## Around every perfect square up to 10^12: k*k-1 gives k-1, k*k and k*k+1 give k.
func test_isqrt_around_perfect_squares_up_to_a_million() -> void:
	var wrong: Array[int] = []
	for k: int in range(1, 1000001):
		if (
			FixedMath.isqrt(k * k - 1) != k - 1
			or FixedMath.isqrt(k * k) != k
			or FixedMath.isqrt(k * k + 1) != k
		):
			wrong.append(k)
	assert_array(wrong).is_empty()


## The Phase 1 method, digit by digit, kept as the oracle for the faster one.
func _digit_isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var rest: int = n
	var root: int = 0
	var bit: int = 1 << 62
	while bit > rest:
		bit >>= 2
	while bit != 0:
		if rest >= root + bit:
			rest -= root + bit
			root = (root >> 1) + bit
		else:
			root >>= 1
		bit >>= 2
	return root


## Around every power of two (where the bit-length guess changes) and around the squares of the
## powers of two plus one.
@warning_ignore("integer_division")
func test_isqrt_equals_the_digit_method_around_powers_of_two_and_their_squares() -> void:
	var wrong: Array[int] = []
	for shift: int in 63:
		var power: int = 1 << shift
		for n: int in [power - 1, power, power + 1, power * 3 / 2]:
			if FixedMath.isqrt(n) != _digit_isqrt(n):
				wrong.append(n)
	for shift: int in 32:
		var root: int = (1 << shift) + 1
		for n: int in [root * root - 1, root * root, root * root + 1, (root - 1) * (root - 1)]:
			if FixedMath.isqrt(n) != _digit_isqrt(n):
				wrong.append(n)
	assert_array(wrong).is_empty()


## Values of every magnitude from a fixed stream: equal to the digit method, and the floor root by
## its own definition (written with quotients, since (r + 1) ^ 2 overflows near 2 ^ 63).
@warning_ignore("integer_division")
func test_isqrt_equals_the_digit_method_and_the_definition_on_random_values() -> void:
	var rng: DetRandom = DetRandom.create(37, 1)
	var wrong: Array[int] = []
	for _case: int in 3000:
		var n: int = ((rng.next_u32() << 31) | rng.next_u32()) >> rng.next_int(63)
		var root: int = FixedMath.isqrt(n)
		var floor_root: bool = (
			n == 0 or (root >= 1 and root <= n / root and root + 1 > n / (root + 1))
		)
		if root != _digit_isqrt(n) or not floor_root:
			wrong.append(n)
	assert_array(wrong).is_empty()


## Phase 1's step, as Sim._move_units wrote it before P37a.
@warning_ignore("integer_division")
func _phase1_step(x: int, y: int, tx: int, ty: int, speed: int) -> Vector2i:
	var dx: int = tx - x
	var dy: int = ty - y
	var d2: int = dx * dx + dy * dy
	if d2 <= speed * speed:
		return Vector2i(tx, ty)
	var distance: int = FixedMath.isqrt(d2)
	return Vector2i(x + dx * speed / distance, y + dy * speed / distance)


## By hand: x, y, tx, ty, speed, and the position after one step.
func test_step_toward_gives_the_known_steps() -> void:
	var cases: Array[Array] = [
		# 3-4-5: the distance is exact, 60 and 80 of the 100.
		[0, 0, 300, 400, 100, 60, 80],
		# Truncation toward zero: 100 * 50 / 141 = 35.4 and, negated, -35 (a floor gives -36).
		[0, 0, 100, 100, 50, 35, 35],
		[0, 0, -100, -100, 50, -35, -35],
		[1000, 1000, 900, 900, 50, 965, 965],
		# One step or less away: snap onto the target (d2 == speed ^ 2 is still a snap).
		[0, 0, 30, 40, 50, 30, 40],
		[7, 7, 7, 7, 93, 7, 7],
		[0, 0, 0, 50, 50, 0, 50],
		# One milli beyond a step does not snap: d2 = 2601, distance 51, step 50.
		[0, 0, 0, 51, 50, 0, 50],
		[0, 0, 51, 0, 50, 50, 0],
		# A unit that cannot move never leaves, and reaches a target on its own spot.
		[0, 0, 10, 0, 0, 0, 0],
		[5, 5, 5, 5, 0, 5, 5],
		# Speed 1 stalls near a diagonal goal: both axis steps truncate to 0 (ADR 0003).
		[0, 0, 3, 3, 1, 0, 0],
		# The longest order on a 64 x 64 map: 64000 * 120 / 90509 = 84.8 truncates to 84.
		[0, 0, 64000, 64000, 120, 84, 84],
		[64000, 0, 0, 64000, 120, 63916, 84],
	]
	for case: Array in cases:
		var step: Vector2i = FixedMath.step_toward(
			int(case[0]), int(case[1]), int(case[2]), int(case[3]), int(case[4])
		)
		var expected: Vector2i = Vector2i(int(case[5]), int(case[6]))
		assert_that(step).override_failure_message(str(case)).is_equal(expected)


func test_step_toward_equals_the_phase_1_step_on_random_cases() -> void:
	var rng: DetRandom = DetRandom.create(37, 2)
	var wrong: Array[String] = []
	for _case: int in 4000:
		var x: int = rng.range_int(0, 64000)
		var y: int = rng.range_int(0, 64000)
		var near: int = rng.next_int(3)
		var spread: int = 64000 if near == 0 else (400 if near == 1 else 4000)
		var tx: int = clampi(x + rng.range_int(-spread, spread), 0, 64000)
		var ty: int = clampi(y + rng.range_int(-spread, spread), 0, 64000)
		var speed: int = rng.range_int(0, 200)
		if FixedMath.step_toward(x, y, tx, ty, speed) != _phase1_step(x, y, tx, ty, speed):
			wrong.append(str([x, y, tx, ty, speed]))
	assert_array(wrong).is_empty()


## The shipped movement in Sim.step takes the same steps, tick by tick, for 60 ticks.
func test_sim_step_moves_a_unit_exactly_as_step_toward_does() -> void:
	# start, goal, speed
	var cases: Array[Array] = [
		[Vector2i(500, 500), Vector2i(9500, 4500), 93],
		[Vector2i(9500, 9500), Vector2i(500, 800), 120],
		[Vector2i(500, 9500), Vector2i(7001, 2), 61],
		[Vector2i(5000, 5000), Vector2i(5003, 5003), 1],
		[Vector2i(2000, 3000), Vector2i(2000, 3000), 93],
	]
	for case: Array in cases:
		var start: Vector2i = case[0]
		var goal: Vector2i = case[1]
		var speed: int = case[2]
		var world: World = World.new()
		world.map_w = 10000
		world.map_h = 10000
		world.type_ids.append(&"tank")
		world.type_speed.append(speed)
		world.type_radius.append(400)
		world.type_selection_radius.append(500)
		world.type_spacing.append(1200)
		world.add_unit(1, 0, start.x, start.y)
		world.prepare()
		world.goal_x[0] = goal.x
		world.goal_y[0] = goal.y
		world.order[0] = World.Order.MOVE
		var none: Array[Command] = []
		var expected: Vector2i = start
		for tick: int in 60:
			Sim.step(world, none)
			expected = FixedMath.step_toward(expected.x, expected.y, goal.x, goal.y, speed)
			(
				assert_that(Vector2i(world.pos_x[0], world.pos_y[0]))
				. override_failure_message("%s tick %d" % [str(case), tick])
				. is_equal(expected)
			)


## A 5 x 5 map with `rock` tiles and, if given, `scrub` tiles (foot units cross scrub).
func _map(rock: Array[Vector2i] = [], scrub: Array[Vector2i] = []) -> World:
	var rows: PackedStringArray = GridWorld.grass(SIDE, SIDE, rock)
	for tile: Vector2i in scrub:
		rows[tile.y] = rows[tile.y].left(tile.x) + "^" + rows[tile.y].substr(tile.x + 1)
	return GridWorld.from_rows(rows)


## line_clear both ways round: a segment has no direction.
func _clear(world: World, a: Vector2i, b: Vector2i, move_class: int = TRACKED) -> bool:
	var forward: bool = FixedMath.line_clear(world, a.x, a.y, b.x, b.y, move_class)
	var backward: bool = FixedMath.line_clear(world, b.x, b.y, a.x, a.y, move_class)
	assert_bool(backward).override_failure_message("%s to %s" % [a, b]).is_equal(forward)
	return forward


## The tiles that block the segment when they alone are rock: the tiles it touches.
@warning_ignore("integer_division")
func _touched(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var world: World = _map()
	var touched: Array[Vector2i] = []
	for cell: int in SIDE * SIDE:
		world.set_terrain(cell, 2)
		if not _clear(world, a, b):
			touched.append(Vector2i(cell % SIDE, cell / SIDE))
		world.set_terrain(cell, 0)
	return touched


func _row(y: int, first: int, last: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x: int in range(first, last + 1):
		tiles.append(Vector2i(x, y))
	return tiles


func _column(x: int, first: int, last: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y: int in range(first, last + 1):
		tiles.append(Vector2i(x, y))
	return tiles


func test_line_clear_on_open_grass_is_true_for_every_class() -> void:
	var world: World = _map()
	var ends: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(5000, 5000),
		Vector2i(0, 5000),
		Vector2i(2500, 2500),
		Vector2i(4999, 1),
	]
	for move_class: int in [FOOT, WHEELED, TRACKED]:
		for a: Vector2i in ends:
			for b: Vector2i in ends:
				assert_bool(_clear(world, a, b, move_class)).is_true()


func test_line_clear_without_a_map_is_true_and_a_missing_class_is_false() -> void:
	var bare: World = World.new()
	assert_bool(FixedMath.line_clear(bare, 0, 0, 900, 900, TRACKED)).is_true()
	var world: World = _map([Vector2i(2, 2)])
	for bad_class: int in [-1, 3, 99]:
		assert_bool(FixedMath.line_clear(world, 500, 500, 600, 500, bad_class)).is_false()


## Through the middle of row 2 or column 2 only the tiles of that row or column count, the first
## and the last included.
func test_line_clear_axis_lines_touch_their_own_row_or_column_only() -> void:
	assert_array(_touched(Vector2i(500, 2500), Vector2i(4500, 2500))).contains_exactly_in_any_order(
		_row(2, 0, 4)
	)
	assert_array(_touched(Vector2i(2500, 4500), Vector2i(2500, 500))).contains_exactly_in_any_order(
		_column(2, 0, 4)
	)
	(
		assert_array(_touched(Vector2i(1500, 2500), Vector2i(3500, 2500)))
		. contains_exactly_in_any_order(_row(2, 1, 3))
	)
	# A point, and a segment inside one tile.
	assert_array(_touched(Vector2i(2500, 2500), Vector2i(2500, 2500))).contains_exactly(
		[Vector2i(2, 2)]
	)
	assert_array(_touched(Vector2i(2100, 2200), Vector2i(2900, 2800))).contains_exactly(
		[Vector2i(2, 2)]
	)


## A tile is a half-open square, like World.cell_of reads a point: a point on its left or top
## edge is in it, a point on its right or bottom edge is in the next tile. A segment that ends on
## the left edge of a tile touches it, one milli short does not, and a segment along an edge
## touches the tiles on its right or lower side only: the unit that stands on the edge is in that
## tile.
func test_line_clear_puts_a_point_on_an_edge_in_the_tile_cell_of_gives_it() -> void:
	var short: Array[Vector2i] = _touched(Vector2i(500, 2500), Vector2i(1999, 2500))
	assert_array(short).contains_exactly_in_any_order(_row(2, 0, 1))
	var reach: Array[Vector2i] = _touched(Vector2i(500, 2500), Vector2i(2000, 2500))
	assert_array(reach).contains_exactly_in_any_order(_row(2, 0, 2))
	# Along y = 2000, between rows 1 and 2: row 2. Along x = 2000, between columns 1 and 2: column 2.
	var along_y: Array[Vector2i] = _touched(Vector2i(500, 2000), Vector2i(4500, 2000))
	assert_array(along_y).contains_exactly_in_any_order(_row(2, 0, 4))
	var along_x: Array[Vector2i] = _touched(Vector2i(2000, 4500), Vector2i(2000, 500))
	assert_array(along_x).contains_exactly_in_any_order(_column(2, 0, 4))
	# A point on an edge, and a point on a corner: one tile each, the one below and to the right.
	var edge: Array[Vector2i] = _touched(Vector2i(2000, 2500), Vector2i(2000, 2500))
	assert_array(edge).contains_exactly([Vector2i(2, 2)])
	var corner: Array[Vector2i] = _touched(Vector2i(2000, 2000), Vector2i(2000, 2000))
	assert_array(corner).contains_exactly([Vector2i(2, 2)])
	# Away from an edge: from the right edge of column 1, or the bottom edge of row 1, outwards.
	var right: Array[Vector2i] = _touched(Vector2i(2000, 2500), Vector2i(4500, 2500))
	assert_array(right).contains_exactly_in_any_order(_row(2, 2, 4))
	var down: Array[Vector2i] = _touched(Vector2i(2500, 2000), Vector2i(2500, 4500))
	assert_array(down).contains_exactly_in_any_order(_column(2, 2, 4))
	# A sloped segment that starts on an edge of a tile is not in the tile on the other side of it.
	var sloped: Array[Vector2i] = _touched(Vector2i(2000, 2500), Vector2i(4500, 2750))
	assert_array(sloped).contains_exactly_in_any_order(_row(2, 2, 4))
	# In the rule's terms: a unit that stands next to rock is on an open tile, and a line away from
	# the rock is clear, from every point of the tile and on every edge of it. Formation hands out
	# such points as goals.
	var rock: World = _map([Vector2i(1, 2)])
	# On the right edge of the rock (the left edge of tile (2, 2)), to the right, and diagonally.
	assert_bool(_clear(rock, Vector2i(2000, 2500), Vector2i(4500, 2500))).is_true()
	assert_bool(_clear(rock, Vector2i(2000, 2500), Vector2i(4500, 4500))).is_true()
	assert_bool(_clear(rock, Vector2i(4500, 2500), Vector2i(2000, 2500))).is_true()
	# One milli to the left is on the rock.
	assert_bool(_clear(rock, Vector2i(1999, 2500), Vector2i(4500, 2500))).is_false()
	# Below the rock at (2, 0): the bottom edge of row 0 is the top edge of row 1.
	var above: World = _map([Vector2i(2, 0)])
	assert_bool(_clear(above, Vector2i(2500, 1000), Vector2i(2500, 4500))).is_true()
	assert_bool(_clear(above, Vector2i(500, 1000), Vector2i(4500, 1000))).is_true()
	assert_bool(_clear(above, Vector2i(500, 999), Vector2i(4500, 999))).is_false()
	# A goal on an edge of an open tile is reached from the tile's own centre and from itself.
	var walled: World = _map(
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(1, 3)]
	)
	for goal: Vector2i in [Vector2i(2000, 2500), Vector2i(2500, 2000), Vector2i(2000, 2000)]:
		assert_bool(_clear(walled, Vector2i(2500, 2500), goal)).is_true()
		assert_bool(_clear(walled, goal, goal)).is_true()


## A diagonal through the corners (1000, 1000), (2000, 2000) and (3000, 3000) touches the four
## tiles around each of them: the two that it crosses and the two beside it.
func test_line_clear_a_diagonal_through_a_corner_touches_the_tiles_beside_it() -> void:
	var down: Array[Vector2i] = _touched(Vector2i(500, 500), Vector2i(3500, 3500))
	(
		assert_array(down)
		. contains_exactly_in_any_order(
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
				Vector2i(2, 1),
				Vector2i(1, 2),
				Vector2i(2, 2),
				Vector2i(3, 2),
				Vector2i(2, 3),
				Vector2i(3, 3),
			]
		)
	)
	# The other diagonal, x + y = 4000, from the corner (3000, 1000) to (1000, 3000) and beyond.
	var up: Array[Vector2i] = _touched(Vector2i(3500, 500), Vector2i(500, 3500))
	(
		assert_array(up)
		. contains_exactly_in_any_order(
			[
				Vector2i(3, 0),
				Vector2i(2, 0),
				Vector2i(3, 1),
				Vector2i(2, 1),
				Vector2i(1, 1),
				Vector2i(2, 2),
				Vector2i(1, 2),
				Vector2i(0, 2),
				Vector2i(1, 3),
				Vector2i(0, 3),
			]
		)
	)


## A corner is crossed only strictly between the ends of the segment. One that ends or starts on a
## corner has no tiles beside it to touch: it is in the tile of the corner at that end.
func test_line_clear_a_diagonal_that_ends_on_a_corner_does_not_cross_it() -> void:
	var ends: Array[Vector2i] = _touched(Vector2i(500, 500), Vector2i(1000, 1000))
	assert_array(ends).contains_exactly_in_any_order([Vector2i(0, 0), Vector2i(1, 1)])
	var starts: Array[Vector2i] = _touched(Vector2i(1000, 1000), Vector2i(1500, 1500))
	assert_array(starts).contains_exactly([Vector2i(1, 1)])
	# From corner (1000, 1000) to corner (3000, 3000): the corner (2000, 2000) is crossed.
	var both: Array[Vector2i] = _touched(Vector2i(1000, 1000), Vector2i(3000, 3000))
	(
		assert_array(both)
		. contains_exactly_in_any_order(
			[
				Vector2i(1, 1),
				Vector2i(2, 1),
				Vector2i(1, 2),
				Vector2i(2, 2),
				Vector2i(3, 3),
			]
		)
	)
	# The other way up, from (1000, 3000) to (3000, 1000): the tile of the end corner is (3, 1).
	var rising: Array[Vector2i] = _touched(Vector2i(1000, 3000), Vector2i(3000, 1000))
	(
		assert_array(rising)
		. contains_exactly_in_any_order(
			[
				Vector2i(1, 3),
				Vector2i(1, 2),
				Vector2i(2, 2),
				Vector2i(2, 1),
				Vector2i(1, 1),
				Vector2i(3, 1),
			]
		)
	)


## Slopes of 1/4 and 4 cross a tile border away from a corner, and a vertical strip spans several
## rows (the second case).
func test_line_clear_shallow_and_steep_lines_touch_the_tiles_they_cross() -> void:
	# y = 500 + (x - 500) / 4: row 0 up to x = 2500, row 1 after it.
	var shallow: Array[Vector2i] = _touched(Vector2i(500, 500), Vector2i(4500, 1500))
	assert_array(shallow).contains_exactly_in_any_order(
		[
			Vector2i(0, 0),
			Vector2i(1, 0),
			Vector2i(2, 0),
			Vector2i(2, 1),
			Vector2i(3, 1),
			Vector2i(4, 1)
		]
	)
	# x = 500 + (y - 500) / 4: column 0 up to y = 2500, column 1 after it.
	var steep: Array[Vector2i] = _touched(Vector2i(500, 500), Vector2i(1500, 4500))
	assert_array(steep).contains_exactly_in_any_order(
		[
			Vector2i(0, 0),
			Vector2i(0, 1),
			Vector2i(0, 2),
			Vector2i(1, 2),
			Vector2i(1, 3),
			Vector2i(1, 4)
		]
	)


## x + y = 4000 only grazes the corner (2000, 2000) of tile (2, 2) and of tile (1, 1). One milli
## towards one of them misses it, and one milli towards the other crosses it.
func test_line_clear_a_line_that_grazes_a_blocked_tile_is_blocked() -> void:
	var upper_left: World = _map([Vector2i(1, 1)])
	var lower_right: World = _map([Vector2i(2, 2)])
	var graze_a: Vector2i = Vector2i(1000, 3000)
	var graze_b: Vector2i = Vector2i(3000, 1000)
	assert_bool(_clear(lower_right, graze_a, graze_b)).is_false()
	assert_bool(_clear(upper_left, graze_a, graze_b)).is_false()
	# x + y = 3999: misses (2, 2) by a milli and crosses (1, 1).
	var near_a: Vector2i = Vector2i(1000, 2999)
	var near_b: Vector2i = Vector2i(2999, 1000)
	assert_bool(_clear(lower_right, near_a, near_b)).is_true()
	assert_bool(_clear(upper_left, near_a, near_b)).is_false()
	# x + y = 4001: crosses (2, 2) and misses (1, 1).
	var far_a: Vector2i = Vector2i(1001, 3000)
	var far_b: Vector2i = Vector2i(3000, 1001)
	assert_bool(_clear(lower_right, far_a, far_b)).is_false()
	assert_bool(_clear(upper_left, far_a, far_b)).is_true()


## Scrub is open to foot units only, rock to nobody; each class reads its own costs.
func test_line_clear_is_per_move_class() -> void:
	var from: Vector2i = Vector2i(500, 2500)
	var to: Vector2i = Vector2i(4500, 2500)
	var scrub: World = _map([], [Vector2i(2, 2)])
	assert_bool(_clear(scrub, from, to, FOOT)).is_true()
	assert_bool(_clear(scrub, from, to, WHEELED)).is_false()
	assert_bool(_clear(scrub, from, to, TRACKED)).is_false()
	var rock: World = _map([Vector2i(2, 2)])
	for move_class: int in [FOOT, WHEELED, TRACKED]:
		assert_bool(_clear(rock, from, to, move_class)).is_false()
	# Scrub beside a diagonal corner blocks the vehicles but not the foot unit.
	var corner: World = _map([], [Vector2i(1, 0)])
	var diagonal_a: Vector2i = Vector2i(500, 500)
	var diagonal_b: Vector2i = Vector2i(3500, 3500)
	assert_bool(_clear(corner, diagonal_a, diagonal_b, FOOT)).is_true()
	assert_bool(_clear(corner, diagonal_a, diagonal_b, TRACKED)).is_false()
	# 'w' is open to foot and wheeled units, 't' to foot and tracked units: the two vehicle classes
	# read their own cost, not each other's.
	var wheels: World = GridWorld.from_rows(PackedStringArray([".....", "..w..", "....."]))
	var tracks: World = GridWorld.from_rows(PackedStringArray([".....", "..t..", "....."]))
	var along: Array[Vector2i] = [Vector2i(500, 1500), Vector2i(4500, 1500)]
	assert_bool(_clear(wheels, along[0], along[1], FOOT)).is_true()
	assert_bool(_clear(wheels, along[0], along[1], WHEELED)).is_true()
	assert_bool(_clear(wheels, along[0], along[1], TRACKED)).is_false()
	assert_bool(_clear(tracks, along[0], along[1], FOOT)).is_true()
	assert_bool(_clear(tracks, along[0], along[1], WHEELED)).is_false()
	assert_bool(_clear(tracks, along[0], along[1], TRACKED)).is_true()
	# A rock in the start tile and in the end tile blocks, a rock one tile before the end does not
	# when the segment stops short of it.
	assert_bool(_clear(_map([Vector2i(0, 2)]), from, to)).is_false()
	assert_bool(_clear(_map([Vector2i(4, 2)]), from, to)).is_false()
	assert_bool(_clear(_map([Vector2i(4, 2)]), from, Vector2i(3999, 2500))).is_true()


## Points are clamped into the grid: a segment that leaves it is read from edge to edge, and one
## that ends on the far edge ends in the last tile.
func test_line_clear_clamps_points_to_the_grid() -> void:
	var wide: Array[Vector2i] = _touched(Vector2i(-3000, 2500), Vector2i(9000, 2500))
	assert_array(wide).contains_exactly_in_any_order(_row(2, 0, 4))
	assert_bool(_clear(_map([Vector2i(4, 4)]), Vector2i(0, 0), Vector2i(5000, 5000))).is_false()
	assert_bool(_clear(_map([Vector2i(4, 4)]), Vector2i(0, 0), Vector2i(3999, 3999))).is_true()
	# The same above and below the grid: a segment wholly outside is read on the top or bottom edge.
	var above: Array[Vector2i] = _touched(Vector2i(500, -5000), Vector2i(4500, -5000))
	assert_array(above).contains_exactly_in_any_order(_row(0, 0, 4))
	var below: Array[Vector2i] = _touched(Vector2i(500, 9000), Vector2i(4500, 9000))
	assert_array(below).contains_exactly_in_any_order(_row(4, 0, 4))
	var tall: Array[Vector2i] = _touched(Vector2i(2500, -4000), Vector2i(2500, 9000))
	assert_array(tall).contains_exactly_in_any_order(_column(2, 0, 4))


## Whether the segment a-b touches tile (tx, ty) of a map of `cols` x `rows` tiles, by the
## definition and in exact integers, independent of the traversal in line_clear. The tile is the
## half-open square [tx * TILE, (tx + 1) * TILE) x [ty * TILE, (ty + 1) * TILE), closed on the far
## edge of the map, and the segment touches it when one of its points is in it. It also touches
## the four tiles around a tile corner that lies strictly between its ends, when it runs along
## neither axis.
func _touches(a: Vector2i, b: Vector2i, tx: int, ty: int, cols: int, rows: int) -> bool:
	var left: int = tx * TILE
	var top: int = ty * TILE
	var right: int = left + TILE + (1 if tx == cols - 1 else 0)
	var bottom: int = top + TILE + (1 if ty == rows - 1 else 0)
	if _has_point_in(a, b, Vector2i(left, top), Vector2i(right, bottom)):
		return true
	if a.x == b.x or a.y == b.y:
		return false
	for corner: Vector2i in [
		Vector2i(left, top),
		Vector2i(left + TILE, top),
		Vector2i(left, top + TILE),
		Vector2i(left + TILE, top + TILE)
	]:
		var along: bool = (b.x - a.x) * (corner.y - a.y) == (b.y - a.y) * (corner.x - a.x)
		if along and corner.x > mini(a.x, b.x) and corner.x < maxi(a.x, b.x):
			return true
	return false


## Whether a point of the segment a-b is in [from.x, to.x) x [from.y, to.y). The points are
## a + t * (b - a) for t in [0, 1]. Each axis allows an interval of t, from a fraction and whether
## it is open to a fraction and whether it is open; the intervals and [0, 1] meet when the
## largest start is below the smallest end, or equal to it with both ends closed.
func _has_point_in(a: Vector2i, b: Vector2i, from: Vector2i, to: Vector2i) -> bool:
	var start: Vector2i = Vector2i(0, 1)
	var start_open: bool = false
	var end: Vector2i = Vector2i(1, 1)
	var end_open: bool = false
	for axis: int in 2:
		var p: int = a.x if axis == 0 else a.y
		var d: int = (b.x - a.x) if axis == 0 else (b.y - a.y)
		var low: int = from.x if axis == 0 else from.y
		var high: int = to.x if axis == 0 else to.y
		if d == 0:
			if p < low or p >= high:
				return false
			continue
		# low <= p + t * d < high. Dividing by d < 0 swaps the ends: t > (high - p) / d from below.
		var first: Vector2i = Vector2i(low - p, d) if d > 0 else Vector2i(p - high, -d)
		var first_open: bool = d < 0
		var last: Vector2i = Vector2i(high - p, d) if d > 0 else Vector2i(p - low, -d)
		var last_open: bool = d > 0
		var start_order: int = _compare(first, start)
		if start_order > 0 or (start_order == 0 and first_open):
			start = first
			start_open = first_open
		var end_order: int = _compare(last, end)
		if end_order < 0 or (end_order == 0 and last_open):
			end = last
			end_open = last_open
	var order: int = _compare(start, end)
	return order < 0 or (order == 0 and not start_open and not end_open)


## -1, 0 or 1 as the fraction x / x.y is below, equal to or above y / y.y (both denominators > 0).
func _compare(x: Vector2i, y: Vector2i) -> int:
	return signi(x.x * y.y - y.x * x.y)


@warning_ignore("integer_division")
func test_line_clear_equals_a_geometric_oracle_on_random_maps_and_segments() -> void:
	var rng: DetRandom = DetRandom.create(37, 3)
	var wrong: Array[String] = []
	var blocked: int = 0
	var cases: int = 0
	# Wide, tall and square maps, so that a mix-up of columns and rows shows.
	for shape: Vector2i in [Vector2i(7, 6), Vector2i(4, 9), Vector2i(9, 4)]:
		var cols: int = shape.x
		var rows_n: int = shape.y
		for _map_index: int in 40:
			var rows: PackedStringArray = PackedStringArray()
			for _y: int in rows_n:
				var line: String = ""
				for _x: int in cols:
					var kind: int = rng.next_int(10)
					line += (
						"#" if kind == 0 else ("^" if kind == 1 else ("w" if kind == 2 else "."))
					)
				rows.append(line)
			var world: World = GridWorld.from_rows(rows)
			for _segment: int in 25:
				# Half of the ends on a half-tile grid, where corners and edges are hit exactly.
				var grid: int = 500 if rng.next_int(2) == 0 else 1
				var a: Vector2i = Vector2i(
					rng.next_int(cols * TILE / grid + 1) * grid,
					rng.next_int(rows_n * TILE / grid + 1) * grid
				)
				var b: Vector2i = Vector2i(
					rng.next_int(cols * TILE / grid + 1) * grid,
					rng.next_int(rows_n * TILE / grid + 1) * grid
				)
				var move_class: int = rng.next_int(3)
				var expected: bool = true
				for ty: int in rows_n:
					for tx: int in cols:
						var terrain: int = GridWorld.GROUND.find(rows[ty][tx])
						var open: bool = GridWorld.GROUND_COST[terrain * 3 + move_class] > 0
						if not open and _touches(a, b, tx, ty, cols, rows_n):
							expected = false
				cases += 1
				blocked += 0 if expected else 1
				if FixedMath.line_clear(world, a.x, a.y, b.x, b.y, move_class) != expected:
					wrong.append("%s %s class %d %s" % [a, b, move_class, str(rows)])
	assert_array(wrong).is_empty()
	# Both answers must be common, or the comparison proves little.
	assert_int(blocked).is_between(cases / 4, cases * 3 / 4)
