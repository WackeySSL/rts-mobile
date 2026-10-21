extends GdUnitTestSuite
## The perf harness on the arena (plan P38p and P49a, ADR 0011 section 4, ADR 0012 section 4, ADR
## 0013 sections 3 and 15). The perf arena is run for 900 ticks through TickJob.run() in SYNC, the
## way MatchRunner runs a tick: a new MatchSnapshot for each tick, the published one as `previous`,
## and a StepProbe whose target is a TimingProbe. A tick takes what the gate's job_usec takes, the
## step, the capture and the copies of the first write, and Sim.step (step_usec) and the phases
## are read from the same job. Seed 42 runs three times and seed 43 once; the suite prints the PERF
## line, the STEP sub-line and the two WATCH lines, writes reports/perf/sim.json and checks that
## the three seed-42 runs agree at every checkpoint and that seed 43 does not.
##
## The wall clock is report only: apart from the catastrophic cap on the best mean (20 ms) nothing
## about the clock is asserted, because the CI wall-clock budget is P49b's. What the suite does
## enforce is deterministic (plan P49a): the cost bounds from World.stats, the 150 units at tick 0,
## no projectile overflow, the pinned alive_end and projectile peak, and the growth of static
## memory (tests/perf/support/perf_bounds.gd holds the bounds and test_perf_bounds.gd pins them);
## the golden hashes are checked by test_golden_hashes.gd.
##
## The second PERF line (plan P38pn, ADR 0013 section 15): when the SimKernels library is loaded,
## seed 42 runs three more times, each after the GDScript run it pairs with, with the kernels
## attached as MatchRunner attaches them (NativeKernels.create() and
## world.native_phases = kernels.phases()), and the suite prints
## `PERF sim impl=native ...`, whose phone estimates read ci_ratio_native_mean and
## ci_ratio_native_p95. Without the library (the web, a build without native/bin) it prints one
## plain note, from the native-line case, and no such line. The native line is the timing that the
## phone runs (the gate's job is native), the GDScript line is report only; the catastrophic cap
## holds for both. Both implementations must end every checkpoint, the last one included, on the
## same state hash. The GDScript line keeps its format exactly (P51 parses both lines).
## The order of the runs is G N G N G N (G the GDScript run, N the native one) and then seed 43, and
## ref_ms is the smallest reading of the reference loop before and after all seven runs, one value
## that both lines share. The RUN lines print grouped by implementation (the GDScript runs, seed 43,
## then the native runs), not in the order in which the runs happened.
##
## The two watch lines have no bound (ADR 0013 section 15's named watch items): the COMMANDS phase
## on the arena's largest order tick plus the same phase for one crafted order of all 150 units
## (Formation.assign), and the p95 of the job minus Sim.step on the checkpoint ticks and on the
## others (the capture and the state hash, which a port cannot speed up). They read the native
## runs, or the GDScript ones when the library is not loaded.
##
## The enforced numbers are the minimum over the three seed-42 runs of each statistic (ADR 0011
## section 4, a fixed method and not a retry). RUN lines print every run, apart from the `PERF`
## lines that CI copies.
##
## The numbers that the line takes from the World (units, alive_end, the World.stats maxima, the
## projectile peak and overflow) follow the fight and the projectiles, which later PRs change, so
## three cases pin the code that reads them without the sim's help: _play on a start that the test
## crafts, _sample on a hand-built world, and _make_report on three runs made by hand. The first two
## assert inequalities only, so the combat and the projectiles cannot break them.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
## The run-outcome pins (plan P49a, ADR 0011 section 4): what the seed-42 arena ends on at
## 4eb974e71b2107be, 71 of its 150 units alive at tick 900 and at most 28 projectile slots in use at
## once. A run must end within PerfBounds.MARGIN_PERCENT (25 %, rounded up) of each, so alive_end in
## 53..89 and the peak in 21..35: a balance change that empties the fight or stops the shooting
## would otherwise shrink the measured load unseen. The first sim PR that moves the arena run (P46b)
## re-pins these two numbers, and the golden hashes of data/dev/perf_gate.tres, in one place each,
## only if the new values fall outside (plan exception 3), with a note that says why they moved.
const ALIVE_END_PIN: int = 71
const PROJ_PEAK_PIN: int = 28
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const REPORT_PATH: String = "res://reports/perf/sim.json"
## reports/ is kept out of the import and the exports by this marker (run-tests.sh writes it too).
const REPORT_IGNORE_PATH: String = "res://reports/.gdignore"
const TICKS: int = 900
const SEED: int = 42
const OTHER_SEED: int = 43
const RUNS: int = 3
## The serial of the match's snapshots (the runner counts one for each start).
const MATCH_SERIAL: int = 1
## The crafted order of the watch line: every unit of the arena, ordered by player 1 (the units of
## player 2 are given to player 1 first), to the middle of the map, where the two armies meet. No
## unit starts on its own slot there, so every row ends the tick with the order (a unit that starts
## on its slot is idle at once, which the count of the case would read as a refused row).
const CRAFTED_TARGET: Vector2i = Vector2i(32, 32)
## Timed calls of the reference loop; the smallest is ref_ms.
const REF_SAMPLES: int = 20
## Half of the thousandth of a ms that the report rounds each time to.
const ROUNDING_MS: float = 0.0005
## The projectile_overflow that the crafted start gives the World (a counter since match start).
const CRAFTED_OVERFLOW: int = 3
## What the suite prints when the library is not loaded, in place of the native line. Plain text: it
## does not start with `PERF ` (P51 copies those lines) and holds nothing verify.sh rejects.
const NATIVE_SKIPPED: String = (
	"perf: no native line, the SimKernels library is not loaded"
	+ " (the web, or a build without it)"
)
## The lines that scripts/verify.sh rejects (its PATTERN), and the engine's warnings.
const REJECTED_LINES: String = "SCRIPT ERROR|^ERROR:|Parse Error|^WARNING:"

