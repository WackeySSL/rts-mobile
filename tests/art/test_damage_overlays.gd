extends GdUnitTestSuite
## The neutral vehicle damage overlays (plan row P160, ADR 0028 section 4, STYLE.md "Damage
## overlays"): the eight hand-written SVGs and their sheet under `assets/art/svg/damage/`, and the
## `damage`, `hang` and `scar_milli` of the eight vehicle models. The generic rules of every
## hand-written file are in test_art_assets.gd; the bake of the sheet is in test_neutral_sheet.gd.

const FOLDER: String = "res://assets/art/svg/damage"
const KEY_COLOURS: PackedStringArray = [
	"#FF9446", "#E8681F", "#B04B12", "#62D6EE", "#1FA6C8", "#137C99"
]
const BAND_DEGREES: float = 20.0  ## ADR 0023 section 5: the key band's half width.
const SATURATION_FLOOR: float = 0.30
const FLAME_HUE_MIN: float = 46.0  ## ADR 0027 section 4: embers are yellow-white.
const MAX_SLOT: Vector2i = Vector2i(64, 48)  ## ADR 0028 section 4: the slots' size at 2x.
const PARTS: Array[StringName] = [&"scar1", &"scar2", &"loose"]
const FRAMES: Array[int] = [2, 2, 4]
const VEHICLES: Array[String] = [
	"fossil/heavy_tank",
	"fossil/light_tank",
	"fossil/artillery",
	"fossil/harvester",
	"renew/renew_tank",
	"renew/renew_artillery",
	"renew/renew_scout",
	"renew/renew_tanker",
]
const TRACKED: Array[String] = ["heavy_tank", "renew_tank"]


func _sheet() -> IsoSheetDef:
	return load(FOLDER + "/damage_sheet.tres") as IsoSheetDef


func test_the_sheet_is_the_neutral_one_with_its_root_and_passes_the_bake_check() -> void:
	var sheet: IsoSheetDef = _sheet()
	assert_str(sheet.faction).is_equal("neutral")
	assert_str(sheet.category).is_equal("dmg")
	assert_str(sheet.root).is_equal(FOLDER)
	assert_array(Array(sheet.parts)).is_equal(["scar1", "scar2", "loose"])
	assert_array(Array(sheet.frames)).is_equal(FRAMES)
	assert_str(IsoAtlas.neutral_problem(sheet, "damage_sheet.tres")).is_empty()
	assert_object(IsoAtlas.load_neutral_sheet(IsoAtlas.NEUTRAL_SHEET)).is_not_null()
	for part: StringName in PARTS:
		var size: Vector2i = sheet.frame_size(part)
		assert_bool(size.x <= MAX_SLOT.x and size.y <= MAX_SLOT.y).is_true()
		var anchor: Vector2i = sheet.anchor(part)
		assert_bool(Rect2i(Vector2i.ZERO, size).has_point(anchor)).is_true()


func test_every_frame_is_a_file_with_a_keep_file_import_and_ink_clear_of_its_edge() -> void:
	var sheet: IsoSheetDef = _sheet()
	var problems: Array[String] = []
	for i: int in PARTS.size():
		var part: StringName = PARTS[i]
		assert_int(sheet.frame_count(part)).is_equal(FRAMES[i])
		for frame: int in FRAMES[i]:
			var path: String = sheet.path(part, -1, frame)
			if not FileAccess.file_exists(path):
				problems.append(path + " is missing")
				continue
			var import: String = FileAccess.get_file_as_string(path + ".import")
			if not import.contains('importer="keep"'):
				problems.append(path + " is not Keep File")
			var text: String = FileAccess.get_file_as_string(path)
			if not text.begins_with("<!-- ") or not text.contains("<!-- Silhouette: "):
				problems.append(path + " has no header comments")
			var image: Image = Image.new()
			image.load_svg_from_string(text, 1.0)
			var size: Vector2i = sheet.frame_size(part)
			if image.get_size() != size:
				problems.append("%s is %s, the sheet says %s" % [path, image.get_size(), size])
				continue
			problems.append_array(_edge_ink(path, image))
	assert_array(problems).is_empty()


