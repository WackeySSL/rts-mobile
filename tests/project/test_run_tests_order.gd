extends GdUnitTestSuite
## scripts/run-tests.sh gives gdUnit4 its suites in an order that does not depend on the file system
## (P56c). gdUnit4 scans a directory in the order the file system lists it, and that order differs
## between machines: P26n2's exit leak (PR #41, closed unmerged) needs one suite to run before
## another, and was green locally and red on CI. So the script turns each `-a <directory>` into one
## `-a <script>` per .gd file below it, in byte order of the path, and gdUnit4 runs the suites in
## the order it is given them (measured on 4.7.2: suites passed as -a files ran in that order, in
## results.xml and in the console, and a whole run of tests/ ran the same suites with the same case
## counts as the directory scan did).
##
## Tested without Godot: the real script runs in a scratch project against a stand-in `godot` that
## writes its arguments to a file. The listing order is varied three ways: the project built
## forwards and backwards, and a `find` that lists backwards. `sort` is replaced by one that folds
## case and ignores punctuation, as en_US collation does, unless it runs with LC_ALL=C. Both
## stand-ins stop at once if they are ever called from a stand-in, so they cannot loop.

const SCRIPT: String = "res://scripts/run-tests.sh"
## What the script passes before the caller's arguments.
const FIXED: Array[String] = [
	"--headless",
	"--path",
	".",
	"-s",
	"res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
	"--ignoreHeadlessMode",
	"-c",
	"-rd",
	"reports/gdunit",
	"-rc",
	"1",
]
## The scratch project's files, in the order they are created. Where `ui_extra` and `Zeta` sort
## differs between byte order and a locale's order, so a sort that follows the locale is seen.
const TREE: Array[String] = [
	"tests/test_b.gd",
	"tests/test_a.gd",
	"tests/a.gd",
	"tests/Zeta/test_upper.gd",
	"tests/ui/test_z.gd",
	"tests/ui_extra/test_y.gd",
	"tests/sim/test_s.gd",
	"tests/sim/native/test_n.gd",
	"tests/support/helper.gd",
	"tests/notes.txt",
	"tests/.hidden/test_h.gd",
	"tests/.dot.gd",
	"tests/skip/.gdignore",
	"tests/skip/test_skipped.gd",
	"tests/skip/deeper/test_d.gd",
	"game/g.gd",
	"addons/gdUnit4/plugin.gd",
	"addons/gdUnit4/src/skip_me.gd",
	"addons/gdUnit4/bin/skip_me.gd",
	"reports/skip_me.gd",
]
## The scripts below tests/ that gdUnit4's scan visits (not the text file, the hidden entries and
## what a .gdignore hides), in byte order of the path.
const TESTS: Array[String] = [
	"tests/Zeta/test_upper.gd",
	"tests/a.gd",
	"tests/sim/native/test_n.gd",
	"tests/sim/test_s.gd",
	"tests/support/helper.gd",
	"tests/test_a.gd",
	"tests/test_b.gd",
	"tests/ui/test_z.gd",
	"tests/ui_extra/test_y.gd",
]
## `run-tests.sh` needs a gdUnit4 tool script, a library for the host (it checks the .gdextension)
## and the report that gdUnit4 writes. `godot` stands in for the engine.
const FAKE_GODOT: String = (
	"#!/usr/bin/env bash\n"
	+ 'printf "%s\\n" "$@" >argv.txt\n'
	+ "mkdir -p reports/gdunit/report_1\n"
	+ "cp fake_results.xml reports/gdunit/report_1/results.xml\n"
	+ '[ ! -f exit_code ] || exit "$(cat exit_code)"\n'
)
## What the stand-in writes as gdUnit4's report; the test cases it names ran.
const RESULTS: String = '<testsuites tests="1"></testsuites>\n'
const GDEXTENSION: String = (
	'linux.debug.x86_64 = "res://native/bin/lib.so"\n'
	+ 'linux.debug.arm64 = "res://native/bin/lib.so"\n'
)
## The first lines of a stand-in: it runs the real tool through STUB_REAL_PATH, so a call that
## reaches a stand-in again (a PATH that lets it find itself) would loop; this exits 97 instead.
const GUARD: String = '[ -z "${STUB_ACTIVE:-}" ] || exit 97\n' + "export STUB_ACTIVE=1\n"
## A `find` that lists backwards, the opposite of a file system that lists by creation time.
const FAKE_FIND: String = (
	"#!/usr/bin/env bash\n"
	+ GUARD
	+ 'env PATH="$STUB_REAL_PATH" find "$@" | env PATH="$STUB_REAL_PATH" sort -r\n'
)
## A `sort` that follows the locale (case folded, punctuation ignored) unless LC_ALL=C.
const FAKE_SORT: String = (
	"#!/usr/bin/env bash\n"
	+ GUARD
	+ 'if [ "${LC_ALL:-}" = C ]; then exec env PATH="$STUB_REAL_PATH" sort "$@"; fi\n'
	+ 'exec env PATH="$STUB_REAL_PATH" sort -f -d "$@"\n'
)
## Runs the script in the project it sits in, with the caller's arguments. A file, because
## OS.execute can set neither the working directory nor the environment (GODOT, PATH).
const LAUNCH: String = (
	"#!/usr/bin/env bash\n"
	+ 'cd "$(dirname "$0")" || exit 2\n'
	+ 'GODOT="$PWD/bin/godot" RUN_TESTS_SKIP_IMPORT=1 bash scripts/run-tests.sh "$@"\n'
)
## The same with the stand-in `find` and `sort` first on the PATH.
const LAUNCH_STUBBED: String = (
	"#!/usr/bin/env bash\n"
	+ 'cd "$(dirname "$0")" || exit 2\n'
	+ 'STUB_REAL_PATH="$PATH" PATH="$PWD/stubs:$PATH" GODOT="$PWD/bin/godot" '
	+ 'RUN_TESTS_SKIP_IMPORT=1 bash scripts/run-tests.sh "$@"\n'
)

