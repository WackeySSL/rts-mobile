extends GdUnitTestSuite
## Every script under game/ and scenes/ must load and be instantiable. `godot --import` does not
## report parse errors in scripts and exits 0, but load() prints "SCRIPT ERROR: Parse Error"
## and returns a script whose can_instantiate() is false. With untyped_declaration=2 a missing
## type is such a parse error.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ROOTS: Array[String] = ["res://game", "res://scenes"]


func test_every_script_loads_and_can_instantiate() -> void:
	var scripts: Array[String] = _all_scripts()
	# Guards against the scan passing because it found nothing.
	assert_array(scripts).contains(["res://game/view/MapView.gd"])
	var broken: Array[String] = []
	for path: String in scripts:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			broken.append(path)
	assert_array(broken).is_empty()


func _all_scripts() -> Array[String]:
	var scripts: Array[String] = []
	for root: String in ROOTS:
		scripts.append_array(FileScan.list_files(root, ".gd"))
	return scripts
