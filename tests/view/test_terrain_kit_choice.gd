extends GdUnitTestSuite
## `TerrainKit`, the pure piece choice (plan P656d1, ADR 0053 section 7 and amendment A2): the cell
## hash and the base variants, the edge piece by mask and priority (ore > scrub > sand > grass), the
## nearest piece where no piece fits, rock flat, and a kit with holes in it. The neighbours are
## ne = (x, y - 1), se = (x + 1, y), sw = (x, y + 1), nw = (x - 1, y) and the diagonals n, e, s, w.

const KIT: String = "res://assets/art/terrain/kit.tres"
const SOURCE: String = "res://game/view/TerrainKit.gd"
const NONE: StringName = &""
const O: StringName = &""  ## Off the map.
const LAND: Array[StringName] = [&"ore", &"scrub", &"sand", &"grass"]  ## Highest first.


func _kit() -> TerrainKitDef:
	return load(KIT) as TerrainKitDef


## An array of ids with `id` at the indexes of `at` and `fill` elsewhere.
func _around(fill: StringName, id: StringName, at: Array[int]) -> Array[StringName]:
	var around: Array[StringName] = [fill, fill, fill, fill]
	for index: int in at:
		around[index] = id
	return around


func _edge(
	own: StringName, edges: Array[StringName], diagonals: Array[StringName] = []
) -> StringName:
	if diagonals.is_empty():
		diagonals = [own, own, own, own]
	return TerrainKit.edge_key(_kit(), own, edges, diagonals)


# --- the hash and the base variants ---


func test_the_hash_is_fixed_on_crafted_cells() -> void:
	# [hash, grass variant, rock variant] on crafted cells; the origin is a boulder cell.
	var expected: Dictionary[Vector2i, Array] = {
		Vector2i(0, 0): [0, 2, 3],
		Vector2i(1, 0): [2182377942, 1, 1],
		Vector2i(0, 1): [3299714085, 1, 1],
		Vector2i(5, 9): [2457582021, 1, 1],
		Vector2i(63, 63): [4291322435, 3, 2],
	}
	for cell: Vector2i in expected:
		var row: Array = expected[cell]
		assert_int(TerrainKit.cell_hash(cell.x, cell.y)).is_equal(row[0])
		assert_int(TerrainKit.base_variant(&"grass", cell.x, cell.y, 4)).is_equal(row[1])
		assert_int(TerrainKit.base_variant(&"rock", cell.x, cell.y, 4)).is_equal(row[2])


func test_the_boulder_variant_is_one_cell_in_eight_on_a_64_by_64_grid() -> void:
	for terrain: StringName in [&"grass", &"rock"]:
		var boulder: int = TerrainKit.BOULDERS[terrain]
		var counts: Array[int] = [0, 0, 0, 0]
		for y: int in 64:
			for x: int in 64:
				counts[TerrainKit.base_variant(terrain, x, y, 4)] += 1
		var cells: int = 64 * 64
		assert_int(counts[boulder]).is_between(cells / 8 - cells / 80, cells / 8 + cells / 80)
		for variant: int in 4:
			if variant != boulder:  # The other three share the rest about evenly.
				assert_int(counts[variant]).is_between(
					cells * 7 / 8 / 3 - 60, cells * 7 / 8 / 3 + 60
				)


func test_a_terrain_without_a_boulder_uses_its_four_variants_evenly() -> void:
	for terrain: StringName in [&"sand", &"scrub", &"water", &"ore"]:
		var counts: Array[int] = [0, 0, 0, 0]
		for y: int in 64:
			for x: int in 64:
				counts[TerrainKit.base_variant(terrain, x, y, 4)] += 1
		for variant: int in 4:
			assert_int(counts[variant]).is_between(1024 - 100, 1024 + 100)


func test_the_variant_is_a_function_of_the_cell_alone() -> void:
	for y: int in 12:
		for x: int in 12:
			var first: int = TerrainKit.base_variant(&"grass", x, y, 4)
			assert_int(TerrainKit.base_variant(&"grass", x, y, 4)).is_equal(first)
			assert_int(first).is_between(0, 3)
			assert_str(TerrainKit.base_key(_kit(), &"grass", x, y)).is_equal(
				StringName("grass/base/%d" % first)
			)


