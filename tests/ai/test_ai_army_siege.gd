extends "res://tests/ai/support/control_suite.gd"
## The siege and the press of a wave (plan row P197, ADR 0030 section 6): a wave at an enemy
## base focuses the producers that decide the match once nothing armed stands near it, a wave
## that is ahead does not retreat for loss of value, and a wave ahead at a producer launches the
## all-in early.

## The wave's spot, 21 tiles from the enemy Headquarters and 24 from the own one (the defence radius
## is 12), and where the enemy buildings stand in the cases, in tiles: a few tiles from the spot.
const SPOT: Vector2i = Vector2i(6500, 30500)
const BARRACKS_AT: Vector2i = Vector2i(8, 28)
const POWER_AT: Vector2i = Vector2i(5, 29)
const TANK_AT: Vector2i = Vector2i(8500, 30500)


## The suite's level with `press` and `siege_on`, on a def with no unseen-hit shift.
func _pressing(press: int, siege_on: int) -> void:
	var level: AiDifficultyDef = _level()
	level.press_percent = press
	level.siege_focus = siege_on
	var own: OpponentDef = _def()
	own.unseen_hit_shift_tiles = 0
	_arm_waves(level, own)


## Puts the wave on the spot (the enemy's starting squads die first).
func _to_spot() -> void:
	_to_field()
	for id: int in _members(AiArmy.WAVE):
		_put(id, SPOT.x, SPOT.y)


## Kills the own rifle squads and leaves tank `id` at 64 hp: the wave is worth 1098 of its 2200.
func _weaken(id: int) -> void:
	for squad: int in _squads():
		_hp(squad, 0)
	_hp(id, 64)
	AiRig.step(_world, _loop)
	_see_all()


## A wave on the spot and the enemy producer `id` at `tile` (a barracks), seen.
func _siege_scene(tile: Vector2i = BARRACKS_AT, type_id: String = "barracks") -> int:
	_two_tanks()
	_to_spot()
	var found: int = AiRig.give(_world, 2, type_id, tile.x, tile.y)
	_settle()
	_see_all()
	return found


func test_a_wave_at_an_enemy_producer_attacks_it_once() -> void:
	_pressing(0, 1)
	var barracks: int = _siege_scene()
	var wave: PackedInt32Array = _members(AiArmy.WAVE)
	_think(LAUNCH + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].target_id).is_equal(barracks)
	assert_array(sent[0].unit_ids).is_equal(wave)
	assert_int(_army.focuses).is_equal(1)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(barracks)
	# The attack-move to the target is replaced, not sent beside it.
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# Held: nothing more while the target stands.
	_think(LAUNCH + 30)
	assert_array(_out).is_empty()
	assert_int(_army.focuses).is_equal(1)


func test_a_producer_comes_before_a_nearer_building_that_decides_nothing() -> void:
	_pressing(0, 1)
	var barracks: int = _siege_scene()
	AiRig.give(_world, 2, "power_plant", POWER_AT.x, POWER_AT.y)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(barracks)


func test_an_unfinished_producer_is_not_a_target() -> void:
	_pressing(0, 1)
	var site: int = _siege_scene()
	_world.build_left[_world.index_of(site)] = 1000000
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK)).is_empty()
	assert_int(_army.focuses).is_equal(0)


func test_a_level_without_the_siege_keeps_the_attack_move() -> void:
	_pressing(0, 0)
	_siege_scene()
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45]:
		_think(tick)
		assert_array(_of(Command.Type.ATTACK)).is_empty()
	assert_int(_army.focuses).is_equal(0)


func test_a_producer_out_of_the_radius_is_not_sieged() -> void:
	_pressing(0, 1)
	_siege_scene(Vector2i(36, 36))
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK)).is_empty()


func test_armed_foes_near_the_wave_come_first() -> void:
	_pressing(0, 1)
	_siege_scene()
	var tank: int = _enemy("heavy_tank", TANK_AT.x, TANK_AT.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK)).is_empty()
	# The tank dies: the producer is next.
	_kill(tank)
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.ATTACK).size()).is_equal(1)


func test_an_armed_building_near_the_wave_comes_first_too() -> void:
	_pressing(0, 1)
	_siege_scene()
	AiRig.give(_world, 2, "defence_turret", 9, 31)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK)).is_empty()


func test_armed_foes_that_show_up_end_the_siege_and_the_attack_move_returns() -> void:
	_pressing(0, 1)
	var barracks: int = _siege_scene()
	_think(LAUNCH + 15)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(barracks)
	_enemy("heavy_tank", TANK_AT.x, TANK_AT.y)
	_see_all()
	# The focus is dropped; the generic re-target sends the attack-move to the base target again.
	_think(LAUNCH + 30)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(AiMemory.NONE)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal(
		[_centre(TARGET).x, _centre(TARGET).y]
	)


