extends GdUnitTestSuite
## SpatialGrid (ADR 0008 section 4, plan P32): the grid sizes, the cell of a point on cell and map
## edges, ascending rows within a cell, the O(units) reset, and the capacity bound. The fixture is
## 10000 x 7000 milli-tiles with 4000-milli cells: 3 x 2 cells, the last column 2000 wide and the
## last row 3000 high. Cell index = row * 3 + column. Every number is a literal, so a wrong rule
## cannot agree with the test by repeating it.

const MAP_W: int = 10000
const MAP_H: int = 7000
const CELL: int = 4000
const CAPACITY: int = 8

var _grid: SpatialGrid
var _xs: PackedInt32Array = PackedInt32Array()
var _ys: PackedInt32Array = PackedInt32Array()


func before_test() -> void:
	_grid = SpatialGrid.new()
	_grid.configure(MAP_W, MAP_H, CELL, CAPACITY)


func test_configure_rounds_the_cells_up_and_sizes_the_arrays() -> void:
	assert_int(_grid.cols).is_equal(3)
	assert_int(_grid.rows).is_equal(2)
	assert_int(_grid.cell_milli).is_equal(4000)
	assert_array(_grid.head).is_equal([-1, -1, -1, -1, -1, -1])
	assert_array(_grid.next).is_equal([-1, -1, -1, -1, -1, -1, -1, -1])
	_expect_size(8000, 4000, 4000, 2, 1)
	_expect_size(8001, 4001, 4000, 3, 2)
	_expect_size(4000, 4000, 4000, 1, 1)
	_expect_size(1, 1, 4000, 1, 1)
	_expect_size(48000, 48000, 1000, 48, 48)
	_expect_size(0, 0, 1000, 0, 0)
	_expect_size(0, 7000, 1000, 0, 0)
	_expect_size(-1000, 7000, 1000, 0, 0)
	_expect_size(10000, 0, 1000, 0, 0)
	_expect_size(10000, -1, 1000, 0, 0)
	_expect_size(10000, 7000, 0, 0, 0)
	_expect_size(10000, 7000, -1, 0, 0)


func test_cell_milli_is_the_configured_side_and_never_below_one() -> void:
	_grid.configure(MAP_W, MAP_H, 1000, CAPACITY)
	assert_int(_grid.cell_milli).is_equal(1000)
	_grid.configure(MAP_W, MAP_H, 0, CAPACITY)
	assert_int(_grid.cell_milli).is_equal(1)
	_grid.configure(MAP_W, MAP_H, -5, CAPACITY)
	assert_int(_grid.cell_milli).is_equal(1)


func test_every_row_is_in_the_list_of_its_cell_ascending() -> void:
	_rebuild(
		[
			Vector2i(500, 500),
			Vector2i(4500, 500),
			Vector2i(600, 700),
			Vector2i(4600, 600),
			Vector2i(700, 800),
			Vector2i(9000, 5000),
			Vector2i(4700, 700),
			Vector2i(800, 900),
		]
	)
	assert_array(_list(0)).is_equal([0, 2, 4, 7])
	assert_array(_list(1)).is_equal([1, 3, 6])
	assert_array(_list(2)).is_empty()
	assert_array(_list(3)).is_empty()
	assert_array(_list(4)).is_empty()
	assert_array(_list(5)).is_equal([5])
	assert_array(_grid.head).is_equal([0, 1, -1, -1, -1, 5])
	assert_array(_grid.next).is_equal([2, 3, 4, 6, 7, -1, -1, -1])


func test_cell_of_on_cell_edges_and_map_edges() -> void:
	assert_int(_grid.cell_of(0, 0)).is_equal(0)
	assert_int(_grid.cell_of(3999, 0)).is_equal(0)
	assert_int(_grid.cell_of(4000, 0)).is_equal(1)
	assert_int(_grid.cell_of(7999, 0)).is_equal(1)
	assert_int(_grid.cell_of(8000, 0)).is_equal(2)
	assert_int(_grid.cell_of(9999, 0)).is_equal(2)
	assert_int(_grid.cell_of(0, 3999)).is_equal(0)
	assert_int(_grid.cell_of(0, 4000)).is_equal(3)
	assert_int(_grid.cell_of(7999, 6999)).is_equal(4)
	assert_int(_grid.cell_of(8000, 4000)).is_equal(5)
	assert_int(_grid.cell_of(MAP_W - 1, MAP_H - 1)).is_equal(5)