func test_a_variant_the_kit_lacks_falls_back_to_variant_zero_then_to_no_piece() -> void:
	var kit: TerrainKitDef = TerrainKitDef.new()
	kit.variants = 4
	kit.pieces = {&"sand/base/0": "sand_base_0.png"}
	for x: int in 16:
		assert_str(TerrainKit.base_key(kit, &"sand", x, 3)).is_equal(&"sand/base/0")
		assert_str(TerrainKit.base_key(kit, &"rock", x, 3)).is_equal(NONE)


func test_the_choice_uses_no_random_call_and_no_node() -> void:
	var text: String = FileAccess.get_file_as_string(SOURCE)
	for banned: String in ["randi", "randf", "RandomNumberGenerator", "extends Node", "Time."]:
		assert_bool(text.contains(banned)).override_failure_message(banned).is_false()


# --- the edge piece by priority ---


func test_every_higher_terrain_blends_onto_every_lower_one_on_each_edge() -> void:
	for low: int in LAND.size():
		for high: int in low:
			for edge: int in 4:
				var edges: Array[StringName] = _around(LAND[low], LAND[high], [edge])
				var expected: StringName = StringName(
					"%s/blend/side_%s" % [LAND[high], TerrainKit.EDGES[edge]]
				)
				assert_str(_edge(LAND[low], edges)).is_equal(expected)


func test_a_lone_diagonal_gives_a_corner_blend() -> void:
	for diagonal: int in 4:
		var diagonals: Array[StringName] = _around(&"grass", &"ore", [diagonal])
		var edges: Array[StringName] = [&"grass", &"grass", &"grass", &"grass"]
		var expected: StringName = StringName(
			"ore/blend/corner_%s" % TerrainKit.DIAGONALS[diagonal]
		)
		assert_str(_edge(&"grass", edges, diagonals)).is_equal(expected)


func test_the_highest_priority_neighbour_wins_every_pair() -> void:
	for first: int in LAND.size() - 1:
		for second: int in range(first + 1, LAND.size() - 1):
			# `first` outranks `second`; both touch a cell of the lowest terrain, on different edges.
			var edges: Array[StringName] = [LAND[first], LAND[second], &"grass", &"grass"]
			var swapped: Array[StringName] = [LAND[second], LAND[first], &"grass", &"grass"]
			for around: Array[StringName] in [edges, swapped]:
				var winner: StringName = LAND[first]
				var mask: StringName = &"side_ne" if around[0] == winner else &"side_se"
				assert_str(_edge(&"grass", around)).is_equal(
					StringName("%s/blend/%s" % [winner, mask])
				)


func test_a_lower_neighbour_or_the_same_terrain_draws_no_blend() -> void:
	assert_str(_edge(&"ore", _around(&"ore", &"grass", [0, 1]))).is_equal(NONE)
	assert_str(_edge(&"scrub", _around(&"scrub", &"sand", [2]))).is_equal(NONE)
	assert_str(_edge(&"sand", _around(&"sand", &"sand", [0, 1, 2, 3]))).is_equal(NONE)
	assert_str(_edge(&"grass", _around(&"grass", &"grass", []))).is_equal(NONE)


func test_rock_and_water_neighbours_never_blend_onto_land() -> void:
	assert_str(_edge(&"grass", _around(&"grass", &"rock", [0, 2]))).is_equal(NONE)
	assert_str(_edge(&"sand", _around(&"sand", &"water", [1]))).is_equal(NONE)


func test_rock_stays_flat_with_no_lip_piece() -> void:
	for edges: Array[StringName] in [
		_around(&"rock", &"grass", [0]), _around(&"rock", &"water", [0, 1, 2, 3])
	]:
		assert_str(_edge(&"rock", edges)).is_equal(NONE)
	(
		assert_str(_edge(&"rock", _around(&"rock", &"rock", []), _around(&"rock", &"sand", [1])))
		. is_equal(NONE)
	)


func test_the_map_edge_is_no_neighbour() -> void:
	assert_str(_edge(&"water", [O, O, O, O], [O, O, O, O])).is_equal(NONE)
	assert_str(_edge(&"grass", [O, &"grass", O, &"grass"], [O, O, O, O])).is_equal(NONE)


# --- shores on the water cell ---


func test_water_has_a_shore_towards_every_other_terrain() -> void:
	for other: StringName in [&"grass", &"sand", &"scrub", &"rock", &"ore"]:
		assert_str(_edge(&"water", _around(&"water", other, [2]))).is_equal(&"water/shore/side_sw")


