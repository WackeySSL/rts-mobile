extends GdUnitTestSuite
## World v6, the air and tech layout (plan row P232, ADR 0036 sections 3, 4 and 13, named exception
## 23): the layer bit derived at load, the air, pad and repair tables, `weapon_targets`, the
## upgrade tables, the row column `ammo` and the three player arrays, each in the hash or the defs
## hash as the ADR says; the open AIR plane of `move_cost` and the three sites that loop over the
## ground classes; `TABS` 5; and the copies in PlayerView and MatchSnapshot. The shape lists are
## pinned in test_world_v1 to test_world_v4, the golden hashes in test_world_hash and
## tests/perf/test_golden_hashes. Numbers are literals, so no layout can agree with itself.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const FOOT: int = World.MoveClass.FOOT
const AIR: int = World.MoveClass.AIR
## A 12 x 3 map: grass, with a wall of rock on column 5 that every ground class stops at.
const WALL: Array[String] = ["....#.......", "....#.......", "....#......."]


func test_the_layer_bit_follows_the_move_class_and_low_flying() -> void:
	var world: World = World.from_scenario(_scenario())
	assert_array(world.type_ids).is_equal([&"tank", &"jet", &"drone", &"depot"])
	assert_array(world.type_layer_bit).is_equal([1, 2, 4, 1])
	assert_array(world.type_move_class).is_equal([2, 3, 3, 0])  # A depot is a UnitDef: foot.
	# A type with no entry is padded as a ground row.
	var bare: World = World.new()
	bare.type_ids.append(&"padded")
	bare.prepare()
	assert_array(bare.type_layer_bit).is_equal([World.Layer.GROUND])


## A hand-built World with more types than definitions (and a weapon with no mask) is padded by
## prepare() with the named pad values, whatever test_world_v1 pins.
func test_prepare_pads_the_air_tables_of_a_hand_built_world_with_the_named_values() -> void:
	var world: World = World.new()
	for id: StringName in [&"a", &"b"]:
		world.type_ids.append(id)
	world.weapon_range.append(4000)
	world.prepare()
	assert_array(world.type_repair_period).is_equal(
		[World.TYPE_PAD_REPAIR_PERIOD, World.TYPE_PAD_REPAIR_PERIOD]
	)
	assert_array(world.type_pad_first).is_equal([0, 0])
	assert_array(world.type_pads).is_equal([0, 0])
	assert_array(world.type_layer_bit).is_equal([World.Layer.GROUND, World.Layer.GROUND])
	assert_array(world.weapon_targets).is_equal([World.Layer.GROUND])


func test_the_air_pad_and_repair_columns_are_copied_per_type() -> void:
	var world: World = World.from_scenario(_scenario())
	assert_array(world.type_ammo).is_equal([0, 6, 0, 0])
	assert_array(world.type_rearm_ticks).is_equal([0, 30, 0, 0])
	assert_array(world.type_pads).is_equal([0, 0, 0, 2])
	assert_array(world.type_upgrade).is_equal([-1, -1, -1, -1])
	assert_array(world.type_repair_classes).is_equal([0, 0, 0, 8])
	assert_array(world.type_repair_hp).is_equal([0, 0, 0, 10])
	assert_array(world.type_repair_period).is_equal([1, 1, 1, 15])
	assert_array(world.type_repair_cost_percent).is_equal([0, 0, 0, 40])
	assert_array(world.type_repair_reach).is_equal([0, 0, 0, 1500])
	assert_array(world.type_repair_slots).is_equal([0, 0, 0, 2])
	assert_array(world.type_repair_seek).is_equal([0, 0, 0, 4000])
	# The pad offsets sit in their own list, from `type_pad_first`: the depot's two pads, in order.
	assert_array(world.pad_offset_x).is_equal([0, 2])
	assert_array(world.pad_offset_y).is_equal([0, 1])
	assert_int(world.type_pad_first[3]).is_equal(0)
	for table: StringName in World.TYPE_ARRAYS:
		assert_int(world.get(table).size()).override_failure_message(table).is_equal(4)


