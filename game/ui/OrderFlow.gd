class_name OrderFlow
extends Container
## The command bar's order buttons (P581): the shown children side by side from the start edge,
## wrapping into a further row when the next one would pass `wrap_width`, so the orders never run
## under BUILD or scroll out of the bar. Every child keeps its own least size; a row is as high as
## its highest child. The least size is the wrapped block, computed from `wrap_width` and not from
## the width the container has, so the bar can ask for it before it is sized. A right-to-left
## layout (the left-handed mode) mirrors the rows.

var wrap_width: float = INF:  ## px; the widest a row may be (a single button is never cut).
	set(value):
		if not is_equal_approx(wrap_width, value):
			wrap_width = value
			update_minimum_size()
			queue_sort()
var gap: float = 0.0:  ## px between buttons and between rows.
	set(value):
		if not is_equal_approx(gap, value):
			gap = value
			update_minimum_size()
			queue_sort()


func _init() -> void:
	child_entered_tree.connect(_on_child)


## The width the shown children ask for in one row.
func natural_width() -> float:
	var total: float = 0.0
	for child: Control in _shown():
		total += child.get_combined_minimum_size().x + (gap if total > 0.0 else 0.0)
	return total


## The least width at which the shown children take at most `max_rows` rows (never under the widest
## child). Where none does it is the width of one row.
func width_for_rows(max_rows: int) -> float:
	var shown: Array[Control] = _shown()
	var widest: float = 0.0
	var widths: Array[float] = []
	for first: int in shown.size():
		var total: float = 0.0
		for last: int in range(first, shown.size()):
			total += shown[last].get_combined_minimum_size().x + (gap if last > first else 0.0)
			widths.append(total)
		widest = maxf(widest, shown[first].get_combined_minimum_size().x)
	widths.sort()
	for width: float in widths:
		if width >= widest and _layout(width).size() <= max_rows:
			return width
	return natural_width()


## How many rows the shown children take at `wrap_width`.
func rows() -> int:
	return _layout(wrap_width).size()


## A child that shows or hides changes the block (the container itself only re-sorts).
func _on_child(child: Node) -> void:
	if (
		child is Control
		and not (child as Control).visibility_changed.is_connected(update_minimum_size)
	):
		(child as Control).visibility_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	var out: Vector2 = Vector2.ZERO
	var plan: Array[Array] = _layout(wrap_width)
	for row: Array in plan:
		out.x = maxf(out.x, _row_width(row))
		out.y += _row_height(row) + (gap if out.y > 0.0 else 0.0)
	return out


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var y: float = 0.0
	for row: Array in _layout(wrap_width):
		var high: float = _row_height(row)
		var x: float = 0.0
		for child: Control in row:
			var wide: float = child.get_combined_minimum_size().x
			var at: float = size.x - x - wide if is_layout_rtl() else x
			fit_child_in_rect(child, Rect2(at, y, wide, high))
			x += wide + gap
		y += high + gap


func _shown() -> Array[Control]:
	var out: Array[Control] = []
	for child: Node in get_children():
		if child is Control and (child as Control).visible:
			out.append(child as Control)
	return out


func _layout(width: float) -> Array[Array]:
	var plan: Array[Array] = []
	var row: Array = []
	var used: float = 0.0
	for child: Control in _shown():
		var wide: float = child.get_combined_minimum_size().x
		if not row.is_empty() and used + gap + wide > width + 0.01:
			plan.append(row)
			row = []
			used = 0.0
		used += wide + (gap if not row.is_empty() else 0.0)
		row.append(child)
	if not row.is_empty():
		plan.append(row)
	return plan


func _row_width(row: Array) -> float:
	var total: float = 0.0
	for child: Control in row:
		total += child.get_combined_minimum_size().x + (gap if total > 0.0 else 0.0)
	return total


func _row_height(row: Array) -> float:
	var high: float = 0.0
	for child: Control in row:
		high = maxf(high, child.get_combined_minimum_size().y)
	return high
