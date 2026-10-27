extends GdUnitTestSuite
## The ore and the ghost patterns of plan rows P91 and P91b (Phase 3), as STYLE.md ("Ore",
## "Ghosts") describes them: the nine ore cells, opaque tiles that fill up by level and join their
## neighbours without a seam, and the two ghost patterns, which repeat without one. (The buildings
## of those rows were drawn in the oblique view and went with P103; their iso successors are pinned
## in test_fossil_buildings.gd and test_artgen*.gd.) The gallery pages that show them are in
## test_art_gallery_pages.gd.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const ORE_ART: String = "res://assets/art/svg/ore/ore_%s.svg"
const GHOST_ART: String = "res://assets/art/svg/ui/ghost_%s.svg"
const STYLE_PATH: String = "res://assets/art/STYLE.md"
const ORE_NAMES: Array[String] = ["0", "1a", "1b", "2a", "2b", "3a", "3b", "4a", "4b"]
## The colours the ore tiles and the ghost patterns may use: STYLE.md's old palette, the team layer
## greys, and the two dirt tones that STYLE.md marks as new.
const PALETTE: PackedStringArray = [
	"#1C2127",
	"#000000",
	"#5B6670",
	"#7D8893",
	"#A9B4BE",
	"#4E5A3A",
	"#6B7A4F",
	"#8C9A6B",
	"#F2B705",
	"#FFD84D",
	"#A67C00",
	"#F5A524",
	"#8A6F4D",
	"#6F583B",
	"#A3865E",
	"#FFFFFF",
	"#BFBFBF",
	"#4D4D4D",
]
const GROUND_BASE: String = "8a6f4d"  ## The dirt every ore tile is filled with, edge to edge.
const GOLD: PackedStringArray = ["f2b705", "ffd84d"]  ## The bright ore colours.


func test_every_ore_and_ghost_svg_names_its_shape_in_one_line_and_uses_the_palette() -> void:
	var files: Array[String] = FileScan.list_files("res://assets/art/svg/ore", ".svg")
	files.append_array([GHOST_ART % "hatch", GHOST_ART % "seen"])
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	var problems: Array[String] = []
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = text.split("\n")
		var second: String = lines[1] if lines.size() > 1 else ""
		var named: bool = (
			second.begins_with("<!-- Silhouette: ")
			or second.begins_with("<!-- Shape: ")
			or second.begins_with("<!-- Pattern: ")
		)
		if not (lines[0].begins_with("<!-- ") and lines[0].ends_with(" -->") and named):
			problems.append(path + " has no two comment lines")
		elif not second.ends_with(" -->") or second.length() < 60:
			problems.append(path + " has no shape line")
		for found: RegExMatch in hex.search_all(text):
			if not PALETTE.has(found.get_string().to_upper()):
				problems.append("%s uses %s" % [path, found.get_string()])
	assert_array(problems).is_empty()
	assert_int(files.size()).is_equal(ORE_NAMES.size() + 2)


func test_the_nine_ore_cells_are_opaque_tiles_of_one_tile_size() -> void:
	assert_array(FileScan.list_files("res://assets/art/svg/ore", ".svg")).has_size(ORE_NAMES.size())
	for name: String in ORE_NAMES:
		var texture: Texture2D = load(ORE_ART % name)
		assert_vector(texture.get_size()).override_failure_message(name).is_equal(Vector2(64, 64))
		var image: Image = _image(ORE_ART % name)
		var clear: int = 0
		for y: int in 64:
			for x: int in 64:
				clear += int(image.get_pixel(x, y).a < 1.0)
		assert_int(clear).override_failure_message(name).is_equal(0)


## No nugget, pit or shadow reaches the outer two px of a tile, so two ore tiles side by side show
## bare dirt on both sides of the join and the map has no grid (STYLE.md, "Fog and terrain").
func test_the_outer_two_px_of_every_ore_cell_are_bare_dirt() -> void:
	for name: String in ORE_NAMES:
		var image: Image = _image(ORE_ART % name)
		var wrong: Array[String] = []
		for y: int in 64:
			for x: int in 64:
				if minf(minf(x, y), minf(63 - x, 63 - y)) < 2.0:
					if image.get_pixel(x, y).to_html(false) != GROUND_BASE:
						wrong.append("%d,%d" % [x, y])
		assert_array(wrong).override_failure_message(name).is_empty()


