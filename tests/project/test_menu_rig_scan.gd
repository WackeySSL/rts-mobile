extends GdUnitTestSuite
## A suite that builds the main scene builds a `BuildSidebar`, whose slide is 160 ms by default
## and whose layout a map gesture or a placement changes (ADR 0024 sections 5 and 8, plan P85f).
## Every such suite calls `MenuRig.begin()` in `before_test` and `MenuRig.end()` in `after_test`
## (`tests/support/menu_rig.gd`), so the layouts it measures never catch the menu half way and no
## override outlives the suite. The scan reads every `.gd` under `tests/` with its comments taken
## out and fails on a file that names `scenes/main.tscn`, instantiates something and lacks one of
## the two calls. A file that only reads the scene as text, or never instantiates it, is listed in
## EXCEPTIONS with its reason; every exception must still be needed.
## It is a line lint, not a proof: a suite that builds the sidebar some other way (a scene of its
## own with a `BuildSidebar` in it) is not seen.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const TESTS_DIR: String = "res://tests"
const SCENE: String = "scenes/main.tscn"
const BEGIN: String = "MenuRig.begin()"
const END: String = "MenuRig.end()"
const BUILDS: String = 'var scene = load("res://scenes/main.tscn").instantiate()\n'
## Files that name the scene without building it, with the reason.
const EXCEPTIONS: Dictionary[String, String] = {
	"res://tests/project/test_cross_file_facts.gd": "reads the scene file as text",
	"res://tests/project/test_menu_rig_scan.gd": "this scan",
	"res://tests/project/test_project_settings.gd": "reads the scene file as text",
	"res://tests/project/test_ui_theme_scan.gd": "reads the scene file as text",
	"res://tests/ui/support/arena_rig.gd": "a rig: the suites that use it are the ones scanned",
	"res://tests/view/test_ghost_memory_layer.gd": "names the scene in a comment only",
}


func test_every_suite_that_builds_the_main_scene_sets_and_clears_the_menu_rig() -> void:
	var missing: Array[String] = []
	for path: String in FileScan.list_files(TESTS_DIR, ".gd"):
		var findings: Array[String] = _findings(FileAccess.get_file_as_string(path))
		if not findings.is_empty() and not EXCEPTIONS.has(path):
			missing.append("%s: %s" % [path, ", ".join(findings)])
	assert_array(missing).override_failure_message("\n".join(missing)).is_empty()


## An exception is a file that names the scene and still needs it: one that now has both calls, or
## that names the scene no more, goes off the list.
func test_every_exception_still_names_the_scene_without_building_it_the_rig_way() -> void:
	for path: String in EXCEPTIONS:
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
		var text: String = FileAccess.get_file_as_string(path)
		var rigged: bool = text.contains(BEGIN) and text.contains(END)
		assert_bool(rigged and path != "res://tests/project/test_menu_rig_scan.gd").is_false()


## The scan flags a suite that builds the scene without the calls, wherever they are missing, and
## leaves alone a suite that has both, a file that does not name the scene and a comment.
func test_the_scan_sees_a_missing_call_and_leaves_the_rest_alone() -> void:
	assert_array(_findings(BUILDS)).is_equal(["no " + BEGIN, "no " + END])
	assert_array(_findings(BUILDS + "\tMenuRig.begin()\n")).is_equal(["no " + END])
	assert_array(_findings(BUILDS + "\tMenuRig.end()\n")).is_equal(["no " + BEGIN])
	assert_array(_findings(BUILDS + "\tMenuRig.begin()\n\tMenuRig.end()\n")).is_empty()
	(
		assert_array(
			_findings("var node = load('res://scenes/dev/art_gallery.tscn').instantiate()")
		)
		. is_empty()
	)
	assert_array(_findings("# res://scenes/main.tscn is instantiate()d elsewhere\n")).is_empty()
	assert_array(_findings('var path: String = "res://scenes/main.tscn"\n')).is_empty()


## What a source lacks: it names the main scene and instantiates something, but not the two calls.
func _findings(text: String) -> Array[String]:
	var code: String = "\n".join(FileScan.code_lines(text))
	var out: Array[String] = []
	if not code.contains(SCENE) or not code.contains(".instantiate()"):
		return out
	if not code.contains(BEGIN):
		out.append("no " + BEGIN)
	if not code.contains(END):
		out.append("no " + END)
	return out
