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
const OrderRunner: GDScript = preload("res://tests/core/support/order_runner.gd")
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


## ADR 0038 section 8: one runner with two OpponentAi at Hard (the frozen perf_ai defs and level,
## as ai_perf_run.gd seats them) plays SYNC and WORKER, the WORKER one free-running with a slow
## third controller that makes the job wait for its batch at least once, then run_ticks() to tick
## 900. Equal Command logs, checkpoints and hashes; both players act.
func test_two_hard_ais_play_the_same_in_sync_and_in_worker_with_a_forced_wait() -> void:
	var sync: MatchRunner = _perf_ai_runner(SYNC)
	sync.run_ticks(TICKS)
	var worker: MatchRunner = _perf_ai_runner(WORKER)
	var waits: Array[int] = []
	worker.ticked.connect(func(_tick: int) -> void: waits.append(worker.snapshot.ai_wait_usec))
	assert_bool(_play_free(worker, 400)).is_true()
	worker.run_ticks(TICKS - worker.snapshot.tick)
	assert_bool(worker.wait_idle()).is_true()
	assert_int(worker.snapshot.tick).is_equal(TICKS)
	assert_int(sync.snapshot.tick).is_equal(TICKS)
	assert_bool(worker._ai_thread != null and worker._ai_thread.is_started()).is_true()
	assert_int(waits.filter(func(usec: int) -> bool: return usec > 0).size()).is_greater(0)
	var players: Dictionary[int, bool] = {}
	var at: int = 0
	var log: PackedInt32Array = sync.replay.commands
	while at < log.size():
		var command: Command = Command.new()
		at = Command.decode(log, at, command)
		assert_int(at).is_greater(0)
		if at <= 0:
			break
		players[command.player_id] = true
	assert_bool(players.has(1) and players.has(2)).is_true()
	assert_array(worker.replay.checkpoint_ticks).is_equal(sync.replay.checkpoint_ticks)
	assert_array(worker.replay.checkpoint_hashes).is_equal(sync.replay.checkpoint_hashes)
	assert_array(worker.replay.commands).is_equal(sync.replay.commands)
	assert_int(worker.world.dropped_commands).is_equal(sync.world.dropped_commands)
	assert_int(worker.last_hash).is_equal(sync.last_hash)


## A wait_idle() that times out on the AI's batch must not lose the job's `done` token (ADR 0012
## section 1: RUNNING means the token is not taken): the runner keeps ticking after it.
func test_a_wait_idle_that_times_out_on_the_ai_keeps_the_runner_ticking() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	var slow: AiController = _slow()
	slow.set(&"wait_msec", 300)
	runner._job.controllers = [slow]
	runner._process(0.07)  # Posts the job of tick 1; its batch keeps the AI thread 300 ms.
	# The job ends in a few ms. Take its token and put it back, so that the wait below takes it
	# at once and times out on the AI alone.
	while not runner._job.done.try_wait():
		OS.delay_msec(1)
	runner._job.done.post()
	var seen: Array[String] = []
	runner._timeout_sink = func(text: String) -> void: seen.append(text)
	assert_bool(runner.wait_idle(2)).is_false()
	assert_array(seen).is_equal(["MatchRunner: the AI thread did not finish within 2 ms"])
	assert_bool(runner.job_in_flight()).is_false()
	assert_bool(runner._job.batch.awaiting).is_true()
	var frames: int = 0
	while runner.snapshot.tick < 3 and frames < 2000:
		runner._process(0.07)
		frames += 1
		OS.delay_msec(2)
	assert_int(runner.snapshot.tick).is_greater_equal(3)
	assert_bool(runner.wait_idle()).is_true()


