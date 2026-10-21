extends GdUnitTestSuite
## Every scene under res://scenes instantiates, survives one frame in the tree and is freed
## without leaving orphans (gdUnit4 reports orphans as exit code 101). Scenes added later are
## covered as soon as they exist. The boot scene and the dev routes (menu, art gallery, touch probe,
## perf arena) must be among them, so that a moved scene cannot make the scan pass on fewer scenes.
## The perf arena caps the frame rate while it is in the tree (plan P50b): the scan also asserts
## that every scene leaves `Engine.max_fps` as it found it.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SCENES_DIR: String = "res://scenes"


func test_every_scene_instantiates_and_survives_a_frame() -> void:
	var scenes: Array[String] = FileScan.list_files(SCENES_DIR, ".tscn")
	# Guards against the scan passing because it found nothing.
	var required: Array[String] = [
		DevRoutes.MAIN_SCENE,
		DevRoutes.DEV_MENU_SCENE,
		DevRoutes.ART_GALLERY_SCENE,
		DevRoutes.TOUCH_PROBE_SCENE,
		DevRoutes.PERF_ARENA_SCENE,
	]
	assert_array(scenes).contains(required)
	var max_fps: int = Engine.max_fps
	for path: String in scenes:
		var packed: PackedScene = load(path)
		assert_object(packed).override_failure_message("cannot load %s" % path).is_not_null()
		var root: Node = auto_free(packed.instantiate())
		assert_object(root).override_failure_message("cannot instantiate %s" % path).is_not_null()
		add_child(root)
		await await_idle_frame()
		assert_bool(root.is_inside_tree()).override_failure_message(path).is_true()
		remove_child(root)
		root.free()
		assert_int(Engine.max_fps).override_failure_message(path).is_equal(max_fps)
