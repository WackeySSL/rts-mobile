extends GdUnitTestSuite
## The perf harness on the arena, report only (plan P38p, ADR 0011 section 4, ADR 0012 section 4).
## The perf arena is stepped through MatchLoop with a TimingProbe for 900 ticks, every tick timed:
## seed 42 three times and seed 43 once. The suite prints the PERF line, writes
## reports/perf/sim.json and checks that the three seed-42 runs agree at every checkpoint, that
## seed 43 does not, and that the mean tick stays under a catastrophic cap. Nothing else about the
## clock is asserted: the wall-clock budget is P49b's, and the deterministic cost bounds are P49a's.
## It times MatchLoop.step; P49a switches to TickJob.run().
##
## The enforced numbers are the minimum over the three seed-42 runs of each statistic (ADR 0011
## section 4, a fixed method and not a retry). RUN lines print every run, apart from the one
## `PERF` line that CI copies.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const REPORT_PATH: String = "res://reports/perf/sim.json"
const TICKS: int = 900
const SEED: int = 42
const OTHER_SEED: int = 43
const RUNS: int = 3
## ADR 0011 section 4: a catastrophic cap on the best mean, and nothing else is timed against a
## limit until P49b adds budget.cfg. The wall-clock budget lives in this file only.
const CATASTROPHIC_MEAN_MS: float = 20.0
## Timed calls of the reference loop; the smallest is ref_ms.
const REF_SAMPLES: int = 20

var _gate: PerfGateDef
var _seed_42: Array[Run] = []
var _seed_43: Run
var _ref_ms: float = 0.0
var _report: Dictionary = {}


## What one match leaves: the tick times, the per-phase sums, the World.stats maxima and the
## checkpoints. An engine base class, so it may sit inside this file (P56c).
class Run:
	extends RefCounted
	var tick_ms: PackedFloat64Array = PackedFloat64Array()
	var phase_usec: PackedInt64Array = PackedInt64Array()
	var stats_max: PackedInt32Array = PackedInt32Array()
	var units: int = 0
	var alive_end: int = 0
	var proj_peak: int = 0
	var overflow: int = 0
	var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
	var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
	var final_hash: int = 0


func before() -> void:
	_gate = load(GATE_PATH) as PerfGateDef
	_ref_ms = _reference_ms()
	for _run: int in RUNS:
		_seed_42.append(_play(SEED))
	_seed_43 = _play(OTHER_SEED)
	_ref_ms = minf(_ref_ms, _reference_ms())
	_report = _make_report()
	for index: int in _seed_42.size():
		print(_run_line(SEED, index + 1, _seed_42[index]))
	print(_run_line(OTHER_SEED, 1, _seed_43))


