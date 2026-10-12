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


## Stamped for the last player, so a stamp that left the map would write into the block of the
## player before or past the end of the array.
func test_masks_clip_at_the_map_edges() -> void:
	var spots: Array[Vector3i] = [
		Vector3i(0, 0, 35), Vector3i(19, 19, 35), Vector3i(0, 10, 63), Vector3i(19, 0, 35)
	]
	for spot: Vector3i in spots:
		var grid: FogGrid = _grid(20, 20, 2)
		grid.stamp(2, spot.y * 20 + spot.x, grid.add_mask(6000), 1)
		assert_array(_seen(grid, 2)).is_equal(_disc(20, 20, spot.x, spot.y, 6000))
		assert_int(_seen(grid, 2).size()).is_equal(spot.z)
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
	assert_array(_seen(grid, 1)).is_equal(PackedInt32Array([0, 1, 8]))
	assert_array(_seen(grid, 3)).is_equal(PackedInt32Array([55, 62, 63]))
	assert_array(_seen(grid, 2, true)).is_empty()
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


func test_the_dirty_list_holds_exactly_the_flipped_cells() -> void:
	var grid: FogGrid = _grid(16, 16, 1)
	var mask: int = grid.add_mask(1000)
	grid.stamp(1, 85, mask, 1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([69, 84, 85, 86, 101]))
	grid.begin_update(1)
	assert_array(grid.dirty_cells(1)).is_empty()
	grid.stamp(1, 86, mask, 1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([70, 87, 102]))
	grid.begin_update(1)
	grid.stamp(1, 85, mask, -1)
	assert_array(grid.dirty_cells(1)).is_equal(PackedInt32Array([69, 84, 101]))
	assert_bool(grid.dirty_overflowed(1)).is_false()


## 8 x 8 cells hold 16 entries per block: three plus shapes and one dot fill it exactly.
func test_a_full_block_sets_the_flag_and_begin_update_clears_it() -> void:
	var grid: FogGrid = _grid(8, 8, 1)
	var plus: int = grid.add_mask(1000)
	var dot: int = grid.add_mask(0)
	for centre: int in [9, 13, 41]:
		grid.stamp(1, centre, plus, 1)
	grid.stamp(1, 54, dot, 1)
	assert_int(grid.dirty_cells(1).size()).is_equal(16)
	assert_bool(grid.dirty_overflowed(1)).is_false()
	grid.stamp(1, 63, dot, 1)
	assert_bool(grid.dirty_overflowed(1)).is_true()
	assert_int(grid.dirty_cells(1).size()).is_equal(16)
	assert_int(grid.dirty_cells(1)[15]).is_equal(54)
	assert_bool(grid.is_visible(1, 63)).is_true()
	grid.begin_update(1)
	assert_bool(grid.dirty_overflowed(1)).is_false()
	assert_int(grid.dirty_cells(1).size()).is_equal(0)


## Two blocks of 16 in one flat array. Its size is the same after configure(), after a full
## block and after begin_update(), and each player's entries sit in its own block.
func test_dirty_lists_are_fixed_blocks_of_one_flat_array() -> void:
	var grid: FogGrid = _grid(8, 8, 2)
	assert_int(grid.dirty.size()).is_equal(32)
	assert_int(grid.dirty_count.size() + grid.dirty_full.size()).is_equal(4)
	grid.stamp(2, 9, grid.add_mask(1000), 1)
	assert_array(grid.dirty_count).is_equal(PackedInt32Array([0, 5]))
	assert_array(grid.dirty.slice(16, 21)).is_equal(PackedInt32Array([1, 8, 9, 10, 17]))
	assert_array(grid.dirty_cells(1)).is_empty()
	var copy: PackedInt32Array = grid.dirty_cells(2)
	assert_array(copy).is_equal(PackedInt32Array([1, 8, 9, 10, 17]))
	copy[0] = 99
	assert_int(grid.dirty[16]).is_equal(1)
	grid.stamp(2, 27, grid.add_mask(6000), 1)
	assert_bool(grid.dirty_overflowed(2)).is_true()
	assert_int(grid.dirty.size()).is_equal(32)
	grid.begin_update(2)
	assert_int(grid.dirty.size()).is_equal(32)


func test_copy_into_answers_as_the_source_and_shares_nothing() -> void:
	var src: FogGrid = _grid(12, 12, 2)
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
		assert_bool(is_same(src.get(field), dst.get(field))).is_false()
		assert_bool(src.get(field) == dst.get(field)).is_true()
	for field: StringName in [&"cols", &"rows", &"cells", &"player_count", &"dirty_capacity"]:
		assert_int(dst.get(field)).is_equal(src.get(field))
	assert_int(dst.dirty_capacity).is_equal(36)
	src.stamp(1, 70, disc, 1)
	src.stamp(2, 5, dot, 1)
	src.begin_update(1)
	assert_array(_answers(dst)).is_equal(expected)


func test_every_packed_array_is_listed_once() -> void:
	assert_array(FogGrid.HASHED).is_equal([&"visible", &"explored"])
	var found: Array[StringName] = []
	for info: Dictionary in FogGrid.new().get_property_list():
		var kind: int = info.type
		var script_var: bool = (int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
		if script_var and kind >= TYPE_PACKED_BYTE_ARRAY and kind < TYPE_MAX:
			found.append(StringName(info.name))
	assert_array(found).contains_exactly_in_any_order(FogGrid.HASHED + FogGrid.UNHASHED)
