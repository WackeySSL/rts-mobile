extends GdUnitTestSuite
## The base arena's perf lines and cost bounds (plan row P93, ADR 0021 section 2, ADR 0013 section
## 15). The seed-42 run of data/scenarios/perf_bases.tres (P80: both factions, about 30 buildings,
## 150 mobile rows, both strikes) is played for 900 ticks through TickJob.run() in SYNC, the way
## test_sim_perf.gd plays the perf arena: three runs with the GDScript phases and three with the C++
## kernels attached, in the order G N G N G N, with the reference loop timed before and after. The
## suite prints `PERF bases units=...` and `PERF bases impl=native units=...`, the keys of the two
## `PERF sim` lines under their own head (tests/perf/support/perf_report.gd); the job summary of
## P96 shows them beside the others. Without the library only the GDScript line prints, and a plain
## note stands in for the native one.
##
## The lines are REPORT ONLY. No time is judged here: not the best mean, not a cap and not a ratio
## to the perf arena. The `[bases]` section of budget.cfg is P93b's, once the last Phase 3 sim row
## has merged. What the suite enforces is deterministic and read from the World, never from the
## clock: the six runs end on the same state hash at every 15 ticks (the GDScript twins against the
## kernels, ADR 0013 section 3), the World.stats maxima are the same in all six, and the three Phase
## 3 counters stay inside their bounds (tests/perf/support/perf_bounds.gd, P49a's margin on the
## measured maxima). The golden hashes are test_golden_hashes.gd's and the hash bytes
## test_base_hash_bytes.gd's.
##
## The counters follow the arena. It has no building death (every building type stands for the whole
## run), so MEMORY_CHECKS here is the MEMORY phase alone; a death in sight adds the checks of the
## in-sight drop in REMOVE (LastSeen.forget_dead, P77b), which the bound's margin is for.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const Run: GDScript = preload("res://tests/perf/support/perf_run.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_bases.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const TICKS: int = 900
const SEED: int = 42
const RUNS: int = 3
## The serial of the match's snapshots (the runner counts one for each start).
const MATCH_SERIAL: int = 1
## Timed calls of the reference loop; the smallest is ref_ms.
const REF_SAMPLES: int = 20
## What the suite prints when the library is not loaded, in place of the native line. Plain text: it
## does not start with `PERF `, so the job summary selects nothing from it.
const NATIVE_SKIPPED: String = (
	"perf: no PERF bases impl=native line, the SimKernels library is not loaded"
	+ " (the web, or a build without it)"
)

var _gate: PerfGateDef
var _gd: Array[Run] = []
var _native: Array[Run] = []
var _native_loaded: bool = false
var _ref_usec: PackedInt64Array = PackedInt64Array()
var _gd_report: Dictionary = {}
var _native_report: Dictionary = {}


func before() -> void:
	_gate = load(GATE_PATH) as PerfGateDef
	_time_reference()
	_native_loaded = NativeKernels.create() != null
	# Each native run follows the GDScript run it pairs with, so that a slow stretch of the machine
	# hits both lines alike.
	for _run: int in RUNS:
		_gd.append(_play(false))
		if _native_loaded:
			_native.append(_play(true))
	_time_reference()
	_gd_report = _make_report(_gd, false)
	if _native_loaded:
		_native_report = _make_report(_native, true)


