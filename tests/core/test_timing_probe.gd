extends GdUnitTestSuite
## TimingProbe, PerfGateDef and RefLoop (plan P38t; ADR 0012 section 4 as ADR 0014 changes it).
## The probe's times are checked against clock reads taken around each call, so the real probe
## always passes and only a wrong one can fail, whatever the machine's load.

const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## Long enough that a time measured from the wrong start lies far outside the bounds.
const WAIT_USEC: int = 3000
## PerfGateDef's defaults, literally: the contract row with ADR 0014's changes (revision 15). The
## types count: an int field stays an int in perf_gate.tres.
const GATE: Dictionary = {
	"heavy_rigs": 135,
	"heavy_frames_min": 600,
	"work_p95_ms": 5.6,
	"work_tick_p95_ms": 5.6,
	"sim_p95_ms": 13.3,
	"job_p99_ms": 26.7,
	"late_ticks_max": 0,
	"fog_update_p95_ms": 0.4,
	"draw_calls_max": 60,
	"release_only": true,
	"ci_ratio_mean": 4.4,
	"ci_ratio_p95": 5.9,
	"drop_slots": 0.5,
	"dropped_pct_max": 1.0,
	"cadence_pct_min": 99.0,
	"hitches_max": 0,
	"jitter_ms": 17.5,
	"median_tolerance_pct": 2.0,
	"refresh_tolerance_pct": 1.0,
	"ref_iterations": 1000,
	"ref_burst_ms": 400,
}


func after_test() -> void:
	CommandQueue.clear()


func test_phase_usec_has_one_entry_per_phase_all_zero() -> void:
	var timing: TimingProbe = TimingProbe.new()
	assert_int(timing.phase_usec.size()).is_equal(SimProbe.Phase.COUNT)
	assert_int(timing.phase_usec.count(0)).is_equal(SimProbe.Phase.COUNT)


## begin(), then COMMANDS, then REMOVE, with a wait before each mark: the time from begin() to
## the first mark goes to COMMANDS, the time between the two marks to REMOVE, and every other phase
## reads 0. A REMOVE timed from begin() would include the first wait and exceed its upper bound.
## The next begin() sets every phase back to 0.
func test_fake_marks_put_the_time_between_two_marks_under_the_later_phase() -> void:
	var timing: TimingProbe = TimingProbe.new()
	var t0: int = Time.get_ticks_usec()
	timing.begin()
	var t1: int = Time.get_ticks_usec()
	_busy(WAIT_USEC)
	var t2: int = Time.get_ticks_usec()
	timing.mark(SimProbe.Phase.COMMANDS)
	var t3: int = Time.get_ticks_usec()
	_busy(WAIT_USEC)
	var t4: int = Time.get_ticks_usec()
	timing.mark(SimProbe.Phase.REMOVE)
	var t5: int = Time.get_ticks_usec()
	var commands: int = timing.phase_usec[SimProbe.Phase.COMMANDS]
	var remove: int = timing.phase_usec[SimProbe.Phase.REMOVE]
	assert_int(commands).is_between(t2 - t1, t3 - t0)
	assert_int(remove).is_between(t4 - t3, t5 - t2)
	assert_int(timing.phase_usec.count(0)).is_equal(SimProbe.Phase.COUNT - 2)
	timing.begin()
	assert_int(timing.phase_usec.count(0)).is_equal(SimProbe.Phase.COUNT)


## As the runner's probe it gets every begin() and mark() of Sim.step through the runner's
## StepProbe, which begins after it and marks before it: so the phases add up to at least
## last_tick_usec (Sim.step alone) and at most last_runner_tick_usec (the whole tick). The phases
## Sim.step marks (read from a RecordingProbe on a plain MatchLoop) are at least 0; every other one
## reads 0 on every tick, although the test leaves -7 in every phase before each tick.
func test_on_the_runner_it_times_the_marked_phases_and_zeroes_the_rest_each_tick() -> void:
	var marked: PackedInt32Array = _marked_phases()
	assert_bool(marked.has(SimProbe.Phase.COMMANDS)).is_true()
	var runner: MatchRunner = _arena_runner()
	var timing: TimingProbe = TimingProbe.new()
	runner.probe = timing
	for _tick: int in 20:
		timing.phase_usec.fill(-7)
		runner.run_ticks(1)
		var label: String = str(runner.world.tick)
		var sum: int = 0
		for phase: int in SimProbe.Phase.COUNT:
			var usec: int = timing.phase_usec[phase]
			if marked.has(phase):
				assert_int(usec).override_failure_message(label).is_greater_equal(0)
			else:
				assert_int(usec).override_failure_message(label).is_equal(0)
			sum += usec
		assert_int(runner.last_tick_usec).override_failure_message(label).is_greater(0)
		assert_int(sum).override_failure_message(label).is_between(
			runner.last_tick_usec, runner.last_runner_tick_usec
		)


