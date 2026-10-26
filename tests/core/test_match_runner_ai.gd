extends GdUnitTestSuite
## MatchRunner's computer players (plan row P82, ADR 0020 sections 2, 3 and 5): start() builds one
## DummyAi per def of `opponents` (player 2 upward) with its player's stream, and the tick job lets
## the controllers think before each step, on the thread that runs it. The dummy match is
## tests/core/support/dummy_start.gd (the start of tests/ai/support/ai_rig.gd as a scenario), seed
## 42, player 2 the shipped dummy and player 1 idle but for one MOVE on a tick the dummy thinks:
## played by a SYNC runner, a WORKER runner and a headless loop that calls AiDriver.think_all before
## MatchLoop.step, it gives the same checkpoints and the same log, the dummy's Commands are in it
## after the human's, and Replay.play reproduces it without any AI. The runners are built the Phase
## 1 way (auto_free, never in the tree) and set their mode explicitly; the WORKER runners wait only
## through wait_idle(). A thread suite: it runs three times in a row (CLAUDE.md).

const DummyStart: GDScript = preload("res://tests/core/support/dummy_start.gd")
const RecordingAi: GDScript = preload("res://tests/core/support/recording_ai.gd")
const SEED: int = 42
## Ticks of the dummy match: 40 checkpoints, in which the dummy queues and places its power plant
## and queues the next items of its build order. Its last think is at tick 592, and the job a
## WORKER runner runs ahead (tick 600 to 601) adds no Command and no checkpoint.
const TICKS: int = 600
## The human's MOVE: stamped on a tick the dummy of player 2 thinks on (7 + 2 - 2, ADR 0020
## section 2), to a grass tile north-east of player 1's Headquarters.
const HUMAN_TICK: int = 7
const HUMAN_TARGET: Vector2i = Vector2i(10500, 4500)
## 60 fps frames with jitter, in seconds, used in turn (as tests/core/test_match_runner_worker.gd).
const FRAMES: Array[float] = [0.0167, 0.0121, 0.0213, 0.0158, 0.0175, 0.0098, 0.0236, 0.0166]
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
## The fields of a record of `_records()`, and of a journal record of RecordingAi.
const TICK: int = 0
const PLAYER: int = 1
const TYPE: int = 2
const JOURNAL_TICK: int = 2
const JOURNAL_THREAD: int = 5

var _runners: Array[MatchRunner] = []


func after_test() -> void:
	for runner: MatchRunner in _runners:
		if is_instance_valid(runner):
			assert_bool(runner.wait_idle()).is_true()
	_runners.clear()
	CommandQueue.clear()


## start() builds one DummyAi per def that is not null, entry i for player 2 + i, in player order,
## none for player 1: each with the def's period, the offset DummyAi.create gives its player, and
## the stream DetRng.create(seed, STREAM_AI_BASE + player), not drawn from. No opponents, no
## controllers.
func test_start_builds_a_dummy_per_opponent_with_its_players_stream() -> void:
	var def: AiDef = DummyStart.dummy_def()
	var runner: MatchRunner = _runner(SYNC, [def, null, def])
	var built: Array[AiController] = runner._job.controllers
	assert_array(built.map(func(ai: AiController) -> int: return ai.player_id)).is_equal([2, 4])
	for controller: AiController in built:
		var player: int = controller.player_id
		var stream: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + player)
		var expected: AiController = DummyAi.create(def, player, stream)
		assert_bool(controller is DummyAi).is_true()
		assert_array([controller.think_period, controller.think_offset]).is_equal(
			[expected.think_period, expected.think_offset]
		)
		assert_array(controller.rng.state()).is_equal(stream.state())
	# Player 2 thinks at tick % 15 == 7, player 4 two ticks later.
	assert_array([built[0].think_offset, built[1].think_offset]).is_equal([8, 6])
	assert_bool(built[0].rng.state() == built[1].rng.state()).is_false()
	var none: Array[AiDef] = []
	assert_array(_runner(SYNC, none)._job.controllers).is_empty()


