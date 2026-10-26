extends GdUnitTestSuite
## Buildings as rows (plan row P71, ADR 0017 section 1): `World.add_building` appends a row at the
## footprint centre through `add_unit`, blocks the footprint for every movement class and bumps
## `map_version` once; `remove_dead` gives the tiles back; a scenario spawn of a BuildingDef places
## buildings through it; `had_producer` follows ADR 0018 section 7. Hand-built Worlds from
## `tests/sim/support/building_worlds.gd`, the shipped units and buildings from `data/units/`.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const RULES_PATH: String = "res://data/rules.tres"
const BLOCKED: Array[int] = [0, 0, 0]
const GRASS: Array[int] = [10, 10, 10]


func _inside(cell: int, cols: int, col: int, line: int, width: int, height: int) -> bool:
	var x: int = cell % cols
	var y: int = cell / cols
	return x >= col and x < col + width and y >= line and y < line + height


func test_a_footprint_blocks_every_class_and_bumps_the_map_version_once() -> void:
	var world: World = Worlds.open(10, 8)
	var hq: int = Worlds.type_of(world, "headquarters")
	var before: int = world.map_version
	var id: int = world.add_building(1, hq, 2, 3)
	assert_int(id).is_greater(0)
	assert_int(world.map_version).is_equal(before + 1)
	for cell: int in 80:
		var expected: Array[int] = BLOCKED if _inside(cell, 10, 2, 3, 3, 3) else GRASS
		(
			assert_array(Worlds.costs_at(world, cell))
			. override_failure_message("cell %d" % cell)
			. is_equal(expected)
		)


func test_a_placement_invalidates_the_flow_cache() -> void:
	var world: World = Worlds.open(10, 8)
	var slot: int = world.flow.acquire(0, World.MoveClass.FOOT, world.map_version, 0)
	world.flow.recount(world.field, world.unit_count())
	assert_int(world.flow.status[slot]).is_not_equal(FlowCache.Status.FREE)
	world.add_building(1, Worlds.type_of(world, "defence_turret"), 5, 5)
	assert_int(world.flow.status[slot]).is_equal(FlowCache.Status.FREE)


func test_a_building_stands_on_its_footprint_centre_and_its_origin_is_derived() -> void:
	var world: World = Worlds.open(14, 8)
	var cases: Array[Array] = [
		["headquarters", 3, 3, 1], ["power_plant", 2, 2, 6], ["defence_turret", 1, 1, 10]
	]
	for case: Array in cases:
		var type: int = Worlds.type_of(world, case[0])
		var id: int = world.add_building(1, type, case[3], 2)
		var row: int = world.index_of(id)
		assert_int(world.pos_x[row]).is_equal(case[3] * 1000 + case[1] * 500)
		assert_int(world.pos_y[row]).is_equal(2000 + case[2] * 500)
		assert_vector(world.footprint_origin(row)).is_equal(Vector2i(case[3], 2))
	var rifle: int = world.index_of(world.add_unit(1, 0, 4500, 6999))
	assert_vector(world.footprint_origin(rifle)).is_equal(Vector2i(4, 6))


func test_the_new_row_is_an_ordinary_row_with_its_event_and_full_hit_points() -> void:
	var world: World = Worlds.open(10, 8)
	var plant: int = Worlds.type_of(world, "power_plant")
	var rows_before: int = world.rows_version
	var id: int = world.add_building(2, plant, 3, 4)
	var row: int = world.index_of(id)
	assert_int(world.rows_version).is_equal(rows_before + 1)
	assert_int(world.owner[row]).is_equal(2)
	assert_int(world.hp[row]).is_equal(world.type_max_hp[plant])
	assert_int(world.fog_cell[row]).is_equal(-1)
	assert_array(world.events.slice(0, 6)).is_equal([World.Event.SPAWNED, id, 4000, 5000, plant, 2])
	assert_int(world.add_building(2, plant, 6, 4)).is_equal(id + 1)


