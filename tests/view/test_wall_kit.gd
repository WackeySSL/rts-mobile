extends GdUnitTestSuite
## `WallKit`, the raised walls' piece choice (ADR 0053 amendment A3, plan P656d2): the face by the
## front mask, the rim by the back mask, the top by the cell hash; pure, so tables.

const COLS: int = 5


func test_the_face_table_names_the_open_front_edges() -> void:
	assert_str(String(WallKit.face_key(0))).is_equal("")  # Both front neighbours are raised.
	assert_str(String(WallKit.face_key(1))).is_equal("rock/wall_face/se")
	assert_str(String(WallKit.face_key(2))).is_equal("rock/wall_face/sw")
	assert_str(String(WallKit.face_key(3))).is_equal("rock/wall_face/s")


func test_the_rim_table_covers_every_back_mask() -> void:
	var want: Array[String] = ["", "ne", "nw", "n", "inner_n", "ne", "nw", "n"]
	for mask: int in 8:
		var key: String = String(WallKit.rim_key(mask))
		assert_str(key).override_failure_message("back mask %d" % mask).is_equal(
			"" if want[mask] == "" else "rock/wall_rim/%s" % want[mask]
		)


func test_the_masks_read_the_neighbours_and_off_the_map_is_not_raised() -> void:
	var grid: PackedByteArray = _grid(["#####", "#####", "##.##", "#####", "#####"])
	# The cell (1, 1): every neighbour raised, so no face and no rim.
	assert_int(WallKit.front_mask(grid, COLS, 1, 1)).is_equal(0)
	assert_int(WallKit.back_mask(grid, COLS, 1, 1)).is_equal(0)
	# (1, 2) has the hole (2, 2) on its south-east: front bit 1. (2, 1) has it on the south-west.
	assert_int(WallKit.front_mask(grid, COLS, 1, 2)).is_equal(1)
	assert_int(WallKit.front_mask(grid, COLS, 2, 1)).is_equal(2)
	# (3, 3): the hole is (2, 2), its back diagonal: the inner corner and nothing else.
	assert_int(WallKit.back_mask(grid, COLS, 3, 3)).is_equal(4)
	assert_str(String(WallKit.rim_key(4))).is_equal("rock/wall_rim/inner_n")
	# The edge of the map is open: (0, 0) has an open back on both sides, (4, 4) both fronts.
	assert_int(WallKit.back_mask(grid, COLS, 0, 0)).is_equal(7)
	assert_int(WallKit.front_mask(grid, COLS, 4, 4)).is_equal(3)


func test_every_mask_of_a_lone_cell_and_its_pieces_in_draw_order() -> void:
	var grid: PackedByteArray = _grid([".....", ".....", "..#..", ".....", "....."])
	var pieces: Array[StringName] = WallKit.pieces(grid, COLS, 2, 2)
	assert_int(pieces.size()).is_equal(3)
	assert_str(String(pieces[0])).is_equal("rock/wall_face/s")
	assert_bool(String(pieces[1]).begins_with("rock/wall_top/")).is_true()
	assert_str(String(pieces[2])).is_equal("rock/wall_rim/n")
	var inner: PackedByteArray = _grid(["###..", "###..", "###..", ".....", "....."])
	var inside: Array[StringName] = WallKit.pieces(inner, COLS, 1, 1)
	assert_str(String(inside[0])).is_equal("")
	assert_str(String(inside[2])).is_equal("")


func test_the_top_hash_is_fixed_and_one_cell_in_eight_is_the_boulder() -> void:
	assert_int(WallKit.cell_hash(3, 7)).is_equal(WallKit.cell_hash(3, 7))
	assert_int(WallKit.cell_hash(3, 7)).is_not_equal(WallKit.cell_hash(7, 3))
	var boulders: int = 0
	for row: int in 64:
		for col: int in 64:
			var variant: int = WallKit.top_variant(col, row, 8)
			assert_int(variant).is_between(0, WallKit.TOP_VARIANTS - 1)
			boulders += int(variant == WallKit.BOULDER)
	# 4096 / 8 = 512, give or take what a hash of this size spreads.
	assert_int(boulders).is_between(430, 600)
	# No rate, no boulder; the other three variants are all drawn.
	assert_int(WallKit.top_variant(0, 0)).is_less(WallKit.BOULDER)


func test_every_key_the_choice_can_return_is_in_all_keys() -> void:
	var keys: Array[StringName] = WallKit.all_keys()
	assert_int(keys.size()).is_equal(11)  # 3 faces, 4 tops, 4 rims.
	for mask: int in 4:
		assert_bool(mask == 0 or keys.has(WallKit.face_key(mask))).is_true()
	for mask: int in 8:
		assert_bool(mask == 0 or keys.has(WallKit.rim_key(mask))).is_true()
	for cell: int in 100:
		assert_bool(keys.has(WallKit.top_key(cell % 10, cell / 10))).is_true()


func _grid(lines: Array[String]) -> PackedByteArray:
	var grid: PackedByteArray = PackedByteArray()
	for text: String in lines:
		for at: int in text.length():
			grid.append(1 if text[at] == "#" else 0)
	return grid
