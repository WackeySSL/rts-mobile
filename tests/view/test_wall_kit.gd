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


func test_the_top_is_the_variant_the_flat_ground_rule_picks() -> void:
	var kit: TerrainKitDef = _kit()
	for row: int in 32:
		for col: int in 32:
			var number: int = TerrainKit.variant(kit, &"rock", &"wall_top", col, row)
			assert_str(String(WallKit.top_key(col, row, kit))).is_equal("rock/wall_top/%d" % number)
			# One hash rule: the flat rock cell shows the same variant number as the raised one.
			assert_int(TerrainKit.variant(kit, &"rock", &"base", col, row)).is_equal(number)


func test_all_keys_follow_the_kits_wall_top_list_whatever_its_count() -> void:
	var kit: TerrainKitDef = _kit()
	var keys: Array[StringName] = WallKit.all_keys(kit)
	assert_int(keys.size()).is_equal(3 + kit.variants_of(&"rock", &"wall_top").size() + 4)
	for mask: int in 4:
		assert_bool(mask == 0 or keys.has(WallKit.face_key(mask))).is_true()
	for mask: int in 8:
		assert_bool(mask == 0 or keys.has(WallKit.rim_key(mask))).is_true()
	for cell: int in 100:
		assert_bool(keys.has(WallKit.top_key(cell % 10, cell / 10, kit))).is_true()
	# A kit with six wall tops (and one with none) is followed exactly.
	var six: TerrainKitDef = kit.duplicate()
	six.pieces = six.pieces.duplicate()
	six.variant_counts = {&"rock/wall_top": 6}
	for number: int in range(4, 6):
		six.pieces[TerrainKitDef.key(&"rock", &"wall_top", StringName(str(number)))] = "x.png"
	six.masks = six.masks.duplicate()
	var wanted: Array[StringName] = []
	for number: int in 6:
		wanted.append(TerrainKitDef.key(&"rock", &"wall_top", StringName(str(number))))
	var tops: Array[StringName] = []
	for key: StringName in WallKit.all_keys(six):
		if String(key).begins_with("rock/wall_top/"):
			tops.append(key)
	assert_array(tops).is_equal(wanted)
	var none: TerrainKitDef = kit.duplicate()
	none.pieces = none.pieces.duplicate()
	for number: int in 4:
		none.pieces.erase(TerrainKitDef.key(&"rock", &"wall_top", StringName(str(number))))
	assert_int(WallKit.all_keys(none).size()).is_equal(3 + 4)
	assert_str(String(WallKit.top_key(1, 1, none))).is_equal("")


func _kit() -> TerrainKitDef:
	return load("res://assets/art/terrain/kit.tres") as TerrainKitDef


func _grid(lines: Array[String]) -> PackedByteArray:
	var grid: PackedByteArray = PackedByteArray()
	for text: String in lines:
		for at: int in text.length():
			grid.append(1 if text[at] == "#" else 0)
	return grid
