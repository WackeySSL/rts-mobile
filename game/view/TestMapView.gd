class_name TestMapView
extends Node2D
## View-only test map: a checkerboard of two grass tones with a 1 px grid. Phase 2 replaces it
## with sim map data. Tile size and colours are set in scenes/main.tscn, the size by main_view.gd.

@export var size_tiles: Vector2i = Vector2i(32, 32):
	set(value):
		size_tiles = value
		queue_redraw()
@export var tile_px: int = 64:
	set(value):
		tile_px = value
		queue_redraw()
@export var tone_a: Color = Color("5E7D4A")
@export var tone_b: Color = Color("6F8F57")
@export var grid_color: Color = Color(0.0, 0.0, 0.0, 0.2)
@export var grid_width_px: float = 1.0


## The map rectangle in world pixels, starting at the origin.
func map_rect_px() -> Rect2i:
	return Rect2i(0, 0, size_tiles.x * tile_px, size_tiles.y * tile_px)


func _draw() -> void:
	var rect: Rect2 = Rect2(map_rect_px())
	draw_rect(rect, tone_a)
	var tile: float = float(tile_px)
	for ty: int in size_tiles.y:
		for tx: int in size_tiles.x:
			if (tx + ty) % 2 == 1:
				draw_rect(Rect2(tx * tile, ty * tile, tile, tile), tone_b)
	for tx: int in size_tiles.x + 1:
		var x: float = tx * tile
		draw_line(Vector2(x, 0.0), Vector2(x, rect.size.y), grid_color, grid_width_px)
	for ty: int in size_tiles.y + 1:
		var y: float = ty * tile
		draw_line(Vector2(0.0, y), Vector2(rect.size.x, y), grid_color, grid_width_px)
