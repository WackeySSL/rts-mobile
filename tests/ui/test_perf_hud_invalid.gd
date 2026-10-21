extends GdUnitTestSuite
## PerfHud part 2 (plan P50a2, ADR 0011 section 5, ADR 0012 section 4, ADR 0014 section 2), the
## INVALID rules: a run is INVALID, with no verdict that can stand and `GATE: FAIL`, when the app
## paused or lost focus during it, when the refresh rate changed by more than
## `refresh_tolerance_pct` between start and end or lies below `max_fps` less that tolerance, when
## the median interval is below P less `median_tolerance_pct` (never above: steady slow frames are
## judged, and fail), and when the heavy window's draw-call p95 or render CPU p95 reads 0 (a
## monitor a release template compiles out). Float rates are never compared exactly. The refused
## preflight is in test_perf_hud_preflight.gd. Nothing here logs an error: gdUnit4 fails a test
## that does.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")


func after_test() -> void:
	CommandQueue.clear()


func test_a_pause_or_a_lost_focus_during_the_run_marks_it_invalid() -> void:
	for what: int in [
		Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT
	]:
		var hud: PerfHud = auto_free(Rig.hud())
		Rig.pass_frames(hud)
		hud.notification(what)  # During the run: it has not reached its last tick.
		Rig.ticks(hud, 900)
		var s: Dictionary = hud.summary()
		assert_array(s["invalid_reasons"]).override_failure_message(str(what)).is_equal(
			["app_paused"]
		)
		assert_str(s["verdicts"][0]).is_equal("INVALID: app_paused")
		assert_bool(s["gate_pass"]).is_false()  # A run that passed everything else.
		assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")


func test_other_notifications_and_a_pause_after_the_run_or_before_a_restart_change_nothing(
) -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	hud.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	Rig.run(hud)
	hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)  # The run is over: nothing to spoil.
	assert_bool(hud.summary()["invalid"]).is_false()
	assert_bool(hud.summary()["gate_pass"]).is_true()
	var early: PerfHud = auto_free(Rig.hud())
	early.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	early.restart()  # A new run starts clean.
	Rig.run(early)
	assert_bool(early.summary()["invalid"]).is_false()
	var spoiled: PerfHud = auto_free(Rig.hud())
	spoiled.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	Rig.run(spoiled)
	assert_bool(spoiled.summary()["invalid"]).is_true()
	spoiled.restart()
	Rig.run(spoiled)
	assert_bool(spoiled.summary()["invalid"]).is_false()  # restart() clears the flag.


func test_the_refresh_rules_judge_a_mode_change_or_a_rate_below_the_cap_and_never_exactly() -> void:
	var cases: Array = [  # start Hz, end Hz, max_fps, the reasons
		[59.94, 59.94, 60, []],  # P = 16.68 ms: a 59.94 Hz panel with a 60 cap is valid.
		[60.0, 59.94, 60, []],  # The end read 0.1 % lower: valid, P and V stay at the start rate.
		[60.0, 90.0, 60, ["refresh_changed"]],
		[50.0, 50.0, 60, ["refresh_below_max_fps"]],
		[50.0, 50.0, 0, []],  # No cap: the refresh rate is the cap.
		[120.0, 120.0, 60, []],
		[60.0, 59.39, 60, ["refresh_changed"]],  # 1.0 % of 60 is 0.6: 59.39 is past it.
		[60.0, 59.41, 60, []],
		[59.39, 59.39, 60, ["refresh_below_max_fps"]],  # Below 59.4 = 60 x 0.99.
		[59.41, 59.41, 60, []],
	]
	for c: Array in cases:
		var hud: PerfHud = _run_at(c[0], c[1], c[2])
		var s: Dictionary = hud.summary()
		var label: String = "%s" % [c]
		assert_array(s["invalid_reasons"]).override_failure_message(label).is_equal(c[3])
		assert_bool(s["invalid"]).override_failure_message(label).is_equal(not c[3].is_empty())
		assert_bool(s["gate_pass"]).override_failure_message(label).is_equal(c[3].is_empty())
		assert_float(s["period_ms"]).is_equal_approx(
			1000.0 / minf(c[0], c[2] if c[2] > 0 else c[0]), 0.0001
		)


func test_the_period_of_a_59_94_hz_panel_is_16_68_ms_and_the_run_passes() -> void:
	var hud: PerfHud = _run_at(59.94, 59.94, 60)
	assert_float(hud.summary()["period_ms"]).is_equal_approx(16.68, 0.005)
	assert_array(hud.summary()["verdicts"]).not_contains(["INVALID: refresh_changed"])
	assert_bool(hud.summary()["gate_pass"]).is_true()


func test_steady_24_ms_frames_are_judged_and_not_invalid() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud, {"interval": 24000})  # Median 24 ms: far above P, a slow run.
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_bool(s["invalid"]).is_false()
	assert_array(Rig.failed(s)).is_equal(["cadence_pct_min", "heavy_cadence_pct"])
	assert_bool(s["gate_pass"]).is_false()
	var worse: PerfHud = auto_free(Rig.hud())  # A median of about 33 ms: every frame misses a vsync.
	Rig.pass_frames(worse, {"interval": 33333})
	Rig.ticks(worse, 900)
	assert_bool(worse.summary()["invalid"]).is_false()


