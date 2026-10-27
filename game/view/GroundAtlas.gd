class_name GroundAtlas
extends RefCounted
## The ground's one texture (ADR 0023 sections 2 and 5, plan P116): the imported ground tiles
## `ground/<terrain_id>_a|b.svg`, the six field stages `fields/<kind>_<stage>.svg` and the wellhead
## with its shadow, packed by `RuntimeAtlas` into one page. The 64 x 32 tiles come first, each a
## whole diamond, and fill the first shelf: a regular grid of 68 x 36 cells (tile and gutter) that a
## `TileSetAtlasSource` reads with a margin of GUTTER_PX and a separation of twice that, drawing
## from the page itself (`use_texture_padding` off: the gutter does that job).

const GROUND_PATH: String = "res://assets/art/svg/ground/%s_%s.svg"
const FIELD_PATH: String = "res://assets/art/svg/fields/%s.svg"
const TILE_PX: Vector2i = Vector2i(64, 32)  ## One cell's diamond; the art is 128 x 64 at 2x.
const KINDS: Array[StringName] = [&"oil", &"gas"]
const STAGES: Array[StringName] = [&"full", &"half", &"dry"]
const WELLHEAD: StringName = &"wellhead"
const WELLHEAD_SHADOW: StringName = &"wellhead_shadow"
## The ground point in each prop's picture, px (STYLE.md "Fields": (56, 88) and (56, 31) at 2x).
const ANCHORS: Dictionary[StringName, Vector2] = {
	WELLHEAD: Vector2(28.0, 44.0), WELLHEAD_SHADOW: Vector2(28.0, 15.5)
}

var tile_set: TileSet = TileSet.new()  ## One atlas source, id 0, a tile for each ground and stage.
var _atlas: RuntimeAtlas = RuntimeAtlas.new()
var _tiles: Dictionary[StringName, Vector2i] = {}  ## Key -> coordinates in the source.


## The page for the terrain ids `terrain_ids`. An id with no art, or a picture that is not a
## 64 x 32 tile, has no tile (`coords` says (-1, -1)) and its cells stay empty.
static func build(terrain_ids: Array[StringName]) -> GroundAtlas:
	var result: GroundAtlas = GroundAtlas.new()
	var tiles: Dictionary[StringName, Texture2D] = {}
	for id: StringName in terrain_ids:
		for variant: String in ["a", "b"]:
			_add(tiles, StringName("%s_%s" % [id, variant]), GROUND_PATH % [id, variant])
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


static func _add(into: Dictionary[StringName, Texture2D], key: StringName, path: String) -> void:
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture != null and Vector2i(texture.get_size()) == TILE_PX:
		into[key] = texture


func _make_tile_set(keys: Array, cell: Vector2i) -> void:
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = TILE_PX
	var gutter: Vector2i = Vector2i(RuntimeAtlas.GUTTER_PX, RuntimeAtlas.GUTTER_PX)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.use_texture_padding = false
	source.texture = _atlas.texture()
	source.texture_region_size = TILE_PX
	source.margins = gutter
	source.separation = gutter * 2
	for key: StringName in keys:
		var at: Vector2i = (region(key).position - gutter) / cell
		_tiles[key] = at
		source.create_tile(at)
	tile_set.add_source(source, 0)
