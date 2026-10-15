extends GdUnitTestSuite
## The perf harness on the arena, report only (plan P38p, ADR 0011 section 4, ADR 0012 section 4).
## The perf arena is stepped through MatchLoop with a TimingProbe for 900 ticks, every tick timed:
## seed 42 three times and seed 43 once. The suite prints the PERF line, writes
## reports/perf/sim.json and checks that the three seed-42 runs agree at every checkpoint, that
## seed 43 does not, and that the mean tick stays under a catastrophic cap. Nothing else about the
## clock is asserted: the wall-clock budget is P49b's, and the deterministic cost bounds (what the
## arena's units and projectiles may do) are P49a's, so alive_end and the projectile numbers are
## printed here and fail nothing.
## It times MatchLoop.step; P49a switches to TickJob.run().
##
## The enforced numbers are the minimum over the three seed-42 runs of each statistic (ADR 0011
## section 4, a fixed method and not a retry). RUN lines print every run, apart from the one
## `PERF` line that CI copies.
##
## The numbers that the line takes from the World (units, alive_end, the World.stats maxima, the
## projectile peak and overflow) are zero or constant on today's arena, so three cases pin the code
## that reads them without the sim's help: _play on a start that the test crafts, _sample on a
## hand-built world, and _make_report on three runs made by hand. The first two assert inequalities
## only, so P41's combat and P42's projectiles do not break them.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const REPORT_PATH: String = "res://reports/perf/sim.json"
## reports/ is kept out of the import and the exports by this marker (run-tests.sh writes it too).
const REPORT_IGNORE_PATH: String = "res://reports/.gdignore"
const TICKS: int = 900
const SEED: int = 42
const OTHER_SEED: int = 43
const RUNS: int = 3
## Timed calls of the reference loop; the smallest is ref_ms.
const REF_SAMPLES: int = 20
## Half of the thousandth of a ms that the report rounds each time to.
const ROUNDING_MS: float = 0.0005
## The projectile_overflow that the crafted start gives the World (a counter since match start).
const CRAFTED_OVERFLOW: int = 3

var _gate: PerfGateDef
var _seed_42: Array[Run] = []
var _seed_43: Run
var _ref_usec: PackedInt64Array = PackedInt64Array()
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
	## pos_x then pos_y of every unit, before the first tick and after the last.
	var start_pos: PackedInt32Array = PackedInt32Array()
	var final_pos: PackedInt32Array = PackedInt32Array()
	var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
	var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
	var final_hash: int = 0


func before() -> void:
	_gate = load(GATE_PATH) as PerfGateDef
	_time_reference()
	for _run: int in RUNS:
		_seed_42.append(_play(SEED))
	_seed_43 = _play(OTHER_SEED)
	_time_reference()
	_report = _make_report(_seed_42)
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
		assert_array(run.start_pos).is_equal(first.start_pos)
		assert_array(run.final_pos).is_equal(first.final_pos)
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
	# Not only the rng words in the hash: the seed gives the match other places for its units.
	assert_int(_seed_43.start_pos.size()).is_equal(same.start_pos.size())
	assert_array(_seed_43.start_pos).is_not_equal(same.start_pos)
	assert_array(_seed_43.final_pos).is_not_equal(same.final_pos)


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
	assert_float(_report["mean_ms"]).is_greater(0.0)
	assert_bool(PerfReport.over_cap(_report, PerfReport.CATASTROPHIC_MEAN_MS)).is_false()


## Harness checks only: what the units and projectiles do is printed, and bounded from P49a on.
func test_each_run_timed_every_tick_of_the_arena() -> void:
	for run: Run in _seed_42 + [_seed_43]:
		assert_int(run.tick_ms.size()).is_equal(TICKS)
		assert_int(run.tick_ms.count(0.0)).is_less(TICKS)
		assert_int(run.units).is_greater(0)
	assert_int(_report["units"]).is_equal(_seed_42[0].units)
	assert_int(_report["alive_end"]).is_equal(_seed_42[0].alive_end)
	assert_int(_report["proj_peak"]).is_equal(_seed_42[0].proj_peak)
	assert_int(_report["projectile_overflow"]).is_equal(_seed_42[0].overflow)


