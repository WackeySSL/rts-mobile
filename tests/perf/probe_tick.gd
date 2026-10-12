extends GdUnitTestSuite
## The CI side of the phone-to-CI speed ratio (plan P26s, ADR 0011 section 5): the perf probe's mock
## tick for 900 ticks and its flow slice (512 cells) for 64 calls, three times on fresh mocks, with
## the mean and p95 per call printed in microseconds for every run and as the minimum over the
## runs (ADR 0011 section 4; the phone card prints the same numbers in ms). Timing is never
## asserted: this test fails on errors and on a mock that stopped doing its work (units not
## moving, no targets, a flow field that does not reach every open tile).
## Spike P26n adds the C++ port (ProbeTickNative) to every run, timed the same way, with its own
## "PROBE ci cpp ..." lines and the speedup over the GDScript mock; the GDScript lines stay as were.
## The speedup is of the builds named on the "PROBE ci builds" line: the GDScript VM of the editor
## that runs the tests (a debug build, slower than a release template) against the library's
## template_debug -O2. The phone compares release GDScript with -O3, so this ratio is not that one.

const CELLS: int = 512
const NOT_LOADED: String = "ProbeTickNative not loaded: run scripts/build-native.sh"


func test_mock_tick_and_flow_slice_are_timed_and_sane() -> void:
	var best: Array[float] = [INF, INF, INF, INF]  # Tick mean and p95, slice mean and p95.
	var cpp_best: Array[float] = [INF, INF, INF, INF]  # The same for the C++ port.
	var probe: PerfProbeTick = null
	var loaded: bool = ClassDB.class_exists(PerfProbeLockstep.NATIVE_CLASS)
	assert_bool(loaded).override_failure_message(NOT_LOADED).is_true()
	var builds: String = ""  # Which two builds the C++ lines compare.
	if loaded:
		var sample: RefCounted = ClassDB.instantiate(PerfProbeLockstep.NATIVE_CLASS)
		builds = (
			"C++ %s | GDScript VM %s build"
			% [sample.get_build_info(), "debug" if OS.is_debug_build() else "release"]
		)
		print("PROBE ci builds: %s" % builds)
	for run: int in 3:
		probe = PerfProbeTick.new()
		var ticks: PackedFloat64Array = PackedFloat64Array()
		for _i: int in 900:
			ticks.append(probe.step())
		var slices: PackedFloat64Array = PackedFloat64Array()
		_time_slices(probe, 8, slices)  # 8 x 512 cells settle one whole 64x64 field.
		var reached: int = probe.flow_cost.size() - probe.flow_cost.count(PerfProbeTick.UNREACHED)
		_time_slices(probe, 56, slices)
		print("PROBE ci run=%d tick_us mean=%.1f p95=%.1f" % [run, _mean(ticks), _p95(ticks)])
		print(
			(
				"PROBE ci run=%d flow_slice_512_us mean=%.1f p95=%.1f"
				% [run, _mean(slices), _p95(slices)]
			)
		)
		best[0] = minf(best[0], _mean(ticks))
		best[1] = minf(best[1], _p95(ticks))
		best[2] = minf(best[2], _mean(slices))
		best[3] = minf(best[3], _p95(slices))
		assert_int(reached).is_equal(3980)  # Every open tile: 4096 less the 116 ridge tiles.
		assert_int(slices.size()).is_equal(56)  # 8 field ends in 64 calls; a short slice is dropped.
		if loaded:
			_time_cpp(run, cpp_best)
	print("PROBE ci min-of-3 tick_us mean=%.1f p95=%.1f" % [best[0], best[1]])
	print("PROBE ci min-of-3 flow_slice_512_us mean=%.1f p95=%.1f" % [best[2], best[3]])
	if loaded:
		print(
			(
				"PROBE ci cpp min-of-3 tick_us mean=%.1f p95=%.1f | %s"
				% [cpp_best[0], cpp_best[1], builds]
			)
		)
		print(
			(
				"PROBE ci cpp min-of-3 flow_slice_512_us mean=%.1f p95=%.1f | %s"
				% [cpp_best[2], cpp_best[3], builds]
			)
		)
		print(
			(
				"PROBE ci cpp speedup tick_us mean %.1fx p95 %.1fx | %s"
				% [best[0] / cpp_best[0], best[1] / cpp_best[1], builds]
			)
		)
		print(
			(
				"PROBE ci cpp speedup flow_slice_512_us mean %.1fx p95 %.1fx | %s"
				% [best[2] / cpp_best[2], best[3] / cpp_best[3], builds]
			)
		)
	var limit: int = PerfProbeTick.COLS * 1000
	for i: int in PerfProbeTick.UNITS:
		assert_int(probe.x[i]).is_between(0, limit - 1)
		assert_int(probe.y[i]).is_between(0, limit - 1)
	var lowest: int = 0
	for count: int in probe.seen:
		lowest = mini(lowest, count)
	assert_int(lowest).is_equal(0)  # Every unstamp undoes a stamp.
	assert_int(probe.seen.count(0)).is_less(probe.seen.size())  # Some cells are in sight.
	assert_int(probe.target.count(-1)).is_less(PerfProbeTick.UNITS)  # Targeting finds enemies.
	var before: PackedInt32Array = probe.x.duplicate()
	probe.step()
	assert_bool(probe.x == before).is_false()  # Units are moving.


