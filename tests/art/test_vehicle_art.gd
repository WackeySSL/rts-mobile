extends GdUnitTestSuite
## The unit art of plan row P92 (Phase 3): the heavy tank, the artillery and the harvester, as
## STYLE.md ("Heavy tank, artillery and harvester") describes them. One canvas per unit, grey team
## layers, a team share of 20-35 % at every turret heading, a gun that sticks out of the hull as its
## own shape, a turret shaded the same either side of the gun line but for one sight hatch, and the
## harvester's empty bin where the cargo cue of P84b will fill it. The gallery page that shows them
## is in test_art_gallery_icon_pages.gd.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNIT_ART: String = "res://assets/art/svg/units/%s_%s.svg"
## The imported canvas of each new unit: the 2x canvas at import scale 0.5.
const SIDE_PX: Dictionary[String, int] = {"heavy_tank": 64, "artillery": 64, "harvester": 80}
const TURRETED: Array[String] = ["heavy_tank", "artillery"]
## The colours the new unit art may use: STYLE.md's palette, the team layer greys and the two dirt
## tones that STYLE.md marks as new (the harvester's bin floor and its lit lip).
const PALETTE: PackedStringArray = [
	"#1C2127",
	"#000000",
	"#5B6670",
	"#7D8893",
	"#A9B4BE",
	"#4E5A3A",
	"#6B7A4F",
	"#8C9A6B",
	"#6F583B",
	"#A3865E",
	"#FFFFFF",
	"#BFBFBF",
	"#4D4D4D",
]
## The sight hatch of each gun head and its mirror image about the gun line, in imported px: the one
## place where the two sides of the gun line may differ (heavy tank: a hatch, centre 23.5,27.5 and
## radius 3; artillery: a sight block, x 25 to 31, y 25.5 to 28).
const HATCH_BOXES: Dictionary[String, Rect2i] = {
	"heavy_tank": Rect2i(19, 23, 10, 18),
	"artillery": Rect2i(24, 25, 8, 14),
}
const HATCH_MIN_PIXELS: int = 8
const SHARE_MIN: float = 0.20
const SHARE_MAX: float = 0.35
## The gun is its own shape in the silhouette at 32 px when it is 3 px long and 3 px thick there,
## which is 6 and 6 px in the imported raster. Every column of it is at least 5 px thick.
const GUN_REACH_MIN_PX: int = 6
const GUN_THICK_MIN_PX: int = 6
const GUN_COLUMN_MIN_PX: int = 5
## The harvester's bin floor as STYLE.md gives it, in imported px: x 16 to 45, y 28 to 52.
const BIN_BOX: Rect2i = Rect2i(16, 28, 29, 24)
const BIN_FLOOR: String = "6f583b"


func test_every_new_unit_layer_is_one_canvas_at_half_scale_and_the_harvester_has_no_turret(
) -> void:
	for unit: String in SIDE_PX:
		for layer: String in ["hull", "team"]:
			var size: Vector2 = (load(UNIT_ART % [unit, layer]) as Texture2D).get_size()
			assert_vector(size).override_failure_message(unit + layer).is_equal(
				Vector2.ONE * SIDE_PX[unit]
			)
		var turret: String = UNIT_ART % [unit, "turret"]
		assert_bool(ResourceLoader.exists(turret)).override_failure_message(unit).is_equal(
			TURRETED.has(unit)
		)
	for unit: String in TURRETED:
		var size: Vector2 = (load(UNIT_ART % [unit, "turret"]) as Texture2D).get_size()
		assert_vector(size).is_equal(Vector2(64, 64))
	var found: Array[String] = []
	for path: String in FileScan.list_files("res://assets/art/svg/units", ".svg"):
		var base: String = path.get_file().get_basename()
		if SIDE_PX.keys().any(func(unit: String) -> bool: return base.begins_with(unit + "_")):
			found.append(base)
	assert_array(found).has_size(SIDE_PX.size() * 2 + TURRETED.size())


func test_the_new_team_layers_hold_only_greys() -> void:
	for unit: String in SIDE_PX:
		var image: Image = _image(UNIT_ART % [unit, "team"])
		var colored: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				colored += int(pixel.a > 0.0 and not (pixel.r == pixel.g and pixel.g == pixel.b))
		assert_int(colored).override_failure_message(unit).is_equal(0)


func test_the_visible_team_share_is_20_to_35_percent_at_every_turret_heading() -> void:
	for unit: String in SIDE_PX:
		for heading: int in [0, 90, 180, 270] if TURRETED.has(unit) else [0]:
			var share: float = _team_share(unit, heading)
			assert_float(share).override_failure_message("%s at %d" % [unit, heading]).is_between(
				SHARE_MIN, SHARE_MAX
			)


## At heading 0 the gun leaves the hull (and its team marks) as its own shape: columns of turret
## ink to the right of the last column of hull ink, long and thick enough for the 32 px check.
func test_the_gun_of_each_armed_unit_sticks_out_of_the_hull_as_its_own_shape() -> void:
	for unit: String in TURRETED:
		var hull: Image = _image(UNIT_ART % [unit, "hull"])
		var team: Image = _image(UNIT_ART % [unit, "team"])
		var gun: Image = _image(UNIT_ART % [unit, "turret"])
		var last_hull: int = 0
		for y: int in hull.get_height():
			for x: int in hull.get_width():
				if hull.get_pixel(x, y).a > 0.5 or team.get_pixel(x, y).a > 0.5:
					last_hull = maxi(last_hull, x)
		var reach: int = 0
		var thick: int = 0
		var thinnest: int = 999
		for x: int in range(last_hull + 1, gun.get_width()):
			var column: int = 0
			for y: int in gun.get_height():
				column += int(gun.get_pixel(x, y).a > 0.5)
			if column > 0:
				reach += 1
				thick = maxi(thick, column)
				thinnest = mini(thinnest, column)
		assert_int(reach).override_failure_message(unit).is_greater_equal(GUN_REACH_MIN_PX)
		assert_int(thick).override_failure_message(unit).is_greater_equal(GUN_THICK_MIN_PX)
		assert_int(thinnest).override_failure_message(unit).is_greater_equal(GUN_COLUMN_MIN_PX)


