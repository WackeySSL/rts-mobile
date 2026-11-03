extends GdUnitTestSuite
## The rules behind generator v4's damage patches (plan row P156, ADR 0028 sections 3 and 4): the
## cut is sound (a stage never reorders what it leaves alone), a change that does not fit the body
## is refused, a `hang` point is on the camera side, the stages a model must have, the sheet
## round trip and the char colour's key band. The moves, the patch and `root` are in
## test_artgen_damage.gd.

const BAND_DEGREES: float = 20.0  ## ADR 0023 section 5: the key band's half width.
const BAND_SATURATION: float = 0.30
const BODY: String = "box hull concrete 0 0 0 1.6 1.6 1.0"
## Three crafted bodies on which the greedy draw order of the stage, without the fix, swaps two
## primitives that the stage leaves alone (found by a search over random bodies): the rows below the
## cut then differed by 118, 139 and 155 of 255.
const REORDERS: Array[Array] = [
	[
		BODY,
		"box hull iron 0.5 -0.0 0.8 0.8 0.6 0.2",
		"box hull iron -0.5 -0.1 0.1 0.5 0.9 0.4",
		"box hull iron -0.1 0.3 0.8 0.6 0.3 0.3",
		"box hull rust 0.2 -0.0 1.0 0.3 0.3 0.3 group=c",
	],
	[
		BODY,
		"box hull olive 0.0 -0.5 0.9 0.4 0.8 0.2",
		"box hull steel 0.3 -0.5 0.3 0.4 0.8 0.3",
		"box hull concrete -0.3 0.3 0.8 0.5 0.6 0.3",
		"box hull rust -0.5 -0.1 1.0 0.3 0.3 0.3 group=c",
	],
	[
		BODY,
		"box hull rust 0.4 -0.1 0.7 0.3 0.6 0.3",
		"box hull iron 0.6 0.4 0.7 0.5 0.3 0.4",
		"box hull rust 0.6 0.5 0.7 0.3 0.8 0.2",
		"box hull rust 0.4 0.1 1.0 0.3 0.3 0.3 group=c",
	],
]


func _building(prims: Array, poses: Array) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"crafted"
	model.faction = &"fossil"
	model.category = &"bld"
	model.footprint = 2
	model.prims = PackedStringArray(prims)
	model.poses = PackedStringArray(poses)
	return model


func _vehicle(emitters: Array) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"tank"
	model.faction = &"renew"
	model.category = &"veh"
	model.prims = PackedStringArray(["box hull graphite 0 0 0 1.2 0.8 0.4"])
	model.emitters = PackedStringArray(emitters)
	return model


func test_a_stage_never_reorders_the_primitives_it_leaves_alone() -> void:
	for prims: Array in REORDERS:
		var model: ArtModel = _building(prims, ["dmg1 0 c hide", "dmg2 0 c hide"])
		assert_array(Array(model.problems())).is_empty()
		assert_int(_rows_below_cut_differ(model, 1)).override_failure_message(str(prims)).is_equal(
			0
		)
		assert_int(_rows_below_cut_differ(model, 2)).override_failure_message(str(prims)).is_equal(
			0
		)


func test_the_untouched_primitives_keep_their_intact_relative_order() -> void:
	var model: ArtModel = _building(REORDERS[0], ["dmg1 0 c hide", "dmg2 0 c hide"])
	var intact: Array[ArtPrim] = model.primitives(&"hull")
	var seen: Array[int] = ArtRender.draw_order(intact, 0.0)
	var wanted: Array[int] = []
	for at: int in seen:
		if intact[at].group == &"":
			wanted.append(intact[at].index)
	var posed: Array[ArtPrim] = model.damage_prims(1)
	var got: Array[int] = []
	for at: int in model.damage_order(1):
		got.append(posed[at].index)
	assert_array(got).is_equal(wanted)


func test_every_committed_model_with_damage_is_intact_below_its_cut() -> void:
	# Empty until P158 gives a building its poses; then it guards each stage of each model.
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		for part: StringName in model.damage_parts():
			var stage: int = ArtModel.DAMAGE_PARTS.find(part) + 1
			(
				assert_int(_rows_below_cut_differ(model, stage))
				. override_failure_message("%s %s" % [path, part])
				. is_equal(0)
			)


func test_a_change_that_does_not_fit_the_body_is_refused() -> void:
	var body: Array = ["box hull concrete 0 0 0 1.6 1.6 1.0"]
	# At the foot of the body: the patch's overlap would not fit its canvas.
	var low: ArtModel = _building(body + ["box hull iron 0.9 0.9 0 0.3 0.3 0.1 damage=1"], [])
	var problems: PackedStringArray = low.problems()
	assert_int(problems.size()).is_equal(2)  # `damage=1` shows in both stages
	for text: String in problems:
		assert_str(text).contains("a damage change reaches below the body")
	# Wholly above the body's canvas: its cut would read as "no patch".
	var high: ArtModel = _building(body + ["box hull iron 0 0 3 0.3 0.3 0.1 damage=1"], [])
	problems = high.problems()
	assert_int(problems.size()).is_equal(2)
	for text: String in problems:
		assert_str(text).contains("above the canvas of the body")
	# A move that changes nothing at its stage.
	var nothing: ArtModel = _building(
		body + ["box hull iron 0 0 1 0.3 0.3 0.1 damage=2 group=g"], ["dmg1 0 g hide"]
	)
	problems = nothing.problems()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("dmg1 changes nothing")
	# What fits is fine.
	var fine: ArtModel = _building(body + ["box hull iron 0 0 1 0.3 0.3 0.1 damage=1"], [])
	assert_array(Array(fine.problems())).is_empty()


