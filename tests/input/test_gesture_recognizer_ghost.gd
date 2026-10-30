extends GdUnitTestSuite
## The GestureRecognizer's two inputs for placement mode (plan P86, ADR 0019 section 2), fed with
## InputEventScreenTouch and InputEventScreenDrag sequences and an explicit clock, the thresholds
## of data/input_settings.tres at 1 px per dp (slop 12, long-press 300 ms). A press on a grab (here:
## x below 150) whose finger then moves beyond the slop is a ghost drag, GHOST_DRAG with the
## finger's position, not a pan, and its release is no tap and no camera end; a press elsewhere
## pans as ever. With `box_enabled` off a hold starts no box. A second finger turns a grab into a
## pinch, and a cancel (a turn of the phone) ends it with no event.

const GRAB_LIMIT: float = 150.0
const ON: Vector2 = Vector2(100, 200)  ## On the grab.
const OFF: Vector2 = Vector2(300, 200)  ## Not on it.

var _rec: GestureRecognizer
var _asked: Array[Vector2] = []


func before_test() -> void:
	_rec = GestureRecognizer.new()
	_rec.configure(load("res://data/input_settings.tres") as InputSettings, 1.0)
	_asked.clear()
	_rec.grab_test = func(at: Vector2) -> bool:
		_asked.append(at)
		return at.x < GRAB_LIMIT


func test_a_drag_from_the_grab_is_ghost_drags_with_the_finger_position_and_no_pan() -> void:
	_down(0, ON, 0)
	_move(0, ON + Vector2(5, 0), 10)  # Inside the slop: nothing yet.
	assert_str(_log()).is_empty()
	_move(0, ON + Vector2(30, 0), 20)
	_move(0, ON + Vector2(40, 10), 30)
	_up(0, ON + Vector2(40, 10), 40)  # Lifted where it is: no further move.
	assert_str(_log()).is_equal("GHOST_DRAG 130,200; GHOST_DRAG 140,210")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.IDLE)
	assert_array(_asked).is_equal([ON])  # Asked once, for the press point.


func test_a_release_at_a_new_place_is_the_last_ghost_drag_and_never_a_tap() -> void:
	_down(0, ON, 0)
	_up(0, ON + Vector2(60, 0), 100)
	assert_str(_log()).is_equal("GHOST_DRAG 160,200")
	_down(0, ON, 1000)
	_move(0, ON + Vector2(50, 0), 1010)
	_up(0, ON + Vector2(50, 0), 1020)
	_log()
	_down(0, ON, 1100)  # A drag leaves no tap to pair with: this press is a plain tap.
	_up(0, ON, 1150)
	assert_str(_log()).is_equal("TAP 100,200")


func test_a_press_off_the_grab_pans_and_a_press_on_it_that_does_not_move_is_a_tap() -> void:
	_down(0, OFF, 0)
	_move(0, OFF + Vector2(30, 0), 10)
	_up(0, OFF + Vector2(30, 0), 20)
	assert_str(_log()).is_equal("PAN; CAMERA_END")
	_down(0, ON, 1000)
	_up(0, ON + Vector2(3, 0), 1100)
	assert_str(_log()).is_equal("TAP 100,200")


func test_the_slop_is_the_same_for_a_grab() -> void:
	for case: Array in [
		[11.9, "TAP 100,200"], [12.0, "TAP 100,200"], [12.1, "GHOST_DRAG 112.1,200"]
	]:
		_down(0, ON, 0)
		_move(0, ON + Vector2(case[0], 0), 10)
		_up(0, ON + Vector2(case[0], 0), 20)
		assert_str(_log()).override_failure_message(str(case[0])).is_equal(case[1])
		_rec.cancel_all()


