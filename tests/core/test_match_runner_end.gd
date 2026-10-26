extends GdUnitTestSuite
## The end of a match in MatchRunner (plan row P81, ADR 0017 section 6, ADR 0018 section 7): once a
## published snapshot shows `match_end_tick`, the runner emits `match_ended(winner)` after that
## tick's `ticked` and plays no further tick, in SYNC and in WORKER mode, until start(). Nothing in
## the sim sets the end before plan row P76, so a `ticked(n)` handler writes it into the World by
## hand, as the ending step would: `match_end_tick` n + 1 (the tick the next step produces, 0 =
## playing) and the winner; the next tick publishes it. The runners are built the Phase 1 way
## (auto_free, never in the tree) on tests/core/support/base_match.gd, seed 42; the WORKER cases
## wait only through wait_idle(), and a GatedProbe that holds nothing counts the jobs begun, so a
## job after the end shows. A thread suite: it runs three times in a row (CLAUDE.md).

const BaseMatch: GDScript = preload("res://tests/core/support/base_match.gd")
const GatedProbe: GDScript = preload("res://tests/core/gated_probe.gd")
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42
## The tick whose step ends the WORKER matches.
const END: int = 6
## A frame of exactly a quarter tick, and a frame of four ticks (SYNC plays at most four a frame).
const FRAME: float = 1.0 / 60.0
const FOUR_TICKS: float = 4.0 / 15.0
## Frames enough to publish END and then run about twenty more ticks' worth.
const FRAMES: int = 4 * END + 80
## The tick the quiet runs pass: every published tick up to it is playing.
const QUIET_TICKS: int = 900
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
	_probes.clear()
	_runners.clear()
	CommandQueue.clear()


## SYNC: `ticked(4)` writes an end at tick 5 with winner 2. run_ticks(10) publishes ticks 1 to 5
## and stops there, `match_ended(2)` coming once, after `ticked(5)`; the World stayed at tick 5 and
## its end is the snapshot's. Then run_ticks() and frames of four ticks play nothing: the same
## snapshot stays published and no job begins.
func test_a_sync_runner_stops_after_the_tick_that_publishes_the_end() -> void:
	var probe: SimProbe = _probe()
	var runner: MatchRunner = _runner(SYNC, probe)
	var heard: Array[String] = _heard(runner)
	_end_at(runner, 5, 2)
	runner.run_ticks(10)
	assert_array(heard).is_equal(["t1", "t2", "t3", "t4", "t5", "e2"])
	var ended: MatchSnapshot = runner.snapshot
	var state: Array = [ended.tick, runner.world.tick, ended.match_end_tick, ended.winner]
	assert_array(state + [probe.begin_count]).is_equal([5, 5, 5, 2, 5])
	runner.run_ticks(3)
	runner._process(FOUR_TICKS)
	runner._process(FOUR_TICKS)
	runner.run_ticks(1)
	assert_bool(is_same(runner.snapshot, ended)).is_true()
	assert_array([runner.world.tick, probe.begin_count, heard.size()]).is_equal([5, 5, 6])


## SYNC: one frame of four ticks whose second tick publishes a draw (`ticked(1)` writes the end at
## tick 2, winner 0) plays two ticks, not four, and `match_ended(0)` follows `ticked(2)`. The next
## frames play nothing.
func test_a_sync_frame_stops_its_catch_up_at_the_end() -> void:
	var probe: SimProbe = _probe()
	var runner: MatchRunner = _runner(SYNC, probe)
	var heard: Array[String] = _heard(runner)
	_end_at(runner, 2, 0)
	runner._process(FOUR_TICKS)
	assert_array(heard).is_equal(["t1", "t2", "e0"])
	(
		assert_array([runner.snapshot.tick, runner.world.tick, runner.snapshot.match_end_tick])
		. is_equal([2, 2, 2])
	)
	for _frame: int in 3:
		runner._process(FOUR_TICKS)
	(
		assert_array([runner.snapshot.tick, runner.world.tick, probe.begin_count, heard.size()])
		. is_equal([2, 2, 2, 3])
	)


