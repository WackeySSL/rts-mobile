extends GdUnitTestSuite
## TouchInput in a small scene: an RtsCamera, a TouchInput, one Button and a fake clock. Events
## enter the window in window px through the helper, on a 2400x1080 phone (stretch 1.5, so base px
## are window px / 1.5). Snaps are immediate unless a test sets `zoom_snap_ms`.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const GestureSpy: GDScript = preload("res://tests/input/support/gesture_spy.gd")
const MAP_TILES: int = 48  ## The map is 48 x 48 tiles: a diamond 3072 px wide.
const MAP_CENTRE: Vector2 = Vector2(0, 768)  ## The middle of that diamond.
const BUTTON: Rect2 = Rect2(40, 40, 120, 120)  ## Base px, in the top-left corner.
const AWAY: Vector2 = Vector2(800, 400)  ## A map point clear of the button.
const INSIDE: Vector2 = Vector2(300, 400)  ## A map point clear of the button in either view.
const UP: int = MOUSE_BUTTON_WHEEL_UP
const DOWN: int = MOUSE_BUTTON_WHEEL_DOWN

var _window_size_before: Vector2i
var _settings: InputSettings
var _camera: RtsCamera
var _touch: TouchInput
var _vp: Viewport
var _now_ms: int = 0
var _presses: int = 0
var _buzzes: Array[int] = []


## Counts the drags and releases that reached `_unhandled_input`: nobody took them.
class UnhandledSpy:
	extends Node
	var unhandled: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventScreenDrag or (event is InputEventScreenTouch and not event.pressed):
			unhandled += 1


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	await _use_profile(&"android_6in")
	_vp = get_viewport()
	_now_ms = 0
	_presses = 0
	_buzzes.clear()
	_settings = (load("res://data/input_settings.tres") as InputSettings).duplicate()
	_settings.zoom_snap_ms = 0
	_camera = auto_free(RtsCamera.new())
	_camera.settings = _settings
	add_child(_camera)
	_camera.set_map_rect(IsoProjection.map_diamond(MAP_TILES, MAP_TILES))
	_camera.centre_on(MAP_CENTRE)
	var hud: CanvasLayer = auto_free(CanvasLayer.new())  # As in main.tscn: the camera cannot move it.
	add_child(hud)
	var button: Button = Button.new()
	button.position = BUTTON.position
	button.size = BUTTON.size
	button.pressed.connect(func() -> void: _presses += 1)
	hud.add_child(button)
	_touch = auto_free(TouchInput.new())
	_touch.settings = _settings
	_touch.camera = _camera
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	add_child(_touch)
	await await_idle_frame()  # The camera moves the canvas on the first frame.


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_a_one_finger_drag_pans_in_base_px_and_a_canceled_release_is_not_a_last_move() -> void:
	var start: Vector2 = _camera.position
	TouchEvents.press(_vp, 0, AWAY)
	TouchEvents.drag(_vp, 0, AWAY + Vector2(100, 40), Vector2(100, 40))  # Past the slop at once.
	TouchEvents.drag(_vp, 0, AWAY + Vector2(150, 40), Vector2(50, 0))
	TouchEvents.release(_vp, 0, AWAY + Vector2(400, 40), true)
	assert_vector(_camera.position).is_equal(start - Vector2(150, 40))


func test_the_slop_is_12_dp_in_base_px_and_follows_the_window() -> void:
	var slops: Dictionary[StringName, float] = {
		&"desktop": 12.0, &"android_6in": 21.0, &"web_tablet": 15.0
	}
	for profile: StringName in slops:
		await _use_profile(profile)  # TouchInput reconfigures on size_changed.
		var moved: Array[float] = [_pan_by(slops[profile] - 1.0), _pan_by(slops[profile] + 1.0)]
		assert_array(moved).override_failure_message(profile).is_equal([0.0, slops[profile] + 1.0])


