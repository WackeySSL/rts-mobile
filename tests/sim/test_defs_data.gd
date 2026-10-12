extends GdUnitTestSuite
## Phase 2 data files (plan P27b): the starting numbers of ADRs 0007-0010 as literals, the rules
## every unit file keeps, and the link from every scenario to data/rules.tres. The perf arena map
## and scenario are a separate data PR (P27c) and get their cases there.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units"
const SCENARIOS_DIR: String = "res://data/scenarios"
const WEAPONS_DIR: String = "res://data/weapons"
const RULES_PATH: String = "res://data/rules.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"


func test_unit_files_hold_the_adr_0009_starting_stats() -> void:
	# speed, radius, selection_radius, formation_spacing, max_hp, armour (0 infantry, 1 light),
	# move_class (0 foot, 2 tracked), sight_range, acquire_range.
	assert_array(_unit_row("light_tank")).is_equal([120, 400, 500, 1200, 300, 1, 2, 7000, 5500])
	assert_array(_unit_row("rifle_squad")).is_equal([67, 300, 350, 900, 100, 0, 0, 6000, 5000])
	assert_array(_unit_row("rocket_squad")).is_equal([60, 300, 350, 900, 90, 0, 0, 6000, 5500])
	assert_array(_unit_label("light_tank")).is_equal(["Light Tank", "tank_cannon"])
	assert_array(_unit_label("rifle_squad")).is_equal(["Rifle Squad", "rifle"])
	assert_array(_unit_label("rocket_squad")).is_equal(["Rocket Squad", "rocket"])


func test_weapon_files_hold_the_adr_0009_starting_stats() -> void:
	# id, range, min_range, damage, cooldown_ticks, projectile_speed (0 = hitscan), then the
	# percent of damage against infantry, light, heavy and building armour.
	assert_array(_weapon_row("tank_cannon")).is_equal(
		["tank_cannon", 4500, 0, 30, 25, 600, [70, 60, 35, 40]]
	)
	assert_array(_weapon_row("rifle")).is_equal(["rifle", 4000, 0, 12, 15, 0, [100, 10, 5, 5]])
	assert_array(_weapon_row("rocket")).is_equal(
		["rocket", 5000, 0, 50, 45, 300, [20, 100, 100, 80]]
	)


func test_the_standard_terrain_set_is_grass_sand_scrub_rock_water_in_that_order() -> void:
	# symbol, id, then the cost for foot, wheeled and tracked. Scrub is the foot-only ground.
	var terrains: TerrainSetDef = load(TERRAIN_PATH)
	var rows: Array = []
	for terrain: TerrainDef in terrains.terrains:
		rows.append([terrain.symbol, String(terrain.id)] + Array(terrain.cost))
	(
		assert_array(rows)
		. is_equal(
			[
				[".", "grass", 10, 10, 10],
				[":", "sand", 10, 10, 10],
				["^", "scrub", 10, 0, 0],
				["#", "rock", 0, 0, 0],
				["~", "water", 0, 0, 0],
			]
		)
	)


func test_rules_file_holds_the_fifteen_starting_ints_and_the_script_defaults_equal_it() -> void:
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
	var rules: RulesDef = load(RULES_PATH)
	var defaults: RulesDef = RulesDef.new()
	var fields: Array[String] = []
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			fields.append(String(info["name"]))
	assert_array(fields).contains_exactly_in_any_order(expected.keys())
	for field: String in expected:
		assert_that(rules.get(field)).override_failure_message(field).is_equal(expected[field])
		assert_that(defaults.get(field)).override_failure_message(field).is_equal(rules.get(field))


func test_every_unit_file_keeps_its_ranges_ordered_and_its_numbers_in_bounds() -> void:
	var units: Array[UnitDef] = []
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		units.append(load(path))
	assert_int(units.size()).is_greater_equal(3)
	assert_array(_catalog_problems(units)).is_empty()


