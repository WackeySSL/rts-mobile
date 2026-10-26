extends GdUnitTestSuite
## Factions as data (plan row P106, ADR 0023 section 6): `UnitDef.faction` becomes `type_faction`
## (an index into `faction_ids`, -1 for none), a scenario's listed factions register their rosters
## after the spawns and the roster, `defs_hash` covers both tables and the state hash neither, and
## `QUEUE` is dropped and counted when the item's faction is set and is not the faction of the
## producer the queue uses. The snapshot copies both tables (the plan's exception 17). Types are
## hand-built definitions for the loader cases; the rule cases take the shipped base of the
## production suites and give its types factions by hand, as the data of P107 will.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const ALPHA: int = 0
const BETA: int = 1
## One item per tab: its id and the tab. The producers are the Headquarters, the barracks and the
## vehicle factory of the production base.
const ITEMS: Array[Array] = [
	["power_plant", World.Tab.STRUCTURES],
	["rifle_squad", World.Tab.INFANTRY],
	["light_tank", World.Tab.VEHICLES],
]
const PRODUCERS: Array[String] = ["headquarters", "barracks", "vehicle_factory"]


func test_a_def_faction_becomes_an_index_in_first_seen_order() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	var types: Array[UnitDef] = [
		_unit(&"u1", &"beta"), _unit(&"u2", &""), _unit(&"u3", &"alpha"), _unit(&"u4", &"beta")
	]
	for unit: UnitDef in types:
		scenario.spawns.append(_spawn(unit))
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"u1", &"u2", &"u3", &"u4"])
	assert_array(world.faction_ids).is_equal([&"beta", &"alpha"])
	assert_array(world.type_faction).is_equal([0, -1, 1, 0])
	# The pad: a hand-built world with a type and no faction entry gets -1 from prepare().
	var plain: World = World.new()
	plain.type_ids.append(&"lone")
	plain.prepare()
	assert_array(plain.type_faction).is_equal([-1])
	assert_array(plain.faction_ids).is_empty()


## A BuildingDef has the field through UnitDef; the type it requires and its free unit are copied in
## after it, each with its own faction, and the building's faction is registered first.
func test_a_building_and_the_types_it_pulls_in_each_have_their_own_faction() -> void:
	var headquarters: BuildingDef = _building(&"hq", &"alpha")
	headquarters.requires = _unit(&"core", &"beta")
	headquarters.free_unit = _unit(&"truck", &"")
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.spawns.append(_spawn(headquarters))
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"hq", &"core", &"truck"])
	assert_array(world.faction_ids).is_equal([&"alpha", &"beta"])
	assert_array(world.type_faction).is_equal([0, 1, -1])


## The listed factions come after the spawns and the roster, by player: entry 0 and a null roster
## entry are skipped, and a type met before (the spawn's, with the first definition winning) keeps
## its first faction, so the faction of the later definition is never registered.
func test_listed_factions_register_their_rosters_after_the_roster_by_player() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.spawns.append(_spawn(_unit(&"s", &"a")))
	scenario.roster.append(_unit(&"r", &"b"))
	var first: Array[UnitDef] = [_unit(&"x1", &"a"), null, _unit(&"x2", &"c")]
	var second: Array[UnitDef] = [_unit(&"s", &"z"), _unit(&"y", &"")]
	scenario.factions.append(null)
	scenario.factions.append(_faction(&"first", first))
	scenario.factions.append(null)
	scenario.factions.append(_faction(&"second", second))
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"s", &"r", &"x1", &"x2", &"y"])
	assert_array(world.faction_ids).is_equal([&"a", &"b", &"c"])
	assert_array(world.type_faction).is_equal([0, 1, 0, 2, -1])


## The perf arena lists no faction (its golden hashes stand on that), and a type that names none has
## index -1 with no id registered.
func test_a_scenario_that_lists_no_faction_has_none() -> void:
	assert_array((load(ARENA_PATH) as ScenarioDef).factions).is_empty()
	var world: World = World.from_scenario(_scenario([&"", &""]))
	assert_array(world.faction_ids).is_empty()
	assert_array(world.type_faction).is_equal([-1, -1])
	var empty: World = World.from_scenario(null)
	assert_array(empty.faction_ids).is_empty()
	assert_array(empty.type_faction).is_empty()


