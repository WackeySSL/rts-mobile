extends "res://tests/ai/support/wave_suite.gd"
## All-in reinforcement groups (plan row P250e): from the all-in tick the home squad gathers and
## joins the wave as one group, at a value or after a cap; off keeps the one-by-one join.

const VALUE: int = 2000
const CAP: int = 300
## The first think after the all-in tick (the slots are 5 + 15 n).
const IN: int = ALL_IN + 15


## A launched wave on a level with group value `value` and cap `cap`; the all-in is reached by
## thinking at `IN`, with a tank (value 1000) waiting at home.
func _wave(value: int, cap: int, def: OpponentDef = null) -> int:
	var level: AiDifficultyDef = _level()
	level.all_in_group_value = value
	level.all_in_group_ticks = cap
	_arm_waves(level, def)
	return _launched()


func test_reinforcements_gather_and_leave_as_one_group() -> void:
	_wave(VALUE, 0)
	var first: int = _tank()
	_think(IN)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_array(_members(AiArmy.HOME)).is_equal(PackedInt32Array([first]))
	var second: int = _tank()
	_think(IN + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([first, second]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_array(_members(AiArmy.HOME)).is_empty()
	assert_int(_army._reinforce.groups).is_equal(1)


func test_the_cap_sends_the_group_that_has_not_reached_the_value() -> void:
	_wave(99999, CAP)
	var tank: int = _tank()
	_think(IN)
	_think(IN + CAP - 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(IN + CAP)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_int(_army._reinforce.groups).is_equal(1)
	# The next group's clock starts with its first unit.
	_tank()
	_think(IN + CAP + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_off_keeps_the_one_by_one_join() -> void:
	_wave(0, 0)
	var tank: int = _tank()
	_think(IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_bool(_members(AiArmy.WAVE).has(tank)).is_true()


func test_a_held_type_is_held_when_its_group_joins_the_wave_and_not_before() -> void:
	var def: OpponentDef = _def()
	def.hold_types = [&"heavy_tank"] as Array[StringName]
	var hold_level: AiDifficultyDef = AiDifficultyDef.new()
	hold_level.hold_in_waves = 1
	var holder: AiHold = AiHold.create(def, hold_level)
	var launched: int = _wave(VALUE, 0, def)
	assert_array(_hold_ids(holder)).is_equal([[launched]])
	_world.stance[_world.index_of(launched)] = 1
	var first: int = _tank()
	_think(IN)
	assert_array(_hold_ids(holder)).is_empty()
	var second: int = _tank()
	_think(IN + 15)
	assert_array(_hold_ids(holder)).is_equal([[first, second]])


func test_the_levels_and_the_frozen_copies() -> void:
	(
		assert_array(
			[Rig.level_of("easy").all_in_group_value, Rig.level_of("easy").all_in_group_ticks]
		)
		. is_equal([0, 0])
	)
	for level: String in ["normal", "hard"]:
		assert_int(Rig.level_of(level).all_in_group_value).is_greater(0)
		assert_int(Rig.level_of(level).all_in_group_ticks).is_greater(0)
	for level: String in ["easy", "normal", "hard"]:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_array([copy.all_in_group_value, copy.all_in_group_ticks]).is_equal([0, 0])


## The unit lists `holder` sets to hold or releases this think, one list a Command.
func _hold_ids(holder: AiHold) -> Array:
	_memory.commands_left = 8
	var sent: Array[Command] = []
	holder.run(_view(), _memory, sent)
	var found: Array = []
	for command: Command in sent:
		found.append(Array(command.unit_ids))
	return found