func test_no_colour_is_in_a_key_band_and_the_embers_are_yellow_white() -> void:
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	var problems: Array[String] = []
	var embers: int = 0
	for file: String in DirAccess.get_files_at(FOLDER):
		if not file.ends_with(".svg"):
			continue
		for found: RegExMatch in hex.search_all(FileAccess.get_file_as_string(FOLDER + "/" + file)):
			var colour: Color = Color(found.get_string())
			var label: String = "%s %s" % [file, found.get_string()]
			if KEY_COLOURS.has(found.get_string().to_upper()) or _in_key_band(colour):
				problems.append(label + " is in a key band")
			if colour.s >= SATURATION_FLOOR:
				embers += 1
				if colour.h * 360.0 < FLAME_HUE_MIN:
					problems.append(label + " is orange or red")
	assert_array(problems).is_empty()
	assert_int(embers).is_greater(0)  # scar2 has its seam.


func test_the_colour_check_catches_a_key_colour() -> void:
	assert_bool(_in_key_band(Color("#FF9446"))).is_true()
	assert_bool(_in_key_band(Color("#1FA6C8"))).is_true()
	assert_bool(_in_key_band(Color("#FFD84D"))).is_false()
	assert_bool(_in_key_band(Color("#7D8893"))).is_false()


func test_every_vehicle_has_one_damage_point_one_hang_point_and_a_scar_scale() -> void:
	for id: String in VEHICLES:
		var model: ArtModel = load("res://assets/art/models/%s.tres" % id) as ArtModel
		var kinds: Array[StringName] = []
		for emitter: Array in model.emitter_list():
			kinds.append(emitter[0])
		assert_int(kinds.count(&"damage")).override_failure_message(id).is_equal(1)
		assert_int(kinds.count(&"hang")).override_failure_message(id).is_equal(1)
		assert_int(model.scar_milli).override_failure_message(id).is_between(1, 1000)
		assert_str(model.marks).is_equal("tracks" if TRACKED.has(model.art_id) else "wheels")
		assert_array(Array(model.problems())).override_failure_message(id).is_empty()
	var tank: ArtModel = load("res://assets/art/models/fossil/heavy_tank.tres") as ArtModel
	assert_int(tank.scar_milli).is_equal(1000)  # The reference.


func test_a_hang_point_is_on_the_camera_side_in_every_hull_frame() -> void:
	for id: String in VEHICLES:
		var path: String = "res://assets/art/models/%s.tres" % id
		var model: ArtModel = load(path) as ArtModel
		var sheet: IsoSheetDef = load(
			"res://assets/art/iso/%s/veh/%s_sheet.tres" % [model.faction, model.art_id]
		)
		var at: int = sheet.emitters.find("hang")
		assert_int(at).is_greater_equal(0)
		var hang: Vector3 = Vector3.ZERO
		for emitter: Array in model.emitter_list():
			if emitter[0] == &"hang":
				hang = emitter[1]
		for dir: int in 16:
			var want: Vector2 = ArtGen.hang_point_px(hang, dir)
			var got: Vector2 = sheet.emitter_point(at, dir)
			(
				assert_float(got.distance_to(want))
				. override_failure_message("%s d%02d" % [id, dir])
				. is_less(0.2)
			)
			# On the camera side: no higher on the screen than its mirror across the long axis.
			var mirror: Vector2 = ArtGen.point_px(Vector3(hang.x, -hang.y, hang.z), dir)
			assert_bool(got.y + 0.1 >= mirror.y).is_true()


## Ink on the outermost pixel row or column: a sprite is drawn at least 1 px inside its canvas.
func _edge_ink(path: String, image: Image) -> Array[String]:
	var found: Array[String] = []
	var w: int = image.get_width()
	var h: int = image.get_height()
	for x: int in w:
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, h - 1).a > 0.0:
			found.append("%s has ink on its top or bottom row" % path)
			break
	for y: int in h:
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(w - 1, y).a > 0.0:
			found.append("%s has ink on its left or right column" % path)
			break
	return found


func _in_key_band(colour: Color) -> bool:
	if colour.s < SATURATION_FLOOR:
		return false
	for key: String in KEY_COLOURS:
		var gap: float = absf(colour.h * 360.0 - Color(key).h * 360.0)
		if minf(gap, 360.0 - gap) <= BAND_DEGREES:
			return true
	return false
