extends "res://tests/ai/support/control_suite.gd"
## The wave recall and armed buildings in the retreat ratio (plan row P180b, ADR 0030 section 6),
## and the three key-ledger fixes of P180's last review: a dead wave's army keys during the all-in,
## the wave units that rejoin during a standing defence, and a retreat whose staging point moves.


func test_a_threat_that_outweighs_the_home_squad_recalls_the_wave_on_the_reaction_tick() -> void:
	_two_tanks()
	_to_field()
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_see_all()
	# Seen at LAUNCH + 15; the defence answers 30 ticks later, and so does the recall.
	_think(LAUNCH + 15)
	_think(LAUNCH + 30)
	assert_array(_out).is_empty()
	_think(LAUNCH + 45)
	var sent: Array[Command] = _of(Command.Type.MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_members(AiArmy.WAVE))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([STAGE_AT.x, STAGE_AT.y])
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.RETREAT)
	assert_int(_army.retreats).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(0)
	assert_int(_view().row_of(foe)).is_greater_equal(0)


func test_a_threat_that_does_not_outweigh_the_home_squad_leaves_the_wave_out() -> void:
	_target_at()
	_tank()
	_tank(10500, 9500)
	_settle()
	_until(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	_to_field()
	# A tank stays home (1000) against two tanks (2000): twice is not past the ratio of 200.
	var home: int = _tank(8500, 11500)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_enemy("heavy_tank", NEAR.x, NEAR.y + 500)
	_settle()
	_see_all()
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45, LAUNCH + 60]:
		_think(tick)
		assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.retreats).is_equal(0)
	assert_array(_members(AiArmy.HOME)).is_equal(PackedInt32Array([home]))
	# One more squad of rifles passes it: 2100 against 1000 times 2.
	_enemy("rifle_squad", NEAR.x + 500, NEAR.y)
	_see_all()
	_think(LAUNCH + 75)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_int(_army.retreats).is_equal(1)


func test_a_level_without_a_ratio_never_recalls() -> void:
	_control(0, 0, 0)
	_two_tanks()
	_to_field()
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_see_all()
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45, LAUNCH + 60]:
		_think(tick)
		assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.retreats).is_equal(0)


func test_the_all_in_overrides_the_recall() -> void:
	_two_tanks()
	_to_field()
	_until(ALL_IN - 15)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_see_all()
	# Seen at ALL_IN: the all-in tick is the first without a defence and without a recall.
	for tick: int in [ALL_IN, ALL_IN + 15, ALL_IN + 30, ALL_IN + 45]:
		_think(tick)
		assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.retreats).is_equal(0)
	assert_int(_memory.squad_state[AiArmy.WAVE]).is_equal(AiMemory.SquadState.WAVE)


func test_armed_seen_buildings_count_in_the_ratio_by_their_hp() -> void:
	# A ratio of 100: the wave retreats when the enemy near it is worth more than its own 2200.
	_control(0, 0, 100)
	_two_tanks()
	_to_field()
	var turret: int = AiRig.type_of(_world, "defence_turret")
	var cost: int = _view().type_cost[turret]
	var count: int = 2200 / cost
	for index: int in count:
		AiRig.give(_world, 2, "defence_turret", 14 + index * 3, 29)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	# `count` turrets are worth at most 2200: not past it.
	assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.retreats).is_equal(0)
	AiRig.give(_world, 2, "defence_turret", 14 + count * 3, 29)
	_settle()
	_see_all()
	_think(LAUNCH + 30)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_int(_army.retreats).is_equal(1)
	# Out of every weapon's range, so nothing fought: a whole turret is worth its cost.
	(
		assert_int(AiIntel.value_of(_view(), _row(AiRig.ids_of(_world, 2, "defence_turret")[0])))
		. is_equal(cost)
	)


func test_an_unarmed_seen_building_does_not_count() -> void:
	_control(0, 0, 100)
	_two_tanks()
	_to_field()
	# Two refineries in view of the wave: worth 2800, more than 2200, with no weapon.
	for index: int in 2:
		AiRig.give(_world, 2, "refinery", 14 + index * 6, 29)
	_settle()
	_see_all()
	for tick: int in [LAUNCH + 15, LAUNCH + 30]:
		_think(tick)
		assert_array(_of(Command.Type.MOVE)).is_empty()
	assert_int(_army.retreats).is_equal(0)


