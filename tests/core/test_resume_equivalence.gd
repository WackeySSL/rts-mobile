extends GdUnitTestSuite
## Resume proofs (plan P516, ADR 0042 sections 6 and 7): a skirmish written at tick 300 and at tick
## 3,007 (not a checkpoint tick, so the end hash has a gap to close), read back, restored by the
## Restorer and played on equals the uninterrupted match. The reference is one GDSCRIPT, SYNC match
## with the Hard AI (a second seed and order schedule is one more); each of the four runners
## (GDSCRIPT and AUTO, each SYNC and WORKER with the AI on its own thread) restores both files,
## compares the World's state hash and the file's end hash at the stored tick, then plays 100 ticks
## more with the reference's own orders and must end on the reference's hash, with the reference's
## checkpoint hashes. The restore feeds no order to `CommandQueue.submitted`. Refusals: a damaged
## log, another defs_hash, another app version, a changed checkpoint, a changed end hash.
##
## A thread suite (the AI thread): it runs three times in a row (CLAUDE.md). The 3,007-tick case
## stays in the regular suite: the whole file runs in a few seconds, so nothing is gated. In WORKER
## mode `run_ticks` plays inline and only the AI thinks on its own thread (ADR 0038). Ticks are
## counted, never timed: the Restorer's clock is a counter.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242
const PLAYER: int = 1
const UNITS: PackedInt32Array = [1, 2, 3]
const EARLY: int = 300
const LATE: int = 3007
const OTHER_SEED: int = 9001
const OTHER_EVERY: int = 170
const MORE: int = 100
const ORDER_EVERY: int = 250
const SLICE_TICKS: int = 64
const FRAME_LIMIT: int = 2000
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
const GDSCRIPT: int = MatchRunner.SimImpl.GDSCRIPT
const AUTO: int = MatchRunner.SimImpl.AUTO

## The references, by seed: {bytes: {stage: file bytes}, hash_at: {tick: hash}, checkpoints}.
## `_seed` and `_every` are the match and the order schedule in use; the first reference is SEED.
var _refs: Dictionary[int, Dictionary] = {}
var _seed: int = SEED
var _every: int = ORDER_EVERY
var _bytes: Dictionary = {}
var _hash_at: Dictionary = {}
var _checkpoints: PackedInt64Array = PackedInt64Array()
var _clock: int = 0
var _submitted: int = 0
var _warnings: Array[String] = []


func before() -> void:
	CommandQueue.clear()
	_refs[SEED] = _reference(SEED, ORDER_EVERY)
	_refs[OTHER_SEED] = _reference(OTHER_SEED, OTHER_EVERY)
	_use(SEED)


## Selects the reference of `seed` and its order schedule.
func _use(seed: int) -> void:
	_seed = seed
	_every = ORDER_EVERY if seed == SEED else OTHER_EVERY
	_bytes = _refs[seed]["bytes"]
	_hash_at = _refs[seed]["hash_at"]
	_checkpoints = _refs[seed]["checkpoints"]


## One uninterrupted GDSCRIPT, SYNC match: the files at EARLY and LATE and the hashes along the way.
func _reference(seed: int, every: int) -> Dictionary:
	_seed = seed
	_every = every
	var ref: Dictionary = {"bytes": {}, "hash_at": {}, "checkpoints": PackedInt64Array()}
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(_setup().apply(runner)).is_equal(OK)
	runner.start()
	for stage: int in [EARLY, LATE]:
		_play_to(runner, stage)
		ref["hash_at"][stage] = runner.world.state_hash()
		ref["bytes"][stage] = ResumeStore.encode(
			_setup(),
			runner.replay,
			stage,
			runner.world.defs_hash(),
			ResumeStore.app_version(),
			ref["hash_at"][stage]
		)
		assert_bool((ref["bytes"][stage] as PackedByteArray).is_empty()).is_false()
		_play_to(runner, stage + MORE)
		ref["hash_at"][stage + MORE] = runner.world.state_hash()
	ref["checkpoints"] = PackedInt64Array(runner.replay.checkpoint_hashes)
	CommandQueue.clear()
	return ref


