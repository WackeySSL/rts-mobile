extends GdUnitTestSuite
## ViewScale: 64 px per tile, 1000 milli per tile (plan Phase 1, interface contracts).


func test_a_tile_is_64_px_and_matches_the_test_map() -> void:
	assert_int(ViewScale.PX_PER_TILE).is_equal(64)
	assert_int(auto_free(TestMapView.new()).tile_px).is_equal(ViewScale.PX_PER_TILE)
	assert_float(ViewScale.milli_to_px(1000)).is_equal(64.0)
	assert_that(ViewScale.milli_to_px_vec(1500, 48000)).is_equal(Vector2(96.0, 3072.0))


func test_px_to_milli_rounds_to_the_nearest_milli_tile() -> void:
	assert_int(ViewScale.px_to_milli(64.0)).is_equal(1000)
	assert_int(ViewScale.px_to_milli(1.0)).is_equal(16)  # 15.625
	assert_int(ViewScale.px_to_milli(0.4)).is_equal(6)  # 6.25


func test_round_trip_is_exact_for_every_eighth_tile_on_the_48_tile_map() -> void:
	for v: int in range(0, 48001, 125):
		var px: float = ViewScale.milli_to_px(v)
		assert_int(ViewScale.px_to_milli(px)).override_failure_message(str(v)).is_equal(v)
