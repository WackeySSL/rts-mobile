extends GdUnitTestSuite
## The art generator and its blockout models (plan row P99, ADR 0023 section 5, STYLE.md "Generated
## art"): every Phase 3 type of both factions has a model, its frames are complete (16 directions
## for a vehicle, turret and head, 8 for a squad, one view for a building), two runs give identical
## bytes, every committed frame equals a fresh run, the frames use only the allowed elements and
## sizes, and no colour outside a faction's key triad lies in that triad's hue band, so only a team
## zone reads as team colour. The rules of the projection, the light and the writer are in
## test_artgen_rules.gd; the pictures at 32 px are in test_artgen_readability.gd.

const ROSTER: Dictionary[String, PackedStringArray] = {
	"fossil":
	[
		"headquarters bld 3 hull",
		"power_plant bld 2 hull",
		"refinery bld 3 hull",
		"barracks bld 2 hull",
		"vehicle_factory bld 3 hull",
		"fossil_radar bld 2 hull",
		"defence_turret bld 1 hull,head",
		"fossil_strike bld 3 hull",
		"rifle_squad inf 0 hull",
		"rocket_squad inf 0 hull",
		"light_tank veh 0 hull,turret",
		"heavy_tank veh 0 hull,turret",
		"artillery veh 0 hull,turret",
		"harvester veh 0 hull",
	],
	"renew":
	[
		"renew_hq bld 3 hull",
		"renew_power bld 2 hull",
		"renew_refinery bld 3 hull",
		"renew_barracks bld 2 hull",
		"renew_factory bld 3 hull",
		"renew_radar bld 2 hull",
		"renew_defence bld 1 hull,head",
		"renew_strike bld 3 hull",
		"renew_rifle inf 0 hull",
		"renew_rocket inf 0 hull",
		"renew_scout veh 0 hull,turret",
		"renew_tank veh 0 hull,turret",
		"renew_artillery veh 0 hull,turret",
		"renew_tanker veh 0 hull",
	],
}
const MAX_FILE_BYTES: int = 28 * 1024  ## STYLE.md "Technical rules".
const BAND_DEGREES: float = 20.0  ## ADR 0023 section 5: the key band's half width.
const BAND_SATURATION: float = 0.30
const ALLOWED_TAGS: Array[String] = ["svg", "g", "polygon"]

var _fresh: Dictionary[String, String] = {}


func before() -> void:
	_fresh = ArtGen.build_all()


func test_every_phase_3_type_of_both_factions_has_a_model() -> void:
	var found: Dictionary[String, PackedStringArray] = {}
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		assert_object(model).override_failure_message(path).is_not_null()
		var parts: PackedStringArray = PackedStringArray()
		for part: StringName in model.parts():
			parts.append(String(part))
		var spec: String = (
			"%s %s %d %s" % [model.art_id, model.category, model.footprint, ",".join(parts)]
		)
		if not found.has(String(model.faction)):
			found[String(model.faction)] = PackedStringArray()
		found[String(model.faction)].append(spec)
		assert_str(path).is_equal(
			"res://assets/art/models/%s/%s.tres" % [model.faction, model.art_id]
		)
	for faction: String in ROSTER:
		var want: Array[String] = []
		want.assign(ROSTER[faction])
		want.sort()
		var got: Array[String] = []
		got.assign(found.get(faction, PackedStringArray()))
		got.sort()
		assert_array(got).override_failure_message(faction).is_equal(want)


func test_every_model_is_valid_and_describes_its_silhouette_in_one_line() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		assert_array(Array(model.problems())).override_failure_message(path).is_empty()
		(
			assert_bool(model.silhouette.length() > 20 and not model.silhouette.contains("\n"))
			. is_true()
		)
		assert_bool(model.prims.size() >= 3).override_failure_message(path).is_true()


func test_every_footprint_is_square_and_a_building_has_one_view() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var hull: Array[int] = model.directions(&"hull")
		if model.category == &"bld":
			assert_array(hull).override_failure_message(path).is_equal([-1])
			assert_int(model.footprint).is_between(1, 3)
			for prim: ArtPrim in model.primitives(&"hull"):
				# The footprint is n x n tiles centred on the origin; nothing leaves it.
				var box: AABB = prim.aabb()
				var half: float = model.footprint / 2.0
				assert_float(maxf(absf(box.position.x), absf(box.end.x))).is_less_equal(half)
				assert_float(maxf(absf(box.position.y), absf(box.end.y))).is_less_equal(half)
		else:
			assert_int(model.footprint).is_equal(0)


