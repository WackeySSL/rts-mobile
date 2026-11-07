extends "res://tests/ai/support/wave_suite.gd"
## `AiArmy`'s retreat, rejoin and all-in (plan row P180, ADR 0030 sections 4 and 6): a wave pulls
## back with a `MOVE` below `retreat_percent` of its launch value or past `retreat_ratio_percent`,
## rejoins the home squad at the staging point, and from `all_in_tick` every combat unit joins.

## Where the staging point is, in milli-tiles.
const STAGE_AT: Vector2i = Vector2i(11500, 11500)
## A spot for a wave and for the enemy beside it: far from every own building (radius 12).
const FIELD: Vector2i = Vector2i(20500, 20500)


func test_a_wave_pulls_back_below_the_retreat_percent_of_its_launch_value() -> void:
	var two: PackedInt32Array = _two_tanks()
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(2200)
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	# Tank a at 65 of 650 hp is worth 100: 1100 is exactly half of 2200, which is not below it.
	_world.hp[_row_in_world(two[0])] = 65
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	assert_array(_out).is_empty()
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)
	# 64 hp is worth 98: 1098 is under half, and the wave goes home on the next think.
	_world.hp[_row_in_world(two[0])] = 64
	_think(LAUNCH + 30)
	var sent: Array[Command] = _out
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.MOVE)
	assert_array(sent[0].unit_ids).is_equal(two)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([STAGE_AT.x, STAGE_AT.y])
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.RETREAT)
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[STAGING.x, STAGING.y]
	)
	assert_array([_army.retreats, _army.waves]).is_equal([1, 1])
	# The army's key went with the attack; the staging point holds a tracked key at the same cell.
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(0)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_greater(0)
	# Once: nothing more while it walks home.
	_think(LAUNCH + 45)
	assert_array(_out).is_empty()
	assert_int(_army.retreats).is_equal(1)


func test_a_wave_pulls_back_when_the_enemy_near_it_passes_the_ratio() -> void:
	_launched()
	_wave_to_field()
	# Two tanks and four squads: 2400, exactly twice the wave's 1200, which is not past the ratio.
	_foes(2, 4)
	_think(LAUNCH + 15)
	assert_array(_out).is_empty()
	assert_int(_army.retreats).is_equal(0)
	_enemy("rifle_squad", FIELD.x + 3000, FIELD.y + 2500)
	_see_all()
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_array(_of(Command.Type.MOVE)[0].unit_ids).is_equal(_members(AiArmy.WAVE))
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.RETREAT)
	assert_int(_army.retreats).is_equal(1)


func test_an_enemy_far_from_the_wave_does_not_count() -> void:
	_launched()
	_wave_to_field()
	# Five tanks in the far corner, 21 tiles from the wave and 40 from every building.
	for index: int in 5:
		_enemy("heavy_tank", 35500, 35500 + index % 2 * 500)
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_out).is_empty()
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)


func test_an_enemy_in_the_box_but_beyond_the_radius_does_not_count() -> void:
	_launched()
	_wave_to_field()
	# Five tanks 9 tiles off on both axes: inside the box round the wave, 12.7 tiles away.
	for index: int in 5:
		_enemy("heavy_tank", FIELD.x + 9000, FIELD.y + 9000 - index * 100)
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_out).is_empty()
	assert_int(_army.tests).is_equal(5)
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)


func test_the_ratio_reads_at_most_the_def_s_tests_and_they_are_counted() -> void:
	var def: OpponentDef = _def()
	def.target_tests_max = 2
	_arm_waves(null, def)
	_launched()
	_wave_to_field()
	_foes(4, 0)
	# Two tests see 2000, not past 2400; with three the wave sees 3000 and goes home.
	_think(LAUNCH + 15)
	assert_int(_army.tests).is_equal(2)
	assert_array(_out).is_empty()
	_army.tests_max = 3
	_think(LAUNCH + 30)
	assert_int(_army.tests).is_equal(3)
	assert_int(_army.retreats).is_equal(1)


func test_a_level_with_no_retreat_never_pulls_back() -> void:
	var level: AiDifficultyDef = _level()
	level.retreat_percent = 0
	level.retreat_ratio_percent = 0
	_arm_waves(level)
	var tank: int = _launched()
	_wave_to_field()
	_foes(5, 0)
	# Both tests would fire (the tank gone leaves 200 of 1200, five tanks stand beside it).
	_world.hp[_row_in_world(tank)] = 0
	AiRig.step(_world, _loop)
	_see_all()
	_think(LAUNCH + 15)
	_think(LAUNCH + 30)
	assert_array(_out).is_empty()
	assert_int(_army.retreats).is_equal(0)
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)