func test_the_catalog_checks_report_a_reused_type_id_weapon_id_and_a_wrong_weapon_name() -> void:
	var first: UnitDef = _fine_unit()
	var copy: UnitDef = _fine_unit()
	first.resource_path = UNITS_DIR + "/tank.tres"
	copy.resource_path = UNITS_DIR + "/copy/tank.tres"
	first.weapon.resource_path = WEAPONS_DIR + "/tank.tres"
	copy.weapon = first.weapon  # Two units may share one weapon file.
	var type_twice: String = "tank.tres: type_id tank is used twice"
	assert_array(_catalog_problems([first, copy])).is_equal([type_twice])
	copy.weapon = _fine_unit().weapon  # A second weapon file with the same id.
	copy.weapon.resource_path = WEAPONS_DIR + "/copy/tank.tres"
	var weapon_twice: String = "tank.tres: weapon id tank is used twice"
	assert_array(_catalog_problems([first, copy])).is_equal([type_twice, weapon_twice])
	first.weapon.id = &"gun"
	var wrong_name: String = "tank.tres: weapon id gun differs from its file name"
	assert_array(_catalog_problems([first, copy])).is_equal([wrong_name, type_twice])


func test_every_rule_accepts_its_edge_values_and_reports_the_next_ones() -> void:
	# Property path from a unit, values that pass, values that fail, and the rule they break.
	var rows: Array = [
		["type_id", [], [&"other"], "type_id differs from the file name"],
		["max_hp", [1], [0], "max_hp is below 1"],
		["radius", [1, 500], [0, 501], "radius is not in 1..500"],
		["speed", [0, 2], [-1, 1], "speed is neither 0 nor at least 2"],
		["armour", [0, 3], [-1, 4], "armour is not an armour class"],
		["move_class", [0, 2], [-1, 3], "move_class is not a movement class"],
		["acquire_range", [5000, 6000], [6001], "acquire_range is above sight_range"],
		["weapon:range", [4000, 5000], [5001], "weapon range is above acquire_range"],
		["weapon:damage", [1], [0], "damage is below 1"],
		["weapon:cooldown_ticks", [1], [0], "cooldown_ticks is below 1"],
		["weapon:min_range", [0, 4000], [-1, 4001], "min_range is not in 0..range"],
		["weapon:projectile_speed", [0, 1], [-1], "projectile_speed is negative"],
		[
			"weapon:vs_armour",
			[[0, 200, 0, 200]],
			[[1, 1, 1], [1, 1, 1, 1, 1], [100, 201, 100, 100], [-1, 100, 100, 100]],
			"vs_armour is not 4 percents in 0..200",
		],
	]
	for row: Array in rows:
		for value: Variant in row[1] + row[2]:
			var unit: UnitDef = _fine_unit()
			unit.set_indexed(row[0], PackedInt32Array(value) if value is Array else value)
			var got: PackedStringArray = _unit_problems("tank.tres", unit)
			var want: Array = [] if row[1].has(value) else ["tank.tres: " + row[3]]
			assert_array(got).override_failure_message("%s = %s" % [row[0], value]).is_equal(want)
	var unarmed: UnitDef = _fine_unit()
	unarmed.weapon = null
	assert_array(_unit_problems("tank.tres", unarmed)).is_empty()


func test_every_scenario_file_sets_the_shared_rules_resource() -> void:
	var files: Array[String] = FileScan.list_files(SCENARIOS_DIR, ".tres")
	assert_array(files).contains(["res://data/scenarios/controls_test.tres"])
	for path: String in files:
		var scenario: ScenarioDef = load(path)
		var rules_path: String = (
			"no rules" if scenario.rules == null else scenario.rules.resource_path
		)
		assert_str(rules_path).override_failure_message(path).is_equal(RULES_PATH)


