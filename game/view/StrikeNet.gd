class_name StrikeNet
extends RefCounted
## The net of light of the Blackout Array (ADR 0027 sections 3 and 6, STYLE.md "Life effects",
## "The net"), for `StrikeFx`: the lines of its lattice, the plan of the nets of a frame and their
## drawing. The lattice is flat-topped hexagons on `LifeRegions`' distances whose centre lies in the
## ground ellipse of the strike. It has two sets of lines per radius, built when the radius is first
## met (`lattice_for`, at the event, never in a frame; a second radius gets a lattice of its own):
## - `edges`: every cell's three owned edges (the top and the two on the left) and, for a side whose
##   neighbour centre falls outside the ellipse, that side's edge too, so the net has no loose end;
## - `ring`: the six edges of each cell on the boundary (a neighbour centre outside), the ring the
##   net settles as while the interior fades.
## A plan entry is a lattice, a centre, a scale and two alphas (the interior's and the ring's).
## `plan`, `draw` and the accessors allocate nothing.

var _axes: PackedVector2Array = PackedVector2Array()  ## The semi-axes each lattice is for.
var _edges: Array[PackedVector2Array] = []
var _rings: Array[PackedVector2Array] = []
var _which: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _scale: PackedFloat32Array = PackedFloat32Array()
var _alpha: PackedFloat32Array = PackedFloat32Array()
var _ring_alpha: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0


## Room for `size` nets in a plan; empties it.
func resize(size: int) -> void:
	_which.resize(size)
	_at.resize(size)
	_scale.resize(size)
	_alpha.resize(size)
	_ring_alpha.resize(size)
	_count = 0


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
	var cols: int = int(axes.x / LifeRegions.NET_COLUMN_PX) + 2
	var rows: int = int(axes.y / LifeRegions.NET_ROW_PX) + 2
	for col: int in range(-cols, cols + 1):
		for row: int in range(-rows, rows + 1):
			if _inside(axes, col, row):
				_add_cell(axes, col, row, edges, ring)
	_edges.append(edges)
	_rings.append(ring)
	return _axes.size() - 1


func lattice_count() -> int:
	return _axes.size()


## The segments (end, end, ...) of the interior lines and of the ring of lattice `index`.
func edges(index: int) -> PackedVector2Array:
	return _edges[index]


func ring(index: int) -> PackedVector2Array:
	return _rings[index]


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


## Draws the plan on `canvas` (inside its `_draw`): each net's interior lines, dark edge under
## light line, then its ring once it is brighter than the interior. The line widths stay what
## `LifeRegions` says in world px whatever the net's scale. Leaves the transform reset.
func draw(canvas: CanvasItem) -> void:
	for net: int in _count:
		var scale_by: float = _scale[net]
		canvas.draw_set_transform(_at[net], 0.0, Vector2(scale_by, scale_by))
		var edges: PackedVector2Array = _edges[_which[net]]
		if edges.size() >= 2:
			_lines(canvas, edges, _alpha[net], scale_by)
		var ring: PackedVector2Array = _rings[_which[net]]
		if ring.size() >= 2 and _ring_alpha[net] > _alpha[net]:
			_lines(canvas, ring, _ring_alpha[net], scale_by)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _lines(
	canvas: CanvasItem, lines: PackedVector2Array, alpha_of: float, scale_by: float
) -> void:
	var edge: Color = Color(LifeRegions.NET_EDGE, alpha_of)
	canvas.draw_multiline(lines, edge, LifeRegions.NET_EDGE_PX / scale_by)
	var light: Color = Color(LifeRegions.NET_LIGHT, alpha_of)
	canvas.draw_multiline(lines, light, LifeRegions.NET_LIGHT_PX / scale_by)


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


static func _add_cell(
	axes: Vector2, col: int, row: int, edges: PackedVector2Array, ring: PackedVector2Array
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
	var out: Array[bool] = []
	for side: int in 6:
		out.append(not _inside(axes, near[side * 2], near[side * 2 + 1]))
	# The owned edges: the top (the cell above owns its own bottom), the two on the left.
	edges.append_array(
		PackedVector2Array([upper_left, upper_right, left, upper_left, left, lower_left])
	)
	if out[1]:  # Nobody below owns this cell's bottom edge.
		edges.append_array(PackedVector2Array([lower_left, lower_right]))
	if out[2]:  # Nor the upper-right neighbour its lower-left edge.
		edges.append_array(PackedVector2Array([right, upper_right]))
	if out[3]:
		edges.append_array(PackedVector2Array([right, lower_right]))
	if out[0] or out[1] or out[2] or out[3] or out[4] or out[5]:
		(
			ring
			. append_array(
				PackedVector2Array(
					[
						upper_left,
						upper_right,
						upper_right,
						right,
						right,
						lower_right,
						lower_right,
						lower_left,
						lower_left,
						left,
						left,
						upper_left,
					]
				)
			)
		)
