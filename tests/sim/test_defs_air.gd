extends GdUnitTestSuite
## P231 (ADR 0036 section 2, ADR 0037 section 2): the air, repair and upgrade defs and the data-test
## rules that go with them. The rules are pinned on built defs, so they hold before any air data
## ships, and the shipped files are checked against them. The World copies none of it yet.

const UNITS_DIR: String = "res://data/units"
const WEAPONS_DIR: String = "res://data/weapons"
const FACTIONS_DIR: String = "res://data/factions"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const AIR: int = 3
const FLIGHT: int = 3


func _air(ammo: int = 0, rearm: int = 0) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = &"jet"
	def.move_class = AIR
	def.ammo = ammo
	def.rearm_ticks = rearm
	return def


func _airfield(offsets: Array[Vector2i]) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = &"field"
	def.footprint = Vector2i(3, 3)
	def.pads = offsets.size()
	def.pad_offsets = offsets
	def.repair_classes = 8
	def.repair_hp = 10
	def.repair_reach_milli = 1500
	return def


func test_the_new_defaults_leave_every_existing_def_valid() -> void:
	assert_array(UnitDef.new().validate()).is_empty()
	assert_array(BuildingDef.new().validate_building(0)).is_empty()
	assert_int(WeaponDef.new().targets).is_equal(1)
	assert_array(WeaponDef.new().validate()).is_empty()
	assert_int(FactionDef.new().upgrades.size()).is_equal(0)


func test_air_only_fields_are_refused_on_ground_types() -> void:
	assert_array(_air(6, 30).validate()).is_empty()
	var low: UnitDef = _air()
	low.low_flying = true
	assert_array(low.validate()).is_empty()
	for field: String in ["low_flying", "ammo", "rearm_ticks"]:
		var ground: UnitDef = UnitDef.new()
		ground.set(field, true if field == "low_flying" else 5)
		ground.rearm_ticks = 5
		assert_int(ground.validate().size()).is_equal(1)
	assert_int(_air(6, 0).validate().size()).is_equal(1)
	assert_int(_air(-1, 5).validate().size()).is_equal(1)


func test_the_repair_role_needs_reach_of_at_least_500_and_bounded_slots() -> void:
	var healer: UnitDef = UnitDef.new()
	healer.repair_classes = 1
	healer.repair_hp = 5
	healer.repair_reach_milli = 500
	healer.repair_slots = 1
	assert_array(healer.validate()).is_empty()
	healer.repair_reach_milli = 499
	assert_int(healer.validate().size()).is_equal(1)
	healer.repair_reach_milli = 500
	healer.repair_slots = 9
	assert_int(healer.validate().size()).is_equal(1)
	healer.repair_slots = 8
	healer.repair_seek_milli = -1
	assert_int(healer.validate().size()).is_equal(1)


func test_pads_lie_at_least_the_largest_flight_spacing_apart() -> void:
	# Pads one tile apart suit a spacing of 1000 and fail 1001; pads must also be in the footprint.
	var field: BuildingDef = _airfield([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_array(field.validate_building(1000)).is_empty()
	assert_int(field.validate_building(1001).size()).is_equal(1)
	field.pad_offsets = [Vector2i(0, 0), Vector2i(3, 0)] as Array[Vector2i]
	assert_int(field.validate_building(1000).size()).is_equal(1)
	field.pads = 1
	assert_int(field.validate_building(1000).size()).is_equal(2)


func test_a_building_without_pads_needs_repair_slots_and_a_reveal_building_no_strike() -> void:
	var shed: BuildingDef = _airfield([] as Array[Vector2i])
	assert_int(shed.validate_building(0).size()).is_equal(1)
	shed.repair_slots = 2
	assert_array(shed.validate_building(0)).is_empty()
	var sat: BuildingDef = BuildingDef.new()
	sat.strike_kind = 3
	sat.charge_ticks = 900
	assert_array(sat.validate_building(0)).is_empty()
	sat.strike_radius = 1
	assert_int(sat.validate_building(0).size()).is_equal(1)


func test_weapon_targets_allow_1_to_7() -> void:
	var weapon: WeaponDef = WeaponDef.new()
	for mask: int in [0, 8]:
		weapon.targets = mask
		assert_int(weapon.validate().size()).is_equal(1)
	for mask: int in range(1, 8):
		weapon.targets = mask
		assert_array(weapon.validate()).is_empty()


func test_upgrade_modifiers_stop_at_400_percent() -> void:
	var up: UpgradeDef = UpgradeDef.new()
	up.id = &"better_bombs"
	up.requires = BuildingDef.new()
	up.applies_to = [UnitDef.new()] as Array[UnitDef]
	for stat: int in [UpgradeDef.DAMAGE_DEALT, UpgradeDef.DAMAGE_TAKEN]:
		up.stat = stat
		up.value = 400
		assert_array(up.validate()).is_empty()
		up.value = 401
		assert_int(up.validate().size()).is_equal(1)
		up.value = 0
		assert_int(up.validate().size()).is_equal(1)
	up.stat = UpgradeDef.AMMO
	up.value = 2
	assert_array(up.validate()).is_empty()
	up.value = 0
	assert_int(up.validate().size()).is_equal(1)
	up.value = 2
	up.applies_to = [] as Array[UnitDef]
	assert_int(up.validate().size()).is_equal(1)


func test_every_shipped_file_keeps_the_rules_and_terrain_cost_keeps_three_entries() -> void:
	var units: Array[UnitDef] = []
	for file: String in DirAccess.get_files_at(UNITS_DIR):
		if file.ends_with(".tres"):
			units.append(load(UNITS_DIR.path_join(file)))
	var spacing: int = 0
	for def: UnitDef in units:
		if def.tab == FLIGHT:
			spacing = maxi(spacing, def.formation_spacing)
	for def: UnitDef in units:
		var faults: PackedStringArray = (
			def.validate_building(spacing) if def is BuildingDef else def.validate()
		)
		assert_array(faults).is_empty()
	for file: String in DirAccess.get_files_at(WEAPONS_DIR):
		if file.ends_with(".tres"):
			assert_array((load(WEAPONS_DIR.path_join(file)) as WeaponDef).validate()).is_empty()
	for file: String in DirAccess.get_files_at(FACTIONS_DIR):
		if file.ends_with(".tres"):
			for up: UpgradeDef in (load(FACTIONS_DIR.path_join(file)) as FactionDef).upgrades:
				assert_array(up.validate()).is_empty()
	for terrain: TerrainDef in (load(TERRAIN_PATH) as TerrainSetDef).terrains:
		assert_int(terrain.cost.size()).is_equal(3)
