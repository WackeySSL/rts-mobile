extends GdUnitTestSuite
## The dev menu's "Perf air" button (plan row P253): it sits after "Perf AI", is at least 48 dp
## and opens the perf arena scene with the air arena (judged against `air_golden_*`).

const MIN_DP: float = 48.0


func test_the_dev_menu_has_the_button_after_perf_ai_at_48_dp() -> void:
	assert_bool(ResourceLoader.exists(DevRoutes.PERF_AIR_SCENARIO)).is_true()
	var menu: Control = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await await_idle_frame()
	var button: Button = menu.find_child("PerfAirButton", true, false)
	var ai: Button = menu.find_child("PerfAiButton", true, false)
	assert_str(button.text).is_equal("Perf air")
	assert_bool(button.disabled).is_false()
	assert_object(button.get_parent()).is_same(ai.get_parent())
	assert_int(button.get_index()).is_equal(ai.get_index() + 1)
	assert_float(button.get_combined_minimum_size().y).is_greater_equal(UiScale.dp(MIN_DP) - 0.5)
	remove_child(menu)
	menu.free()


func test_the_button_opens_the_perf_scene_with_the_air_arena() -> void:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	menu.find_child("PerfAirButton", true, false).pressed.emit()
	await await_idle_frame()
	var arena: Node = tree.current_scene
	assert_str(arena.scene_file_path).is_equal(DevRoutes.PERF_ARENA_SCENE)
	assert_str(arena.arena_kind).is_equal(PerfHud.ARENA_AIR)
	assert_str(arena.hud.arena_kind).is_equal(PerfHud.ARENA_AIR)
	assert_str(arena.scenario.resource_path).is_equal(DevRoutes.PERF_AIR_SCENARIO)
	arena.find_child("BackButton", true, false).pressed.emit()
	await await_idle_frame()
	tree.current_scene.free()
	tree.current_scene = null
