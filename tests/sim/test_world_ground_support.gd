extends GdUnitTestSuite
## P285 (ADR 0037 sections 7, 8 and 11): the ground-support type tables (`type_carry_eject_percent`,
## `type_mine_weapon`, `type_mine_cost`, `type_mine_aware`, `type_detect_milli`), the weapon table
## `weapon_blast_milli` and the mine rules. All of them are rules: in `defs_hash`, never in the
## state hash. The rules that use them come with the mine rows (P286 and later).

const FOOT: int = World.MoveClass.FOOT


func test_the_tables_come_from_the_defs_and_the_mine_weapon_is_a_weapon_table_entry() -> void:
	var world: World = World.from_scenario(_scenario())
	assert_array(world.type_ids).is_equal([&"rifle", &"layer", &"carrier"])
	assert_array(world.type_mine_weapon).is_equal([-1, 0, -1])
	assert_array(world.type_mine_cost).is_equal([0, 60, 0])
	assert_array(world.type_mine_aware).is_equal([0, 1, 0])
	assert_array(world.type_detect_milli).is_equal([0, 3000, 0])
	assert_array(world.type_carry_eject_percent).is_equal([0, 0, 50])
	assert_array(world.weapon_ids).is_equal([&"shot_charge"])
	assert_array(world.weapon_blast_milli).is_equal([1000])
	assert_array(world.weapon_damage).is_equal([80])


func test_a_hand_built_world_pads_them_to_nothing_and_a_gun_has_no_blast() -> void:
	var bare: World = World.new()
	bare.type_ids.append_array([&"a", &"b"])
	bare.weapon_range.append(4000)
	bare.prepare()
	assert_array(bare.type_mine_weapon).is_equal([-1, -1])
	for table: PackedInt32Array in [
		bare.type_mine_cost,
		bare.type_mine_aware,
		bare.type_detect_milli,
		bare.type_carry_eject_percent
	]:
		assert_array(table).is_equal([0, 0])
	assert_array(bare.weapon_blast_milli).is_equal([0])


func test_the_mine_rules_default_inert_and_follow_the_scenario() -> void:
	var plain: World = World.from_scenario(ScenarioDef.new())
	assert_array([plain.mine_cap, plain.mine_lay_ticks, plain.mine_arm_ticks]).is_equal([0, 22, 15])
	assert_array([plain.sweep_ticks, plain.mine_known_cap]).is_equal([30, 24])
	var world: World = World.from_scenario(_scenario())
	assert_array([world.mine_cap, world.mine_lay_ticks, world.mine_arm_ticks]).is_equal([12, 5, 4])
	assert_array([world.sweep_ticks, world.mine_known_cap]).is_equal([6, 7])
	for rule: StringName in [
		&"mine_cap", &"mine_lay_ticks", &"mine_arm_ticks", &"sweep_ticks", &"mine_known_cap"
	]:
		assert_bool(World.RULE_SCALARS.has(rule)).override_failure_message(rule).is_true()
		assert_bool(World.UNHASHED_SCALARS.has(rule)).override_failure_message(rule).is_true()
		assert_bool(World.HASHED_SCALARS.has(rule)).override_failure_message(rule).is_false()


func test_every_new_value_moves_defs_hash_and_none_moves_the_state_hash() -> void:
	var base: World = World.from_scenario(_scenario())
	var state: int = base.state_hash()
	var defs: int = base.defs_hash()
	var edits: Array[Callable] = [
		func(w: World) -> void: w.type_carry_eject_percent[2] = 51,
		func(w: World) -> void: w.type_mine_weapon[1] = -1,
		func(w: World) -> void: w.type_mine_cost[1] = 61,
		func(w: World) -> void: w.type_mine_aware[1] = 0,
		func(w: World) -> void: w.type_detect_milli[1] = 2000,
		func(w: World) -> void: w.weapon_blast_milli[0] = 1500,
		func(w: World) -> void: w.mine_cap = 11,
		func(w: World) -> void: w.mine_lay_ticks = 6,
		func(w: World) -> void: w.mine_arm_ticks = 5,
		func(w: World) -> void: w.sweep_ticks = 7,
		func(w: World) -> void: w.mine_known_cap = 8,
	]
	for i: int in edits.size():
		var world: World = World.from_scenario(_scenario())
		edits[i].call(world)
		assert_int(world.state_hash()).override_failure_message("edit %d" % i).is_equal(state)
		assert_int(world.defs_hash()).override_failure_message("edit %d" % i).is_not_equal(defs)


## A rifle squad, a layer (a mine of 80 damage, blast 1000, 60 credits, mine-aware, detects 3000)
## and a carrier that ejects 50 percent, one row each, on a 12 x 3 grass map.
func _scenario() -> ScenarioDef:
	var terrains: TerrainSetDef = TerrainSetDef.new()
	var grass: TerrainDef = TerrainDef.new()
	grass.symbol = "."
	grass.cost = PackedInt32Array([10, 10, 10])
	terrains.terrains.append(grass)
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(["............", "............", "............"])
	map.terrain = terrains
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 1
	var rules: RulesDef = RulesDef.new()
	rules.passenger_cap = 4
	rules.mine_cap = 12
	rules.mine_lay_ticks = 5
	rules.mine_arm_ticks = 4
	rules.sweep_ticks = 6
	rules.mine_known_cap = 7
	scenario.rules = rules
	var rifle: UnitDef = _unit(&"rifle")
	var layer: UnitDef = _unit(&"layer")
	var mine: WeaponDef = WeaponDef.new()
	mine.id = &"shot_charge"
	mine.damage = 80
	mine.blast_milli = 1000
	layer.mine_weapon = mine
	layer.mine_cost = 60
	layer.mine_aware = true
	layer.detect_milli = 3000
	var carrier: UnitDef = _unit(&"carrier")
	carrier.carry_slots = 3
	carrier.carry_classes = 1
	carrier.carry_eject_percent = 50
	for unit: UnitDef in [rifle, layer, carrier]:
		scenario.roster.append(unit)
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.unit = unit
		spawn.count = 1
		spawn.origin_tile = Vector2i(1 + scenario.spawns.size() * 3, 1)
		scenario.spawns.append(spawn)
	return scenario


func _unit(id: StringName) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = id
	unit.speed = 100
	unit.radius = 300
	unit.sight_range = 3000
	unit.max_hp = 100
	unit.move_class = FOOT
	return unit
