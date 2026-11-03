extends GdUnitTestSuite
## The two life atlases (plan row P135, ADR 0027, STYLE.md "Life effects"): `fx/life_atlas.svg` and
## `fx/strike_atlas.svg`. tests/art/test_art_assets.gd already holds every SVG to the technical
## rules (elements, 28 KB, no pattern or filter, one-decimal coordinates); this suite adds what is
## particular to these two: the region table of the style guide is the one `LifeRegions` holds and
## the atlases keep, every frame has ink inside a clear cell and nothing lies outside the cells, no
## colour is a team colour, flames are yellow-white, the sparks are bright, the greys keep apart
## from the grounds and the hexagon of the net fits its own lattice.

const Support: GDScript = preload("res://tests/art/life_art_support.gd")
const ATLAS_PATHS: Dictionary[String, String] = {
	"life": LifeRegions.LIFE_ART,
	"strike": LifeRegions.STRIKE_ART,
}
## The canvases in imported px (the SVG is twice as large, the import scale is 0.5).
const ATLAS_SIZES: Dictionary[String, Vector2i] = {
	"life": Vector2i(276, 160),
	"strike": Vector2i(240, 236),
}
const MAX_BYTES: int = 28672  ## 28 KB.
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
## A saturated hue below this is orange or red, from this on it is magenta or red: flames are
## yellow-white, so neither end of the hue circle is in the atlases.
const FLAME_HUE_MIN: float = 46.0
const RED_HUE_MIN: float = 300.0
const GRASS: Color = Color("6F8F57")
const SAND: Color = Color("CDB98F")
const GRASS_LUMINANCE: float = 127.0
const SAND_LUMINANCE: float = 186.0
const GROUND_DISTANCE_MIN: float = 15.0
const GREY_STEP_MIN: float = 15.0
## The sparks and the glint are bright flecks: the mean luminance of their ink over a ground and the
## share of it that is as bright as a pale yellow or mint.
const BRIGHT_KINDS: Array[StringName] = [&"spark", &"glint"]
const BRIGHT_MEAN_MIN: float = 140.0
const BRIGHT_LUMINANCE: float = 150.0
const BRIGHT_SHARE_MIN: float = 0.4
const OUTLINE_TOLERANCE_PX: int = 2
const LIGHT_LINE_LUMINANCE: float = 150.0  ## The light line of a hexagon, over its dark edge.


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


## The table of "Life effects" is the one `LifeRegions` holds, kind by kind in order: the atlas, the
## region of frame 0, the frames, the step and the anchor, and the joins and the stretch the text
## names.
func test_the_style_table_is_the_table_of_life_regions() -> void:
	var rows: Array[Dictionary] = Support.table()
	var kinds: Array[StringName] = []
	for row: Dictionary in rows:
		var kind: StringName = row["kind"]
		kinds.append(kind)
		var label: String = String(kind)
		assert_bool(LifeRegions.ATLAS.has(kind)).override_failure_message(label).is_true()
		var atlas: int = (
			LifeRegions.Atlas.LIFE if row["atlas"] == "life" else LifeRegions.Atlas.STRIKE
		)
		assert_int(LifeRegions.ATLAS[kind]).override_failure_message(label).is_equal(atlas)
		assert_that(LifeRegions.FIRST[kind]).override_failure_message(label).is_equal(row["rect"])
		assert_int(LifeRegions.FRAMES[kind]).override_failure_message(label).is_equal(row["frames"])
		assert_int(LifeRegions.STEP[kind]).override_failure_message(label).is_equal(row["step"])
		assert_that(LifeRegions.ANCHOR[kind]).override_failure_message(label).is_equal(
			row["anchor"]
		)
	assert_array(kinds).is_equal(LifeRegions.ATLAS.keys())
	assert_int(kinds.size()).is_equal(21)
	assert_dict(Support.joins()).is_equal(LifeRegions.JOIN)
	var text: String = Support.section().replace("\n", " ")
	for strip: StringName in LifeRegions.MAX_STRETCH:
		assert_float(LifeRegions.MAX_STRETCH[strip]).is_equal(2.0)
	assert_str(text).contains("to at most 2 times its region's length")


