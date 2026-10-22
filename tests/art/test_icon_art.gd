extends GdUnitTestSuite
## The icon and flag art of plan row P92 (Phase 3), as STYLE.md ("Icons and glyphs", "Rally flags")
## describes it: the three tab icons, the eleven item icons and the seventeen glyphs, 128 px
## canvases at import scale 1.0, tab and glyph files in greys only, item icons in palette colours,
## nothing on the outer pixel, and icons that read apart at 32 px in greyscale over the HUD
## backdrop; and the two rally flags, a hull and a grey team layer each, with the foot of the pole
## at the canvas centre. The gallery pages that show them are in test_art_gallery_icon_pages.gd.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const ICON_DIR: String = "res://assets/art/svg/icons"
const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const FLAG_ART: String = "res://assets/art/svg/flags/%s_%s.svg"
const STYLE_PATH: String = "res://assets/art/STYLE.md"
const TABS: Array[String] = ["tab_structures", "tab_infantry", "tab_vehicles"]
## One item icon per buildable type, named by type id (P72); the Headquarters is not buildable.
const ITEMS: Array[String] = [
	"item_power_plant",
	"item_refinery",
	"item_barracks",
	"item_vehicle_factory",
	"item_defence_turret",
	"item_rifle_squad",
	"item_rocket_squad",
	"item_light_tank",
	"item_heavy_tank",
	"item_artillery",
	"item_harvester",
]
const HUD_GLYPHS: Array[String] = [
	"glyph_credits",
	"glyph_power",
	"glyph_low_power",
	"glyph_lock",
	"glyph_check",
	"glyph_cross",
	"glyph_victory",
	"glyph_defeat",
	"glyph_draw",
]
## A glyph for each `Placement.Reason` but OK, by the reason's name in lower case, and the two
## glyphs of the map that are no reason.
const REASONS: Array[String] = [
	"outside",
	"ground",
	"occupied",
	"unexplored",
	"too_far",
	"cap",
]
const MAP_GLYPHS: Array[String] = ["glyph_offline", "glyph_under_attack"]
const FLAGS: Array[String] = ["rally_infantry", "rally_vehicles"]
## The colours the item icons and the flags may use: STYLE.md's palette, the neutral team colour
## that a unit's item icon carries, and the greys of the team layer.
const PALETTE: PackedStringArray = [
	"#1C2127",
	"#000000",
	"#5B6670",
	"#7D8893",
	"#A9B4BE",
	"#4E5A3A",
	"#6B7A4F",
	"#8C9A6B",
	"#CDB98F",
	"#F2B705",
	"#FFD84D",
	"#A67C00",
	"#F5A524",
	"#6F583B",
	"#A3865E",
	"#9AA5B1",
	"#FFFFFF",
	"#BFBFBF",
	"#4D4D4D",
]
const HUD_BACKDROP: Color = Color("0F141C")
## What an item icon must show to be told from the others at 32 px: the mean absolute difference of
## the two greyscale rasters over the HUD backdrop, 0 to 255, at least this much for every pair.
const ITEM_DIFFERENCE_MIN: float = 20.0
const TAB_DIFFERENCE_MIN: float = 40.0
const HUD_DIFFERENCE_MIN: float = 25.0
const MAP_DIFFERENCE_MIN: float = 35.0
## An icon covers a fifth to four fifths of its canvas, and its ink is clearly brighter than the
## backdrop (luminance 19): an item icon at least 60 of 255, a tab or glyph at least 140.
const COVER_MIN: float = 0.18
const COVER_MAX: float = 0.82
const ITEM_LUMINANCE_MIN: float = 60.0
const GLYPH_LUMINANCE_MIN: float = 140.0


func test_the_icon_folder_holds_exactly_the_files_the_style_guide_lists() -> void:
	var expected: Array[String] = []
	expected.append_array(TABS)
	expected.append_array(ITEMS)
	expected.append_array(HUD_GLYPHS)
	expected.append_array(MAP_GLYPHS)
	for reason: String in REASONS:
		expected.append("glyph_reason_" + reason)
	var found: Array[String] = []
	for path: String in FileScan.list_files(ICON_DIR, ".svg"):
		found.append(path.get_file().get_basename())
	expected.sort()
	assert_array(found).is_equal(expected)
	assert_int(found.size()).is_equal(31)


func test_every_icon_is_a_128_px_canvas_imported_at_scale_one_and_every_flag_layer_at_half(
) -> void:
	for icon: String in _all_icons():
		var texture: Texture2D = load(ICON_ART % icon)
		assert_vector(texture.get_size()).override_failure_message(icon).is_equal(Vector2(128, 128))
		assert_str(_import_text(ICON_ART % icon)).override_failure_message(icon).contains(
			"svg/scale=1.0"
		)
	for flag: String in FLAGS:
		for layer: String in ["hull", "team"]:
			var path: String = FLAG_ART % [flag, layer]
			assert_vector((load(path) as Texture2D).get_size()).is_equal(Vector2(64, 64))
			assert_str(_import_text(path)).override_failure_message(path).contains("svg/scale=0.5")
	assert_array(FileScan.list_files("res://assets/art/svg/flags", ".svg")).has_size(4)


