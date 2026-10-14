extends GdUnitTestSuite
## PerfStats (plan P38t): nearest-rank percentiles, the mean and the worst window on small literal
## samples, worked by hand.


## Nearest rank: the value at rank ceil(p / 100 * n), at least 1. On ten values p 10 is rank 1 and
## p 11 rank 2, p 90 rank 9 and p 91 rank 10. On five values (the textbook case) p 30 and p 40
## share rank 2.
func test_percentile_takes_the_nearest_rank() -> void:
	var ten: PackedFloat64Array = PackedFloat64Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var expected: Dictionary[int, float] = {
		0: 1.0,
		1: 1.0,
		10: 1.0,
		11: 2.0,
		25: 3.0,
		50: 5.0,
		51: 6.0,
		90: 9.0,
		91: 10.0,
		95: 10.0,
		100: 10.0
	}
	for p: int in expected:
		assert_float(PerfStats.percentile(ten, p)).override_failure_message(str(p)).is_equal(
			expected[p]
		)
	var five: PackedFloat64Array = PackedFloat64Array([15.0, 20.0, 35.0, 40.0, 50.0])
	var got: Array[float] = []
	for p: int in [5, 30, 40, 50, 95, 100]:
		got.append(PerfStats.percentile(five, p))
	assert_array(got).is_equal([15.0, 20.0, 20.0, 35.0, 50.0, 50.0])


## The rank is integer arithmetic. On 100 values p 7 is rank 7, where the float product
## 7 / 100.0 * 100 is 7.000000000000001 and would round up to rank 8 (also p 14, 28, 55 and 56).
## p 95 of 20 values is rank 19. Out-of-range p clamps; one value is every percentile; no values
## give 0.0.
func test_percentile_edges() -> void:
	var hundred: PackedFloat64Array = PackedFloat64Array()
	for i: int in 100:
		hundred.append(float(i + 1))
	for p: int in [7, 14, 28, 55, 56]:
		assert_float(PerfStats.percentile(hundred, p)).is_equal(float(p))
	var twenty: PackedFloat64Array = hundred.slice(0, 20)
	assert_float(PerfStats.percentile(twenty, 95)).is_equal(19.0)
	assert_float(PerfStats.percentile(twenty, 99)).is_equal(20.0)
	assert_float(PerfStats.percentile(twenty, -5)).is_equal(1.0)
	assert_float(PerfStats.percentile(twenty, 250)).is_equal(20.0)
	var one: PackedFloat64Array = PackedFloat64Array([7.5])
	for p: int in [0, 50, 100]:
		assert_float(PerfStats.percentile(one, p)).is_equal(7.5)
	assert_float(PerfStats.percentile(PackedFloat64Array(), 50)).is_equal(0.0)


func test_mean_is_the_sum_over_the_count() -> void:
	assert_float(PerfStats.mean(PackedFloat64Array([1.5, 2.5, 3.5]))).is_equal(2.5)
	assert_float(PerfStats.mean(PackedFloat64Array([4.0, 0.0, 0.0, 0.0]))).is_equal(1.0)
	assert_float(PerfStats.mean(PackedFloat64Array([-2.0, 6.0]))).is_equal(2.0)
	assert_float(PerfStats.mean(PackedFloat64Array())).is_equal(0.0)


## The largest sum of `window` consecutive values, wherever it lies: at the start, in the middle
## or at the end. A window as long as the series, or longer, is the whole sum; below 1 it is 0.
func test_worst_window_sum_finds_the_heaviest_run_of_values() -> void:
	var values: PackedFloat64Array = PackedFloat64Array([1, 5, 2, 8, 1, 1])
	var expected: Dictionary[int, float] = {1: 8.0, 2: 10.0, 3: 15.0, 4: 16.0, 6: 18.0, 9: 18.0}
	for window: int in expected:
		(
			assert_float(PerfStats.worst_window_sum(values, window))
			. override_failure_message(str(window))
			. is_equal(expected[window])
		)
	# The heaviest window first, and last.
	var first: PackedFloat64Array = PackedFloat64Array([9, 9, 1, 1, 1])
	var last: PackedFloat64Array = PackedFloat64Array([1, 1, 1, 9, 9])
	assert_float(PerfStats.worst_window_sum(first, 2)).is_equal(18.0)
	assert_float(PerfStats.worst_window_sum(last, 2)).is_equal(18.0)
	# Negative values (a sum may fall) and the empty cases.
	var dips: PackedFloat64Array = PackedFloat64Array([-1, -4, -2, -3])
	assert_float(PerfStats.worst_window_sum(dips, 2)).is_equal(-5.0)
	assert_float(PerfStats.worst_window_sum(values, 0)).is_equal(0.0)
	assert_float(PerfStats.worst_window_sum(PackedFloat64Array(), 3)).is_equal(0.0)
