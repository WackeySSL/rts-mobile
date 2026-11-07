extends "res://tests/ai/support/control_suite.gd"
## Hard's unit control (plan row P180b, ADR 0030 sections 4 and 6): a unit under
## `unit_retreat_hp_percent` steps back to the staging point with a `MOVE`, and a group `ATTACK`s
## the weakest seen enemy in reach, bounded by `target_tests_max`. Easy and Normal ship 0 for both.


func test_a_unit_under_the_percent_steps_back_with_one_move_and_is_not_sent_again() -> void:
	_control(STEP_PERCENT, 0)
	var tank: int = _tank()
	_settle()
	# The first think sends the start's `MOVE` of every unit to the staging point.
	_think(5)
	assert_int(_army.stepbacks).is_equal(0)
	# The smallest hp that is not under the percent: not ordered back; one less is.
	_hp(tank, _hp_at_percent())
	_think(20)
	assert_array(_of(Command.Type.MOVE)).is_empty()
	_hp(tank, _hp_at_percent() - 1)
	_think(35)
	var sent: Array[Command] = _of(Command.Type.MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal(
		[_stage_milli().x, _stage_milli().y]
	)
	assert_array(_memory.withdrawn_id).is_equal(PackedInt32Array([tank]))
	assert_int(_army.stepbacks).is_equal(1)
	# One order for the unit that went home, nothing else.
	assert_int(_out.size()).is_equal(1)
	_think(50)
	assert_array(_out).is_empty()
	assert_int(_army.stepbacks).is_equal(1)
	# Its hp back at or over the percent (the sim has no healing today): forgotten. Low again: a
	# new order.
	_hp(tank, 600)
	_think(65)
	assert_array(_memory.withdrawn_id).is_empty()
	_hp(tank, 100)
	_think(80)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_int(_army.stepbacks).is_equal(2)


func test_a_wave_unit_steps_back_alone_and_leaves_the_wave() -> void:
	_control(STEP_PERCENT, 0)
	var two: PackedInt32Array = _two_tanks()
	_hp(two[0], 100)
	_think(LAUNCH + 15)
	var sent: Array[Command] = _of(Command.Type.MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([two[0]]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal(
		[_stage_milli().x, _stage_milli().y]
	)
	assert_array(_members(AiArmy.HOME)).is_equal(PackedInt32Array([two[0]]))
	assert_bool(_members(AiArmy.WAVE).has(two[0])).is_false()
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	assert_int(_army.retreats).is_equal(0)


func test_a_refused_step_back_changes_nothing_and_is_asked_again() -> void:
	_control(STEP_PERCENT, 0)
	var tank: int = _tank()
	_settle()
	_think(5)
	_hp(tank, 100)
	var before: Array = _freeze()
	_think(20, 0)
	assert_array(_out).is_empty()
	assert_array(_memory.withdrawn_id).is_empty()
	assert_int(_army.stepbacks).is_equal(0)
	assert_array(_freeze()).is_equal(before)
	_think(35)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_array(_memory.withdrawn_id).is_equal(PackedInt32Array([tank]))


func test_a_dead_unit_leaves_the_withdrawn_list() -> void:
	_control(STEP_PERCENT, 0)
	var tank: int = _tank()
	_settle()
	_hp(tank, 100)
	_think(5)
	assert_array(_memory.withdrawn_id).is_equal(PackedInt32Array([tank]))
	_kill(tank)
	_think(20)
	assert_array(_memory.withdrawn_id).is_empty()


func test_a_level_without_unit_control_never_steps_back() -> void:
	_control(0, 0)
	var tank: int = _tank()
	_settle()
	_hp(tank, 1)
	for tick: int in [5, 20, 35]:
		_think(tick)
		assert_array(_memory.withdrawn_id).is_empty()
	assert_int(_army.stepbacks).is_equal(0)


func test_a_wave_attacks_the_weakest_seen_enemy_in_reach_and_resumes_when_none_is() -> void:
	_control(0, 1)
	_launched()
	_to_field()
	_enemy("heavy_tank", FIELD.x + 2000, FIELD.y)
	var hurt: int = _enemy("heavy_tank", FIELD.x + 2000, FIELD.y + 500)
	_hp(hurt, 300)
	var rifle: int = _enemy("rifle_squad", FIELD.x + 3000, FIELD.y)
	_see_all()
	_think(LAUNCH + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].target_id).is_equal(rifle)
	assert_array(sent[0].unit_ids).is_equal(_members(AiArmy.WAVE))
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# The target's tile is the army goal: one cell, a key for each class of the wave.
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[23, 20]
	)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	assert_int(_army.focuses).is_equal(1)
	# Held while it stands: nothing, and the march to the base does not come back.
	_think(LAUNCH + 30)
	assert_array(_out).is_empty()
	# It dies: the next weakest.
	_kill(rifle)
	_think(LAUNCH + 45)
	assert_int(_of(Command.Type.ATTACK).size()).is_equal(1)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(hurt)
	# None left in reach: the wave resumes toward the base with one ATTACK_MOVE.
	for id: int in AiRig.ids_of(_world, 2, "heavy_tank"):
		_hp(id, 0)
	AiRig.step(_world, _loop)
	_see_all()
	_think(LAUNCH + 60)
	assert_array(_of(Command.Type.ATTACK)).is_empty()
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	(
		assert_array(
			[_of(Command.Type.ATTACK_MOVE)[0].target_x, _of(Command.Type.ATTACK_MOVE)[0].target_y]
		)
		. is_equal([TARGET.x * 1000 + 500, TARGET.y * 1000 + 500])
	)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(AiMemory.NONE)


func test_a_tie_on_hp_goes_to_the_lowest_id() -> void:
	_control(0, 1)
	_launched()
	_to_field()
	var first: int = _enemy("heavy_tank", FIELD.x + 2500, FIELD.y)
	_enemy("heavy_tank", FIELD.x + 2000, FIELD.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(first)


func test_the_weakest_is_picked_among_the_tests_the_cap_allows() -> void:
	var def: OpponentDef = _def()
	def.target_tests_max = 2
	_control(0, 1, 0, def)
	_launched()
	_to_field()
	_enemy("heavy_tank", FIELD.x + 2000, FIELD.y)
	var second: int = _enemy("heavy_tank", FIELD.x + 2000, FIELD.y + 500)
	var third: int = _enemy("heavy_tank", FIELD.x + 2000, FIELD.y + 1000)
	_hp(second, 400)
	_hp(third, 200)
	_see_all()
	_think(LAUNCH + 15)
	# Two tests a slot: the third and weakest was never looked at.
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(second)
	assert_int(_army.tests).is_less_equal(2)


func test_an_enemy_beyond_the_radius_of_the_group_is_not_a_focus() -> void:
	_control(0, 1)
	_launched()
	_to_field()
	# 9 tiles off on both axes: in the box, 12.7 tiles away.
	_enemy("rifle_squad", FIELD.x + 9000, FIELD.y + 9000)
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK)).is_empty()
	assert_int(_army.focuses).is_equal(0)


