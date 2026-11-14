extends GdUnitTestSuite
## The AI thread of MatchRunner (plan row P303, ADR 0038 sections 2, 3 and 7), on the dummy start of
## tests/core/support/dummy_start.gd, seed 42, with the shipped Fossil opponent as player 2 and a
## human MOVE:
## - SYNC equals WORKER: the same Command log and checkpoint hashes over 900 ticks, the AI thread
##   thinking beside the job (the main thread never does);
## - a slow controller makes the job wait for its batch (`ai_wait_usec` above 0) and still gives the
##   SYNC log: the wait moves no Command to another tick;
## - wait_idle() waits for the batch in flight, and marks it done;
## - the thread is kept across start()s, joined after the sim worker at the runner's end and on
##   PREDELETE, and a start() that fails or that resolves SYNC leaves no AI thread.
## A thread suite: it runs three times in a row (CLAUDE.md). The runners are built the Phase 1 way
## (auto_free, never in the tree) and play through wait_idle() only.

const DummyStart: GDScript = preload("res://tests/core/support/dummy_start.gd")
const WaitingAi: GDScript = preload("res://tests/core/support/waiting_ai.gd")
const SEED: int = 42
const FOSSIL: AiDef = preload("res://data/ai/opponent_fossil.tres")
const TICKS: int = 900
const FRAMES: Array[float] = [0.0167, 0.0121, 0.0213, 0.0158, 0.0175, 0.0098, 0.0236, 0.0166]
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
const HUMAN_TICK: int = 8
const HUMAN_TARGET: Vector2i = Vector2i(10500, 4500)

var _runners: Array[MatchRunner] = []
var _workers_before: int = 0


func before_test() -> void:
	_workers_before = MatchRunner.live_workers()


func after_test() -> void:
	for runner: MatchRunner in _runners:
		if is_instance_valid(runner):
			assert_bool(runner.wait_idle()).is_true()
	_runners.clear()
	CommandQueue.clear()


func test_sync_equals_worker_over_900_ticks_with_the_ai_on_its_own_thread() -> void:
	var sync: MatchRunner = _run(SYNC, FOSSIL, TICKS)
	var worker: MatchRunner = _run(WORKER, FOSSIL, TICKS)
	assert_bool(worker._ai_thread != null and worker._ai_thread.is_started()).is_true()
	assert_object(sync._ai_thread).is_null()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 2)
	assert_int(sync.replay.commands.size()).is_greater(40)
	assert_array(worker.replay.checkpoint_ticks).is_equal(sync.replay.checkpoint_ticks)
	assert_array(worker.replay.checkpoint_hashes).is_equal(sync.replay.checkpoint_hashes)
	assert_array(worker.replay.commands).is_equal(sync.replay.commands)
	assert_int(worker.world.dropped_commands).is_equal(sync.world.dropped_commands)
	assert_int(worker.last_hash).is_equal(sync.last_hash)


func test_a_slow_think_makes_the_job_wait_and_moves_no_command() -> void:
	var main: int = OS.get_thread_caller_id()
	var logs: Array = []
	var waits: Array[int] = []
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode, FOSSIL)
		var slow: AiController = WaitingAi.new()
		slow.player_id = 2
		slow.think_period = 1
		runner._job.controllers = [slow]
		var seen: Array[int] = []
		runner.ticked.connect(func(_tick: int) -> void: seen.append(runner.snapshot.ai_wait_usec))
		assert_bool(_play_free(runner, 24)).is_true()
		waits.append(seen.filter(func(usec: int) -> bool: return usec > 0).size())
		logs.append(runner.replay.commands)
		assert_int(slow.get(&"thinks")).is_greater_equal(23)
		var threads: Dictionary = slow.get(&"threads")
		assert_bool(threads.has(main)).is_equal(mode == SYNC)
		assert_int(threads.size()).is_equal(1)
	assert_int(waits[0]).is_equal(0)
	assert_int(waits[1]).is_greater(0)
	# The free-running WORKER match may be a tick further: the shorter log is a prefix of the other.
	var shared: int = mini(logs[0].size(), logs[1].size())
	assert_int(shared).is_greater(100)
	assert_array(logs[1].slice(0, shared)).is_equal(logs[0].slice(0, shared))