## WORKER: `ticked(END - 1)` writes the end at END with winner 1, before the boundary posts job END.
## Quarter-tick frames with wait_idle() after each publish ticks 1 to END and `match_ended(1)` once;
## the frames after it post no job (no refill either): exactly END jobs began, none is in flight,
## the World is at END, and the main thread may read it. The worker stays started until the join.
func test_a_worker_runner_posts_no_job_after_publishing_the_end() -> void:
	var probe: SimProbe = _probe()
	var runner: MatchRunner = _runner(WORKER, probe)
	var heard: Array[String] = _heard(runner)
	_end_at(runner, END, 1)
	assert_bool(_frames(runner, FRAMES)).is_true()
	var expected: Array[String] = []
	for tick: int in range(1, END + 1):
		expected.append("t%d" % tick)
	expected.append("e1")
	assert_array(heard).is_equal(expected)
	var snap: MatchSnapshot = runner.snapshot
	assert_array([snap.tick, snap.match_end_tick, snap.winner, probe.begin_count]).is_equal(
		[END, END, 1, END]
	)
	assert_array([runner.job_in_flight(), runner.worker_active()]).is_equal([false, true])
	assert_bool(MatchRunner.shared_access_allowed(runner._mode, runner._state)).is_true()
	assert_array([runner.world.tick, runner.world.match_end_tick]).is_equal([END, END])
	assert_array([probe.gave_up, probe.overlapped]).is_equal([false, false])


## WORKER: `ticked(3)` writes the end at tick 4, so the frame that publishes tick 3 posts job 4,
## which carries the end; after wait_idle() it is finished and not published. run_ticks(5)
## publishes it as its first tick, emits `match_ended(2)` and runs none of the other four inline;
## the frames after that post nothing.
func test_run_ticks_in_worker_mode_publishes_the_end_in_flight_and_stops() -> void:
	var probe: SimProbe = _probe()
	var runner: MatchRunner = _runner(WORKER, probe)
	var heard: Array[String] = _heard(runner)
	_end_at(runner, 4, 2)
	var frames: int = 0
	while runner.snapshot.tick < 3 and frames < 40:
		runner._process(FRAME)
		frames += 1
		assert_bool(runner.wait_idle()).is_true()
	assert_array([runner.snapshot.tick, runner.world.tick, probe.begin_count]).is_equal([3, 4, 4])
	runner.run_ticks(5)
	assert_array(heard).is_equal(["t1", "t2", "t3", "t4", "e2"])
	assert_array([runner.snapshot.tick, runner.world.tick, runner.job_in_flight()]).is_equal(
		[4, 4, false]
	)
	assert_bool(_frames(runner, 20)).is_true()
	runner.run_ticks(2)
	assert_array([runner.snapshot.tick, probe.begin_count, heard.size()]).is_equal([4, 4, 5])


## After the end, start() begins a new match that plays again, in both modes: its tick-0 snapshot
## shows no end, frames publish its ticks 1 to 3 under the new match_serial, and no `match_ended`
## comes for it.
func test_start_after_the_end_plays_a_new_match() -> void:
	for mode: int in [SYNC, WORKER]:
		var runner: MatchRunner = _runner(mode, null)
		var heard: Array[String] = _heard(runner)
		_end_at(runner, 2, 1)
		assert_bool(_frames(runner, 20)).is_true()
		assert_array(heard).override_failure_message(str(mode)).is_equal(["t1", "t2", "e1"])
		runner.start()
		assert_array([runner.snapshot.tick, runner.snapshot.match_end_tick]).is_equal([0, 0])
		var frames: int = 0
		while runner.snapshot.tick < 3 and frames < 40:
			runner._process(FRAME)
			frames += 1
			assert_bool(runner.wait_idle()).is_true()
		assert_array([runner.snapshot.tick, runner.snapshot.match_serial]).is_equal([3, 2])
		assert_array(heard).is_equal(["t1", "t2", "e1", "t1", "t2", "t3"])


