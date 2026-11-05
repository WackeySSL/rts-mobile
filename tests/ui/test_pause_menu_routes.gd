extends GdUnitTestSuite
## The pause menu's routes and its turn (plan P124, ADR 0025 section 11): the Yes of Restart opens
## a new main scene of the same scenario with the same computer opponent, the Yes of Exit to menu
## and the Developer menu button open the dev menu, SURRENDER is sent once per match, an open
## confirm keeps the keyboard focus through the HUD's other `changed`s, and a turn of the window
## keeps the menu open and the match paused in the other layout. The rest is test_pause_menu's.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _main: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


## Restart's yes: a new main scene of the same scenario with the same dummy, a match of its own,
## the pause gone. A Restart that dropped the opponents, or a swapped route, fails here.
func test_restart_yes_opens_a_new_match_of_the_same_scenario_and_opponents() -> void:
	for scenario_path: String in [MatchRig.DERRICK, MatchRig.LUMEN]:
		var tree: SceneTree = get_tree()
		var old: Node = await _scene_in_root(scenario_path)
		var dummy_id: StringName = (old.get_node("MatchRunner") as MatchRunner).opponents[0].id
		_confirm(old, "RestartButton")
		await await_idle_frame()
		await await_idle_frame()
		var again: Node = tree.current_scene
		assert_bool(again != old).is_true()
		assert_str(again.scene_file_path).is_equal(DevRoutes.MAIN_SCENE)
		var runner: MatchRunner = again.get_node("MatchRunner")
		assert_str(runner.scenario.resource_path).is_equal(scenario_path)
		assert_int(runner.opponents.size()).is_equal(1)
		assert_str(str(runner.opponents[0].id)).is_equal(str(dummy_id))
		assert_bool(runner.paused).is_false()
		assert_int(runner.snapshot.match_end_tick).is_equal(0)
		assert_bool((again.get_node("Hud/PauseMenu") as Control).visible).is_false()
		again.free()
		tree.current_scene = null
		CommandQueue.clear()


## Exit's yes and the Developer menu button both open the dev menu.
func test_exit_yes_and_the_developer_menu_button_open_the_dev_menu() -> void:
	var tree: SceneTree = get_tree()
	for route: String in ["ExitButton", "DevMenuButton"]:
		if not DevRoutes.is_enabled() and route == "DevMenuButton":
			continue
		var old: Node = await _scene_in_root(MatchRig.DERRICK)
		if route == "ExitButton":
			_confirm(old, route)
		else:
			(old.find_child(route, true, false) as Button).pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		assert_str(tree.current_scene.scene_file_path).override_failure_message(route).is_equal(
			DevRoutes.DEV_MENU_SCENE
		)
		tree.current_scene.free()
		tree.current_scene = null
		CommandQueue.clear()


## One SURRENDER per match: after the confirm the menu does not open again and a second confirm
## sends nothing.
func test_surrender_is_sent_once_per_match() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	var sent: Array[Command] = []
	(_main.get_node("PlayerController") as PlayerController).command_sink = func(
		command: Command
	) -> void:
		sent.append(command)
	var menu: PauseMenu = _main.get_node("Hud/PauseMenu")
	var state: HudState = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	_confirm(_main, "SurrenderButton")
	assert_array(sent).has_size(1)
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()  # The SURRENDER is still on its way.
	assert_bool(state.is_open(HudState.Unfold.PAUSE)).is_false()
	menu.call("_surrender")
	assert_array(sent).has_size(1)


## A `changed` that leaves PAUSE open (the bar's width, the pin) does not move the focus from an
## open confirm to Resume under it.
func test_an_open_confirm_keeps_the_focus_through_other_changes() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	var state: HudState = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	var menu: PauseMenu = _main.get_node("Hud/PauseMenu")
	(menu.find_child("SurrenderButton", true, false) as Button).pressed.emit()
	await await_idle_frame()
	var no_button: Button = null
	for dialog: Node in menu.find_children("*", "ConfirmDialog", true, false):
		if (dialog as ConfirmDialog).visible:
			no_button = dialog.find_child("NoButton", true, false) as Button
	assert_object(no_button).is_not_null()
	assert_bool(no_button.has_focus()).is_true()
	state.set_bar(true, 321.0)  # A `changed` with PAUSE still open.
	state.pinned = true
	assert_bool(no_button.has_focus()).is_true()
	state.pinned = false


## A turn keeps the menu open and the match paused, and the card and the buttons take the other
## layout: side by side sideways, one above the other upright, every button inside the safe rect.
func test_a_turn_keeps_the_menu_open_and_the_match_paused() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	var state: HudState = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	var menu: PauseMenu = _main.get_node("Hud/PauseMenu")
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	var tick: int = runner.snapshot.tick
	for size: Vector2i in [
		ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]
	]:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		var why: String = str(size)
		assert_bool(state.is_open(HudState.Unfold.PAUSE)).override_failure_message(why).is_true()
		assert_bool(runner.paused).override_failure_message(why).is_true()
		assert_int(runner.snapshot.tick).override_failure_message(why).is_equal(tick)
		assert_bool(menu.visible).override_failure_message(why).is_true()
		var body: BoxContainer = (
			menu.find_child("ResumeButton", true, false).get_parent().get_parent().get_parent()
		)
		assert_bool(body.vertical).override_failure_message(why).is_equal(size.y > size.x)
		var card: Rect2 = (body.get_child(0) as Control).get_global_rect()
		var grid: Rect2 = (body.get_child(1) as Control).get_global_rect()
		if size.y > size.x:
			assert_float(grid.position.y).override_failure_message(why).is_greater_equal(
				card.end.y - TOLERANCE_PX
			)
		else:
			assert_float(grid.position.x).override_failure_message(why).is_greater_equal(
				card.end.x - TOLERANCE_PX
			)
		var safe: Rect2 = UiScale.safe_rect_base()
		for node: Node in menu.find_children("*", "Button", true, false):
			var button: Button = node as Button
			if button.is_visible_in_tree():
				assert_bool(safe.grow(TOLERANCE_PX).encloses(button.get_global_rect())).is_true()


## A main scene on `scenario_path` as the tree's current scene (a route changes it), with the pause
## menu open.
func _scene_in_root(scenario_path: String) -> Node:
	var tree: SceneTree = get_tree()
	var old: Node = await MatchRig.open(self, scenario_path)
	remove_child(old)
	tree.root.add_child(old)
	tree.current_scene = old
	old.get_node("Hud/EconomyPill").menu_pressed.emit()
	return old


## Presses `button_name` of the open pause menu of `scene` and answers its confirm with yes.
func _confirm(scene: Node, button_name: String) -> void:
	var menu: PauseMenu = scene.get_node("Hud/PauseMenu")
	if not menu.visible:
		scene.get_node("Hud/EconomyPill").menu_pressed.emit()
	(menu.find_child(button_name, true, false) as Button).pressed.emit()
	for dialog: Node in menu.find_children("*", "ConfirmDialog", true, false):
		if (dialog as ConfirmDialog).visible:
			dialog.find_child("YesButton", true, false).pressed.emit()
			return