func test_a_building_off_the_map_or_without_a_footprint_is_refused_and_counted() -> void:
	var world: World = Worlds.open(10, 8)
	var hq: int = Worlds.type_of(world, "headquarters")
	var costs: PackedByteArray = world.move_cost.duplicate()
	var version: int = world.map_version
	var refused: Array[Vector2i] = [
		Vector2i(-1, 2), Vector2i(2, -1), Vector2i(8, 2), Vector2i(2, 6)
	]
	for origin: Vector2i in refused:
		assert_int(world.add_building(1, hq, origin.x, origin.y)).is_equal(0)
	assert_int(world.add_building(1, Worlds.type_of(world, "rifle_squad"), 2, 2)).is_equal(0)
	assert_int(world.add_building(1, -1, 2, 2)).is_equal(0)
	assert_int(world.add_building(1, 99, 2, 2)).is_equal(0)
	assert_int(world.spawn_refused).is_equal(7)
	assert_int(world.unit_count()).is_equal(0)
	assert_int(world.map_version).is_equal(version)
	assert_array(world.move_cost).is_equal(costs)
	# A footprint that fits exactly in a corner is not refused.
	assert_int(world.add_building(1, hq, 7, 5)).is_greater(0)


func test_a_refusal_of_add_unit_leaves_the_map_alone() -> void:
	var world: World = Worlds.open(10, 8)
	var hq: int = Worlds.type_of(world, "headquarters")
	var costs: PackedByteArray = world.move_cost.duplicate()
	var version: int = world.map_version
	assert_int(world.add_building(3, hq, 2, 2)).is_equal(0)  # Player 3 of 2.
	world.max_rows = world.unit_count()
	assert_int(world.add_building(1, hq, 2, 2)).is_equal(0)  # The table is full.
	assert_int(world.spawn_refused).is_equal(2)
	assert_int(world.map_version).is_equal(version)
	assert_array(world.move_cost).is_equal(costs)


func test_the_death_of_buildings_restores_the_terrain_cost_and_bumps_the_map_version_once() -> void:
	var rows: PackedStringArray = ["........", "..2.....", "..44....", "........", "......^."]
	var world: World = Worlds.world(rows)
	var costs: PackedByteArray = world.move_cost.duplicate()
	var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 2, 1)
	var turret: int = world.add_building(2, Worlds.type_of(world, "defence_turret"), 6, 4)
	assert_array(Worlds.costs_at(world, 1 * 8 + 2)).is_equal(BLOCKED)
	assert_array(Worlds.costs_at(world, 4 * 8 + 6)).is_equal(BLOCKED)
	var version: int = world.map_version
	world.events.clear()
	world.hp[world.index_of(plant)] = 0
	world.hp[world.index_of(turret)] = -5
	world.remove_dead()
	assert_int(world.map_version).is_equal(version + 1)
	assert_array(world.move_cost).is_equal(costs)
	assert_array(Worlds.costs_at(world, 1 * 8 + 2)).is_equal([20, 20, 20])
	assert_array(Worlds.costs_at(world, 2 * 8 + 3)).is_equal([40, 40, 40])
	assert_array(Worlds.costs_at(world, 4 * 8 + 6)).is_equal([10, 0, 0])  # Scrub: foot only.
	assert_int(world.unit_count()).is_equal(0)
	assert_int(world.events.size()).is_equal(2 * World.EVENT_STRIDE)


