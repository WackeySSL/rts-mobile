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
## The same window in milli-tiles, for unit positions: the camera centres on the middle of tile
## (32, 32) (main_view.gd adds 0.5), which gives x 19500..45500 and y 25000..40000. The maxima
## are kept 500 inside that, so a unit also stays in the window for a camera on the tile corner.
const WINDOW_MIN: Vector2i = Vector2i(19500, 25000)
const WINDOW_MAX: Vector2i = Vector2i(45000, 39500)
## The movement classes of the unit files (World.MoveClass from P29a).
const FOOT: int = 0
const TRACKED: int = 2
## The farthest ring cell of a 3x3 footprint from its centre: sqrt(8) tiles, rounded up.
const RING_CORNER_MILLI: int = 2829
## Phase 3 is a two-player game (ADR 0018 section 9 sizes the caps for it).
const PLAYERS: int = 2


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


func test_the_standard_terrain_set_is_grass_sand_scrub_rock_water_ore_in_that_order() -> void:
	# symbol, id, the cost for foot, wheeled and tracked, then whether a building may stand there
	# (grass and sand only; ore is passable for every class and not buildable, ADR 0018 section 2).
	# Scrub is the foot-only ground.
	var terrains: TerrainSetDef = load(TERRAIN_PATH)
	var rows: Array = []
	for terrain: TerrainDef in terrains.terrains:
		rows.append(
			[terrain.symbol, String(terrain.id)] + Array(terrain.cost) + [terrain.buildable]
		)
	(
		assert_array(rows)
		. is_equal(
			[
				[".", "grass", 10, 10, 10, true],
				[":", "sand", 10, 10, 10, true],
				["^", "scrub", 10, 0, 0, false],
				["#", "rock", 0, 0, 0, false],
				["~", "water", 0, 0, 0, false],
				["o", "ore", 10, 10, 10, false],
			]
		)
	)


func test_rules_file_holds_the_thirty_three_starting_ints_and_the_script_defaults_equal_it(
) -> void:
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
		# Phase 3 (ADR 0018 section 9).
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


func test_the_rules_file_keeps_the_phase_3_numbers_in_bounds() -> void:
	assert_array(_rule_problems(load(RULES_PATH))).is_empty()


func test_every_phase_3_rule_accepts_its_edge_values_and_reports_the_next_ones() -> void:
	# Property of RulesDef, values that pass, values that fail, and the rule they break.
	var fit: String = "unit_cap and building_cap of 2 players do not fit max_rows"
	var below_1: String = "%s is below 1"
	var rows: Array = [
		["start_credits", [0, 1], [-1], "start_credits is negative"],
		["ore_start", [0, 20], [-1, 21], "ore_start is not in 0..ore_cell_max"],
		["ore_cell_max", [20, 21], [19, -1], "ore_start is not in 0..ore_cell_max"],
		["credits_per_ore", [1], [0, -1], below_1 % "credits_per_ore"],
		["ore_regrow_ticks", [1], [0], below_1 % "ore_regrow_ticks"],
		["harvest_ticks_per_ore", [1], [0], below_1 % "harvest_ticks_per_ore"],
		["unload_ticks_per_ore", [1], [0], below_1 % "unload_ticks_per_ore"],
		["harvest_retry_ticks", [1], [0], below_1 % "harvest_retry_ticks"],
		["queue_slots", [1], [0], below_1 % "queue_slots"],
		["harvest_resume_ticks", [0, 1], [-1], "harvest_resume_ticks is negative"],
		["low_power_percent", [0, 100], [-1, 101], "low_power_percent is not in 0..100"],
		["harvest_reach_milli", [0], [-1], "a reach is negative"],
		["dock_reach_milli", [0], [-1], "a reach is negative"],
		["harvest_pick_milli", [0], [-1], "a reach is negative"],
		["build_reach_tiles", [0], [-1], "a reach is negative"],
		["unit_cap", [0, 88], [89], fit],
		["building_cap", [0, 53], [54], fit],
		["max_rows", [230, 256], [229], fit],
		["unit_cap", [], [-1], "a cap is negative"],
		["ghost_cap", [0], [-1], "a cap is negative"],
	]
	for row: Array in rows:
		for value: int in row[1] + row[2]:
			var rules: RulesDef = RulesDef.new()
			rules.set(row[0], value)
			var want: Array = [] if row[1].has(value) else ["rules: " + row[3]]
			var got: PackedStringArray = _rule_problems(rules)
			assert_array(got).override_failure_message("%s = %d" % [row[0], value]).is_equal(want)


