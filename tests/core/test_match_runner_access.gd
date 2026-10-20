extends GdUnitTestSuite
## MatchRunner's guarded access (plan P38w1b, ADR 0012 section 1): `world`, `loop`, `replay` and
## `probe` are properties over private fields, guarded by shared_access_allowed(); each has a
## setter, because Godot ignores an assignment to a getter-only property without a word, so the
## World.new() swap cases of P40 and P43a would pass without swapping anything. set_probe() waits
## idle first. live_workers() counts the started workers that are not joined, so a case proves the
## join of a freed runner without calling it. No case reads a getter while a job is RUNNING: its
## error would fail verify.sh's log scan, so the cases read the rule for the runner's state instead
## (the one-tick-ahead case of test_match_runner_worker.gd too), and GuardRunner, whose guard
## answers a flag and logs nothing, pins that the getters and setters ask it. The runners are built
## the Phase 1 way on the seed-42 perf arena; after_test releases every gated probe and then waits
## for every runner still alive, so a case that fails while a probe holds a job still leaves the
## worker free.

const GatedProbe: GDScript = preload("res://tests/core/gated_probe.gd")
const GuardRunner: GDScript = preload("res://tests/core/support/guard_runner.gd")
const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42
## A frame of exactly a quarter tick.
const FRAME: float = 1.0 / 60.0
## How long a delayed job waits in its probe's begin(): far longer than the calls between the frame
## that posts it and the free or the assignment that must find it in flight.
const DELAY_MSEC: int = 30
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
const AUTO: int = MatchRunner.TickMode.AUTO
const IDLE: int = MatchRunner.HandOff.IDLE
const RUNNING: int = MatchRunner.HandOff.RUNNING
const FINISHED: int = MatchRunner.HandOff.FINISHED

var _runners: Array[MatchRunner] = []
var _probes: Array[SimProbe] = []


func after_test() -> void:
	for probe: SimProbe in _probes:
		probe.release()
	for runner: MatchRunner in _runners:
		if is_instance_valid(runner):
			assert_bool(runner.wait_idle()).is_true()
	_probes.clear()
	_runners.clear()
	CommandQueue.clear()


## The rule as a table over every TickMode and HandOff state: only a WORKER runner with a job
## RUNNING keeps the main thread out (the resolved mode is never AUTO; the rule names WORKER alone).
## On a live WORKER runner it follows the hand-off: allowed before the first job, refused while one
## runs, allowed once wait_idle() took its token, when the getters give the runner's own objects.
func test_shared_access_is_refused_only_while_a_worker_job_runs() -> void:
	var table: Array[bool] = []
	for mode: int in [SYNC, WORKER, AUTO]:
		for state: int in [IDLE, RUNNING, FINISHED]:
			table.append(MatchRunner.shared_access_allowed(mode, state))
	assert_array(table).is_equal([true, true, true, true, false, true, true, true, true])
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	assert_array(_access(runner)).is_equal([WORKER, IDLE, true])
	runner._process(FRAME)
	assert_array(_access(runner)).is_equal([WORKER, RUNNING, false])
	assert_bool(runner.wait_idle()).is_true()
	assert_array(_access(runner)).is_equal([WORKER, FINISHED, true])
	var own: Array[bool] = [
		is_same(runner.world, runner._world),
		is_same(runner.loop, runner._loop),
		is_same(runner.replay, runner.loop.replay),
		is_same(runner.probe, gated),
	]
	assert_array(own).is_equal([true, true, true, true])
	assert_int(runner.world.tick).is_equal(1)


