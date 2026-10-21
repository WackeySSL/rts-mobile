extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0014 section 3), the preflight: `preflight(runner)` reads the
## runner's job state once and hands it to `run_preflight`, which asks the pure `preflight_allowed`.
## With a job in flight no seam is called and the run is INVALID with a reason, never an error (a
## test that logged `ERROR:` would fail gdUnit4 and verify.sh, so none does); otherwise the burst
## seam's kept samples give `ref_peak_us` (p25) and `ref_peak_p95_us`. `restart()` keeps the
## results and only the next preflight replaces them. The self-check seam and its order before the
## burst are P50a2's. Samples: test_perf_hud.gd. Verdicts: test_perf_hud_verdicts.gd.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")

var _calls: Array[String] = []
var _t: int = 0
var _reads: int = 0
var _runners: Array[MatchRunner] = []


func after_test() -> void:
	for runner: MatchRunner in _runners:
		if is_instance_valid(runner):
			assert_bool(runner.wait_idle()).is_true()  # No worker job outlives its case.
	_runners.clear()
	_calls.clear()
	CommandQueue.clear()


func test_a_preflight_is_allowed_only_without_a_job_in_flight() -> void:
	assert_bool(PerfHud.preflight_allowed(false)).is_true()
	assert_bool(PerfHud.preflight_allowed(true)).is_false()


func test_the_burst_seam_gives_ref_peak_from_the_p25_and_p95_of_its_kept_samples() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	var kept: PackedFloat64Array = PackedFloat64Array()
	for us: int in [40, 22, 31, 20, 36, 28, 25, 39, 21, 33, 27, 30, 24, 38, 23, 35, 26, 32, 29, 37]:
		kept.append(us)
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return kept
	hud.run_preflight(false, true)
	var s: Dictionary = hud.summary()
	assert_array(_calls).is_equal(["burst"])
	assert_float(s["ref_peak_us"]).is_equal(24.0)  # Rank 5 of 20.
	assert_float(s["ref_peak_p95_us"]).is_equal(39.0)  # Rank 19.
	assert_bool(s["invalid"]).is_false()
	assert_array(s["invalid_reasons"]).is_empty()
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return PackedFloat64Array([50.0])
	hud.run_preflight(false, true)  # The next preflight replaces the results.
	assert_float(hud.summary()["ref_peak_us"]).is_equal(50.0)
	assert_array(_calls).is_equal(["burst", "burst"])


func test_a_job_in_flight_refuses_the_preflight_and_marks_the_run_invalid() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return PackedFloat64Array([99.0])
	hud.run_preflight(true, true)
	var s: Dictionary = hud.summary()
	assert_array(_calls).is_empty()  # No seam was called.
	assert_bool(s["invalid"]).is_true()
	assert_array(s["invalid_reasons"]).is_equal(["preflight_job_in_flight"])
	assert_float(s["ref_peak_us"]).is_equal(0.0)  # The refused call dropped the old results too.
	assert_str(s["verdicts"][0]).is_equal("INVALID: preflight_job_in_flight")
	assert_bool(s["gate_pass"]).is_false()  # A run that passed everything else.
	assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")
	hud.run_preflight(false, true)  # A later preflight that runs clears the reason.
	assert_array(_calls).is_equal(["burst"])
	assert_bool(hud.summary()["invalid"]).is_false()
	assert_float(hud.summary()["ref_peak_us"]).is_equal(99.0)


func test_a_seam_that_is_not_set_is_skipped() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	hud.burst_step = Callable()
	hud.run_preflight(false, true)
	var s: Dictionary = hud.summary()
	assert_float(s["ref_peak_us"]).is_equal(0.0)
	assert_bool(s["invalid"]).is_false()


func test_restart_keeps_the_preflight_results_and_clears_the_samples() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	assert_int(hud.summary()["frames"]).is_equal(1000)
	hud.restart()
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(0)
	assert_float(s["ref_peak_us"]).is_equal(25.0)
	assert_float(s["ref_peak_p95_us"]).is_equal(25.0)
	hud.run_preflight(true, true)  # A refusal is kept too, until the next preflight.
	hud.restart()
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["preflight_job_in_flight"])
	hud.run_preflight(false, true)
	hud.restart()
	assert_bool(hud.summary()["invalid"]).is_false()
	assert_float(hud.summary()["ref_peak_us"]).is_equal(25.0)


func test_preflight_reads_the_runner_and_runs_the_burst_on_an_idle_runner() -> void:
	var runner: MatchRunner = _arena_runner(MatchRunner.TickMode.SYNC)
	var hud: PerfHud = auto_free(Rig.hud())
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return Rig.BURST
	hud.preflight(runner)
	assert_array(_calls).is_equal(["burst"])
	runner.run_ticks(2)
	hud.preflight(runner, false)
	assert_array(_calls).is_equal(["burst", "burst"])
	assert_bool(hud.summary()["invalid"]).is_false()


func test_a_worker_job_in_flight_refuses_the_preflight_through_the_real_runner() -> void:
	var runner: MatchRunner = _arena_runner(MatchRunner.TickMode.WORKER)
	var hud: PerfHud = auto_free(Rig.hud())
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return Rig.BURST
	hud.preflight(runner)  # No job yet: the match was started and nothing posted.
	assert_array(_calls).is_equal(["burst"])
	runner._process(1.0 / 60.0)  # The refill: the worker has its first job.
	assert_bool(runner.job_in_flight()).is_true()
	hud.preflight(runner)
	assert_array(_calls).is_equal(["burst"])  # Refused: the seam was not called again.
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["preflight_job_in_flight"])
	assert_bool(runner.wait_idle()).is_true()  # The "Run again" order: idle first.
	assert_bool(runner.job_in_flight()).is_false()
	hud.preflight(runner, false)
	assert_array(_calls).is_equal(["burst", "burst"])
	assert_bool(hud.summary()["invalid"]).is_false()


func test_the_default_burst_keeps_the_second_half_of_its_back_to_back_runs() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	hud.gate.ref_burst_ms = 20
	hud.gate.ref_iterations = 7
	hud.ref_step = func(iterations: int) -> void: _calls.append("ref %d" % iterations)
	# The clock reads the start, then 1000 runs of 10 us (the first 10 ms), then runs of 20 us.
	hud.clock = func() -> int:
		_reads += 1
		_t += 10 if _reads <= 1001 else 20
		return _t
	var kept: PackedFloat64Array = hud.burst_step.call()
	# The runs that begin in the second 10 ms are the kept ones: 500 runs of 20 us, not the 1000
	# runs of 10 us of the first half.
	assert_int(kept.size()).is_equal(500)
	assert_float(kept[0]).is_equal(20.0)
	assert_float(kept[kept.size() - 1]).is_equal(20.0)
	assert_int(_calls.size()).is_equal(1500)  # Every run of the burst, kept or not,
	assert_str(_calls[0]).is_equal("ref 7")  # on the gate's ref_iterations.
	# The real clock: the default seam fills ref_peak with the time of a RefLoop run.
	var real: PerfHud = auto_free(PerfHud.new())
	real.gate.ref_burst_ms = 10
	real.run_preflight(false, true)
	assert_float(real.summary()["ref_peak_us"]).is_greater(0.0)
	assert_float(real.summary()["ref_peak_p95_us"]).is_greater_equal(real.summary()["ref_peak_us"])


## A runner on the seed-42 perf arena, started, in `mode` (WORKER is explicit, as the worker suites
## set it), joined by after_test() and freed with the case.
func _arena_runner(mode: int) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.tick_mode = mode
	runner.start()
	_runners.append(runner)
	return runner