## The gun head turns about the canvas centre, so its shading is the same either side of the gun
## line (STYLE.md, "Rotating layers"): outside the box of the sight hatch and its mirror image the
## raster is its own mirror image about the middle row, to within the antialiasing of one level.
func test_each_gun_head_is_mirrored_about_the_gun_line_but_for_its_sight_hatch() -> void:
	for unit: String in TURRETED:
		var gun: Image = _image(UNIT_ART % [unit, "turret"])
		var box: Rect2i = HATCH_BOXES[unit]
		var side: int = gun.get_height()
		var wrong: int = 0
		for y: int in side / 2:
			for x: int in gun.get_width():
				if (
					not box.has_point(Vector2i(x, y))
					and not box.has_point(Vector2i(x, side - 1 - y))
				):
					wrong += int(_differs(gun.get_pixel(x, y), gun.get_pixel(x, side - 1 - y)))
		assert_int(wrong).override_failure_message(unit).is_equal(0)


## The same rule asks for one off-axis detail so the heading reads: inside that box the two sides
## differ, because the hatch sits on the upper side only.
func test_each_gun_head_has_one_off_axis_sight_hatch_on_the_upper_side() -> void:
	for unit: String in TURRETED:
		var gun: Image = _image(UNIT_ART % [unit, "turret"])
		var box: Rect2i = HATCH_BOXES[unit]
		var side: int = gun.get_height()
		var differing: int = 0
		for y: int in range(box.position.y, box.position.y + box.size.y):
			for x: int in range(box.position.x, box.end.x):
				if y < side / 2:
					differing += int(_differs(gun.get_pixel(x, y), gun.get_pixel(x, side - 1 - y)))
		assert_int(differing).override_failure_message(unit).is_greater_equal(HATCH_MIN_PIXELS)


## The bin is drawn empty: the floor is flat dirt-dark over the rectangle STYLE.md gives to the
## cargo cue, and the pixels beside the rectangle are the hull, not the floor.
func test_the_harvester_bin_floor_is_flat_dirt_in_the_rectangle_the_cargo_cue_fills() -> void:
	var hull: Image = _image(UNIT_ART % ["harvester", "hull"])
	var inner: Rect2i = BIN_BOX.grow(-4)
	var wrong: Array[String] = []
	for y: int in range(inner.position.y, inner.end.y):
		for x: int in range(inner.position.x, inner.end.x):
			if hull.get_pixel(x, y).to_html(false) != BIN_FLOOR:
				wrong.append("%d,%d" % [x, y])
	assert_array(wrong).is_empty()
	for outside: Vector2i in [
		Vector2i(10, 40), Vector2i(50, 40), Vector2i(30, 24), Vector2i(30, 56)
	]:
		assert_str(hull.get_pixelv(outside).to_html(false)).is_not_equal(BIN_FLOOR)


func test_every_new_unit_svg_names_its_shape_in_one_line_and_uses_palette_colours_only() -> void:
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	var problems: Array[String] = []
	var checked: int = 0
	for unit: String in SIDE_PX:
		for layer: String in ["hull", "team", "turret"]:
			var path: String = UNIT_ART % [unit, layer]
			if not ResourceLoader.exists(path):
				continue
			checked += 1
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
	assert_int(checked).is_equal(8)
	assert_array(problems).is_empty()


func test_the_style_guide_names_every_new_unit_file_and_quotes_its_numbers() -> void:
	var style: String = FileAccess.get_file_as_string("res://assets/art/STYLE.md")
	assert_str(style).contains("units/heavy_tank_{hull,team,turret}.svg")
	assert_str(style).contains("units/artillery_{hull,team,turret}.svg")
	assert_str(style).contains("units/harvester_{hull,team}.svg")
	assert_str(style).contains("x 32 to 90, y 56 to 104")
	assert_str(style).contains("x 16 to 45, y 28 to 52")


func _differs(a: Color, b: Color) -> bool:
	return absf(a.a - b.a) > 0.1 or absf(a.get_luminance() - b.get_luminance()) > 0.1


## The raster of a texture as RGBA8, so a pixel reads the same whatever the import chose.
func _image(path: String) -> Image:
	var image: Image = (load(path) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## The share of the vehicle's body that the team layer shows, in imported px, by the light tank's
## definition: the body is every pixel with ink in a layer (the shadow is 25 % ink and so is not
## counted) and a pixel under the turret is not team's. The turret turns by quarter turns, which a
## raster does exactly.
func _team_share(unit: String, heading: int) -> float:
	var hull: Image = _image(UNIT_ART % [unit, "hull"])
	var team: Image = _image(UNIT_ART % [unit, "team"])
	var gun: Image = null
	if ResourceLoader.exists(UNIT_ART % [unit, "turret"]):
		gun = _image(UNIT_ART % [unit, "turret"])
		for turn: int in heading / 90:
			gun.rotate_90(CLOCKWISE)
	var body: int = 0
	var shown: int = 0
	for y: int in hull.get_height():
		for x: int in hull.get_width():
			var covered: bool = gun != null and gun.get_pixel(x, y).a > 0.5
			var marked: bool = team.get_pixel(x, y).a > 0.5
			body += int(hull.get_pixel(x, y).a > 0.5 or marked or covered)
			shown += int(marked and not covered)
	return float(shown) / float(body)
