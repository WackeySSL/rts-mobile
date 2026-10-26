class_name RuntimeAtlas
extends RefCounted
## One texture atlas built at run time (ADR 0022 section 2): the view copies the imported textures a
## layer needs into a single RGBA8 image and uploads it once, so a layer that draws pieces of many
## source files still draws them as quads of one texture and batches into one call (ADR 0011
## section 3, ADR 0012 section 6). BuildingLayer uses it first; the ground (P97) and the ore (P84b)
## reuse it.
##
## Each source is read once with `Texture2D.get_image()` (a copy), turned into RGBA8 if it is not,
## and put in a padded cell: the image with a GUTTER_PX border on every side that repeats the
## image's own edge pixels (a transparent edge repeats transparent pixels), so linear filtering at
## any zoom never samples a neighbour. The cells are packed in rows (shelves) of at most
## `width_px`, in the order the sources are given. A region is the image inside its gutter, in
## texels of the atlas, which are px of the source: a quad that draws it at its own size is not
## scaled. The build is for the main thread, once per match, never per frame; tests read `image()`
## (the CPU side), never the texture, which reads back stale after an update.

const GUTTER_PX: int = 2
const DEFAULT_WIDTH_PX: int = 1024

var _image: Image = Image.new()
var _texture: ImageTexture = null
var _regions: Dictionary[StringName, Rect2i] = {}


## An atlas of `sources`, keyed as given. A source with no readable image is left out and reported
## (`has_region` answers false for it); an empty set gives an atlas with no texture. The atlas is
## `width_px` wide, or as wide as the widest padded source.
static func build(
	sources: Dictionary[StringName, Texture2D], width_px: int = DEFAULT_WIDTH_PX
) -> RuntimeAtlas:
	var atlas: RuntimeAtlas = RuntimeAtlas.new()
	var keys: Array[StringName] = []
	var cells: Array[Image] = []
	var width: int = width_px
	for key: StringName in sources:
		var image: Image = _readable(sources[key])
		if image == null:
			push_error("RuntimeAtlas: no image to read for %s" % key)
			continue
		keys.append(key)
		cells.append(_pad(image))
		width = maxi(width, cells[-1].get_width())
	if cells.is_empty():
		return atlas
	var places: Array[Vector2i] = []
	var x: int = 0
	var y: int = 0
	var shelf: int = 0
	for cell: Image in cells:
		if x > 0 and x + cell.get_width() > width:
			y += shelf
			x = 0
			shelf = 0
		places.append(Vector2i(x, y))
		x += cell.get_width()
		shelf = maxi(shelf, cell.get_height())
	atlas._image = Image.create(width, y + shelf, false, Image.FORMAT_RGBA8)
	for index: int in cells.size():
		var size: Vector2i = cells[index].get_size()
		atlas._image.blit_rect(cells[index], Rect2i(Vector2i.ZERO, size), places[index])
		atlas._regions[keys[index]] = Rect2i(
			places[index] + Vector2i(GUTTER_PX, GUTTER_PX), size - Vector2i(2, 2) * GUTTER_PX
		)
	atlas._texture = ImageTexture.create_from_image(atlas._image)
	return atlas


## The one texture every quad of the atlas is drawn from; null for an atlas of no source.
func texture() -> ImageTexture:
	return _texture


## The CPU-side image that was uploaded: gutters included.
func image() -> Image:
	return _image


func has_region(key: StringName) -> bool:
	return _regions.has(key)


## The region of `key` in atlas texels, gutter left out; an empty Rect2i for a key that is not here.
func region(key: StringName) -> Rect2i:
	return _regions.get(key, Rect2i())


## `texture`'s image as a copy in RGBA8, or null when it has none to give.
static func _readable(texture: Texture2D) -> Image:
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


## `image` with a GUTTER_PX border that repeats its edge pixels, corners included.
static func _pad(image: Image) -> Image:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var edge: int = GUTTER_PX
	var padded: Image = Image.create(width + 2 * edge, height + 2 * edge, false, Image.FORMAT_RGBA8)
	padded.blit_rect(image, Rect2i(0, 0, width, height), Vector2i(edge, edge))
	for step: int in edge:
		padded.blit_rect(image, Rect2i(0, 0, width, 1), Vector2i(edge, step))
		padded.blit_rect(
			image, Rect2i(0, height - 1, width, 1), Vector2i(edge, edge + height + step)
		)
		padded.blit_rect(image, Rect2i(0, 0, 1, height), Vector2i(step, edge))
		padded.blit_rect(
			image, Rect2i(width - 1, 0, 1, height), Vector2i(edge + width + step, edge)
		)
	padded.fill_rect(Rect2i(0, 0, edge, edge), image.get_pixel(0, 0))
	padded.fill_rect(Rect2i(edge + width, 0, edge, edge), image.get_pixel(width - 1, 0))
	padded.fill_rect(Rect2i(0, edge + height, edge, edge), image.get_pixel(0, height - 1))
	padded.fill_rect(
		Rect2i(edge + width, edge + height, edge, edge), image.get_pixel(width - 1, height - 1)
	)
	return padded
