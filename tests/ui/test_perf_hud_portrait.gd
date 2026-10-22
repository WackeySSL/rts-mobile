extends GdUnitTestSuite
## PerfHud, the portrait rule (plan P63b, ADR 0015, ADR 0011 section 5): the perf gate is a
## landscape measurement (a portrait view shows too few of the 150 rigs for the heavy window), and
## the web preview cannot lock the screen. So a run during which the viewport is portrait at any
## recorded frame is INVALID with `portrait`, a measurement fault like the others (no verdict can
## stand, `GATE: FAIL`). The size comes from the injectable `view_size_source` (the viewport's
## visible size; the default is (0, 0) outside the tree), is read once per recorded frame and
## judged by `UiScale.is_portrait_size()`. The latch holds when the phone is turned back, and
## `restart()` clears it. A landscape run is as it was: its summary, verdicts and card are those of
## a HUD with no source. The same rule on the real viewport: test_perf_arena_portrait.gd. The
## camera rule: test_perf_hud_camera.gd. Nothing here times anything.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
## A square view is landscape (ADR 0015 section 2: portrait is taller than wide), one pixel taller
## is not.
const SQUARE: Vector2i = Vector2i(1000, 1000)
const TALLER: Vector2i = Vector2i(1000, 1001)

var _size: Vector2i = ScreenSizes.LANDSCAPE[0]
var _reads: int = 0
var _sent: Array[String] = []


func before_test() -> void:
	_size = ScreenSizes.LANDSCAPE[0]
	_reads = 0


func after_test() -> void:
	_sent.clear()
	CommandQueue.clear()


func test_the_reason_is_named_portrait_and_a_hud_outside_the_tree_has_no_such_fault() -> void:
	assert_str(PerfHud.REASON_PORTRAIT).is_equal("portrait")
	var hud: PerfHud = auto_free(Rig.hud())
	assert_bool(hud.view_size_source.is_valid()).is_true()
	assert_object(hud.view_size_source.get_object()).is_same(hud)
	assert_that(hud.view_size_source.call()).is_equal(Vector2i.ZERO)  # No viewport, no size.
	Rig.run(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()


func test_a_portrait_frame_anywhere_in_the_run_makes_it_invalid() -> void:
	for portrait: Vector2i in ScreenSizes.PORTRAIT:
		for at: int in [0, 300, 999]:  # The first frame, one in the middle and the last.
			var hud: PerfHud = _hud()
			_frames(hud, {at: portrait})
			Rig.ticks(hud, hud.run_ticks)
			var s: Dictionary = hud.summary()
			var label: String = "%s at frame %d" % [portrait, at]
			assert_array(s["invalid_reasons"]).override_failure_message(label).is_equal(
				["portrait"]
			)
			assert_bool(s["invalid"]).override_failure_message(label).is_true()
			assert_str(s["verdicts"][0]).is_equal("INVALID: portrait")
			assert_array(Rig.failed(s)).override_failure_message(label).is_empty()  # No row failed,
			assert_bool(s["gate_pass"]).override_failure_message(label).is_false()  # yet no pass.
			assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")


func test_a_run_in_portrait_throughout_is_invalid_and_in_landscape_throughout_is_not() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var hud: PerfHud = _hud()
		_size = size
		Rig.pass_frames(hud)
		Rig.ticks(hud, hud.run_ticks)
		var portrait: bool = ScreenSizes.PORTRAIT.has(size)
		var s: Dictionary = hud.summary()
		var want: Array = ["portrait"] if portrait else []
		assert_array(s["invalid_reasons"]).override_failure_message(str(size)).is_equal(want)
		assert_bool(s["gate_pass"]).override_failure_message(str(size)).is_equal(not portrait)


func test_a_square_view_is_landscape_and_one_pixel_taller_is_portrait() -> void:
	for row: Array in [[SQUARE, []], [TALLER, ["portrait"]]]:
		var hud: PerfHud = _hud()
		_size = row[0]
		Rig.pass_frames(hud)
		Rig.ticks(hud, hud.run_ticks)
		(
			assert_array(hud.summary()["invalid_reasons"])
			. override_failure_message(str(row[0]))
			. is_equal(row[1])
		)


## A phone turned upright and back: the turn is not forgiven, the run measured a portrait frame.
func test_turning_the_phone_back_does_not_clear_the_fault() -> void:
	var hud: PerfHud = _hud()
	_frames(hud, {300: ScreenSizes.PORTRAIT[1], 301: ScreenSizes.LANDSCAPE[1]})
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["portrait"])
	assert_bool(hud.summary()["gate_pass"]).is_false()


