class_name MapView
extends Node2D
## Draws the sim's terrain (ADR 0011 section 3, assets/art/STYLE.md "Fog and terrain"). The map is
## baked into one RGBA8 image of `bake_px_per_tile` texels per tile, once per match and once per
## `map_version`, and drawn as one textured rect with NEAREST filtering. The rect is in cell units
## under `IsoProjection.cell_to_px()` (ADR 0023 sections 1-2), so the map shows as a diamond and a
## tile is a 64 x 32 px diamond whose texels are 8 x 4 px steps. The map has no grid (Michael,
## 2026-10-12): tiles meet edge to edge. It reads only `runner.snapshot` (ADR 0012 section 3),
## afresh in every call, and a new `match_serial` is a new match; a change of the map shows from
## the tick after it (the next capture).
##
## Under a ground (P116): while `ground` has a tile for every cell the bake's rect is not drawn; the
## bake stays, for the minimap's colours and P52's keys (ADR 0023 section 15).

const TILE_GRID: int = 8  ## The grid the rects of `tiles` use, whatever the bake size.
const MISSING: Color = Color.MAGENTA  ## Shown for a terrain or colour key the dictionaries lack.

## STYLE.md colours: a terrain id, and `<id>_b` and `<id>_c` for the second and third tone of its
## tile. The gallery's `TERRAIN_COLORS` holds the same keys (P52 compares the two).
@export var colors: Dictionary[StringName, Color] = {
	&"grass": Color("5E7D4A"),
	&"grass_b": Color("6F8F57"),
	&"sand": Color("CDB98F"),
	&"scrub": Color("4E5A3A"),
	&"scrub_b": Color("6B7A4F"),
	&"scrub_c": Color("8C9A6B"),
	&"rock": Color("6E6A66"),
	&"rock_b": Color("8C8782"),
	&"rock_c": Color("4F4B48"),
	&"water": Color("2E5E7E"),
	&"water_b": Color("3C7396"),
	&"ore": Color("8A6F4D"),
}
## STYLE.md tiles: per terrain id the filled rects "x,y,w,h,key" in drawing order, the first being
## the base. A key `<id>_b` is the same terrain's tile on tiles with x + y odd (grass has one).
@export var tiles: Dictionary[StringName, String] = {
	&"grass": "0,0,8,8,grass",
	&"grass_b": "0,0,8,8,grass_b",
	&"sand": "0,0,8,8,sand",
	&"scrub": "0,0,8,8,scrub 1,1,3,3,scrub_b 4,4,3,3,scrub_b 1,1,1,1,scrub_c 4,4,1,1,scrub_c",
	&"rock": "0,0,8,8,rock 0,0,8,1,rock_b 0,0,1,8,rock_b 0,7,8,1,rock_c 7,0,1,8,rock_c",
	&"water": "0,0,8,8,water 1,2,4,1,water_b 4,6,4,1,water_b",
	&"ore": "0,0,8,8,ore",
}
@export var bake_px_per_tile: int = 8
@export var runner: MatchRunner
## The textured ground that hides this node's rect while it covers the map; null draws the bake.
@export var ground: GroundLayer

var _serial: int = -1  ## match_serial of the last bake: another one is a new match.
var _version: int = -1
var _bakes: int = 0
var _draws: int = 0
var _drawn: Rect2 = Rect2()
var _drawn_transform: Transform2D = Transform2D.IDENTITY
var _cells: Vector2 = Vector2.ZERO  ## Columns and rows of the last bake: the rect it is drawn in.
var _image: Image = Image.new()
var _texture: ImageTexture = null
var _covered: bool = false  ## Whether `ground` covered the map when the rect was last decided.


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync()


func _process(_delta: float) -> void:
	_sync()


## The corners of the map's diamond in world px (`IsoProjection.map_diamond`), clockwise from the
## top, and empty with no map: what the camera clamps the view centre into.
func map_diamond_px() -> PackedVector2Array:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return PackedVector2Array()
	return IsoProjection.map_diamond(snap.map_cols, snap.map_rows)


