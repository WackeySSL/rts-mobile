extends GdUnitTestSuite
## The resume restore's report line (plan row P516b, ADR 0042 sections 4 and 6). A skirmish of the
## resume proofs (tests/core/test_resume_equivalence.gd: the Derrick map, the Hard AI, a move or a
## stop every 250 ticks) is played to tick 3,000, written by ResumeStore.encode and restored by the
## Restorer in one frame, SYNC, the way the game restores a file. The suite prints one line,
## `PERF restore impl=... restore_ticks_per_s=... file_bytes=... est_15min_bytes=...`, and
## the job summary of ci.yml copies it under its own heading. Report only: nothing gates on a time.
## What is asserted is deterministic: the tick reached and the end hash, which is the reference's.
## The 15-minute estimate scales the file linearly with the ticks (13,500 ticks); the plan's target
## is under 1 MB compressed (plan line 353), and a restore time on the phone is Michael's PerfCard
## measurement, never this line's.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const HEAD: String = "PERF restore"
const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242
const PLAYER: int = 1
const UNITS: PackedInt32Array = [1, 2, 3]
const TICKS: int = 3000
const ORDER_EVERY: int = 250
## 15 minutes of game time at the tick rate of 15 Hz.
const MATCH_TICKS: int = 15 * 60 * 15
const USEC_PER_S: float = 1000000.0
## One frame plays the whole restore: the slice is far above any restore.
const WHOLE_SLICE_USEC: int = 3600 * 1000000
const FRAME_LIMIT: int = 8

var _ref_hash: int = 0
var _bytes: PackedByteArray = PackedByteArray()


func before() -> void:
	CommandQueue.clear()
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(_setup().apply(runner)).is_equal(OK)
	runner.start()
	while runner.snapshot.tick < TICKS:
		var order: Command = _order(runner.snapshot.tick)
		if order != null:
			CommandQueue.submit(order)
		runner.run_ticks(1)
	_ref_hash = runner.world.state_hash()
	_bytes = ResumeStore.encode(
		_setup(),
		runner.replay,
		TICKS,
		runner.world.defs_hash(),
		ResumeStore.app_version(),
		_ref_hash
	)
	CommandQueue.clear()


func before_test() -> void:
	PrefsRig.begin()
	CommandQueue.clear()


func after_test() -> void:
	ResumeWatcher.restoring = false
	AudioService.clear_mute_reason(AudioService.REASON_RESTORING)
	CommandQueue.clear()
	PrefsRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = SEED
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	return setup


## The local player's order for tick `tick`, or null (the resume proofs' schedule).
func _order(tick: int) -> Command:
	if tick < 20 or (tick - 20) % ORDER_EVERY != 0:
		return null
	var step: int = (tick - 20) / ORDER_EVERY
	if step % 3 == 2:
		return Command.stop(PLAYER, UNITS)
	var east: bool = step % 3 == 0
	return Command.move(PLAYER, UNITS, 20500 if east else 9500, 9500 if east else 20500)


func test_the_restore_of_a_skirmish_reaches_the_stored_tick_and_prints_its_perf_line() -> void:
	var data: ResumeData = ResumeStore.decode(
		_bytes, ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH
	)
	assert_object(data).is_not_null()
	assert_int(data.tick).is_equal(TICKS)
	assert_int(data.end_hash).is_equal(_ref_hash)
	var scene: Node = auto_free(Node.new())
	var runner: MatchRunner = MatchRunner.new()
	runner.name = "MatchRunner"
	runner.sim_impl = MatchRunner.SimImpl.AUTO
	runner.tick_mode = MatchRunner.TickMode.SYNC
	scene.add_child(runner)
	var restorer: Restorer = auto_free(Restorer.new())
	restorer.slice_usec = WHOLE_SLICE_USEC
	var done: Array[Error] = []
	restorer.finished.connect(func(result: Error) -> void: done.append(result))
	assert_int(restorer.begin(data, scene)).is_equal(OK)
	var started: int = Time.get_ticks_usec()
	for _frame: int in FRAME_LIMIT:
		if not done.is_empty():
			break
		restorer._process(0.0)
	var usec: int = maxi(1, Time.get_ticks_usec() - started)
	assert_array(done).is_equal([OK] as Array[Error])
	assert_bool(restorer.runner.wait_idle()).is_true()
	assert_int(restorer.runner.world.tick).is_equal(TICKS)
	assert_int(restorer.runner.world.state_hash()).is_equal(_ref_hash)
	var text: String = _line(usec)
	print(text)
	assert_bool(text.begins_with(HEAD + " ")).is_true()
	assert_bool(text.contains(" restore_ticks_per_s=")).is_true()
	assert_bool(text.contains(" file_bytes=%d " % _bytes.size())).is_true()
	restorer.abandon()
	assert_bool(restorer.runner.wait_idle()).is_true()


## `PERF restore impl=auto ticks=3000 restore_ms=... restore_ticks_per_s=... file_bytes=... ...`.
func _line(usec: int) -> String:
	var per_s: float = TICKS * USEC_PER_S / usec
	var estimate_bytes: int = _bytes.size() * MATCH_TICKS / TICKS
	var parts: PackedStringArray = PackedStringArray([HEAD, "impl=auto"])
	parts.append("ticks=%d" % TICKS)
	parts.append("restore_ms=%.1f" % (usec / 1000.0))
	parts.append("restore_ticks_per_s=%.1f" % per_s)
	parts.append("file_bytes=%d" % _bytes.size())
	parts.append("est_15min_ticks=%d" % MATCH_TICKS)
	parts.append("est_15min_bytes=%d" % estimate_bytes)
	parts.append("est_15min_restore_s=%.1f" % (MATCH_TICKS / per_s))
	parts.append("hash=%016x" % _ref_hash)
	return " ".join(parts)
