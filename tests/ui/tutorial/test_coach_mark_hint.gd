extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The gesture hint wired into the coach mark (plan row P592, ADR 0048 section 6): where it
## stands and which gesture it plays for each case `GuideHintPlan` resolves, at the six sizes and
## the profiles web_phone_small and web_phone_portrait; always inside the safe rect, above the
## card, static with Reduced effects, hidden under a real touch, and part of the see-through test.

const PAN: TutorialConditions.Kind = TutorialConditions.Kind.CAMERA_PANNED
const ZOOM: TutorialConditions.Kind = TutorialConditions.Kind.ZOOM_LEVEL


func _profiles() -> Array[UiMetrics]:
	var out: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		out.append(_profile(size))
	out.append(UiProfiles.all()[&"web_phone_small"])
	out.append(UiProfiles.portrait()[&"web_phone_portrait"])
	return out


func _tile_beat(tile: Vector2i, fields: Dictionary = {}) -> TutorialBeatDef:
	var all: Dictionary = {"anchor": TutorialBeatDef.Anchor.TILE, "anchor_tile": tile}
	all.merge(fields, true)
	return Lesson.beat("tile", NEXT, all)


func _plan() -> GuideHintPlan:
	return _mark.gesture_plan()


func _hand() -> GestureHint:
	return _mark.find_child("GestureHint", true, false) as GestureHint


func _settle() -> void:
	for turn: int in 3:
		await await_idle_frame()


func _expect_inside(label: String) -> void:
	var plan: GuideHintPlan = _plan()
	(
		assert_bool(_safe().grow(TOLERANCE_PX).encloses(plan.bounds))
		. override_failure_message("%s: %s outside %s" % [label, plan.bounds, _safe()])
		. is_true()
	)


func test_a_control_gets_a_tap_at_its_centre() -> void:
	for profile: UiMetrics in _profiles():
		await _open(profile, _control_beat("hit", NEXT))
		var label: String = str(profile.window_size)
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.TAP
		)
		assert_bool(_hand().visible).override_failure_message(label).is_true()
		assert_vector(_plan().point).override_failure_message(label).is_equal_approx(
			_mark.ring_rect().get_center(), Vector2.ONE * 1.0
		)
		_expect_inside(label)
		_close()


func test_a_control_at_the_edge_keeps_the_hand_inside_the_safe_rect() -> void:
	for profile: UiMetrics in _profiles():
		for corner: Vector2 in [Vector2(0.02, 0.98), Vector2(0.98, 0.02), Vector2(0.98, 0.98)]:
			await _open(profile, _control_beat("hit", NEXT))
			_put_target(corner)
			await _settle()
			var label: String = "%s %s" % [profile.window_size, corner]
			_expect_inside(label)
			# The fingertip stays on the control's centre; the hand hangs the other way.
			(
				assert_bool(_mark.ring_rect().has_point(_plan().point))
				. override_failure_message(label)
				. is_true()
			)
			assert_vector(_plan().point).override_failure_message(label).is_equal_approx(
				_mark.ring_rect().get_center(), Vector2.ONE
			)
			_close()


func test_a_beat_with_no_anchor_pans_with_a_drag_at_the_field() -> void:
	for profile: UiMetrics in _profiles():
		await _open(profile, Lesson.beat("pan", PAN), true)
		var label: String = str(profile.window_size)
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.DRAG
		)
		assert_bool(_plan().off_screen).is_false()
		_expect_inside(label)
		# On a short field the hand reaches the card; then the card turns see-through (section 3).
		var meets: bool = _plan().bounds.intersects(_mark.card_rect())
		assert_bool(_mark.see_through()).override_failure_message(label).is_equal(meets)
		_close()


func test_a_pan_beat_uses_the_data_vector() -> void:
	var beat: TutorialBeatDef = Lesson.beat("pan", PAN, {"gesture_vector_dp": Vector2i(0, -120)})
	await _open(_profile(ScreenSizes.PORTRAIT[0]), beat, true)
	assert_vector(_plan().vector_dp).is_equal(Vector2(0.0, -120.0))
	assert_vector(_hand().vector_dp).is_equal(Vector2(0.0, -120.0))
	_expect_inside("vector")
	_close()


