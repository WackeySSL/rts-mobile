extends GdUnitTestSuite
## MatchRunner.controller_of (plan row P543, ADR 0038 section 2): the read-only look at a seat's
## controller that the tutorial director takes after wait_idle(). It is guarded like `world`, but
## with a warning: null while a WORKER job runs, and null while the AI thread's batch is awaited.
## A thread suite (it runs three times in a row, CLAUDE.md); the runners are built the Phase 1 way
## (auto_free, never in the tree) and play through wait_idle() only.

const DummyStart: GDScript = preload("res://tests/core/support/dummy_start.gd")
const WaitingAi: GDScript = preload("res://tests/core/support/waiting_ai.gd")
const GatedProbe: GDScript = preload("res://tests/core/gated_probe.gd")
const FOSSIL: AiDef = preload("res://data/ai/opponent_fossil.tres")
const SEED: int = 42
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
## How long a delayed job waits in its probe's begin(): far longer than the calls between the frame
## that posts it and the call that must find it in flight.
const DELAY_MSEC: int = 30
const FRAME: float = 1.0 / 60.0
const WARNING_TEXT: String = "MatchRunner: controller_of(2) while a job or the AI thread runs "
const WARNING_END: String = "(ADR 0038)"

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


## A seat answers by player id: the opponent is player 2; a human seat and a player that is not in
## the match have no controller. A new start() seats new controllers, so nothing read before it
## stays valid.
func test_it_gives_the_controller_of_the_seat_and_a_new_one_after_start() -> void:
	var runner: MatchRunner = _runner(SYNC, FOSSIL)
	var first: AiController = runner.controller_of(2)
	assert_object(first).is_not_null()
	assert_int(first.player_id).is_equal(2)
	assert_object(runner.controller_of(1)).is_null()
	assert_object(runner.controller_of(9)).is_null()
	assert_object(runner.controller_of(2)).is_same(first)
	runner.start()
	var second: AiController = runner.controller_of(2)
	assert_object(second).is_not_null()
	assert_object(second).is_not_same(first)


## WORKER, a job in flight: the sim worker owns the match, so the call warns and gives null; after
## wait_idle() the same call gives the controller and logs nothing.
func test_it_warns_and_gives_null_while_a_worker_job_runs() -> void:
	var gated: SimProbe = _gated_probe()
	gated.delay(DELAY_MSEC)
	var runner: MatchRunner = _runner(WORKER, FOSSIL, gated)
	runner._process(FRAME)
	assert_bool(runner.job_in_flight()).is_true()
	(
		assert_error(func() -> void: assert_object(runner.controller_of(2)).is_null())
		. is_push_warning(WARNING_TEXT + WARNING_END)
	)
	assert_bool(runner.wait_idle()).is_true()
	assert_object(runner.controller_of(2)).is_not_null()


## WORKER with the AI thread: the job is over but its batch is still being thought (a slow
## controller), so the controllers are the AI thread's. The call warns and gives null until
## wait_idle() has taken the batch, which is the director's order.
func test_it_warns_and_gives_null_while_the_ai_batch_is_awaited() -> void:
	var runner: MatchRunner = _runner(WORKER, FOSSIL)
	var slow: AiController = WaitingAi.new()
	slow.player_id = 2
	slow.think_period = 1
	runner._job.controllers = [slow]
	runner.run_ticks(1)
	assert_bool(runner._job.batch.awaiting).is_true()
	assert_bool(runner._ai_thread != null and runner._ai_thread.is_started()).is_true()
	(
		assert_error(func() -> void: assert_object(runner.controller_of(2)).is_null())
		. is_push_warning(WARNING_TEXT + WARNING_END)
	)
	assert_bool(runner.wait_idle()).is_true()
	assert_object(runner.controller_of(2)).is_same(slow)


func _runner(mode: int, def: AiDef, probe: SimProbe = null) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = DummyStart.scenario()
	runner.match_seed = SEED
	runner.tick_mode = mode
	runner.opponents = [def]
	runner.probe = probe
	runner.start()
	_runners.append(runner)
	return runner


func _gated_probe() -> SimProbe:
	var probe: SimProbe = GatedProbe.new()
	_probes.append(probe)
	return probe