## Every weapon reaches the ring corner of a 3x3 building from its centre, so the approach point of
## an ATTACK on a building (ADR 0017 section 1) is always within range.
func test_every_weapon_file_reaches_the_ring_corner_of_a_three_by_three_building() -> void:
	var files: Array[String] = FileScan.list_files(WEAPONS_DIR, ".tres")
	assert_int(files.size()).is_greater_equal(3)
	for path: String in files:
		var weapon: WeaponDef = load(path)
		assert_int(weapon.range).override_failure_message(path).is_greater_equal(RING_CORNER_MILLI)


## The Phase 3 rules of every unit file, buildings included; empty today because no building file
## exists yet (plan row P72 adds the roster and its exact numbers).
func test_every_unit_file_keeps_the_phase_3_rules() -> void:
	var rules: RulesDef = load(RULES_PATH)
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var unit: UnitDef = load(path)
		var file: String = path.get_file()
		assert_array(_economy_problems(file, unit, rules)).is_empty()


func test_the_phase_3_unit_and_building_rules_accept_their_edge_values_and_report_the_next(
) -> void:
	# Property path from a building, values that pass, values that fail, and the rule they break.
	var foot: String = "footprint is not 1..3"
	var rows: Array = [
		["cost", [0, 1], [-1], "cost is negative"],
		["build_ticks", [0, 1], [-1], "build_ticks is negative"],
		["tab", [-1, 0, 2], [-2, 3], "tab is not -1..2"],
		["harvest_capacity", [0, 25, 500], [-25, 1, 510], "harvest_capacity is not a multiple"],
		["speed", [0], [2], "speed is not 0"],
		["radius", [0], [1], "radius is not 0"],
		["armour", [3], [0, 2], "armour is not Building"],
		["footprint", [Vector2i(1, 1), Vector2i(3, 3)], [Vector2i(0, 1), Vector2i(1, 0)], foot],
		["footprint", [], [Vector2i(1, 4), Vector2i(4, 1), Vector2i(-1, 2)], foot],
		["produces", [-1, 0, 2], [-2, 3], "produces is not -1..2"],
	]
	for row: Array in rows:
		for value: Variant in row[1] + row[2]:
			var building: BuildingDef = _fine_building()
			building.set_indexed(row[0], value)
			var got: PackedStringArray = _economy_problems("depot.tres", building, RulesDef.new())
			var want: Array = [] if row[1].has(value) else ["depot.tres: " + row[3]]
			assert_array(got).override_failure_message("%s = %s" % [row[0], value]).is_equal(want)
	var unit: UnitDef = _fine_building()
	unit.requires = unit
	var got_self: PackedStringArray = _economy_problems("depot.tres", unit, RulesDef.new())
	assert_array(got_self).is_equal(["depot.tres: requires is the unit itself"])
	unit.requires = null  # A reference cycle would never be freed.
	# A plain unit is not held to the building rules: a mobile unit has speed and a radius.
	var tank: UnitDef = _fine_unit()
	tank.speed = 120
	assert_array(_economy_problems("tank.tres", tank, RulesDef.new())).is_empty()


