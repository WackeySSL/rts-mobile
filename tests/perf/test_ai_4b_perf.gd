extends GdUnitTestSuite
## The AI's time and bounds on Phase 4b's arena (plan row P304, ADR 0038 section 7). Two Normal
## `OpponentAi` play `data/scenarios/perf_ai_4b.tres` for 900 ticks of seed 42, three times, through
## `AiDriver.lagged_tick`, exactly as `test_ai_perf.gd` plays `perf_ai`: the base arena's layout
## with each side's Phase 4b rows at tick 0 (a Flight Yard, Burst Stacks, an Engineering Centre, a
## Space Centre, 2 bombers, 2 fighters, 2 transports and 4 drone squads, 75 mobile rows a side) on
## frozen copies of the Phase 4b defs, and the arena's own frozen AI defs of
## `data/dev/arena/ai_4b/`.
##
## The judged things are deterministic and read from the controllers and the World, never from the
## clock: every think stays inside the counted bounds of ADR 0030 section 4 (the same judge as
## `perf_ai`'s, `ai_perf_run.gd`), the runs end on the same state hash at every checkpoint and drop
## no Command, the arena holds the Phase 4b rows the row asks for, and the run is the planned one
## (the contact, the Commands and the passes below). The arena has no golden pair (ADR 0038 section
## 7): the hash is printed in the `WATCH ai flow` line, not pinned. The think times are only
## printed (`WATCH ai think ... arena=perf_ai_4b`, report only, the smallest of the runs).

const AiRun: GDScript = preload("res://tests/perf/support/ai_perf_run.gd")
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const RUNS: int = 3
## The counters this workload moves (asserted greater than 0 in every run): the ones of `perf_ai`'s
## suite, which the base layout moves here too.
const LIVE: Array[String] = [
	"work", "placement_tries", "keys_staging", "unit_id", "own_mobile_id", "hp_id", "commands"
]
const CONTACT: Array[String] = [
	"seen_unit_id", "seen_site_id", "army_tests", "strike_tests", "keys_army", "keys_scout"
]
## What each side starts with (the scenario's own rows): the rules' 75-unit cap filled, the Phase 4b
## aircraft, transports and drone squads, and the four Phase 4b buildings.
const MOBILE_PER_SIDE: int = 75
const AIRCRAFT_PER_SIDE: int = 4
const TRANSPORTS_PER_SIDE: int = 2
const DRONES_PER_SIDE: int = 4
const FIELDS_PER_SIDE: int = 1
const ANTI_AIR_PER_SIDE: int = 2
const CENTRES_PER_SIDE: int = 2
## The buildings of a side at tick 0: the base arena's 14 (Headquarters, 4 Power Plants, a strike
## building, Radar, Refinery, Barracks, Vehicle Factory and 4 turrets) and Phase 4b's 7 (the Flight
## Yard, 2 Burst Stacks, the Engineering Centre, the Space Centre and 2 more Power Plants).
const BUILDINGS_PER_SIDE: int = 21

var _runs: Array[AiRun] = []


func before() -> void:
	for _run: int in RUNS:
		_runs.append(_play())
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	var first: AiRun = _runs[0]
	var p95_us: float = _smallest(AiRun.p95_of)
	var max_us: float = _smallest(AiRun.max_of)
	print(
		AiRun.think_line(
			p95_us, max_us, first.impl, first.thinks, gate.ci_ratio_p95, AiRun.ARENA_4B
		)
	)
	print(AiRun.flow_line(first.flow_full_ticks, World.hash_hex(first.final_hash), AiRun.ARENA_4B))
	print(AiRun.peaks_line(first.peaks, AiRun.ARENA_4B))


## The runs play the whole 900 ticks (no match end), every Command passes the sim's validation, and
## all end on the same state hash at every checkpoint.
func test_the_runs_play_900_ticks_drop_nothing_and_agree_at_every_checkpoint() -> void:
	var first: AiRun = _runs[0]
	@warning_ignore("integer_division")
	var checkpoints: int = AiRun.TICKS / Replay.CHECKPOINT_PERIOD
	assert_int(first.checkpoint_hashes.size()).is_equal(checkpoints)
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var tag: String = "run %d" % index
		assert_int(run.match_end_tick).append_failure_message(tag).is_equal(0)
		assert_int(run.dropped_commands).append_failure_message(tag).is_equal(0)
		assert_array(run.checkpoint_ticks).append_failure_message(tag).is_equal(
			first.checkpoint_ticks
		)
		assert_array(run.checkpoint_hashes).append_failure_message(tag).is_equal(
			first.checkpoint_hashes
		)
		assert_int(run.final_hash).append_failure_message(tag).is_equal(first.final_hash)
		assert_int(run.flow_full_ticks).append_failure_message(tag).is_equal(first.flow_full_ticks)
		assert_int(run.thinks).append_failure_message(tag).is_equal(first.thinks)
		assert_array(_peak_values(run)).append_failure_message(tag).is_equal(_peak_values(first))