func test_a_dead_target_gives_the_next_producer_or_the_attack_move() -> void:
	_pressing(0, 1)
	var barracks: int = _siege_scene()
	var second: int = AiRig.give(_world, 2, "vehicle_factory", 10, 28)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(barracks)
	_kill(barracks)
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.ATTACK)[0].target_id).is_equal(second)
	_kill(second)
	_think(LAUNCH + 45)
	assert_int(_memory.squad_focus[AiArmy.WAVE]).is_equal(AiMemory.NONE)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_a_wave_that_is_ahead_does_not_retreat_for_loss_of_value() -> void:
	_pressing(150, 0)
	var two: PackedInt32Array = _two_tanks()
	_to_spot()
	# Tank a at 64 of 650 hp: the wave is worth 1098, under half of 2200. One rifle squad (100)
	# stands near it: the wave is well ahead.
	_weaken(two[0])
	_enemy("rifle_squad", TANK_AT.x, TANK_AT.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.retreats).is_equal(0)
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)


func test_a_wave_that_is_not_ahead_still_retreats() -> void:
	_pressing(150, 0)
	var two: PackedInt32Array = _two_tanks()
	_to_spot()
	_weaken(two[0])
	# A heavy tank (1000) near a wave of 1098: not 150 percent ahead.
	_enemy("heavy_tank", TANK_AT.x, TANK_AT.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_army.retreats).is_equal(1)


func test_a_level_without_the_press_retreats_a_wave_that_is_ahead() -> void:
	_pressing(0, 0)
	var two: PackedInt32Array = _two_tanks()
	_to_spot()
	_weaken(two[0])
	_enemy("rifle_squad", TANK_AT.x, TANK_AT.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_army.retreats).is_equal(1)


func test_a_wave_ahead_at_a_producer_calls_the_home_squad_early() -> void:
	_pressing(150, 0)
	_siege_scene()
	var home: int = _tank(8500, 11500)
	_settle()
	_see_all()
	assert_bool(ALL_IN > LAUNCH + 60).is_true()
	_think(LAUNCH + 15)
	# The all-in came early: the home tank joined the wave with an order to the wave's goal.
	assert_int(_memory.member_squad[_memory.member_id.bsearch(home)]).is_equal(AiArmy.WAVE)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([home]))


func test_a_wave_that_is_not_at_a_producer_does_not_press() -> void:
	_pressing(150, 0)
	_two_tanks()
	_to_spot()
	var home: int = _tank(8500, 11500)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_memory.member_squad[_memory.member_id.bsearch(home)]).is_equal(AiArmy.HOME)


func test_a_wave_that_is_outweighed_at_a_producer_does_not_press() -> void:
	_pressing(150, 0)
	_siege_scene()
	_enemy("heavy_tank", TANK_AT.x, TANK_AT.y)
	_enemy("heavy_tank", TANK_AT.x, TANK_AT.y + 500)
	var home: int = _tank(8500, 11500)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_memory.member_squad[_memory.member_id.bsearch(home)]).is_equal(AiArmy.HOME)


func test_the_ladder_presses_and_sieges_from_normal_up() -> void:
	var easy: AiDifficultyDef = Rig.level_of("easy")
	var normal: AiDifficultyDef = Rig.level_of("normal")
	var hard: AiDifficultyDef = Rig.level_of("hard")
	assert_array([easy.press_percent, easy.siege_focus]).is_equal([0, 0])
	assert_int(normal.siege_focus).is_equal(1)
	assert_int(hard.siege_focus).is_equal(1)
	# A lower percent presses on a smaller edge: Hard presses sooner than Normal.
	assert_bool(normal.press_percent > hard.press_percent and hard.press_percent > 0).is_true()


func test_the_front_of_a_strung_out_wave_sieges_not_its_centre() -> void:
	_pressing(0, 1)
	var barracks: int = _siege_scene()
	# Three of the four units stand 30 tiles away: the centre is far from the producer, the front is
	# not.
	var wave: PackedInt32Array = _members(AiArmy.WAVE)
	for index: int in 3:
		_put(wave[index + 1], 36500, 6500)
	_think(LAUNCH + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].target_id).is_equal(barracks)


func test_a_foe_far_from_the_front_does_not_stop_the_siege() -> void:
	_pressing(0, 1)
	_siege_scene()
	# 9 tiles from the front (the reach is half the defence radius, 6 tiles): not armed near it.
	_enemy("heavy_tank", SPOT.x + 9000, SPOT.y)
	_see_all()
	_think(LAUNCH + 15)
	assert_int(_of(Command.Type.ATTACK).size()).is_equal(1)


func test_a_wave_far_ahead_sieges_through_a_few_armed_foes() -> void:
	_pressing(150, 1)
	var barracks: int = _siege_scene()
	# A rifle squad (100) near the front against a wave of 2200: far ahead, so the producer comes
	# first.
	_enemy("rifle_squad", TANK_AT.x, TANK_AT.y)
	_see_all()
	_think(LAUNCH + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].target_id).is_equal(barracks)


func test_a_wave_that_is_not_ahead_fights_the_armed_foes_first() -> void:
	_pressing(150, 1)
	_siege_scene()
	_enemy("heavy_tank", TANK_AT.x, TANK_AT.y)
	_enemy("heavy_tank", TANK_AT.x, TANK_AT.y + 500)
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.ATTACK)).is_empty()
