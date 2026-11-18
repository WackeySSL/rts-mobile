extends GdUnitTestSuite
## Restorer (plan P515, ADR 0042 section 6): a saved match played again off the tree equals the
## uninterrupted one, in counted ticks per frame (no timing), with no order chirp, the mute reason
## and the watcher flag held until the scene is in the tree, and a mismatch ending the restore.
## Files live in the PrefsRig folder.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const PLAYER: int = 1
const UNITS: PackedInt32Array = [1, 2, 3]
const SLICE_TICKS: int = 7
const FRAME_LIMIT: int = 400

var _submitted: int = 0
var _clock: int = 0


class FakeFlow:
	extends Node
	signal match_loading(setup: MatchSetup)
	var runner: MatchRunner = null
	var setup: MatchSetup = null

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return setup


func before_test() -> void:
	PrefsRig.begin()
	_submitted = 0
	_clock = 0
	CommandQueue.clear()


func after_test() -> void:
	ResumeWatcher.restoring = false
	AudioService.clear_mute_reason(AudioService.REASON_RESTORING)
	CommandQueue.clear()
	PrefsRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = 4242
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	return setup


## An uninterrupted match with local orders at ticks 20, 41 and 63, played to `ticks`, and the data
## its file reads back as.
func _played(ticks: int, scenario: ScenarioDef = null) -> Array:
	var setup: MatchSetup = _setup()
	if scenario != null:
		setup._scenario = scenario
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	var orders: Dictionary[int, Command] = {
		20: Command.move(PLAYER, UNITS, 20500, 9500),
		41: Command.stop(PLAYER, UNITS),
		63: Command.move(PLAYER, UNITS, 9500, 20500),
	}
	for _i: int in ticks:
		var order: Command = orders.get(runner.snapshot.tick, null)
		if order != null:
			CommandQueue.submit(order)
		runner.run_ticks(1)
	if scenario != null:  # Not a file: the log's scenario path is not the setup's.
		var made: ResumeData = ResumeData.new()
		made.setup = setup
		made.replay = runner.replay
		made.tick = runner.world.tick
		made.local_player = PLAYER
		made.defs_hash = runner.world.defs_hash()
		made.end_hash = runner.world.state_hash()
		return [runner, made]
	assert_int(ResumeStore.write_from(runner, setup)).is_equal(OK)
	return [runner, ResumeStore.read()]


func _scene() -> Node:
	var scene: Node = auto_free(Node.new())
	var runner: MatchRunner = MatchRunner.new()
	runner.name = "MatchRunner"
	scene.add_child(runner)
	return scene


## A restorer whose clock moves 1 per call and whose slice is SLICE_TICKS, so a frame plays exactly
## that many ticks.
func _restorer() -> Restorer:
	var restorer: Restorer = auto_free(Restorer.new())
	restorer.clock = func() -> int:
		_clock += 1
		return _clock
	restorer.slice_usec = SLICE_TICKS
	return restorer


func _run(restorer: Restorer) -> Array[Error]:
	var done: Array[Error] = []
	restorer.finished.connect(func(result: Error) -> void: done.append(result))
	for _frame: int in FRAME_LIMIT:
		if not done.is_empty():
			break
		restorer._process(0.0)
	return done


func _restore(ticks: int) -> Array:
	var played: Array = _played(ticks)
	var scene: Node = _scene()
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(played[1] as ResumeData, scene)).is_equal(OK)
	return [played[0], restorer, _run(restorer)]


func test_the_restored_world_equals_the_uninterrupted_one_at_a_checkpoint_tick() -> void:
	var result: Array = await _restore(90)
	var original: MatchRunner = result[0]
	var restorer: Restorer = result[1]
	assert_array(result[2]).is_equal([OK])
	assert_int(restorer.runner.world.tick).is_equal(90)
	assert_int(restorer.runner.world.state_hash()).is_equal(original.world.state_hash())
	assert_int(restorer.runner.last_hash).is_equal(original.last_hash)
	assert_int(restorer.runner.replay.final_tick).is_equal(original.replay.final_tick)


