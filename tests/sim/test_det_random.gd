extends GdUnitTestSuite
## DetRandom (ADR 0007 section 7). Expected numbers are literals: the generator vector comes
## from Vigna's xoshiro128starstar.c, every other one from tests/sim/reference/det_random_ref.py.


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


func test_mul32_equals_the_true_low_32_bits() -> void:
	assert_int(DetRandom.mul32(0xFFFFFFFF, 0xFFFFFFFF)).is_equal(1)
	assert_int(DetRandom.mul32(0xFFFFFFFF, 2)).is_equal(4294967294)
	assert_int(DetRandom.mul32(0xDEADBEEF, 0x7FEB352D)).is_equal(4084665091)
	# Operands below 2^31 and 2^32 give products below 2^63, so the engine product is exact.
	var rng: DetRandom = DetRandom.create(5, 1)
	for i: int in range(2000):
		var a: int = rng.next_u32() >> 1
		var b: int = rng.next_u32()
		assert_int(DetRandom.mul32(a, b)).is_equal((a * b) & 0xFFFFFFFF)


func test_rotl_rotates_within_32_bits() -> void:
	assert_int(DetRandom.rotl(0x12345678, 8)).is_equal(878082066)
	assert_int(DetRandom.rotl(0xDEADBEEF, 31)).is_equal(4015447927)
	for k: int in range(32):
		assert_int(DetRandom.rotl(0x80000000, k)).is_equal(1 << ((k + 31) % 32))


func test_streams_and_seed_masks() -> void:
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


## n = 0x66666667 is 2^32 / 2.5. Without rejection the residues below 858993458 would be hit
## 3 times in 5 instead of 1 in 2.
func test_next_int_rejects_the_biased_tail() -> void:
	var rng: DetRandom = DetRandom.create(42, 1)
	var below: int = 0
	for i: int in range(20000):
		if rng.next_int(1717986919) < 858993459:
			below += 1
	assert_int(below).is_between(9500, 10500)


func test_next_int_and_range_int_match_the_python_transcription() -> void:
	var rng: DetRandom = DetRandom.create(42, 1)
	var ints: Array[int] = []
	for i: int in range(5):
		ints.append(rng.next_int(1000))
	assert_array(ints).is_equal([245, 650, 811, 129, 441])
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


## The last swap of a shuffle is the one between positions 0 and 1.
func test_shuffle_of_two_values_swaps_for_about_half_of_the_seeds() -> void:
	var swapped: int = 0
	for stream: int in range(40):
		var pair: PackedInt32Array = PackedInt32Array([1, 2])
		DetRandom.create(7, stream).shuffle(pair)
		swapped += 1 if pair[0] == 2 else 0
	assert_int(swapped).is_between(10, 30)


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
	rng.set_state(PackedInt64Array([0x100000001, -1, 5, 6]))
	assert_array(rng.state()).is_equal([1, 0xFFFFFFFF, 5, 6])
	rng.set_state(PackedInt64Array([5]))
	assert_array(rng.state()).is_equal([5, 0, 0, 0])
	rng.set_state(PackedInt64Array([0, 0x100000000, 0, 0]))
	assert_array(rng.state()).is_equal([1, 0, 0, 0])


func _draws(rng: DetRandom, count: int) -> Array[int]:
	var drawn: Array[int] = []
	for i: int in range(count):
		drawn.append(rng.next_u32())
	return drawn
