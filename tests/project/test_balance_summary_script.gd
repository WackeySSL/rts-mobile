extends GdUnitTestSuite
## The flags, exit codes and output of scripts/balance-summary.sh (plan row P187, ADR 0031 section
## 4): `--out PATH [--gate] REPORT...`, exit 0 ok, 1 for a refusal or a run that is not OK, 2 for a
## bad flag, a missing report file or a missing REPORT, 3 for Godot missing. House style of
## run-sim-smoke.sh (test_run_sim_smoke_script.gd): the real script runs in a scratch project
## against a stand-in `godot` that records its arguments in calls.txt and prints what the file
## `mode` says. The merge itself is tests/smoke/test_balance_summary.gd.

const SCRIPT: String = "res://scripts/balance-summary.sh"
const SEED_SCRIPT: String = "res://scripts/seed-extension-list.sh"
const ENTRY: String = "--headless --path . -s res://tests/smoke/balance_summary.gd --"
const OK_LINE: String = "balance-summary: OK, 2 matches from 1 reports, 0 flags\n"
const FAKE_GODOT: String = (
	"#!/usr/bin/env bash\n"
	+ 'printf "%s\\n" "$*" >>calls.txt\n'
	+ 'mode="$(cat mode 2>/dev/null || echo ok)"\n'
	+ 'case " $* " in *" --import "*)\n'
	+ '  [ "$mode" != import_fails ] || { echo "ERROR: import broke"; exit 1; }\n'
	+ "  exit 0 ;;\n"
	+ "esac\n"
	+ "echo 'Godot Engine v4.7.2.stable.official - https://godotengine.org'\n"
	# The files of the run, as the entry writes them: the JSON and its markdown.
	+ 'prev=""\n'
	+ 'for arg in "$@"; do\n'
	+ '  [ "$prev" != --out ] || { printf "{}" >"$arg"; printf "#" >"${arg%.json}.md"; }\n'
	+ '  prev="$arg"\n'
	+ "done\n"
	+ 'ok() { echo "balance-summary: OK, 2 matches from 1 reports, 0 flags"; }\n'
	+ 'case "$mode" in\n'
	+ "  refused) echo \"balance-summary: FAILED, field 'commit' differs\"; exit 1 ;;\n"
	+ '  refused_error) echo "ERROR: broke."; echo "balance-summary: FAILED, x"; exit 1 ;;\n'
	+ '  script_error) echo "SCRIPT ERROR: Invalid call."; ok ;;\n'
	+ '  parse_error) echo "Parse Error: Identifier not found."; ok ;;\n'
	+ '  error_line) echo "ERROR: 3 resources in use."; ok ;;\n'
	+ "  silent) ;;\n"
	+ "  crash) exit 134 ;;\n"
	+ "  *) ok ;;\n"
	+ "esac\n"
)
const LAUNCH: String = (
	"#!/usr/bin/env bash\n"
	+ 'cd "$(dirname "$0")" || exit 2\n'
	+ 'export GODOT="$PWD/bin/godot" BALANCE_SUMMARY_SKIP_IMPORT=1\n'
	+ "%s"
	+ 'bash scripts/balance-summary.sh "$@" >stdout.txt 2>stderr.txt\n'
)
const EXECUTABLE: int = (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
)

var _projects: Array[DirAccess] = []


func after_test() -> void:
	_projects.clear()


func test_the_paths_reach_godot_absolute_and_the_stdout_holds_only_the_runs_lines() -> void:
	var root: String = _project()
	_run(root, ["--out", "build/sets/x.json", "r1.json", "r2.json"])
	var calls: String = _read(root, "calls.txt")
	(
		assert_str(calls)
		. is_equal(
			(
				"%s --out %s %s %s\n"
				% [
					ENTRY,
					root.path_join("build/sets/x.json"),
					root.path_join("r1.json"),
					root.path_join("r2.json"),
				]
			)
		)
	)
	assert_str(_read(root, "stdout.txt")).is_equal(OK_LINE)
	assert_str(_read(root, "stderr.txt")).is_empty()
	# build/ is hidden from the import, as the smoke script does for its reports.
	assert_bool(FileAccess.file_exists(root.path_join("build/.gdignore"))).is_true()


func test_gate_is_passed_on_and_the_markdown_name_follows_the_out_name() -> void:
	var root: String = _project()
	_run(root, ["--gate", "--out", "o.json", "r1.json"])
	assert_str(_read(root, "calls.txt")).contains("--out %s --gate " % root.path_join("o.json"))
	# .json becomes .md; a name that is not .json gets .md added.
	assert_bool(FileAccess.file_exists(root.path_join("o.md"))).is_true()
	assert_bool(FileAccess.file_exists(root.path_join("o.json.md"))).is_false()
	_run(root, ["--out", "plain", "r1.json"])
	assert_bool(FileAccess.file_exists(root.path_join("plain.md"))).is_true()


func test_a_stale_output_does_not_survive_and_a_failed_run_leaves_none() -> void:
	var root: String = _project()
	_write(root.path_join("o.json"), "stale")
	_write(root.path_join("o.md"), "stale")
	_write(root.path_join("mode"), "silent")
	_run(root, ["--out", "o.json", "r1.json"], 1)
	assert_bool(FileAccess.file_exists(root.path_join("o.json"))).is_false()
	assert_bool(FileAccess.file_exists(root.path_join("o.md"))).is_false()
	# Godot wrote the files and then an error line: the failed run removes both.
	for mode: String in ["error_line", "script_error", "refused"]:
		var other: String = _project()
		_write(other.path_join("mode"), mode)
		_run(other, ["--out", "o.json", "r1.json"], 1)
		assert_bool(FileAccess.file_exists(other.path_join("o.json"))).is_false()
		assert_bool(FileAccess.file_exists(other.path_join("o.md"))).is_false()


