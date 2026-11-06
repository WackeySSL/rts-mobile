extends SceneTree
## The entry point of scripts/run-sim-smoke.sh (plan rows P95 and P186, ADR 0031 sections 1 to 3):
## it plays `--matches N` full AI-vs-AI matches of smoke_run.gd with the seeds `--seed-start S` to
## S + N - 1, prints one line per match and a last line, and writes the report JSON when
## `--report PATH` is given.
##
## Run: godot --headless --path . -s res://tests/smoke/run_sim_smoke.gd -- [--matches N]
##      [--report PATH] [--seed-start S] [--levels A,B] [--scenarios KIND] [--ticks T]
##      (PATH is an absolute file path; the shell script resolves it and checks the other flags)
## Output: lines that start with "run-sim-smoke: ": the implementation, the match lines, then either
##   "run-sim-smoke: OK, N matches of at most T ticks, impl I, K timeouts, no dropped commands" and
##   exit code 0, or "run-sim-smoke: FAILED, <what>" and exit code 1. Exit code 2: a bad argument.
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
	var seed_start: int = 1
	var levels: Array[String] = Smoke.DEFAULT_LEVELS.duplicate()
	var kind: String = Smoke.KIND_CROSS
	var ticks: int = Smoke.TICKS
	var index: int = 0
	while index < args.size():
		var value: String = args[index + 1] if index + 1 < args.size() else ""
		var number: bool = value.is_valid_int() and int(value) > 0
		var parsed: Array[String] = _levels_of(value)
		if args[index] == "--matches" and number:
			matches = int(value)
		elif args[index] == "--report" and not value.is_empty():
			report_path = value
		elif args[index] == "--seed-start" and number:
			seed_start = int(value)
		elif args[index] == "--ticks" and number:
			ticks = int(value)
		elif args[index] == "--scenarios" and Smoke.KINDS.has(value):
			kind = value
		elif args[index] == "--levels" and not parsed.is_empty():
			levels = parsed
		else:
			printerr(
				(
					(
						"run-sim-smoke: bad argument '%s' (usage: --matches N --report PATH --seed-start S"
						% args[index]
					)
					+ " --levels A,B --scenarios KIND --ticks T)"
				)
			)
			return 2
		index += 2
	var impl: String = Smoke.impl_name()
	var problems: Array[String] = Smoke.impl_problems()
	if not problems.is_empty():
		print("%sFAILED, native library: %s" % [Smoke.PREFIX, "; ".join(problems)])
		return 1
	print("%simpl %s (AUTO)" % [Smoke.PREFIX, impl])
	var records: Array[Dictionary] = []
	var drops: Dictionary[int, int] = {}
	for number: int in range(1, matches + 1):
		var record: Dictionary = Smoke.play(seed_start + number - 1, ticks, kind, levels, drops)
		records.append(record)
		print(Smoke.line(record, number, matches, drops))
	var failures: PackedStringArray = Smoke.failures(records, drops)
	if not report_path.is_empty():
		var data: Dictionary = Smoke.report(records, matches, ticks, seed_start, levels, kind)
		if not Smoke.write_report(report_path, data):
			failures.append("cannot write the report to %s" % report_path)
	print(Smoke.summary(records, ticks, impl, failures))
	return 1 if not failures.is_empty() else 0


## The levels of the text `A,B`: two names, both known, else an empty array.
func _levels_of(text: String) -> Array[String]:
	var levels: Array[String] = []
	for name: String in text.split(","):
		if not Smoke.LEVELS.has(name):
			return []
		levels.append(name)
	if levels.size() != 2:
		levels.clear()
	return levels