## What _play reads from the World after the ticks, on a start that the test crafts (the arena's own
## values are 0 or constant today): one row fewer at tick 0, and the first row dies in tick 1, which
## moves the rows behind it, so the compaction counts them. Inequalities only: how many more units
## die later is the combat's to decide.
func test_the_run_reads_units_rows_stats_and_overflow_from_the_world() -> void:
	var run: Run = _play(SEED, _craft_a_death)
	assert_int(run.units).is_equal(_seed_42[0].units - 1)
	assert_int(run.start_pos.size()).is_equal(2 * run.units)
	assert_int(run.alive_end).is_less(run.units)
	assert_int(run.final_pos.size()).is_equal(2 * run.alive_end)
	assert_int(run.stats_max[World.Stat.ROWS_COMPACTED]).is_greater(0)
	assert_int(run.overflow).is_greater_equal(CRAFTED_OVERFLOW)


## One tick's reads of the World, with no sim step: a stat is raised to its maximum and the peak
## counts the slots in use, and neither falls on a quieter tick.
func test_a_tick_sample_keeps_the_stats_maxima_and_the_projectile_peak() -> void:
	var world: World = World.new()
	world.max_projectiles = 4
	world.prepare()
	var run: Run = Run.new()
	run.stats_max.resize(World.Stat.size())
	world.stats[World.Stat.FLOW_CELLS] = 7
	world.stats[World.Stat.PROJ_STEPS] = 3
	world.proj_id[0] = 5
	world.proj_id[2] = 6
	_sample(run, world)
	assert_int(run.stats_max[World.Stat.FLOW_CELLS]).is_equal(7)
	assert_int(run.stats_max[World.Stat.PROJ_STEPS]).is_equal(3)
	assert_int(run.stats_max[World.Stat.SEP_PAIRS]).is_equal(0)
	assert_int(run.proj_peak).is_equal(2)
	world.stats[World.Stat.FLOW_CELLS] = 2
	world.proj_id[0] = 0
	_sample(run, world)
	assert_int(run.stats_max[World.Stat.FLOW_CELLS]).is_equal(7)
	assert_int(run.proj_peak).is_equal(2)


## What _make_report takes from the runs it is given, on three runs made by hand that differ in
## every value (the arena's own units, alive_end, proj_peak and overflow are 150, 150, 0 and 0, and
## its stats maxima are zeros, so a fact read from the wrong place would agree with the right one).
## The facts, the hash and the World.stats maxima are the first run's; the statistics and the phases
## are the best over all three, and so come from the second and the third here. Nothing is read
## from the runs of the suite: its own timings are far from the 40 ms and 0.5 ms asserted below.
func test_the_report_takes_each_value_from_the_runs_it_is_given() -> void:
	var runs: Array[Run] = [
		_hand_run(149, 148, 2, 3, 0x1234, 100.0, 900_000, 9001),
		_hand_run(141, 140, 6, 7, 0x5678, 40.0, 450_000, 4004),
		_hand_run(133, 132, 8, 9, 0x9ABC, 70.0, 720_000, 7007),
	]
	var report: Dictionary = _make_report(runs)
	assert_int(report["units"]).is_equal(149)
	assert_int(report["alive_end"]).is_equal(148)
	assert_int(report["proj_peak"]).is_equal(2)
	assert_int(report["projectile_overflow"]).is_equal(3)
	assert_str(report["hash"]).is_equal(World.hash_hex(0x1234))
	assert_int(report["ticks"]).is_equal(TICKS)
	assert_int(report["runs"]).is_equal(RUNS)
	var maxima: Dictionary = report["stats_max"]
	assert_int(maxima[PerfReport.stat_names()[World.Stat.PROJ_STEPS]]).is_equal(9001)
	assert_float(report["mean_ms"]).is_equal_approx(40.0, ROUNDING_MS)
	var phases: Dictionary = report["phases"]
	assert_float(phases[SimProbe.PHASE_NAMES[0]]).is_equal_approx(0.5, ROUNDING_MS)


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


