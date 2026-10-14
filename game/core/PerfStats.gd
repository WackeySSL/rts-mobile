class_name PerfStats
extends RefCounted
## The statistics that tests/perf and the perf card share (ADR 0011 section 5, ADR 0012 section 4):
## nearest-rank percentiles, the mean and the worst window. Pure static functions over sample
## arrays; an empty array gives 0.0.

## The nearest-rank `p`-th percentile (p clamped to 0..100) of `sorted`, which is in ascending
## order: the value at rank ceil(p / 100 * n), at least rank 1, so p 0 is the smallest value and
## p 100 the largest. The rank is integer arithmetic, so no float rounding moves it.
@warning_ignore("integer_division")
static func percentile(sorted: PackedFloat64Array, p: int) -> float:
	var n: int = sorted.size()
	if n == 0:
		return 0.0
	var rank: int = (clampi(p, 0, 100) * n + 99) / 100
	return sorted[maxi(rank, 1) - 1]


## The arithmetic mean of `values`.
static func mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / values.size()


## The largest sum of `window` consecutive values. A series shorter than the window gives its
## whole sum; a window below 1 gives 0.0.
static func worst_window_sum(values: PackedFloat64Array, window: int) -> float:
	var n: int = values.size()
	if n == 0 or window < 1:
		return 0.0
	var width: int = mini(window, n)
	var sum: float = 0.0
	for i: int in width:
		sum += values[i]
	var worst: float = sum
	for i: int in range(width, n):
		sum += values[i] - values[i - width]
		worst = maxf(worst, sum)
	return worst
