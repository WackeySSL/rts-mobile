extends GdUnitTestSuite
## ResumeWatcher (plan P514, ADR 0042 sections 5 and 6) against a fake MenuFlow with the same seams:
## it writes on the app pause, keeps the file of a killed match while none runs, and deletes it when
## a match starts, ends, is left or replaced. Files live in the PrefsRig folder.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const TICKS: int = 40


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


func after_test() -> void:
	PrefsRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = 4242
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	return setup


func _runner(setup: MatchSetup) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	runner.run_ticks(TICKS)
	return runner


func _written() -> void:
	var setup: MatchSetup = _setup()
	assert_int(ResumeStore.write_from(_runner(setup), setup)).is_equal(OK)


func _watched(flow: FakeFlow) -> ResumeWatcher:
	var watcher: ResumeWatcher = auto_free(ResumeWatcher.new())
	watcher.bind(flow)
	return watcher


func _flow_with_match() -> FakeFlow:
	var flow: FakeFlow = auto_free(FakeFlow.new())
	flow.setup = _setup()
	flow.runner = _runner(flow.setup)
	return flow


func test_the_app_pause_writes_the_running_match() -> void:
	var watcher: ResumeWatcher = _watched(_flow_with_match())
	watcher.notification(NOTIFICATION_APPLICATION_PAUSED)
	var data: ResumeData = ResumeStore.read()
	assert_object(data).is_not_null()
	assert_int(data.tick).is_equal(TICKS)


func test_the_app_pause_with_no_match_keeps_the_file_of_a_killed_one() -> void:
	_written()
	var watcher: ResumeWatcher = _watched(auto_free(FakeFlow.new()))
	watcher.notification(NOTIFICATION_APPLICATION_PAUSED)
	watcher._process(0.0)
	assert_bool(ResumeStore.has_file()).is_true()


func test_a_new_match_or_restart_deletes_the_file() -> void:
	_written()
	var flow: FakeFlow = auto_free(FakeFlow.new())
	_watched(flow)
	flow.match_loading.emit(_setup())
	assert_bool(ResumeStore.has_file()).is_false()


func test_the_end_of_the_match_deletes_the_file() -> void:
	var flow: FakeFlow = _flow_with_match()
	var watcher: ResumeWatcher = _watched(flow)
	watcher._process(0.0)
	watcher.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_bool(ResumeStore.has_file()).is_true()
	flow.runner.match_ended.emit(1)
	assert_bool(ResumeStore.has_file()).is_false()


func test_leaving_the_match_deletes_the_file_but_following_it_does_not() -> void:
	var flow: FakeFlow = _flow_with_match()
	var watcher: ResumeWatcher = _watched(flow)
	watcher._process(0.0)
	watcher.notification(NOTIFICATION_APPLICATION_PAUSED)
	watcher._process(0.0)
	assert_bool(ResumeStore.has_file()).is_true()
	flow.runner = null
	watcher._process(0.0)
	assert_bool(ResumeStore.has_file()).is_false()


func test_a_restored_match_appearing_does_not_delete_the_file() -> void:
	_written()
	var flow: FakeFlow = auto_free(FakeFlow.new())
	var watcher: ResumeWatcher = _watched(flow)
	watcher._process(0.0)
	flow.setup = _setup()
	flow.runner = _runner(flow.setup)
	watcher._process(0.0)
	assert_bool(ResumeStore.has_file()).is_true()


func test_a_freed_runner_counts_as_leaving_the_match() -> void:
	var flow: FakeFlow = _flow_with_match()
	var watcher: ResumeWatcher = _watched(flow)
	watcher._process(0.0)
	watcher.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_bool(ResumeStore.has_file()).is_true()
	flow.runner.free()  # The scene change ran after the watcher's frame; the flow still holds it.
	watcher._process(0.0)
	assert_bool(ResumeStore.has_file()).is_false()
	watcher._process(0.0)