## The default definition names no faction, and the faction def holds the plan's fields.
func test_the_defs_default_to_no_faction() -> void:
	assert_str(String(UnitDef.new().faction)).is_empty()
	assert_str(String(BuildingDef.new().faction)).is_empty()
	var faction: FactionDef = FactionDef.new()
	assert_str(String(faction.id)).is_empty()
	assert_str(faction.display_name).is_empty()
	assert_str(String(faction.emblem)).is_empty()
	assert_array(faction.key_triad).is_empty()
	assert_array(faction.roster).is_empty()
	assert_array(ScenarioDef.new().factions).is_empty()


## `defs_hash` differs for scenarios that differ only in a faction: in its id (the index stays 0, so
## only `faction_ids` moves it) and in which type has one (the ids stay [a], so only `type_faction`
## moves it). The state hash follows neither: faction data is type data.
func test_defs_hash_follows_the_factions_and_the_state_hash_does_not() -> void:
	var base: World = World.from_scenario(_scenario([&"a", &""]))
	var again: World = World.from_scenario(_scenario([&"a", &""]))
	assert_int(again.defs_hash()).is_equal(base.defs_hash())
	var renamed: World = World.from_scenario(_scenario([&"b", &""]))
	var moved: World = World.from_scenario(_scenario([&"", &"a"]))
	assert_array(renamed.type_faction).is_equal(base.type_faction)
	assert_array(moved.faction_ids).is_equal(base.faction_ids)
	assert_int(renamed.defs_hash()).is_not_equal(base.defs_hash())
	assert_int(moved.defs_hash()).is_not_equal(base.defs_hash())
	assert_int(renamed.state_hash()).is_equal(base.state_hash())
	assert_int(moved.state_hash()).is_equal(base.state_hash())


func test_a_queue_of_another_factions_type_is_dropped_and_counted_at_each_tab() -> void:
	for item: Array in ITEMS:
		var world: World = _base()
		var type: int = Worlds.type_of(world, item[0])
		var queue: int = Rig.queue_of(1, item[1])
		var credits: int = world.credits[1]
		world.type_faction[type] = BETA
		Rig.step(world, [Rig.queue(world, 1, item[0])])
		assert_int(world.dropped_commands).override_failure_message(item[0]).is_equal(1)
		assert_int(world.queue_count[queue]).override_failure_message(item[0]).is_equal(0)
		assert_int(world.credits[1]).override_failure_message(item[0]).is_equal(credits)
		# The same command is accepted once the item is the producer's faction.
		world.type_faction[type] = ALPHA
		Rig.step(world, [Rig.queue(world, 1, item[0])])
		assert_int(world.dropped_commands).override_failure_message(item[0]).is_equal(1)
		assert_array(Rig.items(world, 1, item[1])).override_failure_message(item[0]).is_equal(
			[type]
		)
		assert_int(world.credits[1]).is_equal(credits - world.type_cost[type])


## A type without a faction is queued at a producer of any faction, as before the rule.
func test_a_type_without_a_faction_is_queued_at_a_producer_of_any_faction() -> void:
	for item: Array in ITEMS:
		var world: World = _base()
		var type: int = Worlds.type_of(world, item[0])
		var credits: int = world.credits[1]
		assert_int(world.type_faction[type]).is_equal(-1)
		Rig.step(world, [Rig.queue(world, 1, item[0])])
		assert_int(world.dropped_commands).override_failure_message(item[0]).is_equal(0)
		assert_array(Rig.items(world, 1, item[1])).override_failure_message(item[0]).is_equal(
			[type]
		)
		assert_int(world.credits[1]).is_equal(credits - world.type_cost[type])


## A producer with no faction queues only the types with none: the rule compares the two indexes
## and a faction is set on the item, so -1 on the producer is not "any".
func test_a_producer_without_a_faction_does_not_queue_a_type_with_one() -> void:
	var world: World = _base()
	world.type_faction[Worlds.type_of(world, "barracks")] = -1
	world.type_faction[Worlds.type_of(world, "rifle_squad")] = ALPHA
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_array([world.dropped_commands, world.queue_count[Rig.queue_of(1, 1)]]).is_equal([1, 0])


