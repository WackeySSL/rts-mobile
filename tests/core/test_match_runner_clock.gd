extends GdUnitTestSuite
## MatchRunner in WORKER mode, part 2 (plan P38w2, ADR 0012 section 1): the clock, the held and
## late ticks, and the slow-worker cases. The clock publishes at most once per frame and drops the
## whole ticks still owed after it, keeping the part of a tick; it is at 0 after every refill and
## resume, and those frames do not advance it; it stops at a held boundary and restarts at 0 in the
## frame that publishes the held job. held_ticks counts each held job once, late_ticks the jobs
## whose post-to-done time is above TICK_USEC, latency_usec_max the largest such time, and start()
## resets the three.
##
## The runners are built the Phase 1 way (auto_free, never in the tree) on the seed-42 perf arena
## and set WORKER explicitly, the exception to "headless tests run SYNC". Every runner has a gated
## probe installed (a plain one unless the case sets up its own), and after_test asserts of every
## probe that no job began before the one before it ended and that no hold reached its cap. A test
## frame is a direct _process(delta) call: it moves the clock by `delta` but costs microseconds,
## while a job takes real milliseconds. So every case that asserts held_ticks 0, one publish per
## boundary or a hash per published tick calls wait_idle() after each frame, and its result depends
## on the clock rule only, never on the machine's speed. A late or not-late count that a case is
## about never rests on a fast job's real time: the late-count and held cases write the timings
## into the finished job's snapshot after wait_idle() and before the frame that publishes it, and
## the late, counter and forced-slow cases delay a job far past the period. late_ticks 0 for real
## fast jobs is asserted only where the plan names it (the first frame, the hitch), with more than
## 50 ms of margin (a fast arena job takes a few ms). Only the overlap, held, pause-during-a-hold,
## late, counter and forced-slow cases make the gated probe hold or delay a job on purpose. The
## cases wait only through wait_idle(), the probe's capped wait_blocked() and frame loops capped at
## WAIT_CAP_MSEC, never a fixed sleep or a wall-clock spin, and fail when a wait returns false;
## after_test releases every gated probe and then waits for every runner, so a case that fails
## while a probe holds a job still leaves the worker free.

