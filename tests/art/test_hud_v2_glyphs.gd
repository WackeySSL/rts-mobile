extends GdUnitTestSuite
## The fourteen glyphs of the corner HUD (plan row P118g, ADR 0025 and ADR 0026). What
## tests/art/test_icon_art.gd asks of every glyph (a 128 px canvas, greys only, nothing in the outer
## 2 px, a shape line, readable apart at 32 px in greyscale) it asks of these too, as they are in
## its lists: thirteen in its HUD group and `glyph_construct`, which is drawn over a building on the
## map, in its map group with the seat that keeps it apart from the ground. This suite adds the
## margin the thirteen keep from every other glyph of the HUD group and the shape each of the
## fourteen is meant to have, so a redraw cannot turn the Deselect glyph into the padlock or the
## cross, the pennant into a white flag, the collapse arrows outward, the chevron off its centre or
## the crane mast into an aerial.

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
## The one of the fourteen that is a map glyph, on a seat (test_icon_art.gd's map group).
const MAP_GLYPH: String = "glyph_construct"
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
## the strike's cancel), and not the offline glyph (a slash across a picture): at least this far
## from each.
const DESELECT_DIFFERENCE_MIN: float = 40.0
## A pixel of the drawing is light (white or the grey shade, red 0.75 or more) or dark (the edge
## grey and the seat, 0.30), whatever it lies on.
const LIGHT_MIN: float = 0.7
const DARK_MAX: float = 0.4


func test_the_fourteen_glyphs_are_the_gallerys_first_three_hud_rows_and_have_files() -> void:
	var rows: Array[String] = []
	for row_name: String in Gallery.HUD_V2_NEW_ROWS:
		rows.append_array(Gallery.HUD_V2_ROWS[row_name])
	assert_array(rows).is_equal(HUD_V2_GLYPHS)
	assert_int(HUD_V2_GLYPHS.size()).is_equal(14)
	for icon: String in HUD_V2_GLYPHS:
		assert_bool(ResourceLoader.exists(ICON_ART % icon)).override_failure_message(icon).is_true()
	assert_bool(Gallery.MAP_GLYPHS.has(MAP_GLYPH)).is_true()
	assert_bool(Gallery.HUD_SITE_BADGES.has(MAP_GLYPH)).is_true()


func test_each_hud_glyph_of_the_thirteen_is_at_least_29_from_every_other_at_32_px() -> void:
	var thirteen: Array[String] = HUD_V2_GLYPHS.filter(
		func(icon: String) -> bool: return icon != MAP_GLYPH
	)
	var group: Array[String] = []
	group.append_array(OLD_HUD_GLYPHS)
	group.append_array(thirteen)
	var problems: Array[String] = []
	for icon: String in thirteen:
		for other: String in group:
			if other != icon and _difference(icon, other) < HUD_V2_DIFFERENCE_MIN:
				problems.append("%s against %s" % [icon, other])
	assert_array(problems).is_empty()


## ADR 0025 section 9: a broken selection ring, not the padlock, not the cross and not the offline
## glyph's slash.
func test_the_deselect_glyph_is_neither_the_padlock_nor_the_cross_nor_the_offline_slash() -> void:
	for other: String in ["glyph_lock", "glyph_cross", "glyph_offline"]:
		(
			assert_float(_difference("glyph_deselect", other))
			. override_failure_message(other)
			. is_greater_equal(DESELECT_DIFFERENCE_MIN)
		)


## The flat two-to-one oval ring (the game's own selection ellipse) is much wider than tall: the
## ends of its middle row (at least 105 px apart) and its top are ink, the space over and under it
## (a round ring of that width would reach it) and the corners of the canvas are clear, and one
## slash runs through it from the upper left to the lower right and out of it at both ends.
func test_the_deselect_glyph_is_a_flat_oval_ring_cut_by_a_diagonal_slash() -> void:
	var image: Image = _image("glyph_deselect")
	_assert_ink(image, [Vector2i(8, 66), Vector2i(120, 66), Vector2i(50, 40)], true)
	_assert_ink(image, [Vector2i(64, 22), Vector2i(64, 110), Vector2i(110, 24)], false)
	_assert_ink(image, [Vector2i(18, 108), Vector2i(8, 8), Vector2i(120, 120)], false)
	_assert_ink(image, [Vector2i(46, 48), Vector2i(96, 100), Vector2i(30, 28)], true)
	assert_int(_rightmost(image, 66) - _leftmost(image, 66)).is_greater(105)


