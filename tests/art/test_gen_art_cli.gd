extends GdUnitTestSuite
## The command line of the art generator (plan rows P99 and P99b, ADR 0023 section 5):
## `scripts/gen-art.sh` and `tools/artgen/gen_art.gd`. The exit codes are the contract that the art
## rows P101 to P105 build on: 0 done (also when nothing changed, or `--check` found nothing), 1 a
## model is invalid or Godot printed a script error (Godot itself exits 0 after one), 2 a wrong
## argument or a model file that is not there, 3 Godot is missing, 4 `--check` found a difference.
##
## The wrapper runs in a scratch project against a stand-in `godot` that prints a console file and
## exits with a chosen status (the pattern of tests/project/test_run_tests_failure_line.gd). The
## generator's own codes run the real binary on this project and never write: `--check`, or a
## scratch model whose files are not committed (`--check` names them and exits 4).

const SCRIPT: String = "res://scripts/gen-art.sh"
const GENERATOR: String = "res://tools/artgen/gen_art.gd"
const LIGHT_TANK: String = "res://assets/art/models/fossil/light_tank.tres"
## What the wrapper runs before the generator: it seeds the extension list and imports; the
## stand-in answers an import at once and otherwise records its arguments, prints `console.txt` and
## exits with `exit_code`.
const FAKE_GODOT: String = (
	"#!/usr/bin/env bash\n"
	+ 'case " $* " in *" --import "*) exit 0 ;; esac\n'
	+ 'echo "$*" > args.txt\n'
	+ "cat console.txt\n"
	+ 'exit "$(cat exit_code)"\n'
)
const LAUNCH: String = (
	"#!/usr/bin/env bash\n"
	+ 'cd "$(dirname "$0")" || exit 2\n'
	+ 'GODOT="${FAKE_GODOT:-$PWD/bin/godot}" bash scripts/gen-art.sh "$@"\n'
)
const EXECUTABLE: int = (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
)

## The scratch projects of the test; freeing one removes its folder.
var _projects: Array[DirAccess] = []


func after_test() -> void:
	_projects.clear()


func test_a_missing_godot_is_exit_3_and_says_so() -> void:
	var root: String = _project("")
	var run: Dictionary = _run(root, ["--no-such-godot"], {"FAKE_GODOT": root + "/bin/missing"})
	assert_int(run["code"]).is_equal(3)
	assert_str(run["text"]).contains("GODOT MISSING")
	assert_bool(FileAccess.file_exists(root.path_join("args.txt"))).is_false()


## Godot exits 0 after a script error, a parse error or an engine error, so the wrapper reads the
## log: each of the three is exit 1 although the stand-in says 0.
func test_an_error_in_the_log_is_exit_1_although_godot_exits_0() -> void:
	for console: String in [
		"SCRIPT ERROR: Parse Error: Identifier not found: Foo\n",
		"fine\nERROR: Cannot open file 'res://assets/art/iso/x.svg'.\n",
		"res://tools/artgen/ArtGen.gd:12 - Parse Error: Unexpected token\n",
	]:
		var run: Dictionary = _run(_project(console), [], {}, 0)
		assert_int(run["code"]).override_failure_message(console).is_equal(1)
		assert_str(run["text"]).contains("Godot reported errors")
		assert_str(run["text"]).contains(console.strip_edges())


## A clean log passes Godot's own status through (0 done, 1 an invalid model, 2 usage, 4 a
## difference), and the log itself is shown.
func test_a_clean_log_passes_the_status_of_godot_through() -> void:
	for status: int in [0, 1, 2, 4]:
		var run: Dictionary = _run(_project("gen-art: 0 written, 304 unchanged\n"), [], {}, status)
		assert_int(run["code"]).override_failure_message("status %d" % status).is_equal(status)
		assert_str(run["text"]).contains("gen-art: 0 written, 304 unchanged")
		assert_str(run["text"]).not_contains("Godot reported errors")


## The wrapper runs the generator script headless on this project and hands its arguments on.
func test_the_wrapper_runs_the_generator_and_hands_on_its_arguments() -> void:
	var root: String = _project("ok\n")
	_run(root, ["--bogus"], {}, 0)
	var args: String = FileAccess.get_file_as_string(root.path_join("args.txt"))
	assert_str(args).contains("--headless --path . --script %s -- --bogus" % GENERATOR)


## The wrapper hands every flag on, in the order given.
func test_the_wrapper_hands_on_the_flags_of_a_one_model_check() -> void:
	var root: String = _project("ok\n")
	_run(root, ["--model", "assets/art/models/fossil/light_tank.tres", "--check"], {}, 0)
	var args: String = FileAccess.get_file_as_string(root.path_join("args.txt"))
	assert_str(args).contains("-- --model assets/art/models/fossil/light_tank.tres --check")


## The generator with the real binary: a wrong argument is exit 2 and the usage line.
func test_the_generator_refuses_a_wrong_argument_and_says_how_to_call_it() -> void:
	for words: Array in [
		["--bogus"],
		["--model"],
		["--model", LIGHT_TANK, "--model", LIGHT_TANK],
		["--all", "--model", LIGHT_TANK],
		["--check", "extra"],
	]:
		var args: Array[String] = []
		args.assign(words)
		var refused: Dictionary = _generator(args)
		assert_int(refused["code"]).override_failure_message(str(args)).is_equal(2)
		assert_str(refused["text"]).contains("gen-art: usage: gen-art.sh [--all | --model PATH]")
	var missing: Dictionary = _generator(["--model", "res://assets/art/models/fossil/nope.tres"])
	assert_int(missing["code"]).is_equal(2)
	assert_str(missing["text"]).contains(
		"gen-art: no model file res://assets/art/models/fossil/nope"
	)


