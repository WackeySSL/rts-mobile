extends GdUnitTestSuite
## Pins balance.yml (P190, ADR 0031 section 5): the triggers and their path list, no schedule and
## no pull request, the concurrency group, each job's permissions, `post` with no checkout, the
## scripts the jobs call, and the shard table of scripts/ci/balance-plan.sh, which a test here runs
## (no balance run plays a seed from 1000 up). A new suite, because test_ci_workflow.gd holds
## gdlint's 20 public methods.

const WORKFLOWS: String = "res://.github/workflows/"
## P190 (ADR 0031 section 5): balance.yml and its shard table (scripts/ci/balance-plan.sh).
const BALANCE: String = "balance.yml"
const BALANCE_PLAN: String = "res://scripts/ci/balance-plan.sh"
const BALANCE_PATHS: Array[String] = [
	'      - "data/**"',
	'      - "game/ai/**"',
	'      - "game/sim/**"',
	'      - "native/**"',
]
const BALANCE_INPUTS: Array[String] = [
	"      suite:",
	"      levels:",
	"      scenarios:",
	"      matches:",
	"      seed_start:",
]
const BALANCE_CONCURRENCY: Array[String] = [
	"concurrency:",
	"  group: balance-${{ github.ref }}-${{ inputs.suite || 'balance' }}",
	"  cancel-in-progress: true",
]
const BALANCE_POST_IF: String = (
	"    if: github.ref == 'refs/heads/main' && !github.event.repository.fork"
	+ " && (github.event_name == 'push' || inputs.suite != 'custom')"
)
const BALANCE_JOBS: Array[String] = ["  build:", "  shards:", "  summarise:", "  post:"]
const GUARD_STEP: String = "Refuse a gate run off main"
const GUARD_IF: String = 'if [ "$SUITE" = "gate" ] && [ "$REF" != "refs/heads/main" ]; then'
const PLAN_MATRIX: String = 'matrix="$(bash scripts/ci/balance-plan.sh matrix)"'
const PLAN_SETS: String = 'sets="$(bash scripts/ci/balance-plan.sh sets)"'
const PLAN_OUTPUT: String = (
	'{ echo "sha=$sha"; echo "matrix=$matrix"; echo "sets=$sets"; }' + ' >> "$GITHUB_OUTPUT"'
)
const POST_HEADER: String = 'echo "### Balance run on \\`main\\` at \\`$SHA\\`"'
const NATIVE_ARTIFACT: Array[String] = [
	"name: balance-native",
	"native/bin/",
	"native/sim_kernels.gdextension",
]
## Set, levels, scenarios, first seed and matches of every shard of a balance run: 190 matches.
const BALANCE_TABLE: Array[String] = [
	"tuning|normal,normal|cross|1|25",
	"tuning|normal,normal|cross|26|25",
	"tuning|normal,normal|cross|51|25",
	"tuning|normal,normal|cross|76|25",
	"ladder-easy|easy,normal|cross|1|10",
	"ladder-easy|normal,easy|cross|1|10",
	"ladder-hard|hard,normal|cross|1|10",
	"ladder-hard|normal,hard|cross|1|10",
	"fossil-mirror|normal,normal|fossil-mirror|1|20",
	"renew-mirror|normal,normal|renew-mirror|1|20",
	"baseline|easy,dummy|cross|1|5",
	"baseline|dummy,easy|cross|1|5",
]


