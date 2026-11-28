class_name WallCover
extends RefCounted
## Which raised rock cells cover a screen point (ADR 0053 section 7, amendment A7 and A8, plan
## P656d3): pure and static, the GDScript twin of `silhouette.gdshader`'s cover test and the
## inverse that the ground taps use. A raised cell is a prism one diamond height (32 px) tall, so
## the cells whose walls cover the screen point `p` are exactly the three that the ground segment
## from p's flat ground point (u, v) to (u + 1, v + 1) crosses: (floor u, floor v), then
## (floor u + 1, floor v) if frac u > frac v else (floor u, floor v + 1), then
## (floor u + 1, floor v + 1). `raised` is a byte per cell, `cols` wide, as `WallLayer` holds it.

const LOOK_A: int = 0
const LOOK_B: int = 1
const TEAM_SAT_MIN: float = 0.35
const BODY: Color = Color(0.09, 0.10, 0.12)
const ALPHA_A: float = 0.85
const ALPHA_B: float = 0.55  ## Look B's veil over everything the wall covers.
const HATCH_ALPHA: float = 0.25  ## And on every hatch line.
const HATCH_PERIOD: float = 4.0  ## Screen diagonals between hatch lines.

## The cells whose rock can hide a unit that stands in cell (c, r), as offsets from the unit's cell:
## the three of its own sprite's lowest rows and the four a tall sprite reaches (A7).
const NEAR: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(1, 2),
	Vector2i(1, -1),
	Vector2i(-1, 1),
]


## Whether the raised cell (`col`, `row`) covers the screen point `p` of a unit standing at ground
## y `ground_y` (world px): it is raised and its centre y is larger than the unit's, so it sorts
## after the unit and draws over it.
static func covers(raised: PackedByteArray, cols: int, col: int, row: int, ground_y: float) -> bool:
	return (
		WallKit.is_raised(raised, cols, col, row)
		and float(col + row + 1) * IsoProjection.HALF_H > ground_y
	)


## The shader's rule: whether any of the three cells of `p` covers it for a unit at `ground_y`.
static func covered(raised: PackedByteArray, cols: int, p: Vector2, ground_y: float) -> bool:
	var tiles: Vector2 = IsoProjection.px_to_tiles(p)
	var col: int = floori(tiles.x)
	var row: int = floori(tiles.y)
	var right: bool = tiles.x - col > tiles.y - row
	return (
		covers(raised, cols, col, row, ground_y)
		or covers(raised, cols, col + int(right), row + int(not right), ground_y)
		or covers(raised, cols, col + 1, row + 1, ground_y)
	)


## The front-most raised cell among the three of `p` (the larger centre y first), as a cell index,
## or -1 when none is raised. Off the map is never raised.
static func front_cell(raised: PackedByteArray, cols: int, p: Vector2) -> int:
	var tiles: Vector2 = IsoProjection.px_to_tiles(p)
	var col: int = floori(tiles.x)
	var row: int = floori(tiles.y)
	var right: bool = tiles.x - col > tiles.y - row
	if WallKit.is_raised(raised, cols, col + 1, row + 1):
		return (row + 1) * cols + col + 1
	if WallKit.is_raised(raised, cols, col + int(right), row + int(not right)):
		return (row + int(not right)) * cols + col + int(right)
	return row * cols + col if WallKit.is_raised(raised, cols, col, row) else -1


## The ground point, in milli-tiles, that a tap at the world px `p` means: the centre of the
## front-most raised cell of p's three (a tap on a wall's top or face lands on the wall, not on the
## ground the wall hides), else the flat ground under `p` as `IsoProjection.px_to_ground` gives it.
@warning_ignore("integer_division")
static func ground_at(raised: PackedByteArray, cols: int, p: Vector2) -> Vector2i:
	var cell: int = front_cell(raised, cols, p) if cols > 0 else -1
	if cell < 0:
		return IsoProjection.px_to_ground(p)
	var milli: int = ViewScale.MILLI_PER_TILE
	return Vector2i((cell % cols) * milli + milli / 2, (cell / cols) * milli + milli / 2)


## The near-wall bytes (A7): 1 for each cell with a raised cell at one of `NEAR`'s offsets, one byte
## per cell like `raised`, which has `cols` columns. Built with the walls, never per frame.
@warning_ignore("integer_division")
static func near_bytes(raised: PackedByteArray, cols: int) -> PackedByteArray:
	var near: PackedByteArray = PackedByteArray()
	near.resize(raised.size())
	if cols <= 0:
		return near
	var rows: int = raised.size() / cols
	for row: int in rows:
		for col: int in cols:
			for offset: Vector2i in NEAR:
				if WallKit.is_raised(raised, cols, col + offset.x, row + offset.y):
					near[row * cols + col] = 1
					break
	return near


## The silhouette's colouring, the twin of `silhouette.gdshader`'s end: a team-colour texel
## (saturation at least `TEAM_SAT_MIN`) keeps its hue, any other is `BODY`. Look A has one alpha;
## look B a lower one, and on every `HATCH_PERIOD`-th screen diagonal (`frag` is FRAGCOORD, the
## pixel's centre) a still lower one. `tex` is the atlas texel.
static func silhouette_colour(tex: Color, look: int, frag: Vector2) -> Color:
	var top: float = maxf(tex.r, maxf(tex.g, tex.b))
	var sat: float = (top - minf(tex.r, minf(tex.g, tex.b))) / top if top > 0.0 else 0.0
	var alpha: float = ALPHA_A
	if look == LOOK_B:
		alpha = HATCH_ALPHA if fposmod(frag.x + frag.y, HATCH_PERIOD) < 1.0 else ALPHA_B
	var rgb: Color = tex if sat >= TEAM_SAT_MIN else BODY
	return Color(rgb.r, rgb.g, rgb.b, tex.a * alpha)
