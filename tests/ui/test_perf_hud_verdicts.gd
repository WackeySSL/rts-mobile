extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0012 section 4, ADR 0014 sections 1 and 3), the verdicts: the
## lines and `GATE: PASS/FAIL` follow a PerfGateDef the test builds, one criterion failing at a
## time; the worker limits judge the raw job times and the main-thread limits the per-frame
## normalised work; the pacing rules judge the intervals (steady 24 ms frames fail the cadence, one
## 70 ms interval in the heavy window the hitch rule). Thresholds come from the gate, never from a
## literal in the HUD, so each case moves one gate field or one sample. The samples are in
## test_perf_hud.gd, the gate's own fields and the windows in test_perf_hud_gate.gd, the
## normalisation by frames of different speeds in test_perf_hud_norm.gd and the preflight in
## test_perf_hud_preflight.gd.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
## The verdict rows in card order (INVALID rows come before them).
const ROWS: PackedStringArray = [
	"heavy_frames_min",
	"dropped_pct_max",
	"heavy_dropped_pct",
	"cadence_pct_min",
	"heavy_cadence_pct",
	"hitches_max",
	"work_p95_ms",
	"work_tick_p95_ms",
	"sim_p95_ms",
	"job_p99_ms",
	"draw_calls_max",
	"late_ticks_max",
	"fog_update_p95_ms",
	"build",
	"impl",
	"golden_hashes",
]


func test_a_passing_run_prints_every_verdict_and_gate_pass() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	var names: Array[String] = []
	for line: String in s["verdicts"]:
		names.append(line.get_slice(":", 0))
		if not line.begins_with("impl:"):  # n/a off Android.
			assert_str(line).override_failure_message(line).contains(": PASS (")
	assert_array(names).is_equal(Array(ROWS))
	assert_array(s["verdicts"]).contains(["impl: n/a (only Android requires the library)"])
	assert_bool(s["gate_pass"]).is_true()
	assert_array(s["verdicts"]).contains(["build: PASS (release template)"])
	var card: PackedStringArray = hud.card_lines()
	assert_str(card[card.size() - 1]).is_equal("GATE: PASS")
	assert_str(card[0]).starts_with("PERF run 1 |")  # The run number: the rig restarts once.
	assert_str(card[0]).contains("WORKER")  # tick_mode and build are on the card.
	assert_str(card[0]).contains("release")


func test_each_criterion_fails_alone_in_a_test_built_gate() -> void:
	var cases: Array = [  # gate field, value, the rows that fail
		["heavy_frames_min", 1001, ["heavy_frames_min"]],
		["dropped_pct_max", -1.0, ["dropped_pct_max", "heavy_dropped_pct"]],
		["cadence_pct_min", 100.0, ["cadence_pct_min", "heavy_cadence_pct"]],
		["hitches_max", -1, ["hitches_max"]],
		["work_p95_ms", 3.0, ["work_p95_ms"]],
		["work_tick_p95_ms", 3.0, ["work_tick_p95_ms"]],
		["sim_p95_ms", 5.0, ["sim_p95_ms"]],
		["job_p99_ms", 5.0, ["job_p99_ms"]],
		["fog_update_p95_ms", 0.1, ["fog_update_p95_ms"]],
		["draw_calls_max", 30, ["draw_calls_max"]],
	]
	for c: Array in cases:
		var gate: PerfGateDef = PerfGateDef.new()
		gate.set(c[0], c[1])
		var hud: PerfHud = auto_free(Rig.hud(gate))
		Rig.run(hud)
		var s: Dictionary = hud.summary()
		assert_array(Rig.failed(s)).override_failure_message(c[0]).is_equal(c[2])
		assert_bool(s["gate_pass"]).override_failure_message(c[0]).is_false()
		assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")
	var late: PerfHud = auto_free(Rig.hud())  # Not a gate field: a worker run with one late job.
	Rig.run(late)
	late.late_ticks = 1
	assert_array(Rig.failed(late.summary())).is_equal(["late_ticks_max"])
	var debug: PerfHud = auto_free(Rig.hud())  # And a debug template.
	Rig.run(debug)
	debug.debug_build = true
	assert_array(Rig.failed(debug.summary())).is_equal(["build"])


func test_the_build_verdict_fails_a_debug_template_only_when_release_only() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	hud.debug_build = true
	assert_array(hud.summary()["verdicts"]).contains(["build: FAIL (debug template)"])
	hud.gate.release_only = false
	assert_array(hud.summary()["verdicts"]).contains(["build: PASS (debug template)"])
	assert_bool(hud.summary()["gate_pass"]).is_true()
	assert_bool(hud.summary()["debug"]).is_true()