## rwx for the owner: the stand-in `godot` and the stubs are run by their path.
const EXECUTABLE: int = (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
)

## The scratch projects of the test; freeing one removes its folder.
var _projects: Array[DirAccess] = []


func after_test() -> void:
	_projects.clear()


func test_a_directory_becomes_its_scripts_in_byte_order_of_the_path() -> void:
	var root: String = _project(TREE)
	assert_array(_run(root, ["-a", "res://tests"])).is_equal(_add(TESTS, "res://"))


## The same list however the files are listed: a project built backwards, and a listing that is
## reversed and sorted by a locale unless the script asks for bytes.
func test_the_listing_order_of_the_file_system_does_not_change_the_order() -> void:
	var backwards: Array[String] = TREE.duplicate()
	backwards.reverse()
	var expected: Array[String] = _add(TESTS, "res://")
	assert_array(_run(_project(backwards), ["-a", "res://tests"])).is_equal(expected)
	assert_array(_run(_project(TREE), ["-a", "res://tests"], true)).is_equal(expected)
	assert_array(_run(_project(backwards), ["-a", "res://tests"], true)).is_equal(expected)


func test_no_arguments_runs_the_scripts_below_tests() -> void:
	assert_array(_run(_project(TREE), [])).is_equal(_add(TESTS, "res://"))


## The caller's arguments stay where they are: a file, a path that is not there, a flag with its
## value, a trailing slash, a path without res://, `--add` and an `-a` without a value. A directory
## that has a .gdignore itself gives nothing, as in gdUnit4's scan.
func test_other_arguments_pass_through_in_the_callers_order() -> void:
	var args: Array[String] = [
		"-a",
		"res://tests/ui/test_z.gd",
		"-i",
		"test_a",
		"-a",
		"res://tests/sim/",
		"-c",
		"-a",
		"res://tests/missing",
		"-a",
		"res://tests/skip",
		"--add",
		"tests/ui_extra",
		"-a",
	]
	var expected: Array[String] = [
		"-a",
		"res://tests/ui/test_z.gd",
		"-i",
		"test_a",
		"-a",
		"res://tests/sim/native/test_n.gd",
		"-a",
		"res://tests/sim/test_s.gd",
		"-c",
		"-a",
		"res://tests/missing",
		"-a",
		"tests/ui_extra/test_y.gd",
		"-a",
	]
	assert_array(_run(_project(TREE), args)).is_equal(expected)


