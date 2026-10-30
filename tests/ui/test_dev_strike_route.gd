extends GdUnitTestSuite
## The "Strike test" dev route (plan row P112d): the dev menu has a "Strike test" button next to
## "Test map", and pressing it opens the main scene with `data/scenarios/dev_strikes.tres` in the
## MatchRunner, where "Test map" still opens it with the scene's own scenario. In that match the
## strike button shows for the local player at the six sizes, and the touch steps of a
## rupture work end to end: aim, place, confirm, and the sim takes the one SUPERWEAPON. The layout
## of the menu at the six sizes is test_dev_menu_layout's, the scenario's data are
## test_dev_strikes', the other routes are test_dev_routes'.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TEST_MAP_SCENARIO: String = "res://data/scenarios/controls_test.tres"
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
## Where the rupture is aimed, in milli-tiles: between the enemy Headquarters and its batteries.
const AIM_POINT: Vector2i = Vector2i(29000, 12000)

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The scene a test left is freed, and the orders a test queued are dropped.
func after_test() -> void:
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null
	CommandQueue.clear()


func test_the_dev_menu_lists_strike_test_right_after_test_map_as_an_enabled_button() -> void:
	var menu: Node = await _open_menu()
	var column: Node = menu.find_child("Column", true, false)
	var test_map: Button = menu.find_child("TestMapButton", true, false)
	var strike: Button = menu.find_child("StrikeTestButton", true, false)
	assert_object(strike).is_not_null()
	assert_str(strike.text).is_equal("Strike test")
	assert_bool(strike.disabled).is_false()
	assert_int(strike.get_index()).is_equal(test_map.get_index() + 1)
	assert_object(strike.get_parent()).is_same(column)


func test_strike_test_opens_the_main_scene_with_the_strike_scenario() -> void:
	var main: Node = await _press("StrikeTestButton")
	assert_str(main.scene_file_path).is_equal(DevRoutes.MAIN_SCENE)
	var runner: MatchRunner = main.get_node("MatchRunner")
	assert_str(runner.scenario.resource_path).is_equal(DevRoutes.STRIKE_TEST_SCENARIO)
	assert_str(DevRoutes.STRIKE_TEST_SCENARIO).is_equal("res://data/scenarios/dev_strikes.tres")
	# The match was built from it, not from the scene's own scenario: the local player has both.
	var types: Array[StringName] = []
	for row: int in runner.world.unit_count():
		if runner.world.owner[row] == 1:
			types.append(runner.world.type_ids[runner.world.type_index[row]])
	assert_array(types).contains([&"fossil_strike", &"renew_strike"])


func test_test_map_still_opens_the_main_scene_with_its_own_scenario() -> void:
	var main: Node = await _press("TestMapButton")
	assert_str(main.scene_file_path).is_equal(DevRoutes.MAIN_SCENE)
	var runner: MatchRunner = main.get_node("MatchRunner")
	assert_str(runner.scenario.resource_path).is_equal(TEST_MAP_SCENARIO)
	for row: int in runner.world.unit_count():
		(
			assert_bool(runner.world.type_ids[runner.world.type_index[row]] == &"fossil_strike")
			. is_false()
		)


## The route works at the six sizes of both orientations (the turn is test_ui_orientation_flip's):
## the strike button shows inside the window, at least 48 dp each way, so the first thing to try is
## in reach.
func test_the_strike_button_shows_in_reach_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		var main: Node = await _press("StrikeTestButton")
		await await_idle_frame()
		var button: Control = main.find_child("StrikeButton", true, false)
		var why: String = "%s: %s" % [size, button.get_global_rect()]
		assert_bool(button.is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(get_window().get_visible_rect().encloses(button.get_global_rect())).is_true()
		var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		get_tree().current_scene.free()
		get_tree().current_scene = null


## The phone steps for a rupture, through the real scene: the button is ready at the start, a tap
## starts the aim, a tap on the map places the point, the check mark sends one SUPERWEAPON, and the
## sim takes it (a rupture is pending for player 1).
func test_the_touch_steps_of_a_rupture_end_in_one_superweapon_the_sim_takes() -> void:
	var main: Node = await _press("StrikeTestButton")
	var runner: MatchRunner = main.get_node("MatchRunner")
	var aim: StrikeAim = main.get_node("StrikeAim")
	var controller: PlayerController = main.get_node("PlayerController")
	controller.vibrate = func(_ms: int) -> void: pass
	runner.run_ticks(1)
	assert_bool(aim.owned).is_true()
	assert_int(aim.building_id).is_not_equal(0)
	assert_str(String(runner.snapshot.type_ids[aim.type_index])).is_equal("fossil_strike")
	assert_bool(aim.begin()).is_true()
	aim.place(AIM_POINT)
	assert_bool(aim.confirm()).is_true()
	runner.run_ticks(1)
	assert_int(runner.world.dropped_commands).is_equal(0)
	assert_int(runner.world.strike_tick[1]).is_not_equal(0)


## Opens the dev menu as the current scene, in the tree for two frames.
func _open_menu() -> Node:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	return menu


## Presses `button_name` on the dev menu; the scene that the press changed to.
func _press(button_name: String) -> Node:
	var menu: Node = await _open_menu()
	var button: Button = menu.find_child(button_name, true, false)
	assert_bool(button.disabled).is_false()
	button.pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	return get_tree().current_scene
