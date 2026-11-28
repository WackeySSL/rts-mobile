class_name GroundAtlas
extends RefCounted
## The ground's one texture (ADR 0023 sections 2 and 5, plan P116): the imported ground tiles
## `ground/<terrain_id>_a|b.svg`, the six field stages `fields/<kind>_<stage>.svg` and the wellhead
## with its shadow, packed by `RuntimeAtlas` into one page. The 64 x 32 tiles come first, each a
## whole diamond, and fill the first shelf: a regular grid of 68 x 36 cells (tile and gutter) that a
## `TileSetAtlasSource` reads with a margin of GUTTER_PX and a separation of twice that, drawing
## from the page itself (`use_texture_padding` off: the gutter does that job).

const GROUND_PATH: String = "res://assets/art/svg/ground/%s_%s.svg"
const LOOK_ROOT: String = "res://assets/art/svg/ground_looks"  ## The folders of the looks.
const LOOK_PATH: String = "%s/%s/%s_%s.svg"  ## Root, look, terrain id and variant.
const FIELD_PATH: String = "res://assets/art/svg/fields/%s.svg"
const TILE_PX: Vector2i = Vector2i(64, 32)  ## One cell's diamond; the art is 128 x 64 at 2x.
const KIT_TILE_PX: Vector2i = Vector2i(128, 64)  ## A kit piece: a diamond at 2x, drawn at 0.5.
const KINDS: Array[StringName] = [&"oil", &"gas"]
const STAGES: Array[StringName] = [&"full", &"half", &"dry"]
const WELLHEAD: StringName = &"wellhead"
const WELLHEAD_SHADOW: StringName = &"wellhead_shadow"
## The ground point in each prop's picture, px (STYLE.md "Fields": (56, 88) and (56, 31) at 2x).
const ANCHORS: Dictionary[StringName, Vector2] = {
	WELLHEAD: Vector2(28.0, 44.0), WELLHEAD_SHADOW: Vector2(28.0, 15.5)
}

const KIT_PAGE_WIDTH_PX: int = 4096  ## The kit page is at most this wide and 512 rows high.

var tile_set: TileSet = TileSet.new()  ## One atlas source, id 0, a tile for each ground and stage.
## The kit page (P656d1): the pre-rendered 128 x 64 pieces, a page of its own, one atlas source (id
## 0) in `kit_tile_set`. Empty when no kit piece loaded. A piece taller than its diamond keeps the
## diamond at its foot (the rows above go: the ground layers stay flat, ADR 0053 A2).
var kit_tile_set: TileSet = TileSet.new()
var _atlas: RuntimeAtlas = RuntimeAtlas.new()
var _kit_page: RuntimeAtlas = RuntimeAtlas.new()
var _tiles: Dictionary[StringName, Vector2i] = {}  ## Key -> coordinates in the source.
var _kit_tiles: Dictionary[StringName, Vector2i] = {}  ## Piece key -> coordinates in the kit page.
var _kit_terrains: Array[StringName] = []  ## The terrains whose every base variant is on the page.


## The page for the terrain ids `terrain_ids`. An id with no art, or a picture that is not a
## 64 x 32 tile, has no tile (`coords` says (-1, -1)) and its cells stay empty. With a `look` (a
## folder of `ground_looks/`, STYLE.md "Map looks") a terrain that the look has both diamonds for
## uses those in the same keys and the same slots, so the page is no bigger than without one.
static func build(
	terrain_ids: Array[StringName],
	look: StringName = &"",
	root: String = LOOK_ROOT,
	kit: TerrainKitDef = null
) -> GroundAtlas:
	var result: GroundAtlas = GroundAtlas.new()
	var tiles: Dictionary[StringName, Texture2D] = {}
	for id: StringName in terrain_ids:
		for variant: String in ["a", "b"]:
			_add(tiles, StringName("%s_%s" % [id, variant]), path_of(id, variant, look, root))
	for kind: StringName in KINDS:
		for stage: StringName in STAGES:
			var key: StringName = StringName("%s_%s" % [kind, stage])
			_add(tiles, key, FIELD_PATH % key)
	var sources: Dictionary[StringName, Texture2D] = {}
	sources.merge(tiles)
	for prop: StringName in ANCHORS:  # After the tiles: bigger cells, a shelf of their own.
		sources[prop] = load(FIELD_PATH % prop) as Texture2D
	var cell: Vector2i = RuntimeAtlas.cell_size(TILE_PX)
	result._atlas = RuntimeAtlas.build(sources, cell.x * maxi(tiles.size(), 1))
	result._make_tile_set(tiles.keys(), cell)
	if kit != null:
		result._build_kit(kit, terrain_ids)
	return result