func test_a_unit_death_leaves_the_map_alone_and_a_building_death_frees_the_flow() -> void:
	var world: World = Worlds.open(10, 8)
	var hq: int = world.add_building(1, Worlds.type_of(world, "headquarters"), 5, 2)
	var rifle: int = world.add_unit(1, 0, 1500, 1500)
	var version: int = world.map_version
	world.hp[world.index_of(rifle)] = 0
	world.remove_dead()
	assert_int(world.map_version).is_equal(version)
	assert_array(Worlds.costs_at(world, 3 * 10 + 6)).is_equal(BLOCKED)
	var slot: int = world.flow.acquire(0, World.MoveClass.FOOT, world.map_version, 0)
	world.flow.recount(world.field, world.unit_count())
	world.hp[world.index_of(hq)] = 0
	world.remove_dead()
	assert_int(world.map_version).is_equal(version + 1)
	assert_int(world.flow.status[slot]).is_equal(FlowCache.Status.FREE)
	assert_array(Worlds.costs_at(world, 3 * 10 + 6)).is_equal(GRASS)


func test_a_scenario_spawn_of_a_building_def_places_buildings_through_add_building() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(16, 12)
	scenario.player_count = 2
	scenario.rules = load(RULES_PATH) as RulesDef
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 2
	spawn.unit = load("res://data/units/headquarters.tres") as UnitDef
	spawn.count = 3
	spawn.columns = 2
	spawn.origin_tile = Vector2i(1, 1)
	spawn.jitter = 5000  # Draws nothing for a building.
	scenario.spawns.append(spawn)
	var rng: DetRandom = DetRandom.create(7, DetRandom.STREAM_SIM)
	var drawn: PackedInt64Array = rng.state()
	var world: World = World.from_scenario(scenario, rng)
	assert_array(rng.state()).is_equal(drawn)
	assert_array(world.unit_id).is_equal([1, 2, 3])
	var origins: Array[Vector2i] = [Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 4)]
	for row: int in 3:
		assert_int(world.owner[row]).is_equal(2)
		assert_vector(world.footprint_origin(row)).is_equal(origins[row])
	for cell: int in 16 * 12:
		var blocked: bool = (
			_inside(cell, 16, 1, 1, 3, 3)
			or _inside(cell, 16, 4, 1, 3, 3)
			or _inside(cell, 16, 1, 4, 3, 3)
		)
		assert_array(Worlds.costs_at(world, cell)).is_equal(BLOCKED if blocked else GRASS)
	assert_array(world.had_producer).is_equal([0, 0, 1])  # The HQ produces a tab.
	assert_int(world.events.size()).is_equal(0)
	assert_bool(world.prepared).is_true()
	assert_int(world.spawn_refused).is_equal(0)


func test_had_producer_is_set_by_a_building_that_produces_a_tab_and_nothing_resets_it() -> void:
	var world: World = Worlds.open(14, 8)
	var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 1, 1)
	assert_array(world.had_producer).is_equal([0, 0, 0])
	var hq: int = world.add_building(2, Worlds.type_of(world, "headquarters"), 6, 1)
	assert_array(world.had_producer).is_equal([0, 0, 1])
	world.hp[world.index_of(hq)] = 0
	world.hp[world.index_of(plant)] = 0
	world.remove_dead()
	assert_array(world.had_producer).is_equal([0, 0, 1])


func test_a_hand_built_world_gets_open_grass_and_no_producer_from_a_table_it_does_not_have(
) -> void:
	var world: World = World.new()
	world.map_w = 8000
	world.map_h = 8000
	world.player_count = 1
	world.type_ids.append(&"block")
	world.type_foot_w.append(2)
	world.type_foot_h.append(2)
	# `type_produces` has no entry yet (prepare() would pad it with -1): no tab is not tab 0.
	assert_int(world.add_building(1, 0, 1, 1)).is_greater(0)
	assert_array(world.had_producer).is_empty()  # Nothing to set; prepare() sizes it.
	assert_int(world.map_cols).is_equal(8)
	assert_array(Worlds.costs_at(world, 1 * 8 + 1)).is_equal(BLOCKED)
	assert_array(Worlds.costs_at(world, 0)).is_equal(GRASS)
	world.type_produces.append(0)
	assert_int(world.add_building(1, 0, 4, 4)).is_greater(0)
	world.prepare()
	assert_array(world.had_producer).is_equal([0, 1])
