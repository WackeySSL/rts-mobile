extends GdUnitTestSuite
## The base arena played for 900 ticks (plan row P80, ADR 0021 section 2, ADR 0023 section 14): the
## scenario `data/scenarios/perf_bases.tres`, seed 42, through MatchLoop. Counted in rows and
## events, never in time. It is played three times: twice in the GDScript phases and once in the C++
## kernels. The cases judge the acceptance of the row: at least 150 mobile rows alive in the heavy
## part, every building type of both factions alive throughout, four harvesters a side unloading,
## both unit tabs producing for both players, no dropped command, and a run that is bit-identical
## across two runs and across the two implementations, that a replay reproduces. Both strikes fire
## inside the 900 ticks (the scenario's strike buildings start their charge part-way through, see
## `SpawnDef.charge_elapsed_ticks`), so the goldens that P93 pins cover them; their rules are
## test_base_arena_strikes'. Golden hashes are not pinned here: plan row P93 pins them (nothing in
## this file names a hash).

const BaseArena: GDScript = preload("res://tests/sim/support/base_arena.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const GATE_FPS: int = 60
const TICKS: int = BaseArena.RUN_TICKS
## The armies close for 65 ticks before the first death; 60 keeps a margin. The gate's own heavy
## window (below) is the number that must hold.
const FULL_TICKS: int = 60
## The tick by which every harvester has unloaded once (the slowest one does at tick 253).
const UNLOAD_BY: int = 300

var _first: BaseArena.Run
var _second: BaseArena.Run
var _native: BaseArena.Run


func before() -> void:
	_first = BaseArena.play(SimImpls.Impl.GDSCRIPT, TICKS)
	_second = BaseArena.play(SimImpls.Impl.GDSCRIPT, TICKS)
	_native = BaseArena.play(SimImpls.Impl.NATIVE, TICKS)


func test_the_three_runs_ran_in_the_implementation_asked_for() -> void:
	for run: BaseArena.Run in [_first, _second, _native]:
		assert_array(run.problems).is_empty()
		assert_int(run.world.tick).is_equal(TICKS)
		for phase: int in SimImpls.EXPECTED_PHASES:
			var native: bool = run.impl == SimImpls.Impl.NATIVE
			assert_bool(SimImpls.is_native(run.world, phase)).is_equal(native)


## The heavy part: 150 mobile rows at the start (75 a side, the unit cap), 150 for a stretch while
## the armies close, and the gate's heavy window (heavy_rigs rows for the ticks that
## heavy_frames_min frames take) held by mobile rows alone, the buildings not counted.
func test_at_least_150_mobile_rows_are_alive_in_the_heavy_part() -> void:
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	var heavy_ticks: int = (gate.heavy_frames_min * Sim.TICK_RATE + GATE_FPS - 1) / GATE_FPS
	var world: World = _first.world
	assert_int(_first.mobile.size()).is_equal(TICKS + 1)
	assert_int(_first.mobile[0]).is_equal(150)
	assert_int(world.unit_cap * world.player_count).is_equal(150)
	assert_int(BaseArena.streak(_first.mobile, 150)).is_greater_equal(FULL_TICKS)
	assert_int(BaseArena.streak(_first.mobile, gate.heavy_rigs)).is_greater_equal(heavy_ticks)
	# Rows are rows: the 28 buildings stand beside them, and a fight went on (the armies lost some).
	assert_int(_first.died).is_greater(40)


func test_every_building_type_of_both_factions_stays_alive_for_the_whole_run() -> void:
	var scenario: ScenarioDef = load(BaseArena.PATH) as ScenarioDef
	var placed: Dictionary[StringName, int] = {}
	for spawn: SpawnDef in scenario.spawns:
		if spawn.unit is BuildingDef:
			placed[spawn.unit.type_id] = placed.get(spawn.unit.type_id, 0) + spawn.count
	var world: World = _first.world
	var types: int = 0
	for faction: FactionDef in [scenario.factions[1], scenario.factions[2]]:
		for unit: UnitDef in faction.roster:
			if not unit is BuildingDef:
				continue
			# Every building type of the roster is placed, and no row of it is ever lost.
			var label: String = str(unit.type_id)
			var count: int = placed.get(unit.type_id, 0)
			assert_int(count).override_failure_message(label).is_greater(0)
			var lowest: int = _first.min_alive[world.type_ids.find(unit.type_id)]
			assert_int(lowest).override_failure_message(label).is_equal(count)
			types += 1
	assert_int(types).is_equal(16)
	assert_int(world.stat_lost_buildings[1] + world.stat_lost_buildings[2]).is_equal(0)


## Four harvesters a side (the 8 of the 150 mobile rows), all alive at the end, each one unloading
## at its refinery by `UNLOAD_BY` and both players richer for it.
func test_four_harvesters_a_side_unload() -> void:
	var world: World = _first.world
	var own: Array[int] = [0, 0, 0]
	for row: int in world.harvester_rows:
		own[world.owner[row]] += 1
	assert_array(own).is_equal([0, 4, 4])
	assert_int(_first.unloaded.size()).is_equal(8)
	for id: int in _first.unloaded:
		assert_int(world.owner[world.index_of(id)]).is_greater(0)
		assert_int(_first.unloaded[id]).override_failure_message(str(id)).is_less(UNLOAD_BY)
	for player: int in [1, 2]:
		assert_int(world.stat_harvested[player]).is_greater(0)


## Both unit tabs spawn units for both players: every QUEUE order of the scenario is built, in its
## own tab. The counts come from the orders, so that a retuned queue moves the case with the data.
func test_both_unit_tabs_produce_for_both_players() -> void:
	var scenario: ScenarioDef = load(BaseArena.PATH) as ScenarioDef
	var queued: PackedInt32Array = PackedInt32Array()
	queued.resize((scenario.player_count + 1) * World.TABS)
	for order: OrderDef in scenario.orders:
		if order.type == Command.Type.QUEUE:
			queued[order.player * World.TABS + order.unit.tab] += 1
	var world: World = _first.world
	for player: int in [1, 2]:
		for tab: int in [World.Tab.INFANTRY, World.Tab.VEHICLES]:
			var at: int = player * World.TABS + tab
			assert_int(queued[at]).override_failure_message("queued %d" % at).is_greater(0)
			assert_int(_first.spawned[at]).override_failure_message("spawned %d" % at).is_equal(
				queued[at]
			)
			assert_int(world.queue_count[at]).is_equal(0)
		assert_int(world.stat_built[player]).is_equal(
			queued[player * World.TABS + 1] + queued[player * World.TABS + 2]
		)


func test_no_command_is_dropped_no_row_refused_and_nobody_loses() -> void:
	for run: BaseArena.Run in [_first, _native]:
		var world: World = run.world
		assert_int(world.dropped_commands).is_equal(0)
		assert_int(world.spawn_refused).is_equal(0)
		assert_int(world.projectile_overflow).is_equal(0)
		assert_int(world.match_end_tick).is_equal(0)
		assert_array(Array(world.defeated_tick)).is_equal([0, 0, 0])


func test_two_gdscript_runs_and_the_native_run_are_bit_identical() -> void:
	assert_int(_first.replay.checkpoint_ticks.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	for run: BaseArena.Run in [_second, _native]:
		assert_array(Array(run.replay.checkpoint_ticks)).is_equal(
			Array(_first.replay.checkpoint_ticks)
		)
		assert_array(Array(run.replay.checkpoint_hashes)).is_equal(
			Array(_first.replay.checkpoint_hashes)
		)
		assert_int(run.replay.final_hash).is_equal(_first.replay.final_hash)
		assert_str(HashReport.mismatch(run.world, _first.world)).is_empty()
	assert_int(_first.world.defs_hash()).is_equal(_native.world.defs_hash())


## The replay holds the scenario's own orders as commands (a group order and the harvesters' ore
## for each side, then its queue items, all at tick 0, then the two strikes on their own ticks) and
## plays back on a fresh world to the same hashes.
func test_the_replay_holds_the_scenario_orders_and_plays_back_to_the_same_hash() -> void:
	var scenario: ScenarioDef = load(BaseArena.PATH) as ScenarioDef
	var items: int = 0
	var strike_ticks: Array[int] = []
	for order: OrderDef in scenario.orders:
		items += 1 if order.type == Command.Type.QUEUE else 0
		if order.type == Command.Type.SUPERWEAPON:
			strike_ticks.append(order.tick)
	strike_ticks.sort()
	var replay: Replay = _first.replay
	var types: Array[int] = []
	var ticks: Array[int] = []
	var payloads: int = 0
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		types.append(command.type)
		ticks.append(command.tick)
		payloads += command.payload.size()
	var side: Array[int] = [Command.Type.ATTACK_MOVE, Command.Type.HARVEST]
	for _item: int in items / 2:
		side.append(Command.Type.QUEUE)
	var strikes: Array[int] = [Command.Type.SUPERWEAPON, Command.Type.SUPERWEAPON]
	assert_array(types).is_equal(side + side + strikes)
	var start: int = side.size() * 2
	for index: int in start:
		assert_int(ticks[index]).override_failure_message(str(index)).is_equal(0)
	assert_array(ticks.slice(start)).is_equal(strike_ticks)
	assert_int(payloads).is_equal(items)
	var fresh: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	assert_int(Replay.play(replay, fresh, TICKS)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)


## One rupture and one blackout land inside the 900 ticks, in both implementations: each strike
## building was fired on its order's tick (it is charging again from there, so the order was not
## dropped), the rupture has landed and hurt a building of the other base, and the
## blackout is in force at the end (when its length reaches that far) on the buildings of the other
## base and nowhere else. The rules (radius, damage, the length) are test_base_arena_strikes'.
func test_one_rupture_and_one_blackout_land_inside_the_run() -> void:
	var scenario: ScenarioDef = load(BaseArena.PATH) as ScenarioDef
	for run: BaseArena.Run in [_first, _native]:
		var world: World = run.world
		var hurt: int = 0
		var offline: Array[int] = [0, 0, 0]
		for row: int in world.unit_count():
			var type: int = world.type_index[row]
			if world.type_foot_w[type] <= 0:
				continue
			if world.owner[row] == 2 and world.hp[row] < world.type_max_hp[type]:
				hurt += 1
			if world.offline_until[row] > world.tick:
				offline[world.owner[row]] += 1
		var kinds: Array[int] = []
		var in_force: bool = false
		for order: OrderDef in scenario.orders:
			if order.type != Command.Type.SUPERWEAPON:
				continue
			var def: BuildingDef = order.unit as BuildingDef
			kinds.append(def.strike_kind)
			if def.strike_kind == Strike.Kind.BLACKOUT:
				in_force = order.tick + 1 + def.strike_ticks > world.tick
			var type: int = world.type_ids.find(def.type_id)
			var row: int = world.type_index.find(type)
			while world.owner[row] != order.player:
				row = world.type_index.find(type, row + 1)
			assert_int(world.ready_tick[row]).is_equal(order.tick + 1 + def.charge_ticks)
			assert_int(order.tick + 1).is_less(TICKS)
		assert_array(kinds).is_equal([Strike.Kind.RUPTURE, Strike.Kind.BLACKOUT])
		assert_int(world.strike_tick[1]).is_equal(0)
		assert_int(hurt).is_greater_equal(1)
		assert_int(offline[0] + offline[2]).is_equal(0)
		if in_force:
			assert_int(offline[1]).is_greater_equal(3)
		else:
			assert_int(offline[1]).is_equal(0)
