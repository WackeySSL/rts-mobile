extends "res://tests/ai/support/support_suite.gd"
## The opponent's ground support (plan row P283, ADR 0037): the defs, medic production, vehicle
## repair and medic orders of `AiRepair`, the roles and the build order.

# --- The defs ---------------------------------------------------------------------------------


func test_the_level_fields_default_off() -> void:
	var level: AiDifficultyDef = AiDifficultyDef.new()
	assert_array([level.repair_retreat_percent, level.medic_per_squads]).is_equal([0, 0])


func test_a_level_with_both_off_sends_nothing_and_resolves_nothing() -> void:
	var world: World = _world()
	_add(world, "tank", 4000, 9000, 10)
	var repair: AiRepair = AiRepair.create(_def(), _level(0, 0))
	assert_array(_repair(world, _memory(), repair)).is_empty()
	assert_int(repair.repairs + repair.returns + repair.medic_orders).is_equal(0)


# --- Production: the medics -------------------------------------------------------------------


func test_one_medic_is_queued_per_medic_per_squads_infantry_squads_ahead_of_the_draw() -> void:
	var world: World = _world()
	for at: int in 4:
		_add(world, "squad", 4000 + at * 500, 6000)
	var production: AiProduction = _production(2)
	var sent: Array[Command] = _produce(production, world, _memory())
	assert_int(_queued(sent, world, "medic")).is_equal(1)
	assert_int(sent[0].payload[0]).is_equal(Worlds.type_of(world, "medic"))
	assert_int(production.medics_queued).is_equal(1)


func test_the_medics_alive_and_queued_count_toward_the_wish() -> void:
	var world: World = _world()
	for at: int in 4:
		_add(world, "squad", 4000 + at * 500, 6000)
	# Four squads, one per two: two medics wanted; one lives, so one more is queued, and then none.
	_add(world, "medic", 3000, 6000)
	var production: AiProduction = _production(2)
	var loop: MatchLoop = AiRig.loop_of(world)
	var memory: AiMemory = _memory()
	var first: Array[Command] = _produce(production, world, memory)
	assert_int(_queued(first, world, "medic")).is_equal(1)
	AiRig.step(world, loop, first)
	var second: Array[Command] = _produce(production, world, memory)
	assert_int(_queued(second, world, "medic")).is_equal(0)


func test_fewer_squads_than_one_group_or_a_level_without_medics_queue_none() -> void:
	var world: World = _world()
	_add(world, "squad", 4000, 6000)
	assert_int(_queued(_produce(_production(2), world, _memory()), world, "medic")).is_equal(0)
	for at: int in 6:
		_add(world, "squad", 4000 + at * 500, 7000)
	assert_int(_queued(_produce(_production(0), world, _memory()), world, "medic")).is_equal(0)


func test_a_roster_without_the_medic_type_queues_no_medic_and_changes_no_draw() -> void:
	var world: World = _world()
	for at: int in 4:
		_add(world, "squad", 4000 + at * 500, 6000)
	var bare: World = _world(true, false)
	for at: int in 4:
		_add(bare, "squad", 4000 + at * 500, 6000)
	var with_medics: Array[Command] = _produce(_production(2), bare, _memory())
	var without: Array[Command] = _produce(_production(0), bare, _memory())
	assert_int(with_medics.size()).is_equal(without.size())
	for at: int in without.size():
		assert_array(with_medics[at].payload).is_equal(without[at].payload)


# --- AiRepair: vehicles -----------------------------------------------------------------------


func test_a_vehicle_under_the_percent_is_sent_to_the_repair_building_with_one_repair() -> void:
	var world: World = _world()
	var hurt: int = _add(world, "tank", 4000, 9000, 39)
	var fit: int = _add(world, "tank", 5000, 9000, 40)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	var sent: Array[Command] = _repair(world, memory, repair)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.REPAIR)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([hurt]))
	assert_int(sent[0].target_id).is_equal(_shed_id(world))
	assert_int(repair.repairs).is_equal(1)
	assert_bool(fit > 0).is_true()
	# The key of the shed's tile for the vehicle class is the repair owner's, and one order only.
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(1)
	# Nothing more is sent, and the key goes once the sent vehicle no longer moves (it is idle here).
	assert_array(_repair(world, memory, repair)).is_empty()
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)


func test_the_tanker_and_a_unit_of_a_wave_are_never_sent() -> void:
	var world: World = _world()
	_add(world, "tanker", 4000, 9000, 5)
	var tank: int = _add(world, "tank", 5000, 9000, 5)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	memory.commands_left = 99
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()


func test_a_repaired_vehicle_goes_back_to_the_staging_point_and_the_key_goes() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	world.hp[world.index_of(tank)] = 100
	var sent: Array[Command] = _repair(world, memory, repair)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.MOVE)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([8500, 8500])
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)
	assert_int(repair.returns).is_equal(1)