const GatedProbe: GDScript = preload("res://tests/core/gated_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42
## A frame of exactly a quarter tick, one of exactly a tick, and 60 fps frames with jitter, each
## under a tick (two ticks per 8 frames), used in turn.
const FRAME: float = 1.0 / 60.0
const TICK: float = 1.0 / 15.0
const FRAMES: Array[float] = [0.0167, 0.0121, 0.0213, 0.0158, 0.0175, 0.0098, 0.0236, 0.0166]
## The long frame (15 ticks), the first frame after start() (3 ticks) and a hitch (2.25 ticks).
const LONG: float = 1.0
const FIRST: float = 0.2
const HITCH: float = 0.15
## The post-to-done time the held case writes into its held job (10 ms, far under the tick period,
## so the job is not late however long the hold lasted), and how many frames it runs while the
## job is held past its boundary.
const HOLD_USEC: int = 10_000
const HOLD_FRAMES: int = 8
## The late-count case writes every job's post this long before the frames that reach its
## boundary, so a publish comes far more than a period after its post.
const POSTED_AGO_USEC: int = 500_000
## A job delayed this long is late (more than a period after its post); the forced-slow cases
## delay every job by SLOW_MSEC, also more than a period, for SLOW_TICKS published ticks.
const LATE_MSEC: int = 100
const SLOW_MSEC: int = 80
const SLOW_TICKS: int = 30
## The tick of the published snapshot the overlap case holds the next job after.
const AHEAD: int = 5
## The memory case reads the monitor at these published ticks; the static memory may grow by at
## most MEMORY_BOUND bytes between them. Measured: about -1 KB; a runner that kept every published
## snapshot grew by about 23 MB (about 29 KB per tick).
const MEMORY_FROM: int = 100
const MEMORY_TO: int = 900
const MEMORY_BOUND: float = 1_000_000.0
## The target_y of the commands a case submits per frame, so they can be told from the scenario's
## orders in the replay.
const MARK_Y: int = 30500
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER

var _runners: Array[MatchRunner] = []
var _probes: Array[SimProbe] = []


func after_test() -> void:
	for probe: SimProbe in _probes:
		probe.release()
	for runner: MatchRunner in _runners:
		if is_instance_valid(runner):
			assert_bool(runner.wait_idle()).is_true()
	for probe: SimProbe in _probes:
		assert_array([probe.overlapped, probe.gave_up]).is_equal([false, false])
	_probes.clear()
	_runners.clear()
	CommandQueue.clear()


## A long frame mid-run, with the clock half a tick into the period: it owes 15.5 ticks, publishes
## exactly one and keeps the half tick, so the next boundary comes two quarter-tick frames later
## and then one every four, with no burst. The owed ticks are dropped, not held: held_ticks stays
## 0. Every published tick has the state hash a SYNC runner has at that tick.
func test_a_long_frame_publishes_one_tick_and_drops_the_whole_ticks_owed() -> void:
	var runner: MatchRunner = _runner(WORKER)
	var hashes: Array[int] = []
	runner.ticked.connect(func(_tick: int) -> void: hashes.append(runner.world.state_hash()))
	assert_bool(_play_to(runner, 3)).is_true()
	var deltas: Array[float] = [FRAME, FRAME, LONG]
	deltas.append_array(_quarters(10))
	assert_array(_frames(runner, deltas)).is_equal([3, 3, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7])
	assert_int(runner.held_ticks).is_equal(0)
	assert_array(hashes).is_equal(_sync_hashes(7))


## The first frame after start() is the refill: it posts the first job with the clock at 0 and does
## not advance it, so its 0.2 s (three ticks) are dropped and tick 1 comes on the fourth
## quarter-tick frame after it. Nothing is held and nothing is late.
func test_the_first_frame_refills_without_advancing_the_clock() -> void:
	var runner: MatchRunner = _runner(WORKER)
	var deltas: Array[float] = [FIRST]
	deltas.append_array(_quarters(8))
	assert_array(_frames(runner, deltas)).is_equal([0, 0, 0, 0, 1, 1, 1, 1, 2])
	assert_array([runner.held_ticks, runner.late_ticks]).is_equal([0, 0])


## run_ticks(2) mid-run, with the clock half a tick into the period, leaves the runner IDLE: the
## next frame refills, which sets the clock to 0 and does not advance it, so the first boundary
## after it comes on the fourth quarter-tick frame (a refill that kept the half tick would publish
## on the second).
func test_the_refill_after_run_ticks_restarts_the_clock_at_zero() -> void:
	var runner: MatchRunner = _runner(WORKER)
	assert_bool(_play_to(runner, 1)).is_true()
	assert_array(_frames(runner, _quarters(2))).is_equal([1, 1])
	runner.run_ticks(2)
	assert_array([runner.snapshot.tick, runner.job_in_flight()]).is_equal([3, false])
	assert_array(_frames(runner, _quarters(9))).is_equal([3, 3, 3, 3, 4, 4, 4, 4, 5])
	assert_int(runner.held_ticks).is_equal(0)


## A 0.15 s hitch among 60 fps frames, a quarter tick into the period: the hitch frame publishes
## exactly one tick and keeps the half tick, so the next boundary comes two frames later. Nothing
## is held and nothing is late.
func test_a_hitch_publishes_one_tick_and_keeps_the_part_of_a_tick() -> void:
	var runner: MatchRunner = _runner(WORKER)
	assert_bool(_play_to(runner, 1)).is_true()
	var deltas: Array[float] = [FRAME, HITCH]
	deltas.append_array(_quarters(6))
	assert_array(_frames(runner, deltas)).is_equal([1, 2, 2, 3, 3, 3, 3, 4])
	assert_array([runner.held_ticks, runner.late_ticks]).is_equal([0, 0])


## The clock restarts at 0 on a resume (ADR 0012 section 1). A pause before the first frame: the
## first frame after it is the refill, which also uses up the resume, so tick 1 comes on the fourth
## quarter-tick frame after it (a refill that left the resume to the next frame would make it the
## fifth). `paused` half a tick into the period: the paused frames do nothing (the job in flight
## finishes, nothing is published), and the first frame after the pause sets the clock to 0
## without advancing it, so the next boundary comes four quarter-tick frames after it. A command
## submitted during that pause is drained at that boundary and stamped 3, one tick after the stamp
## SYNC gives it (2): the job in flight at the pause drained the queue before the pause, so a
## mid-run pause keeps the one-tick WORKER input latency. An application pause has no frames at
## all: the first frame after RESUMED carries the background time (about 0.14 s, two ticks) and
## also only restarts the clock.
func test_a_resume_restarts_the_clock_at_zero() -> void:
	var runner: MatchRunner = _runner(WORKER)
	runner.paused = true
	assert_array(_frames(runner, _quarters(3))).is_equal([0, 0, 0])
	runner.paused = false
	assert_array(_frames(runner, _quarters(5))).is_equal([0, 0, 0, 0, 1])
	assert_bool(_play_to(runner, 2)).is_true()
	assert_array(_frames(runner, _quarters(2))).is_equal([2, 2])
	runner.paused = true
	var command: Command = Command.move(1, PackedInt32Array([1, 2]), 20500, MARK_Y)
	CommandQueue.submit(command)
	assert_array(_frames(runner, _quarters(3))).is_equal([2, 2, 2])
	runner.paused = false
	assert_array(_frames(runner, _quarters(5))).is_equal([2, 2, 2, 2, 3])
	assert_int(command.tick).is_equal(3)
	assert_array(_frames(runner, _quarters(2))).is_equal([3, 3])
	runner.notification(NOTIFICATION_APPLICATION_PAUSED)
	runner.notification(NOTIFICATION_APPLICATION_RESUMED)
	var deltas: Array[float] = [0.14]
	deltas.append_array(_quarters(4))
	assert_array(_frames(runner, deltas)).is_equal([3, 3, 3, 3, 4])
	assert_int(runner.held_ticks).is_equal(0)


## A job held past its boundary is held, not late: held_ticks 1 however many frames the hold lasts,
## alpha() 1.0 and the snapshot unchanged during the hold, and late_ticks 0 for a held job whose
## post-to-done time is 10 ms (HOLD_USEC), as for one released 10 ms after its post: the case
## writes that time into the job's snapshot after wait_idle(), so the count rests on the timings
## and not on how long the hold took on this machine. The frame after the release publishes it and
## restarts the clock at 0, so the next publish comes one full period (four quarter-tick frames)
## later, with no catch-up burst.
func test_a_held_boundary_counts_one_held_tick_and_is_not_late() -> void:
	var gated: SimProbe = _gated_probe()
	gated.hold(3)
	var runner: MatchRunner = _runner(WORKER, gated)
	assert_bool(_play_to(runner, 2, false)).is_true()
	assert_bool(gated.wait_blocked()).is_true()
	# Jobs 1 and 2 were published before the hold; only the held job's count is read, from before
	# the frames that reach its boundary.
	var late: int = runner.late_ticks
	var held: MatchSnapshot = runner.snapshot
	for _frame: int in 4:
		runner._process(FRAME)
	assert_array([runner.held_ticks, runner.alpha(), runner.job_in_flight()]).is_equal(
		[1, 1.0, true]
	)
	var moved: int = 0
	for _frame: int in HOLD_FRAMES:
		runner._process(FRAME)
		if runner.held_ticks != 1 or runner.alpha() != 1.0 or not is_same(runner.snapshot, held):
			moved += 1
	assert_array([moved, runner.late_ticks - late]).is_equal([0, 0])
	gated.release()
	assert_bool(runner.wait_idle()).is_true()
	var done: MatchSnapshot = runner._job.snapshot
	done.post_usec = done.end_usec - HOLD_USEC
	runner._process(FRAME)
	var counts: Array = [runner.snapshot.tick, runner.held_ticks, runner.late_ticks - late]
	assert_array(counts).is_equal([3, 1, 0])
	assert_int(runner.latency_usec_max).is_greater_equal(HOLD_USEC)
	assert_array(_frames(runner, _quarters(8))).is_equal([3, 3, 3, 4, 4, 4, 4, 5])
	assert_array([runner.held_ticks, gated.gave_up]).is_equal([1, false])


## A pause during a hold (ADR 0012 section 1): the held job finishes while paused, and the first
## frame after the pause is both the resume frame and the frame that ends the hold. It publishes
## the held job with the clock at 0, does not advance it and uses up the resume, so the next publish
## comes on the fourth quarter-tick frame after it (a resume left to the next frame would make it
## the fifth), and held_ticks stays 1.
func test_a_pause_during_a_hold_ends_in_the_first_frame_after_it() -> void:
	var gated: SimProbe = _gated_probe()
	gated.hold(3)
	var runner: MatchRunner = _runner(WORKER, gated)
	assert_bool(_play_to(runner, 2, false)).is_true()
	assert_bool(gated.wait_blocked()).is_true()
	for _frame: int in 4:
		runner._process(FRAME)
	assert_array([runner.held_ticks, runner.alpha()]).is_equal([1, 1.0])
	runner.paused = true
	for _frame: int in 2:
		runner._process(FRAME)
	gated.release()
	assert_bool(runner.wait_idle()).is_true()
	runner.paused = false
	assert_array(_frames(runner, _quarters(6))).is_equal([3, 3, 3, 3, 4, 4])
	assert_int(runner.held_ticks).is_equal(1)


## late_ticks and latency_usec_max read a job's post-to-done time, end_usec - post_usec, and a job
## is late only when that is above TICK_USEC. The case writes both timings into every finished
## job's snapshot after wait_idle() and before its boundary: the post POSTED_AGO_USEC (0.5 s)
## before the frames that reach the boundary, so the publish comes far more than a period after
## the post while the job's own run time is far under one, and post-to-done times of 40 ms,
## exactly TICK_USEC, TICK_USEC + 1 and 5 ms in turn. start() reset the counts and every published
## job is one of the four, so no count depends on the machine's speed.
func test_a_late_tick_is_counted_from_its_post_to_done_time() -> void:
	var runner: MatchRunner = _runner(WORKER)
	runner._process(FRAME)
	var tick_usec: int = MatchRunner.TICK_USEC
	var counts: Array[Array] = []
	for span: int in [40_000, tick_usec, tick_usec + 1, 5_000]:
		assert_bool(runner.wait_idle()).is_true()
		var done: MatchSnapshot = runner._job.snapshot
		done.post_usec = Time.get_ticks_usec() - POSTED_AGO_USEC
		done.end_usec = done.post_usec + span
		var tick: int = runner.snapshot.tick
		assert_array(_frames(runner, _quarters(4))).is_equal([tick, tick, tick, tick + 1])
		counts.append([runner.late_ticks, runner.latency_usec_max])
	var expected: Array = [[0, 40_000], [0, tick_usec], [1, tick_usec + 1], [1, tick_usec + 1]]
	assert_array(counts).is_equal(expected)


## A job delayed 100 ms is late: its post-to-done time is above TICK_USEC (the period from
## Sim.TICK_RATE, 66 666 us). late_ticks counts it once at its publish and latency_usec_max keeps
## its time after faster jobs. wait_idle() after every frame means no boundary is held. The same
## holds for an inline tick of a SYNC runner.
func test_a_job_slower_than_a_tick_is_late() -> void:
	@warning_ignore("integer_division")
	var period: int = 1_000_000 / Sim.TICK_RATE
	assert_array([MatchRunner.TICK_USEC, period]).is_equal([66666, 66666])
	var gated: SimProbe = _gated_probe()
	var runner: MatchRunner = _runner(WORKER, gated)
	assert_bool(_play_to(runner, 2)).is_true()
	# Job 3 has finished; job 4, posted at the publish of tick 3, is delayed.
	gated.delay(LATE_MSEC)
	assert_array(_frames(runner, _quarters(4))).is_equal([2, 2, 2, 3])
	gated.delay(0)
	# Only the delayed job's count is read: the fast ones are far under the period.
	var late: int = runner.late_ticks
	assert_array(_frames(runner, _quarters(4))).is_equal([3, 3, 3, 4])
	assert_array([runner.late_ticks - late, runner.held_ticks]).is_equal([1, 0])
	assert_array(_frames(runner, _quarters(4))).is_equal([4, 4, 4, 5])
	assert_int(runner.latency_usec_max).is_greater_equal(LATE_MSEC * 1000)
	# An inline tick counts too: its post is the start of its run.
	var slow: SimProbe = _gated_probe()
	var sync: MatchRunner = _runner(SYNC, slow)
	sync.run_ticks(1)
	late = sync.late_ticks
	slow.delay(LATE_MSEC)
	sync.run_ticks(1)
	slow.delay(0)
	var inline: Array = [sync.snapshot.tick, sync.late_ticks - late, sync.held_ticks]
	assert_array(inline + [sync.latency_usec_max >= LATE_MSEC * 1000]).is_equal([2, 1, 0, true])


## start() resets held_ticks, late_ticks and latency_usec_max: job 1 delayed 100 ms is published
## late, and job 2 is held past its boundary. start() while job 2 is still held (released and
## waited for, but not published) drops it and starts from 0, and the hold ends with it: the refill
## posts the next job and the first boundary comes on the fourth quarter-tick frame after it.
func test_start_resets_the_held_and_late_counts() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(LATE_MSEC)
	gated.hold(2)
	var runner: MatchRunner = _runner(WORKER, gated)
	runner._process(FRAME)
	assert_bool(runner.wait_idle()).is_true()
	gated.delay(0)
	for _frame: int in 4:
		runner._process(FRAME)
	assert_bool(gated.wait_blocked()).is_true()
	for _frame: int in 4:
		runner._process(FRAME)
	var counts: Array = [runner.snapshot.tick, runner.held_ticks, runner.late_ticks]
	assert_array(counts + [runner.latency_usec_max >= LATE_MSEC * 1000]).is_equal([1, 1, 1, true])
	gated.release()
	assert_bool(runner.wait_idle()).is_true()
	runner.start()
	var reset: Array = [runner.held_ticks, runner.late_ticks, runner.latency_usec_max]
	assert_array(reset + [runner.snapshot.tick]).is_equal([0, 0, 0, 0])
	assert_array(_frames(runner, _quarters(5))).is_equal([0, 0, 0, 0, 1])
	assert_int(runner.held_ticks).is_equal(0)


## A published snapshot is never written (ADR 0012 section 3): with job N + 1 held, 30 frames
## digest every field of the published snapshot (hash() per value, the fog's fields one by one).
## After the release, quarter-tick frames with no wait_idle() keep digesting it while the job
## captures from it as its `previous`, until the first frame whose own try_wait() finds the job
## finished publishes it (ADR 0012 section 1: every frame of a hold polls); then frames that do
## not move the clock digest that one while job N + 2 runs. After wait_idle() both digests are
## unchanged, and the polled publish restarted the clock at 0: the next boundary comes on the
## fourth quarter-tick frame.
func test_a_published_snapshot_is_never_written_while_the_next_job_runs() -> void:
	var gated: SimProbe = _gated_probe()
	gated.hold(AHEAD + 1)
	var runner: MatchRunner = _runner(WORKER, gated)
	assert_bool(_play_to(runner, AHEAD, false)).is_true()
	assert_bool(gated.wait_blocked()).is_true()
	var held: MatchSnapshot = runner.snapshot
	var digest: Dictionary = _digest(held)
	var changed: int = 0
	for _frame: int in 30:
		runner._process(FRAME)
		changed += int(_digest(runner.snapshot) != digest)
	assert_array([is_same(runner.snapshot, held), runner.held_ticks]).is_equal([true, 1])
	gated.release()
	var until: int = Time.get_ticks_msec() + MatchRunner.WAIT_CAP_MSEC
	while is_same(runner.snapshot, held) and Time.get_ticks_msec() < until:
		runner._process(FRAME)
		changed += int(_digest(held) != digest)
	var next: MatchSnapshot = runner.snapshot
	var next_digest: Dictionary = _digest(next)
	while runner.job_in_flight() and Time.get_ticks_msec() < until:
		changed += int(_digest(held) != digest) + int(_digest(next) != next_digest)
		runner._process(0.0)
	assert_bool(runner.wait_idle()).is_true()
	assert_array([next.tick, changed]).is_equal([AHEAD + 1, 0])
	assert_bool(_digest(held) == digest and _digest(next) == next_digest).is_true()
	assert_array([gated.begin_count, gated.overlapped]).is_equal([AHEAD + 2, false])
	var after: int = AHEAD + 1
	assert_array(_frames(runner, _quarters(4))).is_equal([after, after, after, after + 1])


## The gated probe ends a job's overlap window at the last mark of its tick (LAST_MARK, FOG since
## P46), not at REMOVE: a job that begins after the one before it marked REMOVE but not FOG overlaps
## it, and one that begins after every mark of a tick, in id order, does not. These two probes
## belong to no runner, so after_test does not check them.
func test_the_gated_probe_ends_a_job_at_the_last_mark_of_its_tick() -> void:
	var early: SimProbe = GatedProbe.new()
	early.begin()
	early.mark(SimProbe.Phase.REMOVE)
	early.begin()
	var whole: SimProbe = GatedProbe.new()
	whole.begin()
	for phase: int in SimProbe.Phase.COUNT:
		whole.mark(phase)
	whole.begin()
	var flags: Array = [early.overlapped, whole.overlapped, whole.begin_count]
	assert_array(flags).is_equal([true, false, 2])


## A runner whose Thread.start() failed before (_start_failed) resolves WORKER to SYNC at start():
## its frames tick inline, so the first frame of a tick publishes tick 1 with no job in flight and
## no thread started.
func test_a_runner_whose_thread_failed_runs_its_frames_inline() -> void:
	var workers: int = MatchRunner.live_workers()
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = SEED
	runner.tick_mode = WORKER
	runner.probe = _gated_probe()
	runner._start_failed = true
	runner.start()
	_runners.append(runner)
	runner._process(TICK)
	var state: Array = [runner.snapshot.tick, runner.job_in_flight(), runner.worker_active()]
	assert_array(state + [MatchRunner.live_workers() - workers]).is_equal([1, false, false, 0])


## Every job delayed 80 ms, more than a period, for 30 published ticks, with frames that wait only
## when a boundary holds: every job is late, holds happen, the published ticks come 1 to 30 once
## each in order, and the 15-tick checkpoints equal those of a SYNC run of the same scenario and
## seed, also without commands.
func test_forced_slow_jobs_publish_every_tick_once_with_the_sync_checkpoints() -> void:
	var gated: SimProbe = _gated_probe()
	var runner: MatchRunner = _runner(WORKER, gated)
	var seen: Array[int] = []
	runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	gated.delay(SLOW_MSEC)
	var sent: Array[int] = []
	assert_bool(_play_slow(runner, false, sent) and runner.wait_idle()).is_true()
	assert_array(seen).is_equal(range(1, SLOW_TICKS + 1))
	assert_array([runner.late_ticks, runner.held_ticks > 0]).is_equal([SLOW_TICKS, true])
	var sync: MatchRunner = _runner(SYNC)
	sync.run_ticks(SLOW_TICKS)
	assert_int(sync.replay.checkpoint_hashes.size()).is_equal(SLOW_TICKS / 15)
	assert_array(runner.replay.checkpoint_hashes).is_equal(sync.replay.checkpoint_hashes)
	assert_array([gated.overlapped, gated.gave_up]).is_equal([false, false])


## The same slow jobs with a command submitted before every frame: each appears exactly once in
## the replay, in submission order, every recorded command has the next sequence, and the log
## replayed in SYNC (Replay.play on a fresh World up to the final tick) matches every checkpoint.
## The stamps depend on the frames, so the recorded log is the equal-input comparison.
func test_forced_slow_jobs_with_commands_record_each_command_once() -> void:
	var gated: SimProbe = _gated_probe()
	var runner: MatchRunner = _runner(WORKER, gated)
	gated.delay(SLOW_MSEC)
	var sent: Array[int] = []
	assert_bool(_play_slow(runner, true, sent) and runner.wait_idle()).is_true()
	assert_int(sent.size()).is_greater(SLOW_TICKS)
	var log: Array[Array] = _decode(runner.replay)
	assert_array(log[0]).is_equal(sent)
	assert_array(log[1]).is_equal(range(log[1].size()))
	assert_int(runner.late_ticks).is_equal(SLOW_TICKS)
	assert_int(_replayed(runner)).is_equal(Replay.PLAY_MATCHED)


## A command submitted while paused before the first frame, with no job in flight, is drained by
## the refill after the resume, and one submitted in a `ticked(30)` handler by that boundary, so
## both get the same stamps in SYNC and WORKER (0 and 30), and the checkpoints are equal. (After a
## mid-run pause WORKER stamps one tick later: the resume case.) The two runners run one after the
## other, because the CommandQueue is an autoload.
func test_commands_from_ticked_and_a_pause_before_any_job_stamp_alike_in_both_modes() -> void:
	var stamps: Array = []
	var hashes: Array[PackedInt64Array] = []
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode)
		var sent: Array[Command] = [Command.move(1, PackedInt32Array([1, 2]), 20500, MARK_Y)]
		runner.paused = true
		CommandQueue.submit(sent[0])
		assert_array(_frames(runner, _quarters(3))).is_equal([0, 0, 0])
		assert_bool(runner.job_in_flight()).is_false()
		runner.paused = false
		runner.ticked.connect(
			func(tick: int) -> void:
				if tick == 30:
					sent.append(Command.attack_move(1, PackedInt32Array([1, 2]), 40500, 40500))
					CommandQueue.submit(sent[-1])
		)
		assert_bool(_play_to(runner, 45)).is_true()
		stamps.append(sent.map(func(command: Command) -> int: return command.tick))
		hashes.append(runner.replay.checkpoint_hashes.duplicate())
	assert_array(stamps).is_equal([[0, 30], [0, 30]])
	assert_int(hashes[0].size()).is_equal(3)
	assert_array(hashes[1]).is_equal(hashes[0])