## Each phase of the report is the smallest mean that one of the three runs had, like the
## statistics, so a phase left out of a run's sums or a report that read one run shows here.
func test_the_phase_split_is_the_best_of_the_three_runs() -> void:
	var wrong: Array[String] = []
	var phases: Dictionary = _report["phases"]
	for phase: int in SimProbe.Phase.COUNT:
		var smallest: float = INF
		for run: Run in _seed_42:
			smallest = minf(smallest, PerfReport.phase_means_ms(run.phase_usec, TICKS)[phase])
		var name: String = SimProbe.PHASE_NAMES[phase]
		if absf(float(phases[name]) - smallest) > 0.0006:
			wrong.append(name)
	assert_array(wrong).is_empty()


## The estimates are computed from the ratios in perf_gate.tres (ADR 0012 section 4), not written by
## hand: the mean ratio and the p95 ratio differ, so using one for the other changes an estimate.
## The ratios are read from the file again, past the resource cache, and not from the harness's own
## `_gate`: a ratio that the harness overrides after loading (or a gate built in code) would
## otherwise agree with itself and print an estimate that the file does not give. The tolerance is
## the rounding of the report (a thousandth of a ms on the time, then on the product), so a ratio
## that is 0.1 off shows as soon as the time is above a few hundredths of a ms.
func test_the_phone_estimates_are_the_best_mean_and_p95_times_the_gate_ratios() -> void:
	var file_gate: PerfGateDef = (
		ResourceLoader.load(GATE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PerfGateDef
	)
	assert_object(file_gate).is_not_null()
	var mean_ms: float = _report["mean_ms"]
	var p95_ms: float = _report["p95_ms"]
	assert_float(_report["est_phone_mean_ms"]).is_equal_approx(
		mean_ms * file_gate.ci_ratio_mean, ROUNDING_MS * (1.0 + file_gate.ci_ratio_mean)
	)
	assert_float(_report["est_phone_p95_ms"]).is_equal_approx(
		p95_ms * file_gate.ci_ratio_p95, ROUNDING_MS * (1.0 + file_gate.ci_ratio_p95)
	)


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
	assert_int(_ref_usec.size()).is_equal(2 * REF_SAMPLES)
	assert_float(_report["ref_ms"]).is_greater(0.0)
	assert_float(_report["ref_ms"]).is_equal_approx(PerfReport.smallest(_ref_usec) / 1000.0, 0.0006)
	assert_float(_report["p50_ms"]).is_less_equal(_report["p95_ms"])
	assert_float(_report["p95_ms"]).is_less_equal(_report["p99_ms"])
	assert_float(_report["p99_ms"]).is_less_equal(_report["max_ms"])
	assert_float(_report["max_ms"]).is_less_equal(_report["worst15_ms"])


func test_sim_json_holds_the_numbers_of_the_line() -> void:
	var path: String = ProjectSettings.globalize_path(REPORT_PATH)
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	_keep_reports_out_of_the_project()
	assert_bool(FileAccess.file_exists(REPORT_IGNORE_PATH)).is_true()
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
## `adjust` (optional) is called with the World right after MatchLoop.create and before anything is
## read from it, to give a test a start of its own.
func _play(match_seed: int, adjust: Callable = Callable()) -> Run:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(
		scenario, DetRandom.create(match_seed, DetRandom.STREAM_SIM)
	)
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, match_seed, world)
	if adjust.is_valid():
		adjust.call(world)
	var probe: TimingProbe = TimingProbe.new()
	var queued: Array[Command] = []
	var run: Run = Run.new()
	run.units = world.unit_count()
	run.tick_ms.resize(TICKS)
	run.phase_usec.resize(SimProbe.Phase.COUNT)
	run.stats_max.resize(World.Stat.size())
	run.start_pos = _positions(world)
	for tick: int in TICKS:
		var started: int = Time.get_ticks_usec()
		loop.step(world, queued, probe)
		run.tick_ms[tick] = (Time.get_ticks_usec() - started) / 1000.0
		PerfReport.add_phases(run.phase_usec, probe.phase_usec)
		_sample(run, world)
	run.alive_end = world.unit_count()
	run.overflow = world.projectile_overflow
	run.final_pos = _positions(world)
	run.checkpoint_ticks = loop.replay.checkpoint_ticks
	run.checkpoint_hashes = loop.replay.checkpoint_hashes
	run.final_hash = world.state_hash()
	return run


