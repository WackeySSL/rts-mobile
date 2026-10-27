extends GdUnitTestSuite
## The item cards the generator writes and the selection ellipse (plan row P99b, ADR 0023 sections
## 3 and 5, STYLE.md "Generated art" and "Feedback markers"): a card is a 128 px dark plate with a
## faint 2:1 grid, a corner in the faction's key colour and the type's default view with its cast
## shadow, in polygons only; the ellipse is a 2:1 ring whose stroke is as wide on the short axis as
## on the long one.

const CARD_PX: int = 128
const PLATE: Color = Color("1C2127")
const RIM: Color = Color("2F363D")
const GRID: Color = Color("2A3036")
const ELLIPSE: String = "res://assets/art/svg/ui/selection_ellipse.svg"
const ALLOWED_TAGS: Array[String] = ["svg", "g", "polygon"]
const EDGE_PX: int = 5  ## The band along the card's edge that only the plate may touch.
const PICTURE_SHARE: Vector2 = Vector2(0.05, 0.6)  ## Of the inner plate, covered by the picture.
const KEY_CORNER_AT: Vector2i = Vector2i(10, 10)
const SMALL_PX: int = 32
const MIN_SPREAD: float = 60.0  ## Luminance, 5th to 95th percentile, 0 to 255.


func test_every_type_has_a_card_of_128_px_made_of_polygons_in_its_own_factions_colours() -> void:
	var tags: RegEx = RegEx.create_from_string("<([a-zA-Z]+)")
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var card: String = FileAccess.get_file_as_string(ArtGen.icon_path(model))
		var lines: PackedStringArray = card.split("\n")
		assert_str(lines[0]).contains(ArtGen.MARKER)
		assert_str(lines[0]).contains(String(model.art_id))
		assert_str(lines[1]).contains('width="128" height="128" viewBox="0 0 128 128"')
		assert_int(card.length()).override_failure_message(path).is_less(28 * 1024)
		for found: RegExMatch in tags.search_all(card):
			assert_array(ALLOWED_TAGS).override_failure_message(path).contains(
				[found.get_string(1)]
			)
		assert_bool(card.contains(ArtPalette.KEYS[model.faction][1])).is_true()
		var other: StringName = &"renew" if model.faction == &"fossil" else &"fossil"
		for key: String in ArtPalette.KEYS[other]:
			assert_bool(card.contains(key)).override_failure_message(path + " " + key).is_false()
		assert_bool(FileAccess.file_exists(ArtGen.icon_path(model) + ".import")).is_true()


func test_a_card_ends_in_the_default_view_of_the_hull_and_its_turret_over_the_shadow() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var dir: int = model.default_dir()
		assert_int(dir).is_equal(6 if model.faction == &"fossil" else 10)
		var want: Array[String] = _fills(
			FileAccess.get_file_as_string(
				ArtGen.frame_path(model, &"hull", -1 if model.category == &"bld" else dir)
			)
		)
		for part: StringName in [&"turret", &"head"]:
			if model.parts().has(part):
				want.append_array(
					_fills(FileAccess.get_file_as_string(ArtGen.frame_path(model, part, dir)))
				)
		var fills: Array[String] = _fills(FileAccess.get_file_as_string(ArtGen.icon_path(model)))
		(
			assert_array(fills.slice(fills.size() - want.size()))
			. override_failure_message(path)
			. is_equal(want)
		)
		# The shadow is under it: black polygons come before the first of the picture.
		var shadow: int = fills.find("#000000")
		assert_bool(shadow >= 0 and shadow < fills.size() - want.size() + 1).is_true()


func test_a_card_is_a_plate_with_a_faint_grid_a_key_corner_and_a_picture_inside_its_edge() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var image: Image = _raster(FileAccess.get_file_as_string(ArtGen.icon_path(model)))
		assert_vector(Vector2(image.get_size())).is_equal(Vector2(CARD_PX, CARD_PX))
		# The corners of the plate are cut, the corner is the key colour's mid tone.
		assert_float(image.get_pixel(0, 0).a).is_less(0.1)
		assert_float(image.get_pixel(64, 64).a).is_greater(0.99)
		var corner: Color = image.get_pixelv(KEY_CORNER_AT)
		var key: Color = Color(ArtPalette.KEYS[model.faction][1])
		assert_float(_distance(corner, key)).override_failure_message(path).is_less(0.03)
		var grid: int = 0
		var picture: int = 0
		var spill: int = 0
		for y: int in CARD_PX:
			for x: int in CARD_PX:
				var pixel: Color = image.get_pixel(x, y)
				var of_card: bool = pixel.a < 0.5 or _of_card(pixel)
				grid += int(pixel.a > 0.9 and _distance(pixel, GRID) < 0.02)
				var inner: bool = minf(minf(x, y), minf(CARD_PX - 1 - x, CARD_PX - 1 - y)) >= 6
				picture += int(inner and pixel.a > 0.9 and not of_card)
				var near_edge: bool = (
					minf(minf(x, y), minf(CARD_PX - 1 - x, CARD_PX - 1 - y)) < EDGE_PX
				)
				spill += int(near_edge and x + y > 40 and not of_card)
		assert_int(grid).override_failure_message(path + " grid").is_greater(300)
		assert_int(spill).override_failure_message(path + " spill").is_equal(0)
		var share: float = picture / float((CARD_PX - 12) * (CARD_PX - 12))
		assert_float(share).override_failure_message(path + " picture").is_between(
			PICTURE_SHARE.x, PICTURE_SHARE.y
		)