## In SYNC mode each setter installs what it is given (is_same) for the next tick. `world =` an
## empty World.new(): the next tick steps it and leaves the old World where it was. `loop =` and
## `replay =` a new MatchLoop and its log: the next tick's command is stamped and recorded there,
## not in the old loop. `probe =` a recording probe: it sees the next tick's begin() and its phases
## in order, and `probe = null` removes it.
func test_the_setters_install_what_they_are_given_for_the_next_sync_tick() -> void:
	var runner: MatchRunner = _runner(SYNC)
	runner.run_ticks(1)
	var old: World = runner.world
	var swapped: World = World.new()
	runner.world = swapped
	assert_array([is_same(runner.world, swapped), swapped.tick]).is_equal([true, 0])
	runner.run_ticks(1)
	assert_array([old.tick, swapped.tick, runner.snapshot.tick]).is_equal([1, 1, 1])
	var old_loop: MatchLoop = runner.loop
	var other: MatchLoop = MatchLoop.create(null, "", SEED, World.new())
	runner.loop = other
	runner.replay = other.replay
	assert_array([is_same(runner.loop, other), is_same(runner.replay, other.replay)]).is_equal(
		[true, true]
	)
	var sequence: int = old_loop.next_sequence
	CommandQueue.submit(Command.move(1, PackedInt32Array([1]), 20500, 30500))
	runner.run_ticks(1)
	assert_array([old_loop.next_sequence, other.next_sequence]).is_equal([sequence, 1])
	assert_int(other.replay.commands.size()).is_greater(0)
	var probe: SimProbe = RecordingProbe.new()
	runner.probe = probe
	assert_bool(is_same(runner.probe, probe)).is_true()
	assert_int(probe.calls.size()).is_equal(0)
	runner.run_ticks(1)
	var seen: PackedInt32Array = probe.calls.duplicate()
	assert_array([seen.size() > 1, seen[0], seen.count(-1)]).is_equal([true, -1, 1])
	var phases: Array = Array(seen.slice(1))
	var sorted: Array = phases.duplicate()
	sorted.sort()
	assert_array(phases).is_equal(sorted)
	runner.probe = null
	runner.run_ticks(1)
	assert_object(runner.probe).is_null()
	assert_array(probe.calls).is_equal(seen)


## In WORKER mode, after wait_idle(), `world =` gives the same result on the next post: the
## finished job is published from the old World, and the job posted after it steps the new one.
## `probe =` while a job runs waits for it first (set_probe()): nothing is in flight once the
## assignment returns, the job in flight kept its gated probe, and the next job reports to the new
## probe alone.
func test_the_setters_reach_the_next_post_in_worker_mode() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	runner._process(FRAME)
	assert_bool(runner.job_in_flight()).is_true()
	var probe: SimProbe = RecordingProbe.new()
	runner.probe = probe
	assert_array([runner.job_in_flight(), is_same(runner.probe, probe)]).is_equal([false, true])
	assert_array([gated.begin_count, probe.calls.size()]).is_equal([1, 0])
	var old: World = runner.world
	var swapped: World = World.new()
	runner.world = swapped
	assert_bool(is_same(runner.world, swapped)).is_true()
	var frames: int = 0
	while runner.snapshot.tick < 1 and frames < 8:
		runner._process(FRAME)
		frames += 1
	assert_bool(runner.wait_idle()).is_true()
	assert_array([runner.snapshot.tick, old.tick, swapped.tick]).is_equal([1, 1, 1])
	assert_array([gated.begin_count, probe.calls.count(-1)]).is_equal([1, 1])


## A WORKER runner never added to the tree and freed while its job runs: its worker counted in
## live_workers() while it ran, and NOTIFICATION_PREDELETE joins it, so the count is back to its
## value before the case, with no error.
func test_a_runner_freed_during_a_job_outside_the_tree_joins_its_worker() -> void:
	await _assert_freed_during_a_job_joins(false)


## The same for a WORKER runner in the tree. NOTIFICATION_PREDELETE reaches the script before the
## runner leaves the tree, so the free joins the worker there too and _exit_tree() finds it joined;
## the leaving-the-tree case of test_match_runner_worker.gd covers the join on a tree exit.
func test_a_runner_freed_during_a_job_in_the_tree_joins_its_worker() -> void:
	await _assert_freed_during_a_job_joins(true)


## A SYNC runner that ticks, in the tree and out of it, starts no thread, and freeing it logs no
## error: no wait_to_finish() on an unstarted Thread. live_workers() never moves.
func test_a_sync_runner_starts_no_thread_and_frees_without_an_error() -> void:
	var before: int = MatchRunner.live_workers()
	for in_tree: bool in [false, true]:
		var runner: MatchRunner = _runner(SYNC)
		if in_tree:
			add_child(runner)
		runner.run_ticks(2)
		for _frame: int in 8:
			runner._process(FRAME)
		assert_array([runner.snapshot.tick, runner.worker_active()]).is_equal([4, false])
		assert_int(MatchRunner.live_workers()).is_equal(before)
		await assert_error(func() -> void: runner.free()).is_success()
		assert_bool(is_instance_valid(runner)).is_false()
		assert_int(MatchRunner.live_workers()).is_equal(before)


