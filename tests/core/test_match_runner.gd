extends GdUnitTestSuite
## MatchRunner (ADR 0003 section 7). The scenario is built here with literal stats: three tanks
## of player 1 at (2500, 2500), (4000, 2500) and (5500, 2500) on a 20x20 map, speed 120
## milli-tiles per tick. Unit 1 given a goal on its row moves 120 per tick.

var _runner: MatchRunner


func before_test() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _scenario()
	_runner.start()


func after_test() -> void:
	CommandQueue.clear()


func test_start_builds_the_world_and_clears_the_queue() -> void:
	CommandQueue.submit(_move(12500))
	_runner.run_ticks(2)
	CommandQueue.submit(_move(12500))
	_runner.start()
	assert_int(CommandQueue.pending()).is_equal(0)
	assert_int(_runner.world.tick).is_equal(0)
	assert_int(_runner.world.unit_count()).is_equal(3)
	assert_array(_runner.prev_pos_x).is_equal(PackedInt32Array([2500, 4000, 5500]))
	assert_array(_runner.prev_pos_y).is_equal(PackedInt32Array([2500, 2500, 2500]))
	assert_float(_runner.alpha()).is_equal(0.0)
	assert_int(_runner.max_catch_up_ticks).is_equal(4)


func test_ready_starts_the_match_only_when_a_scenario_is_set() -> void:
	var with_scenario: MatchRunner = auto_free(MatchRunner.new())
	with_scenario.scenario = _scenario()
	add_child(with_scenario)
	assert_int(with_scenario.world.unit_count()).is_equal(3)
	var without: MatchRunner = auto_free(MatchRunner.new())
	add_child(without)
	without.run_ticks(3)
	without._process(1.0)
	assert_object(without.world).is_null()


func test_run_ticks_advances_the_clock_and_emits_ticked_after_each_tick() -> void:
	var seen: Array[int] = []
	_runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	_runner.run_ticks(3)
	assert_array(seen).is_equal([1, 2, 3])
	_runner.run_ticks(12)
	_runner.run_ticks(-4)
	assert_int(_runner.world.tick).is_equal(15)
	assert_int(seen.size()).is_equal(15)


func test_commands_get_the_next_tick_and_an_increasing_sequence() -> void:
	_runner.run_ticks(5)
	var first: Command = _move(12500)
	var second: Command = _move(13500)
	# Values the submitter set are replaced.
	first.tick = 99
	first.sequence = 77
	CommandQueue.submit(first)
	CommandQueue.submit(second)
	_runner.run_ticks(1)
	assert_array([first.tick, second.tick]).is_equal([5, 5])
	assert_array([first.sequence, second.sequence]).is_equal([1, 2])
	# Both ran on tick 5, the later submission last, and nothing was dropped.
	assert_int(_runner.world.goal_x[0]).is_equal(13500)
	assert_int(_runner.world.order[0]).is_equal(World.Order.ATTACK_MOVE)
	_runner.run_ticks(2)
	var third: Command = _move(14500)
	CommandQueue.submit(third)
	_runner.run_ticks(1)
	assert_array([third.tick, third.sequence]).is_equal([8, 3])
	assert_int(_runner.world.goal_x[0]).is_equal(14500)
	assert_int(_runner.world.dropped_commands).is_equal(0)
	assert_int(CommandQueue.pending()).is_equal(0)


func test_prev_positions_hold_the_positions_before_the_last_tick() -> void:
	CommandQueue.submit(_move(12500))
	_runner.run_ticks(1)
	assert_array(_runner.prev_pos_x).is_equal(PackedInt32Array([2500, 4000, 5500]))
	assert_array(_runner.world.pos_x).is_equal(PackedInt32Array([2620, 4000, 5500]))
	_runner.run_ticks(1)
	assert_array(_runner.prev_pos_x).is_equal(PackedInt32Array([2620, 4000, 5500]))
	assert_array(_runner.world.pos_x).is_equal(PackedInt32Array([2740, 4000, 5500]))


