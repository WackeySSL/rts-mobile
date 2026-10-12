extends GdUnitTestSuite
## Phase 2 definitions (plan P27a): the script defaults of the new Resources and fields, the 15
## RulesDef starting values, and MapDef.size_tiles() and validate(). World does not read the new
## fields yet, and the data files that fill them come with P27b.


func test_unit_def_defaults_are_an_unarmed_unit_that_does_not_spawn_dead() -> void:
	var unit: UnitDef = UnitDef.new()
	assert_int(unit.max_hp).is_equal(1)
	assert_str(unit.display_name).is_empty()
	assert_array([unit.armour, unit.move_class]).is_equal([0, 0])
	assert_array([unit.sight_range, unit.acquire_range]).is_equal([0, 0])
	assert_object(unit.weapon).is_null()


func test_armour_and_move_class_are_enum_exports_in_enum_order() -> void:
	var unit: UnitDef = UnitDef.new()
	assert_str(_enum_hint(unit, "armour")).is_equal("Infantry,Light,Heavy,Building")
	assert_str(_enum_hint(unit, "move_class")).is_equal("Foot,Wheeled,Tracked")


func test_weapon_def_defaults_deal_full_damage_to_every_armour_class() -> void:
	var weapon: WeaponDef = WeaponDef.new()
	assert_str(String(weapon.id)).is_empty()
	assert_array([weapon.range, weapon.min_range, weapon.damage]).is_equal([0, 0, 0])
	assert_array([weapon.cooldown_ticks, weapon.projectile_speed]).is_equal([1, 0])
	assert_int(weapon.vs_armour.size()).is_equal(4)
	assert_array(weapon.vs_armour).is_equal([100, 100, 100, 100])


func test_rules_def_has_exactly_the_fifteen_starting_ints() -> void:
	var expected: Dictionary[String, int] = {
		"retarget_period_ticks": 5,
		"fog_period_ticks": 3,
		"line_check_period_ticks": 5,
		"flow_cells_per_tick": 512,
		"flow_cache_size": 8,
		"separation_neighbours": 8,
		"separation_scan": 16,
		"separation_idle_share": 75,
		"separation_push_max": 60,
		"separation_coincident_divisor": 4,
		"stall_ticks": 15,
		"stall_range_spacings": 2,
		"attack_rekey_milli": 4000,
		"max_projectiles": 512,
		"max_rows": 256,
	}
	var rules: RulesDef = RulesDef.new()
	var fields: Array[String] = []
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			fields.append(String(info["name"]))
			assert_int(int(info["type"])).is_equal(TYPE_INT)
	assert_int(fields.size()).is_equal(15)
	assert_array(fields).contains_exactly_in_any_order(expected.keys())
	for field: String in expected:
		assert_that(rules.get(field)).override_failure_message(field).is_equal(expected[field])


func test_terrain_defs_default_to_normal_ground_for_all_three_move_classes() -> void:
	var terrain: TerrainDef = TerrainDef.new()
	assert_str(terrain.symbol).is_empty()
	assert_str(String(terrain.id)).is_empty()
	assert_int(terrain.cost.size()).is_equal(3)
	assert_array(terrain.cost).is_equal([10, 10, 10])
	assert_array(TerrainSetDef.new().terrains).is_empty()


func test_size_tiles_is_width_by_height_of_the_first_row_and_zero_without_rows() -> void:
	var map: MapDef = MapDef.new()
	assert_that(map.size_tiles()).is_equal(Vector2i.ZERO)
	map.rows = PackedStringArray(["..#", "~.."])
	assert_that(map.size_tiles()).is_equal(Vector2i(3, 2))
	map.rows = PackedStringArray([".", ".", ".", "."])
	assert_that(map.size_tiles()).is_equal(Vector2i(1, 4))


func test_validate_is_empty_for_a_valid_map_and_reports_a_null_terrain_by_index() -> void:
	var map: MapDef = _map(["..#", "~.:"])
	assert_array(map.validate()).is_empty()
	map.terrain.terrains.append(null)
	map.terrain.terrains.insert(1, null)
	assert_array(map.validate()).is_equal(["terrain 1 is null", "terrain 5 is null"])


func test_validate_reports_a_symbol_that_an_earlier_terrain_already_uses() -> void:
	var map: MapDef = _map(["..#", "~.:"])
	map.terrain.terrains.append(_terrain("#"))
	assert_array(map.validate()).is_equal(["terrain 4 repeats symbol '#'"])


func test_validate_reports_a_terrain_without_one_cost_per_move_class() -> void:
	var map: MapDef = _map(["..#", "~.:"])
	map.terrain.terrains[0].cost = PackedInt32Array([10])
	map.terrain.terrains[2].cost = PackedInt32Array([10, 10, 10, 10])
	map.terrain.terrains[3].cost = PackedInt32Array()
	(
		assert_array(map.validate())
		. is_equal(
			[
				"terrain 0 has 1 costs, expected 3",
				"terrain 2 has 4 costs, expected 3",
				"terrain 3 has 0 costs, expected 3",
			]
		)
	)


## World keeps a cost in a byte: 256 would read as blocked and -1 as 255. 0 and 40 are legal.
func test_validate_reports_a_cost_outside_0_to_40_by_terrain_and_entry() -> void:
	var map: MapDef = _map(["..#", "~.:"])
	map.terrain.terrains[0].cost = PackedInt32Array([0, 40, 41])
	map.terrain.terrains[2].cost = PackedInt32Array([-1, 10, 256])
	var problem: String = "terrain %d cost %d is %d, expected 0..40"
	assert_array(map.validate()).is_equal(
		[problem % [0, 2, 41], problem % [2, 0, -1], problem % [2, 2, 256]]
	)