## P190: the triggers of balance.yml. A push to main that changes the AI, the sim, the data or the
## native code, and a manual run with the suite and the custom set's inputs. No schedule,
## no pull request (so it can never be a required check), and nothing else starts it.
func test_balance_workflow_runs_on_a_filtered_push_and_by_hand_only() -> void:
	var lines: PackedStringArray = _lines(BALANCE)
	var block: PackedStringArray = _top_block(lines, "on:")
	var keys: Array[String] = []
	for line: String in block:
		if line.begins_with("  ") and line[2] != " ":
			keys.append(line)
	assert_array(keys).contains_exactly(["  push:", "  workflow_dispatch:"])
	assert_array(Array(block)).contains(["    branches: [main]"])
	var paths: int = block.find("    paths:")
	assert_int(paths).is_greater(-1)
	assert_array(Array(block.slice(paths + 1, paths + 1 + BALANCE_PATHS.size()))).is_equal(
		BALANCE_PATHS
	)
	assert_bool(block[paths + 1 + BALANCE_PATHS.size()].begins_with("      - ")).is_false()
	var inputs: Array[String] = []
	for line: String in block:
		if line.begins_with("      ") and line[6] != " ":
			inputs.append(line)
	# The path list's own entries are also at six spaces.
	inputs = inputs.filter(func(line: String) -> bool: return not line.begins_with("      - "))
	assert_array(inputs).contains_exactly(BALANCE_INPUTS)
	assert_array(Array(block)).contains(["        options: [balance, gate, custom]"])
	assert_array(Array(block)).contains(["        default: balance"])
	for line: String in lines:
		if line.strip_edges().begins_with("#"):
			continue
		for word: String in ["schedule", "pull_request", "workflow_run", "workflow_call"]:
			assert_bool(line.contains(word)).is_false()
	var at: int = lines.find(BALANCE_CONCURRENCY[0])
	assert_int(at).is_greater(-1)
	assert_array(Array(lines.slice(at, at + 3))).is_equal(BALANCE_CONCURRENCY)


## P190: the top level grants nothing, each job names its own permissions, and `post` holds issues:
## write alone and runs no repository code: no checkout, no local action, no repository script.
func test_balance_workflow_jobs_hold_the_least_permissions_and_post_runs_no_repository_code(
) -> void:
	var lines: PackedStringArray = _lines(BALANCE)
	assert_array(Array(lines)).contains(["permissions: {}"])
	var wanted: Dictionary = {
		"  build:": "contents: read",
		"  shards:": "contents: read",
		"  summarise:": "contents: read",
		"  post:": "issues: write",
	}
	for header: String in wanted:
		var job: PackedStringArray = _job(lines, header)
		var at: int = job.find("    permissions:")
		assert_int(at).is_greater(-1)
		var granted: Array[String] = []
		for line: String in job.slice(at + 1):
			if not line.begins_with("      "):
				break
			granted.append(line.strip_edges())
		assert_array(granted).contains_exactly([wanted[header]])
		assert_bool(job.has("    runs-on: ubuntu-24.04")).is_true()
		_assert_job_always_runs(job)
	var post: PackedStringArray = _job(lines, "  post:")
	assert_bool(post.has(BALANCE_POST_IF)).is_true()
	var post_uses: Array[String] = []
	for line: String in post:
		if line.strip_edges().begins_with("- uses:") or line.strip_edges().begins_with("uses:"):
			post_uses.append(line.strip_edges().trim_prefix("- "))
	assert_int(post_uses.size()).is_equal(1)
	assert_str(post_uses[0]).starts_with("uses: actions/download-artifact@")
	var jobs: Array[String] = []
	for at: int in range(lines.find("jobs:") + 1, lines.size()):
		if lines[at].begins_with("  ") and lines[at][2] != " " and lines[at][2] != "#":
			jobs.append(lines[at])
	assert_array(jobs).contains_exactly(BALANCE_JOBS)
	for line: String in post:
		for word: String in ["checkout", "uses: ./", "scripts/", "bash scripts", "hashFiles"]:
			assert_bool(line.contains(word)).is_false()
	var shards: PackedStringArray = _job(lines, "  shards:")
	assert_array(Array(shards)).contains(["    timeout-minutes: 30", "      fail-fast: false"])


