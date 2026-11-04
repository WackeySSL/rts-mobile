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


func test_dress_draws_every_part_over_its_canvas_at_odd_sizes_and_scales() -> void:
	for scale: float in [1.0, 0.5, 0.875]:
		var sheet: IsoSheetDef = _sheet({&"hull": Vector2i(101, 71), &"dmg1": Vector2i(102, 70)})
		var sort: WorldSort = auto_free(WorldSort.new())
		sort.atlas = IsoAtlas.build([sheet], [_art()], scale, false, _reader(sheet))
		assert_float(sort.atlas.bake_scale()).is_equal(scale)
		for part: StringName in [&"hull", &"dmg1", &"shadow"]:
			var sprite: Sprite2D = auto_free(Sprite2D.new())
			sort.dress(sprite, sheet, part)
			sort.show_frame(sprite, sheet, part, -1, 1)
			var canvas: Vector2 = Vector2(sheet.frame_size(part))
			var drawn: Vector2 = (sprite.offset + Vector2(sprite.region_rect.size)) * sprite.scale
			var want: Vector2 = (canvas - Vector2(sheet.origin(part))) * WorldSort.ART_SCALE
			(
				assert_vector(drawn)
				. override_failure_message("%s at %s" % [part, scale])
				. is_equal_approx(want, Vector2(0.001, 0.001))
			)
			assert_float(-sprite.offset.x * sprite.scale.x).is_equal_approx(
				sheet.origin(part).x * WorldSort.ART_SCALE, 0.001
			)


func test_the_pose_offsets_and_the_ghost_anim_agree_with_dress_below_scale_1() -> void:
	var sheet: IsoSheetDef = _sheet(
		{&"hull": Vector2i(101, 71), &"walk": Vector2i(101, 71), &"idle": Vector2i(101, 71)}
	)
	sheet.art_id = &"squad"
	sheet.stride_milli = 1000
	sheet.frames = PackedInt32Array([1, 4, 2, 1])
	sheet.footprint = 0
	var building: IsoSheetDef = _sheet({&"hull": Vector2i(103, 73), &"anim": Vector2i(51, 33)})
	building.art_id = &"mast"
	var sheets: Array[IsoSheetDef] = [sheet, building]
	for scale: float in [1.0, 0.875]:
		var sort: WorldSort = auto_free(WorldSort.new())
		sort.atlas = IsoAtlas.build(sheets, [_art()], scale, false, _reader(sheet, building))
		var pose: RigLife.Pose = RigLife.Pose.new()
		assert_bool(pose.dress(sheet, sort.atlas.bake_scale())).is_true()
		for index: int in RigLife.POSE_PARTS.size():
			var part: StringName = RigLife.POSE_PARTS[index]
			var sprite: Sprite2D = auto_free(Sprite2D.new())
			sort.dress(sprite, sheet, part)
			assert_vector(pose.offsets[index]).is_equal_approx(sprite.offset, Vector2(1e-4, 1e-4))
		var body: Sprite2D = auto_free(Sprite2D.new())
		var live: Sprite2D = auto_free(Sprite2D.new())
		sort.dress(live, building, &"anim")
		sort.dress(body, building, &"hull")
		BuildingAnims.dress_ghost(body, sort, building, 1)
		var child: Sprite2D = body.get_child(0) as Sprite2D
		assert_object(child).is_not_null()
		auto_free(child)
		var ghost_scale: Vector2 = body.scale * child.scale
		assert_vector(ghost_scale).is_equal_approx(live.scale, Vector2(1e-4, 1e-4))
		assert_vector(child.offset * ghost_scale).is_equal_approx(
			live.offset * live.scale, Vector2(1e-3, 1e-3)
		)


func test_a_patch_canvas_taller_than_a_body_but_raster_shorter_packs_after_it() -> void:
	var sheet: IsoSheetDef = _sheet({&"hull": Vector2i(100, 100), &"dmg1": Vector2i(100, 120)})
	var atlas: IsoAtlas = IsoAtlas.build([sheet], [_art()], 1.0, true, _reader(sheet))
	var body: Rect2i = atlas.region(&"hut", &"hull", -1)
	var patch: Rect2i = atlas.region(&"hut", &"dmg1", -1)
	assert_int(patch.size.y).is_equal(90)
	assert_that(body.position).is_equal(Vector2i(RuntimeAtlas.GUTTER_PX, RuntimeAtlas.GUTTER_PX))
	assert_int(patch.position.x).is_greater(body.position.x)


func test_planned_page_follows_the_factor_when_the_patches_set_the_shelf() -> void:
	var sheet: IsoSheetDef = _sheet(
		{&"hull": Vector2i(50, 50), &"dmg1": Vector2i(100, 100), &"shadow": Vector2i(50, 50)}
	)
	var sheets: Array[IsoSheetDef] = [sheet]
	var arts: Array[IsoPlayerArt] = [_art()]
	for scale: float in [1.0, 0.5]:
		var atlas: IsoAtlas = IsoAtlas.build(sheets, arts, scale, false, _reader(sheet))
		var planned: Vector2i = IsoAtlas.planned_page(sheets, arts, scale, _reader(sheet))
		assert_that(planned).is_equal(atlas.page_px())
	var flat: Array[Vector2i] = [Vector2i(100, 100)]
	assert_int(IsoAtlas.planned_page(sheets, arts, 1.0, _reader(sheet)).y).is_equal(
		IsoAtlas.page_size(flat, 1.0, [IsoAtlas.DAMAGE_SCALE] as Array[float]).y
	)


