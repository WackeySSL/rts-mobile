extends GdUnitTestSuite
## The gesture hint (plan row P590, ADR 0048 section 6): the pose of every kind at fixed times, the
## hold and the double-tap gap from `data/input_settings.tres`, the still key pose of Reduced
## effects, no input handled, one reused pose object, and the hide while touched and after it. The
## clock is `advance`, stepped by hand, never the wall clock.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const GUIDE_PATH: String = "res://data/tutorial/guide_settings.tres"
const INPUT_PATH: String = "res://data/input_settings.tres"
const TAP: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.TAP
const DOUBLE: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.DOUBLE_TAP
const HOLD: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.LONG_PRESS
const DRAG: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.DRAG
const BOX: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.BOX
const PINCH_OUT: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.PINCH_OUT
const PINCH_IN: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.PINCH_IN
const ALL: Array[TutorialBeatDef.Gesture] = [TAP, DOUBLE, HOLD, DRAG, BOX, PINCH_OUT, PINCH_IN]


## Counts what reaches `_unhandled_input`: an event the hint handled would not.
class Witness:
	extends Node
	var seen: int = 0

	func _unhandled_input(_event: InputEvent) -> void:
		seen += 1


var _hint: GestureHint
var _timing: GestureHint.Timing
var _guide: GuideSettingsDef
var _input: InputSettings


func before_test() -> void:
	_guide = load(GUIDE_PATH) as GuideSettingsDef
	_input = load(INPUT_PATH) as InputSettings
	_hint = auto_free(GestureHint.new())
	add_child(_hint)
	_timing = GestureHint.Timing.new().load_from(_guide, _input)


