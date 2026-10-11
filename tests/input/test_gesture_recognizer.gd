extends GdUnitTestSuite
## GestureRecognizer with one finger (ADR 0004 section 2), explicit now_ms, the thresholds of
## data/input_settings.tres as literals (12 dp, 300 ms, 32 dp) at 1 px per dp. P8 adds fingers.
## _play() runs a timeline, "d0 100,200 @0": d down, m move, u up, c canceled up, a advance,
## k cancel_all; the digit is the finger. _log() renders events as text: "KIND x,y; KIND".

const SETTINGS_PATH: String = "res://data/input_settings.tres"
const A: Vector2 = Vector2(100, 200)
const TAP_A: String = "TAP 100,200"

var _rec: GestureRecognizer


func before_test() -> void:
	_rec = GestureRecognizer.new()
	_rec.configure(load(SETTINGS_PATH) as InputSettings, 1.0)


func test_tap_is_press_and_release_inside_the_slop_and_acts_at_once() -> void:
	_play("d0 100,200 @1000")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.PENDING)
	assert_str(_log()).is_empty()
	_play("u0 100,200 @1100; d0 100,200 @5000; u0 100,200 @5450")  # 2nd: held 450 ms, no advance
	assert_str(_log()).is_equal(TAP_A + "; " + TAP_A)


func test_slop_is_12_from_the_press_point_and_measured_as_distance() -> void:
	# (-8.4, 8.4) is 11.88 away and (8.5, 8.5) is 12.02, so a per-axis rule gets both wrong.
	var cases: Array[Array] = [
		[Vector2(11.9, 0), TAP_A],
		[Vector2(12, 0), TAP_A],
		[Vector2(-8.4, 8.4), TAP_A],
		[Vector2(12.1, 0), "PAN 12.1,0; CAMERA_END"],
		[Vector2(8.5, 8.5), "PAN 8.5,8.5; CAMERA_END"],
		[Vector2(0, -12.1), "PAN 0,-12.1; CAMERA_END"],
	]
	for i: int in cases.size():
		assert_str(_drag_log(i * 1000, false, cases[i][0])).is_equal(cases[i][1])


func test_first_pan_delta_is_the_whole_movement_then_deltas_are_incremental() -> void:
	_play("d0 100,200 @0; m0 106,200 @5; m0 112.1,200 @10; m0 125,195 @20; m0 101,201 @30")
	assert_str(_log()).is_equal("PAN 12.1,0; PAN 12.9,-5; PAN -24,6")
	_play("a @5000; u0 101,201 @5100")  # a pan never turns into a long-press
	assert_str(_log()).is_equal("CAMERA_END")


func test_long_press_comes_at_300_ms_not_299_and_holding_first_makes_a_box() -> void:
	_play("d0 100,200 @1000; m0 105,200 @1100; a @1299")  # the press point, not 105
	assert_str(_log()).is_empty()
	_play("a @1300; a @2000")
	assert_str(_log()).is_equal("LONG_PRESS 100,200")
	# Moving first is a pan. Holding first is a box, even when no advance() ran before the move.
	_play("k; d0 100,200 @3000; m0 140,200 @3299; k; d0 100,200 @4000; m0 140,200 @4300")
	assert_str(_log()).is_equal(
		"BOX_CANCEL; PAN 40,0; CAMERA_END; LONG_PRESS 100,200; BOX_UPDATE 100,200,40,0"
	)


func test_box_drag_emits_normalised_rects_in_every_direction_then_box_end() -> void:
	_play("d0 100,200 @0; a @300; m0 150,260 @400; m0 60,120 @500")  # down-right, up-left
	_play("m0 130,120 @600; m0 60,230 @700; u0 60,230 @800")  # up-right, down-left
	assert_str(_log()).is_equal(
		(
			"LONG_PRESS 100,200; BOX_UPDATE 100,200,50,60; BOX_UPDATE 60,120,40,80;"
			+ " BOX_UPDATE 100,120,30,80; BOX_UPDATE 60,200,40,30; BOX_END 60,200,40,30"
		)
	)
	# A release at a new place counts as the last move: a fast flick may send no drag event.
	_play("d0 100,200 @5000; a @5300; u0 160,300 @5400; d0 100,200 @6000; u0 150,200 @6010")
	var flick: String = "LONG_PRESS 100,200; BOX_UPDATE 100,200,60,100; BOX_END 100,200,60,100; "
	assert_str(_log()).is_equal(flick + "PAN 50,0; CAMERA_END")


