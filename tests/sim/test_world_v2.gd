extends GdUnitTestSuite
## World v2, the layout (plan P70, ADR 0017 section 3): the new enums, lists and rule ints by name,
## the four harvest row columns, the player, ore and ghost state that prepare() sizes at its start
## values, the ore cells and the buildable flags a map gives, and the Phase 3 type tables that a
## BuildingDef and a UnitDef fill. The hash sections are in test_world_v2_hash. Numbers are
## literals, so no data file can agree with a wrong rule.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const RULES_PATH: String = "res://data/rules.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
## The 18 Phase 3 rule ints in RulesDef's order, with their values in data/rules.tres.
const PHASE_3_RULES: Dictionary[String, int] = {
	"start_credits": 2000,
	"ore_start": 20,
	"ore_cell_max": 20,
	"ore_regrow_ticks": 150,
	"credits_per_ore": 25,
	"harvest_ticks_per_ore": 3,
	"unload_ticks_per_ore": 1,
	"harvest_reach_milli": 1200,
	"dock_reach_milli": 1500,
	"harvest_retry_ticks": 15,
	"harvest_resume_ticks": 75,
	"harvest_pick_milli": 3000,
	"low_power_percent": 50,
	"queue_slots": 5,
	"build_reach_tiles": 4,
	"unit_cap": 75,
	"building_cap": 40,
	"ghost_cap": 40,
}


func test_the_tabs_and_harvest_modes_are_the_contract() -> void:
	assert_dict(World.Tab).is_equal({"STRUCTURES": 0, "INFANTRY": 1, "VEHICLES": 2})
	assert_int(World.TABS).is_equal(World.Tab.size())
	var modes: Dictionary = {"IDLE": 0, "SEEK": 1, "MINE": 2, "RETURN": 3, "UNLOAD": 4}
	assert_dict(World.HarvestMode).is_equal(modes)
	assert_array([World.STATE_FORMAT, World.HASH_OTHER_SECTIONS]).is_equal([3, 7])


## The lists that Phase 3 declares at once (ADR 0017 section 3), by name and in order. The other
## shape lists are pinned in test_world_v1.
func test_the_new_arrays_are_listed_by_name_in_their_lists() -> void:
	var rows: Array[String] = ["harvest_mode", "cargo", "harvest_slot", "home"]
	assert_array(World.ROW_ARRAYS.slice(20)).is_equal(rows)
	var types: Array[String] = ["type_foot_w", "type_foot_h", "type_cost", "type_build_ticks"]
	types.append_array(["type_tab", "type_requires", "type_produces", "type_power"])
	types.append_array(["type_harvest", "type_free_unit", "type_dock_x", "type_dock_y"])
	types.append_array(["type_exit_x", "type_exit_y"])
	assert_array(World.TYPE_ARRAYS.slice(11)).is_equal(types)
	var players: Array[String] = ["credits", "defeated_tick", "had_producer", "stat_built"]
	players.append_array(["stat_lost_units", "stat_lost_buildings", "stat_harvested"])
	players.append_array(["queue_count", "queue_progress", "rally_x", "rally_y", "queue_type"])
	assert_array(World.PLAYER_ARRAYS).is_equal(players)
	assert_array(World.ORE_ARRAYS).is_equal(["ore_amount"])
	var ghosts: Array[String] = ["ghost_id", "ghost_type", "ghost_owner", "ghost_cell"]
	assert_array(World.GHOST_ARRAYS).is_equal(ghosts + ["ghost_count"])
	var derived: Array[String] = ["power_made", "power_used", "building_rows", "harvester_rows"]
	assert_array(World.DERIVED_ARRAYS).is_equal(derived)
	assert_array(World.HASHED_SCALARS.slice(-2)).is_equal(["match_end_tick", "winner"])
	var sections: PackedStringArray = World.hash_section_names()
	assert_array(sections.slice(-5)).is_equal(["projectiles", "fog", "players", "ore", "ghosts"])
	assert_int(sections.size()).is_equal(World.ROW_ARRAYS.size() + World.HASH_OTHER_SECTIONS)