func test_the_shore_mask_follows_the_edges_and_diagonals() -> void:
	var water: Array[StringName] = [&"water", &"water", &"water", &"water"]
	for edge: int in 4:  # One land edge: its side.
		assert_str(_edge(&"water", _around(&"water", &"grass", [edge]))).is_equal(
			StringName("water/shore/side_%s" % TerrainKit.EDGES[edge])
		)
	for diagonal: int in 4:  # Two land edges that meet at a corner: that outer corner.
		var pair: Vector2i = TerrainKit._CORNER_EDGES[diagonal]
		assert_str(_edge(&"water", _around(&"water", &"sand", [pair.x, pair.y]))).is_equal(
			StringName("water/shore/outer_%s" % TerrainKit.DIAGONALS[diagonal])
		)
	for diagonal: int in 4:  # Only the diagonal is land: the inner corner.
		assert_str(_edge(&"water", water, _around(&"water", &"grass", [diagonal]))).is_equal(
			StringName("water/shore/inner_%s" % TerrainKit.DIAGONALS[diagonal])
		)


func test_a_mask_with_no_piece_takes_the_nearest_one() -> void:
	# Two opposite edges: the first edge's side.
	assert_str(_edge(&"water", _around(&"water", &"grass", [0, 2]))).is_equal(
		&"water/shore/side_ne"
	)
	assert_str(_edge(&"water", _around(&"water", &"grass", [1, 3]))).is_equal(
		&"water/shore/side_se"
	)
	# Three open edges: the first outer corner they hold (n, e, s, w order).
	assert_str(_edge(&"water", _around(&"water", &"grass", [0, 1, 2]))).is_equal(
		&"water/shore/outer_e"
	)
	assert_str(_edge(&"water", _around(&"water", &"grass", [1, 2, 3]))).is_equal(
		&"water/shore/outer_s"
	)
	assert_str(_edge(&"water", _around(&"water", &"grass", [0, 2, 3]))).is_equal(
		&"water/shore/outer_n"
	)
	# Four open edges.
	assert_str(_edge(&"water", _around(&"water", &"grass", [0, 1, 2, 3]))).is_equal(
		&"water/shore/outer_n"
	)
	# Several diagonals and no edge: the first diagonal's inner corner.
	var edges: Array[StringName] = [&"water", &"water", &"water", &"water"]
	assert_str(_edge(&"water", edges, _around(&"water", &"grass", [1, 3]))).is_equal(
		&"water/shore/inner_e"
	)
	# An edge and a diagonal: the edge decides.
	(
		assert_str(
			_edge(&"water", _around(&"water", &"grass", [3]), _around(&"water", &"grass", [0]))
		)
		. is_equal(&"water/shore/side_nw")
	)


func test_blends_with_two_edges_or_several_diagonals_take_the_nearest_piece() -> void:
	var edges: Array[StringName] = [&"grass", &"ore", &"grass", &"ore"]
	assert_str(_edge(&"grass", edges)).is_equal(&"ore/blend/side_se")
	edges = [&"ore", &"ore", &"grass", &"grass"]
	assert_str(_edge(&"grass", edges)).is_equal(&"ore/blend/side_ne")
	var plain: Array[StringName] = [&"grass", &"grass", &"grass", &"grass"]
	assert_str(_edge(&"grass", plain, _around(&"grass", &"ore", [2, 3]))).is_equal(
		&"ore/blend/corner_s"
	)


func test_a_kit_with_holes_falls_back_to_the_next_piece_or_none() -> void:
	var kit: TerrainKitDef = _kit().duplicate()
	kit.pieces = kit.pieces.duplicate()
	kit.pieces.erase(&"ore/blend/side_ne")
	var edges: Array[StringName] = [&"ore", &"scrub", &"grass", &"grass"]
	var own: Array[StringName] = [&"grass", &"grass", &"grass", &"grass"]
	# Ore has no side_ne piece, so the scrub on the other edge is drawn.
	assert_str(TerrainKit.edge_key(kit, &"grass", edges, own)).is_equal(&"scrub/blend/side_se")
	kit.pieces.erase(&"scrub/blend/side_se")
	assert_str(TerrainKit.edge_key(kit, &"grass", edges, own)).is_equal(NONE)
	kit.pieces.erase(&"water/shore/side_ne")
	assert_str(TerrainKit.edge_key(kit, &"water", _around(&"water", &"grass", [0]), own)).is_equal(
		NONE
	)