func test_a_set_that_fits_only_because_of_the_factor_keeps_the_scale() -> void:
	var canvases: Array[Vector2i] = [
		Vector2i(2100, 1100), Vector2i(2100, 1100), Vector2i(2100, 1100), Vector2i(2100, 1100)
	]
	var factors: Array[float] = [0.75, 0.75, 0.75, 0.75]
	assert_float(IsoAtlas.fit_scale(canvases, 1.0)).is_less(1.0)
	assert_float(IsoAtlas.fit_scale(canvases, 1.0, factors)).is_equal(1.0)
	var sheet: IsoSheetDef = _sheet({&"hull": Vector2i(8, 8), &"dmg1": Vector2i(2100, 1100)})
	sheet.parts = PackedStringArray(["hull", "dmg1", "dmg2"])
	sheet.counts = PackedInt32Array([1, 1, 1])
	sheet.frames = PackedInt32Array([1, 1, 1])
	sheet.sizes = PackedInt32Array([8, 8, 2100, 1100, 2100, 1100])
	sheet.anchors = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var players: Array[IsoPlayerArt] = [_art(), _art()]
	var atlas: IsoAtlas = IsoAtlas.build([sheet], players, 1.0, false, _reader(sheet))
	assert_float(atlas.bake_scale()).is_equal(1.0)


func test_a_patch_region_is_the_rounded_raster_of_its_canvas() -> void:
	for height: int in [99, 100, 101, 102]:
		for scale: float in [1.0, 0.875, 0.5]:
			var sheet: IsoSheetDef = _sheet({&"dmg1": Vector2i(height, height)})
			var atlas: IsoAtlas = IsoAtlas.build([sheet], [_art()], scale, true, _reader(sheet))
			var cell: Vector2i = IsoAtlas.page_size(
				[Vector2i(height, height)] as Array[Vector2i],
				scale,
				[IsoAtlas.DAMAGE_SCALE] as Array[float]
			)
			var got: int = atlas.region(&"hut", &"dmg1", -1).size.y
			assert_int(got).is_equal(roundi(height * scale * IsoAtlas.DAMAGE_SCALE))
			assert_int(got).is_less_equal(cell.y - 2 * RuntimeAtlas.GUTTER_PX)


func test_only_the_two_damage_parts_have_a_factor() -> void:
	for part: StringName in [&"dmg", &"dmg10", &"dmg3", &"dmg1x", &"scar1", &"loose", &"anim"]:
		assert_float(IsoAtlas.part_factor(part)).is_equal(1.0)
	assert_float(IsoAtlas.part_factor(&"dmg1")).is_equal(0.75)
	assert_float(IsoAtlas.part_factor(&"dmg2")).is_equal(0.75)


func test_body_cut_row_is_the_integer_ceil() -> void:
	assert_int(IsoAtlas.body_cut_row(4, 100, 100)).is_equal(4)
	assert_int(IsoAtlas.body_cut_row(4, 100, 25)).is_equal(1)  # 1.0 exactly.
	assert_int(IsoAtlas.body_cut_row(5, 100, 25)).is_equal(2)  # 1.25 rounds up.
	assert_int(IsoAtlas.body_cut_row(0, 100, 50)).is_equal(0)
	assert_int(IsoAtlas.body_cut_row(60, 101, 51)).is_equal(31)  # 30.3 rounds up.


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


## A crafted building: a hull, a shadow and the patches, each `ART_PX` square unless `sizes` says.
func _sheet(sizes: Dictionary = {}) -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"hut"
	sheet.faction = &"fossil"
	sheet.category = &"bld"
	sheet.footprint = 2
	var names: Array[StringName] = [&"hull", &"shadow", &"dmg1", &"dmg2"]
	if not sizes.is_empty():
		names = []
		for part: StringName in sizes:
			names.append(part)
		if not names.has(&"shadow"):
			names.append(&"shadow")
	var parts: PackedStringArray = PackedStringArray()
	for part: StringName in names:
		parts.append(part)
		var size: Vector2i = sizes.get(part, Vector2i(ART_PX, ART_PX))
		sheet.sizes.append_array([size.x, size.y])
		sheet.anchors.append_array([40, 60])
	sheet.parts = parts
	sheet.counts = PackedInt32Array()
	sheet.frames = PackedInt32Array()
	for part: int in names.size():
		sheet.counts.append(1)
		sheet.frames.append(1)
	return sheet


func _art() -> IsoPlayerArt:
	return IsoPlayerArt.make(&"fossil", KEY, TRIAD)


## Every frame is an SVG of its canvas size, distinct per file so no two frames share a slot.
func _reader(sheet: IsoSheetDef = null, other: IsoSheetDef = null) -> Callable:
	var sheet_def: IsoSheetDef = sheet if sheet != null else _sheet()
	return func(path: String) -> String:
		var size: Vector2i = Vector2i(ART_PX, ART_PX)
		for def: IsoSheetDef in [sheet_def, other]:
			if def == null or not path.contains(String(def.art_id)):
				continue
			for part: String in def.parts:
				if path.get_file().contains(part):
					size = def.frame_size(StringName(part))
		var grey: int = 16 + (path.hash() % 200)
		return (
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [size.x, size.y]
			+ '<rect width="%d" height="%d" fill="#%02X8080"/></svg>' % [size.x, size.y, grey]
		)
