extends GdUnitTestSuite
## Phase 2 data files (plan P27b): the starting numbers of ADRs 0007-0010 as literals, the rules
## every unit file keeps, and the link from every scenario to data/rules.tres. The perf arena map
## and scenario (P27c, ADR 0011 section 4) are pinned here too.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNITS_DIR: String = "res://data/units"
const SCENARIOS_DIR: String = "res://data/scenarios"
const WEAPONS_DIR: String = "res://data/weapons"
const RULES_PATH: String = "res://data/rules.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const ARENA_MAP_PATH: String = "res://data/maps/perf_arena.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## The 26 x 15 tile window of the fight, centred on tile (32, 32): columns 19..44, rows 25..39.
const WINDOW_TILES: Rect2i = Rect2i(19, 25, 26, 15)
## The same window in milli-tiles, for unit positions. It lies inside the window whether
## "centred on tile (32, 32)" means the corner or the centre of that tile.
const WINDOW_MIN: Vector2i = Vector2i(19500, 25000)
const WINDOW_MAX: Vector2i = Vector2i(45000, 39500)
const TRACKED: int = 2


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
	assert_array(files).contains(["res://data/scenarios/controls_test.tres", ARENA_PATH])
	for path: String in files:
		var scenario: ScenarioDef = load(path)
		var rules_path: String = (
			"no rules" if scenario.rules == null else scenario.rules.resource_path
		)
		assert_str(rules_path).override_failure_message(path).is_equal(RULES_PATH)


func test_the_perf_arena_map_is_64_by_64_with_a_ridge_three_gaps_and_scenery_in_the_window(
) -> void:
	var map: MapDef = load(ARENA_MAP_PATH)
	assert_array(map.validate()).is_empty()
	assert_that(map.size_tiles()).is_equal(Vector2i(64, 64))
	assert_str(map.terrain.resource_path).is_equal(TERRAIN_PATH)
	# The ridge is rock in columns 31 and 32 on every row but the gap rows, and rock nowhere else.
	var gap_rows: Array[int] = []
	var outside: Array[Vector2i] = []
	var water: int = 0
	var scrub_patches: int = 0
	for y: int in map.rows.size():
		var row: String = map.rows[y]
		if row.count("#") == 0:
			gap_rows.append(y)
			for x: int in [31, 32]:
				assert_int(_cost(map, x, y, TRACKED)).override_failure_message(str(y)).is_greater(0)
		else:
			assert_str(row.substr(31, 2)).override_failure_message(str(y)).is_equal("##")
			assert_int(row.count("#")).override_failure_message(str(y)).is_equal(2)
		for x: int in len(row):
			var symbol: String = row[x]
			if symbol != "." and symbol != "#" and not WINDOW_TILES.has_point(Vector2i(x, y)):
				outside.append(Vector2i(x, y))
			water += 1 if symbol == "~" else 0
			# A patch is counted once, at its first tile in reading order.
			if (
				symbol == "^"
				and (x == 0 or row[x - 1] != "^")
				and (y == 0 or map.rows[y - 1][x] != "^")
			):
				scrub_patches += 1
	assert_array(gap_rows).is_equal([26, 27, 31, 32, 33, 37, 38])
	assert_array(outside).is_empty()
	assert_int(water).is_greater(0)
	assert_int(scrub_patches).is_greater_equal(2)