func test_the_same_start_plays_the_same_ticks() -> void:
	var a: PerfProbeTick = PerfProbeTick.new()
	var b: PerfProbeTick = PerfProbeTick.new()
	for _i: int in 300:
		a.step()
		b.step()
	assert_array(a.x).is_equal(b.x)
	assert_array(a.target).is_equal(b.target)
	assert_array(a.seen).is_equal(b.seen)


## One run of the same method on a fresh C++ port (900 ticks, then 64 flow slices of 512 cells),
## printed per run; `best` keeps the minimum over the runs.
func _time_cpp(run: int, best: Array[float]) -> void:
	var cpp: RefCounted = ClassDB.instantiate(PerfProbeLockstep.NATIVE_CLASS)
	var ticks: PackedFloat64Array = PackedFloat64Array()
	for _i: int in 900:
		ticks.append(cpp.step())
	var slices: PackedFloat64Array = PackedFloat64Array()
	_time_slices(cpp, 8, slices)
	var flow_cost: PackedInt32Array = cpp.flow_cost
	var reached: int = flow_cost.size() - flow_cost.count(PerfProbeTick.UNREACHED)
	_time_slices(cpp, 56, slices)
	print("PROBE ci cpp run=%d tick_us mean=%.1f p95=%.1f" % [run, _mean(ticks), _p95(ticks)])
	print(
		(
			"PROBE ci cpp run=%d flow_slice_512_us mean=%.1f p95=%.1f"
			% [run, _mean(slices), _p95(slices)]
		)
	)
	best[0] = minf(best[0], _mean(ticks))
	best[1] = minf(best[1], _p95(ticks))
	best[2] = minf(best[2], _mean(slices))
	best[3] = minf(best[3], _p95(slices))
	assert_int(reached).is_equal(3980)
	assert_int(slices.size()).is_equal(56)


## Times `calls` flow slices into `into`; the short slice that ends a field is left out.
func _time_slices(probe: RefCounted, calls: int, into: PackedFloat64Array) -> void:
	for _i: int in calls:
		var elapsed: int = probe.flow_slice(CELLS)
		if probe.slice_cells == CELLS:
			into.append(elapsed)


func _mean(values: PackedFloat64Array) -> float:
	return PerfProbeTick.mean(values)


func _p95(values: PackedFloat64Array) -> float:
	return PerfProbeTick.percentile(values, 95)