## P190: what the jobs run. The plan, the shard (all of its arguments from the matrix, through env),
## the native check, the summary per set with `--gate` for the gate set only, the artifact kept for
## 90 days, and the comment that fails when the issue is missing and never creates it.
func test_balance_workflow_calls_the_scripts_and_keeps_the_artifact() -> void:
	var lines: PackedStringArray = _lines(BALANCE)
	var build: PackedStringArray = _job(lines, "  build:")
	var plan: Array = Array(_step(build, "Plan the shards"))
	# The results are assigned before they are echoed: a failing script then fails the step.
	var at_matrix: int = plan.find(PLAN_MATRIX)
	assert_int(at_matrix).is_greater(-1)
	assert_int(plan.find(PLAN_SETS)).is_greater(at_matrix)
	assert_int(plan.find(PLAN_OUTPUT)).is_greater(plan.find(PLAN_SETS))
	assert_array(plan).contains(["SUITE: ${{ inputs.suite || 'balance' }}"])
	_assert_plan_step_fails_on_bad_input(plan)
	var guard: Array = Array(_step(build, GUARD_STEP))
	assert_array(guard).contains(
		["SUITE: ${{ inputs.suite || 'balance' }}", "REF: ${{ github.ref }}", GUARD_IF, "exit 1"]
	)
	var checkout: int = build.find(
		"      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
	)
	assert_int(build.find("      - name: " + GUARD_STEP)).is_less(checkout)
	assert_int(checkout).is_greater(-1)
	_assert_order(build, [GUARD_STEP, "Plan the shards"])
	for line: String in build:
		assert_bool(line.contains("install-godot") or line.contains("actions/cache@")).is_false()
	var restore: Array = Array(_step(build, "Restore godot-cpp and the SCons object cache"))
	assert_str(restore[1]).starts_with("uses: actions/cache/restore@")
	assert_array(Array(_step(build, "Upload the native library"))).contains(NATIVE_ARTIFACT)
	# One run plays one commit: the checkouts name it, and there is no ref input.
	assert_bool(build.has("          ref: ${{ github.sha }}")).is_true()
	for header: String in ["  shards:", "  summarise:"]:
		(
			assert_bool(_job(lines, header).has("          ref: ${{ needs.build.outputs.sha }}"))
			. is_true()
		)
	for line: String in lines:
		assert_bool(line.contains("inputs.ref")).is_false()
	_assert_no_expression_in_run_blocks(lines)
	assert_str(_pin(WORKFLOWS + BALANCE, "GODOT_VERSION")).is_equal(
		_pin(WORKFLOWS + "ci.yml", "GODOT_VERSION")
	)
	_assert_order(build, ["Build the library (build-native.sh)", "Upload the native library"])
	_assert_step(
		build, "Build the library (build-native.sh)", ["run: bash scripts/build-native.sh"]
	)
	var shards: PackedStringArray = _job(lines, "  shards:")
	var shard: Array = Array(_step(shards, "Play the shard (run-sim-smoke.sh)"))
	var run: String = (
		'GITHUB_SHA="$BUILD_SHA" bash scripts/run-sim-smoke.sh --matches "$MATCHES"'
		+ ' --seed-start "$SEED_START"'
		+ ' --levels "$LEVELS" --scenarios "$SCENARIOS" --report "build/balance/$SHARD.json"'
	)
	assert_array(shard).contains([run, "BUILD_SHA: ${{ needs.build.outputs.sha }}"])
	# The runner resets GITHUB_* in a step's env, so it is never set there.
	assert_bool(shard.has("GITHUB_SHA: ${{ needs.build.outputs.sha }}")).is_false()
	for field: String in ["matches", "seed_start", "levels", "scenarios", "name"]:
		(
			assert_bool(
				shard.any(
					func(line: String) -> bool: return line.ends_with("${{ matrix.%s }}" % field)
				)
			)
			. is_true()
		)
	var native: Array = Array(_step(shards, "Check the shard ran native on the built commit"))
	assert_bool(native.any(_checks_native_and_commit)).is_true()
	for step: Array in [shard, native, guard]:
		for line: String in step:
			(
				assert_bool(line.begins_with("if:") or line.begins_with("continue-on-error:"))
				. is_false()
			)
	assert_array(Array(lines)).contains(
		["  SCONS_VERSION: " + '"%s"' % _pin("res://scripts/build-native.sh", "SCONS_VERSION")]
	)
	var summarise: PackedStringArray = _job(lines, "  summarise:")
	var summary: Array = Array(_step(summarise, "Summarise each set (balance-summary.sh)"))
	(
		assert_array(summary)
		. contains(
			[
				'if [ "$set" = "gate" ]; then flags=(--gate); fi',
				(
					'bash scripts/balance-summary.sh --out "build/balance/summary/$set.json"'
					+ ' "${flags[@]}" build/balance/shards/"$set"-*.json'
				),
				"SETS: ${{ needs.build.outputs.sets }}",
			]
		)
	)
	var upload: Array = Array(_step(summarise, "Upload the summaries"))
	assert_array(upload).contains(["name: ${{ steps.name.outputs.name }}", "retention-days: 90"])
	assert_array(Array(_step(summarise, "Name the artifact"))).contains(
		['run: echo "name=balance-$(date -u +%F)-${SHA:0:7}" >> "$GITHUB_OUTPUT"']
	)
	var post: Array = Array(_step(_job(lines, "  post:"), "Comment on the balance issue"))
	var text: String = "\n".join(post)
	assert_bool(text.contains("--label balance --state open")).is_true()
	assert_bool(text.contains('select(.title == "Balance reports")')).is_true()
	assert_bool(text.contains("exit 1")).is_true()
	assert_bool(text.contains(POST_HEADER)).is_true()
	assert_bool(text.contains("for set in $SETS; do")).is_true()
	assert_bool(text.contains("gh issue comment")).is_true()
	for word: String in ["gh issue create", "gh label", "gh api"]:
		assert_bool(text.contains(word)).is_false()


