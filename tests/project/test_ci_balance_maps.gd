extends GdUnitTestSuite
## Pins the harness sets of maps 2 and 3 (P554): balance.yml's `maps` suite and its `map` input, the
## `map` column of scripts/ci/balance-plan.sh's shard table, and that the files of Heron Fords and
## Curlew Crags still start the workflow after P509's negated paths. A new suite, because
## test_ci_balance_workflow.gd is full (gdlint's 20 public methods and the size of that file).

const BALANCE: String = "res://.github/workflows/balance.yml"
const BALANCE_PLAN: String = "res://scripts/ci/balance-plan.sh"
## The `maps` suite: set, levels, scenarios, map, first seed, matches. Seeds 1-50 per map, none from
## 1000 up. The sets are named after the maps, and no set name is the prefix of another's.
const MAPS_TABLE: Array[String] = [
	"heron-fords|normal,normal|cross|heron|1|25",
	"curlew-crags|normal,normal|cross|curlew|1|25",
	"heron-fords|normal,normal|cross|heron|26|25",
	"curlew-crags|normal,normal|cross|curlew|26|25",
]
## Every file of maps 2 and 3 that the balance of a match reads: the maps and the four scenarios of
## each. A change to one must start the balance run.
const MAP_FILES: Array[String] = [
	"data/maps/heron_fords.tres",
	"data/maps/curlew_crags.tres",
	"data/scenarios/skirmish_heron_fords.tres",
	"data/scenarios/skirmish_heron_fords_mirrored.tres",
	"data/scenarios/skirmish_heron_fords_fossil_mirror.tres",
	"data/scenarios/skirmish_heron_fords_renew_mirror.tres",
	"data/scenarios/skirmish_curlew_crags.tres",
	"data/scenarios/skirmish_curlew_crags_mirrored.tres",
	"data/scenarios/skirmish_curlew_crags_fossil_mirror.tres",
	"data/scenarios/skirmish_curlew_crags_renew_mirror.tres",
]
## Files that P509 keeps out of the trigger: the tutorial's maps and scenarios and the catalog.
const EXCLUDED_FILES: Array[String] = [
	"data/maps/catalog.tres",
	"data/maps/tutorial_yard.tres",
	"data/scenarios/tutorial_first_steps.tres",
	"data/tutorial/step_1.tres",
	"game/ai/TutorialAi.gd",
]


## The maps suite plays one set per new map, each with its own report prefix, on its own map.
func test_the_maps_suite_is_one_set_per_new_map() -> void:
	var plan: Dictionary = _plan("SUITE=maps", "matrix")
	assert_int(plan["code"]).is_equal(0)
	var rows: Array = (JSON.parse_string(plan["out"]) as Dictionary)["include"]
	assert_array(rows.map(_row_text)).is_equal(MAPS_TABLE)
	for row: Dictionary in rows:
		assert_int(int(row["seed_start"]) + int(row["matches"]) - 1).is_less(1000)
		assert_str(row["name"]).starts_with(str(row["set"]) + "-")
	assert_str(_plan("SUITE=maps", "sets")["out"]).is_equal("heron-fords curlew-crags")
	# The other suites stay on Kestrel Flats, so the balance table and the gate are as they were.
	for suite: String in ["balance", "gate"]:
		var other: Array = (
			JSON.parse_string(_plan("SUITE=" + suite, "matrix")["out"]) as Dictionary
		)["include"]
		for row: Dictionary in other:
			assert_str(row["map"]).is_equal("kestrel")


## A custom run plays the map it is given (default Kestrel Flats, or `all`) and refuses another.
func test_a_custom_run_takes_a_map_and_refuses_an_unknown_one() -> void:
	var default_row: Array = _rows(_plan("SUITE=custom", "matrix")["out"])
	assert_str(default_row[0]["map"]).is_equal("kestrel")
	for map: String in ["kestrel", "heron", "curlew", "all"]:
		var rows: Array = _rows(_plan("SUITE=custom MATCHES=30 MAP=" + map, "matrix")["out"])
		assert_int(rows.size()).is_equal(2)
		for row: Dictionary in rows:
			assert_str(row["map"]).is_equal(map)
	for refused: String in ["MAP=map_2", "MAP=Heron", "MAP=heron,curlew", "MAP=kestrel_flats"]:
		assert_int(_plan("SUITE=custom " + refused, "matrix")["code"]).is_equal(2)
	# The map is ignored outside a custom run: the maps suite fixes its own.
	assert_array(_rows(_plan("SUITE=maps MAP=all", "matrix")["out"]).map(_row_text)).is_equal(
		MAPS_TABLE
	)