## A WORKER run on jittered 60 fps frames with a command submitted after every frame, so between
## boundaries: after wait_idle(), the recorded log replayed on a fresh World matches every
## checkpoint, and the commands changed the match (its checkpoints are not those of a run without
## them).
func test_a_worker_run_with_commands_between_boundaries_replays() -> void:
	var runner: MatchRunner = _runner(WORKER)
	var frames: int = 0
	var waited: bool = true
	while runner.snapshot.tick < 45 and frames < 400 and waited:
		runner._process(FRAMES[frames % FRAMES.size()])
		frames += 1
		var target: int = 20000 + frames * 50
		CommandQueue.submit(Command.move(1, PackedInt32Array([1, 2]), target, MARK_Y))
		waited = runner.wait_idle()
	assert_array([waited, runner.snapshot.tick]).is_equal([true, 45])
	assert_int(_decode(runner.replay)[0].size()).is_greater(100)
	assert_int(_replayed(runner)).is_equal(Replay.PLAY_MATCHED)
	var quiet: MatchRunner = _runner(SYNC)
	quiet.run_ticks(45)
	assert_int(runner.replay.checkpoint_hashes.size()).is_equal(3)
	assert_array(runner.replay.checkpoint_hashes).is_not_equal(quiet.replay.checkpoint_hashes)


