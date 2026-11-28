extends GdUnitTestSuite
## The stone rule of `TerrainKit.variant` (plan P656d1; Michael, 2026-11-28): the variants that
## carry stones, the chance scaled by a low-frequency integer value noise, one hash rule for the
## flat ground and the raised walls, and any variant count.

const KIT: String = "res://assets/art/terrain/kit.tres"
const NONE: StringName = &""


func _kit() -> TerrainKitDef:
	return load(KIT) as TerrainKitDef


## A kit with `count` variants of grass/base and rock/base and rock/wall_top, `stones` of them stone
## variants on all three, `permille` and `cells` as the rule.
func _stone_kit(count: int, stones: Array[int], permille: int, cells: int) -> TerrainKitDef:
	var kit: TerrainKitDef = TerrainKitDef.new()
	for rule: String in ["grass/base", "rock/base", "rock/wall_top"]:
		var parts: PackedStringArray = rule.split("/")
		kit.variant_counts[StringName(rule)] = count
		kit.stone_variants[StringName(rule)] = PackedInt32Array(stones)
		kit.stone_permille[StringName(rule)] = permille
		for number: int in count:
			kit.pieces[TerrainKitDef.key(parts[0], parts[1], StringName(str(number)))] = "x.png"
	kit.stone_cluster_cells = cells
	return kit


func test_the_kit_data_names_the_stones_and_the_rule() -> void:
	var kit: TerrainKitDef = _kit()
	assert_array(Array(kit.stone_variants[&"grass/base"])).is_equal([2, 3, 4, 5, 6, 7])
	assert_array(Array(kit.stone_variants[&"rock/base"])).is_equal([3, 4, 5, 6, 7, 8])
	assert_array(Array(kit.stone_variants[&"rock/wall_top"])).is_equal([3, 4, 5, 6, 7, 8])
	assert_int(kit.stone_permille[&"grass/base"]).is_equal(150)
	assert_int(kit.stone_permille[&"rock/base"]).is_equal(240)
	assert_int(kit.stone_permille[&"rock/wall_top"]).is_equal(240)
	assert_int(kit.stone_cluster_cells).is_equal(8)
	assert_array(Array(kit.variants_of(&"grass", &"base"))).is_equal([0, 1, 2, 3, 4, 5, 6, 7])
	assert_array(Array(kit.variants_of(&"rock", &"wall_top"))).is_equal([0, 1, 2, 3, 4, 5, 6, 7, 8])


func test_no_stone_variant_when_the_density_is_zero() -> void:
	var kit: TerrainKitDef = _stone_kit(8, [2, 3, 4], 0, 10)
	var plain: Dictionary[int, bool] = {}
	for y: int in 64:
		for x: int in 64:
			var number: int = TerrainKit.variant(kit, &"grass", &"base", x, y)
			assert_bool([2, 3, 4].has(number)).is_false()
			plain[number] = true
	assert_array(plain.keys()).contains_exactly_in_any_order([0, 1, 5, 6, 7])  # All the plain ones.
	# A kind with no stone entry has no stones: all its variants are plain.
	kit.stone_variants.clear()
	var every: Dictionary[int, bool] = {}
	for y: int in 32:
		for x: int in 32:
			every[TerrainKit.variant(kit, &"grass", &"base", x, y)] = true
	assert_int(every.size()).is_equal(8)


func test_the_density_follows_the_noise_on_a_fixed_grid() -> void:
	var kit: TerrainKitDef = _stone_kit(8, [5, 6, 7], 1000, 8)
	var high: Array[int] = [0, 0]  # Cells with noise 800 or more: [stones, all].
	var low: Array[int] = [0, 0]  # Cells with noise 200 or less.
	for y: int in 64:
		for x: int in 64:
			var noise: int = TerrainKit.cluster_noise(x, y, 8)
			var stone: int = int(TerrainKit.variant(kit, &"grass", &"base", x, y) >= 5)
			if noise >= 800:
				high[0] += stone
				high[1] += 1
			elif noise <= 200:
				low[0] += stone
				low[1] += 1
	assert_int(high[1]).is_greater(100)  # Both patches are there to be compared.
	assert_int(low[1]).is_greater(100)
	assert_float(float(high[0]) / high[1]).is_greater(0.7)  # A high-noise patch is mostly stones.
	assert_float(float(low[0]) / low[1]).is_less(0.3)  # A low-noise stretch has few.
	# Without clusters the density is flat: a permille of 500 gives about half the cells.
	var flat: TerrainKitDef = _stone_kit(8, [5, 6, 7], 500, 0)
	var total: int = 0
	for y: int in 64:
		for x: int in 64:
			total += int(TerrainKit.variant(flat, &"grass", &"base", x, y) >= 5)
	assert_int(total).is_between(1800, 2300)


