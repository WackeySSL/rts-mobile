class_name FixedMath
extends RefCounted
## Integer math for the simulation (ADR 0003 section 2, ADR 0008 section 2): the integer square
## root, the truncating movement step and the supercover line test. No sine table and no dir_to in
## Phase 2: no rule needs a direction, because a unit has no facing.

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


## Whether every tile that the segment (x0, y0)-(x1, y1) touches is passable for `move_class`
## (ADR 0008 section 2). Points are milli-tiles and are clamped into the grid. A point is in the
## tile that World.cell_of gives it (ADR 0008 section 1), so a tile is a half-open square: its left
## and top edge belong to it, its right and bottom edge to the next tile, and the far edge of the
## map to the last tile. The segment touches the tiles of its points, and where it crosses a tile
## corner exactly (the corner is between its ends, and the segment is along no axis) it also touches
## the two tiles beside the corner, which keeps the flow field's rule against cutting a corner. A
## segment along an edge touches the tiles on one side only: a unit that stands on that edge is in
## that tile, so a goal on an open tile is in reach of a clear line from every point of its tile.
## It reads the grid like World.is_passable: true while no map is loaded, false for a class that
## does not exist. Callers use it at event cadence (a line check, ADR 0007 section 1).
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