func test_vehicles_have_16_directions_squads_8_and_a_turret_or_head_16() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var expected: Dictionary[StringName, int] = {&"veh": 16, &"inf": 8, &"bld": 1}
		var frames: int = 0
		for dir: int in model.directions(&"hull"):
			(
				assert_bool(_fresh.has(ArtGen.frame_path(model, &"hull", dir)))
				. override_failure_message(path)
				. is_true()
			)
			frames += 1
		assert_int(frames).override_failure_message(path).is_equal(expected[model.category])
		if model.category == &"inf":
			assert_array(model.directions(&"hull")).is_equal([0, 2, 4, 6, 8, 10, 12, 14])
		for part: StringName in [&"turret", &"head"]:
			if model.parts().has(part):
				assert_array(model.directions(part)).is_equal(range(16))
				for dir: int in 16:
					assert_bool(_fresh.has(ArtGen.frame_path(model, part, dir))).is_true()


func test_two_runs_give_identical_bytes() -> void:
	var again: Dictionary[String, String] = ArtGen.build_all()
	assert_int(again.size()).is_equal(_fresh.size())
	assert_int(_fresh.size()).is_greater(500)
	for path: String in _fresh:
		assert_bool(again.get(path, "") == _fresh[path]).override_failure_message(path).is_true()


func test_every_committed_frame_equals_a_fresh_run() -> void:
	for path: String in _fresh:
		var committed: String = FileAccess.get_file_as_string(path)
		(
			assert_bool(committed == _fresh[path])
			. override_failure_message(
				"%s is missing or stale: bash scripts/gen-art.sh --all" % path
			)
			. is_true()
		)


func test_no_generated_frame_is_committed_that_a_run_does_not_make() -> void:
	var committed: Array[String] = _list("res://assets/art/iso", ".svg")
	assert_int(committed.size() * 2).is_equal(_fresh.size())
	for path: String in committed:
		var first: String = FileAccess.get_file_as_string(path).split("\n")[0]
		if first.contains(ArtGen.MARKER):
			assert_bool(_fresh.has(path)).override_failure_message(path).is_true()
			assert_bool(_fresh.has(path + ".import")).override_failure_message(path).is_true()


func test_frames_use_only_the_allowed_elements_and_sizes() -> void:
	var tags: RegEx = RegEx.create_from_string("<([a-zA-Z]+)")
	var decimals: RegEx = RegEx.create_from_string("\\d\\.\\d\\d")
	var lower_hex: RegEx = RegEx.create_from_string("#[0-9a-f]*[a-f][0-9a-f]*\\b")
	for path: String in _fresh:
		if not path.ends_with(".svg"):
			continue
		var text: String = _fresh[path]
		assert_int(text.length()).override_failure_message(path).is_less(MAX_FILE_BYTES)
		for found: RegExMatch in tags.search_all(text):
			assert_array(ALLOWED_TAGS).override_failure_message(path).contains(
				[found.get_string(1)]
			)
		for banned: String in ["href", "style", "<text", "<image", "<filter", "<script"]:
			assert_bool(text.contains(banned)).override_failure_message(path).is_false()
		(
			assert_object(decimals.search(text))
			. override_failure_message(path + ": a second decimal")
			. is_null()
		)
		(
			assert_object(lower_hex.search(text))
			. override_failure_message(path + ": lower-case hex")
			. is_null()
		)
		var root: String = text.split("\n")[1]
		var width: int = _attribute(root, "width")
		var height: int = _attribute(root, "height")
		assert_str(root).override_failure_message(path).contains(
			'viewBox="0 0 %d %d"' % [width, height]
		)
		assert_bool(width > 0 and height > 0 and width % 2 == 0 and height % 2 == 0).is_true()


