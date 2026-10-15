extends GdUnitTestSuite
## The failure line of scripts/run-tests.sh (P56d). gdUnit4's exit status is a result code, not a
## count: 100 means "some test failed or errored", 101 "orphan nodes and nothing else", 105 "script
## errors". The old line, `gdUnit4 exited with 100 (100 failures/errors, 101 orphans, 105 script
## errors)`, put those codes where a reader looks for counts. The line now names the status as a
## code, says what it means, and gives the counts that gdUnit4 printed on its "Overall Summary"
## line (or says that there was none, as after a script error or a crash).
##
## Tested without gdUnit4 running: the real script runs in a scratch project against a stand-in
## `godot` that prints a console file and exits with a chosen status. The summary line is the one
## gdUnit4 4.x printed in a real run (checked on 2026-10-15 with two failing cases and one orphan:
## colour codes around "Overall Summary:" and around the counts), with other numbers, all different,
## so that a count read from the wrong place shows. The exit codes themselves are pinned by
## test_run_tests_order.gd.

const SCRIPT: String = "res://scripts/run-tests.sh"
const ESC: String = "\u001b"
## The text before the counts of a real summary line, and the counts: 7 test cases, 3 errors, 2
## failures, 5 flaky, 6 skipped and 1 orphan.
const SUMMARY: String = (
	ESC
	+ "[38;2;30;144;255mOverall Summary:"
	+ ESC
	+ "[0m"
	+ ESC
	+ "[38;2;255;255;255m 7 test cases | 3 errors | 2 failures | 5 flaky | 6 skipped | 1 orphans |"
	+ ESC
	+ "[0m"
)
const COUNTS: String = "7 test cases, 3 errors, 2 failures, 1 orphans"
const NO_SUMMARY: String = "no Overall Summary line in the gdUnit4 output above"
## `run-tests.sh` needs a gdUnit4 tool script, a library for the host (it checks the .gdextension)
## and the report that gdUnit4 writes.
const FAKE_GODOT: String = (
	"#!/usr/bin/env bash\n"
	+ "mkdir -p reports/gdunit/report_1\n"
	+ "cp fake_results.xml reports/gdunit/report_1/results.xml\n"
	+ "cat console.txt\n"
	+ 'exit "$(cat exit_code)"\n'
)
const RESULTS: String = '<testsuites tests="7"></testsuites>\n'
const GDEXTENSION: String = (
	'linux.debug.x86_64 = "res://native/bin/lib.so"\n'
	+ 'linux.debug.arm64 = "res://native/bin/lib.so"\n'
)
const LAUNCH: String = (
	"#!/usr/bin/env bash\n"
	+ 'cd "$(dirname "$0")" || exit 2\n'
	+ 'GODOT="$PWD/bin/godot" RUN_TESTS_SKIP_IMPORT=1 bash scripts/run-tests.sh\n'
)
const EXECUTABLE: int = (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
)

## The scratch projects of the test; freeing one removes its folder.
var _projects: Array[DirAccess] = []


func after_test() -> void:
	_projects.clear()


## 100 is named as a code and as failures or errors, and the counts are the ones on the summary
## line, each from its own place (the flaky and skipped counts are not printed).
func test_status_100_is_a_code_and_the_counts_are_the_summarys() -> void:
	var lines: Array[String] = _run(_project("some output\n%s\n" % SUMMARY), 100)
	var wanted: String = "run-tests: gdUnit4 exited with code 100 (test failures or errors): "
	assert_str(lines[-1]).is_equal(wanted + COUNTS)
	assert_str(lines[-1]).not_contains("100 failures/errors")
	# gdUnit4's own output still reaches the caller, colour codes and all.
	assert_array(lines).contains(["some output", SUMMARY])


func test_status_101_means_orphan_nodes() -> void:
	var lines: Array[String] = _run(_project(SUMMARY + "\n"), 101)
	var wanted: String = "run-tests: gdUnit4 exited with code 101 (orphan nodes): "
	assert_str(lines[-1]).is_equal(wanted + COUNTS)


## A script error stops the run before any test case: there is no summary to read.
func test_status_105_means_script_errors_and_a_missing_summary_is_said() -> void:
	var lines: Array[String] = _run(_project("Script errors were detected\n"), 105)
	var wanted: String = "run-tests: gdUnit4 exited with code 105 (script errors): "
	assert_str(lines[-1]).is_equal(wanted + NO_SUMMARY)


## Any other status (a crash gives 134 or 139, a kill 137) is named as not one of gdUnit4's codes.
func test_any_other_status_is_not_called_a_gdunit_result() -> void:
	for code: int in [1, 134]:
		var lines: Array[String] = _run(_project(SUMMARY + "\n"), code)
		var wanted: String = "run-tests: gdUnit4 exited with code %d (not a gdUnit4 result code): "
		assert_str(lines[-1]).is_equal((wanted % code) + COUNTS)


## The summary is read from this run: a log from the run before is overwritten, so a run that
## printed none does not report the earlier run's numbers.
func test_the_summary_of_an_earlier_run_is_not_read() -> void:
	var root: String = _project(SUMMARY + "\n")
	assert_str(_run(root, 100)[-1]).ends_with(COUNTS)
	_write(root.path_join("console.txt"), "no summary this time\n")
	assert_str(_run(root, 105)[-1]).ends_with(NO_SUMMARY)


## A scratch project with the script under test and a stand-in `godot` that prints `console`.
func _project(console: String) -> String:
	var access: DirAccess = DirAccess.create_temp("run_tests_failure_line_")
	_projects.append(access)
	var root: String = access.get_current_dir()
	_write(root.path_join("scripts/run-tests.sh"), FileAccess.get_file_as_string(SCRIPT))
	_write(root.path_join("addons/gdUnit4/bin/GdUnitCmdTool.gd"), "")
	_write(root.path_join("native/sim_kernels.gdextension"), GDEXTENSION)
	_write(root.path_join("native/bin/lib.so"), "lib")
	_write(root.path_join("bin/godot"), FAKE_GODOT, true)
	_write(root.path_join("fake_results.xml"), RESULTS)
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


## The non-empty lines the script printed (stdout and stderr together) when the stand-in `godot`
## exits with `status`; the script must exit with the same status.
func _run(root: String, status: int) -> Array[String]:
	_write(root.path_join("exit_code"), str(status))
	var output: Array = []
	var code: int = OS.execute("bash", [root.path_join("launch.sh")], output, true)
	assert_int(code).override_failure_message("run-tests.sh exited %d" % code).is_equal(status)
	var lines: Array[String] = []
	for line: String in String(output[0]).split("\n", false):
		lines.append(line)
	assert_array(lines).is_not_empty()
	return lines