func test_cell_of_puts_a_point_outside_the_map_in_the_nearest_edge_cell() -> void:
	assert_int(_grid.cell_of(MAP_W, MAP_H)).is_equal(5)
	assert_int(_grid.cell_of(-1, -1)).is_equal(0)
	assert_int(_grid.cell_of(-4500, -4500)).is_equal(0)
	assert_int(_grid.cell_of(20000, -5)).is_equal(2)
	assert_int(_grid.cell_of(-5, 20000)).is_equal(3)


func test_rebuild_puts_rows_on_cell_and_map_edges_in_the_right_cells() -> void:
	_rebuild(
		[
			Vector2i(0, 0),
			Vector2i(4000, 0),
			Vector2i(3999, 3999),
			Vector2i(9999, 6999),
			Vector2i(0, 4000),
			Vector2i(8000, 3999),
			Vector2i(7999, 4000),
			Vector2i(4000, 3999),
		]
	)
	assert_array(_list(0)).is_equal([0, 2])
	assert_array(_list(1)).is_equal([1, 7])
	assert_array(_list(2)).is_equal([5])
	assert_array(_list(3)).is_equal([4])
	assert_array(_list(4)).is_equal([6])
	assert_array(_list(5)).is_equal([3])


func test_rebuild_puts_rows_outside_the_map_in_the_nearest_edge_cell() -> void:
	_rebuild(
		[
			Vector2i(-1, -1),
			Vector2i(10000, 7000),
			Vector2i(12000, 100),
			Vector2i(100, 9000),
			Vector2i(-5000, -5000),
			Vector2i(-9000, 5000),
			Vector2i(5000, -9000),
		]
	)
	assert_array(_list(0)).is_equal([0, 4])
	assert_array(_list(1)).is_equal([6])
	assert_array(_list(2)).is_equal([2])
	assert_array(_list(3)).is_equal([3, 5])
	assert_array(_list(4)).is_empty()
	assert_array(_list(5)).is_equal([1])


func test_a_rebuild_after_units_moved_leaves_no_row_in_its_old_cell() -> void:
	_rebuild([Vector2i(500, 500), Vector2i(4500, 500), Vector2i(8500, 500), Vector2i(500, 4500)])
	assert_array(_grid.head).is_equal([0, 1, 2, 3, -1, -1])
	_rebuild([Vector2i(9000, 6000), Vector2i(9100, 6100), Vector2i(5000, 5000), Vector2i(100, 100)])
	assert_array(_grid.head).is_equal([3, -1, -1, -1, 2, 0])
	assert_array(_grid.next).is_equal([1, -1, -1, -1, -1, -1, -1, -1])
	var fresh: SpatialGrid = SpatialGrid.new()
	fresh.configure(MAP_W, MAP_H, CELL, CAPACITY)
	fresh.rebuild(_xs, _ys, 4)
	assert_array(_grid.head).is_equal(fresh.head)
	assert_array(_grid.next).is_equal(fresh.next)


func test_a_rebuild_resets_only_the_cells_occupied_last_time() -> void:
	var points: Array[Vector2i] = [Vector2i(500, 500), Vector2i(4500, 4500)]
	_rebuild(points)
	_grid.head[2] = 77
	_rebuild(points)
	assert_array(_grid.head).is_equal([0, -1, 77, -1, 1, -1])


## The occupied list restarts on every rebuild: a cell occupied two rebuilds ago is not reset.
func test_a_cell_occupied_two_rebuilds_ago_is_not_reset_again() -> void:
	var first: Array[Vector2i] = [Vector2i(500, 500)]
	var second: Array[Vector2i] = [Vector2i(4500, 4500)]
	_rebuild(first)
	_rebuild(second)
	_grid.head[0] = 77
	_rebuild(second)
	assert_array(_grid.head).is_equal([77, -1, -1, -1, 0, -1])


func test_many_rebuilds_never_grow_the_occupied_list_past_the_capacity() -> void:
	var spread: Array[Vector2i] = [
		Vector2i(500, 500),
		Vector2i(4500, 500),
		Vector2i(8500, 500),
		Vector2i(500, 4500),
		Vector2i(4500, 4500),
		Vector2i(8500, 4500),
	]
	for _round: int in 20:
		_rebuild(spread)
	assert_array(_grid.head).is_equal([0, 1, 2, 3, 4, 5])
	assert_array(_grid.next).is_equal([-1, -1, -1, -1, -1, -1, -1, -1])


