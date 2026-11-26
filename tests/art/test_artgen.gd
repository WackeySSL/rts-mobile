extends GdUnitTestSuite
## The art generator and its blockout models (plan rows P99 and P99b, ADR 0023 section 5, STYLE.md
## "Generated art"): every Phase 3 type of both factions has a model, its frames are complete (16
## directions for a vehicle, turret and head, 8 for a squad, one view for a building, a cast shadow
## for each hull frame), two runs give identical bytes, every committed file (frames, sheets, item
## cards, the index) equals a fresh run, the frames use only the allowed elements and sizes, and no
## colour outside a faction's key triad lies in that triad's hue band, so only a team zone reads as
## team colour. The rules of the projection, the light and the writer are in test_artgen_rules.gd;
## the shadows, the sheets and the cards are in test_artgen_shadows.gd, test_artgen_sheets.gd and
## test_artgen_cards.gd; the pictures at 32 px are in test_artgen_readability.gd.

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
		"fossil_space bld 3 hull",
		"fossil_aa bld 1 hull,head",
		"fossil_airfield bld 3 hull",
		"fossil_engineering bld 2 hull",
		"fossil_weld_shed bld 2 hull",
		"rifle_squad inf 0 hull",
		"rocket_squad inf 0 hull",
		"fossil_patchers inf 0 hull",
		"light_tank veh 0 hull,turret",
		"heavy_tank veh 0 hull,turret",
		"artillery veh 0 hull,turret",
		"harvester veh 0 hull",
		"fossil_fighter veh 0 hull",
		"fossil_bomber veh 0 hull",
		"fossil_bunk_wagon veh 0 hull",
		"fossil_shot_truck veh 0 hull",
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
		"renew_space bld 3 hull",
		"renew_aa bld 1 hull,head",
		"renew_airfield bld 3 hull",
		"renew_engineering bld 2 hull",
		"renew_drone_dock bld 2 hull",
		"renew_rifle inf 0 hull",
		"renew_rocket inf 0 hull",
		"renew_menders inf 0 hull",
		"renew_scout veh 0 hull,turret",
		"renew_tank veh 0 hull,turret",
		"renew_artillery veh 0 hull,turret",
		"renew_tanker veh 0 hull",
		"renew_fighter veh 0 hull",
		"renew_bomber veh 0 hull",
		"renew_linecar veh 0 hull",
		"renew_seeder veh 0 hull",
	],
}
## The item cards of the four upgrades, drawn by hand beside the generated ones (P249).
const HAND_CARDS: Array[String] = [
	"item_heavy_bombs", "item_plated_hull", "item_focus_bombs", "item_glaze_hull"
]
const MAX_FILE_BYTES: int = 28 * 1024  ## STYLE.md "Technical rules".
## A generated frame of a model at detail 2 or more: up to 64 KB, and `linearGradient` in `defs` for
## the metal sheen besides the three elements (ADR 0050 section 1).
const MAX_DETAIL_FILE_BYTES: int = 64 * 1024
const DETAIL_TAGS: Array[String] = ["defs", "linearGradient", "stop"]
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
			(
				assert_bool(_fresh.has(ArtGen.frame_path(model, ArtModel.SHADOW, dir)))
				. override_failure_message(path + " shadow")
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
			. override_failure_message("%s is missing or stale: bash scripts/gen-art.sh" % path)
			. is_true()
		)


func test_no_generated_file_is_committed_that_a_run_does_not_make() -> void:
	var committed: Array[String] = []
	for path: String in (
		_list("res://assets/art/iso", ".svg") + _list("res://assets/art/iso", ".tres")
	):
		# The four research cards are hand-written (P249): no model stands behind an upgrade.
		if not path.get_file().get_basename() in HAND_CARDS:
			committed.append(path)
	var generated: int = 0
	for path: String in _fresh:
		generated += int(not path.ends_with(".import"))
	assert_int(committed.size()).is_equal(generated)
	for path: String in committed:
		assert_bool(_fresh.has(path)).override_failure_message(path).is_true()
		var first: String = FileAccess.get_file_as_string(path).split("\n")[0]
		assert_bool(first.contains(ArtGen.MARKER) or first.contains(ArtSheet.MARKER)).is_true()
	# Every frame has its "Keep File" import; a card's is the texture import Godot writes.
	for path: String in _fresh:
		if path.ends_with(".svg") and not path.contains("/icons/"):
			assert_bool(FileAccess.file_exists(path + ".import")).is_true()
		if path.contains("/icons/"):
			assert_str(FileAccess.get_file_as_string(path + ".import")).contains("texture")