func test_the_job_p99_skips_the_nine_slowest_of_900_so_a_tick_zero_spike_passes() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	Rig.ticks(hud, 900, 1, 120_000)  # Tick 1: the opening orders and a hash.
	var s: Dictionary = hud.summary()
	assert_float(s["job_max_ms"]).is_equal(120.0)
	assert_float(s["job_p99_ms"]).is_equal(10.0)  # Rank 891 of 900.
	assert_float(s["job_p95_ms"]).is_equal(10.0)
	assert_array(s["verdicts"]).contains(["job_p99_ms: PASS (10.00 ms raw job p99, limit 26.70)"])
	assert_bool(s["gate_pass"]).is_true()
	# Ten slow jobs are above the 99th percentile (10 of 900 is 1.1 %) but not the 95th.
	var tail: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(tail)
	Rig.ticks(tail, 900, 10, 40_000)
	assert_float(tail.summary()["job_p99_ms"]).is_equal(40.0)
	assert_array(Rig.failed(tail.summary())).is_equal(["job_p99_ms"])


func test_work_p95_covers_all_heavy_frames_and_work_tick_p95_the_publish_frames_only() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	# 1000 heavy frames, 250 publish frames; 30 of those cost 8 ms: 3 % of all frames (so the
	# all-frames p95 is an ordinary 4 ms) and 12 % of the publish frames (their p95 is 8 ms).
	var slow: Dictionary = {}
	for i: int in 30:
		slow[i * 4] = {"process": 7000}
	Rig.pass_frames(hud, {}, slow)
	# Outside the heavy window, publish frames among them: judged by no row.
	Rig.frames(hud, 500, {"rigs": 100, "process": 29000, "published": true})
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_int(s["heavy_frames"]).is_equal(1000)
	assert_float(s["work_p95_ms"]).is_equal_approx(4.0, 0.0001)
	assert_float(s["work_tick_p95_ms"]).is_equal_approx(8.0, 0.0001)
	assert_float(s["work_other_p95_ms"]).is_equal_approx(4.0, 0.0001)
	assert_array(s["verdicts"]).contains(["work_p95_ms: PASS (4.00 ms normalised, limit 5.60)"])
	assert_array(s["verdicts"]).contains(
		["work_tick_p95_ms: FAIL (8.00 ms normalised, limit 5.60)"]
	)
	assert_array(Rig.failed(s)).is_equal(["work_tick_p95_ms"])


func test_the_card_lists_every_verdict_line_after_the_header_and_ends_with_gate() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	var lines: PackedStringArray = hud.card_lines()
	var verdicts: Array = hud.summary()["verdicts"]
	assert_int(verdicts.size()).is_equal(ROWS.size())
	for line: String in verdicts:
		assert_bool(lines.has(line)).override_failure_message(line).is_true()
	assert_str(lines[lines.size() - 1]).is_equal("GATE: PASS")
	assert_array(Array(lines.slice(1, 1 + verdicts.size()))).is_equal(verdicts)  # Right after it.
	assert_array(Array(lines)).contains(["held_ticks 0 (no verdict)"])


func test_late_ticks_are_judged_for_a_worker_run_and_not_applicable_for_a_sync_run() -> void:
	var worker: PerfHud = auto_free(Rig.hud())
	Rig.run(worker)
	worker.late_ticks = 3
	assert_array(worker.summary()["verdicts"]).contains(
		["late_ticks_max: FAIL (3.00 late ticks, limit 0.00)"]
	)
	var sync: PerfHud = auto_free(Rig.hud())
	Rig.run(sync)
	sync.worker_mode = false  # SYNC counts inline ticks too: the count says nothing about a worker.
	sync.late_ticks = 3
	var s: Dictionary = sync.summary()
	assert_str(s["tick_mode"]).is_equal("SYNC")
	assert_array(s["verdicts"]).contains(
		["late_ticks_max: n/a (SYNC: late_ticks counts inline ticks)"]
	)
	assert_int(s["late_ticks"]).is_equal(3)
	assert_bool(s["gate_pass"]).is_true()
	sync.held_ticks = 50  # Held ticks are shown and never judged.
	s = sync.summary()
	assert_int(s["held_ticks"]).is_equal(50)
	assert_bool(s["gate_pass"]).is_true()
	for line: String in s["verdicts"]:
		assert_str(line).not_contains("held")
	assert_array(Array(sync.card_lines())).contains(["held_ticks 50 (no verdict)"])