## `-a res://` visits the whole project, except the folders that gdUnit4 never scans.
func test_the_project_root_skips_what_gdunit_does_not_scan() -> void:
	var expected: Array[String] = ["addons/gdUnit4/plugin.gd", "game/g.gd"]
	expected.append_array(TESTS)
	assert_array(_run(_project(TREE), ["-a", "res://"])).is_equal(_add(expected, "res://"))


## gdUnit4's exit code is the script's own (100 failures, 101 orphans, 105 script errors), and a
## run in which no test case ran exits 1 when gdUnit4 says 0.
func test_the_exit_codes_stay_the_same() -> void:
	var root: String = _project(TREE)
	var args: Array[String] = ["-a", "res://tests/ui/test_z.gd"]
	for code: int in [100, 101, 105]:
		_write(root.path_join("exit_code"), str(code))
		assert_array(_run(root, args, false, code)).is_equal(args)
	_write(root.path_join("exit_code"), "0")
	_write(root.path_join("fake_results.xml"), '<testsuites tests="0"></testsuites>\n')
	assert_array(_run(root, args, false, 1)).is_equal(args)


## "-a <prefix><path>" for each path.
func _add(paths: Array[String], prefix: String) -> Array[String]:
	var args: Array[String] = []
	for path: String in paths:
		args.append_array(["-a", prefix + path])
	return args


## A scratch project with `files` created in that order, and the script under test.
func _project(files: Array[String]) -> String:
	var access: DirAccess = DirAccess.create_temp("run_tests_order_")
	_projects.append(access)
	var root: String = access.get_current_dir()
	for file: String in files:
		_write(root.path_join(file), "")
	_write(root.path_join("scripts/run-tests.sh"), FileAccess.get_file_as_string(SCRIPT))
	_write(root.path_join("addons/gdUnit4/bin/GdUnitCmdTool.gd"), "")
	_write(root.path_join("native/sim_kernels.gdextension"), GDEXTENSION)
	_write(root.path_join("native/bin/lib.so"), "lib")
	_write(root.path_join("bin/godot"), FAKE_GODOT, true)
	_write(root.path_join("fake_results.xml"), RESULTS)
	_write(root.path_join("stubs/find"), FAKE_FIND, true)
	_write(root.path_join("stubs/sort"), FAKE_SORT, true)
	_write(root.path_join("launch.sh"), LAUNCH)
	_write(root.path_join("launch_stubbed.sh"), LAUNCH_STUBBED)
	return root


func _write(path: String, text: String, executable: bool = false) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(text)
	file.close()
	if executable:
		assert_int(FileAccess.set_unix_permissions(path, EXECUTABLE)).is_equal(OK)


## What the script handed to `godot` after its own arguments, with the script's exit code checked
## (0 unless `wanted` says otherwise).
func _run(
	root: String, args: Array[String], stubbed: bool = false, wanted: int = 0
) -> Array[String]:
	var launcher: String = "launch_stubbed.sh" if stubbed else "launch.sh"
	var arguments: PackedStringArray = [root.path_join(launcher)]
	arguments.append_array(PackedStringArray(args))
	var output: Array = []
	var code: int = OS.execute("bash", arguments, output, true)
	(
		assert_int(code)
		. override_failure_message("run-tests.sh exited %d: %s" % [code, output])
		. is_equal(wanted)
	)
	var argv: PackedStringArray = FileAccess.get_file_as_string(root.path_join("argv.txt")).split(
		"\n", false
	)
	assert_array(Array(argv.slice(0, FIXED.size()))).is_equal(FIXED)
	var passed: Array[String] = []
	for arg: String in argv.slice(FIXED.size()):
		passed.append(arg)
	return passed
