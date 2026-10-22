extends GdUnitTestSuite
## The autoload contract of ADR 0002 section 1. The autoloads are Node-side bridges with no
## class_name: a class_name equal to an autoload name is a silent parse error (exit code 0).
## UiOrientation (ADR 0015 section 2) is a screen concern and lives in game/ui.

const SERVICE_SCRIPTS: Dictionary = {
	"DetRng": "res://game/core/det_rng_service.gd",
	"CommandQueue": "res://game/core/command_queue_service.gd",
	"UiOrientation": "res://game/ui/ui_orientation_service.gd",
}
const SIM_DIR: String = "res://game/sim/"


func test_autoload_nodes_exist_with_contract_scripts() -> void:
	for autoload_name: String in SERVICE_SCRIPTS:
		var node: Node = get_tree().root.get_node_or_null(autoload_name)
		(
			assert_object(node)
			. override_failure_message("missing /root/%s" % autoload_name)
			. is_not_null()
		)
		if node == null:
			continue
		var script: Script = node.get_script()
		assert_object(script).is_not_null()
		assert_str(script.resource_path).is_equal(SERVICE_SCRIPTS[autoload_name])


func test_autoload_scripts_declare_no_class_name() -> void:
	for autoload_name: String in SERVICE_SCRIPTS:
		var script: Script = load(SERVICE_SCRIPTS[autoload_name])
		assert_object(script).is_not_null()
		assert_str(String(script.get_global_name())).is_empty()


func test_no_global_class_is_named_like_an_autoload() -> void:
	var clashes: Array[String] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var global_class: String = entry["class"]
		if SERVICE_SCRIPTS.has(global_class):
			clashes.append("%s (%s)" % [global_class, entry["path"]])
	assert_array(clashes).is_empty()


func test_no_autoload_script_lives_in_the_simulation() -> void:
	var autoload_paths: Array[String] = _autoload_script_paths()
	# Guards against the check passing because it found nothing.
	assert_array(autoload_paths).contains(SERVICE_SCRIPTS.values())
	var inside_sim: Array[String] = []
	for path: String in autoload_paths:
		if path.begins_with(SIM_DIR):
			inside_sim.append(path)
	assert_array(inside_sim).is_empty()


## Script paths of every autoload in project.godot, with the "*" singleton marker removed and
## a uid:// reference resolved to its path.
func _autoload_script_paths() -> Array[String]:
	var paths: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = property["name"]
		if not property_name.begins_with("autoload/"):
			continue
		var value: String = ProjectSettings.get_setting(property_name)
		value = value.trim_prefix("*")
		if value.begins_with("uid://"):
			value = ResourceUID.uid_to_path(value)
		paths.append(value)
	paths.sort()
	return paths
