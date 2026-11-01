extends GdUnitTestSuite
## TouchInput.map_gesture (plan P85f, ADR 0024 section 5): the build menu collapses on the first
## event of a gesture made from a press the GUI did not take: TAP, DOUBLE_TAP, LONG_PRESS, PAN,
## PINCH and GHOST_DRAG, and on a wheel step. It is emitted once per gesture and before that event
## is routed, so the gesture then does what it always did. The ends and cancels of a gesture (BOX_*,
## CAMERA_END), a turn's and a focus loss's cancel_all(), a press on a Control, and mouse buttons
## and motion never emit it. A small scene as in test_touch_input: a camera, a TouchInput, a button
## and a fake clock, on a 2400x1080 phone. The menu's reaction is test_build_menu_triggers.gd's.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const GestureSpy: GDScript = preload("res://tests/input/support/gesture_spy.gd")
const MAP_TILES: int = 48
const MAP_CENTRE: Vector2 = Vector2(0, 768)
const BUTTON: Rect2 = Rect2(40, 40, 120, 120)  ## Base px, in the top-left corner.
const AWAY: Vector2 = Vector2(800, 400)  ## A map point clear of the button.

var _window_size_before: Vector2i
var _settings: InputSettings
var _camera: RtsCamera
var _touch: TouchInput
var _spy: GestureSpy
var _vp: Viewport
var _now_ms: int = 0
var _told: Array[Dictionary] = []  ## What the camera and the controller had seen at each emission.
var _presses: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	var profile: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_vp = get_viewport()
	_now_ms = 0
	_presses = 0
	_told.clear()
	_settings = (load("res://data/input_settings.tres") as InputSettings).duplicate()
	_settings.zoom_snap_ms = 0
	_camera = auto_free(RtsCamera.new())
	_camera.settings = _settings
	add_child(_camera)
	_camera.set_map_rect(IsoProjection.map_diamond(MAP_TILES, MAP_TILES))
	_camera.centre_on(MAP_CENTRE)
	var hud: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(hud)
	var button: Button = Button.new()
	button.position = BUTTON.position
	button.size = BUTTON.size
	button.pressed.connect(func() -> void: _presses += 1)
	hud.add_child(button)
	_spy = auto_free(GestureSpy.new())
	add_child(_spy)
	_touch = auto_free(TouchInput.new())
	_touch.settings = _settings
	_touch.camera = _camera
	_touch.controller = _spy
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_touch.map_gesture.connect(_on_map_gesture)
	add_child(_touch)
	await await_idle_frame()


func after_test() -> void:
	UiScale.clear_override()


func _on_map_gesture() -> void:
	_told.append({"camera": _camera.position, "gestures": _spy.kinds.size()})


func test_a_tap_a_double_tap_and_a_long_press_each_tell_once_before_the_controller_hears() -> void:
	TouchEvents.press(_vp, 0, AWAY)
	_now_ms += 50
	TouchEvents.release(_vp, 0, AWAY)
	assert_array(_spy.kinds).is_equal([GestureEvent.Kind.TAP])
	assert_array(_told).has_size(1)
	assert_int(_told[0]["gestures"]).is_equal(0)  # Told first, then the tap was routed.
	_now_ms += 100
	TouchEvents.press(_vp, 0, AWAY)
	_now_ms += 50
	TouchEvents.release(_vp, 0, AWAY)
	assert_array(_spy.kinds).is_equal([GestureEvent.Kind.TAP, GestureEvent.Kind.DOUBLE_TAP])
	assert_array(_told).has_size(2)  # Its own gesture: a second touch.
	assert_int(_told[1]["gestures"]).is_equal(1)
	_now_ms += 1000
	_told.clear()
	_spy.kinds.clear()
	TouchEvents.press(_vp, 0, AWAY)
	assert_array(_told).is_empty()  # A press alone is not a gesture yet.
	_now_ms += _settings.long_press_ms
	_touch._process(0.0)
	assert_array(_spy.kinds).is_equal([GestureEvent.Kind.LONG_PRESS])
	assert_array(_told).has_size(1)
	assert_int(_told[0]["gestures"]).is_equal(0)
	TouchEvents.drag(_vp, 0, AWAY + Vector2(80, 60), Vector2(80, 60))  # The box: BOX_UPDATE.
	TouchEvents.release(_vp, 0, AWAY + Vector2(80, 60))  # BOX_END.
	assert_array(_told).has_size(1)  # The rest of the hold-and-drag is one gesture.
	assert_array(_spy.kinds).contains([GestureEvent.Kind.BOX_END])