func test_validate_reports_every_row_whose_length_differs_from_the_first() -> void:
	var map: MapDef = _map(["...", "..", "....", "..."])
	assert_array(map.validate()).is_equal(
		["row 1 has 2 tiles, expected 3", "row 2 has 4 tiles, expected 3"]
	)
	assert_array(_map(["...", "", "..."]).validate()).is_equal(["row 1 has 0 tiles, expected 3"])


func test_validate_reports_the_first_unknown_symbol_of_each_row() -> void:
	var map: MapDef = _map(["..?", ".x.", "?.x"])
	(
		assert_array(map.validate())
		. is_equal(
			[
				"row 0 column 2: unknown symbol '?'",
				"row 1 column 1: unknown symbol 'x'",
				"row 2 column 0: unknown symbol '?'",
			]
		)
	)


func test_validate_lists_a_wrong_length_row_and_its_unknown_symbol_separately() -> void:
	assert_array(_map(["...", "x"]).validate()).is_equal(
		["row 1 has 1 tiles, expected 3", "row 1 column 0: unknown symbol 'x'"]
	)
	assert_array(_map(["...", "...x"]).validate()).is_equal(
		["row 1 has 4 tiles, expected 3", "row 1 column 3: unknown symbol 'x'"]
	)


func test_validate_reports_a_missing_terrain_set_once_and_an_empty_map() -> void:
	var map: MapDef = _map(["...", "..."])
	map.terrain = null
	assert_array(map.validate()).is_equal(["map has no terrain set"])
	map.rows = PackedStringArray(["...", ".."])
	assert_array(map.validate()).is_equal(
		["map has no terrain set", "row 1 has 2 tiles, expected 3"]
	)
	map.rows = PackedStringArray()
	assert_array(map.validate()).is_equal(["map has no tiles", "map has no terrain set"])
	map.rows = PackedStringArray([""])
	assert_array(map.validate()).is_equal(["map has no tiles", "map has no terrain set"])


func test_an_empty_map_with_a_terrain_set_reports_only_that_it_has_no_tiles() -> void:
	assert_array(_map([]).validate()).is_equal(["map has no tiles"])


func test_scenario_and_spawn_defaults_keep_phase_1_scenarios_unchanged() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	assert_int(scenario.player_count).is_equal(0)
	assert_array(scenario.roster).is_empty()
	assert_array(scenario.orders).is_empty()
	assert_object(scenario.map).is_null()
	assert_object(scenario.rules).is_null()
	assert_int(SpawnDef.new().jitter).is_equal(0)


func test_order_def_defaults_to_an_attack_move_at_tick_0_for_no_player() -> void:
	var order: OrderDef = OrderDef.new()
	assert_array([order.tick, order.player, order.type]).is_equal([0, 0, 1])
	assert_that(order.target_tile).is_equal(Vector2i.ZERO)


func test_every_def_field_is_exported_so_a_resave_of_a_data_file_keeps_it() -> void:
	var defs: Array[Resource] = [
		UnitDef.new(),
		WeaponDef.new(),
		TerrainDef.new(),
		TerrainSetDef.new(),
		MapDef.new(),
		OrderDef.new(),
		ScenarioDef.new(),
		SpawnDef.new(),
		RulesDef.new(),
	]
	for def: Resource in defs:
		for info: Dictionary in def.get_property_list():
			if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				var stored: int = int(info["usage"]) & PROPERTY_USAGE_STORAGE
				assert_int(stored).override_failure_message(String(info["name"])).is_not_equal(0)


func test_resource_exports_keep_their_declared_types() -> void:
	var array_of: String = "%d/%d:" % [TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE]
	assert_str(_hint_string(UnitDef.new(), "weapon")).is_equal("WeaponDef")
	assert_str(_hint_string(MapDef.new(), "terrain")).is_equal("TerrainSetDef")
	assert_str(_hint_string(ScenarioDef.new(), "map")).is_equal("MapDef")
	assert_str(_hint_string(ScenarioDef.new(), "rules")).is_equal("RulesDef")
	assert_str(_hint_string(TerrainSetDef.new(), "terrains")).is_equal(array_of + "TerrainDef")
	assert_str(_hint_string(ScenarioDef.new(), "orders")).is_equal(array_of + "OrderDef")
	assert_str(_hint_string(ScenarioDef.new(), "roster")).is_equal(array_of + "UnitDef")


func _terrain(symbol: String) -> TerrainDef:
	var terrain: TerrainDef = TerrainDef.new()
	terrain.symbol = symbol
	return terrain


func _map(rows: Array[String]) -> MapDef:
	var terrains: TerrainSetDef = TerrainSetDef.new()
	for symbol: String in [".", ":", "#", "~"]:
		terrains.terrains.append(_terrain(symbol))
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(rows)
	map.terrain = terrains
	return map


func _enum_hint(object: Object, property: String) -> String:
	for info: Dictionary in object.get_property_list():
		if info["name"] == property:
			assert_int(int(info["hint"])).is_equal(PROPERTY_HINT_ENUM)
			return String(info["hint_string"])
	return "no such property: " + property


func _hint_string(object: Object, property: String) -> String:
	for info: Dictionary in object.get_property_list():
		if info["name"] == property:
			return String(info["hint_string"])
	return "no such property: " + property
