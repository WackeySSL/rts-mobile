extends GdUnitTestSuite
## FogGrid (ADR 0010 section 1, ADR 0013 section 2, ADR 0012 section 3). Hand-built grids with
## literal numbers; the counts in the tables come from the rule, not from the code.


func _grid(cols: int, rows: int, players: int) -> FogGrid:
	var grid: FogGrid = FogGrid.new()
	grid.configure(cols, rows, players)
	return grid


## The cells the player sees (or has explored), ascending.
func _seen(grid: FogGrid, player: int, explored: bool = false) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for cell: int in grid.cells:
		if grid.is_explored(player, cell) if explored else grid.is_visible(player, cell):
			out.append(cell)
	return out


## Brute force over the whole map: the tiles inside the disc of `sight` milli-tiles at (cx, cy).
func _disc(cols: int, rows: int, cx: int, cy: int, sight: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for y: int in rows:
		for x: int in cols:
			var dx: int = (x - cx) * 1000
			var dy: int = (y - cy) * 1000
			if dx * dx + dy * dy <= sight * sight:
				out.append(y * cols + x)
	return out


## Everything a reader can ask of the grid, per player.
func _answers(grid: FogGrid) -> Array:
	var out: Array = []
	for player: int in range(1, grid.player_count + 1):
		var one: Array = [_seen(grid, player), _seen(grid, player, true)]
		one.append_array([grid.version_of(player), grid.dirty_overflowed(player)])
		one.append(grid.dirty_cells(player))
		out.append(one)
	return out


## Sight in milli-tiles to the tiles inside, from (dx*1000)^2 + (dy*1000)^2 <= sight^2, compared
## with a brute force over the map: the radius rounds down to whole tiles, and a diagonal only
## counts once it is reached. All masks live in one grid, so each id has to find its own rows.
func test_masks_cover_exactly_the_tiles_within_the_squared_distance() -> void:
	assert_int(FogGrid.MILLI_PER_TILE).is_equal(World.MILLI_PER_TILE)
	var sights: Array[int] = [0, 999, 1000, 1414, 1415, 2000, 6000, 6500, 7000]
	var sizes: Array[int] = [1, 1, 5, 5, 9, 13, 113, 137, 149]
	var grid: FogGrid = _grid(20, 20, 1)
	for mask: int in sights.size():
		assert_int(grid.add_mask(sights[mask])).is_equal(mask)
	for mask: int in sights.size():
		grid.stamp(1, 210, mask, 1)
		assert_int(_seen(grid, 1).size()).is_equal(sizes[mask])
		assert_array(_seen(grid, 1)).is_equal(_disc(20, 20, 10, 10, sights[mask]))
		grid.stamp(1, 210, mask, -1)
		assert_array(_seen(grid, 1)).is_empty()


## A 20 x 14 map (cols != rows), stamped for the last player, so a stamp that left the map would
## write into the block of the player before or past the end of the array.
func test_masks_clip_at_the_map_edges() -> void:
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(19, 0), Vector2i(0, 13), Vector2i(19, 13)]:
		var grid: FogGrid = _grid(20, 14, 2)
		grid.stamp(2, corner.y * 20 + corner.x, grid.add_mask(6000), 1)
		assert_array(_seen(grid, 2)).is_equal(_disc(20, 14, corner.x, corner.y, 6000))
		assert_int(_seen(grid, 2).size()).is_equal(35)
		assert_array(_seen(grid, 1)).is_empty()


func test_overlap_stays_visible_and_explored_stays_after_one_unstamp() -> void:
	var grid: FogGrid = _grid(20, 20, 1)
	var mask: int = grid.add_mask(3000)
	grid.stamp(1, 10 * 20 + 7, mask, 1)
	grid.stamp(1, 10 * 20 + 11, mask, 1)
	assert_int(grid.visible[10 * 20 + 9]).is_equal(2)
	grid.stamp(1, 10 * 20 + 7, mask, -1)
	assert_int(grid.visible[10 * 20 + 9]).is_equal(1)
	assert_array(_seen(grid, 1)).is_equal(_disc(20, 20, 11, 10, 3000))
	var both: PackedInt32Array = _disc(20, 20, 7, 10, 3000) + _disc(20, 20, 11, 10, 3000)
	for cell: int in grid.cells:
		assert_bool(grid.is_explored(1, cell)).is_equal(both.has(cell))


func test_players_use_their_own_blocks_at_both_ends() -> void:
	var grid: FogGrid = _grid(8, 8, 3)
	var plus: int = grid.add_mask(1000)
	grid.stamp(1, 0, plus, 1)
	grid.stamp(3, 63, plus, 1)
	assert_int(grid.visible.size()).is_equal(192)
	for explored: bool in [false, true]:
		assert_array(_seen(grid, 1, explored)).is_equal(PackedInt32Array([0, 1, 8]))
		assert_array(_seen(grid, 3, explored)).is_equal(PackedInt32Array([55, 62, 63]))
		assert_array(_seen(grid, 2, explored)).is_empty()
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([0, 1, 8]))
	assert_array(grid.dirty_cells(3)).is_equal(PackedInt32Array([55, 62, 63]))
	assert_array(grid.dirty_cells(2)).is_empty()
	assert_int(grid.visible[0] + grid.visible[191]).is_equal(2)
	assert_array(grid.version).is_equal(PackedInt32Array([1, 0, 1]))