## The 18 ints join the Phase 2 ones in RULE_SCALARS after max_rows, in RulesDef's order, and in the
## unhashed tail; a World made by hand holds the RulesDef defaults, which are the values of the
## file (the pin pattern of test_defs_data).
func test_the_eighteen_phase_3_rule_ints_follow_max_rows_and_equal_the_file() -> void:
	var names: Array[StringName] = []
	for rule_name: String in PHASE_3_RULES:
		names.append(StringName(rule_name))
	var at: int = World.RULE_SCALARS.find(&"max_rows") + 1
	assert_array(World.RULE_SCALARS.slice(at)).is_equal(names)
	assert_array(World.UNHASHED_SCALARS.slice(-names.size())).is_equal(names)
	assert_int(World.RULE_SCALARS.size()).is_equal(33)
	var world: World = World.new()
	var file: RulesDef = load(RULES_PATH) as RulesDef
	for rule_name: String in PHASE_3_RULES:
		var message: String = rule_name
		assert_int(world.get(rule_name)).override_failure_message(message).is_equal(
			PHASE_3_RULES[rule_name]
		)
		assert_int(file.get(rule_name)).override_failure_message(message).is_equal(
			PHASE_3_RULES[rule_name]
		)


## A new row is idle, carries nothing, works no ore cell and has no refinery, and the compaction
## that removes a dead row moves the four columns with the others.
func test_add_unit_writes_the_harvest_columns_and_a_removal_compacts_them() -> void:
	var world: World = World.new()
	world.type_ids.append(&"unit")
	world.player_count = 1
	world.prepare()
	for _i: int in 4:
		world.add_unit(1, 0, 1000, 1000)
	assert_array(world.harvest_mode).is_equal([0, 0, 0, 0])
	assert_array(world.cargo).is_equal([0, 0, 0, 0])
	assert_array(world.harvest_slot).is_equal([-1, -1, -1, -1])
	assert_array(world.home).is_equal([0, 0, 0, 0])
	for row: int in 4:
		world.harvest_mode[row] = World.HarvestMode.SEEK + row % 2
		world.cargo[row] = 100 * (row + 1)
		world.harvest_slot[row] = row + 7
		world.home[row] = 10 + row
	world.hp[1] = 0
	world.remove_dead()
	assert_array(world.unit_id).is_equal([1, 3, 4])
	assert_array(world.harvest_mode).is_equal([1, 1, 2])
	assert_array(world.cargo).is_equal([100, 300, 400])
	assert_array(world.harvest_slot).is_equal([7, 9, 10])
	assert_array(world.home).is_equal([10, 12, 13])


## prepare() gives every per-player array an entry for the neutral player 0 and one per player:
## credits at start_credits for the players only, no defeat and no producer, empty queues, no rally
## point, every queue slot empty, no last-seen record, and zero power. The sizes follow the rule
## ints, and a second prepare() keeps what the match wrote since.
func test_prepare_sizes_the_player_state_at_its_start_values() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	var rules: RulesDef = RulesDef.new()
	rules.start_credits = 777
	rules.queue_slots = 2
	rules.ghost_cap = 3
	scenario.rules = rules
	scenario.player_count = 2
	var world: World = World.from_scenario(scenario)
	assert_array(world.credits).is_equal([0, 777, 777])
	for column: StringName in [
		&"defeated_tick",
		&"had_producer",
		&"stat_built",
		&"stat_lost_units",
		&"stat_lost_buildings",
		&"stat_harvested",
		&"ghost_count",
		&"power_made",
		&"power_used"
	]:
		assert_array(world.get(column)).override_failure_message(column).is_equal([0, 0, 0])
	for column: StringName in [&"queue_count", &"queue_progress"]:  # Player and tab: 3 x 3.
		assert_array(world.get(column)).override_failure_message(column).is_equal(
			[0, 0, 0, 0, 0, 0, 0, 0, 0]
		)
	var minus: Array[int] = []
	minus.resize(9)
	minus.fill(-1)
	assert_array(world.rally_x).is_equal(minus)
	assert_array(world.rally_y).is_equal(minus)
	minus.resize(18)  # Player, tab and queue slot: 3 x 3 x 2.
	minus.fill(-1)
	assert_array(world.queue_type).is_equal(minus)
	for column: StringName in [&"ghost_id", &"ghost_type", &"ghost_owner", &"ghost_cell"]:
		assert_int(world.get(column).size()).override_failure_message(column).is_equal(9)  # 3 x 3.
	assert_array([world.building_rows.size(), world.harvester_rows.size()]).is_equal([0, 0])
	assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])
	world.credits[1] = 5
	world.prepare()
	assert_array(world.credits).is_equal([0, 5, 777])


