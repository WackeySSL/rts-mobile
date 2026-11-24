extends GdUnitTestSuite
## The generator features of P630 (ADR 0050 section 1) that change no output: the macro lines
## (tracks, wheels, grille, hatch, pylon), the per-primitive `detail=` and the face decals.


func _model(prims: Array[String], decals: Array[String] = []) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"p630_test"
	model.faction = &"fossil"
	model.category = &"veh"
	model.prims = PackedStringArray(prims)
	model.decals = PackedStringArray(decals)
	return model


func test_each_macro_expands_to_valid_primitives_with_its_own_keys() -> void:
	var lines: Dictionary[String, int] = {
		"tracks hull iron 0 -0.4 0 1.2 0.2 0.2": 6,
		"wheels hull iron 0 0 0 1 0.8 0.2 n=3": 6,
		"grille hull steel 0 0 0.3 0.4 0.3 0.1 bars=3": 4,
		"hatch hull steel 0 0 0.3 0.2 0.2 0.1": 2,
		"pylon hull steel 0 0 0 0.3 0.3 0.6": 3,
	}
	for line: String in lines:
		var found: Array[ArtPrim] = ArtPrim.parse_all(line)
		assert_int(found.size()).override_failure_message(line).is_equal(lines[line])
		var keys: Dictionary[int, bool] = {}
		for prim: ArtPrim in found:
			keys[prim.key()] = true
			assert_str(prim.label()).is_equal(line)
		assert_int(keys.size()).is_equal(found.size())


func test_a_macro_passes_group_damage_and_detail_to_every_primitive() -> void:
	var found: Array[ArtPrim] = ArtPrim.parse_all(
		"tracks hull iron 0 0 0 1 0.2 0.2 wheels=3 group=left detail=2"
	)
	assert_int(found.size()).is_equal(4)
	for prim: ArtPrim in found:
		assert_str(String(prim.group)).is_equal("left")
		assert_int(prim.detail).is_equal(2)


func test_a_bad_macro_expands_to_nothing() -> void:
	for line: String in [
		"tracks hull iron 0 0 0 1 0.2 0.2 wheels=1",
		"tracks hull iron 0 0 0 1 0.2 0.2 bars=3",
		"tracks hull iron 0 0 0 1 0.2",
		"tracks hull iron 0 0 0 1 0.2 -0.2",
		"hatch hull steel 0 0 0 0.2 0.3 0.1",
		"wheels hull iron 0 0 0 1 0.8 0.2 w=0.5",
		"grille hull steel 0 0 0 1 1 0.1 bars=40",
		"pylon hull steel 0 0 0 1 1 1 taper=0",
		"tracks tail iron 0 0 0 1 0.2 0.2",
		"tracks hull iron 0 0 0 1 0.2 0.2 group=a group=b",
	]:
		assert_int(ArtPrim.parse_all(line).size()).override_failure_message(line).is_equal(0)


func test_problems_cover_the_macro_materials_and_the_decals() -> void:
	var good: Array[String] = ["tracks hull iron 0 0 0 1 0.2 0.2 wheel=steel"]
	assert_array(_model(good).problems()).is_empty()
	var bad_material: Array[String] = ["tracks hull iron 0 0 0 1 0.2 0.2 wheel=nosuch"]
	assert_array(_model(bad_material).problems()).is_not_empty()
	var box: Array[String] = ["box hull steel 0 0 0 1 1 0.2", "rod hull iron 0 0 0 1 0 0 3"]
	assert_array(_model(box, ["number 0 top 0.5 0.5 0.3 n=7"]).problems()).is_empty()
	for decal: String in [
		"number 0 top 0.5 0.5 0.3",
		"hazard 0 top 0.5 0.5 0.3 n=7",
		"vent 0 side 0.5 0.5 0.3",
		"vent 0 top 1.5 0.5 0.3",
		"vent 0 top 0.5 0.5 0",
		"vent 5 top 0.5 0.5 0.3",
		"vent 1 top 0.5 0.5 0.3",
	]:
		assert_array(_model(box, [decal]).problems()).override_failure_message(decal).is_not_empty()


func test_detail_is_a_level_from_0_to_3() -> void:
	assert_int(ArtPrim.parse("box hull steel 0 0 0 1 1 1 detail=3").detail).is_equal(3)
	assert_int(ArtPrim.parse("box hull steel 0 0 0 1 1 1").detail).is_equal(-1)
	assert_object(ArtPrim.parse("box hull steel 0 0 0 1 1 1 detail=4")).is_null()
	assert_object(ArtPrim.parse("rod hull steel 0 0 0 1 0 0 3 detail=0")).is_not_null()


func test_decals_and_macros_leave_every_frame_byte_identical() -> void:
	# The shipped models use none of them, so `--check` (gen-art.sh) is the proof; this pins that a
	# model with a decal and a `detail=` renders the same frames as one without.
	var plain: Array[String] = ["box hull steel 0 0 0 1 1 0.2"]
	var marked: Array[String] = ["box hull steel 0 0 0 1 1 0.2 detail=2"]
	var a: Dictionary[String, String] = ArtGen.build(_model(plain))
	var b: Dictionary[String, String] = ArtGen.build(
		_model(marked, ["number 0 top 0.5 0.5 0.3 n=7"])
	)
	assert_int(a.size()).is_equal(b.size())
	for path: String in a:
		(
			assert_bool(a[path] == b[path] or path.ends_with("_sheet.tres"))
			. override_failure_message(path)
			. is_true()
		)
