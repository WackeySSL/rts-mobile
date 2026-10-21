extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0014 sections 1 and 3), the defaults of the seams that P50b leaves
## alone and that every other suite replaces with a stub: the build flag, the frame cap and the
## refresh rate read the engine, and the rig and fog seams fail closed (a HUD that nothing has set
## judges no frame heavy and samples no fog update, so its run cannot pass by accident). A wrong
## default misbehaves on a real device only: a debug APK that prints a release build, a 120 Hz panel
## judged against a period without its frame cap, or a 90 Hz panel reported as 60 Hz. The suites
## that stub a seam are test_perf_hud.gd (samples), test_perf_hud_live.gd (the live path) and
## test_perf_hud_verdicts.gd (the lines). Nothing here logs an error (gdUnit4 fails a test that
## does, and so does verify.sh).

## The scripted clock of the live-path case: each call returns the next time of the script (us).
var _times: Array[int] = []
## The engine's frame cap before the case, restored by after_test().
var _max_fps: int = 0


func before_test() -> void:
	_max_fps = Engine.max_fps


func after_test() -> void:
	Engine.max_fps = _max_fps  # The cases below set the engine's frame cap.
	_times.clear()
	CommandQueue.clear()


func test_the_build_flag_defaults_to_the_engines_build_and_the_verdict_follows_it() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	var debug: bool = OS.is_debug_build()
	assert_bool(hud.debug_build).is_equal(debug)
	var s: Dictionary = hud.summary()
	assert_bool(s["debug"]).is_equal(debug)
	# The default gate wants a release template. gdUnit4 itself runs in a debug build, so a `false`
	# default is caught here (a debug APK that printed `build: PASS (release template)`).
	var expected: String = "build: %s (%s template)"
	expected = expected % ["FAIL" if debug else "PASS", "debug" if debug else "release"]
	assert_array(s["verdicts"]).contains([expected])


func test_the_frame_cap_defaults_to_the_engines_max_fps_read_at_each_restart() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	hud.refresh_source = func() -> float: return 120.0
	for cap: int in [60, 30, 0]:
		Engine.max_fps = cap
		var label: String = "max_fps %d" % cap
		assert_int(int(hud.max_fps_source.call())).override_failure_message(label).is_equal(cap)
		hud.restart()
		# P = 1000 / min(refresh, max_fps), a cap of 0 meaning none; the slot V stays the panel's.
		var period: float = 1000.0 / (cap if cap > 0 else 120)
		assert_float(hud.period_ms()).override_failure_message(label).is_equal_approx(
			period, 0.0001
		)
		var drop: float = period + 0.5 * 1000.0 / 120.0
		assert_float(hud.drop_ms()).override_failure_message(label).is_equal_approx(drop, 0.0001)


func test_the_refresh_rate_defaults_to_the_displays() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	var rate: float = DisplayServer.screen_get_refresh_rate()
	assert_float(float(hud.refresh_source.call())).is_equal(rate)
	hud.restart()
	assert_float(hud.refresh_hz_start).is_equal(rate)
	assert_float(hud.refresh_hz_end).is_equal(rate)
	assert_float(hud.summary()["refresh_hz_start"]).is_equal(rate)


func test_a_hud_with_no_rig_or_fog_seam_set_judges_no_frame_heavy_and_samples_no_fog_update(
) -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	assert_int(int(hud.rigs_source.call())).is_equal(0)
	assert_int(int(hud.fog_source.call())).is_equal(-1)  # -1: no fog update since the last call.
	var runner: MatchRunner = auto_free(MatchRunner.new())
	hud.runner = runner
	hud.clock = _scripted_clock
	hud.ref_step = func(_iterations: int) -> void: pass
	add_child(hud)
	hud.restart()
	# Frame 1 anchors; frame 2 (top at 17667, sample 17700 to 17725, drawn at 21725) is recorded.
	_times = [1000, 17667, 17700, 17725, 21725]
	hud._process(0.0)
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	assert_array(_times).is_empty()
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(1)
	assert_int(s["drawn_rigs_max"]).is_equal(0)
	assert_int(s["heavy_frames"]).is_equal(0)  # 0 rigs are below heavy_rigs.
	assert_int(s["fog_updates"]).is_equal(0)
	assert_float(s["fog_update_p95_ms"]).is_equal(0.0)


func _scripted_clock() -> int:
	return _times.pop_front()