func test_a_part_has_one_canvas_in_every_direction_and_a_building_is_anchored_at_its_back_corner(
) -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		for part: StringName in layouts:
			var layout: ArtGen.Layout = layouts[part]
			for dir: int in model.directions(part):
				var root: String = _fresh[ArtGen.frame_path(model, part, dir)].split("\n")[1]
				assert_int(_attribute(root, "width")).override_failure_message(path).is_equal(
					layout.size.x
				)
				assert_int(_attribute(root, "height")).override_failure_message(path).is_equal(
					layout.size.y
				)
			assert_bool(Rect2i(Vector2i.ZERO, layout.size).has_point(layout.origin)).is_true()
			if part == &"hull" and model.category == &"bld":
				# A tile is 128 x 64 px at 2x: the canvas is the footprint wide, the origin its
				# centre, the anchor the diamond's back corner 32 x n px above it (Spec 03).
				assert_int(layout.size.x).override_failure_message(path).is_equal(
					128 * model.footprint
				)
				assert_vector(Vector2(layout.origin)).is_equal(
					Vector2(64 * model.footprint, layout.origin.y)
				)
				assert_int(layout.origin.y - layout.anchor.y).is_equal(32 * model.footprint)
				assert_int(layout.size.y - layout.origin.y).is_greater_equal(32 * model.footprint)
				assert_int(layout.anchor.y).is_greater_equal(0)
			else:
				assert_vector(Vector2(layout.anchor)).is_equal(Vector2(layout.origin))


func test_the_key_band_is_the_one_of_adr_0023() -> void:
	# ADR 0023 section 5: hue within 20 degrees of a key colour and saturation of at least 0.30.
	var ranges: Dictionary[StringName, Vector2] = {
		&"fossil": Vector2(1.6, 45.3), &"renew": Vector2(170.3, 213.0)
	}
	for faction: StringName in ranges:
		var hues: Array[float] = []
		for hex: String in ArtPalette.KEYS[faction]:
			hues.append(Color(hex).h * 360.0)
		assert_float(hues.min() - BAND_DEGREES).is_equal_approx(ranges[faction].x, 0.1)
		assert_float(hues.max() + BAND_DEGREES).is_equal_approx(ranges[faction].y, 0.1)
	# The four canvas colours the ADR changed fall in the band; their replacements do not.
	for hex: String in ["#8E5A38", "#FFC45C"]:
		assert_bool(_in_band(hex, &"fossil")).override_failure_message(hex).is_true()
	for hex: String in ["#8AD6E6", "#9BF6FF"]:
		assert_bool(_in_band(hex, &"renew")).override_failure_message(hex).is_true()
	for faction: StringName in ArtPalette.MATERIALS:
		for material: StringName in ArtPalette.MATERIALS[faction]:
			var hex: String = ArtPalette.MATERIALS[faction][material]
			assert_bool(_in_band(hex, faction)).override_failure_message(hex).is_false()


func test_no_colour_but_the_key_triad_is_in_the_key_band_of_its_faction() -> void:
	var colour: RegEx = RegEx.create_from_string("#[0-9A-F]{6}")
	var key_count: Dictionary[String, int] = {}
	for path: String in _fresh:
		if not path.ends_with(".svg"):
			continue
		var faction: StringName = StringName(
			path.trim_prefix("res://assets/art/iso/").split("/")[0]
		)
		var other: StringName = &"renew" if faction == &"fossil" else &"fossil"
		for found: RegExMatch in colour.search_all(_fresh[path]):
			var hex: String = found.get_string()
			(
				assert_bool(ArtPalette.KEYS[other].has(hex))
				. override_failure_message(path + " " + hex)
				. is_false()
			)
			if ArtPalette.KEYS[faction].has(hex):
				key_count[path] = key_count.get(path, 0) + 1
			else:
				(
					assert_bool(_in_band(hex, faction))
					. override_failure_message(path + " " + hex)
					. is_false()
				)
	# Every type has a team zone somewhere in its frames.
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var zone: bool = false
		for part: StringName in model.parts():
			for dir: int in model.directions(part):
				zone = zone or key_count.has(ArtGen.frame_path(model, part, dir))
		assert_bool(zone).override_failure_message(path + " has no team zone").is_true()


func _in_band(hex: String, faction: StringName) -> bool:
	var colour: Color = Color(hex)
	if colour.s < BAND_SATURATION:
		return false
	for key: String in ArtPalette.KEYS[faction]:
		var gap: float = absf(colour.h * 360.0 - Color(key).h * 360.0)
		if minf(gap, 360.0 - gap) <= BAND_DEGREES:
			return true
	return false


func _attribute(root: String, name: String) -> int:
	return root.split('%s="' % name)[1].split('"')[0].to_int()


func _list(dir: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir):
		found.append_array(_list(dir.path_join(sub), extension))
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(extension):
			found.append(dir.path_join(file))
	found.sort()
	return found
