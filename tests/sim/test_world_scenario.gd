extends GdUnitTestSuite
## World.from_scenario v1 (plan P29c): the type, weapon and terrain tables, the rules, the roster,
## the player count, spawn jitter (two draws per unit, clamped, kept on passable ground) and the
## prepared world with no events. Numbers are literals, so no data file can agree with a wrong rule.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## A 4 x 3 map of grass '.' and scrub '^' of the standard terrain set, 4000 x 3000 milli. Only
## foot units may enter scrub (costs 10, 0, 0).
const SCRUB_MAP: Array[String] = ["....", ".^..", "..^."]


## The tables hold what the shipped unit and weapon files say (ADR 0009 section 1), in the order of
## first appearance in the spawns; the terrain ids follow the terrain set.
func test_from_scenario_copies_the_unit_weapon_and_terrain_tables_of_the_arena() -> void:
	var world: World = World.from_scenario(load(ARENA_PATH) as ScenarioDef)
	assert_array(world.type_ids).is_equal([&"light_tank", &"rifle_squad", &"rocket_squad"])
	assert_array(world.weapon_ids).is_equal([&"tank_cannon", &"rifle", &"rocket"])
	assert_array(world.terrain_ids).is_equal([&"grass", &"sand", &"scrub", &"rock", &"water"])
	var expected: Dictionary[StringName, Array] = {
		&"type_speed": [120, 67, 60],
		&"type_radius": [400, 300, 300],
		&"type_selection_radius": [500, 350, 350],
		&"type_spacing": [1200, 900, 900],
		&"type_max_hp": [300, 100, 90],
		&"type_armour": [World.Armour.LIGHT, World.Armour.INFANTRY, World.Armour.INFANTRY],
		&"type_move_class": [World.MoveClass.TRACKED, World.MoveClass.FOOT, World.MoveClass.FOOT],
		&"type_sight": [7000, 6000, 6000],
		&"type_acquire": [5500, 5000, 5500],
		&"type_weapon": [0, 1, 2],
		&"type_names": ["Light Tank", "Rifle Squad", "Rocket Squad"],
		&"weapon_range": [4500, 4000, 5000],
		&"weapon_min_range": [0, 0, 0],
		&"weapon_damage": [30, 12, 50],
		&"weapon_cooldown": [25, 15, 45],
		&"weapon_projectile_speed": [600, 0, 300],
		&"weapon_vs_armour": [70, 60, 35, 40, 100, 10, 5, 5, 20, 100, 100, 80],
	}
	assert_array(expected.keys()).contains_exactly_in_any_order(
		World.TYPE_ARRAYS + World.WEAPON_ARRAYS
	)
	_assert_columns(world, expected)
	# The first row of each type: 30 tanks, then 27 rifle squads, then rocket squads.
	assert_array([world.hp[0], world.hp[30], world.hp[57]]).is_equal([300, 100, 90])


func test_the_rules_come_from_the_scenario_else_the_defaults_and_size_the_fixed_arrays() -> void:
	var fields: Array[String] = _rule_fields()
	assert_int(fields.size()).is_equal(15)
	var defaults: RulesDef = RulesDef.new()
	var rules: RulesDef = RulesDef.new()
	for i: int in fields.size():
		rules.set(fields[i], 101 + i)
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.rules = rules
	var world: World = World.from_scenario(scenario)
	for i: int in fields.size():
		assert_int(int(world.get(fields[i]))).override_failure_message(fields[i]).is_equal(101 + i)
	# max_projectiles is the 14th field and max_rows the 15th: prepare() sizes with the scenario's.
	assert_array([world.proj_id.size(), world.intent_x.size()]).is_equal([114, 115])
	scenario.rules = null
	var plain: World = World.from_scenario(scenario)
	for field: String in fields:
		assert_int(int(plain.get(field))).override_failure_message(field).is_equal(
			int(defaults.get(field))
		)


func test_the_roster_adds_types_after_the_spawn_types_and_a_weapon_is_shared_by_its_id() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	var rifle: UnitDef = _unit(&"rifle_squad", _weapon(&"rifle", 12), 40)
	scenario.spawns.append(_block(1, rifle, 2, Vector2i(1, 1), 2, 1000, 0))
	# The roster: a new type and weapon, a null, a repeat of the spawned type (the first definition
	# wins, so its other weapon is never read), a new type with the rifle's id and another damage,
	# and an unarmed type with max hp 0, which is stored as 1.
	var twin: UnitDef = _unit(&"twin", _weapon(&"rifle", 99), 7)
	twin.display_name = "Twin Guns"
	scenario.roster.append(_unit(&"rocket_squad", _weapon(&"rocket", 50), 90))
	scenario.roster.append(null)
	scenario.roster.append(_unit(&"rifle_squad", _weapon(&"other", 1), 5))
	scenario.roster.append(twin)
	scenario.roster.append(_unit(&"bare", null, 0))
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"rifle_squad", &"rocket_squad", &"twin", &"bare"])
	assert_array(world.weapon_ids).is_equal([&"rifle", &"rocket"])
	var expected: Dictionary[StringName, Array] = {
		&"type_weapon": [0, 1, 0, -1],
		&"type_max_hp": [40, 90, 7, 1],
		&"weapon_damage": [12, 50],
		&"type_names": ["Rifle Squad", "Rocket Squad", "Twin Guns", "Bare"],
		&"unit_id": [1, 2],
		&"type_index": [0, 0],
	}
	_assert_columns(world, expected)
	for table: StringName in World.TYPE_ARRAYS:
		assert_int(world.get(table).size()).override_failure_message(table).is_equal(4)