var _gate: PerfGateDef
var _seed_42: Array[Run] = []
var _seed_43: Run
## Seed 42 with the kernels attached, three runs; empty when the library is not loaded.
var _native_42: Array[Run] = []
var _native_loaded: bool = false
var _ref_usec: PackedInt64Array = PackedInt64Array()
var _report: Dictionary = {}
var _native_report: Dictionary = {}
## The crafted order of the COMMANDS watch line (_craft_a_large_order), made once.
var _crafted: Dictionary = {}


## What one match leaves: the tick times (the job, and Sim.step inside it), the per-phase sums, the
## World.stats maxima and the checkpoints. An engine base class, so it may sit inside this file
## (P56c).
class Run:
	extends RefCounted
	## TickJob.run() of each tick, in ms (the snapshot's job_usec), and Sim.step alone (step_usec).
	var tick_ms: PackedFloat64Array = PackedFloat64Array()
	var step_ms: PackedFloat64Array = PackedFloat64Array()
	## The COMMANDS phase of each tick in microseconds, and the replay's command log, which says
	## which tick ordered the most units.
	var commands_usec: PackedInt64Array = PackedInt64Array()
	var order_log: PackedInt32Array = PackedInt32Array()
	var phase_usec: PackedInt64Array = PackedInt64Array()
	var stats_max: PackedInt32Array = PackedInt32Array()
	var units: int = 0
	var alive_end: int = 0
	var proj_peak: int = 0
	var overflow: int = 0
	## The rules the World ran with that bound the cost counters.
	var flow_budget: int = 0
	var sep_scan: int = 0
	## Performance.MEMORY_STATIC after tick PerfBounds.MEMORY_FIRST_TICK and MEMORY_LAST_TICK.
	var memory_first: int = 0
	var memory_last: int = 0
	## The ticks whose snapshot has prev_pos_x other than pos_x (it slid from the previous one).
	var slid_ticks: int = 0
	## The phases that ran in C++ (World.native_phases after the last tick): 0 for a GDScript run.
	var native_mask: int = 0
	## pos_x then pos_y of every unit, before the first tick and after the last.
	var start_pos: PackedInt32Array = PackedInt32Array()
	var final_pos: PackedInt32Array = PackedInt32Array()
	var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
	var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
	var final_hash: int = 0


func before() -> void:
	_gate = load(GATE_PATH) as PerfGateDef
	_time_reference()
	_native_loaded = NativeKernels.create() != null
	# Each native run follows the GDScript run it pairs with, so that a slow stretch of the machine
	# hits both lines alike (GDScript phases that no kernel replaces cost the same in both).
	for _run: int in RUNS:
		_seed_42.append(_play(SEED))
		if _native_loaded:
			_native_42.append(_play(SEED, _attach_native))
	_seed_43 = _play(OTHER_SEED)
	_time_reference()
	_report = _make_report(_seed_42)
	if _native_loaded:
		_native_report = _make_report(_native_42, true)
	_crafted = _craft_a_large_order(_native_loaded)
	for index: int in _seed_42.size():
		print(_run_line(SEED, index + 1, _seed_42[index]))
	print(_run_line(OTHER_SEED, 1, _seed_43))
	for index: int in _native_42.size():
		print(_run_line(SEED, index + 1, _native_42[index], true))
	for printed: Dictionary in _printed():
		var native: bool = printed["report"].has(PerfReport.IMPL_KEY)
		print(PerfReport.sub_line(PerfReport.STEP_HEAD, _step_values(printed["runs"]), native))
	var watched: Array[Run] = _native_42 if _native_loaded else _seed_42
	print(
		PerfReport.sub_line(
			PerfReport.COMMANDS_HEAD, _commands_values(watched, _crafted), _native_loaded
		)
	)
	print(PerfReport.sub_line(PerfReport.OVERHEAD_HEAD, _overhead_values(watched), _native_loaded))


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
	assert_int(_printed().size()).is_equal(2 if _native_loaded else 1)
	for printed: Dictionary in _printed():
		var report: Dictionary = printed["report"]
		var runs: Array[Run] = printed["runs"]
		for key: String in PerfReport.STAT_KEYS:
			var smallest: float = INF
			for run: Run in runs:
				smallest = minf(smallest, PerfReport.run_stats(run.tick_ms)[key])
			if absf(float(report[key]) - smallest) > 0.0006:
				wrong.append("%s %s" % [report.get(PerfReport.IMPL_KEY, "gdscript"), key])
		assert_int(report["runs"]).is_equal(runs.size())
		assert_int(report["ticks"]).is_equal(TICKS)
	assert_array(wrong).is_empty()