## Every frame of every kind: `LifeRegions.region` is the cell the table implies (frame 0 moved by
## frame x step), in the file the atlas names. Not `LifeRegions` against itself: the cells come
## from the style guide, and the ink test below holds the SVG to the same cells.
func test_every_frame_region_is_the_cell_the_style_guide_implies() -> void:
	var cells: Array[Dictionary] = Support.cells()
	assert_int(cells.size()).is_equal(36)
	for cell: Dictionary in cells:
		var kind: StringName = cell["kind"]
		var label: String = "%s %d" % [kind, cell["frame"]]
		(
			assert_that(LifeRegions.region(kind, cell["frame"]))
			. override_failure_message(label)
			. is_equal(cell["rect"])
		)
		assert_str(LifeRegions.texture_path(kind)).is_equal(ATLAS_PATHS[cell["atlas"]])


func test_every_frame_has_ink_in_a_clear_cell_and_nothing_lies_outside_the_cells() -> void:
	var frames: Array[Dictionary] = Support.cells()
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
			problems.append_array(_ink_in_cell(image, cell, frame["kind"], label))
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
				problems.append(label + " is orange or red")
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


## The colour checks themselves: the key colours, an orange, a crimson and a magenta (the steam's
## rim turned red would be one) fail, a flame yellow, a mint and a grey pass.
func test_the_colour_checks_catch_a_key_colour_an_orange_a_crimson_and_a_magenta() -> void:
	for bad: String in ["#FF9446", "#1FA6C8", "#F5A524"]:
		assert_bool(_in_key_band(Color(bad)) or _is_orange_or_red(Color(bad))).is_true()
	for bad: String in ["#D02848", "#E5484D", "#C0207A"]:
		assert_bool(_is_orange_or_red(Color(bad))).override_failure_message(bad).is_true()
	for good: String in ["#FFD84D", "#FFE066", "#FFF8D2", "#A8F5B0", "#1F5C3A", "#6F7D86"]:
		assert_bool(_in_key_band(Color(good)) or _is_orange_or_red(Color(good))).is_false()


func test_the_style_guide_lists_every_colour_of_both_atlases() -> void:
	var section: String = Support.section().to_upper()
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
	var means: Dictionary[StringName, float] = {}
	var image: Image = _image("life")
	for kind: StringName in [&"dust", &"smoke", &"soot", &"steam", &"puff", &"exhaust"]:
		var total: float = 0.0
		var count: int = 0
		for frame: int in LifeRegions.FRAMES[kind]:
			var cell: Rect2i = LifeRegions.region(kind, frame)
			for y: int in cell.size.y:
				for x: int in cell.size.x:
					var pixel: Color = image.get_pixel(cell.position.x + x, cell.position.y + y)
					if pixel.a >= 0.9:
						total += _luminance(pixel)
						count += 1
		means[kind] = total / count
	for kind: StringName in means:
		for ground: float in [GRASS_LUMINANCE, SAND_LUMINANCE]:
			(
				assert_float(absf(means[kind] - ground))
				. override_failure_message("%s %.1f" % [kind, means[kind]])
				. is_greater_equal(GROUND_DISTANCE_MIN)
			)
	var chain: Array[StringName] = [&"soot", &"exhaust", &"smoke", &"dust", &"steam"]
	for index: int in chain.size() - 1:
		(
			assert_float(means[chain[index + 1]] - means[chain[index]])
			. override_failure_message("%s then %s" % [chain[index], chain[index + 1]])
			. is_greater_equal(GREY_STEP_MIN)
		)