func test_version_changes_only_when_a_cell_flips() -> void:
	var grid: FogGrid = _grid(16, 16, 2)
	var mask: int = grid.add_mask(2000)
	grid.stamp(1, 136, mask, 1)
	assert_int(grid.version_of(1)).is_equal(1)
	grid.stamp(1, 136, mask, 1)
	grid.stamp(1, 136, mask, -1)
	assert_int(grid.version_of(1)).is_equal(1)
	grid.stamp(1, 136, mask, -1)
	assert_int(grid.version_of(1)).is_equal(2)
	grid.stamp(1, 136, mask, 1)
	assert_int(grid.version_of(1)).is_equal(3)
	assert_int(grid.version_of(2)).is_equal(0)


## begin_update empties the list and touches nothing else: no version change, nothing re-fogged.
func test_the_dirty_list_holds_exactly_the_flipped_cells() -> void:
	var grid: FogGrid = _grid(16, 16, 1)
	var mask: int = grid.add_mask(1000)
	grid.stamp(1, 85, mask, 1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([69, 84, 85, 86, 101]))
	grid.begin_update(1)
	assert_array(grid.dirty_cells(1)).is_empty()
	assert_int(grid.version_of(1)).is_equal(1)
	assert_bool(grid.is_visible(1, 85)).is_true()
	assert_bool(grid.is_explored(1, 85)).is_true()
	grid.stamp(1, 86, mask, 1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([70, 87, 102]))
	grid.begin_update(1)
	grid.stamp(1, 85, mask, -1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([69, 84, 101]))
	assert_bool(grid.dirty_overflowed(1)).is_false()


## 8 x 8 cells hold 16 entries per block: three plus shapes and one dot fill it exactly. A flip
## that finds the block full still grows the version (the view's trigger) and leaves no mark, so
## once begin_update empties the block the cell is listed when it flips back.
func test_a_full_block_sets_the_flag_grows_the_version_and_leaves_no_mark() -> void:
	var grid: FogGrid = _grid(8, 8, 1)
	var plus: int = grid.add_mask(1000)
	var dot: int = grid.add_mask(0)
	for centre: int in [9, 13, 41]:
		grid.stamp(1, centre, plus, 1)
	grid.stamp(1, 54, dot, 1)
	assert_int(grid.dirty_cells(1).size()).is_equal(16)
	assert_bool(grid.dirty_overflowed(1)).is_false()
	assert_int(grid.version_of(1)).is_equal(4)
	grid.stamp(1, 63, dot, 1)
	assert_bool(grid.dirty_overflowed(1)).is_true()
	assert_int(grid.version_of(1)).is_equal(5)
	assert_int(grid.dirty_cells(1).size()).is_equal(16)
	assert_int(grid.dirty_cells(1)[15]).is_equal(54)
	assert_bool(grid.is_visible(1, 63)).is_true()
	grid.stamp(1, 54, dot, 1)
	assert_bool(grid.dirty_overflowed(1)).is_true()
	assert_int(grid.dirty_cells(1).size()).is_equal(16)
	grid.begin_update(1)
	assert_bool(grid.dirty_overflowed(1)).is_false()
	assert_array(grid.dirty_cells(1)).is_empty()
	grid.stamp(1, 63, dot, -1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([63]))


## A lone unit of player 2 with sight 6000 (113 tiles) moves one tile on a 30 x 30 map. Unstamping
## the old disc first flips every cell of both discs (126), stamping the new one first only the 26
## that change; either way a cell is listed once and the block of 225 does not overflow.
func test_a_cell_is_listed_once_per_update_in_either_stamp_order() -> void:
	var old_disc: PackedInt32Array = _disc(30, 30, 15, 15, 6000)
	var new_disc: PackedInt32Array = _disc(30, 30, 16, 15, 6000)
	for new_first: bool in [false, true]:
		var grid: FogGrid = _grid(30, 30, 2)
		var mask: int = grid.add_mask(6000)
		grid.stamp(2, 465, mask, 1)
		grid.begin_update(2)
		if new_first:
			grid.stamp(2, 466, mask, 1)
			grid.stamp(2, 465, mask, -1)
		else:
			grid.stamp(2, 465, mask, -1)
			grid.stamp(2, 466, mask, 1)
		var expected: PackedInt32Array = PackedInt32Array()
		for cell: int in grid.cells:
			var was: bool = old_disc.has(cell)
			var now: bool = new_disc.has(cell)
			if (was != now) if new_first else (was or now):
				expected.append(cell)
		var got: PackedInt32Array = grid.dirty_cells(2)
		got.sort()
		assert_int(got.size()).is_equal(26 if new_first else 126)
		assert_array(got).is_equal(expected)
		assert_bool(grid.dirty_overflowed(2)).is_false()