## Every think of both AIs stays inside the bounds of ADR 0030 sections 3 and 4, and the run is the
## planned one: two AIs, at most one think a tick, and as many thinks as the driver's rule owes.
func test_every_think_stays_inside_the_counted_bounds_of_the_adr() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var tag: String = "run %d" % index
		assert_array(run.violations).append_failure_message(tag).is_empty()
		assert_int(run.controllers.size()).append_failure_message(tag).is_equal(2)
		assert_int(run.most_in_a_tick).append_failure_message(tag).is_equal(1)
		assert_int(run.thinks).append_failure_message(tag).is_equal(run.thinks_owed)
		assert_int(run.thinks).append_failure_message(tag).is_equal(run.think_usec.size())


## The counters that this workload moves did move, so their bounds were judged on something, and
## each AI thought in every slot.
func test_the_counters_this_workload_moves_are_live() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		for name: String in LIVE + CONTACT:
			(
				assert_int(run.peaks.get(name, 0))
				. override_failure_message("run %d: %s never moved" % [index, name])
				. is_greater(0)
			)
		assert_int(run.peaks["work"]).override_failure_message("run %d" % index).is_equal(
			AiRun.PASSES_MAX
		)
		for controller: AiController in run.controllers:
			var ai: OpponentAi = controller as OpponentAi
			for slot: int in OpponentAi.SLOTS:
				(
					assert_int(ai.slot_thinks[slot])
					. override_failure_message(
						"run %d player %d slot %d" % [index, ai.player_id, slot]
					)
					. is_greater(0)
				)


## The memory of each AI held every one of its buildings and its 75 mobile rows at some think (the
## peaks of the lists, which the caps of the bound test only cap), so the Phase 4b rows are in the
## views the thinks read.
func test_the_ai_memory_holds_every_row_the_arena_starts_with() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var tag: String = "run %d" % index
		assert_int(run.peaks["site_id"]).append_failure_message(tag).is_greater_equal(
			BUILDINGS_PER_SIDE
		)
		assert_int(run.peaks["own_mobile_id"]).append_failure_message(tag).is_equal(MOBILE_PER_SIDE)


## The early scout and first wave of the frozen defs make contact on this arena too.
func test_the_frozen_defs_make_contact_within_the_900_ticks() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var waves: int = 0
		for at: int in run.controllers.size():
			var ai: OpponentAi = run.controllers[at] as OpponentAi
			var tag: String = "run %d player %d" % [index, ai.player_id]
			assert_int(ai.memory.scout_trip_tick).append_failure_message(tag).is_not_equal(
				AiMemory.NONE
			)
			waves += ai.army.waves
			assert_int(run.seen_peaks[at]).append_failure_message(tag).is_greater(0)
		assert_int(waves).append_failure_message("run %d" % index).is_greater(0)


## The arena is what the row asks for: each side starts with the Phase 4b rows (read from the spawns
## and the loaded World, so a def that lost its aircraft or carrier flags fails here), every spawn
## on a file of `data/dev/arena/`, none refused, and the units at the rules' cap.
func test_each_side_starts_with_its_phase_4b_rows_on_frozen_defs() -> void:
	var scenario: ScenarioDef = load(AiRun.PATH_4B) as ScenarioDef
	for owner: int in [1, 2]:
		var mobile: int = 0
		var aircraft: int = 0
		var transports: int = 0
		var drones: int = 0
		var fields: int = 0
		var anti_air: int = 0
		var centres: int = 0
		for spawn: SpawnDef in scenario.spawns:
			if spawn.owner != owner:
				continue
			assert_str(spawn.unit.resource_path).starts_with("res://data/dev/arena/")
			if spawn.unit is BuildingDef:
				var building: BuildingDef = spawn.unit as BuildingDef
				fields += spawn.count if building.pads > 0 else 0
				anti_air += spawn.count if String(building.type_id).ends_with("_aa") else 0
				centres += spawn.count if _is_centre(building) else 0
				continue
			mobile += spawn.count
			if spawn.unit.move_class == World.MoveClass.AIR:
				if spawn.unit.low_flying:
					drones += spawn.count
				elif spawn.unit.carry_slots > 0:
					transports += spawn.count
				else:
					aircraft += spawn.count
		var tag: String = "player %d" % owner
		assert_int(mobile).append_failure_message(tag).is_equal(MOBILE_PER_SIDE)
		assert_int(aircraft).append_failure_message(tag).is_equal(AIRCRAFT_PER_SIDE)
		assert_int(transports).append_failure_message(tag).is_equal(TRANSPORTS_PER_SIDE)
		assert_int(drones).append_failure_message(tag).is_equal(DRONES_PER_SIDE)
		assert_int(fields).append_failure_message(tag).is_equal(FIELDS_PER_SIDE)
		assert_int(anti_air).append_failure_message(tag).is_equal(ANTI_AIR_PER_SIDE)
		assert_int(centres).append_failure_message(tag).is_equal(CENTRES_PER_SIDE)
	var world: World = World.from_scenario(
		scenario, DetRandom.create(AiRun.SEED, DetRandom.STREAM_SIM)
	)
	assert_int(world.spawn_refused).is_equal(0)
	assert_int(world.unit_cap).is_equal(MOBILE_PER_SIDE)