func test_the_three_seed_42_runs_match_at_every_15_ticks() -> void:
	assert_int(_seed_42.size()).is_equal(3)
	var first: Run = _seed_42[0]
	assert_int(first.checkpoint_ticks.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	assert_int(first.checkpoint_ticks[0]).is_equal(Replay.CHECKPOINT_PERIOD)
	assert_int(first.checkpoint_ticks[-1]).is_equal(TICKS)
	# Not vacuous: the 60 checkpoints are 60 different states.
	var distinct: Dictionary[int, bool] = {}
	for hash_value: int in first.checkpoint_hashes:
		distinct[hash_value] = true
	assert_int(distinct.size()).is_equal(first.checkpoint_hashes.size())
	for index: int in range(1, RUNS):
		var run: Run = _seed_42[index]
		assert_array(run.checkpoint_ticks).is_equal(first.checkpoint_ticks)
		assert_array(run.checkpoint_hashes).is_equal(first.checkpoint_hashes)
		assert_int(run.final_hash).is_equal(first.final_hash)
		assert_array(run.stats_max).is_equal(first.stats_max)
	assert_int(first.final_hash).is_equal(first.checkpoint_hashes[-1])


func test_seed_43_differs_at_every_checkpoint_and_in_the_final_hash() -> void:
	var same: Run = _seed_42[0]
	assert_array(_seed_43.checkpoint_ticks).is_equal(same.checkpoint_ticks)
	assert_int(_seed_43.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	var equal_at: Array[int] = []
	for index: int in same.checkpoint_hashes.size():
		if _seed_43.checkpoint_hashes[index] == same.checkpoint_hashes[index]:
			equal_at.append(same.checkpoint_ticks[index])
	assert_array(equal_at).is_empty()
	assert_int(_seed_43.final_hash).is_not_equal(same.final_hash)


## Every statistic of the report is the smallest value that one of the three seed-42 runs had, to
## the thousandth of a ms the report rounds to (ADR 0011 section 4: the minimum over the runs).
func test_the_report_holds_the_minimum_of_each_statistic_over_the_three_runs() -> void:
	var wrong: Array[String] = []
	for key: String in PerfReport.STAT_KEYS:
		var smallest: float = INF
		for run: Run in _seed_42:
			smallest = minf(smallest, PerfReport.run_stats(run.tick_ms)[key])
		if absf(float(_report[key]) - smallest) > 0.0006:
			wrong.append(key)
	assert_array(wrong).is_empty()
	assert_int(_report["runs"]).is_equal(_seed_42.size())
	assert_int(_report["ticks"]).is_equal(TICKS)


func test_the_best_mean_stays_under_the_catastrophic_cap() -> void:
	var mean_ms: float = _report["mean_ms"]
	assert_float(mean_ms).is_greater(0.0)
	assert_float(mean_ms).is_less_equal(CATASTROPHIC_MEAN_MS)


func test_each_run_timed_every_tick_and_played_the_whole_match() -> void:
	for run: Run in _seed_42 + [_seed_43]:
		assert_int(run.tick_ms.size()).is_equal(TICKS)
		assert_int(run.tick_ms.count(0.0)).is_less(TICKS)
		assert_int(run.units).is_greater(0)
		assert_int(run.alive_end).is_between(1, run.units)
		assert_int(run.overflow).is_equal(0)
	assert_int(_report["units"]).is_equal(_seed_42[0].units)
	assert_int(_report["alive_end"]).is_equal(_seed_42[0].alive_end)
	assert_int(_report["proj_peak"]).is_equal(_seed_42[0].proj_peak)


## The phases are timed inside the step, so their means cannot add up to more than the tick mean
## (up to the rounding of the report), and a tick that does work has a phase that reads above 0.
func test_the_phase_split_is_part_of_the_tick() -> void:
	var phases: Dictionary = _report["phases"]
	assert_array(phases.keys()).is_equal(SimProbe.PHASE_NAMES)
	var sum: float = 0.0
	for phase_ms: float in phases.values():
		assert_float(phase_ms).is_greater_equal(0.0)
		sum += phase_ms
	assert_float(sum).is_greater(0.0)
	assert_float(sum).is_less_equal(float(_report["mean_ms"]) + 0.01)


## The estimates are computed from the ratios in perf_gate.tres (ADR 0012 section 4), not written by
## hand: the mean ratio and the p95 ratio differ, so using one for the other changes an estimate.
func test_the_phone_estimates_are_the_best_mean_and_p95_times_the_gate_ratios() -> void:
	var mean_ms: float = _report["mean_ms"]
	var p95_ms: float = _report["p95_ms"]
	assert_float(_report["est_phone_mean_ms"]).is_equal_approx(mean_ms * _gate.ci_ratio_mean, 0.01)
	assert_float(_report["est_phone_p95_ms"]).is_equal_approx(p95_ms * _gate.ci_ratio_p95, 0.01)


## The line carries each measure once and in order, and the hash is the seed-42 final state.
func test_the_perf_line_prints_and_holds_every_measure_in_order() -> void:
	var text: String = PerfReport.line(_report)
	print(text)
	assert_str(text).starts_with("PERF sim units=")
	assert_bool("\n" in text).is_false()
	var keys: Array[String] = []
	for field: String in text.split(" "):
		keys.append(field.get_slice("=", 0))
	var expected: Array[String] = ["PERF", "sim"]
	expected.append_array(PerfReport.LINE_KEYS)
	expected.append_array(["stats_max", "phases", "hash"])
	assert_array(keys).is_equal(expected)
	var hash_text: String = text.get_slice("hash=", 1)
	assert_str(hash_text).is_equal(World.hash_hex(_seed_42[0].final_hash))
	assert_int(hash_text.length()).is_equal(16)
	assert_float(_report["ref_ms"]).is_greater(0.0)
	assert_float(_report["p50_ms"]).is_less_equal(_report["p95_ms"])
	assert_float(_report["p95_ms"]).is_less_equal(_report["p99_ms"])
	assert_float(_report["p99_ms"]).is_less_equal(_report["max_ms"])
	assert_float(_report["max_ms"]).is_less_equal(_report["worst15_ms"])


func test_sim_json_holds_the_numbers_of_the_line() -> void:
	var path: String = ProjectSettings.globalize_path(REPORT_PATH)
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(PerfReport.json(_report))
	file.close()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_int(typeof(parsed)).is_equal(TYPE_DICTIONARY)
	var data: Dictionary = parsed
	var differ: Array[String] = []
	for key: String in PerfReport.LINE_KEYS:
		if not is_equal_approx(float(data[key]), float(_report[key])):
			differ.append(key)
	for group: String in ["phases", "stats_max"]:
		var report_group: Dictionary = _report[group]
		var json_group: Dictionary = data[group]
		assert_int(json_group.size()).is_equal(report_group.size())
		for key: String in report_group:
			if not is_equal_approx(float(json_group[key]), float(report_group[key])):
				differ.append(group + "." + key)
	assert_array(differ).is_empty()
	assert_str(data["hash"]).is_equal(_report["hash"])
	assert_array(data["phases"].keys()).contains_exactly_in_any_order(SimProbe.PHASE_NAMES)
	assert_array(data["stats_max"].keys()).contains_exactly_in_any_order(
		Array(PerfReport.stat_names())
	)


## Steps the arena for TICKS ticks from `match_seed` with the scenario's own orders only, and times
## each MatchLoop.step. The phases, stats and projectile peak are read after the clock stops.
func _play(match_seed: int) -> Run:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(
		scenario, DetRandom.create(match_seed, DetRandom.STREAM_SIM)
	)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, match_seed, world)
	var probe: TimingProbe = TimingProbe.new()
	var queued: Array[Command] = []
	var run: Run = Run.new()
	run.units = world.unit_count()
	run.tick_ms.resize(TICKS)
	run.phase_usec.resize(SimProbe.Phase.COUNT)
	run.stats_max.resize(World.Stat.size())
	for tick: int in TICKS:
		var started: int = Time.get_ticks_usec()
		loop.step(world, queued, probe)
		run.tick_ms[tick] = (Time.get_ticks_usec() - started) / 1000.0
		for phase: int in SimProbe.Phase.COUNT:
			run.phase_usec[phase] += probe.phase_usec[phase]
		PerfReport.raise_maxima(run.stats_max, world.stats)
		run.proj_peak = maxi(run.proj_peak, PerfReport.live_projectiles(world))
	run.alive_end = world.unit_count()
	run.overflow = world.projectile_overflow
	run.checkpoint_ticks = loop.replay.checkpoint_ticks
	run.checkpoint_hashes = loop.replay.checkpoint_hashes
	run.final_hash = world.state_hash()
	return run


## ref_ms: the smallest of REF_SAMPLES timed calls of the reference loop (after one warm-up call),
## in ms. The line's `ref_ms` is the smaller of the readings before and after the runs, so a
## slow runner shows in it (ADR 0011 section 4: a proven runner-speed problem may switch to a
## relative budget through a new ADR).
func _reference_ms() -> float:
	var sink: int = RefLoop.run(_gate.ref_iterations)
	var smallest_usec: int = 1 << 40
	for _sample: int in REF_SAMPLES:
		var started: int = Time.get_ticks_usec()
		sink += RefLoop.run(_gate.ref_iterations)
		smallest_usec = mini(smallest_usec, Time.get_ticks_usec() - started)
	assert_int(sink).is_greater(0)
	return smallest_usec / 1000.0


func _make_report() -> Dictionary:
	var stats: Array[Dictionary] = []
	var phases: Array[PackedFloat64Array] = []
	for run: Run in _seed_42:
		stats.append(PerfReport.run_stats(run.tick_ms))
		phases.append(PerfReport.phase_means_ms(run.phase_usec, TICKS))
	var first: Run = _seed_42[0]
	var facts: Dictionary = {
		"units": first.units,
		"ticks": TICKS,
		"runs": RUNS,
		"ref_ms": _ref_ms,
		"alive_end": first.alive_end,
		"proj_peak": first.proj_peak,
		"projectile_overflow": first.overflow,
		"hash": World.hash_hex(first.final_hash),
	}
	return PerfReport.finish(
		facts, PerfReport.best_of(stats), PerfReport.best_phases(phases), first.stats_max, _gate
	)


func _run_line(match_seed: int, number: int, run: Run) -> String:
	var stats: Dictionary = PerfReport.run_stats(run.tick_ms)
	return (
		"RUN sim seed=%d run=%d mean_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f hash=%s"
		% [
			match_seed,
			number,
			stats["mean_ms"],
			stats["p50_ms"],
			stats["p95_ms"],
			stats["max_ms"],
			World.hash_hex(run.final_hash),
		]
	)