## `--check` writes nothing and finds nothing on the committed files (test_artgen.gd names the stale
## ones when it does), for every model and for one in each of the ways a path can be written.
func test_a_check_of_the_fresh_files_is_exit_0_and_writes_nothing() -> void:
	var all: Dictionary = _generator(["--check"])
	assert_int(all["code"]).override_failure_message(all["text"]).is_equal(0)
	assert_str(all["text"]).contains("gen-art: 0 differ, ")
	for path: String in [
		LIGHT_TANK,
		"assets/art/models/fossil/light_tank.tres",
		"./assets/art/models/fossil/light_tank.tres",
		ProjectSettings.globalize_path(LIGHT_TANK),
	]:
		var one: Dictionary = _generator(["--model", path, "--check"])
		assert_int(one["code"]).override_failure_message(path + "\n" + one["text"]).is_equal(0)
		assert_str(one["text"]).contains("gen-art: 0 differ, ")
	var explicit: Dictionary = _generator(["--all", "--check"])
	assert_int(explicit["code"]).is_equal(0)


## A model whose files are not committed is a difference: `--check` names them, writes none of
## them and exits 4. An invalid model is exit 1 whatever the flags.
func test_a_check_of_a_model_that_is_not_committed_names_its_files_and_is_exit_4() -> void:
	var folder: String = _scratch("box hull steel 0 0 0 1 1 1")
	var found: Dictionary = _generator(["--model", folder.path_join("zz_scratch.tres"), "--check"])
	assert_int(found["code"]).override_failure_message(found["text"]).is_equal(4)
	assert_str(found["text"]).contains(
		"gen-art: differs: res://assets/art/iso/fossil/veh/zz_scratch_hull_d00.svg"
	)
	# 16 hull and 16 shadow frames with an import each, the sheet and the card.
	assert_str(found["text"]).contains("gen-art: 66 differ, ")
	assert_bool(FileAccess.file_exists("res://assets/art/iso/icons/item_zz_scratch.svg")).is_false()
	var invalid: Dictionary = _generator(
		["--model", _scratch("box hull no_such_material 0 0 0 1 1 1").path_join("zz_scratch.tres")]
	)
	assert_int(invalid["code"]).is_equal(1)
	assert_str(invalid["text"]).contains("not a primitive or an unknown material")


## A scratch folder with one model `zz_scratch.tres` of the Derrick League and the given primitive.
func _scratch(prim: String) -> String:
	var access: DirAccess = DirAccess.create_temp("gen_art_model_")
	_projects.append(access)
	var model: String = (
		'[gd_resource type="Resource" script_class="ArtModel" format=3]\n\n'
		+ '[ext_resource type="Script" path="res://tools/artgen/ArtModel.gd" id="1_model"]\n\n'
		+ '[resource]\nscript = ExtResource("1_model")\nart_id = &"zz_scratch"\n'
		+ 'faction = &"fossil"\ncategory = &"veh"\n'
		+ 'prims = PackedStringArray("%s")\n' % prim
	)
	_write(access.get_current_dir().path_join("zz_scratch.tres"), model)
	return access.get_current_dir()


## A scratch project with the script under test, a stand-in for the script that seeds the extension
## list and a stand-in `godot` that prints `console`.
func _project(console: String) -> String:
	var access: DirAccess = DirAccess.create_temp("gen_art_cli_")
	_projects.append(access)
	var root: String = access.get_current_dir()
	_write(root.path_join("scripts/gen-art.sh"), FileAccess.get_file_as_string(SCRIPT))
	_write(root.path_join("scripts/seed-extension-list.sh"), "exit 0\n")
	_write(root.path_join("bin/godot"), FAKE_GODOT, true)
	_write(root.path_join("console.txt"), console)
	_write(root.path_join("launch.sh"), LAUNCH)
	return root


func _write(path: String, text: String, executable: bool = false) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(text)
	file.close()
	if executable:
		assert_int(FileAccess.set_unix_permissions(path, EXECUTABLE)).is_equal(OK)


## What the wrapper exits with and prints (stdout and stderr together) when the stand-in `godot`
## exits with `status`; `env` adds environment variables.
func _run(root: String, args: Array[String], env: Dictionary, status: int = 0) -> Dictionary:
	_write(root.path_join("exit_code"), str(status))
	var launch: PackedStringArray = PackedStringArray()
	for name: String in env:
		launch.append("%s=%s" % [name, env[name]])
	launch.append_array(["bash", root.path_join("launch.sh")])
	launch.append_array(args)
	var output: Array = []
	var code: int = OS.execute("env", launch, output, true)
	return {"code": code, "text": String(output[0])}


## The generator script run by the real binary on this project.
func _generator(args: Array[String]) -> Dictionary:
	var launch: PackedStringArray = PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", GENERATOR]
	)
	launch.append("--")
	launch.append_array(args)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), launch, output, true)
	return {"code": code, "text": String(output[0])}