func _touch(index: int, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	_hint._input(event)


func test_a_tap_presses_for_hint_tap_ms_then_rests() -> void:
	var down: GestureHint.Pose = _hint.pose(TAP, 90, _timing)
	assert_bool(down.pressed).is_true()
	assert_float(down.press_progress).is_equal_approx(0.5, 0.001)
	assert_vector(down.finger_a).is_equal(Vector2.ZERO)
	var rest: GestureHint.Pose = _hint.pose(TAP, 700, _timing)
	assert_bool(rest.pressed).is_false()
	assert_float(rest.alpha).is_equal(1.0)


func test_the_loop_is_the_cycle_and_wraps() -> void:
	var period: int = _timing.period_ms(TAP)
	assert_int(period).is_equal(_guide.hint_cycle_ms)
	assert_bool(_hint.pose(TAP, period + 90, _timing).pressed).is_true()


func test_a_hold_lasts_long_press_ms_plus_the_extra() -> void:
	var hold: int = _input.long_press_ms + _guide.hint_hold_extra_ms
	assert_int(_timing.active_ms(HOLD)).is_equal(hold)
	assert_bool(_hint.pose(HOLD, hold - 1, _timing).pressed).is_true()
	assert_bool(_hint.pose(HOLD, hold, _timing).pressed).is_false()


func test_the_hold_follows_a_changed_long_press() -> void:
	var slower: InputSettings = _input.duplicate()
	slower.long_press_ms = 500
	var timing: GestureHint.Timing = GestureHint.Timing.new().load_from(_guide, slower)
	assert_int(timing.active_ms(HOLD)).is_equal(500 + _guide.hint_hold_extra_ms)
	assert_int(timing.active_ms(BOX)).is_equal(
		500 + _guide.hint_hold_extra_ms + _guide.hint_drag_ms
	)


func test_a_double_tap_has_two_presses_with_a_gap_inside_double_tap_ms() -> void:
	assert_int(_timing.gap_ms).is_equal(_input.double_tap_ms / 2)
	assert_int(_timing.gap_ms).is_less(_input.double_tap_ms)
	assert_bool(_hint.pose(DOUBLE, 10, _timing).pressed).is_true()
	var gap_t: int = _timing.tap_ms + _timing.gap_ms / 2
	assert_bool(_hint.pose(DOUBLE, gap_t, _timing).pressed).is_false()
	var second_t: int = _timing.tap_ms + _timing.gap_ms + 10
	assert_bool(_hint.pose(DOUBLE, second_t, _timing).pressed).is_true()
	var wider: InputSettings = _input.duplicate()
	wider.double_tap_ms = 400
	var timing: GestureHint.Timing = GestureHint.Timing.new().load_from(_guide, wider)
	assert_int(timing.gap_ms).is_equal(200)


func test_a_drag_moves_the_finger_along_the_vector_while_pressed() -> void:
	_timing.vector_dp = Vector2(-160.0, 0.0)
	var half: GestureHint.Pose = _hint.pose(DRAG, _guide.hint_drag_ms / 2, _timing)
	assert_bool(half.pressed).is_true()
	assert_vector(half.finger_a).is_equal(Vector2(-80.0, 0.0))
	var end: GestureHint.Pose = _hint.pose(DRAG, _guide.hint_drag_ms + 10, _timing)
	assert_bool(end.pressed).is_false()
	assert_vector(end.finger_a).is_equal(Vector2(-160.0, 0.0))


func test_a_box_holds_then_drags_the_diagonal() -> void:
	_timing.vector_dp = Vector2(120.0, 80.0)
	var holding: GestureHint.Pose = _hint.pose(BOX, _timing.hold_ms / 2, _timing)
	assert_vector(holding.finger_a).is_equal(Vector2.ZERO)
	assert_bool(holding.pressed).is_true()
	var mid_t: int = _timing.hold_ms + _guide.hint_drag_ms / 2
	assert_vector(_hint.pose(BOX, mid_t, _timing).finger_a).is_equal(Vector2(60.0, 40.0))


func test_a_pinch_has_two_fingers_apart_or_together() -> void:
	var last: int = _guide.hint_pinch_ms - 1
	var out_start: GestureHint.Pose = _hint.pose(PINCH_OUT, 0, _timing)
	var out_gap: float = out_start.finger_a.distance_to(out_start.finger_b)
	var out_end: GestureHint.Pose = _hint.pose(PINCH_OUT, last, _timing)
	assert_bool(out_end.two_fingers).is_true()
	assert_float(out_end.finger_a.distance_to(out_end.finger_b)).is_greater(out_gap)
	assert_vector(out_end.finger_a + out_end.finger_b).is_equal(Vector2.ZERO)
	var in_start: GestureHint.Pose = _hint.pose(PINCH_IN, 0, _timing)
	var in_gap: float = in_start.finger_a.distance_to(in_start.finger_b)
	var in_end: GestureHint.Pose = _hint.pose(PINCH_IN, last, _timing)
	assert_float(in_end.finger_a.distance_to(in_end.finger_b)).is_less(in_gap)


func test_auto_and_none_show_nothing() -> void:
	for none: TutorialBeatDef.Gesture in [
		TutorialBeatDef.Gesture.AUTO, TutorialBeatDef.Gesture.NONE
	]:
		assert_float(_hint.pose(none, 100, _timing).alpha).is_equal(0.0)
		assert_float(_hint.key_pose(none, _timing).alpha).is_equal(0.0)


func test_the_pose_fades_at_the_loop_edges() -> void:
	assert_float(_hint.pose(TAP, 0, _timing).alpha).is_equal(0.0)
	var late: int = _timing.period_ms(TAP) - 1
	assert_float(_hint.pose(TAP, late, _timing).alpha).is_less(0.5)


func test_pose_returns_the_same_instance_every_call() -> void:
	var first: GestureHint.Pose = _hint.pose(TAP, 10, _timing)
	for kind: TutorialBeatDef.Gesture in ALL:
		assert_object(_hint.pose(kind, 123, _timing)).is_same(first)
		assert_object(_hint.key_pose(kind, _timing)).is_same(first)


func test_reduced_effects_is_one_still_pose_whatever_the_time() -> void:
	for kind: TutorialBeatDef.Gesture in ALL:
		var key: GestureHint.Pose = _hint.key_pose(kind, _timing)
		var before: Array = [key.finger_a, key.finger_b, key.pressed, key.alpha, key.rings]
		assert_bool(key.pressed).is_true()
		assert_float(key.alpha).is_equal(1.0)
		_hint.advance(321)
		var again: GestureHint.Pose = _hint.key_pose(kind, _timing)
		var after: Array = [again.finger_a, again.finger_b, again.pressed, again.alpha, again.rings]
		assert_array(after).is_equal(before)
	assert_int(_hint.key_pose(DOUBLE, _timing).rings).is_equal(2)


func test_reduced_effects_starts_no_tween() -> void:
	_hint.reduced = true
	_hint.kind = PINCH_OUT
	_hint.advance(500)
	assert_int(_hint.get_tree().get_processed_tweens().size()).is_equal(0)


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
