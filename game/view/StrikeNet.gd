class_name StrikeNet
extends RefCounted
## The net of light of the Dusk Array (ADR 0027 sections 3 and 6, STYLE.md "Life effects",
## "The net"), for `StrikeFx`: the lines of its lattice, the plan of the nets of a frame and their
## drawing. The lattice is flat-topped hexagons on `LifeRegions`' distances whose centre lies in the
## ground ellipse of the strike. It has three sets of lines per radius, built when the radius is
## first met (`lattice_for`, at the
## event, never in a frame; a second radius gets a lattice of its own). Every edge of the lattice
## is in them once:
## - `edges`: all of it: every cell's three owned edges (the top and the two on the left) and, for a
##   side whose neighbour centre falls outside the ellipse, that side's edge too, so the net has no
##   loose end;
## - `ring`: the edges of the cells on the boundary (a neighbour centre outside), the closed
##   hexagons the net settles as;
## - `interior`: the rest, `edges` less `ring`.
## While the net falls it is drawn as `edges` in one pass; while it settles, `interior` fades faster
## than `ring`, two passes. `draw` records what it drew (`drawn_*`) for the tests.
## A plan entry is a lattice, a centre, a scale and two alphas (the interior's and the ring's).
## `plan`, `draw` and the accessors allocate nothing.

var _axes: PackedVector2Array = PackedVector2Array()  ## The semi-axes each lattice is for.
var _edges: Array[PackedVector2Array] = []
var _rings: Array[PackedVector2Array] = []
var _interiors: Array[PackedVector2Array] = []
var _which: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _scale: PackedFloat32Array = PackedFloat32Array()
var _alpha: PackedFloat32Array = PackedFloat32Array()
var _ring_alpha: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0
## What the last `draw` painted, per net and pass (net x 2 + 0 for the interior or the whole net,
## + 1 for the ring): segments, alpha and the two line widths as given to `draw_multiline`.
var _drawn_nets: int = 0
var _drawn_segments: PackedInt32Array = PackedInt32Array()
var _drawn_alpha: PackedFloat32Array = PackedFloat32Array()
var _drawn_edge_width: PackedFloat32Array = PackedFloat32Array()
var _drawn_light_width: PackedFloat32Array = PackedFloat32Array()


## Room for `size` nets in a plan; empties it.
func resize(size: int) -> void:
	_which.resize(size)
	_at.resize(size)
	_scale.resize(size)
	_alpha.resize(size)
	_ring_alpha.resize(size)
	_drawn_segments.resize(size * 2)
	_drawn_alpha.resize(size * 2)
	_drawn_edge_width.resize(size * 2)
	_drawn_light_width.resize(size * 2)
	_count = 0
	_drawn_nets = 0


func clear() -> void:
	_count = 0


## The index of the lattice of semi-axes `axes`, built on the first call for them.
func lattice_for(axes: Vector2) -> int:
	var found: int = _axes.find(axes)
	if found >= 0:
		return found
	_axes.append(axes)
	var edges: PackedVector2Array = PackedVector2Array()
	var ring: PackedVector2Array = PackedVector2Array()
	var interior: PackedVector2Array = PackedVector2Array()
	var cols: int = int(axes.x / LifeRegions.NET_COLUMN_PX) + 2
	var rows: int = int(axes.y / LifeRegions.NET_ROW_PX) + 2
	for col: int in range(-cols, cols + 1):
		for row: int in range(-rows, rows + 1):
			if _inside(axes, col, row):
				_add_cell(axes, col, row, edges, interior, ring)
	_edges.append(edges)
	_rings.append(ring)
	_interiors.append(interior)
	return _axes.size() - 1


func lattice_count() -> int:
	return _axes.size()


## The segments (end, end, ...) of the interior lines and of the ring of lattice `index`.
func edges(index: int) -> PackedVector2Array:
	return _edges[index]


func ring(index: int) -> PackedVector2Array:
	return _rings[index]


func interior(index: int) -> PackedVector2Array:
	return _interiors[index]


## Adds a net of lattice `index` centred on `at`. `alpha` is the interior's, `ring_alpha` the
## ring's (equal while it falls).
func plan(index: int, at: Vector2, scale_by: float, alpha: float, ring_alpha: float) -> void:
	_which[_count] = index
	_at[_count] = at
	_scale[_count] = scale_by
	_alpha[_count] = alpha
	_ring_alpha[_count] = ring_alpha
	_count += 1


func count() -> int:
	return _count


## The lattice net `net` of the plan is drawn from.
func lattice_of(net: int) -> int:
	return _which[net]


func at(net: int) -> Vector2:
	return _at[net]


func scale_of(net: int) -> float:
	return _scale[net]


func alpha(net: int) -> float:
	return _alpha[net]


func ring_alpha(net: int) -> float:
	return _ring_alpha[net]