func test_the_restored_world_equals_the_uninterrupted_one_between_checkpoints() -> void:
	var result: Array = await _restore(100)
	var original: MatchRunner = result[0]
	var restorer: Restorer = result[1]
	assert_array(result[2]).is_equal([OK])
	assert_int(restorer.runner.world.tick).is_equal(100)
	assert_int(restorer.runner.world.state_hash()).is_equal(original.world.state_hash())
	# The new runner's own log is the same log again, so a second save works.
	assert_array(restorer.runner.replay.commands).is_equal(original.replay.commands)
	assert_array(restorer.runner.replay.checkpoint_hashes).is_equal(
		original.replay.checkpoint_hashes
	)


func test_a_restore_under_auto_equals_the_uninterrupted_gdscript_match() -> void:
	var played: Array = _played(60)
	var scene: Node = _scene()
	var restorer: Restorer = _restorer()
	scene.get_node("MatchRunner").sim_impl = MatchRunner.SimImpl.AUTO
	assert_int(restorer.begin(played[1] as ResumeData, scene)).is_equal(OK)
	assert_array(_run(restorer)).is_equal([OK])
	assert_int(restorer.runner.world.state_hash()).is_equal(
		(played[0] as MatchRunner).world.state_hash()
	)


func test_a_frame_plays_no_more_ticks_than_its_slice_and_at_least_one() -> void:
	var played: Array = _played(60)
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(played[1] as ResumeData, _scene())).is_equal(OK)
	restorer._process(0.0)
	assert_int(restorer.last_frame_ticks).is_equal(SLICE_TICKS)
	assert_int(restorer.runner.snapshot.tick).is_equal(SLICE_TICKS)
	restorer.slice_usec = 0  # Already over budget: still one tick.
	restorer._process(0.0)
	assert_int(restorer.last_frame_ticks).is_equal(1)


func test_progress_is_reported_per_frame() -> void:
	var played: Array = _played(30)
	var restorer: Restorer = _restorer()
	var seen: Array[Vector2i] = []
	restorer.progressed.connect(
		func(done: int, total: int) -> void: seen.append(Vector2i(done, total))
	)
	assert_int(restorer.begin(played[1] as ResumeData, _scene())).is_equal(OK)
	restorer._process(0.0)
	assert_array(seen).is_equal([Vector2i(SLICE_TICKS, 30)])


func test_no_order_chirp_and_the_mute_reason_is_held_until_the_scene_is_in_the_tree() -> void:
	var played: Array = _played(60)
	var watch: Callable = func(_command: Command) -> void: _submitted += 1
	CommandQueue.submitted.connect(watch)
	var scene: Node = _scene()
	var restorer: Restorer = _restorer()
	add_child(restorer)
	assert_int(restorer.begin(played[1] as ResumeData, scene)).is_equal(OK)
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_true()
	assert_array(_run(restorer)).is_equal([OK])
	CommandQueue.submitted.disconnect(watch)
	assert_int(_submitted).is_equal(0)
	assert_bool(restorer.runner.paused).is_true()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_true()
	assert_bool(ResumeWatcher.restoring).is_false()  # Only the mute waits.
	restorer.hand_over(scene)
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_true()
	add_child(scene)
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()
	assert_bool(ResumeWatcher.restoring).is_false()


func test_a_checkpoint_mismatch_stops_the_restore_and_releases_the_holds() -> void:
	var played: Array = _played(60)
	var data: ResumeData = played[1]
	data.replay.checkpoint_hashes[1] += 1
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene())).is_equal(OK)
	assert_array(_run(restorer)).is_equal([ERR_FILE_CORRUPT])
	assert_int(restorer.runner.snapshot.tick).is_equal(30)  # Stopped at the checkpoint that differs.
	assert_bool(restorer.runner.paused).is_false()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()
	assert_bool(ResumeWatcher.restoring).is_false()


func test_another_defs_hash_is_refused_before_a_tick_is_played() -> void:
	var played: Array = _played(30)
	var data: ResumeData = played[1]
	data.defs_hash += 1
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene())).is_equal(ERR_FILE_CORRUPT)
	assert_bool(ResumeWatcher.restoring).is_false()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()


