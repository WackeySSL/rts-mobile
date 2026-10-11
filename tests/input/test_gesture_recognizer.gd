extends GdUnitTestSuite
## GestureRecognizer (ADR 0004 section 2), explicit now_ms, the thresholds of
## data/input_settings.tres as literals (12 dp, 300 ms, 32 dp) at 1 px per dp.
## _play() runs a timeline, "d0 100,200 @0": d down, m move, u up, c canceled up, a advance,
## k cancel_all; the digit is the finger. _log() renders events as text: "KIND x,y; KIND".

const SETTINGS_PATH: String = "res://data/input_settings.tres"
const A: Vector2 = Vector2(100, 200)
const TAP_A: String = "TAP 100,200"
const BANNED: String = r"\b(Input|Time|OS|Engine|DisplayServer|Node\w*|SceneTree|get_tree)\b"

var _rec: GestureRecognizer


func before_test() -> void:
	_rec = GestureRecognizer.new()
	_rec.configure(load(SETTINGS_PATH) as InputSettings, 1.0)


func test_tap_is_press_and_release_inside_the_slop_and_acts_at_once() -> void:
	_play("d0 100,200 @1000")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.PENDING)
	assert_str(_log()).is_empty()
	_play("u0 100,200 @1100; d0 100,200 @5000; u0 105,200 @5450")  # 2nd: held 450 ms, no advance
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
	# A release at a new place is the last move, with the time applied first: no drag event and
	# no advance() needed. The same release after 10 ms is a pan.
	_play("d0 100,200 @5000; u0 160,300 @5400; d0 100,200 @6000; u0 150,200 @6010")
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
	_tap(A + Vector2(24, 24), 7100, 7150)  # 33.9 apart, each axis under 32
	assert_str(_log()).is_equal(TAP_A + "; " + TAP_A + "; " + TAP_A + "; TAP 124,224")
	_tap(A, 9000, 9050)  # a pan or a long press in between breaks the double tap
	_play("d0 100,200 @9100; m0 150,200 @9110; u0 150,200 @9120")
	_tap(A, 9200, 9250)
	_tap(A, 10000, 10050)
	_play("d0 100,200 @10100; a @10400; u0 100,200 @10450")
	var pan: String = TAP_A + "; PAN 50,0; CAMERA_END; " + TAP_A
	assert_str(_log()).is_equal(pan + "; " + TAP_A + "; LONG_PRESS 100,200; BOX_CANCEL; " + TAP_A)


func test_canceled_release_and_cancel_all_end_the_gesture_without_a_tap() -> void:
	_play("d0 100,200 @0; c0 300,200 @50; d0 100,200 @100; a @400; c0 300,200 @450")
	_play("d0 100,200 @1000; m0 130,200 @1010; c0 130,200 @1020")
	_play("d0 100,200 @2000; a @2300; k; u0 100,200 @2400")  # the old touch is gone: no tap
	_play("d0 100,200 @3000; m0 130,200 @3010; k; d0 100,200 @4000; k")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.IDLE)
	_tap(A, 5000, 5050)
	_play("k")
	_tap(A, 5100, 5150)  # cancel_all forgot the first tap
	var ended: String = "LONG_PRESS 100,200; BOX_CANCEL; PAN 30,0; CAMERA_END; "
	assert_str(_log()).is_equal(ended + ended + TAP_A + "; " + TAP_A)


func test_finger_identity_unknown_indices_are_ignored_and_a_duplicate_down_cancels() -> void:
	_play("m7 100,200 @0; u7 100,200 @10; d2 100,200 @100")
	# Finger 2 and finger 1 pair up. The never-pressed finger 7 changes nothing, even now.
	_play("d1 500,200 @110; m7 900,200 @115; m1 700,200 @120; u7 100,200 @125; u1 700,200 @130")
	_play("u2 100,200 @150")  # distance 400 -> 600, centre 300 -> 400; no tap
	# A press for an index that is already down cancels that touch first.
	_play("d0 100,200 @1000; a @1300; d0 500,300 @1400; u0 500,300 @1450")
	_play("d0 100,200 @2000; m0 130,200 @2010; d0 500,300 @2020")
	var duplicate_down: String = "LONG_PRESS 100,200; BOX_CANCEL; TAP 500,300; PAN 30,0; CAMERA_END"
	var pair: String = "PINCH 400,200,100,0,1.5; CAMERA_END; CAMERA_END; "
	assert_str(_log()).is_equal(pair + duplicate_down)
	# The same with two fingers down: the old finger 1 ends and the new one pairs with finger 0.
	_play("k; d0 100,200 @3000; d1 300,200 @3010; d1 500,200 @3020; m1 700,200 @3030")
	assert_str(_log()).is_equal("CAMERA_END; PINCH 400,200,100,0,1.5")


