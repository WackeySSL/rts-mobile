class_name IsoProjection
extends RefCounted
## The view's one projection from the sim's square grid to the screen (ADR 0023 section 1):
## dimetric 2:1, a tile is a 64 x 32 px diamond, nothing is ever rotated. Grid +x runs down and to
## the right on the screen, grid +y down and to the left, and ground (0, 0) is the top corner of the
## map's diamond. For a ground point of (x, y) milli-tiles:
##   px = (x - y) * 32 / 1000      py = (x + y) * 16 / 1000
## The sim keeps its square grid, its integers and its rules; only drawing and input convert here,
## and this is the only file that holds the 32 and the 16. Pure and static, and it allocates
## nothing but the value types it returns (and the diamond's four corners).

const HALF_W: int = 32  ## Half the width of a tile's diamond, px.
const HALF_H: int = 16  ## Half its height, px.
const SQRT2: float = 1.4142135623730951
## A shape lying on the ground keeps its width on the screen and its height falls to this share: a
## circle is a 2:1 ellipse (`ellipse_px`), the markers' chevrons and diamond are flattened by it.
const GROUND_FLATTEN: float = 0.5
## Where a `TileMapLayer` node sits (tile size 64 x 32, diamond down) so that its `map_to_local`
## of a cell is `cell_centre_px` of that cell: the engine puts cell (0, 0)'s diamond in the box
## from (0, 0) to (64, 32), while ground (0, 0) is the map's top corner.
const TILE_LAYER_OFFSET: Vector2 = Vector2(-HALF_W, 0)
const _MILLI: int = ViewScale.MILLI_PER_TILE


## The screen point (world px) of the ground point (x, y), in milli-tiles.
static func ground_to_px(x: int, y: int) -> Vector2:
	return Vector2(float((x - y) * HALF_W) / _MILLI, float((x + y) * HALF_H) / _MILLI)


## The ground point under the world px `p`, rounded to the nearest milli-tile, so the sim only
## sees integers. It may lie outside the map: the sim clamps a Command's target.
static func px_to_ground(p: Vector2) -> Vector2i:
	var sum: float = p.y / HALF_H  # x + y, in tiles.
	var diff: float = p.x / HALF_W  # x - y, in tiles.
	return Vector2i(roundi((sum + diff) * _MILLI * 0.5), roundi((sum - diff) * _MILLI * 0.5))


## The centre of the diamond of cell (`col`, `row`), world px.
static func cell_centre_px(col: int, row: int) -> Vector2:
	return Vector2(float((col - row) * HALF_W), float((col + row + 1) * HALF_H))


## The two semi-axes, px, of the ground circle of radius `r` milli-tiles: a 2:1 ellipse whose
## horizontal semi-axis is `r * 32 * sqrt(2) / 1000` and whose vertical one is half of it.
static func ellipse_px(r: int) -> Vector2:
	var across: float = float(r * HALF_W) * SQRT2 / _MILLI
	return Vector2(across, across * HALF_H / HALF_W)


## The corners of the diamond of a map of `map_w` x `map_h` tiles (the snapshot's `map_cols` and
## `map_rows`), world px, clockwise from the top: ground (0, 0), (map_w, 0), (map_w, map_h) and
## (0, map_h). An empty array for a map with no area.
static func map_diamond(map_w: int, map_h: int) -> PackedVector2Array:
	if map_w <= 0 or map_h <= 0:
		return PackedVector2Array()
	var side: int = _MILLI
	return PackedVector2Array(
		[
			ground_to_px(0, 0),
			ground_to_px(map_w * side, 0),
			ground_to_px(map_w * side, map_h * side),
			ground_to_px(0, map_h * side),
		]
	)


## The bounding rect of `map_diamond(map_w, map_h)`.
static func map_bounds(map_w: int, map_h: int) -> Rect2:
	var size: int = map_w + map_h
	return Rect2(float(-map_h * HALF_W), 0.0, float(size * HALF_W), float(size * HALF_H))


## The transform from cell units to world px: a unit square (a texel of the fog, a cell of the
## terrain) becomes that cell's diamond, with the map's top corner at the origin.
static func cell_to_px() -> Transform2D:
	return Transform2D(Vector2(HALF_W, HALF_H), Vector2(-HALF_W, HALF_H), Vector2.ZERO)


## The angle on the screen (radians, east 0, y down) of a ground vector (`dx`, `dy`), in any one
## unit: the way a thing that drives or aims along it looks turned.
static func screen_angle(dx: float, dy: float) -> float:
	return atan2((dx + dy) * HALF_H, (dx - dy) * HALF_W)


## The point of `diamond` (as `map_diamond` gives it) nearest `p` along the diamond's own axes:
## `p`'s ground point clamped into the map and projected back, without the rounding of
## `px_to_ground`. `p` for an empty diamond.
static func clamp_to_diamond(p: Vector2, diamond: PackedVector2Array) -> Vector2:
	if diamond.size() != 4:
		return p
	var top: Vector2 = diamond[0]
	var edge_x: Vector2 = diamond[1] - top  # One map width along grid +x.
	var edge_y: Vector2 = diamond[3] - top  # One map height along grid +y.
	var det: float = edge_x.x * edge_y.y - edge_x.y * edge_y.x
	if is_zero_approx(det):
		return p
	var d: Vector2 = p - top
	var along_x: float = clampf((d.x * edge_y.y - d.y * edge_y.x) / det, 0.0, 1.0)
	var along_y: float = clampf((edge_x.x * d.y - edge_x.y * d.x) / det, 0.0, 1.0)
	return top + edge_x * along_x + edge_y * along_y
