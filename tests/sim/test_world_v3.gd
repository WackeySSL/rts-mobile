extends GdUnitTestSuite
## World v3, the strike layout (plan row P109, ADR 0023 section 10, exceptions 10 and 18): the
## two row columns, the three per-player arrays and the six type tables that a BuildingDef's strike
## exports fill, each in exactly one shape list; what is state (the row columns and the pending
## strike, in the hash) and what is not (the type tables, in defs_hash); and the perf arena, which
## has no strike building, keeping every new column at its start value. The rules of the strike
## state are P110's (test_strike_command, test_strike_rupture, test_strike_tick). The layout re-pin
## itself is pinned where the hashes are (test_world_hash's TICK_0_SEED_1, data/dev/perf_gate.tres
## through tests/perf/test_golden_hashes).
## Numbers are literals, so no data file can agree with a wrong rule.

const HashBytes: GDScript = preload("res://tests/perf/support/hash_bytes.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TICKS: int = 150
const ROW_COLUMNS: Array[StringName] = [&"ready_tick", &"offline_until"]
const PLAYER_COLUMNS: Array[StringName] = [&"strike_x", &"strike_y", &"strike_tick"]
const TYPE_COLUMNS: Array[StringName] = [
	&"type_strike_kind",
	&"type_charge_ticks",
	&"type_strike_radius",
	&"type_strike_delay",
	&"type_strike_ticks",
	&"type_strike_weapon",
]


func test_the_layout_version_and_the_new_arrays_are_the_contract() -> void:
	assert_array([World.STATE_FORMAT, World.HASH_OTHER_SECTIONS]).is_equal([4, 7])
	assert_array(World.ROW_ARRAYS.slice(-2)).is_equal(ROW_COLUMNS)
	assert_array(World.PLAYER_ARRAYS.slice(-3)).is_equal(PLAYER_COLUMNS)
	assert_array(World.TYPE_ARRAYS.slice(-6)).is_equal(TYPE_COLUMNS)
	var tail: Array[String] = ["home", "ready_tick", "offline_until", "projectiles", "fog"]
	tail.append_array(["players", "ore", "ghosts"])
	assert_array(World.hash_section_names().slice(-8)).is_equal(tail)
	assert_int(World.hash_section_names().size()).is_equal(
		World.ROW_ARRAYS.size() + World.HASH_OTHER_SECTIONS
	)


## Acceptance: every new array is in exactly one shape list, and is an int32 table of the World.
func test_every_new_array_is_in_exactly_one_shape_list() -> void:
	var lists: Array = [World.ROW_ARRAYS, World.TYPE_ARRAYS, World.WEAPON_ARRAYS]
	lists.append_array([World.PROJECTILE_ARRAYS, World.MAP_ARRAYS, World.SCRATCH_ARRAYS])
	lists.append_array([World.RUNTIME_ARRAYS, World.PLAYER_ARRAYS, World.ORE_ARRAYS])
	lists.append_array([World.GHOST_ARRAYS, World.DERIVED_ARRAYS])
	var names: Array[StringName] = []
	names.append_array(ROW_COLUMNS)
	names.append_array(PLAYER_COLUMNS)
	names.append_array(TYPE_COLUMNS)
	assert_int(names.size()).is_equal(11)
	var world: World = World.new()
	for column_name: StringName in names:
		var found: int = 0
		for list: Array in lists:
			if list.has(column_name):
				found += 1
		assert_int(found).override_failure_message(column_name).is_equal(1)
		assert_int(typeof(world.get(column_name))).is_equal(TYPE_PACKED_INT32_ARRAY)


## A new row starts with no charge and no blackout, and the compaction that removes a dead row moves
## both columns with the others.
func test_add_unit_starts_both_row_columns_at_zero_and_a_removal_compacts_them() -> void:
	var world: World = World.new()
	world.type_ids.append(&"unit")
	world.player_count = 1
	world.prepare()
	for _i: int in 4:
		world.add_unit(1, 0, 1000, 1000)
	assert_array(world.ready_tick).is_equal([0, 0, 0, 0])
	assert_array(world.offline_until).is_equal([0, 0, 0, 0])
	for row: int in 4:
		world.ready_tick[row] = 100 * (row + 1)
		world.offline_until[row] = 7 + row
	world.hp[1] = 0
	world.remove_dead()
	assert_array(world.unit_id).is_equal([1, 3, 4])
	assert_array(world.ready_tick).is_equal([100, 300, 400])
	assert_array(world.offline_until).is_equal([7, 9, 10])


## prepare() gives each pending-strike array an entry for the neutral player 0 and one per player,
## all 0 (no rupture pending), whatever start_credits or the queue sizes are.
func test_prepare_sizes_the_pending_strike_of_every_player_at_none() -> void:
	for players: int in [1, 2, 4]:
		var scenario: ScenarioDef = ScenarioDef.new()
		scenario.player_count = players
		var world: World = World.from_scenario(scenario)
		var zeros: Array[int] = []
		zeros.resize(players + 1)
		zeros.fill(0)
		for column_name: StringName in PLAYER_COLUMNS:
			assert_array(world.get(column_name)).override_failure_message(column_name).is_equal(
				zeros
			)
	var world: World = World.new()
	world.player_count = 2
	world.prepare()
	world.strike_x[2] = 41500
	world.strike_y[2] = 12500
	world.strike_tick[2] = 77
	world.prepare()  # Idempotent: what the match wrote since stays.
	assert_array(world.strike_x).is_equal([0, 0, 41500])
	assert_array(world.strike_y).is_equal([0, 0, 12500])
	assert_array(world.strike_tick).is_equal([0, 0, 77])


## A BuildingDef's six strike exports fill the six type tables, column by column; a building with
## none and a unit pad them (kind 0, no lengths, weapon -1), and the strike weapon is a weapon of
## the weapon tables, so its damage and armour percents are the weapon's.
func test_a_building_def_fills_the_strike_tables_and_a_plain_type_pads_them() -> void:
	var bore: BuildingDef = _building(&"bore")
	bore.strike_kind = 1
	bore.charge_ticks = 4500
	bore.strike_radius = 3000
	bore.strike_delay = 45
	bore.strike_weapon = _weapon(&"bore_charge", 600)
	var array: BuildingDef = _building(&"array")
	array.strike_kind = 2
	array.charge_ticks = 3000
	array.strike_radius = 4000
	array.strike_ticks = 450
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(bore)
	scenario.roster.append(array)
	scenario.roster.append(_building(&"depot"))
	var scout: UnitDef = UnitDef.new()
	scout.type_id = &"scout"
	scenario.roster.append(scout)
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"bore", &"array", &"depot", &"scout"])
	var expected: Dictionary[StringName, Array] = {
		&"type_strike_kind": [1, 2, 0, 0],
		&"type_charge_ticks": [4500, 3000, 0, 0],
		&"type_strike_radius": [3000, 4000, 0, 0],
		&"type_strike_delay": [45, 0, 0, 0],
		&"type_strike_ticks": [0, 450, 0, 0],
		&"type_strike_weapon": [0, -1, -1, -1],
	}
	assert_array(expected.keys()).is_equal(TYPE_COLUMNS)
	for table: StringName in expected:
		assert_array(world.get(table)).override_failure_message(table).is_equal(expected[table])
	assert_array(world.weapon_ids).is_equal([&"bore_charge"])
	assert_array([world.weapon_damage[0], world.weapon_cooldown[0]]).is_equal([600, 1])
	assert_array(world.type_weapon).is_equal([-1, -1, -1, -1])  # No type shoots it: it is a strike.