func test_a_box_must_be_larger_than_12_on_either_axis_else_it_is_a_slow_tap() -> void:
	_play("d0 100,200 @0; a @300; u0 100,200 @500")
	assert_str(_log()).is_equal("LONG_PRESS 100,200; BOX_CANCEL; " + TAP_A)
	var cases: Array[Array] = [
		[Vector2(12, 12), "BOX_UPDATE 100,200,12,12; BOX_CANCEL; " + TAP_A],
		[Vector2(12.5, 0), "BOX_UPDATE 100,200,12.5,0; BOX_END 100,200,12.5,0"],
		[Vector2(0, -12.5), "BOX_UPDATE 100,187.5,0,12.5; BOX_END 100,187.5,0,12.5"],
	]
	for i: int in cases.size():
		var got: String = _drag_log(10000 + i * 1000, true, cases[i][0])
		assert_str(got).is_equal("LONG_PRESS 100,200; " + cases[i][1])


func test_double_tap_limits_300_ms_and_32_apart_and_a_third_tap_starts_over() -> void:
	_tap(A, 0, 250)
	_tap(A + Vector2(32, 0), 550, 600)  # 300 ms after the release, 550 after the first press
	_tap(A, 2000, 2050)  # a triple tap: the third one starts over
	_tap(A, 2100, 2150)
	_tap(A, 2200, 2250)
	var inside: String = TAP_A + "; DOUBLE_TAP 132,200; " + TAP_A + "; DOUBLE_TAP 100,200; "
	assert_str(_log()).is_equal(inside + TAP_A)
	_tap(A, 5000, 5250)
	_tap(A, 5551, 5600)  # 301 ms
	_tap(A, 7000, 7050)
	_tap(A + Vector2(33, 0), 7100, 7150)  # 33 apart
	assert_str(_log()).is_equal(TAP_A + "; " + TAP_A + "; " + TAP_A + "; TAP 133,200")
	_tap(A, 9000, 9050)  # a pan or a long press in between breaks the double tap
	_play("d0 100,200 @9100; m0 150,200 @9110; u0 150,200 @9120")
	_tap(A, 9200, 9250)
	_tap(A, 10000, 10050)
	_play("d0 100,200 @10100; a @10400; u0 100,200 @10450")
	var pan: String = TAP_A + "; PAN 50,0; CAMERA_END; " + TAP_A
	assert_str(_log()).is_equal(pan + "; " + TAP_A + "; LONG_PRESS 100,200; BOX_CANCEL; " + TAP_A)


func test_canceled_release_and_cancel_all_end_the_gesture_without_a_tap() -> void:
	_play("d0 100,200 @0; c0 100,200 @50; d0 100,200 @100; a @400; c0 100,200 @450")
	_play("d0 100,200 @1000; m0 130,200 @1010; c0 130,200 @1020")
	_play("d0 100,200 @2000; a @2300; k; u0 100,200 @2400")  # the old touch is gone: no tap
	_play("d0 100,200 @3000; m0 130,200 @3010; k; d0 100,200 @4000; k")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.IDLE)
	_tap(A, 5000, 5050)
	_play("k")
	_tap(A, 5100, 5150)  # cancel_all forgot the first tap
	var ended: String = "LONG_PRESS 100,200; BOX_CANCEL; PAN 30,0; CAMERA_END; "
	assert_str(_log()).is_equal(ended + ended + TAP_A + "; " + TAP_A)


func test_finger_identity_duplicate_down_cancels_unknown_and_second_fingers_are_ignored() -> void:
	_play("m7 100,200 @0; u7 100,200 @10; d0 100,200 @100")
	# P7 tracks one finger: finger 1 and the never-pressed finger 7 change nothing.
	_play("d1 500,300 @110; m1 580,300 @120; u1 500,300 @130; m7 500,300 @140; u0 100,200 @150")
	# A press for an index that is already down cancels that touch first.
	_play("d0 100,200 @1000; a @1300; d0 500,300 @1400; u0 500,300 @1450")
	_play("d0 100,200 @2000; m0 130,200 @2010; d0 500,300 @2020")
	var duplicate_down: String = "LONG_PRESS 100,200; BOX_CANCEL; TAP 500,300; PAN 30,0; CAMERA_END"
	assert_str(_log()).is_equal(TAP_A + "; " + duplicate_down)


