extends GdUnitTestSuite
## scripts/prerender.sh's pinned-image preflight (plan row P656a, ADR 0053 sections 5 and 9): its
## exit codes, run on a fixture listing of what is "installed" so no Mesa, xvfb or Godot is
## needed. Exit 0 the image is the pin, 3 a tool is missing, 4 a version differs (one line per
## package, expected and found), 2 no arguments. Nothing is rendered or installed.

const SCRIPT: String = "res://scripts/prerender.sh"
const ADR: String = "res://docs/adr/0053-prerendered-terrain-and-buildings.md"
const VERSIONS: String = "user://prerender_versions.txt"
const MESA: String = "25.2.8-0ubuntu0.24.04.5"
const PINNED: Dictionary = {
	"os": "Ubuntu 24.04.5 LTS",
	"godot": "4.7.2.stable.official.ed1daf0bf",
	"python": "3.13",
	"numpy": "2.5.3",
	"pillow": "12.3.0",
	"mesa-vulkan-drivers": MESA,
	"libgl1-mesa-dri": MESA,
	"libglx-mesa0": MESA,
	"libgbm1": MESA,
	"mesa-libgallium": MESA,
	"libllvm20": "1:20.1.2-0ubuntu1~24.04.3",
	"xvfb": "2:21.1.12-1ubuntu1.9",
}


func after_test() -> void:
	for file: String in [VERSIONS, "user://prerender_manifest.tres"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## Runs `--preflight` against `listing` (name -> version); `tools` is PRERENDER_TOOLS.
func _preflight(listing: Dictionary, tools: String = "bash") -> Dictionary:
	var lines: PackedStringArray = PackedStringArray()
	for name: String in listing:
		lines.append("%s %s" % [name, listing[name]])
	var file: FileAccess = FileAccess.open(VERSIONS, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	var output: Array = []
	var code: int = (
		OS
		. execute(
			"env",
			[
				"PRERENDER_VERSIONS_FILE=" + ProjectSettings.globalize_path(VERSIONS),
				"PRERENDER_TOOLS=" + tools,
				"bash",
				ProjectSettings.globalize_path(SCRIPT),
				"--preflight",
			],
			output,
			true
		)
	)
	return {"code": code, "text": "".join(output)}


func test_the_pinned_image_passes() -> void:
	var run: Dictionary = _preflight(PINNED)
	assert_int(run.code).is_equal(0)
	assert_str(run.text).contains("preflight OK")


func test_a_different_version_exits_4_and_names_the_package_expected_and_found() -> void:
	var listing: Dictionary = PINNED.duplicate()
	listing["libllvm20"] = "1:20.1.2-0ubuntu1~24.04.2"
	listing["numpy"] = "2.4.0"
	var run: Dictionary = _preflight(listing)
	assert_int(run.code).is_equal(4)
	assert_str(run.text).contains(
		"MISMATCH libllvm20: expected 1:20.1.2-0ubuntu1~24.04.3, found 1:20.1.2-0ubuntu1~24.04.2"
	)
	assert_str(run.text).contains("MISMATCH numpy: expected 2.5.3, found 2.4.0")
	assert_str(run.text).not_contains("MISMATCH xvfb")
	assert_str(run.text).not_contains("preflight OK")


func test_a_package_that_is_not_installed_is_a_mismatch_too() -> void:
	var listing: Dictionary = PINNED.duplicate()
	listing.erase("mesa-vulkan-drivers")
	var run: Dictionary = _preflight(listing)
	assert_int(run.code).is_equal(4)
	assert_str(run.text).contains("MISMATCH mesa-vulkan-drivers: expected %s, found (not" % MESA)


func test_godot_must_be_the_pinned_4_7_2() -> void:
	var listing: Dictionary = PINNED.duplicate()
	listing["godot"] = "4.7.3.stable.official.abcdef"
	var run: Dictionary = _preflight(listing)
	assert_int(run.code).is_equal(4)
	assert_str(run.text).contains("MISMATCH godot: expected 4.7.2")


func test_a_missing_tool_has_its_own_exit_code_before_any_version_is_read() -> void:
	var run: Dictionary = _preflight(PINNED, "bash prerender-no-such-tool")
	assert_int(run.code).is_equal(3)
	assert_str(run.text).contains("TOOL MISSING: 'prerender-no-such-tool'")
	assert_str(run.text).not_contains("MISMATCH")


func test_no_argument_is_a_usage_error() -> void:
	var output: Array = []
	var code: int = OS.execute("bash", [ProjectSettings.globalize_path(SCRIPT)], output, true)
	assert_int(code).is_equal(2)


func test_the_pins_in_the_script_are_the_ones_the_adr_names() -> void:
	var adr: String = FileAccess.get_file_as_string(ADR)
	assert_str(adr).is_not_empty()
	for name: String in PINNED:
		if name in ["os", "godot", "python"]:
			continue
		assert_str(adr).contains(PINNED[name])
	var pins: String = FileAccess.get_file_as_string("res://tools/prerender/requirements.txt")
	assert_str(pins).contains("numpy==%s" % PINNED.numpy).contains("Pillow==%s" % PINNED.pillow)
	var script: String = FileAccess.get_file_as_string(SCRIPT)
	for name: String in PINNED:
		if name not in ["numpy", "pillow"]:
			assert_str(script).contains("%s|%s" % [name, PINNED[name].get_slice(".stable", 0)])


func test_check_refuses_another_stamp_with_exit_5_and_compares_nothing() -> void:
	var manifest: FileAccess = FileAccess.open("user://prerender_manifest.tres", FileAccess.WRITE)
	manifest.store_string('[resource]\nstamp = "Vulkan 1.4.318 - Forward+ - llvmpipe / Mesa 1"\n')
	manifest = null
	var run: Dictionary = _check("Vulkan 1.3 - Forward+ - a real GPU / Mesa 2")
	assert_int(run.code).is_equal(5)
	assert_str(run.text).contains("STAMP differs").contains("this machine 'Vulkan 1.3")
	assert_int(_check("Vulkan 1.4.318 - Forward+ - llvmpipe / Mesa 1").code).is_equal(0)


func _check(stamp: String) -> Dictionary:
	var listing: FileAccess = FileAccess.open(VERSIONS, FileAccess.WRITE)
	for name: String in PINNED:
		listing.store_line("%s %s" % [name, PINNED[name]])
	listing = null
	var output: Array = []
	var code: int = (
		OS
		. execute(
			"env",
			[
				"PRERENDER_VERSIONS_FILE=" + ProjectSettings.globalize_path(VERSIONS),
				"PRERENDER_TOOLS=bash",
				"PRERENDER_STAMP=" + stamp,
				"PRERENDER_SKIP_IMPORT=1",
				(
					"PRERENDER_MANIFEST="
					+ ProjectSettings.globalize_path("user://prerender_manifest.tres")
				),
				"bash",
				ProjectSettings.globalize_path(SCRIPT),
				"--check",
			],
			output,
			true
		)
	)
	return {"code": code, "text": "".join(output)}
