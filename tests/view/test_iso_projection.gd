extends GdUnitTestSuite
## IsoProjection (P117, ADR 0023 section 1): the 2:1 formulas, the inverse that rounds to milli, the
## cell centres a diamond TileMapLayer agrees with, the ground ellipse, the map's diamond, the fog's
## cell transform, the angle of a ground vector on screen and the clamp into the diamond.

const MILLI: int = 1000
## Crafted ground points in milli: the four quadrants round the origin, the corners and edge
## midpoints of a 64 x 64 map, off-map points (a tap in the void) and a few odd values.
const POINTS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(1500, 48000),
	Vector2i(48000, 1500),
	Vector2i(-300, 700),
	Vector2i(700, -300),
	Vector2i(-4000, -9000),
	Vector2i(64000, 0),
	Vector2i(0, 64000),
	Vector2i(64000, 64000),
	Vector2i(32000, 0),
	Vector2i(0, 32000),
	Vector2i(64000, 32000),
	Vector2i(32000, 64000),
	Vector2i(12345, 54321),
	Vector2i(63999, 1),
	Vector2i(70000, 70000),
]


func test_the_formula_puts_one_tile_along_each_axis_on_the_2_to_1_diamond() -> void:
	assert_that(IsoProjection.ground_to_px(0, 0)).is_equal(Vector2(0, 0))
	assert_that(IsoProjection.ground_to_px(MILLI, 0)).is_equal(Vector2(32, 16))
	assert_that(IsoProjection.ground_to_px(0, MILLI)).is_equal(Vector2(-32, 16))
	assert_that(IsoProjection.ground_to_px(MILLI, MILLI)).is_equal(Vector2(0, 32))
	assert_that(IsoProjection.ground_to_px(1500, 48000)).is_equal(Vector2(-1488, 792))
	assert_that(IsoProjection.ground_to_px(-3000, -1000)).is_equal(Vector2(-64, -64))
	# A milli is not a whole px: the result is not rounded.
	assert_vector(IsoProjection.ground_to_px(1, 0)).is_equal_approx(
		Vector2(0.032, 0.016), Vector2(0.0001, 0.0001)
	)


func test_the_inverse_gives_back_every_crafted_point_exactly() -> void:
	for ground: Vector2i in POINTS:
		var px: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
		assert_that(IsoProjection.px_to_ground(px)).override_failure_message(str(ground)).is_equal(
			ground
		)


func test_the_round_trip_is_within_one_milli_over_a_sweep_of_a_64_tile_map() -> void:
	var worst: int = 0
	for x: int in range(-3000, 67000, 1901):
		for y: int in range(-3000, 67000, 2003):
			var back: Vector2i = IsoProjection.px_to_ground(IsoProjection.ground_to_px(x, y))
			worst = maxi(worst, maxi(absi(back.x - x), absi(back.y - y)))
	assert_int(worst).is_less_equal(1)


func test_the_inverse_rounds_to_the_nearest_milli() -> void:
	# One px across is 15.625 milli on each axis, one px down is 31.25 milli on each.
	assert_that(IsoProjection.px_to_ground(Vector2(1, 0))).is_equal(Vector2i(16, -16))
	assert_that(IsoProjection.px_to_ground(Vector2(0.4, 0))).is_equal(Vector2i(6, -6))
	assert_that(IsoProjection.px_to_ground(Vector2(0, 1))).is_equal(Vector2i(31, 31))
	assert_that(IsoProjection.px_to_ground(Vector2(0, 0.5))).is_equal(Vector2i(16, 16))
	assert_that(IsoProjection.px_to_ground(Vector2(-1, 0))).is_equal(Vector2i(-16, 16))
	assert_that(IsoProjection.px_to_ground(Vector2(32, 16))).is_equal(Vector2i(MILLI, 0))


func test_a_cell_centre_is_the_middle_of_its_diamond_and_a_tile_layers_map_to_local() -> void:
	var tiles: TileSet = TileSet.new()
	tiles.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tiles.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tiles.tile_size = Vector2i(64, 32)
	var layer: TileMapLayer = auto_free(TileMapLayer.new())
	layer.tile_set = tiles
	layer.position = IsoProjection.TILE_LAYER_OFFSET
	for cell: Vector2i in [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(10, 7),
		Vector2i(63, 0),
		Vector2i(0, 63),
		Vector2i(63, 63),
		Vector2i(21, 40),
	]:
		var centre: Vector2 = IsoProjection.cell_centre_px(cell.x, cell.y)
		(
			assert_that(layer.position + layer.map_to_local(cell))
			. override_failure_message(str(cell))
			. is_equal(centre)
		)
		# The middle of the diamond: the ground point (col + 0.5, row + 0.5).
		var ground: Vector2 = Vector2(cell) * MILLI + Vector2(500, 500)
		assert_that(IsoProjection.ground_to_px(int(ground.x), int(ground.y))).is_equal(centre)
		assert_that(layer.local_to_map(centre - layer.position)).is_equal(cell)