func test_the_best_mean_stays_under_the_catastrophic_cap() -> void:
	for printed: Dictionary in _printed():
		var report: Dictionary = printed["report"]
		assert_float(report["mean_ms"]).is_greater(0.0)
		assert_bool(PerfReport.over_cap(report, PerfReport.CATASTROPHIC_MEAN_MS)).is_false()


## What a run took from TickJob.run(): every tick has a job time, a Sim.step time inside it and a
## COMMANDS time, so the quantity is the gate's job_usec and not the step alone; the job ran on a
## new snapshot with the published one as `previous` (the snapshots slid, which they cannot with a
## `previous` of null); and Sim.step and the phases come from the StepProbe and its TimingProbe.
## Which units live and which projectiles fly is bounded by the case after.
func test_each_run_timed_every_tick_of_the_arena() -> void:
	for run: Run in _seed_42 + [_seed_43] + _native_42:
		assert_int(run.tick_ms.size()).is_equal(TICKS)
		assert_int(run.step_ms.size()).is_equal(TICKS)
		assert_int(run.commands_usec.size()).is_equal(TICKS)
		assert_int(run.tick_ms.count(0.0)).is_less(TICKS)
		assert_int(run.step_ms.count(0.0)).is_less(TICKS)
		assert_int(run.units).is_greater(0)
		var inside: int = 0
		var job_sum: float = 0.0
		var step_sum: float = 0.0
		for tick: int in TICKS:
			inside += 1 if run.tick_ms[tick] >= run.step_ms[tick] else 0
			job_sum += run.tick_ms[tick]
			step_sum += run.step_ms[tick]
		# The job holds the step on every tick, and the capture and the hash on top of it.
		assert_int(inside).is_equal(TICKS)
		assert_float(job_sum).is_greater(step_sum)
		assert_int(run.slid_ticks).is_greater(TICKS / 3)
	assert_int(_report["units"]).is_equal(_seed_42[0].units)
	assert_int(_report["alive_end"]).is_equal(_seed_42[0].alive_end)
	assert_int(_report["proj_peak"]).is_equal(_seed_42[0].proj_peak)
	assert_int(_report["projectile_overflow"]).is_equal(_seed_42[0].overflow)


## The deterministic bounds of plan P49a (ADR 0011 section 4) hold for every seed-42 run, the
## GDScript twins and the C++ kernels alike (they measure the same numbers): each cost counter of
## World.stats under its bound, 150 units at tick 0, no projectile overflow, alive_end and the
## projectile peak within the margin of their pins, and the static memory (debug builds). A bounded
## counter that reads 0 fails too, so a sample that read nothing cannot pass. PerfBounds is pinned
## by test_perf_bounds.gd; the wall clock is not bounded here (P49b).
func test_the_arena_stays_inside_its_cost_load_and_memory_bounds() -> void:
	var found: Array[String] = []
	for printed: Dictionary in _printed():
		var label: String = printed["report"].get(PerfReport.IMPL_KEY, "gdscript")
		var runs: Array[Run] = printed["runs"]
		for run: Run in runs:
			var bounds: Dictionary[int, int] = PerfBounds.cost_bounds(
				run.flow_budget, run.sep_scan, run.units
			)
			var lines: Array[String] = PerfBounds.cost_violations(run.stats_max, bounds)
			for stat: int in bounds:
				if run.stats_max[stat] <= 0:
					lines.append("%s reads 0" % PerfReport.stat_names()[stat])
			lines.append_array(
				PerfBounds.load_violations(
					run.units,
					run.overflow,
					run.alive_end,
					run.proj_peak,
					ALIVE_END_PIN,
					PROJ_PEAK_PIN
				)
			)
			lines.append_array(
				PerfBounds.memory_violations(run.memory_first, run.memory_last, OS.is_debug_build())
			)
			for line: String in lines:
				var entry: String = "%s: %s" % [label, line]
				if not found.has(entry):
					found.append(entry)
	assert_array(found).is_empty()


