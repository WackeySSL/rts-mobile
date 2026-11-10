class_name FixedMath
extends RefCounted
## Integer math for the simulation (ADR 0003 section 2, ADR 0008 section 2): the integer square
## root, the truncating movement step and the supercover line test. No sine table and no dir_to in
## Phase 2: no rule needs a direction, because a unit has no facing. isqrt() has a C++ twin,
## core/fixed_math.cpp, which the INTEGRATE kernel's stall calls (ADR 0013 section 5).

## The floor of the square root of n, or 0 when n <= 0. Newton's method from above: a power of
## two at or over the root, found from the bit length of n, then x = (x + n / x) / 2 until it no
## longer falls, which ends on the floor. Exact over the whole 64-bit range, no float, and no sum
## that can overflow (x is at most 2^32 and n / x at most 2^31).
@warning_ignore("integer_division")
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	# The shifts below add up to 2 * half and leave 1 to 3 in `rest`, so n < 2 ^ (2 * half + 2).
	var rest: int = n
	var half: int = 0
	if rest >= (1 << 32):
		rest >>= 32
		half += 16
	if rest >= (1 << 16):
		rest >>= 16
		half += 8
	if rest >= (1 << 8):
		rest >>= 8
		half += 4
	if rest >= (1 << 4):
		rest >>= 4
		half += 2
	if rest >= (1 << 2):
		rest >>= 2
		half += 1
	var root: int = 1 << (half + 1)
	var next: int = (root + n / root) >> 1
	while next < root:
		root = next
		next = (root + n / root) >> 1
	return root


## One movement step from (x, y) towards (tx, ty) at `speed` milli-tiles per tick (ADR 0003
## section 5). A target within one step (d2 <= speed * speed) is reached exactly. Otherwise each
## axis moves `d_axis * speed / distance`, truncated toward zero, with the floor of the distance.
@warning_ignore("integer_division")
static func step_toward(x: int, y: int, tx: int, ty: int, speed: int) -> Vector2i:
	var dx: int = tx - x
	var dy: int = ty - y
	var d2: int = dx * dx + dy * dy
	if d2 <= speed * speed:
		return Vector2i(tx, ty)
	var distance: int = isqrt(d2)
	return Vector2i(x + dx * speed / distance, y + dy * speed / distance)


## A coordinate on a tile border belongs to the tile on the map centre's side: one milli-tile is
## taken off a border coordinate past the middle of a map `side` milli-tiles wide. The tile is then
## the usual floor, and a half turn of the map maps the tile of a point to the tile of its image
## (the floor alone keeps the border in the tile after it, which a half turn turns into the one
## before). C++ twin: fixed_math::centre_side.
static func centre_side(coord: int, side: int) -> int:
	if coord % World.MILLI_PER_TILE == 0 and coord * 2 > side:
		return coord - 1
	return coord


## Whether every tile that the segment (x0, y0)-(x1, y1) touches is passable for `move_class`
## (ADR 0008 section 2). Points are milli-tiles and are clamped into the grid. A point is in the
## tile that World.cell_of gives it (ADR 0008 section 1): up to the middle of the map a tile is a
## half-open square whose left and top edge belong to it, and past the middle a point on a border
## is in the tile before it (see `centre_side`). The far edge of the map belongs to the last tile.
## The segment touches the tiles of its points, and where it crosses a tile
## corner exactly (the corner is between its ends, and the segment is along no axis) it also touches
## the two tiles beside the corner, which keeps the flow field's rule against cutting a corner. A
## segment along an edge touches the tiles on one side only: a unit that stands on that edge is in
## that tile, so a goal on an open tile is in reach of a clear line from every point of its tile.
## It reads the grid like World.is_passable: true while no map is loaded, false for a class that
## does not exist. Callers use it at event cadence (a line check, ADR 0007 section 1).
##
## The limit of the border rule: `centre_side` moves an end point by one milli, and so tilts the
## whole segment, which is then the one between the moved ends. The tile of each end is exact, but
## a corner in between is not always: on a 10 x 10 map the segment (2000, 1000)-(8000, 4000) passes
## the corner (4000, 2000) exactly, and with its end moved to (7999, 4000) it passes just after it,
## so the tile (4, 1) beside the corner is no longer touched. A canonical frame (the segment turned
## so that both of its orientations are the same segment) would be exact, and is not done.
##
## Column by column: in the strip of tile column c the segment spans the y range between its
## values at the strip's left and right edge. With dx = x1 - x0 > 0 that y is
## (y0 * dx + dy * (x - x0)) / dx, so the numerators over dx * 1000 give tiles, and the rows
## touched run from floor(low) to floor(high). The right edge of a strip is in the next column, so
## when y rises there the strip ends one numerator short of it; a corner there adds the rows on
## both sides of it, in both strips. A vertical segment is one column of its y range.
@warning_ignore("integer_division")
static func line_clear(world: World, x0: int, y0: int, x1: int, y1: int, move_class: int) -> bool:
	var cols: int = world.map_cols
	if cols == 0:
		return true
	if move_class < 0 or move_class >= World.MoveClass.size():
		return false
	var rows: int = world.map_rows
	x0 = centre_side(x0, cols * World.MILLI_PER_TILE)
	x1 = centre_side(x1, cols * World.MILLI_PER_TILE)
	y0 = centre_side(y0, rows * World.MILLI_PER_TILE)
	y1 = centre_side(y1, rows * World.MILLI_PER_TILE)
	var cost: PackedByteArray = world.move_cost
	var base: int = move_class * cols * rows
	var tile: int = World.MILLI_PER_TILE
	var max_x: int = cols * tile
	var max_y: int = rows * tile
	# Left to right, inside the grid, so every numerator and quotient below is not negative.
	var flip: bool = x0 > x1
	var ax: int = clampi(x1 if flip else x0, 0, max_x)
	var ay: int = clampi(y1 if flip else y0, 0, max_y)
	var bx: int = clampi(x0 if flip else x1, 0, max_x)
	var by: int = clampi(y0 if flip else y1, 0, max_y)
	var dx: int = bx - ax
	var dy: int = by - ay
	var scale: int = dx * tile if dx > 0 else tile
	var last_column: int = mini(bx / tile, cols - 1)
	for column: int in range(mini(ax / tile, cols - 1), last_column + 1):
		var first_row: int = mini(ay, by) / tile
		var last_row: int = maxi(ay, by) / tile
		if dx > 0:
			var left_x: int = maxi(column * tile, ax)
			var right_x: int = mini((column + 1) * tile, bx)
			var left: int = ay * dx + dy * (left_x - ax)
			var right: int = ay * dx + dy * (right_x - ax)
			var open_end: int = 1 if dy > 0 and column < last_column else 0
			first_row = mini(left, right) / scale
			last_row = (maxi(left, right) - open_end) / scale
			if dy != 0 and left_x > ax and left_x < bx and left % scale == 0:
				first_row = mini(first_row, left / scale - 1)
				last_row = maxi(last_row, left / scale)
			if dy != 0 and right_x < bx and right % scale == 0:
				first_row = mini(first_row, right / scale - 1)
				last_row = maxi(last_row, right / scale)
		for row: int in range(mini(first_row, rows - 1), mini(last_row, rows - 1) + 1):
			if cost[base + row * cols + column] == 0:
				return false
	return true