## The probe reads only the clock: the arena with seed 42 for 45 ticks gives the same 15-tick
## checkpoints with a TimingProbe on the runner as a MatchLoop without any probe.
func test_the_checkpoints_with_a_timing_probe_equal_a_run_without_it() -> void:
	var runner: MatchRunner = _arena_runner()
	runner.probe = TimingProbe.new()
	runner.run_ticks(45)
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 42, world)
	var none: Array[Command] = []
	for _tick: int in 45:
		loop.step(world, none)
	assert_array(runner.replay.checkpoint_ticks).is_equal(PackedInt32Array([15, 30, 45]))
	assert_array(runner.replay.checkpoint_hashes).is_equal(loop.replay.checkpoint_hashes)
	assert_int(runner.world.state_hash()).is_equal(world.state_hash())


## PerfGateDef.new() holds the contract's values with their types, exported so perf_gate.tres
## stores them, empty golden arrays, and no other field: ADR 0014 dropped on_time_ms and
## on_time_share_pct.
func test_the_gate_def_defaults_are_the_contract_values() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	var names: Array[String] = []
	for property: Dictionary in gate.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
			var stored: bool = (property["usage"] & PROPERTY_USAGE_STORAGE) != 0
			assert_bool(stored).override_failure_message(property["name"]).is_true()
	for name: String in GATE:
		var value: Variant = gate.get(name)
		assert_int(typeof(value)).override_failure_message(name).is_equal(typeof(GATE[name]))
		assert_bool(value == GATE[name]).override_failure_message(name).is_true()
	assert_array(gate.golden_ticks).is_empty()
	assert_array(gate.golden_hex).is_empty()
	var expected: Array[String] = ["golden_ticks", "golden_hex"]
	for name: String in GATE:
		expected.append(name)
	expected.sort()
	names.sort()
	assert_array(names).is_equal(expected)


## The per-frame method of ADR 0014 (calibration 2026-10-13): the p95 over frames of
## work_i x min(1, peak / sample_i). Twenty frames, peak 20: seventeen of work 1 at the peak's
## speed, one of work 12 at half speed (6), one of work 7 sampled faster than the peak (clamped to
## 7, not 14) and one of work 30 at a quarter speed (7.5). Sorted, rank 19 is 7. The raw p95 is 12,
## the class method (raw p95 x min(1, peak / p25 of the samples), p25 = 20) gives 12 too, and
## without the clamp the p95 is 7.5.
func test_ref_loop_normalises_each_frame_by_its_own_sample() -> void:
	var work: PackedFloat64Array = PackedFloat64Array()
	var samples: PackedFloat64Array = PackedFloat64Array()
	for _i: int in 20:
		work.append(1.0)
		samples.append(20.0)
	work[0] = 30.0
	samples[0] = 80.0
	work[3] = 12.0
	samples[3] = 40.0
	work[10] = 7.0
	samples[10] = 10.0
	assert_float(RefLoop.normalised_p95(work, samples, 20.0)).is_equal(7.0)
	var raw: PackedFloat64Array = work.duplicate()
	raw.sort()
	assert_float(PerfStats.percentile(raw, 95)).is_equal(12.0)
	# Without a peak, or without a frame's sample, the raw value stays.
	assert_float(RefLoop.normalised_p95(work, samples, 0.0)).is_equal(12.0)
	assert_float(RefLoop.normalised_p95(work, PackedFloat64Array(), 20.0)).is_equal(12.0)
	# Frame 3 without a sample keeps its 12, so rank 19 is frame 0's 7.5.
	samples[3] = 0.0
	assert_float(RefLoop.normalised_p95(work, samples, 20.0)).is_equal(7.5)
	assert_float(RefLoop.normalised_p95(PackedFloat64Array(), samples, 20.0)).is_equal(0.0)


## The fixed loop: acc = (acc * 31 + i) & 0xFFFFFF from 1. Pinned, so the reference work behind
## ref_peak and every frame sample never changes silently.
func test_ref_loop_run_is_the_fixed_integer_loop() -> void:
	assert_int(RefLoop.run(0)).is_equal(1)
	assert_int(RefLoop.run(3)).is_equal(29824)
	var iterations: int = PerfGateDef.new().ref_iterations
	assert_int(RefLoop.run(iterations)).is_equal(16346357)


## The phases Sim.step marks on one tick of the arena, in id order.
func _marked_phases() -> PackedInt32Array:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 42, world)
	var recording: SimProbe = RecordingProbe.new()
	var none: Array[Command] = []
	loop.step(world, none, recording)
	var marked: PackedInt32Array = PackedInt32Array()
	for call: int in recording.calls:
		if call >= 0:
			marked.append(call)
	return marked


func _arena_runner() -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = 42
	runner.start()
	return runner


## Waits `usec` microseconds on the clock.
func _busy(usec: int) -> void:
	var until: int = Time.get_ticks_usec() + usec
	while Time.get_ticks_usec() < until:
		pass
