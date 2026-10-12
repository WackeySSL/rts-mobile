extends GdUnitTestSuite
## World v1, parts 1 and 2 (plan P29a, P29a2): the rule ints and the default stream of a
## hand-built world, type table padding, add_unit's new columns and event, the Phase 1-shaped
## world through Sim.step, the shape lists and the sizes prepare() gives the fixed-capacity
## arrays. Numbers are literals, so no data file can agree with a wrong rule. A push_error would
## fail verify, which scans the log.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const MAP: int = 48000
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
}


func test_the_enums_and_the_event_stride_are_the_contract() -> void:
	var stat: Dictionary = {"FLOW_CELLS": 0, "LINE_CHECKS": 1, "SEP_PAIRS": 2}
	stat.merge({"TARGET_CANDIDATES": 3, "FOG_CELLS": 4, "PROJ_STEPS": 5, "ROWS_COMPACTED": 6})
	assert_dict(World.Stat).is_equal(stat)
	assert_dict(World.Order).is_equal({"IDLE": 0, "ATTACK_MOVE": 1, "MOVE": 2, "ATTACK": 3})
	assert_dict(World.Armour).is_equal({"INFANTRY": 0, "LIGHT": 1, "HEAVY": 2, "BUILDING": 3})
	assert_dict(World.MoveClass).is_equal({"FOOT": 0, "WHEELED": 1, "TRACKED": 2})
	assert_dict(World.Event).is_equal({"SPAWNED": 1, "DIED": 2, "SHOT": 3, "IMPACT": 4})
	var nav: Dictionary = {"NONE": 0, "DIRECT": 1, "FIELD": 2, "HOLD": 3, "CHASE": 4}
	assert_dict(World.NavMode).is_equal(nav)
	assert_array([World.EVENT_STRIDE, World.STATE_FORMAT]).is_equal([8, 1])


## A Phase 1-shaped world: the rule ints and the stream exist, player_count follows the owners
## and never drops, and a type with no max hp entry gives 1 hp.
func test_a_hand_built_world_has_the_rule_defaults_and_the_default_stream() -> void:
	var world: World = _phase1_world()
	var defaults: RulesDef = RulesDef.new()
	var fields: Array[String] = []
	for info: Dictionary in defaults.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			fields.append(String(info["name"]))
	assert_int(fields.size()).is_equal(15)
	for field: String in fields:
		assert_that(world.get(field)).override_failure_message(field).is_equal(defaults.get(field))
	for field: String in RULES:
		assert_that(world.get(field)).override_failure_message(field).is_equal(RULES[field])
	assert_array(world.rng.state()).is_equal(DetRandom.create(0, DetRandom.STREAM_SIM).state())
	assert_int(world.next_projectile_id).is_equal(1)
	var zeros: Array[String] = ["player_count", "spawn_refused", "projectile_overflow"]
	zeros.append_array(["proj_free_top", "map_cols", "map_rows", "map_version"])
	for scalar: String in zeros:
		assert_int(world.get(scalar)).override_failure_message(scalar).is_equal(0)
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
	assert_array(World.MAP_ARRAYS).is_equal(["terrain", "move_cost"])
	assert_array(World.SCRATCH_ARRAYS).is_equal(["intent_x", "intent_y", "push_x", "push_y"])
	assert_array(World.RUNTIME_ARRAYS).is_equal(["events", "stats"])
	var hashed: Array[String] = ["tick", "next_id", "next_projectile_id", "dropped_commands"]
	hashed.append_array(["projectile_overflow", "spawn_refused", "player_count", "proj_free_top"])
	hashed.append("map_version")
	assert_array(World.HASHED_SCALARS).is_equal(hashed)
	var unhashed: Array[String] = ["map_w", "map_h", "map_cols", "map_rows", "rows_version"]
	unhashed.append("flow_cells_per_tick")
	unhashed.append_array(RULES.keys())
	assert_array(World.UNHASHED_SCALARS).contains_exactly_in_any_order(unhashed)
	var array_lists: Array = [World.ROW_ARRAYS, World.TYPE_ARRAYS, World.WEAPON_ARRAYS]
	array_lists.append_array([World.PROJECTILE_ARRAYS, World.MAP_ARRAYS, World.SCRATCH_ARRAYS])
	array_lists.append(World.RUNTIME_ARRAYS)
	var scalar_lists: Array = [World.HASHED_SCALARS, World.UNHASHED_SCALARS]
	var packed: Array[String] = []
	var ints: Array[String] = []
	var not_int32: Array[String] = []
	var others: Array[String] = []
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
		else:
			others.append(column)
	assert_int(packed.size()).is_equal(54)
	assert_int(ints.size()).is_equal(29)
	# Every Packed*Array is an int32 table but the byte map tables and the names. Members that are
	# neither an int nor a Packed*Array sit in no list: the id tables and the stream. P31a adds
	# the helper objects here.
	assert_array(not_int32).contains_exactly_in_any_order(["type_names", "terrain", "move_cost"])
	var unlisted: Array[String] = ["type_ids", "weapon_ids", "terrain_ids", "rng"]
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
	assert_int(world.stats.size()).is_equal(7)
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
	assert_array([small.stats[5], small.stats.size()]).is_equal([9, 7])
	for column_name: StringName in World.SCRATCH_ARRAYS:
		assert_int(small.get(column_name).size()).override_failure_message(column_name).is_equal(6)
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		assert_int(small.get(column_name).size()).override_failure_message(column_name).is_equal(4)


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