func test_prev_arrays_keep_their_size_and_follow_a_unit_added_to_a_running_world() -> void:
	CommandQueue.submit(_move(12500))
	for _t: int in 10:
		_runner.run_ticks(1)
		assert_array([_runner.prev_pos_x.size(), _runner.prev_pos_y.size()]).is_equal([3, 3])
	_runner.world.add_unit(1, 0, 7000, 8000)
	_runner.run_ticks(1)
	assert_array([_runner.prev_pos_x.size(), _runner.prev_pos_y.size()]).is_equal([4, 4])
	assert_array([_runner.prev_pos_x[3], _runner.prev_pos_y[3]]).is_equal([7000, 8000])


func test_alpha_is_the_part_of_the_next_tick_that_has_passed() -> void:
	_runner._process(0.05)
	assert_int(_runner.world.tick).is_equal(0)
	assert_float(_runner.alpha()).is_equal_approx(0.75, 0.0001)
	_runner._process(0.05)
	assert_int(_runner.world.tick).is_equal(1)
	assert_float(_runner.alpha()).is_equal_approx(0.5, 0.0001)
	_runner._process(-1.0)
	assert_int(_runner.world.tick).is_equal(1)
	assert_float(_runner.alpha()).is_equal_approx(0.5, 0.0001)
	# Whole ticks add up exactly: 1/60 s is a quarter tick.
	_runner._process(1.0 / 60.0)
	_runner._process(1.0 / 60.0)
	assert_int(_runner.world.tick).is_equal(2)
	assert_float(_runner.alpha()).is_equal_approx(0.0, 0.0001)


func test_alpha_stays_between_zero_and_one_for_any_frame_length() -> void:
	for delta: float in [0.0, 0.001, 0.0167, 0.2, 0.5, 3.0, 0.033, 0.0667, 100.0, 0.016]:
		_runner._process(delta)
		assert_float(_runner.alpha()).is_between(0.0, 1.0)


func test_a_long_frame_plays_at_most_four_ticks_and_drops_the_backlog() -> void:
	_runner._process(1.0)
	assert_int(_runner.world.tick).is_equal(4)
	assert_float(_runner.alpha()).is_equal(0.0)
	# The 11 dropped ticks are not paid back later.
	_runner._process(0.0)
	assert_int(_runner.world.tick).is_equal(4)
	_runner._process(1.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(5)


func test_the_catch_up_cap_is_the_exported_value_and_a_part_tick_survives_the_drop() -> void:
	_runner.max_catch_up_ticks = 2
	# 6.5 ticks: two are played, four are dropped and the half tick stays on the clock.
	_runner._process(6.5 / 15.0)
	assert_int(_runner.world.tick).is_equal(2)
	assert_float(_runner.alpha()).is_equal_approx(0.5, 0.0001)
	# A cap below one would freeze the match, so it plays one tick.
	_runner.max_catch_up_ticks = 0
	_runner._process(3.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(3)


func test_paused_stops_the_clock_and_accumulates_nothing() -> void:
	_runner.paused = true
	_runner._process(1.0)
	assert_int(_runner.world.tick).is_equal(0)
	# run_ticks is the synchronous driver, so pause does not stop it.
	_runner.run_ticks(2)
	assert_int(_runner.world.tick).is_equal(2)
	_runner.paused = false
	_runner._process(1.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(3)


func test_an_application_pause_stops_the_clock_until_the_application_resumes() -> void:
	_runner.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_runner._process(1.0)
	assert_int(_runner.world.tick).is_equal(0)
	_runner.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_runner._process(1.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(1)
	# The application pause is not the `paused` flag.
	_runner.paused = true
	_runner.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_runner.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_runner._process(1.0)
	assert_int(_runner.world.tick).is_equal(1)


func _move(target_x: int) -> Command:
	return Command.attack_move(1, PackedInt32Array([1]), target_x, 2500)


func _scenario() -> ScenarioDef:
	var tank: UnitDef = UnitDef.new()
	tank.speed = 120
	tank.radius = 400
	tank.formation_spacing = 1200
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = tank
	spawn.count = 3
	spawn.origin_tile = Vector2i(2, 2)
	spawn.columns = 3
	spawn.spacing = 1500
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(20, 20)
	scenario.spawns.append(spawn)
	return scenario