## The sparks and the glint are bright flecks, not dark crosses under a heavy edge: over grass and
## over sand the mean luminance of their ink and the share of it that is pale both hold.
func test_the_sparks_and_the_glint_are_bright_on_both_grounds() -> void:
	var problems: Array[String] = []
	for kind: StringName in BRIGHT_KINDS:
		var image: Image = _image(
			"life" if LifeRegions.ATLAS[kind] == LifeRegions.Atlas.LIFE else "strike"
		)
		for frame: int in LifeRegions.FRAMES[kind]:
			var cell: Rect2i = LifeRegions.region(kind, frame)
			for ground: Color in [GRASS, SAND]:
				var total: float = 0.0
				var pale: int = 0
				var count: int = 0
				for y: int in cell.size.y:
					for x: int in cell.size.x:
						var pixel: Color = image.get_pixel(cell.position.x + x, cell.position.y + y)
						if pixel.a <= 0.5:
							continue
						var lum: float = _luminance(ground.lerp(Color(pixel, 1.0), pixel.a))
						total += lum
						pale += int(lum >= BRIGHT_LUMINANCE)
						count += 1
				var label: String = "%s %d on %s" % [kind, frame, ground.to_html(false)]
				if count < MIN_OPAQUE_PX or total / count < BRIGHT_MEAN_MIN:
					problems.append(
						"%s has a mean of %.1f over %d px" % [label, total / maxi(count, 1), count]
					)
				if count > 0 and float(pale) / count < BRIGHT_SHARE_MIN:
					problems.append("%s has %.2f of its ink pale" % [label, float(pale) / count])
	assert_array(problems).is_empty()


## The hexagon of the net fits the lattice the guide and `LifeRegions` give: the light lines of its
## flat top and bottom are `NET_ROW_PX` apart and its vertices `NET_COLUMN_PX` / 0.75 apart, so
## neighbours share an edge with their lines on one another and no dark seam shows between them.
## The lit hexagon has the outline of the unlit one to within the antialiasing of its edge (its
## fill is as bright as its line, so the line cannot be told from it by light).
func test_the_hexagon_of_the_net_fits_its_lattice_of_a_column_of_24_and_a_row_of_13_9() -> void:
	var image: Image = _image("strike")
	var cell: Rect2i = LifeRegions.region(&"hex")
	var centre: Vector2i = cell.position + Vector2i(LifeRegions.ANCHOR[&"hex"])
	var top: float = _light_line_y(image, centre.x, cell.position.y, centre.y)
	var bottom: float = _light_line_y(image, centre.x, centre.y, cell.end.y)
	(
		assert_float(bottom - top)
		. override_failure_message("%.2f %.2f" % [top, bottom])
		. is_equal_approx(LifeRegions.NET_ROW_PX, 0.5)
	)
	var left: float = _light_line_x(image, cell.position.x, centre.x, centre.y)
	var right: float = _light_line_x(image, centre.x, cell.end.x, centre.y)
	(
		assert_float((right - left) * 0.75)
		. override_failure_message("%.2f %.2f" % [left, right])
		. is_equal_approx(LifeRegions.NET_COLUMN_PX, 0.75)
	)
	assert_float(LifeRegions.NET_SHIFT_PX).is_equal_approx(LifeRegions.NET_ROW_PX / 2.0, 0.01)
	var lit: Rect2i = LifeRegions.region(&"hex_lit")
	var plain_box: Rect2i = _ink_box(image, cell)
	var lit_box: Rect2i = _ink_box(image, lit)
	assert_int(absi(lit_box.size.x - plain_box.size.x)).is_less_equal(OUTLINE_TOLERANCE_PX)
	assert_int(absi(lit_box.size.y - plain_box.size.y)).is_less_equal(OUTLINE_TOLERANCE_PX)
	assert_int(absi(lit_box.get_center().y - plain_box.get_center().y)).is_less_equal(1)
	var text: String = FileAccess.get_file_as_string(LifeRegions.STRIKE_ART).to_upper()
	assert_str(text).contains(LifeRegions.NET_LIGHT.to_html(false).to_upper())
	assert_str(text).contains(LifeRegions.NET_EDGE.to_html(false).to_upper())
	assert_str(Support.section()).contains("a column every 24 px, a row every 13.9 px")


## The box, relative to `cell`, of the pixels of `cell` that are mostly opaque.
func _ink_box(image: Image, cell: Rect2i) -> Rect2i:
	var box: Rect2i = Rect2i()
	var first: bool = true
	for y: int in cell.size.y:
		for x: int in cell.size.x:
			if image.get_pixel(cell.position.x + x, cell.position.y + y).a < 0.5:
				continue
			var point: Rect2i = Rect2i(Vector2i(x, y), Vector2i.ONE)
			box = point if first else box.merge(point)
			first = false
	return box