func before_test() -> void:
	PrefsRig.begin()
	_use(SEED)
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
	PrefsRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = _seed
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	return setup


## The local player's order for tick `tick`, or null: a move or a stop every ORDER_EVERY ticks from
## tick 20, so both files hold orders and the play after each restore has more.
func _order(tick: int) -> Command:
	if tick < 20 or (tick - 20) % _every != 0:
		return null
	var step: int = (tick - 20) / _every
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


func test_a_restore_at_tick_3007_equals_the_uninterrupted_match_gdscript_sync() -> void:
	_prove(LATE, GDSCRIPT, SYNC)


func test_a_restore_at_tick_3007_equals_the_uninterrupted_match_auto_sync() -> void:
	_prove(LATE, AUTO, SYNC)


func test_a_restore_at_tick_3007_equals_the_uninterrupted_match_gdscript_worker() -> void:
	_prove(LATE, GDSCRIPT, WORKER)


func test_a_restore_at_tick_3007_equals_the_uninterrupted_match_auto_worker() -> void:
	_prove(LATE, AUTO, WORKER)


func test_a_restore_under_another_seed_and_order_schedule_equals_its_match() -> void:
	_use(OTHER_SEED)
	_prove(LATE, AUTO, WORKER)
	_prove(EARLY, GDSCRIPT, SYNC)


## Frames the way the game plays them: the runner's own `_process`, until it has reached `tick`.
func _play_free(runner: MatchRunner, tick: int) -> bool:
	var frames: int = 0
	while runner.snapshot.tick < tick and frames < 4000:
		runner._process(0.07)
		frames += 1
		OS.delay_msec(2)
	return runner.wait_idle() and runner.snapshot.tick >= tick


func test_a_worker_restore_played_on_by_frames_uses_the_sim_worker_and_keeps_the_checkpoints(
) -> void:
	var scene: Node = _scene(GDSCRIPT, WORKER)
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(_data(EARLY), scene)).is_equal(OK)
	assert_int(_run(restorer)).is_equal(OK)
	var runner: MatchRunner = restorer.runner
	assert_bool(runner.worker_active()).is_false()  # The restore played inline.
	runner.paused = false
	# The next local order is at tick 520: up to tick 450 the free play is the reference's.
	assert_bool(_play_free(runner, 450)).is_true()
	assert_bool(runner.worker_active()).is_true()
	var count: int = 450 / Replay.CHECKPOINT_PERIOD
	var hashes: PackedInt64Array = PackedInt64Array(runner.replay.checkpoint_hashes)
	assert_array(hashes.slice(0, count)).is_equal(_checkpoints.slice(0, count))
	restorer.abandon()
	assert_bool(runner.wait_idle()).is_true()


func test_a_file_written_from_a_free_running_worker_restores_in_sync_and_worker() -> void:
	var setup: MatchSetup = _setup()
	var live: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(live)).is_equal(OK)
	live.tick_mode = WORKER as MatchRunner.TickMode
	live.start()
	assert_bool(_play_free(live, 27)).is_true()
	# The sim worker is on its next job now, as at a pause between frames.
	live._process(0.07)
	assert_int(ResumeStore.write_from(live, setup)).is_equal(OK)
	var data: ResumeData = ResumeStore.read()
	assert_object(data).is_not_null()
	assert_bool(live.worker_active()).is_true()
	assert_bool(live.wait_idle()).is_true()
	assert_int(data.tick).is_equal(live.world.tick)
	for mode: int in [SYNC, WORKER]:
		var restorer: Restorer = _restorer()
		assert_int(restorer.begin(data, _scene(GDSCRIPT, mode))).is_equal(OK)
		assert_int(_run(restorer)).is_equal(OK)
		assert_int(restorer.runner.world.tick).is_equal(data.tick)
		assert_int(restorer.runner.world.state_hash()).is_equal(data.end_hash)
		restorer.abandon()
		assert_bool(restorer.runner.wait_idle()).is_true()


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