func test_a_pad_list_is_found_from_the_first_entry_of_each_type() -> void:
	var second: BuildingDef = _depot(&"second", [Vector2i(1, 1)] as Array[Vector2i])
	var scenario: ScenarioDef = _scenario()
	scenario.roster.append(second)
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_pads).is_equal([0, 0, 0, 2, 1])
	assert_array(world.type_pad_first).is_equal([0, 0, 0, 0, 2])
	assert_array([world.pad_offset_x[2], world.pad_offset_y[2]]).is_equal([1, 1])


func test_a_row_starts_with_the_ammo_of_its_type() -> void:
	var world: World = World.from_scenario(_scenario())
	var jet: int = world.add_unit(1, 1, 3500, 1500)
	var tank: int = world.add_unit(1, 0, 3500, 500)
	assert_int(world.ammo[world.index_of(jet)]).is_equal(6)
	assert_int(world.ammo[world.index_of(tank)]).is_equal(0)
	assert_int(world.ammo.size()).is_equal(world.unit_count())
	# A type with no entry has no ammo, and the column still has a row.
	var bare: World = World.new()
	bare.add_unit(1, 0, 500, 500)
	assert_array(bare.ammo).is_equal([0])


func test_weapon_targets_are_copied_and_a_hand_built_weapon_hits_the_ground() -> void:
	var gun: WeaponDef = WeaponDef.new()
	gun.id = &"gun"
	var flak: WeaponDef = WeaponDef.new()
	flak.id = &"flak"
	flak.targets = 6
	var scenario: ScenarioDef = _scenario()
	scenario.roster[0].weapon = gun
	scenario.roster[1].weapon = flak
	var world: World = World.from_scenario(scenario)
	assert_array(world.weapon_ids).is_equal([&"gun", &"flak"])
	assert_array(world.weapon_targets).is_equal([1, 6])
	var by_hand: World = World.new()
	by_hand.weapon_range.append_array(PackedInt32Array([4000, 5000]))
	by_hand.prepare()
	assert_array(by_hand.weapon_targets).is_equal([1, 1])


func test_upgrades_load_once_by_id_in_faction_order_with_their_types() -> void:
	var scenario: ScenarioDef = _scenario()
	var faction: FactionDef = FactionDef.new()
	faction.id = &"fossil"
	faction.upgrades.append(
		_upgrade(&"bombs", UpgradeDef.Stat.DAMAGE_DEALT, 120, [scenario.roster[1]])
	)
	faction.upgrades.append(null)
	faction.upgrades.append(_upgrade(&"holes", 0, 105, [null, scenario.roster[0]]))
	faction.upgrades.append(_upgrade(&"bombs", 1, 50, []))  # The same id again: the first wins.
	var twin: FactionDef = FactionDef.new()
	twin.id = &"renew"
	var both: Array[UnitDef] = [scenario.roster[0], scenario.roster[1]]
	twin.upgrades.append(_upgrade(&"racks", UpgradeDef.Stat.AMMO, 2, both))
	scenario.factions.append(faction)
	scenario.factions.append(twin)
	var world: World = World.from_scenario(scenario)
	assert_array(world.upgrade_ids).is_equal([&"bombs", &"holes", &"racks"])
	assert_array(world.upgrade_stat).is_equal([0, 0, 2])
	assert_array(world.upgrade_value).is_equal([120, 105, 2])
	assert_array(world.upgrade_type_first).is_equal([0, 1, 2])
	# A null entry names no type and is not counted: "holes" changes the tank alone.
	assert_array(world.upgrade_type_count).is_equal([1, 1, 2])
	assert_array(world.upgrade_types).is_equal([1, 0, 0, 1])  # The jet; the tank; both.
	for player: int in range(1, world.player_count + 1):
		assert_int(world.upgrades[player]).is_equal(0)