## The arena's AI defs are the `ai_4b` folder's, not `perf_ai`'s: a run on it plays other files than
## the CI suite of `perf_ai`, and the card's "Perf AI" route plays the same ones.
func test_the_run_and_the_perf_ai_route_play_the_ai_4b_defs() -> void:
	var route: Array[String] = [
		DevRoutes.PERF_AI_4B_FOSSIL, DevRoutes.PERF_AI_4B_RENEW, DevRoutes.PERF_AI_4B_LEVEL
	]
	var suite: Array[String] = []
	suite.assign(AiRun.OPPONENT_PATHS_4B)
	suite.append(AiRun.LEVEL_PATH_4B)
	assert_array(suite).is_equal(route)
	assert_str(AiRun.PATH_4B).is_equal(DevRoutes.PERF_AI_4B_SCENARIO)
	for path: String in route:
		assert_str(path).starts_with("res://data/dev/arena/ai_4b/")
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
	assert_array(AiRun.OPPONENT_PATHS).is_not_equal(AiRun.OPPONENT_PATHS_4B)


## The lines carry `arena=` last, so the one `WATCH ai` grep of CI tells the two arenas apart, and
## `perf_ai`'s lines (no arena) keep their form.
func test_the_watch_lines_of_this_arena_end_in_the_arena_key() -> void:
	var think: String = AiRun.think_line(1900.0, 2000.0, "gdscript", 20, 5.9, AiRun.ARENA_4B)
	assert_str(think).is_equal(
		(
			"WATCH ai think impl=gdscript slots=3 thinks=20 p95_us=1900.000 max_us=2000.000 "
			+ "est_phone_p95_ms=11.210 arena=perf_ai_4b"
		)
	)
	assert_str(AiRun.flow_line(191, "00ab", AiRun.ARENA_4B)).is_equal(
		"WATCH ai flow seed=42 ticks=900 full_ticks=191 hash=00ab arena=perf_ai_4b"
	)
	var counts: Dictionary[String, int] = {"work": 3, "keys_scout": 0}
	assert_str(AiRun.peaks_line(counts, AiRun.ARENA_4B)).is_equal(
		"WATCH ai peaks work=3 keys_scout=0 arena=perf_ai_4b"
	)
	assert_str(AiRun.flow_line(191, "00ab")).is_equal(
		"WATCH ai flow seed=42 ticks=900 full_ticks=191 hash=00ab"
	)


## A building that is one of the Phase 4b centres: the Engineering Centre or the Space Centre.
func _is_centre(building: BuildingDef) -> bool:
	var id: String = String(building.type_id)
	return id.ends_with("_engineering") or id.ends_with("_space")


func _play() -> AiRun:
	var run: AiRun = AiRun.new()
	run.scenario_path = AiRun.PATH_4B
	run.opponent_paths = AiRun.OPPONENT_PATHS_4B
	run.level_path = AiRun.LEVEL_PATH_4B
	run.play()
	return run


## The p95 and the max, each the smallest over the runs (like `PerfReport.best_of`).
func _smallest(statistic: Callable) -> float:
	var smallest: float = INF
	for run: AiRun in _runs:
		smallest = minf(smallest, statistic.call(run.think_usec))
	return smallest


## The peaks of `run` as a list in the order they were first seen, to compare two runs.
func _peak_values(run: AiRun) -> Array[int]:
	var values: Array[int] = []
	for name: String in run.peaks:
		values.append(run.peaks[name])
	return values