func test_wait_idle_waits_for_the_batch_in_flight_and_marks_it_done() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	var slow: AiController = WaitingAi.new()
	slow.player_id = 2
	slow.think_period = 1
	runner._job.controllers = [slow]
	runner.run_ticks(1)
	assert_bool(runner._job.batch.awaiting).is_true()
	assert_bool(runner.wait_idle()).is_true()
	assert_bool(runner._job.batch.awaiting).is_false()
	for _i: int in 3:
		runner._process(0.07)
		assert_bool(runner.wait_idle()).is_true()
		assert_bool(runner._job.batch.awaiting).is_false()
	assert_int(slow.get(&"thinks")).is_greater_equal(2)
	# Taken by wait_idle(), the batch is still the next job's to collect.
	assert_bool(runner._job.batch.pending).is_true()
	assert_int(runner._job.batch.commands.size()).is_greater(0)


func test_the_thread_is_kept_across_starts_and_joined_after_the_sim_worker() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	assert_bool(_play_to(runner, 12)).is_true()
	var thread: Thread = runner._ai_thread
	assert_object(thread).is_not_null()
	runner.start()
	assert_object(runner._ai_thread).is_same(thread)
	assert_bool(_play_to(runner, 12)).is_true()
	runner._join_worker()
	assert_object(runner._ai_thread).is_null()
	assert_object(runner._thread).is_null()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)
	# A second join, and a start() after it, are clean.
	runner._join_worker()
	runner.start()
	assert_bool(_play_to(runner, 12)).is_true()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 2)
	runner._join_worker()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)


func test_predelete_joins_both_threads_with_a_batch_in_flight() -> void:
	var runner: MatchRunner = MatchRunner.new()
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = WORKER
	runner.opponents = [FOSSIL]
	runner.start()
	var slow: AiController = WaitingAi.new()
	slow.player_id = 2
	slow.think_period = 1
	runner._job.controllers = [slow]
	for frame: int in 6:
		runner._process(FRAMES[frame])
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 2)
	runner.free()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)


func test_a_start_that_resolves_sync_joins_the_thread_and_a_failed_start_thinks_inline() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	assert_bool(_play_to(runner, 12)).is_true()
	assert_object(runner._ai_thread).is_not_null()
	runner.tick_mode = SYNC
	runner.start()
	assert_object(runner._ai_thread).is_null()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 1)  # The sim worker stays.
	# A failed AI start leaves the job inline, with the SYNC log.
	var sync: MatchRunner = _run(SYNC, FOSSIL, 300)
	var failed: MatchRunner = _run(WORKER, FOSSIL, 300, true)
	assert_object(failed._ai_thread).is_null()
	assert_array(failed.replay.commands).is_equal(sync.replay.commands)
	assert_array(failed.replay.checkpoint_hashes).is_equal(sync.replay.checkpoint_hashes)


## A started runner on the dummy start in `mode`, with `def` as player 2.
func _runner(mode: int, def: AiDef, ai_failed: bool = false) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner._ai_start_failed = ai_failed
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.opponents = [def]
	runner.start()
	_runners.append(runner)
	return runner


## Plays `ticks` ticks of the match with the human's MOVE at HUMAN_TICK.
func _run(mode: int, def: AiDef, ticks: int, ai_failed: bool = false) -> MatchRunner:
	var runner: MatchRunner = _runner(mode, def, ai_failed)
	var squad: PackedInt32Array = PackedInt32Array()
	var world: World = runner.world
	var squad_type: int = world.type_ids.find(&"rifle_squad")
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_index[row] == squad_type:
			squad.append(world.unit_id[row])
	runner.ticked.connect(
		func(tick: int) -> void:
			if tick == HUMAN_TICK:
				CommandQueue.submit(Command.move(1, squad, HUMAN_TARGET.x, HUMAN_TARGET.y))
	)
	assert_bool(_play_to(runner, ticks)).is_true()
	return runner


## Plays `runner` with the jittered frames and wait_idle() after each until it publishes `tick`.
func _play_to(runner: MatchRunner, tick: int) -> bool:
	var frames: int = 0
	while runner.snapshot.tick < tick and frames < 8 * tick + 8:
		runner._process(FRAMES[frames % FRAMES.size()])
		frames += 1
		if not runner.wait_idle():
			return false
	return runner.snapshot.tick == tick


## Plays `runner` without waiting between the frames, as the game does, until it publishes `tick`,
## then waits idle; false when the frames run out.
func _play_free(runner: MatchRunner, tick: int) -> bool:
	var frames: int = 0
	while runner.snapshot.tick < tick and frames < 4000:
		runner._process(0.07)
		frames += 1
		OS.delay_msec(2)
	return runner.wait_idle() and runner.snapshot.tick >= tick