## The rules of every unit file, and the ones that span files: a type_id used once, and a weapon id
## that equals its file name and belongs to one file. Two units may share one weapon file. Only
## weapons linked from a unit are checked, as the sim reaches weapons through units alone.
func _catalog_problems(units: Array[UnitDef]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var type_ids: Dictionary[String, bool] = {}
	var weapon_files: Dictionary[String, String] = {}
	for unit: UnitDef in units:
		var file: String = unit.resource_path.get_file()
		problems.append_array(_unit_problems(file, unit))
		if type_ids.has(String(unit.type_id)):
			problems.append("%s: type_id %s is used twice" % [file, unit.type_id])
		type_ids[String(unit.type_id)] = true
		if unit.weapon == null:
			continue
		var weapon_id: String = String(unit.weapon.id)
		var weapon_path: String = unit.weapon.resource_path
		if weapon_id != weapon_path.get_file().get_basename():
			problems.append("%s: weapon id %s differs from its file name" % [file, weapon_id])
		if weapon_files.get(weapon_id, weapon_path) != weapon_path:
			problems.append("%s: weapon id %s is used twice" % [file, weapon_id])
		weapon_files[weapon_id] = weapon_path
	return problems


## One text per broken rule of a unit file and its weapon; empty when the file is fine.
func _unit_problems(file: String, unit: UnitDef) -> PackedStringArray:
	var broken: Dictionary[String, bool] = {
		"type_id differs from the file name": String(unit.type_id) != file.get_basename(),
		"max_hp is below 1": unit.max_hp < 1,
		# The 1-tile separation grid finds contact pairs only when every radius is at most 500.
		"radius is not in 1..500": unit.radius < 1 or unit.radius > 500,
		"speed is neither 0 nor at least 2": unit.speed < 0 or unit.speed == 1,
		"armour is not an armour class": unit.armour < 0 or unit.armour > 3,
		"move_class is not a movement class": unit.move_class < 0 or unit.move_class > 2,
		"acquire_range is above sight_range": unit.acquire_range > unit.sight_range,
	}
	var weapon: WeaponDef = unit.weapon
	if weapon != null:
		var percents: Array = Array(weapon.vs_armour)
		broken["weapon range is above acquire_range"] = weapon.range > unit.acquire_range
		broken["damage is below 1"] = weapon.damage < 1
		broken["cooldown_ticks is below 1"] = weapon.cooldown_ticks < 1
		# A min_range above range leaves no distance to fire from. Speed 0 is hitscan.
		broken["min_range is not in 0..range"] = (
			weapon.min_range < 0 or weapon.min_range > weapon.range
		)
		broken["projectile_speed is negative"] = weapon.projectile_speed < 0
		broken["vs_armour is not 4 percents in 0..200"] = (
			percents.size() != 4 or percents.min() < 0 or percents.max() > 200
		)
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("%s: %s" % [file, message])
	return problems


## A unit that breaks no rule when its file is tank.tres. Its weapon has the default percents.
func _fine_unit() -> UnitDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = &"tank"
	weapon.range = 4000
	weapon.damage = 1
	var unit: UnitDef = UnitDef.new()
	unit.type_id = &"tank"
	unit.radius = 300
	unit.sight_range = 6000
	unit.acquire_range = 5000
	unit.weapon = weapon
	return unit


func _unit_row(name: String) -> Array:
	var unit: UnitDef = load("%s/%s.tres" % [UNITS_DIR, name])
	if unit == null:
		return ["missing unit: " + name]
	return [
		unit.speed,
		unit.radius,
		unit.selection_radius,
		unit.formation_spacing,
		unit.max_hp,
		unit.armour,
		unit.move_class,
		unit.sight_range,
		unit.acquire_range,
	]


func _unit_label(name: String) -> Array:
	var unit: UnitDef = load("%s/%s.tres" % [UNITS_DIR, name])
	if unit == null or unit.weapon == null:
		return ["missing unit or weapon: " + name]
	return [unit.display_name, String(unit.weapon.id)]


func _weapon_row(name: String) -> Array:
	var weapon: WeaponDef = load("%s/%s.tres" % [WEAPONS_DIR, name])
	if weapon == null:
		return ["missing weapon: " + name]
	return [
		String(weapon.id),
		weapon.range,
		weapon.min_range,
		weapon.damage,
		weapon.cooldown_ticks,
		weapon.projectile_speed,
		Array(weapon.vs_armour),
	]
