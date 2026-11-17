extends "res://tests/ai/support/support_suite.gd"
## The ground support next to the army (P283 round 1): slots, takeover by the army, retreating
## waves, medic phases and the mixed wave at the key cap.

# --- Round 1: slots, takeover, wave members, keys --------------------------------------------


func test_at_most_the_repair_slots_of_the_building_are_in_flight() -> void:
	var world: World = _world()
	var first: int = _add(world, "tank", 4000, 9000, 10)
	var second: int = _add(world, "tank", 4500, 9000, 10)
	var third: int = _add(world, "tank", 5000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	var sent: Array[Command] = _repair(world, memory, repair)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([first, second]))
	assert_bool(third > 0).is_true()
	# The slots are full while both are hurt: the third waits.
	assert_array(_repair(world, memory, repair)).is_empty()
	assert_int(repair.repairs).is_equal(2)


func test_a_vehicle_that_the_army_re_ordered_and_is_still_hurt_is_sent_again() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	# AiArmy's return moved the home goal and ordered the vehicle to the staging point.
	memory.squad_goal_x[HOME] = 8
	memory.squad_goal_y[HOME] = 8
	var again: Array[Command] = _repair(world, memory, repair)
	assert_int(again.size()).is_equal(1)
	assert_int(again[0].type).is_equal(Command.Type.REPAIR)
	assert_array(again[0].unit_ids).is_equal(PackedInt32Array([tank]))


func test_a_dead_building_sends_no_move_to_a_vehicle_that_joined_a_wave() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	world.build_left[world.index_of(_shed_id(world))] = 1
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var out: Array[Command] = []
	memory.commands_left = 99
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()


func test_only_hard_repairs_the_members_of_a_retreating_wave() -> void:
	for wave_retreat: int in [0, 1]:
		var world: World = _world()
		var tank: int = _add(world, "tank", 4000, 9000, 10)
		var memory: AiMemory = _memory()
		_fill(world, memory)
		_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
		memory.squad_state[WAVE] = AiMemory.SquadState.RETREAT
		var repair: AiRepair = AiRepair.create(_def(), _level(40, 0, wave_retreat))
		var out: Array[Command] = []
		repair.run(PlayerView.of(world, 1), memory, out)
		assert_int(out.size()).is_equal(wave_retreat)
		if wave_retreat == 1:
			assert_int(out[0].type).is_equal(Command.Type.REPAIR)


func test_a_repaired_vehicle_goes_back_to_the_home_goal_not_only_the_staging_point() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	memory.squad_goal_x[HOME] = 12
	memory.squad_goal_y[HOME] = 12
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	world.hp[world.index_of(tank)] = 100
	var sent: Array[Command] = _repair(world, memory, repair)
	assert_int(sent[0].type).is_equal(Command.Type.ATTACK_MOVE)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([12500, 12500])


func test_the_repair_key_goes_when_the_sent_vehicles_stand_still_and_not_before() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	world.order[world.index_of(tank)] = World.Order.MOVE
	assert_array(_repair(world, memory, repair)).is_empty()
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(1)
	# It arrived (idle) and is being repaired (hp rose): the key goes and nothing is sent again.
	world.order[world.index_of(tank)] = World.Order.IDLE
	world.hp[world.index_of(tank)] += 30
	assert_array(_repair(world, memory, repair)).is_empty()
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)


# --- Round 1: medics ---------------------------------------------------------------------------


func test_a_retreating_wave_sends_its_medics_home_with_move() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000)
	var medic: int = _add(world, "medic", 3000, 9000)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(0, 4))
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	memory.squad_state[WAVE] = AiMemory.SquadState.RETREAT
	memory.commands_left = 99
	out.clear()
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.MOVE)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([medic]))


func test_a_dead_medic_does_not_make_the_group_follow_again() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000)
	var first: int = _add(world, "medic", 3000, 9000)
	var second: int = _add(world, "medic", 3500, 9000)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(0, 4))
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([first, second]))
	memory.own_mobile_id.remove_at(memory.own_mobile_id.find(second))
	memory.commands_left = 99
	out.clear()
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()


func test_the_medics_never_get_attack_or_repair_in_any_phase() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var medic: int = _add(world, "medic", 3000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 4, 1))
	var states: Array[int] = [
		AiMemory.SquadState.HOME,
		AiMemory.SquadState.WAVE,
		AiMemory.SquadState.RETREAT,
		AiMemory.SquadState.HOME
	]
	var seen: int = 0
	for state: int in states:
		_fill(world, memory)
		if state != AiMemory.SquadState.HOME:
			_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
			memory.squad_state[WAVE] = state
		memory.commands_left = 99
		var out: Array[Command] = []
		repair.run(PlayerView.of(world, 1), memory, out)
		for command: Command in out:
			if command.unit_ids.has(medic):
				seen += 1
				assert_int(command.type).is_in([Command.Type.MOVE, Command.Type.ATTACK_MOVE])
	assert_int(seen).is_greater(0)


