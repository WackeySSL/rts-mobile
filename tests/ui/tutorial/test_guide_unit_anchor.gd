extends "res://tests/ui/tutorial/support/unit_anchor_suite.gd"
## `GuideUnitAnchor` (plan P593b-1, ADR 0048 sections 13.3 and 13.4) on controls_test:
## tanks 1-30 are the local player's (rows of 10, ids rising east), 31-40 the enemy's.
## The camera stands over a unit so the pick is exact. The resolver reads only the published
## snapshot, the camera and the layers' `tap_point`.


func test_nearest_camera_picks_the_closest_own_unit_by_integer_distance() -> void:
	_look_at(7)
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA))
	assert_int(_anchor.unit_id).is_equal(7)
	assert_bool(_anchor.point != Vector2.INF).is_true()
	assert_float(_anchor.half).is_greater_equal(24.0)


func test_newest_picks_the_highest_id_of_the_side() -> void:
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST))
	assert_int(_anchor.unit_id).is_equal(30)
	_update(_aim(TutorialUnitPickDef.Whose.ENEMY, TutorialUnitPickDef.Pick.NEWEST))
	assert_int(_anchor.unit_id).is_equal(40)


func test_a_tie_goes_to_the_lower_id() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.pos_x[11] = snap.pos_x[10]  # Units 12 and 11 stand on one point.
	snap.pos_y[11] = snap.pos_y[10]
	_look_at(11)
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA))
	assert_int(_anchor.unit_id).is_equal(11)


func test_the_type_and_side_filter_and_neutral_and_buildings_are_left_out() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[0]
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST
	)
	aim.unit.type_id = &"no_such_type"
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(-1)
	assert_that(_anchor.point).is_equal(Vector2.INF)
	aim = _aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST)
	aim.unit.type_id = StringName(snap.type_ids[type])
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(30)
	snap.owner[39] = 0  # Unit 40 turns neutral: the newest enemy is 39.
	aim = _aim(TutorialUnitPickDef.Whose.ENEMY, TutorialUnitPickDef.Pick.NEWEST)
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(39)
	snap.type_foot_w[type] = 2  # The tank's type counts as a building now: nothing is left.
	aim = _aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST)
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(-1)


func test_a_fogged_enemy_is_never_picked_and_a_seen_one_is() -> void:
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.ENEMY, TutorialUnitPickDef.Pick.NEWEST
	)
	Buildings.see(_runner.snapshot, 1, [])
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(-1)
	assert_that(_anchor.point).is_equal(Vector2.INF)
	_see_all()
	_tick()
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(40)


func test_the_pick_is_held_while_it_stays_a_candidate() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(7)
	_look_at(20)  # A pan to a nearer unit does not move the pick.
	_tick()
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(7)


func test_the_hold_is_dropped_on_the_frame_the_unit_dies_or_is_fogged() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(7)
	_runner.world.hp[6] = 0
	_tick()
	_update(aim)  # The same frame: a new unit, never the dead one.
	assert_int(_anchor.unit_id).is_not_equal(7)
	assert_int(_anchor.unit_id).is_not_equal(-1)
	var enemy: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.ENEMY, TutorialUnitPickDef.Pick.NEWEST
	)
	_update(enemy)
	assert_int(_anchor.unit_id).is_equal(40)
	Buildings.see(_runner.snapshot, 1, [])
	_tick()
	Buildings.see(_runner.snapshot, 1, [])
	_update(enemy)
	assert_int(_anchor.unit_id).is_equal(-1)


func test_a_new_step_and_a_new_match_pick_again() -> void:
	_look_at(7)
	var first: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(first)
	_look_at(20)
	var second: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(second)  # Another step on the same snapshot: scanned now.
	assert_int(_anchor.unit_id).is_equal(20)
	_runner.snapshot.match_serial += 1
	_look_at(3)
	_update(second)
	assert_int(_anchor.unit_id).is_equal(3)


func test_it_scans_once_per_snapshot_and_once_on_a_new_step() -> void:
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	_update(aim)
	_update(aim)
	assert_int(_anchor.scans).is_equal(1)
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST))
	assert_int(_anchor.scans).is_equal(2)  # The new step on the same snapshot.
	_update(aim)
	assert_int(_anchor.scans).is_equal(3)
	_tick()
	_update(aim)  # A held unit that still fits: no scan on a new tick.
	_update(aim)
	assert_int(_anchor.scans).is_equal(3)
	var none: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST
	)
	none.unit.type_id = &"no_such_type"
	_update(none)
	var before: int = _anchor.scans
	_update(none)  # With none found the next scan waits for the next snapshot.
	assert_int(_anchor.scans).is_equal(before)
	_tick()
	_update(none)
	assert_int(_anchor.scans).is_equal(before + 1)


