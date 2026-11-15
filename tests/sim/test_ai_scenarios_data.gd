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


## Plan row P304: `perf_ai_4b` is `perf_ai`'s arena (map, rules, factions, size, no orders) with
## Phase 4b's rows added, so the base spawns keep their places and every footprint fits.
func test_perf_ai_4b_is_the_base_arena_of_perf_ai_with_phase_4b_rows_added() -> void:
	var four: ScenarioDef = load(PERF_AI_4B) as ScenarioDef
	var ai: ScenarioDef = load(PERF_AI) as ScenarioDef
	assert_object(four.map).is_same(ai.map)
	assert_object(four.rules).is_same(ai.rules)
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