func test_a_median_interval_below_the_period_less_two_percent_is_invalid() -> void:
	# P = 16.667 ms at 60 Hz, so the limit is 16.333 ms: below it the limiter is not pacing at P.
	for interval: int in [16000, 16320]:
		var hud: PerfHud = auto_free(Rig.hud())
		Rig.pass_frames(hud, {"interval": interval})
		Rig.ticks(hud, 900)
		var s: Dictionary = hud.summary()
		assert_array(s["invalid_reasons"]).override_failure_message(str(interval)).is_equal(
			["median_below_period"]
		)
		assert_bool(s["gate_pass"]).is_false()
	for interval: int in [16350, 16667, 17000]:
		var hud: PerfHud = auto_free(Rig.hud())
		Rig.pass_frames(hud, {"interval": interval})
		Rig.ticks(hud, 900)
		assert_bool(hud.summary()["invalid"]).override_failure_message(str(interval)).is_false()
	# The median, not the mean: 600 short frames and 400 long ones have a mean of 25 ms.
	var short: PerfHud = auto_free(Rig.hud())
	var at: Dictionary = {}
	for i: int in 400:
		at[i] = {"interval": 40000}
	Rig.pass_frames(short, {"interval": 16000}, at)
	assert_array(short.summary()["invalid_reasons"]).is_equal(["median_below_period"])
	var long: PerfHud = auto_free(Rig.hud())
	at.clear()
	for i: int in 600:
		at[i] = {"interval": 40000}
	Rig.pass_frames(long, {"interval": 16000}, at)
	assert_array(long.summary()["invalid_reasons"]).is_empty()  # Median 40 ms.


func test_a_heavy_window_that_reads_zero_draw_calls_or_render_cpu_is_invalid() -> void:
	var cases: Array = [  # frame spec, the reasons
		[{"calls": 0}, ["draw_calls_p95_zero"]],
		[{"render": 0}, ["render_cpu_p95_zero"]],
		[{"calls": 0, "render": 0}, ["draw_calls_p95_zero", "render_cpu_p95_zero"]],
	]
	for c: Array in cases:
		var hud: PerfHud = auto_free(Rig.hud())
		Rig.pass_frames(hud, c[0])
		Rig.ticks(hud, 900)
		var s: Dictionary = hud.summary()
		assert_array(s["invalid_reasons"]).override_failure_message(str(c)).is_equal(c[1])
		assert_str(s["verdicts"][0]).is_equal("INVALID: " + c[1][0])
		assert_bool(s["gate_pass"]).override_failure_message(str(c)).is_false()
		assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")
	var calls: Array = []  # The same zero feeds draw_calls_max a PASS, which INVALID overrides.
	var zero: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(zero, {"calls": 0})
	Rig.ticks(zero, 900)
	for line: String in zero.summary()["verdicts"]:
		if line.begins_with("draw_calls_max"):
			calls.append(line)
	assert_array(calls).is_equal(["draw_calls_max: PASS (0.00 calls p95, limit 60.00)"])


func test_the_zero_monitor_rule_reads_the_p95_of_the_heavy_window_only() -> void:
	# Rank 950 of 1000 is the p95: 950 zero readings make it 0, 949 do not.
	for zeros: int in [950, 949]:
		var hud: PerfHud = auto_free(Rig.hud())
		var at: Dictionary = {}
		for i: int in zeros:
			at[i] = {"calls": 0, "render": 0}
		Rig.pass_frames(hud, {}, at)
		Rig.ticks(hud, 900)
		var expected: Array = ["draw_calls_p95_zero", "render_cpu_p95_zero"] if zeros == 950 else []
		(
			assert_array(hud.summary()["invalid_reasons"])
			. override_failure_message(str(zeros))
			. is_equal(expected)
		)
	# Zero readings outside the heavy window are no fault; the window itself fails its own row.
	var light: PerfHud = auto_free(Rig.hud())
	Rig.frames(light, 1000, {"rigs": 100, "calls": 0, "render": 0})
	Rig.ticks(light, 900)
	assert_array(light.summary()["invalid_reasons"]).is_empty()
	assert_array(Rig.failed(light.summary())).contains(["heavy_frames_min"])
	var empty: PerfHud = auto_free(Rig.hud())  # No frame at all: no window, and no fault either.
	assert_array(empty.summary()["invalid_reasons"]).is_empty()
	assert_array(Rig.failed(empty.summary())).contains(["heavy_frames_min"])


func test_the_reasons_come_in_a_fixed_order_and_each_is_a_line_before_the_verdicts() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.refresh_source = func() -> float: return 60.0
	hud.max_fps_source = func() -> int: return 60
	hud.restart()
	hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	Rig.pass_frames(hud, {"calls": 0, "render": 0})
	hud.refresh_source = func() -> float: return 90.0
	Rig.ticks(hud, 900)
	hud.run_preflight(true, true)  # Refused: a job in flight.
	var s: Dictionary = hud.summary()
	var reasons: Array = [
		"preflight_job_in_flight",
		"app_paused",
		"refresh_changed",
		"draw_calls_p95_zero",
		"render_cpu_p95_zero",
	]
	assert_array(s["invalid_reasons"]).is_equal(reasons)
	for i: int in reasons.size():
		assert_str(s["verdicts"][i]).is_equal("INVALID: " + reasons[i])
	assert_str(s["verdicts"][reasons.size()]).starts_with("heavy_frames_min")


## A finished run at `start` Hz, ending at `end`, under the frame cap `cap`, its frames at the
## period they are paced at and the sample `spec` merged into each.
func _run_at(start: float, end: float, cap: int, spec: Dictionary = {}) -> PerfHud:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.refresh_source = func() -> float: return start
	hud.max_fps_source = func() -> int: return cap
	hud.restart()
	hud.worker_mode = true
	var rate: float = minf(start, float(cap)) if cap > 0 else start
	var interval: int = roundi(1_000_000.0 / rate)
	Rig.pass_frames(hud, {"interval": interval}.merged(spec, true))
	hud.refresh_source = func() -> float: return end
	Rig.ticks(hud, hud.run_ticks)
	return hud
