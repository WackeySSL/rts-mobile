extends GdUnitTestSuite
## MatchRunner (ADR 0003 section 7; v1 on MatchLoop, ADR 0007 sections 6 and 9, plan P38). The
## scenario is built here with literal stats: three tanks of player 1 at (2500, 2500),
## (4000, 2500) and (5500, 2500) on a 20x20 map, speed 120 milli-tiles per tick. Unit 1 given a
## goal on its row moves 120 per tick. The v1 cases also run the data scenarios: controls_test
## (no jitter, no orders) and the perf arena (150 units, jitter 300, one order per player at
## tick 0).

const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## Frame lengths in seconds for the jittered run, used in turn: below a tick (1/15 s), a few far
## above it (3 ticks, and 7.5 ticks, of which the cap of 4 drops 3), and a zero frame.
const JITTER: Array[float] = [0.016, 0.0333, 0.004, 0.061, 0.0167, 0.2, 0.025, 0.0, 0.5, 0.0083]

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
	# A part tick on the clock, which start() must clear.
	_runner._process(0.05)
	CommandQueue.submit(_move(12500))
	_runner.start()
	assert_int(CommandQueue.pending()).is_equal(0)
	assert_int(_runner.world.tick).is_equal(0)
	assert_int(_runner.world.unit_count()).is_equal(3)
	assert_array(_runner.prev_pos_x).is_equal(PackedInt32Array([2500, 4000, 5500]))
	assert_array(_runner.prev_pos_y).is_equal(PackedInt32Array([2500, 2500, 2500]))
	assert_float(_runner.alpha()).is_equal(0.0)
	assert_int(_runner.max_catch_up_ticks).is_equal(4)
	# Sequence numbers start over with the match, at 0 (MatchLoop's first).
	var again: Command = _move(12500)
	CommandQueue.submit(again)
	_runner.run_ticks(1)
	assert_int(again.sequence).is_equal(0)


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
	assert_array([first.sequence, second.sequence]).is_equal([0, 1])
	# Both ran on tick 5, the later submission last, and nothing was dropped.
	assert_int(_runner.world.goal_x[0]).is_equal(13500)
	assert_int(_runner.world.order[0]).is_equal(World.Order.ATTACK_MOVE)
	_runner.run_ticks(2)
	var third: Command = _move(14500)
	CommandQueue.submit(third)
	_runner.run_ticks(1)
	assert_array([third.tick, third.sequence]).is_equal([8, 2])
	assert_int(_runner.world.goal_x[0]).is_equal(14500)
	assert_int(_runner.world.dropped_commands).is_equal(0)
	assert_int(CommandQueue.pending()).is_equal(0)


func test_process_stamps_commands_emits_ticked_and_keeps_prev_positions_on_both_axes() -> void:
	var seen: Array[int] = []
	_runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	var command: Command = Command.attack_move(1, PackedInt32Array([1]), 12500, 4500)
	CommandQueue.submit(command)
	_runner._process(1.0 / 15.0)
	assert_array([command.tick, command.sequence]).is_equal([0, 0])
	assert_array(_runner.prev_pos_x).is_equal(PackedInt32Array([2500, 4000, 5500]))
	assert_array(_runner.prev_pos_y).is_equal(PackedInt32Array([2500, 2500, 2500]))
	var x1: int = _runner.world.pos_x[0]
	var y1: int = _runner.world.pos_y[0]
	_runner._process(1.0 / 15.0)
	assert_array(seen).is_equal([1, 2])
	assert_array([_runner.prev_pos_x[0], _runner.prev_pos_y[0]]).is_equal([x1, y1])
	assert_int(_runner.world.pos_y[0]).is_greater(y1)


