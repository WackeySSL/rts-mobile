extends GdUnitTestSuite
## A turn of the phone is view-only (ADR 0015 sections 1, 3 and 4, plan P62). The main scene on the
## 6-inch phone plays 60 ticks; at tick 30 the phone turns to portrait in the middle of a pan, a
## box, a pinch or a press that has not moved yet; the fingers lift after the turn. Three own
## tanks are selected, so a tap that the turn failed to cancel would be a MOVE order. No Command is
## made, nothing is left in the queue, the selection is the one it was, and the state hash at
## tick 60 is the one of a run with no gesture and no turn. Time is a fake clock, only run_ticks()
## moves the sim, and the Commands are caught on their way into the real CommandQueue.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const START_PROFILE: StringName = &"android_6in"
const TURNED_PROFILE: StringName = &"android_6in_portrait"
const TICKS: int = 60  ## The checkpoints of the state hash are every 15th tick.
const TURN_AT: int = 30
const FINGER: Vector2 = Vector2(400, 300)  ## Base px, clear of the HUD and inside both views.
const SELECTED: PackedInt32Array = [1, 2, 3]
const IDLE_RUN: StringName = &"idle"
## The pinch: two fingers 100 px apart that end 135 px apart, which is zoom 1.35, off a level.
const PINCH_ZOOM: float = 1.35

var _window_size_before: Vector2i
var _now_ms: int = 0
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


## The override, queue and window size are global and must not outlive the test. The scene goes
## first, so no live HUD sees the resize.
func after_test() -> void:
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_a_turn_during_a_pan_a_box_a_pinch_or_a_press_makes_no_command_and_keeps_the_hash(
) -> void:
	var idle: Dictionary = await _play(IDLE_RUN, false)
	assert_int(idle["hash"]).is_not_equal(0)
	assert_int(idle["commands"]).is_equal(0)
	for gesture: StringName in [&"pan", &"box", &"pinch", &"press"]:
		var turned: Dictionary = await _play(gesture, true)
		for key: String in ["hash", "commands", "pending", "selected"]:
			var why: String = "%s turned, %s" % [gesture, key]
			assert_that(turned[key]).override_failure_message(why).is_equal(idle[key])


## The same three gestures with no turn are view-only as well, which is what the hash above is
## compared with. A press with no turn is a tap and an order, which is what the turn must cancel:
## the harness sees it.
func test_a_pan_a_box_and_a_pinch_without_a_turn_leave_the_hash_too_and_a_tap_orders() -> void:
	var idle: Dictionary = await _play(IDLE_RUN, false)
	var tapped: Dictionary = await _play(&"press", false)
	assert_int(tapped["commands"]).is_equal(1)
	assert_int(tapped["hash"]).is_not_equal(idle["hash"])
	for gesture: StringName in [&"pan", &"box", &"pinch"]:
		var upright: Dictionary = await _play(gesture, false)
		assert_that(upright["hash"]).override_failure_message(gesture).is_equal(idle["hash"])
		assert_that(upright["commands"]).override_failure_message(gesture).is_equal(0)


## The turn's cancel is not a gesture end: the camera is not snapped to a level (a CAMERA_END
## would put the zoom on 1.5, as the lift of the same pinch with no turn does).
func test_the_pinch_keeps_its_zoom_through_the_turn_and_the_lift_after_it() -> void:
	var turned: Dictionary = await _play(&"pinch", true)
	assert_float(turned["zoom"]).is_equal_approx(PINCH_ZOOM, 0.0001)
	var upright: Dictionary = await _play(&"pinch", false)
	assert_float(upright["zoom"]).is_equal(1.5)


## A new main scene on the phone with three tanks selected, the gesture started, 30 ticks, the turn
## if asked, the lift, 30 ticks. Returns what the run leaves, and frees the scene.
func _play(gesture: StringName, turn: bool) -> Dictionary:
	await _open()
	_start(gesture)
	_runner.run_ticks(TURN_AT)
	if turn:
		await _use_profile(TURNED_PROFILE)
	_lift(gesture)  # Before the last ticks, so a Command that it makes is in the hash.
	await await_idle_frame()
	_runner.run_ticks(TICKS - TURN_AT)
	assert_int(_runner.world.tick).is_equal(TICKS)
	var selected: Array = Array(_controller.selection.selected)
	var left: Dictionary = {
		"hash": _runner.last_hash,
		"commands": _sent.size(),
		"pending": CommandQueue.pending(),
		"selected": selected,
		"zoom": _camera.zoom.x,
	}
	remove_child(_main)
	_main.free()
	return left


func _open() -> void:
	await _use_profile(START_PROFILE)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_camera = _main.get_node("Camera")
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	add_child(_main)
	await await_idle_frame()
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_controller.selection.set_ids(SELECTED)


func _use_profile(profile_name: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile_name)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()


## The fingers go down and move, and stay down.
func _start(gesture: StringName) -> void:
	var vp: Viewport = get_viewport()
	match gesture:
		&"pan":
			TouchEvents.press(vp, 0, FINGER)
			TouchEvents.drag(vp, 0, FINGER + Vector2(80, 0), Vector2(80, 0))
		&"box":
			TouchEvents.press(vp, 0, FINGER)
			_now_ms += _touch.settings.long_press_ms
			_touch._process(0.0)  # The frame that sees the hold.
			TouchEvents.drag(vp, 0, FINGER + Vector2(80, 60), Vector2(80, 60))
		&"pinch":
			TouchEvents.press(vp, 0, FINGER - Vector2(50, 0))
			TouchEvents.press(vp, 1, FINGER + Vector2(50, 0))
			TouchEvents.drag(vp, 1, FINGER + Vector2(85, 0), Vector2(35, 0))
		&"press":
			TouchEvents.press(vp, 0, FINGER)


## The fingers lift where they were.
func _lift(gesture: StringName) -> void:
	var vp: Viewport = get_viewport()
	_now_ms += 1000
	match gesture:
		&"pan":
			TouchEvents.release(vp, 0, FINGER + Vector2(80, 0))
		&"box":
			TouchEvents.release(vp, 0, FINGER + Vector2(80, 60))
		&"pinch":
			TouchEvents.release(vp, 1, FINGER + Vector2(85, 0))
			TouchEvents.release(vp, 0, FINGER - Vector2(50, 0))
		&"press":
			TouchEvents.release(vp, 0, FINGER)
