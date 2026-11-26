extends GdUnitTestSuite
## The coach mark on a `UNIT` step (plan P593b-1b, ADR 0048 section 13.5) over controls_test: the
## ring follows a moving unit, is pinned at the edge off screen, the hand drags when the unit is
## not in the field and taps when it is, no unit gives no ring and no hand, the card turns back
## from see-through only past an 8 dp band, and the card is not laid out for a ring-only move.

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const NEAR: Vector2 = Vector2(1.0, 1.0)

var _runner: MatchRunner
var _camera: RtsCamera
var _ground: UnitLayer
var _air: AirLayer
var _director: TutorialDirector
var _mark: CoachMark
var _hud_root: Control
var _fit: CountingFit
var _window_before: Vector2i


## A card fit that counts the layouts it is asked for.
class CountingFit:
	extends GuideCardFit
	var count: int = 0

	func fit(
		width: float, max_height: float, dp: float, mirror: bool, settings: GuideSettingsDef
	) -> Vector2:
		count += 1
		return super(width, max_height, dp, mirror, settings)


func before() -> void:
	_window_before = get_window().size


func after() -> void:
	get_window().size = _window_before


func before_test() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	var snap: MatchSnapshot = _runner.snapshot
	var fog: FogGrid = snap.fog
	var tiles: Array = []
	for cell: int in fog.cells:
		tiles.append(Vector2i(cell % fog.cols, cell / fog.cols))
	Buildings.see(snap, 1, tiles)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_ground = auto_free(UnitLayer.new())
	_ground.runner = _runner
	_ground.camera = _camera
	add_child(_ground)
	_ground.set_process(false)
	_air = auto_free(Air.layer(self, _runner))
	_director = auto_free(TutorialDirector.new())
	_director.runner = _runner
	_director.hud = HudState.new()
	_director.selection = SelectionModel.new()


func after_test() -> void:
	for item: Node in [_mark, _hud_root]:
		if is_instance_valid(item):
			item.get_parent().remove_child(item)
			item.free()
	_mark = null
	_hud_root = null


func test_the_ring_stands_on_the_unit_and_follows_it() -> void:
	await _open(_beat(), 7)
	var unit: GuideUnitAnchor = _mark.unit_anchor()
	assert_int(unit.unit_id).is_equal(7)
	assert_that(_mark.ring_rect().get_center()).is_equal_approx(unit.point, NEAR)
	var before: Vector2 = _mark.ring_rect().get_center()
	_ground.rig(6).position += Vector2(60.0, 0.0)  # The unit moves.
	await _settle()
	var moved: Vector2 = _mark.ring_rect().get_center() - before
	assert_float(moved.x).is_equal_approx(60.0 * _camera.zoom.x, 1.0)
	assert_that(_mark.ring_rect().get_center()).is_equal_approx(unit.point, NEAR)


func test_off_screen_the_ring_is_pinned_and_the_hand_drags() -> void:
	await _open(_beat(), 7)
	_ground.rig(6).position += Vector2(6000.0, 0.0)
	await _settle()
	var safe: Rect2 = _safe()
	assert_bool(_mark.unit_anchor().in_field).is_false()
	assert_bool(_mark.ring_rect().has_area()).is_true()
	assert_bool(safe.grow(0.5).encloses(_mark.ring_rect())).is_true()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.DRAG)
	assert_bool(_mark.gesture_plan().off_screen).is_true()


func test_in_the_field_the_hand_taps_the_unit() -> void:
	await _open(_beat(), 7)
	assert_bool(_mark.unit_anchor().in_field).is_true()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.TAP)
	assert_that(_mark.gesture_plan().point).is_equal_approx(_mark.unit_anchor().point, NEAR)


func test_no_unit_means_no_ring_and_no_hand() -> void:
	var beat: TutorialBeatDef = _beat()
	beat.unit.type_id = &"no_such_type"
	await _open(beat, 7)
	assert_int(_mark.unit_anchor().unit_id).is_equal(-1)
	assert_bool(_mark.ring_rect().has_area()).is_false()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.NONE)
	assert_bool(_mark.card_open()).is_true()  # The card alone, as today.


