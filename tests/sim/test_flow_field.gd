extends GdUnitTestSuite
## FlowField (ADR 0008 section 3, ADR 0013 section 2): costs, slices, the double buffer, cells.

const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED
const UNREACHED: int = FlowField.UNREACHED
const BIG: int = 100000
## Map characters: open, scrub (foot only), rock, slow, slower. Foot, wheeled, tracked costs.
const GROUND: String = ".^#24"
const GROUND_COST: Array[int] = [10, 10, 10, 10, 0, 0, 0, 0, 0, 20, 20, 20, 40, 40, 40]

## The World's own `move_cost` (entry `class * cells + cell`) for one character per cell.
@warning_ignore("integer_division")
func _costs(rows: PackedStringArray) -> PackedByteArray:
	var world: World = World.new()
	var cols: int = rows[0].length()
	world.map_w = cols * 1000
	world.map_h = rows.size() * 1000
	world.prepare()
	world.terrain_cost = PackedByteArray(GROUND_COST)
	for i: int in cols * rows.size():
		world.set_terrain(i, GROUND.find(rows[i / cols][i % cols]))
	return world.move_cost


func _open(cols: int, rows: int) -> PackedStringArray:
	return (".".repeat(cols) + "\n").repeat(rows).strip_edges().split("\n")


## A finished field for `rows` from (gx, gy).
func _field(rows: PackedStringArray, gx: int, gy: int, move_class: int = FOOT) -> FlowField:
	var field: FlowField = FlowField.new()
	var cols: int = rows[0].length()
	field.begin(gy * cols + gx, move_class, _costs(rows), cols, rows.size())
	field.advance(BIG)
	return field


## The served cost of the plain cell (x, y) of a map `cols` wide.
func _at(field: FlowField, cols: int, x: int, y: int) -> int:
	return field.cost[(y + 1) * (cols + 2) + x + 1]


func test_open_grid_costs_are_the_octile_distance() -> void:
	var field: FlowField = _field(_open(16, 16), 5, 9)
	for y: int in 16:
		for x: int in 16:
			var dx: int = absi(x - 5)
			var dy: int = absi(y - 9)
			assert_int(_at(field, 16, x, y)).is_equal(10 * maxi(dx, dy) + 4 * mini(dx, dy))
	var pins: Array[int] = [_at(field, 16, 6, 10), _at(field, 16, 15, 9), _at(field, 16, 0, 0)]
	assert_array(pins).is_equal([14, 100, 110])


## A 5x3 map is 7 x 5 padded entries, the 20 ring entries UNREACHED; methods use plain cells.
func test_cost_is_padded_by_one_unreached_ring_and_methods_take_plain_cells() -> void:
	var field: FlowField = _field(_open(5, 3), 4, 0)
	assert_array([field.cost.size(), field.next.size()]).is_equal([35, 35])
	assert_int(field.cost.count(UNREACHED)).is_equal(20)
	# Cell 10 is (0, 2): north-east (1, 1) = cell 6 costs 34, east 38 and north 44.
	assert_int(_at(field, 5, 0, 2)).is_equal(48)
	assert_int(field.best_neighbour(10)).is_equal(6)


func test_a_wall_with_one_gap_leads_through_the_gap() -> void:
	var rows: PackedStringArray = [".........", ".........", "####.####", ".........", "........."]
	var field: FlowField = _field(rows, 8, 0)
	assert_int(_at(field, 9, 4, 2)).is_equal(54)
	var chain: Array[int] = []
	var cell: int = 36
	while cell != -1:
		chain.append(cell)
		cell = field.best_neighbour(cell)
	# (0,4) (1,3) (2,3) (3,3) (4,3) (4,2) (4,1) (5,0) (6,0) (7,0) (8,0), as y * 9 + x.
	assert_array(chain).is_equal([36, 28, 29, 30, 31, 22, 13, 5, 6, 7, 8])


