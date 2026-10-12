extends GdUnitTestSuite
## DetRandom (ADR 0007 section 7). Expected numbers are literals from
## tests/sim/reference/det_random_ref.py; its docstring says where the generator vector comes from.


func test_core_generator_matches_the_published_reference() -> void:
	var rng: DetRandom = DetRandom.new()
	rng.set_state(PackedInt64Array([1, 2, 3, 4]))
	assert_array(_draws(rng, 6)).is_equal([11520, 0, 5927040, 70819200, 2031721883, 1637235492])


func test_seeding_matches_the_python_transcription() -> void:
	assert_array(_draws(DetRandom.create(0, 1), 5)).is_equal(
		[3264697434, 147764464, 1438197714, 3292832681, 1476699434]
	)
	assert_array(_draws(DetRandom.create(42, 1), 5)).is_equal(
		[3096445245, 3376376650, 4001731811, 3693849129, 2209484441]
	)
	assert_array(_draws(DetRandom.create(7, 101), 5)).is_equal(
		[3000987990, 2895628540, 628647319, 1088727151, 1005758799]
	)
	# Seed bit 30 and stream bit 15 are set.
	assert_array(_draws(DetRandom.create(0x7FFFFFFF, 65535), 5)).is_equal(
		[2797220835, 2825680778, 2432194248, 1616142701, 1962500657]
	)


func test_mul32_equals_the_true_low_32_bits() -> void:
	assert_int(DetRandom.mul32(0xFFFFFFFF, 0xFFFFFFFF)).is_equal(1)
	assert_int(DetRandom.mul32(0xFFFFFFFF, 2)).is_equal(4294967294)
	assert_int(DetRandom.mul32(0xDEADBEEF, 0x7FEB352D)).is_equal(4084665091)


func test_rotl_rotates_within_32_bits() -> void:
	assert_int(DetRandom.rotl(0x12345678, 8)).is_equal(878082066)
	assert_int(DetRandom.rotl(0xDEADBEEF, 31)).is_equal(4015447927)
	for k: int in range(32):
		assert_int(DetRandom.rotl(0x80000000, k)).is_equal(1 << ((k + 31) % 32))


func test_streams_and_seed_masks() -> void:
	assert_int(DetRandom.STREAM_SIM).is_equal(1)
	assert_int(DetRandom.STREAM_AI_BASE).is_equal(100)
	assert_array(DetRandom.create(1, 1).state()).is_not_equal(DetRandom.create(1, 101).state())
	var base: PackedInt64Array = DetRandom.create(5, 1).state()
	assert_array(DetRandom.create((1 << 31) + 5, 1).state()).is_equal(base)
	assert_array(DetRandom.create(5, 65536 + 1).state()).is_equal(base)
	assert_array(DetRandom.create(5, 256 + 1).state()).is_not_equal(base)
	assert_array(DetRandom.create(-1, 1).state()).is_equal(DetRandom.create(0x7FFFFFFF, 1).state())


func test_a_hundred_thousand_draws_stay_below_2_pow_32() -> void:
	var rng: DetRandom = DetRandom.create(1, 1)
	var low: int = 0xFFFFFFFF
	var high: int = 0
	for i: int in range(100000):
		var value: int = rng.next_u32()
		low = mini(low, value)
		high = maxi(high, value)
	assert_int(low).is_between(0, 0x0FFFFFFF)
	assert_int(high).is_between(0xF0000000, 0xFFFFFFFF)


func test_next_int_buckets_are_even() -> void:
	var rng: DetRandom = DetRandom.create(42, 1)
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(10)
	for i: int in range(100000):
		counts[rng.next_int(10)] += 1
	for bucket: int in range(10):
		assert_int(counts[bucket]).is_between(9700, 10300)


## n = 1431655766 rejects a third of the draws (limit 2863311532 = 2^32 - 2^32 % n). A twin that
## draws again while the value is at or above the limit must agree on every result and every draw.
func test_next_int_draws_again_until_the_value_is_below_the_limit() -> void:
	var rng: DetRandom = DetRandom.create(42, 1)
	var twin: DetRandom = DetRandom.create(42, 1)
	for i: int in range(3000):
		var value: int = twin.next_u32()
		while value >= 2863311532:
			value = twin.next_u32()
		assert_int(rng.next_int(1431655766)).is_equal(value % 1431655766)
	assert_array(rng.state()).is_equal(twin.state())


## For n = 3 the limit is 0xFFFFFFFF, so a draw of exactly the limit is rejected (it would be 0).
## The first draw of this state is 0xFFFFFFFF, the second is 40319 (2 modulo 3), and no third.
func test_next_int_rejects_a_draw_equal_to_the_limit() -> void:
	var rng: DetRandom = DetRandom.new()
	rng.set_state(PackedInt64Array([1, 2199679431, 8, 7]))
	assert_int(rng.next_int(3)).is_equal(2)
	assert_array(rng.state()).is_equal([3817735191, 954437126, 2199675848, 2477699844])


func test_next_int_and_range_int_match_the_python_transcription() -> void:
	# n = 0x66666667 is 2^32 / 2.5. Draws 3 and 4 of this stream are rejected in a row.
	var rng: DetRandom = DetRandom.create(42, 1)
	var ints: Array[int] = []
	for i: int in range(8):
		ints.append(rng.next_int(1717986919))
	assert_array(ints).is_equal(
		[1378458326, 1658389731, 491497522, 229147235, 763497333, 1076119403, 407490571, 57000160]
	)
	rng = DetRandom.create(42, 1)
	var ranged: Array[int] = []
	for i: int in range(5):
		ranged.append(rng.range_int(-5, 5))
	assert_array(ranged).is_equal([-2, 4, -5, -2, 5])


