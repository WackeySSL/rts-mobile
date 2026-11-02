extends GdUnitTestSuite
## The fourteen glyphs of the corner HUD (plan row P118g, ADR 0025 and ADR 0026). What
## tests/art/test_icon_art.gd asks of every glyph (a 128 px canvas, greys only, nothing in the outer
## 2 px, a shape line, readable apart at 32 px in greyscale) it asks of these too, as they are in
## its lists. This suite adds the margin the new glyphs keep from every other glyph of the HUD group
## and the shape each one is meant to have, so a redraw cannot turn the Deselect glyph into the
## padlock or the cross, the pennant into a white flag, or the crane mast into an aerial.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const HUD_BACKDROP: Color = Color("0F141C")
## The fourteen, by the part of the HUD that uses them (the gallery's Hud page keeps the same rows).
const HUD_V2_GLYPHS: Array[String] = [
	"glyph_deselect",
	"glyph_stop",
	"glyph_all_army",
	"glyph_plus",
	"glyph_menu",
	"glyph_resume",
	"glyph_restart",
	"glyph_surrender",
	"glyph_exit",
	"glyph_vibration",
	"glyph_collapse",
	"glyph_chevron",
	"glyph_alert",
	"glyph_construct",
]
## The glyphs of the HUD group that were there before: the two result and build menu sets, the
## credits, the power and the requirement and placement glyphs.
const OLD_HUD_GLYPHS: Array[String] = [
	"glyph_credits",
	"glyph_power",
	"glyph_low_power",
	"glyph_lock",
	"glyph_check",
	"glyph_cross",
	"glyph_victory",
	"glyph_defeat",
	"glyph_draw",
	"glyph_menu_open",
	"glyph_pin",
	"glyph_pin_off",
]
## The old group's floor was 29.3 (the power bolt against the star): no new glyph is nearer than
## this to any glyph of the group, old or new, at 32 px in greyscale over the HUD backdrop.
const HUD_V2_DIFFERENCE_MIN: float = 29.0
## The Deselect glyph is not the padlock (a missing requirement) and not the cross (placement's and
## the strike's cancel): at least this far from either.
const DESELECT_DIFFERENCE_MIN: float = 40.0


func test_the_fourteen_glyphs_are_the_gallerys_first_three_hud_rows_and_have_files() -> void:
	var rows: Array[String] = []
	for row_name: String in Gallery.HUD_V2_NEW_ROWS:
		rows.append_array(Gallery.HUD_V2_ROWS[row_name])
	assert_array(rows).is_equal(HUD_V2_GLYPHS)
	assert_int(HUD_V2_GLYPHS.size()).is_equal(14)
	for icon: String in HUD_V2_GLYPHS:
		assert_bool(ResourceLoader.exists(ICON_ART % icon)).override_failure_message(icon).is_true()


func test_each_new_glyph_is_at_least_29_from_every_other_hud_glyph_at_32_px() -> void:
	var group: Array[String] = []
	group.append_array(OLD_HUD_GLYPHS)
	group.append_array(HUD_V2_GLYPHS)
	var problems: Array[String] = []
	for icon: String in HUD_V2_GLYPHS:
		for other: String in group:
			if other != icon and _difference(icon, other) < HUD_V2_DIFFERENCE_MIN:
				problems.append("%s against %s" % [icon, other])
	assert_array(problems).is_empty()


## ADR 0025 section 9: a broken selection ring, not the padlock and not the cross.
func test_the_deselect_glyph_is_neither_the_padlock_nor_the_cross() -> void:
	for other: String in ["glyph_lock", "glyph_cross"]:
		(
			assert_float(_difference("glyph_deselect", other))
			. override_failure_message(other)
			. is_greater_equal(DESELECT_DIFFERENCE_MIN)
		)


## The oval ring is wider than tall (the ends of its middle row and its top are ink, the space over
## and under it and the corners of the canvas are clear), and one slash runs through it from the
## upper left to the lower right and out of it at both ends.
func test_the_deselect_glyph_is_a_wide_oval_ring_cut_by_a_diagonal_slash() -> void:
	var image: Image = _image("glyph_deselect")
	_assert_ink(image, [Vector2i(12, 66), Vector2i(116, 66), Vector2i(64, 37)], true)
	_assert_ink(image, [Vector2i(64, 18), Vector2i(64, 114), Vector2i(110, 24)], false)
	_assert_ink(image, [Vector2i(18, 108), Vector2i(8, 8), Vector2i(120, 120)], false)
	_assert_ink(image, [Vector2i(46, 48), Vector2i(96, 100), Vector2i(30, 28)], true)


## A square inside a ring, with clear space between them.
func test_the_stop_glyph_is_a_square_in_a_ring_with_a_gap() -> void:
	var image: Image = _image("glyph_stop")
	_assert_ink(image, [Vector2i(64, 64), Vector2i(50, 50), Vector2i(64, 17)], true)
	_assert_ink(image, [Vector2i(111, 64), Vector2i(17, 64), Vector2i(64, 111)], true)
	_assert_ink(image, [Vector2i(64, 36), Vector2i(36, 64), Vector2i(8, 8)], false)
	_assert_ink(image, [Vector2i(120, 120), Vector2i(120, 8), Vector2i(8, 120)], false)