func test_a_pan_tells_once_before_the_camera_moves_and_the_next_pan_tells_again() -> void:
	var start: Vector2 = _camera.position
	TouchEvents.press(_vp, 0, AWAY)
	TouchEvents.drag(_vp, 0, AWAY + Vector2(100, 0), Vector2(100, 0))
	TouchEvents.drag(_vp, 0, AWAY + Vector2(150, 0), Vector2(50, 0))
	TouchEvents.drag(_vp, 0, AWAY + Vector2(200, 0), Vector2(50, 0))
	assert_array(_told).has_size(1)
	assert_vector(_told[0]["camera"]).is_equal(start)  # Told before the first pan moved it.
	assert_vector(_camera.position).is_not_equal(start)  # And the pan still did its work.
	TouchEvents.release(_vp, 0, AWAY + Vector2(200, 0))  # CAMERA_END: not a gesture of its own.
	assert_array(_told).has_size(1)
	TouchEvents.press(_vp, 0, AWAY)
	TouchEvents.drag(_vp, 0, AWAY + Vector2(100, 0), Vector2(100, 0))
	TouchEvents.release(_vp, 0, AWAY + Vector2(100, 0))
	assert_array(_told).has_size(2)


func test_a_pinch_tells_once_and_a_second_finger_joining_a_pan_does_not_tell_again() -> void:
	TouchEvents.press(_vp, 0, Vector2(700, 400))
	TouchEvents.drag(_vp, 0, Vector2(760, 400), Vector2(60, 0))  # The pan, told.
	assert_array(_told).has_size(1)
	TouchEvents.press(_vp, 1, Vector2(900, 400))
	TouchEvents.drag(_vp, 1, Vector2(960, 400), Vector2(60, 0))  # Now a pinch: the same gesture.
	TouchEvents.drag(_vp, 0, Vector2(730, 400), Vector2(-30, 0))
	assert_array(_told).has_size(1)
	TouchEvents.release(_vp, 1, Vector2(960, 400))
	TouchEvents.release(_vp, 0, Vector2(730, 400))
	assert_array(_told).has_size(1)
	TouchEvents.press(_vp, 0, Vector2(700, 400))  # Two fresh fingers: a new gesture.
	TouchEvents.press(_vp, 1, Vector2(900, 400))
	var start: Vector2 = _camera.zoom
	TouchEvents.drag(_vp, 1, Vector2(980, 400), Vector2(80, 0))
	assert_array(_told).has_size(2)
	assert_vector(_camera.zoom).is_not_equal(start)  # The pinch did its work.
	TouchEvents.release(_vp, 1, Vector2(980, 400))
	TouchEvents.release(_vp, 0, Vector2(700, 400))


func test_a_ghost_drag_tells_once_on_its_first_event() -> void:
	_touch._recognizer.grab_test = func(_at: Vector2) -> bool: return true
	TouchEvents.press(_vp, 0, AWAY)
	assert_array(_told).is_empty()
	TouchEvents.drag(_vp, 0, AWAY + Vector2(60, 0), Vector2(60, 0))
	TouchEvents.drag(_vp, 0, AWAY + Vector2(90, 0), Vector2(30, 0))
	assert_array(_spy.kinds).contains([GestureEvent.Kind.GHOST_DRAG])
	assert_array(_told).has_size(1)
	assert_int(_told[0]["gestures"]).is_equal(0)
	TouchEvents.release(_vp, 0, AWAY + Vector2(90, 0))
	assert_array(_told).has_size(1)


