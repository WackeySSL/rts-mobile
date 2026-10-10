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