# --- Round 1: roles, production and the order --------------------------------------------------


func test_an_armed_healer_is_no_medic_and_a_building_without_slots_is_no_repair_building() -> void:
	var view: PlayerView = PlayerView.of(_world(true, true, true, true), 1)
	var faction: int = view.type_faction[0]
	assert_int(AiRepair.role_type_of(view, faction, false)).is_equal(view.type_index_of(&"medic"))
	assert_int(AiRepair.role_type_of(view, faction, true)).is_equal(view.type_index_of(&"shed"))


func test_a_queued_medic_alone_stops_a_second_one() -> void:
	var world: World = _world()
	for at: int in 2:
		_add(world, "squad", 4000 + at * 500, 6000)
	var production: AiProduction = _production(2)
	var loop: MatchLoop = AiRig.loop_of(world)
	var memory: AiMemory = _memory()
	var first: Array[Command] = _produce(production, world, memory)
	assert_int(_queued(first, world, "medic")).is_equal(1)
	AiRig.step(world, loop, first)
	assert_int(_queued(_produce(production, world, memory), world, "medic")).is_equal(0)


func test_the_repair_building_follows_the_factory_or_ends_the_order_without_one() -> void:
	var world: World = _world(true, true, false)
	assert_array(_order_of(world, [&"barracks", &"factory", &"hq"] as Array[StringName])).is_equal(
		[&"barracks", &"factory", &"shed", &"hq"]
	)
	assert_array(_order_of(world, [&"barracks", &"hq"] as Array[StringName])).is_equal(
		[&"barracks", &"hq", &"shed"]
	)


# --- Round 1: the army and the repairs on one memory at the key cap -----------------------------


func test_a_mixed_wave_launches_and_retargets_while_a_repair_is_in_flight_at_cap_four() -> void:
	var world: World = _world()
	_add(world, "squad", 4000, 6000)
	_add(world, "squad", 4500, 6000)
	_add(world, "tank", 5000, 6000)
	var hurt: int = _add(world, "tank", 5500, 6000, 10)
	var def: OpponentDef = _def()
	def.goal_keys_max = 4
	def.scout_type = &"no_scout"
	var level: AiDifficultyDef = _level(40, 0)
	level.wave_first_tick = 100
	level.wave_first_strength = 100
	level.wave_jitter_ticks = 0
	level.reaction_ticks = 30
	level.all_in_tick = 0
	var intel: AiIntel = AiIntel.create(def, level, 1)
	var army: AiArmy = AiArmy.create(def, level, 1)
	var repair: AiRepair = AiRepair.create(def, level)
	var memory: AiMemory = AiMemory.create(def)
	memory.base_x = 20
	memory.base_y = 12
	var rng: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	var launched: Array[Command] = []
	var in_flight: int = 0
	for tick: int in [5, 20, 35, 110, 125]:
		world.tick = tick
		var view: PlayerView = PlayerView.of(world, 1)
		var out: Array[Command] = []
		memory.commands_left = 8
		memory.unit_cap = view.unit_cap
		intel.refresh(view, memory)
		army.run(view, memory, rng, out)
		repair.run(view, memory, out)
		for command: Command in out:
			if command.type == Command.Type.REPAIR:
				in_flight += 1
				# The sim would move it now: the repair is really in flight when the wave launches.
				world.order[world.index_of(hurt)] = World.Order.MOVE
			if command.type == Command.Type.ATTACK_MOVE and command.unit_ids.has(hurt):
				launched.append(command)
		assert_bool(memory.goal_keys() <= 4).is_true()
	# The repair went out before the wave (its key held a place), the mixed wave still launched
	# with the vehicle in it, and the repair key gave way.
	assert_int(in_flight).is_equal(1)
	assert_int(memory.wave_count).is_equal(1)
	assert_int(launched.size()).is_greater(0)
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)
	assert_int(memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	# Re-targeting the marching mixed wave still finds room.
	memory.base_x = 18
	memory.base_y = 4
	world.tick = 140
	var view: PlayerView = PlayerView.of(world, 1)
	var out: Array[Command] = []
	memory.commands_left = 8
	intel.refresh(view, memory)
	army.run(view, memory, rng, out)
	repair.run(view, memory, out)
	var moved: int = 0
	for command: Command in out:
		(
			assert_bool(command.type == Command.Type.REPAIR or command.type == Command.Type.MOVE)
			. is_false()
		)
		if command.type == Command.Type.ATTACK_MOVE:
			moved += 1
	assert_int(moved).is_greater(0)


# --- Round 2: step-back, stalls, a second building, medic budget ------------------------------


func test_a_sent_vehicle_that_is_stepped_back_is_sent_again() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 45)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(50, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	# Hit down to 20 on the way, Hard's step-back gives it a MOVE to the staging point (the home
	# goal stays): it is still moving, withdrawn since it was sent.
	world.hp[world.index_of(tank)] = 20
	world.order[world.index_of(tank)] = World.Order.MOVE
	memory.withdrawn_id = PackedInt32Array([tank])
	var again: Array[Command] = _repair(world, memory, repair)
	assert_int(again.size()).is_equal(1)
	assert_int(again[0].type).is_equal(Command.Type.REPAIR)
	assert_array(again[0].unit_ids).is_equal(PackedInt32Array([tank]))


func test_a_vehicle_that_was_withdrawn_before_it_was_sent_is_not_sent_again_and_again() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 20)
	var memory: AiMemory = _memory()
	memory.withdrawn_id = PackedInt32Array([tank])
	var repair: AiRepair = AiRepair.create(_def(), _level(50, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	world.order[world.index_of(tank)] = World.Order.MOVE
	for _think: int in 3:
		assert_array(_repair(world, memory, repair)).is_empty()


func test_a_sent_vehicle_that_stands_idle_without_a_gain_is_sent_again() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000, 20)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(50, 0))
	assert_int(_repair(world, memory, repair).size()).is_equal(1)
	# The next think only records its hp (the order may not have started), the one after finds no
	# gain at a standstill (a defence, a focus or a restage re-ordered it, or the credits ran out).
	assert_array(_repair(world, memory, repair)).is_empty()
	var again: Array[Command] = _repair(world, memory, repair)
	assert_int(again.size()).is_equal(1)
	assert_int(again[0].type).is_equal(Command.Type.REPAIR)
	# While its hp rises it stays put.
	world.hp[world.index_of(tank)] = 30
	assert_array(_repair(world, memory, repair)).is_empty()
	world.hp[world.index_of(tank)] = 40
	assert_array(_repair(world, memory, repair)).is_empty()


