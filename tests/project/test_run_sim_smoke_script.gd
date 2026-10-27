extends GdUnitTestSuite
## The flags, exit codes and output of scripts/run-sim-smoke.sh (plan row P95, ADR 0020 question
## 2): `--matches N` and `--report PATH` as the Phase 0 stub documented them, exit 0 ok, 2 for a
## bad flag, and the new 3 (Godot missing) and 1 (a run that is not OK). CLAUDE.md says CI and
## skills call the flags, so they stay stable.
##
## Tested without playing a match: the real script runs in a scratch project against a stand-in
## `godot` that records its arguments in calls.txt and prints what a mode of the file `mode`
## says, as `run-sim-smoke.sh`'s Godot would (the Godot banner, the script's lines, an engine
## error, nothing). The matches themselves are tests/smoke/test_smoke_run.gd, and verify.sh runs
## the real thing once.

const SCRIPT: String = "res://scripts/run-sim-smoke.sh"
const SEED_SCRIPT: String = "res://scripts/seed-extension-list.sh"
## What the script hands to `godot` to play, before `--matches`.
const ENTRY: String = "--headless --path . -s res://tests/smoke/run_sim_smoke.gd --"
const OK_LINES: String = (
	"run-sim-smoke: match 1 of 2: seed 1, 1800 ticks, winner none, hash 0123456789abcdef\n"
	+ "run-sim-smoke: match 2 of 2: seed 2, 1800 ticks, winner none, hash fedcba9876543210\n"
	+ "run-sim-smoke: OK, 2 matches of 1800 ticks, no dropped commands\n"
)
## The stand-in. An import call (`--import`) only logs, and exits 1 in the mode import_fails. A play
## call prints the banner and a blank line (what Godot prints first) and then does what the mode
## says: print the lines of ok_lines.txt with an engine error before or after them, print nothing,
## or crash. The modes that finish a run also write `{}` to the path after `--report`.
const FAKE_GODOT: String = (
	"#!/usr/bin/env bash\n"
	+ 'printf "%s\\n" "$*" >>calls.txt\n'
	+ 'mode="$(cat mode 2>/dev/null || echo ok)"\n'
	+ 'case " $* " in *" --import "*)\n'
	+ '  [ "$mode" != import_fails ] || { echo "ERROR: import broke"; exit 1; }\n'
	+ "  exit 0 ;;\n"
	+ "esac\n"
	+ "echo 'Godot Engine v4.7.2.stable.official - https://godotengine.org'\n"
	+ "echo\n"
	+ "report() {\n"
	+ '  prev=""\n'
	+ '  for arg in "$@"; do\n'
	+ '    [ "$prev" != --report ] || printf "{}" >"$arg"\n'
	+ '    prev="$arg"\n'
	+ "  done\n"
	+ "}\n"
	+ 'case "$mode" in\n'
	+ "  failed)\n"
	+ '    report "$@"\n'
	+ '    echo "run-sim-smoke: match 1 of 1: seed 1, 1800 ticks, dropped 2"\n'
	+ '    echo "run-sim-smoke: FAILED, seed 1: dropped commands 2"\n'
	+ "    exit 1 ;;\n"
	+ '  script_error) echo "SCRIPT ERROR: Invalid call."; cat ok_lines.txt ;;\n'
	+ '  parse_error) echo "Parse Error: Identifier not found." ;;\n'
	+ '  error_line) echo "ERROR: 3 resources still in use at exit."; cat ok_lines.txt ;;\n'
	+ "  silent) ;;\n"
	+ "  crash) exit 134 ;;\n"
	+ '  *) report "$@"; cat ok_lines.txt ;;\n'
	+ "esac\n"
)
## Runs the script in the scratch project with the caller's arguments. A file, because OS.execute
## can set neither the working directory nor the environment (GODOT, RUN_SIM_SMOKE_SKIP_IMPORT).
## `%s` is the lines that change the environment of one case. stdout and stderr go to files.
const LAUNCH: String = (
	"#!/usr/bin/env bash\n"
	+ 'cd "$(dirname "$0")" || exit 2\n'
	+ 'export GODOT="$PWD/bin/godot" RUN_SIM_SMOKE_SKIP_IMPORT=1\n'
	+ "%s"
	+ 'bash scripts/run-sim-smoke.sh "$@" >stdout.txt 2>stderr.txt\n'
)
## rwx for the owner: the stand-in `godot` is run by its path.
const EXECUTABLE: int = (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
)