func test_a_retreat_the_budget_cannot_pay_changes_nothing_and_is_asked_again() -> void:
	var two: PackedInt32Array = _two_tanks()
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	_world.hp[_row_in_world(two[0])] = 1
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15, 0)
	assert_array(_out).is_empty()
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)
	assert_int(_army.retreats).is_equal(0)
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_int(_army.retreats).is_equal(1)


func test_a_retreat_leaves_the_army_key_to_a_defence_that_holds_it() -> void:
	var two: PackedInt32Array = _two_tanks()
	# A new squad stays at home and defends against a foe at the base: the army goal is its now.
	var defender: int = AiRig.add_unit_of(_world, 1, "rifle_squad", 8500, 11500)
	_enemy("heavy_tank", 15500, 7500)
	_settle()
	_see_all()
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45]:
		_think(tick)
	assert_int(_army.defences).is_equal(1)
	assert_array([_memory.squad_goal_x[AiArmy.HOME], _memory.squad_goal_y[AiArmy.HOME]]).is_equal(
		[15, 7]
	)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_greater(0)
	for id: int in _squads():
		if id != defender:
			_world.hp[_row_in_world(id)] = 0
	_world.hp[_row_in_world(two[0])] = 1
	AiRig.step(_world, _loop)
	_see_all()
	_think(LAUNCH + 60)
	assert_int(_army.retreats).is_equal(1)
	assert_array(_members(AiArmy.HOME)).is_equal(PackedInt32Array([defender]))
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_greater(0)


func test_a_wave_rejoins_the_home_squad_when_every_unit_has_stopped() -> void:
	var two: PackedInt32Array = _two_tanks()
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	_world.hp[_row_in_world(two[0])] = 1
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	AiRig.step(_world, _loop, _of(Command.Type.MOVE))
	assert_int(_world.order[_row_in_world(two[1])]).is_equal(World.Order.MOVE)
	# Still walking: the wave stays a wave, in retreat.
	_think(LAUNCH + 30)
	assert_array(_members(AiArmy.WAVE)).is_equal(two)
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.RETREAT)
	# One is home, one still walks: still not.
	_world.order[_row_in_world(two[0])] = World.Order.IDLE
	_think(LAUNCH + 45)
	assert_array(_members(AiArmy.WAVE)).is_equal(two)
	# Both stopped: the squad is the home squad again and no order is sent.
	_world.order[_row_in_world(two[1])] = World.Order.IDLE
	_think(LAUNCH + 60)
	assert_array(_out).is_empty()
	assert_array(_members(AiArmy.HOME)).is_equal(two)
	assert_array(_members(AiArmy.WAVE)).is_empty()
	assert_array([_memory.squad_role[AiArmy.WAVE], _memory.wave_start_tick]).is_equal(
		[AiMemory.NONE, LAUNCH + 60]
	)
	assert_int(_memory.wave_count).is_equal(1)
	assert_int(_memory.squad_state[AiArmy.HOME]).is_equal(AiMemory.SquadState.HOME)
	# The next wave asks the grown strength (1800), not the first (1200): 1500 does not launch,
	# 2000 does.
	_world.hp[_row_in_world(two[0])] = 325
	_think(LAUNCH + 75)
	assert_int(_memory.wave_count).is_equal(1)
	assert_array(_out).is_empty()
	_world.hp[_row_in_world(two[0])] = 650
	_think(LAUNCH + 90)
	assert_int(_memory.wave_count).is_equal(2)


func test_from_the_all_in_tick_the_whole_home_squad_goes_whatever_its_value() -> void:
	_target_at()
	_settle()
	_think(ALL_IN - 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_memory.wave_count).is_equal(0)
	_think(ALL_IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_squads())
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_array([_memory.wave_count, _army.waves]).is_equal([1, 1])
	assert_int(_memory.squad_launch_value[AiArmy.WAVE]).is_equal(200)


func test_after_the_all_in_tick_every_new_unit_joins_the_wave_with_its_own_order() -> void:
	_target_at()
	_settle()
	_think(ALL_IN)
	var late: int = _tank()
	_settle()
	_think(ALL_IN + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([late]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_array(_members(AiArmy.WAVE)).is_equal(_all_ids(late))
	assert_array([_memory.wave_count, _army.waves]).is_equal([1, 1])
	_think(ALL_IN + 30)
	assert_array(_out).is_empty()


func test_an_all_in_joiner_of_a_shifted_home_squad_leaves_the_flag_clear_and_the_keys_held(
) -> void:
	_target_at()
	_settle()
	_think(ALL_IN)
	_memory.home_shifted = 1
	_memory.squad_goal_x[AiArmy.HOME] = 20
	_memory.squad_goal_y[AiArmy.HOME] = 20
	_tank()
	_settle()
	_think(ALL_IN + 15)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.home_shifted).is_equal(0)
	assert_array([_memory.squad_goal_x[AiArmy.HOME], _memory.squad_goal_y[AiArmy.HOME]]).is_equal(
		[STAGING.x, STAGING.y]
	)
	# Foot and tracked: the wave's two keys, held on the next thinks.
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	_think(ALL_IN + 30)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)


