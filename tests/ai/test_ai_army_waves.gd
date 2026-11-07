extends "res://tests/ai/support/wave_suite.gd"
## `AiArmy`'s waves (plan row P180, ADR 0030 sections 4 and 6): the launch on exact ticks, the start
## jitter from the AI's own stream, the strength and its growth, the target, the re-target and the
## goal keys, on hand-built Worlds read through `PlayerView`.


func test_a_wave_launches_on_the_first_think_after_the_first_tick() -> void:
	_target_at()
	var tank: int = _tank()
	_settle()
	for tick: int in range(5, LAUNCH, 15):
		_think(tick)
		assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# The start tick was drawn once, on the first think: the first tick and no jitter.
	assert_int(_memory.wave_start_tick).is_equal(FIRST_TICK)
	_think(LAUNCH)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(tank))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_int(sent[0].player_id).is_equal(1)
	assert_array(_members(AiArmy.WAVE)).is_equal(_all_ids(tank))
	assert_array([_memory.wave_count, _army.waves]).is_equal([1, 1])
	assert_array([_memory.squad_role[AiArmy.WAVE], _memory.squad_state[AiArmy.WAVE]]).is_equal(
		[AiArmy.ROLE_WAVE, AiMemory.SquadState.WAVE]
	)
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(STRENGTH)
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[TARGET.x, TARGET.y]
	)
	# Nothing again while the wave marches.
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_array([_memory.wave_count, _army.waves]).is_equal([1, 1])


func test_the_start_jitter_is_drawn_once_from_the_stream_and_delays_the_launch() -> void:
	_arm_waves(_level(40))
	var reference: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	var jitter: int = reference.next_int(41)
	assert_int(jitter).is_greater(0)
	var expected: int = reference.next_int(1000)
	_target_at()
	_tank()
	_settle()
	var launched_at: int = -1
	for tick: int in range(5, 400, 15):
		_think(tick)
		if not _of(Command.Type.ATTACK_MOVE).is_empty():
			launched_at = tick
			break
	assert_int(_memory.wave_start_tick).is_equal(FIRST_TICK + jitter)
	# The first slot at or after the drawn tick, and exactly one draw was made.
	assert_int(launched_at).is_greater_equal(FIRST_TICK + jitter)
	assert_int(launched_at - 15).is_less(FIRST_TICK + jitter)
	assert_int(_rng.next_int(1000)).is_equal(expected)


func test_no_jitter_means_no_draw() -> void:
	var reference: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	var expected: int = reference.next_int(1000)
	_launched()
	assert_int(_rng.next_int(1000)).is_equal(expected)


func test_the_value_is_scaled_by_hit_points_and_the_strength_is_inclusive() -> void:
	_target_at()
	var tank: int = _tank()
	_settle()
	var row: int = _row_in_world(tank)
	# 649 of 650 hp is worth 998 of 1000: the squads and the tank are 1198, under 1200.
	_world.hp[row] = 649
	_until(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_memory.wave_count).is_equal(0)
	_world.hp[row] = 650
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(STRENGTH)


func test_a_half_dead_army_does_not_reach_the_strength() -> void:
	_target_at()
	var tank: int = _tank()
	_settle()
	_world.hp[_row_in_world(tank)] = 325
	_until(LAUNCH + 30)
	# 500 + 200 is far under 1200.
	assert_int(_memory.wave_count).is_equal(0)
	assert_array(_members(AiArmy.WAVE)).is_empty()


