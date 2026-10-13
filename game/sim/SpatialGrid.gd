class_name SpatialGrid
extends RefCounted
## A linked-list bucket grid over the map (ADR 0008 section 4): `head` per cell, `next` per row.
## The separation grid has 1-tile cells and the targeting grid 4-tile cells. A rebuild costs
## O(units), not O(cells), and allocates nothing after configure(). Derived state: it is never
## hashed. Everything a rebuild changes lives in Packed arrays and ints of this object (ADR 0013
## section 2), so a native kernel can later write it in place.

## Nothing here is in the state hash; UNHASHED names every int and Packed array member once (ADR
## 0007 section 8).
const HASHED: Array[StringName] = []
const UNHASHED: Array[StringName] = [
	&"cols",
	&"rows",
	&"head",
	&"next",
	&"cell_milli",
	&"_capacity",
	&"_occupied",
	&"_occupied_count",
	&"_inserted",
]

## Cells per row and rows of cells: the map rounded up, so the last cell of a row or a column may
## be partial. 0 for an empty map.
var cols: int = 0
var rows: int = 0
## Per cell, `row * cols + column`: the lowest row in the cell, or -1 when the cell is empty.
var head: PackedInt32Array = PackedInt32Array()
## Per row, `capacity` entries: the next higher row in the same cell, or -1 at the end of its
## list. Entries from the last rebuild's count on are -1.
var next: PackedInt32Array = PackedInt32Array()

## The side of a cell in milli-tiles, at least 1. Set by configure(). A consumer that turns a reach
## into the cells covering it (targeting) reads this, so the size is written in one place only.
var cell_milli: int = 1

var _capacity: int = 0
## `_occupied[0.._occupied_count]` are the cells with a row after the last rebuild, once each.
var _occupied: PackedInt32Array = PackedInt32Array()
var _occupied_count: int = 0
## Rows inserted by the last rebuild.
var _inserted: int = 0

## Sizes the grid for a map of `map_w` x `map_h` milli-tiles with square cells of `cell_milli`,
## and for at most `capacity` rows. An empty map (a size or `cell_milli` of 0 or less) gives 0
## cells, and a rebuild then inserts nothing. This is the only place that allocates. It costs
## O(cells), so call it when a size changes, not every tick. The parameters keep the contract's
## names, so `cell_milli` shadows the field of the same name.
@warning_ignore("integer_division", "shadowed_variable")
func configure(map_w: int, map_h: int, cell_milli: int, capacity: int) -> void:
	var side: int = maxi(cell_milli, 1)
	self.cell_milli = side
	_capacity = maxi(capacity, 0)
	cols = 0
	rows = 0
	if map_w > 0 and map_h > 0 and cell_milli > 0:
		cols = (map_w + side - 1) / side
		rows = (map_h + side - 1) / side
	head.resize(cols * rows)
	head.fill(-1)
	next.resize(_capacity)
	next.fill(-1)
	_occupied.resize(_capacity)
	_occupied_count = 0
	_inserted = 0


## Rebuilds the lists from rows 0..count - 1 at (xs[row], ys[row]). Only the cells that held a
## row last time are reset, and rows go in descending order so each cell lists its rows in
## ascending order. Rows from `capacity` on are left out. A point outside the map goes to the
## nearest edge cell: a negative coordinate divides toward zero and then clamps to column or row 0.
@warning_ignore("integer_division")
func rebuild(xs: PackedInt32Array, ys: PackedInt32Array, count: int) -> void:
	var heads: PackedInt32Array = head
	var links: PackedInt32Array = next
	var occupied: PackedInt32Array = _occupied
	for i: int in range(_occupied_count):
		heads[occupied[i]] = -1
	var used: int = 0
	var last_column: int = cols - 1
	var last_line: int = rows - 1
	var cell: int = cell_milli
	var width: int = cols
	var total: int = clampi(count, 0, _capacity) if width > 0 else 0
	for row: int in range(total - 1, -1, -1):
		var column: int = xs[row] / cell
		var line: int = ys[row] / cell
		if column < 0:
			column = 0
		elif column > last_column:
			column = last_column
		if line < 0:
			line = 0
		elif line > last_line:
			line = last_line
		var slot: int = line * width + column
		var first: int = heads[slot]
		if first == -1:
			occupied[used] = slot
			used += 1
		links[row] = first
		heads[slot] = row
	for row: int in range(total, _inserted):
		links[row] = -1
	_occupied_count = used
	_inserted = total


## The cell holding the point (x, y) in milli-tiles, for points inside the map
## `(y / cell_milli) * cols + x / cell_milli`. A point outside the map gives the nearest edge
## cell (a negative coordinate divides toward zero and then clamps to 0). With an empty map it
## is 0.
@warning_ignore("integer_division")
func cell_of(x: int, y: int) -> int:
	if cols == 0:
		return 0
	return clampi(y / cell_milli, 0, rows - 1) * cols + clampi(x / cell_milli, 0, cols - 1)
