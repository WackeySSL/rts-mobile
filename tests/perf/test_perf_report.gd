extends GdUnitTestSuite
## The numbers and the text of the perf harness (plan P38p, ADR 0011 section 4, ADR 0012 section
## 4), on fake samples and with no clock: the statistics of a run, the best of several runs, the
## phone estimates from the gate, the catastrophic cap, the PERF line and sim.json, and the
## contents of data/dev/perf_gate.tres. test_sim_perf.gd runs the real arena through the same code.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
## Every field with this prefix is a printed phone / CI ratio, not a threshold (plan exception 5).
const RATIO_PREFIX: String = "ci_ratio_"
## The golden arrays are P49a's: they only have to pair up.
const GOLDEN_FIELDS: Array[String] = ["golden_ticks", "golden_hex"]
## The fields that are exempt from equality and still need a line in the file. The native ratios
## are not listed: P54r adds them to the script, but P38pn writes them to the file.
const EXEMPT_FIELDS_IN_FILE: Array[String] = [
	"ci_ratio_mean", "ci_ratio_p95", "golden_ticks", "golden_hex"
]
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## A line made from known inputs, with PerfGateDef's ratios 4.4 and 5.9: 1.5 x 4.4 and 3 x 5.9.
const KNOWN_LINE: String = (
	"PERF sim units=150 ticks=900 runs=3 mean_ms=1.500 p50_ms=1.000 p95_ms=3.000 p99_ms=4.000"
	+ " max_ms=5.000 worst15_ms=20.000 ticks_per_s=666.667 ref_ms=0.250 est_phone_mean_ms=6.600"
	+ " est_phone_p95_ms=17.700 alive_end=148 proj_peak=7 projectile_overflow=0"
	+ " phases=commands:0.100,flow:0.200,grids:0.300,targeting:0.400,intents:0.500,"
	+ "separation:0.600,integrate:0.700,projectiles:0.800,fire:0.900,remove:1.000,fog:1.100"
	+ " hash=0123456789abcdef"
)


## 30 ticks of 1 ms with a 100 ms tick at index 3 and a 50 ms tick at index 26, 23 ticks apart, so
## no 15-tick window holds both. Sorted, the series ends in 50 and 100; the worst window is
## 14 + 100 in tick order and 13 + 50 + 100 if the series were sorted first.
func test_run_stats_read_the_nearest_ranks_and_the_worst_window_in_tick_order() -> void:
	var tick_ms: PackedFloat64Array = PackedFloat64Array()
	tick_ms.resize(30)
	tick_ms.fill(1.0)
	tick_ms[3] = 100.0
	tick_ms[26] = 50.0
	var stats: Dictionary = PerfReport.run_stats(tick_ms)
	assert_array(stats.keys()).is_equal(PerfReport.STAT_KEYS)
	assert_float(stats["mean_ms"]).is_equal_approx(178.0 / 30.0, 0.000001)
	assert_float(stats["p50_ms"]).is_equal(1.0)
	assert_float(stats["p95_ms"]).is_equal(50.0)
	assert_float(stats["p99_ms"]).is_equal(100.0)
	assert_float(stats["max_ms"]).is_equal(100.0)
	assert_float(stats["worst15_ms"]).is_equal(114.0)
	# The caller's series is not sorted in place.
	assert_float(tick_ms[3]).is_equal(100.0)


## 200 ticks that are a permutation of 1 to 200 ms (37 is coprime to 200), so the nearest ranks
## 100, 190 and 198 are the values 100, 190 and 198, and a neighbouring percentile reads another.
func test_run_stats_read_ranks_100_190_and_198_of_200_shuffled_ticks() -> void:
	var tick_ms: PackedFloat64Array = PackedFloat64Array()
	for index: int in 200:
		tick_ms.append(float(index * 37 % 200 + 1))
	var stats: Dictionary = PerfReport.run_stats(tick_ms)
	assert_float(stats["mean_ms"]).is_equal(100.5)
	assert_float(stats["p50_ms"]).is_equal(100.0)
	assert_float(stats["p95_ms"]).is_equal(190.0)
	assert_float(stats["p99_ms"]).is_equal(198.0)
	assert_float(stats["max_ms"]).is_equal(200.0)
	# The worst window of 15, by brute force.
	var worst: float = 0.0
	for start: int in range(0, 200 - 15 + 1):
		var sum: float = 0.0
		for offset: int in 15:
			sum += tick_ms[start + offset]
		worst = maxf(worst, sum)
	assert_float(stats["worst15_ms"]).is_equal(worst)


