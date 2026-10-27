extends SceneTree
## The entry point of scripts/run-sim-smoke.sh (plan row P95, ADR 0020 question 2 = ja): it plays
## `--matches N` dummy-vs-dummy matches of smoke_run.gd with the seeds 1 to N, prints one line per
## match and a last line, and writes the report JSON when `--report PATH` is given.
##
## Run: godot --headless --path . -s res://tests/smoke/run_sim_smoke.gd -- [--matches N]
##      [--report PATH]   (PATH is an absolute file path; the shell script resolves it)
## Output: lines that start with "run-sim-smoke: ": the match lines, then either
##   "run-sim-smoke: OK, N matches of T ticks, no dropped commands" and exit code 0, or
##   "run-sim-smoke: FAILED, <what>" and exit code 1. Exit code 2: a bad argument.
## Godot can exit 0 after a script error, so the shell script also requires the OK line.
##
## This is a plain script and no GdUnitTestSuite on purpose, as dump_states.gd is: gdUnit4 drops a
## script that has no GdUnitTestSuite base when it loads it, so run-tests.sh never runs it.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


## Plays the matches and returns the exit code.
func _run(args: PackedStringArray) -> int:
	var matches: int = 3
	var report_path: String = ""
	var index: int = 0
	while index < args.size():
		var value: String = args[index + 1] if index + 1 < args.size() else ""
		if args[index] == "--matches" and value.is_valid_int() and int(value) > 0:
			matches = int(value)
		elif args[index] == "--report" and not value.is_empty():
			report_path = value
		else:
			printerr(
				"run-sim-smoke: bad argument '%s' (usage: --matches N --report PATH)" % args[index]
			)
			return 2
		index += 2
	var records: Array[Dictionary] = []
	for number: int in range(1, matches + 1):
		var record: Dictionary = Smoke.play(number)
		records.append(record)
		print(Smoke.line(record, number, matches))
	var failures: PackedStringArray = Smoke.failures(records)
	if not report_path.is_empty():
		if not Smoke.write_report(report_path, Smoke.report(records, matches)):
			failures.append("cannot write the report to %s" % report_path)
	print(Smoke.summary(matches, failures))
	return 1 if not failures.is_empty() else 0
