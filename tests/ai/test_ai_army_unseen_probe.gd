extends "res://tests/ai/support/army_suite.gd"
## The unseen-hit shift is a probe (plan row P179b, lead decision 2026-11-07): the home squad holds
## the shifted goal while a member the shift named is alive and not idle; when every one has
## arrived idle or died, the return to the staging point follows and releases the army keys. A new
## hit shifts again after that (out and back, never creeping). The def has a shift of 4 tiles and,
## unless a case says so, no defence radius.

const SHIFT: int = 4
const FIRST: int = 5
## A spot 8 tiles east of the Headquarters, inside the defence radius of 12 of the staging def.
const NEAR: Vector2i = Vector2i(15500, 7500)


func _arm_shift(radius: int = 0) -> void:
	var def: OpponentDef = _def()
	def.defend_radius_tiles = radius
	def.unseen_hit_shift_tiles = SHIFT
	_arm("normal", def)


func _start() -> void:
	_settle()
	_see_all()
	_think(FIRST)


func _hurt(id: int, amount: int = 1) -> void:
	_world.hp[_row_in_world(id)] -= amount


func _goal() -> Array[int]:
	return [_memory.squad_goal_x[0], _memory.squad_goal_y[0]]


## A hit and the shift's think at `tick`, with the order applied in the World (one tick).
func _shift_at(tick: int) -> void:
	_hurt(_squads()[0])
	_think(tick)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	AiRig.step(_world, _loop, _out)


## Steps the World until no unit of player 1 has an order (at most `ticks`).
func _walk_until_idle(ticks: int = 600) -> void:
	for _tick: int in ticks:
		var moving: bool = false
		for id: int in _squads():
			moving = moving or _world.order[_row_in_world(id)] != World.Order.IDLE
		if not moving:
			return
		AiRig.step(_world, _loop)


func test_while_a_named_member_still_moves_nothing_is_sent_and_the_goal_is_held() -> void:
	_arm_shift()
	_start()
	_shift_at(FIRST + 15)
	assert_int(_world.order[_row_in_world(_squads()[0])]).is_equal(World.Order.ATTACK_MOVE)
	for tick: int in [30, 45, 60]:
		_think(FIRST + tick)
		assert_array(_out).is_empty()
	assert_array(_goal()).is_equal([14, 14])
	assert_array([_memory.home_shifted, _memory.goal_keys_of(AiMemory.Owner.ARMY)]).is_equal([1, 1])


func test_a_shifted_squad_that_arrives_idle_goes_back_and_releases_the_army_keys() -> void:
	_arm_shift()
	_start()
	_shift_at(FIRST + 15)
	_walk_until_idle()
	_see_all()
	_think(FIRST + 700)
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array(moves[0].unit_ids).is_equal(_squads())
	assert_array([moves[0].target_x, moves[0].target_y]).is_equal([11500, 11500])
	assert_array(_goal()).is_equal([11, 11])
	assert_array([_memory.home_shifted, _memory.goal_keys_of(AiMemory.Owner.ARMY)]).is_equal([0, 0])
	assert_int(_army.returns).is_equal(2)
	# A new hit shifts again, out and back: not a creep.
	AiRig.step(_world, _loop, _out)
	_hurt(_squads()[0])
	_think(FIRST + 715)
	assert_array(_goal()).is_equal([14, 14])
	assert_int(_army.shifts).is_equal(2)


