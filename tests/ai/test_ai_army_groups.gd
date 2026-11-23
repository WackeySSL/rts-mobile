extends "res://tests/ai/support/groups_suite.gd"
## The gather of the all-in wave (plan row P250e): from the all-in tick the home units wait at the
## staging point and join the wave together, when the group size is there or the first has waited
## the gather time; a dead wave is launched again as a full group; off at 0 (Easy).


func test_a_lone_home_unit_waits_for_the_group_after_the_all_in() -> void:
	_grouped()
	_wave_before_all_in()
	var late: int = _tank()
	_settle()
	_think(ALL_IN)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_bool(_members(AiArmy.HOME).has(late)).is_true()
	_think(ALL_IN + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_the_group_goes_together_when_it_is_big_enough() -> void:
	_grouped()
	_wave_before_all_in()
	var first: int = _tank()
	var second: int = _tank(9600, 9500)
	_settle()
	_think(ALL_IN)
	_think(ALL_IN + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	var third: int = _tank(9700, 9500)
	_settle()
	_think(ALL_IN + 30)
	assert_array(_first_ids()).is_equal(PackedInt32Array([first, second, third]))
	assert_array([_army.group_stats()[0], _army.group_stats()[1]]).is_equal([1, 0])
	assert_bool(_members(AiArmy.WAVE).has(third)).is_true()


func test_the_gather_time_sends_a_short_group_and_counts_the_timeout() -> void:
	_grouped()
	_wave_before_all_in()
	var late: int = _tank()
	_settle()
	_think(ALL_IN)
	# The first think that saw it: the gather started at ALL_IN, so it goes at ALL_IN + GATHER.
	for tick: int in range(ALL_IN + 15, ALL_IN + GATHER, 15):
		_think(tick)
		assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(ALL_IN + GATHER)
	assert_array(_first_ids()).is_equal(PackedInt32Array([late]))
	assert_array([_army.group_stats()[0], _army.group_stats()[1]]).is_equal([1, 1])


func test_a_group_size_of_zero_lets_every_unit_join_at_once() -> void:
	_grouped(0, GATHER)
	_wave_before_all_in()
	var late: int = _tank()
	_settle()
	_think(ALL_IN)
	assert_array(_first_ids()).is_equal(PackedInt32Array([late]))
	assert_array(_army.group_stats()).is_equal([0, 0, 0, 0])


func test_a_dead_wave_is_launched_again_only_as_a_full_group() -> void:
	_grouped()
	var tank: int = _wave_before_all_in()
	for id: int in _all_ids(tank):
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)
	var one: int = _tank()
	_settle()
	_think(ALL_IN)
	_think(ALL_IN + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_memory.squad_role[AiArmy.WAVE]).is_equal(AiMemory.NONE)
	var two: int = _tank(9600, 9500)
	var three: int = _tank(9700, 9500)
	_settle()
	_think(ALL_IN + 30)
	assert_array(_first_ids()).is_equal(PackedInt32Array([one, two, three]))
	assert_int(_memory.wave_count).is_equal(2)


func test_the_gather_waits_from_the_first_unit_not_from_the_think_before() -> void:
	_grouped()
	_wave_before_all_in()
	_think(ALL_IN)
	_think(ALL_IN + 15)
	var late: int = _tank()
	_settle()
	# The timer starts when it is first seen, not at the all-in tick.
	_think(ALL_IN + 30)
	_think(ALL_IN + 30 + GATHER - 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(ALL_IN + 30 + GATHER)
	assert_array(_first_ids()).is_equal(PackedInt32Array([late]))


func test_the_level_files_turn_the_groups_off_for_easy_and_on_for_the_others() -> void:
	var easy: AiDifficultyDef = Rig.level_of("easy")
	(
		assert_array(
			[
				easy.group_min_size,
				easy.group_gather_ticks,
				easy.wave_regroup_spread_tiles,
				easy.wave_regroup_ticks,
				easy.wave_lead_percent
			]
		)
		. is_equal([0, 0, 0, 0, 0])
	)
	for level: String in ["normal", "hard"]:
		var def: AiDifficultyDef = Rig.level_of(level)
		assert_int(def.group_min_size).is_greater(1)
		assert_int(def.group_gather_ticks).is_greater(0)
		assert_int(def.wave_regroup_spread_tiles).is_greater(0)
		assert_int(def.wave_regroup_ticks).is_greater(0)
		assert_int(def.wave_lead_percent).is_greater(0)
