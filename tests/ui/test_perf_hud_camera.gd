extends GdUnitTestSuite
## PerfHud, the camera rule (plan P50c, ADR 0014 section 2): the heavy window counts the rigs inside
## the camera, so a camera that moves while a run records makes the run INVALID with
## `camera_moved`, a measurement fault like the others (no verdict can stand, `GATE: FAIL`). The
## view comes from the injectable `camera_source` (any value: the arena gives its visible world
## rect), is read at `restart()` and compared on every recorded frame; any change, however small,
## is a move, and a pan away and back is still one. Without a source (the null Callable) the rule is
## off. `run_again()` calls `before_restart` between the runner's start and `restart()`, so a scene
## can put the view back where a run starts. The arena's own wiring: test_perf_arena_camera.gd. The
## other rules: test_perf_hud_invalid.gd. Nothing here times anything.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const SpyRunner: GDScript = preload("res://tests/ui/support/spy_runner.gd")
## The view a run starts at, and the views a finger can leave the camera at.
const VIEW: Rect2 = Rect2(1000.0, 800.0, 1706.0, 960.0)
const PANNED: Rect2 = Rect2(1064.0, 800.0, 1706.0, 960.0)
const ZOOMED: Rect2 = Rect2(1000.0, 800.0, 853.0, 480.0)
const NUDGED: Rect2 = Rect2(1000.01, 800.0, 1706.0, 960.0)

var _view: Rect2 = VIEW
var _reads: int = 0
var _calls: Array[String] = []
var _sent: Array[String] = []


func before_test() -> void:
	_view = VIEW
	_reads = 0


func after_test() -> void:
	_calls.clear()
	_sent.clear()
	CommandQueue.clear()


func test_the_reason_is_named_camera_moved_and_the_rule_is_off_by_default() -> void:
	assert_str(PerfHud.REASON_CAMERA_MOVED).is_equal("camera_moved")
	var hud: PerfHud = auto_free(PerfHud.new())
	assert_bool(hud.camera_source.is_valid()).is_false()
	assert_bool(hud.before_restart.is_valid()).is_false()


func test_a_pan_a_zoom_or_a_nudge_during_the_run_makes_it_invalid() -> void:
	var cases: Array = [  # label, the frame the camera moves at, the view it moves to
		["pan", 300, PANNED],
		["zoom", 300, ZOOMED],
		["a nudge of 0.01 px", 300, NUDGED],
		["the first frame", 0, PANNED],
		["the last frame", 999, PANNED],
	]
	for c: Array in cases:
		var hud: PerfHud = _hud()
		_frames(hud, {c[1]: c[2]})
		Rig.ticks(hud, hud.run_ticks)
		var s: Dictionary = hud.summary()
		assert_array(s["invalid_reasons"]).override_failure_message(c[0]).is_equal(["camera_moved"])
		assert_bool(s["invalid"]).override_failure_message(c[0]).is_true()
		assert_str(s["verdicts"][0]).is_equal("INVALID: camera_moved")
		assert_array(Rig.failed(s)).override_failure_message(c[0]).is_empty()  # Nothing else failed,
		assert_bool(s["gate_pass"]).override_failure_message(c[0]).is_false()  # yet no pass.
		assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")


func test_a_pan_away_and_back_is_still_a_move() -> void:
	var hud: PerfHud = _hud()
	_frames(hud, {300: PANNED, 301: VIEW})  # The last frame sees the start view again.
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["camera_moved"])
	assert_bool(hud.summary()["gate_pass"]).is_false()


func test_a_still_camera_is_valid_and_the_source_is_read_once_per_recorded_frame() -> void:
	var hud: PerfHud = _hud()
	assert_int(_reads).is_equal(1)  # restart() reads the start view.
	_frames(hud, {})
	assert_int(_reads).is_equal(1001)
	Rig.ticks(hud, hud.run_ticks)
	var s: Dictionary = hud.summary()
	assert_array(s["invalid_reasons"]).is_empty()
	assert_bool(s["invalid"]).is_false()
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["gate_pass"]).is_true()


func test_without_a_source_nothing_is_watched() -> void:
	var hud: PerfHud = auto_free(Rig.hud())  # No source: the test's own _view reaches no one.
	_view = PANNED
	Rig.pass_frames(hud)
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()
	var gone: PerfHud = _hud()
	gone.camera_source = Callable()  # A source taken away mid-run: the rule is off again.
	_view = PANNED
	_frames(gone, {})
	Rig.ticks(gone, gone.run_ticks)
	assert_array(gone.summary()["invalid_reasons"]).is_empty()