func test_the_card_turns_back_from_see_through_only_past_the_8_dp_band() -> void:
	var beat: TutorialBeatDef = _beat()
	beat.gesture = TutorialBeatDef.Gesture.NONE  # No hand: the ring alone meets the card.
	await _open(beat, 7)
	var dp: float = UiScale.base_px_per_dp()
	var half: float = _mark.ring_rect().size.y * 0.5
	var foot: float = _mark.card_rect().end.y
	await _stand_at(foot + half - 2.0 * dp)  # The ring's top 2 dp inside the card.
	assert_bool(_mark.see_through()).is_true()
	await _stand_at(foot + half + 4.0 * dp)  # Clear by 4 dp: inside the band, still through.
	assert_bool(_mark.see_through()).is_true()
	await _stand_at(foot + half + 12.0 * dp)  # Clear by 12 dp: back.
	assert_bool(_mark.see_through()).is_false()
	await _stand_at(foot + half + 4.0 * dp)  # Back inside the band: no flicker.
	assert_bool(_mark.see_through()).is_false()


func test_a_ring_only_move_does_not_lay_the_card_out_again() -> void:
	await _open(_beat(), 7, true)
	await _settle()
	var laid: int = _fit.count
	for step: int in 5:
		_ground.rig(6).position += Vector2(3.0, 1.0)
		await await_idle_frame()
	assert_int(laid).is_greater(0)  # The counter does fire for a layout.
	assert_int(_fit.count).is_equal(laid)
	assert_that(_mark.ring_rect().get_center()).is_equal_approx(_mark.unit_anchor().point, NEAR)


func test_a_control_ring_has_no_band() -> void:
	var beat: TutorialBeatDef = (
		Lesson
		. beat(
			"control",
			TutorialConditions.Kind.NEXT,
			{
				"anchor": TutorialBeatDef.Anchor.CONTROL,
				"anchor_control": &"CoachTarget",
				"gesture": TutorialBeatDef.Gesture.NONE,
			}
		)
	)
	var target: Control = Control.new()
	target.name = "CoachTarget"
	var dp: float = UiScale.base_px_per_dp()
	target.size = Vector2.ONE * 56.0 * dp
	await _open(beat, 7, false, target)
	var foot: float = _mark.card_rect().end.y
	var grow: float = GuideRing.RING_GROW_DP * dp
	target.position = Vector2(_view().x * 0.5, foot - 2.0 * dp + grow)  # The ring meets the card.
	await _settle()
	assert_bool(_mark.see_through()).is_true()
	target.position.y = foot + 4.0 * dp + grow  # 4 dp clear: a control keeps no band.
	await _settle()
	assert_bool(_mark.see_through()).is_false()


func test_a_tile_ring_has_no_band() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var tile: Vector2i = Vector2i(snap.map_cols / 2, snap.map_rows / 2)
	var beat: TutorialBeatDef = (
		Lesson
		. beat(
			"tile",
			TutorialConditions.Kind.NEXT,
			{
				"anchor": TutorialBeatDef.Anchor.TILE,
				"anchor_tile": tile,
				"gesture": TutorialBeatDef.Gesture.NONE,
			}
		)
	)
	await _open(beat, 7)
	var dp: float = UiScale.base_px_per_dp()
	var half: float = _mark.ring_rect().size.y * 0.5
	var foot: float = _mark.card_rect().end.y
	var cell: Vector2 = IsoProjection.cell_centre_px(tile.x, tile.y)
	await _centre_tile(cell, foot + half - 2.0 * dp)
	assert_bool(_mark.see_through()).is_true()
	await _centre_tile(cell, foot + half + 4.0 * dp)
	assert_bool(_mark.see_through()).is_false()


func test_a_unit_lead_in_off_the_field_gets_the_drag_and_its_own_gesture_rules() -> void:
	var step: TutorialLeadInDef = TutorialLeadInDef.new()
	step.anchor = TutorialBeatDef.Anchor.UNIT
	step.unit = TutorialUnitPickDef.new()
	step.kind = TutorialConditions.Kind.SELECTED
	var beat: TutorialBeatDef = (
		Lesson
		. beat(
			"lead",
			TutorialConditions.Kind.NEXT,
			{
				"anchor": TutorialBeatDef.Anchor.CONTROL,
				"anchor_control": &"CoachTarget",
				"lead_in": [step],
				"gesture": TutorialBeatDef.Gesture.NONE,  # The beat's own gesture is not the step's.
			}
		)
	)
	await _open(beat, 7)
	_ground.rig(6).position += Vector2(6000.0, 0.0)
	await _settle()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.DRAG)
	assert_bool(_mark.gesture_plan().off_screen).is_true()
	step.gesture = TutorialBeatDef.Gesture.NONE  # An explicit NONE on the step suppresses it.
	_mark._dirty = true
	await _settle()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.NONE)