func test_no_more_than_the_most_upgrades_are_loaded() -> void:
	var scenario: ScenarioDef = _scenario()
	var faction: FactionDef = FactionDef.new()
	for index: int in World.UPGRADES_MAX + 3:
		faction.upgrades.append(_upgrade(StringName("up%d" % index), 0, 110, []))
	scenario.factions.append(faction)
	var world: World = World.from_scenario(scenario)
	assert_int(world.upgrade_ids.size()).is_equal(World.UPGRADES_MAX)
	assert_int(world.upgrade_stat.size()).is_equal(World.UPGRADES_MAX)
	assert_int(world.upgrade_ids[World.UPGRADES_MAX - 1].length()).is_equal(4)  # "up29"


func test_the_player_arrays_start_at_zero_with_a_queue_for_each_of_the_five_tabs() -> void:
	var scenario: ScenarioDef = _scenario()
	scenario.player_count = 2
	var world: World = World.from_scenario(scenario)
	for column: StringName in [&"reveal_site", &"reveal", &"upgrades"]:
		assert_array(world.get(column)).override_failure_message(column).is_equal([0, 0, 0])
	assert_int(World.TABS).is_equal(5)
	assert_int(world.queue_count.size()).is_equal(3 * 5)
	assert_int(world.queue_type.size()).is_equal(3 * 5 * world.queue_slots)
	assert_int(world.rally_x.size()).is_equal(15)


## The AIR plane (class 3) is open grass whatever the terrain; the ground planes follow the map.
func test_the_air_plane_is_open_over_rock_and_the_ground_planes_are_not() -> void:
	var world: World = World.from_scenario(_scenario())
	var cells: int = world.map_cols * world.map_rows
	assert_int(world.move_cost.size()).is_equal(4 * cells)
	assert_int(world.terrain_cost.size()).is_equal(6)  # Two terrains of three ground classes.
	var wall: int = 4  # Column 4 of row 0.
	assert_array(Worlds.costs_at(world, wall)).is_equal([0, 0, 0])
	assert_int(Worlds.air_cost_at(world, wall)).is_equal(10)
	assert_bool(world.is_passable(wall, AIR)).is_true()
	assert_bool(world.is_passable(wall, FOOT)).is_false()
	for cell: int in cells:
		assert_int(Worlds.air_cost_at(world, cell)).is_equal(World.GRASS_COST)


func test_set_terrain_leaves_the_air_plane_alone() -> void:
	var world: World = World.from_scenario(_scenario())
	var grass: int = 0
	var rock: int = 1
	world.set_terrain(world.terrain.find(grass), rock)
	assert_array(Worlds.costs_at(world, 0)).is_equal([0, 0, 0])
	assert_int(Worlds.air_cost_at(world, 0)).is_equal(10)
	world.set_terrain(4, grass)  # The wall tile opens for the ground classes again.
	assert_array(Worlds.costs_at(world, 4)).is_equal([10, 10, 10])
	assert_int(Worlds.air_cost_at(world, 4)).is_equal(10)
	assert_int(world.map_version).is_equal(2)


## A footprint closes the ground planes and not the AIR plane, and its death restores the ground.
func test_a_building_closes_the_ground_planes_and_never_the_air_plane() -> void:
	var world: World = World.from_scenario(_scenario())
	var id: int = world.add_building(1, 3, 6, 0)  # The depot, 2 x 2 tiles at columns 6 and 7.
	assert_int(id).is_greater(0)
	for cell: int in [6, 7, 12 + 6, 12 + 7]:
		assert_array(Worlds.costs_at(world, cell)).is_equal([0, 0, 0])
		assert_int(Worlds.air_cost_at(world, cell)).is_equal(10)
	world.hp[world.index_of(id)] = 0
	world.remove_dead()
	for cell: int in [6, 7, 12 + 6, 12 + 7]:
		assert_array(Worlds.costs_at(world, cell)).is_equal([10, 10, 10])
		assert_int(Worlds.air_cost_at(world, cell)).is_equal(10)


func test_a_straight_line_is_always_clear_for_air_over_rock() -> void:
	var world: World = World.from_scenario(_scenario())
	assert_bool(FixedMath.line_clear(world, 500, 1500, 11500, 1500, FOOT)).is_false()
	assert_bool(FixedMath.line_clear(world, 500, 1500, 11500, 1500, AIR)).is_true()
	assert_bool(FixedMath.line_clear(world, 500, 500, 11500, 2500, AIR)).is_true()
	assert_bool(FixedMath.line_clear(world, 500, 500, 11500, 2500, 4)).is_false()  # No such class.