func test_a_touch_that_starts_on_the_button_stays_with_it_even_for_a_stale_map_finger() -> void:
	var middle: Vector2 = BUTTON.get_center()
	TouchEvents.press(_vp, 0, AWAY)  # Finger 0 pans the map, then its release is lost.
	TouchEvents.drag(_vp, 0, AWAY + Vector2(60, 0), Vector2(60, 0))
	var start: Vector2 = _camera.position
	TouchEvents.press(_vp, 0, middle)  # The same index, now on the button.
	TouchEvents.drag(_vp, 0, middle + Vector2(4, 0), Vector2(4, 0))
	TouchEvents.release(_vp, 0, middle)
	assert_int(_presses).is_equal(1)
	assert_vector(_camera.position).is_equal(start)
	TouchEvents.press(_vp, 0, middle)
	TouchEvents.drag(_vp, 0, AWAY, AWAY - middle)  # Dragged off the button: not a pan either.
	TouchEvents.release(_vp, 0, AWAY)
	assert_vector(_camera.position).is_equal(start)


func test_a_pan_that_crosses_the_button_keeps_panning_and_does_not_press_it() -> void:
	var start: Vector2 = _camera.position
	var over: Vector2 = BUTTON.get_center()  # (100, 100)
	var spy: UnhandledSpy = auto_free(UnhandledSpy.new())
	add_child(spy)
	TouchEvents.press(_vp, 0, Vector2(300, 100))
	TouchEvents.drag(_vp, 0, over, Vector2(-200, 0))
	assert_vector(_camera.position).is_equal(start + Vector2(200, 0))
	TouchEvents.drag(_vp, 0, Vector2(20, 100), Vector2(-80, 0))  # Past it, on the margin.
	TouchEvents.drag(_vp, 0, over, Vector2(80, 0))  # Back, and let go over it.
	TouchEvents.release(_vp, 0, over)
	assert_vector(_camera.position).is_equal(start + Vector2(200, 0))
	assert_int(spy.unhandled).is_equal(0)  # The drags and the release were taken: the proof.
	TouchEvents.drag(_vp, 0, AWAY, Vector2(5, 5))  # Finger 0 is up: the map owns nothing now.
	assert_int(spy.unhandled).is_equal(1)
	TouchEvents.release(_vp, 5, AWAY)  # A stray release starts nothing.
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)


func test_mouse_buttons_and_motion_are_ignored_and_the_wheel_steps_the_zoom() -> void:
	var start: Vector2 = _camera.position
	var at: Vector2 = _vp.get_final_transform() * AWAY
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	_vp.push_input(click)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = at + Vector2(90, 0)
	motion.relative = Vector2(90, 0)
	_vp.push_input(motion)
	assert_vector(_camera.position).is_equal(start)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	var world: Vector2 = _camera.screen_to_world(AWAY)
	for step: Array in [[UP, 1.5], [DOWN, 1.0], [DOWN, 0.75], [DOWN, 0.75]]:
		TouchEvents.wheel(_vp, step[0], AWAY)
		_zoom_is(step[1])
		assert_vector(_camera.screen_to_world(AWAY)).is_equal_approx(world, Vector2.ONE * 0.5)


## Half way the zoom (0.833 or 1.333) is still nearest the old level: counting from it loses a step.
func test_two_quick_wheel_steps_go_two_levels_even_with_a_pan_released_in_between() -> void:
	_settings.zoom_snap_ms = 150
	for c: Array in [[0.75, UP, UP, 1.5], [1.5, DOWN, DOWN, 0.75], [1.0, DOWN, UP, 1.0]]:
		_camera.zoom = Vector2(c[0], c[0])
		TouchEvents.wheel(_vp, c[1], AWAY)
		_camera._snap.pause()  # The tween is stepped by hand: exact, no wall-clock waits.
		_camera._snap.custom_step(0.05)  # A third of the way.
		_pan_by(30.0)  # Its release ends the gesture: the snap keeps its level.
		TouchEvents.wheel(_vp, c[2], AWAY)
		_camera._snap.pause()
		_camera._snap.custom_step(1.0)
		_zoom_is(c[3])


func test_a_pinch_zooms_about_the_centroid_applying_every_event_and_snaps_on_release() -> void:
	var world: Vector2 = _camera.screen_to_world(Vector2(800, 400))
	TouchEvents.press(_vp, 0, Vector2(700, 400))
	TouchEvents.press(_vp, 1, Vector2(900, 400))  # 200 apart.
	TouchEvents.drag(_vp, 0, Vector2(670, 400), Vector2(-30, 0))  # x1.15, the centroid is at 785.
	TouchEvents.drag(_vp, 1, Vector2(940, 400), Vector2(40, 0))  # x1.174, the centroid is at 805.
	_zoom_is(1.35)
	var under: Vector2 = _camera.screen_to_world(Vector2(805, 400))
	assert_vector(under).is_equal_approx(world, Vector2.ONE * 0.5)
	TouchEvents.release(_vp, 1, Vector2(940, 400))
	TouchEvents.release(_vp, 0, Vector2(670, 400))
	_zoom_is(1.5)