## The library is loaded wherever the tests run (verify.sh builds it), so the native runs exist and
## ran with the kernels attached, the GDScript ones with none; a suite that left the native runs
## out would otherwise pass everything below on an empty list. All six ended on the same state hash
## at every checkpoint, ticks 15 to 900: the base arena is bit-identical across the runs and
## across the two implementations (the arena's own pins are test_golden_hashes.gd's).
func test_the_six_runs_end_on_the_same_hash_at_every_checkpoint() -> void:
	assert_bool(_native_loaded).is_equal(ClassDB.class_exists(&"SimKernels"))
	assert_int(_gd.size()).is_equal(RUNS)
	assert_int(_native.size()).is_equal(RUNS if _native_loaded else 0)
	var twin: Run = _gd[0]
	assert_int(twin.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	for run: Run in _gd:
		assert_int(run.native_mask).is_equal(0)
	for run: Run in _native:
		assert_int(run.native_mask).is_equal(NativeKernels.create().phases())
	for run: Run in _gd + _native:
		assert_array(run.checkpoint_ticks).is_equal(twin.checkpoint_ticks)
		assert_array(run.checkpoint_hashes).is_equal(twin.checkpoint_hashes)
		assert_int(run.final_hash).is_equal(twin.final_hash)
		assert_int(run.units).is_equal(twin.units)
		assert_int(run.alive_end).is_equal(twin.alive_end)
		assert_int(run.proj_peak).is_equal(twin.proj_peak)
		assert_int(run.overflow).is_equal(twin.overflow)


## The stats maxima, which the bounds judge, are the same in all six runs, all ten counters of
## World.Stat: the three Phase 3 phases are GDScript in both, and the kernels count the others like
## their twins. Each of the three bounded counters moved (a counter that reads 0 is not live), and
## the base arena stays inside the bounds of PerfBounds.base_cost_bounds().
func test_the_base_arena_stays_inside_its_phase_3_cost_bounds_in_all_six_runs() -> void:
	var twin: Run = _gd[0]
	var found: Array[String] = []
	for run: Run in _gd + _native:
		assert_array(run.stats_max).is_equal(twin.stats_max)
		for line: String in run.base_bound_lines():
			if not found.has(line):
				found.append(line)
	assert_array(found).is_empty()
	for stat: int in PerfBounds.base_cost_bounds():
		assert_int(twin.stats_max[stat]).override_failure_message(str(stat)).is_greater(0)


## The `PERF bases` line has the keys of the `PERF sim` line in the same order under its own head,
## and the native line puts `impl=native` right after the head, as `PERF sim impl=native` does. The
## facts come from the base arena: more rows than the 150 mobile ones (the buildings stand beside
## them) at tick 0, 900 ticks, three runs, and the hash of the final state, the last of the golden
## hashes of the gate file. None of the lines is a `PERF sim` line (P51 selects those), and neither
## holds a newline. Without the library only the GDScript line is made and the plain note prints.
func test_the_perf_bases_lines_have_the_keys_of_perf_sim_under_their_own_head() -> void:
	var text: String = PerfReport.line(_gd_report, PerfReport.BASES_HEAD)
	var native_text: String = _native_text()
	print(text)
	print(native_text)
	assert_str(text).starts_with("PERF bases units=")
	assert_bool("\n" in text).is_false()
	var expected: Array[String] = ["PERF", "bases"]
	expected.append_array(PerfReport.LINE_KEYS)
	expected.append_array(["stats_max", "phases", "hash"])
	assert_array(_keys_of(text)).is_equal(expected)
	assert_int(_gd_report["units"]).is_greater(150)
	assert_int(_gd_report["units"]).is_equal(_gd[0].units)
	assert_int(_gd_report["ticks"]).is_equal(TICKS)
	assert_int(_gd_report["runs"]).is_equal(RUNS)
	assert_str(text.get_slice("hash=", 1)).is_equal(World.hash_hex(_gd[0].final_hash))
	assert_str(text.get_slice("hash=", 1)).is_equal(_gate.bases_golden_hex[-1])
	assert_bool(text.begins_with(PerfReport.HEAD)).is_false()
	if not _native_loaded:
		assert_str(native_text).is_equal(NATIVE_SKIPPED)
		return
	assert_str(native_text).starts_with("PERF bases impl=native units=")
	assert_bool("\n" in native_text).is_false()
	expected.insert(2, PerfReport.IMPL_KEY)
	assert_array(_keys_of(native_text)).is_equal(expected)
	assert_str(native_text.get_slice("hash=", 1)).is_equal(_gate.bases_golden_hex[-1])
	assert_str(_native_report[PerfReport.IMPL_KEY]).is_equal(PerfReport.IMPL_NATIVE)
	assert_bool(_gd_report.has(PerfReport.IMPL_KEY)).is_false()
	# The facts are the arena's, so both lines share them, and the reference loop is one reading.
	for key: String in ["units", "ticks", "runs", "ref_ms", "alive_end", "hash"]:
		assert_that(_native_report[key]).override_failure_message(key).is_equal(_gd_report[key])
	assert_bool(native_text.begins_with(PerfReport.HEAD)).is_false()


## The line's stats_max and phases are the arena's: every World.Stat name once, the phase names of
## SimProbe in order, and the Phase 3 counters in stats_max as the bounds read them.
func test_the_line_holds_every_stat_and_every_phase_of_the_tick() -> void:
	var stats: Dictionary = _gd_report["stats_max"]
	assert_array(stats.keys()).is_equal(Array(PerfReport.stat_names()))
	var phases: Dictionary = _gd_report["phases"]
	assert_array(phases.keys()).is_equal(Array(SimProbe.PHASE_NAMES))
	for stat: int in PerfBounds.base_cost_bounds():
		assert_int(stats[PerfReport.stat_names()[stat]]).is_equal(_gd[0].stats_max[stat])


## The native line when it is made, else the plain note.
func _native_text() -> String:
	if _native_report.is_empty():
		return NATIVE_SKIPPED
	return PerfReport.line(_native_report, PerfReport.BASES_HEAD)


## The key of every space-separated field of a PERF line: `PERF`, `bases`, then each name before
## its `=`.
func _keys_of(text: String) -> Array[String]:
	var keys: Array[String] = []
	for field: String in text.split(" "):
		keys.append(field.get_slice("=", 0))
	return keys


## One match of the base arena through TickJob.run(), the tick time being the snapshot's job_usec
## (what the gate judges). `native` attaches the kernels as MatchRunner does when sim_impl resolves
## to NATIVE. The stats maxima, the projectile peak and the checkpoints are read after the clock
## stops; nothing here judges a time.
func _play(native: bool) -> Run:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	if native:
		var kernels: Object = NativeKernels.create()
		world.kernels = kernels
		world.native_phases = kernels.phases()
	var step_probe: StepProbe = StepProbe.new()
	step_probe.target = TimingProbe.new()
	var job: TickJob = TickJob.new()
	var published: MatchSnapshot = MatchSnapshot.new()
	published.match_serial = MATCH_SERIAL
	published.capture(world, null)
	var run: Run = Run.new()
	run.units = world.unit_count()
	run.tick_ms.resize(TICKS)
	run.phase_usec.resize(SimProbe.Phase.COUNT)
	run.stats_max.resize(World.Stat.size())
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
		PerfReport.add_phases(run.phase_usec, next.phase_usec)
		PerfReport.raise_maxima(run.stats_max, world.stats)
		run.proj_peak = maxi(run.proj_peak, PerfReport.live_projectiles(world))
		published = next
	run.alive_end = world.unit_count()
	run.overflow = world.projectile_overflow
	run.native_mask = world.native_phases
	run.checkpoint_ticks = loop.replay.checkpoint_ticks
	run.checkpoint_hashes = loop.replay.checkpoint_hashes
	run.final_hash = world.state_hash()
	return run


## Times REF_SAMPLES calls of the reference loop (after one warm-up call) into _ref_usec. ref_ms is
## the smallest sample of the readings before and after the runs, one value that both lines share.
func _time_reference() -> void:
	var sink: int = RefLoop.run(_gate.ref_iterations)
	for _call: int in REF_SAMPLES:
		var started: int = Time.get_ticks_usec()
		sink += RefLoop.run(_gate.ref_iterations)
		_ref_usec.append(Time.get_ticks_usec() - started)
	assert_int(sink).is_greater(0)


## The report of `runs`: the facts are the first run's, the statistics and the phases the best of
## all of them (like test_sim_perf.gd). `native` makes the report of the runs with the kernels
## attached (finish() reads the native ratios, which ADR 0021 section 5 keeps).
func _make_report(runs: Array[Run], native: bool) -> Dictionary:
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