func test_a_vehicle_waits_while_hurt_and_goes_home_when_the_building_dies() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	assert_array(_repair(world, memory, repair)).is_empty()
	world.hp[world.index_of(_shed_id(world))] = 0
	world.build_left[world.index_of(_shed_id(world))] = 1
	var sent: Array[Command] = _repair(world, memory, repair)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.MOVE)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))


func test_no_repair_building_no_order() -> void:
	var world: World = _world(false)
	_add(world, "tank", 4000, 9000, 5)
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_array(_repair(world, _memory(), repair)).is_empty()


func test_a_full_goal_cache_holds_the_order_back_until_a_key_is_free() -> void:
	var world: World = _world()
	_add(world, "tank", 4000, 9000, 5)
	var memory: AiMemory = _memory()
	for at: int in memory.goal_keys_max:
		assert_bool(memory.add_goal_key(at, 0, AiMemory.FOOT, AiMemory.Owner.ARMY)).is_true()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_array(_repair(world, memory, repair)).is_empty()
	assert_int(memory.goal_keys()).is_equal(memory.goal_keys_max)
	memory.release_owner(AiMemory.Owner.ARMY)
	assert_int(_repair(world, memory, repair).size()).is_equal(1)


func test_without_budget_nothing_is_sent_and_the_vehicle_is_asked_again() -> void:
	var world: World = _world()
	_add(world, "tank", 4000, 9000, 5)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	_fill(world, memory)
	memory.commands_left = 0
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()
	assert_int(_repair(world, memory, repair).size()).is_equal(1)


# --- AiRepair: medics -------------------------------------------------------------------------


func test_the_medics_follow_a_wave_with_attack_move_and_come_home_when_it_is_over() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000)
	var medic: int = _add(world, "medic", 3000, 9000)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(0, 4))
	# No wave: no order, the medic waits at the rally point.
	assert_array(_repair(world, memory, repair)).is_empty()
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	memory.commands_left = 99
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.ATTACK_MOVE)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([medic]))
	assert_array([out[0].target_x, out[0].target_y]).is_equal([20500, 12500])
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)
	# The same wave and goal: nothing more.
	out.clear()
	memory.commands_left = 99
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()
	# The wave is disbanded: the medics go to the staging point with a MOVE, never an ATTACK.
	memory.squad_role[WAVE] = NONE
	memory.squad_state[WAVE] = AiMemory.SquadState.HOME
	memory.commands_left = 99
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.MOVE)
	assert_array([out[0].target_x, out[0].target_y]).is_equal([8500, 8500])
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)
	out.clear()
	memory.commands_left = 99
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()


func test_a_new_medic_joins_a_wave_in_the_field_and_a_moved_goal_is_followed() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000)
	var first: int = _add(world, "medic", 3000, 9000)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(0, 4))
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	memory.commands_left = 99
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	var second: int = _add(world, "medic", 3500, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	memory.commands_left = 99
	out.clear()
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([first, second]))
	memory.squad_goal_x[WAVE] = 18
	memory.commands_left = 99
	out.clear()
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].target_x).is_equal(18500)
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)


func test_a_level_without_medics_leaves_them_alone() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000)
	_add(world, "medic", 3000, 9000)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	memory.commands_left = 99
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()


# --- The roles and the build order -------------------------------------------------------------


func test_the_role_bits_are_the_move_classes_of_the_rules() -> void:
	assert_int(AiRepair.FOOT_CLASS).is_equal(1 << World.MoveClass.FOOT)
	assert_int(AiRepair.VEHICLE_CLASSES).is_equal(
		(1 << World.MoveClass.WHEELED) | (1 << World.MoveClass.TRACKED)
	)


func test_the_repair_building_and_the_medic_are_found_by_role_not_by_id() -> void:
	var view: PlayerView = PlayerView.of(_world(), 1)
	var shed: int = AiRepair.role_type_of(view, view.type_faction[0], true)
	var medic: int = AiRepair.role_type_of(view, view.type_faction[0], false)
	assert_int(shed).is_equal(view.type_index_of(&"shed"))
	assert_int(medic).is_equal(view.type_index_of(&"medic"))
	var bare: PlayerView = PlayerView.of(_world(false, false), 1)
	assert_int(AiRepair.role_type_of(bare, bare.type_faction[0], true)).is_equal(NONE)
	assert_int(AiRepair.role_type_of(bare, bare.type_faction[0], false)).is_equal(NONE)


func test_the_economy_builds_the_repair_building_after_the_factory_only_when_the_level_uses_it(
) -> void:
	assert_array(_economy_queues(_world(true, true, false), 40)).contains(["shed"])
	assert_array(_economy_queues(_world(true, true, false), 0)).not_contains(["shed"])