## A World with no player has the neutral entry alone; the player count at prepare() sizes the
## arrays of one made by hand.
func test_the_player_arrays_follow_the_player_count_at_prepare() -> void:
	var world: World = World.new()
	world.prepare()
	assert_array(world.credits).is_equal([0])
	assert_int(world.queue_type.size()).is_equal(15)  # 1 x 3 x 5.
	assert_int(world.ghost_id.size()).is_equal(40)
	var late: World = World.new()
	late.add_unit(3, 0, 1000, 1000)
	late.prepare()
	assert_array(late.credits).is_equal([0, 2000, 2000, 2000])
	assert_array([late.rally_x.size(), late.queue_type.size()]).is_equal([12, 60])


## The ore terrain's cells are listed ascending at load and each starts at ore_start units; the
## buildable flag is copied per terrain; set_terrain moves neither (the cells are fixed at load).
func test_a_map_lists_its_ore_cells_and_starts_them_at_ore_start() -> void:
	var scenario: ScenarioDef = _ore_scenario(["..oo", "o.#:", "~~.o"])
	var rules: RulesDef = RulesDef.new()
	rules.ore_start = 7
	scenario.rules = rules
	var world: World = World.from_scenario(scenario)
	assert_array(world.terrain_ids).is_equal(
		[&"grass", &"sand", &"scrub", &"rock", &"water", &"ore"]
	)
	assert_array(world.ore_cell).is_equal([2, 3, 4, 11])
	assert_array(world.ore_amount).is_equal([7, 7, 7, 7])
	assert_array(world.terrain_buildable).is_equal([1, 1, 0, 0, 0, 0])
	world.set_terrain(0, 5)
	world.set_terrain(2, 0)
	assert_array(world.ore_cell).is_equal([2, 3, 4, 11])
	assert_array(world.terrain_buildable).is_equal([1, 1, 0, 0, 0, 0])
	var plain: World = World.from_scenario(_ore_scenario(["..", ".:"]))
	assert_array([plain.ore_cell.size(), plain.ore_amount.size()]).is_equal([0, 0])


## Open grass (no map, or a map that fails validate()) is buildable and has no ore.
func test_open_grass_is_buildable_and_has_no_ore() -> void:
	var world: World = World.new()
	world.map_w = 3000
	world.map_h = 2000
	world.prepare()
	assert_array(world.terrain_buildable).is_equal([1])
	assert_array([world.ore_cell.size(), world.ore_amount.size()]).is_equal([0, 0])
	var arena: World = World.from_scenario(load(ARENA_PATH) as ScenarioDef)
	assert_array(arena.terrain_buildable).is_equal([1, 1, 0, 0, 0, 0])
	assert_array([arena.ore_cell.size(), arena.ore_amount.size()]).is_equal([0, 0])
	assert_array(World.from_scenario(null).terrain_buildable).is_equal([1])


## The constants that mirror the data: grass is buildable and the ore terrain has the id ORE_ID,
## the last of the standard set; no other terrain has it.
func test_the_world_constants_equal_the_standard_terrain_set() -> void:
	var terrains: TerrainSetDef = load(TERRAIN_PATH) as TerrainSetDef
	assert_str(String(terrains.terrains[0].id)).is_equal(String(World.GRASS_ID))
	assert_int(1 if terrains.terrains[0].buildable else 0).is_equal(World.GRASS_BUILDABLE)
	assert_str(String(terrains.terrains[-1].id)).is_equal(String(World.ORE_ID))
	var ore: Array[TerrainDef] = terrains.terrains.filter(
		func(terrain: TerrainDef) -> bool: return terrain.id == World.ORE_ID
	)
	assert_int(ore.size()).is_equal(1)