func test_restart_reads_the_view_again_and_a_move_between_runs_is_no_fault() -> void:
	var hud: PerfHud = _hud()
	_frames(hud, {500: PANNED})
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["camera_moved"])
	_view = ZOOMED  # Between the runs: the finger is on the camera, the card is up.
	hud.restart()
	assert_array(hud.summary()["invalid_reasons"]).is_empty()  # restart() clears the latch,
	_frames(hud, {})  # and the new run starts at the view it read.
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()


func test_a_move_after_the_run_has_finished_is_no_fault() -> void:
	var hud: PerfHud = _hud()
	_frames(hud, {})
	Rig.ticks(hud, hud.run_ticks)  # The card is up.
	_view = PANNED  # A finger on the camera while the report is read.
	Rig.frame(hud)  # A frame after the end is not recorded.
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_bool(hud.summary()["gate_pass"]).is_true()


func test_the_reason_comes_after_the_other_reasons() -> void:
	var hud: PerfHud = _hud()
	hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_frames(hud, {10: PANNED})
	Rig.ticks(hud, hud.run_ticks)
	var s: Dictionary = hud.summary()
	assert_array(s["invalid_reasons"]).is_equal(["app_paused", "camera_moved"])
	assert_str(s["verdicts"][0]).is_equal("INVALID: app_paused")
	assert_str(s["verdicts"][1]).is_equal("INVALID: camera_moved")


func test_the_card_and_the_copy_report_carry_the_reason() -> void:
	var hud: PerfHud = _hud()
	hud.clipboard_sink = func(text: String) -> void: _sent.append(text)
	_frames(hud, {300: PANNED})
	Rig.ticks(hud, hud.run_ticks)
	var header: Label = hud.get_node("Column/Header")
	assert_str(header.text).starts_with("GATE: FAIL (INVALID: camera_moved) | PERF run")
	hud.copy_report()
	assert_array(_sent).has_size(1)
	var json: JSON = JSON.new()
	assert_int(json.parse(_sent[0])).is_equal(OK)
	var report: Dictionary = json.data
	assert_array(report["invalid_reasons"]).is_equal(["camera_moved"])
	assert_bool(report["invalid"]).is_true()
	assert_bool(report["gate_pass"]).is_false()
	assert_str(report["verdicts"][0]).is_equal("INVALID: camera_moved")
	assert_str(_sent[0]).is_equal(JSON.stringify(hud.summary(), "", true))


## "Run again" calls the hook after the runner's start and before restart(), which then reads the
## view the hook put back: the pan of the run before is not carried into the next one.
func test_run_again_puts_the_view_back_after_the_start_and_before_the_restart() -> void:
	var runner: SpyRunner = _spy_runner()
	var hud: PerfHud = _hud()
	runner.calls = _calls
	hud.runner = runner
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return Rig.BURST
	hud.refresh_source = func() -> float:
		_calls.append("restart")
		return 60.0
	hud.before_restart = func() -> void:
		_calls.append("before_restart")
		_view = VIEW
	_frames(hud, {100: PANNED})  # The pan of the first run, left where it is.
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["camera_moved"])
	var runs: int = hud.summary()["runs"]
	_calls.clear()
	hud.run_again()
	assert_array(_calls).is_equal(["wait_idle", "burst", "start", "before_restart", "restart"])
	_frames(hud, {})
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	assert_int(hud.summary()["runs"]).is_equal(runs + 1)


func test_run_again_without_a_hook_leaves_the_view_alone() -> void:
	var hud: PerfHud = _hud()
	_view = PANNED
	hud.run_again()  # No runner, no hook: only restart(), which reads the view as it is.
	_frames(hud, {})
	Rig.ticks(hud, hud.run_ticks)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()


## A rig HUD whose camera source reads `_view` (and counts its reads), restarted so that it holds
## the start view `VIEW`.
func _hud() -> PerfHud:
	_view = VIEW
	var hud: PerfHud = auto_free(Rig.hud())
	hud.camera_source = func() -> Rect2:
		_reads += 1
		return _view
	hud.restart()
	hud.worker_mode = true  # restart() clears it, as the rig's own setup does.
	return hud


## The frames of a run that passes every verdict (the rig's `pass_frames`), the camera moving to
## `moves[frame]` before that frame is recorded.
func _frames(hud: PerfHud, moves: Dictionary) -> void:
	for i: int in 1000:
		_view = moves.get(i, _view)
		Rig.frame(hud, {"published": i % 4 == 0, "fog": 200 if i % 12 == 0 else -1})


## A SYNC runner on the seed-42 perf arena, started, freed with the case.
func _spy_runner() -> SpyRunner:
	var runner: SpyRunner = auto_free(SpyRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.tick_mode = MatchRunner.TickMode.SYNC
	runner.start()
	return runner