func test_vehicles_sent_to_a_dead_building_go_to_the_one_that_stands() -> void:
	var world: World = _world(true, true, true, false, true)
	var tank: int = _add(world, "tank", 4000, 9000, 10)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(40, 0))
	var first: Array[Command] = _repair(world, memory, repair)
	assert_int(first[0].target_id).is_equal(_shed_id(world))
	var view: PlayerView = PlayerView.of(world, 1)
	var other: int = NONE
	for row: int in view.own_rows:
		if (
			view.row_type(row) == Worlds.type_of(world, "shed")
			and view.row_id(row) != _shed_id(world)
		):
			other = view.row_id(row)
	world.build_left[world.index_of(_shed_id(world))] = 1
	var again: Array[Command] = _repair(world, memory, repair)
	assert_int(again.size()).is_equal(1)
	assert_int(again[0].type).is_equal(Command.Type.REPAIR)
	assert_int(again[0].target_id).is_equal(other)
	assert_array(again[0].unit_ids).is_equal(PackedInt32Array([tank]))


func test_a_medic_that_got_no_order_for_lack_of_budget_follows_when_there_is_budget() -> void:
	var world: World = _world()
	var tank: int = _add(world, "tank", 4000, 9000)
	var first: int = _add(world, "medic", 3000, 9000)
	var memory: AiMemory = _memory()
	var repair: AiRepair = AiRepair.create(_def(), _level(0, 4))
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([first]))
	var second: int = _add(world, "medic", 3500, 9000)
	_fill(world, memory)
	_launch_wave(memory, PackedInt32Array([tank]), Vector2i(20, 12))
	memory.commands_left = 0
	out.clear()
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()
	memory.commands_left = 99
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([first, second]))


func test_a_memory_with_one_squad_slot_has_no_wave_to_read() -> void:
	var world: World = _world()
	_add(world, "tank", 4000, 9000, 10)
	_add(world, "medic", 3000, 9000)
	var def: OpponentDef = _def()
	def.squads_max = 1
	var memory: AiMemory = AiMemory.create(def)
	memory.staging_x = 8
	memory.staging_y = 8
	var repair: AiRepair = AiRepair.create(def, _level(40, 4))
	_fill(world, memory)
	memory.commands_left = 99
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.REPAIR)


func test_the_cache_gives_up_the_repair_key_only_when_the_scouts_did_not_make_room() -> void:
	var memory: AiMemory = _memory()
	memory.add_goal_key(1, 1, AiMemory.FOOT, AiMemory.Owner.STAGING)
	memory.add_goal_key(1, 1, AiMemory.TRACKED, AiMemory.Owner.STAGING)
	memory.add_goal_key(5, 5, AiMemory.FOOT, AiMemory.Owner.SCOUT)
	memory.add_goal_key(6, 6, AiMemory.TRACKED, AiMemory.Owner.REPAIR)
	memory.yield_keys()
	assert_int(memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(0)
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(1)
	# Without a scout key the repair key is the one that gives way.
	memory.add_goal_key(7, 7, AiMemory.FOOT, AiMemory.Owner.ARMY)
	memory.yield_keys()
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(0)