func test_an_explicit_none_on_the_final_unit_step_suppresses_the_drag() -> void:
	var beat: TutorialBeatDef = _beat()
	beat.gesture = TutorialBeatDef.Gesture.NONE
	await _open(beat, 7)
	_ground.rig(6).position += Vector2(6000.0, 0.0)
	await _settle()
	assert_bool(_mark.unit_anchor().in_field).is_false()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.NONE)


func test_a_unit_under_a_dock_rect_is_not_in_the_field_and_gets_the_drag() -> void:
	await _open(_beat(), 7)
	var part: Rect2 = _mark._dock_rects[HudCorners.PILL]
	assert_bool(part.has_area()).is_true()
	await _put_unit_at(part.get_center())
	assert_bool(_safe().has_point(_mark.unit_anchor().point)).is_true()  # On the screen.
	assert_bool(_mark.unit_anchor().in_field).is_false()
	assert_int(_mark.gesture_plan().kind).is_equal(TutorialBeatDef.Gesture.DRAG)


func test_the_drag_runs_from_the_pinned_edge_toward_the_field_point() -> void:
	for away: Vector2 in [Vector2(6000.0, 0.0), Vector2(-6000.0, 2000.0), Vector2(0.0, -6000.0)]:
		await _open(_beat(), 7)
		_ground.rig(6).position += away
		await _settle()
		var plan: GuideHintPlan = _mark.gesture_plan()
		assert_int(plan.kind).is_equal(TutorialBeatDef.Gesture.DRAG)
		var want: Vector2 = (_mark._field_point() - plan.point).normalized()
		(
			assert_float(plan.vector_dp.normalized().dot(want))
			. override_failure_message(str(away))
			. is_greater(0.95)
		)
		_mark.get_parent().remove_child(_mark)
		_mark.free()
		_hud_root.free()
		_mark = null
		_hud_root = null
		_director.skip()


func _beat() -> TutorialBeatDef:
	var pick: TutorialUnitPickDef = TutorialUnitPickDef.new()
	pick.pick = TutorialUnitPickDef.Pick.NEAREST_CAMERA
	return Lesson.beat(
		"unit", TutorialConditions.Kind.NEXT, {"anchor": TutorialBeatDef.Anchor.UNIT, "unit": pick}
	)


## The mark over a HUD root with `beat` on show, the camera over unit `id`.
func _open(beat: TutorialBeatDef, id: int, counting: bool = false, target: Control = null) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	_camera.centre_on(IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]))
	_ground._process(0.0)
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)
	if target != null:
		_hud_root.add_child(target)
	_mark = CoachMark.new()
	_mark.hud_root = _hud_root
	_mark.camera = _camera
	_mark.runner = _runner
	_mark.ground_layer = _ground
	_mark.air_layer = _air
	_mark.director = _director
	if counting:
		_fit = CountingFit.new()
		_mark._fit = _fit
	add_child(_mark)
	_director.start(Lesson.lesson("basics", [beat]))
	_director.advance()
	await _settle()
	await _stand_at(get_viewport().get_visible_rect().size.y * 0.6)  # Clear of the map's edge.


## Moves unit 7 so that its tap point (the ring's centre) is `y` px down the screen, in the card's
## middle column.
func _stand_at(y: float) -> void:
	var rig: Node2D = _ground.rig(6)
	var lift: Vector2 = rig.global_position - _ground.tap_point(7)
	var x: float = get_viewport().get_visible_rect().size.x * 0.5
	rig.global_position = _camera.screen_to_world(Vector2(x, y)) + lift
	await _settle()


func _settle() -> void:
	for turn: int in 4:
		await await_idle_frame()


func _safe() -> Rect2:
	return SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)


func _view() -> Vector2:
	return get_viewport().get_visible_rect().size


## Moves unit 7 so that its tap point is at screen point `at`.
func _put_unit_at(at: Vector2) -> void:
	var rig: Node2D = _ground.rig(6)
	var lift: Vector2 = rig.global_position - _ground.tap_point(7)
	rig.global_position = _camera.screen_to_world(at) + lift
	await _settle()


## Centres the camera so that the world point `cell` stands at the middle column, `y` down.
func _centre_tile(cell: Vector2, y: float) -> void:
	var at: Vector2 = Vector2(_view().x * 0.5, y)
	_camera.centre_on(cell - (at - _view() * 0.5) / _camera.zoom)
	await _settle()