func test_a_hang_point_is_on_the_side_that_faces_the_camera() -> void:
	var point: Vector3 = Vector3(0.2, 0.6, 0.2)
	for y: float in [0.6, -0.6]:
		var model: ArtModel = _vehicle(["damage 0 0 0.5", "hang 0.2 %s 0.2" % y])
		assert_array(Array(model.problems())).is_empty()
		var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
		assert_int(sheet.emitter_points.size()).is_equal(32)  # 16 hull frames each
		var mirrored: int = 0
		for dir: int in 16:
			# The side that faces the camera; edge-on (both sides at a right angle) either will do.
			var wanted: Array[Vector2] = []
			for s: float in [1.0, -1.0]:
				var normal: Vector3 = ArtRender.rotate(Vector3(0.0, s, 0.0), ArtGen.yaw(dir))
				if normal.dot(ArtRender.VIEW) > -1e-6:
					wanted.append(ArtGen.point_px(Vector3(point.x, s * point.y, point.z), dir))
			assert_int(wanted.size()).is_greater(0)
			var got: Vector2 = sheet.emitter_point(1, dir)
			var hit: bool = false
			for want: Vector2 in wanted:
				hit = hit or got.is_equal_approx(want.snapped(Vector2.ONE * 0.1))
				hit = hit or got.distance_to(want) < 0.12
			assert_bool(hit).override_failure_message("d%02d y %s" % [dir, y]).is_true()
			var plain: Vector2 = ArtGen.point_px(Vector3(point.x, y, point.z), dir)
			if got.distance_to(plain) > 0.12:
				mirrored += 1
		# The side turns away from the camera in about half of the sixteen frames.
		assert_int(mirrored).is_between(4, 12)
	# The damage point is not mirrored: it is on the top face, where it was put.
	var tank: ArtModel = _vehicle(["damage 0.1 0.2 0.5", "hang 0.2 0.6 0.2"])
	var sheet: IsoSheetDef = ArtSheet.of(tank, ArtGen.all_shots(tank))
	for dir: int in 16:
		assert_vector(sheet.emitter_point(0, dir)).is_equal_approx(
			ArtGen.point_px(Vector3(0.1, 0.2, 0.5), dir), Vector2.ONE * 0.11
		)


func test_the_damage_and_hang_counts_are_refused() -> void:
	var cases: Array[Array] = [
		[_vehicle(["hang 0 0.5 0", "hang 0 0.5 0.1"]), "hang is a vehicle's, one at most"],
		[_vehicle(["damage 0 0 0.5", "damage 0 0.1 0.5"]), "one damage point at most"],
		[
			_building(["box hull concrete 0 0 0 1 1 1"], []),
			"hang is a vehicle's, one at most",
		],
	]
	cases[2][0].emitters = PackedStringArray(["hang 0 0.5 0"])
	for found: Array in cases:
		var problems: PackedStringArray = (found[0] as ArtModel).problems()
		assert_int(problems.size()).override_failure_message(found[1]).is_equal(1)
		assert_str(problems[0]).contains(found[1])
	# A building has two damage points (ADR 0028 section 4).
	var building: ArtModel = _building(["box hull concrete 0 0 0 1 1 1"], [])
	building.emitters = PackedStringArray(["damage 0 0 1", "damage 0.2 0 1"])
	assert_array(Array(building.problems())).is_empty()


func test_a_stage_exists_when_a_primitive_of_an_earlier_stage_appears_in_it() -> void:
	# Only a `damage=1` primitive, no move: stage 1 shows it, and so does stage 2.
	var model: ArtModel = _building([BODY, "box hull iron 0 0 1 0.3 0.3 0.1 damage=1"], [])
	assert_array(model.damage_parts()).is_equal([&"dmg1", &"dmg2"])
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_int(sheet.cuts[0]).is_greater(0)
	assert_int(sheet.cuts[1]).is_equal(sheet.cuts[0])
	# A `damage=2` primitive is stage 2 alone.
	var late: ArtModel = _building([BODY, "box hull iron 0 0 1 0.3 0.3 0.1 damage=2"], [])
	assert_array(late.damage_parts()).is_equal([&"dmg2"])


