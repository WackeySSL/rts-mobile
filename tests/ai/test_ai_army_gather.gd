extends "res://tests/ai/support/control_suite.gd"
## The assembly of a wave and the reinforcement batches (plan row P197, ADR 0030 section 6): a wave
## walks to a point before its target, goes on together, and from the all-in the home squad joins a
## wave that is past its assembly in batches.

## The assembly point of the suite: 10 tiles from the target (32, 32) on the line to the staging
## point (11, 11): (32, 32) + (-21, -21) * 10 / 29, truncated.
const GATHER: Vector2i = Vector2i(25, 25)
const TILES: int = 10
const TICKS: int = 600
const PERCENT: int = 75


## The suite's level with the assembly numbers, no siege and no press.
func _gathering(tiles: int = TILES, percent: int = PERCENT, reinforce: int = 0) -> void:
	var level: AiDifficultyDef = _level()
	level.gather_tiles = tiles
	level.gather_ticks = TICKS
	level.gather_percent = percent
	level.reinforce_percent = reinforce
	var own: OpponentDef = _def()
	own.unseen_hit_shift_tiles = 0
	_arm_waves(level, own)


## Puts the wave's units at (`x`, `y`) milli-tiles, the first `count` of them (all when 0).
func _wave_to(x: int, y: int, count: int = 0) -> void:
	var done: int = 0
	for id: int in _members(AiArmy.WAVE):
		if count > 0 and done >= count:
			break
		_put(id, x, y)
		done += 1


func _goal_of(command: Command) -> Array[int]:
	return [command.target_x, command.target_y]


func test_a_wave_is_launched_to_the_assembly_point() -> void:
	_gathering()
	_target_at()
	_tank()
	_tank(10500, 9500)
	_settle()
	_until(LAUNCH - 15)
	_think(LAUNCH)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(_goal_of(sent[0])).is_equal([_centre(GATHER).x, _centre(GATHER).y])
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[GATHER.x, GATHER.y]
	)


func test_a_wave_that_has_not_assembled_holds_the_point() -> void:
	_gathering()
	_two_tanks()
	_wave_to(FIELD.x, FIELD.y)
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45]:
		_think(tick)
		assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[GATHER.x, GATHER.y]
	)


func test_an_assembled_wave_goes_on_to_the_target() -> void:
	_gathering()
	_two_tanks()
	_wave_to(_centre(GATHER).x, _centre(GATHER).y)
	_think(LAUNCH + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(_goal_of(sent[0])).is_equal([_centre(TARGET).x, _centre(TARGET).y])
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[TARGET.x, TARGET.y]
	)
	# Once: it does not go back to the point.
	_wave_to(FIELD.x, FIELD.y)
	_think(LAUNCH + 30)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[TARGET.x, TARGET.y]
	)


func test_the_percent_of_the_wave_at_the_point_decides() -> void:
	_gathering()
	_two_tanks()
	# The wave is two tanks and two squads: 2 of 4 stand at the point, under 75 percent.
	_wave_to(FIELD.x, FIELD.y)
	_wave_to(_centre(GATHER).x, _centre(GATHER).y, 2)
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# 3 of 4: enough.
	_wave_to(_centre(GATHER).x, _centre(GATHER).y, 3)
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_a_wave_goes_on_when_the_ticks_have_passed() -> void:
	_gathering()
	_two_tanks()
	_wave_to(FIELD.x, FIELD.y)
	_think(LAUNCH + 15 * 39)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(LAUNCH + 15 * 40)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(_goal_of(sent[0])).is_equal([_centre(TARGET).x, _centre(TARGET).y])


func test_a_staging_point_nearer_than_the_distance_means_no_stop() -> void:
	_gathering(40)
	_target_at()
	_tank()
	_tank(10500, 9500)
	_settle()
	_until(LAUNCH - 15)
	_think(LAUNCH)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_array(_goal_of(sent[0])).is_equal([_centre(TARGET).x, _centre(TARGET).y])


func test_a_level_without_the_assembly_goes_straight_to_the_target() -> void:
	_gathering(0)
	_target_at()
	_tank()
	_tank(10500, 9500)
	_settle()
	_until(LAUNCH - 15)
	_think(LAUNCH)
	assert_array(_goal_of(_of(Command.Type.ATTACK_MOVE)[0])).is_equal(
		[_centre(TARGET).x, _centre(TARGET).y]
	)


func test_the_home_squad_waits_for_a_batch_when_the_wave_is_past_the_assembly() -> void:
	# Worth 100 percent of the first strength (1200) before it joins; the wave goes to the target.
	_gathering(0, PERCENT, 100)
	_two_tanks()
	_wave_to(FIELD.x, FIELD.y)
	_between(LAUNCH + 15, ALL_IN - 15)
	var one: int = _tank(8500, 11500)
	_settle()
	_see_all()
	# 1000 is under 1200: it stays home at the all-in.
	_think(ALL_IN)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_memory.member_squad[_memory.member_id.bsearch(one)]).is_equal(AiArmy.HOME)
	# Two tanks (2000) are a batch: one order, both join.
	var two: int = _tank(8500, 12500)
	_settle()
	_see_all()
	_think(ALL_IN + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([one, two]))
	assert_int(_memory.member_squad[_memory.member_id.bsearch(one)]).is_equal(AiArmy.WAVE)


func test_a_level_without_batches_sends_every_unit_at_once() -> void:
	_gathering(0, PERCENT, 0)
	_two_tanks()
	_wave_to(FIELD.x, FIELD.y)
	_between(LAUNCH + 15, ALL_IN - 15)
	var one: int = _tank(8500, 11500)
	_settle()
	_see_all()
	_think(ALL_IN)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.member_squad[_memory.member_id.bsearch(one)]).is_equal(AiArmy.WAVE)


func test_a_wave_that_gathers_takes_the_home_squad_at_once() -> void:
	_gathering(TILES, PERCENT, 100)
	# The assembly would wait for ever: a long tick limit and no unit at the point.
	_army.gather_ticks = 100000
	_two_tanks()
	_wave_to(FIELD.x, FIELD.y)
	_between(LAUNCH + 15, ALL_IN - 15)
	var one: int = _tank(8500, 11500)
	_settle()
	_see_all()
	# 1000 is under a batch of 1200, but the wave still gathers: the unit goes to the point at once.
	_think(ALL_IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([one]))
	assert_array(_goal_of(sent[0])).is_equal([_centre(GATHER).x, _centre(GATHER).y])


func test_the_ladder_gathers_from_normal_up() -> void:
	var easy: AiDifficultyDef = Rig.level_of("easy")
	var normal: AiDifficultyDef = Rig.level_of("normal")
	var hard: AiDifficultyDef = Rig.level_of("hard")
	assert_array([easy.gather_tiles, easy.reinforce_percent]).is_equal([0, 0])
	assert_int(normal.gather_tiles).is_greater(0)
	assert_int(hard.gather_tiles).is_equal(normal.gather_tiles)
	assert_int(hard.reinforce_percent).is_less_equal(normal.reinforce_percent)