## The chevron points right (the code turns it for the other directions): the row through its tip
## reaches much further right than the rows of its arms' ends, and the arms' ends lie further left.
func test_the_chevron_points_right() -> void:
	var image: Image = _image("glyph_chevron")
	var tip: int = _rightmost(image, 64)
	assert_int(tip).is_greater(95)
	for y: int in [26, 102]:
		assert_int(_rightmost(image, y)).override_failure_message(str(y)).is_less(tip - 30)
	assert_int(_leftmost(image, 26)).is_less(_leftmost(image, 64) - 8)
	assert_int(_leftmost(image, 102)).is_less(_leftmost(image, 64) - 8)


## ADR 0025: a pennant, not a white flag. A pole with a ball on its top, and a triangle hanging from
## it that narrows to a low point (a rectangular flag would cover the points over and under it).
func test_the_surrender_glyph_is_a_pennant_not_a_rectangular_flag() -> void:
	var image: Image = _image("glyph_surrender")
	_assert_ink(image, [Vector2i(34, 17), Vector2i(34, 60), Vector2i(50, 44)], true)
	_assert_ink(image, [Vector2i(100, 79), Vector2i(64, 62), Vector2i(34, 111)], true)
	_assert_ink(image, [Vector2i(100, 40), Vector2i(100, 100), Vector2i(112, 30)], false)
	_assert_ink(image, [Vector2i(70, 28), Vector2i(8, 60), Vector2i(120, 60)], false)


## A mast with a jib and a hook, so that it is a crane at a site and not an aerial: ink in the
## legs and a rung, along the jib and down the hook's line, open triangles between the braces, and
## clear space between the mast and the hook.
func test_the_construct_glyph_is_a_lattice_mast_with_a_jib_and_a_hook() -> void:
	var image: Image = _image("glyph_construct")
	_assert_ink(image, [Vector2i(28, 60), Vector2i(55, 60), Vector2i(41, 69)], true)
	_assert_ink(image, [Vector2i(80, 20), Vector2i(110, 20), Vector2i(102, 50)], true)
	_assert_ink(image, [Vector2i(94, 74), Vector2i(41, 108)], true)
	_assert_ink(image, [Vector2i(41, 100), Vector2i(80, 60), Vector2i(80, 100)], false)
	_assert_ink(image, [Vector2i(120, 100), Vector2i(8, 8), Vector2i(120, 120)], false)
	var open_between: int = 0
	for y: int in range(46, 104):
		for x: int in range(28, 56):
			open_between += int(image.get_pixel(x, y).a < 0.05)
	assert_int(open_between).override_failure_message("open pixels in the mast").is_greater(100)


## The Alert glyph is a disc with its mark, not a ring: the middle is ink and the corners clear.
func test_the_alert_glyph_is_a_filled_disc_with_a_mark_in_it() -> void:
	var image: Image = _image("glyph_alert")
	_assert_ink(image, [Vector2i(64, 64), Vector2i(64, 110), Vector2i(20, 64)], true)
	_assert_ink(image, [Vector2i(8, 8), Vector2i(120, 8), Vector2i(8, 120)], false)
	# the dark mark is darker than the white disc round it
	var mark: float = image.get_pixel(64, 40).r
	var disc: float = image.get_pixel(30, 64).r
	assert_float(mark).is_less(0.4)
	assert_float(disc).is_greater(0.9)


## Each ink point of `points` is opaque if `ink`, otherwise clear.
func _assert_ink(image: Image, points: Array[Vector2i], ink: bool) -> void:
	for at: Vector2i in points:
		var alpha: float = image.get_pixelv(at).a
		var message: String = "%s should be %s" % [at, "ink" if ink else "clear"]
		if ink:
			assert_float(alpha).override_failure_message(message).is_greater(0.5)
		else:
			assert_float(alpha).override_failure_message(message).is_less(0.05)


## The glyph as RGBA8, so a pixel reads the same whatever the import chose.
func _image(icon: String) -> Image:
	var image: Image = (load(ICON_ART % icon) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## The mean absolute difference between two glyphs' 32 px greyscale rasters (each file rasterised
## at scale 0.25 and composited over the HUD backdrop), 0 to 255: the measure of test_icon_art.gd.
func _difference(a: String, b: String) -> float:
	var left: PackedFloat32Array = _grey_at_32(a)
	var right: PackedFloat32Array = _grey_at_32(b)
	var total: float = 0.0
	for k: int in left.size():
		total += absf(left[k] - right[k])
	return total / left.size()


func _grey_at_32(icon: String) -> PackedFloat32Array:
	var image: Image = Image.new()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ICON_ART % icon)
	assert_int(image.load_svg_from_buffer(bytes, 0.25)).is_equal(OK)
	image.convert(Image.FORMAT_RGBA8)
	var grey: PackedFloat32Array = PackedFloat32Array()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			var seen: Color = HUD_BACKDROP.lerp(pixel, pixel.a)
			grey.append(255.0 * (0.299 * seen.r + 0.587 * seen.g + 0.114 * seen.b))
	return grey


## The x of the rightmost opaque pixel of row `y`, or -1.
func _rightmost(image: Image, y: int) -> int:
	for x: int in range(127, -1, -1):
		if image.get_pixel(x, y).a > 0.5:
			return x
	return -1


## The x of the leftmost opaque pixel of row `y`, or 128.
func _leftmost(image: Image, y: int) -> int:
	for x: int in 128:
		if image.get_pixel(x, y).a > 0.5:
			return x
	return 128