## The same for start(): its wait on the AI times out, it logs and returns with the old match, whose
## job token it took, so the old match keeps ticking.
func test_a_start_that_times_out_on_the_ai_keeps_the_old_match_ticking() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	var slow: AiController = _slow()
	slow.set(&"wait_msec", 300)
	runner._job.controllers = [slow]
	runner._start_cap_msec = 2
	runner._process(0.07)
	while not runner._job.done.try_wait():
		OS.delay_msec(1)
	runner._job.done.post()
	var serial: int = runner.match_serial
	var seen: Array[String] = []
	runner._timeout_sink = func(text: String) -> void: seen.append(text)
	runner.start()
	assert_array(seen).is_equal(["MatchRunner: the AI thread did not finish within 2 ms"])
	assert_int(runner.match_serial).is_equal(serial)
	assert_bool(runner.job_in_flight()).is_false()
	var frames: int = 0
	while runner.snapshot.tick < 3 and frames < 2000:
		runner._process(0.07)
		frames += 1
		OS.delay_msec(2)
	assert_int(runner.snapshot.tick).is_greater_equal(3)
	assert_bool(runner.wait_idle()).is_true()


func test_a_slow_think_makes_the_job_wait_and_moves_no_command() -> void:
	var main: int = OS.get_thread_caller_id()
	var logs: Array = []
	var waits: Array[int] = []
	var stamps: Array = []
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode, FOSSIL)
		var slow: AiController = WaitingAi.new()
		slow.player_id = 2
		slow.think_period = 1
		runner._job.controllers = [slow]
		var seen: Array[int] = []
		var thought: Array[bool] = []
		runner.ticked.connect(
			func(_tick: int) -> void:
				seen.append(runner.snapshot.ai_wait_usec)
				thought.append(runner.snapshot.think_usec > 0)
		)
		assert_bool(_play_free(runner, 24)).is_true()
		waits.append(seen.filter(func(usec: int) -> bool: return usec > 0).size())
		logs.append(runner.replay.commands)
		stamps.append(thought.slice(0, 23))
		assert_int(slow.get(&"thinks")).is_greater_equal(23)
		var threads: Dictionary = slow.get(&"threads")
		assert_bool(threads.has(main)).is_equal(mode == SYNC)
		assert_int(threads.size()).is_equal(1)
	assert_int(waits[0]).is_equal(0)
	assert_int(waits[1]).is_greater(0)
	# think_usec is stamped on the tick that collects a batch, in both modes (ADR 0038 section 7).
	assert_array(stamps[1]).is_equal(stamps[0])
	assert_bool(stamps[0].has(true)).is_true()
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
	var scan: LogScan = LogScan.new()
	OS.add_logger(scan)
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
	OS.remove_logger(scan)
	assert_array(Array(scan.hits())).is_empty()


func test_predelete_joins_both_threads_while_the_job_waits_for_the_batch() -> void:
	var runner: MatchRunner = MatchRunner.new()
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = WORKER
	runner.opponents = [FOSSIL]
	runner.start()
	runner._job.controllers = [_slow()]
	# The refill posts the job of tick 1, which hands its batch to the AI thread for 40 ms; the
	# frame that publishes it posts the job of tick 2, whose step 1 then waits for that batch.
	var frames: int = 0
	while runner.snapshot.tick < 1 and frames < 20000:
		runner._process(0.07)
		frames += 1
		OS.delay_usec(200)
	assert_int(runner.snapshot.tick).is_equal(1)
	assert_bool(runner.job_in_flight()).is_true()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 2)
	var scan: LogScan = LogScan.new()
	OS.add_logger(scan)
	runner.free()
	OS.remove_logger(scan)
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)
	assert_array(Array(scan.hits())).is_empty()


func test_the_ai_thread_is_joined_after_the_sim_worker() -> void:
	var runner: MatchRunner = auto_free(OrderRunner.new())
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = WORKER
	runner.opponents = [FOSSIL]
	runner.start()
	_runners.append(runner)
	assert_bool(_play_to(runner, 12)).is_true()
	runner._join_worker()
	assert_array(runner.get(&"sim_joined_first")).is_equal([true])


