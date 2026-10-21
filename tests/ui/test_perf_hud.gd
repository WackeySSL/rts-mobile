extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0012 section 4, ADR 0014), the samples: injected frame, work,
## tick and drawn-rig samples give the right percentiles (through PerfStats), pacing shares, heavy
## window counts and averages; the live path times a frame with a scripted clock; a runner run
## installs the probe and reads only the published snapshot; `summary()` holds every key and
## `restart()` resets every sample. The verdicts are in test_perf_hud_verdicts.gd (the lines), in
## test_perf_hud_gate.gd (the gate's fields and the windows) and in test_perf_hud_norm.gd (the
## per-frame normalisation), the live path and `restart()` in depth in test_perf_hud_live.gd and the
## preflight in test_perf_hud_preflight.gd (gdlint allows 20 public methods per file). Nothing here
## logs an error: gdUnit4 fails a test that does (`push_error`), and so does verify.sh. Headless
## Godot draws no frame and so never emits `frame_pre_draw` or `frame_post_draw`: the cases that
## need a frame call `_process`, `_on_pre_draw` and `_on_post_draw` themselves.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
## Every key P50a's summary holds: the plan's "Perf arena" row with ADR 0014 section 4's renames
## and additions, then P50a2's golden, implementation and ADR 0013 section 15 keys.
const KEYS: PackedStringArray = [
	"runs",
	"frames",
	"fps_avg",
	"frame_p50_ms",
	"frame_p95_ms",
	"frame_p99_ms",
	"frame_max_ms",
	"jitter_pct",
	"heavy_jitter_pct",
	"heavy_frames",
	"heavy_publish_frames",
	"fog_updates",
	"job_ticks",
	"finished",
	"invalid_reasons",
	"refresh_hz_start",
	"refresh_hz_end",
	"period_ms",
	"drop_ms",
	"dropped",
	"dropped_pct",
	"heavy_dropped",
	"heavy_dropped_pct",
	"cadence_pct",
	"heavy_cadence_pct",
	"hitches",
	"heavy_hitches",
	"extra_slots",
	"work_p95_ms",
	"work_tick_p95_ms",
	"work_other_p95_ms",
	"work_p95_norm_ms",
	"work_tick_p95_norm_ms",
	"work_other_p95_norm_ms",
	"fog_update_p95_ms",
	"fog_update_p95_norm_ms",
	"view_p95_ms",
	"render_cpu_p95_ms",
	"draw_calls_p95",
	"drawn_rigs_p50",
	"drawn_rigs_max",
	"ref_peak_us",
	"ref_peak_p95_us",
	"speed_main_pct",
	"speed_tick_pct",
	"speed_fog_pct",
	"tick_p50_ms",
	"tick_p95_ms",
	"tick_max_ms",
	"job_mean_ms",
	"job_p50_ms",
	"job_p95_ms",
	"job_p99_ms",
	"job_max_ms",
	"late_ticks",
	"held_ticks",
	"latency_usec_max",
	"flow_slice_p95_ms",
	"phases_ms",
	"tick_mode",
	"alive",
	"hash_hex",
	"checkpoints",
	"golden_match",
	"golden_checked",
	"golden_mismatch_tick",
	"sim_impl",
	"native_phases",
	"self_check",
	"phases_p95_noncp_ms",
	"job_p95_noncp_ms",
	"job_minus_step_p95_cp_ms",
	"job_minus_step_p95_noncp_ms",
	"invalid",
	"layer_mode",
	"screen",
	"zoom",
	"model",
	"os",
	"engine",
	"debug",
	"verdicts",
	"gate_pass",
]
## Keys the renames replaced.
const GONE: PackedStringArray = ["on_time_pct", "heavy_on_time_pct", "refresh_hz"]

## The scripted clock of the live-path cases: each call returns the next time of the script.
var _times: Array[int] = []
var _log: Array[String] = []


func after_test() -> void:
	_times.clear()
	_log.clear()
	CommandQueue.clear()


