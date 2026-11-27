extends "res://tests/ui/tutorial/support/unit_anchor_suite.gd"
## Where a `UNIT` hand's drag starts when the unit stands under a card button or a HUD part (plan
## row P593b-4, ADR 0048 section 13.5): on the nearest free field point, vector unchanged, never on
## a button; with no free point, no hand. The set-up is `unit_anchor_suite.gd`.

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const BUTTON: Vector2 = Vector2(160.0, 56.0)

var _plan: GuideHintPlan = GuideHintPlan.new()
var _settings: GuideSettingsDef = null
var _buttons: Array[Rect2] = []
var _aim_def: TutorialLeadInDef = null
var _beat_def: TutorialBeatDef = null


func before_test() -> void:
	super()
	_settings = GuideSettingsDef.new()
	_settings.hint_size_dp = 64.0
	_settings.hint_margin_dp = 4.0
	_settings.hint_drag_max_dp = 200.0
	_buttons = []
	_look_at(7)
	_aim_def = _aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA)
	_beat_def = Lesson.beat("unit", TutorialConditions.Kind.NEXT, {})


func test_a_unit_under_next_skip_or_the_tab_starts_the_drag_on_free_ground() -> void:
	_anchor_up()
	var home: Vector2 = _anchor.point
	for count: int in [1, 2, 3]:  # Next; Next and Skip; Next, Skip and the tab, side by side.
		_buttons = _buttons_at(count)
		_run(_buttons)
		assert_bool(_anchor.in_field).is_false()
		assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
		_assert_free(_plan.point, count)
		assert_that(_plan.point).is_not_equal(home)
		assert_bool(SAFE.encloses(_plan.bounds)).is_true()


func test_the_vector_keeps_its_way_into_the_field() -> void:
	_buttons = _buttons_at(1)
	_run(_buttons)
	var way: Vector2 = (_field() - _anchor.point) / 1.0
	assert_float(_plan.vector_dp.normalized().dot(way.normalized())).is_greater(0.95)
	assert_float(_plan.vector_dp.length()).is_less_equal(_settings.hint_drag_max_dp + 0.01)


func test_a_start_clear_of_every_rect_stays_where_it_was() -> void:
	_buttons = [Rect2(Vector2(10.0, 10.0), BUTTON)]
	_hud[HudCorners.PILL] = Rect2(Vector2(10.0, 400.0), Vector2(100.0, 40.0))
	_anchor_up()
	assert_bool(_anchor.clear_at(_anchor.point)).is_true()
	_run(_buttons)
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.TAP)
	assert_that(_plan.point).is_equal(_anchor.point)


func test_a_hud_rect_under_the_unit_moves_the_start_off_it_too() -> void:
	_anchor_up()
	var at: Vector2 = _anchor.point
	_hud[HudCorners.PILL] = Rect2(at - Vector2(100.0, 40.0), Vector2(200.0, 80.0))
	_buttons = [Rect2(at - Vector2(20.0, 20.0), Vector2(40.0, 40.0))]
	_run(_buttons)
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
	_assert_free(_plan.point, 1)


func test_no_free_point_means_no_hand() -> void:
	_buttons = [SAFE.grow(-1.0)]  # A button over the whole screen: the band leaves no free point.
	_run(_buttons)
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.NONE)
	assert_bool(_plan.bounds.has_area()).is_false()
	_buttons = _buttons_at(1)  # And it is back once a button leaves room.
	_run(_buttons)
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)


func test_the_band_and_the_dp_grow_the_buttons_the_start_must_clear() -> void:
	_buttons = _buttons_at(1)
	for dp: float in [1.0, 2.5]:
		_anchor.update(_aim_def, _runner, _camera, _ground, _air, SAFE, dp, _hud, _buttons)
		_plan.resolve(
			_beat_def, _aim_def, false, Rect2(), _camera, _field_of, SAFE, dp, _settings, _anchor
		)
		assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
		var grown: Rect2 = _buttons[0].grow(GuideUnitAnchor.THROUGH_BAND_DP * dp)
		assert_bool(grown.has_point(_plan.point)).override_failure_message(str(dp)).is_false()


