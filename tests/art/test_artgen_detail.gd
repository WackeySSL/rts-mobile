extends GdUnitTestSuite
## The detail renderer (plan row P631, ADR 0050 section 1): level 0 is today's bytes, each level
## draws only what `ArtDetail` allows, the gradients are named in order and hold no key colour, the
## budgets hold, two builds give the same bytes, and a level 2 hull sits in the same-scene bands.

const Support: GDScript = preload("res://tests/art/detail_support.gd")
const BASIC: Array[String] = ["svg", "g", "polygon"]
const WITH_SHEEN: Array[String] = ["svg", "g", "polygon", "defs", "linearGradient", "stop"]
const UNIT_POLYS: int = 600  ## ADR 0050 section 1: a unit hull at level 2.
const UNIT_BYTES: int = 64 * 1024
const NUMBER_PAINT: String = "#E9E5D6"
## The models that have opted in, by restyle batch (docs/art/treadline-batches.json); every other
## model of the game is at detail 0 until its own batch. P638: the Nordvaern ground vehicles; P639:
## the Facet ground vehicles; P640: the three Nordvaern squads.
const OPTED_IN: Dictionary[String, int] = {
	"light_tank": 2,
	"heavy_tank": 2,
	"artillery": 2,
	"harvester": 2,
	"renew_scout": 2,
	"renew_tank": 2,
	"renew_artillery": 2,
	"renew_tanker": 2,
	"rifle_squad": 2,
	"rocket_squad": 2,
	"fossil_patchers": 2,
}


func _tags(text: String) -> Array[String]:
	var found: Array[String] = []
	var tag: RegEx = RegEx.create_from_string("<([A-Za-z]+)")
	for hit: RegExMatch in tag.search_all(text):
		if hit.get_string(1) not in found:
			found.append(hit.get_string(1))
	found.sort()
	return found


func _sorted(names: Array[String]) -> Array[String]:
	var found: Array[String] = names.duplicate()
	found.sort()
	return found


func _polygons(text: String) -> int:
	return text.count("<polygon")


func _hull(level: int, dir: int = 6) -> String:
	var m: ArtModel = Support.model(level)
	return Support.files(level)[ArtGen.frame_path(m, &"hull", dir)]


func test_the_fixtures_are_valid_models() -> void:
	for level: int in [1, 2, 3]:
		assert_array(Support.model(level).problems()).is_empty()
		assert_int(Support.model(level).detail).is_equal(level)


func test_detail_0_is_the_flat_renderer_byte_for_byte() -> void:
	var flat: ArtModel = Support.model(2).duplicate() as ArtModel
	flat.detail = 0
	var plain: ArtModel = flat.duplicate() as ArtModel
	plain.decals = PackedStringArray()
	assert_bool(ArtGen.build(flat) == ArtGen.build(plain)).is_true()
	var prims: Array[ArtPrim] = flat.primitives(&"hull")
	var want: Array[ArtRender.Poly] = ArtRender.render(prims, 22.5, flat.faction)
	var got: Array[ArtRender.Poly] = ArtDetail.render(flat, prims, 22.5)
	assert_int(got.size()).is_equal(want.size())
	for i: int in want.size():
		assert_bool(got[i] == want[i] or got[i].points == want[i].points).is_true()
		assert_str(got[i].fill).is_equal(want[i].fill)


func test_only_the_models_of_a_finished_batch_opt_in() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		assert_int(model.detail).override_failure_message(path).is_equal(
			OPTED_IN.get(String(model.art_id), 0)
		)


func test_each_level_uses_only_its_allowed_elements() -> void:
	assert_array(_tags(_hull(1))).is_equal(_sorted(BASIC))
	assert_array(_tags(_hull(2))).is_equal(_sorted(WITH_SHEEN))
	assert_array(_tags(_hull(3))).is_equal(_sorted(WITH_SHEEN))
	for level: int in [1, 2, 3]:
		for path: String in Support.frames(level):
			var allowed: Array[String] = _sorted(BASIC if level == 1 else WITH_SHEEN)
			for tag: String in _tags(Support.frames(level)[path]):
				assert_bool(tag in allowed).override_failure_message(path + " " + tag).is_true()
	for path: String in Support.frames(1):
		assert_str(Support.frames(1)[path]).not_contains("url(")
	for path: String in Support.frames(2):
		if path.contains("_shadow"):
			assert_str(Support.frames(2)[path]).not_contains("<defs>")