## Each statistic keeps its own smallest value: run A has the better mean, run B the better p95.
func test_best_of_takes_the_minimum_of_each_statistic_separately() -> void:
	var a: Dictionary = {}
	var b: Dictionary = {}
	for key: String in PerfReport.STAT_KEYS:
		a[key] = 10.0
		b[key] = 12.0
	a["mean_ms"] = 3.0
	b["mean_ms"] = 4.0
	a["p95_ms"] = 9.0
	b["p95_ms"] = 8.0
	b["max_ms"] = 7.0
	var runs: Array[Dictionary] = [a, b]
	var best: Dictionary = PerfReport.best_of(runs)
	assert_array(best.keys()).is_equal(PerfReport.STAT_KEYS)
	assert_array(best.values()).is_equal([3.0, 10.0, 8.0, 10.0, 7.0, 10.0])
	var none: Array[Dictionary] = []
	assert_array(PerfReport.best_of(none).values()).is_equal([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func test_phase_means_are_the_microsecond_sums_over_the_ticks_in_ms() -> void:
	var sums: PackedInt64Array = PackedInt64Array()
	sums.resize(SimProbe.Phase.COUNT)
	sums[SimProbe.Phase.COMMANDS] = 900_000
	sums[SimProbe.Phase.INTEGRATE] = 450_000
	sums[SimProbe.Phase.FOG] = 1
	var means: PackedFloat64Array = PerfReport.phase_means_ms(sums, 900)
	assert_int(means.size()).is_equal(SimProbe.Phase.COUNT)
	assert_float(means[SimProbe.Phase.COMMANDS]).is_equal_approx(1.0, 0.000001)
	assert_float(means[SimProbe.Phase.INTEGRATE]).is_equal_approx(0.5, 0.000001)
	assert_float(means[SimProbe.Phase.FOG]).is_equal_approx(1.0 / 900_000.0, 1e-12)
	assert_float(means[SimProbe.Phase.FLOW]).is_equal(0.0)


func test_best_phases_take_the_minimum_of_each_phase() -> void:
	var runs: Array[PackedFloat64Array] = []
	for scale: float in [3.0, 1.0, 2.0]:
		var phases: PackedFloat64Array = PackedFloat64Array()
		phases.resize(SimProbe.Phase.COUNT)
		for phase: int in SimProbe.Phase.COUNT:
			phases[phase] = (phase + 1) * scale
		runs.append(phases)
	runs[0][SimProbe.Phase.FIRE] = 0.5
	var best: PackedFloat64Array = PerfReport.best_phases(runs)
	assert_int(best.size()).is_equal(SimProbe.Phase.COUNT)
	for phase: int in SimProbe.Phase.COUNT:
		var expected: float = 0.5 if phase == SimProbe.Phase.FIRE else (phase + 1) * 1.0
		assert_float(best[phase]).is_equal(expected)


func test_raise_maxima_keeps_the_larger_value_at_each_index() -> void:
	var maxima: PackedInt32Array = PackedInt32Array([0, 5, 0, 9])
	PerfReport.raise_maxima(maxima, PackedInt32Array([3, 2, 0, 11]))
	assert_array(maxima).is_equal(PackedInt32Array([3, 5, 0, 11]))
	PerfReport.raise_maxima(maxima, PackedInt32Array([1, 6, 0, 2]))
	assert_array(maxima).is_equal(PackedInt32Array([3, 6, 0, 11]))


## The last phase is in the list on purpose: a loop that stops one short leaves FOG at 0.
func test_add_phases_adds_every_phase_of_a_tick_to_the_sums() -> void:
	var sums: PackedInt64Array = PackedInt64Array()
	sums.resize(SimProbe.Phase.COUNT)
	var tick_usec: PackedInt64Array = PackedInt64Array()
	tick_usec.resize(SimProbe.Phase.COUNT)
	for phase: int in SimProbe.Phase.COUNT:
		tick_usec[phase] = (phase + 1) * 10
	PerfReport.add_phases(sums, tick_usec)
	PerfReport.add_phases(sums, tick_usec)
	for phase: int in SimProbe.Phase.COUNT:
		assert_int(sums[phase]).is_equal(2 * (phase + 1) * 10)
	assert_int(sums.size()).is_equal(SimProbe.Phase.COUNT)


func test_smallest_is_the_least_sample_wherever_it_is_and_zero_for_none() -> void:
	assert_int(PerfReport.smallest(PackedInt64Array([5, 3, 9]))).is_equal(3)
	assert_int(PerfReport.smallest(PackedInt64Array([3, 5, 9]))).is_equal(3)
	assert_int(PerfReport.smallest(PackedInt64Array([9, 5, 3]))).is_equal(3)
	assert_int(PerfReport.smallest(PackedInt64Array([7]))).is_equal(7)
	assert_int(PerfReport.smallest(PackedInt64Array())).is_equal(0)


## ADR 0011 section 4: 20 ms, on the best mean and on nothing else. The boundary is not over.
func test_the_cap_is_20_ms_of_the_best_mean_and_of_nothing_else() -> void:
	var cap: float = PerfReport.CATASTROPHIC_MEAN_MS
	assert_float(cap).is_equal(20.0)
	assert_bool(PerfReport.over_cap({"mean_ms": 19.999}, cap)).is_false()
	assert_bool(PerfReport.over_cap({"mean_ms": 20.0}, cap)).is_false()
	assert_bool(PerfReport.over_cap({"mean_ms": 20.001}, cap)).is_true()
	assert_bool(PerfReport.over_cap({"mean_ms": 5.0}, 4.0)).is_true()
	var slow_tail: Dictionary = {
		"mean_ms": 5.0,
		"p50_ms": 99.0,
		"p95_ms": 99.0,
		"p99_ms": 99.0,
		"max_ms": 999.0,
		"worst15_ms": 9999.0,
	}
	assert_bool(PerfReport.over_cap(slow_tail, cap)).is_false()


func test_live_projectiles_counts_the_slots_that_hold_an_id() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(1, DetRandom.STREAM_SIM))
	world.prepare()
	assert_int(world.proj_id.size()).is_greater(1)
	assert_int(PerfReport.live_projectiles(world)).is_equal(0)
	world.proj_id[0] = 5
	world.proj_id[world.proj_id.size() - 1] = 9
	assert_int(PerfReport.live_projectiles(world)).is_equal(2)


func test_stat_names_are_the_world_stat_enum_in_index_order() -> void:
	var names: PackedStringArray = PerfReport.stat_names()
	assert_int(names.size()).is_equal(World.Stat.size())
	assert_str(names[World.Stat.FLOW_CELLS]).is_equal("flow_cells")
	assert_str(names[World.Stat.TARGET_CANDIDATES]).is_equal("target_candidates")
	assert_str(names[World.Stat.ROWS_COMPACTED]).is_equal("rows_compacted")


func test_the_line_is_exactly_the_known_text() -> void:
	assert_str(PerfReport.line(_known_report(PerfGateDef.new()))).is_equal(_known_line())


## The estimates read the gate they are given: ratios 2 and 3 instead of 4.4 and 5.9 give 3 and 9,
## and nothing else on the line moves.
func test_the_estimates_come_from_the_gate_argument() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.ci_ratio_mean = 2.0
	gate.ci_ratio_p95 = 3.0
	var report: Dictionary = _known_report(gate)
	assert_float(report["est_phone_mean_ms"]).is_equal(3.0)
	assert_float(report["est_phone_p95_ms"]).is_equal(9.0)
	var line: String = PerfReport.line(report)
	assert_str(line).contains(" est_phone_mean_ms=3.000 est_phone_p95_ms=9.000 ")
	var changed: String = _known_line().replace(
		"est_phone_mean_ms=6.600 est_phone_p95_ms=17.700",
		"est_phone_mean_ms=3.000 est_phone_p95_ms=9.000"
	)
	assert_str(line).is_equal(changed)


func test_the_json_is_the_report_with_sorted_keys_and_a_final_newline() -> void:
	var report: Dictionary = _known_report(PerfGateDef.new())
	var text: String = PerfReport.json(report)
	assert_str(text).ends_with("}\n")
	assert_str(text).starts_with('{\n\t"alive_end": 148,')
	var parsed: Dictionary = JSON.parse_string(text)
	assert_float(parsed["mean_ms"]).is_equal(1.5)
	assert_float(parsed["est_phone_p95_ms"]).is_equal(17.7)
	assert_str(parsed["hash"]).is_equal("0123456789abcdef")
	assert_float(parsed["phases"]["fog"]).is_equal(1.1)
	assert_int(parsed["stats_max"].size()).is_equal(World.Stat.size())


## perf_gate.tres is a PerfGateDef whose fields hold PerfGateDef's contract values, with their
## types (an int field stays an int). Two groups are exempt from equality. Every ratio (ci_ratio_*,
## also the native ones that P54r adds to the script) is a printed estimate that the lead's
## one-value PR changes in this file alone (plan exception 5), so it only has to be a sensible
## float. The golden arrays are P49a's, so they only have to pair up.
func test_the_gate_file_holds_the_contract_values() -> void:
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	assert_object(gate).is_not_null()
	var defaults: PerfGateDef = PerfGateDef.new()
	var compared: Array[String] = []
	var ratios: Array[String] = []
	for field: String in _gate_fields(defaults):
		if field.begins_with(RATIO_PREFIX):
			ratios.append(field)
		elif field not in GOLDEN_FIELDS:
			compared.append(field)
	var wrong: Array[String] = []
	for field: String in compared:
		if typeof(gate.get(field)) != typeof(defaults.get(field)):
			wrong.append(field + " (type)")
		elif gate.get(field) != defaults.get(field):
			wrong.append(field + " (value)")
	assert_array(wrong).is_empty()
	# Not vacuous: the 19 thresholds and pacing values of the contract, and the two ratios.
	assert_int(compared.size()).is_greater_equal(19)
	assert_array(ratios).contains(["ci_ratio_mean", "ci_ratio_p95"])
	for field: String in ratios:
		assert_int(typeof(gate.get(field))).override_failure_message(field).is_equal(TYPE_FLOAT)
		assert_float(gate.get(field)).override_failure_message(field).is_between(1.0, 100.0)
	assert_int(typeof(gate.golden_ticks)).is_equal(TYPE_PACKED_INT32_ARRAY)
	assert_int(typeof(gate.golden_hex)).is_equal(TYPE_PACKED_STRING_ARRAY)
	assert_int(gate.golden_ticks.size()).is_equal(gate.golden_hex.size())


## A line that is missing from the file loads as the script default, so it passes the test above,
## and it follows a later change of that default. Each compared field, the two ratios and the
## golden arrays have a `field = value` line in the file. The native ratios are left out until
## P38pn writes them. Godot leaves out default-valued lines when the editor saves a resource, so
## edit this file as text.
func test_the_gate_file_has_a_line_for_every_contract_value() -> void:
	var text: String = "\n" + FileAccess.get_file_as_string(GATE_PATH)
	assert_str(text).is_not_equal("\n")
	var required: Array[String] = EXEMPT_FIELDS_IN_FILE.duplicate()
	for field: String in _gate_fields(PerfGateDef.new()):
		if not field.begins_with(RATIO_PREFIX) and field not in GOLDEN_FIELDS:
			required.append(field)
	var missing: Array[String] = []
	for field: String in required:
		if not text.contains("\n" + field + " = "):
			missing.append(field)
	assert_array(missing).is_empty()
	assert_int(required.size()).is_greater_equal(23)


## The names of the script variables of `gate`, in declaration order.
func _gate_fields(gate: PerfGateDef) -> Array[String]:
	var fields: Array[String] = []
	for property: Dictionary in gate.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(property["name"])
	return fields


## The report of the known line: statistics and facts as described at KNOWN_LINE.
func _known_report(gate: PerfGateDef) -> Dictionary:
	var best: Dictionary = {
		"mean_ms": 1.5,
		"p50_ms": 1.0,
		"p95_ms": 3.0,
		"p99_ms": 4.0,
		"max_ms": 5.0,
		"worst15_ms": 20.0,
	}
	var facts: Dictionary = {
		"units": 150,
		"ticks": 900,
		"runs": 3,
		"ref_ms": 0.25,
		"alive_end": 148,
		"proj_peak": 7,
		"projectile_overflow": 0,
		"hash": "0123456789abcdef",
	}
	var phases: PackedFloat64Array = PackedFloat64Array()
	for phase: int in SimProbe.Phase.COUNT:
		phases.append((phase + 1) / 10.0)
	var maxima: PackedInt32Array = PackedInt32Array()
	maxima.resize(World.Stat.size())
	for stat: int in maxima.size():
		maxima[stat] = stat * 10
	return PerfReport.finish(facts, best, phases, maxima, gate)


## KNOWN_LINE with the stats_max part put in before phases=. It is made from the World.Stat names
## (the maximum of stat i is 10 x i), so that a new stat does not break this suite.
func _known_line() -> String:
	var pairs: PackedStringArray = PackedStringArray()
	var names: PackedStringArray = PerfReport.stat_names()
	for index: int in names.size():
		pairs.append("%s:%d" % [names[index], index * 10])
	return KNOWN_LINE.replace(" phases=", " stats_max=" + ",".join(pairs) + " phases=")
