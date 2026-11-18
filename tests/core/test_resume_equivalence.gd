extends GdUnitTestSuite
## Resume proofs (plan P516, ADR 0042 sections 6 and 7): a skirmish written at tick 300 and at tick
## 3,000, read back, restored by the Restorer and played on equals the uninterrupted match. The
## reference is one GDSCRIPT, SYNC match with the Hard AI; each of the four runners
## (GDSCRIPT and AUTO, each SYNC and WORKER with the AI on its own thread) restores both files,
## compares the World's state hash and the file's end hash at the stored tick, then plays 100 ticks
## more with the reference's own orders and must end on the reference's hash, with the reference's
## checkpoint hashes. The restore feeds no order to `CommandQueue.submitted`. Refusals: a damaged
## log, another defs_hash, another app version, a changed checkpoint, a changed end hash.
##
## A thread suite (the AI thread): it runs three times in a row (CLAUDE.md). The 3,000-tick case
## stays in the regular suite: the whole file runs in a few seconds, so nothing is gated. In WORKER
## mode `run_ticks` plays inline and only the AI thinks on its own thread (ADR 0038). Ticks are
## counted, never timed: the Restorer's clock is a counter.

const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242
const PLAYER: int = 1
const UNITS: PackedInt32Array = [1, 2, 3]
const EARLY: int = 300
const LATE: int = 3000
const MORE: int = 100
const ORDER_EVERY: int = 250
const SLICE_TICKS: int = 64
const FRAME_LIMIT: int = 2000
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
const GDSCRIPT: int = MatchRunner.SimImpl.GDSCRIPT
const AUTO: int = MatchRunner.SimImpl.AUTO

## The reference: the files at EARLY and LATE as bytes, and the hashes at each stage.
var _bytes: Dictionary[int, PackedByteArray] = {}
var _hash_at: Dictionary[int, int] = {}
var _checkpoints: PackedInt64Array = PackedInt64Array()
var _clock: int = 0
var _submitted: int = 0
var _warnings: Array[String] = []


func before() -> void:
	CommandQueue.clear()
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(_setup().apply(runner)).is_equal(OK)
	runner.start()
	for stage: int in [EARLY, LATE]:
		_play_to(runner, stage)
		_hash_at[stage] = runner.world.state_hash()
		_bytes[stage] = ResumeStore.encode(
			_setup(),
			runner.replay,
			stage,
			runner.world.defs_hash(),
			ResumeStore.app_version(),
			_hash_at[stage]
		)
		assert_bool(_bytes[stage].is_empty()).is_false()
		_play_to(runner, stage + MORE)
		_hash_at[stage + MORE] = runner.world.state_hash()
	_checkpoints = PackedInt64Array(runner.replay.checkpoint_hashes)
	CommandQueue.clear()


func before_test() -> void:
	_clock = 0
	_submitted = 0
	_warnings.clear()
	CommandQueue.clear()
	ResumeStore.warning_sink = func(text: String) -> void: _warnings.append(text)


func after_test() -> void:
	ResumeStore.warning_sink = Callable()
	ResumeWatcher.restoring = false
	AudioService.clear_mute_reason(AudioService.REASON_RESTORING)
	CommandQueue.clear()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = SEED
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	return setup


## The local player's order for tick `tick`, or null: a move or a stop every ORDER_EVERY ticks from
## tick 20, so both files hold orders and the play after each restore has more.
func _order(tick: int) -> Command:
	if tick < 20 or (tick - 20) % ORDER_EVERY != 0:
		return null
	var step: int = (tick - 20) / ORDER_EVERY
	if step % 3 == 2:
		return Command.stop(PLAYER, UNITS)
	var east: bool = step % 3 == 0
	return Command.move(PLAYER, UNITS, 20500 if east else 9500, 9500 if east else 20500)


## Plays `runner` on to tick `target` with the schedule's orders.
func _play_to(runner: MatchRunner, target: int) -> void:
	while runner.snapshot.tick < target:
		var order: Command = _order(runner.snapshot.tick)
		if order != null:
			CommandQueue.submit(order)
		runner.run_ticks(1)


func _scene(impl: int, mode: int) -> Node:
	var scene: Node = auto_free(Node.new())
	var runner: MatchRunner = MatchRunner.new()
	runner.name = "MatchRunner"
	runner.sim_impl = impl as MatchRunner.SimImpl
	runner.tick_mode = mode as MatchRunner.TickMode
	scene.add_child(runner)
	return scene


func _restorer() -> Restorer:
	var restorer: Restorer = auto_free(Restorer.new())
	restorer.clock = func() -> int:
		_clock += 1
		return _clock
	restorer.slice_usec = SLICE_TICKS
	return restorer


func _data(stage: int) -> ResumeData:
	var data: ResumeData = ResumeStore.decode(
		_bytes[stage], ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH
	)
	assert_object(data).is_not_null()
	return data


## Counted frames until `finished`; the result is its argument, or -1 when it never came.
func _run(restorer: Restorer) -> Error:
	var done: Array[Error] = []
	restorer.finished.connect(func(result: Error) -> void: done.append(result))
	for _frame: int in FRAME_LIMIT:
		if not done.is_empty():
			break
		restorer._process(0.0)
	return done[0] if not done.is_empty() else ERR_TIMEOUT