## The static memory (Performance.MEMORY_STATIC, a debug-build monitor: 0 on release builds, so the
## case asserts it reads above 0; CI and verify.sh run debug builds) at published tick 900 of a
## WORKER run is within MEMORY_BOUND of its value at tick 100: the published snapshots, a new one
## per tick, are freed.
func test_static_memory_stays_flat_over_a_worker_run() -> void:
	var runner: MatchRunner = _runner(WORKER)
	var memory: Dictionary[int, float] = {}
	runner.ticked.connect(
		func(tick: int) -> void:
			if tick in [MEMORY_FROM, MEMORY_TO]:
				memory[tick] = Performance.get_monitor(Performance.MEMORY_STATIC)
	)
	var frames: int = 0
	var waited: bool = true
	while runner.snapshot.tick < MEMORY_TO and frames < MEMORY_TO + 10 and waited:
		runner._process(TICK)
		frames += 1
		waited = runner.wait_idle()
	assert_array([waited, runner.snapshot.tick, memory.size()]).is_equal([true, MEMORY_TO, 2])
	assert_float(memory[MEMORY_FROM]).is_greater(0.0)
	assert_float(memory[MEMORY_TO] - memory[MEMORY_FROM]).is_less(MEMORY_BOUND)


## Plays `runner` with quarter-tick frames and wait_idle() after each until it publishes `tick`,
## with the clock at 0 after that publish; without `wait_last`, the frame that publishes `tick` is
## not waited for, so the job it posted may stay held. False when a wait reaches its cap or the
## frames run out.
func _play_to(runner: MatchRunner, tick: int, wait_last: bool = true) -> bool:
	var frames: int = 0
	while runner.snapshot.tick < tick and frames < 4 * tick + 8:
		runner._process(FRAME)
		frames += 1
		if (runner.snapshot.tick < tick or wait_last) and not runner.wait_idle():
			return false
	return runner.snapshot.tick == tick