func test_frames_use_only_the_allowed_elements_and_sizes() -> void:
	var tags: RegEx = RegEx.create_from_string("<([a-zA-Z]+)")
	var decimals: RegEx = RegEx.create_from_string("\\d\\.\\d\\d")
	var opacity: RegEx = RegEx.create_from_string('opacity="[^"]*"')
	var lower_hex: RegEx = RegEx.create_from_string("#[0-9a-f]*[a-f][0-9a-f]*\\b")
	var detailed: PackedStringArray = PackedStringArray()
	for model_path: String in ArtGen.model_paths():
		var model: ArtModel = load(model_path) as ArtModel
		if model.detail >= 2:
			detailed.append(String(model.art_id) + "_")
			detailed.append("item_" + String(model.art_id) + ".")
	for path: String in _fresh:
		if not path.ends_with(".svg"):
			continue
		var text: String = _fresh[path]
		var rich: bool = false
		for prefix: String in detailed:
			rich = rich or path.get_file().begins_with(prefix)
		var allowed: Array[String] = ALLOWED_TAGS.duplicate()
		if rich:
			allowed.append_array(DETAIL_TAGS)
		var cap: int = MAX_DETAIL_FILE_BYTES if rich else MAX_FILE_BYTES
		assert_int(text.length()).override_failure_message(path).is_less(cap)
		for found: RegExMatch in tags.search_all(text):
			assert_array(allowed).override_failure_message(path).contains([found.get_string(1)])
		for banned: String in ["href", "style", "<text", "<image", "<filter", "<script"]:
			assert_bool(text.contains(banned)).override_failure_message(path).is_false()
		(
			assert_object(decimals.search(opacity.sub(text, "", true)))
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
				# A pose part has several frames per direction, each in a file of its own.
				for frame: int in model.frames(part):
					var file: String = ArtGen.frame_path(
						model, part, dir, frame if model.frames(part) > 1 else -1
					)
					assert_bool(_fresh.has(file)).override_failure_message(file).is_true()
					var root: String = _fresh[file].split("\n")[1]
					assert_int(_attribute(root, "width")).override_failure_message(file).is_equal(
						layout.size.x
					)
					assert_int(_attribute(root, "height")).override_failure_message(file).is_equal(
						layout.size.y
					)
			# The origin is in the canvas; a building's `anim` part is cropped to its element and the
			# origin, which then lies on the bottom edge (the footprint's centre is the anchor).
			var slack: Vector2i = Vector2i.ONE if part == ArtPrim.ANIM else Vector2i.ZERO
			var canvas: Rect2i = Rect2i(Vector2i.ZERO, layout.size + slack)
			# A damage patch (ADR 0028 section 3) ends above the ground point, which lies below it.
			if part not in ArtModel.DAMAGE_PARTS:
				(
					assert_bool(canvas.has_point(layout.origin))
					. override_failure_message(path)
					. is_true()
				)
			if part in ArtModel.DAMAGE_PARTS:
				# Anchored like the body: the back corner, 32 px a tile above the footprint's centre.
				assert_int(layout.origin.y - layout.anchor.y).is_equal(32 * model.footprint)
				# It may reach below the footprint's centre (a KRITISK patch, ADR 0029 section 4) and
				# stand above the body's canvas (a snapped mast's rod), but never below the body's
				# foot: its bottom (rows under the ground point) is within the body's.
				var body: ArtGen.Layout = layouts[&"hull"]
				(
					assert_int(layout.size.y - layout.origin.y)
					. override_failure_message(path)
					. is_less_equal(body.size.y - body.origin.y)
				)
			elif part in [&"hull", ArtModel.SHADOW] and model.category == &"bld":
				# A tile is 128 x 64 px at 2x: the canvas of the body is the footprint wide, the
				# origin its centre, the anchor the diamond's back corner 32 x n px above it
				# (Spec 03); the shadow reaches past the east corner and has the same anchor.
				if part == &"hull":
					assert_int(layout.size.x).override_failure_message(path).is_equal(
						128 * model.footprint
					)
					assert_vector(Vector2(layout.origin)).is_equal(
						Vector2(64 * model.footprint, layout.origin.y)
					)
				else:
					assert_int(layout.size.x).override_failure_message(path).is_greater_equal(
						128 * model.footprint
					)
					assert_int(layout.origin.x).is_greater_equal(64 * model.footprint)
				assert_int(layout.origin.y - layout.anchor.y).is_equal(32 * model.footprint)
				assert_int(layout.size.y - layout.origin.y).is_greater_equal(32 * model.footprint)
				assert_int(layout.anchor.y).is_greater_equal(0)
			else:
				assert_vector(Vector2(layout.anchor)).is_equal(Vector2(layout.origin))


func test_the_key_band_is_the_one_of_adr_0023() -> void:
	# ADR 0023 section 5, ADR 0050 section 3: hue within 20 degrees of the sentinel's (300, magenta)
	# and saturation of at least 0.30, one band for both factions.
	var hues: Array[float] = []
	for hex: String in ArtPalette.SENTINEL:
		hues.append(Color(hex).h * 360.0)
	assert_float(hues.min() - BAND_DEGREES).is_equal_approx(280.0, 0.1)
	assert_float(hues.max() + BAND_DEGREES).is_equal_approx(320.0, 0.1)
	assert_dict(ArtPalette.KEYS).is_equal(
		{&"fossil": ArtPalette.SENTINEL, &"renew": ArtPalette.SENTINEL}
	)
	# A magenta is in the band; the fixed faction colours and the old key hues are not.
	for hex: String in ["#C040C0", "#E070E0"]:
		assert_bool(_in_band(hex, &"fossil")).override_failure_message(hex).is_true()
	for hex: String in ["#FF6E1F", "#40A3FF", "#E8681F", "#1FA6C8"]:
		assert_bool(_in_band(hex, &"renew")).override_failure_message(hex).is_false()
	for faction: StringName in ArtPalette.MATERIALS:
		for material: StringName in ArtPalette.MATERIALS[faction]:
			var hex: String = ArtPalette.MATERIALS[faction][material]
			assert_bool(_in_band(hex, faction)).override_failure_message(hex).is_false()
		# The damage materials, and every tone of them, stay outside it too.
		var damage: Array = ArtPalette.SHARED.keys() + [ArtPalette.INTERIOR]
		for material: StringName in damage:
			for level: int in 3:
				var hex: String = ArtPalette.tone(faction, material, level)
				assert_bool(_in_band(hex, faction)).override_failure_message(hex).is_false()


func test_no_colour_but_the_sentinel_triad_is_in_the_key_band() -> void:
	var colour: RegEx = RegEx.create_from_string("#[0-9A-F]{6}")
	var key_count: Dictionary[String, int] = {}
	for path: String in _fresh:
		if not path.ends_with(".svg"):
			continue
		var faction: StringName = _faction_of(path)
		for found: RegExMatch in colour.search_all(_fresh[path]):
			var hex: String = found.get_string()
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


## The faction of a generated file: the folder of a frame, the model of a card.
func _faction_of(path: String) -> StringName:
	if path.contains("/icons/"):
		var id: String = path.get_file().trim_prefix("item_").trim_suffix(".svg")
		for model_path: String in ArtGen.model_paths():
			if model_path.get_file() == id + ".tres":
				return (load(model_path) as ArtModel).faction
	return StringName(path.trim_prefix("res://assets/art/iso/").split("/")[0])


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
