extends "res://tests/ai/support/wave_suite.gd"
## Wave cohesion (plan row P250d): a wave that strings out on the march halts at its centre, marches
## on when the rear has closed up or the cap has passed, does nothing when off, and halts and walks
## with its held artillery. The suite's wave numbers (`wave_suite.gd`) and its own spread and cap.

const SPREAD: int = 8
const CAP: int = 300
## The first think after the launch at `LAUNCH`.
const HALT_AT: int = 125
## The tank's place when the wave is strung out: 15 tiles from the squads' centre.
const FAR: Vector2i = Vector2i(24500, 24500)


## Launches a wave (the squads and a tank) on a level with spread `spread` and cap `cap`; the
## tank's id.
func _march(spread: int = SPREAD, cap: int = CAP) -> int:
	var level: AiDifficultyDef = _level()
	level.wave_spread_tiles = spread
	level.wave_regroup_ticks = cap
	_arm_waves(level)
	return _launched()


## The wave's units in a ball round tile (`col`, `line`).
func _gather(tank: int, col: int, line: int) -> void:
	_put(tank, col * 1000 + 500, line * 1000 + 500)
	for id: int in _squads():
		_put(id, col * 1000 + 1000, line * 1000 + 500)


func _centre_tile() -> Vector2i:
	return _army._wave_at / 1000


func test_a_strung_out_wave_halts_at_its_centre() -> void:
	var tank: int = _march()
	_put(tank, FAR.x, FAR.y)
	_think(HALT_AT)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(tank))
	var tile: Vector2i = _centre_tile()
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal(
		[tile.x * 1000 + 500, tile.y * 1000 + 500]
	)
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[tile.x, tile.y]
	)
	assert_int(_army._cohesion.halts).is_equal(1)
	assert_bool(_army._cohesion.halted).is_true()
	# Halted: nothing more is said while the rear is still far.
	_think(HALT_AT + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_army._cohesion.halts).is_equal(1)


func test_a_close_wave_does_not_halt() -> void:
	var tank: int = _march()
	_gather(tank, 12, 12)
	_think(HALT_AT)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_army._cohesion.halts).is_equal(0)


func test_the_wave_marches_on_when_the_rear_has_closed_up() -> void:
	var tank: int = _march()
	_put(tank, FAR.x, FAR.y)
	_think(HALT_AT)
	_gather(tank, 14, 14)
	_think(HALT_AT + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(tank))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[TARGET.x, TARGET.y]
	)
	assert_array([_army._cohesion.halted, _army._cohesion.resumes]).is_equal([false, 1])


func test_the_cap_ends_the_wait_and_the_wave_does_not_halt_again_for_the_span() -> void:
	var tank: int = _march()
	_put(tank, FAR.x, FAR.y)
	_think(HALT_AT)
	_think(HALT_AT + CAP - 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# The cap: the straggler is still far, the wave goes on.
	_think(HALT_AT + CAP)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_array([_army._cohesion.halted, _army._cohesion.resumes]).is_equal([false, 1])
	# Still strung out, but not again within the span, then again.
	_think(HALT_AT + CAP + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(HALT_AT + 2 * CAP - 15)
	assert_int(_army._cohesion.halts).is_equal(1)
	_think(HALT_AT + 2 * CAP)
	assert_int(_army._cohesion.halts).is_equal(2)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_off_keeps_the_old_march() -> void:
	var tank: int = _march(0, 0)
	_put(tank, FAR.x, FAR.y)
	for tick: int in range(HALT_AT, HALT_AT + 300, 15):
		_think(tick)
		assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_array([_army._cohesion.halts, _army._cohesion.halted]).is_equal([0, false])


func test_an_enemy_near_the_front_keeps_the_wave_marching() -> void:
	var tank: int = _march()
	_put(tank, 22500, 22500)
	_enemy("heavy_tank", 24500, 24500)
	_see_all()
	_think(HALT_AT)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_army._cohesion.halts).is_equal(0)


func test_the_all_in_is_not_halted() -> void:
	var tank: int = _march()
	_put(tank, FAR.x, FAR.y)
	_think(ALL_IN + 5)
	assert_int(_army._cohesion.halts).is_equal(0)


func test_held_artillery_halts_and_marches_with_the_wave_and_stays_held() -> void:
	var def: OpponentDef = _def()
	def.hold_types = [&"heavy_tank"] as Array[StringName]
	var hold_level: AiDifficultyDef = AiDifficultyDef.new()
	hold_level.hold_in_waves = 1
	var holder: AiHold = AiHold.create(def, hold_level)
	var level: AiDifficultyDef = _level()
	level.wave_spread_tiles = SPREAD
	level.wave_regroup_ticks = CAP
	_arm_waves(level, def)
	var tank: int = _launched()
	_put(tank, FAR.x, FAR.y)
	# The wave's launch think: the tank is held; the sim applies the stance.
	assert_array(_hold_orders(holder)).is_equal([[tank]])
	_world.stance[_world.index_of(tank)] = 1
	_think(HALT_AT)
	var halt: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(halt.size()).is_equal(1)
	assert_bool(halt[0].unit_ids.has(tank)).is_true()
	assert_array(_hold_orders(holder)).is_empty()
	_gather(tank, 14, 14)
	_think(HALT_AT + 15)
	var march: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(march.size()).is_equal(1)
	assert_bool(march[0].unit_ids.has(tank)).is_true()
	assert_array([march[0].target_x, march[0].target_y]).is_equal([32500, 32500])
	assert_array(_hold_orders(holder)).is_empty()
	assert_array([holder.holds, holder.releases]).is_equal([1, 0])


func test_the_levels_and_the_frozen_copies() -> void:
	(
		assert_array(
			[Rig.level_of("easy").wave_spread_tiles, Rig.level_of("easy").wave_regroup_ticks]
		)
		. is_equal([0, 0])
	)
	for level: String in ["normal", "hard"]:
		assert_int(Rig.level_of(level).wave_spread_tiles).is_greater(0)
		assert_int(Rig.level_of(level).wave_regroup_ticks).is_greater(0)
	for level: String in ["easy", "normal", "hard"]:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_array([copy.wave_spread_tiles, copy.wave_regroup_ticks]).is_equal([0, 0])


## The ids `holder` sets to hold or releases this think, one list a Command.
func _hold_orders(holder: AiHold) -> Array:
	_memory.commands_left = 8
	var sent: Array[Command] = []
	holder.run(_view(), _memory, sent)
	var found: Array = []
	for command: Command in sent:
		found.append(Array(command.unit_ids))
	return found