## Runs one frame of each delta with wait_idle() after it, and gives the published tick after each
## (-1 for a wait that reached its cap, which ends the run).
func _frames(runner: MatchRunner, deltas: Array[float]) -> Array[int]:
	var ticks: Array[int] = []
	for delta: float in deltas:
		runner._process(delta)
		if not runner.wait_idle():
			ticks.append(-1)
			return ticks
		ticks.append(runner.snapshot.tick)
	return ticks


## Plays `runner`, whose jobs are slow, to SLOW_TICKS with quarter-tick frames that wait only when a
## boundary holds (alpha() is 1.0 then), as a real frame loop would poll until the job is done.
## With `submit`, a MOVE with target_x 20000 plus the frame number is submitted before every frame
## and its target_x appended to `sent`. False when a wait reaches its cap or the frames run out.
func _play_slow(runner: MatchRunner, submit: bool, sent: Array[int]) -> bool:
	var frames: int = 0
	while runner.snapshot.tick < SLOW_TICKS and frames < 8 * SLOW_TICKS:
		if submit:
			sent.append(20000 + frames)
			CommandQueue.submit(Command.move(1, PackedInt32Array([1, 2]), sent[-1], MARK_Y))
		runner._process(FRAME)
		frames += 1
		if runner.alpha() == 1.0 and not runner.wait_idle():
			return false
	return runner.snapshot.tick == SLOW_TICKS


