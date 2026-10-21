extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0012 section 4, ADR 0014 section 1), the gate and the windows:
## every threshold comes from the PerfGateDef the test builds (the fields that no other case moves,
## each verdict inclusive at its limit), the run-wide and heavy-window pacing rows are separate, the
## heavy window scopes every main-thread row, and a missing measurement never passes. The samples
## are in test_perf_hud.gd, the verdict lines in test_perf_hud_verdicts.gd, the live path in
## test_perf_hud_live.gd and the normalisation in test_perf_hud_norm.gd.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
## The verdict rows that compare one summary key with one gate field: the row, the key, the field,
## whether the field is a lower bound and whether it is an int.
const LIMITS: Array = [
	["heavy_frames_min", "heavy_frames", "heavy_frames_min", true, true],
	["dropped_pct_max", "dropped_pct", "dropped_pct_max", false, false],
	["heavy_dropped_pct", "heavy_dropped_pct", "dropped_pct_max", false, false],
	["cadence_pct_min", "cadence_pct", "cadence_pct_min", true, false],
	["heavy_cadence_pct", "heavy_cadence_pct", "cadence_pct_min", true, false],
	["hitches_max", "heavy_hitches", "hitches_max", false, true],
	["work_p95_ms", "work_p95_norm_ms", "work_p95_ms", false, false],
	["work_tick_p95_ms", "work_tick_p95_norm_ms", "work_tick_p95_ms", false, false],
	["sim_p95_ms", "job_p95_ms", "sim_p95_ms", false, false],
	["job_p99_ms", "job_p99_ms", "job_p99_ms", false, false],
	["draw_calls_max", "draw_calls_p95", "draw_calls_max", false, true],
	["late_ticks_max", "late_ticks", "late_ticks_max", false, true],
	["fog_update_p95_ms", "fog_update_p95_norm_ms", "fog_update_p95_ms", false, false],
]


func after_test() -> void:
	CommandQueue.clear()


func test_late_ticks_max_follows_the_gate() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.late_ticks_max = 2
	var hud: PerfHud = auto_free(Rig.hud(gate))
	Rig.run(hud)
	hud.late_ticks = 2
	assert_array(Rig.failed(hud.summary())).is_empty()
	hud.late_ticks = 3
	assert_array(Rig.failed(hud.summary())).is_equal(["late_ticks_max"])


func test_drop_slots_move_the_dropped_limit_and_the_slot_bins() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.drop_slots = 1.0  # The limit is P + one slot: 33.3 ms at 60 Hz.
	var hud: PerfHud = auto_free(Rig.hud(gate))
	Rig.frames(hud, 10, {"interval": 30000})  # 0.8 slots beyond P, plus one: bin 1, not dropped.
	Rig.frame(hud, {"interval": 40000})  # 1.4 slots beyond P, plus one: bin 2, dropped.
	var s: Dictionary = hud.summary()
	assert_float(hud.drop_ms()).is_equal_approx(2000.0 / 60.0, 0.0001)
	assert_int(s["dropped"]).is_equal(1)
	assert_array(s["extra_slots"]).is_equal([0, 10, 1, 0])


func test_a_frame_exactly_at_the_dropped_limit_is_not_dropped() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.refresh_source = func() -> float: return 100.0  # P = V = 10 ms, so the limit is 15 ms.
	hud.restart()
	Rig.frame(hud, {"interval": 15000})
	assert_float(hud.drop_ms()).is_equal(15.0)
	assert_int(hud.summary()["dropped"]).is_equal(0)
	Rig.frame(hud, {"interval": 15001})
	assert_int(hud.summary()["dropped"]).is_equal(1)


func test_heavy_rigs_and_jitter_ms_follow_the_gate() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.heavy_rigs = 100
	gate.jitter_ms = 16.0
	var hud: PerfHud = auto_free(Rig.hud(gate))
	Rig.frames(hud, 3, {"rigs": 100})
	Rig.frames(hud, 2, {"rigs": 99})
	assert_int(hud.summary()["heavy_frames"]).is_equal(3)
	var jitter: PerfHud = auto_free(Rig.hud(gate))
	for interval: int in [16000, 16500, 15500]:  # Jitter is up to the limit, inclusive.
		Rig.frame(jitter, {"interval": interval})
	assert_float(jitter.summary()["jitter_pct"]).is_equal_approx(200.0 / 3.0, 0.0001)
	assert_float(jitter.summary()["heavy_jitter_pct"]).is_equal_approx(200.0 / 3.0, 0.0001)


func test_run_wide_and_heavy_window_pacing_verdicts_are_separate_rows() -> void:
	# Slow frames outside the window fail the run-wide rows only.
	var outside: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(outside)
	Rig.frames(outside, 100, {"rigs": 100, "interval": 30000})
	Rig.ticks(outside, 900)
	assert_array(Rig.failed(outside.summary())).is_equal(["dropped_pct_max", "cadence_pct_min"])
	# 30 slow frames inside the window (3 % of its frames, 0.3 % of the run) fail its rows only.
	var inside: PerfHud = auto_free(Rig.hud())
	var slow: Dictionary = {}
	for i: int in 30:
		slow[i * 10] = {"interval": 30000}
	Rig.pass_frames(inside, {}, slow)
	Rig.frames(inside, 9000, {"rigs": 100})
	Rig.ticks(inside, 900)
	assert_array(Rig.failed(inside.summary())).is_equal(["heavy_dropped_pct", "heavy_cadence_pct"])