## A restart builds the new match's controllers and lets the old ones go at once, as it does the old
## World: after start() with no opponents the job holds none and the old dummy is freed; with the
## def back, a new dummy with a fresh stream.
func test_a_restart_replaces_the_controllers_and_frees_the_old_ones() -> void:
	var def: AiDef = DummyStart.dummy_def()
	var runner: MatchRunner = _runner(SYNC, [def])
	runner.run_ticks(HUMAN_TICK + 1)
	var old: WeakRef = _weak_first_controller(runner)
	# A bool, not the object: an assert on the object would keep a reference to it.
	assert_bool(old.get_ref() != null).is_true()
	runner.opponents = []
	runner.start()
	assert_array(runner._job.controllers).is_empty()
	assert_object(old.get_ref()).is_null()
	runner.opponents = [def]
	runner.start()
	assert_int(runner._job.controllers.size()).is_equal(1)
	var stream: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + 2)
	assert_array(runner._job.controllers[0].rng.state()).is_equal(stream.state())


## The controllers think on the thread that runs the job (ADR 0020 section 3): the main thread in
## SYNC, the worker in WORKER. A recording controller of player 2 put in the job after start()
## thinks once per tick, on the World of that tick before its step.
func test_the_controllers_think_on_the_thread_that_runs_the_job() -> void:
	var main: int = OS.get_thread_caller_id()
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode, [])
		var journal: Array = []
		var recorder: AiController = RecordingAi.new()
		recorder.player_id = 2
		recorder.set(&"journal", journal)
		runner._job.controllers = [recorder]
		assert_bool(_play_to(runner, 5)).is_true()
		var ticks: Array = journal.map(func(record: Array) -> int: return record[JOURNAL_TICK])
		assert_array(ticks.slice(0, 5)).override_failure_message(str(mode)).is_equal(range(5))
		for record: Array in journal:
			assert_bool(record[JOURNAL_THREAD] == main).is_equal(mode == SYNC)


## The dummy match, played by a SYNC runner and a WORKER runner with the human's MOVE submitted in
## `ticked(HUMAN_TICK)`, and by the headless loop: the same 40 checkpoints and the same log in all
## three, and nothing dropped.
func test_a_dummy_match_is_the_same_in_sync_in_worker_and_in_a_headless_loop() -> void:
	var world: World = _start_world()
	var loop: MatchLoop = _headless_match(world)
	var expected: Replay = loop.replay
	assert_int(expected.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	assert_int(world.dropped_commands).is_equal(0)
	var squad: PackedInt32Array = _squad_of_player_1()
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode, [DummyStart.dummy_def()])
		runner.ticked.connect(
			func(tick: int) -> void:
				if tick == HUMAN_TICK:
					CommandQueue.submit(_human(squad))
		)
		assert_bool(_play_to(runner, TICKS)).is_true()
		var replay: Replay = runner.replay
		var label: String = "mode %d" % mode
		assert_array(replay.checkpoint_ticks).override_failure_message(label).is_equal(
			expected.checkpoint_ticks
		)
		assert_array(replay.checkpoint_hashes).override_failure_message(label).is_equal(
			expected.checkpoint_hashes
		)
		assert_array(replay.commands).override_failure_message(label).is_equal(expected.commands)
		assert_int(runner.world.dropped_commands).is_equal(0)