func test_a_zoom_beat_pinches_out_to_zoom_in_and_in_to_zoom_out() -> void:
	for profile: UiMetrics in _profiles():
		await _open(profile, Lesson.beat("zoom", ZOOM, {"value": 2}), true)
		var label: String = str(profile.window_size)
		_camera.zoom = Vector2.ONE * _camera.settings.zoom_levels[0]
		await _settle()
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.PINCH_OUT
		)
		_expect_inside(label + " out")
		_camera.zoom = Vector2.ONE * _camera.settings.zoom_levels[2]
		_director.current.value = 0
		await _settle()
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.PINCH_IN
		)
		_expect_inside(label + " in")
		_director.current.value = 2
		await _settle()
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.NONE
		)
		assert_bool(_hand().visible).is_false()
		_close()


func test_a_tile_off_the_screen_is_a_drag_toward_the_field() -> void:
	for profile: UiMetrics in _profiles():
		await _open(
			profile, _tile_beat(Vector2i(60, 60), {"gesture": TutorialBeatDef.Gesture.TAP}), true
		)
		var label: String = str(profile.window_size)
		var plan: GuideHintPlan = _plan()
		assert_int(plan.kind).override_failure_message(label).is_equal(TutorialBeatDef.Gesture.DRAG)
		assert_bool(plan.off_screen).override_failure_message(label).is_true()
		assert_bool(plan.vector_dp.length() > 0.0).override_failure_message(label).is_true()
		var tile: Vector2 = _camera.world_to_screen(IsoProjection.cell_centre_px(60, 60))
		var toward: Vector2 = _safe().get_center() - tile
		assert_bool(plan.vector_dp.dot(toward) > 0.0).override_failure_message(label).is_true()
		assert_float(plan.vector_dp.length()).is_less_equal(_mark.settings.hint_drag_max_dp + 0.01)
		_expect_inside(label)
		_close()


func test_a_tile_on_the_screen_plays_its_data_gesture_and_auto_plays_none() -> void:
	for profile: UiMetrics in _profiles():
		var label: String = str(profile.window_size)
		await _open(
			profile, _tile_beat(Vector2i(7, 5), {"gesture": TutorialBeatDef.Gesture.BOX}), true
		)
		_camera.centre_on(IsoProjection.cell_centre_px(7, 5))
		await _settle()
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.BOX
		)
		assert_bool(_plan().off_screen).is_false()
		_expect_inside(label)
		_close()
		await _open(profile, _tile_beat(Vector2i(7, 5)), true)
		_camera.centre_on(IsoProjection.cell_centre_px(7, 5))
		await _settle()
		assert_int(_plan().kind).override_failure_message(label).is_equal(
			TutorialBeatDef.Gesture.NONE
		)
		assert_bool(_hand().visible).is_false()
		_close()


func test_a_none_gesture_shows_no_hand_and_a_set_one_beats_auto() -> void:
	var beat: TutorialBeatDef = _control_beat("hit", NEXT)
	beat.gesture = TutorialBeatDef.Gesture.NONE
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_bool(_hand().visible).is_false()
	assert_bool(_plan().bounds.has_area()).is_false()
	_close()
	beat.gesture = TutorialBeatDef.Gesture.DOUBLE_TAP
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_int(_plan().kind).is_equal(TutorialBeatDef.Gesture.DOUBLE_TAP)
	assert_int(_hand().kind).is_equal(TutorialBeatDef.Gesture.DOUBLE_TAP)
	_close()


func test_a_lead_in_step_taps_its_control_whatever_the_beats_gesture() -> void:
	var beat: TutorialBeatDef = _control_beat("chain", NEXT)
	beat.anchor_control = &"NoSuchControl"
	beat.gesture = TutorialBeatDef.Gesture.BOX
	beat.lead_in.append(
		Lesson.lead_in("CoachTarget", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.DRAWER)
	)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_int(_plan().kind).is_equal(TutorialBeatDef.Gesture.TAP)
	assert_vector(_plan().point).is_equal_approx(_mark.ring_rect().get_center(), Vector2.ONE)
	_close()


func test_reduced_effects_hold_the_hand_still() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT), false, [], true)
	var hand: GestureHint = _hand()
	assert_bool(hand.reduced).is_true()
	var first: GestureHint.Pose = hand.draw_pose()
	assert_float(first.alpha).is_equal(1.0)
	var before: Vector2 = first.finger_a
	hand.advance(700.0)
	assert_vector(hand.draw_pose().finger_a).is_equal(before)
	assert_float(hand.draw_pose().alpha).is_equal(1.0)
	_close()