func test_a_ground_circle_is_a_2_to_1_ellipse_with_the_documented_semi_axes() -> void:
	var semi: Vector2 = IsoProjection.ellipse_px(MILLI)
	assert_float(semi.x).is_equal_approx(32.0 * sqrt(2.0), 0.0001)
	assert_float(semi.y).is_equal_approx(16.0 * sqrt(2.0), 0.0001)
	assert_float(semi.x / semi.y).is_equal_approx(2.0, 0.0000001)
	# What a flat shape on the ground keeps of its height (the markers' chevrons and diamond): the
	# ellipse's ratio, half.
	assert_float(IsoProjection.GROUND_FLATTEN).is_equal(0.5)
	assert_float(IsoProjection.GROUND_FLATTEN).is_equal_approx(semi.y / semi.x, 0.0000001)
	assert_that(IsoProjection.ellipse_px(0)).is_equal(Vector2.ZERO)
	assert_float(IsoProjection.ellipse_px(2500).x).is_equal_approx(2.5 * semi.x, 0.0001)
	# Points of the ground circle of radius 4 tiles land on that ellipse, whatever the angle.
	var radius: int = 4 * MILLI
	var ring: Vector2 = IsoProjection.ellipse_px(radius)
	var centre: Vector2 = IsoProjection.ground_to_px(10 * MILLI, 10 * MILLI)
	for step: int in 16:
		var turn: float = TAU * step / 16.0
		var at: Vector2 = IsoProjection.ground_to_px(
			10 * MILLI + roundi(cos(turn) * radius), 10 * MILLI + roundi(sin(turn) * radius)
		)
		var offset: Vector2 = (at - centre) / ring
		assert_float(offset.length()).override_failure_message(str(step)).is_equal_approx(
			1.0, 0.001
		)


func test_the_map_diamond_runs_clockwise_from_the_top_corner() -> void:
	var square: PackedVector2Array = IsoProjection.map_diamond(64, 64)
	assert_array(square).contains_exactly(
		[Vector2(0, 0), Vector2(2048, 1024), Vector2(0, 2048), Vector2(-2048, 1024)]
	)
	# A 64 x 64 map is a 4096 x 2048 px diamond (ADR 0023 section 4).
	assert_that(IsoProjection.map_bounds(64, 64)).is_equal(Rect2(-2048, 0, 4096, 2048))
	var wide: PackedVector2Array = IsoProjection.map_diamond(6, 2)
	assert_array(wide).contains_exactly(
		[Vector2(0, 0), Vector2(192, 96), Vector2(128, 128), Vector2(-64, 32)]
	)
	assert_that(IsoProjection.map_bounds(6, 2)).is_equal(Rect2(-64, 0, 256, 128))
	assert_int(IsoProjection.map_diamond(0, 5).size()).is_equal(0)
	assert_int(IsoProjection.map_diamond(5, -1).size()).is_equal(0)


func test_map_bounds_is_the_bounding_rect_of_the_diamond_for_any_size() -> void:
	for size: Vector2i in [Vector2i(1, 1), Vector2i(3, 2), Vector2i(48, 48), Vector2i(2, 64)]:
		var rect: Rect2 = Rect2(IsoProjection.map_diamond(size.x, size.y)[0], Vector2.ZERO)
		for corner: Vector2 in IsoProjection.map_diamond(size.x, size.y):
			rect = rect.expand(corner)
		assert_that(IsoProjection.map_bounds(size.x, size.y)).is_equal(rect)


func test_cell_to_px_turns_a_texel_into_its_diamond() -> void:
	var transform: Transform2D = IsoProjection.cell_to_px()
	assert_that(transform.x).is_equal(Vector2(32, 16))
	assert_that(transform.y).is_equal(Vector2(-32, 16))
	assert_that(transform.origin).is_equal(Vector2.ZERO)
	# The texel corners are ground corners, and the texture's four corners are the map's diamond.
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(47, 1), Vector2i(2, 48)]:
		assert_that(transform * Vector2(cell)).is_equal(
			IsoProjection.ground_to_px(cell.x * MILLI, cell.y * MILLI)
		)
	var corners: PackedVector2Array = IsoProjection.map_diamond(48, 30)
	assert_that(transform * Vector2(0, 0)).is_equal(corners[0])
	assert_that(transform * Vector2(48, 0)).is_equal(corners[1])
	assert_that(transform * Vector2(48, 30)).is_equal(corners[2])
	assert_that(transform * Vector2(0, 30)).is_equal(corners[3])