func test_the_home_squad_focuses_a_foe_in_reach_instead_of_the_defence_move() -> void:
	_control(0, 1)
	var strong: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	var hurt: int = _enemy("heavy_tank", NEAR.x, NEAR.y + 500)
	_hp(hurt, 300)
	_settle()
	_see_all()
	_think(5)
	_think(20)
	assert_array(_out).is_empty()
	_think(35)
	var sent: Array[Command] = _of(Command.Type.ATTACK)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].target_id).is_equal(hurt)
	assert_array(sent[0].unit_ids).is_equal(_squads())
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_army.defences).is_equal(0)
	# A joiner gets the group's order again; a stand-still costs nothing.
	_think(50)
	assert_array(_out).is_empty()
	var late: int = _tank()
	_see_all()
	_think(65)
	assert_array(_of(Command.Type.ATTACK)[0].unit_ids).is_equal(_all_ids(late))
	# The target dies and the other one is attacked.
	_kill(hurt)
	_think(80)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(strong)


func test_a_threat_out_of_the_squads_reach_is_still_met_by_the_defence_move() -> void:
	_control(0, 1)
	for id: int in _squads():
		_put(id, 7500, 30500)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [5, 20, 35]:
		_think(tick)
	assert_array(_of(Command.Type.ATTACK)).is_empty()
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_army.defences).is_equal(1)


func test_a_refused_focus_order_changes_nothing_and_is_sent_next_think() -> void:
	_control(0, 1)
	_launched()
	_to_field()
	var rifle: int = _enemy("rifle_squad", FIELD.x + 3000, FIELD.y)
	_see_all()
	_think(LAUNCH + 15, 0)
	assert_array(_out).is_empty()
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[TARGET.x, TARGET.y]
	)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(AiMemory.NONE)
	assert_int(_army.focuses).is_equal(0)
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(rifle)


func test_a_focus_search_cut_off_by_the_shared_cap_keeps_a_living_target() -> void:
	var def: OpponentDef = _def()
	def.target_tests_max = 3
	_control(0, 1, RATIO_PERCENT, def)
	_launched()
	_to_field()
	var first: int = _enemy("rifle_squad", FIELD.x + 3000, FIELD.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(first)
	# Two more foes in reach: the ratio read uses the three tests, the focus search sees none.
	_enemy("rifle_squad", FIELD.x + 3000, FIELD.y + 500)
	_enemy("rifle_squad", FIELD.x + 3000, FIELD.y + 1000)
	_see_all()
	_think(LAUNCH + 30)
	assert_array(_out).is_empty()
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(first)