func test_the_all_in_tick_sends_a_retreating_wave_out_again_and_ends_retreats() -> void:
	var first: int = _launched()
	_world.hp[_row_in_world(first)] = 0
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.RETREAT)
	# The squads are still walking home at the all-in tick: it, not idleness, ends the retreat.
	AiRig.step(_world, _loop, _of(Command.Type.MOVE))
	for id: int in _squads():
		assert_int(_world.order[_row_in_world(id)]).is_equal(World.Order.MOVE)
	_think(ALL_IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_squads())
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)
	assert_array([_memory.wave_count, _army.waves, _army.retreats]).is_equal([2, 2, 1])
	# Weaker than the retreat percent of its launch value, and it goes on: no retreat in the all-in.
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 40
	_think(ALL_IN + 15)
	assert_array(_out).is_empty()
	assert_int(_army.retreats).is_equal(1)


func test_all_in_tick_zero_never_sends_everything() -> void:
	var level: AiDifficultyDef = _level()
	level.all_in_tick = 0
	_arm_waves(level)
	_target_at()
	_settle()
	# The two squads (200) are far under the strength: no launch at any tick.
	for tick: int in [LAUNCH, ALL_IN, ALL_IN * 5]:
		_think(tick)
		assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_memory.wave_count).is_equal(0)


func test_the_all_in_overrides_the_defence_and_a_standing_threat() -> void:
	_target_at()
	_enemy("heavy_tank", 15500, 7500)
	_settle()
	_see_all()
	_think(ALL_IN - 30)
	_think(ALL_IN - 15)
	assert_int(_army.defences).is_equal(0)
	assert_int(_memory.wave_count).is_equal(0)
	# The threat has stood for the reaction delay: no defence order, one launch order.
	_think(ALL_IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_squads())
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_int(_army.defences).is_equal(0)
	# A new unit joins the wave with one order, not a defence order as well.
	var late: int = _tank()
	_see_all()
	_think(ALL_IN + 15)
	sent = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([late]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_int(_army.defences).is_equal(0)


func test_a_wave_in_the_field_goes_on_after_the_headquarters_is_gone() -> void:
	AiRig.give(_world, 1, "barracks", 12, 6)
	var two: PackedInt32Array = _two_tanks()
	var hq: int = _row_in_world(AiRig.ids_of(_world, 1, "headquarters")[0])
	_world.hp[hq] = 0
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	assert_int(_memory.home_x).is_equal(AiMemory.NONE)
	# Tank a at 65 of 650 and tank b full: 1100 is half of 2200; 64 hp is under it.
	_world.hp[_row_in_world(two[0])] = 64
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_array(_of(Command.Type.MOVE)[0].unit_ids).is_equal(two)
	assert_int(_army.retreats).is_equal(1)


func test_a_wave_unit_s_hp_lost_in_the_wave_is_no_home_unseen_hit_after_the_disband() -> void:
	var two: PackedInt32Array = _two_tanks()
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	# Tank a loses hp in the wave (no seen enemy near it), and the wave goes home.
	_world.hp[_row_in_world(two[0])] = 1
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	AiRig.step(_world, _loop, _of(Command.Type.MOVE))
	for id: int in two:
		_world.order[_row_in_world(id)] = World.Order.IDLE
	_think(LAUNCH + 30)
	assert_array(_members(AiArmy.HOME)).is_equal(two)
	# Home again with the hp it has: no think finds a hit, no shift order is sent.
	for tick: int in [LAUNCH + 45, LAUNCH + 60, LAUNCH + 75]:
		_think(tick)
		assert_array(_out).is_empty()
	assert_int(_army.shifts).is_equal(0)


## Launches the first wave with two tanks (a, b ascending) and the squads: value 2200. Returns the
## two tanks' ids.
func _two_tanks() -> PackedInt32Array:
	_target_at()
	var a: int = _tank()
	var b: int = _tank(10500, 9500)
	_settle()
	_until(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	return PackedInt32Array([a, b])


## Puts every unit of the wave on the field's spot, and kills the enemy's two starting squads (9
## tiles from it: they would count in the ratio).
func _wave_to_field() -> void:
	for id: int in AiRig.ids_of(_world, 2, "rifle_squad"):
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)
	for id: int in _members(AiArmy.WAVE):
		_put(id, FIELD.x, FIELD.y)


## `tanks` heavy tanks and `squads` rifle squads of player 2 beside the field's spot, seen.
func _foes(tanks: int, squads: int) -> void:
	for index: int in tanks:
		_enemy("heavy_tank", FIELD.x + 2000, FIELD.y + index * 500)
	for index: int in squads:
		_enemy("rifle_squad", FIELD.x + 3000, FIELD.y + index * 500)
	_see_all()