## SYNC: a `ticked(3)` handler that restarts the match on the snapshot that shows the end (at tick
## 3) gets no `match_ended` for the old match: that snapshot is no longer the published one. The
## rest of run_ticks(10) plays the new match, ticks 1 to 7.
func test_a_ticked_handler_that_restarts_on_the_end_gets_no_match_ended() -> void:
	var runner: MatchRunner = _runner(SYNC, null)
	var heard: Array[String] = _heard(runner)
	_end_at(runner, 3, 2)
	var restarted: Array[bool] = [false]
	runner.ticked.connect(
		func(_tick: int) -> void:
			if runner.snapshot.match_end_tick > 0 and not restarted[0]:
				restarted[0] = true
				runner.start()
	)
	runner.run_ticks(10)
	var expected: Array[String] = ["t1", "t2", "t3"]
	for tick: int in range(1, 8):
		expected.append("t%d" % tick)
	assert_array(heard).is_equal(expected)
	assert_array([runner.match_serial, runner.snapshot.tick, runner.world.match_end_tick]).is_equal(
		[2, 7, 0]
	)


## The preview's main scenario and the perf arena never end: no side owns a producer, so no rule
## of ADR 0018 section 7 defeats one. A SYNC runner on each plays QUIET_TICKS with run_ticks()
## and one more tick with a frame, publishing every tick with no end and no `match_ended`.
func test_controls_test_and_the_perf_arena_tick_past_900_without_an_end() -> void:
	for path: String in [CONTROLS_PATH, ARENA_PATH]:
		var runner: MatchRunner = auto_free(MatchRunner.new())
		runner.scenario = load(path) as ScenarioDef
		runner.match_seed = SEED
		if path == ARENA_PATH:
			runner.sim_impl = MatchRunner.SimImpl.NATIVE
		runner.start()
		var ends: Array[int] = []
		var ended: Array[int] = []
		runner.ticked.connect(
			func(_tick: int) -> void:
				if runner.snapshot.match_end_tick != 0 or runner.snapshot.winner != 0:
					ends.append(runner.snapshot.tick)
		)
		runner.match_ended.connect(func(winner: int) -> void: ended.append(winner))
		runner.run_ticks(QUIET_TICKS)
		runner._process(1.0 / 15.0)
		(
			assert_array([runner.snapshot.tick, runner.world.tick])
			. override_failure_message(path)
			. is_equal([QUIET_TICKS + 1, QUIET_TICKS + 1])
		)
		assert_array(ends + ended).override_failure_message(path).is_empty()


## A started runner on the base match in `mode`, with `probe` installed before start().
func _runner(mode: int, probe: SimProbe) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = BaseMatch.scenario()
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.probe = probe
	runner.start()
	_runners.append(runner)
	return runner


func _probe() -> SimProbe:
	var probe: SimProbe = GatedProbe.new()
	_probes.append(probe)
	return probe


## What `runner` emits, in order: "t<tick>" per `ticked`, "e<winner>" per `match_ended`.
func _heard(runner: MatchRunner) -> Array[String]:
	var heard: Array[String] = []
	runner.ticked.connect(func(tick: int) -> void: heard.append("t%d" % tick))
	runner.match_ended.connect(func(winner: int) -> void: heard.append("e%d" % winner))
	return heard


## Makes the step to `tick` end the match with `winner`, as the sim will (plan row P76): inside
## `ticked(tick - 1)`, where no job is in flight in either mode, the World gets `match_end_tick`
## `tick` and the winner.
func _end_at(runner: MatchRunner, tick: int, winner: int) -> void:
	runner.ticked.connect(
		func(at: int) -> void:
			if at == tick - 1 and runner.snapshot.match_serial == 1:
				runner.world.match_end_tick = tick
				runner.world.winner = winner
	)


## Plays `frames` quarter-tick frames of `runner`, with wait_idle() after each; false when a wait
## reaches its cap.
func _frames(runner: MatchRunner, frames: int) -> bool:
	for _frame: int in frames:
		runner._process(FRAME)
		if not runner.wait_idle():
			return false
	return true