func _quarters(count: int) -> Array[float]:
	var deltas: Array[float] = []
	for _i: int in count:
		deltas.append(FRAME)
	return deltas


## The state hash after each of the first `ticks` ticks of a SYNC runner.
func _sync_hashes(ticks: int) -> Array[int]:
	var sync: MatchRunner = _runner(SYNC)
	var hashes: Array[int] = []
	for _tick: int in ticks:
		sync.run_ticks(1)
		hashes.append(sync.world.state_hash())
	return hashes


## Every script field of `snap` as hash() of its value, by name, with its fog's fields as
## "fog.<name>".
func _digest(snap: MatchSnapshot) -> Dictionary:
	var digest: Dictionary = {}
	for property: Dictionary in snap.get_property_list():
		var name: String = property["name"]
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if name != "fog":
			digest[name] = hash(snap.get(name))
			continue
		for field: Dictionary in snap.fog.get_property_list():
			if field["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
				digest["fog." + String(field["name"])] = hash(snap.fog.get(field["name"]))
	return digest


## The replay's log decoded: the target_x of the MOVE commands marked with MARK_Y, in log order,
## and the sequence of every command.
func _decode(replay: Replay) -> Array[Array]:
	var targets: Array[int] = []
	var sequences: Array[int] = []
	var at: int = 0
	while at >= 0 and at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		if at >= 0:
			sequences.append(command.sequence)
			if command.type == Command.Type.MOVE and command.target_y == MARK_Y:
				targets.append(command.target_x)
	return [targets, sequences]


## Replay.play of the runner's replay on a fresh World of the arena up to the World's tick; the
## caller has waited for the runner.
func _replayed(runner: MatchRunner) -> int:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	return Replay.play(runner.replay, world, runner.world.tick)


## A started runner on the seed-42 arena in `mode`, with `probe` installed before start(), or a
## plain gated probe (no hold, no delay) when the case gives none.
func _runner(mode: int, probe: SimProbe = null) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.probe = probe if probe != null else _gated_probe()
	runner.start()
	_runners.append(runner)
	return runner


func _gated_probe() -> SimProbe:
	var probe: SimProbe = GatedProbe.new()
	_probes.append(probe)
	return probe