## A square inside a ring, with clear space between them.
func test_the_stop_glyph_is_a_square_in_a_ring_with_a_gap() -> void:
	var image: Image = _image("glyph_stop")
	_assert_ink(image, [Vector2i(64, 64), Vector2i(50, 50), Vector2i(64, 17)], true)
	_assert_ink(image, [Vector2i(111, 64), Vector2i(17, 64), Vector2i(64, 111)], true)
	_assert_ink(image, [Vector2i(64, 36), Vector2i(36, 64), Vector2i(8, 8)], false)
	_assert_ink(image, [Vector2i(120, 120), Vector2i(120, 8), Vector2i(8, 120)], false)


## The chevron points right (the code turns it for the other directions): the row through its tip
## reaches much further right than the rows of its arms' ends, and the arms' ends lie further left.
## It is centred on the canvas, because the code rotates it about the canvas centre.
func test_the_chevron_points_right_and_is_centred_for_the_code_that_turns_it() -> void:
	var image: Image = _image("glyph_chevron")
	var tip: int = _rightmost(image, 64)
	assert_int(tip).is_greater(95)
	for y: int in [26, 102]:
		assert_int(_rightmost(image, y)).override_failure_message(str(y)).is_less(tip - 30)
	assert_int(_leftmost(image, 26)).is_less(_leftmost(image, 64) - 8)
	assert_int(_leftmost(image, 102)).is_less(_leftmost(image, 64) - 8)
	var box: Rect2i = _ink_box(image)
	assert_float(box.position.x + box.size.x / 2.0).is_equal_approx(64.0, 1.5)
	assert_float(box.position.y + box.size.y / 2.0).is_equal_approx(64.0, 1.5)


## ADR 0025: a pennant, not a white flag, struck down to the foot of the pole (the colours are
## struck). A pole with a ball on its top, and a triangle hanging from it low down that narrows to a
## point: a rectangular flag would be as tall at the tip as at the pole (the column of ink at x = 96
## is under half that at x = 50), and nothing hangs from the top of the pole.
func test_the_surrender_glyph_is_a_pennant_struck_down_the_pole() -> void:
	var image: Image = _image("glyph_surrender")
	_assert_ink(image, [Vector2i(34, 17), Vector2i(34, 40), Vector2i(34, 111)], true)
	_assert_ink(image, [Vector2i(60, 80), Vector2i(100, 88), Vector2i(20, 111)], true)
	_assert_ink(image, [Vector2i(60, 30), Vector2i(100, 40), Vector2i(112, 30)], false)
	_assert_ink(image, [Vector2i(100, 100), Vector2i(70, 100), Vector2i(8, 60)], false)
	assert_int(_column_ink(image, 96)).is_less(_column_ink(image, 50) / 2)


## The two arrows point inward: their heads, wide ends outward, stand near the middle, with the
## tips facing each other across a small gap and a shaft running out to each corner.
func test_the_collapse_arrows_point_at_each_other() -> void:
	var image: Image = _image("glyph_collapse")
	_assert_ink(image, [Vector2i(80, 50), Vector2i(48, 78), Vector2i(100, 28)], true)
	_assert_ink(image, [Vector2i(28, 100), Vector2i(106, 22), Vector2i(22, 106)], true)
	_assert_ink(image, [Vector2i(64, 64), Vector2i(112, 40), Vector2i(16, 88)], false)
	_assert_ink(image, [Vector2i(20, 20), Vector2i(108, 108), Vector2i(8, 120)], false)


## Three bars, level and of one length, in a column with clear gaps between them.
func test_the_menu_glyph_is_three_level_bars() -> void:
	var image: Image = _image("glyph_menu")
	assert_int(_ink_runs_in_column(image, 64)).is_equal(3)
	assert_int(_ink_runs_in_column(image, 20)).is_equal(3)
	assert_int(_ink_runs_in_column(image, 108)).is_equal(3)
	for y: int in [32, 64, 96]:
		assert_int(_rightmost(image, y) - _leftmost(image, y)).is_greater(95)
	_assert_ink(image, [Vector2i(8, 8), Vector2i(120, 120), Vector2i(64, 14)], false)


## A soldier in front of a small tank, so that "all army" shows an infantryman and a vehicle: a
## helmeted head on the left, a barrel and a track pod on the right, and nothing above the tank
## where a third head would be.
func test_the_all_army_glyph_is_a_soldier_in_front_of_a_tank() -> void:
	var image: Image = _image("glyph_all_army")
	_assert_ink(image, [Vector2i(36, 44), Vector2i(36, 100), Vector2i(112, 69)], true)
	_assert_ink(image, [Vector2i(86, 112), Vector2i(86, 84), Vector2i(86, 68)], true)
	_assert_ink(image, [Vector2i(100, 40), Vector2i(110, 20), Vector2i(8, 8)], false)
	_assert_ink(image, [Vector2i(120, 120), Vector2i(120, 60), Vector2i(4, 40)], false)