## A weapon is known by its id: a strike weapon and a unit's weapon of one id are one entry (the
## first definition wins), and the order of the weapon table is the order of the types.
func test_a_strike_weapon_is_found_by_its_id_among_the_unit_weapons() -> void:
	var bore: BuildingDef = _building(&"bore")
	bore.strike_kind = 1
	bore.strike_weapon = _weapon(&"charge", 600)
	var gunner: UnitDef = UnitDef.new()
	gunner.type_id = &"gunner"
	gunner.weapon = _weapon(&"charge", 12)
	var other: UnitDef = UnitDef.new()
	other.type_id = &"other"
	other.weapon = _weapon(&"rifle", 15)
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.roster.append(bore)
	scenario.roster.append(gunner)
	scenario.roster.append(other)
	var world: World = World.from_scenario(scenario)
	assert_array(world.weapon_ids).is_equal([&"charge", &"rifle"])
	assert_array(world.weapon_damage).is_equal([600, 15])
	assert_array(world.type_strike_weapon).is_equal([0, -1, -1])
	assert_array(world.type_weapon).is_equal([-1, 0, 1])


## The row columns and the pending strike are state: each changes its own section and no other, and
## the byte stream that the perf suite's helper rebuilds from the shape lists (an independent walk)
## hashes to state_hash(). The six type tables are not state: they move no section, and
## defs_hash sees each.
func test_the_row_columns_and_the_pending_strike_are_state_and_the_type_tables_are_not() -> void:
	var base: World = _arena()
	var defs: int = base.defs_hash()
	for column_name: StringName in ROW_COLUMNS:
		var world: World = _arena()
		var column: PackedInt32Array = world.get(column_name)
		column[column.size() - 1] = 90
		_assert_sections(base, world, [String(column_name)], column_name)
	for column_name: StringName in PLAYER_COLUMNS:
		var world: World = _arena()
		var column: PackedInt32Array = world.get(column_name)
		column[column.size() - 1] = 90
		_assert_sections(base, world, ["players"], column_name)
	for column_name: StringName in TYPE_COLUMNS:
		var world: World = _arena()
		var column: PackedInt32Array = world.get(column_name)
		column[column.size() - 1] += 1
		_assert_sections(base, world, [], column_name)
		assert_int(world.defs_hash()).override_failure_message(column_name).is_not_equal(defs)
	var written: World = _arena()
	written.ready_tick[3] = 4500
	written.offline_until[149] = 450
	written.strike_x[1] = 20500
	written.strike_y[1] = 8500
	written.strike_tick[1] = 46
	assert_int(HashBytes.digest(HashBytes.stream(written))).is_equal(written.state_hash())
	assert_int(written.state_hash()).is_not_equal(base.state_hash())


