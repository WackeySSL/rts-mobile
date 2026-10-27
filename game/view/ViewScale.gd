class_name ViewScale
extends RefCounted
## The sim's tile size and the scalar length helper of the view. Positions go through
## `IsoProjection` (ADR 0023 section 1), which holds the projection's 32 and 16; this file keeps
## what a position function cannot: the 1000 milli per tile and a length along a tile's width.

const PX_PER_TILE: int = 64  ## A tile's diamond is this wide on screen (test_view_scale).
const MILLI_PER_TILE: int = World.MILLI_PER_TILE  ## The sim's tile size.


static func milli_to_px(v: int) -> float:
	return float(v) * PX_PER_TILE / MILLI_PER_TILE
