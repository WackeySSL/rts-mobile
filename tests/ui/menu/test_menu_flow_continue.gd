extends GdUnitTestSuite
## MenuFlow.continue_match (plan P515, ADR 0042 section 6) with the scene changes replaced: the
## restore keeps its file (no `match_loading`), hands the paused match over, and a failed restore
## deletes the file and goes back to the menu with a notice. Cancel keeps the file.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const StuckRunner: GDScript = preload("res://tests/core/support/stuck_runner.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"
const TICKS: int = 45

var _flow: Node
var _menus: int = 0
var _mains: Array[Node] = []


func before_test() -> void:
	MenuRig.begin()
	_menus = 0
	_mains.clear()
	_flow = auto_free((load("res://game/ui/menu/menu_flow_service.gd") as GDScript).new())
	add_child(_flow)
	_flow.switch_to_main = _enter_main
	_flow.switch_to_menu = _enter_menu


func after_test() -> void:
	for main: Node in _mains:
		if is_instance_valid(main):
			remove_child(main)
			main.free()
	ResumeWatcher.restoring = false
	AudioService.clear_mute_reason(AudioService.REASON_RESTORING)
	MenuRig.end()


func _enter_main(main: Node) -> Error:
	_mains.append(main)
	add_child(main)
	return OK


func _enter_menu() -> Error:
	_menus += 1
	return OK


## Plays a match for TICKS and writes its file; `damage` spoils a checkpoint first.
func _file(damage: bool = false) -> MatchRunner:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	setup.opponents = [load(DUMMY) as AiDef]
	setup.opponent_levels = [load(LEVEL) as AiDifficultyDef]
	setup.match_seed = 4242
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	runner.run_ticks(TICKS)
	if damage:
		runner.replay.checkpoint_hashes[0] += 1
	assert_int(ResumeStore.write_from(runner, setup)).is_equal(OK)
	return runner


func test_a_restore_hands_over_the_paused_match_and_keeps_the_file() -> void:
	var original: MatchRunner = _file()
	var loading: Array[int] = []
	_flow.match_loading.connect(func(_s: MatchSetup) -> void: loading.append(1))
	assert_int(await _flow.continue_match()).is_equal(OK)
	assert_array(loading).is_empty()
	assert_bool(ResumeStore.has_file()).is_true()
	assert_int(_mains.size()).is_equal(1)
	assert_int(_menus).is_equal(0)
	var runner: MatchRunner = _flow.current_runner()
	assert_object(runner).is_not_null()
	assert_int(runner.world.tick).is_equal(TICKS)
	assert_int(runner.world.state_hash()).is_equal(original.world.state_hash())
	assert_bool(runner.paused).is_true()
	assert_object(_flow.current_setup()).is_not_null()
	await await_idle_frame()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()
	assert_bool(ResumeWatcher.restoring).is_false()
	# The pause menu is open over the paused match.
	var menu: PauseMenu = _mains[0].find_children("*", "PauseMenu", true, false)[0] as PauseMenu
	assert_bool(menu.visible).is_true()
	assert_bool(menu.feed.state.is_open(HudState.Unfold.PAUSE)).is_true()


## A scene with just a runner: a main scene freed before it entered the tree leaves orphans (its
## HUD builds nodes in `_init` and adds them in `_ready`), so the failing paths use this one.
func _light() -> Node:
	var scene: Node = Node.new()
	var runner: MatchRunner = MatchRunner.new()
	runner.name = "MatchRunner"
	scene.add_child(runner)
	return scene


func test_a_failed_restore_deletes_the_file_and_opens_the_menu_with_a_notice() -> void:
	_file(true)
	_flow.make_main = _light
	assert_int(await _flow.continue_match()).is_equal(ERR_FILE_CORRUPT)
	assert_bool(ResumeStore.has_file()).is_false()
	assert_int(_menus).is_equal(1)
	assert_int(_mains.size()).is_equal(0)
	assert_str(_flow.take_pending_notice()).is_equal(MainMenuText.RESTORE_FAILED)
	assert_str(_flow.take_pending_notice()).is_equal("")
	assert_bool(ResumeWatcher.restoring).is_false()
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()


func test_cancel_keeps_the_file_and_gives_no_notice() -> void:
	_file()
	_flow.make_main = _light
	_flow.restore_started.connect(
		func(restorer: Restorer) -> void:
			restorer.slice_usec = 1  # One tick a frame, so the first frame reports and is over.
			restorer.progressed.connect(
				func(_done: int, _total: int) -> void: _flow.cancel_restore()
			)
	)
	assert_int(await _flow.continue_match()).is_equal(ERR_SKIP)
	assert_bool(ResumeStore.has_file()).is_true()
	assert_int(_menus).is_equal(1)
	assert_str(_flow.take_pending_notice()).is_equal("")


func test_a_damaged_file_that_has_a_pointer_goes_back_to_the_menu_with_the_notice() -> void:
	_file()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ResumeStore.path())
	bytes[bytes.size() - 1] ^= 0xFF  # The seal fails; the pointer stays.
	var file: FileAccess = FileAccess.open(ResumeStore.path(), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_bool(ResumeStore.has_file()).is_true()
	ResumeStore.warning_sink = func(_text: String) -> void: pass
	assert_int(await _flow.continue_match()).is_equal(ERR_FILE_NOT_FOUND)
	ResumeStore.warning_sink = Callable()
	assert_bool(ResumeStore.has_file()).is_false()
	assert_int(_menus).is_equal(1)
	assert_str(_flow.take_pending_notice()).is_equal(MainMenuText.RESTORE_FAILED)


func test_cancel_with_no_restore_running_leaves_for_the_menu() -> void:
	_flow.cancel_restore()
	assert_int(_menus).is_equal(1)


func test_a_restored_match_takes_the_saved_reduced_switch() -> void:
	_file()
	var life: LifeSettings = load("res://data/life_settings.tres") as LifeSettings
	var before: bool = life.reduced
	MenuPrefs.set_reduced_effects(true)
	assert_int(await _flow.continue_match()).is_equal(OK)
	assert_bool(life.reduced).is_true()
	MenuPrefs.set_reduced_effects(false)
	life.reduced = before


func test_the_autoload_installs_the_resume_watcher() -> void:
	var watcher: ResumeWatcher = get_tree().root.get_node_or_null("ResumeWatcher") as ResumeWatcher
	assert_object(watcher).is_not_null()
	assert_object(watcher.flow).is_same(MenuFlow)


func test_a_restore_that_times_out_keeps_the_file_and_opens_the_menu_with_the_notice() -> void:
	_file()
	_flow.make_main = func() -> Node:
		var scene: Node = Node.new()
		var runner: MatchRunner = StuckRunner.new()
		runner.stuck = true
		runner.name = "MatchRunner"
		scene.add_child(runner)
		return scene
	assert_int(await _flow.continue_match()).is_equal(ERR_TIMEOUT)
	assert_bool(ResumeStore.has_file()).is_true()
	assert_int(_menus).is_equal(1)
	assert_str(_flow.take_pending_notice()).is_equal(MainMenuText.RESTORE_FAILED)