func test_a_start_during_a_think_waits_for_the_batch_and_drops_it() -> void:
	var fresh: MatchRunner = _runner(WORKER, FOSSIL)
	fresh._job.controllers = [_slow()]
	assert_bool(_play_to(fresh, 4)).is_true()
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	runner._job.controllers = [_slow()]
	runner.run_ticks(1)
	assert_bool(runner._job.batch.awaiting).is_true()
	runner.start()
	assert_bool(runner._job.batch.awaiting).is_false()
	# A think that start() left running would end in here, add its Command and post its token.
	OS.delay_msec(100)
	assert_array(runner._job.batch.commands).is_empty()
	assert_bool(runner._job.ai_done.try_wait()).is_false()
	runner._job.controllers = [_slow()]
	assert_bool(_play_to(runner, 4)).is_true()
	assert_array(runner.replay.commands).is_equal(fresh.replay.commands)
	assert_int(runner.last_hash).is_equal(fresh.last_hash)


func test_a_start_that_resolves_sync_joins_the_thread_and_a_failed_start_thinks_inline() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	assert_bool(_play_to(runner, 12)).is_true()
	assert_object(runner._ai_thread).is_not_null()
	runner.tick_mode = SYNC
	runner.start()
	assert_object(runner._ai_thread).is_null()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 1)  # The sim worker stays.
	# A failed AI start leaves the job inline, with the SYNC log, and logs one warning.
	var sync: MatchRunner = _runner(SYNC, FOSSIL)
	assert_bool(_play_to(sync, 300)).is_true()
	var started: Array[MatchRunner] = []
	await (
		assert_error(func() -> void: started.append(_runner(WORKER, FOSSIL, true)))
		. is_push_warning("MatchRunner: no AI thread (error 20); the thinks run inline")
	)
	var failed: MatchRunner = started[0]
	assert_bool(_play_to(failed, 300)).is_true()
	assert_bool(failed._ai_start_failed).is_true()
	assert_object(failed._ai_thread).is_null()
	assert_object(failed._job.ai_work).is_null()
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before + 2)  # The two sim workers.
	assert_array(failed.replay.commands).is_equal(sync.replay.commands)
	assert_array(failed.replay.checkpoint_hashes).is_equal(sync.replay.checkpoint_hashes)


## The perf_ai arena with its two frozen OpponentAi at the frozen Hard level, players 1 and 2; in
## plus a WaitingAi of player 1 that thinks every 15th tick and sleeps 40 ms, in both modes.
func _perf_ai_runner(mode: int) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load("res://data/scenarios/perf_ai.tres") as ScenarioDef
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.first_opponent = 1
	var fossil: AiDef = load("res://data/dev/arena/ai/opponent_fossil.tres") as AiDef
	var renew: AiDef = load("res://data/dev/arena/ai/opponent_renew.tres") as AiDef
	var hard: AiDifficultyDef = load("res://data/dev/arena/ai/difficulty/hard.tres")
	runner.opponents = [fossil, renew]
	runner.opponent_levels = [hard, hard]
	runner.start()
	_runners.append(runner)
	var slow: AiController = WaitingAi.new()
	slow.player_id = 1
	slow.think_period = 15
	slow.think_offset = 1
	runner._job.controllers.append(slow)
	return runner


## A WaitingAi for player 2 that thinks every tick.
func _slow() -> AiController:
	var slow: AiController = WaitingAi.new()
	slow.player_id = 2
	slow.think_period = 1
	return slow


## A started runner on the dummy start in `mode`, with `def` as player 2.
func _runner(mode: int, def: AiDef, ai_failed: bool = false) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	if ai_failed:
		runner._ai_start_error = ERR_CANT_CREATE
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.opponents = [def]
	runner.start()
	_runners.append(runner)
	return runner


## Plays `ticks` ticks of the match with the human's MOVE at HUMAN_TICK.
func _run(mode: int, def: AiDef, ticks: int) -> MatchRunner:
	var runner: MatchRunner = _runner(mode, def)
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


## Every warning and error the engine logs, from any thread.
class LogScan:
	extends Logger

	var _mutex: Mutex = Mutex.new()
	var _hits: PackedStringArray = PackedStringArray()

	func hits() -> PackedStringArray:
		_mutex.lock()
		var copy: PackedStringArray = _hits.duplicate()
		_mutex.unlock()
		return copy

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		_hits.append("%s:%d %s %s" % [file, line, code, rationale])
		_mutex.unlock()