func test_it_still_resolves_with_an_empty_world() -> void:
	_runner.world = World.new()
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST))
	assert_int(_anchor.unit_id).is_equal(30)
	assert_bool(_anchor.point != Vector2.INF).is_true()


func test_in_field_is_false_under_a_hud_part_but_not_under_the_economy_card() -> void:
	_look_at(7)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	assert_bool(_anchor.in_field).is_true()
	var at: Vector2 = _anchor.point
	_hud[HudCorners.CARD] = Rect2(at - Vector2(5.0, 5.0), Vector2(10.0, 10.0))
	_update(aim)
	assert_bool(_anchor.in_field).is_true()
	_hud[HudCorners.BAR] = Rect2(at - Vector2(5.0, 5.0), Vector2(10.0, 10.0))
	_update(aim)
	assert_bool(_anchor.in_field).is_false()
	assert_that(_anchor.point).is_equal(at)  # Still has a point: it gets the edge pin.
	_hud.clear()
	_camera.position += Vector2(5000.0, 0.0)
	_update(aim)
	assert_bool(_anchor.in_field).is_false()


func test_a_moving_target_smoke_no_new_objects_over_sixty_frames() -> void:
	_hud[HudCorners.BUILD] = Rect2(1000.0, 600.0, 100.0, 80.0)  # The rect loop runs.
	_hud[HudCorners.PILL] = Rect2(10.0, 10.0, 200.0, 50.0)
	_hud[HudCorners.BAR] = Rect2(10.0, 640.0, 300.0, 60.0)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	for warm: int in 4:  # The first frames fill the layers' caches.
		_ground._process(0.016)
		_update(aim)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var memory: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	for frame: int in 60:  # The camera moves every frame, so the point does too.
		_camera.position += Vector2(1.0, 0.5)
		_update(aim)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)
	# MEMORY_STATIC is noisy (the engine itself moves it by a few KB), so it only bounds the growth.
	var grown: float = Performance.get_monitor(Performance.MEMORY_STATIC) - memory
	assert_float(grown).is_less(32768.0)


func test_a_row_shift_keeps_the_hold_and_the_row_is_reused_while_rows_version_holds() -> void:
	_look_at(20)
	var aim: TutorialLeadInDef = _aim(
		TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA
	)
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(20)
	var looks: int = _anchor.lookups
	_tick()
	_update(aim)  # Rows did not move: the held row is reused, no index_of.
	assert_int(_anchor.lookups).is_equal(looks)
	_runner.world.hp[6] = 0  # Unit 7 dies: unit 20 moves up a row.
	_tick()
	_update(aim)
	assert_int(_anchor.unit_id).is_equal(20)
	assert_int(_anchor.lookups).is_equal(looks + 1)
	assert_that(_anchor.point).is_equal_approx(
		_camera.world_to_screen(_ground.tap_point(20)), Vector2(0.01, 0.01)
	)
	_tick()
	_update(aim)
	assert_int(_anchor.lookups).is_equal(looks + 1)  # The new row is reused in turn.


func test_a_nearest_pick_off_axis_follows_the_integer_distances() -> void:
	_look_at(7)
	_camera.position += Vector2(37.0, -53.0)  # Between rows and columns, on no unit.
	var snap: MatchSnapshot = _runner.snapshot
	var centre: Vector2i = IsoProjection.px_to_ground(_camera.position)
	var best: int = -1
	var best_gap: int = 0
	for row: int in 30:  # The player's tanks, ascending ids.
		var dx: int = snap.pos_x[row] - centre.x
		var dy: int = snap.pos_y[row] - centre.y
		if best < 0 or dx * dx + dy * dy < best_gap:
			best = row
			best_gap = dx * dx + dy * dy
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEAREST_CAMERA))
	assert_int(_anchor.unit_id).is_equal(snap.unit_id[best])


func test_an_own_unit_on_a_fogged_cell_is_still_picked() -> void:
	Buildings.see(_runner.snapshot, 1, [])
	_update(_aim(TutorialUnitPickDef.Whose.OWN, TutorialUnitPickDef.Pick.NEWEST))
	assert_int(_anchor.unit_id).is_equal(30)
	assert_bool(_anchor.point != Vector2.INF).is_true()