func texture() -> ImageTexture:
	return _atlas.texture()


## The CPU page that was uploaded; tests read it, never the texture.
func image() -> Image:
	return _atlas.image()


## The coordinates of the tile `key` in the source, (-1, -1) when it has none.
func coords(key: StringName) -> Vector2i:
	return _tiles.get(key, Vector2i(-1, -1))


## The region of `key` on the page in texels, gutter left out.
func region(key: StringName) -> Rect2i:
	return _atlas.region(key)


## Whether the kit page holds every base variant of `id`, so its cells need no SVG diamond.
func kit_covers(id: StringName) -> bool:
	return _kit_terrains.has(id)


## The coordinates of the kit piece `key` in `kit_tile_set`, (-1, -1) for none.
func kit_coords(key: StringName) -> Vector2i:
	return _kit_tiles.get(key, Vector2i(-1, -1))


## The CPU kit page, for tests; empty when the atlas has no kit.
func kit_image() -> Image:
	return _kit_page.image()


## The region of the kit piece `key` on the kit page in texels, gutter left out.
func kit_region(key: StringName) -> Rect2i:
	return _kit_page.region(key)


## The path of a diamond: the look's when the look has both variants of the terrain, else the
## standard one (a look with only one of the two is no look for that terrain). `root` is the folder
## of the looks, which a test points at a fixture.
static func path_of(
	id: StringName, variant: String, look: StringName, root: String = LOOK_ROOT
) -> String:
	if has_look(id, look, root):
		return LOOK_PATH % [root, look, id, variant]
	return GROUND_PATH % [id, variant]


## Whether the look `look` under `root` has both diamonds of the terrain `id`.
static func has_look(id: StringName, look: StringName, root: String = LOOK_ROOT) -> bool:
	return (
		look != &""
		and ResourceLoader.exists(LOOK_PATH % [root, look, id, "a"])
		and ResourceLoader.exists(LOOK_PATH % [root, look, id, "b"])
	)


static func _add(into: Dictionary[StringName, Texture2D], key: StringName, path: String) -> void:
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture != null and Vector2i(texture.get_size()) == TILE_PX:
		into[key] = texture


func _make_tile_set(keys: Array, cell: Vector2i) -> void:
	_fill_tile_set(tile_set, _atlas, TILE_PX, keys, cell, _tiles)


## The kit pieces of the terrains in `ids` (base variants, the blends of the terrains that have
## them, the shores), as one page of 128 x 64 tiles. A piece that does not load or is not 128 wide
## is left out, and a terrain missing a base variant is left to the SVG diamonds.
func _build_kit(kit: TerrainKitDef, ids: Array[StringName]) -> void:
	var images: Dictionary[StringName, Image] = {}
	for id: StringName in ids:
		for kind: StringName in kit.kinds.get(id, PackedStringArray()):
			if kind != TerrainKit.BASE and kind != TerrainKit.BLEND and kind != TerrainKit.SHORE:
				continue
			for mask: StringName in kit.masks.get(kind, PackedStringArray()):
				var key: StringName = TerrainKitDef.key(id, kind, mask)
				var image: Image = _kit_image(kit.path_of(id, kind, mask))
				if image != null and kind == TerrainKit.BASE:
					_solidify(image)
				if image != null and kit.pieces.has(key):
					images[key] = image
		var whole: bool = kit.variants > 0
		for variant: int in kit.variants:
			whole = (
				whole
				and images.has(TerrainKitDef.key(id, TerrainKit.BASE, StringName(str(variant))))
			)
		if whole:
			_kit_terrains.append(id)
	if images.is_empty():
		return
	var cell: Vector2i = RuntimeAtlas.cell_size(KIT_TILE_PX)
	_kit_page = RuntimeAtlas.build_images(images, KIT_PAGE_WIDTH_PX)
	_fill_tile_set(kit_tile_set, _kit_page, KIT_TILE_PX, images.keys(), cell, _kit_tiles)