## A BuildingDef fills the footprint, power, produced tab, free unit, dock and exit tables, a
## UnitDef its cost, build time, tab and cargo and pads the building ones; the type that a def
## requires and the free unit are copied in after it (a chain in order, once each).
func test_a_building_def_fills_the_phase_3_tables_and_its_links_become_types() -> void:
	var harvester: UnitDef = _unit(&"harvester", 1200, 300, 2)
	harvester.speed = 73
	harvester.harvest_capacity = 500
	var headquarters: BuildingDef = _building(&"headquarters", Vector2i(3, 3), 20, 0)
	headquarters.exit = Vector2i(1, 3)
	var plant: BuildingDef = _building(&"power_plant", Vector2i(2, 2), 100, -1)
	plant.cost = 300
	plant.build_ticks = 150
	plant.tab = 0
	plant.requires = headquarters
	var refinery: BuildingDef = _building(&"refinery", Vector2i(3, 3), -30, -1)
	refinery.cost = 1400
	refinery.build_ticks = 375
	refinery.tab = 0
	refinery.requires = plant
	refinery.free_unit = harvester
	refinery.dock = Vector2i(1, 3)
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(refinery)
	var world: World = World.from_scenario(scenario)
	var ids: Array[StringName] = [&"refinery", &"power_plant", &"headquarters", &"harvester"]
	assert_array(world.type_ids).is_equal(ids)
	var expected: Dictionary[StringName, Array] = {
		&"type_foot_w": [3, 2, 3, 0],
		&"type_foot_h": [3, 2, 3, 0],
		&"type_cost": [1400, 300, 0, 1200],
		&"type_build_ticks": [375, 150, 0, 300],
		&"type_tab": [0, 0, -1, 2],
		&"type_requires": [1, 2, -1, -1],
		&"type_produces": [-1, -1, 0, -1],
		&"type_power": [-30, 100, 20, 0],
		&"type_harvest": [0, 0, 0, 500],
		&"type_free_unit": [3, -1, -1, -1],
		&"type_dock_x": [1, 0, 0, 0],
		&"type_dock_y": [3, 0, 0, 0],
		&"type_exit_x": [0, 0, 1, 0],
		&"type_exit_y": [0, 0, 3, 0],
		&"type_speed": [0, 0, 0, 73],
	}
	for table: StringName in expected:
		assert_array(world.get(table)).override_failure_message(table).is_equal(expected[table])
	for table: StringName in World.TYPE_ARRAYS:
		assert_int(world.get(table).size()).override_failure_message(table).is_equal(4)


## A footprint that is not square keeps its width in type_foot_w and its height in type_foot_h, and
## the dock and the exit keep their columns apart (x in _x, y in _y). Every other case uses a
## square footprint, where a width read from the height would pass.
func test_a_non_square_footprint_and_distinct_offsets_keep_each_column() -> void:
	var depot: BuildingDef = _building(&"depot", Vector2i(2, 3), 0, -1)
	depot.dock = Vector2i(0, 3)
	depot.exit = Vector2i(2, 1)
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(depot)
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"depot"])
	var expected: Dictionary[StringName, int] = {
		&"type_foot_w": 2,
		&"type_foot_h": 3,
		&"type_dock_x": 0,
		&"type_dock_y": 3,
		&"type_exit_x": 2,
		&"type_exit_y": 1,
	}
	for table: StringName in expected:
		assert_array(world.get(table)).override_failure_message(table).is_equal([expected[table]])


## Two defs that require each other make two types, each pointing at the other, and the copy ends.
## The two defs are reference counted, so the cycle is cut as soon as the copy is done: a cycle left
## standing keeps the UnitDef script in use at exit, which verify.sh reads as a leak.
func test_defs_that_require_each_other_are_copied_once() -> void:
	var first: UnitDef = _unit(&"first", 0, 0, -1)
	var second: UnitDef = _unit(&"second", 0, 0, -1)
	first.requires = second
	second.requires = first
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(first)
	var world: World = World.from_scenario(scenario)
	first.requires = null
	second.requires = null
	assert_array(world.type_ids).is_equal([&"first", &"second"])
	assert_array(world.type_requires).is_equal([1, 0])


## A scenario spawn of a building def is a row for now (P71 places it through add_building); the
## row still starts at the harvest values and its type has a footprint.
func test_a_building_def_in_a_spawn_is_a_row_with_the_phase_3_columns() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.count = 1
	spawn.unit = _building(&"tower", Vector2i(1, 1), -20, -1)
	scenario.spawns.append(spawn)
	var world: World = World.from_scenario(scenario)
	assert_array([world.unit_count(), world.type_foot_w[0], world.type_foot_h[0]]).is_equal(
		[1, 1, 1]
	)
	assert_array([world.harvest_mode[0], world.harvest_slot[0], world.home[0]]).is_equal([0, -1, 0])


## A map over the standard terrain set (grass, sand, scrub, rock, water, ore), 2 players.
func _ore_scenario(rows: Array[String]) -> ScenarioDef:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(rows)
	map.terrain = load(TERRAIN_PATH) as TerrainSetDef
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 2
	return scenario


func _unit(type_id: StringName, cost: int, build_ticks: int, tab: int) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = type_id
	unit.cost = cost
	unit.build_ticks = build_ticks
	unit.tab = tab
	return unit


func _building(type_id: StringName, footprint: Vector2i, power: int, produces: int) -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.type_id = type_id
	building.footprint = footprint
	building.power = power
	building.produces = produces
	return building