func test_prev_arrays_keep_their_size_and_follow_a_unit_added_to_a_running_world() -> void:
	CommandQueue.submit(_move(12500))
	var x_before: PackedInt32Array = _runner.prev_pos_x
	var y_before: PackedInt32Array = _runner.prev_pos_y
	for _t: int in 10:
		_runner.run_ticks(1)
		assert_array([_runner.prev_pos_x.size(), _runner.prev_pos_y.size()]).is_equal([3, 3])
	# Written in place: a duplicate() per tick would hand out new arrays.
	assert_bool(is_same(x_before, _runner.prev_pos_x)).is_true()
	assert_bool(is_same(y_before, _runner.prev_pos_y)).is_true()
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
	# A listener that pauses in the middle of a long frame stops the rest of that frame.
	_runner.ticked.connect(func(_tick: int) -> void: _runner.paused = true)
	_runner._process(3.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(4)


func test_an_application_pause_stops_the_clock_until_the_application_resumes() -> void:
	_runner.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_runner._process(1.0)
	assert_int(_runner.world.tick).is_equal(0)
	# run_ticks ignores this pause too.
	_runner.run_ticks(1)
	assert_int(_runner.world.tick).is_equal(1)
	_runner.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_runner._process(1.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(2)
	# The application pause is not the `paused` flag, and neither sticks to the other.
	_runner.paused = true
	_runner.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_runner.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_runner._process(1.0)
	assert_int(_runner.world.tick).is_equal(2)
	_runner.paused = false
	_runner._process(1.0 / 15.0)
	assert_int(_runner.world.tick).is_equal(3)


## start() makes the sim stream through DetRng from match_seed (controls_test has no jitter, so
## the setup draws nothing and the stream is still fresh) and a MatchLoop, whose replay is the
## runner's and records the scenario path, the seed and the defs hash. Every start(), the one
## _ready() makes too, counts in match_serial.
func test_start_seeds_the_world_from_match_seed_records_it_and_counts_the_match() -> void:
	var runner: MatchRunner = _data_runner(CONTROLS_PATH, 7)
	assert_array(runner.world.rng.state()).is_equal(_sim_stream(7).state())
	assert_bool(is_same(runner.replay, runner.loop.replay)).is_true()
	assert_str(runner.replay.scenario_path).is_equal(CONTROLS_PATH)
	assert_array([runner.replay.seed, runner.replay.defs_hash]).is_equal(
		[7, runner.world.defs_hash()]
	)
	(
		assert_array([runner.last_hash, runner.loop.next_sequence, runner.replay.commands.size()])
		. is_equal([0, 0, 0])
	)
	# A restart with another seed makes a new world, loop and replay from that seed.
	var old_loop: MatchLoop = runner.loop
	runner.match_seed = 9
	runner.start()
	assert_array(runner.world.rng.state()).is_equal(_sim_stream(9).state())
	assert_bool(is_same(runner.loop, old_loop)).is_false()
	assert_bool(is_same(runner.replay, runner.loop.replay)).is_true()
	assert_int(runner.replay.seed).is_equal(9)
	# The default seed is 1; a scenario built in code records an empty path.
	assert_int(_runner.match_seed).is_equal(1)
	assert_array(_runner.world.rng.state()).is_equal(_sim_stream(1).state())
	assert_str(_runner.replay.scenario_path).is_empty()
	assert_array([runner.match_serial, _runner.match_serial]).is_equal([2, 1])
	_runner.start()
	_runner.start()
	assert_int(_runner.match_serial).is_equal(3)
	var fresh: MatchRunner = auto_free(MatchRunner.new())
	assert_int(fresh.match_serial).is_equal(0)
	fresh.scenario = _scenario()
	add_child(fresh)
	assert_int(fresh.match_serial).is_equal(1)


## The runner's log replays: the arena with seed 7 (jittered spawns and the two scenario orders at
## tick 0), commands submitted before ticks 0, 4 and 20, played by run_ticks and by frames. A
## fresh world of the same scenario and seed plays it back with every checkpoint equal; one of
## another seed differs at the first checkpoint, so the seed in the log is the world's.
func test_the_replay_of_a_run_plays_back_on_a_fresh_world() -> void:
	var runner: MatchRunner = _data_runner(ARENA_PATH, 7)
	CommandQueue.submit(Command.move(1, PackedInt32Array([1, 2]), 30500, 20500))
	runner.run_ticks(4)
	CommandQueue.submit(Command.stop(2, PackedInt32Array([76])))
	CommandQueue.submit(Command.attack_move(2, PackedInt32Array([77]), 10500, 10500))
	for _frame: int in 64:
		runner._process(1.0 / 60.0)
	CommandQueue.submit(Command.move(1, PackedInt32Array([3]), 5500, 5500))
	runner.run_ticks(25)
	assert_int(runner.world.tick).is_equal(45)
	# Two scenario orders and four submitted commands.
	assert_int(runner.loop.next_sequence).is_equal(6)
	assert_array(runner.replay.checkpoint_ticks).is_equal([15, 30, 45])
	var fresh: World = _arena_world(7)
	assert_int(Replay.play(runner.replay, fresh, 45)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.state_hash()).is_equal(runner.world.state_hash())
	assert_int(Replay.play(runner.replay, _arena_world(8), 45)).is_equal(15)


## Every tick sets last_hash to the hash of the last checkpoint (0 until tick 15, then the state
## hash at 15 until tick 30 replaces it), last_tick_usec to Sim.step alone, the time the runner's
## StepProbe took from begin() to the last mark (so a checkpoint's hash is not in it), and
## last_runner_tick_usec to the whole tick, which is at least as long. start() sets all three
## back to 0.
func test_every_tick_sets_last_hash_and_the_tick_times() -> void:
	var runner: MatchRunner = _data_runner(CONTROLS_PATH, 1)
	CommandQueue.submit(Command.move(1, PackedInt32Array([1, 2, 3]), 20500, 20500))
	var expected: int = 0
	var hashes: Array[int] = []
	for tick: int in 31:
		if tick == 30:
			runner._process(1.0 / 15.0)
		else:
			runner.run_ticks(1)
		if runner.world.tick % 15 == 0:
			expected = runner.world.state_hash()
			hashes.append(expected)
		var label: String = str(runner.world.tick)
		assert_int(runner.last_hash).override_failure_message(label).is_equal(expected)
		assert_bool(runner.last_tick_usec > 0).override_failure_message(label).is_true()
		assert_int(runner.last_runner_tick_usec).is_greater_equal(runner.last_tick_usec)
		assert_int(runner.last_tick_usec).is_equal(runner._step_probe.step_usec)
	assert_array(runner.replay.checkpoint_hashes).is_equal(hashes)
	assert_bool(hashes.size() == 2 and hashes[0] != hashes[1]).is_true()
	runner.start()
	assert_array([runner.last_hash, runner.last_tick_usec, runner.last_runner_tick_usec]).is_equal(
		[0, 0, 0]
	)


## The StepProbe times from begin() to the last mark(): a later mark extends it and a new begin()
## sets it back to 0. It passes every call on to its target, and works without one.
func test_the_probe_times_to_the_last_mark_and_the_runners_probe_gets_every_call() -> void:
	var timer: StepProbe = StepProbe.new()
	timer.begin()
	_busy(2000)
	timer.mark(SimProbe.Phase.COMMANDS)
	assert_int(timer.step_usec).is_greater_equal(2000)
	_busy(2000)
	timer.mark(SimProbe.Phase.REMOVE)
	assert_int(timer.step_usec).is_greater_equal(4000)
	var target: SimProbe = RecordingProbe.new()
	timer.target = target
	timer.begin()
	assert_int(timer.step_usec).is_equal(0)
	timer.mark(SimProbe.Phase.INTEGRATE)
	timer.mark(SimProbe.Phase.REMOVE)
	assert_array(target.calls).is_equal(PackedInt32Array([-1, 6, 9]))
	# The runner hands its probe every begin() and mark() of Sim.step through its StepProbe: the
	# calls a probe given to a MatchLoop directly gets, with the same checkpoint. Without a probe
	# nothing is called.
	var runner: MatchRunner = _data_runner(CONTROLS_PATH, 1)
	var probe: SimProbe = RecordingProbe.new()
	runner.probe = probe
	var scenario: ScenarioDef = load(CONTROLS_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, _sim_stream(1))
	var loop: MatchLoop = MatchLoop.create(scenario, CONTROLS_PATH, 1, world)
	var direct: SimProbe = RecordingProbe.new()
	var none: Array[Command] = []
	for _tick: int in 15:
		runner.run_ticks(1)
		loop.step(world, none, direct)
	assert_int(probe.calls.count(-1)).is_equal(15)
	assert_array(probe.calls).is_equal(direct.calls)
	assert_array(runner.replay.checkpoint_hashes).is_equal(loop.replay.checkpoint_hashes)
	runner.probe = null
	runner.run_ticks(1)
	assert_int(probe.calls.count(-1)).is_equal(15)
	assert_int(runner.last_tick_usec).is_greater(0)


## Ticks without row changes keep every World column and both prev arrays: the same arrays
## (is_same) with the same sizes, as in Phase 1. On ticks without commands no object is created
## either: the runner reuses its command list and its probe. MatchLoop stamps the queued commands
## in place and never empties the list, so the runner clears its list after every step: the
## command submitted once is stamped, recorded and applied once.
func test_ticks_without_row_changes_keep_every_array_and_a_command_runs_once() -> void:
	var command: Command = _move(12500)
	CommandQueue.submit(command)
	_runner.run_ticks(1)
	var before: Array = _row_arrays(_runner)
	var sizes: Array[int] = _sizes(before)
	var x1: int = _runner.world.pos_x[0]
	# Private, read only to tell them apart from new ones.
	var list: Array[Command] = _runner._commands
	var step_probe: StepProbe = _runner._step_probe
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for _frame: int in 20:
		_runner._process(1.0 / 30.0)
	_runner.run_ticks(3)
	var objects_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	assert_int(_runner.world.tick).is_equal(14)
	assert_int(_runner.world.pos_x[0]).is_greater(x1)
	var after: Array = _row_arrays(_runner)
	assert_array(_sizes(after)).is_equal(sizes)
	for k: int in before.size():
		assert_bool(is_same(before[k], after[k])).override_failure_message(str(k)).is_true()
	assert_int(objects_after).is_equal(objects)
	(
		assert_bool(is_same(_runner._commands, list) and is_same(_runner._step_probe, step_probe))
		. is_true()
	)
	assert_array([command.tick, command.sequence, _runner.loop.next_sequence]).is_equal([0, 0, 1])
	var once: PackedInt32Array = PackedInt32Array()
	command.encode(once)
	assert_array(_runner.replay.commands).is_equal(once)
	assert_int(_runner.world.dropped_commands).is_equal(0)


## Frame-rate independence: the arena with seed 42 for 300 ticks, played by frames at 30, 60 and
## 120 fps and by jittered frames, ends with the 15-tick checkpoints of a run through MatchLoop
## alone. At 120 fps a tick takes 8 frames, and alpha() changes on every frame.
func test_the_arena_gives_the_same_checkpoints_at_any_frame_rate() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = _arena_world(42)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, 42, world)
	var none: Array[Command] = []
	for _tick: int in 300:
		loop.step(world, none)
	assert_int(loop.replay.checkpoint_ticks.size()).is_equal(20)
	# 0 stands for the jittered frames.
	for fps: int in [30, 60, 120, 0]:
		var runner: MatchRunner = _data_runner(ARENA_PATH, 42)
		var frames: int = 0
		var alpha_held: int = 0
		while runner.world.tick < 300:
			var delta: float = 1.0 / float(fps) if fps > 0 else JITTER[frames % JITTER.size()]
			# Near the end a frame plays at most one tick, so the run stops at 300 exactly.
			if runner.world.tick > 290:
				delta = minf(delta, 0.06)
			var alpha_before: float = runner.alpha()
			runner._process(delta)
			frames += 1
			if runner.alpha() == alpha_before:
				alpha_held += 1
		var label: String = "fps %d" % fps
		assert_int(runner.world.tick).override_failure_message(label).is_equal(300)
		if fps > 0:
			assert_int(frames).override_failure_message(label).is_equal(300 * fps / 15)
		if fps == 120:
			assert_int(alpha_held).is_equal(0)
		assert_array(runner.replay.checkpoint_ticks).is_equal(loop.replay.checkpoint_ticks)
		assert_array(runner.replay.checkpoint_hashes).override_failure_message(label).is_equal(
			loop.replay.checkpoint_hashes
		)
		assert_int(runner.last_hash).is_equal(loop.last_hash)


## A started runner on the data scenario at `path` with `match_seed`.
func _data_runner(path: String, match_seed: int) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(path) as ScenarioDef
	runner.match_seed = match_seed
	runner.start()
	return runner


func _arena_world(match_seed: int) -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef, _sim_stream(match_seed))


func _sim_stream(match_seed: int) -> DetRandom:
	return DetRandom.create(match_seed, DetRandom.STREAM_SIM)


## Every ROW_ARRAYS column of the runner's world, then prev_pos_x and prev_pos_y.
func _row_arrays(runner: MatchRunner) -> Array:
	var arrays: Array = []
	for column: StringName in World.ROW_ARRAYS:
		arrays.append(runner.world.get(column))
	arrays.append(runner.prev_pos_x)
	arrays.append(runner.prev_pos_y)
	return arrays


func _sizes(arrays: Array) -> Array[int]:
	var sizes: Array[int] = []
	for array: Variant in arrays:
		sizes.append(int(array.size()))
	return sizes


## Waits `usec` microseconds on the clock.
func _busy(usec: int) -> void:
	var until: int = Time.get_ticks_usec() + usec
	while Time.get_ticks_usec() < until:
		pass


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
