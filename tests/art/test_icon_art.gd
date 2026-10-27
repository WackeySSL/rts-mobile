extends GdUnitTestSuite
## The icon and flag art of plan row P92 (Phase 3), as STYLE.md ("Icons and glyphs", "Rally flags")
## describes it: the three tab icons, the eleven item icons and the seventeen glyphs, 128 px
## canvases at import scale 1.0, tab and glyph files in greys only, item icons in palette colours,
## nothing on the outer pixel, and icons that read apart at 32 px in greyscale over the HUD
## backdrop; the eight glyphs of the map on a dark seat that keeps them apart from grass, sand and
## the red ghost, read apart as the HUD tints them; and the two rally flags, a hull and a grey team
## layer each, with the foot of the pole at the canvas centre. The gallery pages that show them are
## in test_art_gallery_icon_pages.gd.

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
## The factions' emblems (P103: the Derrick League's; P104 adds the Lumen Accord's), pinned in
## test_fossil_buildings.gd.
const EMBLEMS: Array[String] = ["emblem_fossil"]
## The colours the item icons and the flags may use: STYLE.md's palette with A's muted materials of
## ADR 0022 (the building icons use them; P92b brings the unit icons), the neutral team colour that
## a unit's item icon carries, and the greys of the team layer.
const PALETTE: PackedStringArray = [
	"#4A4F53",
	"#62676A",
	"#8D8F88",
	"#B3B4AC",
	"#6B6D68",
	"#5D6B68",
	"#A0ACA8",
	"#46532F",
	"#78885B",
	"#8F5731",
	"#B59F72",
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
## A map glyph is seen tinted, on a ground, and every one shares its seat, which is about three
## quarters of the canvas, so the mean over the canvas is smaller than for the HUD groups.
const MAP_DIFFERENCE_MIN: float = 9.0
## A map glyph must stand out from the ground under it: this share of its ink at 32 px differs from
## the ground by more than MAP_CONTRAST_LUMINANCE in luminance (0 to 255), on every ground below.
const MAP_CONTRAST_MIN: float = 0.5
const MAP_CONTRAST_LUMINANCE: float = 25.0
## The seat of a map glyph is #4D4D4D with a white rim; a plate, or a disc for the arrow that the
## HUD turns. Its dark edge is 3 px wide and the white rim inside it is 4 px wide.
const SEAT_GREY: float = 77.0 / 255.0
const SEAT_EDGE_PX: int = 3
const SEAT_RIM_PX: int = 4
## An icon covers a fifth to four fifths of its canvas, and its ink is clearly brighter than the
## backdrop (luminance 19): an item icon at least 60 of 255, a tab or glyph at least 140.
const COVER_MIN: float = 0.18
const COVER_MAX: float = 0.82
const ITEM_LUMINANCE_MIN: float = 60.0
const GLYPH_LUMINANCE_MIN: float = 140.0
## A map glyph's ink is its dark seat (#4D4D4D, luminance 77) and its light drawing, 120 to 150 on
## average, so it is below a tab's; what sets it apart from the ground is tested on the ground
## (MAP_CONTRAST_MIN).
const SEAT_LUMINANCE_MIN: float = 100.0


func test_the_icon_folder_holds_exactly_the_files_the_style_guide_lists() -> void:
	var expected: Array[String] = []
	expected.append_array(TABS)
	expected.append_array(ITEMS)
	expected.append_array(HUD_GLYPHS)
	expected.append_array(MAP_GLYPHS)
	for reason: String in REASONS:
		expected.append("glyph_reason_" + reason)
	expected.append_array(EMBLEMS)
	var found: Array[String] = []
	for path: String in FileScan.list_files(ICON_DIR, ".svg"):
		found.append(path.get_file().get_basename())
	expected.sort()
	assert_array(found).is_equal(expected)
	assert_int(found.size()).is_equal(32)


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
		var floor_value: float = GLYPH_LUMINANCE_MIN
		if icon.begins_with("item_"):
			floor_value = ITEM_LUMINANCE_MIN
		elif _map_glyphs().has(icon):
			floor_value = SEAT_LUMINANCE_MIN
		assert_float(luminance / count).override_failure_message(icon).is_greater(floor_value)


## The readability check of STYLE.md for icons: each file rasterised at 32 px, composited over the
## HUD backdrop and converted to greyscale; any two icons of a group differ by at least a margin.
func test_the_item_icons_read_apart_at_32_px_in_greyscale() -> void:
	assert_float(_closest_pair(ITEMS)).is_greater_equal(ITEM_DIFFERENCE_MIN)


func test_the_three_tabs_read_apart_at_32_px_in_greyscale() -> void:
	assert_float(_closest_pair(TABS)).is_greater_equal(TAB_DIFFERENCE_MIN)


func test_the_hud_glyphs_and_result_emblems_read_apart_at_32_px_in_greyscale() -> void:
	assert_float(_closest_pair(HUD_GLYPHS)).is_greater_equal(HUD_DIFFERENCE_MIN)


## The eight glyphs of the map are never seen white on the HUD: they are tinted (the gallery's
## `GLYPH_TINTS`) and lie on terrain or on the red ghost, so that is how they are compared.
func test_the_map_glyphs_and_the_placement_reasons_read_apart_at_32_px_in_greyscale() -> void:
	var grounds: Dictionary[String, Color] = _map_grounds()
	for ground_name: String in grounds:
		var closest: float = _closest_pair(_map_glyphs(), grounds[ground_name], true)
		assert_float(closest).override_failure_message(ground_name).is_greater_equal(
			MAP_DIFFERENCE_MIN
		)


## What the style guide's check "identifiable at 32 px in greyscale" means for a glyph on the map:
## tinted, over the ground it sits on, a good share of its ink differs from that ground. Without
## the seat the white body of a danger-tinted glyph (luminance 114) is as bright as grass (110) and
## only its thin edge sets it apart: on its worst ground 24 to 56 % of a glyph's ink stood out,
## and 56 % or more does now.
func test_the_map_glyphs_stand_out_from_every_ground_they_sit_on() -> void:
	var problems: Array[String] = []
	var grounds: Dictionary[String, Color] = _map_grounds()
	for icon: String in _map_glyphs():
		for ground_name: String in grounds:
			var share: float = _standing_out(icon, grounds[ground_name])
			if share < MAP_CONTRAST_MIN:
				problems.append("%s on %s: %.2f" % [icon, ground_name, share])
	assert_array(problems).is_empty()


## The seat is in the file: from each of the four sides, the first ink along the middle line is a
## dark edge and then the white rim. A plate for the reasons and the offline glyph (its corners are
## round and filled), a disc for the arrow (the corner at 16 px is clear). The corners of the canvas
## are clear. So a glyph is the same badge on any ground and keeps its seat when the HUD turns it.
func test_every_map_glyph_sits_on_a_dark_seat_with_a_white_rim() -> void:
	var sides: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var corners: Array[Vector2i] = [
		Vector2i(4, 4), Vector2i(123, 4), Vector2i(4, 123), Vector2i(123, 123)
	]
	for icon: String in _map_glyphs():
		var image: Image = _image(ICON_ART % icon)
		for step: Vector2i in sides:
			var at: Vector2i = (Vector2i(64, 64) - step * 64).clamp(
				Vector2i.ZERO, Vector2i(127, 127)
			)
			while image.get_pixel(at.x, at.y).a <= 0.5:
				at += step
			var edge: Vector2i = at + step * (SEAT_EDGE_PX - 2)
			var rim: Vector2i = at + step * (SEAT_EDGE_PX + SEAT_RIM_PX / 2)
			var label: String = "%s from %s" % [icon, step]
			var edge_pixel: Color = image.get_pixel(edge.x, edge.y)
			var rim_pixel: Color = image.get_pixel(rim.x, rim.y)
			assert_float(edge_pixel.r).override_failure_message(label).is_equal_approx(
				SEAT_GREY, 0.01
			)
			assert_float(edge_pixel.a).override_failure_message(label).is_equal(1.0)
			assert_float(rim_pixel.r).override_failure_message(label).is_equal(1.0)
			assert_float(rim_pixel.a).override_failure_message(label).is_equal(1.0)
		for corner: Vector2i in corners:
			(
				assert_float(image.get_pixel(corner.x, corner.y).a)
				. override_failure_message(icon)
				. is_less(0.05)
			)
		var is_disc: bool = icon == "glyph_under_attack"
		var inner_corner: float = image.get_pixel(16, 16).a
		assert_bool(inner_corner < 0.05).override_failure_message(icon).is_equal(is_disc)
		assert_bool(inner_corner > 0.5).override_failure_message(icon).is_equal(not is_disc)


## An item icon is named by the art id of what it builds: a building's model
## `models/fossil/<id>.tres` (P103: the oblique files are gone) or a unit's `units/<id>_hull.svg`,
## so the sidebar finds the icon by the type id alone.
func test_every_item_icon_is_named_after_an_existing_building_or_unit_art_id() -> void:
	for icon: String in ITEMS:
		var id: String = icon.trim_prefix("item_")
		var building: String = "res://assets/art/models/fossil/%s.tres" % id
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
	assert_str(section).contains("Map glyphs sit on a seat")


## The six placement reasons' glyphs and the other two glyphs of the map.
func _map_glyphs() -> Array[String]:
	var icons: Array[String] = []
	for reason: String in REASONS:
		icons.append("glyph_reason_" + reason)
	icons.append_array(MAP_GLYPHS)
	return icons


## The grounds a map glyph is seen on: the base colour of each terrain tile (a 1 texel edge line of
## a tile is not a ground) and the two areas of the ghost that does not fit, as the gallery draws
## it: the danger wash over grass, and the hatch band over that wash (STYLE.md, "Ghosts").
func _map_grounds() -> Dictionary[String, Color]:
	var grounds: Dictionary[String, Color] = {}
	for terrain: StringName in [&"grass", &"grass_b", &"sand", &"scrub", &"rock", &"water"]:
		grounds[String(terrain)] = Gallery.TERRAIN_COLORS[terrain]
	var wash: Color = Gallery.TERRAIN_COLORS[&"grass_b"].lerp(
		Gallery.GHOST_DANGER, Gallery.GHOST_WASH_ALPHA
	)
	grounds["ghost wash"] = wash
	grounds["ghost hatch"] = wash.lerp(Gallery.GHOST_DANGER, Gallery.GHOST_HATCH_ALPHA)
	return grounds


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


## The icon at 32 px (scale 0.25 of its 128 px canvas, as the readability check does), as RGBA8.
func _raster_32(icon: String) -> Image:
	var image: Image = Image.new()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ICON_ART % icon)
	assert_int(image.load_svg_from_buffer(bytes, 0.25)).is_equal(OK)
	image.convert(Image.FORMAT_RGBA8)
	return image


