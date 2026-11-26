extends "res://tests/ui/tutorial/support/unit_anchor_suite.gd"
## `GuideUnitAnchor`'s ring size, field, flyer and missing-layer cases (plan P593b-1, ADR 0048
## section 13.3 to 13.5); the set-up is `unit_anchor_suite.gd`.


func test_a_missing_layer_means_no_unit() -> void:
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST
	)
	_anchor.update(aim, _runner, _camera, null, _air, SAFE, 1.0, _hud)
	assert_int(_anchor.unit_id).is_equal(-1)
	_anchor.update(aim, _runner, _camera, _ground, null, SAFE, 1.0, _hud)
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
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud)
	assert_float(_anchor.half).is_equal_approx(maxf(art * 2.0, 24.0), 0.001)
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 100.0, _hud)
	assert_float(_anchor.half).is_equal(2400.0)  # The 24 dp floor at dp 100.
	snap.type_selection_radius[type] = 5000  # A large ring.
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud)
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
	_anchor.update(aim, _runner, _camera, _ground, _air, small, 1.0, _hud)
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
	_anchor.update(aim, runner, _camera, ground, air, SAFE, 1.0, _hud)
	assert_int(_anchor.unit_id).is_equal(Air.FIGHTER_ID)
	assert_bool(_anchor.flyer).is_true()
	assert_that(_anchor.point).is_equal_approx(
		_camera.world_to_screen(air.tap_point(Air.FIGHTER_ID)), Vector2(0.01, 0.01)
	)
	assert_that(ground.tap_point(Air.FIGHTER_ID)).is_equal(Vector2.INF)