## Every layout number the ADR names moves the hash section it belongs to and no other.
func test_the_new_columns_move_their_own_hash_section_only() -> void:
	var base: World = _played_world()
	var jet: int = 2
	var row: World = _played_world()
	row.ammo[jet] += 1
	_assert_sections(base, row, ["ammo"])
	for column: StringName in [&"reveal_site", &"reveal", &"upgrades"]:
		var player: World = _played_world()
		player.get(column)[1] += 1
		_assert_sections(base, player, ["players"], String(column))
	# Derived and rule tables are not state: only defs_hash sees them.
	var defs: int = base.defs_hash()
	for table: StringName in World.TYPE_ARRAYS + World.PAD_ARRAYS + World.UPGRADE_ARRAYS:
		if table == &"type_names":  # The one string table; test_world_v1 covers it.
			continue
		var rules: World = _played_world()
		var column: PackedInt32Array = rules.get(table)
		if column.is_empty():
			column.append(1)
		else:
			column[0] += 1
		_assert_sections(base, rules, [], String(table))
		assert_int(rules.defs_hash()).override_failure_message(table).is_not_equal(defs)
	var targets: World = _played_world()
	targets.weapon_targets[0] += 1
	_assert_sections(base, targets, [], "weapon_targets")
	assert_int(targets.defs_hash()).is_not_equal(defs)
	var named: World = _played_world()
	named.upgrade_ids[0] = &"other"
	assert_int(named.defs_hash()).is_not_equal(defs)
	assert_int(_played_world().defs_hash()).is_equal(defs)
	assert_int(_played_world().state_hash()).is_equal(base.state_hash())


func test_player_view_and_snapshot_carry_the_layer_tables_as_copies() -> void:
	var world: World = _played_world()
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(view.type_layer_bit).is_equal([1, 2, 4, 1])
	assert_array(view.weapon_targets).is_equal([1, 6])
	view.type_layer_bit[0] = 99
	view.weapon_targets[0] = 99
	assert_array(world.type_layer_bit).is_equal([1, 2, 4, 1])
	assert_array(world.weapon_targets).is_equal([1, 6])
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.capture(world, null)
	assert_array(snap.type_layer_bit).is_equal([1, 2, 4, 1])
	assert_array(snap.weapon_targets).is_equal([1, 6])
	assert_array(PlayerView.of(world, 2).type_layer_bit).is_equal([1, 2, 4, 1])
	assert_int(PlayerView.TABS).is_equal(5)
	assert_int(view.queue_count.size()).is_equal(5)
	assert_int(view.queue_type.size()).is_equal(5 * world.queue_slots)


## An aircraft ordered across the wall flies straight over it, asks for no flow field and ends at
## its goal; the C++ kernels (FLOW configured with four classes, never an AIR key) and the
## GDScript twins end on one state hash.
func test_an_aircraft_crosses_rock_in_a_straight_line_under_both_implementations() -> void:
	var hashes: Array[int] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = World.from_scenario(_scenario(true), DetRandom.create(7, 0))
		assert_array(SimImpls.use(world, impl)).is_empty()
		assert_int(world.flow.classes).is_equal(4)
		var ids: PackedInt32Array = PackedInt32Array([world.unit_id[0]])
		var order: Command = Command.move(1, ids, 11500, 1500)
		order.tick = world.tick
		var first: Array[Command] = [order]
		Sim.step(world, first)
		for _tick: int in 220:
			Sim.step(world, [])
		assert_int(world.pos_x[0]).override_failure_message("impl %d" % impl).is_equal(11500)
		assert_int(world.pos_y[0]).is_equal(1500)
		assert_int(world.flow.requests).override_failure_message("impl %d" % impl).is_equal(0)
		assert_int(world.dropped_commands).is_equal(0)
		hashes.append(world.state_hash())
	assert_int(hashes[0]).is_equal(hashes[1])