func test_two_px_per_dp_doubles_the_slops_and_leaves_the_times_alone() -> void:
	_rec.configure(load(SETTINGS_PATH) as InputSettings, 2.0)
	assert_str(_drag_log(0, false, Vector2(23.9, 0))).is_equal(TAP_A)
	assert_str(_drag_log(1000, false, Vector2(24.1, 0))).is_equal("PAN 24.1,0; CAMERA_END")
	assert_str(_drag_log(2000, true, Vector2(24, 24))).ends_with(TAP_A)
	assert_str(_drag_log(3000, true, Vector2(24.5, 0))).ends_with("BOX_END 100,200,24.5,0")
	_tap(A, 4000, 4050)
	_tap(A + Vector2(64, 0), 4100, 4150)
	_tap(A, 5000, 5050)
	_tap(A + Vector2(48, 48), 5100, 5150)  # 67.9 apart, each axis under 64
	_tap(A, 5200, 5250)
	_tap(A, 5551, 5600)  # 301 ms: the double-tap time is not scaled
	var tail: String = "; TAP 148,248; " + TAP_A + "; " + TAP_A
	assert_str(_log()).is_equal(TAP_A + "; DOUBLE_TAP 164,200; " + TAP_A + tail)
	_play("d0 100,200 @6000; a @6299")
	assert_str(_log()).is_empty()
	_play("a @6300")
	assert_str(_log()).is_equal("LONG_PRESS 100,200")


func test_a_second_finger_drops_a_pending_tap_cancels_a_box_and_takes_over_a_pan() -> void:
	_play("d0 100,200 @0; d1 300,200 @400")  # undecided, even after 300 ms: no long-press
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.MULTI)
	assert_str(_log()).is_empty()
	_play("u1 300,200 @410; u0 100,200 @420")
	assert_str(_log()).is_equal("CAMERA_END; CAMERA_END")  # no TAP
	_play("d0 100,200 @1000; a @1300; d1 300,200 @1400")
	assert_str(_log()).is_equal("LONG_PRESS 100,200; BOX_CANCEL")
	_play("k")
	_play("d0 100,200 @2000; m0 150,200 @2010; d1 300,200 @2020")  # a pan carries on as a pinch
	assert_str(_log()).is_equal("CAMERA_END; PAN 50,0")
	_play("m1 450,200 @2030")  # from where finger 0 is now: distance 150 -> 300
	assert_str(_log()).is_equal("PINCH 300,200,75,0,2")


func test_pinch_scale_is_the_distance_ratio_since_the_last_pinch_and_delta_the_centroid_move(
) -> void:
	_play("d0 100,200 @0; d1 300,200 @10")  # distance 200, centre 200,200: nothing yet
	assert_str(_log()).is_empty()
	_play("m1 500,200 @20; m0 200,200 @30")  # 200 -> 400 is 2, then 400 -> 300 is 0.75 (not 1.5)
	assert_str(_log()).is_equal("PINCH 300,200,100,0,2; PINCH 350,200,50,0,0.75")
	# A two-finger drag with the spacing kept: scale 1, and the deltas add up to the drag.
	_play("k; d0 100,200 @100; d1 300,200 @110; m0 180,360 @120; m1 380,360 @130")
	assert_str(_log()).is_equal("CAMERA_END; PINCH 240,280,40,80,1; PINCH 280,360,40,80,1")


func test_lifting_one_of_two_fingers_hands_over_to_a_pan_and_no_tap_comes_after() -> void:
	_play("d0 100,200 @0; d1 300,200 @10; m0 60,200 @20; u1 360,200 @30")  # finger 1 lifts at 360
	assert_str(_log()).is_equal("PINCH 180,200,-20,0,1.2; PINCH 210,200,30,0,1.25; CAMERA_END")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.PAN)
	_play("m0 90,200 @40; a @5000; m0 90,230 @5010")  # no long-press; from where it was, not 100
	assert_str(_log()).is_equal("PAN 30,0; PAN 0,30")
	_play("u0 90,230 @5020")
	assert_str(_log()).is_equal("CAMERA_END")
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.IDLE)
	# Fingers that never moved: still no TAP, whichever one lifts first.
	_play("d0 100,200 @6000; d1 300,200 @6010; u0 100,200 @6020; u1 300,200 @6030")
	assert_str(_log()).is_equal("CAMERA_END; CAMERA_END")
	_tap(A, 7000, 7050)
	assert_str(_log()).is_equal(TAP_A)