## A map glyph on a seat, over a building (ADR 0026 section 9): a mast with straight sides (two
## legs, a rung and crossed braces), a jib across its top with a grey counterweight at its back end
## and a hook down from its far end, all light on the dark seat, and the dark seat between the
## braces, so that it is a crane at a site and not an aerial or a pylon.
func test_the_construct_glyph_is_a_seated_crane_mast_with_a_jib_a_counterweight_and_a_hook(
) -> void:
	var image: Image = _image(MAP_GLYPH)
	# the seat: dark inside the rim, clear outside the rounded corners
	_assert_ink(
		image, [Vector2i(8, 8), Vector2i(120, 8), Vector2i(8, 120), Vector2i(120, 120)], false
	)
	_assert_ink(image, [Vector2i(16, 16), Vector2i(112, 112), Vector2i(64, 64)], true)
	_assert_dark(image, [Vector2i(30, 72), Vector2i(80, 72), Vector2i(80, 50), Vector2i(80, 86)])
	# the mast: both legs, the rung between them, the crossing of a brace; the legs are as far apart
	# at the top as at the foot
	_assert_light(image, [Vector2i(43, 80), Vector2i(64, 80), Vector2i(43, 44), Vector2i(64, 44)])
	_assert_light(image, [Vector2i(53, 68), Vector2i(53, 53), Vector2i(53, 83)])
	# the jib, the counterweight at its back end (left of the mast) and the hook's line
	_assert_light(image, [Vector2i(30, 29), Vector2i(80, 29), Vector2i(104, 29)])
	_assert_light(image, [Vector2i(26, 43), Vector2i(99, 50)])
	# the mast is open between its braces: dark seat inside it
	var dark_between: int = 0
	for y: int in range(40, 96):
		for x: int in range(46, 62):
			dark_between += int(image.get_pixel(x, y).r < DARK_MAX)
	assert_int(dark_between).override_failure_message("seat between the braces").is_greater(80)


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


## Each point of `points` is opaque if `ink`, otherwise clear.
func _assert_ink(image: Image, points: Array[Vector2i], ink: bool) -> void:
	for at: Vector2i in points:
		var alpha: float = image.get_pixelv(at).a
		var message: String = "%s should be %s" % [at, "ink" if ink else "clear"]
		if ink:
			assert_float(alpha).override_failure_message(message).is_greater(0.5)
		else:
			assert_float(alpha).override_failure_message(message).is_less(0.05)


func _assert_light(image: Image, points: Array[Vector2i]) -> void:
	for at: Vector2i in points:
		var pixel: Color = image.get_pixelv(at)
		assert_float(pixel.a).override_failure_message("%s is not ink" % at).is_greater(0.5)
		assert_float(pixel.r).override_failure_message("%s should be light" % at).is_greater(
			LIGHT_MIN
		)


func _assert_dark(image: Image, points: Array[Vector2i]) -> void:
	for at: Vector2i in points:
		var pixel: Color = image.get_pixelv(at)
		assert_float(pixel.a).override_failure_message("%s is not ink" % at).is_greater(0.5)
		assert_float(pixel.r).override_failure_message("%s should be dark" % at).is_less(DARK_MAX)


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


## The number of opaque pixels in column `x` for y from 0 to 100 (above the foot of a pole).
func _column_ink(image: Image, x: int) -> int:
	var count: int = 0
	for y: int in 101:
		count += int(image.get_pixel(x, y).a > 0.5)
	return count


## The number of separate runs of opaque pixels down column `x`.
func _ink_runs_in_column(image: Image, x: int) -> int:
	var runs: int = 0
	var inside: bool = false
	for y: int in 128:
		var ink: bool = image.get_pixel(x, y).a > 0.5
		runs += int(ink and not inside)
		inside = ink
	return runs


## The box of the opaque pixels.
func _ink_box(image: Image) -> Rect2i:
	var box: Rect2i = Rect2i(128, 128, 0, 0)
	var low: Vector2i = Vector2i(128, 128)
	var high: Vector2i = Vector2i(-1, -1)
	for y: int in 128:
		for x: int in 128:
			if image.get_pixel(x, y).a > 0.5:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	box.position = low
	box.size = high - low + Vector2i.ONE
	return box