## from_scenario swaps a map that fails validate() for open grass without a message (gdUnit4
## fails a test on a push_error), so the map check here is what catches a typo in a shipped map.
func test_every_scenario_file_sets_the_shared_rules_resource_and_has_a_valid_map() -> void:
	var files: Array[String] = FileScan.list_files(SCENARIOS_DIR, ".tres")
	assert_array(files).contains(["res://data/scenarios/controls_test.tres", ARENA_PATH])
	for path: String in files:
		var scenario: ScenarioDef = load(path)
		var rules_path: String = (
			"no rules" if scenario.rules == null else scenario.rules.resource_path
		)
		assert_str(rules_path).override_failure_message(path).is_equal(RULES_PATH)
		if scenario.map != null:
			assert_array(scenario.map.validate()).override_failure_message(path).is_empty()


## What World.from_scenario takes on trust from a scenario file: every grid point inside the map and
## on ground its class may enter (the jitter fallback is the grid point), a jitter in 0..8000 (the
## spawn draws nothing from a span above 2^31), at most `max_rows` units (nothing refuses a row
## before prepare()) and a player_count of 0 or at least the highest spawn owner.
func test_every_scenario_file_places_its_units_inside_the_map_and_within_its_limits() -> void:
	for path: String in FileScan.list_files(SCENARIOS_DIR, ".tres"):
		var scenario: ScenarioDef = load(path)
		var world: World = World.from_scenario(scenario)
		var map: Rect2i = Rect2i(0, 0, world.map_w, world.map_h)
		var problems: Array[String] = []
		var units: int = 0
		var owners: int = 0
		for spawn: SpawnDef in scenario.spawns:
			units += spawn.count
			owners = maxi(owners, spawn.owner)
			if spawn.jitter < 0 or spawn.jitter > 8000:
				problems.append("jitter %d of %s" % [spawn.jitter, spawn.unit.type_id])
			for k: int in spawn.count:
				var at: Vector2i = _grid_point(spawn, k)
				if not map.has_point(at) or not _passable(world, at, spawn.unit.move_class):
					problems.append("%s %d at %s" % [spawn.unit.type_id, k, at])
		if units > world.max_rows:
			problems.append("%d units, max_rows %d" % [units, world.max_rows])
		if scenario.player_count != 0 and scenario.player_count < owners:
			problems.append("player_count %d, owner %d" % [scenario.player_count, owners])
		assert_array(problems).override_failure_message(path).is_empty()


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
	# P48 may tune the pond and the scrub, so only that they exist is pinned.
	assert_int(water).is_greater(0)
	assert_int(scrub_patches).is_greater_equal(2)


@warning_ignore("integer_division")
func test_the_perf_arena_scenario_spawns_150_units_inside_the_window_on_open_ground() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH)
	assert_str(scenario.map.resource_path).is_equal(ARENA_MAP_PATH)
	assert_array(scenario.map.validate()).is_empty()
	assert_int(scenario.player_count).is_equal(2)
	assert_that(scenario.map_size_tiles).is_equal(Vector2i(64, 64))
	assert_int(scenario.local_player).is_equal(1)
	assert_that(scenario.camera_start_tile).is_equal(Vector2i(32, 32))
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
	var jitters: Array[int] = []
	var problems: Array[String] = []
	for spawn: SpawnDef in scenario.spawns:
		for k: int in spawn.count:
			var point: Vector2i = _grid_point(spawn, k)
			points.append(point)
			jitters.append(spawn.jitter)
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
	# Not even the two maximum jitters of a pair bring two units onto one point.
	var touching: int = 0
	for i: int in points.size():
		for j: int in range(i + 1, points.size()):
			var apart: Vector2i = (points[i] - points[j]).abs()
			var reach: int = jitters[i] + jitters[j]
			touching += 1 if apart.x <= reach and apart.y <= reach else 0
	assert_int(touching).is_equal(0)
	# The real spawn code agrees with the placement above: 75 units per player, and each unit
	# within its jitter of its grid point (the rows are in spawn order, ids ascending).
	var world: World = World.from_scenario(scenario)
	assert_int(world.unit_count()).is_equal(150)
	assert_array([world.owner.count(1), world.owner.count(2)]).is_equal([75, 75])
	var drifted: int = 0
	for row: int in points.size():
		var off: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row]) - points[row]
		drifted += 1 if maxi(absi(off.x), absi(off.y)) > jitters[row] else 0
	assert_int(drifted).is_equal(0)


