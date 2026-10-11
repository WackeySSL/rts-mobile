class_name ViewScale
extends RefCounted
## Sim milli-tiles to world pixels and back. The sim counts 1000 milli per tile and the view draws
## a tile 64 px wide. View code converts here and nowhere else, so no other file holds the 64.

const PX_PER_TILE: int = 64  ## TestMapView.tile_px must equal this.
const MILLI_PER_TILE: int = World.MILLI_PER_TILE  ## The sim's tile size.


static func milli_to_px(v: int) -> float:
	return float(v) * PX_PER_TILE / MILLI_PER_TILE


## Rounds to the nearest milli-tile. Used for command targets, so the sim only sees integers.
static func px_to_milli(v: float) -> int:
	return roundi(v * MILLI_PER_TILE / PX_PER_TILE)


static func milli_to_px_vec(x: int, y: int) -> Vector2:
	return Vector2(milli_to_px(x), milli_to_px(y))
