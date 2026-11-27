extends "res://tests/ui/tutorial/support/unit_anchor_suite.gd"
## `GuideUnitAnchor`'s ring size, field, flyer and missing-layer cases (plan P593b-1, ADR 0048
## section 13.3 to 13.5); the set-up is `unit_anchor_suite.gd`.


func test_a_missing_layer_means_no_unit() -> void:
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST
	)
	_anchor.update(aim, _runner, _camera, null, _air, SAFE, 1.0, _hud, NO_BUTTONS)
	assert_int(_anchor.unit_id).is_equal(-1)
	_anchor.update(aim, _runner, _camera, _ground, null, SAFE, 1.0, _hud, NO_BUTTONS)
	assert_int(_anchor.unit_id).is_equal(-1)
	assert_that(_anchor.point).is_equal(Vector2.INF)


func test_half_follows_the_zoom_the_dp_and_a_big_selection_radius() -> void:
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST
	)
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[29]
	var art: float = IsoProjection.ellipse_px(snap.type_selection_radius[type]).x
	_camera.zoom = Vector2(2.0, 2.0)
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, NO_BUTTONS)
	assert_float(_anchor.half).is_equal_approx(maxf(art * 2.0, 24.0), 0.001)
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 100.0, _hud, NO_BUTTONS)
	assert_float(_anchor.half).is_equal(2400.0)  # The 24 dp floor at dp 100.
	snap.type_selection_radius[type] = 5000  # A large ring.
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, NO_BUTTONS)
	assert_float(_anchor.half).is_equal_approx(IsoProjection.ellipse_px(5000).x * 2.0, 0.001)
	assert_float(_anchor.half).is_greater(24.0)


func test_in_field_uses_the_given_safe_rect_and_a_gap_between_two_rects() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	var at: Vector2 = _anchor.point
	_hud[HudCorners.PILL] = Rect2(at + Vector2(-60.0, -20.0), Vector2(40.0, 40.0))
	_hud[HudCorners.BUILD] = Rect2(at + Vector2(20.0, -20.0), Vector2(40.0, 40.0))
	_update(aim)  # The point stands in the gap between them.
	assert_bool(_anchor.in_field).is_true()
	var small: Rect2 = Rect2(at + Vector2(100.0, 100.0), Vector2(50.0, 50.0))
	_anchor.update(aim, _runner, _camera, _ground, _air, small, 1.0, _hud, NO_BUTTONS)
	assert_bool(SAFE.has_point(at)).is_true()  # On the screen, but outside the safe rect.
	assert_bool(_anchor.in_field).is_false()


func test_a_flyer_resolves_through_the_air_layer() -> void:
	var runner: MatchRunner = auto_free(Air.runner())
	var air: AirLayer = auto_free(Air.layer(self, runner))
	var ground: UnitLayer = auto_free(UnitLayer.new())
	ground.runner = runner
	ground.camera = _camera
	add_child(ground)
	var fog: FogGrid = runner.snapshot.fog
	var tiles: Array = []
	for cell: int in fog.cells:
		tiles.append(Vector2i(cell % fog.cols, cell / fog.cols))
	Buildings.see(runner.snapshot, 1, tiles)
	air._process(0.0)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST
	)
	aim.unit.type_id = Air.FIGHTER
	_anchor.update(aim, runner, _camera, ground, air, SAFE, 1.0, _hud, NO_BUTTONS)
	assert_int(_anchor.unit_id).is_equal(Air.FIGHTER_ID)
	assert_bool(_anchor.flyer).is_true()
	assert_that(_anchor.point).is_equal_approx(
		_camera.world_to_screen(air.tap_point(Air.FIGHTER_ID)), Vector2(0.01, 0.01)
	)
	assert_that(ground.tap_point(Air.FIGHTER_ID)).is_equal(Vector2.INF)


