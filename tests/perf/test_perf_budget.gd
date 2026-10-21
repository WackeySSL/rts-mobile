extends GdUnitTestSuite
## The CI wall-clock budget (plan P49b), pinned on hand-made budgets and reports:
## tests/perf/support/perf_budget.gd reads tests/perf/budget.cfg and judges a perf report against
## it, test_sim_perf.gd applies it to the native line of the arena. No clock and no World here, so
## the suite reads the same on every machine. The two times of the file are not pinned: they are a
## ratchet that only a qa-engineer PR moves, with its calibration numbers (ADR 0012 section 4).

const PerfBudget: GDScript = preload("res://tests/perf/support/perf_budget.gd")
const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const SECTION: String = "sim"


## The file holds the four values of [sim] for the arena of the harness: 900 ticks of 150 units,
## and two times that are above 0, in order (a mean never above the p95) and far under the
## catastrophic cap, which stays the backstop.
func test_the_file_holds_a_budget_for_the_900_tick_150_unit_arena() -> void:
	var budget: Dictionary = PerfBudget.read()
	assert_array(budget.keys()).is_equal(["mean_ms", "p95_ms", "ticks", "units"])
	assert_int(budget["ticks"]).is_equal(900)
	assert_int(budget["units"]).is_equal(PerfBounds.ARENA_UNITS)
	assert_int(typeof(budget["mean_ms"])).is_equal(TYPE_FLOAT)
	assert_int(typeof(budget["p95_ms"])).is_equal(TYPE_FLOAT)
	assert_float(budget["mean_ms"]).is_greater(0.0)
	assert_float(budget["mean_ms"]).is_less_equal(budget["p95_ms"])
	assert_float(budget["p95_ms"]).is_less(PerfReport.CATASTROPHIC_MEAN_MS)


## A time on its limit passes, and one thousandth over it (the precision of the report) is named
## with its value and its limit. Each time is read from its own key: the mean over with the p95
## under names the mean, and the other way round. The limits have a fourth decimal, as 1.5 x a
## min-of-3 has, so 0.457 is under 0.4575 and 0.458 is over it.
func test_a_time_on_its_limit_passes_and_one_thousandth_over_is_named() -> void:
	var budget: Dictionary = _budget(0.4575, 0.8475)
	assert_array(PerfBudget.violations(_report(0.457, 0.847), budget)).is_empty()
	assert_array(PerfBudget.violations(_report(0.4575, 0.8475), budget)).is_empty()
	assert_array(PerfBudget.violations(_report(0.458, 0.847), budget)).is_equal(
		["mean_ms 0.458 is above the budget 0.4575"]
	)
	assert_array(PerfBudget.violations(_report(0.457, 0.848), budget)).is_equal(
		["p95_ms 0.848 is above the budget 0.8475"]
	)
	assert_array(PerfBudget.violations(_report(0.5, 0.9), budget)).is_equal(
		["mean_ms 0.500 is above the budget 0.4575", "p95_ms 0.900 is above the budget 0.8475"]
	)


## The numbers are calibrated on 900 ticks of 150 units: a run of another size is named whatever
## its times, and so is each count on its own, so a harness that changes the workload (or a
## report that lost its units) cannot pass a budget that was never calibrated for it.
func test_a_run_of_another_size_is_named_even_when_its_times_pass() -> void:
	var budget: Dictionary = _budget(1.0, 2.0)
	assert_array(PerfBudget.violations(_report(0.1, 0.2, 450, 150), budget)).is_equal(
		["the run has 450 ticks, the budget is for 900"]
	)
	assert_array(PerfBudget.violations(_report(0.1, 0.2, 900, 149), budget)).is_equal(
		["the run has 149 units, the budget is for 150"]
	)
	assert_array(PerfBudget.violations(_report(0.1, 0.2, 450, 100), budget)).has_size(2)
	assert_array(PerfBudget.violations(_report(0.1, 0.2, 900, 150), budget)).is_empty()