func test_a_wheel_step_tells_per_notch_and_mouse_buttons_and_motion_tell_nothing() -> void:
	TouchEvents.wheel(_vp, MOUSE_BUTTON_WHEEL_UP, AWAY)
	TouchEvents.wheel(_vp, MOUSE_BUTTON_WHEEL_DOWN, AWAY)
	assert_array(_told).has_size(2)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _vp.get_final_transform() * AWAY
	_vp.push_input(click)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = click.position + Vector2(90, 0)
	motion.relative = Vector2(90, 0)
	_vp.push_input(motion)
	assert_array(_told).has_size(2)


func test_a_touch_on_a_control_never_tells_whatever_it_does() -> void:
	var middle: Vector2 = BUTTON.get_center()
	TouchEvents.press(_vp, 0, middle)
	_now_ms += 50
	TouchEvents.release(_vp, 0, middle)  # A tap on the button.
	assert_int(_presses).is_equal(1)
	TouchEvents.press(_vp, 0, middle)
	_now_ms += _settings.long_press_ms
	_touch._process(0.0)  # A hold on it.
	TouchEvents.release(_vp, 0, middle)
	TouchEvents.press(_vp, 0, middle)
	TouchEvents.drag(_vp, 0, middle + Vector2(200, 0), Vector2(200, 0))  # A drag from it.
	TouchEvents.release(_vp, 0, middle + Vector2(200, 0))
	assert_array(_told).is_empty()
	assert_array(_spy.kinds).is_empty()


func test_a_pan_that_crosses_a_control_told_once_on_the_map_and_never_again() -> void:
	TouchEvents.press(_vp, 0, Vector2(300, 100))
	TouchEvents.drag(_vp, 0, BUTTON.get_center(), Vector2(-200, 0))
	TouchEvents.drag(_vp, 0, Vector2(300, 100), Vector2(200, 0))
	TouchEvents.release(_vp, 0, Vector2(300, 100))
	assert_array(_told).has_size(1)


## A turn and a lost focus cancel what is in flight: the box's cancel and the camera's end are not
## a gesture on the map, so they tell nothing; the finger that was down for them told nothing yet.
func test_a_turn_and_a_focus_loss_cancel_without_telling() -> void:
	TouchEvents.press(_vp, 0, AWAY)  # Down, no event yet.
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	UiScale.set_override(portrait)
	get_window().size = portrait.window_size
	await await_idle_frame()
	TouchEvents.release(_vp, 0, AWAY)
	assert_array(_told).is_empty()
	assert_array(_spy.kinds).is_empty()  # The turn made no tap either.
	TouchEvents.press(_vp, 0, AWAY)  # Held to a box, which told (LONG_PRESS).
	_now_ms += _settings.long_press_ms
	_touch._process(0.0)
	assert_array(_told).has_size(1)
	_touch.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)  # BOX_CANCEL.
	assert_array(_spy.kinds).contains([GestureEvent.Kind.BOX_CANCEL])
	assert_array(_told).has_size(1)
	TouchEvents.press(_vp, 0, AWAY)  # The first finger is lost; a new gesture counts again.
	TouchEvents.drag(_vp, 0, AWAY + Vector2(80, 0), Vector2(80, 0))
	assert_array(_told).has_size(2)


## A finger held through a turn is nobody's any more (the recognizer forgot it) but stays in the
## touches TouchInput owns, so the lift of the last finger of a later gesture never clears the
## flag that says the gesture was told. A press on an idle recognizer starts a new gesture: every
## tap and pan after the turn tells again, while the old finger is still down.
func test_a_finger_held_through_a_turn_does_not_silence_the_gestures_after_it() -> void:
	TouchEvents.press(_vp, 0, AWAY)
	TouchEvents.drag(_vp, 0, AWAY + Vector2(80, 0), Vector2(80, 0))  # A pan: told.
	assert_array(_told).has_size(1)
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	UiScale.set_override(portrait)
	get_window().size = portrait.window_size
	await await_idle_frame()  # The turn cancels the pan. Finger 0 stays down, held.
	for round: int in 3:
		TouchEvents.press(_vp, 1, AWAY)
		_now_ms += 50
		TouchEvents.release(_vp, 1, AWAY)  # A tap with another finger.
		_now_ms += 1000
		assert_array(_told).override_failure_message("tap %d" % round).has_size(2 + round)
