extends "res://tests/ai/support/control_suite.gd"
## What a unit that stepped back still does and does not do (plan row P180b, lead decision): it is
## left out of wave launches (their strength, their launch value and their ids) and joins, but still
## takes the home defence and the all-in, and never triggers the unseen-hit shift. From the all-in
## tick no unit is ordered back.


func test_a_unit_that_stepped_back_still_takes_the_home_defence_order() -> void:
	_control(STEP_PERCENT, 0)
	var tank: int = _tank()
	_hp(tank, 100)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(5)
	assert_int(_army.stepbacks).is_equal(1)
	_think(20)
	_think(35)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(tank))
	assert_int(_army.defences).is_equal(1)


func test_a_unit_that_stepped_back_is_left_out_of_a_wave_s_launch() -> void:
	_control(STEP_PERCENT, 0)
	_target_at()
	var hurt: int = _tank()
	var whole: int = _tank(10500, 9500)
	_hp(hurt, 100)
	_settle()
	_until(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	var expected: PackedInt32Array = _squads()
	expected.append(whole)
	assert_array(sent[0].unit_ids).is_equal(expected)
	assert_array(_members(AiArmy.HOME)).is_equal(PackedInt32Array([hurt]))
	assert_bool(_members(AiArmy.WAVE).has(hurt)).is_false()


func test_a_unit_that_stepped_back_joins_the_all_in() -> void:
	_control(STEP_PERCENT, 0)
	_target_at()
	var hurt: int = _tank()
	_hp(hurt, 100)
	_settle()
	_until(ALL_IN - 15)
	assert_int(_memory.wave_count).is_equal(0)
	_think(ALL_IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(hurt))
	assert_array(_members(AiArmy.WAVE)).is_equal(_all_ids(hurt))


func test_a_withdrawn_unit_never_triggers_the_unseen_hit_shift() -> void:
	var def: OpponentDef = _def()
	def.unseen_hit_shift_tiles = 4
	_control(STEP_PERCENT, 0, RATIO_PERCENT, def)
	var tank: int = _tank()
	_hp(tank, 100)
	_settle()
	_think(5)
	assert_int(_army.stepbacks).is_equal(1)
	# It loses hp with no seen foe in range: a unit that stood at home would shift the squad.
	_hp(tank, 50)
	_think(20)
	assert_array(_out).is_empty()
	assert_int(_army.shifts).is_equal(0)


func test_the_launch_counts_only_the_units_that_march() -> void:
	# Strength 1300: the squads (200) and a whole tank (1000) are 1200; the withdrawn tank's 153
	# would make 1353, but it stays home.
	_control(STEP_PERCENT, 0, RATIO_PERCENT, null, 1300)
	_target_at()
	var hurt: int = _tank()
	_tank(10500, 9500)
	_hp(hurt, 100)
	_settle()
	_until(LAUNCH + 30)
	assert_int(_memory.wave_count).is_equal(0)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_the_launch_value_is_the_value_of_the_units_that_march() -> void:
	_control(STEP_PERCENT, 0)
	_target_at()
	var hurt: int = _tank()
	_tank(10500, 9500)
	_hp(hurt, 100)
	_settle()
	_until(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(1200)


func test_the_all_in_takes_a_withdrawn_unit_into_the_wave_in_the_field() -> void:
	_control(STEP_PERCENT, 0)
	_two_tanks()
	var late: int = _tank(8500, 11500)
	_hp(late, 100)
	_settle()
	_between(LAUNCH + 15, ALL_IN)
	assert_int(_army.stepbacks).is_equal(1)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([late]))
	assert_bool(_members(AiArmy.WAVE).has(late)).is_true()
	assert_array(_members(AiArmy.HOME)).is_empty()


func test_no_unit_is_ordered_back_from_the_all_in_tick() -> void:
	# A strength nothing reaches: no wave before the all-in, so the unit is still at home.
	_control(STEP_PERCENT, 0, RATIO_PERCENT, null, 99999)
	_target_at()
	var tank: int = _tank()
	_settle()
	_until(ALL_IN - 15)
	_hp(tank, 100)
	_think(ALL_IN)
	# The all-in sends the unit out with the rest: no `MOVE` home for it in the same think.
	assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.stepbacks).is_equal(0)
	assert_array(_of(Command.Type.ATTACK_MOVE)[0].unit_ids).is_equal(_all_ids(tank))
