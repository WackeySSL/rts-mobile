extends GdUnitTestSuite
## The two life atlases (plan row P135, ADR 0027, STYLE.md "Life effects"): `fx/life_atlas.svg` and
## `fx/strike_atlas.svg`. tests/art/test_art_assets.gd already holds every SVG to the technical
## rules (elements, 28 KB, no pattern or filter, one-decimal coordinates); this suite adds what is
## particular to these two: the region table of the style guide is the one the gallery draws and
## the atlases keep, every frame has ink inside a clear cell and nothing lies outside the cells,
## no colour is a team colour, flames are yellow-white, and the greys keep apart from the grounds.

const Life: GDScript = preload("res://game/view/art_gallery_life.gd")
const STYLE_PATH: String = "res://assets/art/STYLE.md"
const ATLAS_PATHS: Dictionary[String, String] = {
	"life": "res://assets/art/svg/fx/life_atlas.svg",
	"strike": "res://assets/art/svg/fx/strike_atlas.svg",
}
## The canvases in imported px (the SVG is twice as large, the import scale is 0.5).
const ATLAS_SIZES: Dictionary[String, Vector2i] = {
	"life": Vector2i(276, 160),
	"strike": Vector2i(240, 236),
}
const MAX_BYTES: int = 28672  ## 28 KB.
## The strips whose end touches their region's edge on purpose (STYLE.md "Life effects").
const FLUSH_KINDS: Array[String] = ["trail", "seed_trail"]
## A pixel of a sprite (the shadow, the softest, peaks at 0.5) and the fewest in a frame.
const INK_ALPHA: float = 0.3
const MIN_OPAQUE_PX: int = 30
const MIN_GAP_PX: int = 4
## The six key colours of the two triads (ADR 0023 section 5) and the key band's width and floor.
const KEY_COLOURS: PackedStringArray = [
	"#FF9446", "#E8681F", "#B04B12", "#62D6EE", "#1FA6C8", "#137C99"
]
const BAND_DEGREES: float = 20.0
const SATURATION_FLOOR: float = 0.30
## A pixel darker than this is an antialiased blend with a dark edge, not a colour of its own: the
## darkest key colour (#B04B12) has a value of 0.69.
const VALUE_FLOOR: float = 0.55
const FLAME_HUE_MIN: float = 46.0
const WARM_HUE_MAX: float = 100.0  ## Below this a saturated hue is yellow, orange or red.
const GRASS_LUMINANCE: float = 127.0
const SAND_LUMINANCE: float = 186.0
const GROUND_DISTANCE_MIN: float = 15.0
const GREY_STEP_MIN: float = 15.0


func test_both_atlases_are_hand_written_svg_of_the_canvas_the_style_guide_names() -> void:
	for atlas: String in ATLAS_PATHS:
		var text: String = FileAccess.get_file_as_string(ATLAS_PATHS[atlas])
		assert_int(text.to_utf8_buffer().size()).override_failure_message(atlas).is_less(MAX_BYTES)
		var lines: PackedStringArray = text.split("\n")
		assert_str(lines[0]).starts_with("<!-- ")
		assert_str(lines[1]).starts_with("<!-- Silhouette: ")
		for word: String in [
			"<pattern", "<filter", "<text", "<image", "<style", "<script", "data:"
		]:
			assert_str(text).override_failure_message(atlas + word).not_contains(word)
		var size: Vector2i = ATLAS_SIZES[atlas]
		assert_str(text).contains(
			(
				'width="%d" height="%d" viewBox="0 0 %d %d"'
				% [size.x * 2, size.y * 2, size.x * 2, size.y * 2]
			)
		)
		var texture: Texture2D = load(ATLAS_PATHS[atlas]) as Texture2D
		assert_vector(texture.get_size()).is_equal(Vector2(size))


## The table of "Life effects" is the one the gallery's Life page draws, kind by kind in order.
func test_the_style_table_is_the_regions_the_gallery_draws() -> void:
	var rows: Array[Dictionary] = _table()
	var gallery: Array[String] = []
	for kind: String in Life.LIFE_KINDS:
		gallery.append("life %s %s" % [kind, Life.LIFE_KINDS[kind]])
	for kind: String in Life.STRIKE_KINDS:
		gallery.append("strike %s %s" % [kind, Life.STRIKE_KINDS[kind]])
	var written: Array[String] = []
	for row: Dictionary in rows:
		var box: Rect2i = row["rect"]
		(
			written
			. append(
				(
					"%s %s %d,%d,%d,%d,%d,%d"
					% [
						row["atlas"],
						row["kind"],
						box.position.x,
						box.position.y,
						box.size.x,
						box.size.y,
						row["frames"],
						row["step"],
					]
				)
			)
		)
	assert_array(written).is_equal(gallery)
	assert_int(rows.size()).is_equal(21)


