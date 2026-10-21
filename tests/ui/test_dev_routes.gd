extends GdUnitTestSuite
## DevRoutes: gating and the dev menu's entries. DevRoutes.open() with a missing path is not
## tested on purpose: its push_error prints "ERROR:" even when the test asserts it, which the
## error scan of verify.sh and CI turns into a failure (ADR 0002, Consequences).


func test_dev_menu_is_enabled_in_a_debug_run() -> void:
	assert_bool(DevRoutes.is_enabled()).is_true()


func test_main_dev_menu_and_gallery_scenes_exist() -> void:
	assert_bool(ResourceLoader.exists(DevRoutes.MAIN_SCENE)).is_true()
	assert_bool(ResourceLoader.exists(DevRoutes.DEV_MENU_SCENE)).is_true()
	assert_bool(ResourceLoader.exists(DevRoutes.ART_GALLERY_SCENE)).is_true()
	assert_str(DevRoutes.PERF_ARENA_SCENE).is_equal("res://scenes/dev/perf_arena.tscn")
	assert_bool(ResourceLoader.exists(DevRoutes.PERF_ARENA_SCENE)).is_true()


## The entry's disabled state for a missing scene is not tested: a gallery that moved must fail
## here, not turn the entry grey while the suite stays green.
func test_gallery_entry_is_enabled() -> void:
	var packed: PackedScene = load(DevRoutes.DEV_MENU_SCENE)
	var menu: Node = auto_free(packed.instantiate())
	# In the tree, so that _ready runs and sets the button states.
	add_child(menu)
	await await_idle_frame()
	var gallery: Button = menu.find_child("GalleryButton", true, false)
	assert_object(gallery).is_not_null()
	assert_bool(gallery.disabled).is_false()


func test_test_map_entry_is_enabled() -> void:
	var packed: PackedScene = load(DevRoutes.DEV_MENU_SCENE)
	var menu: Node = auto_free(packed.instantiate())
	add_child(menu)
	await await_idle_frame()
	var test_map: Button = menu.find_child("TestMapButton", true, false)
	assert_object(test_map).is_not_null()
	assert_bool(test_map.disabled).is_false()


## Dev menu -> Touch probe -> Back -> Dev menu, through the real buttons and scene changes.
func test_dev_menu_opens_the_touch_probe_and_back_returns_to_the_dev_menu() -> void:
	assert_str(DevRoutes.TOUCH_PROBE_SCENE).is_equal("res://scenes/dev/touch_probe.tscn")
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	var probe_button: Button = menu.find_child("TouchProbeButton", true, false)
	assert_bool(probe_button.disabled).is_false()
	probe_button.pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.TOUCH_PROBE_SCENE)
	tree.current_scene.find_child("BackButton", true, false).pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.DEV_MENU_SCENE)
	tree.current_scene.free()
	tree.current_scene = null


## Dev menu -> Perf arena -> Back -> Dev menu, through the real buttons and scene changes. The arena
## runs its real preflight on entry (the slow seams are the card's defaults here), which this one
## case pays for. Leaving it restores the frame cap it set.
func test_dev_menu_opens_the_perf_arena_and_back_returns_to_the_dev_menu() -> void:
	var fps_before: int = Engine.max_fps
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	var arena_button: Button = menu.find_child("PerfArenaButton", true, false)
	assert_object(arena_button).is_not_null()
	assert_str(arena_button.text).is_equal("Perf arena")
	assert_bool(arena_button.disabled).is_false()
	arena_button.pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.PERF_ARENA_SCENE)
	assert_int(Engine.max_fps).is_equal(60)
	tree.current_scene.find_child("BackButton", true, false).pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.DEV_MENU_SCENE)
	assert_int(Engine.max_fps).is_equal(fps_before)
	tree.current_scene.free()
	tree.current_scene = null