## The values of the STEP line and the two WATCH lines come from the runs they are given, and the
## arena gives them what the plan says. Three runs made by hand have each value best in another
## run (Sim.step and the COMMANDS time in the second, the checkpoint overhead in the third, the
## overhead of the other ticks in the first), with a COMMANDS time that names its tick, so a value
## read from the wrong run or the wrong tick shows. The arena: both players order their 75 movers
## in tick 0, so tick 0 is the largest order tick with 150 units; the crafted order puts all 150
## into one command, and every row takes it and nothing is dropped; there are 60 checkpoint
## ticks and 840 others, and every value of the lines is above 0.
func test_the_step_and_watch_lines_read_the_runs_and_the_arena_orders() -> void:
	var runs: Array[Run] = [
		_timed_run(3.0, 9.0, 1.5, 900),
		_timed_run(1.0, 6.0, 3.0, 700),
		_timed_run(2.0, 4.0, 2.0, 800),
	]
	var step: Dictionary = _step_values(runs)
	assert_array(step.keys()).is_equal(PerfReport.STEP_KEYS)
	for key: String in PerfReport.STEP_KEYS:
		assert_float(step[key]).override_failure_message(key).is_equal_approx(1.0, 0.0001)
	var crafted: Dictionary = {"units": 150, "usec": 12345}
	var commands: Dictionary = _commands_values(runs, crafted)
	assert_array(commands.keys()).is_equal(
		["order_tick", "order_units", "commands_ms", "crafted_units", "crafted_commands_ms"]
	)
	assert_int(commands["order_tick"]).is_equal(3)
	assert_int(commands["order_units"]).is_equal(45)
	assert_float(commands["commands_ms"]).is_equal_approx(7.003, 0.0001)
	assert_int(commands["crafted_units"]).is_equal(150)
	assert_float(commands["crafted_commands_ms"]).is_equal_approx(12.345, 0.0001)
	var overhead: Dictionary = _overhead_values(runs)
	assert_array(overhead.keys()).is_equal(
		["checkpoint_ticks", "p95_checkpoint_ms", "other_ticks", "p95_other_ms"]
	)
	assert_int(overhead["checkpoint_ticks"]).is_equal(2)
	assert_float(overhead["p95_checkpoint_ms"]).is_equal_approx(4.0, 0.0001)
	assert_int(overhead["other_ticks"]).is_equal(28)
	assert_float(overhead["p95_other_ms"]).is_equal_approx(1.5, 0.0001)
	# The arena itself.
	var order: Vector2i = PerfReport.largest_order_tick(_seed_42[0].order_log)
	assert_array([order.x, order.y]).is_equal([0, 2 * 75])
	assert_array([_crafted["units"], _crafted["applied"], _crafted["dropped"]]).is_equal(
		[150, 150, 0]
	)
	assert_int(_crafted["usec"]).is_greater(0)
	for printed: Dictionary in _printed():
		var watched: Array[Run] = printed["runs"]
		var arena: Dictionary = _overhead_values(watched)
		assert_int(arena["checkpoint_ticks"]).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
		assert_int(arena["other_ticks"]).is_equal(TICKS - TICKS / Replay.CHECKPOINT_PERIOD)
		assert_float(arena["p95_checkpoint_ms"]).is_greater(0.0)
		assert_float(arena["p95_other_ms"]).is_greater(0.0)
		assert_float(_commands_values(watched, _crafted)["commands_ms"]).is_greater(0.0)
		var arena_step: Dictionary = _step_values(watched)
		assert_float(arena_step["mean_ms"]).is_greater(0.0)
		assert_float(arena_step["p50_ms"]).is_less_equal(arena_step["p95_ms"])
		assert_float(arena_step["p95_ms"]).is_less_equal(arena_step["max_ms"])