func test_screen_angle_is_the_angle_of_the_projected_vector() -> void:
	for ground: Vector2i in [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
		Vector2i(-3, 2),
		Vector2i(7, 1),
		Vector2i(-2, -9),
	]:
		var along: Vector2 = IsoProjection.ground_to_px(ground.x * MILLI, ground.y * MILLI)
		(
			assert_float(IsoProjection.screen_angle(ground.x, ground.y))
			. override_failure_message(str(ground))
			. is_equal_approx(along.angle(), 0.0001)
		)
	# Grid +x runs down and right (a 2:1 slope), grid +y down and left, +x +y straight down.
	assert_float(IsoProjection.screen_angle(1.0, 0.0)).is_equal_approx(atan2(16.0, 32.0), 0.0001)
	assert_float(IsoProjection.screen_angle(0.0, 1.0)).is_equal_approx(atan2(16.0, -32.0), 0.0001)
	assert_float(IsoProjection.screen_angle(1.0, 1.0)).is_equal_approx(PI / 2.0, 0.0001)


func test_the_clamp_leaves_every_point_of_the_diamond_where_it_is() -> void:
	var diamond: PackedVector2Array = IsoProjection.map_diamond(64, 64)
	var inside: Array[Vector2] = [Vector2(0, 1024), Vector2(-1000, 700), Vector2(1000, 1200)]
	inside.append_array(diamond)
	for point: Vector2 in inside:
		(
			assert_that(IsoProjection.clamp_to_diamond(point, diamond))
			. override_failure_message(str(point))
			. is_equal_approx(point, Vector2(0.001, 0.001))
		)


func test_the_clamp_pulls_an_outside_point_to_the_nearest_edge_along_the_grid_axes() -> void:
	var diamond: PackedVector2Array = IsoProjection.map_diamond(64, 64)
	# Beyond each tip, the tip itself.
	assert_vector(IsoProjection.clamp_to_diamond(Vector2(0, -900), diamond)).is_equal_approx(
		diamond[0], Vector2(0.001, 0.001)
	)
	assert_vector(IsoProjection.clamp_to_diamond(Vector2(9000, 1024), diamond)).is_equal_approx(
		diamond[1], Vector2(0.001, 0.001)
	)
	assert_vector(IsoProjection.clamp_to_diamond(Vector2(0, 9000), diamond)).is_equal_approx(
		diamond[2], Vector2(0.001, 0.001)
	)
	assert_vector(IsoProjection.clamp_to_diamond(Vector2(-9000, 1024), diamond)).is_equal_approx(
		diamond[3], Vector2(0.001, 0.001)
	)
	# Beside the north-west edge (ground x < 0) the point keeps its ground y and loses its x.
	var beside: Vector2 = IsoProjection.ground_to_px(-5000, 20000)
	var held: Vector2i = IsoProjection.px_to_ground(IsoProjection.clamp_to_diamond(beside, diamond))
	assert_that(held).is_equal(Vector2i(0, 20000))
	# Past the south-east edge (ground x > map) likewise, and past the north-east one (y < 0).
	var east: Vector2 = IsoProjection.ground_to_px(70000, 10000)
	assert_that(IsoProjection.px_to_ground(IsoProjection.clamp_to_diamond(east, diamond))).is_equal(
		Vector2i(64000, 10000)
	)
	var north: Vector2 = IsoProjection.ground_to_px(30000, -8000)
	(
		assert_that(IsoProjection.px_to_ground(IsoProjection.clamp_to_diamond(north, diamond)))
		. is_equal(Vector2i(30000, 0))
	)


func test_the_clamp_is_idempotent_and_ignores_an_empty_diamond() -> void:
	var diamond: PackedVector2Array = IsoProjection.map_diamond(6, 2)
	for point: Vector2 in [Vector2(500, 500), Vector2(-700, -20), Vector2(33, 7), Vector2(0, 90)]:
		var once: Vector2 = IsoProjection.clamp_to_diamond(point, diamond)
		assert_vector(IsoProjection.clamp_to_diamond(once, diamond)).is_equal_approx(
			once, Vector2(0.001, 0.001)
		)
		var ground: Vector2i = IsoProjection.px_to_ground(once)
		assert_int(ground.x).is_between(0, 6 * MILLI)
		assert_int(ground.y).is_between(0, 2 * MILLI)
	var none: PackedVector2Array = PackedVector2Array()
	assert_that(IsoProjection.clamp_to_diamond(Vector2(123, -45), none)).is_equal(Vector2(123, -45))