## The scratch projects of the test; freeing one removes its folder.
var _projects: Array[DirAccess] = []


func after_test() -> void:
	_projects.clear()


func test_no_arguments_play_three_matches_and_print_only_the_runs_lines() -> void:
	var root: String = _project()
	_run(root, [])
	assert_str(_read(root, "calls.txt")).is_equal(ENTRY + " --matches 3\n")
	# The banner and the blank line of Godot's output stay in its log: stdout holds the script's
	# lines and nothing else.
	assert_str(_read(root, "stdout.txt")).is_equal(OK_LINES)
	assert_str(_read(root, "stderr.txt")).is_empty()


func test_the_flags_reach_godot_and_the_report_path_is_made_absolute() -> void:
	var root: String = _project()
	_run(root, ["--report", "out/deep/r.json", "--matches", "5"])
	var report: String = root.path_join("out/deep/r.json")
	assert_str(_read(root, "calls.txt")).is_equal(ENTRY + " --matches 5 --report " + report + "\n")
	assert_str(_read(root, "out/deep/r.json")).is_equal("{}")
	_write(root.path_join("mode"), "ok")
	_run(root, ["--report", "here.json"])
	assert_bool(FileAccess.file_exists(root.path_join("here.json"))).is_true()


## Godot imports what lies below the project folder, so a report in build/ or reports/ gets the
## .gdignore that keeps it out.
func test_a_report_in_build_or_reports_hides_that_folder_from_the_import() -> void:
	var root: String = _project()
	_run(root, ["--report", "build/sub/r.json"])
	assert_bool(FileAccess.file_exists(root.path_join("build/.gdignore"))).is_true()
	assert_bool(FileAccess.file_exists(root.path_join("reports/.gdignore"))).is_false()
	_run(root, ["--report", "reports/r.json"])
	assert_bool(FileAccess.file_exists(root.path_join("reports/.gdignore"))).is_true()


func test_the_report_of_an_older_run_does_not_survive_a_run_that_writes_none() -> void:
	var root: String = _project()
	_write(root.path_join("mode"), "silent")
	_write(root.path_join("old/r.json"), "stale")
	_run(root, ["--report", "old/r.json"], 1)
	assert_bool(FileAccess.file_exists(root.path_join("old/r.json"))).is_false()


func test_a_bad_flag_exits_2_and_never_starts_godot() -> void:
	var bad: Array[Array] = [
		["--matches"],
		["--matches", "0"],
		["--matches", "03"],
		["--matches", "-1"],
		["--matches", "two"],
		["--matches", ""],
		["--report"],
		["--report", ""],
		["--bogus"],
		["3"],
	]
	for args: Array in bad:
		var root: String = _project()
		var arguments: Array[String] = []
		arguments.assign(args)
		_run(root, arguments, 2)
		assert_bool(FileAccess.file_exists(root.path_join("calls.txt"))).is_false()
		assert_str(_read(root, "stderr.txt")).contains("run-sim-smoke: ")
		assert_str(_read(root, "stdout.txt")).is_empty()


func test_help_prints_the_usage_and_exits_0() -> void:
	var root: String = _project()
	_run(root, ["--help"])
	assert_str(_read(root, "stderr.txt")).contains("[--matches N] [--report PATH]")
	assert_bool(FileAccess.file_exists(root.path_join("calls.txt"))).is_false()


