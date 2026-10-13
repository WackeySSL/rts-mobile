class_name MapView
extends Node2D
## Draws the sim's terrain (ADR 0011 section 3, assets/art/STYLE.md "Fog and terrain"). The map is
## baked into one RGBA8 image of `bake_px_per_tile` texels per tile, once per match and once per
## `map_version`, and drawn as one textured rect with NEAREST filtering, so a texel is 8 x 8 world
## px. The map has no grid (Michael, 2026-10-12): tiles meet edge to edge. Until P40 it reads
## `runner.world`, and a new World object is a new match (P38 adds `match_serial`, which then
## replaces the instance id).

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
}
@export var bake_px_per_tile: int = 8
@export var runner: MatchRunner

var _world_id: int = 0  ## Instance id of the last baked World: a new one is a new match.
var _version: int = -1
var _bakes: int = 0
var _draws: int = 0
var _drawn: Rect2 = Rect2()
var _image: Image = Image.new()
var _texture: ImageTexture = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync()


func _process(_delta: float) -> void:
	_sync()


## The map in world px, from the origin: columns and rows of the World times 64.
func map_rect_px() -> Rect2i:
	if runner == null or runner.world == null:
		return Rect2i()
	var world: World = runner.world
	return Rect2i(
		0, 0, world.map_cols * ViewScale.PX_PER_TILE, world.map_rows * ViewScale.PX_PER_TILE
	)


## Bakes made so far: one per match and one per `map_version`, never one per frame.
func bake_count() -> int:
	return _bakes


## Draw commands the last `_draw()` issued. The map is one textured rect, so 1 once it is baked.
func draw_count() -> int:
	return _draws


## The rect the last `_draw()` gave `draw_texture_rect`, empty when nothing was drawn.
func drawn_rect() -> Rect2:
	return _drawn


## The CPU-side bake that is uploaded. Tests read texels here, never from the ImageTexture, which
## reads back stale after `update()`.
func image() -> Image:
	_sync()
	return _image


func _draw() -> void:
	_draws = 0
	_drawn = Rect2()
	if _texture != null:
		_drawn = Rect2(map_rect_px())
		draw_texture_rect(_texture, _drawn, false)
		_draws += 1


func _sync() -> void:
	var world: World = runner.world if runner != null else null
	if world != null and (world.get_instance_id() != _world_id or world.map_version != _version):
		_bake(world)


func _bake(world: World) -> void:
	_world_id = world.get_instance_id()
	_version = world.map_version
	_bakes += 1
	var cols: int = world.map_cols
	var rows: int = world.map_rows
	if cols <= 0 or rows <= 0:  # No map: nothing to show, and nothing left of the last match.
		_image = Image.new()
		_texture = null
		queue_redraw()
		return
	var px: int = maxi(bake_px_per_tile, 1)
	# Two tiles per terrain, for even and odd x + y, built once and blitted per cell.
	var kinds: Array[Image] = []
	for id: StringName in world.terrain_ids:
		kinds.append(_tile(id, px))
		var odd: StringName = StringName(String(id) + "_b")
		kinds.append(_tile(odd, px) if tiles.has(odd) else kinds[-1])
	var image: Image = Image.create(cols * px, rows * px, false, Image.FORMAT_RGBA8)
	var terrain: PackedByteArray = world.terrain
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