func test_the_levels_add_what_they_say() -> void:
	var l1: String = _hull(1)
	var l2: String = _hull(2)
	var l3: String = _hull(3)
	# 1: seams only. 2: tints, bolts, decals and sheen. 3: bevels and contact bands.
	assert_str(l1).contains('fill-opacity="0.25"')
	assert_str(l1).not_contains('fill-opacity="0.45"')
	assert_str(l1).not_contains('fill-opacity="0.06"')
	assert_str(l2).contains('fill-opacity="0.06"')
	assert_str(l2).contains('fill-opacity="0.45"')
	assert_str(l2).not_contains('fill-opacity="0.28"')
	assert_str(l3).contains('fill-opacity="0.28"')
	assert_str(l3).contains('fill-opacity="0.12"')
	assert_int(_polygons(l1)).is_less(_polygons(l2))
	assert_int(_polygons(l2)).is_less(_polygons(l3))
	# The decals (a hazard backing, a number's paint on a top face) appear from level 2 only.
	var backing: Array[int] = [0, 0]
	var paint: Array[int] = [0, 0]
	for level: int in [1, 2]:
		for dir: int in 16:
			var text: String = _hull(level, dir)
			backing[level - 1] += text.count('fill-opacity="0.35"')
			paint[level - 1] += text.count(NUMBER_PAINT)
	assert_array(backing).is_equal([0, backing[1]])
	assert_array(paint).is_equal([0, paint[1]])
	assert_int(backing[1]).is_greater(0)
	assert_int(paint[1]).is_greater(0)


func test_gradient_ids_are_in_order_and_hold_no_key_colour() -> void:
	var id_tag: RegEx = RegEx.create_from_string('<linearGradient id="(s\\d+)"')
	var stop: RegEx = RegEx.create_from_string('stop-color="(#[0-9A-F]{6})"')
	var used: RegEx = RegEx.create_from_string('fill="url\\(#(s\\d+)\\)"')
	var keys: Array = []
	for faction: StringName in ArtPalette.KEYS:
		keys.append_array(ArtPalette.KEYS[faction])
	var checked: int = 0
	for level: int in [2, 3]:
		for path: String in Support.frames(level):
			var text: String = Support.frames(level)[path]
			var ids: Array[String] = []
			for hit: RegExMatch in id_tag.search_all(text):
				ids.append(hit.get_string(1))
			for i: int in ids.size():
				assert_str(ids[i]).override_failure_message(path).is_equal("s%d" % i)
			for hit: RegExMatch in used.search_all(text):
				assert_bool(hit.get_string(1) in ids).override_failure_message(path).is_true()
			for hit: RegExMatch in stop.search_all(text):
				assert_bool(hit.get_string(1) in keys).override_failure_message(path).is_false()
				assert_bool(ArtPalette.in_key_band(&"fossil", hit.get_string(1))).is_false()
				checked += 1
	assert_int(checked).is_greater(100)
	# A team face is never a gradient: its fill is a key hex, every key hex is a polygon fill.
	var hull: String = _hull(2)
	assert_str(hull).contains('fill="#D234D2"')
	assert_int(hull.count("stop-color=")).is_equal(2 * hull.count("<linearGradient"))


func test_the_budgets_hold_at_every_level() -> void:
	for level: int in [1, 2, 3]:
		var worst: int = 0
		for path: String in Support.frames(level):
			var text: String = Support.frames(level)[path]
			assert_int(text.length()).override_failure_message(path).is_less(UNIT_BYTES)
			if not path.contains("_shadow"):
				worst = maxi(worst, _polygons(text))
		assert_int(worst).is_less(UNIT_POLYS)