func test_a_point_under_a_card_button_is_not_in_the_field() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	var at: Vector2 = _anchor.point
	assert_bool(_anchor.in_field).is_true()
	# Next, Skip and the tab are three rects of one list: any of them hides the field.
	for slot: int in 3:
		var buttons: Array[Rect2] = [Rect2(), Rect2(), Rect2()]
		buttons[slot] = Rect2(at - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
		_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, buttons)
		assert_bool(_anchor.in_field).override_failure_message("slot %d" % slot).is_false()
	var apart: Array[Rect2] = [Rect2(at + Vector2(200.0, 0.0), Vector2(40.0, 40.0))]
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, apart)
	assert_bool(_anchor.in_field).is_true()  # A hidden button is no rect: nothing is passed.


func test_a_button_edge_has_a_band_of_8_dp_with_hysteresis_both_ways() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	var at: Vector2 = _anchor.point
	var band: float = GuideUnitAnchor.THROUGH_BAND_DP
	# `gap` is how far the button's left edge stands to the right of the point (negative: the
	# point is inside the rect).
	var steps: Array = [
		[band - 1.0, true],  # Outside the plain rect, never under: in the field.
		[-1.0, false],  # Enters the plain rect.
		[band - 1.0, false],  # Inside the band: still under, no flip.
		[band + 1.0, true],  # Past the band: clear.
		[band - 1.0, true],  # Back inside the band: still clear, no flip.
		[-1.0, false],
	]
	for step: Array in steps:
		var gap: float = step[0] as float
		var rects: Array[Rect2] = [Rect2(at + Vector2(gap, -20.0), Vector2(40.0, 40.0))]
		_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, rects)
		assert_bool(_anchor.in_field).override_failure_message("gap %s" % gap).is_equal(step[1])
	var dp: float = 3.0  # The band grows with dp.
	var wide: Array[Rect2] = [Rect2(at + Vector2(-1.0, -20.0), Vector2(40.0, 40.0))]
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, dp, _hud, wide)
	wide[0] = Rect2(at + Vector2(band * dp - 1.0, -20.0), Vector2(40.0, 40.0))
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, dp, _hud, wide)
	assert_bool(_anchor.in_field).is_false()
	wide[0] = Rect2(at + Vector2(band * dp + 1.0, -20.0), Vector2(40.0, 40.0))
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, dp, _hud, wide)
	assert_bool(_anchor.in_field).is_true()


func test_the_band_state_is_dropped_when_the_unit_is_lost_or_changes() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	var at: Vector2 = _anchor.point
	var band: float = GuideUnitAnchor.THROUGH_BAND_DP
	var under: Array[Rect2] = [Rect2(at - Vector2(20.0, 20.0), Vector2(40.0, 40.0))]
	var near: Array[Rect2] = [Rect2(at + Vector2(band - 1.0, -20.0), Vector2(40.0, 40.0))]
	# No unit (a missing layer): the state is dropped, so a point in the band starts clear.
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, under)
	assert_bool(_anchor.in_field).is_false()
	_anchor.update(aim, _runner, _camera, null, _air, SAFE, 1.0, _hud, under)
	assert_int(_anchor.unit_id).is_equal(-1)
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, near)
	assert_bool(_anchor.in_field).is_true()
	# A unit that is no longer a candidate: the next pick starts clear as well.
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, under)
	assert_bool(_anchor.in_field).is_false()
	# The held unit stops fitting (the selector now names the enemy side): the rescan's pick starts
	# clear of a button although it stands in the band of one.
	var other: GuideUnitAnchor = GuideUnitAnchor.new()
	var foe: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.ENEMY, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_look_at(35)
	_tick()
	other.update(foe, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, NO_BUTTONS)
	assert_bool(other.in_field).is_true()
	var beside: Array[Rect2] = [
		Rect2(other.point + Vector2(band - 1.0, -20.0), Vector2(40.0, 40.0))
	]
	aim.unit.side = TutorialUnitPickDef.Whose.ENEMY  # The same step, so the rescan path runs.
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud, beside)
	assert_int(_anchor.unit_id).is_equal(other.unit_id)
	assert_bool(_anchor.in_field).is_true()