func test_cancel_keeps_the_file_and_ends_with_skipped() -> void:
	var played: Array = _played(60)
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(played[1] as ResumeData, _scene())).is_equal(OK)
	var done: Array[Error] = []
	restorer.finished.connect(func(result: Error) -> void: done.append(result))
	restorer._process(0.0)
	restorer.cancel()
	assert_array(done).is_equal([ERR_SKIP])
	assert_bool(ResumeStore.has_file()).is_true()
	assert_bool(ResumeWatcher.restoring).is_false()
	restorer._process(0.0)  # Nothing runs after it.
	assert_int(restorer.last_frame_ticks).is_equal(SLICE_TICKS)


func test_the_watcher_keeps_the_file_and_writes_nothing_during_a_restore() -> void:
	var played: Array = _played(60)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(ResumeStore.path())
	var flow: FakeFlow = auto_free(FakeFlow.new())
	flow.setup = _setup()
	flow.runner = auto_free(MatchRunner.new())  # A partial match, as a pause mid-restore would see.
	assert_int(flow.setup.apply(flow.runner)).is_equal(OK)
	flow.runner.start()
	var watcher: ResumeWatcher = auto_free(ResumeWatcher.new())
	watcher.bind(flow)
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(played[1] as ResumeData, _scene())).is_equal(OK)
	restorer._process(0.0)
	flow.match_loading.emit(flow.setup)
	assert_bool(ResumeStore.has_file()).is_true()
	assert_int(watcher.write_now()).is_equal(ERR_BUSY)
	watcher.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_array(FileAccess.get_file_as_bytes(ResumeStore.path())).is_equal(before)
	restorer.cancel()
	# After the restore a match start deletes the file again.
	flow.match_loading.emit(flow.setup)
	assert_bool(ResumeStore.has_file()).is_false()


func test_only_the_local_orders_before_the_stored_tick_are_fed() -> void:
	var played: Array = _played(40)
	var data: ResumeData = played[1]
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene())).is_equal(OK)
	# The orders are at ticks 20, 41 and 63; the log ends at 40, so one is fed (the skirmish gives
	# the local player no orders of its own to skip).
	assert_int(restorer._local.size()).is_equal(1)


func test_a_scenario_order_of_the_local_player_is_not_fed_twice() -> void:
	var scenario: ScenarioDef = load(SCENARIO).duplicate() as ScenarioDef
	var order: OrderDef = OrderDef.new()
	order.tick = 5
	order.player = PLAYER
	order.target_tile = Vector2i(12, 9)
	scenario.orders = [order]
	var played: Array = _played(60, scenario)
	var data: ResumeData = played[1]
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene())).is_equal(OK)
	assert_int(restorer._local.size()).is_equal(2)
	# The moves at ticks 20 and 41; the tick 5 order is the scenario's (fed twice it would be 3).
	assert_array(_run(restorer)).is_equal([OK])
	assert_int(restorer.runner.world.state_hash()).is_equal(
		(played[0] as MatchRunner).world.state_hash()
	)


func test_a_wrong_end_hash_fails_the_restore_at_the_stored_tick() -> void:
	# 100 is between checkpoints (90 and 105): only the end hash can catch a difference there.
	var played: Array = _played(100)
	var data: ResumeData = played[1]
	assert_int(data.end_hash).is_equal((played[0] as MatchRunner).world.state_hash())
	data.end_hash += 1
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene())).is_equal(OK)
	assert_array(_run(restorer)).is_equal([ERR_FILE_CORRUPT])
	assert_int(restorer.runner.snapshot.tick).is_equal(100)
	assert_bool(restorer.runner.paused).is_false()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()
	assert_bool(ResumeWatcher.restoring).is_false()


func test_the_end_hash_of_a_checkpoint_tick_is_checked_too() -> void:
	var played: Array = _played(90)
	var data: ResumeData = played[1]
	data.end_hash += 1
	var restorer: Restorer = _restorer()
	assert_int(restorer.begin(data, _scene())).is_equal(OK)
	assert_array(_run(restorer)).is_equal([ERR_FILE_CORRUPT])