## The scenario value, else the highest spawn owner. An owner above the scenario value raises it
## (add_unit does that before prepare()), and a negative value counts as 0.
func test_player_count_is_the_scenario_value_else_the_highest_spawn_owner() -> void:
	var cases: Array[Array] = [  # scenario value, spawn owners, player_count
		[0, [1, 3], 3],
		[5, [1, 2], 5],
		[1, [2], 2],
		[-4, [1], 1],
		[-4, [], 0],
	]
	for case: Array in cases:
		var scenario: ScenarioDef = ScenarioDef.new()
		scenario.player_count = int(case[0])
		for owner: int in case[1]:
			scenario.spawns.append(_block(owner, _unit(&"tank", null), 1, Vector2i.ZERO, 1, 0, 0))
		var world: World = World.from_scenario(scenario)
		assert_int(world.player_count).override_failure_message(str(case)).is_equal(case[2])


## Two draws per unit, x then y, from the world's stream, and none for a spawn without a jitter
## (its units stay on the grid points of Phase 1; test_world_setup pins those, and the controls
## scenario in test_world_v1 leaves the stream fresh). The replay makes the same draws by hand.
func test_jitter_draws_x_then_y_for_each_unit_of_a_spawn_with_a_jitter_only() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	var tank: UnitDef = _unit(&"tank", null)
	scenario.spawns.append(_block(1, tank, 3, Vector2i(2, 2), 2, 1000, 0))
	scenario.spawns.append(_block(2, tank, 4, Vector2i(10, 5), 2, 1500, 200))
	scenario.spawns.append(_block(1, tank, 2, Vector2i(5, 12), 1, 1000, 400))
	var world: World = World.from_scenario(scenario, _stream(7))
	var replay: DetRandom = _stream(7)
	var drawn: Array[Vector2i] = []
	for spawn: SpawnDef in scenario.spawns:
		for k: int in spawn.count:
			var point: Vector2i = _grid_point(spawn, k)
			if spawn.jitter > 0:
				point.x += replay.range_int(-spawn.jitter, spawn.jitter)
				point.y += replay.range_int(-spawn.jitter, spawn.jitter)
			drawn.append(point)
	assert_array(_points(world)).is_equal(drawn)
	assert_array(world.goal_x).is_equal(world.pos_x)
	assert_array(world.goal_y).is_equal(world.pos_y)
	assert_array(world.rng.state()).is_equal(replay.state())
	assert_array(replay.state()).is_not_equal(_stream(7).state())


## The arena (jitter 300 on tile centres): each unit within 300 of its grid point on both axes and
## on ground its class may enter; the same for the same seed and different for another. A null rng
## is the stream of seed 0.
func test_the_arena_jitter_stays_within_300_on_passable_ground_and_follows_the_seed() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var first: World = World.from_scenario(scenario, _stream(1))
	var repeat: World = World.from_scenario(scenario, _stream(1))
	var second: World = World.from_scenario(scenario, _stream(2))
	assert_array(_points(repeat)).is_equal(_points(first))
	assert_array(repeat.rng.state()).is_equal(first.rng.state())
	assert_array(_points(second)).is_not_equal(_points(first))
	var implicit: World = World.from_scenario(scenario)
	var seed_0: World = World.from_scenario(scenario, DetRandom.create(0, DetRandom.STREAM_SIM))
	assert_array(_points(implicit)).is_equal(_points(seed_0))
	assert_array(implicit.rng.state()).is_equal(seed_0.rng.state())
	assert_array(_points(implicit)).is_not_equal(_points(first))
	var points: Array[Vector2i] = _points(first)
	var row: int = 0
	var too_far: int = 0
	var blocked: int = 0
	var moved: int = 0
	for spawn: SpawnDef in scenario.spawns:
		for k: int in spawn.count:
			var off: Vector2i = points[row] - _grid_point(spawn, k)
			var cell: int = first.cell_of(points[row].x, points[row].y)
			var move_class: int = first.type_move_class[first.type_index[row]]
			too_far += 1 if maxi(absi(off.x), absi(off.y)) > spawn.jitter else 0
			blocked += 0 if first.is_passable(cell, move_class) else 1
			moved += 1 if off != Vector2i.ZERO else 0
			row += 1
	assert_array([row, too_far, blocked, moved]).is_equal([150, 0, 0, 150])


