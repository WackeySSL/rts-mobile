extends GdUnitTestSuite
## TouchInput in a small scene: an RtsCamera, a TouchInput, one Button and a fake clock. Events
## enter the window in window px through the helper, on a 2400x1080 phone (stretch 1.5, so base px
## are window px / 1.5). Snaps are immediate unless a test sets `zoom_snap_ms`.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MAP: Rect2 = Rect2(0, 0, 3072, 3072)
const BUTTON: Rect2 = Rect2(40, 40, 120, 120)  ## Base px, in the top-left corner.
const AWAY: Vector2 = Vector2(800, 400)  ## A map point clear of the button.
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
	_camera.set_map_rect(MAP)
	_camera.centre_on(MAP.get_center())
	var button: Button = auto_free(Button.new())
	button.position = BUTTON.position
	button.size = BUTTON.size
	button.pressed.connect(func() -> void: _presses += 1)
	add_child(button)
	_touch = auto_free(TouchInput.new())
	_touch.settings = _settings
	_touch.camera = _camera
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	add_child(_touch)


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


func test_a_tap_on_the_button_presses_it_and_the_recognizer_never_sees_the_finger() -> void:
	TouchEvents.press(_vp, 0, BUTTON.get_center())
	await await_idle_frame()
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	TouchEvents.release(_vp, 0, BUTTON.get_center())
	await await_idle_frame()
	assert_int(_presses).is_equal(1)


func test_a_drag_that_starts_on_the_button_never_reaches_the_recognizer() -> void:
	var start: Vector2 = _camera.position
	TouchEvents.press(_vp, 0, BUTTON.get_center())
	TouchEvents.drag(_vp, 0, AWAY, AWAY - BUTTON.get_center())
	TouchEvents.release(_vp, 0, AWAY)
	await await_idle_frame()
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	assert_vector(_camera.position).is_equal(start)
	assert_int(_presses).is_equal(0)


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
	await await_idle_frame()
	assert_vector(_camera.position).is_equal(start + Vector2(200, 0))
	assert_int(_presses).is_equal(0)
	assert_int(spy.unhandled).is_equal(0)  # The drags and the release were taken.
	TouchEvents.drag(_vp, 3, AWAY, Vector2(5, 5))  # A finger the map never owned is not.
	assert_int(spy.unhandled).is_equal(1)


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
func test_two_quick_wheel_steps_while_a_snap_is_in_flight_go_two_levels() -> void:
	_settings.zoom_snap_ms = 150
	_camera.zoom = Vector2(0.75, 0.75)
	for step: Array in [[UP, 1.5], [DOWN, 0.75]]:
		TouchEvents.wheel(_vp, step[0], AWAY)
		_camera._snap.pause()  # The tween is stepped by hand: exact, no wall-clock waits.
		_camera._snap.custom_step(0.05)  # A third of the way.
		TouchEvents.wheel(_vp, step[0], AWAY)
		_camera._snap.pause()
		_camera._snap.custom_step(1.0)
		_zoom_is(step[1])


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


func test_focus_loss_cancels_the_gesture() -> void:
	TouchEvents.press(_vp, 0, Vector2(700, 400))
	TouchEvents.press(_vp, 1, Vector2(900, 400))
	TouchEvents.drag(_vp, 1, Vector2(980, 400), Vector2(80, 0))  # x1.4
	_zoom_is(1.4)
	_touch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_zoom_is(1.5)  # CAMERA_END snapped it.
	var at: Vector2 = _camera.position
	TouchEvents.drag(_vp, 0, Vector2(760, 400), Vector2(60, 0))  # The lost finger is nobody's now.
	assert_vector(_camera.position).is_equal(at)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)


func test_long_press_comes_at_300_ms_from_process_and_buzzes_when_haptics_are_on() -> void:
	var start: Vector2 = _camera.position
	_now_ms = 1000
	TouchEvents.press(_vp, 0, AWAY)
	_now_ms = 1299
	await await_idle_frame()
	assert_array(_buzzes).is_empty()
	_now_ms = 1300
	await await_idle_frame()
	assert_array(_buzzes).is_equal([15])
	TouchEvents.drag(_vp, 0, AWAY + Vector2(100, 0), Vector2(100, 0))  # Holding first: a box.
	TouchEvents.release(_vp, 0, AWAY + Vector2(100, 0))
	assert_vector(_camera.position).is_equal(start)
	_settings.haptics_enabled = false
	_now_ms = 2000
	TouchEvents.press(_vp, 0, AWAY)
	_now_ms = 2300
	await await_idle_frame()
	assert_array(_buzzes).has_size(1)


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
