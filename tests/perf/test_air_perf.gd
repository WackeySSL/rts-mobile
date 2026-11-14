extends GdUnitTestSuite
## The air arena's perf line and counted bounds (plan row P253, ADR 0013 section 1). The seed-42 run
## of `data/scenarios/perf_air.tres` (the perf arena's 150 units, 16 of them aircraft, one airfield
## for each side, on the frozen defs of `data/dev/arena/`) is played for 900 ticks through
## TickJob.run() in SYNC, once with the GDScript phases and once with the C++ kernels attached (the
## aircraft rules, `Air.gd`, are GDScript in both). The suite prints `PERF air units=...` with the
## sample's keys, and judges only what is deterministic and read from the World, never the clock:
## the two runs end on the same state hash at every 15 ticks, no Command is dropped, the cost
## counters stay inside the bounds of `PerfBounds.cost_bounds` (the perf arena's, which the aircraft
## share), the run itself holds (150 units, 16 of them aircraft, no projectile overflow, the pinned
## survivors and projectile peak) and the aircraft count never rises. The golden hashes are
## test_golden_hashes.gd's (`air_golden_*` of the gate file).

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const Run: GDScript = preload("res://tests/perf/support/perf_run.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_air.tres"
const TICKS: int = 900
const SEED: int = 42
const MATCH_SERIAL: int = 1
## The run's pins, measured on the seed-42 run: the units alive after the last tick and the most
## projectiles in flight. `PerfBounds.load_violations` allows P49a's margin either side.
const ALIVE_END_PIN: int = 85
const PROJ_PEAK_PIN: int = 22
## The aircraft the arena starts with (8 for each side), and what the run left of them.
const AIRCRAFT: int = 16
const AIR_END_PIN: int = 12

var _gd: Run
var _native: Run
var _air_start: int = 0
var _air_peak: int = 0
var _air_end: int = 0
var _dropped: int = 0
var _native_loaded: bool = false


func before() -> void:
	_native_loaded = NativeKernels.create() != null
	_gd = _play(false)
	if _native_loaded:
		_native = _play(true)
	print(
		(
			"PERF air units=%d aircraft=%d air_end=%d alive_end=%d proj_peak=%d hash=%s"
			% [
				_gd.units,
				_air_start,
				_air_end,
				_gd.alive_end,
				_gd.proj_peak,
				World.hash_hex(_gd.final_hash),
			]
		)
	)
	print("PERF air stats_max=%s" % str(_gd.stats_max))


## The two runs end on the same hash at every checkpoint (ticks 15 to 900), the native run with the
## kernels attached and the GDScript one with none. Without the library only the twin runs.
func test_the_runs_end_on_the_same_hash_at_every_checkpoint() -> void:
	assert_bool(_native_loaded).is_equal(ClassDB.class_exists(&"SimKernels"))
	assert_int(_gd.native_mask).is_equal(0)
	assert_int(_gd.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	assert_int(_dropped).is_equal(0)
	if _native_loaded:
		assert_int(_native.native_mask).is_equal(NativeKernels.create().phases())
		assert_array(_native.checkpoint_ticks).is_equal(_gd.checkpoint_ticks)
		assert_array(_native.checkpoint_hashes).is_equal(_gd.checkpoint_hashes)
		assert_int(_native.final_hash).is_equal(_gd.final_hash)
		assert_array(_native.stats_max).is_equal(_gd.stats_max)


## The run is the planned one and stays inside the counted bounds of the perf arena's counters: 150
## units at tick 0, 16 of them aircraft, no projectile overflow, the pinned survivors and projectile
## peak, and every bounded counter moved (a counter that reads 0 is not live).
func test_the_air_arena_stays_inside_its_counted_bounds() -> void:
	assert_int(_air_start).is_equal(AIRCRAFT)
	assert_int(_air_peak).is_equal(AIRCRAFT)
	assert_int(_air_end).is_equal(AIR_END_PIN)
	for run: Run in [_gd, _native] if _native_loaded else [_gd]:
		assert_array(run.bound_lines(ALIVE_END_PIN, PROJ_PEAK_PIN)).is_empty()


## The unit count and the aircraft: `Air.is_aircraft` is the rule, so a def that lost its AIR bit
## shows here and not as a quiet drop in the load.
func test_the_aircraft_are_the_bombers_and_fighters_of_the_frozen_defs() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var air: int = 0
	var ground: int = 0
	for spawn: SpawnDef in scenario.spawns:
		if spawn.unit is BuildingDef:
			continue
		if spawn.unit.move_class == World.MoveClass.AIR:
			air += spawn.count
		else:
			ground += spawn.count
		assert_str(spawn.unit.resource_path).starts_with("res://data/dev/arena/units/")
	assert_int(air).is_equal(AIRCRAFT)
	assert_int(air + ground).is_equal(PerfBounds.ARENA_UNITS - 2)


## The seed-42 scenario for TICKS ticks through TickJob, with or without the kernels.
func _play(native: bool) -> Run:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	if native:
		var kernels: Object = NativeKernels.create()
		world.kernels = kernels
		world.native_phases = kernels.phases()
	var job: TickJob = TickJob.new()
	var published: MatchSnapshot = MatchSnapshot.new()
	published.match_serial = MATCH_SERIAL
	published.capture(world, null)
	var run: Run = Run.new()
	run.units = world.unit_count()
	run.flow_budget = world.flow_cells_per_tick
	run.sep_scan = world.separation_scan
	run.stats_max.resize(World.Stat.size())
	Buildings.rebuild_lists(world)
	_air_start = world.air_rows.size()
	for _tick: int in TICKS:
		var next: MatchSnapshot = MatchSnapshot.new()
		next.match_serial = MATCH_SERIAL
		job.world = world
		job.loop = loop
		job.snapshot = next
		job.previous = published
		job.post_usec = Time.get_ticks_usec()
		job.run()
		PerfReport.raise_maxima(run.stats_max, world.stats)
		run.proj_peak = maxi(run.proj_peak, PerfReport.live_projectiles(world))
		_air_peak = maxi(_air_peak, world.air_rows.size())
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
	_air_end = world.air_rows.size()
	_dropped = maxi(_dropped, world.dropped_commands)
	return run
