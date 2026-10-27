extends RefCounted
## What the building suites measure on a generated building (plan row P104): its default view at
## zoom 1 on a transparent page, the team share of that view, its silhouette at 32 px, the overlap
## of two silhouettes, the pieces of a picture and the cover of a model's members at a height. Not a
## test suite (no GdUnitTestSuite base).

const Z_PX: float = 39.19183588453085  ## A tile of height at zoom 1 (ArtRender.Z_PX / 2).
const SCALE: float = 0.5  ## The 2x art at zoom 1.
const PAGE: Vector2i = Vector2i(320, 320)
const GROUND_POINT: Vector2i = Vector2i(160, 200)  ## Where the footprint's centre goes.
const SIDE_PX: int = 32
const KEY_TOLERANCE: float = 0.06  ## Summed difference of the three channels in 0 to 1.


static func raster(text: String, scale: float) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text, scale)
	return image


## "width height" of the SVG in `path`, from its root element.
static func svg_size(path: String) -> String:
	var root: RegEx = RegEx.create_from_string('<svg[^>]* width="(\\d+)" height="(\\d+)"')
	var found: RegExMatch = root.search(FileAccess.get_file_as_string(path))
	return "%s %s" % [found.get_string(1), found.get_string(2)] if found != null else ""


## The default view of a building on a transparent page at zoom 1, its footprint's centre at
## GROUND_POINT: the body, and the head at its mount facing `head_dir`.
static func default_picture(sheet: IsoSheetDef, head_dir: int) -> Image:
	var picture: Image = Image.create_empty(PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8)
	var body: Image = raster(FileAccess.get_file_as_string(sheet.path(&"hull", -1)), SCALE)
	picture.blend_rect(
		body,
		Rect2i(Vector2i.ZERO, body.get_size()),
		GROUND_POINT - Vector2i(Vector2(sheet.origin(&"hull")) * SCALE)
	)
	if sheet.has_part(&"head"):
		var head: Image = raster(
			FileAccess.get_file_as_string(sheet.path(&"head", head_dir)), SCALE
		)
		var at: Vector2 = sheet.mount(0) - Vector2(sheet.origin(&"head"))
		picture.blend_rect(
			head, Rect2i(Vector2i.ZERO, head.get_size()), GROUND_POINT + Vector2i(at * SCALE)
		)
	return picture


## The share of the opaque pixels (alpha above 0.95) that are one of the faction's key colours.
static func team_share(picture: Image, faction: StringName) -> float:
	var keys: Array[Color] = []
	for hex: String in ArtPalette.KEYS[faction]:
		keys.append(Color(hex))
	var team: int = 0
	var body: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var pixel: Color = picture.get_pixel(x, y)
			if pixel.a < 0.95:
				continue
			body += 1
			for key: Color in keys:
				var gap: float = absf(pixel.r - key.r) + absf(pixel.g - key.g)
				if gap + absf(pixel.b - key.b) < KEY_TOLERANCE:
					team += 1
					break
	return float(team) / maxi(body, 1)


## The silhouette of a picture scaled to fit 32 px and centred on a 32 px page.
static func mask_32(picture: Image) -> Image:
	var box: Rect2i = picture.get_used_rect()
	var small: Image = picture.get_region(box)
	var factor: float = float(SIDE_PX) / maxi(box.size.x, box.size.y)
	small.resize(
		maxi(1, roundi(box.size.x * factor)),
		maxi(1, roundi(box.size.y * factor)),
		Image.INTERPOLATE_LANCZOS
	)
	var page: Image = Image.create_empty(SIDE_PX, SIDE_PX, false, Image.FORMAT_RGBA8)
	page.blend_rect(
		small,
		Rect2i(Vector2i.ZERO, small.get_size()),
		Vector2i((SIDE_PX - small.get_width()) / 2, (SIDE_PX - small.get_height()) / 2)
	)
	return page


## Intersection over union of the pixels with ink in two pages of one size.
static func overlap(a: Image, b: Image) -> float:
	var both: int = 0
	var either: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var in_a: bool = a.get_pixel(x, y).a > 0.5
			var in_b: bool = b.get_pixel(x, y).a > 0.5
			both += int(in_a and in_b)
			either += int(in_a or in_b)
	return float(both) / maxi(either, 1)


## The number of connected shapes (8 neighbours, pixels more than half opaque) in an image.
static func pieces(image: Image) -> int:
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	var w: int = image.get_width()
	var h: int = image.get_height()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	var count: int = 0
	for first: int in w * h:
		if seen[first] == 1 or data[first * 4 + 3] <= 127:
			continue
		count += 1
		seen[first] = 1
		var stack: PackedInt32Array = PackedInt32Array([first])
		while not stack.is_empty():
			var at: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var x: int = at % w + dx
					var y: int = at / w + dy
					if x < 0 or y < 0 or x >= w or y >= h:
						continue
					var next: int = y * w + x
					if seen[next] == 0 and data[next * 4 + 3] > 127:
						seen[next] = 1
						stack.append(next)
	return count


## The tallest point of a model in tiles, a head at its mount.
static func top(model: ArtModel) -> float:
	var tallest: float = 0.0
	for part: StringName in model.parts():
		for prim: ArtPrim in model.primitives(part):
			var lift: float = model.mount.z if part == &"head" else 0.0
			tallest = maxf(tallest, prim.aabb().end.z + lift)
	return tallest


## The share of the box of the hull's members at height `z` that they cover, summed over their own
## boxes (an overlap counts twice, so it is an upper bound): a frame stays low, a solid mass is 1.
static func cross_section(model: ArtModel, z: float) -> float:
	var area: float = 0.0
	var box: Rect2 = Rect2()
	var first: bool = true
	for prim: ArtPrim in model.primitives(&"hull"):
		var shape: AABB = prim.aabb()
		if shape.position.z <= z and z <= shape.end.z:
			var flat: Rect2 = Rect2(shape.position.x, shape.position.y, shape.size.x, shape.size.y)
			area += flat.get_area()
			box = flat if first else box.merge(flat)
			first = false
	return area / box.get_area() if not first else 0.0


static func grey(image: Image, at: Vector2i) -> float:
	var pixel: Color = image.get_pixelv(at)
	return 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
