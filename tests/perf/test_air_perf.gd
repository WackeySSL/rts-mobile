extends GdUnitTestSuite
## The air arena's perf line and counted bounds (plan row P253, ADR 0013 section 1). The seed-42 run
## of `data/scenarios/perf_air.tres` (the perf arena's 150 mobile units, 16 of them aircraft, a
## Flight Yard and a Burst Stack for each side, on frozen defs) is played for 900 ticks through
## TickJob.run() in SYNC, the way test_base_arena_perf.gd plays the base arena: three runs with the
## GDScript phases and three with the C++ kernels attached, in the order G N G N G N, with the
## reference loop timed before and after. The suite prints `PERF air units=...` and `PERF air
## impl=native units=...`, the keys of the two `PERF sim` lines under their own head (report only:
## no budget judges them, and `ci.yml` selects them once the release engineer adds `^PERF air`). The
## aircraft rules (`Air.gd`) are GDScript in both.
##
## What is judged is deterministic and read from the World, never from the clock: the six runs end
## on the same state hash at every 15 ticks and drop no Command; the cost counters stay inside this
## arena's own bounds (`PerfBounds.air_cost_bounds`, measured on it); the rows that SEPARATION's
## walk passes for being on another layer (ADR 0036 section 4) stay inside their bound, measured by
## the tally probe on a seventh, GDScript run that ends on the same hash as the others; and the run
## is what the row asks for: 150 units, 16 aircraft that never rise in number, bombs dropped,
## aircraft shots, shots from the ground at aircraft, and aircraft still at it after tick 600. The
## golden hashes are test_golden_hashes.gd's (`air_golden_*` of the gate file).

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const Run: GDScript = preload("res://tests/perf/support/perf_run.gd")
const TallyProbe: GDScript = preload("res://tests/sim/support/separation_tally_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_air.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const TICKS: int = 900
const SEED: int = 42
const RUNS: int = 3
const MATCH_SERIAL: int = 1
const REF_SAMPLES: int = 20
## The buildings that stand beside the 150 mobile rows: a Flight Yard and a Burst Stack each.
const BUILDINGS: int = 4
## The run's pins, measured on the seed-42 run: the units alive after the last tick and the most
## projectiles in flight. `PerfBounds.load_violations` allows P49a's margin either side.
const ALIVE_END_PIN: int = 29
const PROJ_PEAK_PIN: int = 27
## The aircraft the arena starts with (8 for each side) and what the run left of them.
const AIRCRAFT: int = 16
const AIR_END_PIN: int = 6
## The tick after which the aircraft must still be bombing or in a dogfight (the last is at 706).
const BUSY_UNTIL: int = 600
const BOMBS: StringName = &"drillhead_bombs"
const AIR_GUN: StringName = &"torchjet_gun"

var _gate: PerfGateDef
var _gd: Array[Run] = []
var _native: Array[Run] = []
var _gd_facts: Array[Facts] = []
var _native_facts: Array[Facts] = []
var _native_loaded: bool = false
var _ref_usec: PackedInt64Array = PackedInt64Array()
var _gd_report: Dictionary = {}
var _native_report: Dictionary = {}
var _tally_facts: Facts


## What a run counted from the World: the aircraft at start, at most and at the end, the dropped
## Commands, the bombs, the shots of the aircraft guns, the shots from the ground at an aircraft,
## the last tick of a bomb or an aircraft shot, and (the tally run only) the most rows one tick's
## separation walk passed for being on another layer.
class Facts:
	extends RefCounted
	var air_start: int = 0
	var air_peak: int = 0
	var air_end: int = 0
	var dropped: int = 0
	var bombs: int = 0
	var air_shots: int = 0
	var ground_to_air: int = 0
	var last_air_tick: int = 0
	var other_layer_max: int = 0
	var hash: int = 0


func before() -> void:
	_gate = load(GATE_PATH) as PerfGateDef
	_time_reference()
	_native_loaded = NativeKernels.create() != null
	for _run: int in RUNS:
		_gd.append(_play(false, _gd_facts))
		if _native_loaded:
			_native.append(_play(true, _native_facts))
	_time_reference()
	_gd_report = _make_report(_gd, false)
	if _native_loaded:
		_native_report = _make_report(_native, true)
	var tallied: Array[Facts] = []
	_play(false, tallied, true)
	_tally_facts = tallied[0]
	print(PerfReport.line(_gd_report, PerfReport.AIR_HEAD))
	print(_native_text())
	var facts: Facts = _gd_facts[0]
	print(
		(
			"WATCH air aircraft=%d air_end=%d bombs=%d air_shots=%d ground_to_air=%d last_air=%d"
			% [
				facts.air_start,
				facts.air_end,
				facts.bombs,
				facts.air_shots,
				facts.ground_to_air,
				facts.last_air_tick
			]
		)
	)
	print("WATCH air other_layer_max=%d" % _tally_facts.other_layer_max)


## The six runs end on the same hash at every checkpoint (ticks 15 to 900): the GDScript twins with
## no kernels and the native ones with them. The seventh run, with the tally probe attached, ends on
## the same hash too: the probe only reads.
func test_the_runs_end_on_the_same_hash_at_every_checkpoint() -> void:
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
		assert_array(run.stats_max).is_equal(twin.stats_max)
	for facts: Facts in _gd_facts + _native_facts:
		assert_int(facts.dropped).is_equal(0)
	assert_int(_tally_facts.hash).is_equal(twin.final_hash)
	assert_int(_tally_facts.dropped).is_equal(0)


## The run is the planned one and stays inside the counted bounds: this arena's own cost bounds, 150
## units, no projectile overflow, the pinned survivors and projectile peak, every bounded counter
## moved, and the rows past another layer within their bound (and above 0, so the walk was judged on
## something).
func test_the_air_arena_stays_inside_its_counted_bounds() -> void:
	for run: Run in _gd + _native:
		assert_array(run.air_bound_lines(ALIVE_END_PIN, PROJ_PEAK_PIN, BUILDINGS)).is_empty()
	var limit: int = PerfBounds.with_margin(PerfBounds.MEASURED_AIR_OTHER_LAYER)
	assert_int(_tally_facts.other_layer_max).is_greater(0)
	assert_int(_tally_facts.other_layer_max).is_less_equal(limit)


## What the aircraft do, the same in every run: 16 at the start and never more, the pinned number
## left, bombs dropped, shots of the aircraft guns, shots from the ground at aircraft (the rifle,
## rocket and Burst Stack of the air arena carry the layer masks), and a bomb or an aircraft shot
## after tick BUSY_UNTIL.
func test_the_aircraft_fly_bomb_fight_and_are_shot_at_to_the_end() -> void:
	var first: Facts = _gd_facts[0]
	for facts: Facts in _gd_facts + _native_facts:
		assert_int(facts.air_start).is_equal(AIRCRAFT)
		assert_int(facts.air_peak).is_equal(AIRCRAFT)
		assert_int(facts.air_end).is_equal(AIR_END_PIN)
		(
			assert_array([facts.bombs, facts.air_shots, facts.ground_to_air, facts.last_air_tick])
			. is_equal([first.bombs, first.air_shots, first.ground_to_air, first.last_air_tick])
		)
	assert_int(first.bombs).is_greater(0)
	assert_int(first.air_shots).is_greater(0)
	assert_int(first.ground_to_air).is_greater(0)
	assert_int(first.last_air_tick).is_greater(BUSY_UNTIL)


## The `PERF air` lines have the keys of the `PERF sim` line in the same order under their own head,
## and the native line puts `impl=native` right after it. The facts come from the air arena: 154
## rows at tick 0 (150 mobile and the 4 buildings), 900 ticks, three runs, and the hash of the final
## state, the last of the gate's `air_golden_hex`. Neither is a `PERF sim` line (P51 selects those)
## and neither holds a newline. Without the library only the GDScript line is made.
func test_the_perf_air_lines_have_the_keys_of_perf_sim_under_their_own_head() -> void:
	var text: String = PerfReport.line(_gd_report, PerfReport.AIR_HEAD)
	assert_str(text).starts_with("PERF air units=")
	assert_bool("\n" in text).is_false()
	var expected: Array[String] = ["PERF", "air"]
	expected.append_array(PerfReport.LINE_KEYS)
	expected.append_array(["stats_max", "phases", "hash"])
	assert_array(_keys_of(text)).is_equal(expected)
	assert_int(_gd_report["units"]).is_equal(PerfBounds.ARENA_UNITS + BUILDINGS)
	assert_int(_gd_report["ticks"]).is_equal(TICKS)
	assert_int(_gd_report["runs"]).is_equal(RUNS)
	assert_str(text.get_slice("hash=", 1)).is_equal(World.hash_hex(_gd[0].final_hash))
	assert_str(text.get_slice("hash=", 1)).is_equal(_gate.air_golden_hex[-1])
	assert_bool(text.begins_with(PerfReport.HEAD)).is_false()
	assert_bool(text.begins_with(PerfReport.BASES_HEAD)).is_false()
	var native_text: String = _native_text()
	assert_bool("\n" in native_text).is_false()
	if _native_loaded:
		assert_str(native_text).starts_with("PERF air impl=native units=")
		expected.insert(2, "impl")
		assert_array(_keys_of(native_text)).is_equal(expected)
		assert_str(native_text.get_slice("hash=", 1)).is_equal(_gate.air_golden_hex[-1])


## The spawns are the 150 mobile units (16 aircraft of the frozen defs) and the four buildings, all
## from `data/dev/arena/`.
func test_the_scenario_holds_150_mobile_units_of_which_16_are_aircraft() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var air: int = 0
	var mobile: int = 0
	var buildings: int = 0
	for spawn: SpawnDef in scenario.spawns:
		assert_str(spawn.unit.resource_path).starts_with("res://data/dev/arena/")
		if spawn.unit is BuildingDef:
			buildings += spawn.count
			continue
		mobile += spawn.count
		if spawn.unit.move_class == World.MoveClass.AIR:
			air += spawn.count
	assert_int(air).is_equal(AIRCRAFT)
	assert_int(mobile).is_equal(PerfBounds.ARENA_UNITS)
	assert_int(buildings).is_equal(BUILDINGS)


## One seed-42 run of TICKS ticks through TickJob. `native` attaches the kernels; `tally` attaches
## the separation tally probe (and no timing) and keeps its per-tick `other_layer` maximum.
func _play(native: bool, into: Array[Facts], tally: bool = false) -> Run:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	if native:
		var kernels: Object = NativeKernels.create()
		world.kernels = kernels
		world.native_phases = kernels.phases()
	var probe: SimProbe = null
	var step_probe: StepProbe = StepProbe.new()
	step_probe.target = TimingProbe.new()
	probe = TallyProbe.new(world) if tally else step_probe
	var job: TickJob = TickJob.new()
	var published: MatchSnapshot = MatchSnapshot.new()
	published.match_serial = MATCH_SERIAL
	published.capture(world, null)
	var run: Run = Run.new()
	var facts: Facts = Facts.new()
	run.units = world.unit_count()
	run.flow_budget = world.flow_cells_per_tick
	run.sep_scan = world.separation_scan
	run.tick_ms.resize(TICKS)
	run.phase_usec.resize(SimProbe.Phase.COUNT)
	run.stats_max.resize(World.Stat.size())
	Buildings.rebuild_lists(world)
	facts.air_start = world.air_rows.size()
	var air_ids: Dictionary[int, bool] = _air_ids(world)
	var layers_before: int = 0
	for tick: int in TICKS:
		var next: MatchSnapshot = MatchSnapshot.new()
		next.match_serial = MATCH_SERIAL
		job.world = world
		job.loop = loop
		job.probe = probe
		job.snapshot = next
		job.previous = published
		job.post_usec = Time.get_ticks_usec()
		job.run()
		run.tick_ms[tick] = next.job_usec / 1000.0
		PerfReport.add_phases(run.phase_usec, next.phase_usec)
		PerfReport.raise_maxima(run.stats_max, world.stats)
		run.proj_peak = maxi(run.proj_peak, PerfReport.live_projectiles(world))
		facts.air_peak = maxi(facts.air_peak, world.air_rows.size())
		_count_shots(world, air_ids, facts)
		air_ids = _air_ids(world)
		if tally:
			var layers: int = (probe as TallyProbe).tally[&"other_layer"]
			facts.other_layer_max = maxi(facts.other_layer_max, layers - layers_before)
			layers_before = layers
		published = next
		if world.tick == PerfBounds.MEMORY_FIRST_TICK:
			run.memory_first = Run.static_memory()
		elif world.tick == PerfBounds.MEMORY_LAST_TICK:
			run.memory_last = Run.static_memory()
	run.alive_end = world.unit_count()
	run.overflow = world.projectile_overflow
	run.native_mask = world.native_phases
	run.checkpoint_ticks = loop.replay.checkpoint_ticks
	run.checkpoint_hashes = loop.replay.checkpoint_hashes
	run.final_hash = world.state_hash()
	facts.air_end = world.air_rows.size()
	facts.dropped = world.dropped_commands
	facts.hash = run.final_hash
	into.append(facts)
	return run


## The ids of the aircraft rows of `world`.
func _air_ids(world: World) -> Dictionary[int, bool]:
	var ids: Dictionary[int, bool] = {}
	for row: int in world.air_rows:
		ids[world.unit_id[row]] = true
	return ids


## Adds the SHOT records of the tick that just ran: a bomb, a shot of the aircraft gun, or a shot
## from anything else at a row that was an aircraft before the tick (`air_ids`).
func _count_shots(world: World, air_ids: Dictionary[int, bool], facts: Facts) -> void:
	var at: int = 0
	while at + World.EVENT_STRIDE <= world.events.size():
		if world.events[at] == World.Event.SHOT:
			var weapon: StringName = world.weapon_ids[world.events[at + 5]]
			var busy: bool = true
			if weapon == BOMBS:
				facts.bombs += 1
			elif weapon == AIR_GUN:
				facts.air_shots += 1
			elif air_ids.has(world.events[at + 4]):
				facts.ground_to_air += 1
			else:
				busy = false
			if busy:
				facts.last_air_tick = world.tick
		at += World.EVENT_STRIDE


## The reference loop timed (report only), as test_base_arena_perf.gd does.
func _time_reference() -> void:
	var sink: int = RefLoop.run(_gate.ref_iterations)
	for _call: int in REF_SAMPLES:
		var started: int = Time.get_ticks_usec()
		sink += RefLoop.run(_gate.ref_iterations)
		_ref_usec.append(Time.get_ticks_usec() - started)
	assert_int(sink).is_greater(0)


## The report of `runs`: the facts are the first run's, the statistics and the phases the best of
## all of them. `native` makes the report of the runs with the kernels attached.
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


## What the suite prints when the library is not loaded, in place of the native line.
func _native_text() -> String:
	if _native_report.is_empty():
		return "perf: no PERF air impl=native line, the SimKernels library is not loaded"
	return PerfReport.line(_native_report, PerfReport.AIR_HEAD)


## The key of every space-separated field of a PERF line.
func _keys_of(text: String) -> Array[String]:
	var keys: Array[String] = []
	for field: String in text.split(" "):
		keys.append(field.get_slice("=", 0))
	return keys