func test_frame_samples_give_percentiles_pacing_shares_and_the_heavy_window() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.frames(hud, 50, {"interval": 16000})  # Heavy.
	Rig.frames(hud, 10, {"interval": 30000})  # Heavy and dropped (above 25.0 ms).
	Rig.frames(hud, 40, {"interval": 16000, "rigs": 100})  # Not heavy.
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(100)
	assert_float(s["frame_p50_ms"]).is_equal(16.0)
	assert_float(s["frame_p95_ms"]).is_equal(30.0)  # Rank 95 of 100.
	assert_float(s["frame_p99_ms"]).is_equal(30.0)
	assert_float(s["frame_max_ms"]).is_equal(30.0)
	assert_float(s["fps_avg"]).is_equal_approx(1000.0 / 17.4, 0.001)  # Mean interval 17.4 ms.
	assert_float(s["period_ms"]).is_equal_approx(1000.0 / 60.0, 0.0001)
	assert_float(s["drop_ms"]).is_equal_approx(25.0, 0.0001)  # P + 0.5 slot.
	assert_int(s["dropped"]).is_equal(10)
	assert_float(s["dropped_pct"]).is_equal_approx(10.0, 0.0001)
	assert_int(s["heavy_frames"]).is_equal(60)
	assert_int(s["heavy_dropped"]).is_equal(10)
	assert_float(s["heavy_dropped_pct"]).is_equal_approx(100.0 / 6.0, 0.0001)
	assert_float(s["cadence_pct"]).is_equal_approx(100.0 * (1000.0 / 60.0) / 17.4, 0.0001)
	var heavy_mean: float = (50.0 * 16.0 + 10.0 * 30.0) / 60.0
	assert_float(s["heavy_cadence_pct"]).is_equal_approx(
		100.0 * (1000.0 / 60.0) / heavy_mean, 0.0001
	)
	assert_float(s["jitter_pct"]).is_equal_approx(90.0, 0.0001)  # Up to 17.5 ms.
	assert_float(s["heavy_jitter_pct"]).is_equal_approx(100.0 * 50.0 / 60.0, 0.0001)
	assert_array(s["extra_slots"]).is_equal([90, 10, 0, 0])
	assert_int(s["drawn_rigs_p50"]).is_equal(140)  # 40 frames of 100 rigs, then 60 of 140.
	assert_int(s["drawn_rigs_max"]).is_equal(140)
	assert_int(s["hitches"]).is_equal(0)
	assert_float(s["view_p95_ms"]).is_equal_approx(3.0, 0.0001)  # The process time alone,
	assert_float(s["render_cpu_p95_ms"]).is_equal_approx(1.0, 0.0001)  # the render CPU alone,
	assert_float(s["work_p95_ms"]).is_equal_approx(4.0, 0.0001)  # and their sum is the work.
	assert_int(s["draw_calls_p95"]).is_equal(40)


func test_the_heavy_window_starts_at_heavy_rigs() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.frames(hud, 3, {"rigs": hud.gate.heavy_rigs - 1})
	Rig.frames(hud, 2, {"rigs": hud.gate.heavy_rigs})
	assert_int(hud.summary()["heavy_frames"]).is_equal(2)


func test_a_hitch_is_an_interval_of_at_least_one_tick_period() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	for interval: int in [
		MatchRunner.TICK_USEC - 1, MatchRunner.TICK_USEC, MatchRunner.TICK_USEC + 1
	]:
		Rig.frame(hud, {"interval": interval})
	assert_int(hud.summary()["hitches"]).is_equal(2)
	assert_int(hud.summary()["heavy_hitches"]).is_equal(2)


func test_extra_slots_count_the_intervals_by_slots_beyond_the_period() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	# 60 Hz: P = V = 16.67 ms, so the slot edges lie at P + 0.5 V = 25.0, 41.7 and 58.3 ms: below
	# the first is no extra slot (so the dropped limit and the first bin agree), then one, two and
	# three or more.
	for interval: int in [16667, 24900, 25100, 41600, 42000, 58400, 80000]:
		Rig.frame(hud, {"interval": interval})
	assert_array(hud.summary()["extra_slots"]).is_equal([2, 2, 1, 2])