func test_the_tab_and_glyph_files_and_the_flag_team_layers_hold_only_greys() -> void:
	var paths: Array[String] = []
	for icon: String in _grey_icons():
		paths.append(ICON_ART % icon)
	for flag: String in FLAGS:
		paths.append(FLAG_ART % [flag, "team"])
	for path: String in paths:
		var image: Image = _image(path)
		var colored: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				colored += int(pixel.a > 0.0 and not (pixel.r == pixel.g and pixel.g == pixel.b))
		assert_int(colored).override_failure_message(path).is_equal(0)


func test_every_new_svg_names_its_shape_in_one_line_and_item_icons_and_flags_use_palette_colours(
) -> void:
	var paths: Array[String] = []
	for icon: String in _all_icons():
		paths.append(ICON_ART % icon)
	for flag: String in FLAGS:
		paths.append_array([FLAG_ART % [flag, "hull"], FLAG_ART % [flag, "team"]])
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	var problems: Array[String] = []
	for path: String in paths:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = text.split("\n")
		var second: String = lines[1] if lines.size() > 1 else ""
		var named: bool = (
			second.begins_with("<!-- Silhouette: ") or second.begins_with("<!-- Shape: ")
		)
		if not (lines[0].begins_with("<!-- ") and lines[0].ends_with(" -->") and named):
			problems.append(path + " has no two comment lines")
		elif not second.ends_with(" -->") or second.length() < 60:
			problems.append(path + " has no shape line")
		for found: RegExMatch in hex.search_all(text):
			if not PALETTE.has(found.get_string().to_upper()):
				problems.append("%s uses %s" % [path, found.get_string()])
	assert_array(problems).is_empty()
	assert_int(paths.size()).is_equal(35)


## The outer 2 px of the 128 px canvas (1 px of a 64 px raster) hold no ink, so an icon never
## touches the edge of its tile or its tab.
func test_no_icon_has_ink_in_the_outer_two_px_of_its_canvas() -> void:
	for icon: String in _all_icons():
		var image: Image = _image(ICON_ART % icon)
		var wrong: int = 0
		for y: int in 128:
			for x: int in 128:
				if minf(minf(x, y), minf(127 - x, 127 - y)) < 2.0:
					wrong += int(image.get_pixel(x, y).a > 0.5)
		assert_int(wrong).override_failure_message(icon).is_equal(0)