## Two blocks of 16 in one flat array whose size never changes. Both players overflow with the
## same stamp; begin_update(2) empties player 2 only, and the marks are per player, so player 2
## can list cell 0 again while player 1 still has it.
func test_dirty_lists_are_fixed_blocks_and_begin_update_clears_one_player() -> void:
	var grid: FogGrid = _grid(8, 8, 2)
	var wide: int = grid.add_mask(6000)
	var dot: int = grid.add_mask(0)
	assert_int(grid.dirty.size() + grid.dirty_count.size() + grid.dirty_full.size()).is_equal(36)
	for player: int in [1, 2]:
		grid.stamp(player, 27, wide, 1)
	var first: PackedInt32Array = PackedInt32Array(range(16))
	assert_array(grid.dirty.slice(0, 32)).is_equal(first + first)
	assert_array(grid.dirty_count + grid.dirty_full).is_equal(PackedInt32Array([16, 16, 1, 1]))
	var copy: PackedInt32Array = grid.dirty_cells(2)
	copy[0] = 99
	assert_int(grid.dirty[16]).is_equal(0)
	grid.begin_update(2)
	assert_array(grid.dirty_count + grid.dirty_full).is_equal(PackedInt32Array([16, 0, 1, 0]))
	assert_array(grid.dirty_cells(1)).is_equal(first)
	assert_array(grid.dirty_cells(2)).is_empty()
	grid.stamp(2, 0, dot, -1)
	grid.stamp(1, 0, dot, -1)
	assert_array(grid.dirty_cells(2)).is_equal(PackedInt32Array([0]))
	assert_array(grid.dirty_cells(1)).is_equal(first)
	assert_int(grid.dirty.size()).is_equal(32)


## begin_update(2) clears the marks of player 2's cells only: cell 5 of player 1 is still listed,
## so its flip back adds no second entry.
func test_begin_update_of_another_player_keeps_a_cell_listed_once() -> void:
	var grid: FogGrid = _grid(8, 8, 2)
	var dot: int = grid.add_mask(0)
	grid.stamp(1, 5, dot, 1)
	grid.begin_update(2)
	grid.stamp(1, 5, dot, -1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([5]))


## 7 x 5 is not square and has 35 cells, so a quarter is 8, rounded down. configure() on a used
## grid gives the arrays of a new one and keeps the masks.
func test_configure_sizes_every_block_and_clears_a_used_grid() -> void:
	var grid: FogGrid = _grid(7, 5, 2)
	var mask: int = grid.add_mask(2000)
	assert_array([grid.cells, grid.dirty_capacity, grid.dirty.size()]).is_equal([35, 8, 16])
	assert_int(grid.visible.size() + grid.explored.size() + grid.listed.size()).is_equal(210)
	grid.stamp(2, 17, mask, 1)
	assert_bool(grid.dirty_overflowed(2)).is_true()
	grid.configure(7, 5, 2)
	var fresh: FogGrid = _grid(7, 5, 2)
	fresh.add_mask(2000)
	for field: StringName in FogGrid.HASHED + FogGrid.UNHASHED:
		assert_bool(grid.get(field) == fresh.get(field)).is_true()


## 12 x 10 (cols != rows), so a copy that takes one size for the other fails the field loop.
func test_copy_into_answers_as_the_source_and_shares_nothing() -> void:
	var src: FogGrid = _grid(12, 10, 2)
	var disc: int = src.add_mask(3000)
	var dot: int = src.add_mask(0)
	src.stamp(1, 30, disc, 1)
	src.stamp(2, 100, disc, 1)
	src.stamp(2, 100, disc, -1)
	src.begin_update(1)
	src.stamp(1, 31, dot, 1)
	var dst: FogGrid = _grid(3, 3, 5)
	dst.stamp(1, 4, dst.add_mask(1000), 1)
	src.copy_into(dst)
	var expected: Array = _answers(src)
	assert_array(_answers(dst)).is_equal(expected)
	for field: StringName in FogGrid.HASHED + FogGrid.UNHASHED:
		assert_bool(src.get(field) == dst.get(field)).is_true()
		if typeof(src.get(field)) != TYPE_INT:
			assert_bool(is_same(src.get(field), dst.get(field))).is_false()
	src.stamp(1, 70, disc, 1)
	src.stamp(2, 5, dot, 1)
	src.begin_update(2)
	assert_array(src.dirty_cells(2)).is_empty()
	assert_array(_answers(dst)).is_equal(expected)


func test_every_int_and_packed_array_is_listed_once() -> void:
	assert_array(FogGrid.HASHED).is_equal([&"visible", &"explored"])
	var found: Array[StringName] = []
	for info: Dictionary in FogGrid.new().get_property_list():
		var kind: int = info.type
		var script_var: bool = (int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
		var packed: bool = kind >= TYPE_PACKED_BYTE_ARRAY and kind < TYPE_MAX
		if script_var and (kind == TYPE_INT or packed):
			found.append(StringName(info.name))
	assert_array(found).contains_exactly_in_any_order(FogGrid.HASHED + FogGrid.UNHASHED)
