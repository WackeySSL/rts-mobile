extends GdUnitTestSuite
## The scenarios the opponent AI plays (plan row P174, ADR 0031): `perf_ai`, the base arena's layout
## on the frozen defs with no scenario orders, and the two same-faction Kestrel Flats skirmishes on
## the shipped defs. Data only: nothing here pins a hash, and no rule number is a literal.

const PERF_AI: String = "res://data/scenarios/perf_ai.tres"
const PERF_AI_4B: String = "res://data/scenarios/perf_ai_4b.tres"
const PERF_BASES: String = "res://data/scenarios/perf_bases.tres"
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const FOSSIL_MIRROR: String = "res://data/scenarios/skirmish_kestrel_flats_fossil_mirror.tres"
const RENEW_MIRROR: String = "res://data/scenarios/skirmish_kestrel_flats_renew_mirror.tres"
const SEED: int = 42


func test_perf_ai_has_the_base_arenas_map_spawns_and_frozen_defs_but_no_orders() -> void:
	var ai: ScenarioDef = load(PERF_AI) as ScenarioDef
	var bases: ScenarioDef = load(PERF_BASES) as ScenarioDef
	assert_object(ai.map).is_same(bases.map)
	assert_object(ai.rules).is_same(bases.rules)
	assert_that(ai.map_size_tiles).is_equal(bases.map_size_tiles)
	assert_that(ai.camera_start_tile).is_equal(bases.camera_start_tile)
	assert_int(ai.player_count).is_equal(bases.player_count)
	assert_array(ai.orders).is_empty()
	assert_int(bases.orders.size()).is_greater(0)
	assert_int(ai.factions.size()).is_equal(bases.factions.size())
	for i: int in ai.factions.size():
		assert_object(ai.factions[i]).is_same(bases.factions[i])
	assert_int(ai.spawns.size()).is_equal(bases.spawns.size())
	for i: int in ai.spawns.size():
		(
			assert_bool(_same_spawn(ai.spawns[i], bases.spawns[i]))
			. override_failure_message("spawn %d" % i)
			. is_true()
		)


func test_perf_ai_loads_with_every_footprint_on_the_map() -> void:
	var world: World = World.from_scenario(
		load(PERF_AI) as ScenarioDef, DetRandom.create(SEED, DetRandom.STREAM_SIM)
	)
	assert_int(world.spawn_refused).is_equal(0)
	assert_int(world.max_rows).is_greater(0)


