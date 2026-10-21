extends RefCounted
## The CI wall-clock budget (plan P49b, ADR 0012 section 4): reads tests/perf/budget.cfg and judges
## a perf report against it. A regression ratchet at 1.5 x the worst calibrated min-of-3 of the
## native tick; the numbers live only in that file. Pure: no clock and no World, the caller passes
## the report. test_perf_budget.gd pins it on hand-made budgets and reports; test_sim_perf.gd
## applies it to the report of the native runs. Not a test suite.

const PATH: String = "res://tests/perf/budget.cfg"
const SECTION: String = "sim"
## The times that the report may not pass (the report's best mean and p95, ms per tick), and the
## workload that they are calibrated on (the report's ticks and units, which must be equal).
const MS_KEYS: Array[String] = ["mean_ms", "p95_ms"]
const COUNT_KEYS: Array[String] = ["ticks", "units"]
## What the suite prints in place of the headroom line when the library is not loaded (the web, a
## build without it): the budget is calibrated on the native tick, so the GDScript line is not
## judged. Plain text: it does not start with `PERF ` (P51 copies those lines).
const SKIPPED: String = (
	"perf: no budget check, the SimKernels library is not loaded"
	+ " (the budget is calibrated on the native tick)"
)


## The budget of the file at `path`: mean_ms and p95_ms (floats) and ticks and units (ints); an
## empty dictionary when the file cannot be read or does not hold all four in [sim].
static func read(path: String = PATH) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return {}
	return from_config(config)


## The budget that `config` holds, or an empty dictionary when one of the four is missing, of
## another type (a whole number is taken for a time) or not above 0.
static func from_config(config: ConfigFile) -> Dictionary:
	var budget: Dictionary = {}
	for key: String in MS_KEYS + COUNT_KEYS:
		if not config.has_section_key(SECTION, key):
			return {}
		var value: Variant = config.get_value(SECTION, key)
		var is_count: bool = key in COUNT_KEYS
		if typeof(value) != TYPE_INT and (is_count or typeof(value) != TYPE_FLOAT):
			return {}
		if value <= 0:
			return {}
		budget[key] = value if is_count else float(value)
	return budget


## One line for each way that `report` (a PerfReport dictionary) fails `budget`: a ticks or units
## count that is not the budget's (the numbers are calibrated on that workload), a best mean or p95
## above its limit. An empty budget is refused with one line, so a missing file cannot pass.
static func violations(report: Dictionary, budget: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if budget.is_empty():
		found.append("%s is missing or has no value above 0 for each of [%s]" % [PATH, SECTION])
		return found
	for key: String in COUNT_KEYS:
		if report[key] != budget[key]:
			found.append(
				"the run has %d %s, the budget is for %d" % [report[key], key, budget[key]]
			)
	for key: String in MS_KEYS:
		if report[key] > budget[key]:
			found.append("%s %.3f is above the budget %.4f" % [key, report[key], budget[key]])
	return found


## The line the suite prints: each time of `report` against its limit, or SKIPPED for an empty
## report (no native line). Printed from the one statement that both paths run.
static func status_line(report: Dictionary, budget: Dictionary) -> String:
	if report.is_empty():
		return SKIPPED
	return (
		"perf: native %s of the budget %s, %s of %s"
		% [
			"mean_ms %.3f" % report["mean_ms"],
			"%.4f" % budget.get("mean_ms", 0.0),
			"p95_ms %.3f" % report["p95_ms"],
			"%.4f" % budget.get("p95_ms", 0.0),
		]
	)