func test_every_frame_has_ink_in_a_clear_cell_and_nothing_lies_outside_the_cells() -> void:
	var frames: Array[Dictionary] = _frames()
	for atlas: String in ATLAS_PATHS:
		var image: Image = _image(atlas)
		var cells: Array[Rect2i] = []
		var problems: Array[String] = []
		for frame: Dictionary in frames:
			if frame["atlas"] != atlas:
				continue
			var cell: Rect2i = frame["rect"]
			cells.append(cell)
			var label: String = "%s %s %d" % [atlas, frame["kind"], frame["frame"]]
			if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(cell):
				problems.append(label + " is off the canvas")
				continue
			var opaque: int = 0
			var touching: int = 0
			for y: int in cell.size.y:
				for x: int in cell.size.x:
					var alpha: float = image.get_pixel(cell.position.x + x, cell.position.y + y).a
					opaque += int(alpha > INK_ALPHA)
					var on_edge: bool = (
						x == 0 or y == 0 or x == cell.size.x - 1 or y == cell.size.y - 1
					)
					touching += int(on_edge and alpha > 0.02)
			if opaque < MIN_OPAQUE_PX:
				problems.append("%s has %d ink px" % [label, opaque])
			if touching > 0 and not FLUSH_KINDS.has(frame["kind"]):
				problems.append("%s has ink on its cell's edge" % label)
		problems.append_array(_stray_ink(image, cells, atlas))
		problems.append_array(_close_cells(cells, atlas))
		assert_array(problems).override_failure_message(atlas + str(problems)).is_empty()


## ADR 0027 section 4: life effects carry no team colour. Every authored colour first, then every
## bright opaque pixel of the rasterised atlas (a dark pixel is the blend of a flame into its edge).
func test_no_colour_of_either_atlas_is_in_a_key_band_and_the_warm_ones_are_yellow_white() -> void:
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	var problems: Array[String] = []
	for atlas: String in ATLAS_PATHS:
		var text: String = FileAccess.get_file_as_string(ATLAS_PATHS[atlas])
		for found: RegExMatch in hex.search_all(text):
			var colour: Color = Color(found.get_string())
			var label: String = "%s %s" % [atlas, found.get_string()]
			if KEY_COLOURS.has(found.get_string().to_upper()):
				problems.append(label + " is a key colour")
			if _in_key_band(colour):
				problems.append(label + " is in a key band")
			if _is_orange_or_red(colour):
				problems.append(label + " is warmer than yellow-white")
		var image: Image = _image(atlas)
		var seen: Dictionary[String, bool] = {}
		for y: int in image.get_height():
			for x: int in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a < 0.9 or pixel.v < VALUE_FLOOR:
					continue
				if _in_key_band(pixel) or _is_orange_or_red(pixel):
					seen["%s %s" % [atlas, pixel.to_html(false)]] = true
		problems.append_array(seen.keys())
	assert_array(problems).is_empty()


func test_the_style_guide_lists_every_colour_of_both_atlases() -> void:
	var section: String = _section().to_upper()
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	var missing: Array[String] = []
	for atlas: String in ATLAS_PATHS:
		var text: String = FileAccess.get_file_as_string(ATLAS_PATHS[atlas])
		for found: RegExMatch in hex.search_all(text):
			if not section.contains(found.get_string().to_upper()):
				missing.append("%s %s" % [atlas, found.get_string()])
	assert_array(missing).is_empty()


## The clouds and the heap read against both grounds (grass 127, sand 186), and the greys that
## share a colour family keep apart: soot, exhaust, smoke, dust, steam.
func test_the_clouds_keep_clear_of_the_grounds_and_the_greys_keep_apart() -> void:
	var means: Dictionary[String, float] = {}
	var image: Image = _image("life")
	for row: Dictionary in _table():
		if row["atlas"] != "life":
			continue
		var kind: String = row["kind"]
		if ["flare", "fire", "spark"].has(kind):
			continue
		var total: float = 0.0
		var count: int = 0
		for frame: int in row["frames"]:
			var cell: Rect2i = Life.region(Life.LIFE_KINDS[kind], frame)
			for y: int in cell.size.y:
				for x: int in cell.size.x:
					var pixel: Color = image.get_pixel(cell.position.x + x, cell.position.y + y)
					if pixel.a >= 0.9:
						total += _luminance(pixel)
						count += 1
		means[kind] = total / count
	for kind: String in means:
		for ground: float in [GRASS_LUMINANCE, SAND_LUMINANCE]:
			(
				assert_float(absf(means[kind] - ground))
				. override_failure_message("%s %.1f" % [kind, means[kind]])
				. is_greater_equal(GROUND_DISTANCE_MIN)
			)
	var chain: Array[String] = ["soot", "exhaust", "smoke", "dust", "steam"]
	for index: int in chain.size() - 1:
		(
			assert_float(means[chain[index + 1]] - means[chain[index]])
			. override_failure_message("%s then %s" % [chain[index], chain[index + 1]])
			. is_greater_equal(GREY_STEP_MIN)
		)