## What _play reads from the World after the ticks, on a start that the test crafts (what the arena
## itself leaves in these values is the combat's and the projectiles' to decide, and moves with
## them): one row fewer at tick 0, and the first row dies in tick 1, which moves the rows behind it,
## so the compaction counts them. Inequalities only: how many more units die later is the combat's
## to decide.
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
## every value (on the arena the facts agree with each other or sit at 0 for as long as the fight
## and the projectiles leave them there, so a fact read from the wrong place could agree with the
## right one).
## The facts, the hash and the World.stats maxima are the first run's; the statistics and the phases
## are the best over all three: the second run holds the smallest tick mean (40 ms) and the third
## the smallest first phase (0.4 ms), so a report that skips the last run, or the second, shows.
## Nothing is read from the runs of the suite: its own timings are far from the values asserted.
func test_the_report_takes_each_value_from_the_runs_it_is_given() -> void:
	var runs: Array[Run] = [
		_hand_run(149, 148, 2, 3, 0x1234, 100.0, 900_000, 9001),
		_hand_run(141, 140, 6, 7, 0x5678, 40.0, 450_000, 4004),
		_hand_run(133, 132, 8, 9, 0x9ABC, 70.0, 360_000, 7007),
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
	assert_float(phases[SimProbe.PHASE_NAMES[0]]).is_equal_approx(0.4, ROUNDING_MS)


## The phases are timed inside the step, so their means cannot add up to more than the tick mean
## (up to the rounding of the report), and a tick that does work has a phase that reads above 0.
func test_the_phase_split_is_part_of_the_tick() -> void:
	for printed: Dictionary in _printed():
		var report: Dictionary = printed["report"]
		var phases: Dictionary = report["phases"]
		assert_array(phases.keys()).is_equal(SimProbe.PHASE_NAMES)
		var sum: float = 0.0
		for phase_ms: float in phases.values():
			assert_float(phase_ms).is_greater_equal(0.0)
			sum += phase_ms
		assert_float(sum).is_greater(0.0)
		assert_float(sum).is_less_equal(float(report["mean_ms"]) + 0.01)


## Each phase of the report is the smallest mean that one of the three runs had, like the
## statistics, so a phase left out of a run's sums or a report that read one run shows here.
func test_the_phase_split_is_the_best_of_the_three_runs() -> void:
	var wrong: Array[String] = []
	for printed: Dictionary in _printed():
		var report: Dictionary = printed["report"]
		var runs: Array[Run] = printed["runs"]
		var phases: Dictionary = report["phases"]
		for phase: int in SimProbe.Phase.COUNT:
			var smallest: float = INF
			for run: Run in runs:
				smallest = minf(smallest, PerfReport.phase_means_ms(run.phase_usec, TICKS)[phase])
			var name: String = SimProbe.PHASE_NAMES[phase]
			if absf(float(phases[name]) - smallest) > 0.0006:
				wrong.append("%s %s" % [report.get(PerfReport.IMPL_KEY, "gdscript"), name])
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
	# The format P38p fixed: no impl key, which only the native line carries.
	assert_str(text).not_contains(PerfReport.IMPL_KEY + "=")
	var expected: Array[String] = ["PERF", "sim"]
	expected.append_array(PerfReport.LINE_KEYS)
	expected.append_array(["stats_max", "phases", "hash"])
	assert_array(_keys_of(text)).is_equal(expected)
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


## The runs with the kernels attached end where the GDScript runs do (ADR 0013 section 3): the same
## state hash at every 15 ticks and after the last, and the same rows left. They ran with the mask
## the library reports, FLOW, SEPARATION and INTEGRATE among its phases, and the GDScript runs with
## 0, so a native run that attached nothing (or a GDScript run that did) shows here.
func test_the_native_runs_end_on_the_gdscript_hash_at_every_checkpoint() -> void:
	# The library is loaded wherever the tests run (verify.sh builds it): a suite that left the native
	# runs out, or found the ABI wrong, would otherwise pass everything below on an empty list.
	assert_bool(_native_loaded).is_equal(ClassDB.class_exists(&"SimKernels"))
	assert_int(_native_42.size()).is_equal(RUNS if _native_loaded else 0)
	for run: Run in _seed_42 + [_seed_43]:
		assert_int(run.native_mask).is_equal(0)
	var twin: Run = _seed_42[0]
	for run: Run in _native_42:
		assert_int(run.native_mask).is_equal(NativeKernels.create().phases())
		for phase: int in [
			SimProbe.Phase.FLOW, SimProbe.Phase.SEPARATION, SimProbe.Phase.INTEGRATE
		]:
			assert_int((run.native_mask >> phase) & 1).is_equal(1)
		assert_int(run.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
		assert_array(run.checkpoint_ticks).is_equal(twin.checkpoint_ticks)
		assert_array(run.checkpoint_hashes).is_equal(twin.checkpoint_hashes)
		assert_int(run.final_hash).is_equal(twin.final_hash)
		assert_int(run.alive_end).is_equal(twin.alive_end)
		assert_array(run.final_pos).is_equal(twin.final_pos)


## The second line is `PERF sim impl=native` and then the keys of the GDScript line in their order
## (P51 parses both), from the native runs: the same facts and the same final state as the first.
## Without the library this case prints the plain note instead of the line (the only place that
## prints it, so it appears once) and reads that. verify.sh builds the library first, so that path
## runs only when the library is hidden by hand.
func test_the_native_line_has_impl_native_after_perf_sim_and_the_other_keys_in_order() -> void:
	var text: String = _native_text(_native_report)
	print(text)
	if not _native_loaded:
		assert_str(text).is_equal(NATIVE_SKIPPED)
		return
	assert_str(text).starts_with("PERF sim impl=native units=")
	assert_bool("\n" in text).is_false()
	var expected: Array[String] = ["PERF", "sim", PerfReport.IMPL_KEY]
	expected.append_array(PerfReport.LINE_KEYS)
	expected.append_array(["stats_max", "phases", "hash"])
	assert_array(_keys_of(text)).is_equal(expected)
	assert_str(text.get_slice("hash=", 1)).is_equal(World.hash_hex(_native_42[0].final_hash))
	# ref_ms is the one reference reading that both lines share (the header).
	for key: String in ["units", "ticks", "runs", "ref_ms", "alive_end", "hash"]:
		assert_that(_native_report[key]).override_failure_message(key).is_equal(_report[key])
	assert_str(_native_report[PerfReport.IMPL_KEY]).is_equal(PerfReport.IMPL_NATIVE)
	assert_bool(_report.has(PerfReport.IMPL_KEY)).is_false()
	# The RUN lines say which implementation ran, like the PERF line.
	assert_str(_run_line(SEED, 2, _native_42[1], true)).starts_with(
		"RUN sim impl=native seed=42 run=2 "
	)
	assert_str(_run_line(SEED, 2, _seed_42[1])).starts_with("RUN sim seed=42 run=2 ")


## The native estimates are the native line's best mean and p95 times ci_ratio_native_mean and
## ci_ratio_native_p95, read from the file again like the GDScript line's (past the resource cache),
## so a line that used the GDScript ratios, or swapped the two, is off by far more than the
## rounding.
func test_the_native_estimates_are_the_native_times_and_the_native_ratios_of_the_file() -> void:
	if not _native_loaded:
		assert_dict(_native_report).is_empty()
		return
	var file_gate: PerfGateDef = (
		ResourceLoader.load(GATE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PerfGateDef
	)
	assert_object(file_gate).is_not_null()
	var mean_ms: float = _native_report["mean_ms"]
	var p95_ms: float = _native_report["p95_ms"]
	assert_float(_native_report["est_phone_mean_ms"]).is_equal_approx(
		mean_ms * file_gate.ci_ratio_native_mean,
		ROUNDING_MS * (1.0 + file_gate.ci_ratio_native_mean)
	)
	assert_float(_native_report["est_phone_p95_ms"]).is_equal_approx(
		p95_ms * file_gate.ci_ratio_native_p95, ROUNDING_MS * (1.0 + file_gate.ci_ratio_native_p95)
	)


## Without the library the native line is skipped with a plain note: not a `PERF ` line (P51 copies
## those) and none of the lines that scripts/verify.sh rejects or the engine warns with. With the
## library the line is printed and the note is not.
func test_a_missing_library_skips_the_native_line_with_a_plain_note() -> void:
	var note: String = _native_text({})
	assert_str(note).is_equal(NATIVE_SKIPPED)
	assert_bool(note.begins_with("PERF ")).is_false()
	assert_bool("\n" in note).is_false()
	var rejected: RegEx = RegEx.create_from_string("(?m)" + REJECTED_LINES)
	assert_object(rejected.search(note)).is_null()
	assert_bool(_native_text(_native_report) == NATIVE_SKIPPED).is_equal(not _native_loaded)


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


## Steps the arena for TICKS ticks from `match_seed` with the scenario's own orders only, each tick
## as MatchRunner runs one in SYNC: TickJob.run() with a new snapshot, the last published one as its
## `previous`, and a StepProbe whose target is the TimingProbe (a bare TimingProbe would leave
## step_usec 0 and phase_usec empty). The tick takes the snapshot's job_usec, the quantity the gate
## judges; the stats, the projectile peak and the memory are read after the clock stops.
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
	var step_probe: StepProbe = StepProbe.new()
	step_probe.target = TimingProbe.new()
	var job: TickJob = TickJob.new()
	var published: MatchSnapshot = MatchSnapshot.new()
	published.match_serial = MATCH_SERIAL
	published.capture(world, null)
	var run: Run = Run.new()
	run.units = world.unit_count()
	run.flow_budget = world.flow_cells_per_tick
	run.sep_scan = world.separation_scan
	run.tick_ms.resize(TICKS)
	run.step_ms.resize(TICKS)
	run.commands_usec.resize(TICKS)
	run.phase_usec.resize(SimProbe.Phase.COUNT)
	run.stats_max.resize(World.Stat.size())
	run.start_pos = _positions(world)
	for tick: int in TICKS:
		var next: MatchSnapshot = MatchSnapshot.new()
		next.match_serial = MATCH_SERIAL
		job.world = world
		job.loop = loop
		job.probe = step_probe
		job.snapshot = next
		job.previous = published
		job.post_usec = Time.get_ticks_usec()
		job.run()
		run.tick_ms[tick] = next.job_usec / 1000.0
		run.step_ms[tick] = next.step_usec / 1000.0
		run.commands_usec[tick] = next.phase_usec[SimProbe.Phase.COMMANDS]
		PerfReport.add_phases(run.phase_usec, next.phase_usec)
		_sample(run, world)
		if next.prev_pos_x != next.pos_x:
			run.slid_ticks += 1
		published = next
		if world.tick == PerfBounds.MEMORY_FIRST_TICK:
			run.memory_first = _static_memory()
		elif world.tick == PerfBounds.MEMORY_LAST_TICK:
			run.memory_last = _static_memory()
	run.alive_end = world.unit_count()
	run.overflow = world.projectile_overflow
	run.native_mask = world.native_phases
	run.final_pos = _positions(world)
	run.checkpoint_ticks = loop.replay.checkpoint_ticks
	run.checkpoint_hashes = loop.replay.checkpoint_hashes
	run.order_log = loop.replay.commands
	run.final_hash = world.state_hash()
	return run


## What a tick that just ran leaves in the World: the World.stats maxima and the projectile peak.
func _sample(run: Run, world: World) -> void:
	PerfReport.raise_maxima(run.stats_max, world.stats)
	run.proj_peak = maxi(run.proj_peak, PerfReport.live_projectiles(world))


## The adjust of a native run: new kernels from NativeKernels.create() (the ABI-checked library) and
## the phases they report, as MatchRunner attaches them when sim_impl resolves to NATIVE.
func _attach_native(world: World) -> void:
	var kernels: Object = NativeKernels.create()
	if kernels != null:
		world.kernels = kernels
		world.native_phases = kernels.phases()


## Performance.MEMORY_STATIC in bytes: the engine counts it in debug builds only, 0 otherwise.
func _static_memory() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))


## The Sim.step statistics of `runs` as the values of a STEP sub-line: each one the smallest over
## the runs, like the statistics of the PERF line.
func _step_values(runs: Array[Run]) -> Dictionary:
	var stats: Array[Dictionary] = []
	for run: Run in runs:
		stats.append(PerfReport.run_stats(run.step_ms))
	var best: Dictionary = PerfReport.best_of(stats)
	var values: Dictionary = {}
	for key: String in PerfReport.STEP_KEYS:
		values[key] = best[key]
	return values


## The values of the COMMANDS watch line: the tick of `runs` that ordered the most units (from the
## first run's command log, the same in every run), the units it ordered, the smallest COMMANDS time
## that any run took on that tick, and the same for the `crafted` order (_craft_a_large_order).
func _commands_values(runs: Array[Run], crafted: Dictionary) -> Dictionary:
	var order: Vector2i = PerfReport.largest_order_tick(runs[0].order_log)
	var best_usec: int = 0
	if order.x >= 0:
		best_usec = runs[0].commands_usec[order.x]
		for run: Run in runs:
			best_usec = mini(best_usec, run.commands_usec[order.x])
	return {
		"order_tick": order.x,
		"order_units": order.y,
		"commands_ms": best_usec / 1000.0,
		"crafted_units": crafted["units"],
		"crafted_commands_ms": crafted["usec"] / 1000.0,
	}


## The values of the job-minus-step watch line: how many checkpoint and other ticks a run has, and
## the p95 of the job's time outside Sim.step on each kind, the smallest over the runs.
func _overhead_values(runs: Array[Run]) -> Dictionary:
	var first: Run = runs[0]
	var best_checkpoint: float = INF
	var best_others: float = INF
	for run: Run in runs:
		var at_checkpoint: PackedFloat64Array = PerfReport.job_minus_step_ms(
			run.tick_ms, run.step_ms, true
		)
		var elsewhere: PackedFloat64Array = PerfReport.job_minus_step_ms(
			run.tick_ms, run.step_ms, false
		)
		best_checkpoint = minf(best_checkpoint, PerfReport.p95(at_checkpoint))
		best_others = minf(best_others, PerfReport.p95(elsewhere))
	return {
		"checkpoint_ticks": PerfReport.job_minus_step_ms(first.tick_ms, first.step_ms, true).size(),
		"p95_checkpoint_ms": best_checkpoint,
		"other_ticks": PerfReport.job_minus_step_ms(first.tick_ms, first.step_ms, false).size(),
		"p95_other_ms": best_others,
	}


## One order for every unit of the arena, applied in the first tick of a World that is otherwise the
## arena's start (no scenario order: Sim.step is called on its own): the units of player 2 are
## given to player 1 first, so that one attack-move command of 150 ids is valid. Times its
## COMMANDS phase (Formation.assign for 150 units) RUNS times with a fresh World and keeps the
## smallest. Returns `units` (the ids in the command), `applied` (the rows that took the order),
## `dropped` (World.dropped_commands) and `usec`.
func _craft_a_large_order(native: bool) -> Dictionary:
	var best: int = -1
	var result: Dictionary = {"units": 0, "applied": 0, "dropped": -1, "usec": 0}
	for _sample_number: int in RUNS:
		var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
		var world: World = World.from_scenario(
			scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM)
		)
		world.prepare()
		if native:
			_attach_native(world)
		var ids: PackedInt32Array = world.unit_id.duplicate()
		world.owner.fill(1)
		var command: Command = Command.attack_move(
			1,
			ids,
			CRAFTED_TARGET.x * World.MILLI_PER_TILE + World.TILE_CENTRE,
			CRAFTED_TARGET.y * World.MILLI_PER_TILE + World.TILE_CENTRE
		)
		command.tick = world.tick
		var timing: TimingProbe = TimingProbe.new()
		var queued: Array[Command] = [command]
		Sim.step(world, queued, timing)
		var usec: int = timing.phase_usec[SimProbe.Phase.COMMANDS]
		if best < 0 or usec < best:
			best = usec
		result["units"] = ids.size()
		result["applied"] = world.order.count(World.Order.ATTACK_MOVE)
		result["dropped"] = world.dropped_commands
	result["usec"] = maxi(best, 0)
	return result


