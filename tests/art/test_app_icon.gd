extends GdUnitTestSuite
## The app icon of plan row P98: the full square for the stores and the two
## 432 px layers of an Android adaptive icon (108 dp at 4x). Every file imports at its stated size
## and follows the technical rules, the foreground paints only inside the 288 px safe circle, the
## background and the square have no transparent edge, the warm sky is on the left and the cool sky
## on the right, and the tank still reads against its surroundings in greyscale at launcher sizes.
## The icon is not wired into the export presets here; that is the release engineer's row.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ICON_DIR: String = "res://assets/art/svg/icon"
const ICON_ART: String = "res://assets/art/svg/icon/%s.svg"
## File name to canvas side in px: the square for the stores, the two layers at 108 dp x 4.
const SIDES: Dictionary[String, int] = {
	"app_icon": 512,
	"icon_foreground": 432,
	"icon_background": 432,
}
const LAYER_SIDE: int = 432
## The adaptive icon's safe zone: a circle of 288 px (66 % of the 432 px canvas) at its centre.
const SAFE_RADIUS_PX: float = 144.0
const MAX_BYTES: int = 28672  ## 28 KB, the limit of every art file (STYLE.md, "Technical rules").
## Strings no icon file may hold: what ThorVG cannot draw, an embedded raster, an external link.
const FORBIDDEN: Array[String] = [
	"<pattern",
	"<text",
	"<image",
	"<filter",
	"<foreignObject",
	"<style",
	"<script",
	"data:",
	"xlink",
	"base64",
]
## The tank must differ from the ground around it by at least this many grey levels (of 255) in a
## greyscale reading of 48 and 36 cells across (the launcher size and a little under it).
const MIN_GREY_CONTRAST: float = 40.0
## A cell of the reading counts as tank above this coverage, as surround below the other.
const TANK_COVER: float = 0.6
const SURROUND_COVER: float = 0.05
const SURROUND_CELLS: int = 2


func test_the_folder_holds_exactly_the_square_and_the_two_layers() -> void:
	var found: Array[String] = FileScan.list_files(ICON_DIR, ".svg")
	var want: Array[String] = []
	for icon_name: String in SIDES:
		want.append(ICON_ART % icon_name)
	want.sort()
	assert_array(found).is_equal(want)


func test_each_file_imports_as_a_texture_of_the_stated_size() -> void:
	for icon_name: String in SIDES:
		var texture: Texture2D = load(ICON_ART % icon_name) as Texture2D
		assert_object(texture).override_failure_message(icon_name).is_not_null()
		assert_vector(texture.get_size()).override_failure_message(icon_name).is_equal(
			Vector2.ONE * SIDES[icon_name]
		)


func test_each_file_sets_its_canvas_and_opens_with_the_layer_and_silhouette_comments() -> void:
	for icon_name: String in SIDES:
		var text: String = FileAccess.get_file_as_string(ICON_ART % icon_name)
		var side: int = SIDES[icon_name]
		var canvas: String = (
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
			% [side, side, side, side]
		)
		assert_bool(text.contains(canvas)).override_failure_message(icon_name).is_true()
		var lines: PackedStringArray = text.split("\n")
		assert_str(lines[0]).override_failure_message(icon_name).starts_with("<!-- ")
		assert_str(lines[1]).override_failure_message(icon_name).starts_with("<!-- Silhouette: ")
		assert_int(text.to_utf8_buffer().size()).is_less_equal(MAX_BYTES)


func test_no_file_has_a_pattern_text_image_filter_or_external_reference() -> void:
	var href: RegEx = RegEx.create_from_string('href="([^"]*)"')
	var url: RegEx = RegEx.create_from_string("url\\(#([^)]+)\\)")
	var problems: Array[String] = []
	for icon_name: String in SIDES:
		var text: String = FileAccess.get_file_as_string(ICON_ART % icon_name)
		for word: String in FORBIDDEN:
			if text.contains(word):
				problems.append("%s has '%s'" % [icon_name, word])
		for found: RegExMatch in href.search_all(text):
			problems.append("%s has the reference %s" % [icon_name, found.get_string(1)])
		# A gradient or a clip path that a fill names must be in the same file.
		for found: RegExMatch in url.search_all(text):
			if not text.contains('id="%s"' % found.get_string(1)):
				problems.append("%s has no id %s" % [icon_name, found.get_string(1)])
	assert_array(problems).is_empty()


func test_the_foreground_paints_only_inside_the_safe_circle() -> void:
	var data: PackedByteArray = _rgba("icon_foreground").get_data()
	var outside: int = 0
	var farthest: float = 0.0
	for y: int in LAYER_SIDE:
		for x: int in LAYER_SIDE:
			if data[(y * LAYER_SIDE + x) * 4 + 3] == 0:
				continue
			var from_centre: float = Vector2(x + 0.5, y + 0.5).distance_to(
				Vector2.ONE * (LAYER_SIDE / 2.0)
			)
			farthest = maxf(farthest, from_centre)
			outside += int(from_centre > SAFE_RADIUS_PX)
	assert_int(outside).override_failure_message("farthest %.1f px" % farthest).is_equal(0)