## The log of the dummy match (the runners' equals it, above): the human's MOVE is the one Command
## of player 1, stamped HUMAN_TICK and logged before the dummy's Commands of that tick; every
## Command of player 2 is stamped on its think ticks, QUEUE and PLACE among them. Replay.play on a
## fresh World of the scenario, with no AI, reaches every checkpoint and the run's final state.
func test_the_dummys_commands_are_in_the_replay_and_it_replays_without_the_ai() -> void:
	var world: World = _start_world()
	var loop: MatchLoop = _headless_match(world)
	var records: Array = _records(loop.replay)
	var human: Array = records.filter(func(record: Array) -> bool: return record[PLAYER] == 1)
	assert_array(human).is_equal([[HUMAN_TICK, 1, Command.Type.MOVE]])
	var at_human: Array = records.filter(
		func(record: Array) -> bool: return record[TICK] == HUMAN_TICK
	)
	assert_int(at_human.size()).is_greater(1)
	assert_array(at_human[0]).is_equal(human[0])
	# The dummy's turns, as start() builds it for player 2 (seed and stream do not change them).
	var dummy: AiController = DummyAi.create(DummyStart.dummy_def(), 2, null)
	var types: Dictionary[int, int] = {}
	for record: Array in records:
		if record[PLAYER] != 1:
			assert_int(record[PLAYER]).is_equal(2)
			assert_int((record[TICK] + dummy.think_offset) % dummy.think_period).is_equal(0)
			types[record[TYPE]] = types.get(record[TYPE], 0) + 1
	assert_bool(types.has(Command.Type.QUEUE) and types.has(Command.Type.PLACE)).is_true()
	var replayed: World = _start_world()
	assert_int(Replay.play(loop.replay, replayed, world.tick)).is_equal(Replay.PLAY_MATCHED)
	assert_array([replayed.tick, replayed.state_hash()]).is_equal([TICKS, world.state_hash()])


## A started runner on the dummy start, seed 42, in `mode`, with `defs` as its opponents.
func _runner(mode: int, defs: Array[AiDef]) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.opponents = defs
	runner.start()
	_runners.append(runner)
	return runner


## The World a runner starts the dummy match with: the scenario and the sim stream of the seed.
func _start_world() -> World:
	var stream: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_SIM)
	return World.from_scenario(DummyStart.scenario(), stream)


## TICKS ticks of the dummy match on `world` through the headless driver of ADR 0020 section 3:
## each tick the human's Commands, then AiDriver.think_all with the shipped dummy of player 2 (built
## as start() builds it), then MatchLoop.step. Returns the loop, whose replay is the match's log.
func _headless_match(world: World) -> MatchLoop:
	var loop: MatchLoop = MatchLoop.create(DummyStart.scenario(), "", SEED, world)
	var stream: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + 2)
	var controllers: Array[AiController] = [DummyAi.create(DummyStart.dummy_def(), 2, stream)]
	var squad: PackedInt32Array = _squad_of_player_1()
	var queued: Array[Command] = []
	for _tick: int in TICKS:
		queued.clear()
		if world.tick == HUMAN_TICK:
			queued.append(_human(squad))
		AiDriver.think_all(world, controllers, queued)
		loop.step(world, queued)
	return loop


## The ids of player 1's rifle squads at the start.
func _squad_of_player_1() -> PackedInt32Array:
	var world: World = _start_world()
	var ids: PackedInt32Array = PackedInt32Array()
	var squad_type: int = world.type_ids.find(&"rifle_squad")
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_index[row] == squad_type:
			ids.append(world.unit_id[row])
	assert_int(ids.size()).is_equal(2)
	return ids


func _human(squad: PackedInt32Array) -> Command:
	return Command.move(1, squad, HUMAN_TARGET.x, HUMAN_TARGET.y)


## The replay's log as [tick, player_id, type] per command, in log order.
func _records(replay: Replay) -> Array:
	var records: Array = []
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		assert_int(at).is_greater(0)
		if at <= 0:
			break
		records.append([command.tick, command.player_id, command.type])
	return records


## A weak reference to the first controller of `runner`'s job, made here so that the case keeps no
## strong one.
func _weak_first_controller(runner: MatchRunner) -> WeakRef:
	return weakref(runner._job.controllers[0])


## Plays `runner` with the jittered frames and wait_idle() after each until it publishes `tick`;
## false when a wait reaches its cap or the frames run out.
func _play_to(runner: MatchRunner, tick: int) -> bool:
	var frames: int = 0
	while runner.snapshot.tick < tick and frames < 8 * tick + 8:
		runner._process(FRAMES[frames % FRAMES.size()])
		frames += 1
		if not runner.wait_idle():
			return false
	return runner.snapshot.tick == tick