## What a tick that just ran leaves in the World: the World.stats maxima and the projectile peak.
func _sample(run: Run, world: World) -> void:
	PerfReport.raise_maxima(run.stats_max, world.stats)
	run.proj_peak = maxi(run.proj_peak, PerfReport.live_projectiles(world))


## The crafted start of the case above: the last row is dead and removed before tick 0, the first
## row is dead (it leaves in tick 1) and the overflow counter starts at CRAFTED_OVERFLOW.
func _craft_a_death(world: World) -> void:
	world.hp[world.unit_count() - 1] = 0
	world.remove_dead()
	world.hp[0] = 0
	world.projectile_overflow = CRAFTED_OVERFLOW


## Times REF_SAMPLES calls of the reference loop (after one warm-up call) into _ref_usec. ref_ms is
## the smallest sample of the readings before and after the runs, so a slow runner shows in it
## (ADR 0011 section 4: a proven runner-speed problem may switch to a relative budget through a
## new ADR).
func _time_reference() -> void:
	var sink: int = RefLoop.run(_gate.ref_iterations)
	for _call: int in REF_SAMPLES:
		var started: int = Time.get_ticks_usec()
		sink += RefLoop.run(_gate.ref_iterations)
		_ref_usec.append(Time.get_ticks_usec() - started)
	assert_int(sink).is_greater(0)


## pos_x of every unit, then pos_y.
func _positions(world: World) -> PackedInt32Array:
	var all: PackedInt32Array = world.pos_x.duplicate()
	all.append_array(world.pos_y)
	return all


## Makes sure reports/ holds the marker that keeps it out of the import and of the exports, as
## run-tests.sh and run-sim-smoke.sh do, so a run that skipped them cannot pack sim.json.
func _keep_reports_out_of_the_project() -> void:
	var marker: String = ProjectSettings.globalize_path(REPORT_IGNORE_PATH)
	if not FileAccess.file_exists(marker):
		var file: FileAccess = FileAccess.open(marker, FileAccess.WRITE)
		assert_object(file).is_not_null()
		file.close()


## The report of `runs`: the facts (units, alive_end, proj_peak, projectile_overflow, hash) and the
## World.stats maxima are the first run's, the statistics and the phases the best of all of them.
func _make_report(runs: Array[Run]) -> Dictionary:
	var stats: Array[Dictionary] = []
	var phases: Array[PackedFloat64Array] = []
	for run: Run in runs:
		stats.append(PerfReport.run_stats(run.tick_ms))
		phases.append(PerfReport.phase_means_ms(run.phase_usec, TICKS))
	var first: Run = runs[0]
	var facts: Dictionary = {
		"units": first.units,
		"ticks": TICKS,
		"runs": RUNS,
		"ref_ms": PerfReport.smallest(_ref_usec) / 1000.0,
		"alive_end": first.alive_end,
		"proj_peak": first.proj_peak,
		"projectile_overflow": first.overflow,
		"hash": World.hash_hex(first.final_hash),
	}
	return PerfReport.finish(
		facts, PerfReport.best_of(stats), PerfReport.best_phases(phases), first.stats_max, _gate
	)


## A run that no match produced: two ticks of `tick_ms`, `phase_usec` in the first phase over all
## the TICKS ticks, and `steps_max` as the World.stats maximum of the projectile steps.
func _hand_run(
	units: int,
	alive_end: int,
	proj_peak: int,
	overflow: int,
	final_hash: int,
	tick_ms: float,
	phase_usec: int,
	steps_max: int
) -> Run:
	var run: Run = Run.new()
	run.units = units
	run.alive_end = alive_end
	run.proj_peak = proj_peak
	run.overflow = overflow
	run.final_hash = final_hash
	run.tick_ms = PackedFloat64Array([tick_ms, tick_ms])
	run.phase_usec.resize(SimProbe.Phase.COUNT)
	run.phase_usec[0] = phase_usec
	run.stats_max.resize(World.Stat.size())
	run.stats_max[World.Stat.PROJ_STEPS] = steps_max
	return run


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