func test_period_and_drop_limits_follow_the_refresh_rate_and_the_frame_cap() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var cases: Array = [  # refresh Hz, max_fps, period ms, drop ms
		[60.0, 0, 1000.0 / 60.0, 25.0],
		[59.94, 60, 1000.0 / 59.94, 1.5 * 1000.0 / 59.94],  # Never compared exactly.
		[120.0, 60, 1000.0 / 60.0, 1000.0 / 60.0 + 0.5 * 1000.0 / 120.0],
		[90.0, 0, 1000.0 / 90.0, 1.5 * 1000.0 / 90.0],
		[-1.0, 0, 0.0, 0.0],  # Unknown, as headless: no limit to judge against.
	]
	for c: Array in cases:
		hud.refresh_source = func() -> float: return c[0]
		hud.max_fps_source = func() -> int: return c[1]
		hud.restart()
		var label: String = "%s Hz, max_fps %s" % [c[0], c[1]]
		assert_float(hud.period_ms()).override_failure_message(label).is_equal_approx(c[2], 0.0001)
		assert_float(hud.drop_ms()).override_failure_message(label).is_equal_approx(c[3], 0.0001)
		assert_float(hud.summary()["refresh_hz_start"]).is_equal(c[0])


func test_tick_samples_give_job_step_phase_and_flow_values() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var rules: RulesDef = RulesDef.new()
	assert_int(hud.flow_cells_per_tick).is_equal(rules.flow_cells_per_tick)
	for tick: int in range(1, 21):
		var snap: MatchSnapshot = Rig.snapshot(tick, tick * 1000, tick * 500)
		snap.unit_id = PackedInt32Array([1, 2, 3])
		snap.phase_usec = PackedInt64Array()
		snap.phase_usec.resize(SimProbe.Phase.COUNT)
		for phase: int in SimProbe.Phase.COUNT:
			snap.phase_usec[phase] = (phase + 1) * 100
		snap.phase_usec[SimProbe.Phase.FLOW] = 1000 + tick
		snap.stats.resize(World.Stat.ROWS_COMPACTED + 1)  # Even ticks settle a whole slice.
		snap.stats[World.Stat.FLOW_CELLS] = rules.flow_cells_per_tick if tick % 2 == 0 else 100
		hud.record_snapshot(snap)
	var s: Dictionary = hud.summary()
	assert_float(s["job_mean_ms"]).is_equal(10.5)
	assert_float(s["job_p50_ms"]).is_equal(10.0)
	assert_float(s["job_p95_ms"]).is_equal(19.0)
	assert_float(s["job_p99_ms"]).is_equal(20.0)
	assert_float(s["job_max_ms"]).is_equal(20.0)
	assert_float(s["tick_p50_ms"]).is_equal(5.0)
	assert_float(s["tick_p95_ms"]).is_equal(9.5)
	assert_float(s["tick_max_ms"]).is_equal(10.0)
	# The slice sample is the FLOW phase of the even ticks only: 2 to 20, rank 10 of 10 is tick 20.
	assert_float(s["flow_slice_p95_ms"]).is_equal_approx(1.020, 0.00001)
	var phases: Array = s["phases_ms"]
	assert_int(phases.size()).is_equal(SimProbe.Phase.COUNT)
	for phase: int in SimProbe.Phase.COUNT:
		if phase != SimProbe.Phase.FLOW:
			assert_float(phases[phase]).is_equal_approx((phase + 1) * 0.1, 0.00001)
	assert_float(phases[SimProbe.Phase.FLOW]).is_equal_approx(1.0105, 0.00001)  # Mean of 1001-1020.
	assert_int(s["alive"]).is_equal(3)