## A missing Godot is exit 3 with export-web.sh's message, and a bad flag still comes first.
func test_a_missing_godot_exits_3_after_the_flags_are_checked() -> void:
	var root: String = _project()
	var missing: String = 'export GODOT="$PWD/bin/no_godot_here"\n'
	_run(root, [], 3, missing)
	assert_str(_read(root, "stderr.txt")).contains("GODOT MISSING: ")
	assert_str(_read(root, "stderr.txt")).contains("(set GODOT=/path/to/godot)")
	assert_str(_read(root, "stdout.txt")).is_empty()
	_run(root, ["--matches", "0"], 2, missing)


## Godot can exit 0 after a script error, so the exit code is not enough: an engine error line or
## a missing OK line fails the run, and the lines of the run still reach stdout.
func test_a_run_that_is_not_ok_exits_1() -> void:
	var cases: Dictionary[String, String] = {
		"failed": "FAILED, seed 1: dropped commands 2",
		"script_error": "SCRIPT ERROR: Invalid call.",
		"parse_error": "Parse Error: Identifier not found.",
		"error_line": "ERROR: 3 resources still in use at exit.",
		"silent": "the OK line is missing",
		"crash": "Godot exited with code 134",
	}
	for mode: String in cases:
		var root: String = _project()
		_write(root.path_join("mode"), mode)
		_run(root, [], 1)
		assert_str(_read(root, "stderr.txt")).contains(cases[mode])
	var failed: String = _project()
	_write(failed.path_join("mode"), "failed")
	_run(failed, [], 1)
	assert_str(_read(failed, "stdout.txt")).contains("run-sim-smoke: FAILED, seed 1")


## The import makes the class cache that the entry script needs; verify.sh has just made it and
## skips the step.
func test_the_import_runs_before_the_matches_unless_it_is_skipped() -> void:
	var root: String = _project()
	var import: String = "unset RUN_SIM_SMOKE_SKIP_IMPORT\n"
	_run(root, [], 0, import)
	assert_str(_read(root, "calls.txt")).is_equal(
		"--headless --path . --import\n" + ENTRY + " --matches 3\n"
	)
	var failing: String = _project()
	_write(failing.path_join("mode"), "import_fails")
	_run(failing, [], 1, import)
	assert_str(_read(failing, "calls.txt")).is_equal("--headless --path . --import\n")
	assert_str(_read(failing, "stderr.txt")).contains("the import failed")


## A scratch project with the script, the seed script it calls and the stand-in `godot`.
func _project() -> String:
	var access: DirAccess = DirAccess.create_temp("run_sim_smoke_")
	_projects.append(access)
	var root: String = access.get_current_dir()
	_write(root.path_join("scripts/run-sim-smoke.sh"), FileAccess.get_file_as_string(SCRIPT))
	var seed_script: String = FileAccess.get_file_as_string(SEED_SCRIPT)
	_write(root.path_join("scripts/seed-extension-list.sh"), seed_script)
	_write(root.path_join("ok_lines.txt"), OK_LINES)
	_write(root.path_join("bin/godot"), FAKE_GODOT, true)
	return root


func _write(path: String, text: String, executable: bool = false) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(text)
	file.close()
	if executable:
		assert_int(FileAccess.set_unix_permissions(path, EXECUTABLE)).is_equal(OK)


func _read(root: String, file: String) -> String:
	return FileAccess.get_file_as_string(root.path_join(file))


## Runs the script in `root` with `args` and `env` (shell lines for the launcher), and checks its
## exit code against `wanted`.
func _run(root: String, args: Array[String], wanted: int = 0, env: String = "") -> void:
	_write(root.path_join("launch.sh"), LAUNCH % env)
	var arguments: PackedStringArray = [root.path_join("launch.sh")]
	arguments.append_array(PackedStringArray(args))
	var output: Array = []
	var code: int = OS.execute("bash", arguments, output, true)
	(
		assert_int(code)
		. override_failure_message(
			"run-sim-smoke.sh exited %d, not %d: %s" % [code, wanted, _read(root, "stderr.txt")]
		)
		. is_equal(wanted)
	)