func test_a_shifted_mixed_squad_that_dies_releases_its_keys_and_the_scout_may_go() -> void:
	_arm_shift()
	_start()
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_think(FIRST + 15)
	_hurt(tank)
	_think(FIRST + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	AiRig.step(_world, _loop, _out)
	# Foot and tracked keys on the shifted cell, and the staging key: the cap (4) has room for one.
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	_world.hp[_row_in_world(tank)] = 0
	AiRig.step(_world, _loop)
	_see_all()
	_think(FIRST + 45)
	assert_array(_out).is_empty()
	assert_int(_memory.unit_id.size()).is_equal(0)
	assert_array([_memory.home_shifted, _memory.goal_keys_of(AiMemory.Owner.ARMY)]).is_equal([0, 0])
	assert_array(_goal()).is_equal([11, 11])
	assert_bool(_memory.add_goal_key(30, 30, AiIntel.TRACKED, AiMemory.Owner.SCOUT)).is_true()
	assert_int(_memory.goal_room(AiMemory.Owner.SCOUT)).is_greater_equal(1)


func test_a_shifted_squad_is_not_shifted_again_while_it_holds_the_goal() -> void:
	_arm_shift()
	_start()
	_shift_at(FIRST + 15)
	var keys: int = _memory.goal_keys()
	for tick: int in [30, 45]:
		_hurt(_squads()[0])
		_hurt(_squads()[1])
		_think(FIRST + tick)
		assert_array(_out).is_empty()
		assert_array(_goal()).is_equal([14, 14])
	assert_array([_army.shifts, _memory.goal_keys()]).is_equal([1, keys])


func test_a_defence_replaces_a_shifted_goal_and_the_squads_then_go_back() -> void:
	_arm_shift(12)
	_start()
	_shift_at(FIRST + 15)
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_see_all()
	for tick: int in [30, 45, 60]:
		_think(FIRST + tick)
	assert_array(_goal()).is_equal([15, 7])
	assert_int(_memory.home_shifted).is_equal(0)
	_world.hp[_row_in_world(foe)] = 0
	AiRig.step(_world, _loop)
	_think(FIRST + 75)
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array([moves[0].target_x, moves[0].target_y]).is_equal([11500, 11500])
	assert_array(_goal()).is_equal([11, 11])


func test_two_hurt_units_in_one_slot_give_one_shift() -> void:
	_arm_shift()
	_start()
	_hurt(_squads()[0])
	_hurt(_squads()[1])
	_think(FIRST + 15)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_array(_goal()).is_equal([14, 14])
	assert_int(_army.shifts).is_equal(1)


func test_a_known_base_estimate_serves_without_a_headquarters() -> void:
	_arm_shift()
	_start()
	_memory.base_x = 30
	_memory.base_y = 30
	AiRig.kill(_world, _loop, AiRig.row_of(_world, 1, String(_intel.hq_type)))
	_see_all()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_int(_memory.home_x).is_equal(-1)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	# From (11, 11) along (19, 19), length 26: (2.9, 2.9) rounds to (3, 3).
	assert_array(_goal()).is_equal([14, 14])


func test_a_unit_that_joins_in_the_slot_of_the_shift_is_named_by_it() -> void:
	_arm_shift()
	_start()
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_hurt(_squads()[0])
	_think(FIRST + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([_squads()[0], _squads()[1], tank]))
	AiRig.step(_world, _loop, _out)
	# The squads have arrived, the tank is still on its way: the probe goes on for the tank.
	for id: int in _squads():
		_world.order[_row_in_world(id)] = World.Order.IDLE
	_think(FIRST + 30)
	assert_array(_out).is_empty()
	assert_int(_memory.home_shifted).is_equal(1)


func test_an_idle_member_that_fires_at_a_foe_in_range_keeps_the_probe_until_it_is_gone() -> void:
	# No defence radius: the foe is no threat, only a target in weapon range of the arrived squad.
	_arm_shift()
	_start()
	_shift_at(FIRST + 15)
	_walk_until_idle()
	var at: Vector2i = Vector2i(
		_world.pos_x[_row_in_world(_squads()[0])], _world.pos_y[_row_in_world(_squads()[0])]
	)
	var foe: int = _enemy("rifle_squad", at.x + 2000, at.y)
	_see_all()
	_think(FIRST + 700)
	assert_array(_out).is_empty()
	assert_array([_memory.home_shifted, _memory.goal_keys_of(AiMemory.Owner.ARMY)]).is_equal([1, 1])
	_world.hp[_row_in_world(foe)] = 0
	AiRig.step(_world, _loop)
	_see_all()
	_think(FIRST + 715)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_array([_memory.home_shifted, _memory.goal_keys_of(AiMemory.Owner.ARMY)]).is_equal([0, 0])


func test_a_shift_that_lands_on_the_staging_tile_still_ends_with_the_keys_released() -> void:
	_arm_shift()
	_start()
	# A defence goal (8, 8) whose return was refused: the shift from it lands on (11, 11).
	_memory.squad_goal_x[0] = 8
	_memory.squad_goal_y[0] = 8
	_shift_at(FIRST + 15)
	assert_array(_goal()).is_equal([11, 11])
	_walk_until_idle()
	_see_all()
	_think(FIRST + 700)
	assert_array([_memory.home_shifted, _memory.goal_keys_of(AiMemory.Owner.ARMY)]).is_equal([0, 0])
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(1)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)


func test_a_fresh_unit_walking_to_the_rally_point_does_not_hold_the_probe() -> void:
	_arm_shift()
	_start()
	_shift_at(FIRST + 15)
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_think(FIRST + 30)
	assert_array(_out).is_empty()
	AiRig.step(_world, _loop, [Command.move(1, PackedInt32Array([tank]), 20500, 20500)])
	_walk_until_idle()
	_see_all()
	_think(FIRST + 700)
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array(moves[0].unit_ids).is_equal(PackedInt32Array([_squads()[0], _squads()[1], tank]))
	assert_int(_memory.home_shifted).is_equal(0)


func test_a_range_test_cut_off_by_the_cap_does_not_hold_the_probe() -> void:
	_arm_shift()
	_start()
	_shift_at(FIRST + 15)
	_walk_until_idle()
	var at: Vector2i = Vector2i(
		_world.pos_x[_row_in_world(_squads()[0])], _world.pos_y[_row_in_world(_squads()[0])]
	)
	# The foe has the highest id, so it is the last row of the seen lists: the last test.
	_enemy("rifle_squad", at.x + 2000, at.y)
	_see_all()
	_intel.refresh(_view(), _memory)
	var rows: int = _memory.seen_unit_id.size() + _memory.seen_site_id.size()
	_army.tests_max = rows - 1
	_think(FIRST + 700)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_int(_memory.home_shifted).is_equal(0)
