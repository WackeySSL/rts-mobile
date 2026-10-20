extends GdUnitTestSuite
## MatchRunner in WORKER mode, part 1 (plan P38w, ADR 0012 section 1): the hand-off table, the mode
## rules, a WORKER runner in lockstep with a SYNC runner and its clock beside a SYNC clock, one tick
## ahead and the held boundary, start() during a job and run_ticks(). The runners are built the
## Phase 1 way (auto_free, never in the tree) on the seed-42 perf arena and set WORKER explicitly,
## the exception to "headless tests run SYNC" (headless, AUTO resolves to SYNC). The cases wait
## only through wait_idle() and fail when it returns false; after_test releases every gated probe
## and then waits for every runner, so a case that fails while a probe holds a job still leaves the
## worker free. One case lets a frame take the token itself: it runs frames of zero length while a
## job is in flight, capped like wait_idle() (lead decision, P38w fix round 1: neither a fixed
## sleep nor a try_wait() on the runner's semaphores).

const GatedProbe: GDScript = preload("res://tests/core/gated_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42
## Ticks of the lockstep run: 20 checkpoints.
const TICKS: int = 300
## 60 fps frames with jitter, in seconds, used in turn: each under a tick, two ticks per 8 frames.
const FRAMES: Array[float] = [0.0167, 0.0121, 0.0213, 0.0158, 0.0175, 0.0098, 0.0236, 0.0166]
## A frame of exactly a quarter tick.
const FRAME: float = 1.0 / 60.0
## A steady frame of 17 ms, 0.255 of a tick: boundaries fall inside frames, so each one leaves a
## part of a tick on the clock. The clock case plays this many of them: 153 ticks in SYNC.
const STEADY: float = 0.017
const STEADY_FRAMES: int = 600
## The tick whose publish the one-tick-ahead case stops at.
const AHEAD: int = 5
## How long a delayed job waits in its probe's begin(): far longer than a frame call, and a shorter
## delay that still keeps every job running well past the frame that posted it.
const DELAY_MSEC: int = 30
const SHORT_DELAY_MSEC: int = 5
## The MatchSnapshot fields that are timings, not state, so the lockstep leaves them out.
const TIMINGS: Array[StringName] = [
	&"phase_usec", &"step_usec", &"job_usec", &"post_usec", &"end_usec"
]
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
const AUTO: int = MatchRunner.TickMode.AUTO
const IDLE: int = MatchRunner.HandOff.IDLE
const RUNNING: int = MatchRunner.HandOff.RUNNING
const FINISHED: int = MatchRunner.HandOff.FINISHED
const NONE: int = MatchRunner.HandOffStep.NONE
const WAIT: int = MatchRunner.HandOffStep.WAIT
const DISCARD: int = MatchRunner.HandOffStep.DISCARD
const PUBLISH: int = MatchRunner.HandOffStep.PUBLISH
const POST: int = MatchRunner.HandOffStep.POST
const HOLD: int = MatchRunner.HandOffStep.HOLD
const ON_FRAME: int = MatchRunner.HandOffEvent.FRAME
const ON_TAKEN: int = MatchRunner.HandOffEvent.FRAME_TAKEN
const ON_BOUNDARY: int = MatchRunner.HandOffEvent.BOUNDARY
const ON_WAIT_IDLE: int = MatchRunner.HandOffEvent.WAIT_IDLE
const ON_START: int = MatchRunner.HandOffEvent.START
const ON_RUN_TICKS: int = MatchRunner.HandOffEvent.RUN_TICKS
const ON_STOP: int = MatchRunner.HandOffEvent.STOP
## ADR 0012 section 1's table: per event, the next state and the steps from IDLE, RUNNING and
## FINISHED. FRAME_TAKEN is reached only from RUNNING, a boundary never in IDLE (the refill comes
## first); such a cell keeps the state and does nothing.
const TABLE: Dictionary[int, Array] = {
	ON_FRAME: [Vector2i(RUNNING, POST), Vector2i(RUNNING, NONE), Vector2i(FINISHED, NONE)],
	ON_TAKEN: [Vector2i(IDLE, NONE), Vector2i(FINISHED, NONE), Vector2i(FINISHED, NONE)],
	ON_BOUNDARY: [Vector2i(IDLE, NONE), Vector2i(RUNNING, HOLD), Vector2i(RUNNING, PUBLISH | POST)],
	ON_WAIT_IDLE: [Vector2i(IDLE, NONE), Vector2i(FINISHED, WAIT), Vector2i(FINISHED, NONE)],
	ON_START: [Vector2i(IDLE, NONE), Vector2i(IDLE, WAIT | DISCARD), Vector2i(IDLE, DISCARD)],
	ON_RUN_TICKS: [Vector2i(IDLE, NONE), Vector2i(IDLE, WAIT | PUBLISH), Vector2i(IDLE, PUBLISH)],
	ON_STOP: [Vector2i(IDLE, NONE), Vector2i(IDLE, WAIT | DISCARD), Vector2i(IDLE, DISCARD)],
}
## resolve_mode(AUTO, threads, web, headless) over (threads, web, headless) from (false, false,
## false) to (true, true, true), headless changing fastest.
const AUTO_RESOLVED: Array[int] = [SYNC, SYNC, SYNC, SYNC, WORKER, SYNC, SYNC, SYNC]

var _main_thread: int = 0
var _runners: Array[MatchRunner] = []
var _probes: Array[SimProbe] = []


func before_test() -> void:
	_main_thread = OS.get_thread_caller_id()


func after_test() -> void:
	for probe: SimProbe in _probes:
		probe.release()
	for runner: MatchRunner in _runners:
		if is_instance_valid(runner):
			assert_bool(runner.wait_idle()).is_true()
	_probes.clear()
	_runners.clear()
	CommandQueue.clear()


## Every cell of the table, the enum values, and the plan's sequences through it. No wait can block
## on a token that is gone: only RUNNING waits.
func test_hand_off_is_the_table_of_adr_0012() -> void:
	assert_array([IDLE, RUNNING, FINISHED]).is_equal([0, 1, 2])
	assert_array(TABLE.keys()).is_equal([0, 1, 2, 3, 4, 5, 6])
	assert_array([NONE, WAIT, DISCARD, PUBLISH, POST, HOLD]).is_equal([0, 1, 2, 4, 8, 16])
	for event: int in TABLE:
		var found: Array[Vector2i] = []
		for state: int in [IDLE, RUNNING, FINISHED]:
			found.append(MatchRunner.hand_off(state, event))
			if state != RUNNING:
				assert_int(found[state].y & WAIT).is_equal(0)
		assert_array(found).override_failure_message(str(event)).is_equal(TABLE[event])
	# A state or an event outside the enums keeps the state and does nothing (a negative state
	# would otherwise index the table from its end).
	var outside: Array[Vector2i] = [Vector2i(3, ON_FRAME), Vector2i(-1, ON_FRAME)]
	outside.append_array([Vector2i(IDLE, 7), Vector2i(RUNNING, -1)])
	for pair: Vector2i in outside:
		assert_that(MatchRunner.hand_off(pair.x, pair.y)).is_equal(Vector2i(pair.x, NONE))
	# wait_idle() twice: the second returns at once. wait_idle() with no job ever posted.
	var twice: Array[Vector2i] = [Vector2i(FINISHED, WAIT), Vector2i(FINISHED, NONE)]
	assert_array(_chain(RUNNING, [ON_WAIT_IDLE, ON_WAIT_IDLE])).is_equal(twice)
	assert_array(_chain(IDLE, [ON_WAIT_IDLE])).is_equal([Vector2i(IDLE, NONE)])
	# A pause with the job finished (no frame runs, so its token is not taken), then run_ticks(2):
	# the wait returns at once, the job is the first tick, one runs inline, the next frame refills.
	var paused: Array[Vector2i] = [Vector2i(RUNNING, POST), Vector2i(IDLE, WAIT | PUBLISH)]
	paused.append(Vector2i(RUNNING, POST))
	assert_array(_chain(IDLE, [ON_FRAME, ON_RUN_TICKS, ON_FRAME])).is_equal(paused)
	# start() with a finished, unpublished job drops it without a wait.
	var restart: Array[Vector2i] = [Vector2i(FINISHED, NONE), Vector2i(IDLE, DISCARD)]
	assert_array(_chain(RUNNING, [ON_TAKEN, ON_START])).is_equal(restart)
	# One tick ahead: the refill, a frame without the token, the frame that takes it, then a
	# boundary that publishes and posts, and the next one in the same frame holds.
	var ahead: Array[Vector2i] = [Vector2i(RUNNING, POST), Vector2i(RUNNING, NONE)]
	ahead.append_array([Vector2i(FINISHED, NONE), Vector2i(RUNNING, PUBLISH | POST)])
	ahead.append(Vector2i(RUNNING, HOLD))
	var events: Array[int] = [ON_FRAME, ON_FRAME, ON_TAKEN, ON_BOUNDARY, ON_BOUNDARY]
	assert_array(_chain(IDLE, events)).is_equal(ahead)
	assert_array(_chain(FINISHED, [ON_STOP])).is_equal([Vector2i(IDLE, DISCARD)])


## resolve_mode() over every mode and (threads, web, headless): AUTO is WORKER only with threads,
## off the web and not headless, so the scene tests stay synchronous; SYNC and WORKER stay as asked;
## anything else is SYNC. mode_after_start(): any error from Thread.start() makes WORKER SYNC. A
## runner with AUTO started here (headless) ticks inline and starts no thread.
func test_resolve_mode_and_mode_after_start() -> void:
	assert_array([SYNC, WORKER, AUTO]).is_equal([0, 1, 2])
	var auto: Array[int] = []
	for threads: bool in [false, true]:
		for web: bool in [false, true]:
			for headless: bool in [false, true]:
				auto.append(MatchRunner.resolve_mode(AUTO, threads, web, headless))
				var asked: Array[int] = [
					MatchRunner.resolve_mode(SYNC, threads, web, headless),
					MatchRunner.resolve_mode(WORKER, threads, web, headless),
					MatchRunner.resolve_mode(3, threads, web, headless),
				]
				assert_array(asked).is_equal([SYNC, WORKER, SYNC])
	assert_array(auto).is_equal(AUTO_RESOLVED)
	var after: Array[int] = [
		MatchRunner.mode_after_start(WORKER, OK),
		MatchRunner.mode_after_start(WORKER, ERR_CANT_CREATE),
		MatchRunner.mode_after_start(WORKER, FAILED),
		MatchRunner.mode_after_start(SYNC, OK),
		MatchRunner.mode_after_start(SYNC, ERR_CANT_CREATE),
	]
	assert_array(after).is_equal([WORKER, SYNC, SYNC, SYNC, SYNC])
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(runner.tick_mode).is_equal(SYNC)
	runner = _runner(AUTO)
	runner._process(1.0 / 15.0)
	assert_array([runner.snapshot.tick, runner.job_in_flight(), runner.worker_active()]).is_equal(
		[1, false, false]
	)


## A WORKER runner and a SYNC runner on the arena, driven by the same jittered 60 fps frames, with
## wait_idle() after every frame of the WORKER runner: this case compares values (the overlap case
## is P38w2's). At every published tick up to 300 every snapshot field but the timings (the arrays,
## both prev_pos_*, prev_proj_*, events, stats, the header and the fog copy) is equal, and both
## replays hold the checkpoints of a pure MatchLoop run. `ticked` comes once per tick, in order, on
## the main thread, with no job in flight and the World at that tick. Every published snapshot is
## a new object with its post and end times set, and still holds its tick at the end. Never two
## jobs: the gated probe saw no job begin before the one before it ended, and never more jobs than
## the published tick plus one. With the GDScript twins and with the native kernels.
func test_a_worker_runner_publishes_what_a_sync_runner_does_tick_by_tick() -> void:
	var expected: PackedInt64Array = _pure_checkpoints(TICKS)
	assert_int(expected.size()).is_equal(TICKS / 15)
	for impl: int in [MatchRunner.SimImpl.GDSCRIPT, MatchRunner.SimImpl.NATIVE]:
		_assert_lockstep(impl, expected)


## The WORKER clock keeps the part of a tick at each boundary, as the SYNC clock does (ADR 0012
## section 1). A SYNC and a WORKER runner on the arena play the same steady 17 ms frames, with
## wait_idle() after every frame of the WORKER runner, so no boundary is held. The WORKER runner
## trails by 0 or 1 tick at every frame, never more, because only its refill frame does not move
## its clock: after 600 frames SYNC has published tick 153 and WORKER tick 152, with 0.745 of a
## tick on its clock. A clock that dropped the part of a tick at each boundary would trail by 4. A
## negative frame does not move the WORKER clock.
func test_the_worker_clock_keeps_the_part_of_a_tick_like_the_sync_clock() -> void:
	var sync: MatchRunner = _runner(SYNC)
	var worker: MatchRunner = _runner(WORKER)
	var lags: Vector2i = Vector2i.ZERO
	var waited: bool = true
	var frames: int = 0
	while frames < STEADY_FRAMES and waited:
		sync._process(STEADY)
		worker._process(STEADY)
		frames += 1
		waited = worker.wait_idle()
		var lag: int = sync.snapshot.tick - worker.snapshot.tick
		lags = Vector2i(mini(lags.x, lag), maxi(lags.y, lag))
	assert_array([waited, lags, sync.snapshot.tick, worker.snapshot.tick]).is_equal(
		[true, Vector2i(0, 1), 153, 152]
	)
	var part: float = worker.alpha()
	assert_float(part).is_equal_approx(0.745, 0.000001)
	worker._process(-1.0)
	assert_array([worker.snapshot.tick, worker.alpha()]).is_equal([152, part])


## With a gated probe holding job N + 1 from its begin(), the frame that publishes tick N has
## posted it: N + 1 jobs began, one is in flight, and the snapshot is still tick N. That is frame
## 1 + 4N of quarter-tick frames, because the refill frame does not move the clock. Its boundary is
## held: frames publish nothing, start no job and keep alpha() at 1.0. After the release and
## wait_idle() the World is one tick ahead of the snapshot, and the next frame publishes it; the
## clock stopped at the held boundary, so the frame after that publishes nothing.
func test_the_worker_runs_one_tick_ahead_and_holds_a_boundary_while_its_job_runs() -> void:
	var gated: SimProbe = _gated_probe()
	gated.hold(AHEAD + 1)
	var runner: MatchRunner = _runner(WORKER, gated)
	assert_bool(runner.worker_active()).is_false()
	var frames: int = 0
	while runner.snapshot.tick < AHEAD and frames < 100:
		runner._process(FRAME)
		frames += 1
		if runner.snapshot.tick < AHEAD:
			assert_bool(runner.wait_idle()).is_true()
	assert_array([runner.snapshot.tick, frames]).is_equal([AHEAD, 1 + 4 * AHEAD])
	assert_bool(gated.wait_blocked()).is_true()
	assert_array([gated.begin_count, runner.job_in_flight(), runner.worker_active()]).is_equal(
		[AHEAD + 1, true, true]
	)
	# The worker owns the World now: the rule for the runner's state refuses the main thread. The
	# getter itself is not called, so nothing is logged.
	assert_bool(MatchRunner.shared_access_allowed(runner._mode, runner._state)).is_false()
	var held: MatchSnapshot = runner.snapshot
	for _frame: int in 8:
		runner._process(FRAME)
	assert_bool(is_same(runner.snapshot, held)).is_true()
	assert_float(runner.alpha()).is_equal(1.0)
	assert_array([gated.begin_count, runner.job_in_flight()]).is_equal([AHEAD + 1, true])
	gated.release()
	assert_bool(runner.wait_idle()).is_true()
	assert_bool(MatchRunner.shared_access_allowed(runner._mode, runner._state)).is_true()
	assert_array([runner.world.tick, runner.snapshot.tick]).is_equal([AHEAD + 1, AHEAD])
	assert_bool(runner.job_in_flight()).is_false()
	runner._process(FRAME)
	assert_array([runner.snapshot.tick, runner.job_in_flight()]).is_equal([AHEAD + 1, true])
	assert_bool(runner.wait_idle()).is_true()
	# The clock stopped at the held boundary, so no time owed from the hold publishes now.
	runner._process(FRAME)
	assert_int(runner.snapshot.tick).is_equal(AHEAD + 1)
	assert_array([gated.begin_count, gated.gave_up, gated.overlapped]).is_equal(
		[AHEAD + 2, false, false]
	)


## start() while a job runs (its probe delays it 30 ms) waits for the job and drops it: no `ticked`,
## the tick-0 snapshot of the second match, nothing in flight, and the old World freed at once. The
## new match's ticks come 1 to 15 and its tick-15 hash is a fresh run's, with every job still
## delayed, so a token left over from the dropped job would publish a job that is still running.
func test_start_during_a_job_waits_for_it_and_drops_it() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	var seen: Array[int] = []
	runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	var old: WeakRef = weakref(runner.world)
	runner._process(FRAME)
	assert_bool(runner.job_in_flight()).is_true()
	runner.start()
	assert_bool(runner.job_in_flight()).is_false()
	# The dropped job keeps nothing of the old match.
	assert_object(old.get_ref()).is_null()
	var state: Array = [runner.snapshot.tick, runner.match_serial, runner.world.tick]
	assert_array(state + [seen.size(), gated.begin_count]).is_equal([0, 2, 0, 0, 1])
	gated.delay(SHORT_DELAY_MSEC)
	var frames: int = 0
	while runner.snapshot.tick < 15 and frames < 100:
		runner._process(FRAME)
		frames += 1
		assert_bool(runner.wait_idle()).is_true()
	assert_array(seen).is_equal(range(1, 16))
	var fresh: PackedInt64Array = _pure_checkpoints(15)
	assert_array([runner.last_hash, runner.snapshot.last_hash]).is_equal([fresh[0], fresh[0]])
	assert_array([gated.begin_count, gated.overlapped]).is_equal([17, false])


## run_ticks(5) in WORKER mode advances the published tick by exactly 5 from each state: a job in
## flight (delayed 30 ms) is waited for and published as the first tick, a finished one is
## published without a wait, and from IDLE all five run inline. Every tick runs once and is
## published once, in order, and tick 15 has a fresh run's hash. run_ticks(0) does nothing, with a
## job in flight, with a finished one and from IDLE.
func test_run_ticks_in_worker_mode_advances_the_published_tick_by_exactly_n() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	var seen: Array[int] = []
	runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	runner._process(FRAME)
	assert_bool(runner.job_in_flight()).is_true()
	runner.run_ticks(0)
	assert_array([runner.snapshot.tick, runner.job_in_flight()]).is_equal([0, true])
	runner.run_ticks(5)
	assert_array(_published(runner)).is_equal([5, 5, false])
	gated.delay(0)
	runner._process(FRAME)
	assert_bool(runner.wait_idle()).is_true()
	assert_array(_published(runner)).is_equal([5, 6, false])
	runner.run_ticks(0)
	assert_array(_published(runner)).is_equal([5, 6, false])
	runner.run_ticks(5)
	assert_array(_published(runner)).is_equal([10, 10, false])
	runner.run_ticks(5)
	runner.run_ticks(0)
	assert_array(_published(runner)).is_equal([15, 15, false])
	assert_array(seen).is_equal(range(1, 16))
	assert_int(runner.last_hash).is_equal(_pure_checkpoints(15)[0])
	assert_array([gated.begin_count, gated.overlapped]).is_equal([15, false])


## A frame takes the finished job's `done` token itself (FRAME_TAKEN), with no wait_idle(): frames
## of zero length run while the job is in flight, capped like wait_idle(). The clock does not move,
## so nothing is published. start() then drops the finished job without a wait: the second match's
## tick-0 snapshot, no `ticked`, nothing in flight and the old World freed.
func test_a_frame_takes_the_token_and_start_drops_the_finished_job_without_a_wait() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(SHORT_DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	var seen: Array[int] = []
	runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	runner._process(FRAME)
	assert_bool(runner.job_in_flight()).is_true()
	var until: int = Time.get_ticks_msec() + MatchRunner.WAIT_CAP_MSEC
	while runner.job_in_flight() and Time.get_ticks_msec() < until:
		runner._process(0.0)
	assert_bool(runner.job_in_flight()).is_false()
	assert_array([runner.snapshot.tick, runner.world.tick]).is_equal([0, 1])
	var old: WeakRef = weakref(runner.world)
	runner.start()
	assert_object(old.get_ref()).is_null()
	var state: Array = [runner.match_serial, runner.snapshot.tick, runner.world.tick]
	assert_array(state + [runner.job_in_flight(), seen.size()]).is_equal([2, 0, 0, false, 0])


## A command submitted before the first frame (the refill drains it) and commands submitted in
## `ticked(3)`, `ticked(7)` and `ticked(14)` get the same stamps in WORKER as in SYNC: 0, 3, 7 and
## 14, because a boundary publishes and emits `ticked` before it drains (ADR 0012 section 1). The
## replays and their checkpoints are equal. The two runners run one after the other, because the
## CommandQueue is an autoload.
func test_commands_get_the_same_stamps_in_both_modes() -> void:
	var stamps: Array = []
	var logs: Array[PackedInt32Array] = []
	var hashes: Array[PackedInt64Array] = []
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode)
		var sent: Array[Command] = [Command.move(1, PackedInt32Array([1, 2]), 20500, 30500)]
		CommandQueue.submit(sent[0])
		runner.ticked.connect(
			func(tick: int) -> void:
				if tick in [3, 7, 14]:
					sent.append(
						Command.move(1, PackedInt32Array([1, 2]), 20500 + tick * 500, 30500)
					)
					CommandQueue.submit(sent[-1])
		)
		assert_bool(_play_to(runner, 30)).is_true()
		stamps.append(sent.map(func(command: Command) -> int: return command.tick))
		logs.append(runner.replay.commands.duplicate())
		hashes.append(runner.replay.checkpoint_hashes.duplicate())
	assert_array(stamps).is_equal([[0, 3, 7, 14], [0, 3, 7, 14]])
	assert_array(logs[1]).is_equal(logs[0])
	assert_array(hashes[1]).is_equal(hashes[0])


## A `ticked` handler that switches a WORKER runner to SYNC and restarts the match: the boundary
## posts no job after the handler, so none is in flight once that frame returns and no job runs on
## the worker beside the inline ticks. The new match publishes ticks 1 to 15 with a fresh run's
## hash.
func test_a_ticked_handler_that_restarts_in_sync_mode_gets_no_job_posted() -> void:
	var runner: MatchRunner = _runner(WORKER)
	var seen: Array[int] = []
	runner.ticked.connect(
		func(tick: int) -> void:
			seen.append(tick)
			if tick == 2 and runner.match_serial == 1:
				runner.tick_mode = SYNC
				runner.start()
	)
	var frames: int = 0
	while runner.match_serial == 1 and frames < 100:
		runner._process(FRAME)
		frames += 1
		if runner.match_serial == 1:
			assert_bool(runner.wait_idle()).is_true()
	assert_array([runner.match_serial, runner.snapshot.tick, runner.job_in_flight()]).is_equal(
		[2, 0, false]
	)
	assert_bool(runner.wait_idle()).is_true()
	while runner.snapshot.tick < 15 and frames < 200:
		runner._process(FRAME)
		frames += 1
	assert_array(seen).is_equal([1, 2] + range(1, 16))
	assert_int(runner.last_hash).is_equal(_pure_checkpoints(15)[0])


## A `ticked(2)` handler that calls run_ticks(1) in WORKER mode: the boundary is IDLE inside the
## handler, with no job in flight and none finished, so tick 3 runs inline and is published with
## its own `ticked`, and the boundary posts job 4 after the handler. Ticks 1 to 15 arrive once
## each, in order, and tick 15 has a fresh run's hash.
func test_a_ticked_handler_that_calls_run_ticks_plays_the_tick_inline() -> void:
	var runner: MatchRunner = _runner(WORKER)
	var seen: Array[int] = []
	runner.ticked.connect(
		func(tick: int) -> void:
			seen.append(tick)
			if tick == 2:
				runner.run_ticks(1)
	)
	assert_bool(_play_to(runner, 15)).is_true()
	assert_array(seen).is_equal(range(1, 16))
	assert_int(runner.last_hash).is_equal(_pure_checkpoints(15)[0])


## Leaving the tree joins the worker (ADR 0012 section 1, stop): the job in flight is waited for
## and dropped, so the World has played a tick that is never published (why a WORKER runner must
## not leave the tree during a match). Back in the tree, start() begins a new match whose first
## job starts a new worker: it publishes ticks 1 to 3 in order, and leaving again joins it.
func test_leaving_the_tree_joins_the_worker_and_a_restart_starts_a_new_one() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	add_child(runner)
	runner._process(FRAME)
	assert_array([runner.job_in_flight(), runner.worker_active()]).is_equal([true, true])
	remove_child(runner)
	assert_array([runner.job_in_flight(), runner.worker_active()]).is_equal([false, false])
	assert_array([runner.snapshot.tick, runner.world.tick]).is_equal([0, 1])
	add_child(runner)
	gated.delay(0)
	runner.start()
	var seen: Array[int] = []
	runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	assert_bool(_play_to(runner, 3)).is_true()
	assert_array([seen, runner.worker_active()]).is_equal([[1, 2, 3], true])
	remove_child(runner)
	assert_array([runner.job_in_flight(), runner.worker_active()]).is_equal([false, false])
	assert_array([gated.begin_count, gated.overlapped]).is_equal([5, false])


## The lockstep of the WORKER and the SYNC runner with `impl` (see the case above).
func _assert_lockstep(impl: int, expected: PackedInt64Array) -> void:
	var label: String = "impl %d" % impl
	var gated: SimProbe = _gated_probe()
	var sync: MatchRunner = _runner(SYNC, null, impl)
	var worker: MatchRunner = _runner(WORKER, gated, impl)
	var runners: Array[MatchRunner] = [sync, worker]
	var pending: Array[Dictionary] = [{}, {}]
	var ticks: Array = [[], []]
	var kept: Array = [[], []]
	var problems: Array[String] = []
	for side: int in runners.size():
		var runner: MatchRunner = runners[side]
		runner.ticked.connect(
			func(tick: int) -> void: _arrive(runner, side, tick, pending, ticks, kept, problems)
		)
	var frames: int = 0
	var over: int = 0
	while (sync.snapshot.tick < TICKS or worker.snapshot.tick < TICKS) and frames < 3 * TICKS * 4:
		var delta: float = FRAMES[frames % FRAMES.size()]
		frames += 1
		if sync.snapshot.tick < TICKS:
			sync._process(delta)
		if worker.snapshot.tick < TICKS:
			worker._process(delta)
			if not worker.wait_idle():
				problems.append("wait_idle failed at frame %d" % frames)
				break
			if gated.begin_count > worker.snapshot.tick + 1:
				over += 1
	assert_array(problems).override_failure_message(label + str(problems)).is_empty()
	assert_array([sync.snapshot.tick, worker.snapshot.tick, worker.world.tick]).is_equal(
		[TICKS, TICKS, TICKS + 1]
	)
	assert_array(pending[0].keys() + pending[1].keys()).is_empty()
	for side: int in 2:
		assert_array(ticks[side]).override_failure_message(label).is_equal(range(1, TICKS + 1))
		var objects: Dictionary[int, int] = {}
		var held: Array[int] = []
		for snap: MatchSnapshot in kept[side]:
			objects[snap.get_instance_id()] = snap.tick
			held.append(snap.tick)
		assert_array(held).override_failure_message(label).is_equal(range(1, TICKS + 1))
		assert_int(objects.size()).override_failure_message(label).is_equal(TICKS)
	assert_array([over, gated.begin_count, gated.overlapped]).is_equal([0, TICKS + 1, false])
	for runner: MatchRunner in runners:
		assert_array(runner.replay.checkpoint_hashes).override_failure_message(label).is_equal(
			expected
		)
		var native: bool = runner.world.native_phases != 0
		assert_bool(native).override_failure_message(label).is_equal(
			impl == MatchRunner.SimImpl.NATIVE
		)
	var names: Array = _state_of(sync.snapshot).keys()
	assert_array(names).contains(["pos_x", "prev_pos_y", "prev_proj_x", "events", "stats"])
	assert_array(names).contains(["tick", "last_hash", "target_row", "fog.visible", "fog.explored"])
	assert_array(names).not_contains(["job_usec", "fog"])


## A `ticked(tick)` of runner `side` (0 SYNC, 1 WORKER): keeps the snapshot, checks the thread, that
## no job is in flight, that the World and the snapshot are at `tick` and the snapshot's post and
## end times, then compares the snapshot with the other runner's of the same tick, or keeps its
## values until that one arrives.
func _arrive(
	runner: MatchRunner,
	side: int,
	tick: int,
	pending: Array[Dictionary],
	ticks: Array,
	snaps: Array,
	problems: Array[String]
) -> void:
	ticks[side].append(tick)
	snaps[side].append(runner.snapshot)
	var where: String = "side %d tick %d: " % [side, tick]
	if OS.get_thread_caller_id() != _main_thread:
		problems.append(where + "ticked off the main thread")
	if runner.job_in_flight() or runner.world.tick != tick or runner.snapshot.tick != tick:
		problems.append(where + "a job in flight, or the World or the snapshot at another tick")
	if runner.snapshot.post_usec <= 0 or runner.snapshot.end_usec < runner.snapshot.post_usec:
		problems.append(where + "no post time, or an end time before it")
	var state: Dictionary = _state_of(runner.snapshot)
	var other: Dictionary = pending[1 - side]
	if not other.has(tick):
		pending[side][tick] = state
		return
	var kept: Dictionary = other[tick]
	other.erase(tick)
	if kept.keys() != state.keys():
		problems.append(where + "other fields")
	for name: String in state:
		if kept.get(name) != state[name]:
			problems.append(where + name)


## Every script field of `snap` but the timings, by name, with its fog's fields as "fog.<name>".
## A published snapshot is never written, so the values are kept as they are.
func _state_of(snap: MatchSnapshot) -> Dictionary:
	var state: Dictionary = {}
	for property: Dictionary in snap.get_property_list():
		var name: StringName = property["name"]
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or TIMINGS.has(name):
			continue
		if name != &"fog":
			state[String(name)] = snap.get(name)
			continue
		for field: Dictionary in snap.fog.get_property_list():
			if field["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
				state["fog." + String(field["name"])] = snap.fog.get(field["name"])
	return state


## The published tick, the World's tick and whether a job is in flight; the World only after
## wait_idle() or with none in flight.
func _published(runner: MatchRunner) -> Array:
	return [runner.snapshot.tick, runner.world.tick, runner.job_in_flight()]


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


## The states and steps hand_off() gives for `events` in turn, from `state`.
func _chain(state: int, events: Array[int]) -> Array[Vector2i]:
	var steps: Array[Vector2i] = []
	for event: int in events:
		var step: Vector2i = MatchRunner.hand_off(state, event)
		steps.append(step)
		state = step.x
	return steps


## A started runner on the seed-42 arena in `mode`, with `probe` installed before start().
func _runner(
	mode: int, probe: SimProbe = null, impl: int = MatchRunner.SimImpl.GDSCRIPT
) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.sim_impl = impl
	runner.probe = probe
	runner.start()
	_runners.append(runner)
	return runner


func _gated_probe() -> SimProbe:
	var probe: SimProbe = GatedProbe.new()
	_probes.append(probe)
	return probe


## The checkpoint hashes of `ticks` ticks of the seed-42 arena through MatchLoop alone.
func _pure_checkpoints(ticks: int) -> PackedInt64Array:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	var none: Array[Command] = []
	for _tick: int in ticks:
		loop.step(world, none)
	return loop.replay.checkpoint_hashes
