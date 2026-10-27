extends RefCounted
## The ground, field, prop and decal art of plan row P105 as the suites read it: the folders and
## names, rasters of the SVG text and the measures of STYLE.md ("Iso ground tiles", "Fields"). Not a
## test suite (no GdUnitTestSuite base).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const GROUND_DIR: String = "res://assets/art/svg/ground"
const FIELDS_DIR: String = "res://assets/art/svg/fields"
const DECALS_DIR: String = "res://assets/art/svg/decals"
const TERRAIN_SET: String = "res://data/terrain/standard.tres"
## The six terrain ids of `data/terrain/standard.tres`, in its order.
const TERRAIN_IDS: Array[StringName] = [&"grass", &"sand", &"scrub", &"rock", &"water", &"ore"]
const KINDS: Array[String] = ["oil", "gas"]
const STAGES: Array[String] = ["full", "half", "dry"]
const TILE: Vector2i = Vector2i(128, 64)  ## A cell at 2x.
const GREY_SCALE: float = 0.25  ## 32 px for a 128 px canvas.
## Rec. 601 luminance of a stage over `ore_a` or a tile alone, at 32 px: pinned by STYLE.md.
const GAP: float = 11.0  ## The least difference of two means for "told apart" in greyscale.


static func ground_path(id: String, variant: String) -> String:
	return "%s/%s_%s.svg" % [GROUND_DIR, id, variant]


static func field_path(kind: String, stage: String) -> String:
	return "%s/%s_%s.svg" % [FIELDS_DIR, kind, stage]


static func text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func raster(path: String, scale: float) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text(path), scale)
	return image


## The diamond's metric of a pixel: 0 in the middle, 1 on the diamond's edge (a pixel's centre).
static func metric(x: int, y: int, size: Vector2i) -> float:
	var half: Vector2 = Vector2(size) / 2.0
	return absf(x + 0.5 - half.x) / half.x + absf(y + 0.5 - half.y) / half.y


## The pixel on the line from the middle to the middle of one of the four edges (`corner` 0 to 3:
## north-west, north-east, south-east, south-west), at `m` times the way to the edge.
static func edge_pixel(corner: int, m: float, size: Vector2i) -> Vector2i:
	var signs: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var half: Vector2 = Vector2(size) / 2.0
	var at: Vector2 = half + signs[corner] * half / 2.0 * m
	return Vector2i(int(at.x), int(at.y))


static func luminance(color: Color) -> float:
	return 0.299 * color.r8 + 0.587 * color.g8 + 0.114 * color.b8


## The mean luminance over the pixels with alpha above 0.9 of `top` drawn over `base` (or alone).
static func mean_grey(top: Image, base: Image = null) -> float:
	var picture: Image = Image.create_empty(
		top.get_width(), top.get_height(), false, top.get_format()
	)
	if base != null:
		picture.blend_rect(base, Rect2i(Vector2i.ZERO, base.get_size()), Vector2i.ZERO)
	picture.blend_rect(top, Rect2i(Vector2i.ZERO, top.get_size()), Vector2i.ZERO)
	var total: float = 0.0
	var count: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var pixel: Color = picture.get_pixel(x, y)
			if pixel.a > 0.9:
				total += luminance(pixel)
				count += 1
	return total / maxi(count, 1)


## The means at 32 px of the twelve ground tiles by file name and of the six stages over `ore_a`.
static func grey_means() -> Dictionary[String, float]:
	var means: Dictionary[String, float] = {}
	for id: StringName in TERRAIN_IDS:
		for variant: String in ["a", "b"]:
			means["%s_%s" % [id, variant]] = mean_grey(raster(ground_path(id, variant), GREY_SCALE))
	var ore: Image = raster(ground_path("ore", "a"), GREY_SCALE)
	for kind: String in KINDS:
		for stage: String in STAGES:
			var key: String = "%s_%s" % [kind, stage]
			means[key] = mean_grey(raster(field_path(kind, stage), GREY_SCALE), ore)
	return means