## The workflow offers the suite and the input, hands the input to the plan through env, and gives
## each shard its row's map: no `${{` in a run block, the new flag after the old ones.
func test_the_workflow_hands_the_map_from_the_input_to_the_plan_and_the_shard() -> void:
	var text: String = FileAccess.get_file_as_string(BALANCE)
	assert_str(text).contains("        options: [balance, gate, maps, custom]")
	assert_str(text).contains('      map:\n        description: "custom: the map')
	assert_str(text).contains("        default: kestrel\n")
	assert_str(text).contains("          MAP: ${{ inputs.map }}\n")
	assert_str(text).contains("          MAP: ${{ matrix.map }}\n")
	assert_str(text).contains('--scenarios "$SCENARIOS" --map "$MAP" --report')
	# A maps run posts like a balance run: only a custom run keeps its artifact only.
	assert_str(text).contains("(github.event_name == 'push' || inputs.suite != 'custom')")
	# The old inputs and their defaults stay.
	for old: String in ["      suite:", "      levels:", "      scenarios:", "      matches:"]:
		assert_str(text).contains(old)
	assert_str(text).contains('        default: "20"\n')
	assert_str(text).contains("        default: normal,normal\n")
	assert_str(text).contains("        default: cross\n")


## P509 negates the tutorial's files and the catalog; the files of maps 2 and 3 still match a
## positive path and no negation after it, so a change to them starts the run. GitHub's rule: the
## last pattern that matches decides, and a file that matches none does not start the run.
func test_the_files_of_maps_2_and_3_still_start_the_balance_run() -> void:
	var patterns: Array[String] = _push_paths()
	assert_int(patterns.size()).is_greater(10)
	for file: String in MAP_FILES:
		assert_bool(_starts_run(patterns, file)).override_failure_message(file).is_true()
		assert_bool(ResourceLoader.exists("res://" + file)).override_failure_message(file).is_true()
	for file: String in EXCLUDED_FILES:
		assert_bool(_starts_run(patterns, file)).override_failure_message(file).is_false()
	# The sim and the AI still start it.
	assert_bool(_starts_run(patterns, "game/sim/World.gd")).is_true()
	assert_bool(_starts_run(patterns, "data/ai/opponent_fossil.tres")).is_true()


## The paths of the push trigger, in order, as written (`!` kept).
func _push_paths() -> Array[String]:
	var found: Array[String] = []
	var in_paths: bool = false
	for line: String in FileAccess.get_file_as_string(BALANCE).split("\n"):
		if line == "    paths:":
			in_paths = true
		elif in_paths and line.begins_with('      - "'):
			found.append(line.trim_prefix('      - "').trim_suffix('"'))
		elif in_paths:
			break
	return found


## Whether `file` starts the run under `patterns`: the last matching pattern decides, a `!` one
## excludes, and no match at all does not start it.
func _starts_run(patterns: Array[String], file: String) -> bool:
	var starts: bool = false
	for pattern: String in patterns:
		var negated: bool = pattern.begins_with("!")
		if _glob(pattern.trim_prefix("!")).search(file) != null:
			starts = not negated
	return starts


## The regex of a GitHub path glob: `**` crosses folders, `*` stays inside one.
func _glob(pattern: String) -> RegEx:
	var source: String = "^"
	var at: int = 0
	while at < pattern.length():
		if pattern.substr(at, 2) == "**":
			source += ".*"
			at += 2
		else:
			var letter: String = pattern[at]
			source += "[^/]*" if letter == "*" else letter.replace(".", "\\.")
			at += 1
	var regex: RegEx = RegEx.create_from_string(source + "$")
	assert_bool(regex.is_valid()).is_true()
	return regex


func _rows(matrix_json: String) -> Array:
	var parsed: Variant = JSON.parse_string(matrix_json)
	assert_bool(parsed is Dictionary).is_true()
	return (parsed as Dictionary)["include"]


func _row_text(row: Dictionary) -> String:
	return (
		"%s|%s|%s|%s|%d|%d"
		% [
			row["set"],
			row["levels"],
			row["scenarios"],
			row["map"],
			int(row["seed_start"]),
			int(row["matches"])
		]
	)


## Runs balance-plan.sh under `env -i` with `assignments` (VAR=value words) in its environment.
func _plan(assignments: String, mode: String) -> Dictionary:
	var out: Array = []
	var arguments: PackedStringArray = ["-i", "PATH=" + OS.get_environment("PATH")]
	for word: String in assignments.split(" ", false):
		arguments.append(word)
	arguments.append_array(["bash", ProjectSettings.globalize_path(BALANCE_PLAN), mode])
	var code: int = OS.execute("env", arguments, out)
	return {"code": code, "out": str(out[0]).strip_edges() if out.size() > 0 else ""}