func test_a_bad_flag_exits_2_and_never_starts_godot() -> void:
	var bad: Array[Array] = [
		[],
		["r1.json"],
		["--out"],
		["--out", ""],
		["--out", "o.json"],
		["--out", "o.json", "--bogus", "r1.json"],
		["--out", "o.json", "missing.json"],
		["--out", "o.json", ""],
		["--out", "o.json", "."],
		["--out", "--gate", "r1.json"],
		["--out", "-o.json", "r1.json"],
		["--out", ".", "r1.json"],
		["--gate", "r1.json"],
	]
	for args: Array in bad:
		var root: String = _project()
		var arguments: Array[String] = []
		arguments.assign(args)
		_run(root, arguments, 2)
		assert_bool(FileAccess.file_exists(root.path_join("calls.txt"))).is_false()
		assert_str(_read(root, "stderr.txt")).contains("balance-summary: ")
		assert_str(_read(root, "stdout.txt")).is_empty()
		assert_bool(FileAccess.file_exists(root.path_join("o.json"))).is_false()


func test_help_prints_the_usage_and_exits_0() -> void:
	var root: String = _project()
	_run(root, ["--help"])
	assert_str(_read(root, "stderr.txt")).contains("--out PATH [--gate] REPORT...")
	assert_bool(FileAccess.file_exists(root.path_join("calls.txt"))).is_false()


func test_a_missing_godot_exits_3_after_the_flags_are_checked() -> void:
	var root: String = _project()
	var missing: String = 'export GODOT="$PWD/bin/no_godot_here"\n'
	_run(root, ["--out", "o.json", "r1.json"], 3, missing)
	assert_str(_read(root, "stderr.txt")).contains("GODOT MISSING: ")
	assert_str(_read(root, "stderr.txt")).contains("(set GODOT=/path/to/godot)")
	_run(root, ["--bogus"], 2, missing)


## Godot can exit 0 after a script error, and the fake then prints the full OK line, so only the
## scan of Godot's output can fail these runs.
func test_a_refusal_exits_1_with_its_line_and_the_error_scan_fails_a_run_that_prints_ok() -> void:
	var root: String = _project()
	_write(root.path_join("mode"), "refused")
	_run(root, ["--out", "o.json", "r1.json"], 1)
	assert_str(_read(root, "stdout.txt")).contains("FAILED, field 'commit' differs")
	var scanned: Dictionary[String, String] = {
		"script_error": "SCRIPT ERROR: Invalid call.",
		"parse_error": "Parse Error: Identifier not found.",
		"error_line": "ERROR: 3 resources in use.",
		# An error line before the script's own FAILED line is shown too.
		"refused_error": "ERROR: broke.",
	}
	for mode: String in scanned:
		var other: String = _project()
		_write(other.path_join("mode"), mode)
		_run(other, ["--out", "o.json", "r1.json"], 1)
		assert_str(_read(other, "stderr.txt")).contains("Godot wrote errors")
		assert_str(_read(other, "stderr.txt")).contains(scanned[mode])
	var cases: Dictionary[String, String] = {
		"silent": "the OK line is missing",
		"crash": "Godot exited with code 134",
	}
	for mode: String in cases:
		var other: String = _project()
		_write(other.path_join("mode"), mode)
		_run(other, ["--out", "o.json", "r1.json"], 1)
		assert_str(_read(other, "stderr.txt")).contains(cases[mode])


func test_the_import_runs_first_unless_it_is_skipped() -> void:
	var root: String = _project()
	_run(root, ["--out", "o.json", "r1.json"], 0, "unset BALANCE_SUMMARY_SKIP_IMPORT\n")
	assert_str(_read(root, "calls.txt")).starts_with("--headless --path . --import\n")
	var failing: String = _project()
	_write(failing.path_join("mode"), "import_fails")
	_run(failing, ["--out", "o.json", "r1.json"], 1, "unset BALANCE_SUMMARY_SKIP_IMPORT\n")
	assert_str(_read(failing, "stderr.txt")).contains("the import failed")


## A scratch project with the script, the seed script it calls, two report files and the stand-in.
func _project() -> String:
	var access: DirAccess = DirAccess.create_temp("balance_summary_")
	_projects.append(access)
	var root: String = access.get_current_dir()
	_write(root.path_join("scripts/balance-summary.sh"), FileAccess.get_file_as_string(SCRIPT))
	var seed_script: String = FileAccess.get_file_as_string(SEED_SCRIPT)
	_write(root.path_join("scripts/seed-extension-list.sh"), seed_script)
	_write(root.path_join("r1.json"), "{}")
	_write(root.path_join("r2.json"), "{}")
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


func _run(root: String, args: Array[String], wanted: int = 0, env: String = "") -> void:
	_write(root.path_join("launch.sh"), LAUNCH % env)
	var arguments: PackedStringArray = [root.path_join("launch.sh")]
	arguments.append_array(PackedStringArray(args))
	var output: Array = []
	var code: int = OS.execute("bash", arguments, output, true)
	(
		assert_int(code)
		. override_failure_message(
			"balance-summary.sh exited %d, not %d: %s" % [code, wanted, _read(root, "stderr.txt")]
		)
		. is_equal(wanted)
	)
