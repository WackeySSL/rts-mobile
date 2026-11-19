extends RefCounted
## What every map ground look has to satisfy (STYLE.md "Map looks", plan rows P551 and P553): the
## checks of the standard diamonds, run on the diamonds of one look folder. Each function returns
## the problems it found, one text each, so a suite asserts the array is empty. Not a test suite
## (no GdUnitTestSuite base).

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
const FOLDER: String = "res://assets/art/svg/ground_looks/%s"
const ZOOMS: Array[float] = [0.375, 0.5, 0.75]
const MOST_BYTES: int = 4096  ## STYLE.md: 2 to 4 KB a file.
const BANDS: Array[float] = [0.89, 0.93, 0.97]
const GREY_TOLERANCE: float = 1.0  ## Levels a tile's mean may differ from the standard tile's.
## The base colour of each terrain's diamond (STYLE.md "Iso ground tiles").
const BASE: Dictionary[StringName, String] = {
	&"grass": "#6F8F57",
	&"sand": "#CDB98F",
	&"scrub": "#58653F",
	&"rock": "#726E69",
	&"water": "#2A5978",
	&"ore": "#51433A",
}


static func path(look: StringName, id: StringName, variant: String) -> String:
	return "%s/%s_%s.svg" % [FOLDER % look, id, variant]


## The folder holds exactly the diamonds `ids` (a and b), each well formed.
static func file_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	var files: Array[String] = Support.FileScan.list_files(FOLDER % look, ".svg")
	if files.size() != ids.size() * 2:
		problems.append("%d files, expected %d" % [files.size(), ids.size() * 2])
	for id: StringName in ids:
		for variant: String in ["a", "b"]:
			var file: String = path(look, id, variant)
			if not files.has(file):
				problems.append("%s is missing" % file)
				continue
			var text: String = Support.text(file)
			var lines: PackedStringArray = text.split("\n")
			if text.length() >= MOST_BYTES:
				problems.append("%s is %d bytes" % [file, text.length()])
			if not lines[0].begins_with("<!--") or not lines[1].begins_with("<!-- Pattern: "):
				problems.append("%s lacks its two comments" % file)
			if not lines[2].contains('width="128" height="64" viewBox="0 0 128 64"'):
				problems.append("%s is not 128 x 64" % file)
			for banned: String in ["<text", "<image", "<filter", "Gradient", "evenodd", "href"]:
				if text.contains(banned):
					problems.append("%s has %s" % [file, banned])
			var size: Vector2 = (load(file) as Texture2D).get_size()
			if size != Vector2(64, 32):
				problems.append("%s imports at %s, not 64 x 32" % [file, size])
	return problems


## Opaque to 0.99 of the way to the edge, clear beyond 1.12: the canvas corners stay empty.
static func diamond_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	for id: StringName in ids:
		for variant: String in ["a", "b"]:
			var image: Image = Support.raster(path(look, id, variant), 1.0)
			for y: int in Support.TILE.y:
				for x: int in Support.TILE.x:
					var m: float = Support.metric(x, y, Support.TILE)
					var alpha: float = image.get_pixel(x, y).a
					if m <= 0.99 and alpha < 0.99:
						problems.append("%s_%s %d,%d is not opaque" % [id, variant, x, y])
					elif m >= 1.12 and alpha > 0.02:
						problems.append("%s_%s %d,%d is outside" % [id, variant, x, y])
	return problems


## No rim: the base colour at three bands towards the middle of each edge.
static func rim_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	for id: StringName in ids:
		var base: Color = Color(BASE[id])
		for variant: String in ["a", "b"]:
			var image: Image = Support.raster(path(look, id, variant), 1.0)
			for corner: int in 4:
				for band: float in BANDS:
					var at: Vector2i = Support.edge_pixel(corner, band, Support.TILE)
					var got: Color = image.get_pixel(at.x, at.y)
					var off: float = (
						absf(got.r8 - base.r8) + absf(got.g8 - base.g8) + absf(got.b8 - base.b8)
					)
					if off > 3.0:
						problems.append(
							"%s_%s edge %d at %s: %s" % [id, variant, corner, band, got]
						)
	return problems