## A diagonal needs both orthogonal cells open: either one rock blocks it, in the integration
## and in best_neighbour.
func test_no_corner_cutting_past_a_blocked_orthogonal_neighbour() -> void:
	var rock_south: FlowField = _field(PackedStringArray(["..", "#."]), 0, 0)
	assert_array([_at(rock_south, 2, 1, 1), rock_south.best_neighbour(3)]).is_equal([20, 1])
	var rock_east: FlowField = _field(PackedStringArray([".#", ".."]), 0, 0)
	assert_array([_at(rock_east, 2, 1, 1), rock_east.best_neighbour(3)]).is_equal([20, 2])
	var both: FlowField = _field(PackedStringArray([".#", "#."]), 0, 0)
	assert_array([_at(both, 2, 1, 1), both.best_neighbour(3)]).is_equal([UNREACHED, -1])


func test_scrub_is_foot_ground_and_an_enclosed_cell_stays_unreached() -> void:
	var strip: PackedStringArray = [".^."]
	var foot: FlowField = _field(strip, 0, 0, FOOT)
	assert_array([_at(foot, 3, 1, 0), _at(foot, 3, 2, 0)]).is_equal([10, 20])
	var tracked: FlowField = _field(strip, 0, 0, TRACKED)
	assert_array([_at(tracked, 3, 1, 0), _at(tracked, 3, 2, 0)]).is_equal([UNREACHED, UNREACHED])
	# A goal on ground the class cannot enter is still seeded, and its neighbours are reached.
	var on_scrub: FlowField = _field(strip, 1, 0, TRACKED)
	assert_array([_at(on_scrub, 3, 1, 0), _at(on_scrub, 3, 0, 0)]).is_equal([0, 10])
	assert_int(on_scrub.best_neighbour(0)).is_equal(1)
	var ring: PackedStringArray = [".....", ".###.", ".#.#.", ".###.", "....."]
	var enclosed: FlowField = _field(ring, 0, 0)
	assert_array([_at(enclosed, 5, 2, 2), _at(enclosed, 5, 1, 1)]).is_equal([UNREACHED, UNREACHED])
	assert_array([_at(enclosed, 5, 4, 4), enclosed.best_neighbour(12)]).is_equal([80, -1])


## A step costs the terrain of the cell it labels, times 14 / 10 on a diagonal.
func test_terrain_cost_weighs_each_step() -> void:
	assert_int(_at(_field(PackedStringArray([".24."]), 0, 0), 4, 3, 0)).is_equal(70)
	assert_int(_at(_field(PackedStringArray(["..", ".2"]), 0, 0), 2, 1, 1)).is_equal(28)


## -1 at the goal, outside the map and before completion; a goal outside the map completes at
## once. In the last field (2,2) reaches the goal through (2,1) = 5 or (1,2) = 7, both 30: 5 wins.
func test_best_neighbour_is_minus_one_at_the_ends_and_ties_go_to_the_lower_cell() -> void:
	var field: FlowField = _field(_open(4, 4), 1, 1)
	for cell: int in [5, -1, 16]:
		assert_int(field.best_neighbour(cell)).is_equal(-1)
	assert_int(field.best_neighbour(0)).is_equal(5)
	var pending: FlowField = FlowField.new()
	pending.begin(5, FOOT, _costs(_open(4, 4)), 4, 4)
	pending.advance(3)
	assert_array([pending.complete, pending.best_neighbour(0)]).is_equal([false, -1])
	pending.begin(16, FOOT, _costs(_open(4, 4)), 4, 4)
	assert_array([pending.complete, pending.advance(BIG), pending.cost.count(UNREACHED)]).is_equal(
		[true, 0, 36]
	)
	var tie: FlowField = _field(PackedStringArray(["...", ".#.", "..."]), 0, 0)
	assert_array([_at(tie, 3, 2, 1), _at(tie, 3, 1, 2)]).is_equal([30, 30])
	assert_int(tie.best_neighbour(8)).is_equal(5)


@warning_ignore("integer_division")
func test_slices_complete_in_whole_budgets_on_an_open_64_grid() -> void:
	var rows: PackedStringArray = _open(64, 64)
	var whole: PackedInt32Array = _field(rows, 0, 0).cost
	for budget: int in [1024, 512]:
		var field: FlowField = FlowField.new()
		field.begin(0, FOOT, _costs(rows), 64, 64)
		assert_int(field.advance(0) + field.advance(-5)).is_equal(0)
		var calls: int = 0
		while not field.complete:
			assert_int(field.advance(budget)).is_equal(budget)
			calls += 1
		assert_int(calls).is_equal(4096 / budget)
		assert_array(field.cost).is_equal(whole)
		assert_int(field.advance(budget)).is_equal(0)