## Restores `stage` in `impl` and `mode`, checks it against the reference at the stored tick, then
## plays MORE ticks on and checks again.
func _prove(stage: int, impl: int, mode: int) -> void:
	var data: ResumeData = _data(stage)
	assert_int(data.tick).is_equal(stage)
	assert_int(data.end_hash).is_equal(_hash_at[stage])
	var watch: Callable = func(_command: Command) -> void: _submitted += 1
	CommandQueue.submitted.connect(watch)
	var scene: Node = _scene(impl, mode)
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, scene)).is_equal(OK)
	var result: Error = _run(restorer)
	CommandQueue.submitted.disconnect(watch)
	assert_int(result).is_equal(OK)
	assert_int(_submitted).is_equal(0)
	var runner: MatchRunner = restorer.runner
	assert_bool(runner.wait_idle()).is_true()
	assert_int(runner.world.tick).is_equal(stage)
	assert_int(runner.world.state_hash()).is_equal(_hash_at[stage])
	assert_bool(runner.paused).is_true()
	if mode == WORKER:  # run_ticks plays inline; the AI thinks on its own thread (ADR 0038).
		assert_bool(runner._ai_thread != null and runner._ai_thread.is_started()).is_true()
	_play_to(runner, stage + MORE)
	assert_bool(runner.wait_idle()).is_true()
	assert_int(runner.world.state_hash()).is_equal(_hash_at[stage + MORE])
	# The restored log is the reference's log: its checkpoints are the reference's, tick for tick.
	var hashes: PackedInt64Array = PackedInt64Array(runner.replay.checkpoint_hashes)
	assert_int(hashes.size()).is_equal((stage + MORE) / Replay.CHECKPOINT_PERIOD)
	assert_array(hashes).is_equal(_checkpoints.slice(0, hashes.size()))
	restorer.abandon()
	assert_bool(runner.wait_idle()).is_true()


func test_a_restore_at_tick_300_equals_the_uninterrupted_match_gdscript_sync() -> void:
	_prove(EARLY, GDSCRIPT, SYNC)


func test_a_restore_at_tick_300_equals_the_uninterrupted_match_auto_sync() -> void:
	_prove(EARLY, AUTO, SYNC)


func test_a_restore_at_tick_300_equals_the_uninterrupted_match_gdscript_worker() -> void:
	_prove(EARLY, GDSCRIPT, WORKER)


func test_a_restore_at_tick_300_equals_the_uninterrupted_match_auto_worker() -> void:
	_prove(EARLY, AUTO, WORKER)


func test_a_restore_at_tick_3000_equals_the_uninterrupted_match_gdscript_sync() -> void:
	_prove(LATE, GDSCRIPT, SYNC)


func test_a_restore_at_tick_3000_equals_the_uninterrupted_match_auto_sync() -> void:
	_prove(LATE, AUTO, SYNC)


func test_a_restore_at_tick_3000_equals_the_uninterrupted_match_gdscript_worker() -> void:
	_prove(LATE, GDSCRIPT, WORKER)


func test_a_restore_at_tick_3000_equals_the_uninterrupted_match_auto_worker() -> void:
	_prove(LATE, AUTO, WORKER)


# --- Refusals ---------------------------------------------------------------------------------


func _refused(bytes: PackedByteArray, version: String, defs_hash: int) -> void:
	_warnings.clear()
	assert_object(ResumeStore.decode(bytes, version, defs_hash)).is_null()
	assert_int(_warnings.size()).is_equal(1)


func test_a_damaged_log_is_refused() -> void:
	var bytes: PackedByteArray = _bytes[EARLY].duplicate()
	bytes[bytes.size() - 5] ^= 0x40  # In the compressed log: the seal does not match.
	_refused(bytes, ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH)


func test_another_defs_hash_is_refused() -> void:
	var defs: int = _data(EARLY).defs_hash
	_refused(_bytes[EARLY], ResumeStore.app_version(), defs + 1)
	assert_object(ResumeStore.decode(_bytes[EARLY], ResumeStore.app_version(), defs)).is_not_null()


func test_another_app_version_is_refused() -> void:
	_refused(_bytes[EARLY], ResumeStore.app_version() + ".1", ResumeStore.ANY_DEFS_HASH)


func test_a_log_whose_checkpoint_was_changed_before_it_was_written_fails_the_restore() -> void:
	# A file with a right seal whose log does not replay to its own checkpoint: the writer's word
	# is not trusted past what the sim gives again.
	var data: ResumeData = _data(EARLY)
	data.replay.checkpoint_hashes[3] += 1
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene(GDSCRIPT, SYNC))).is_equal(OK)
	assert_int(_run(restorer)).is_equal(ERR_FILE_CORRUPT)
	assert_int(restorer.runner.world.tick).is_equal(4 * Replay.CHECKPOINT_PERIOD)
	assert_bool(ResumeWatcher.restoring).is_false()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()


func test_a_changed_end_hash_fails_the_restore_after_the_last_checkpoint() -> void:
	# 300 is a checkpoint tick, so the end hash is the same value as the last checkpoint's; a
	# resealed file that changes it is refused at the stored tick, not accepted.
	var data: ResumeData = _data(EARLY)
	data.end_hash += 1
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene(GDSCRIPT, SYNC))).is_equal(OK)
	assert_int(_run(restorer)).is_equal(ERR_FILE_CORRUPT)
	assert_int(restorer.runner.world.tick).is_equal(EARLY)
	assert_bool(restorer.runner.paused).is_false()