func test_the_nearest_free_point_wins() -> void:
	_buttons = _tall_button()
	_run(_buttons)
	var band: float = GuideUnitAnchor.THROUGH_BAND_DP + GuideHintPlan.START_GAP_DP + _hang_right()
	# The button reaches 20 px left of the unit and 60 right: its left side is the nearer.
	assert_float(_plan.point.x).is_equal_approx(_buttons[0].position.x - band, 0.01)
	assert_float(_plan.point.y).is_equal_approx(_anchor.point.y, 0.01)


func test_a_candidate_the_clamp_pushes_into_a_blocked_rect_is_rejected() -> void:
	_buttons = _tall_button()
	var top: Rect2 = Rect2(Vector2(0.0, _anchor.point.y - 5.0), SAFE.size)  # Hand box leaves it.
	_run(_buttons, top)
	var nearest: Vector2 = _plan.point
	assert_float(nearest.y - _anchor.point.y).is_greater(12.0)  # The clamp moved it down.
	var trap: Rect2 = Rect2(nearest - Vector2(10.0, 10.0), Vector2(20.0, 20.0))
	assert_bool(trap.has_point(Vector2(nearest.x, _anchor.point.y))).is_false()  # Clear before it.
	_hud[HudCorners.PILL] = trap
	_run(_buttons, top)
	assert_bool(_plan.kind == TutorialBeatDef.Gesture.NONE or _plan.point != nearest).is_true()
	if _plan.kind != TutorialBeatDef.Gesture.NONE:
		assert_bool(_anchor.clear_at(_plan.point)).is_true()
		assert_bool(trap.has_point(_plan.point)).is_false()


func test_the_card_rect_does_not_block_a_start_inside_it() -> void:
	_anchor_up()
	var at: Vector2 = _anchor.point
	_hud[HudCorners.CARD] = Rect2(at - Vector2(300.0, 200.0), Vector2(600.0, 400.0))
	_buttons = [Rect2(at - Vector2(30.0, 20.0), Vector2(60.0, 40.0))]
	_run(_buttons)
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
	var card: Rect2 = _hud[HudCorners.CARD]
	assert_bool(card.has_point(_plan.point)).is_true()
	assert_bool(_buttons[0].grow(GuideUnitAnchor.THROUGH_BAND_DP).has_point(_plan.point)).is_false()
	var gap: float = GuideUnitAnchor.THROUGH_BAND_DP + GuideHintPlan.START_GAP_DP + _hang_right()
	assert_float(_plan.point.distance_to(at)).is_less(30.0 + gap + 1.0)  # Just outside the hint.


func test_a_move_along_one_axis_that_lands_in_another_rect_leaves_no_hand() -> void:
	_anchor_up()
	var at: Vector2 = _anchor.point
	_buttons = [Rect2(at - Vector2(20.0, 20.0), Vector2(40.0, 40.0))]
	# A band along the unit's row stops the x moves, a column through it the y moves; free ground
	# lies in the corners, but a start moves along one axis only.
	_hud[HudCorners.PILL] = Rect2(Vector2(0.0, at.y - 60.0), Vector2(SAFE.size.x, 120.0))
	_hud[HudCorners.BUILD] = Rect2(Vector2(at.x - 60.0, 0.0), Vector2(120.0, SAFE.size.y))
	_run(_buttons)
	assert_bool(_anchor.clear_at(Vector2(100.0, 100.0))).is_true()
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.NONE)


func test_the_drawn_ring_and_hand_clear_next_skip_and_the_tab() -> void:
	for dp: float in [1.0, 2.5]:
		for count: int in [1, 2, 3]:
			_buttons = _buttons_at(count)
			_hud[HudCorners.PILL] = Rect2(_anchor.point + Vector2(0.0, 90.0), Vector2(200.0, 40.0))
			_anchor.update(_aim_def, _runner, _camera, _ground, _air, SAFE, dp, _hud, _buttons)
			_plan.resolve(
				_beat_def,
				_aim_def,
				false,
				Rect2(),
				_camera,
				_field_of,
				SAFE,
				dp,
				_settings,
				_anchor
			)
			assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
			_assert_drawn_clear(dp, "%d at %s dp" % [count, dp])