## P48 tuned the opening orders: each side attack-moves to a firing line two tiles before the
## ridge on its own side (columns 29 and 34), not to the other side's spawn centre (tiles 39 and
## 24), because the rush into the enemy ended the heavy window (135 rows in the 26 x 15 window)
## after 136 ticks, and the gate needs 150. test_scenarios pins the pace.
func test_the_perf_arena_orders_send_each_side_to_a_firing_line_before_the_ridge() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH)
	var orders: Array = []
	for order: OrderDef in scenario.orders:
		orders.append([order.tick, order.player, order.type, order.target_tile])
	(
		assert_array(orders)
		. is_equal(
			[
				[0, 1, Command.Type.ATTACK_MOVE, Vector2i(29, 32)],
				[0, 2, Command.Type.ATTACK_MOVE, Vector2i(34, 32)],
			]
		)
	)
	for order: OrderDef in scenario.orders:
		# On its own side of the ridge (columns 31 and 32), with the other side's units across it.
		var enemy_centre: Vector2i = _spawn_centre_tile(scenario, 3 - order.player)
		var own_side: bool = (
			order.target_tile.x < 31 if order.player == 1 else order.target_tile.x > 32
		)
		var enemy_side: bool = enemy_centre.x > 32 if order.player == 1 else enemy_centre.x < 31
		assert_bool(own_side).override_failure_message("own side of %d" % order.player).is_true()
		assert_bool(enemy_side).override_failure_message("enemy of %d" % order.player).is_true()


## The ridge cuts the map in two: with every gap shut the two spawn centres are cut off, and with
## any one gap open alone foot and tracked units get from their centre to the other one. Scrub
## stops tracked units, so both ends must be tiles the class can enter.
func test_each_perf_arena_gap_alone_lets_foot_and_tracked_units_cross_the_ridge() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH)
	var map: MapDef = scenario.map
	var gaps: Array = [[26, 27], [31, 32, 33], [37, 38]]  # the runs of gap rows pinned above
	for order: OrderDef in scenario.orders:
		# P48: the goal is the other side's spawn centre, which the orders no longer name.
		var start: Vector2i = _spawn_centre_tile(scenario, order.player)
		var goal: Vector2i = _spawn_centre_tile(scenario, 3 - order.player)
		for move_class: int in [FOOT, TRACKED]:
			for tile: Vector2i in [start, goal]:
				var enter: int = _cost(map, tile.x, tile.y, move_class)
				assert_int(enter).override_failure_message("enter %s" % [tile]).is_greater(0)
			var shut: bool = _reaches(map, start, goal, move_class, [])
			assert_bool(shut).override_failure_message("all gaps shut").is_false()
			for rows: Array in gaps:
				var crossed: bool = _reaches(map, start, goal, move_class, rows)
				assert_bool(crossed).override_failure_message("rows %s" % [rows]).is_true()


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


## A building that breaks no rule when its file is depot.tres: 2x2, speed 0, radius 0, armour
## Building, not buildable by the player (tab -1).
func _fine_building() -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.footprint = Vector2i(2, 2)
	building.armour = 3
	return building