## P190: the shard table is the output of balance-plan.sh, which this runs. A balance run is the
## five sets of ADR 0031 section 5 (190 matches) and plays no seed from 1000 up; the gate run is
## seeds 1001-1100 and nothing else; a custom run refuses the gate's seeds and a bad input. A set's
## report prefix (`<set>-`) belongs to that set alone, as the summarise job's glob needs.
func test_balance_plan_is_the_shard_table_and_keeps_the_gate_seeds_unplayed() -> void:
	var balance: Dictionary = _plan("SUITE=balance", "matrix")
	assert_int(balance["code"]).is_equal(0)
	var rows: Array = _plan_rows(balance["out"])
	assert_array(rows.map(_row_text)).is_equal(BALANCE_TABLE)
	var total: int = 0
	var names: Array[String] = []
	for row: Dictionary in rows:
		total += int(row["matches"])
		assert_int(int(row["seed_start"]) + int(row["matches"]) - 1).is_less(1000)
		names.append(row["name"])
		for other: Dictionary in rows:
			if str(other["name"]).begins_with(str(row["set"]) + "-"):
				assert_str(other["set"]).is_equal(row["set"])
	assert_int(total).is_equal(190)
	assert_int(names.size()).is_equal(12)
	for shard_name: String in names:
		assert_int(names.count(shard_name)).is_equal(1)
	var sets: Dictionary = _plan("SUITE=balance", "sets")
	assert_str(sets["out"]).is_equal(
		"tuning ladder-easy ladder-hard fossil-mirror renew-mirror baseline"
	)
	assert_str(_plan("", "sets")["out"]).is_equal(sets["out"])
	var gate_rows: Array = _plan_rows(_plan("SUITE=gate", "matrix")["out"])
	(
		assert_array(gate_rows.map(_row_text))
		. is_equal(
			[
				"gate|normal,normal|cross|1001|25",
				"gate|normal,normal|cross|1026|25",
				"gate|normal,normal|cross|1051|25",
				"gate|normal,normal|cross|1076|25",
			]
		)
	)
	assert_str(_plan("SUITE=gate", "sets")["out"]).is_equal("gate")
	var rerun: Dictionary = _plan("SUITE=custom SEED_START=1101 MATCHES=100", "matrix")
	assert_int(rerun["code"]).is_equal(0)
	assert_int(_plan_rows(rerun["out"]).size()).is_equal(4)
	var odd: Array = _plan_rows(_plan("SUITE=custom MATCHES=30 LEVELS=easy,hard", "matrix")["out"])
	assert_array(odd.map(_row_text)).is_equal(
		["custom|easy,hard|cross|1|25", "custom|easy,hard|cross|26|5"]
	)
	var edge: Dictionary = _plan("SUITE=custom SEED_START=980 MATCHES=20", "matrix")
	assert_int(edge["code"]).is_equal(0)
	assert_array(_plan_rows(edge["out"]).map(_row_text)).is_equal(
		["custom|normal,normal|cross|980|20"]
	)
	for refused: String in [
		"SUITE=custom SEED_START=981 MATCHES=20",
		"SUITE=custom SEED_START=999999990 MATCHES=50",
		"SUITE=custom SEED_START=990 MATCHES=20",
		"SUITE=custom SEED_START=1000",
		"SUITE=custom SEED_START=1100 MATCHES=5",
		"SUITE=custom SEED_START=1001 MATCHES=100",
		"SUITE=custom MATCHES=201",
		"SUITE=custom MATCHES=0",
		"SUITE=custom LEVELS=normal",
		"SUITE=custom LEVELS=normal,godlike",
		"SUITE=custom SCENARIOS=kestrel",
		"SUITE=custom SEED_START=01",
		"SUITE=other",
	]:
		assert_int(_plan(refused, "matrix")["code"]).override_failure_message(refused).is_equal(2)