## The arena has no strike building, so through a run its row columns and pending strikes stay at
## their start values and its type tables pad (no later Phase 3 row may move them there).
func test_the_perf_arena_keeps_the_strike_state_at_its_start_values_through_a_run() -> void:
	var world: World = _arena()
	var none: Array[Command] = []
	for _tick: int in TICKS:
		Sim.step(world, none)
	for column_name: StringName in ROW_COLUMNS:
		var rows: PackedInt32Array = world.get(column_name)
		assert_int(rows.size()).is_equal(world.unit_count())
		assert_int(rows.count(0)).override_failure_message(column_name).is_equal(rows.size())
	for column_name: StringName in PLAYER_COLUMNS:
		assert_array(world.get(column_name)).override_failure_message(column_name).is_equal(
			[0, 0, 0]
		)
	for column_name: StringName in TYPE_COLUMNS:
		var pad: int = -1 if column_name == &"type_strike_weapon" else 0
		var table: PackedInt32Array = world.get(column_name)
		assert_int(table.size()).is_equal(world.type_ids.size())
		assert_int(table.count(pad)).override_failure_message(column_name).is_equal(table.size())


func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)


func _building(type_id: StringName) -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.type_id = type_id
	building.armour = 3
	return building


func _weapon(id: StringName, damage: int) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = id
	weapon.damage = damage
	return weapon


## The names of the hash sections where `a` and `b` differ; the failure names `what`.
func _assert_sections(a: World, b: World, expected: Array[String], what: Variant) -> void:
	assert_array(_differing(a, b)).override_failure_message(str(what)).is_equal(expected)


func _differing(a: World, b: World) -> Array[String]:
	var names: PackedStringArray = World.hash_section_names()
	var left: PackedInt64Array = a.hash_parts()
	var right: PackedInt64Array = b.hash_parts()
	var found: Array[String] = []
	for index: int in names.size():
		if left[index] != right[index]:
			found.append(names[index])
	return found
