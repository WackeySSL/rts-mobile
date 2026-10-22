extends GdUnitTestSuite
## World v1, parts 1 to 3 (plan P29a, P29a2, P29b): the rule ints and the default stream of a
## hand-built world, type table padding, add_unit's new columns and event, the Phase 1-shaped
## world through Sim.step, the shape lists, the sizes prepare() gives the fixed-capacity arrays,
## and the map grid (cell_of, is_passable, set_terrain, open grass, a MapDef in from_scenario).
## Part 4 (P31a): the helper objects, the refusals after prepare() and the flow invalidation.
## Numbers are literals, so no data file can agree with a wrong rule. A push_error would fail
## verify, which scans the log.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const MAP: int = 48000
## A 4 x 3 map of grass '.', scrub '^', hills 'h' and rock '#' (terrain 0 to 3, costs foot,
## wheeled, tracked: 10 10 10, 10 0 0, 25 15 40, 0 0 0). Its terrain per cell, and its costs per
## class (move_cost holds the three lists one after the other).
const TILES: Array[String] = ["..^h", "h#^.", "#..h"]
const TILE_TERRAIN: Array[int] = [0, 0, 1, 2, 2, 3, 1, 0, 3, 0, 0, 2]
const TILE_FOOT: Array[int] = [10, 10, 10, 25, 25, 0, 10, 10, 0, 10, 10, 25]
const TILE_WHEELED: Array[int] = [10, 10, 0, 15, 15, 0, 0, 10, 0, 10, 10, 15]
const TILE_TRACKED: Array[int] = [10, 10, 0, 40, 40, 0, 0, 10, 0, 10, 10, 40]
const TERRAIN_COSTS: Array[int] = [10, 10, 10, 10, 0, 0, 25, 15, 40, 0, 0, 0]
## flow_cells_per_tick is left out: it moves in P27f, and test_defs pins it in RulesDef.
const RULES: Dictionary[String, int] = {
	"retarget_period_ticks": 5,
	"fog_period_ticks": 3,
	"line_check_period_ticks": 5,
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


func test_the_enums_and_the_event_stride_are_the_contract() -> void:
	var stat: Dictionary = {"FLOW_CELLS": 0, "LINE_CHECKS": 1, "SEP_PAIRS": 2}
	stat.merge({"TARGET_CANDIDATES": 3, "FOG_CELLS": 4, "PROJ_STEPS": 5, "ROWS_COMPACTED": 6})
	stat.merge({"ORE_SCANNED": 7, "EXIT_SCANNED": 8, "MEMORY_CHECKS": 9})
	assert_dict(World.Stat).is_equal(stat)
	assert_dict(World.Order).is_equal({"IDLE": 0, "ATTACK_MOVE": 1, "MOVE": 2, "ATTACK": 3})
	assert_dict(World.Armour).is_equal({"INFANTRY": 0, "LIGHT": 1, "HEAVY": 2, "BUILDING": 3})
	assert_dict(World.MoveClass).is_equal({"FOOT": 0, "WHEELED": 1, "TRACKED": 2})
	assert_dict(World.Event).is_equal({"SPAWNED": 1, "DIED": 2, "SHOT": 3, "IMPACT": 4})
	var nav: Dictionary = {"NONE": 0, "DIRECT": 1, "FIELD": 2, "HOLD": 3, "CHASE": 4}
	assert_dict(World.NavMode).is_equal(nav)
	# 2 since P65 (ADR 0016, exception 10): fog.visible left the state hash. 3 since P70 (ADR 0017
	# section 7, exception 10): Phase 3's state joined it.
	assert_array([World.EVENT_STRIDE, World.STATE_FORMAT]).is_equal([8, 3])


## A Phase 1-shaped world: the rule ints and the stream exist, player_count follows the owners
## and never drops, and a type with no max hp entry gives 1 hp.
func test_a_hand_built_world_has_the_rule_defaults_and_the_default_stream() -> void:
	var world: World = _phase1_world()
	var defaults: RulesDef = RulesDef.new()
	var fields: Array[String] = []
	for info: Dictionary in defaults.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			fields.append(String(info["name"]))
	assert_int(fields.size()).is_equal(33)
	for field: String in fields:
		assert_that(world.get(field)).override_failure_message(field).is_equal(defaults.get(field))
	for field: String in RULES:
		assert_that(world.get(field)).override_failure_message(field).is_equal(RULES[field])
	assert_array(world.rng.state()).is_equal(DetRandom.create(0, DetRandom.STREAM_SIM).state())
	assert_int(world.next_projectile_id).is_equal(1)
	var zeros: Array[String] = ["player_count", "spawn_refused", "projectile_overflow"]
	zeros.append_array(["proj_free_top", "map_cols", "map_rows", "map_version", "native_phases"])
	for scalar: String in zeros:
		assert_int(world.get(scalar)).override_failure_message(scalar).is_equal(0)
	assert_object(world.kernels).is_null()  # A World runs the GDScript phases until told otherwise.
	world.add_unit(1, 0, 1000, 1000)
	assert_int(world.player_count).is_equal(1)
	for player: int in [2, 1, 3, 1]:
		world.add_unit(player, 0, 1000, 1000)
	assert_int(world.player_count).is_equal(3)
	assert_array(world.hp).is_equal([1, 1, 1, 1, 1])


func test_from_scenario_keeps_a_given_stream_and_defaults_to_the_sim_stream() -> void:
	var given: DetRandom = DetRandom.create(42, DetRandom.STREAM_SIM)
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	assert_object(World.from_scenario(null, given).rng).is_same(given)
	assert_object(World.from_scenario(scenario, given).rng).is_same(given)
	var world: World = World.from_scenario(scenario)
	assert_int(world.unit_count()).is_equal(40)
	assert_array(world.rng.state()).is_equal(DetRandom.create(0, DetRandom.STREAM_SIM).state())


func test_prepare_pads_every_type_table_to_the_type_count_and_keeps_entries() -> void:
	var world: World = World.new()
	for id: StringName in [&"mk_two", &"scout_test", &"rifle_squad"]:
		world.type_ids.append(id)
	# Type 0 already has an entry in each v1 table, and type_speed has two entries.
	world.type_speed.append_array(PackedInt32Array([93, 60]))
	world.type_max_hp.append(300)
	world.type_armour.append(2)
	world.type_move_class.append(0)
	world.type_sight.append(7000)
	world.type_acquire.append(5500)
	world.type_weapon.append(4)
	world.type_names.append("Mark 2")
	var expected: Dictionary[StringName, Array] = {
		&"type_speed": [93, 60, 0],
		&"type_radius": [0, 0, 0],
		&"type_selection_radius": [0, 0, 0],
		&"type_spacing": [0, 0, 0],
		&"type_max_hp": [300, 1, 1],
		&"type_armour": [2, 0, 0],
		&"type_move_class": [0, 2, 2],
		&"type_sight": [7000, 0, 0],
		&"type_acquire": [5500, 0, 0],
		&"type_weapon": [4, -1, -1],
		&"type_names": ["Mark 2", "Scout Test", "Rifle Squad"],
		&"type_foot_w": [0, 0, 0],
		&"type_foot_h": [0, 0, 0],
		&"type_cost": [0, 0, 0],
		&"type_build_ticks": [0, 0, 0],
		&"type_tab": [-1, -1, -1],
		&"type_requires": [-1, -1, -1],
		&"type_produces": [-1, -1, -1],
		&"type_power": [0, 0, 0],
		&"type_harvest": [0, 0, 0],
		&"type_free_unit": [-1, -1, -1],
		&"type_dock_x": [0, 0, 0],
		&"type_dock_y": [0, 0, 0],
		&"type_exit_x": [0, 0, 0],
		&"type_exit_y": [0, 0, 0],
	}
	assert_array(World.TYPE_ARRAYS).is_equal(expected.keys())
	for _pass: int in 2:
		world.prepare()
		_assert_columns(world, expected)


func test_add_unit_writes_every_column_at_its_spawn_value_and_one_spawned_record() -> void:
	var world: World = _phase1_world()
	world.type_max_hp.append_array(PackedInt32Array([300, 0]))
	var expected: Dictionary[StringName, Array] = {
		&"unit_id": [1],
		&"owner": [2],
		&"type_index": [0],
		&"pos_x": [3500],
		&"pos_y": [4500],
		&"goal_x": [3500],
		&"goal_y": [4500],
		&"group_cell": [-1],
		&"order": [0],
		&"hp": [300],
		&"order_target": [0],
		&"target": [0],
		&"cooldown": [0],
		&"nav_mode": [0],
		&"field": [-1],
		&"nav_cell": [-1],
		&"nav_next": [-1],
		&"best_dist": [0x3FFFFFFF],
		&"stall": [0],
		&"fog_cell": [-1],
		&"harvest_mode": [0],
		&"cargo": [0],
		&"harvest_slot": [-1],
		&"home": [0],
	}
	assert_array(World.ROW_ARRAYS).is_equal(expected.keys())
	assert_int(world.add_unit(2, 0, 3500, 4500)).is_equal(1)
	_assert_columns(world, expected)
	assert_array(world.events).is_equal([1, 1, 3500, 4500, 0, 2, 0, 0])
	assert_int(world.rows_version).is_equal(1)
	# A max hp of 0 and a type with no entry both give 1 hp. Records append, 8 ints each.
	assert_int(world.add_unit(1, 1, 10, 20)).is_equal(2)
	assert_int(world.add_unit(1, 2, 30, 40)).is_equal(3)
	assert_array(world.hp).is_equal([300, 1, 1])
	var records: Array[int] = [1, 1, 3500, 4500, 0, 2, 0, 0, 1, 2, 10, 20, 1, 1, 0, 0]
	records.append_array([1, 3, 30, 40, 2, 1, 0, 0])
	assert_array(world.events).is_equal(records)
	assert_array([world.rows_version, world.next_id]).is_equal([3, 4])


## Three types as in test_sim_step: speed 120, 0 and 60. A lone mover keeps exact Phase 1 numbers
## in every later phase: nothing else is near it and no type has a weapon.
func test_the_phase_1_shaped_world_steps_ten_ticks() -> void:
	var world: World = _phase1_world()
	world.add_unit(1, 0, 10000, 10000)
	world.add_unit(1, 2, 10000, 20000)
	world.add_unit(2, 1, 40000, 40000)
	world.prepare()
	assert_array(world.type_max_hp).is_equal([1, 1, 1])
	assert_array(world.type_armour).is_equal([0, 0, 0])
	assert_array(world.type_move_class).is_equal([2, 2, 2])
	assert_array(world.type_sight).is_equal([0, 0, 0])
	assert_array(world.type_acquire).is_equal([0, 0, 0])
	assert_array(world.type_weapon).is_equal([-1, -1, -1])
	assert_array(world.type_names).is_equal(["Type", "Type", "Type"])
	var order: Command = Command.attack_move(1, PackedInt32Array([1]), 30000, 10000)
	order.tick = 0
	var first: Array[Command] = [order]
	Sim.step(world, first)
	for _t: int in 9:
		Sim.step(world, [])
	assert_int(world.tick).is_equal(10)
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(world.pos_x).is_equal([11200, 10000, 40000])
	assert_array(world.pos_y).is_equal([10000, 20000, 40000])
	assert_array(world.order).is_equal([World.Order.ATTACK_MOVE, 0, 0])
	assert_array(world.hp).is_equal([1, 1, 1])


## The same world with no prepare() call: Sim.step prepares a hand-built world on its first tick.
func test_the_phase_1_shaped_world_steps_ten_ticks_without_an_explicit_prepare() -> void:
	var world: World = _phase1_world()
	world.add_unit(1, 0, 10000, 10000)
	world.add_unit(1, 2, 10000, 20000)
	world.add_unit(2, 1, 40000, 40000)
	assert_bool(world.prepared).is_false()
	var order: Command = Command.attack_move(1, PackedInt32Array([1]), 30000, 10000)
	order.tick = 0
	var first: Array[Command] = [order]
	Sim.step(world, first)
	for _t: int in 9:
		Sim.step(world, [])
	assert_bool(world.prepared).is_true()
	assert_array([world.tick, world.dropped_commands]).is_equal([10, 0])
	assert_array(world.pos_x).is_equal([11200, 10000, 40000])
	assert_array(world.pos_y).is_equal([10000, 20000, 40000])
	assert_array(world.hp).is_equal([1, 1, 1])
	assert_array(world.type_names).is_equal(["Type", "Type", "Type"])


## The shape lists: the new ones are pinned by name, and every Packed*Array property is in
## exactly one array list and every int property in exactly one scalar list. A name in a list that
## is no property would make a list longer than the properties, so the sums are compared too.
func test_the_shape_lists_cover_every_array_and_int_property_once() -> void:
	var weapons: Array[String] = ["weapon_range", "weapon_min_range", "weapon_damage"]
	weapons.append_array(["weapon_cooldown", "weapon_projectile_speed", "weapon_vs_armour"])
	assert_array(World.WEAPON_ARRAYS).is_equal(weapons)
	var slots: Array[String] = ["proj_id", "proj_owner", "proj_weapon", "proj_target", "proj_x"]
	slots.append_array(["proj_y", "proj_aim_x", "proj_aim_y", "proj_ticks", "proj_free"])
	assert_array(World.PROJECTILE_ARRAYS).is_equal(slots)
	var map: Array[String] = ["terrain", "move_cost", "terrain_cost", "terrain_buildable"]
	assert_array(World.MAP_ARRAYS).is_equal(map + ["ore_cell"])
	assert_array(World.SCRATCH_ARRAYS).is_equal(["intent_x", "intent_y", "push_x", "push_y"])
	assert_array(World.RUNTIME_ARRAYS).is_equal(["events", "stats"])
	var hashed: Array[String] = ["tick", "next_id", "next_projectile_id", "dropped_commands"]
	hashed.append_array(["projectile_overflow", "spawn_refused", "player_count", "proj_free_top"])
	hashed.append_array(["map_version", "match_end_tick", "winner"])
	assert_array(World.HASHED_SCALARS).is_equal(hashed)
	var unhashed: Array[String] = ["map_w", "map_h", "map_cols", "map_rows", "rows_version"]
	unhashed.append_array(["flow_cells_per_tick", "native_phases"])  # The mask is never state (P54).
	unhashed.append_array(["_map_digest", "_map_digest_version"])  # The map digest cache (P31b).
	unhashed.append_array(RULES.keys())
	assert_array(World.UNHASHED_SCALARS).contains_exactly_in_any_order(unhashed)
	var array_lists: Array = [World.ROW_ARRAYS, World.TYPE_ARRAYS, World.WEAPON_ARRAYS]
	array_lists.append_array([World.PROJECTILE_ARRAYS, World.MAP_ARRAYS, World.SCRATCH_ARRAYS])
	array_lists.append_array([World.RUNTIME_ARRAYS, World.PLAYER_ARRAYS, World.ORE_ARRAYS])
	array_lists.append_array([World.GHOST_ARRAYS, World.DERIVED_ARRAYS])
	var scalar_lists: Array = [World.HASHED_SCALARS, World.UNHASHED_SCALARS]
	var packed: Array[String] = []
	var ints: Array[String] = []
	var not_int32: Array[String] = []
	var others: Array[String] = []
	var skipped: Array[String] = []
	for info: Dictionary in World.new().get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var kind: int = int(info["type"])
		var column: String = String(info["name"])
		if kind == TYPE_INT:
			ints.append(column)
		elif kind >= TYPE_PACKED_BYTE_ARRAY and kind <= TYPE_PACKED_VECTOR4_ARRAY:
			packed.append(column)
			if kind != TYPE_PACKED_INT32_ARRAY:
				not_int32.append(column)
		elif World.NON_STATE_MEMBERS.has(StringName(column)):
			skipped.append(column)
		else:
			others.append(column)
	assert_int(packed.size()).is_equal(98)
	assert_int(ints.size()).is_equal(52)
	# Every Packed*Array is an int32 table but the byte map tables and the names. Members that are
	# neither an int nor a Packed*Array sit in no list: the id tables, the stream, the four helper
	# objects and the bool `prepared`. The one non-state member, the kernels, is skipped by name, so
	# any other object member still fails here (ADR 0013 section 3).
	assert_array(World.NON_STATE_MEMBERS).is_equal([&"kernels"])
	assert_array(skipped).is_equal(["kernels"])
	var byte_tables: Array[String] = ["type_names", "terrain", "move_cost", "terrain_cost"]
	byte_tables.append("terrain_buildable")
	assert_array(not_int32).contains_exactly_in_any_order(byte_tables)
	var unlisted: Array[String] = ["type_ids", "weapon_ids", "terrain_ids", "rng", "prepared"]
	unlisted.append_array(["fog", "flow", "sep_grid", "target_grid"])
	assert_array(others).contains_exactly_in_any_order(unlisted)
	_assert_listed_once(packed, array_lists)
	_assert_listed_once(ints, scalar_lists)


## prepare() sizes the scratch arrays to max_rows, stats to the Stat count and every projectile
## slot array to max_projectiles, all slots free with slot 0 on top of the stack. Small rule
## values show the order. Later prepare() calls keep whatever the tick wrote since.
func test_prepare_sizes_the_fixed_capacity_arrays_and_a_second_call_keeps_them() -> void:
	var world: World = World.new()
	for column: StringName in World.SCRATCH_ARRAYS:
		assert_int(world.get(column).size()).is_equal(0)
	world.prepare()
	assert_int(world.stats.size()).is_equal(10)
	for column: StringName in World.SCRATCH_ARRAYS:
		assert_int(world.get(column).size()).override_failure_message(column).is_equal(256)
	for column: StringName in World.PROJECTILE_ARRAYS:
		assert_int(world.get(column).size()).override_failure_message(column).is_equal(512)
	assert_int(world.proj_free_top).is_equal(512)
	assert_array([world.proj_free[0], world.proj_free[1], world.proj_free[511]]).is_equal(
		[511, 510, 0]
	)
	assert_int(world.proj_free[world.proj_free_top - 1]).is_equal(0)
	assert_int(world.proj_id.count(0)).is_equal(512)
	var small: World = World.new()
	small.max_rows = 6
	small.max_projectiles = 4
	small.prepare()
	assert_array(small.proj_free).is_equal([3, 2, 1, 0])
	assert_int(small.proj_free_top).is_equal(4)
	assert_array(small.push_x).is_equal([0, 0, 0, 0, 0, 0])
	# A tick takes slot 0 for a shot and writes scratch and stats. prepare() must not undo any of
	# it, so every scratch array and every slot column (but the stack) gets its own sentinel.
	small.proj_free_top = 3
	var sentinels: Dictionary[StringName, int] = {}
	for column_name: StringName in World.SCRATCH_ARRAYS:
		sentinels[column_name] = 30 + sentinels.size()
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		if column_name != &"proj_free":
			sentinels[column_name] = 30 + sentinels.size()
	for column_name: StringName in sentinels:
		var column: PackedInt32Array = small.get(column_name)
		column[2] = sentinels[column_name]
	small.stats[World.Stat.PROJ_STEPS] = 9
	small.prepare()
	assert_array(small.proj_free).is_equal([3, 2, 1, 0])
	assert_int(small.proj_free_top).is_equal(3)
	for column_name: StringName in sentinels:
		var column: PackedInt32Array = small.get(column_name)
		var wanted: int = sentinels[column_name]
		assert_int(column[2]).override_failure_message(column_name).is_equal(wanted)
	assert_array([small.stats[5], small.stats.size()]).is_equal([9, 10])
	for column_name: StringName in World.SCRATCH_ARRAYS:
		assert_int(small.get(column_name).size()).override_failure_message(column_name).is_equal(6)
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		assert_int(small.get(column_name).size()).override_failure_message(column_name).is_equal(4)


## A 64 x 48 map has 64 columns and 48 rows, and a cell is `row * 64 + column`. A point outside
## the map goes to the nearest edge cell on each axis alone.
func test_cell_of_clamps_each_axis_into_the_map() -> void:
	var world: World = _open_world(64000, 48000)
	var last: int = 47 * 64 + 63
	# x, y, cell: the four corners, a tile edge, then points outside on one or both axes.
	var cases: Array[Array] = [
		[0, 0, 0],
		[63999, 0, 63],
		[0, 47999, 47 * 64],
		[63999, 47999, last],
		[999, 999, 0],
		[1000, 0, 1],
		[0, 1000, 64],
		[5500, 3500, 3 * 64 + 5],
		[-1, -1, 0],
		[-5000, 0, 0],
		[-5000, 5000, 5 * 64],
		[5000, -5000, 5],
		[64000, 0, 63],
		[0, 48000, 47 * 64],
		[999999, 999999, last],
		[999999, 5000, 5 * 64 + 63],
		[5000, 999999, 47 * 64 + 5],
	]
	for point: Array in cases:
		var cell: int = world.cell_of(int(point[0]), int(point[1]))
		assert_int(cell).override_failure_message(str(point)).is_equal(int(point[2]))
	# No map yet: the only answer that is never outside a map is 0.
	assert_array([World.new().cell_of(5000, 7000), World.new().cell_of(-1, -1)]).is_equal([0, 0])


## Open grass is terrain 0 and normal ground for the three classes, over the size rounded up to
## whole tiles. A size of 0 or less on either axis leaves no map on both, which is passable.
func test_prepare_derives_open_grass_from_the_map_size_rounded_up_to_whole_tiles() -> void:
	assert_int(World.GRASS_COST).is_equal(10)
	assert_int(World.GRASS_COST).is_equal(TerrainDef.new().cost[0])
	var standard: TerrainSetDef = load("res://data/terrain/standard.tres") as TerrainSetDef
	assert_array([World.GRASS_ID, standard.terrains[0].id]).is_equal([&"grass", &"grass"])
	# width, height, columns, rows
	var sizes: Array[Array] = [
		[64000, 48000, 64, 48],
		[1000, 1000, 1, 1],
		[1001, 1000, 2, 1],
		[2500, 600, 3, 1],
		[1, 1, 1, 1],
		[-5000, 1000, 0, 0],
		[1000, -5000, 0, 0],
		[0, 48000, 0, 0],
		[64000, 0, 0, 0],
	]
	for size: Array in sizes:
		var world: World = _open_world(int(size[0]), int(size[1]))
		var cells: int = int(size[2]) * int(size[3])
		assert_array([world.map_cols, world.map_rows]).is_equal([size[2], size[3]])
		assert_array([world.terrain.size(), world.terrain.count(0)]).is_equal([cells, cells])
		assert_array([world.move_cost.size(), world.move_cost.count(10)]).is_equal(
			[3 * cells, 3 * cells]
		)
		assert_array(world.terrain_cost).is_equal([10, 10, 10])
		assert_array(world.terrain_ids).is_equal([&"grass"])
		assert_int(world.map_version).is_equal(0)
		assert_bool(world.is_passable(0, 0)).override_failure_message(str(size)).is_true()
	# prepare() derives the grid once: a later call keeps what the world holds.
	var kept: World = _open_world(3000, 2000)
	kept.move_cost[7] = 0
	kept.prepare()
	assert_array([kept.move_cost[7], kept.move_cost.size()]).is_equal([0, 18])


## Besides grass, scrub (foot only), hills (every class, cost above 10) and rock, the map has a
## wheeled-only and a tracked-only terrain, so a swapped class block or a test for exactly 10 shows.
func test_is_passable_is_true_without_a_map_and_reads_the_cost_of_the_class_with_one() -> void:
	for cell: int in [0, -1]:
		assert_str(_classes(World.new(), cell)).is_equal("FWT")
	var scenario: ScenarioDef = _tile_scenario()
	scenario.map.terrain.terrains.append(_terrain("w", [0, 12, 0]))
	scenario.map.terrain.terrains.append(_terrain("t", [0, 0, 12]))
	scenario.map.rows = PackedStringArray(["wt^h", "h#^.", "#..h"])
	var world: World = World.from_scenario(scenario)
	# Cells 0 to 7 hold w, t, scrub, hills, hills, rock, scrub, grass; then cells outside.
	var expected: Dictionary[int, String] = {0: "W", 1: "T", 2: "F", 3: "FWT", 4: "FWT", 5: ""}
	expected.merge({6: "F", 7: "FWT", 8: "", -1: "", 12: "", 1000: ""})
	for cell: int in expected:
		assert_str(_classes(world, cell)).override_failure_message(str(cell)).is_equal(
			expected[cell]
		)
	# A class that does not exist is blocked, and so is a cell past a narrow map.
	assert_bool(world.is_passable(3, -1)).is_false()
	assert_bool(world.is_passable(3, 3)).is_false()
	assert_bool(_open_world(2000, 1000).is_passable(2, 0)).is_false()


## The map sets the size (not map_size_tiles), the terrain index is the position in the terrain
## set, and move_cost holds each class in its own block. Every terrain's costs are kept for
## set_terrain.
func test_from_scenario_copies_the_map_size_terrain_indexes_and_costs_per_class() -> void:
	var world: World = World.from_scenario(_tile_scenario())
	assert_array([world.map_cols, world.map_rows]).is_equal([4, 3])
	assert_array([world.map_w, world.map_h, world.map_version]).is_equal([4000, 3000, 0])
	assert_array(world.terrain).is_equal(TILE_TERRAIN)
	assert_array(world.move_cost).is_equal(TILE_FOOT + TILE_WHEELED + TILE_TRACKED)
	assert_array(world.terrain_cost).is_equal(TERRAIN_COSTS)
	# A terrain whose symbol is not one character fits no tile, but it keeps its index and costs.
	var odd: ScenarioDef = _tile_scenario()
	odd.map.terrain.terrains.append(_terrain("", [7, 8, 9]))
	var with_odd: World = World.from_scenario(odd)
	assert_array(with_odd.terrain).is_equal(TILE_TERRAIN)
	assert_array(with_odd.terrain_cost).is_equal(TERRAIN_COSTS + [7, 8, 9])


func test_from_scenario_without_a_usable_map_is_open_grass_of_the_scenario_size() -> void:
	# controls_test has had a map since P48, so the case clears the map of a copy of it (the loaded
	# resource is shared and stays as it is): what is left is the open grass of its 48 x 48 size.
	var no_map: ScenarioDef = (load(SCENARIO_PATH) as ScenarioDef).duplicate()
	no_map.map = null
	var controls: World = World.from_scenario(no_map)
	assert_array([controls.map_cols, controls.map_rows, controls.map_w]).is_equal([48, 48, MAP])
	assert_array([controls.terrain.count(0), controls.move_cost.count(10)]).is_equal([2304, 6912])
	var bad_symbol: ScenarioDef = _tile_scenario()
	bad_symbol.map.rows[1] = "h?^."
	var no_terrain: ScenarioDef = _tile_scenario()
	no_terrain.map.terrain = null
	var no_rows: ScenarioDef = _tile_scenario()
	no_rows.map.rows = PackedStringArray()
	for scenario: ScenarioDef in [bad_symbol, no_terrain, no_rows]:
		scenario.map_size_tiles = Vector2i(5, 2)
		var world: World = World.from_scenario(scenario)
		assert_array([world.map_cols, world.map_rows]).is_equal([5, 2])
		assert_array([world.map_w, world.map_h]).is_equal([5000, 2000])
		assert_array([world.terrain.count(0), world.move_cost.count(10)]).is_equal([10, 30])
		assert_array(world.terrain_cost).is_equal([10, 10, 10])


## The shipped arena (data/maps/perf_arena.tres): the ridge at columns 31 and 32 with its gap at
## row 27 by position, and the first scrub and water cell wherever P48 leaves them (test_defs_data
## pins that both exist). The terrain set is grass, sand, scrub, rock, water.
func test_the_perf_arena_map_is_loaded_into_the_world() -> void:
	var world: World = World.from_scenario(load(ARENA_PATH) as ScenarioDef)
	var size: Array[int] = [world.map_cols, world.map_rows, world.map_w, world.map_h]
	assert_array(size).is_equal([64, 64, 64000, 64000])
	assert_array([world.terrain.size(), world.move_cost.size()]).is_equal([4096, 12288])
	var costs: Array[int] = [10, 10, 10, 10, 10, 10, 10, 0, 0, 0, 0, 0, 0, 0, 0]
	assert_array(world.terrain_cost).is_equal(costs + [10, 10, 10])  # The sixth terrain is ore.
	# x, y (a tile centre), terrain, the classes that can stand there
	var spots: Array[Array] = [[31500, 500, 3, ""], [32500, 63500, 3, ""], [31500, 27500, 0, "FWT"]]
	for spot: Array in spots:
		var cell: int = world.cell_of(int(spot[0]), int(spot[1]))
		assert_int(world.terrain[cell]).override_failure_message(str(spot)).is_equal(spot[2])
		assert_str(_classes(world, cell)).override_failure_message(str(spot)).is_equal(spot[3])
	# terrain, the classes that can stand on the first such cell
	for kind: Array in [[2, "F"], [4, ""]]:
		var first: int = world.terrain.find(int(kind[0]))
		assert_int(first).override_failure_message(str(kind)).is_greater_equal(0)
		assert_str(_classes(world, first)).override_failure_message(str(kind)).is_equal(kind[1])


## set_terrain takes the new terrain's cost for each class from the table, bumps map_version on
## every valid call (also for the same terrain), and ignores a cell or terrain that does not exist.
func test_set_terrain_rewrites_the_cell_and_its_costs_and_bumps_map_version() -> void:
	var world: World = World.from_scenario(_tile_scenario())
	world.set_terrain(0, 3)
	var terrain: Array[int] = TILE_TERRAIN.duplicate()
	var costs: Array[int] = TILE_FOOT + TILE_WHEELED + TILE_TRACKED
	terrain[0] = 3
	for block: int in 3:
		costs[block * 12] = 0
	assert_array(world.terrain).is_equal(terrain)
	assert_array(world.move_cost).is_equal(costs)
	assert_int(world.map_version).is_equal(1)
	world.set_terrain(5, 2)
	terrain[5] = 2
	costs[5] = 25
	costs[12 + 5] = 15
	costs[24 + 5] = 40
	assert_array(world.terrain).is_equal(terrain)
	assert_array(world.move_cost).is_equal(costs)
	assert_int(world.map_version).is_equal(2)
	world.set_terrain(5, 2)
	assert_int(world.map_version).is_equal(3)
	for bad: Array in [[-1, 0], [12, 0], [0, -1], [0, 4]]:
		world.set_terrain(int(bad[0]), int(bad[1]))
	assert_array(world.terrain).is_equal(terrain)
	assert_array(world.move_cost).is_equal(costs)
	assert_int(world.map_version).is_equal(3)
	# No map: nothing to change. Open grass knows the terrain 0 only.
	var bare: World = World.new()
	bare.set_terrain(0, 0)
	var grass: World = _open_world(3000, 1000)
	grass.set_terrain(1, 1)
	assert_array([bare.map_version, grass.map_version]).is_equal([0, 0])
	grass.set_terrain(1, 0)
	assert_int(grass.map_version).is_equal(1)


## prepare() sizes the helpers from the World. A 5.5 x 3 tile map shows columns and rows apart and
## the rounding up (6 columns; one row of two 4-tile columns), and 2 players, 7 rows and 3 slots
## show where each size comes from.
func test_prepare_sizes_the_helpers_from_the_map_the_players_and_the_rules() -> void:
	var world: World = World.new()
	assert_bool(world.prepared).is_false()
	world.map_w = 5500
	world.map_h = 3000
	world.max_rows = 7
	world.flow_cache_size = 3
	world.add_unit(2, 0, 500, 500)
	world.prepare()
	assert_bool(world.prepared).is_true()
	assert_array([world.fog.cols, world.fog.rows, world.fog.player_count]).is_equal([6, 3, 2])
	assert_int(world.fog.visible.size()).is_equal(36)
	assert_array([world.flow.cols, world.flow.rows, world.flow.classes]).is_equal([6, 3, 3])
	assert_array([world.flow.fields.size(), world.flow.fields[2].cost.size()]).is_equal([3, 40])
	var sep: SpatialGrid = world.sep_grid
	assert_array([sep.cols, sep.rows, sep.cell_milli, sep.next.size()]).is_equal([6, 3, 1000, 7])
	var target: SpatialGrid = world.target_grid
	var four_tiles: Array[int] = [2, 1, 4000, 7]
	assert_array([target.cols, target.rows, target.cell_milli, target.next.size()]).is_equal(
		four_tiles
	)


## A second prepare() and a Sim.step (which prepares first) change no helper: every object and array
## stays the same buffer with the same contents, after a rebuilt grid, a stamped fog and a finished
## flow slot. configure() would re-create or clear each of them. The tick has no order and no
## move, so it writes no helper, except the separation grid, which it rebuilds from the same
## positions (P39b), and player 1's fog update (P46), which at tick 0 empties its dirty list: the
## counts, the `listed` marks and the flag change, so the case reads the `dirty` block (an update
## never clears an entry of it) and not `listed`. The first rule that writes more updates this case.
func test_a_second_prepare_keeps_the_helper_state() -> void:
	var world: World = World.new()
	world.map_w = 6000
	world.map_h = 4000
	# The tick separates since P39b, which reads the radius of every unit's type: prepare() pads it.
	world.type_ids.append(&"tank")
	world.add_unit(1, 0, 1500, 500)
	world.add_unit(2, 0, 4500, 3500)
	world.prepare()
	world.sep_grid.rebuild(world.pos_x, world.pos_y, 2)
	world.target_grid.rebuild(world.pos_x, world.pos_y, 2)
	world.fog.stamp(2, 9, world.fog.add_mask(2000), 1)
	var slot: int = world.flow.acquire(5, World.MoveClass.FOOT, 0, 4)
	world.flow.advance(world.move_cost, 100)
	assert_bool(world.flow.fields[slot].complete).is_true()
	var before: Array = _helper_state(world, slot)
	var contents: Array = []
	for item: Variant in before:
		contents.append(item if item is Object else item.duplicate())
	Sim.step(world, [])
	world.prepare()
	var after: Array = _helper_state(world, slot)
	var changed: Array[int] = []
	for i: int in before.size():
		if not is_same(before[i], after[i]) or after[i] != contents[i]:
			changed.append(i)
	assert_array(changed).is_empty()
	# The state is not the cleared one, or a configure() would not show.
	assert_int(world.fog.visible.count(0)).is_less(world.fog.visible.size())
	assert_int(world.sep_grid.head.count(-1)).is_less(world.sep_grid.head.size())


## After prepare(), an owner above player_count and a row beyond max_rows are refused with nothing
## else changed. Before it a spawn is never refused (from_scenario relies on that). A row that
## remove_dead freed can be filled again.
func test_add_unit_refuses_an_owner_and_a_row_the_prepared_world_cannot_hold() -> void:
	var early: World = World.new()
	early.max_rows = 1
	assert_array([early.add_unit(1, 0, 0, 0), early.add_unit(5, 0, 0, 0)]).is_equal([1, 2])
	assert_int(early.spawn_refused).is_equal(0)
	var world: World = World.new()
	world.max_rows = 3
	world.add_unit(2, 0, 1000, 1000)
	world.prepare()
	world.events.clear()
	assert_int(world.add_unit(3, 0, 1, 1)).is_equal(0)
	assert_array([world.spawn_refused, world.unit_count(), world.next_id]).is_equal([1, 1, 2])
	assert_array([world.player_count, world.rows_version, world.events.size()]).is_equal([2, 1, 0])
	assert_int(world.add_unit(2, 0, 2000, 1000)).is_equal(2)
	assert_int(world.add_unit(0, 0, 3000, 1000)).is_equal(3)
	assert_int(world.add_unit(1, 0, 4000, 1000)).is_equal(0)
	assert_array([world.spawn_refused, world.unit_count(), world.next_id]).is_equal([2, 3, 4])
	world.hp[0] = 0
	world.remove_dead()
	assert_int(world.add_unit(1, 0, 4000, 1000)).is_equal(4)


## set_terrain() tells the flow cache the new map_version: a slot a unit points at is re-keyed to
## the new version, one nobody points at is dropped, and acquire() under the new version finds the
## re-keyed slot instead of a second slot with the same key.
func test_set_terrain_invalidates_the_flow_cache_under_the_new_map_version() -> void:
	var world: World = World.from_scenario(_tile_scenario())
	var foot: int = World.MoveClass.FOOT
	var held: int = world.flow.acquire(1, foot, world.map_version, 5)
	var spare: int = world.flow.acquire(2, foot, world.map_version, 6)
	world.add_unit(0, 0, 500, 500)
	world.field[0] = held
	world.flow.recount(world.field, 1)
	assert_array([world.flow.refs(held), world.flow.refs(spare)]).is_equal([1, 0])
	world.set_terrain(0, 3)
	assert_int(world.map_version).is_equal(1)
	assert_array([world.flow.key_version[held], world.flow.status[held]]).is_equal(
		[1, FlowCache.Status.WAITING]
	)
	assert_int(world.flow.status[spare]).is_equal(FlowCache.Status.FREE)
	assert_int(world.flow.acquire(1, foot, world.map_version, 7)).is_equal(held)


## A World with a size and no map, prepared: open grass.
func _open_world(width: int, height: int) -> World:
	var world: World = World.new()
	world.map_w = width
	world.map_h = height
	world.prepare()
	return world


## A scenario whose map is TILES over a terrain set of grass, scrub, hills and rock. Its
## map_size_tiles is not the map's size, so a test sees which one the world takes.
func _tile_scenario() -> ScenarioDef:
	var terrains: TerrainSetDef = TerrainSetDef.new()
	terrains.terrains.append(_terrain(".", [10, 10, 10]))
	terrains.terrains.append(_terrain("^", [10, 0, 0]))
	terrains.terrains.append(_terrain("h", [25, 15, 40]))
	terrains.terrains.append(_terrain("#", [0, 0, 0]))
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(TILES)
	map.terrain = terrains
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(9, 9)
	scenario.map = map
	return scenario


## The movement classes that may stand on `cell`: F foot, W wheeled, T tracked.
func _classes(world: World, cell: int) -> String:
	var letters: String = ""
	for move_class: int in 3:
		letters += "FWT"[move_class] if world.is_passable(cell, move_class) else ""
	return letters


func _terrain(symbol: String, cost: Array[int]) -> TerrainDef:
	var terrain: TerrainDef = TerrainDef.new()
	terrain.symbol = symbol
	terrain.cost = PackedInt32Array(cost)
	return terrain


## The five Phase 1 type arrays and nothing else, as test_sim_step builds a world.
func _phase1_world() -> World:
	var world: World = World.new()
	world.map_w = MAP
	world.map_h = MAP
	for speed: int in [120, 0, 60]:
		world.type_ids.append(&"type")
		world.type_speed.append(speed)
		world.type_radius.append(400)
		world.type_selection_radius.append(500)
		world.type_spacing.append(1200)
	return world


## The helper objects and the arrays that configure() would re-create: the fog grids (the dirty
## block, not its marks, see above), both spatial grids, the cache's state arrays and the cost
## array of slot `slot`.
func _helper_state(world: World, slot: int) -> Array:
	var state: Array = [world.fog, world.flow, world.sep_grid, world.target_grid]
	state.append_array([world.fog.visible, world.fog.explored, world.fog.dirty])
	state.append_array([world.sep_grid.head, world.sep_grid.next])
	state.append_array([world.target_grid.head, world.target_grid.next])
	state.append_array([world.flow.key_goal, world.flow.status, world.flow.fields[slot].cost])
	return state


func _assert_columns(world: World, expected: Dictionary[StringName, Array]) -> void:
	for column: StringName in expected:
		assert_array(world.get(column)).override_failure_message(column).is_equal(expected[column])


## Every name of `names` is in exactly one of `lists`, and the lists hold nothing else.
func _assert_listed_once(names: Array[String], lists: Array) -> void:
	var listed: int = 0
	for list: Array in lists:
		listed += list.size()
	assert_int(listed).is_equal(names.size())
	for property: String in names:
		var found: int = 0
		for list: Array in lists:
			found += int(list.has(StringName(property)))
		assert_int(found).override_failure_message(property).is_equal(1)