func test_a_building_has_both_stages_or_stage_2_alone() -> void:
	var both: ArtModel = _building(
		[BODY, "box hull iron 0 0 1 0.3 0.3 0.1 group=g"], ["dmg1 0 g hide", "dmg2 0 g hide"]
	)
	assert_array(Array(both.problems())).is_empty()
	var first: ArtModel = _building(
		[BODY, "box hull iron 0 0 1 0.3 0.3 0.1 group=g"], ["dmg1 0 g hide"]
	)
	var problems: PackedStringArray = first.problems()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("dmg1 without dmg2")
	var second: ArtModel = _building(
		[BODY, "box hull iron 0 0 1 0.3 0.3 0.1 group=g"], ["dmg2 0 g hide"]
	)
	assert_array(Array(second.problems())).is_empty()


func test_the_cuts_and_the_patch_anchors_survive_a_loaded_sheet() -> void:
	var model: ArtModel = _building(
		[BODY, "box hull iron 0 0 1 0.3 0.3 0.1 group=g"], ["dmg1 0 g hide", "dmg2 0 g char 80"]
	)
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	var path: String = "user://p156_roundtrip_sheet.tres"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(ArtSheet.text(sheet))
	file.close()
	var loaded: IsoSheetDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	assert_array(Array(loaded.cuts)).is_equal(Array(sheet.cuts))
	assert_array(Array(loaded.parts)).is_equal(["hull", "dmg1", "dmg2", "shadow"])
	for part: StringName in ArtModel.DAMAGE_PARTS:
		assert_vector(Vector2(loaded.anchor(part))).is_equal(Vector2(sheet.anchor(part)))
		assert_vector(Vector2(loaded.frame_size(part))).is_equal(Vector2(sheet.frame_size(part)))
		assert_vector(Vector2(loaded.origin(part))).is_equal(Vector2(sheet.origin(part)))
	DirAccess.remove_absolute(path)


func test_char_never_enters_a_key_band() -> void:
	for faction: StringName in ArtPalette.MATERIALS:
		for material: StringName in ArtPalette.MATERIALS[faction]:
			var colours: Array[String] = []
			for level: int in 3:
				colours.append(ArtPalette.tone(faction, material, level))
			colours.append(ArtPalette.edge(faction, material, true))
			colours.append(ArtPalette.edge(faction, material, false))
			for hex: String in colours:
				for percent: int in 101:
					var mixed: String = ArtPalette.scorched(hex, percent)
					(
						assert_bool(_in_band(mixed, faction))
						. override_failure_message(
							"%s %s %d%%: %s" % [faction, material, percent, mixed]
						)
						. is_false()
					)
	assert_bool(_in_band(ArtPalette.CHAR, &"fossil")).is_false()
	assert_bool(_in_band(ArtPalette.CHAR, &"renew")).is_false()


func test_the_origin_and_anchor_of_a_patch_follow_the_body() -> void:
	var model: ArtModel = _building(
		[BODY, "box hull iron 0 0 1 0.3 0.3 0.1 group=g"], ["dmg1 0 g hide", "dmg2 0 g hide"]
	)
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	for part: StringName in ArtModel.DAMAGE_PARTS:
		var layout: ArtGen.Layout = shots[part].layout
		assert_int(layout.origin.y - layout.anchor.y).is_equal(32 * model.footprint)
		# The patch ends above the ground point: the origin lies below its canvas.
		assert_int(layout.origin.y).is_greater_equal(layout.size.y)


## The rows from the stage's cut down that differ between the intact body and the stage's picture.
func _rows_below_cut_differ(model: ArtModel, stage: int) -> int:
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var body: ArtGen.Layout = shots[&"hull"].layout
	var cut: int = shots[ArtModel.DAMAGE_PARTS[stage - 1]].cut
	var intact: Image = _image(shots[&"hull"].polys[0], body)
	var posed: Image = _image(ArtGen.stage_polys(model, stage), body)
	var rows: int = 0
	for y: int in range(cut, body.size.y):
		var differs: bool = false
		for x: int in body.size.x:
			var a: Color = intact.get_pixel(x, y)
			var b: Color = posed.get_pixel(x, y)
			differs = differs or absf(a.a - b.a) * 255.0 > 6.0
			for c: int in 3:
				differs = differs or absf(a[c] * a.a - b[c] * b.a) * 255.0 > 6.0
		rows += 1 if differs else 0
	return rows


func _image(polys: Array, layout: ArtGen.Layout) -> Image:
	var typed: Array[ArtRender.Poly] = []
	typed.assign(polys)
	var image: Image = Image.create(layout.size.x, layout.size.y, false, Image.FORMAT_RGBA8)
	image.load_svg_from_string(ArtSvg.frame("t", layout.size, layout.origin, typed), 1.0)
	return image


func _in_band(hex: String, faction: StringName) -> bool:
	var colour: Color = Color(hex)
	if colour.s < BAND_SATURATION:
		return false
	for key: String in ArtPalette.KEYS[faction]:
		var gap: float = absf(colour.h * 360.0 - Color(key).h * 360.0)
		if minf(gap, 360.0 - gap) <= BAND_DEGREES:
			return true
	return false