func test_the_next_wave_asks_the_growth_more_after_a_fresh_start_tick() -> void:
	var first: int = _launched()
	# The whole wave dies: the squad is gone on the next think and its units are none.
	for id: int in _all_ids(first):
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	assert_array([_memory.squad_role[AiArmy.WAVE], _memory.wave_start_tick]).is_equal(
		[AiMemory.NONE, LAUNCH + 15]
	)
	# 1200 of new units is the first strength, not the second (1200 * 150 / 100 = 1800).
	_tank()
	_squad_row(2, 8)
	_settle()
	_think(LAUNCH + 30)
	assert_int(_memory.wave_count).is_equal(1)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# 1700, one squad short.
	_squad_row(5, 9)
	_settle()
	_think(LAUNCH + 45)
	assert_int(_memory.wave_count).is_equal(1)
	# 1800 exactly launches the second wave.
	_squad_row(1, 10)
	_settle()
	_think(LAUNCH + 60)
	assert_int(_memory.wave_count).is_equal(2)
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(1800)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	# The third wave asks 1800 * 150 / 100 = 2700, compounded (linear growth would ask 2400).
	for id: int in _members(AiArmy.WAVE):
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)
	_think(LAUNCH + 75)
	_tank()
	_tank(10500, 9500)
	_squad_row(4, 10)
	_settle()
	_think(LAUNCH + 90)
	assert_int(_memory.wave_count).is_equal(2)
	_squad_row(3, 11)
	_settle()
	_think(LAUNCH + 105)
	assert_int(_memory.wave_count).is_equal(3)
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(2700)


## `count` own rifle squads in a row on tile line `line`.
func _squad_row(count: int, line: int) -> void:
	for index: int in count:
		AiRig.add_unit_of(_world, 1, "rifle_squad", 8500 + index * 500, line * 1000 + 500)


func test_without_a_known_producer_the_target_is_the_base_estimate() -> void:
	_tank()
	_settle()
	for tick: int in range(5, LAUNCH + 1, 15):
		_both(tick)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_array([_memory.base_x, _memory.base_y]).is_equal([TARGET.x, TARGET.y])


func test_the_target_is_the_nearest_known_producer() -> void:
	var near: int = AiRig.give(_world, 2, "barracks", 20, 25)
	AiRig.give(_world, 2, "barracks", 30, 30)
	_tank()
	_settle()
	_see_all()
	for tick: int in range(5, LAUNCH + 1, 15):
		_both(tick)
	var at: Vector2i = _view().row_pos(_view().row_of(near)) / 1000
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal(
		[at.x * 1000 + 500, at.y * 1000 + 500]
	)
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[at.x, at.y]
	)


func test_a_wave_re_targets_once_when_its_target_is_gone() -> void:
	var near: int = AiRig.give(_world, 2, "barracks", 20, 25)
	AiRig.give(_world, 2, "barracks", 30, 30)
	# The next nearest producer is the enemy Headquarters.
	var far: int = AiRig.ids_of(_world, 2, "headquarters")[0]
	var tank: int = _tank()
	_settle()
	_see_all()
	for tick: int in range(5, LAUNCH + 1, 15):
		_both(tick)
	assert_int(_memory.wave_count).is_equal(1)
	# The nearer producer is destroyed; the estimate moves to the other, and the wave follows once.
	AiRig.kill(_world, _loop, _row_in_world(near))
	_see_all()
	_both(LAUNCH + 15)
	var at: Vector2i = _view().row_pos(_view().row_of(far)) / 1000
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(tank))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal(
		[at.x * 1000 + 500, at.y * 1000 + 500]
	)
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[at.x, at.y]
	)
	_both(LAUNCH + 30)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_memory.wave_count).is_equal(1)