func test_a_start_the_point_and_band_rule_passed_is_moved_off_the_ring_and_hand() -> void:
	_anchor_up()
	var at: Vector2 = _anchor.point
	# The P593b-4 rule (point outside the rect grown by the band) passes just left of the button,
	# but the 64 dp hand's box reaches 38 px right of the tip into it.
	_buttons = [Rect2(at + Vector2(-12.0, -100.0), Vector2(160.0, 200.0))]
	_run(_buttons)
	assert_int(_plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
	var old: Vector2 = Vector2(_buttons[0].position.x - GuideUnitAnchor.THROUGH_BAND_DP - 1.0, at.y)
	assert_bool(_anchor.clear_at(old)).is_true()  # The old rule would take this start...
	assert_bool(_drawn(old, 1.0)[1].intersects(_buttons[0])).is_true()  # ...and draw on the button.
	_assert_drawn_clear(1.0, "old rule")
	assert_bool(_plan.point.x < old.x).is_true()


func _field_of() -> Vector2:
	return _field()


func _field() -> Vector2:
	return SAFE.get_center() + Vector2(0.0, 150.0)


## `count` buttons in a row, the first one centred on the unit.
func _buttons_at(count: int) -> Array[Rect2]:
	_anchor_up()
	var made: Array[Rect2] = []
	var first: Vector2 = _anchor.point - BUTTON * 0.5
	for index: int in count:
		made.append(Rect2(first + Vector2((BUTTON.x + 10.0) * index, 0.0), BUTTON))
	return made


## One tall button, 20 px left of the unit to 60 px right of it.
func _tall_button() -> Array[Rect2]:
	_anchor_up()
	var at: Vector2 = _anchor.point
	return [Rect2(at + Vector2(-20.0, -100.0), Vector2(80.0, 200.0))]


func _anchor_up() -> void:
	_anchor.update(_aim_def, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, NO_BUTTONS)


func _run(buttons: Array[Rect2], safe: Rect2 = SAFE) -> void:
	_anchor.update(_aim_def, _runner, _camera, _ground, _air, safe, 1.0, _hud, buttons)
	_plan.resolve(
		_beat_def, _aim_def, false, Rect2(), _camera, _field_of, safe, 1.0, _settings, _anchor
	)


## How far the hand's box hangs right of the tip, or the ring's reach if that is more: px at dp 1.
func _hang_right() -> float:
	var side: float = _settings.hint_size_dp
	var reach: float = GestureHint.ring_reach_dp(side, 1)
	return maxf(reach, (1.0 - GestureHint.POINT_TIP.x) * side)


## The drawn ring's square and the hand's box (the tip at `at`, no flip) at `dp`.
func _drawn(at: Vector2, dp: float) -> Array[Rect2]:
	var side: float = _settings.hint_size_dp * dp
	var reach: float = GestureHint.ring_reach_dp(_settings.hint_size_dp, 1) * dp
	var ring: Rect2 = Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var hand: Rect2 = Rect2(at - GestureHint.POINT_TIP * side, Vector2(side, side))
	return [ring, hand]


func _assert_drawn_clear(dp: float, label: String) -> void:
	for box: Rect2 in _drawn(_plan.point, dp):
		for rect: Rect2 in _buttons:
			assert_bool(box.intersects(rect)).override_failure_message(label).is_false()
		for key: StringName in _hud:
			if key != HudCorners.CARD:
				assert_bool(box.intersects(_hud[key])).override_failure_message(label).is_false()


func _assert_free(at: Vector2, count: int) -> void:
	var band: float = GuideUnitAnchor.THROUGH_BAND_DP
	assert_bool(SAFE.has_point(at)).is_true()
	for rect: Rect2 in _buttons:
		assert_bool(rect.grow(band).has_point(at)).override_failure_message(str(count)).is_false()
	for key: StringName in _hud:
		assert_bool(_hud[key].has_point(at)).override_failure_message(str(key)).is_false()