func test_the_cluster_noise_is_integer_value_noise_between_0_and_1000() -> void:
	for y: int in 40:
		for x: int in 40:
			var noise: int = TerrainKit.cluster_noise(x, y, 10)
			assert_int(noise).is_between(0, 1000)
			assert_int(TerrainKit.cluster_noise(x, y, 10)).is_equal(noise)
	assert_int(TerrainKit.cluster_noise(3, 4, 0)).is_equal(1000)  # No clusters.
	# It is smooth: a step of one cell moves it by far less than its whole range.
	for x: int in 39:
		(
			assert_int(
				absi(TerrainKit.cluster_noise(x, 7, 10) - TerrainKit.cluster_noise(x + 1, 7, 10))
			)
			. is_less(400)
		)


func test_a_stone_is_drawn_from_the_stone_variants_and_all_of_them_show() -> void:
	var kit: TerrainKitDef = _stone_kit(8, [5, 6, 7], 1000, 0)  # Every cell a stone variant.
	var seen: Dictionary[int, bool] = {}
	for y: int in 32:
		for x: int in 32:
			seen[TerrainKit.variant(kit, &"grass", &"base", x, y)] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([5, 6, 7])


func test_the_same_cell_gets_the_same_variant_flat_or_raised() -> void:
	var kit: TerrainKitDef = _stone_kit(6, [3, 4, 5], 400, 10)
	for y: int in 48:
		for x: int in 48:
			var flat: int = TerrainKit.variant(kit, &"rock", &"base", x, y)
			assert_int(TerrainKit.variant(kit, &"rock", &"wall_top", x, y)).is_equal(flat)
			assert_int(TerrainKit.variant(kit, &"rock", &"base", x, y)).is_equal(flat)
	var real: TerrainKitDef = _kit()  # And in today's kit, whose two lists are the same.
	for y: int in 48:
		for x: int in 48:
			assert_int(TerrainKit.variant(real, &"rock", &"wall_top", x, y)).is_equal(
				TerrainKit.variant(real, &"rock", &"base", x, y)
			)


func test_any_variant_count_works_and_a_kit_without_pieces_has_none() -> void:
	for count: int in [1, 2, 4, 8]:
		var kit: TerrainKitDef = _stone_kit(count, [count - 1], 300, 6)
		for y: int in 16:
			for x: int in 16:
				assert_int(TerrainKit.variant(kit, &"grass", &"base", x, y)).is_between(
					0, count - 1
				)
	var empty: TerrainKitDef = TerrainKitDef.new()
	assert_int(TerrainKit.variant(empty, &"grass", &"base", 1, 1)).is_equal(-1)
	assert_str(TerrainKit.base_key(empty, &"grass", 1, 1)).is_equal(NONE)
	# A key with no count lists 4; a missing piece is left out of the list.
	var four: TerrainKitDef = TerrainKitDef.new()
	four.pieces = {&"sand/base/0": "a.png", &"sand/base/1": "b.png", &"sand/base/3": "c.png"}
	assert_array(Array(four.variants_of(&"sand", &"base"))).is_equal([0, 1, 3])


func test_the_base_key_names_the_variant_the_rule_picks() -> void:
	var kit: TerrainKitDef = _kit()
	for y: int in 16:
		for x: int in 16:
			var number: int = TerrainKit.variant(kit, &"grass", &"base", x, y)
			assert_str(TerrainKit.base_key(kit, &"grass", x, y)).is_equal(
				StringName("grass/base/%d" % number)
			)