func test_a_landscape_run_is_as_it_was_and_the_source_is_read_once_per_recorded_frame() -> void:
	var hud: PerfHud = _hud()
	assert_int(_reads).is_equal(0)  # restart() does not read: only a recorded frame is judged.
	_size = ScreenSizes.LANDSCAPE[2]
	Rig.pass_frames(hud)
	assert_int(_reads).is_equal(1000)
	Rig.ticks(hud, hud.run_ticks)
	var bare: PerfHud = auto_free(Rig.hud())  # The rig's HUD with no portrait in sight.
	Rig.run(bare)
	var s: Dictionary = hud.summary()
	assert_array(s["invalid_reasons"]).is_empty()
	assert_bool(s["gate_pass"]).is_true()
	assert_array(s["verdicts"]).is_equal(bare.summary()["verdicts"])
	assert_array(hud.card_lines().slice(1)).is_equal(bare.card_lines().slice(1))  # Past "run N".
	assert_str(hud.card_lines()[-1]).is_equal("GATE: PASS")


func test_without_a_source_nothing_is_watched() -> void:
	var hud: PerfHud = _hud()
	hud.view_size_source = Callable()  # A null Callable is no rule.
	_size = ScreenSizes.PORTRAIT[1]
	Rig.pass_frames(hud)
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()
	assert_int(_reads).is_equal(0)


func test_restart_clears_the_fault_and_a_portrait_view_between_runs_is_no_fault() -> void:
	var hud: PerfHud = _hud()
	_frames(hud, {500: ScreenSizes.PORTRAIT[0]})
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["portrait"])
	_size = ScreenSizes.PORTRAIT[2]  # Between the runs: the phone is upright, the card is up.
	hud.restart()
	assert_array(hud.summary()["invalid_reasons"]).is_empty()  # No frame of the new run yet,
	_size = ScreenSizes.LANDSCAPE[0]  # and the phone is turned before the first one records.
	_frames(hud, {})
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()
	_size = ScreenSizes.PORTRAIT[0]
	hud.restart()
	Rig.frame(hud)  # A run that starts upright is judged at its first frame.
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["portrait"])


func test_a_portrait_view_after_the_run_has_finished_is_no_fault() -> void:
	var hud: PerfHud = _hud()
	_frames(hud, {})
	Rig.ticks(hud, hud.run_ticks)  # The card is up.
	_size = ScreenSizes.PORTRAIT[0]  # The phone is turned to read the report.
	Rig.frame(hud)  # A frame after the end is not recorded.
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()


func test_the_reason_comes_after_the_camera_and_the_other_reasons() -> void:
	var hud: PerfHud = _hud()
	var view: Array[Rect2] = [Rect2(0.0, 0.0, 100.0, 50.0)]
	hud.camera_source = func() -> Rect2: return view[0]
	hud.restart()
	hud.worker_mode = true
	hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_size = ScreenSizes.PORTRAIT[0]
	view[0] = Rect2(10.0, 0.0, 100.0, 50.0)
	Rig.pass_frames(hud)
	Rig.ticks(hud, hud.run_ticks)
	var s: Dictionary = hud.summary()
	assert_array(s["invalid_reasons"]).is_equal(["app_paused", "camera_moved", "portrait"])
	assert_array(s["verdicts"].slice(0, 3)).is_equal(
		["INVALID: app_paused", "INVALID: camera_moved", "INVALID: portrait"]
	)


func test_the_card_and_the_copy_report_carry_the_reason() -> void:
	var hud: PerfHud = _hud()
	hud.clipboard_sink = func(text: String) -> void: _sent.append(text)
	_frames(hud, {300: ScreenSizes.PORTRAIT[1]})
	Rig.ticks(hud, hud.run_ticks)
	var header: Label = hud.get_node("Column/Header")
	assert_str(header.text).starts_with("GATE: FAIL (INVALID: portrait) | PERF run")
	hud.copy_report()
	assert_array(_sent).has_size(1)
	var json: JSON = JSON.new()
	assert_int(json.parse(_sent[0])).is_equal(OK)
	var report: Dictionary = json.data
	assert_array(report["invalid_reasons"]).is_equal(["portrait"])
	assert_bool(report["invalid"]).is_true()
	assert_bool(report["gate_pass"]).is_false()
	assert_str(report["verdicts"][0]).is_equal("INVALID: portrait")
	assert_str(_sent[0]).is_equal(JSON.stringify(hud.summary(), "", true))


## A rig HUD (restarted, a worker run) whose view size source reads `_size` and counts its reads.
func _hud() -> PerfHud:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.view_size_source = func() -> Vector2i:
		_reads += 1
		return _size
	_reads = 0
	return hud


## The frames of a run that passes every verdict (the rig's `pass_frames`), the view taking the
## size `sizes[frame]` for that frame alone and the landscape one before and after it.
func _frames(hud: PerfHud, sizes: Dictionary) -> void:
	for i: int in 1000:
		_size = sizes.get(i, ScreenSizes.LANDSCAPE[0])
		Rig.frame(hud, {"published": i % 4 == 0, "fog": 200 if i % 12 == 0 else -1})