func test_two_px_per_dp_doubles_the_slops_and_leaves_the_times_alone() -> void:
	_rec.configure(load(SETTINGS_PATH) as InputSettings, 2.0)
	assert_str(_drag_log(0, false, Vector2(23.9, 0))).is_equal(TAP_A)
	assert_str(_drag_log(1000, false, Vector2(24.1, 0))).is_equal("PAN 24.1,0; CAMERA_END")
	assert_str(_drag_log(2000, true, Vector2(24, 24))).ends_with(TAP_A)
	assert_str(_drag_log(3000, true, Vector2(24.5, 0))).ends_with("BOX_END 100,200,24.5,0")
	_tap(A, 4000, 4050)
	_tap(A + Vector2(64, 0), 4100, 4150)
	_tap(A, 5000, 5050)
	_tap(A + Vector2(65, 0), 5100, 5150)
	assert_str(_log()).is_equal(TAP_A + "; DOUBLE_TAP 164,200; " + TAP_A + "; TAP 165,200")
	_play("d0 100,200 @6000; a @6299")
	assert_str(_log()).is_empty()
	_play("a @6300")
	assert_str(_log()).is_equal("LONG_PRESS 100,200")


func test_take_events_appends_in_order_clears_the_queue_and_counts() -> void:
	_tap(A, 0, 50)
	_tap(Vector2(500, 300), 1000, 1050)
	var out: Array[GestureEvent] = [GestureEvent.new(GestureEvent.Kind.PAN)]
	assert_int(_rec.take_events(out)).is_equal(2)
	assert_int(_rec.take_events(out)).is_equal(0)
	assert_int(out.size()).is_equal(3)
	assert_vector(out[2].position).is_equal(Vector2(500, 300))


func test_sources_are_ref_counted_and_use_no_node_input_or_time() -> void:
	var banned: RegEx = RegEx.create_from_string(r"\b(Input|Time|OS|Node\w*|SceneTree|get_tree)\b")
	for name: String in ["GestureRecognizer", "GestureEvent"]:
		var source: String = FileAccess.get_file_as_string("res://game/input/%s.gd" % name)
		var code: String = RegEx.create_from_string(r"#.*").sub(source, "", true)
		assert_bool(code.contains("\nextends RefCounted\n")).is_true()
		assert_object(banned.search(code)).is_null()


## Runs a timeline: steps split by ";", each "<op><finger> <x>,<y> @<ms>" ("a @ms", "k").
func _play(script: String) -> void:
	for step: String in script.split(";", false):
		var words: PackedStringArray = step.strip_edges().split(" ", false)
		var ms: int = words[-1].trim_prefix("@").to_int()
		var finger: int = words[0].substr(1).to_int()
		var xy: PackedFloat64Array = words[1].split_floats(",") if words.size() == 3 else [0, 0]
		var pos: Vector2 = Vector2(xy[0], xy[1])
		match words[0][0]:
			"d":
				_rec.touch_down(finger, pos, ms)
			"m":
				_rec.touch_move(finger, pos, ms)
			"u", "c":
				_rec.touch_up(finger, pos, ms, words[0][0] == "c")
			"a":
				_rec.advance(ms)
			"k":
				_rec.cancel_all()


## The queued events as one line, "KIND x,y[,w,h]; ...": the press point for taps, the delta for
## PAN and the rect for BOX_UPDATE and BOX_END, rounded to 0.1. Other kinds have no numbers.
func _log() -> String:
	var events: Array[GestureEvent] = []
	_rec.take_events(events)
	var lines: PackedStringArray = []
	for event: GestureEvent in events:
		var numbers: Array[float] = []
		match event.kind:
			GestureEvent.Kind.TAP, GestureEvent.Kind.DOUBLE_TAP, GestureEvent.Kind.LONG_PRESS:
				numbers = [event.position.x, event.position.y]
			GestureEvent.Kind.PAN:
				numbers = [event.delta.x, event.delta.y]
			GestureEvent.Kind.BOX_UPDATE, GestureEvent.Kind.BOX_END:
				var r: Rect2 = event.rect
				numbers = [r.position.x, r.position.y, r.size.x, r.size.y]
		var text: PackedStringArray = []
		for number: float in numbers:
			text.append(("%.1f" % number).trim_suffix(".0"))
		var kind_name: String = GestureEvent.Kind.keys()[event.kind]
		lines.append((kind_name + " " + ",".join(text)).strip_edges())
	return "; ".join(lines)


func _tap(pos: Vector2, down_ms: int, up_ms: int) -> void:
	_rec.touch_down(0, pos, down_ms)
	_rec.touch_up(0, pos, up_ms)


## Press at A, optionally hold past the long-press time, move by `offset`, release there.
func _drag_log(t: int, hold: bool, offset: Vector2) -> String:
	_rec.touch_down(0, A, t)
	if hold:
		_rec.advance(t + 300)
	var move_ms: int = t + (310 if hold else 100)
	_rec.touch_move(0, A + offset, move_ms)
	_rec.touch_up(0, A + offset, move_ms + 10)
	return _log()
