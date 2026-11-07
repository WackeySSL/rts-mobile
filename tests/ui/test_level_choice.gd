extends GdUnitTestSuite
## The level choice (plan P183, ADR 0030): the dev menu shows Easy, Normal and Hard of at least 48
## dp, Normal chosen at the start with the choice named in a label; each Skirmish button starts the
## computer (`OpponentDef`) of the other side at the chosen level; the pause menu's Restart and the
## result screen's Play again keep the opponent, the level and the seat. The layout at the six sizes
## and both orientations is test_dev_menu_layout's (it lists these buttons too).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const LEVEL_BUTTONS: Array[String] = ["LevelEasyButton", "LevelNormalButton", "LevelHardButton"]
const LEVEL_IDS: Array[StringName] = [&"easy", &"normal", &"hard"]
const ROUTES: Array[Dictionary] = [
	{"button": "SkirmishDerrickButton", "opponent": &"opponent_renew"},
	{"button": "SkirmishLumenButton", "opponent": &"opponent_fossil"},
]
const THINK_TICKS: int = 300

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null
	CommandQueue.clear()


## The level files carry the ids of their buttons; the computers are `OpponentDef`s, the dummies
## (kept for tests/e2e) are plain `AiDef`s.
func test_the_paths_load_the_computers_and_the_three_levels() -> void:
	var levels: Array[String] = [DevRoutes.LEVEL_EASY, DevRoutes.LEVEL_NORMAL, DevRoutes.LEVEL_HARD]
	for index: int in levels.size():
		var level: AiDifficultyDef = load(levels[index]) as AiDifficultyDef
		assert_object(level).is_not_null()
		assert_str(str(level.id)).is_equal(str(LEVEL_IDS[index]))
	for path: String in [DevRoutes.OPPONENT_FOSSIL, DevRoutes.OPPONENT_RENEW]:
		assert_bool(load(path) is OpponentDef).override_failure_message(path).is_true()
	for path: String in [DevRoutes.DUMMY_FOSSIL, DevRoutes.DUMMY_RENEW]:
		assert_bool(load(path) is AiDef and not load(path) is OpponentDef).is_true()


## Three toggle buttons of at least 48 dp; Normal is down at the start and the label says so. The
## six sizes are test_dev_menu_layout's.
func test_three_level_buttons_normal_chosen_at_the_start_and_the_choice_shown() -> void:
	var menu: Node = await _open_menu()
	var floor_px: float = UiScale.dp(48.0) - 0.5
	var names: Array[String] = ["Easy", "Normal", "Hard"]
	for index: int in LEVEL_BUTTONS.size():
		var button: Button = menu.find_child(LEVEL_BUTTONS[index], true, false)
		var label: String = LEVEL_BUTTONS[index]
		assert_str(button.text).override_failure_message(label).is_equal(names[index])
		assert_bool(button.disabled).override_failure_message(label).is_false()
		(
			assert_bool(button.get_global_rect().size.y >= floor_px)
			. override_failure_message(label)
			. is_true()
		)
		assert_bool(button.button_pressed).override_failure_message(label).is_equal(index == 1)
	assert_str((menu.find_child("LevelLabel", true, false) as Label).text).is_equal("Level: Normal")


func test_pressing_a_level_moves_the_choice_and_its_label() -> void:
	var menu: Node = await _open_menu()
	var shown: Label = menu.find_child("LevelLabel", true, false)
	for index: int in [2, 0, 1]:
		(menu.find_child(LEVEL_BUTTONS[index], true, false) as Button).button_pressed = true
		for other: int in LEVEL_BUTTONS.size():
			var button: Button = menu.find_child(LEVEL_BUTTONS[other], true, false)
			assert_bool(button.button_pressed).is_equal(other == index)
		assert_str(shown.text).is_equal("Level: %s" % str(LEVEL_IDS[index]).capitalize())


## Both Skirmish buttons at each level: the other side's `OpponentDef` as player 2 at that level
## (Normal without a press), and the computer plays: it sends Commands as player 2.
func test_each_skirmish_button_starts_the_other_sides_computer_at_the_chosen_level() -> void:
	for route: Dictionary in ROUTES:
		for chosen: int in [-1, 0, 1, 2]:  # -1: no press, the level of the start.
			var main: Node = await _start(route["button"], chosen)
			var runner: MatchRunner = main.get_node("MatchRunner")
			var label: String = "%s at %d" % [route["button"], chosen]
			assert_int(runner.opponents.size()).override_failure_message(label).is_equal(1)
			(
				assert_bool(runner.opponents[0] is OpponentDef)
				. override_failure_message(label)
				. is_true()
			)
			assert_str(str(runner.opponents[0].id)).override_failure_message(label).is_equal(
				str(route["opponent"])
			)
			assert_int(runner.opponent_levels.size()).is_equal(1)
			assert_str(str(runner.opponent_levels[0].id)).override_failure_message(label).is_equal(
				str(LEVEL_IDS[1 if chosen < 0 else chosen])
			)
			assert_int(runner.first_opponent).is_equal(2)
			main.free()
			get_tree().current_scene = null
			CommandQueue.clear()