## One text per broken Phase 3 rule of a unit or building file; empty when the file is fine. The
## rules of ADR 0018 section 9 that need the whole roster (the requirement chains reach the
## Headquarters) wait for plan row P72.
func _economy_problems(file: String, unit: UnitDef, rules: RulesDef) -> PackedStringArray:
	var broken: Dictionary[String, bool] = {
		"cost is negative": unit.cost < 0,
		"build_ticks is negative": unit.build_ticks < 0,
		"tab is not -1..2": unit.tab < -1 or unit.tab > 2,
		"harvest_capacity is not a multiple":
		unit.harvest_capacity < 0 or unit.harvest_capacity % rules.credits_per_ore != 0,
		"requires is the unit itself": unit.requires == unit,
	}
	if unit is BuildingDef:
		var building: BuildingDef = unit
		broken["speed is not 0"] = building.speed != 0
		broken["radius is not 0"] = building.radius != 0
		broken["armour is not Building"] = building.armour != 3
		broken["footprint is not 1..3"] = (
			building.footprint.x < 1
			or building.footprint.x > 3
			or building.footprint.y < 1
			or building.footprint.y > 3
		)
		broken["produces is not -1..2"] = building.produces < -1 or building.produces > 2
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("%s: %s" % [file, message])
	return problems


## One text per broken Phase 3 rule of a RulesDef; empty when the numbers are fine. The divisors
## are at least 1 because the sim takes a tick number modulo them.
func _rule_problems(rules: RulesDef) -> PackedStringArray:
	var broken: Dictionary[String, bool] = {
		"start_credits is negative": rules.start_credits < 0,
		"ore_start is not in 0..ore_cell_max":
		rules.ore_start < 0 or rules.ore_start > rules.ore_cell_max,
		"harvest_resume_ticks is negative": rules.harvest_resume_ticks < 0,
		"low_power_percent is not in 0..100":
		rules.low_power_percent < 0 or rules.low_power_percent > 100,
		"a reach is negative":
		(
			mini(
				mini(rules.harvest_reach_milli, rules.dock_reach_milli),
				mini(rules.harvest_pick_milli, rules.build_reach_tiles)
			)
			< 0
		),
		"a cap is negative": mini(mini(rules.unit_cap, rules.building_cap), rules.ghost_cap) < 0,
		"unit_cap and building_cap of 2 players do not fit max_rows":
		PLAYERS * (rules.unit_cap + rules.building_cap) > rules.max_rows,
	}
	for divisor: String in [
		"credits_per_ore",
		"ore_regrow_ticks",
		"harvest_ticks_per_ore",
		"unload_ticks_per_ore",
		"harvest_retry_ticks",
		"queue_slots",
	]:
		broken["%s is below 1" % divisor] = int(rules.get(divisor)) < 1
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("rules: " + message)
	return problems


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


func _passable(world: World, at: Vector2i, move_class: int) -> bool:
	return world.is_passable(world.cell_of(at.x, at.y), move_class)


func _in_window(at: Vector2i) -> bool:
	return (
		at.x >= WINDOW_MIN.x
		and at.y >= WINDOW_MIN.y
		and at.x <= WINDOW_MAX.x
		and at.y <= WINDOW_MAX.y
	)


## Whether a unit of `move_class` walks from tile `start` to tile `goal`: 8 neighbours, no step
## past a blocked orthogonal neighbour (ADR 0008), the ridge (columns 31-32) shut but on `rows`.
func _reaches(map: MapDef, start: Vector2i, goal: Vector2i, move_class: int, rows: Array) -> bool:
	var size: Vector2i = map.size_tiles()
	var stride: int = size.x + 2  # a blocked ring around the map, so no step leaves the grid
	var open: PackedByteArray = PackedByteArray()
	open.resize(stride * (size.y + 2))
	for y: int in size.y:
		for x: int in size.x:
			var shut: bool = (x == 31 or x == 32) and not rows.has(y)
			open[(y + 1) * stride + x + 1] = 0 if shut or _cost(map, x, y, move_class) <= 0 else 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(open.size())
	var queue: PackedInt32Array = [(start.y + 1) * stride + start.x + 1]
	seen[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		if cell == (goal.y + 1) * stride + goal.x + 1:
			return true
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				var next: int = cell + dy * stride + dx
				var cuts: bool = (
					dx != 0 and dy != 0 and open[cell + dx] + open[cell + dy * stride] < 2
				)
				if open[next] == 1 and seen[next] == 0 and not cuts:
					seen[next] = 1
					queue.append(next)
	return false


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
