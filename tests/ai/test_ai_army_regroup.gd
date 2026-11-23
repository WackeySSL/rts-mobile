extends "res://tests/ai/support/groups_suite.gd"
## The regroup and the closing push of the all-in wave (plan row P250e): a wave whose farthest
## member is over the spread from its centre halts there until the rear is within half of it, the
## cap passes or an enemy is near; never before the all-in tick, never near the target. A wave at
## the target with a lead over the enemy seen near it is reinforced at once.

var _tank_id: int = -1


## A launched wave (two squads and a tank) with the squads at (15.5, 15.5) and (16.5, 15.5) and the
## tank at (`tank_x`, `tank_y`) milli-tiles, the thinks done up to the tick before the all-in.
func _strung(tank_x: int, tank_y: int, spread: int = SPREAD) -> void:
	_grouped(0, 0, spread, CAP, LEAD)
	_tank_id = _wave_before_all_in()
	var squads: PackedInt32Array = _squads()
	_put(squads[0], 15500, 15500)
	_put(squads[1], 16500, 15500)
	_put(_tank_id, tank_x, tank_y)


func _halts() -> int:
	return _army.group_stats()[2]


func test_a_strung_out_wave_halts_at_its_centre_from_the_all_in_tick() -> void:
	_strung(22500, 22500)
	_think(ALL_IN)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_all_ids(_tank_id))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([18500, 17500])
	assert_array([_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]]).is_equal(
		[18, 17]
	)
	assert_int(_halts()).is_equal(1)


func test_a_wave_is_not_halted_before_the_all_in_tick() -> void:
	_strung(22500, 22500)
	_think(ALL_IN - 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_halts()).is_equal(0)


func test_a_closed_up_wave_is_not_halted() -> void:
	_strung(19500, 17500)
	_think(ALL_IN)
	assert_int(_halts()).is_equal(0)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_the_halt_holds_until_the_rear_is_within_half_of_the_spread() -> void:
	_strung(22500, 22500)
	_think(ALL_IN)
	_think(ALL_IN + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# 6.4 tiles from the centre: over half of 5 (2.5), so it still waits.
	_put(_tank_id, 21000, 21000)
	_think(ALL_IN + 30)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	# The tank has come up: the farthest member is within 2.5 tiles of the centre.
	_put(_tank_id, 17500, 16500)
	_think(ALL_IN + 45)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([32500, 32500])
	assert_int(_halts()).is_equal(1)


func test_the_halt_ends_only_when_the_rear_is_within_half_of_the_spread_not_a_bit_over() -> void:
	_strung(22500, 22500)
	_think(ALL_IN)
	# 3.3 tiles from the centre of the three: over half of 5 (2.5), under the spread itself.
	_put(_tank_id, 21000, 15500)
	_think(ALL_IN + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_an_enemy_near_the_rear_alone_ends_the_halt() -> void:
	_strung(22000, 22000)
	var squads: PackedInt32Array = _squads()
	_put(squads[0], 8500, 8500)
	_put(squads[1], 22500, 22500)
	_think(ALL_IN)
	assert_int(_halts()).is_equal(1)
	_see_all()
	# 2 tiles from the rear squad, 18 from the front: only the rear has an enemy near.
	_enemy("heavy_tank", 8500, 10500)
	_settle()
	_think(ALL_IN + 15)
	assert_array([_first_target()]).is_equal([Vector2i(32500, 32500)])


func test_the_cap_ends_the_halt_and_no_new_halt_comes_for_the_same_span() -> void:
	_strung(22500, 22500)
	_think(ALL_IN)
	_think(ALL_IN + CAP - 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(ALL_IN + CAP)
	assert_array([_first_target()]).is_equal([Vector2i(32500, 32500)])
	_think(ALL_IN + CAP + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_halts()).is_equal(1)
	_think(ALL_IN + 2 * CAP)
	assert_int(_halts()).is_equal(2)


func test_an_enemy_near_the_front_stops_the_halt_and_prevents_it() -> void:
	_strung(22500, 22500)
	_see_all()
	_enemy("heavy_tank", 24500, 24500)
	_settle()
	_think(ALL_IN)
	assert_int(_halts()).is_equal(0)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_an_enemy_that_comes_near_ends_a_standing_halt() -> void:
	_strung(22500, 22500)
	_think(ALL_IN)
	_see_all()
	_enemy("heavy_tank", 24500, 24500)
	_settle()
	_think(ALL_IN + 15)
	assert_array([_first_target()]).is_equal([Vector2i(32500, 32500)])


func test_a_front_that_has_arrived_is_never_halted() -> void:
	_strung(26500, 26500)
	_think(ALL_IN)
	assert_int(_halts()).is_equal(0)


func test_a_spread_of_zero_never_halts() -> void:
	_strung(22500, 22500, 0)
	_think(ALL_IN)
	assert_int(_halts()).is_equal(0)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()


func test_a_wave_at_the_target_with_a_lead_is_reinforced_at_once() -> void:
	_grouped(GROUP_MIN, GATHER, SPREAD, CAP, LEAD)
	_tank_id = _wave_before_all_in()
	_put(_tank_id, 30500, 30500)
	for id: int in _squads():
		_put(id, 30500, 31500)
	var late: int = _tank(9500, 9500)
	_settle()
	_think(ALL_IN)
	assert_array(_first_ids()).is_equal(PackedInt32Array([late]))
	assert_int(_army.group_stats()[3]).is_equal(1)


func test_a_wave_at_the_target_without_a_lead_waits_for_its_group() -> void:
	_grouped(GROUP_MIN, GATHER, SPREAD, CAP, LEAD)
	_tank_id = _wave_before_all_in()
	_put(_tank_id, 30500, 30500)
	for id: int in _squads():
		_put(id, 30500, 31500)
	_see_all()
	# Three enemy heavy tanks (3000) against the wave's 1200: not twice as much.
	for step: int in 3:
		_enemy("heavy_tank", 31500 + step * 500, 31500)
	_tank(9500, 9500)
	_settle()
	_think(ALL_IN)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_army.group_stats()[3]).is_equal(0)


func _first_target() -> Vector2i:
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	return Vector2i(sent[0].target_x, sent[0].target_y) if not sent.is_empty() else Vector2i(-1, -1)