func _scenario(with_jet_only: bool = false) -> ScenarioDef:
	var terrains: TerrainSetDef = TerrainSetDef.new()
	terrains.terrains.append(_terrain(".", [10, 10, 10]))
	terrains.terrains.append(_terrain("#", [0, 0, 0]))
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(WALL)
	map.terrain = terrains
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 1
	var tank: UnitDef = _unit(&"tank", World.MoveClass.TRACKED)
	var jet: UnitDef = _unit(&"jet", AIR)
	jet.ammo = 6
	jet.rearm_ticks = 30
	var drone: UnitDef = _unit(&"drone", AIR)
	drone.low_flying = true
	scenario.roster.append_array(
		[tank, jet, drone, _depot(&"depot", [Vector2i(0, 0), Vector2i(2, 1)])]
	)
	if with_jet_only:
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.unit = jet
		spawn.count = 1
		spawn.origin_tile = Vector2i(1, 1)
		scenario.spawns.append(spawn)
		scenario.roster.clear()
	return scenario


func _unit(id: StringName, move_class: int) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = id
	unit.speed = 100
	unit.radius = 300
	unit.sight_range = 3000
	unit.max_hp = 100
	unit.move_class = move_class
	return unit


func _depot(id: StringName, pads: Array[Vector2i]) -> BuildingDef:
	var depot: BuildingDef = BuildingDef.new()
	depot.type_id = id
	depot.footprint = Vector2i(2, 2)
	depot.armour = World.Armour.BUILDING
	depot.max_hp = 200
	depot.pads = pads.size()
	depot.pad_offsets = pads
	depot.repair_classes = 8
	depot.repair_hp = 10
	depot.repair_period_ticks = 15
	depot.repair_cost_percent = 40
	depot.repair_reach_milli = 1500
	depot.repair_slots = 2
	depot.repair_seek_milli = 4000
	return depot


func _upgrade(id: StringName, stat: int, value: int, types: Array[UnitDef]) -> UpgradeDef:
	var upgrade: UpgradeDef = UpgradeDef.new()
	upgrade.id = id
	upgrade.stat = stat
	upgrade.value = value
	upgrade.applies_to = types
	return upgrade


func _terrain(symbol: String, cost: Array[int]) -> TerrainDef:
	var terrain: TerrainDef = TerrainDef.new()
	terrain.symbol = symbol
	terrain.cost = PackedInt32Array(cost)
	return terrain


## A prepared world of the scenario with two players, a weapon of each kind and three rows (a tank,
## a jet with 6 shots and a drone), the state that the hash cases poke one value of.
func _played_world() -> World:
	var scenario: ScenarioDef = _scenario()
	scenario.player_count = 2
	var gun: WeaponDef = WeaponDef.new()
	gun.id = &"gun"
	var flak: WeaponDef = WeaponDef.new()
	flak.id = &"flak"
	flak.targets = 6
	scenario.roster[0].weapon = gun
	scenario.roster[1].weapon = flak
	var faction: FactionDef = FactionDef.new()
	faction.id = &"fossil"
	faction.upgrades.append(_upgrade(&"bombs", 0, 120, [scenario.roster[1]]))
	scenario.factions.append(faction)
	var world: World = World.from_scenario(scenario, DetRandom.create(1, 0))
	world.add_unit(1, 0, 500, 500)
	world.add_unit(2, 0, 1500, 1500)
	world.add_unit(1, 1, 2500, 500)
	return world


func _assert_sections(
	base: World, world: World, expected: Array[String], label: String = ""
) -> void:
	var names: PackedStringArray = World.hash_section_names()
	var before: PackedInt64Array = base.hash_parts()
	var parts: PackedInt64Array = world.hash_parts()
	var differing: Array[String] = []
	for i: int in names.size():
		if parts[i] != before[i]:
			differing.append(names[i])
	assert_array(differing).override_failure_message(label).is_equal(expected)
	var changed: bool = world.state_hash() != base.state_hash()
	assert_bool(changed).override_failure_message(label).is_equal(not expected.is_empty())