func test_a_damaged_armed_building_counts_its_hp_share() -> void:
	_control(0, 0, 100)
	_two_tanks()
	_to_field()
	var cost: int = _view().type_cost[AiRig.type_of(_world, "defence_turret")]
	var count: int = 2200 / cost + 1
	var ids: Array[int] = []
	for index: int in count:
		ids.append(AiRig.give(_world, 2, "defence_turret", 14 + index * 3, 29))
	# Every turret at a third of its hp: `count` of them are worth a third of `count` costs.
	for id: int in ids:
		_hp(id, _view().type_max_hp[AiRig.type_of(_world, "defence_turret")] / 3)
	_settle()
	_see_all()
	_think(LAUNCH + 15)
	assert_array(_of(Command.Type.MOVE)).is_empty()


func test_a_dead_wave_s_army_keys_go_in_the_all_in_with_a_threat_standing() -> void:
	# No ratio: the threat does not recall the wave, so it stays out with its keys.
	_control(0, 0, 0)
	_two_tanks()
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_see_all()
	_until(ALL_IN - 15)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	for id: int in _members(AiArmy.WAVE):
		_hp(id, 0)
	AiRig.step(_world, _loop)
	_see_all()
	_think(ALL_IN)
	assert_int(_memory.squad_role[AiArmy.WAVE]).is_equal(AiMemory.NONE)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(0)
	assert_int(_memory.threat_first_tick).is_not_equal(AiMemory.NONE)


func test_wave_units_that_rejoin_during_a_standing_defence_are_sent_to_it() -> void:
	_control(0, 0, 0)
	var two: PackedInt32Array = _two_tanks()
	var defender: int = AiRig.add_unit_of(_world, 1, "rifle_squad", 8500, 11500)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [LAUNCH + 15, LAUNCH + 30, LAUNCH + 45]:
		_think(tick)
	assert_int(_army.defences).is_equal(1)
	for id: int in _squads():
		if id != defender:
			_hp(id, 0)
	_hp(two[0], 1)
	AiRig.step(_world, _loop)
	_see_all()
	_think(LAUNCH + 60)
	assert_int(_army.retreats).is_equal(1)
	AiRig.step(_world, _loop, _of(Command.Type.MOVE))
	for id: int in two:
		_world.order[_row_in_world(id)] = World.Order.IDLE
	# Home again: the wave is over and the two join the home squad.
	_think(LAUNCH + 75)
	assert_array(_members(AiArmy.HOME)).is_equal(PackedInt32Array([two[0], two[1], defender]))
	# The defence stands on its tile: the two, and only the two, are sent to it, once.
	_think(LAUNCH + 90)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(two)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([NEAR.x, NEAR.y])
	_think(LAUNCH + 105)
	assert_array(_out).is_empty()


func test_a_retreat_follows_the_staging_point_when_it_moves() -> void:
	_control(0, 0, 0)
	var two: PackedInt32Array = _two_tanks()
	for id: int in _squads():
		_hp(id, 0)
	_hp(two[0], 1)
	AiRig.step(_world, _loop)
	_think(LAUNCH + 15)
	assert_int(_army.retreats).is_equal(1)
	AiRig.step(_world, _loop, _of(Command.Type.MOVE))
	# The enemy base estimate moves: the staging point goes to (13, 7).
	_target_at(Vector2i(32, 8))
	_think(LAUNCH + 30)
	var sent: Array[Command] = _of(Command.Type.MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(two)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([13500, 7500])
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([13, 7])
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[13, 7]
	)
	# The books hold the new point and not the old one; asked once.
	for key: int in _memory.goal_keys():
		assert_bool(_memory.goal_x[key] == 11 and _memory.goal_y[key] == 11).is_false()
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_greater(0)
	_think(LAUNCH + 45)
	assert_array(_of(Command.Type.MOVE)).is_empty()