func test_checkpoints_are_the_published_hashes_every_150_ticks_as_world_hash_hex() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.run_ticks = 450
	Rig.ticks(hud, 449)
	var s: Dictionary = hud.summary()
	assert_array(s["checkpoints"]).has_size(2)
	assert_int(s["checkpoints"][0]["tick"]).is_equal(150)
	assert_str(s["checkpoints"][0]["hash_hex"]).is_equal(World.hash_hex(150 * 1000 + 7))
	assert_int(s["checkpoints"][1]["tick"]).is_equal(300)
	assert_str(s["checkpoints"][1]["hash_hex"]).is_equal(World.hash_hex(300 * 1000 + 7))
	assert_str(s["hash_hex"]).is_equal(World.hash_hex(449 * 1000 + 7))
	assert_float(s["refresh_hz_end"]).is_equal(60.0)  # The start rate until the run ends.
	assert_float(hud.period_ms()).is_equal_approx(1000.0 / 60.0, 0.0001)
	hud.refresh_source = func() -> float: return 59.94
	hud.record_snapshot(Rig.snapshot(450))  # Reaches run_ticks: the run ends with its checkpoint.
	hud.record_snapshot(Rig.snapshot(451, 99_000))  # Nothing after the end is recorded.
	s = hud.summary()
	assert_array(s["checkpoints"]).has_size(3)
	assert_str(s["checkpoints"][2]["hash_hex"]).is_equal(World.hash_hex(450 * 1000 + 7))
	assert_float(s["refresh_hz_start"]).is_equal(60.0)  # Read again when the run ended.
	assert_float(s["refresh_hz_end"]).is_equal(59.94)
	# P and V stay at the start rate (a rate change above 1 % is INVALID, below it moot).
	assert_float(hud.period_ms()).is_equal_approx(1000.0 / 60.0, 0.0001)
	assert_float(hud.drop_ms()).is_equal_approx(25.0, 0.0001)  # P + 1.5 V, V = 1000 / 60.
	assert_float(s["job_max_ms"]).is_equal(10.0)


func test_a_runner_run_installs_the_probe_and_records_published_ticks_from_the_snapshot() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.start()
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	hud.run_ticks = 150
	add_child(hud)  # _ready installs the TimingProbe with set_probe() and listens to `ticked`.
	hud.restart()
	var header: Label = hud.get_node("Column/Header")
	assert_bool(hud.visible).is_false()  # The card shows at the end of the run, not before.
	runner.run_ticks(149)
	assert_bool(hud.visible).is_false()
	runner.late_ticks = 2  # The runner's counts, copied at the publish.
	runner.held_ticks = 4
	runner.latency_usec_max = 900_000
	runner.run_ticks(1)  # Tick 150: the checkpoint, and the end of the run.
	var s: Dictionary = hud.summary()
	assert_bool(hud.visible).is_true()
	assert_str(header.text).contains("GATE:")
	assert_str(s["tick_mode"]).is_equal("SYNC")
	assert_array(s["checkpoints"]).has_size(1)
	assert_int(s["checkpoints"][0]["tick"]).is_equal(150)
	assert_str(s["checkpoints"][0]["hash_hex"]).is_equal(World.hash_hex(runner.snapshot.last_hash))
	assert_int(s["alive"]).is_equal(runner.snapshot.unit_count())
	assert_float(s["job_max_ms"]).is_greater(0.0)
	assert_float(s["tick_p95_ms"]).is_greater(0.0)
	var phase_total: float = 0.0  # Only the installed probe fills the split.
	for ms: float in s["phases_ms"]:
		phase_total += ms
	assert_float(phase_total).is_greater(0.0)
	# The HUD holds what the runner held at the publish. The tick itself ran inline and timed, so
	# a stall may have counted it late: compare with the runner's counts after the tick.
	assert_array([s["late_ticks"], s["held_ticks"], s["latency_usec_max"]]).is_equal(
		[runner.late_ticks, runner.held_ticks, runner.latency_usec_max]
	)
	assert_int(s["late_ticks"]).is_greater_equal(2)
	assert_int(s["held_ticks"]).is_greater_equal(4)
	assert_int(s["latency_usec_max"]).is_greater_equal(900_000)
	runner.run_ticks(5)  # The finished run takes no more.
	assert_float(hud.summary()["job_max_ms"]).is_equal(s["job_max_ms"])


func test_a_worker_run_is_recorded_as_a_worker_run() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.tick_mode = MatchRunner.TickMode.WORKER
	runner.start()
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	add_child(hud)  # set_probe() waits idle: no job has been posted.
	hud.restart()
	runner._process(1.0 / 60.0)  # The refill posts the first job.
	assert_bool(runner.wait_idle()).is_true()
	runner._process(1.0 / 15.0)  # The boundary publishes it and posts the next.
	assert_bool(runner.wait_idle()).is_true()
	assert_int(runner.snapshot.tick).is_equal(1)
	var s: Dictionary = hud.summary()
	assert_str(s["tick_mode"]).is_equal("WORKER")
	assert_float(s["job_max_ms"]).is_greater(0.0)
	assert_float(s["job_max_ms"]).is_equal(runner.snapshot.job_usec / 1000.0)


