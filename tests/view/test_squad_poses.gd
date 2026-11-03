extends "res://tests/view/support/squad_pose_suite.gd"
## The squads' walk cycle and idle poses (plan P142, ADR 0027 sections 3 to 5): a squad that moved
## at least half a step in the last tick shows the `walk` frame `floor((travel + phase) / quarter)
## mod 4` of the ground it covered on its Hull (travel is the straight-line length of each step,
## phase `mix(id, 0) mod stride`), so the feet follow the speed and stop with the squad; one that
## has stood `idle_after_ms` with no target shows an `idle` frame in one window of each cycle; else
## the standing hull. A change of pose writes the region and the offset (the anchors differ), a
## change of frame the region only, and only inside the view rect grown by a tile. The functions
## are in test_squad_pose_life.gd; this is the layer's use of them. The fixture is in
## support/squad_pose_suite.gd; rows, resumes and the clock are in test_squad_pose_rows.gd.


func test_a_squad_driven_a_tile_shows_the_walk_frame_of_the_ground_it_covered() -> void:
	var row: int = _row(RIFLE)
	var shown: Array[Vector2i] = _walk(row, 15, SPEED, 0)
	var phase: int = LifeClock.pick(RIFLE, 0, STRIDE)
	assert_array(shown).is_equal(_expected(15, SPEED, phase))
	# 14 ticks and three quarters of one are 988 milli: the frame changed once for every 88 of it.
	var changes: int = _changes(shown)
	assert_int(changes).is_equal((phase + 988) / QUARTER - phase / QUARTER)
	assert_int(changes).is_between(10, 12)  # 1000 milli over 88 per frame is 11.4.


func test_a_squad_twice_as_fast_changes_its_frame_twice_as_often() -> void:
	var slow: int = _changes(_walk(_row(RIFLE), 15, SPEED, 0))
	_restart(LifeSettings.new())
	var fast: Array[Vector2i] = _walk(_row(RIFLE), 15, 2 * SPEED, 0)
	var phase: int = LifeClock.pick(RIFLE, 0, STRIDE)
	assert_array(fast).is_equal(_expected(15, 2 * SPEED, phase))
	assert_int(_changes(fast)).is_between(2 * slow - 1, 2 * slow + 1)


func test_a_diagonal_step_covers_its_straight_line_length_not_the_sum_of_its_axes() -> void:
	# 47 across and 47 down is 66 milli, not 94: with |dx| + |dy| the feet would run 1.42 times too
	# fast (the cadence of P139's art is 2.8 cycles a second at this speed; the sum would say 4).
	var shown: Array[Vector2i] = _walk(_row(RIFLE), 15, 47, 47)
	var phase: int = LifeClock.pick(RIFLE, 0, STRIDE)
	assert_array(shown).is_equal(_expected(15, 66, phase))
	assert_array(shown).is_not_equal(_expected(15, 94, phase))  # The test can tell the two apart.
	assert_int(_changes(shown)).is_equal((phase + 66 * 14 + 49) / QUARTER - phase / QUARTER)


func test_a_squad_that_stops_shows_its_hull_in_the_next_frame_and_the_hulls_offset() -> void:
	var row: int = _row(RIFLE)
	_walk(row, 6, SPEED, 0)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)
	_still(row, FIRST_TICK + 6, 0.0)  # A tick with no step.
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
	assert_vector(_hull(row).offset).is_equal(_offset(row, &"hull"))


func test_a_step_of_under_half_a_step_is_no_walk_and_half_a_step_is() -> void:
	var row: int = _row(RIFLE)
	_walk(row, 3, 33, 0)  # Four times 33 squared is under 67 squared.
	assert_int(_shown(row).x).is_equal(RigLife.POSE_HULL)
	_walk(row, 3, 34, 0, 10)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)


func test_the_offset_goes_with_the_region_in_both_directions_for_both_factions() -> void:
	_layer.reveal_enemies = true  # The Lumen Accord squad is far off, in the fog.
	var base: int = 0
	for id: int in [RIFLE, ENEMY]:
		var row: int = _row(id)
		var snap: MatchSnapshot = _runner.snapshot
		var speed: int = snap.type_speed[snap.type_index[row]]
		_camera.position = _rig(row).position
		var sheet: IsoSheetDef = _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
		# The anchors of the poses are not the hull's: this is the 1 or 2 px the offset must follow.
		assert_vector(Vector2(sheet.origin(&"idle"))).is_not_equal(Vector2(sheet.origin(&"hull")))
		_walk(row, 2, speed, 0, base)
		assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"walk"))
		_still(row, FIRST_TICK + base + 2, 0.0)  # It stands, and idles in its first window.
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"hull"))
		var window: int = _first_window(id)
		_at_ms(float(window) + 100.5)
		assert_int(_shown(row).x).is_equal(RigLife.POSE_IDLE)
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"idle"))
		_at_ms(float(window) + 700.5)  # Past the window of 600 ms: the hull again.
		assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"hull"))
		base += 600
		_walk(row, 2, speed, 0, base)
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"walk"))
		_still(row, FIRST_TICK + base + 2, 0.0)
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"hull"))
		base += 600