## The level is 0 for an empty cell and 1 + (amount - 1) x 4 / ore_cell_max above it (STYLE.md,
## "Ore"), so each level holds visibly more gold than the one below it. The two variants of a
## level hold the same amount of gold, laid out differently.
func test_ore_fills_up_with_the_level_and_both_variants_hold_the_same_amount() -> void:
	var gold: Dictionary[String, int] = {}
	for name: String in ORE_NAMES:
		var image: Image = _image(ORE_ART % name)
		var count: int = 0
		for y: int in 64:
			for x: int in 64:
				count += int(GOLD.has(image.get_pixel(x, y).to_html(false)))
		gold[name] = count
	assert_int(gold["0"]).is_equal(0)
	for variant: String in ["a", "b"]:
		var below: int = 0
		for level: int in [1, 2, 3, 4]:
			var now: int = gold["%d%s" % [level, variant]]
			assert_float(float(now)).override_failure_message(variant + str(level)).is_greater(
				maxf(1.0, below * 1.5)
			)
			below = now
	for level: int in [1, 2, 3, 4]:
		var a: int = gold["%da" % level]
		var b: int = gold["%db" % level]
		assert_float(absf(a - b) / float(a)).override_failure_message(str(level)).is_less(0.05)
		var pair: Array[PackedByteArray] = [
			_image(ORE_ART % ("%da" % level)).get_data(),
			_image(ORE_ART % ("%db" % level)).get_data()
		]
		assert_bool(pair[0] == pair[1]).override_failure_message(str(level)).is_false()


## The hatch is a diagonal band pattern with a period of 32 px along x and y in the imported tile,
## so shifting it by half the tile in either direction gives the same picture: it repeats with no
## seam. The dots are a staggered lattice, 16 px apart in a row with every second row shifted by 8.
func test_the_two_ghost_patterns_repeat_without_a_seam() -> void:
	var shifts: Dictionary[String, Array] = {
		"hatch": [Vector2i(32, 0), Vector2i(0, 32)],
		"seen": [Vector2i(16, 0), Vector2i(8, 16)],
	}
	for name: String in shifts:
		var texture: Texture2D = load(GHOST_ART % name)
		assert_vector(texture.get_size()).is_equal(Vector2(64, 64))
		var image: Image = _image(GHOST_ART % name)
		var ink: int = 0
		for y: int in 64:
			for x: int in 64:
				ink += int(image.get_pixel(x, y).a > 0.5)
		# A tile that is neither empty nor full, so it has something to repeat.
		assert_float(ink / 4096.0).override_failure_message(name).is_between(0.1, 0.6)
		for shift: Vector2i in shifts[name]:
			var worst: float = 0.0
			for y: int in 64:
				for x: int in 64:
					var moved: Vector2i = Vector2i((x + shift.x) % 64, (y + shift.y) % 64)
					worst = maxf(worst, absf(image.get_pixel(x, y).a - image.get_pixelv(moved).a))
			assert_float(worst).override_failure_message("%s %s" % [name, shift]).is_less(0.1)


func test_the_style_guide_names_every_ore_and_ghost_file() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	for name: String in ORE_NAMES:
		assert_str(style).contains("`%s`" % ("ore_" + name + ".svg"))
	for name: String in ["hatch", "seen"]:
		assert_str(style).contains("ui/ghost_%s.svg" % name)
	assert_str(style).contains("1 + (amount - 1) * 4 / ore_cell_max")


## The ghost looks STYLE.md quotes are the ones the gallery draws.
func test_the_style_guide_quotes_the_ghost_look_the_gallery_draws() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var start: int = style.find("## Ghosts")
	assert_int(start).is_greater(-1)
	var section: String = style.substr(start, style.find("\n## ", start + 1) - start)
	var flat: String = section.replace("\n", " ")
	for line: String in [
		"sprite alpha %s" % Gallery.GHOST_SPRITE_ALPHA,
		"`CanvasGroup.self_modulate`",
		"wash alpha %s" % Gallery.GHOST_WASH_ALPHA,
		"hatch alpha %s" % Gallery.GHOST_HATCH_ALPHA,
		"dots alpha %s" % Gallery.GHOST_DOTS_ALPHA,
		"frame %d dp" % int(Gallery.GHOST_FRAME_PX),
		"#" + Gallery.GHOST_OK.to_html(false).to_upper(),
		"#" + Gallery.GHOST_DANGER.to_html(false).to_upper(),
		"#" + Gallery.GHOST_NEUTRAL.to_html(false).to_upper(),
	]:
		assert_str(flat).contains(line)


## The raster of a texture as RGBA8, so a pixel reads the same whatever the import chose.
func _image(path: String) -> Image:
	var image: Image = (load(path) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image