## The icon at 32 px over `ground` (the HUD backdrop unless given), tinted as the HUD tints it if
## `tinted`, as the luminance of each pixel, 0 to 255.
func _grey_at_32(
	icon: String, ground: Color = HUD_BACKDROP, tinted: bool = false
) -> PackedFloat32Array:
	var image: Image = _raster_32(icon)
	var tint: Color = Gallery.GLYPH_TINTS[icon] if tinted else Color.WHITE
	var grey: PackedFloat32Array = PackedFloat32Array()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			grey.append(_luminance(ground.lerp(pixel * tint, pixel.a)))
	return grey


## The share of the glyph's ink at 32 px, tinted as the HUD tints it, whose luminance differs from
## that of `ground` by more than MAP_CONTRAST_LUMINANCE.
func _standing_out(icon: String, ground: Color) -> float:
	var image: Image = _raster_32(icon)
	var tint: Color = Gallery.GLYPH_TINTS[icon]
	var ink: int = 0
	var apart: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.5:
				ink += 1
				var seen: float = _luminance(ground.lerp(pixel * tint, pixel.a))
				apart += int(absf(seen - _luminance(ground)) > MAP_CONTRAST_LUMINANCE)
	return float(apart) / float(ink)


func _luminance(colour: Color) -> float:
	return 255.0 * (0.299 * colour.r + 0.587 * colour.g + 0.114 * colour.b)


## The smallest mean absolute difference between the 32 px greyscale rasters of two of `names`,
## over the HUD backdrop untinted unless `ground` and `tinted` say how they are seen.
func _closest_pair(
	names: Array[String], ground: Color = HUD_BACKDROP, tinted: bool = false
) -> float:
	var rasters: Array[PackedFloat32Array] = []
	for icon: String in names:
		rasters.append(_grey_at_32(icon, ground, tinted))
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
