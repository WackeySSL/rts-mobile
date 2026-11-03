extends "res://tests/view/support/squad_pose_suite.gd"
## The squad poses across the rows and the clock (plan P142): the walk table through a death and a
## birth in one published tick, a WORKER resume inside a tick, the half-step edge, a squad that
## becomes idle off view and one that stands up mid-tick. The fixture is in
## support/squad_pose_suite.gd.


func test_a_squad_that_stands_up_mid_tick_counts_from_the_start_of_the_tick() -> void:
	var row: int = _row(RIFLE)
	_walk(row, 3, SPEED, 0)
	_still(row, FIRST_TICK + 3, 0.6)  # The first standing frame comes 60 % into tick 33.
	assert_float((_rig(row) as UnitLayer.Rig).idle.still_ms).is_equal(
		LifeClock.tick_ms(FIRST_TICK + 3)
	)


func test_a_resume_inside_a_tick_does_not_step_the_walk_back() -> void:
	var row: int = _row(RIFLE)
	_walk(row, 5, SPEED, 0)
	var tick: int = _runner.snapshot.tick
	Rig.at(_runner, tick, 0.75)
	_layer._process(0.0)
	var shown: Vector2i = _shown(row)
	Rig.at(_runner, tick, 0.0)  # WORKER mode restarts alpha at 0 after a pause, in the same tick.
	_layer._process(0.0)
	assert_vector(_shown(row)).is_equal(shown)
	Rig.at(_runner, tick, 0.25)
	_layer._process(0.0)
	assert_vector(_shown(row)).is_equal(shown)
	# And the next tick goes on from the whole step, as if nothing had happened.
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_x[row] = snap.pos_x[row]
	snap.pos_x[row] += SPEED
	Rig.at(_runner, tick + 1, 0.0)
	_layer._process(0.0)
	var phase: int = LifeClock.pick(RIFLE, 0, STRIDE)
	assert_int(_shown(row).y).is_equal((5 * SPEED + phase) / QUARTER % 4)


func test_a_step_of_exactly_half_a_step_walks() -> void:
	var row: int = _row(RIFLE)
	var snap: MatchSnapshot = _runner.snapshot
	snap.type_speed[snap.type_index[row]] = 68  # 4 * 34 squared is 68 squared, to the unit.
	_walk(row, 2, 34, 0)
	assert_int(_shown(row).x).is_equal(RigLife.POSE_WALK)
	_walk(row, 2, 33, 0, 5)  # One milli under it.
	assert_int(_shown(row).x).is_equal(RigLife.POSE_HULL)


func test_a_squad_that_becomes_idle_off_view_shows_its_window_when_the_camera_comes_back() -> void:
	var row: int = _row(RIFLE)
	var at: Vector2 = _rig(row).position
	_camera.position = Vector2(FAR, FAR)
	for ms: int in range(5, 9000, 500):  # Standing since 0, its first window passes unseen.
		_at_ms(float(ms) + 0.5)
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))
	_camera.position = at
	_at_ms(float(WINDOWS[3]) + 100.5)  # The second window, which began while it was off view.
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_IDLE, WINDOWS[5]))
	_at_ms(float(WINDOWS[4]) + 100.5)  # And the hull again after it.
	assert_vector(_shown(row)).is_equal(Vector2i(RigLife.POSE_HULL, 0))


func test_the_walk_table_follows_the_rows_through_a_death_and_a_birth() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var rifle_type: int = snap.type_index[_row(RIFLE)]
	var rocket_type: int = snap.type_index[_row(ROCKET)]
	var stride: int = _layer.world_sort.sheet(snap.type_ids[rocket_type]).stride_milli
	var phase: int = LifeClock.pick(ROCKET, 0, stride)
	CommandQueue.submit(Command.move(1, PackedInt32Array([RIFLE, ROCKET]), 30000, 10500))
	var total: int = 0  # The ground ROCKET covered in the ticks before this one, summed plainly.
	var wrong: Array[String] = []
	var born: int = 0
	for tick: int in 14:
		if tick == 7:  # In one published tick RIFLE (row 0) dies and a squad is born.
			_runner.world.hp[_runner.world.unit_id.find(RIFLE)] = 0
			born = _runner.world.add_unit(1, rifle_type, 5500, 5500)
		_runner.run_ticks(1)
		snap = _runner.snapshot
		var row: int = _row(ROCKET)
		var speed: int = snap.type_speed[rocket_type]
		var dx: int = snap.pos_x[row] - snap.prev_pos_x[row]
		var dy: int = snap.pos_y[row] - snap.prev_pos_y[row]
		var walking: bool = dx * dx + dy * dy > 0 and 4 * (dx * dx + dy * dy) >= speed * speed
		var step: int = FixedMath.isqrt(dx * dx + dy * dy) if walking else 0
		for part: int in SAMPLES:
			var alpha: float = float(part) / SAMPLES
			Rig.at(_runner, snap.tick, alpha)
			_layer._process(0.0)
			var want: Vector2i = Vector2i(RigLife.POSE_HULL, 0)
			if walking:
				want = Vector2i(
					RigLife.POSE_WALK, (total + int(alpha * step) + phase) / QUARTER % 4
				)
			if _shown(row) != want:
				wrong.append("tick %d row %d: %s, wanted %s" % [snap.tick, row, _shown(row), want])
		total += step
	assert_array(wrong).is_empty()
	assert_int(_row(ROCKET)).is_equal(0)  # It moved up a row when RIFLE died.
	assert_int(total).is_greater(500)  # It did walk, on both sides of the death.
	# The newborn starts from nothing, with a phase of its own, and the table has a row for each.
	_layer.sync_rows()
	var walk: PackedInt32Array = _layer._walk
	var newborn: int = _row(born)
	assert_int(walk.size()).is_equal(snap.unit_count() * RigLife.WALK_INTS)
	var at: int = newborn * RigLife.WALK_INTS
	assert_array(walk.slice(at, at + RigLife.WALK_INTS)).is_equal(
		[0, 0, snap.tick, LifeClock.pick(born, 0, stride), 0]
	)
