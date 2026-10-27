class_name RuntimeAtlas
extends RefCounted
## One texture atlas built at run time (ADR 0023 section 2; from the shelved P84's helper): the
## pictures a layer needs go into a single RGBA8 image that is uploaded once, so the layer draws
## them as regions of one texture in one call (ADR 0011 section 3). IsoAtlas feeds it rasterised
## frames, the ground (P116) imported textures. Each source sits in a padded cell: the image with a
## GUTTER_PX border that repeats its own edge pixels (a transparent edge repeats transparent
## pixels), so linear filtering never samples a neighbour. Cells are packed in rows (shelves) in the
## order given (`layout`). A region is the image inside its gutter, in texels of the atlas. Built on
## the main thread, once per match; tests read `image()`, never the texture, which reads stale.

const GUTTER_PX: int = 2
const DEFAULT_WIDTH_PX: int = 1024

var _image: Image = Image.new()
var _texture: ImageTexture = null
var _regions: Dictionary[StringName, Rect2i] = {}


## An atlas of the imported `sources`, keyed as given: `build_images` of their copies. A source
## with no readable image is left out and reported (`has_region` answers false for it).
static func build(
	sources: Dictionary[StringName, Texture2D], width_px: int = DEFAULT_WIDTH_PX
) -> RuntimeAtlas:
	var images: Dictionary[StringName, Image] = {}
	for key: StringName in sources:
		var texture: Texture2D = sources[key]
		images[key] = texture.get_image() if texture != null else null
	return build_images(images, width_px)


## An atlas of `sources`, keyed as given; the images are made RGBA8 in place. An image that is
## null or empty is left out and reported; an empty set gives an atlas with no texture. The atlas
## is `width_px` wide, or as wide as the widest padded source. The CPU image is kept (`image()`)
## unless `keep_image` is false: the upload is the only copy a match needs.
static func build_images(
	sources: Dictionary[StringName, Image],
	width_px: int = DEFAULT_WIDTH_PX,
	keep_image: bool = true
) -> RuntimeAtlas:
	var atlas: RuntimeAtlas = RuntimeAtlas.new()
	var keys: Array[StringName] = []
	var cells: Array[Vector2i] = []
	for key: StringName in sources:
		var image: Image = sources[key]
		if image == null or image.is_empty():
			push_error("RuntimeAtlas: no image to read for %s" % key)
			continue
		if image.is_compressed():
			image.decompress()
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		keys.append(key)
		cells.append(cell_size(image.get_size()))
	if keys.is_empty():
		return atlas
	var places: Array[Vector2i] = []
	var page: Vector2i = layout(cells, width_px, places)
	atlas._image = Image.create(page.x, page.y, false, Image.FORMAT_RGBA8)
	for index: int in keys.size():
		var image: Image = sources[keys[index]]
		_stamp(atlas._image, image, places[index])
		atlas._regions[keys[index]] = Rect2i(
			places[index] + Vector2i(GUTTER_PX, GUTTER_PX), image.get_size()
		)
	atlas._texture = ImageTexture.create_from_image(atlas._image)
	if not keep_image:
		atlas._image = Image.new()
	return atlas


## The padded cell of an image of `size`: the gutter on every side.
static func cell_size(size: Vector2i) -> Vector2i:
	return size + Vector2i(2, 2) * GUTTER_PX


## The shelf packing of `cells` (padded sizes) in the order given: `places` gets the top-left of
## each (it is cleared first) and the result is the page size, `width_px` wide or as wide as the
## widest cell, as tall as the shelves. A cell starts a new shelf when it would pass `width_px`.
## Pure, so a caller can ask how tall a page would be before it rasterises anything.
static func layout(cells: Array[Vector2i], width_px: int, places: Array[Vector2i]) -> Vector2i:
	places.clear()
	var width: int = width_px
	for cell: Vector2i in cells:
		width = maxi(width, cell.x)
	var x: int = 0
	var y: int = 0
	var shelf: int = 0
	for cell: Vector2i in cells:
		if x > 0 and x + cell.x > width:
			y += shelf
			x = 0
			shelf = 0
		places.append(Vector2i(x, y))
		x += cell.x
		shelf = maxi(shelf, cell.y)
	return Vector2i(width, y + shelf)


## The one texture every quad of the atlas is drawn from; null for an atlas of no source.
func texture() -> ImageTexture:
	return _texture


## The CPU-side image that was uploaded: gutters included. Empty when `keep_image` was false.
func image() -> Image:
	return _image


func has_region(key: StringName) -> bool:
	return _regions.has(key)


## The region of `key` in atlas texels, gutter left out; an empty Rect2i for a key that is not here.
func region(key: StringName) -> Rect2i:
	return _regions.get(key, Rect2i())


## `image` stamped into `page` at `origin` (its cell's top-left) with the GUTTER_PX border that
## repeats its edge pixels, corners included.
static func _stamp(page: Image, image: Image, origin: Vector2i) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var edge: int = GUTTER_PX
	page.blit_rect(image, Rect2i(0, 0, width, height), origin + Vector2i(edge, edge))
	for step: int in edge:
		var top: Rect2i = Rect2i(0, 0, width, 1)
		page.blit_rect(image, top, origin + Vector2i(edge, step))
		var bottom: Rect2i = Rect2i(0, height - 1, width, 1)
		page.blit_rect(image, bottom, origin + Vector2i(edge, edge + height + step))
		var left: Rect2i = Rect2i(0, 0, 1, height)
		page.blit_rect(image, left, origin + Vector2i(step, edge))
		var right: Rect2i = Rect2i(width - 1, 0, 1, height)
		page.blit_rect(image, right, origin + Vector2i(edge + width + step, edge))
	page.fill_rect(Rect2i(origin, Vector2i(edge, edge)), image.get_pixel(0, 0))
	var east: Vector2i = origin + Vector2i(edge + width, 0)
	page.fill_rect(Rect2i(east, Vector2i(edge, edge)), image.get_pixel(width - 1, 0))
	var south: Vector2i = origin + Vector2i(0, edge + height)
	page.fill_rect(Rect2i(south, Vector2i(edge, edge)), image.get_pixel(0, height - 1))
	var corner: Vector2i = origin + Vector2i(edge + width, edge + height)
	page.fill_rect(Rect2i(corner, Vector2i(edge, edge)), image.get_pixel(width - 1, height - 1))
