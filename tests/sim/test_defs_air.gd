extends GdUnitTestSuite
## P231 (ADR 0036 section 2, ADR 0037 section 2): the script defaults, types and inspector hints of
## the air, repair-role and upgrade fields, as test_defs_v3 pins the strike fields. The rules these
## fields obey are in test_defs_data_air. The World copies none of them yet.


func test_unit_def_air_and_repair_defaults_leave_every_existing_type_unchanged() -> void:
	var unit: UnitDef = UnitDef.new()
	assert_bool(unit.low_flying).is_false()
	var numbers: Array[int] = [unit.ammo, unit.rearm_ticks, unit.repair_classes, unit.repair_hp]
	numbers.append_array([unit.repair_period_ticks, unit.repair_cost_percent])
	numbers.append_array([unit.repair_reach_milli, unit.repair_slots, unit.repair_seek_milli])
	# The period is 1, not 0, so a later `tick % period` never divides by zero.
	assert_array(numbers).is_equal([0, 0, 0, 0, 1, 0, 0, 0, 0])
	var types: Dictionary[String, int] = _types(unit)
	assert_int(types["low_flying"]).is_equal(TYPE_BOOL)
	for field: String in [
		"ammo", "rearm_ticks", "repair_classes", "repair_hp", "repair_seek_milli"
	]:
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_INT)
	for field: String in ["repair_period_ticks", "repair_cost_percent", "repair_reach_milli"]:
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_INT)
	assert_int(types["repair_slots"]).is_equal(TYPE_INT)
	assert_str(_hint_string(unit, "move_class")).is_equal("Foot,Wheeled,Tracked,Air")


func test_building_def_pads_default_to_none_and_the_offsets_are_typed_vector2i() -> void:
	var building: BuildingDef = BuildingDef.new()
	assert_int(building.pads).is_equal(0)
	assert_int(building.pad_offsets.size()).is_equal(0)
	assert_int(building.pad_offsets.get_typed_builtin()).is_equal(TYPE_VECTOR2I)
	var types: Dictionary[String, int] = _types(building)
	assert_int(types["pads"]).is_equal(TYPE_INT)
	assert_int(types["pad_offsets"]).is_equal(TYPE_ARRAY)
	assert_str(_hint_string(building, "pad_offsets")).is_equal("%d:" % TYPE_VECTOR2I)


func test_weapon_def_targets_default_to_ground_and_are_a_three_bit_flags_export() -> void:
	var weapon: WeaponDef = WeaponDef.new()
	assert_int(weapon.targets).is_equal(1)
	assert_int(_types(weapon)["targets"]).is_equal(TYPE_INT)
	assert_str(_hint_string(weapon, "targets")).is_equal("Ground:1,Air:2,Low air:4")


func test_upgrade_def_fields_defaults_types_and_hints() -> void:
	var up: UpgradeDef = UpgradeDef.new()
	var names: Array[String] = []
	var script_fields: Array[Dictionary] = up.get_property_list().filter(
		func(info: Dictionary) -> bool:
			return (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
	)
	for info: Dictionary in script_fields:
		names.append(String(info["name"]))
	assert_array(names).is_equal(
		[
			"id",
			"display_name",
			"faction",
			"cost",
			"research_ticks",
			"requires",
			"stat",
			"value",
			"applies_to"
		]
	)
	assert_array([up.cost, up.research_ticks, up.stat, up.value]).is_equal([0, 1, 0, 100])
	assert_object(up.requires).is_null()
	assert_int(up.applies_to.size()).is_equal(0)
	assert_int(up.applies_to.get_typed_builtin()).is_equal(TYPE_OBJECT)
	assert_str(String((up.applies_to.get_typed_script() as Script).get_global_name())).is_equal(
		"UnitDef"
	)
	assert_str(_hint_string(up, "requires")).is_equal("BuildingDef")
	assert_str(_hint_string(up, "stat")).is_equal("Damage dealt:0,Damage taken:1,Ammo:2")
	assert_int(UpgradeDef.Stat.DAMAGE_DEALT).is_equal(0)
	assert_int(UpgradeDef.Stat.DAMAGE_TAKEN).is_equal(1)
	assert_int(UpgradeDef.Stat.AMMO).is_equal(2)
	var types: Dictionary[String, int] = _types(up)
	for field: String in ["cost", "research_ticks", "stat", "value"]:
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_INT)
	for field: String in ["id", "faction"]:
		assert_int(types[field]).override_failure_message(field).is_equal(TYPE_STRING_NAME)


func test_faction_def_lists_upgrades_typed_and_empty_by_default() -> void:
	var faction: FactionDef = FactionDef.new()
	assert_int(faction.upgrades.size()).is_equal(0)
	assert_str(String((faction.upgrades.get_typed_script() as Script).get_global_name())).is_equal(
		"UpgradeDef"
	)


func test_terrain_cost_keeps_one_entry_per_ground_class() -> void:
	assert_int(TerrainDef.new().cost.size()).is_equal(3)
	var terrains: TerrainSetDef = load("res://data/terrain/standard.tres")
	assert_int(terrains.terrains.size()).is_greater(0)
	for terrain: TerrainDef in terrains.terrains:
		assert_int(terrain.cost.size()).is_equal(3)


func _types(object: Object) -> Dictionary[String, int]:
	var types: Dictionary[String, int] = {}
	for info: Dictionary in object.get_property_list():
		types[String(info["name"])] = int(info["type"])
	return types


func _hint_string(object: Object, property: String) -> String:
	for info: Dictionary in object.get_property_list():
		if info["name"] == property:
			return String(info["hint_string"])
	return "no such property: " + property