## The bounding rect of the diamond in world px, and an empty rect with no map.
func map_rect_px() -> Rect2i:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or snap.map_cols <= 0 or snap.map_rows <= 0:
		return Rect2i()
	return Rect2i(IsoProjection.map_bounds(snap.map_cols, snap.map_rows))


## Bakes made so far: one per match and one per `map_version`, never one per frame.
func bake_count() -> int:
	return _bakes


## Draw commands the last `_draw()` issued. The map is one textured rect, so 1 once it is baked,
## and 0 while a ground covers it.
func draw_count() -> int:
	return _draws


## The rect the last `_draw()` gave `draw_texture_rect`, in cell units (the map's columns and
## rows from the origin), empty when nothing was drawn.
func drawn_rect() -> Rect2:
	return _drawn


## The transform the last `_draw()` drew `drawn_rect()` under (`IsoProjection.cell_to_px()`), the
## identity when nothing was drawn.
func drawn_transform() -> Transform2D:
	return _drawn_transform


## The CPU-side bake that is uploaded. Tests read texels here, never from the ImageTexture, which
## reads back stale after `update()`.
func image() -> Image:
	_sync()
	return _image


func _draw() -> void:
	_draws = 0
	_drawn = Rect2()
	_drawn_transform = Transform2D.IDENTITY
	if _texture != null and not _covered:
		_drawn = Rect2(Vector2.ZERO, _cells)
		_drawn_transform = IsoProjection.cell_to_px()
		draw_set_transform_matrix(_drawn_transform)
		draw_texture_rect(_texture, _drawn, false)
		_draws += 1


func _sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap != null and (snap.match_serial != _serial or snap.map_version != _version):
		_bake(snap)
	var covered: bool = ground != null and ground.covers_map()
	if covered != _covered:
		_covered = covered
		queue_redraw()


func _bake(snap: MatchSnapshot) -> void:
	_serial = snap.match_serial
	_version = snap.map_version
	_bakes += 1
	var cols: int = snap.map_cols
	var rows: int = snap.map_rows
	_cells = Vector2(cols, rows)
	if cols <= 0 or rows <= 0:  # No map: nothing to show, and nothing left of the last match.
		_image = Image.new()
		_texture = null
		queue_redraw()
		return
	var px: int = maxi(bake_px_per_tile, 1)
	# Two tiles per terrain, for even and odd x + y, built once and blitted per cell.
	var kinds: Array[Image] = []
	for id: StringName in snap.terrain_ids:
		kinds.append(_tile(id, px))
		var odd: StringName = StringName(String(id) + "_b")
		kinds.append(_tile(odd, px) if tiles.has(odd) else kinds[-1])
	var image: Image = Image.create(cols * px, rows * px, false, Image.FORMAT_RGBA8)
	var terrain: PackedByteArray = snap.terrain
	var tile_rect: Rect2i = Rect2i(0, 0, px, px)
	var cell: int = 0
	for y: int in rows:
		for x: int in cols:
			image.blit_rect(
				kinds[terrain[cell] * 2 + ((x + y) & 1)], tile_rect, Vector2i(x, y) * px
			)
			cell += 1
	_image = image
	if _texture != null and _texture.get_size() == Vector2(image.get_size()):
		_texture.update(image)
	else:
		_texture = ImageTexture.create_from_image(image)
	queue_redraw()


## One tile: the rects of `tiles[key]` in drawing order on the 8 x 8 grid, scaled to `px` texels.
## A missing tile, or a key in it that `colors` lacks, shows `MISSING`.
func _tile(key: StringName, px: int) -> Image:
	var image: Image = Image.create(TILE_GRID, TILE_GRID, false, Image.FORMAT_RGBA8)
	image.fill(MISSING)
	var spec: String = tiles[key] if tiles.has(key) else ""
	for fill: String in spec.split(" ", false):
		var part: PackedStringArray = fill.split(",")
		var color: Color = colors.get(StringName(part[4]), MISSING)
		image.fill_rect(Rect2i(int(part[0]), int(part[1]), int(part[2]), int(part[3])), color)
	if px != TILE_GRID:
		image.resize(px, px, Image.INTERPOLATE_NEAREST)
	return image