func test_the_computer_of_a_route_plays_as_player_2() -> void:
	var main: Node = await _start("SkirmishDerrickButton", 2)
	var runner: MatchRunner = main.get_node("MatchRunner")
	runner.run_ticks(THINK_TICKS)
	var players: Dictionary[int, bool] = {}
	var at: int = 0
	while at < runner.replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(runner.replay.commands, at, command)
		assert_int(at).is_greater(0)
		if at <= 0:
			break
		players[command.player_id] = true
	assert_dict(players).is_equal({2: true})
	assert_int(runner.world.dropped_commands).is_equal(0)


## Restart's yes on a Hard Lumen Skirmish: the new match has the same computer at Hard.
func test_the_pause_menus_restart_keeps_the_opponent_and_the_level() -> void:
	for chosen: int in [0, 2]:
		var old: Node = await _start("SkirmishLumenButton", chosen)
		(old.get_node("MatchRunner") as MatchRunner).first_opponent = 1  # Not the default seat.
		var facts: Dictionary = _facts(old)
		var menu: PauseMenu = old.get_node("Hud/PauseMenu")
		old.get_node("Hud/EconomyPill").menu_pressed.emit()
		(menu.find_child("RestartButton", true, false) as Button).pressed.emit()
		var asking: Array[Node] = menu.find_children("*", "ConfirmDialog", true, false).filter(
			func(dialog: Node) -> bool: return (dialog as ConfirmDialog).visible
		)
		assert_int(asking.size()).is_equal(1)  # Restart asks first.
		asking[0].find_child("YesButton", true, false).pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		_expect_same_opponent(facts, get_tree().current_scene, "restart", chosen)
		get_tree().current_scene.free()
		get_tree().current_scene = null
		CommandQueue.clear()


## Play again on a won match: the same computer at the same level.
func test_the_result_screens_play_again_keeps_the_opponent_and_the_level() -> void:
	for chosen: int in [0, 2]:
		var old: Node = await _start("SkirmishDerrickButton", chosen)
		(old.get_node("MatchRunner") as MatchRunner).first_opponent = 1  # Not the default seat.
		var facts: Dictionary = _facts(old)
		CommandQueue.submit(Command.surrender(2))
		(old.get_node("MatchRunner") as MatchRunner).run_ticks(1)
		var screen: Node = old.find_child("ResultScreen", true, false)
		(screen.find_child("PlayAgainButton", true, false) as Button).pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		_expect_same_opponent(facts, get_tree().current_scene, "play again", chosen)
		get_tree().current_scene.free()
		get_tree().current_scene = null
		CommandQueue.clear()


## The opponent's id and seat of `main`'s runner, read before a scene change frees it.
func _facts(main: Node) -> Dictionary:
	var runner: MatchRunner = main.get_node("MatchRunner")
	return {
		"id": str(runner.opponents[0].id),
		"seat": runner.first_opponent,
		"scene": main.get_instance_id()
	}


## The match `again` has the opponent, seat and level `facts` name, in a scene of its own.
func _expect_same_opponent(facts: Dictionary, again: Node, what: String, chosen: int) -> void:
	var runner: MatchRunner = again.get_node("MatchRunner")
	var label: String = "%s at %d" % [what, chosen]
	assert_bool(again.get_instance_id() != facts["scene"]).override_failure_message(label).is_true()
	assert_int(runner.opponents.size()).override_failure_message(label).is_equal(1)
	assert_str(str(runner.opponents[0].id)).override_failure_message(label).is_equal(facts["id"])
	assert_bool(runner.opponents[0] is OpponentDef).override_failure_message(label).is_true()
	assert_int(runner.opponent_levels.size()).override_failure_message(label).is_equal(1)
	assert_str(str(runner.opponent_levels[0].id)).override_failure_message(label).is_equal(
		str(LEVEL_IDS[chosen])
	)
	assert_int(runner.first_opponent).override_failure_message(label).is_equal(facts["seat"])


## The dev menu, `level` (an index of LEVEL_BUTTONS, -1 none) pressed, then `button_name`; the new
## scene. The old menu is freed by the scene change.
func _start(button_name: String, level: int) -> Node:
	var menu: Node = await _open_menu()
	if level >= 0:
		(menu.find_child(LEVEL_BUTTONS[level], true, false) as Button).button_pressed = true
	(menu.find_child(button_name, true, false) as Button).pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	var main: Node = get_tree().current_scene
	assert_str(main.scene_file_path).is_equal(DevRoutes.MAIN_SCENE)
	return main


func _open_menu() -> Node:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	return menu