## The unit budget on the real frames (ADR 0050 section 1): every frame of an opted-in unit, its
## shadows too, has at most 600 polygons and 64 KB (P638).
func test_every_frame_of_an_opted_in_unit_holds_the_unit_budget() -> void:
	var built: Dictionary[String, String] = ArtGen.build_all()
	var seen: int = 0
	for path: String in built:
		if not path.ends_with(".svg") or not _opted_in(path):
			continue
		var text: String = built[path]
		assert_int(text.length()).override_failure_message(path).is_less(UNIT_BYTES)
		assert_int(_polygons(text)).override_failure_message(path).is_less(UNIT_POLYS)
		seen += 1
	# Hull, turret and shadow of six units, hull and shadow of the two tankers, 16 directions each;
	# hull and shadow of the three squads, 8 directions each (P640).
	assert_int(seen).is_equal(22 * 16 + 3 * 2 * 8)


func _opted_in(path: String) -> bool:
	var name: String = path.get_file()
	for id: String in OPTED_IN:
		if (
			name.begins_with(id + "_hull_")
			or name.begins_with(id + "_turret_")
			or name.begins_with(id + "_shadow_")
		):
			return true
	return false


func test_two_builds_give_the_same_bytes_at_every_level() -> void:
	for level: int in [1, 2, 3]:
		assert_bool(ArtGen.build(Support.model(level)) == Support.files(level)).is_true()


func test_a_primitive_detail_overrides_the_models() -> void:
	var line: String = "box hull steel 0 0 0 1 1 0.5"
	var up: ArtModel = _model([line + " detail=2"], 0)
	var down: ArtModel = _model([line + " detail=0"], 2)
	var flat: ArtModel = _model([line], 0)
	var hull: StringName = &"hull"
	var text_up: String = ArtGen.build(up)[ArtGen.frame_path(up, hull, 6)]
	var text_down: String = ArtGen.build(down)[ArtGen.frame_path(down, hull, 6)]
	var text_flat: String = ArtGen.build(flat)[ArtGen.frame_path(flat, hull, 6)]
	assert_str(text_up).contains("<defs>")
	assert_str(text_down).not_contains("<defs>")
	assert_str(text_down.replace("p631_down", "p631_flat")).is_equal(text_flat)


func test_detail_is_a_level_from_0_to_3() -> void:
	assert_array(_model(["box hull steel 0 0 0 1 1 0.5"], 3).problems()).is_empty()
	assert_array(_model(["box hull steel 0 0 0 1 1 0.5"], 4).problems()).is_not_empty()
	assert_array(_model(["box hull steel 0 0 0 1 1 0.5"], -1).problems()).is_not_empty()


func test_a_clipped_extra_keeps_its_opacity() -> void:
	var poly: ArtRender.Poly = ArtRender.Poly.new()
	poly.points = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	poly.fill = "#000000"
	poly.fill_opacity = "0.25"
	var cut: Array[ArtRender.Poly] = ArtRender.clip_below([poly] as Array[ArtRender.Poly], 5.0)
	assert_str(cut[0].fill_opacity).is_equal("0.25")


func test_a_level_2_hull_sits_in_the_same_scene_bands() -> void:
	var bands: SameSceneBands = SameScene.load_bands()
	for zoom: float in [0.75, 1.0, 1.5]:
		var s: SameScene.Sprite = Support.sprite(2, zoom)
		var measured: Dictionary = SameScene.measure(s)
		if zoom == 1.0:
			assert_array(SameScene.problems("p631_l2", measured, bands)).is_empty()
		assert_float(measured[&"up_down"]).is_greater(bands.light_up_min)
	var l3: SameScene.Sprite = Support.sprite(3)
	assert_array(SameScene.problems("p631_l3", SameScene.measure(l3), bands)).is_empty()


func _model(prims: Array[String], level: int) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"p631_down" if level == 2 else &"p631_flat"
	model.faction = &"fossil"
	model.category = &"veh"
	model.detail = level
	model.prims = PackedStringArray(prims)
	return model