## A 3 x 3 block of mixed a and b at the three camera zooms has no pixel clear or half clear.
static func seam_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	for id: StringName in ids:
		for scale: float in ZOOMS:
			var tile: Vector2 = Vector2(Support.TILE) * scale
			var block: Image = Image.create_empty(
				int(tile.x * 3.0), int(tile.y * 3.0), false, Image.FORMAT_RGBA8
			)
			for row: int in 3:
				for column: int in 3:
					var image: Image = Support.raster(
						path(look, id, "ab"[(column + row) % 2]), scale
					)
					var at: Vector2i = Vector2i(
						(column - row + 2) * int(tile.x / 2.0), (column + row) * int(tile.y / 2.0)
					)
					block.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
			var seams: int = 0
			for y: int in block.get_height():
				for x: int in block.get_width():
					if (
						Support.metric(x, y, block.get_size()) <= 0.94
						and block.get_pixel(x, y).a < 0.99
					):
						seams += 1
			if seams > 0:
				problems.append("%s at %s: %d seams" % [id, scale, seams])
	return problems


## Each tile's mean at 32 px is within GREY_TOLERANCE of the standard tile's of the same name.
static func grey_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	var means: Dictionary[String, float] = Support.grey_means()
	for id: StringName in ids:
		for variant: String in ["a", "b"]:
			var own: float = Support.mean_grey(
				Support.raster(path(look, id, variant), Support.GREY_SCALE)
			)
			var want: float = means["%s_%s" % [id, variant]]
			if absf(own - want) > GREY_TOLERANCE:
				problems.append("%s_%s is %.2f, the standard tile %.2f" % [id, variant, own, want])
	return problems


## a and b differ inside every tile (by more than 60 pixels).
static func variant_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	for id: StringName in ids:
		var a: Image = Support.raster(path(look, id, "a"), 1.0)
		var b: Image = Support.raster(path(look, id, "b"), 1.0)
		var inside: int = 0
		for y: int in Support.TILE.y:
			for x: int in Support.TILE.x:
				if (
					Support.metric(x, y, Support.TILE) < 0.84
					and a.get_pixel(x, y) != b.get_pixel(x, y)
				):
					inside += 1
		if inside <= 60:
			problems.append("%s: a and b differ in %d pixels" % [id, inside])
	return problems


## The atlas built for the look has the page size and slots of the standard one, the look's
## diamonds for `ids` and the standard ones for every other terrain.
static func atlas_problems(look: StringName, ids: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	var all: Array[StringName] = [&"grass", &"sand", &"scrub", &"rock", &"water", &"ore"]
	var plain: GroundAtlas = GroundAtlas.build(all)
	var styled: GroundAtlas = GroundAtlas.build(all, look)
	if styled.image().get_size() != plain.image().get_size():
		problems.append(
			"the page is %s, not %s" % [styled.image().get_size(), plain.image().get_size()]
		)
	for id: StringName in all:
		for variant: String in ["a", "b"]:
			var key: StringName = StringName("%s_%s" % [id, variant])
			if styled.coords(key) != plain.coords(key):
				problems.append("%s moved" % key)
			var got: PackedByteArray = styled.image().get_region(styled.region(key)).get_data()
			var want: PackedByteArray = (
				(load(path(look, id, variant)) as Texture2D).get_image().get_data()
				if ids.has(id)
				else plain.image().get_region(plain.region(key)).get_data()
			)
			if got != want:
				problems.append(
					"%s is not the %s tile" % [key, "look's" if ids.has(id) else "standard"]
				)
	for id: StringName in all:
		if GroundAtlas.has_look(id, look) != ids.has(id):
			problems.append("has_look(%s) is wrong" % id)
	return problems