func test_a_third_finger_is_ignored_and_a_lost_tracked_finger_re_pairs_without_a_jump() -> void:
	_play("d0 100,200 @0; d1 300,200 @10; d2 500,500 @20; m2 600,600 @30; u2 600,600 @40")
	assert_str(_log()).is_empty()
	_play("d2 500,500 @50; m2 600,600 @60; u0 100,200 @70")  # finger 0 lifts: 1 and 2 are the pair
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.MULTI)
	assert_str(_log()).is_empty()
	_play("m2 660,680 @80")  # distance 500 -> 600, centre 450,400 -> 480,440
	assert_str(_log()).is_equal("PINCH 480,440,30,40,1.2")
	_play("u1 300,200 @90; m2 700,680 @100; u2 700,680 @110")
	assert_str(_log()).is_equal("CAMERA_END; PAN 40,0; CAMERA_END")
	# The second tracked finger lifts: 0 and 2 are the pair.
	_play("d0 0,0 @200; d1 300,0 @210; d2 300,400 @220; u1 300,0 @230; m2 480,640 @240")
	assert_str(_log()).is_equal("PINCH 240,320,90,120,1.6")


func test_pinch_never_divides_by_a_zero_distance_and_keeps_scale_1_below_8_dp() -> void:
	# [gap between the fingers, how far the second one moves, the PINCH]
	var cases: Array[Array] = [
		[0.0, 30.0, "PINCH 115,200,15,0,1"],  # both on one point
		[7.5, 7.5, "PINCH 107.5,200,3.75,0,1"],
		[8.0, 8.0, "PINCH 108,200,4,0,2"],
		[30.0, 100.0, "PINCH 165,200,50,0,4.33"],
	]
	for c: Array in cases:
		assert_str(_spread_log(c[0], c[1])).is_equal(c[2])
	_rec.configure(load(SETTINGS_PATH) as InputSettings, 2.0)  # the minimum is 16 px there
	assert_str(_spread_log(15.0, 15.0)).is_equal("PINCH 115,200,7.5,0,1")
	assert_str(_spread_log(16.0, 16.0)).is_equal("PINCH 116,200,8,0,2")


func test_a_new_recognizer_has_the_default_thresholds_and_configure_is_safe_mid_gesture() -> void:
	_rec = GestureRecognizer.new()  # never configured: the InputSettings defaults at 1 px per dp
	assert_str(_drag_log(0, false, Vector2(11.9, 0))).is_equal(TAP_A)
	assert_str(_drag_log(1000, false, Vector2(12.1, 0))).is_equal("PAN 12.1,0; CAMERA_END")
	_play("d0 100,200 @2000; a @2299")
	assert_str(_log()).is_empty()
	_play("a @2300; k")
	assert_str(_log()).is_equal("LONG_PRESS 100,200; BOX_CANCEL")
	_tap(A, 3000, 3050)
	_tap(A + Vector2(32, 0), 3350, 3400)
	assert_str(_log()).is_equal(TAP_A + "; DOUBLE_TAP 132,200")
	# configure() swaps thresholds only. A gesture under way keeps its state.
	var settings: InputSettings = load(SETTINGS_PATH) as InputSettings
	_play("d0 100,200 @4000")
	_rec.configure(settings, 2.0)
	_play("m0 120,200 @4010")  # 20 px is inside the new 24 px slop
	assert_int(_rec.state()).is_equal(GestureRecognizer.State.PENDING)
	_play("u0 120,200 @4020; d0 100,200 @5000; m0 130,200 @5010")  # 30 px: a pan
	_rec.configure(settings, 1.0)
	_play("m0 135,200 @5020; u0 135,200 @5030")
	assert_str(_log()).is_equal(TAP_A + "; PAN 30,0; PAN 5,0; CAMERA_END")


func test_take_events_appends_in_order_clears_the_queue_and_counts() -> void:
	_tap(A, 0, 50)
	_tap(Vector2(500, 300), 1000, 1050)
	var out: Array[GestureEvent] = [GestureEvent.new(GestureEvent.Kind.PAN)]
	assert_int(_rec.take_events(out)).is_equal(2)
	assert_int(_rec.take_events(out)).is_equal(0)
	assert_int(out.size()).is_equal(3)
	assert_vector(out[2].position).is_equal(Vector2(500, 300))


func test_sources_are_ref_counted_and_use_no_node_input_or_time() -> void:
	var banned: RegEx = RegEx.create_from_string(BANNED)
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
## PAN, the rect for BOX_UPDATE and BOX_END and "centre, delta, scale" for PINCH, rounded to 0.01.
## CAMERA_END and BOX_CANCEL have no numbers.
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
			GestureEvent.Kind.PINCH:
				numbers = [
					event.centre.x, event.centre.y, event.delta.x, event.delta.y, event.scale
				]
		var text: PackedStringArray = []
		for number: float in numbers:
			text.append(("%.2f" % number).trim_suffix("0").trim_suffix("0").trim_suffix("."))
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


## Two fingers `gap` apart; the second moves `move` further. The log of that one PINCH.
func _spread_log(gap: float, move: float) -> String:
	_rec.touch_down(0, A, 0)
	_rec.touch_down(1, A + Vector2(gap, 0), 10)
	_rec.touch_move(1, A + Vector2(gap + move, 0), 20)
	var got: String = _log()
	_rec.cancel_all()
	_log()
	return got
