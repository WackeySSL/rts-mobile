extends GdUnitTestSuite
## FogGrid.reveal (plan row P233, ADR 0036 section 11): the whole-block +1 and -1 of the map sweep,
## with the flips, the explored bytes, the dirty list and the version of a stamp.


func _grid(cols: int, rows: int) -> FogGrid:
	var grid: FogGrid = FogGrid.new()
	grid.configure(cols, rows, 2)
	return grid


func test_a_reveal_adds_one_to_every_cell_of_the_player_and_marks_it_explored() -> void:
	var grid: FogGrid = _grid(4, 4)
	grid.reveal(2, 1)
	assert_int(grid.visible.slice(16).count(1)).is_equal(16)
	assert_int(grid.visible.slice(0, 16).count(0)).is_equal(16)
	assert_int(grid.explored.slice(16).count(1)).is_equal(16)
	assert_int(grid.explored.slice(0, 16).count(1)).is_equal(0)
	assert_array([grid.version_of(1), grid.version_of(2)]).is_equal([0, 1])
	assert_int(grid.dirty_cells(2).size()).is_equal(4)  # capacity 16 / 4: full, a prefix.
	assert_bool(grid.dirty_overflowed(2)).is_true()


func test_the_flips_are_listed_once_in_order_while_the_block_has_room() -> void:
	var grid: FogGrid = _grid(4, 4)
	grid.dirty_capacity = 16
	grid.dirty = PackedInt32Array()
	grid.dirty.resize(32)
	grid.reveal(1, 1)
	assert_array(Array(grid.dirty_cells(1))).is_equal(range(16))
	assert_bool(grid.dirty_overflowed(1)).is_false()
	grid.reveal(1, -1)
	assert_array(Array(grid.dirty_cells(1))).is_equal(range(16))  # Each cell once.
	assert_int(grid.visible.slice(0, 16).count(0)).is_equal(16)
	assert_int(grid.explored.slice(0, 16).count(1)).is_equal(16)  # Explored is history.
	assert_int(grid.version_of(1)).is_equal(2)


func test_a_cell_that_stays_visible_does_not_flip() -> void:
	var grid: FogGrid = _grid(4, 4)
	var mask: int = grid.add_mask(1000)
	grid.stamp(1, 5, mask, 1)
	var version: int = grid.version_of(1)
	grid.begin_update(1)
	grid.reveal(1, 1)
	assert_int(grid.visible[5]).is_equal(2)
	# 5 cells of the disc were already visible: 11 flips, the version moves once.
	assert_int(grid.version_of(1)).is_equal(version + 1)
	grid.begin_update(1)
	grid.reveal(1, -1)
	assert_int(grid.visible[5]).is_equal(1)
	assert_int(grid.visible.slice(0, 16).count(1)).is_equal(5)