func test_focus_loss_cancels_the_gesture_and_the_lost_finger_is_nobodys() -> void:
	var spy: UnhandledSpy = auto_free(UnhandledSpy.new())
	add_child(spy)
	for what: int in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_camera.zoom = Vector2.ONE
		spy.unhandled = 0
		TouchEvents.press(_vp, 0, Vector2(700, 400))
		TouchEvents.press(_vp, 1, Vector2(900, 400))
		TouchEvents.drag(_vp, 1, Vector2(980, 400), Vector2(80, 0))  # x1.4
		_zoom_is(1.4)
		_touch.notification(what)
		_zoom_is(1.5)  # CAMERA_END snapped it.
		var at: Vector2 = _camera.position
		TouchEvents.drag(_vp, 0, Vector2(760, 400), Vector2(60, 0))  # Finger 0 is lost.
		assert_vector(_camera.position).is_equal(at)
		assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
		assert_int(spy.unhandled).override_failure_message(str(what)).is_equal(1)


func test_long_press_comes_at_300_ms_from_process_and_buzzes_when_haptics_are_on() -> void:
	var start: Vector2 = _camera.position
	_settings.haptic_ms = 25  # Not the default: a hardcoded buzz fails.
	_now_ms = 1000
	TouchEvents.press(_vp, 0, AWAY)
	_now_ms = 1299
	await await_idle_frame()
	assert_array(_buzzes).is_empty()
	_now_ms = 1300
	await await_idle_frame()
	assert_array(_buzzes).is_equal([25])
	TouchEvents.drag(_vp, 0, AWAY + Vector2(100, 0), Vector2(100, 0))  # Holding first: a box.
	TouchEvents.release(_vp, 0, AWAY + Vector2(100, 0))
	assert_vector(_camera.position).is_equal(start)
	_settings.haptics_enabled = false
	_now_ms = 2000
	TouchEvents.press(_vp, 0, AWAY)
	_now_ms = 2300
	await await_idle_frame()
	assert_array(_buzzes).has_size(1)


## A turn of the phone ends every gesture in flight (ADR 0015 section 3, plan P62). The zoom is
## between levels, so a CAMERA_END that reached the camera would snap it, and a lift after the turn
## must make no tap and no box. The turn is 2400x1080 to 1080x2400: the stretch is 1.5 both ways, so
## the camera keeps the zoom and only the gesture handling is under test.
func test_a_turn_during_a_pan_ends_it_with_no_snap_and_its_lift_is_nothing() -> void:
	var spy: GestureSpy = _spy()
	_camera.zoom = Vector2(1.2, 1.2)
	TouchEvents.press(_vp, 0, INSIDE)
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(100, 0), Vector2(100, 0))
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.PAN)
	await _use_profile(&"android_6in_portrait")
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	_zoom_is(1.2)  # A CAMERA_END would have snapped it to 1.0.
	var at: Vector2 = _camera.position
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(300, 0), Vector2(200, 0))  # The finger goes on.
	TouchEvents.release(_vp, 0, INSIDE + Vector2(300, 0))
	assert_vector(_camera.position).is_equal(at)
	_zoom_is(1.2)
	assert_array(spy.kinds).is_empty()


func test_a_turn_during_a_box_cancels_it_for_the_controller_and_its_lift_is_no_box_end() -> void:
	var spy: GestureSpy = _spy()
	_now_ms = 1000
	TouchEvents.press(_vp, 0, INSIDE)
	_now_ms = 1300
	await await_idle_frame()  # The frame that sees the hold.
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(100, 60), Vector2(100, 60))
	var started: Array[int] = [GestureEvent.Kind.LONG_PRESS, GestureEvent.Kind.BOX_UPDATE]
	assert_array(spy.kinds).is_equal(started)
	await _use_profile(&"android_6in_portrait")
	assert_array(spy.kinds).is_equal(started + [GestureEvent.Kind.BOX_CANCEL])
	TouchEvents.release(_vp, 0, INSIDE + Vector2(100, 60))
	await await_idle_frame()
	assert_array(spy.kinds).has_size(3)  # No BOX_END and no TAP.
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)