## A budget that cannot be read is refused, never read as "no limit": a missing file, an empty
## config, each of the four values missing, a value of another section, a count that is not a whole
## number, a time that is not a number and a value that is not above 0 all give an empty budget, and
## an empty budget fails a report with a line that names the file. A whole number is a time.
func test_a_budget_that_cannot_be_read_is_refused() -> void:
	var empty: Dictionary = {}
	assert_dict(PerfBudget.read("res://tests/perf/no_such_budget.cfg")).is_equal(empty)
	assert_dict(PerfBudget.from_config(ConfigFile.new())).is_equal(empty)
	assert_dict(PerfBudget.from_config(_config({}))).is_not_empty()
	for key: String in ["mean_ms", "p95_ms", "ticks", "units"]:
		var values: Dictionary = {key: null}
		assert_dict(PerfBudget.from_config(_config(values))).override_failure_message(key).is_equal(
			empty
		)
	var other: ConfigFile = ConfigFile.new()
	for key: String in ["mean_ms", "p95_ms", "ticks", "units"]:
		other.set_value("other", key, 900 if key in PerfBudget.COUNT_KEYS else 1.0)
	assert_dict(PerfBudget.from_config(other)).is_equal(empty)
	for bad: Dictionary in [
		{"mean_ms": "1.0"},
		{"ticks": 900.0},
		{"units": "150"},
		{"mean_ms": 0.0},
		{"p95_ms": -1.0},
		{"ticks": 0},
		{"units": -150},
	]:
		(
			assert_dict(PerfBudget.from_config(_config(bad)))
			. override_failure_message(str(bad))
			. is_equal(empty)
		)
	var whole: Dictionary = PerfBudget.from_config(_config({"mean_ms": 1}))
	assert_int(typeof(whole["mean_ms"])).is_equal(TYPE_FLOAT)
	assert_float(whole["mean_ms"]).is_equal(1.0)
	var refused: Array[String] = PerfBudget.violations(_report(0.1, 0.2), empty)
	assert_array(refused).has_size(1)
	assert_str(refused[0]).contains("budget.cfg")


## The line the suite prints: each time against its limit, or the plain note without a report (the
## library is not loaded). The note is not a `PERF ` line (P51 copies those) and holds nothing that
## scripts/verify.sh rejects or the engine warns with.
func test_the_status_line_shows_the_headroom_or_the_skip_note() -> void:
	assert_str(PerfBudget.status_line(_report(0.279, 0.492), _budget(0.4575, 0.8475))).is_equal(
		"perf: native mean_ms 0.279 of the budget 0.4575, p95_ms 0.492 of 0.8475"
	)
	var note: String = PerfBudget.status_line({}, _budget(0.4575, 0.8475))
	assert_str(note).is_equal(PerfBudget.SKIPPED)
	assert_bool(note.begins_with("perf: ")).is_true()
	assert_bool("\n" in note).is_false()
	for rejected: String in ["SCRIPT ERROR", "ERROR:", "Parse Error", "WARNING:"]:
		assert_bool(note.contains(rejected)).is_false()


func _budget(mean_ms: float, p95_ms: float) -> Dictionary:
	return {"mean_ms": mean_ms, "p95_ms": p95_ms, "ticks": 900, "units": 150}


func _report(mean_ms: float, p95_ms: float, ticks: int = 900, units: int = 150) -> Dictionary:
	return {"mean_ms": mean_ms, "p95_ms": p95_ms, "ticks": ticks, "units": units}


## A config with the four values of a good budget in [sim], then `changes` on top of them: a value
## is replaced, and a null value is left out.
func _config(changes: Dictionary) -> ConfigFile:
	var values: Dictionary = {"mean_ms": 0.4575, "p95_ms": 0.8475, "ticks": 900, "units": 150}
	values.merge(changes, true)
	var config: ConfigFile = ConfigFile.new()
	for key: String in values:
		if values[key] != null:
			config.set_value(SECTION, key, values[key])
	return config
