extends GdUnitTestSuite
## The damage patches are baked at 75 % (plan P157b, ADR 0028 section 3 amended 2026-11-03): a
## crafted sheet with a body, a shadow and `dmg1`/`dmg2` parts of 100x100 art px.

const KEY: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]
const TRIAD: PackedStringArray = ["#62D6EE", "#1FA6C8", "#137C99"]
const ART_PX: int = 100


func test_a_patch_takes_75_texels_and_a_body_stays_100() -> void:
	var atlas: IsoAtlas = IsoAtlas.build([_sheet()], [_art()], 1.0, true, _reader())
	assert_float(atlas.bake_scale()).is_equal(1.0)
	assert_that(atlas.region(&"hut", &"hull", -1).size).is_equal(Vector2i(ART_PX, ART_PX))
	assert_that(atlas.region(&"hut", &"shadow", -1).size).is_equal(Vector2i(ART_PX, ART_PX))
	for part: StringName in [&"dmg1", &"dmg2"]:
		assert_that(atlas.region(&"hut", part, -1).size).is_equal(Vector2i(75, 75))
	assert_float(atlas.part_scale(&"hull")).is_equal(1.0)
	assert_float(atlas.part_scale(&"dmg2")).is_equal(IsoAtlas.DAMAGE_SCALE)


func test_the_same_holds_at_a_lower_bake_scale() -> void:
	var atlas: IsoAtlas = IsoAtlas.build([_sheet()], [_art()], 0.5, true, _reader())
	assert_that(atlas.region(&"hut", &"hull", -1).size).is_equal(Vector2i(50, 50))
	assert_that(atlas.region(&"hut", &"dmg1", -1).size).is_equal(Vector2i(38, 38))  # 37.5 rounds.
	assert_float(atlas.part_scale(&"dmg1")).is_equal(0.375)


func test_planned_page_matches_the_bake_and_is_smaller_than_full_scale() -> void:
	var sheets: Array[IsoSheetDef] = [_sheet()]
	var arts: Array[IsoPlayerArt] = [_art()]
	var atlas: IsoAtlas = IsoAtlas.build(sheets, arts, 1.0, false, _reader())
	assert_that(IsoAtlas.planned_page(sheets, arts, 1.0, _reader())).is_equal(atlas.page_px())
	# Forty 100x100 patches need fewer rows at 75 % than at full scale.
	var canvases: Array[Vector2i] = []
	var factors: Array[float] = []
	for i: int in 40:
		canvases.append(Vector2i(ART_PX, ART_PX))
		factors.append(IsoAtlas.part_factor(&"dmg1"))
	var full: Vector2i = IsoAtlas.page_size(canvases, 1.0)
	assert_int(IsoAtlas.page_size(canvases, 1.0, factors).y).is_less(full.y)


func test_dress_sizes_a_patch_and_a_body_sprite() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.atlas = IsoAtlas.build([_sheet()], [_art()], 0.5, false, _reader())
	var sheet: IsoSheetDef = _sheet()
	var body: Sprite2D = auto_free(Sprite2D.new())
	var patch: Sprite2D = auto_free(Sprite2D.new())
	sort.dress(body, sheet, &"hull")
	sort.dress(patch, sheet, &"dmg1")
	assert_float(body.scale.x).is_equal_approx(WorldSort.ART_SCALE / 0.5, 0.0001)
	assert_float(patch.scale.x).is_equal_approx(WorldSort.ART_SCALE / 0.375, 0.0001)
	assert_that(body.offset).is_equal(-Vector2(sheet.origin(&"hull")) * 0.5)
	assert_that(patch.offset).is_equal(-Vector2(sheet.origin(&"dmg1")) * 0.375)
	# A patch texel covers the same world size as the body's art px it replaces.
	assert_float(100 * 0.375 * patch.scale.x).is_equal_approx(100 * 0.5 * body.scale.x, 0.0001)


func test_the_patch_overlap_keeps_a_texel_at_every_scale_down_to_min_scale() -> void:
	# The generator's 4 px overlap is 3 px at 75 %, 0.75 texel at MIN_SCALE.
	var overlap: float = 4.0
	var scale: float = 1.0
	while scale >= IsoAtlas.MIN_SCALE:
		var patch: int = IsoAtlas.patch_overlap_texels(overlap, scale)
		var trim: int = IsoAtlas.body_trim_texels(overlap, scale)
		assert_int(patch).is_greater_equal(1)
		# In art px: the body is trimmed by at most the overlap, the patch reaches at least it.
		assert_float(trim / scale).is_less_equal(overlap + 0.0001)
		assert_float(patch / (scale * IsoAtlas.DAMAGE_SCALE)).is_greater_equal(overlap - 0.0001)
		scale *= IsoAtlas.SCALE_STEP
	assert_int(IsoAtlas.patch_overlap_texels(overlap, IsoAtlas.MIN_SCALE)).is_equal(1)
	assert_int(IsoAtlas.body_trim_texels(overlap, IsoAtlas.MIN_SCALE)).is_equal(1)
	assert_int(IsoAtlas.patch_overlap_texels(overlap, 1.0)).is_equal(3)


func test_a_sheet_with_no_patch_is_baked_as_before() -> void:
	var sheet: IsoSheetDef = _sheet()
	sheet.parts = PackedStringArray(["hull", "shadow"])
	sheet.counts = PackedInt32Array([1, 1])
	sheet.frames = PackedInt32Array([1, 1])
	sheet.sizes = PackedInt32Array([ART_PX, ART_PX, ART_PX, ART_PX])
	sheet.anchors = PackedInt32Array([0, 0, 0, 0])
	var sheets: Array[IsoSheetDef] = [sheet]
	var atlas: IsoAtlas = IsoAtlas.build(sheets, [_art()], 1.0, true, _reader())
	assert_that(atlas.region(&"hut", &"hull", -1).size).is_equal(Vector2i(ART_PX, ART_PX))
	var factors: Array[float] = [1.0, 1.0]
	var canvases: Array[Vector2i] = [Vector2i(ART_PX, ART_PX), Vector2i(ART_PX, ART_PX)]
	assert_that(IsoAtlas.page_size(canvases, 1.0)).is_equal(
		IsoAtlas.page_size(canvases, 1.0, factors)
	)


func _sheet() -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"hut"
	sheet.faction = &"fossil"
	sheet.category = &"bld"
	sheet.footprint = 2
	sheet.parts = PackedStringArray(["hull", "shadow", "dmg1", "dmg2"])
	sheet.counts = PackedInt32Array([1, 1, 1, 1])
	sheet.frames = PackedInt32Array([1, 1, 1, 1])
	for part: int in 4:
		sheet.sizes.append_array([ART_PX, ART_PX])
		sheet.anchors.append_array([40, 60])
	return sheet


func _art() -> IsoPlayerArt:
	return IsoPlayerArt.make(&"fossil", KEY, TRIAD)


## Every frame is a distinct 100x100 canvas, so no two share a slot.
func _reader() -> Callable:
	return func(path: String) -> String:
		var grey: int = 16 + (path.hash() % 200)
		return (
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [ART_PX, ART_PX]
			+ '<rect width="%d" height="%d" fill="#%02X8080"/></svg>' % [ART_PX, ART_PX, grey]
		)