func test_steady_24_ms_frames_fail_the_cadence_and_not_the_dropped_share() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud, {"interval": 24000})  # 42 fps, yet below the 25.0 ms limit.
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_int(s["dropped"]).is_equal(0)
	assert_float(s["cadence_pct"]).is_equal_approx(100.0 * (1000.0 / 60.0) / 24.0, 0.0001)
	assert_array(Rig.failed(s)).is_equal(["cadence_pct_min", "heavy_cadence_pct"])


func test_one_70_ms_interval_in_the_heavy_window_fails_the_hitch_rule_alone() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud, {}, {500: {"interval": 70000}})
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_int(s["heavy_hitches"]).is_equal(1)
	assert_int(s["dropped"]).is_equal(1)  # 0.1 %: under the 1 % rule, so only the hitch fails.
	assert_array(Rig.failed(s)).is_equal(["hitches_max"])
	# The same stall outside the heavy window is counted run-wide, without a verdict.
	var light: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(light, {}, {500: {"interval": 70000, "rigs": 100}})
	Rig.ticks(light, 900)
	s = light.summary()
	assert_int(s["hitches"]).is_equal(1)
	assert_int(s["heavy_hitches"]).is_equal(0)
	assert_int(s["heavy_frames"]).is_equal(999)
	assert_array(Rig.failed(s)).is_empty()


func test_main_thread_verdicts_use_the_per_frame_normalisation_and_worker_ones_stay_raw() -> void:
	var slow: PerfHud = auto_free(Rig.hud())
	# 7 ms of work in frames whose reference sample is 50 us against a peak of 25 us: the main
	# thread ran at half speed, so the work is judged as 3.5 ms (7 raw would fail the 5.6 limit).
	Rig.pass_frames(slow, {"process": 6000, "ref": 50})
	Rig.ticks(slow, 900)
	var s: Dictionary = slow.summary()
	assert_float(s["work_p95_ms"]).is_equal_approx(7.0, 0.0001)  # Raw next to normalised.
	assert_float(s["work_p95_norm_ms"]).is_equal_approx(3.5, 0.0001)
	assert_float(s["work_tick_p95_norm_ms"]).is_equal_approx(3.5, 0.0001)
	for key: String in ["speed_main_pct", "speed_tick_pct", "speed_fog_pct"]:
		assert_float(s[key]).override_failure_message(key).is_equal_approx(50.0, 0.0001)
	assert_float(s["ref_peak_us"]).is_equal(25.0)
	assert_array(s["verdicts"]).contains(["work_p95_ms: PASS (3.50 ms normalised, limit 5.60)"])
	assert_array(Rig.failed(s)).is_empty()
	# Never above raw: samples faster than the peak, or none, keep the raw 7 ms and fail.
	for ref: int in [20, 0]:
		var fast: PerfHud = auto_free(Rig.hud())
		Rig.pass_frames(fast, {"process": 6000, "ref": ref})
		Rig.ticks(fast, 900)
		var f: Dictionary = fast.summary()
		(
			assert_float(f["work_p95_norm_ms"])
			. override_failure_message("ref %d" % ref)
			. is_equal_approx(7.0, 0.0001)
		)
		assert_array(Rig.failed(f)).is_equal(["work_p95_ms", "work_tick_p95_ms"])
	# The worker stays raw: a slow reference sample does not excuse a slow job.
	var late_job: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(late_job, {"ref": 50})
	Rig.ticks(late_job, 900, 900, 20_000)
	assert_array(Rig.failed(late_job.summary())).is_equal(["sim_p95_ms"])


func test_pacing_and_the_fog_verdict_fail_closed_without_their_measurements() -> void:
	var headless: PerfHud = auto_free(Rig.hud())
	headless.refresh_source = func() -> float: return -1.0  # DisplayServer headless.
	headless.restart()
	Rig.run(headless)
	assert_array(Rig.failed(headless.summary())).is_equal(
		["dropped_pct_max", "heavy_dropped_pct", "cadence_pct_min", "heavy_cadence_pct"]
	)
	var no_fog: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(no_fog, {"fog": -1})
	Rig.ticks(no_fog, 900)
	assert_array(Rig.failed(no_fog.summary())).is_equal(["fog_update_p95_ms"])