@warning_ignore("integer_division")
func test_the_perf_arena_scenario_spawns_150_units_inside_the_window_on_open_ground() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH)
	assert_str(scenario.map.resource_path).is_equal(ARENA_MAP_PATH)
	assert_array(scenario.map.validate()).is_empty()
	assert_int(scenario.player_count).is_equal(2)
	assert_that(scenario.map_size_tiles).is_equal(Vector2i(64, 64))
	# owner, type, count, origin tile, columns, spacing, jitter. Player 1 is west of the ridge.
	var blocks: Array = []
	for spawn: SpawnDef in scenario.spawns:
		(
			blocks
			. append(
				[
					spawn.owner,
					String(spawn.unit.type_id),
					spawn.count,
					spawn.origin_tile,
					spawn.columns,
					spawn.spacing,
					spawn.jitter,
				]
			)
		)
	(
		assert_array(blocks)
		. is_equal(
			[
				[1, "light_tank", 30, Vector2i(25, 27), 3, 1000, 300],
				[1, "rifle_squad", 27, Vector2i(22, 28), 3, 1000, 300],
				[1, "rocket_squad", 18, Vector2i(20, 28), 2, 1000, 300],
				[2, "light_tank", 30, Vector2i(36, 27), 3, 1000, 300],
				[2, "rifle_squad", 27, Vector2i(39, 28), 3, 1000, 300],
				[2, "rocket_squad", 18, Vector2i(42, 28), 2, 1000, 300],
			]
		)
	)
	# Every unit, at each corner of its largest jitter, is inside the window, on its own side of
	# the ridge (columns 31-32, x 31000..33000) and on a tile its movement class can enter.
	var points: Array[Vector2i] = []
	var problems: Array[String] = []
	for spawn: SpawnDef in scenario.spawns:
		for k: int in spawn.count:
			var point: Vector2i = _grid_point(spawn, k)
			points.append(point)
			for sign_x: int in [-1, 1]:
				for sign_y: int in [-1, 1]:
					var at: Vector2i = point + Vector2i(sign_x, sign_y) * spawn.jitter
					var on_side: bool = at.x < 31000 if spawn.owner == 1 else at.x >= 33000
					var open: int = _cost(
						scenario.map, at.x / 1000, at.y / 1000, spawn.unit.move_class
					)
					if not _in_window(at) or not on_side or open <= 0:
						problems.append("%s unit %d at %s" % [spawn.unit.type_id, k, at])
	assert_int(points.size()).is_equal(150)
	assert_array(problems).is_empty()
	# Not even two maximum jitters bring two units onto one point.
	var touching: int = 0
	for i: int in points.size():
		for j: int in range(i + 1, points.size()):
			var apart: Vector2i = (points[i] - points[j]).abs()
			touching += 1 if apart.x <= 2 * 300 and apart.y <= 2 * 300 else 0
	assert_int(touching).is_equal(0)


func test_the_perf_arena_orders_send_each_side_to_the_centre_of_the_other() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH)
	var orders: Array = []
	for order: OrderDef in scenario.orders:
		orders.append([order.tick, order.player, order.type, order.target_tile])
	(
		assert_array(orders)
		. is_equal(
			[
				[0, 1, Command.Type.ATTACK_MOVE, Vector2i(39, 32)],
				[0, 2, Command.Type.ATTACK_MOVE, Vector2i(24, 32)],
			]
		)
	)
	for order: OrderDef in scenario.orders:
		var enemy_centre: Vector2i = _spawn_centre_tile(scenario, 3 - order.player)
		assert_that(order.target_tile).is_equal(enemy_centre)


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


## Where unit k of a block starts before jitter (the SpawnDef rule), in milli-tiles.
@warning_ignore("integer_division")
func _grid_point(spawn: SpawnDef, k: int) -> Vector2i:
	var columns: int = maxi(spawn.columns, 1)
	return Vector2i(
		spawn.origin_tile.x * 1000 + 500 + (k % columns) * spawn.spacing,
		spawn.origin_tile.y * 1000 + 500 + (k / columns) * spawn.spacing,
	)


## The tile of the mean start point of all units of `player`, before jitter.
@warning_ignore("integer_division")
func _spawn_centre_tile(scenario: ScenarioDef, player: int) -> Vector2i:
	var sum: Vector2i = Vector2i.ZERO
	var units: int = 0
	for spawn: SpawnDef in scenario.spawns:
		if spawn.owner != player:
			continue
		for k: int in spawn.count:
			sum += _grid_point(spawn, k)
			units += 1
	return sum / units / 1000


func _in_window(at: Vector2i) -> bool:
	return (
		at.x >= WINDOW_MIN.x
		and at.y >= WINDOW_MIN.y
		and at.x <= WINDOW_MAX.x
		and at.y <= WINDOW_MAX.y
	)


## The cost of tile (x, y) for a movement class, 0 = blocked; -1 for a symbol the set lacks.
func _cost(map: MapDef, x: int, y: int, move_class: int) -> int:
	for terrain: TerrainDef in map.terrain.terrains:
		if terrain.symbol == map.rows[y][x]:
			return terrain.cost[move_class]
	return -1


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
