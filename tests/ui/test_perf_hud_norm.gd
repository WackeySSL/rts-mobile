extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0014 section 3), the normalisation by the per-frame method
## (calibration 2026-10-13): each main-thread frame's work is scaled by its own reference sample
## against `ref_peak` (the p25 of the burst), never above the raw value, and the fog patch the same
## way on its own samples. Every case gives the frames different samples, so a class factor (one
## sample for a whole class of frames) or a work column paired with the wrong samples reads a
## different value. The uniform-sample cases are in test_perf_hud_verdicts.gd.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")


func after_test() -> void:
	CommandQueue.clear()


func test_the_per_frame_method_scales_each_frame_by_its_own_sample() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var at: Dictionary = {}
	for i: int in 250:  # Every 4th frame publishes: 8 ms of work at half speed (sample 50 us).
		at[i * 4] = {"process": 7000, "ref": 50}
	for k: int in 40:  # Forty more cost 12 ms at quarter speed; the other 710 cost 3 ms at 25.
		at[k * 24 + 1] = {"process": 11000, "ref": 100}
	Rig.pass_frames(hud, {"process": 2000}, at)
	Rig.frames(hud, 400, {"rigs": 100, "ref": 10})  # Outside the window, and a fast sample.
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	# All heavy frames: 710 at 3 ms, 250 at 8 ms (4 ms normalised) and 40 at 12 ms (3 normalised).
	# The p95 is 8 ms raw, where one factor for the class (its p25 sample, 25 us) would keep it.
	assert_float(s["work_p95_ms"]).is_equal_approx(8.0, 0.0001)
	assert_float(s["work_p95_norm_ms"]).is_equal_approx(4.0, 0.0001)
	assert_float(s["work_tick_p95_ms"]).is_equal_approx(8.0, 0.0001)
	assert_float(s["work_tick_p95_norm_ms"]).is_equal_approx(4.0, 0.0001)
	# The other frames: the slow 40 are 12 ms raw but 3 ms normalised, so the p95 is 3 ms.
	assert_float(s["work_other_p95_ms"]).is_equal_approx(12.0, 0.0001)
	assert_float(s["work_other_p95_norm_ms"]).is_equal_approx(3.0, 0.0001)
	assert_float(s["fog_update_p95_ms"]).is_equal_approx(0.2, 0.0001)  # Fog is on publish frames.
	assert_float(s["fog_update_p95_norm_ms"]).is_equal_approx(0.1, 0.0001)
	# The clock factor of each class is its own p25 sample against the peak.
	assert_float(s["speed_main_pct"]).is_equal_approx(100.0, 0.0001)
	assert_float(s["speed_tick_pct"]).is_equal_approx(50.0, 0.0001)
	assert_float(s["speed_fog_pct"]).is_equal_approx(50.0, 0.0001)
	assert_array(s["verdicts"]).contains(["work_p95_ms: PASS (4.00 ms normalised, limit 5.60)"])
	assert_array(s["verdicts"]).contains(
		["work_tick_p95_ms: PASS (4.00 ms normalised, limit 5.60)"]
	)
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["gate_pass"]).is_true()


func test_the_fog_verdict_is_normalised_and_ref_peak_is_the_p25_of_the_burst() -> void:
	# 17 of 20 kept samples are 25 us and 3 are 50: the p25 is 25 and the p95 is 50.
	var burst: PackedFloat64Array = PackedFloat64Array()
	for i: int in 20:
		burst.append(25.0 if i < 17 else 50.0)
	var hud: PerfHud = auto_free(Rig.hud(null, burst))
	var at: Dictionary = {}
	# The 84 fog frames cost 7 ms of work. 64 run at half speed (sample 50 us) with 0.6 ms of fog,
	# 20 at quarter speed (sample 100 us) with 1.0 ms: 0.3 and 0.25 ms scaled by their own sample.
	for i: int in 84:
		at[i * 12] = {"process": 6000, "ref": 100 if i < 20 else 50, "fog": 1000 if i < 20 else 600}
	Rig.pass_frames(hud, {}, at)
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_float(s["ref_peak_us"]).is_equal(25.0)
	assert_float(s["ref_peak_p95_us"]).is_equal(50.0)
	# Raw, the fog patch (1.0 ms against a limit of 0.4) and 8.4 % of the frames (7 against 5.6)
	# would fail, and so would one factor for the whole fog class (its p25 sample, 50 us: 0.5 ms);
	# scaled by each update's own sample against the p25 peak, both pass.
	assert_float(s["fog_update_p95_ms"]).is_equal_approx(1.0, 0.0001)
	assert_float(s["fog_update_p95_norm_ms"]).is_equal_approx(0.3, 0.0001)
	assert_int(s["fog_updates"]).is_equal(84)
	assert_float(s["work_p95_ms"]).is_equal_approx(7.0, 0.0001)
	assert_float(s["work_p95_norm_ms"]).is_equal_approx(4.0, 0.0001)
	assert_float(s["speed_main_pct"]).is_equal_approx(100.0, 0.0001)
	assert_float(s["speed_fog_pct"]).is_equal_approx(50.0, 0.0001)
	assert_array(s["verdicts"]).contains(
		["fog_update_p95_ms: PASS (0.30 ms normalised, 84 updates, limit 0.40)"]
	)
	assert_array(s["verdicts"]).contains(["work_p95_ms: PASS (4.00 ms normalised, limit 5.60)"])
	assert_array(Rig.failed(s)).is_empty()