func test_without_a_box_a_hold_stays_a_press_then_pans_grabs_or_taps() -> void:
	_rec.box_enabled = false
	_down(0, OFF, 0)
	_rec.advance(400)
	assert_str(_log()).is_empty()  # No LONG_PRESS.
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.PENDING)
	_move(0, OFF + Vector2(40, 0), 500)  # After the hold: a pan, not a box.
	_up(0, OFF + Vector2(40, 0), 510)
	assert_str(_log()).is_equal("PAN; CAMERA_END")
	_down(0, ON, 1000)
	_rec.advance(1400)
	_move(0, ON + Vector2(40, 0), 1410)
	_up(0, ON + Vector2(40, 0), 1420)
	assert_str(_log()).is_equal("GHOST_DRAG 140,200")
	_down(0, OFF, 2000)
	_rec.advance(2400)
	_up(0, OFF, 2500)  # A hold released where it was: a slow tap.
	assert_str(_log()).is_equal("TAP 300,200")
	_rec.box_enabled = true
	_down(0, OFF, 3000)
	_rec.advance(3300)
	assert_str(_log()).is_equal("LONG_PRESS 300,200")  # The box is back when the mode ends.


func test_a_second_finger_makes_the_grab_a_pinch_and_what_is_left_pans() -> void:
	_down(0, ON, 0)
	_move(0, ON + Vector2(30, 0), 10)
	_log()
	_down(1, OFF, 20)  # Not asked: only a first finger can grab.
	assert_array(_asked).is_equal([ON])
	_move(1, OFF + Vector2(40, 0), 30)
	assert_str(_log()).contains("PINCH").not_contains("GHOST_DRAG")
	_up(1, OFF + Vector2(40, 0), 40)
	assert_str(_log()).is_equal("CAMERA_END")
	_move(0, ON + Vector2(80, 0), 50)  # The finger that is left pans.
	assert_str(_log()).is_equal("PAN")


func test_a_cancel_during_a_grab_ends_it_with_no_event_and_its_lift_is_nothing() -> void:
	_down(0, ON, 0)
	_move(0, ON + Vector2(30, 0), 10)
	_log()
	_rec.cancel_all()  # A turn of the phone.
	assert_str(_log()).is_empty()
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.IDLE)
	_move(0, ON + Vector2(90, 0), 20)
	_up(0, ON + Vector2(90, 0), 30)
	assert_str(_log()).is_empty()


func test_a_recognizer_with_no_grab_test_never_grabs() -> void:
	_rec.grab_test = Callable()
	_down(0, ON, 0)
	_move(0, ON + Vector2(30, 0), 10)
	_up(0, ON + Vector2(30, 0), 20)
	assert_str(_log()).is_equal("PAN; CAMERA_END")


func _down(index: int, at: Vector2, ms: int) -> void:
	_feed(_touch(index, at, true), ms)


func _up(index: int, at: Vector2, ms: int) -> void:
	_feed(_touch(index, at, false), ms)


func _move(index: int, at: Vector2, ms: int) -> void:
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = index
	drag.position = at
	_feed(drag, ms)


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = pressed
	return touch


## What TouchInput does with an event, minus the viewport.
func _feed(event: InputEvent, ms: int) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed:
		_rec.touch_down(touch.index, touch.position, ms)
	elif touch != null:
		_rec.touch_up(touch.index, touch.position, ms, touch.canceled)
	elif drag != null:
		_rec.touch_move(drag.index, drag.position, ms)


## The queued events as "KIND x,y; ..." for GHOST_DRAG, TAP and LONG_PRESS (the position, rounded
## to 0.01), the kind alone for the rest.
func _log() -> String:
	var events: Array[GestureEvent] = []
	_rec.take_events(events)
	var lines: PackedStringArray = []
	for event: GestureEvent in events:
		var line: String = GestureEvent.Kind.keys()[event.kind]
		if [GestureEvent.Kind.GHOST_DRAG, GestureEvent.Kind.TAP, GestureEvent.Kind.LONG_PRESS].has(
			event.kind
		):
			line += " %s,%s" % [_num(event.position.x), _num(event.position.y)]
		lines.append(line)
	return "; ".join(lines)


func _num(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