## The lines that were printed, each with its report and the runs it is made from: the GDScript one
## always, the native one when the library is loaded.
func _printed() -> Array[Dictionary]:
	var printed: Array[Dictionary] = [{"report": _report, "runs": _seed_42}]
	if _native_loaded:
		printed.append({"report": _native_report, "runs": _native_42})
	return printed


## The native line of `report`, or the plain note when there is none (the library is not loaded).
func _native_text(report: Dictionary) -> String:
	return PerfReport.line(report) if not report.is_empty() else NATIVE_SKIPPED


## The key of every space-separated field of a PERF line: `PERF`, `sim`, then each name before
## its `=`.
func _keys_of(text: String) -> Array[String]:
	var keys: Array[String] = []
	for field: String in text.split(" "):
		keys.append(field.get_slice("=", 0))
	return keys


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
## `native` makes the report of the runs with the kernels attached (finish() reads the native
## ratios).
func _make_report(runs: Array[Run], native: bool = false) -> Dictionary:
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
		facts,
		PerfReport.best_of(stats),
		PerfReport.best_phases(phases),
		first.stats_max,
		_gate,
		native
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


## A run that no match produced, for the STEP and WATCH lines: 30 ticks, two of them checkpoints.
## Sim.step takes `step` ms on every tick; the job takes `checkpoint_extra` ms more on a checkpoint
## tick and `other_extra` more on the others; the COMMANDS time of tick i is `commands_base` * 10 +
## i microseconds; the command log orders 25 and 20 units in tick 3 and 40 in tick 7.
func _timed_run(
	step: float, checkpoint_extra: float, other_extra: float, commands_base: int
) -> Run:
	var run: Run = Run.new()
	for index: int in 30:
		var checkpoint: bool = (index + 1) % Replay.CHECKPOINT_PERIOD == 0
		run.step_ms.append(step)
		run.tick_ms.append(step + (checkpoint_extra if checkpoint else other_extra))
		run.commands_usec.append(commands_base * 10 + index)
	for order: Array in [[3, 25], [3, 20], [7, 40]]:
		var ids: PackedInt32Array = PackedInt32Array()
		ids.resize(order[1])
		var command: Command = Command.attack_move(1, ids, 0, 0)
		command.tick = order[0]
		command.encode(run.order_log)
	return run


## The line of one run; a native run says so right after `RUN sim`, like the PERF line.
func _run_line(match_seed: int, number: int, run: Run, native: bool = false) -> String:
	var stats: Dictionary = PerfReport.run_stats(run.tick_ms)
	var impl: String = PerfReport.IMPL_KEY + "=" + PerfReport.IMPL_NATIVE + " " if native else ""
	return (
		"RUN sim %sseed=%d run=%d mean_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f hash=%s"
		% [
			impl,
			match_seed,
			number,
			stats["mean_ms"],
			stats["p50_ms"],
			stats["p95_ms"],
			stats["max_ms"],
			World.hash_hex(run.final_hash),
		]
	)