func test_next_int_outside_1_to_2_pow_31_returns_0_without_drawing() -> void:
	var rng: DetRandom = DetRandom.create(3, 1)
	var before: PackedInt64Array = rng.state()
	for n: int in [0, -3, 0x80000001]:
		assert_int(rng.next_int(n)).is_equal(0)
	assert_int(rng.range_int(5, 1)).is_equal(5)
	assert_array(rng.state()).is_equal(before)
	# n = 1 and n = 2^31 are valid: each draws exactly once (2^32 is a multiple of both).
	var twin: DetRandom = DetRandom.create(3, 1)
	assert_int(rng.next_int(1)).is_equal(0)
	twin.next_u32()
	assert_array(rng.state()).is_equal(twin.state())
	# A span of one value is a draw of next_int(1) too, also through pick_random.
	assert_int(rng.range_int(7, 7)).is_equal(7)
	assert_int(rng.pick_random(PackedInt32Array([4]))).is_equal(4)
	twin.next_u32()
	twin.next_u32()
	assert_array(rng.state()).is_equal(twin.state())
	assert_int(rng.next_int(0x80000000)).is_equal(twin.next_u32() & 0x7FFFFFFF)
	assert_array(rng.state()).is_equal(twin.state())


func test_range_int_covers_both_bounds_and_nothing_else() -> void:
	var rng: DetRandom = DetRandom.create(9, 1)
	var low: int = 99
	var high: int = -99
	for i: int in range(2000):
		var value: int = rng.range_int(-5, 5)
		low = mini(low, value)
		high = maxi(high, value)
	assert_int(low).is_equal(-5)
	assert_int(high).is_equal(5)


func test_shuffle_is_the_same_permutation_for_the_same_seed() -> void:
	var values: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	DetRandom.create(42, 1).shuffle(values)
	assert_array(values).is_equal([7, 8, 2, 4, 0, 6, 9, 3, 1, 5])
	var again: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	DetRandom.create(42, 1).shuffle(again)
	assert_array(again).is_equal(values)
	var sorted: Array = Array(values)
	sorted.sort()
	assert_array(sorted).is_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	# The last swap is the one between positions 0 and 1: stream 1 makes it, stream 0 does not.
	for stream: int in [0, 1]:
		var pair: PackedInt32Array = PackedInt32Array([1, 2])
		DetRandom.create(7, stream).shuffle(pair)
		assert_array(pair).is_equal([2, 1] if stream == 1 else [1, 2])


func test_shuffle_and_pick_random_edge_cases() -> void:
	var rng: DetRandom = DetRandom.create(42, 1)
	var before: PackedInt64Array = rng.state()
	var none: PackedInt32Array = PackedInt32Array()
	var one: PackedInt32Array = PackedInt32Array([4])
	rng.shuffle(none)
	rng.shuffle(one)
	assert_int(rng.pick_random(none)).is_equal(0)
	assert_array(rng.state()).is_equal(before)
	assert_array(one).is_equal([4])
	var values: PackedInt32Array = PackedInt32Array([10, 20, 30, 40, 50])
	var picked: Array[int] = []
	for i: int in range(5):
		picked.append(rng.pick_random(values))
	assert_array(picked).is_equal([10, 10, 20, 50, 20])


func test_state_round_trips_with_words_above_2_pow_31() -> void:
	var words: PackedInt64Array = PackedInt64Array([0xFFFFFFFF, 0x80000000, 0x80000001, 0xDEADBEEF])
	var rng: DetRandom = DetRandom.new()
	rng.set_state(words)
	assert_array(rng.state()).is_equal(words)
	_draws(rng, 7)
	var twin: DetRandom = DetRandom.new()
	twin.set_state(rng.state())
	assert_array(_draws(twin, 10)).is_equal(_draws(rng, 10))
	assert_array(twin.state()).is_equal(rng.state())


func test_set_state_masks_pads_and_avoids_the_all_zero_state() -> void:
	var rng: DetRandom = DetRandom.new()
	assert_array(rng.state()).is_equal([1, 0, 0, 0])
	# Each row: the words given, then the state expected. Only a state of zeros is replaced.
	var rows: Array[Array] = [
		[[0x100000001, -1, 0x100000003, 0x100000004], [1, 0xFFFFFFFF, 3, 4]],
		[[0, 5, 0, 0], [0, 5, 0, 0]],
		[[0, 0, 6, 0], [0, 0, 6, 0]],
		[[0, 0, 0, 9], [0, 0, 0, 9]],
		[[0, 0x100000000, 0, 0], [1, 0, 0, 0]],
		[[], [1, 0, 0, 0]],
		[[7, 8], [7, 8, 0, 0]],
		[[7, 8, 9], [7, 8, 9, 0]],
	]
	for row: Array in rows:
		rng.set_state(PackedInt64Array(row[0]))
		assert_array(rng.state()).is_equal(row[1])


func _draws(rng: DetRandom, count: int) -> Array[int]:
	var drawn: Array[int] = []
	for i: int in range(count):
		drawn.append(rng.next_u32())
	return drawn