## The lines of a top-level key's block: from the line after `header` to the next top-level line.
func _top_block(lines: PackedStringArray, header: String) -> PackedStringArray:
	var start: int = lines.find(header)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < lines.size() and (lines[end].is_empty() or lines[end].begins_with(" ")):
		end += 1
	return lines.slice(start + 1, end)


## Runs balance-plan.sh under `env -i` with `assignments` (VAR=value words, space separated) in its
## environment: its exit code and its stdout without the final newline.
func _plan(assignments: String, mode: String) -> Dictionary:
	var out: Array = []
	var arguments: PackedStringArray = ["-i", "PATH=" + OS.get_environment("PATH")]
	for word: String in assignments.split(" ", false):
		arguments.append(word)
	arguments.append_array(["bash", ProjectSettings.globalize_path(BALANCE_PLAN), mode])
	var code: int = OS.execute("env", arguments, out)
	return {"code": code, "out": str(out[0]).strip_edges() if out.size() > 0 else ""}


## The step's own commands, run as the runner runs them (`bash --noprofile --norc -eo pipefail`),
## fail when the script refuses its input and succeed on a good one.
func _assert_plan_step_fails_on_bad_input(plan: Array) -> void:
	var commands: Array[String] = []
	for line: String in plan.slice(plan.find("run: |") + 1):
		commands.append(line)
	var script: String = "\n".join(commands)
	var good: Array = _run_plan_step(script, "SUITE=balance")
	assert_int(good[0]).is_equal(0)
	for bad: String in ["SUITE=custom MATCHES=0", "SUITE=custom MATCHES=500", "SUITE=nope"]:
		assert_int(_run_plan_step(script, bad)[0]).override_failure_message(bad).is_not_equal(0)