func test_a_turn_during_a_pinch_leaves_the_zoom_off_its_level_and_the_lifts_are_nothing() -> void:
	var spy: GestureSpy = _spy()
	TouchEvents.press(_vp, 0, INSIDE - Vector2(50, 0))
	TouchEvents.press(_vp, 1, INSIDE + Vector2(150, 0))  # 200 apart.
	TouchEvents.drag(_vp, 1, INSIDE + Vector2(230, 0), Vector2(80, 0))  # x1.4
	_zoom_is(1.4)
	await _use_profile(&"android_6in_portrait")
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	_zoom_is(1.4)  # A CAMERA_END would have snapped it to 1.5.
	var at: Vector2 = _camera.position
	TouchEvents.release(_vp, 1, INSIDE + Vector2(230, 0))
	TouchEvents.release(_vp, 0, INSIDE - Vector2(50, 0))
	assert_vector(_camera.position).is_equal(at)
	_zoom_is(1.4)
	assert_array(spy.kinds).is_empty()


func test_a_press_that_has_not_moved_is_no_tap_after_a_turn() -> void:
	var spy: GestureSpy = _spy()
	TouchEvents.press(_vp, 0, INSIDE)
	await _use_profile(&"android_6in_portrait")
	TouchEvents.release(_vp, 0, INSIDE)
	assert_array(spy.kinds).is_empty()
	TouchEvents.press(_vp, 0, INSIDE)  # The next touch is a tap as ever.
	TouchEvents.release(_vp, 0, INSIDE)
	assert_array(spy.kinds).is_equal([GestureEvent.Kind.TAP])


## The camera connects before TouchInput in main.tscn and a camera built after it runs after it:
## either way no CAMERA_END reaches the camera, because TouchInput keeps its own orientation.
func test_the_camera_is_spared_whichever_handler_runs_first() -> void:
	_camera = auto_free(RtsCamera.new())  # Connected after TouchInput's handler now.
	_camera.settings = _settings
	add_child(_camera)
	_camera.set_map_rect(IsoProjection.map_diamond(MAP_TILES, MAP_TILES))
	_camera.centre_on(MAP_CENTRE)
	_touch.camera = _camera
	_camera.zoom = Vector2(1.2, 1.2)
	TouchEvents.press(_vp, 0, INSIDE)
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(100, 0), Vector2(100, 0))
	await _use_profile(&"android_6in_portrait")
	_zoom_is(1.2)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	await _use_profile(&"android_6in")  # And turning back is a turn again.
	TouchEvents.press(_vp, 0, INSIDE)
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(100, 0), Vector2(100, 0))
	await _use_profile(&"android_6in_portrait")
	_zoom_is(1.2)


## A browser toolbar or a window drag is not a turn: the gesture goes on and the slop follows.
func test_a_resize_within_one_orientation_leaves_the_gesture_alone() -> void:
	TouchEvents.press(_vp, 0, INSIDE)
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(100, 0), Vector2(100, 0))
	var at: Vector2 = _camera.position
	await _use_profile(&"web_tablet")
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.PAN)
	TouchEvents.drag(_vp, 0, INSIDE + Vector2(150, 0), Vector2(50, 0))
	assert_vector(_camera.position).is_not_equal(at)  # Still panning.


func _spy() -> GestureSpy:
	var spy: GestureSpy = auto_free(GestureSpy.new())
	add_child(spy)
	_touch.controller = spy
	return spy


func _use_profile(profile_name: StringName) -> void:
	var profile: UiMetrics = UiProfiles.by_name(profile_name)
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()


## A one-finger drag to the right by `distance` base px. Returns how far the camera moved left.
func _pan_by(distance: float) -> float:
	var start_x: float = _camera.position.x
	var to: Vector2 = AWAY + Vector2(distance, 0)
	TouchEvents.press(_vp, 0, AWAY)
	TouchEvents.drag(_vp, 0, to, Vector2(distance, 0))
	TouchEvents.release(_vp, 0, to)
	return snappedf(start_x - _camera.position.x, 0.001)


func _zoom_is(expected: float) -> void:
	assert_vector(_camera.zoom).is_equal_approx(Vector2(expected, expected), Vector2.ONE * 0.0001)