## Seeded slow ground and rock: the costs equal a brute force that relaxes every cell until
## nothing changes, for any slicing; a call never settles more than its budget. Goal (12, 12).
@warning_ignore("integer_division")
func test_costs_match_a_brute_force_on_a_seeded_map_for_any_slicing() -> void:
	var rng: DetRandom = DetRandom.create(42, 7)
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 24:
		var row: String = ""
		for x: int in 24:
			row += "." if x == 12 and y == 12 else "....###22^4"[rng.next_int(11)]
		rows.append(row)
	var costs: PackedByteArray = _costs(rows)
	var brute: Array[int] = []
	brute.resize(576)
	brute.fill(UNREACHED)
	brute[300] = 0
	var changed: bool = true
	while changed:
		changed = false
		for u: int in 576:
			for k: int in 8:
				var vx: int = u % 24 + FlowField.DX[k]
				var vy: int = u / 24 + FlowField.DY[k]
				if vx < 0 or vy < 0 or vx > 23 or vy > 23 or costs[u] == 0:
					continue
				var diagonal: bool = FlowField.DX[k] != 0 and FlowField.DY[k] != 0
				if diagonal and (costs[u / 24 * 24 + vx] == 0 or costs[vy * 24 + u % 24] == 0):
					continue
				var through: int = brute[vy * 24 + vx] + costs[u] * (14 if diagonal else 10) / 10
				if through < brute[u]:
					brute[u] = through
					changed = true
	var reached: int = 576 - brute.count(UNREACHED)
	assert_int(reached).is_between(300, 500)
	for budget: int in [1, 7, 300]:
		var field: FlowField = FlowField.new()
		field.begin(300, FOOT, costs, 24, 24)
		var total: int = 0
		while not field.complete:
			var settled: int = field.advance(budget)
			assert_int(settled).is_between(1, budget)
			total += settled
		assert_int(total).is_equal(reached)
		for cell: int in 576:
			assert_int(_at(field, 24, cell % 24, cell / 24)).is_equal(brute[cell])


## `cost` keeps the old values until the swap, another key serves nothing until it completes,
## and neither begin nor the swap allocates: the same arrays (cost and next exchanged), same sizes.
func test_a_reintegration_serves_the_old_cost_until_the_swap_without_allocating() -> void:
	var field: FlowField = FlowField.new()
	var rows: PackedStringArray = _open(8, 8)
	field.begin(0, FOOT, _costs(rows), 8, 8)
	assert_array([field.complete, field.cost[0]]).is_equal([false, UNREACHED])
	field.advance(BIG)
	var old: PackedInt32Array = field.cost.duplicate()
	var held: Array = []
	var sizes: Array[int] = []
	for name: StringName in FlowField.STATE_ARRAYS:
		held.append(field.get(name))
		sizes.append(field.get(name).size())
	assert_array(sizes).is_equal([100, 100, 100, FlowField.BUCKETS, 100, 100])
	rows[3] = "...####."
	field.begin(0, FOOT, _costs(rows), 8, 8)
	assert_bool(field.complete).is_true()
	assert_int(field.advance(10)).is_equal(10)
	assert_array(field.cost).is_equal(old)
	assert_int(field.advance(BIG)).is_greater(0)
	assert_array(field.cost).is_equal(_field(rows, 0, 0).cost)
	assert_int(_at(field, 8, 4, 3)).is_equal(UNREACHED)
	var swapped: Dictionary[StringName, StringName] = {&"cost": &"next", &"next": &"cost"}
	for i: int in sizes.size():
		var name: StringName = FlowField.STATE_ARRAYS[i]
		assert_int(field.get(name).size()).is_equal(sizes[i])
		assert_bool(is_same(held[i], field.get(swapped.get(name, name)))).is_true()
	for key: Vector2i in [Vector2i(63, FOOT), Vector2i(0, TRACKED)]:
		field.begin(0, FOOT, _costs(rows), 8, 8)
		field.advance(BIG)
		field.begin(key.x, key.y, _costs(rows), 8, 8)
		assert_array([field.complete, field.cost[10]]).is_equal([false, UNREACHED])