func test_the_live_path_times_a_frame_from_the_second_frame_after_restart() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	hud.clock = _scripted_clock
	hud.rigs_source = func() -> int: return 140
	hud.fog_source = func() -> int: return 250
	hud.ref_step = func(iterations: int) -> void: _log.append("ref %d" % iterations)
	add_child(hud)
	assert_int(hud.process_priority).is_equal(-1000)  # The top of the frame.
	hud.restart()
	# Frame 1 only sets the anchor and takes no sample; frame 2 is the first interval: the top at
	# 17667, the warm-up and the sample (17700 to 17725), the work from 17725 to the draw at 21725.
	_times = [1000, 17667, 17700, 17725, 21725]
	hud._process(0.0)
	hud._on_post_draw()
	assert_int(hud.summary()["frames"]).is_equal(0)
	assert_array(_times).has_size(4)
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	assert_array(_times).is_empty()
	# The reference sample is the second of two runs of ref_iterations: the warm-up comes first and
	# lies before the clock read that starts the sample (and so before the work).
	var run: String = "ref %d" % hud.gate.ref_iterations
	assert_array(_log).is_equal(["clock", "clock", run, "clock", run, "clock", "clock"])
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(1)
	assert_float(s["frame_p50_ms"]).is_equal_approx(16.667, 0.0001)
	assert_float(s["work_p95_ms"]).is_equal_approx(4.0, 0.0001)  # Headless render CPU is 0.
	assert_float(s["view_p95_ms"]).is_equal_approx(4.0, 0.0001)
	assert_int(s["drawn_rigs_max"]).is_equal(140)
	assert_int(s["fog_updates"]).is_equal(1)
	assert_float(s["fog_update_p95_ms"]).is_equal_approx(0.25, 0.0001)
	assert_float(s["fog_update_p95_norm_ms"]).is_equal_approx(0.25, 0.0001)  # Sample equals the peak.
	hud._on_post_draw()  # A second draw in the same frame adds nothing.
	assert_int(hud.summary()["frames"]).is_equal(1)


func test_no_reference_sample_is_taken_without_a_run_or_after_its_end() -> void:
	var hud: PerfHud = auto_free(Rig.hud())  # No runner: not active.
	hud.clock = _scripted_clock
	_times = [1, 2, 3]
	hud._process(0.0)
	hud._on_post_draw()
	assert_array(_times).has_size(3)
	assert_int(hud.summary()["frames"]).is_equal(0)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var live: PerfHud = auto_free(Rig.hud())
	live.runner = runner
	live.clock = _scripted_clock
	add_child(live)
	live.record_snapshot(Rig.snapshot(live.run_ticks))  # The run is over.
	live._process(0.0)
	live._process(0.0)
	assert_array(_times).has_size(3)


func test_summary_holds_every_listed_key_and_none_of_the_renamed_ones() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	for key: String in KEYS:
		assert_bool(s.has(key)).override_failure_message("missing key " + key).is_true()
	for key: String in GONE:
		assert_bool(s.has(key)).override_failure_message("renamed key " + key).is_false()
	assert_int(s["phases_ms"].size()).is_equal(SimProbe.Phase.COUNT)
	assert_int(s["extra_slots"].size()).is_equal(4)
	assert_str(s["tick_mode"]).is_equal("WORKER")
	assert_bool(s["debug"]).is_false()
	assert_str(s["layer_mode"]).is_equal("all")
	assert_int(s["job_ticks"]).is_equal(900)
	assert_bool(s["finished"]).is_true()


