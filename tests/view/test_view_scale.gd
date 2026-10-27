extends GdUnitTestSuite
## ViewScale: 1000 milli per tile and a length along a tile's width of 64 px per tile. Positions
## moved to IsoProjection (P117, ADR 0023 section 1); this pins that the two agree on the tile.


func test_a_tile_is_1000_milli_and_64_px_wide() -> void:
	assert_int(ViewScale.MILLI_PER_TILE).is_equal(1000)
	assert_int(ViewScale.PX_PER_TILE).is_equal(64)
	assert_float(ViewScale.milli_to_px(1000)).is_equal(64.0)
	assert_float(ViewScale.milli_to_px(1)).is_equal_approx(0.064, 0.0001)  # Not whole px.
	assert_float(ViewScale.milli_to_px(48000)).is_equal(3072.0)


func test_the_diamond_of_a_tile_is_as_wide_as_the_scalar_tile_width() -> void:
	# One tile along +x and then along -y spans the width of the tile's diamond (ground (1, 0)
	# to (0, 1)), the figure the scalar helper keeps.
	var across: float = (
		IsoProjection.ground_to_px(ViewScale.MILLI_PER_TILE, 0).x
		- IsoProjection.ground_to_px(0, ViewScale.MILLI_PER_TILE).x
	)
	assert_float(across).is_equal(ViewScale.milli_to_px(ViewScale.MILLI_PER_TILE))


func test_map_view_draws_the_map_as_its_diamond_and_the_far_corner_is_where_a_unit_stands() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(3, 2)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = scenario
	runner.start()
	var map_view: MapView = auto_free(MapView.new())
	map_view.runner = runner
	add_child(map_view)
	await await_idle_frame()
	# The rect is in cells, under the cell transform: its far corner is the milli point (3000, 2000).
	assert_that(map_view.drawn_rect()).is_equal(Rect2(0, 0, 3, 2))
	assert_that(IsoProjection.cell_to_px() * map_view.drawn_rect().end).is_equal(
		IsoProjection.ground_to_px(3000, 2000)
	)
	assert_that(IsoProjection.ground_to_px(3000, 2000)).is_equal(Vector2(32.0, 80.0))