func test_a_squad_idles_in_the_windows_of_its_id_after_standing_and_not_before() -> void:
	var row: int = _row(RIFLE)
	var wrong: Array[String] = []
	for ms: int in range(5, 17000, 10):
		var now: float = float(ms) + 0.5
		_at_ms(now)
		var want: Vector2i = Vector2i(RigLife.POSE_HULL, 0)
		for window: int in 3:
			if now > WINDOWS[3 * window] and now < WINDOWS[3 * window + 1]:
				want = Vector2i(RigLife.POSE_IDLE, WINDOWS[3 * window + 2])
		if _shown(row) != want:
			wrong.append("%d: %s, wanted %s" % [ms, _shown(row), want])
	assert_array(wrong).is_empty()


func test_a_squad_that_walked_stands_again_from_the_tick_it_stopped() -> void:
	var row: int = _row(RIFLE)
	_walk(row, 30, SPEED, 0)  # Ticks 30 to 59: match time 2000 to 4000 ms.
	_still(row, FIRST_TICK + 30, 0.0)
	var stood: float = LifeClock.ms(_runner.snapshot, 0.0)
	assert_float((_rig(row) as UnitLayer.Rig).idle.still_ms).is_equal_approx(stood, 0.001)
	# Its first window is that of the id counted from here, and before it the hull shows.
	var from: float = stood + float(WINDOWS[0])
	_at_ms(from - 100.0)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_HULL)
	_at_ms(from + 100.5)
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_IDLE, WINDOWS[2]))


func test_a_squad_with_a_target_shows_its_hull_and_stands_again_when_it_lets_go() -> void:
	var row: int = _row(RIFLE)
	_runner.snapshot.target[row] = 99999
	for ms: int in range(5, 17000, 250):
		_at_ms(float(ms) + 0.5)
		assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
	_runner.snapshot.target[row] = 0
	_at_ms(17000.5)
	# It stands from the start of the tick that first saw it stand (tick 255 = 17000 ms), not from
	# the frame: the windows are the same on every device (ADR 0027 section 2).
	var stood: float = (_rig(row) as UnitLayer.Rig).idle.still_ms
	assert_float(stood).is_equal(LifeClock.tick_ms(255))
	_at_ms(stood + WINDOWS[0] + 100.0)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_IDLE)


func test_reduced_effects_keep_the_walk_and_the_idle_poses() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.reduced = true  # The ambient goes (ADR 0027 answer 3); walking and idling tell something.
	_restart(life)
	var row: int = _row(RIFLE)
	var phase: int = LifeClock.pick(RIFLE, 0, STRIDE)
	assert_array(_walk(row, 15, SPEED, 0)).is_equal(_expected(15, SPEED, phase))
	_still(row, FIRST_TICK + 15, 0.0)
	_at_ms(float(_first_window(RIFLE)) + 100.5)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_IDLE)


func test_a_squad_just_inside_the_grown_view_rect_walks_and_one_just_outside_is_left_alone(
) -> void:
	_restart(Rig.calmed(null))  # The tank in view would write too.
	var row: int = _row(RIFLE)
	var at: Vector2 = _rig(row).position
	var margin: float = UnitLayer.IDLE_MARGIN_PX
	var half: float = _camera.visible_world_rect().size.x * 0.5
	# The squad's left, 12 px inside the grown rect (it drives right, deeper in).
	_camera.position = at + Vector2(half + margin - 12.0, 0.0)
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(at)).is_true()
	_walk(row, 2, SPEED, 0)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)
	_restart(Rig.calmed(null))
	row = _row(RIFLE)
	_camera.position = at + Vector2(half + margin + 12.0, 0.0)  # 12 px outside it.
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(at)).is_false()
	var writes: int = _layer.life_writes()
	_walk(row, 2, SPEED, 0)
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
	assert_int(_layer.life_writes()).is_equal(writes)  # Not written at all.
	_camera.position = at + Vector2(half + margin - 12.0, 0.0)  # The camera comes back.
	_walk(row, 1, SPEED, 0, 2)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)


func test_a_hidden_enemy_squad_keeps_its_hull_and_shows_its_walk_when_seen() -> void:
	var row: int = _row(ENEMY)
	_camera.position = _rig(row).position
	assert_bool(_layer.is_shown(row)).is_false()
	var speed: int = _runner.snapshot.type_speed[_runner.snapshot.type_index[row]]
	_walk(row, 3, speed, 0)
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
	Buildings.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	assert_bool(_layer.is_shown(row)).is_true()
	_walk(row, 1, speed, 0, 3)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)


func test_a_vehicle_never_takes_a_pose() -> void:
	var row: int = _row(TANK)
	_camera.position = _rig(row).position
	var hull: Sprite2D = _hull(row)
	var offset: Vector2 = hull.offset
	var region: Rect2 = hull.region_rect
	_walk(row, 15, 80, 0)
	_at_ms(9000.5)
	assert_vector(hull.offset).is_equal(offset)
	assert_that(hull.region_rect).is_equal(region)
	assert_int((_rig(row) as UnitLayer.Rig).pose.quarter).is_equal(0)


