extends GdUnitTestSuite
## The repair drone's art (plan row P280, ADR 0037 section 14, STYLE.md "Drone effect"): the
## hand-written atlas `fx/drone_atlas.svg`, 240 x 72 at 2x (120 x 36 px after the 0.5 import
## scale), with the drone in two rotor-blur frames and its shadow, each in a clear cell of 40 x 36
## px. tests/art/test_art_assets.gd holds it to the technical rules of every SVG; this suite adds
## what is particular to it: the region table of `DroneArt`, ink in every cell and none outside,
## no team colour and no key-band hue (the drone carries none), a mint light in the frames, and
## the two frames differing only in their rotors.

const KEY_COLOURS: PackedStringArray = [
	"#FF9446", "#E8681F", "#B04B12", "#62D6EE", "#1FA6C8", "#137C99"
]
const BAND_DEGREES: float = 20.0
const SATURATION_FLOOR: float = 0.30
const VALUE_FLOOR: float = 0.55
const INK_ALPHA: float = 0.3
const MIN_OPAQUE_PX: int = 60
const MINT_TOLERANCE: float = 0.12  ## Summed channel difference, 0 to 3.
const MINT_MIN_PX: int = 4


func test_the_atlas_is_a_hand_written_svg_of_the_canvas_the_table_names() -> void:
	var text: String = FileAccess.get_file_as_string(DroneArt.ART)
	assert_int(text.to_utf8_buffer().size()).is_less(28672)
	var lines: PackedStringArray = text.split("\n")
	assert_str(lines[0]).starts_with("<!-- ")
	assert_str(lines[1]).starts_with("<!-- Silhouette: ")
	assert_str(text).contains('width="240" height="72" viewBox="0 0 240 72"')
	assert_str(FileAccess.get_file_as_string(DroneArt.ART + ".import")).contains("svg/scale=0.5")
	var texture: Texture2D = load(DroneArt.ART) as Texture2D
	assert_vector(texture.get_size()).is_equal(Vector2(DroneArt.SIZE_PX))
	assert_int(DroneArt.REGIONS.size()).is_equal(DroneArt.FRAMES)
	assert_that(DroneArt.region(0)).is_equal(DroneArt.REGIONS[0])
	assert_that(DroneArt.region(3)).is_equal(DroneArt.REGIONS[1])
	# The table in the file's own comment is the one the code holds.
	assert_str(lines[2]).contains("drone_0 0,0,40,36; drone_1 40,0,40,36; shadow 80,0,40,36")


func test_every_cell_has_ink_and_nothing_lies_outside_the_cells() -> void:
	var image: Image = (load(DroneArt.ART) as Texture2D).get_image()
	var cells: Array[Rect2i] = DroneArt.REGIONS.duplicate()
	cells.append(DroneArt.SHADOW)
	var inside: int = 0
	for cell: Rect2i in cells:
		var opaque: int = 0
		for y: int in range(cell.position.y, cell.end.y):
			for x: int in range(cell.position.x, cell.end.x):
				opaque += int(image.get_pixel(x, y).a > INK_ALPHA)
		assert_int(opaque).override_failure_message(str(cell)).is_greater(MIN_OPAQUE_PX)
		inside += opaque
	var total: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			total += int(image.get_pixel(x, y).a > INK_ALPHA)
	assert_int(total).is_equal(inside)
	# Each cell's ink keeps one pixel off the cell's edge, so a frame never touches the next.
	for cell: Rect2i in cells:
		for x: int in range(cell.position.x, cell.end.x):
			assert_float(image.get_pixel(x, cell.position.y).a).is_less_equal(INK_ALPHA)
			assert_float(image.get_pixel(x, cell.end.y - 1).a).is_less_equal(INK_ALPHA)


func test_no_colour_of_the_atlas_is_in_a_team_key_band() -> void:
	var text: String = FileAccess.get_file_as_string(DroneArt.ART).to_upper()
	for key: String in KEY_COLOURS:
		assert_bool(text.contains(key)).override_failure_message(key).is_false()
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	for found: RegExMatch in hex.search_all(text):
		var colour: Color = Color(found.get_string())
		if colour.s < SATURATION_FLOOR or colour.v < VALUE_FLOOR:
			continue
		for key: String in KEY_COLOURS:
			var gap: float = absf(colour.h - Color(key).h) * 360.0
			gap = minf(gap, 360.0 - gap)
			(
				assert_bool(gap > BAND_DEGREES)
				. override_failure_message("%s near %s" % [found.get_string(), key])
				. is_true()
			)


func test_the_two_frames_have_a_mint_light_and_differ_in_their_rotors_only() -> void:
	var image: Image = (load(DroneArt.ART) as Texture2D).get_image()
	var first: Rect2i = DroneArt.REGIONS[0]
	var second: Rect2i = DroneArt.REGIONS[1]
	var mint: Color = Color("#A8F5B0")
	var same_body: int = 0
	var differing: int = 0
	for y: int in first.size.y:
		for x: int in first.size.x:
			var a: Color = image.get_pixel(first.position.x + x, y)
			var b: Color = image.get_pixel(second.position.x + x, y)
			if a.is_equal_approx(b):
				same_body += int(a.a > INK_ALPHA)
			else:
				differing += 1
	assert_int(differing).is_greater(10)
	assert_int(same_body).is_greater(differing)  # The body, arms and lights are the same.
	for cell: Rect2i in [first, second]:
		var lit: int = 0
		for y: int in range(cell.position.y, cell.end.y):
			for x: int in range(cell.position.x, cell.end.x):
				var pixel: Color = image.get_pixel(x, y)
				lit += int(pixel.a > 0.9 and _gap(pixel, mint) < MINT_TOLERANCE)
		assert_int(lit).override_failure_message(str(cell)).is_greater(MINT_MIN_PX)


func _gap(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