## A jitter of 1400 from two corners of the 4 x 3 map throws draws off the map and onto scrub, which
## only foot units may enter. The draws are replayed here: clamped into 0..3999 by 0..2999, kept
## unless the tile is scrub and the class is not foot, in which case the unit starts on its grid
## point. Wheeled and tracked units are blocked, the third block of foot units never is.
@warning_ignore("integer_division")
func test_jitter_is_clamped_into_the_map_and_blocked_ground_keeps_the_grid_point() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = MapDef.new()
	scenario.map.rows = PackedStringArray(SCRUB_MAP)
	scenario.map.terrain = load("res://data/terrain/standard.tres") as TerrainSetDef
	var classes: Array[int] = [
		World.MoveClass.TRACKED, World.MoveClass.WHEELED, World.MoveClass.FOOT
	]
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 2), Vector2i(0, 0)]
	for i: int in 3:
		var unit: UnitDef = _unit(StringName("class_%d" % classes[i]), null)
		unit.move_class = classes[i]
		scenario.spawns.append(_block(1, unit, 40, corners[i], 1, 0, 1400))
	var world: World = World.from_scenario(scenario, _stream(5))
	var replay: DetRandom = _stream(5)
	var expected: Array[Vector2i] = []
	var clamped: int = 0
	var kept: Array[int] = [0, 0, 0]
	for i: int in 3:
		var grid: Vector2i = _grid_point(scenario.spawns[i], 0)
		for _k: int in 40:
			var drawn: Vector2i = grid
			drawn.x += replay.range_int(-1400, 1400)
			drawn.y += replay.range_int(-1400, 1400)
			var at: Vector2i = Vector2i(clampi(drawn.x, 0, 3999), clampi(drawn.y, 0, 2999))
			var blocked: bool = SCRUB_MAP[at.y / 1000][at.x / 1000] == "^" and classes[i] != 0
			clamped += 1 if at != drawn else 0
			kept[i] += 1 if blocked else 0
			expected.append(grid if blocked else at)
	assert_array(_points(world)).is_equal(expected)
	assert_int(clamped).is_greater(10)
	assert_array([kept[0] > 0, kept[1] > 0, kept[2]]).is_equal([true, true, 0])


## from_scenario ends with prepare() (also for a null scenario) and drops the SPAWNED events of the
## setup. The rows stay, so rows_version counts them, and a later add_unit writes the next record.
func test_from_scenario_ends_with_prepare_and_drops_the_spawn_events() -> void:
	for scenario: ScenarioDef in [load(SCENARIO_PATH), ScenarioDef.new(), null]:
		var world: World = World.from_scenario(scenario)
		assert_array(world.events).is_empty()
		assert_array([world.intent_x.size(), world.proj_id.size(), world.stats.size()]).is_equal(
			[256, 512, 7]
		)
	var controls: World = World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)
	assert_array([controls.unit_count(), controls.rows_version, controls.next_id]).is_equal(
		[40, 40, 41]
	)
	controls.add_unit(1, 0, 500, 700)
	assert_array(controls.events).is_equal([1, 41, 500, 700, 0, 1, 0, 0])


func _stream(match_seed: int) -> DetRandom:
	return DetRandom.create(match_seed, DetRandom.STREAM_SIM)


## Unit `k` of a block before jitter (the SpawnDef rule), in milli-tiles.
@warning_ignore("integer_division")
func _grid_point(spawn: SpawnDef, k: int) -> Vector2i:
	var origin: Vector2i = spawn.origin_tile * 1000 + Vector2i(500, 500)
	return origin + Vector2i(k % spawn.columns, k / spawn.columns) * spawn.spacing


func _points(world: World) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for row: int in world.unit_count():
		points.append(Vector2i(world.pos_x[row], world.pos_y[row]))
	return points


func _block(
	owner: int, unit: UnitDef, count: int, origin: Vector2i, columns: int, spacing: int, jitter: int
) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner
	spawn.unit = unit
	spawn.count = count
	spawn.origin_tile = origin
	spawn.columns = columns
	spawn.spacing = spacing
	spawn.jitter = jitter
	return spawn


func _unit(type_id: StringName, weapon: WeaponDef, max_hp: int = 1) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = type_id
	unit.weapon = weapon
	unit.max_hp = max_hp
	return unit


func _weapon(id: StringName, damage: int) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = id
	weapon.damage = damage
	return weapon


func _rule_fields() -> Array[String]:
	var fields: Array[String] = []
	for info: Dictionary in RulesDef.new().get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			fields.append(String(info["name"]))
	return fields


func _assert_columns(world: World, expected: Dictionary[StringName, Array]) -> void:
	for column: StringName in expected:
		assert_array(world.get(column)).override_failure_message(column).is_equal(expected[column])