func test_the_foreground_is_a_large_tank_with_transparent_corners() -> void:
	var image: Image = _rgba("icon_foreground")
	var data: PackedByteArray = image.get_data()
	var painted: int = 0
	for i: int in range(3, data.size(), 4):
		painted += int(data[i] > 0)
	var circle_area: float = PI * SAFE_RADIUS_PX * SAFE_RADIUS_PX
	# The tank fills well over a third of the circle that is all of the icon the launchers promise.
	assert_float(painted / circle_area).is_greater(0.35)
	for corner: Vector2i in [
		Vector2i(0, 0), Vector2i(431, 0), Vector2i(0, 431), Vector2i(431, 431)
	]:
		assert_float(image.get_pixelv(corner).a).override_failure_message(str(corner)).is_equal(0.0)
	# The turret, the deck of the hull and the glacis under them are solid.
	for point: Vector2i in [Vector2i(190, 185), Vector2i(240, 215), Vector2i(216, 245)]:
		assert_float(image.get_pixelv(point).a).override_failure_message(str(point)).is_equal(1.0)


func test_the_background_and_the_square_are_opaque_to_every_edge() -> void:
	var layer: PackedByteArray = _rgba("icon_background").get_data()
	var transparent: int = 0
	for i: int in range(3, layer.size(), 4):
		transparent += int(layer[i] < 255)
	assert_int(transparent).override_failure_message("background").is_equal(0)
	var square: Image = _rgba("app_icon")
	var side: int = SIDES["app_icon"]
	var open_edge: int = 0
	for i: int in side:
		for edge: Vector2i in [Vector2i(i, 0), Vector2i(i, side - 1), Vector2i(0, i)]:
			open_edge += int(square.get_pixelv(edge).a < 1.0)
		open_edge += int(square.get_pixelv(Vector2i(side - 1, i)).a < 1.0)
	assert_int(open_edge).override_failure_message("app icon edge").is_equal(0)
	# No rounded corner is baked in: the corner pixel carries the sky, not the launcher's backdrop.
	assert_float(square.get_pixelv(Vector2i(0, 0)).a).is_equal(1.0)
	assert_float(square.get_pixelv(Vector2i(side - 1, side - 1)).a).is_equal(1.0)


func test_the_warm_sky_is_on_the_left_and_the_cool_sky_on_the_right() -> void:
	# The pale light core sits in the middle; these points are high in the sky, well to the amber
	# side of it (left) and well to the cyan side (right).
	for image_name: String in ["icon_background", "app_icon"]:
		var image: Image = _rgba(image_name)
		var side: int = image.get_width()
		var warm: Color = image.get_pixelv(Vector2i(side * 4 / 10, side / 8))
		var cool: Color = image.get_pixelv(Vector2i(side * 9 / 10, side / 8))
		assert_float(warm.r - warm.b).override_failure_message(image_name).is_greater(0.35)
		assert_float(cool.b - cool.r).override_failure_message(image_name).is_greater(0.2)


func test_the_tank_reads_against_its_surround_in_greyscale_at_launcher_sizes() -> void:
	var foreground: Image = _rgba("icon_foreground")
	var composite: Image = _rgba("icon_background")
	composite.blend_rect(foreground, Rect2i(Vector2i.ZERO, foreground.get_size()), Vector2i.ZERO)
	for cells: int in [48, 36]:
		var grey: PackedFloat32Array = _cell_means(composite.get_data(), cells, false)
		var cover: PackedFloat32Array = _cell_means(foreground.get_data(), cells, true)
		var gap: float = _surround_mean(grey, cover, cells) - _tank_mean(grey, cover)
		assert_float(gap).override_failure_message("%d cells" % cells).is_greater(MIN_GREY_CONTRAST)


## The icon file as an RGBA8 image, read back from the imported texture.
func _rgba(icon_name: String) -> Image:
	var image: Image = (load(ICON_ART % icon_name) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Per cell of a cells x cells grid over a 432 px layer: the mean Rec. 601 grey (0-255) of the
## pixels, or, with `alpha_only`, the mean alpha as a coverage from 0 to 1.
func _cell_means(data: PackedByteArray, cells: int, alpha_only: bool) -> PackedFloat32Array:
	var block: int = LAYER_SIDE / cells
	var sums: PackedFloat32Array = PackedFloat32Array()
	sums.resize(cells * cells)
	for y: int in LAYER_SIDE:
		for x: int in LAYER_SIDE:
			var at: int = (y * LAYER_SIDE + x) * 4
			var value: float = data[at + 3] / 255.0
			if not alpha_only:
				value = 0.299 * data[at] + 0.587 * data[at + 1] + 0.114 * data[at + 2]
			sums[(y / block) * cells + x / block] += value
	for i: int in sums.size():
		sums[i] /= block * block
	return sums


func _tank_mean(grey: PackedFloat32Array, cover: PackedFloat32Array) -> float:
	var total: float = 0.0
	var count: int = 0
	for i: int in cover.size():
		if cover[i] >= TANK_COVER:
			total += grey[i]
			count += 1
	assert_int(count).is_greater(100)
	return total / count


## The mean grey of the cells that hold no tank but lie within SURROUND_CELLS of one.
func _surround_mean(grey: PackedFloat32Array, cover: PackedFloat32Array, cells: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in cells:
		for x: int in cells:
			if cover[y * cells + x] > SURROUND_COVER or not _near_tank(cover, cells, x, y):
				continue
			total += grey[y * cells + x]
			count += 1
	assert_int(count).is_greater(50)
	return total / count


func _near_tank(cover: PackedFloat32Array, cells: int, x: int, y: int) -> bool:
	for ny: int in range(maxi(y - SURROUND_CELLS, 0), mini(y + SURROUND_CELLS + 1, cells)):
		for nx: int in range(maxi(x - SURROUND_CELLS, 0), mini(x + SURROUND_CELLS + 1, cells)):
			if cover[ny * cells + nx] >= TANK_COVER:
				return true
	return false
