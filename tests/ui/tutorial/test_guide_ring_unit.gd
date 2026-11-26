extends GdUnitTestSuite
## `GuideRing.box` (plan P593b-1, ADR 0048 section 13.5): the UNIT branch (the 48 dp floor, the edge
## pin, no unit no ring) and the CONTROL and TILE branches unchanged by the optional parameter.

const VIEW: Vector2 = Vector2(1280.0, 720.0)
const SAFE: Rect2 = Rect2(20.0, 10.0, 1240.0, 700.0)

var _camera: RtsCamera
var _unit: GuideUnitAnchor


func before_test() -> void:
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_unit = GuideUnitAnchor.new()


func test_a_tiny_unit_gets_the_48_dp_floor_about_its_point() -> void:
	_unit.point = Vector2(400.0, 300.0)
	_unit.half = 5.0
	var box: Rect2 = _box(_aim(TutorialBeatDef.Anchor.UNIT), 2.0, _unit)
	assert_that(box.size).is_equal(Vector2(96.0, 96.0))
	assert_that(box.get_center()).is_equal(_unit.point)


func test_a_big_unit_keeps_its_own_size() -> void:
	_unit.point = Vector2(400.0, 300.0)
	_unit.half = 80.0
	assert_that(_box(_aim(TutorialBeatDef.Anchor.UNIT), 1.0, _unit).size).is_equal(
		Vector2(160.0, 160.0)
	)


func test_an_off_screen_unit_is_pinned_inside_the_safe_rect() -> void:
	for far: Vector2 in [Vector2(-900.0, 300.0), Vector2(5000.0, 300.0), Vector2(400.0, -700.0)]:
		_unit.point = far
		_unit.half = 30.0
		var box: Rect2 = _box(_aim(TutorialBeatDef.Anchor.UNIT), 1.0, _unit)
		assert_bool(box.has_area()).is_true()
		assert_bool(SAFE.encloses(box)).override_failure_message(str(far)).is_true()


func test_no_unit_or_an_inf_point_is_an_empty_rect() -> void:
	var aim: TutorialLeadInDef = _aim(TutorialBeatDef.Anchor.UNIT)
	assert_bool(_box(aim, 1.0, null).has_area()).is_false()
	_unit.point = Vector2.INF
	_unit.half = 30.0
	assert_bool(_box(aim, 1.0, _unit).has_area()).is_false()


func test_control_and_tile_do_not_read_the_unit() -> void:
	_unit.point = Vector2(900.0, 500.0)
	_unit.half = 30.0
	var holder: Control = auto_free(Control.new())
	add_child(holder)
	var button: Control = Control.new()
	button.position = Vector2(100.0, 100.0)
	button.size = Vector2(200.0, 100.0)
	holder.add_child(button)
	var control: TutorialLeadInDef = _aim(TutorialBeatDef.Anchor.CONTROL)
	var with_unit: Rect2 = GuideRing.box(control, button, _camera, holder, VIEW, SAFE, 1.0, _unit)
	var without: Rect2 = GuideRing.box(control, button, _camera, holder, VIEW, SAFE, 1.0)
	assert_that(with_unit).is_equal(without)
	assert_that(without).is_equal(button.get_global_rect().grow(GuideRing.RING_GROW_DP))
	var tile: TutorialLeadInDef = _aim(TutorialBeatDef.Anchor.TILE)
	tile.anchor_tile = Vector2i(0, 0)
	var at: Rect2 = _box(tile, 1.0, _unit)
	assert_that(at).is_equal(_box(tile, 1.0, null))
	var centre: Vector2 = _camera.world_to_screen(IsoProjection.cell_centre_px(0, 0))
	assert_that(at.get_center()).is_equal_approx(centre, Vector2(0.01, 0.01))


func _aim(anchor: TutorialBeatDef.Anchor) -> TutorialLeadInDef:
	var step: TutorialLeadInDef = TutorialLeadInDef.new()
	step.anchor = anchor
	return step


func _box(aim: TutorialLeadInDef, dp: float, unit: GuideUnitAnchor) -> Rect2:
	return GuideRing.box(aim, null, _camera, null, VIEW, SAFE, dp, unit)