func test_a_card_is_identifiable_at_32_px_in_greyscale() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var small: Image = _raster(FileAccess.get_file_as_string(ArtGen.icon_path(model)))
		small.resize(SMALL_PX, SMALL_PX, Image.INTERPOLATE_LANCZOS)
		var grey: Array[float] = []
		for y: int in SMALL_PX:
			for x: int in SMALL_PX:
				var pixel: Color = small.get_pixel(x, y)
				if pixel.a > 0.9:
					grey.append((0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) * 255.0)
		grey.sort()
		# The picture is light on a dark plate: the spread of the tones says there is a body.
		var spread: float = grey[int(grey.size() * 0.95)] - grey[int(grey.size() * 0.05)]
		assert_float(spread).override_failure_message("%s spread %.0f" % [path, spread]).is_greater(
			MIN_SPREAD
		)


func test_the_selection_ellipse_is_a_2_to_1_ring_with_the_same_stroke_all_the_way_round() -> void:
	var texture: Texture2D = load(ELLIPSE)
	assert_vector(texture.get_size()).is_equal(Vector2(168, 96))
	var image: Image = texture.get_image()
	var drawn: String = FileAccess.get_file_as_string(ELLIPSE)
	assert_str(drawn).contains('rx="72" ry="36"')
	assert_str(drawn).contains('stroke-width="20"').contains('stroke-width="12"')
	# From the centre line outwards and inwards, along its normal, at 24 places round: the white
	# band 12 px wide (within 4 px of the line), the dark outline from 6 to 10 px, then clear. A
	# circle squashed to half its height would have a band half as wide at the top and bottom.
	for step: int in 24:
		var t: float = (step + 0.5) * TAU / 24.0
		var at: Vector2 = Vector2(84.0 + 72.0 * cos(t), 48.0 + 36.0 * sin(t))
		var normal: Vector2 = Vector2(cos(t) / 72.0, sin(t) / 36.0).normalized()
		for offset: int in range(-11, 12):
			var found: String = _ink(image.get_pixelv(Vector2i(at + normal * float(offset))))
			var want: String = ""
			if absi(offset) <= 4:
				want = "W"
			elif absi(offset) >= 7 and absi(offset) <= 8:
				want = "D"
			elif absi(offset) == 11:
				want = "."
			if want != "":
				(
					assert_str(found)
					. override_failure_message("step %d offset %d" % [step, offset])
					. is_equal(want)
				)


func test_the_gallery_scales_the_ellipse_by_the_semi_axis_the_texture_has() -> void:
	var gallery: GDScript = load("res://game/view/art_gallery_iso.gd")
	var constants: Dictionary = gallery.get_script_constant_map()
	assert_float(constants["RING_TEX_RX_PX"]).is_equal(72.0)
	assert_str(constants["RING_ART"]).is_equal(ELLIPSE)


func test_the_style_guide_states_the_ellipse_and_the_card() -> void:
	var guide: String = FileAccess.get_file_as_string("res://assets/art/STYLE.md")
	guide = RegEx.create_from_string("\\s+").sub(guide, " ", true)
	for words: String in [
		"168 x 96 px",
		"centre-line semi-axes 72 and 36 px",
		"`RING_TEX_RX_PX` = 72",
		"128 x 128 px, a dark plate (#%s" % PLATE.to_html(false).to_upper(),
		"`d06`, `d10` for the Lumen Accord",
	]:
		assert_bool(guide.contains(words)).override_failure_message(words).is_true()


func _fills(text: String) -> Array[String]:
	var found: Array[String] = []
	var fill: RegEx = RegEx.create_from_string('fill="(#[0-9A-F]{6})"')
	for hit: RegExMatch in fill.search_all(text):
		found.append(hit.get_string(1))
	return found


func _raster(text: String) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text, 1.0)
	return image


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _of_card(pixel: Color) -> bool:
	return (
		_distance(pixel, PLATE) < 0.08
		or _distance(pixel, RIM) < 0.08
		or _distance(pixel, GRID) < 0.08
	)


## One character for a pixel of the ellipse: clear, white or dark.
func _ink(pixel: Color) -> String:
	if pixel.a < 0.3:
		return "."
	return "W" if pixel.r > 0.8 else "D"