func test_a_rebuild_with_fewer_units_keeps_the_array_sizes() -> void:
	var all: Array[Vector2i] = []
	for row: int in 8:
		all.append(Vector2i(500 + row, 500))
	_rebuild(all)
	assert_array(_grid.next).is_equal([1, 2, 3, 4, 5, 6, 7, -1])
	_grid.rebuild(_xs, _ys, 3)
	assert_int(_grid.head.size()).is_equal(6)
	assert_int(_grid.next.size()).is_equal(8)
	assert_array(_grid.head).is_equal([0, -1, -1, -1, -1, -1])
	assert_array(_grid.next).is_equal([1, 2, -1, -1, -1, -1, -1, -1])
	_grid.rebuild(_xs, _ys, 0)
	assert_int(_grid.head.size()).is_equal(6)
	assert_int(_grid.next.size()).is_equal(8)
	assert_array(_grid.head).is_equal([-1, -1, -1, -1, -1, -1])
	assert_array(_grid.next).is_equal([-1, -1, -1, -1, -1, -1, -1, -1])


func test_capacity_bounds_the_rows_and_a_negative_count_inserts_none() -> void:
	var xs: PackedInt32Array = PackedInt32Array()
	xs.resize(10)
	xs.fill(500)
	_grid.rebuild(xs, xs, 10)
	assert_int(_grid.next.size()).is_equal(8)
	assert_array(_list(0)).is_equal([0, 1, 2, 3, 4, 5, 6, 7])
	_grid.rebuild(xs, xs, -3)
	assert_array(_grid.head).is_equal([-1, -1, -1, -1, -1, -1])


func test_a_negative_capacity_holds_no_rows() -> void:
	_grid.configure(MAP_W, MAP_H, CELL, -1)
	assert_int(_grid.next.size()).is_equal(0)
	_rebuild([Vector2i(500, 500), Vector2i(4500, 500)])
	assert_array(_grid.head).is_equal([-1, -1, -1, -1, -1, -1])


func test_configure_again_resets_the_lists_and_resizes() -> void:
	var all: Array[Vector2i] = []
	all.resize(CAPACITY)
	all.fill(Vector2i(9000, 6000))
	_rebuild(all)
	_grid.configure(8000, 4000, CELL, 2)
	assert_array(_grid.head).is_equal([-1, -1])
	assert_array(_grid.next).is_equal([-1, -1])
	_rebuild([Vector2i(7000, 100), Vector2i(100, 100)])
	assert_array(_grid.head).is_equal([1, 0])


func test_an_empty_map_inserts_nothing_and_errors_nowhere() -> void:
	_grid.configure(0, 0, 1000, 4)
	_rebuild([Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 7)])
	assert_int(_grid.head.size()).is_equal(0)
	assert_array(_grid.next).is_equal([-1, -1, -1, -1])
	assert_int(_grid.cell_of(5, 5)).is_equal(0)


@warning_ignore("integer_division")
func test_random_points_match_a_brute_force_over_the_rows() -> void:
	var rng: DetRandom = DetRandom.create(7, DetRandom.STREAM_SIM)
	_grid.configure(MAP_W, MAP_H, 1000, 256)
	for count: int in [200, 50, 256, 0, 130]:
		var points: Array[Vector2i] = []
		for _row: int in count:
			points.append(Vector2i(rng.next_int(MAP_W), rng.next_int(MAP_H)))
		_rebuild(points)
		var seen: int = 0
		for cell: int in 70:
			var expected: Array[int] = []
			for row: int in count:
				if (points[row].y / 1000) * 10 + points[row].x / 1000 == cell:
					expected.append(row)
			assert_array(_list(cell)).is_equal(expected)
			seen += expected.size()
		assert_int(seen).is_equal(count)


func _rebuild(points: Array[Vector2i]) -> void:
	_xs.resize(points.size())
	_ys.resize(points.size())
	for row: int in points.size():
		_xs[row] = points[row].x
		_ys[row] = points[row].y
	_grid.rebuild(_xs, _ys, points.size())


## The rows listed by `cell`, in list order. The walk stops after `next.size()` steps, so a cycle
## fails the comparison instead of hanging.
func _list(cell: int) -> Array[int]:
	var out: Array[int] = []
	var row: int = _grid.head[cell]
	while row != -1 and out.size() <= _grid.next.size():
		out.append(row)
		row = _grid.next[row]
	return out


func _expect_size(map_w: int, map_h: int, cell: int, cols: int, rows: int) -> void:
	var grid: SpatialGrid = SpatialGrid.new()
	grid.configure(map_w, map_h, cell, 3)
	assert_int(grid.cols).is_equal(cols)
	assert_int(grid.rows).is_equal(rows)
	assert_int(grid.head.size()).is_equal(cols * rows)
	assert_int(grid.next.size()).is_equal(3)