## Plan row P304: `perf_ai_4b` is `perf_ai`'s arena (map, factions, size, no orders; its own rules
## copy) with Phase 4b's rows added, so the base spawns keep their places and every footprint fits.
func test_perf_ai_4b_is_the_base_arena_of_perf_ai_with_phase_4b_rows_added() -> void:
	var four: ScenarioDef = load(PERF_AI_4B) as ScenarioDef
	var ai: ScenarioDef = load(PERF_AI) as ScenarioDef
	assert_object(four.map).is_same(ai.map)
	# Its own frozen rules: perf_ai's with today's carry, mend, sell and mine values, so they work.
	assert_str(four.rules.resource_path).is_equal("res://data/dev/arena/arena_4b/rules.tres")
	assert_int(four.rules.unit_cap).is_equal(ai.rules.unit_cap)
	assert_int(four.rules.flow_cache_size).is_equal(ai.rules.flow_cache_size)
	assert_int(four.rules.passenger_cap).is_greater(0)
	assert_int(four.rules.load_reach_milli).is_greater(0)
	assert_int(four.rules.mend_hp).is_greater(0)
	assert_int(four.rules.sell_refund_percent).is_greater(0)
	assert_that(four.map_size_tiles).is_equal(ai.map_size_tiles)
	assert_that(four.camera_start_tile).is_equal(ai.camera_start_tile)
	assert_int(four.player_count).is_equal(ai.player_count)
	assert_array(four.orders).is_empty()
	assert_int(four.factions.size()).is_equal(ai.factions.size())
	for i: int in four.factions.size():
		assert_object(four.factions[i]).is_same(ai.factions[i])
	# Every building and the base arena's tanks, heavies and tankers keep their spawn.
	for owner: int in [1, 2]:
		for kind: String in ["headquarters", "hq", "refinery", "barracks", "factory"]:
			assert_int(_count_of(four, owner, kind)).override_failure_message(kind).is_equal(
				_count_of(ai, owner, kind)
			)
	assert_int(four.spawns.size()).is_greater(ai.spawns.size())
	var world: World = World.from_scenario(four, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	assert_int(world.spawn_refused).is_equal(0)
	# 75 mobile rows and 21 buildings for each side, inside the rules' row budget.
	assert_int(world.unit_count()).is_equal(2 * (75 + 21))
	assert_int(world.unit_count()).is_less_equal(world.max_rows)


## Every Phase 4b type is on each side at tick 0, counted by type (a dropped Space Centre or bomber
## fails, which a count by category would miss): a type id ends in the suffix.
func test_every_phase_4b_type_is_on_each_side_at_tick_0() -> void:
	var four: ScenarioDef = load(PERF_AI_4B) as ScenarioDef
	var want: Dictionary[String, int] = {
		"_airfield": 1,
		"_aa": 2,
		"_engineering": 1,
		"_space": 1,
		"_bomber": 2,
		"_fighter": 2,
		"_transport": 2,
		"_drone": 4,
	}
	for owner: int in [1, 2]:
		for suffix: String in want:
			(
				assert_int(_count_of(four, owner, suffix))
				. override_failure_message("player %d %s" % [owner, suffix])
				. is_equal(want[suffix])
			)
	# The Space Centres start charged, so P252's sweep can fire inside the run.
	for spawn: SpawnDef in four.spawns:
		if String(spawn.unit.type_id).ends_with("_space"):
			assert_int(spawn.charge_elapsed_ticks).is_greater_equal(
				(spawn.unit as BuildingDef).charge_ticks
			)


## Mending and carrying work on the 4b arena: its rules enable them (a rule at 0 is inert), the
## transports can carry and unload, and the anti-air weapons the arena's spawns shoot with keep the
## shipped layer masks (ground 1, low flying 2, air 4: rifle 5, rocket 7, needle and Burst Stack 6).
func test_perf_ai_4b_mends_unloads_and_shoots_at_aircraft_as_shipped() -> void:
	var four: ScenarioDef = load(PERF_AI_4B) as ScenarioDef
	var rules: RulesDef = four.rules
	assert_int(rules.mend_hp).is_greater(0)
	assert_int(rules.mend_period_ticks).is_greater(0)
	assert_int(rules.unload_reach_tiles).is_greater(0)
	assert_int(rules.load_reach_milli).is_greater(0)
	assert_int(rules.passenger_cap).is_greater(0)
	var masks: Dictionary[String, int] = {
		"rifle_squad": 5,
		"renew_rifle": 5,
		"rocket_squad": 7,
		"renew_rocket": 7,
		"defence_turret": 5,
		"fossil_aa": 6,
		"renew_aa": 6,
		"fossil_fighter": 2,
		"renew_fighter": 2,
	}
	var seen: Dictionary[String, bool] = {}
	for spawn: SpawnDef in four.spawns:
		var id: String = String(spawn.unit.type_id)
		if masks.has(id):
			seen[id] = true
			assert_int(spawn.unit.weapon.targets).override_failure_message(id).is_equal(masks[id])
	assert_int(seen.size()).is_equal(masks.size())


func test_the_fossil_mirror_is_the_skirmish_with_player_two_swapped_to_fossil() -> void:
	_assert_mirror(FOSSIL_MIRROR, &"fossil", &"fossil")


func test_the_renew_mirror_is_the_skirmish_with_player_one_swapped_to_renew() -> void:
	_assert_mirror(RENEW_MIRROR, &"renew", &"renew")


func test_the_mirrors_load_and_every_footprint_fits() -> void:
	for path: String in [FOSSIL_MIRROR, RENEW_MIRROR]:
		var world: World = World.from_scenario(
			load(path) as ScenarioDef, DetRandom.create(SEED, DetRandom.STREAM_SIM)
		)
		assert_int(world.spawn_refused).override_failure_message(path).is_equal(0)


## Spawns equal the source's (owner, count, tile, layout) and the unit differs only where the
## owner's faction changed; both sides' units belong to the faction the mirror names.
func _assert_mirror(path: String, faction_one: StringName, faction_two: StringName) -> void:
	var mirror: ScenarioDef = load(path) as ScenarioDef
	var source: ScenarioDef = load(SKIRMISH) as ScenarioDef
	assert_object(mirror.map).is_same(source.map)
	assert_object(mirror.rules).is_same(source.rules)
	assert_int(mirror.player_count).is_equal(source.player_count)
	assert_that(mirror.camera_start_tile).is_equal(source.camera_start_tile)
	assert_array(mirror.orders).is_empty()
	assert_int(mirror.factions.size()).is_equal(3)
	assert_str(String(mirror.factions[1].id)).is_equal(String(faction_one))
	assert_str(String(mirror.factions[2].id)).is_equal(String(faction_two))
	assert_int(mirror.spawns.size()).is_equal(source.spawns.size())
	for i: int in mirror.spawns.size():
		var made: SpawnDef = mirror.spawns[i]
		var base: SpawnDef = source.spawns[i]
		assert_int(made.owner).is_equal(base.owner)
		assert_int(made.count).is_equal(base.count)
		assert_that(made.origin_tile).is_equal(base.origin_tile)
		assert_int(made.columns).is_equal(base.columns)
		assert_int(made.spacing).is_equal(base.spacing)
		assert_int(made.jitter).is_equal(base.jitter)
		var faction: FactionDef = mirror.factions[made.owner]
		(
			assert_bool(made.unit in faction.roster)
			. override_failure_message("%s spawn %d" % [path, i])
			. is_true()
		)
		if base.unit in source.factions[base.owner].roster and base.unit in faction.roster:
			assert_object(made.unit).is_same(base.unit)
	# A mirror: both sides start with the same blocks of the same units, in the same order.
	assert_array(_type_ids(mirror, 2)).override_failure_message(path).is_equal(_type_ids(mirror, 1))


## The units that `owner` starts with whose type id ends in `suffix` (a spawn's count summed).
func _count_of(scenario: ScenarioDef, owner: int, suffix: String) -> int:
	var total: int = 0
	for spawn: SpawnDef in scenario.spawns:
		if spawn.owner == owner and String(spawn.unit.type_id).ends_with(suffix):
			total += spawn.count
	return total


func _type_ids(scenario: ScenarioDef, owner: int) -> Array[String]:
	var ids: Array[String] = []
	for spawn: SpawnDef in scenario.spawns:
		if spawn.owner == owner:
			ids.append(String(spawn.unit.type_id))
	return ids


func _same_spawn(a: SpawnDef, b: SpawnDef) -> bool:
	return (
		a.owner == b.owner
		and a.unit == b.unit
		and a.count == b.count
		and a.origin_tile == b.origin_tile
		and a.columns == b.columns
		and a.spacing == b.spacing
		and a.jitter == b.jitter
		and a.charge_elapsed_ticks == b.charge_elapsed_ticks
	)
