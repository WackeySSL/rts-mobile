extends GdUnitTestSuite
## The wall band of the sorted page (ADR 0053 amendment A5 and A6, plan P656d2): the pieces packed
## lit and dim under every sheet's frames, within the row cap, with the placeholder pieces of
## `wall_rig.gd` (the real art is P656d4's).

const Rig: GDScript = preload("res://tests/view/support/wall_rig.gd")
const SHADE: int = 140


func test_the_band_holds_every_piece_lit_and_dim_within_the_row_cap() -> void:
	var atlas: IsoAtlas = IsoAtlas.build([], [], 1.0, true, Callable(), Rig.pieces(), SHADE)
	assert_int(atlas.wall_band_rows()).is_between(1, IsoAtlas.WALL_BAND_ROWS_MAX)
	assert_int(atlas.image().get_height()).is_equal(atlas.wall_band_rows())
	for key: StringName in WallKit.all_keys():
		for dim: bool in [false, true]:
			var region: Rect2i = atlas.wall_region(key, dim)
			assert_that(region.size).is_equal(TerrainKitDef.WALL_CANVAS)
			assert_bool(Rect2i(Vector2i.ZERO, atlas.image().get_size()).encloses(region)).is_true()
	assert_bool(atlas.wall_region(&"rock/wall_top/9", false).has_area()).is_false()


func test_a_lit_region_is_the_piece_and_a_dim_one_has_the_fogs_black_over_it() -> void:
	var pieces: Dictionary[StringName, Image] = Rig.pieces()
	var key: StringName = WallKit.all_keys()[4]
	var want: Color = pieces[key].get_pixel(10, 10)
	var atlas: IsoAtlas = IsoAtlas.build([], [], 1.0, true, Callable(), pieces, SHADE)
	var lit: Rect2i = atlas.wall_region(key, false)
	var dim: Rect2i = atlas.wall_region(key, true)
	assert_that(atlas.image().get_pixel(lit.position.x + 10, lit.position.y + 10)).is_equal(want)
	var got: Color = atlas.image().get_pixel(dim.position.x + 10, dim.position.y + 10)
	var factor: float = 1.0 - SHADE / 255.0
	assert_float(float(got.r8)).is_equal_approx(float(want.r8) * factor, 2.0)
	assert_float(float(got.g8)).is_equal_approx(float(want.g8) * factor, 2.0)
	assert_float(float(got.b8)).is_equal_approx(float(want.b8) * factor, 2.0)
	assert_int(got.a8).is_equal(255)


func test_the_band_sits_under_the_sources_and_moves_none_of_their_regions() -> void:
	var sources: Dictionary[StringName, Image] = {}
	for name: String in ["a", "b", "c"]:
		sources[StringName(name)] = Image.create(
			300, 90 + name.unicode_at(0), false, Image.FORMAT_RGBA8
		)
	var plain: RuntimeAtlas = RuntimeAtlas.build_images(sources.duplicate(), 4096, true)
	var band: Dictionary[StringName, Image] = IsoAtlas.wall_band(Rig.pieces(), SHADE)
	var banded: RuntimeAtlas = RuntimeAtlas.build_images(sources.duplicate(), 4096, true, band)
	var below: int = plain.image().get_height()
	for key: StringName in sources:
		assert_that(banded.region(key)).is_equal(plain.region(key))
	for key: StringName in band:
		assert_int(banded.region(key).position.y).is_greater_equal(below)
	assert_int(banded.image().get_height() - below).is_equal(IsoAtlas.band_rows(band))


func test_a_page_that_leaves_no_room_for_the_band_lowers_the_scale() -> void:
	var canvases: Array[Vector2i] = []
	for at: int in 40:
		canvases.append(Vector2i(400, 400))
	var plain: float = IsoAtlas.fit_scale(canvases, 1.0)
	var reserved: float = IsoAtlas.fit_scale(canvases, 1.0, [], [], IsoAtlas.WALL_BAND_ROWS_MAX)
	assert_float(reserved).is_less_equal(plain)
	var page: Vector2i = IsoAtlas.page_size(canvases, reserved)
	assert_int(page.y + IsoAtlas.WALL_BAND_ROWS_MAX).is_less_equal(IsoAtlas.PAGE_MAX_PX)


func test_the_cross_faction_page_and_the_band_stay_inside_the_budget() -> void:
	var cross: int = 2756  # `test_iso_atlas_budget.gd`'s TODAY_CROSS.
	assert_int(cross + IsoAtlas.WALL_BAND_ROWS_MAX).is_less_equal(3584)
	# 2756 + the cap of 288 is 3044; the stone set's real band is 280 rows, so 3036.
	assert_int(cross + IsoAtlas.WALL_BAND_ROWS_MAX).is_equal(3044)