func test_a_real_touch_hides_the_hand_and_never_marks_it_handled() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var hand: GestureHint = _hand()
	assert_object(hand.draw_pose()).is_not_null()
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2.ONE * 40.0
	hand._input(touch)
	assert_bool(hand.touched_hidden()).is_true()
	assert_object(hand.draw_pose()).is_null()
	assert_int(hand.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	_close()


func test_the_hands_box_joins_the_see_through_test() -> void:
	for portrait: bool in [false, true]:
		var size: Vector2i = ScreenSizes.PORTRAIT[0] if portrait else ScreenSizes.LANDSCAPE[0]
		await _open(_profile(size), _control_beat("hit", NEXT))
		var dp: float = UiScale.base_px_per_dp()
		var card: Rect2 = _mark.card_rect()
		var label: String = str(size)
		# The ring stands 6 dp clear of the card, yet the hand's ring and margin reach it.
		_put_target_at(Vector2(card.get_center().x, card.end.y + 36.0 * dp))
		await _settle()
		assert_bool(_mark.ring_rect().intersects(_mark.card_rect())).is_false()
		assert_bool(_plan().bounds.intersects(_mark.card_rect())).is_true()
		(
			assert_bool(_mark.see_through())
			. override_failure_message(
				(
					"%s hand %s card %s ring %s"
					% [label, _plan().bounds, _mark.card_rect(), _mark.ring_rect()]
				)
			)
			. is_true()
		)
		_put_target_at(Vector2(card.get_center().x, card.end.y + 140.0 * dp))
		await _settle()
		assert_bool(_mark.see_through()).override_failure_message(label).is_false()
		_close()


func _far_tile(side: Vector2) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var world: Vector2 = IsoProjection.cell_centre_px(30, 30)
	_camera.centre_on(world - side * view / _camera.zoom)


func test_an_off_screen_tile_drags_toward_the_field_from_each_side() -> void:
	var sides: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		for gesture: TutorialBeatDef.Gesture in [
			TutorialBeatDef.Gesture.AUTO, TutorialBeatDef.Gesture.TAP, TutorialBeatDef.Gesture.BOX
		]:
			await _open(_profile(size), _tile_beat(Vector2i(30, 30), {"gesture": gesture}), true)
			for side: Vector2 in sides:
				_far_tile(side)
				await _settle()
				var label: String = "%s %s %s" % [size, gesture, side]
				var plan: GuideHintPlan = _plan()
				assert_int(plan.kind).override_failure_message(label).is_equal(
					TutorialBeatDef.Gesture.DRAG
				)
				assert_bool(plan.off_screen).override_failure_message(label).is_true()
				var tile: Vector2 = _camera.world_to_screen(IsoProjection.cell_centre_px(30, 30))
				var toward: Vector2 = _safe().get_center() - tile
				(
					assert_bool(plan.vector_dp.dot(toward) > 0.0)
					. override_failure_message(label)
					. is_true()
				)
				assert_float(plan.vector_dp.length()).override_failure_message(label).is_less_equal(
					_mark.settings.hint_drag_max_dp + 0.01
				)
				_expect_inside(label)
			_close()


func test_an_explicit_none_suppresses_the_drag_toward_an_off_screen_tile() -> void:
	var beat: TutorialBeatDef = _tile_beat(
		Vector2i(30, 30), {"gesture": TutorialBeatDef.Gesture.NONE}
	)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat, true)
	_far_tile(Vector2.LEFT)
	await _settle()
	assert_int(_plan().kind).is_equal(TutorialBeatDef.Gesture.NONE)
	assert_bool(_hand().visible).is_false()
	_close()


func test_the_reduced_key_poses_arrows_lie_inside_the_hands_box() -> void:
	for profile: UiMetrics in _profiles():
		await _open(profile, Lesson.beat("pan", PAN), true, [], true)
		var dp: float = UiScale.base_px_per_dp()
		var label: String = str(profile.window_size)
		var plan: GuideHintPlan = _plan()
		(
			assert_bool(plan.bounds.grow(0.5).has_point(plan.point + plan.vector_dp * dp))
			. override_failure_message(label)
			. is_true()
		)
		_close()
		await _open(profile, Lesson.beat("zoom", ZOOM, {"value": 2}), true, [], true)
		_camera.zoom = Vector2.ONE * _camera.settings.zoom_levels[0]
		await _settle()
		plan = _plan()
		var far: Vector2 = (
			GestureHint.PINCH_AXIS * _mark.settings.hint_size_dp * dp * GestureHint.SPREAD_FAR_SHARE
		)
		for end: Vector2 in [far, -far]:
			(
				assert_bool(plan.bounds.grow(0.5).has_point(plan.point + end))
				. override_failure_message(label)
				. is_true()
			)
		_close()