func test_the_walk_keeps_its_frame_and_pose_when_the_squad_turns() -> void:
	var row: int = _row(RIFLE)
	_walk(row, 3, SPEED, 0)
	# Now it drives south: one frame with time to turn (delta 1 s) in the next tick.
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_x[row] = snap.pos_x[row]
	snap.prev_pos_y[row] = snap.pos_y[row]
	snap.pos_y[row] += SPEED
	snap.tick += 1
	_layer._process(1.0)
	var pose: RigLife.Pose = (_rig(row) as UnitLayer.Rig).pose
	assert_int(pose.shown).is_equal(RigLife.POSE_WALK)
	assert_vector(_shown(row, UnitLayer.D_EAST)).is_equal(Vector2i(-1, -1))  # Not facing east now.
	assert_vector(_shown(row, 10)).is_equal(Vector2i(RigLife.POSE_WALK, pose.frame))
	assert_vector(_hull(row).offset).is_equal(_offset(row, &"walk"))


func test_a_new_match_dresses_a_pooled_squad_rig_in_its_hull() -> void:
	var walker: Node2D = _rig(_row(RIFLE))
	_walk(_row(RIFLE), 3, SPEED, 0)
	assert_int(_shown(_row(RIFLE)).x).is_equal(RigLife.POSE_WALK)
	_runner.start()  # The rigs go to the pool and the new match's squads take them.
	_layer._process(0.0)
	var taken: Array[Node2D] = []
	for id: int in [RIFLE, ROCKET, ENEMY]:
		var row: int = _row(id)
		taken.append(_rig(row))
		var pose: RigLife.Pose = (_rig(row) as UnitLayer.Rig).pose
		assert_int(pose.shown).is_equal(RigLife.POSE_HULL)
		assert_int(pose.quarter).is_greater(0)
		assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
		assert_vector(_hull(row).offset).is_equal(_offset(row, &"hull"))
		assert_float((_rig(row) as UnitLayer.Rig).idle.still_ms).is_equal_approx(0.0, 0.01)
	assert_bool(taken.has(walker)).is_true()  # The walking rig was one of them.


func test_two_runs_of_the_same_play_show_the_same_frames_offsets_and_writes() -> void:
	var first: Array = _play()
	var writes: int = _layer.life_writes()
	_restart(LifeSettings.new())
	assert_array(_play()).is_equal(first)
	assert_int(_layer.life_writes()).is_equal(writes)
	assert_int(writes).is_greater(10)


func test_a_walk_writes_once_per_frame_change_and_builds_no_string_key_after_the_first() -> void:
	var calm: LifeSettings = Rig.calmed(null)  # Without the shake of the tank in view.
	calm.idle_ms = 600  # But with the squad's idle windows.
	_restart(calm)
	var row: int = _row(RIFLE)
	var before: int = _layer.life_writes()
	var shown: Array[Vector2i] = _walk(row, 15, SPEED, 0)
	# One write for the pose (the region and the offset together), one for each frame after it.
	assert_int(_layer.life_writes() - before).is_equal(1 + _changes(shown))
	assert_int(_layer.life_writes() - before).is_less_equal(13)  # About 11 in a second at a tile/s.
	var keys: int = IsoAtlas.keys_built()
	_walk(row, 15, SPEED, 0, 15, false)  # A second second of walking in the same direction.
	assert_int(IsoAtlas.keys_built()).is_equal(keys)
	# Walk -> hull -> idle -> hull -> walk again: every change of pose is a table read.
	_still(row, FIRST_TICK + 30, 0.0)
	var window: int = _first_window(RIFLE)
	_at_ms(float(window) + 100.5)
	assert_int((_rig(row) as UnitLayer.Rig).pose.shown).is_equal(RigLife.POSE_IDLE)
	_at_ms(float(window) + 700.5)
	assert_int((_rig(row) as UnitLayer.Rig).pose.shown).is_equal(RigLife.POSE_HULL)
	_walk(row, 15, SPEED, 0, ceili(float(window) * 0.015) + 5 - FIRST_TICK, false)
	assert_int((_rig(row) as UnitLayer.Rig).pose.shown).is_equal(RigLife.POSE_WALK)
	assert_int(IsoAtlas.keys_built()).is_equal(keys)


func test_walking_and_idling_leave_no_object_or_node_behind() -> void:
	var row: int = _row(RIFLE)
	var tick: int = 0
	for round_no: int in 4:  # Warm up: the first frames may make the engine's own objects.
		tick = _cycle(row, tick)
	var objects: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var writes: int = _layer.life_writes()
	for round_no: int in 20:
		tick = _cycle(row, tick)
	var objects_after: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes_after: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	assert_int(_layer.life_writes()).is_greater(writes)
	assert_int(objects_after).is_equal(objects)
	assert_int(nodes_after).is_equal(nodes)