## The style guide says the net is a lattice of the hexagon: side 16, a column every 24 px, a row
## every 13.9 px, and the hexagon of `hex` spans exactly that (vertices at the sides, 32 x 14).
func test_the_hexagon_of_the_net_spans_a_side_of_16_and_a_height_of_14() -> void:
	var image: Image = _image("strike")
	var cell: Rect2i = Life.region(Life.STRIKE_KINDS["hex"])
	var mid: int = cell.position.y + cell.size.y / 2
	var left: int = -1
	var right: int = -1
	for x: int in cell.size.x:
		if image.get_pixel(cell.position.x + x, mid).a > 0.5:
			left = x if left < 0 else left
			right = x
	# the dark edge is about 1 px outside the 32 px between the vertices
	assert_int(right - left + 1).is_between(32, 36)
	var top: int = -1
	var bottom: int = -1
	var centre: int = cell.position.x + cell.size.x / 2
	for y: int in cell.size.y:
		if image.get_pixel(centre, cell.position.y + y).a > 0.5:
			top = y if top < 0 else top
			bottom = y
	assert_int(bottom - top + 1).is_between(14, 17)
	assert_str(_section()).contains("a column every 24 px, a row every 13.9 px")


## The table's rows: kind, atlas, region, frames and step, in the order the style guide gives them.
func _table() -> Array[Dictionary]:
	var row: RegEx = (
		RegEx
		. create_from_string(
			"\\| `(\\w+)` \\| (life|strike) \\| (\\d+), (\\d+), (\\d+), (\\d+) \\| (\\d+) \\| (\\d+) \\|"
		)
	)
	var rows: Array[Dictionary] = []
	for found: RegExMatch in row.search_all(_section()):
		(
			rows
			. append(
				{
					"kind": found.get_string(1),
					"atlas": found.get_string(2),
					"rect":
					Rect2i(
						int(found.get_string(3)),
						int(found.get_string(4)),
						int(found.get_string(5)),
						int(found.get_string(6))
					),
					"frames": int(found.get_string(7)),
					"step": int(found.get_string(8)),
				}
			)
		)
	return rows


## Every frame of every kind: atlas, kind, frame number and its region.
func _frames() -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for row: Dictionary in _table():
		var box: Rect2i = row["rect"]
		for frame: int in row["frames"]:
			(
				frames
				. append(
					{
						"atlas": row["atlas"],
						"kind": row["kind"],
						"frame": frame,
						"rect": Rect2i(box.position + Vector2i(frame * row["step"], 0), box.size),
					}
				)
			)
	return frames


## Ink pixels (alpha above 0.02) that lie in no cell.
func _stray_ink(image: Image, cells: Array[Rect2i], atlas: String) -> Array[String]:
	var stray: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a <= 0.02:
				continue
			var inside: bool = false
			for cell: Rect2i in cells:
				if cell.has_point(Vector2i(x, y)):
					inside = true
					break
			stray += int(not inside)
	var found: Array[String] = []
	if stray > 0:
		found.append("%s has %d ink px outside its cells" % [atlas, stray])
	return found


## Cells closer than MIN_GAP_PX (a gap along the axis they are apart on).
func _close_cells(cells: Array[Rect2i], atlas: String) -> Array[String]:
	var found: Array[String] = []
	for first: int in cells.size():
		for second: int in range(first + 1, cells.size()):
			var a: Rect2i = cells[first]
			var b: Rect2i = cells[second]
			var gap_x: int = maxi(a.position.x - b.end.x, b.position.x - a.end.x)
			var gap_y: int = maxi(a.position.y - b.end.y, b.position.y - a.end.y)
			if maxi(gap_x, gap_y) < MIN_GAP_PX:
				found.append(
					"%s cells %s and %s are %d px apart" % [atlas, a, b, maxi(gap_x, gap_y)]
				)
	return found


func _in_key_band(colour: Color) -> bool:
	if colour.s < SATURATION_FLOOR:
		return false
	for key: String in KEY_COLOURS:
		var gap: float = absf(colour.h * 360.0 - Color(key).h * 360.0)
		if minf(gap, 360.0 - gap) <= BAND_DEGREES:
			return true
	return false


## Saturated and warmer than yellow-white: a hue below 46 degrees (red and orange).
func _is_orange_or_red(colour: Color) -> bool:
	var hue: float = colour.h * 360.0
	return colour.s >= SATURATION_FLOOR and hue < FLAME_HUE_MIN and hue < WARM_HUE_MAX


## Rec. 601 luminance of the 8-bit colour (STYLE.md, Palette).
func _luminance(colour: Color) -> float:
	return 0.299 * colour.r8 + 0.587 * colour.g8 + 0.114 * colour.b8


func _image(atlas: String) -> Image:
	return (load(ATLAS_PATHS[atlas]) as Texture2D).get_image()


## The text of STYLE.md from the "Life effects" heading to the next one.
func _section() -> String:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var start: int = style.find("## Life effects")
	return style.substr(start, style.find("\n## ", start + 1) - start)