func test_each_icon_covers_a_good_share_of_its_canvas_in_ink_that_stands_out_from_the_hud() -> void:
	for icon: String in _all_icons():
		var image: Image = _image(ICON_ART % icon)
		var count: int = 0
		var luminance: float = 0.0
		for y: int in 128:
			for x: int in 128:
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.5:
					count += 1
					luminance += 255.0 * (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
		var cover: float = count / 16384.0
		assert_float(cover).override_failure_message(icon).is_between(COVER_MIN, COVER_MAX)
		var floor_value: float = (
			ITEM_LUMINANCE_MIN if icon.begins_with("item_") else GLYPH_LUMINANCE_MIN
		)
		assert_float(luminance / count).override_failure_message(icon).is_greater(floor_value)


## The readability check of STYLE.md for icons: each file rasterised at 32 px, composited over the
## HUD backdrop and converted to greyscale; any two icons of a group differ by at least a margin.
func test_the_item_icons_read_apart_at_32_px_in_greyscale() -> void:
	assert_float(_closest_pair(ITEMS)).is_greater_equal(ITEM_DIFFERENCE_MIN)


func test_the_three_tabs_read_apart_at_32_px_in_greyscale() -> void:
	assert_float(_closest_pair(TABS)).is_greater_equal(TAB_DIFFERENCE_MIN)


func test_the_hud_glyphs_and_result_emblems_read_apart_at_32_px_in_greyscale() -> void:
	assert_float(_closest_pair(HUD_GLYPHS)).is_greater_equal(HUD_DIFFERENCE_MIN)


func test_the_map_glyphs_and_the_placement_reasons_read_apart_at_32_px_in_greyscale() -> void:
	var names: Array[String] = []
	for reason: String in REASONS:
		names.append("glyph_reason_" + reason)
	names.append_array(MAP_GLYPHS)
	assert_float(_closest_pair(names)).is_greater_equal(MAP_DIFFERENCE_MIN)


## An item icon is named by the art id of what it builds: a building's `buildings/<id>_hull.svg`
## or a unit's `units/<id>_hull.svg`, so the sidebar finds the icon by the type id alone.
func test_every_item_icon_is_named_after_an_existing_building_or_unit_art_id() -> void:
	for icon: String in ITEMS:
		var id: String = icon.trim_prefix("item_")
		var building: String = "res://assets/art/svg/buildings/%s_hull.svg" % id
		var unit: String = "res://assets/art/svg/units/%s_hull.svg" % id
		(
			assert_bool(ResourceLoader.exists(building) or ResourceLoader.exists(unit))
			. override_failure_message(icon)
			. is_true()
		)
	assert_bool(ResourceLoader.exists(ICON_ART % "item_headquarters")).is_false()


## The foot of the pole is the canvas centre: the hull is opaque there and holds the pole above it,
## the team layer is clear there (a ring or a frame round it) and holds the cloth beside the pole.
func test_the_rally_flags_stand_on_the_canvas_centre_with_cloth_beside_the_pole() -> void:
	for flag: String in FLAGS:
		var hull: Image = _image(FLAG_ART % [flag, "hull"])
		var team: Image = _image(FLAG_ART % [flag, "team"])
		assert_float(hull.get_pixel(32, 32).a).override_failure_message(flag).is_equal(1.0)
		assert_float(hull.get_pixel(32, 16).a).override_failure_message(flag).is_equal(1.0)
		assert_float(hull.get_pixel(32, 49).a).override_failure_message(flag).is_less(0.05)
		assert_float(team.get_pixel(32, 32).a).override_failure_message(flag).is_less(0.05)
		assert_float(team.get_pixel(44, 14).a).override_failure_message(flag).is_equal(1.0)
		assert_float(team.get_pixel(28, 14).a).override_failure_message(flag).is_less(0.05)


## The two tabs' flags differ by shape (STYLE.md): a ring with a pennant, a frame with a banner.
func test_the_two_rally_flags_differ_in_shape_not_only_in_colour() -> void:
	var infantry: Image = _image(FLAG_ART % ["rally_infantry", "team"])
	var vehicles: Image = _image(FLAG_ART % ["rally_vehicles", "team"])
	var common: int = 0
	var either: int = 0
	for y: int in 64:
		for x: int in 64:
			var a: bool = infantry.get_pixel(x, y).a > 0.5
			var b: bool = vehicles.get_pixel(x, y).a > 0.5
			common += int(a and b)
			either += int(a or b)
	assert_float(float(common) / float(either)).is_less(0.6)


func test_the_style_guide_names_every_icon_and_flag_file_and_the_tints_the_gallery_uses() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	for icon: String in _all_icons():
		assert_str(style).override_failure_message(icon).contains("`%s.svg`" % icon)
	for flag: String in FLAGS:
		assert_str(style).contains("flags/%s_{hull,team}.svg" % flag)
	var start: int = style.find("## Icons and glyphs")
	assert_int(start).is_greater(-1)
	var section: String = style.substr(start, style.find("\n## ", start + 1) - start)
	for icon: String in Gallery.GLYPH_TINTS:
		var tint: String = "#" + (Gallery.GLYPH_TINTS[icon] as Color).to_html(false).to_upper()
		assert_str(section).override_failure_message(icon + " " + tint).contains(tint)
		assert_array(_all_icons()).override_failure_message(icon).contains([icon])
	assert_str(section).contains("Import scale 1.0 (new)")
	assert_str(section).contains("glyph_reason_<reason>")


func _all_icons() -> Array[String]:
	var icons: Array[String] = []
	icons.append_array(_grey_icons())
	icons.append_array(ITEMS)
	return icons


## The tabs and the glyphs: the files in greys that the HUD tints.
func _grey_icons() -> Array[String]:
	var icons: Array[String] = []
	icons.append_array(TABS)
	icons.append_array(HUD_GLYPHS)
	icons.append_array(MAP_GLYPHS)
	for reason: String in REASONS:
		icons.append("glyph_reason_" + reason)
	return icons


func _import_text(path: String) -> String:
	return FileAccess.get_file_as_string(path + ".import")


## The raster of a texture as RGBA8, so a pixel reads the same whatever the import chose.
func _image(path: String) -> Image:
	var image: Image = (load(path) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## The icon at 32 px (scale 0.25 of its 128 px canvas, as the readability check does), over the
## HUD backdrop, as the luminance of each pixel, 0 to 255.
func _grey_at_32(icon: String) -> PackedFloat32Array:
	var image: Image = Image.new()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ICON_ART % icon)
	assert_int(image.load_svg_from_buffer(bytes, 0.25)).is_equal(OK)
	image.convert(Image.FORMAT_RGBA8)
	var grey: PackedFloat32Array = PackedFloat32Array()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = HUD_BACKDROP.lerp(image.get_pixel(x, y), image.get_pixel(x, y).a)
			grey.append(255.0 * (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b))
	return grey


## The smallest mean absolute difference between the 32 px greyscale rasters of two of `names`.
func _closest_pair(names: Array[String]) -> float:
	var rasters: Array[PackedFloat32Array] = []
	for icon: String in names:
		rasters.append(_grey_at_32(icon))
	var closest: float = 255.0
	for i: int in names.size():
		for j: int in range(i + 1, names.size()):
			var total: float = 0.0
			for k: int in rasters[i].size():
				total += absf(rasters[i][k] - rasters[j][k])
			var mean: float = total / rasters[i].size()
			if mean < closest:
				closest = mean
	return closest