func test_a_shifted_home_squad_that_launches_a_wave_keeps_the_wave_s_army_keys() -> void:
	_target_at()
	_tank()
	_settle()
	_until(LAUNCH - 15)
	# The unseen-hit response (P179b) moved the home squad's goal and set its flag.
	_memory.home_shifted = 1
	_memory.squad_goal_x[AiArmy.HOME] = 20
	_memory.squad_goal_y[AiArmy.HOME] = 20
	# A squad member is still walking, so the probe holds the shifted goal until the launch.
	_world.order[_row_in_world(_squads()[0])] = World.Order.MOVE
	_think(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	assert_int(_memory.home_shifted).is_equal(0)
	# The empty home squad's goal is the staging point, and the wave keeps its two keys while it
	# marches: neither the return nor the next thinks release them.
	assert_array([_memory.squad_goal_x[AiArmy.HOME], _memory.squad_goal_y[AiArmy.HOME]]).is_equal(
		[STAGING.x, STAGING.y]
	)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	_think(LAUNCH + 15)
	_think(LAUNCH + 30)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	assert_array(_out).is_empty()


func test_a_launch_the_budget_cannot_pay_changes_nothing_and_is_asked_again() -> void:
	_target_at()
	var tank: int = _tank()
	_settle()
	_until(LAUNCH - 15)
	var before: Array = _freeze()
	_think(LAUNCH, 0)
	assert_array(_out).is_empty()
	assert_array(_freeze()).is_equal(before)
	_think(LAUNCH + 15)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_array(_members(AiArmy.WAVE)).is_equal(_all_ids(tank))


func test_a_launch_the_keys_cannot_hold_is_refused_whole() -> void:
	var def: OpponentDef = _def()
	def.goal_keys_max = 3
	_arm_waves(null, def)
	AiRig.give(_world, 1, "barracks", 12, 6)
	AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_target_at()
	_tank()
	_settle()
	_until(LAUNCH - 15)
	# The staging point holds foot and tracked; a mixed wave needs two more of the cap of three.
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(2)
	var before: Array = _freeze()
	var starved: int = _army.starved
	_think(LAUNCH)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_array(_freeze()).is_equal(before)
	assert_int(_army.starved).is_equal(starved + 1)


func test_a_wave_takes_the_scout_s_key_at_the_cap() -> void:
	AiRig.give(_world, 1, "barracks", 12, 6)
	AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_target_at()
	_tank()
	_settle()
	_until(LAUNCH - 15)
	assert_bool(_memory.add_goal_key(30, 30, AiIntel.TRACKED, AiMemory.Owner.SCOUT)).is_true()
	_think(LAUNCH)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(0)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(2)
	assert_int(_memory.goal_keys()).is_equal(KEYS)


func test_no_wave_launches_on_the_think_a_threat_first_appears_or_while_it_stands() -> void:
	_target_at()
	_tank()
	_settle()
	_see_all()
	_until(LAUNCH - 15)
	assert_int(_memory.wave_count).is_equal(0)
	# The foe shows up on the launch think itself: this think's threat blocks the launch.
	var foe: int = _enemy("heavy_tank", 15500, 7500)
	_see_all()
	_think(LAUNCH)
	assert_int(_memory.threat_first_tick).is_equal(LAUNCH)
	assert_int(_memory.wave_count).is_equal(0)
	_think(LAUNCH + 15)
	_think(LAUNCH + 30)
	assert_int(_memory.wave_count).is_equal(0)
	# The think that sees it gone launches at once: no think of lag.
	AiRig.kill(_world, _loop, _row_in_world(foe))
	_see_all()
	_think(LAUNCH + 45)
	assert_int(_memory.threat_first_tick).is_equal(AiMemory.NONE)
	assert_int(_memory.wave_count).is_equal(1)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_a_defence_return_does_not_replace_the_new_wave_s_army_key() -> void:
	_target_at()
	_tank()
	var foe: int = _enemy("heavy_tank", 15500, 7500)
	_settle()
	_see_all()
	_until(LAUNCH + 30)
	assert_int(_memory.wave_count).is_equal(0)
	# The foe dies on the think that would both return the squads and launch the wave.
	AiRig.kill(_world, _loop, _row_in_world(foe))
	_see_all()
	_think(LAUNCH + 45)
	assert_int(_memory.wave_count).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_greater(0)


func test_a_threat_with_an_empty_home_squad_leaves_the_wave_its_army_keys() -> void:
	_launched()
	_enemy("heavy_tank", 15500, 7500)
	_settle()
	_see_all()
	# The defence has no unit to send, no order is made, and the wave's keys stay.
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45, LAUNCH + 60]:
		_think(tick)
		assert_array(_out).is_empty()
		assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	assert_int(_memory.threat_first_tick).is_not_equal(AiMemory.NONE)
	assert_int(_army.defences).is_equal(0)