## The producer the queue uses decides: the lowest-id building of the player that produces the tab.
## The refinery (id 3, above the barracks' 2) produces the infantry tab too here (a table edit, the
## data has no second producer) and has the other faction: it is passed over while the barracks
## stands, and takes over when the barracks dies.
func test_the_producer_the_queue_uses_decides_the_faction() -> void:
	var world: World = _base()
	var refinery: int = Worlds.type_of(world, "refinery")
	assert_int(refinery).is_greater_equal(0)
	world.type_produces[refinery] = World.Tab.INFANTRY
	world.type_faction[refinery] = BETA
	var infantry: int = World.Tab.INFANTRY
	assert_int(Production.producer_row(world, 1, infantry)).is_equal(world.index_of(Rig.BARRACKS))
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	var rocket: int = Worlds.type_of(world, "rocket_squad")
	world.type_faction[rifle] = ALPHA
	world.type_faction[rocket] = BETA
	Rig.step(world, [Rig.queue(world, 1, "rocket_squad"), Rig.queue(world, 1, "rifle_squad", 1)])
	assert_array(Rig.items(world, 1, infantry)).is_equal([rifle])
	assert_int(world.dropped_commands).is_equal(1)
	world.hp[world.index_of(Rig.BARRACKS)] = 0
	Rig.step(world)
	assert_int(Production.producer_row(world, 1, infantry)).is_equal(world.index_of(Rig.REFINERY))
	Rig.step(world, [Rig.queue(world, 1, "rocket_squad"), Rig.queue(world, 1, "rifle_squad", 1)])
	assert_array(Rig.items(world, 1, infantry)).is_equal([rifle, rocket])
	assert_int(world.dropped_commands).is_equal(2)


## The snapshot's `faction_ids` is a typed, equal, non-empty copy that is not the World's array, and
## `type_faction` an equal copy that a later change of the World does not reach (exception 17).
func test_the_snapshot_copies_both_faction_tables() -> void:
	var scenario: ScenarioDef = _scenario([&"a", &"b"])
	scenario.factions.append(null)
	scenario.factions.append(_faction(&"b", [_unit(&"z", &"c")] as Array[UnitDef]))
	var world: World = World.from_scenario(scenario)
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = 1
	snap.capture(world, null)
	assert_array(world.faction_ids).is_equal([&"a", &"b", &"c"])
	assert_int(snap.faction_ids.get_typed_builtin()).is_equal(TYPE_STRING_NAME)
	assert_array(snap.faction_ids).is_equal(world.faction_ids)
	assert_bool(is_same(snap.faction_ids, world.faction_ids)).is_false()
	assert_array(snap.type_faction).is_equal([0, 1, 2])
	assert_array(snap.type_faction).is_equal(world.type_faction)
	world.faction_ids.append(&"d")
	world.type_faction[0] = 7
	assert_array(snap.faction_ids).is_equal([&"a", &"b", &"c"])
	assert_array(snap.type_faction).is_equal([0, 1, 2])


## The production base with a Headquarters, whose three producers (Headquarters, barracks, vehicle
## factory) have the faction ALPHA, and the two faction ids registered; every other type has none.
func _base() -> World:
	var world: World = Rig.base()
	Rig.add_headquarters(world)
	var names: Array[StringName] = [&"alpha", &"beta"]
	world.faction_ids.append_array(names)
	for id: String in PRODUCERS:
		world.type_faction[Worlds.type_of(world, id)] = ALPHA
	return world


## Two types, "one" with the first faction and "two" with the second, both spawned.
func _scenario(factions: Array[StringName]) -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.spawns.append(_spawn(_unit(&"one", factions[0])))
	scenario.spawns.append(_spawn(_unit(&"two", factions[1])))
	return scenario


func _unit(type_id: StringName, faction: StringName) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = type_id
	unit.faction = faction
	return unit


func _building(type_id: StringName, faction: StringName) -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.type_id = type_id
	building.faction = faction
	return building


func _spawn(unit: UnitDef) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.count = 1
	spawn.unit = unit
	return spawn


func _faction(id: StringName, roster: Array[UnitDef]) -> FactionDef:
	var faction: FactionDef = FactionDef.new()
	faction.id = id
	faction.roster = roster
	return faction