## Makes a base piece's anti-aliased rim opaque and grows the diamond one texel (the colour of the
## rim texel inside it). Two base pieces that meet each cover the seam fully, so no hairline and no
## dot at the four-way corners lets the clear colour through (the dark dashes of P656d1's shots).
static func _solidify(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var edits: Dictionary[Vector2i, Color] = {}
	for line: int in height + width:
		var along_x: bool = line < height
		var count: int = width if along_x else height
		var span: Array[int] = [0, count - 1]
		for end: int in 2:
			var step: int = 1 - 2 * end
			var at: int = span[end]
			while at >= 0 and at < count:
				var cell: Vector2i = Vector2i(at, line) if along_x else Vector2i(line - height, at)
				if image.get_pixelv(cell).a > 0.0:
					break
				at += step
			if at < 0 or at >= count:
				continue
			for depth: int in 3:  # The rim texels, then the one beyond the edge.
				var inner: int = at + step * depth
				var cell: Vector2i = (
					Vector2i(inner, line) if along_x else Vector2i(line - height, inner)
				)
				if inner < 0 or inner >= count:
					break
				var color: Color = image.get_pixelv(cell)
				if color.a > 0.0 and color.a < 1.0:
					edits[cell] = Color(color, 1.0)
			var outer: int = at - step
			if outer >= 0 and outer < count:
				var out_cell: Vector2i = (
					Vector2i(outer, line) if along_x else Vector2i(line - height, outer)
				)
				var edge: Vector2i = Vector2i(at, line) if along_x else Vector2i(line - height, at)
				edits[out_cell] = Color(image.get_pixelv(edge), 1.0)
	for cell: Vector2i in edits:
		image.set_pixelv(cell, edits[cell])


## A piece's image cropped to its diamond at the foot, null when it is missing or not 128 wide.
static func _kit_image(path: String) -> Image:
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if (
		texture == null
		or texture.get_width() != KIT_TILE_PX.x
		or texture.get_height() < KIT_TILE_PX.y
	):
		return null
	var image: Image = texture.get_image()
	var rise: int = image.get_height() - KIT_TILE_PX.y
	return image.get_region(Rect2i(0, rise, KIT_TILE_PX.x, KIT_TILE_PX.y)) if rise > 0 else image


## `set_def` with one atlas source of `page`, a tile of `size` at each key's region (the page is a
## regular grid of `cell`, a gutter around each tile), the coordinates noted into `into`.
static func _fill_tile_set(
	set_def: TileSet,
	page: RuntimeAtlas,
	size: Vector2i,
	keys: Array,
	cell: Vector2i,
	into: Dictionary[StringName, Vector2i]
) -> void:
	set_def.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	set_def.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	set_def.tile_size = size
	var gutter: Vector2i = Vector2i(RuntimeAtlas.GUTTER_PX, RuntimeAtlas.GUTTER_PX)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.use_texture_padding = false
	source.texture = page.texture()
	source.texture_region_size = size
	source.margins = gutter
	source.separation = gutter * 2
	for key: StringName in keys:
		var at: Vector2i = (page.region(key).position - gutter) / cell
		into[key] = at
		source.create_tile(at)
	set_def.add_source(source, 0)
