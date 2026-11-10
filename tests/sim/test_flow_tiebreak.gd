extends GdUnitTestSuite
## FlowField.best_neighbour breaks an equal-cost tie by the goal, not by the scan order (seat
## symmetry, ADR 0033): the larger dot product of the step with (goal - cell), then the larger cross
## product. Both are unchanged by a turn of the map, so a field turned by a half turn (or a quarter
## turn on a square map) names the turned step from the turned cell. Random terrain with many
## equal-cost neighbours, fixed seeds, 64 x 64 and a wide map; the C++ kernel runs the same rule
## (tests/sim/native/test_flow_tiebreak_lockstep.gd).

const BIG: int = 100000
## Terrain costs of the rolls below: open, open, open, slow, rock.
const ROLL_COST: Array[int] = [10, 10, 10, 20, 0]
const SEEDS: Array[int] = [11, 29, 47]


## A field for `costs` (one class, one cost per cell, 0 = rock), integrated to the end.
func _field(costs: PackedByteArray, cols: int, rows: int, goal: int) -> FlowField:
	var field: FlowField = FlowField.new()
	field.begin(goal, 0, costs, cols, rows)
	field.advance(BIG)
	assert_bool(field.complete).is_true()
	return field


## Random terrain on cols x rows from `seed`; the goal cell is left open.
func _terrain(seed: int, cols: int, rows: int, goal: int, rocky: bool) -> PackedByteArray:
	var rng: DetRandom = DetRandom.create(seed, 1)
	var costs: PackedByteArray = PackedByteArray()
	costs.resize(cols * rows)
	for cell: int in cols * rows:
		costs[cell] = ROLL_COST[rng.next_int(5) if rocky else 0]
	costs[goal] = 10
	return costs


## The cell after a quarter turn clockwise on a map of `side` x `side`: (x, y) goes to
## (side - 1 - y, x), the step (dx, dy) to (-dy, dx).
func _quarter(cell: int, side: int) -> int:
	return (cell % side) * side + (side - 1 - cell / side)


## Compares every cell of `field` with the same cell of `turned`, mapped by `to_turned`.
func _agree(field: FlowField, turned: FlowField, to_turned: Callable, cells: int) -> int:
	var named: int = 0
	for cell: int in cells:
		var step: int = field.best_neighbour(cell)
		var expected: int = -1 if step == -1 else int(to_turned.call(step))
		(
			assert_int(turned.best_neighbour(int(to_turned.call(cell))))
			. override_failure_message("cell %d" % cell)
			. is_equal(expected)
		)
		named += int(step != -1)
	return named


func test_a_half_turned_field_names_the_half_turned_step_on_64_by_64() -> void:
	var cells: int = 64 * 64
	var turn: Callable = func(cell: int) -> int: return cells - 1 - cell
	for seed: int in SEEDS:
		for rocky: bool in [false, true]:
			for goal: int in [seed * 7 % cells, 31 * 64 + 17, 0]:
				var costs: PackedByteArray = _terrain(seed, 64, 64, goal, rocky)
				var turned: PackedByteArray = PackedByteArray()
				turned.resize(cells)
				for cell: int in cells:
					turned[turn.call(cell)] = costs[cell]
				var field: FlowField = _field(costs, 64, 64, goal)
				var named: int = _agree(field, _field(turned, 64, 64, turn.call(goal)), turn, cells)
				assert_int(named).is_greater(cells / 2)


func test_a_half_turned_field_on_a_wide_map_names_the_half_turned_step() -> void:
	var cells: int = 40 * 24
	var turn: Callable = func(cell: int) -> int: return cells - 1 - cell
	for seed: int in SEEDS:
		var goal: int = seed * 13 % cells
		var costs: PackedByteArray = _terrain(seed, 40, 24, goal, false)
		var turned: PackedByteArray = PackedByteArray()
		turned.resize(cells)
		for cell: int in cells:
			turned[turn.call(cell)] = costs[cell]
		_agree(_field(costs, 40, 24, goal), _field(turned, 40, 24, turn.call(goal)), turn, cells)


func test_a_quarter_turned_field_on_a_square_map_names_the_quarter_turned_step() -> void:
	var side: int = 32
	var cells: int = side * side
	var turn: Callable = func(cell: int) -> int: return _quarter(cell, side)
	for seed: int in SEEDS:
		for rocky: bool in [false, true]:
			var goal: int = seed * 5 % cells
			var costs: PackedByteArray = _terrain(seed, side, side, goal, rocky)
			var turned: PackedByteArray = PackedByteArray()
			turned.resize(cells)
			for cell: int in cells:
				turned[turn.call(cell)] = costs[cell]
			var field: FlowField = _field(costs, side, side, goal)
			var named: int = _agree(field, _field(turned, side, side, turn.call(goal)), turn, cells)
			assert_int(named).is_greater(cells / 2)


## On open ground the diagonal toward the goal wins a tie over the orthogonal, and the cross product
## breaks a dot-product tie: with a rock pillar on each diagonal neighbour of the goal (4, 4) of a
## 9 x 9 map, the corner tiles (2, 2), (6, 2), (6, 6), (2, 6) have two equal steps each and take
## E, S, W, N: the same turn of the pattern at each corner, not the scan order's north-west bias.
func test_the_cross_product_breaks_a_tie_between_equally_aimed_steps() -> void:
	var costs: PackedByteArray = PackedByteArray()
	costs.resize(81)
	costs.fill(10)
	for tile: Vector2i in [Vector2i(3, 3), Vector2i(5, 3), Vector2i(3, 5), Vector2i(5, 5)]:
		costs[tile.y * 9 + tile.x] = 0
	var field: FlowField = _field(costs, 9, 9, 4 * 9 + 4)
	assert_int(field.best_neighbour(2 * 9 + 2)).is_equal(2 * 9 + 3)
	assert_int(field.best_neighbour(2 * 9 + 6)).is_equal(3 * 9 + 6)
	assert_int(field.best_neighbour(6 * 9 + 6)).is_equal(6 * 9 + 5)
	assert_int(field.best_neighbour(6 * 9 + 2)).is_equal(5 * 9 + 2)


## A tie among a diagonal and two orthogonal steps of the same cost goes to the larger cross
## product: (3, 1) of the 7 x 7 map whose goal (3, 3) has dear orthogonal neighbours (14 each, so
## SW, S and SE all cost 14 and are equally aimed) takes SE, where the scan order took SW.
func test_three_equal_steps_go_to_the_larger_cross_product() -> void:
	var costs: PackedByteArray = PackedByteArray()
	costs.resize(49)
	costs.fill(10)
	for cell: int in [2 * 7 + 3, 4 * 7 + 3, 3 * 7 + 2, 3 * 7 + 4]:
		costs[cell] = 14
	var field: FlowField = _field(costs, 7, 7, 3 * 7 + 3)
	assert_int(field.best_neighbour(1 * 7 + 3)).is_equal(2 * 7 + 4)
