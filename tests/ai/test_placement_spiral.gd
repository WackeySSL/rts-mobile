extends GdUnitTestSuite
## The fixed spiral of building slots (plan row P83, ADR 0020 section 4): ring by ring round the
## base cell, clockwise from the top-left corner, no cell twice, the base cell never.

const RING_1: Array[int] = [-1, -1, 0, -1, 1, -1, 1, 0, 1, 1, 0, 1, -1, 1, -1, 0]


func test_ring_one_goes_clockwise_from_the_top_left_corner() -> void:
	assert_array(Array(PlacementSpiral.cells(8))).is_equal(RING_1)


func test_ring_two_starts_at_its_top_left_corner_and_ends_beside_it() -> void:
	var cells: PackedInt32Array = PlacementSpiral.cells(24)
	assert_array(Array(cells.slice(16, 20))).is_equal([-2, -2, -1, -2])
	assert_array(Array(cells.slice(44, 48))).is_equal([-2, 0, -2, -1])
	# The top row ends in the top-right corner, and the right column runs down from just under it.
	assert_array(Array(cells.slice(24, 26))).is_equal([2, -2])
	assert_array(Array(cells.slice(26, 32))).is_equal([2, -1, 2, 0, 2, 1])


func test_ring_k_holds_8_k_cells_and_the_rings_follow_each_other() -> void:
	var cells: PackedInt32Array = PlacementSpiral.cells(8 + 16 + 24 + 32)
	var counts: Dictionary[int, int] = {}
	var last_ring: int = 0
	for at: int in cells.size() / 2:
		var ring: int = maxi(absi(cells[at * 2]), absi(cells[at * 2 + 1]))
		counts[ring] = counts.get(ring, 0) + 1
		assert_int(ring).is_greater_equal(last_ring)
		last_ring = ring
	assert_dict(counts).is_equal({1: 8, 2: 16, 3: 24, 4: 32})


func test_no_cell_repeats_and_the_base_cell_is_never_one() -> void:
	var cells: PackedInt32Array = PlacementSpiral.cells(200)
	var seen: Dictionary[Vector2i, bool] = {}
	for at: int in cells.size() / 2:
		var cell: Vector2i = Vector2i(cells[at * 2], cells[at * 2 + 1])
		assert_bool(seen.has(cell)).is_false()
		assert_bool(cell == Vector2i.ZERO).is_false()
		seen[cell] = true
	assert_int(seen.size()).is_equal(200)


func test_neighbours_in_a_ring_touch_and_a_prefix_is_a_prefix() -> void:
	var cells: PackedInt32Array = PlacementSpiral.cells(48)
	for at: int in range(1, 48):
		var step: Vector2i = (
			Vector2i(cells[at * 2], cells[at * 2 + 1])
			- Vector2i(cells[at * 2 - 2], cells[at * 2 - 1])
		)
		var ring: int = maxi(absi(cells[at * 2]), absi(cells[at * 2 + 1]))
		var before: int = maxi(absi(cells[at * 2 - 2]), absi(cells[at * 2 - 1]))
		if ring == before:
			assert_int(absi(step.x) + absi(step.y)).is_equal(1)
	assert_array(Array(PlacementSpiral.cells(5))).is_equal(Array(cells.slice(0, 10)))


func test_a_count_of_zero_or_less_gives_no_cell_and_n_gives_n_pairs() -> void:
	assert_int(PlacementSpiral.cells(0).size()).is_equal(0)
	assert_int(PlacementSpiral.cells(-3).size()).is_equal(0)
	for count: int in [1, 7, 9, 64]:
		assert_int(PlacementSpiral.cells(count).size()).is_equal(count * 2)