## Draws the plan on `canvas` (inside its `_draw`). A net that falls is one pass of all its lines;
## one that settles is its interior, then its ring, which is brighter. Each pass is a dark edge
## under a light line, of the widths `LifeRegions` gives in world px whatever the net's scale.
## Leaves the transform reset.
func draw(canvas: CanvasItem) -> void:
	_drawn_nets = _count
	for net: int in _count:
		var scale_by: float = _scale[net]
		canvas.draw_set_transform(_at[net], 0.0, Vector2(scale_by, scale_by))
		var split: bool = _ring_alpha[net] > _alpha[net]
		var first: PackedVector2Array = _interiors[_which[net]] if split else _edges[_which[net]]
		_pass(canvas, net * 2, first, true, _alpha[net], scale_by)
		var ring: PackedVector2Array = _rings[_which[net]]
		_pass(canvas, net * 2 + 1, ring, split, _ring_alpha[net], scale_by)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Nets of the last `draw`, and for net `net` and pass `pass_of` (0 the interior or the whole net, 1
## the ring): the segments it drew (0 for a pass that did not run), its alpha and line widths.
func drawn_nets() -> int:
	return _drawn_nets


func drawn_segments(net: int, pass_of: int) -> int:
	return _drawn_segments[net * 2 + pass_of]


func drawn_alpha(net: int, pass_of: int) -> float:
	return _drawn_alpha[net * 2 + pass_of]


func drawn_edge_width(net: int, pass_of: int) -> float:
	return _drawn_edge_width[net * 2 + pass_of]


func drawn_light_width(net: int, pass_of: int) -> float:
	return _drawn_light_width[net * 2 + pass_of]


@warning_ignore("integer_division")
func _pass(
	canvas: CanvasItem,
	slot: int,
	lines: PackedVector2Array,
	on: bool,
	alpha_of: float,
	scale_by: float
) -> void:
	var drawn: int = lines.size() / 2 if on and lines.size() >= 2 else 0
	_drawn_segments[slot] = drawn
	if drawn == 0:
		return
	var edge_width: float = LifeRegions.NET_EDGE_PX / scale_by
	var light_width: float = LifeRegions.NET_LIGHT_PX / scale_by
	_drawn_alpha[slot] = alpha_of
	_drawn_edge_width[slot] = edge_width
	_drawn_light_width[slot] = light_width
	canvas.draw_multiline(lines, Color(LifeRegions.NET_EDGE, alpha_of), edge_width)
	canvas.draw_multiline(lines, Color(LifeRegions.NET_LIGHT, alpha_of), light_width)


## The centre of cell (col, row): a column every `NET_COLUMN_PX`, every other one moved down.
static func centre_of(col: int, row: int) -> Vector2:
	var shift: float = LifeRegions.NET_SHIFT_PX if (col & 1) == 1 else 0.0
	return Vector2(
		float(col) * LifeRegions.NET_COLUMN_PX, float(row) * LifeRegions.NET_ROW_PX + shift
	)


static func _inside(axes: Vector2, col: int, row: int) -> bool:
	var at_cell: Vector2 = centre_of(col, row)
	return (
		(at_cell.x * at_cell.x) / (axes.x * axes.x) + (at_cell.y * at_cell.y) / (axes.y * axes.y)
		<= 1.0
	)


## The neighbours of cell (col, row), as cell indices: up, down, then upper-right, lower-right,
## upper-left and lower-left (the columns beside it are half a row off, the odd ones down).
static func _neighbours(col: int, row: int) -> PackedInt32Array:
	var odd: int = col & 1
	return PackedInt32Array(
		[
			col,
			row - 1,
			col,
			row + 1,
			col + 1,
			row - 1 + odd,
			col + 1,
			row + odd,
			col - 1,
			row - 1 + odd,
			col - 1,
			row + odd,
		]
	)


## Whether cell (col, row), inside the ellipse, is on its boundary: a neighbour centre is outside.
static func _is_boundary(axes: Vector2, col: int, row: int) -> bool:
	var near: PackedInt32Array = _neighbours(col, row)
	for side: int in 6:
		if not _inside(axes, near[side * 2], near[side * 2 + 1]):
			return true
	return false


## Adds the edges of cell (col, row) to `all_lines`, and to `ring_lines` or `interior`: its owned
## edges and the
## closing ones (see the header), each to the ring when this cell or the neighbour across it is on
## the boundary, else to the interior.
static func _add_cell(
	axes: Vector2,
	col: int,
	row: int,
	all_lines: PackedVector2Array,
	interior: PackedVector2Array,
	ring_lines: PackedVector2Array
) -> void:
	var c: Vector2 = centre_of(col, row)
	var half: float = LifeRegions.NET_SIDE_PX * 0.5
	var high: float = LifeRegions.NET_SHIFT_PX  # Half the hexagon's height.
	var upper_left: Vector2 = c + Vector2(-half, -high)
	var upper_right: Vector2 = c + Vector2(half, -high)
	var left: Vector2 = c + Vector2(-LifeRegions.NET_SIDE_PX, 0.0)
	var right: Vector2 = c + Vector2(LifeRegions.NET_SIDE_PX, 0.0)
	var lower_left: Vector2 = c + Vector2(-half, high)
	var lower_right: Vector2 = c + Vector2(half, high)
	var near: PackedInt32Array = _neighbours(col, row)
	var own: bool = _is_boundary(axes, col, row)
	# Sides 0 (top), 4 (upper-left) and 5 (lower-left) are always this cell's; 1 (bottom), 2
	# (upper-right) and 3 (lower-right) only where nobody beside the cell owns them.
	var sides: Array[Array] = [
		[0, upper_left, upper_right],
		[4, left, upper_left],
		[5, left, lower_left],
		[1, lower_left, lower_right],
		[2, right, upper_right],
		[3, right, lower_right],
	]
	for entry: Array in sides:
		var side: int = entry[0]
		var neighbour_in: bool = _inside(axes, near[side * 2], near[side * 2 + 1])
		if side >= 1 and side <= 3 and neighbour_in:
			continue
		var ring: bool = (
			own or (neighbour_in and _is_boundary(axes, near[side * 2], near[side * 2 + 1]))
		)
		var ends: PackedVector2Array = PackedVector2Array([entry[1], entry[2]])
		all_lines.append_array(ends)
		if ring:
			ring_lines.append_array(ends)
		else:
			interior.append_array(ends)