## The step's commands go to a file: OS.execute mangles `$` in an argument (the same reason as
## test_run_sim_smoke_script.gd's launcher file).
func _run_plan_step(script: String, assignments: String) -> Array:
	var path: String = "user://balance_plan_step.sh"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("export " + assignments + "\n" + script + "\n")
	file.close()
	var arguments: PackedStringArray = ["-i", "PATH=" + OS.get_environment("PATH")]
	arguments.append_array(["GITHUB_OUTPUT=/dev/null", "bash", "--noprofile", "--norc"])
	arguments.append_array(["-eo", "pipefail", ProjectSettings.globalize_path(path)])
	var out: Array = []
	var code: int = OS.execute("env", arguments, out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return [code, out]


## No `${{` inside a `run:` (single line or block): event data and inputs reach scripts through env.
func _assert_no_expression_in_run_blocks(lines: PackedStringArray) -> void:
	var block_indent: int = -1
	for line: String in lines:
		var indent: int = line.length() - line.lstrip(" ").length()
		var text: String = line.strip_edges()
		if block_indent >= 0:
			if text.is_empty() or indent > block_indent:
				assert_bool(line.contains("${{")).is_false()
				continue
			block_indent = -1
		var key: String = text.trim_prefix("- ")
		if key.begins_with("run:"):
			assert_bool(line.contains("${{")).is_false()
			if key.trim_prefix("run:").strip_edges() in ["|", ">", "|-", ">-"]:
				block_indent = indent + (2 if text.begins_with("- ") else 0)


func _checks_native_and_commit(line: String) -> bool:
	return line.contains('r["impl"] == "native"') and line.contains('r["commit"] == sys.argv[2]')


func _plan_rows(matrix_json: String) -> Array:
	var parsed: Variant = JSON.parse_string(matrix_json)
	assert_bool(parsed is Dictionary).is_true()
	return (parsed as Dictionary)["include"]


func _row_text(row: Dictionary) -> String:
	return (
		"%s|%s|%s|%d|%d"
		% [row["set"], row["levels"], row["scenarios"], int(row["seed_start"]), int(row["matches"])]
	)


func _lines(file_name: String) -> PackedStringArray:
	var file: FileAccess = FileAccess.open(WORKFLOWS + file_name, FileAccess.READ)
	assert_object(file).is_not_null()
	return file.get_as_text().split("\n")


## The lines of one job: from the line after its header to the next job (or the comment before it).
func _job(lines: PackedStringArray, header: String) -> PackedStringArray:
	var start: int = lines.find(header)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < lines.size() and not (lines[end].begins_with("  ") and lines[end][2] != " "):
		end += 1
	return lines.slice(start + 1, end)


## One step of a job, stripped, without its blank and comment lines: its "- name:" line to the next.
func _step(job: PackedStringArray, step_name: String) -> PackedStringArray:
	var start: int = job.find("      - name: " + step_name)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < job.size() and not job[end].begins_with("      - "):
		end += 1
	var out: PackedStringArray = PackedStringArray()
	for line: String in job.slice(start, end):
		if not line.strip_edges().is_empty() and not line.strip_edges().begins_with("#"):
			out.append(line.strip_edges())
	return out


## A step is exactly its name line and these lines: no `if:` or `continue-on-error` can neuter it.
func _assert_step(job: PackedStringArray, step_name: String, body: Array) -> void:
	assert_array(Array(_step(job, step_name))).contains_exactly(["- name: " + step_name] + body)


## The steps exist and come in this order: a missing one is -1, never greater than the last.
func _assert_order(job: PackedStringArray, step_names: Array) -> void:
	var last: int = -1
	for step_name: String in step_names:
		var at: int = job.find("      - name: " + step_name)
		assert_int(at).is_greater(last)
		last = at


## Job-level keys sit at four spaces: no failure is tolerated (`post`'s own `if:` is pinned apart).
func _assert_job_always_runs(job: PackedStringArray) -> void:
	for line: String in job:
		assert_bool(line.begins_with("    continue-on-error:")).is_false()


func _pin(path: String, pin_name: String) -> String:
	var rx: RegEx = RegEx.create_from_string("(?m)^\\s*" + pin_name + '[=:]\\s*"([^"]+)"')
	var hit: RegExMatch = rx.search(FileAccess.get_file_as_string(path))
	return hit.get_string(1) if hit != null else ""
