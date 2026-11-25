extends GdUnitTestSuite
## The gesture hint's input (plan row P590, ADR 0048 section 6): it only reads events, hides while a
## finger is down and for `hint_idle_ms` after, counts the left mouse button but not the wheel,
## and lets go of the fingers when the window loses focus. The clock is `advance`, by hand.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")


## Counts what reaches `_unhandled_input`: an event the hint handled would not.
class Witness:
	extends Node
	var seen: int = 0

	func _unhandled_input(_event: InputEvent) -> void:
		seen += 1


var _hint: GestureHint
var _guide: GuideSettingsDef


func before_test() -> void:
	_guide = load("res://data/tutorial/guide_settings.tres") as GuideSettingsDef
	_hint = auto_free(GestureHint.new())
	add_child(_hint)


func _touch(index: int, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	_hint._input(event)


func test_the_hint_never_handles_an_event() -> void:
	var witness: Witness = auto_free(Witness.new())
	add_child(witness)
	var vp: Viewport = _hint.get_viewport()
	TouchEvents.press(vp, 0, Vector2(100.0, 100.0))
	TouchEvents.release(vp, 0, Vector2(100.0, 100.0))
	assert_int(witness.seen).is_equal(2)
	assert_int(_hint.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var handled_before: bool = vp.is_input_handled()
	_touch(0, true)
	assert_bool(vp.is_input_handled()).is_equal(handled_before)


func test_a_touch_hides_the_hint_until_hint_idle_ms_after_release() -> void:
	assert_bool(_hint.touched_hidden()).is_false()
	_touch(0, true)
	_hint.advance(5000)
	assert_bool(_hint.touched_hidden()).is_true()
	_touch(0, false)
	_hint.advance(_guide.hint_idle_ms - 1)
	assert_bool(_hint.touched_hidden()).is_true()
	_hint.advance(1)
	assert_bool(_hint.touched_hidden()).is_false()


func test_it_waits_for_the_last_of_two_fingers() -> void:
	_touch(0, true)
	_touch(1, true)
	_touch(0, false)
	_hint.advance(_guide.hint_idle_ms * 2)
	assert_bool(_hint.touched_hidden()).is_true()
	_touch(1, false)
	assert_bool(_hint.touched_hidden()).is_true()


func test_the_idle_time_is_the_guide_def_s() -> void:
	var faster: GuideSettingsDef = _guide.duplicate()
	faster.hint_idle_ms = 100
	_hint.settings = faster
	_touch(0, true)
	_touch(0, false)
	_hint.advance(100)
	assert_bool(_hint.touched_hidden()).is_false()


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	_hint._input(event)


func test_a_left_mouse_press_hides_the_hint_like_a_touch() -> void:
	_mouse(MOUSE_BUTTON_LEFT, true)
	assert_bool(_hint.touched_hidden()).is_true()
	_mouse(MOUSE_BUTTON_LEFT, false)
	_hint.advance(_guide.hint_idle_ms - 1)
	assert_bool(_hint.touched_hidden()).is_true()
	_hint.advance(1)
	assert_bool(_hint.touched_hidden()).is_false()


func test_a_wheel_notch_does_not_hide_the_hint() -> void:
	for button: MouseButton in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_mouse(button, true)
		_mouse(button, false)
	assert_bool(_hint.touched_hidden()).is_false()


func test_a_touch_and_its_emulated_mouse_stay_hidden_until_both_are_up() -> void:
	_touch(0, true)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_touch(0, false)
	_hint.advance(_guide.hint_idle_ms * 2)
	assert_bool(_hint.touched_hidden()).is_true()
	_mouse(MOUSE_BUTTON_LEFT, false)
	assert_bool(_hint.touched_hidden()).is_true()
	_hint.advance(_guide.hint_idle_ms)
	assert_bool(_hint.touched_hidden()).is_false()


func test_losing_focus_lets_go_of_the_fingers_that_were_down() -> void:
	_touch(0, true)
	_touch(1, true)
	_hint.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(_hint.touched_hidden()).is_true()  # The idle time still runs.
	_hint.advance(_guide.hint_idle_ms)
	assert_bool(_hint.touched_hidden()).is_false()
	_touch(2, true)
	_hint.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_hint.advance(_guide.hint_idle_ms)
	assert_bool(_hint.touched_hidden()).is_false()
