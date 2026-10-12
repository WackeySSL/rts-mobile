extends GdUnitTestSuite
## The CI side of the phone-to-CI speed ratio (plan P26s, ADR 0011 section 5): the perf probe's mock
## tick for 900 ticks and its flow slice (512 cells) for 64 calls, with the mean and p95 per call
## printed in microseconds (the phone card prints the same numbers in ms). Timing is never
## asserted: this test fails on errors and on a mock that stopped doing its work.


func test_mock_tick_and_flow_slice_are_timed_and_sane() -> void:
	var probe: PerfProbeTick = PerfProbeTick.new()
	var ticks: PackedFloat64Array = PackedFloat64Array()
	for _i: int in 900:
		ticks.append(probe.step())
	var slices: PackedFloat64Array = PackedFloat64Array()
	for _i: int in 8:  # 8 x 512 cells settle one whole 64x64 field.
		slices.append(probe.flow_slice(512))
	var reached: int = probe.flow_cost.size() - probe.flow_cost.count(PerfProbeTick.UNREACHED)
	for _i: int in 56:
		slices.append(probe.flow_slice(512))
	print("PROBE ci tick_us mean=%.1f p95=%.1f" % _stats(ticks))
	print("PROBE ci flow_slice_512_us mean=%.1f p95=%.1f" % _stats(slices))
	assert_int(reached).is_equal(3980)  # Every open tile: 4096 less the 116 ridge tiles.
	var limit: int = PerfProbeTick.COLS * 1000
	for i: int in PerfProbeTick.UNITS:
		assert_int(probe.x[i]).is_between(0, limit - 1)
		assert_int(probe.y[i]).is_between(0, limit - 1)
	var lowest: int = 0
	for count: int in probe.seen:
		lowest = mini(lowest, count)
	assert_int(lowest).is_equal(0)  # Every unstamp undoes a stamp.
	assert_int(probe.seen.count(0)).is_less(probe.seen.size())  # Some cells are in sight.


func test_the_same_start_plays_the_same_ticks() -> void:
	var a: PerfProbeTick = PerfProbeTick.new()
	var b: PerfProbeTick = PerfProbeTick.new()
	for _i: int in 300:
		a.step()
		b.step()
	assert_array(a.x).is_equal(b.x)
	assert_array(a.target).is_equal(b.target)
	assert_array(a.seen).is_equal(b.seen)


func _stats(values: PackedFloat64Array) -> Array[float]:
	return [PerfProbeTick.mean(values), PerfProbeTick.percentile(values, 95)]