func test_the_descriptive_fields_pass_through_summary_and_the_card() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.layer_mode = "units only"  # P50b sets both; the copy report names the mode it measured.
	hud.zoom = 0.75
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	var size: Vector2i = DisplayServer.screen_get_size()
	assert_str(s["layer_mode"]).is_equal("units only")
	assert_float(s["zoom"]).is_equal(0.75)
	assert_str(s["os"]).is_equal(OS.get_name())
	assert_str(s["model"]).is_equal(OS.get_model_name())
	assert_str(s["engine"]).is_equal(Engine.get_version_info()["string"])
	assert_str(s["screen"]).is_equal("%dx%d" % [size.x, size.y])
	assert_str(hud.card_lines()[0]).contains("units only")


func test_the_flow_slice_is_the_scenarios_rule_and_the_default_without_one() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = ScenarioDef.new()
	runner.scenario.rules = RulesDef.new()
	runner.scenario.rules.flow_cells_per_tick = 64
	hud.runner = runner
	hud.restart()
	assert_int(hud.flow_cells_per_tick).is_equal(64)
	# A tick that settled 64 cells is a slice sample, one that settled the default is not.
	hud.record_snapshot(_flow_snapshot(1, 64, 2000))
	hud.record_snapshot(_flow_snapshot(2, RulesDef.new().flow_cells_per_tick, 9000))
	assert_float(hud.summary()["flow_slice_p95_ms"]).is_equal_approx(2.0, 0.00001)
	runner.scenario.rules = null  # A scenario without rules plays the default ones.
	hud.restart()
	assert_int(hud.flow_cells_per_tick).is_equal(RulesDef.new().flow_cells_per_tick)
	runner.scenario = null
	hud.flow_cells_per_tick = 64
	hud.restart()
	assert_int(hud.flow_cells_per_tick).is_equal(RulesDef.new().flow_cells_per_tick)


func test_restart_resets_every_sample_and_the_counts() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	hud.late_ticks = 2
	hud.held_ticks = 3
	hud.latency_usec_max = 70_000
	Rig.frame(hud)  # The run is over: nothing more is recorded.
	var before: Dictionary = hud.summary()
	assert_int(before["frames"]).is_equal(1000)
	assert_int(before["runs"]).is_equal(1)
	hud.restart()
	var s: Dictionary = hud.summary()
	assert_int(s["runs"]).is_equal(2)
	for key: String in ["frames", "heavy_frames", "dropped", "hitches", "alive", "fog_updates"]:
		assert_int(s[key]).override_failure_message(key).is_equal(0)
	assert_int(s["job_ticks"]).is_equal(0)
	assert_bool(before["finished"]).is_true()
	assert_bool(s["finished"]).is_false()
	for key: String in ["frame_p50_ms", "work_p95_ms", "work_p95_norm_ms", "job_mean_ms"]:
		assert_float(s[key]).override_failure_message(key).is_equal(0.0)
	for key: String in ["job_p99_ms", "tick_max_ms", "flow_slice_p95_ms", "speed_main_pct"]:
		assert_float(s[key]).override_failure_message(key).is_equal(0.0)
	for key: String in ["late_ticks", "held_ticks", "latency_usec_max"]:
		assert_int(s[key]).override_failure_message(key).is_equal(0)
	assert_array(s["checkpoints"]).is_empty()
	assert_str(s["hash_hex"]).is_empty()
	assert_array(s["extra_slots"]).is_equal([0, 0, 0, 0])
	for ms: float in s["phases_ms"]:
		assert_float(ms).is_equal(0.0)
	# A finished run records again after the restart.
	Rig.frames(hud, 3)
	assert_int(hud.summary()["frames"]).is_equal(3)


func _scripted_clock() -> int:
	_log.append("clock")
	return _times.pop_front()


## Published tick `tick` that settled `cells` flow cells, its FLOW phase taking `flow_usec`.
func _flow_snapshot(tick: int, cells: int, flow_usec: int) -> MatchSnapshot:
	var snap: MatchSnapshot = Rig.snapshot(tick)
	snap.phase_usec = PackedInt64Array()
	snap.phase_usec.resize(SimProbe.Phase.COUNT)
	snap.phase_usec[SimProbe.Phase.FLOW] = flow_usec
	snap.stats.resize(World.Stat.ROWS_COMPACTED + 1)
	snap.stats[World.Stat.FLOW_CELLS] = cells
	return snap
