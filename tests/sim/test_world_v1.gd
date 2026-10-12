extends GdUnitTestSuite
## World v1, part 1 (plan P29a): the rule ints and the default stream of a hand-built world, type
## table padding, add_unit's new columns and event, and the Phase 1-shaped world through
## Sim.step. Numbers are literals, so no data file can agree with a wrong rule. A push_error
## would fail verify, which scans the log.

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
	for player: int in [2, 1, 3, 1]:
		world.add_unit(player, 0, 1000, 1000)
	assert_int(world.player_count).is_equal(3)
	assert_array(world.hp).is_equal([1, 1, 1, 1])


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
	assert_array(world.events.slice(8, 16)).is_equal([1, 2, 10, 20, 1, 1, 0, 0])
	assert_int(world.events.size()).is_equal(3 * World.EVENT_STRIDE)
	assert_array([world.rows_version, world.next_id]).is_equal([3, 4])


## Three types as in test_sim_step: speed 120, 0 and 60. A lone mover keeps exact Phase 1 numbers
## in every later phase: nothing else is near it and no type has a weapon.
func test_the_phase_1_shaped_world_steps_ten_ticks() -> void:
	var world: World = _phase1_world()
	world.add_unit(1, 0, 10000, 10000)
	world.add_unit(1, 2, 10000, 20000)
	world.add_unit(2, 1, 40000, 40000)
	world.prepare()
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