func test_frames_outside_the_heavy_window_are_not_judged() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	# Publish frames with a huge process, render and draw-call cost, one rig short of the window.
	var spec: Dictionary = {"published": true, "process": 29000, "calls": 900, "render": 20000}
	Rig.frames(hud, 500, spec.merged({"rigs": hud.gate.heavy_rigs - 1}))
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_int(s["heavy_frames"]).is_equal(1000)
	assert_int(s["heavy_publish_frames"]).is_equal(250)
	assert_float(s["work_tick_p95_ms"]).is_equal_approx(4.0, 0.0001)
	assert_int(s["draw_calls_p95"]).is_equal(40)
	assert_float(s["render_cpu_p95_ms"]).is_equal_approx(1.0, 0.0001)
	assert_float(s["view_p95_ms"]).is_equal_approx(3.0, 0.0001)
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["gate_pass"]).is_true()


func test_every_verdict_is_inclusive_at_its_limit_and_fails_just_past_it() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	hud.late_ticks = 2
	var s: Dictionary = hud.summary()
	for c: Array in LIMITS:
		for past: bool in [false, true]:
			hud.gate = PerfGateDef.new()
			hud.gate.set(c[2], _limit(c, s[c[1]], past))
			var label: String = "%s %s" % [c[0], "past its limit" if past else "at its limit"]
			(
				assert_bool(Rig.failed(hud.summary()).has(c[0]))
				. override_failure_message(label)
				. is_equal(past)
			)


func test_a_run_without_publish_frames_in_the_heavy_window_fails_the_work_tick_row() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud, {"published": false})
	Rig.frames(hud, 200, {"rigs": 100, "published": true})  # Publish frames, but outside.
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_int(s["heavy_frames"]).is_equal(1000)
	assert_int(s["heavy_publish_frames"]).is_equal(0)
	assert_float(s["work_tick_p95_norm_ms"]).is_equal(0.0)  # An empty class reads 0, never a pass.
	assert_array(s["verdicts"]).contains(["work_tick_p95_ms: FAIL (no heavy_publish_frames)"])
	assert_array(Rig.failed(s)).is_equal(["work_tick_p95_ms"])
	assert_bool(s["gate_pass"]).is_false()


func test_an_empty_run_has_no_cadence_and_fails_closed() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(0)
	for key: String in ["fps_avg", "cadence_pct", "heavy_cadence_pct"]:
		assert_float(s[key]).override_failure_message(key).is_equal(0.0)
	assert_array(Rig.failed(s)).is_equal(
		[
			"heavy_frames_min",
			"cadence_pct_min",
			"heavy_cadence_pct",
			"work_tick_p95_ms",
			"sim_p95_ms",
			"job_p99_ms",
			"fog_update_p95_ms",
			"golden_hashes"  # No checkpoint to compare: a missing measurement never passes.
		]
	)
	assert_bool(s["gate_pass"]).is_false()


func test_frames_without_a_published_tick_fail_the_job_rows_and_a_partial_run_is_no_pass() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	var s: Dictionary = hud.summary()
	assert_int(s["job_ticks"]).is_equal(0)
	assert_array(Rig.failed(s)).is_equal(["sim_p95_ms", "job_p99_ms", "golden_hashes"])
	assert_array(s["verdicts"]).contains(
		["sim_p95_ms: FAIL (no job_ticks)", "job_p99_ms: FAIL (no job_ticks)"]
	)
	assert_bool(s["gate_pass"]).is_false()
	# 300 of the 900 ticks: every row has samples and passes, yet the run is not over.
	Rig.ticks(hud, 300)
	s = hud.summary()
	assert_int(s["job_ticks"]).is_equal(300)
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["finished"]).is_false()
	assert_bool(s["gate_pass"]).is_false()
	# Tick 900 ends the run, and now it passes.
	for tick: int in range(301, hud.run_ticks + 1):
		hud.record_snapshot(Rig.snapshot(tick))
	s = hud.summary()
	assert_bool(s["finished"]).is_true()
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["gate_pass"]).is_true()


func test_a_fog_update_of_zero_us_counts_and_no_update_does_not() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.frame(hud, {"fog": 0})
	Rig.frame(hud, {"fog": -1})
	var s: Dictionary = hud.summary()
	assert_int(s["fog_updates"]).is_equal(1)
	assert_float(s["fog_update_p95_ms"]).is_equal(0.0)


func test_the_rank_keys_read_their_own_percentile() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	for i: int in 100:  # Intervals of 1 to 100 ms and 1 to 100 rigs: every rank has its own value.
		Rig.frame(hud, {"interval": (i + 1) * 1000, "rigs": i + 1})
	var s: Dictionary = hud.summary()
	assert_float(s["frame_p50_ms"]).is_equal(50.0)
	assert_float(s["frame_p95_ms"]).is_equal(95.0)
	assert_float(s["frame_p99_ms"]).is_equal(99.0)
	assert_float(s["frame_max_ms"]).is_equal(100.0)
	assert_float(s["fps_avg"]).is_equal_approx(1000.0 / 50.5, 0.0001)
	assert_int(s["drawn_rigs_p50"]).is_equal(50)
	assert_int(s["drawn_rigs_max"]).is_equal(100)


## The gate field of LIMITS row `c` that judges `value`: the value itself, or (`past`) the least
## step beyond it that fails, a whole unit for an int field.
func _limit(c: Array, value: float, past: bool) -> Variant:
	var step: float = 0.0
	if past:
		step = (1.0 if c[4] else 1e-9) * (1.0 if c[3] else -1.0)
	return int(value + step) if c[4] else value + step