## The problems of one frame's cell: too little ink, or ink on an edge of the cell (the one edge a
## strip is flush with is the exception).
func _ink_in_cell(image: Image, cell: Rect2i, kind: StringName, label: String) -> Array[String]:
	var found: Array[String] = []
	var opaque: int = 0
	var edges: Dictionary[StringName, int] = {&"left": 0, &"right": 0, &"top": 0, &"bottom": 0}
	for y: int in cell.size.y:
		for x: int in cell.size.x:
			var alpha: float = image.get_pixel(cell.position.x + x, cell.position.y + y).a
			opaque += int(alpha > INK_ALPHA)
			if alpha <= 0.02:
				continue
			edges[&"left"] += int(x == 0)
			edges[&"right"] += int(x == cell.size.x - 1)
			edges[&"top"] += int(y == 0)
			edges[&"bottom"] += int(y == cell.size.y - 1)
	if opaque < MIN_OPAQUE_PX:
		found.append("%s has %d ink px" % [label, opaque])
	for edge: StringName in edges:
		if edges[edge] > 0 and LifeRegions.FLUSH_EDGE.get(kind, &"") != edge:
			found.append("%s has ink on its cell's %s edge" % [label, edge])
	if LifeRegions.FLUSH_EDGE.has(kind) and edges[LifeRegions.FLUSH_EDGE[kind]] == 0:
		found.append("%s is not flush with its %s edge" % [label, LifeRegions.FLUSH_EDGE[kind]])
	return found


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


## The y (px, pixel centres) of the light line of a hexagon in the rows `from_y` to `to_y` of the
## three columns round `x`: the centroid of the light pixels (luminance weighted).
func _light_line_y(image: Image, x: int, from_y: int, to_y: int) -> float:
	var weight: float = 0.0
	var sum: float = 0.0
	for column: int in range(x - 1, x + 2):
		for y: int in range(from_y, to_y):
			var pixel: Color = image.get_pixel(column, y)
			var lum: float = _luminance(pixel)
			if pixel.a >= 0.9 and lum >= LIGHT_LINE_LUMINANCE:
				weight += lum
				sum += lum * (y + 0.5)
	return sum / weight if weight > 0.0 else -1000.0


## The x of the light line of a hexagon in the columns `from_x` to `to_x` of the two rows next to
## the vertices' row `y`, by the same centroid.
func _light_line_x(image: Image, from_x: int, to_x: int, y: int) -> float:
	var weight: float = 0.0
	var sum: float = 0.0
	for row: int in range(y - 1, y + 1):
		for x: int in range(from_x, to_x):
			var pixel: Color = image.get_pixel(x, row)
			var lum: float = _luminance(pixel)
			if pixel.a >= 0.9 and lum >= LIGHT_LINE_LUMINANCE:
				weight += lum
				sum += lum * (x + 0.5)
	return sum / weight if weight > 0.0 else -1000.0


func _in_key_band(colour: Color) -> bool:
	if colour.s < SATURATION_FLOOR:
		return false
	for key: String in KEY_COLOURS:
		var gap: float = absf(colour.h * 360.0 - Color(key).h * 360.0)
		if minf(gap, 360.0 - gap) <= BAND_DEGREES:
			return true
	return false


## Saturated and either end of the hue circle: orange and red below 46 degrees, crimson, magenta and
## red from 300 degrees on. Yellow-white (46 to 60), mint and the greys pass.
func _is_orange_or_red(colour: Color) -> bool:
	var hue: float = colour.h * 360.0
	return colour.s >= SATURATION_FLOOR and (hue < FLAME_HUE_MIN or hue >= RED_HUE_MIN)


## Rec. 601 luminance of the 8-bit colour (STYLE.md, Palette).
func _luminance(colour: Color) -> float:
	return 0.299 * colour.r8 + 0.587 * colour.g8 + 0.114 * colour.b8


func _image(atlas: String) -> Image:
	return (load(ATLAS_PATHS[atlas]) as Texture2D).get_image()