## live_workers() counts a runner's worker once, however many jobs it posts, and a free gives it
## back with no job running too: a WORKER runner that published three ticks (four posts, one
## thread) adds one, and freed in FINISHED after wait_idle(), so the join waits for nothing, it
## gives that one back.
func test_live_workers_counts_a_worker_once_and_a_free_with_no_job_running_gives_it_back() -> void:
	var before: int = MatchRunner.live_workers()
	var runner: MatchRunner = _runner(WORKER)
	var frames: int = 0
	while runner.snapshot.tick < 3 and frames < 64:
		runner._process(FRAME)
		assert_bool(runner.wait_idle()).is_true()
		frames += 1
	assert_array([runner.snapshot.tick, runner._state, runner.worker_active()]).is_equal(
		[3, FINISHED, true]
	)
	assert_int(MatchRunner.live_workers()).is_equal(before + 1)
	await assert_error(func() -> void: runner.free()).is_success()
	assert_bool(is_instance_valid(runner)).is_false()
	assert_int(MatchRunner.live_workers()).is_equal(before)


## The four getters and the world, loop and replay setters ask the guard, _shared(): GuardRunner
## closes it with no job in flight and no error. Closed, each getter gives null and each of the
## three setters changes nothing; open again, the getters give the runner's own objects. `probe =`
## goes through set_probe(), which waits idle instead.
func test_the_getters_and_the_setters_ask_the_guard() -> void:
	var runner: MatchRunner = auto_free(GuardRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = SEED
	var probe: SimProbe = RecordingProbe.new()
	runner.probe = probe
	runner.start()
	var own: Array[Object] = [runner.world, runner.loop, runner.replay, runner.probe]
	assert_bool(own.has(null)).is_false()
	runner.allow = false
	var closed: Array[bool] = [
		runner.world == null, runner.loop == null, runner.replay == null, runner.probe == null
	]
	assert_array(closed).is_equal([true, true, true, true])
	var other: MatchLoop = MatchLoop.create(null, "", SEED, World.new())
	runner.world = World.new()
	runner.loop = other
	runner.replay = other.replay
	runner.allow = true
	var kept: Array[bool] = [
		is_same(runner.world, own[0]),
		is_same(runner.loop, own[1]),
		is_same(runner.replay, own[2]),
		is_same(runner.probe, probe),
	]
	assert_array(kept).is_equal([true, true, true, true])


## Frees a WORKER runner (in the tree when `in_tree`) while its delayed job is in flight.
func _assert_freed_during_a_job_joins(in_tree: bool) -> void:
	var before: int = MatchRunner.live_workers()
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, gated)
	if in_tree:
		add_child(runner)
	assert_int(MatchRunner.live_workers()).is_equal(before)
	runner._process(FRAME)
	assert_array([runner.job_in_flight(), runner.worker_active()]).is_equal([true, true])
	assert_int(MatchRunner.live_workers()).is_equal(before + 1)
	await assert_error(func() -> void: runner.free()).is_success()
	assert_bool(is_instance_valid(runner)).is_false()
	assert_int(MatchRunner.live_workers()).is_equal(before)
	assert_array([gated.begin_count, gated.gave_up, gated.overlapped]).is_equal([1, false, false])


## The runner's resolved mode, its hand-off state and what the rule says for them.
func _access(runner: MatchRunner) -> Array:
	return [
		runner._mode, runner._state, MatchRunner.shared_access_allowed(runner._mode, runner._state)
	]


## A started runner on the seed-42 arena in `mode`, with `probe` installed before start().
func _runner(mode: int, probe: SimProbe = null) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.probe = probe
	runner.start()
	_runners.append(runner)
	return runner


func _gated_probe() -> SimProbe:
	var probe: SimProbe = GatedProbe.new()
	_probes.append(probe)
	return probe
