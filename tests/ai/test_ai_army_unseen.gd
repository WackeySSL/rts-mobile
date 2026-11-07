extends "res://tests/ai/support/army_suite.gd"
## `AiArmy`'s response to a hit by the unseen (plan row P179b, ADR 0030 section 4): a unit that lost
## hp since the last think with no seen enemy in its weapon range moves its squad's goal
## `unseen_hit_shift_tiles` toward the base estimate, as an army order under the goal-key rules.
## The suite's def has no defence radius (a seen enemy in range is not a threat here, so the range
## test is what the cases pin) and a shift of 4 tiles. From the staging point (11, 11) toward the
## point mirror (32, 32) the first shift lands on (14, 14), the second on (17, 17).

const SHIFT: int = 4
## The first ARMY slot of the suite (15 ticks apart), and a spot 8 tiles east of the Headquarters.
const FIRST: int = 5
const NEAR: Vector2i = Vector2i(15500, 7500)


## The suite's managers: the shift above, no defence radius, `keys` goal keys, `tests` per slot.
func _arm_shift(keys: int = KEYS, tests: int = 512) -> void:
	var def: OpponentDef = _def()
	def.defend_radius_tiles = 0
	def.unseen_hit_shift_tiles = SHIFT
	def.goal_keys_max = keys
	def.target_tests_max = tests
	_arm("normal", def)


## Settles the World, sees everything and takes the first slot, which sends the squads to the
## staging point and records every unit's hp.
func _start() -> void:
	_settle()
	_see_all()
	_think(FIRST)


## Takes `amount` hp off the unit `id` (any owner).
func _hurt(id: int, amount: int = 1) -> void:
	_world.hp[_row_in_world(id)] -= amount


## The goal of squad `squad`, in tiles.
func _goal(squad: int = 0) -> Array[int]:
	return [_memory.squad_goal_x[squad], _memory.squad_goal_y[squad]]


## The weapon range of the own unit `id` in milli-tiles, from the view.
func _reach(id: int) -> int:
	return _view().type_range[_view().row_type(_view().row_of(id))]


## An enemy heavy tank `gap` milli-tiles east of the own unit `id`.
func _east_of(id: int, gap: int) -> int:
	var at: Vector2i = _view().row_pos(_view().row_of(id))
	return _enemy("heavy_tank", at.x + gap, at.y)


func test_a_hit_with_no_enemy_in_sight_moves_the_squad_goal_toward_the_base_estimate() -> void:
	_arm_shift()
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(_out.size()).is_equal(1)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(_squads())
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([14500, 14500])
	assert_int(sent[0].player_id).is_equal(1)
	assert_array(_goal()).is_equal([14, 14])
	assert_array([_army.shifts, _memory.squad_shifted[0], _memory.commands_left]).is_equal(
		[1, 1, 7]
	)


func test_the_shifted_goal_holds_one_army_key_and_the_staging_key_stays() -> void:
	_arm_shift()
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(1)
	for at: int in _memory.goal_keys():
		if _memory.goal_owner[at] & (1 << AiMemory.Owner.ARMY) != 0:
			assert_array([_memory.goal_x[at], _memory.goal_y[at]]).is_equal([14, 14])
			assert_int(_memory.goal_class[at]).is_equal(AiMemory.FOOT)


func test_nothing_is_sent_without_a_loss_and_the_return_leaves_a_shifted_goal_alone() -> void:
	_arm_shift()
	_start()
	_think(FIRST + 15)
	assert_array(_out).is_empty()
	_hurt(_squads()[0])
	_think(FIRST + 30)
	assert_int(_army.shifts).is_equal(1)
	# The same hp next slots: no second shift and no MOVE back to the staging point.
	for tick: int in [45, 60, 75]:
		_think(FIRST + tick)
		assert_array(_out).is_empty()
	assert_array(_goal()).is_equal([14, 14])
	assert_int(_army.returns).is_equal(1)


func test_every_loss_shifts_again_and_the_shift_ends_on_the_base_estimate() -> void:
	_arm_shift()
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	_hurt(_squads()[0])
	_think(FIRST + 30)
	assert_array(_goal()).is_equal([17, 17])
	# A known base estimate 2 tiles from the goal: the goal goes to it, not past it.
	_memory.base_x = 18
	_memory.base_y = 19
	_hurt(_squads()[1])
	_think(FIRST + 45)
	assert_array(_goal()).is_equal([18, 19])
	assert_array([_of(Command.Type.ATTACK_MOVE)[0].target_x, _out[0].target_y]).is_equal(
		[18500, 19500]
	)
	# On the estimate there is nothing to shift to: the loss is read and no Command is sent.
	_hurt(_squads()[1])
	_think(FIRST + 60)
	assert_array(_out).is_empty()
	assert_int(_army.shifts).is_equal(3)


func test_a_known_base_estimate_sets_the_direction() -> void:
	_arm_shift()
	_memory.base_x = 11
	_memory.base_y = 31
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	# The staging point moves with the estimate: (8, 13) (6 tiles from (7, 7) toward (11, 31)), and
	# the shift goes 4 tiles on, along (3, 18): to (9, 17).
	assert_array(_goal()).is_equal([9, 17])


func test_a_seen_enemy_unit_in_weapon_range_is_not_an_unseen_hit() -> void:
	_arm_shift()
	var squad: int = _squads()[0]
	var foe: int = _east_of(squad, _reach(squad))
	_start()
	_hurt(squad)
	_think(FIRST + 15)
	assert_array(_out).is_empty()
	assert_int(_memory.seen_unit_id.find(foe)).is_greater_equal(0)
	assert_int(_army.shifts).is_equal(0)


func test_one_milli_tile_beyond_the_weapon_range_it_is() -> void:
	_arm_shift()
	var squad: int = _squads()[0]
	_east_of(squad, _reach(squad) + 1)
	_start()
	_hurt(squad)
	_think(FIRST + 15)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_array(_goal()).is_equal([14, 14])


func test_a_seen_enemy_building_in_weapon_range_covers_the_hit_and_a_fogged_unit_does_not() -> void:
	_arm_shift()
	var squad: int = _squads()[0]
	var building: int = AiRig.give(_world, 2, "barracks", 30, 30)
	_settle()
	var at: Vector2i = _view().row_pos(_view().row_of(squad))
	_put(building, at.x + _reach(squad), at.y)
	_see_all()
	_think(FIRST)
	assert_int(_memory.seen_site_id.find(building)).is_greater_equal(0)
	_hurt(squad)
	_think(FIRST + 15)
	assert_array(_out).is_empty()
	# The building beyond the range, and a tank in range that the fog hides: an unseen hit.
	_put(building, at.x + _reach(squad) + 1, at.y)
	_east_of(squad, 0)
	_world.fog.visible.fill(0)
	_hurt(squad)
	_think(FIRST + 30)
	assert_int(_view().row_of(_east_of(squad, 0))).is_less(0)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_the_test_cap_counts_a_unit_it_cannot_finish_as_covered() -> void:
	# Every seen enemy row is out of range: a hit unit is tested against all of them.
	_arm_shift()
	_start()
	var rows: int = _memory.seen_unit_id.size() + _memory.seen_site_id.size()
	assert_int(rows).is_greater(1)
	_arm_shift(KEYS, rows - 1)
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_array(_out).is_empty()
	assert_int(_army.hit_tests).is_equal(rows - 1)
	assert_int(_army.shifts).is_equal(0)
	# With one test more the unit is tested against every row: an unseen hit.
	_arm_shift(KEYS, rows)
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_int(_army.hit_tests).is_equal(rows)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_a_unit_that_joins_hurt_is_no_hit_until_its_hp_is_on_record() -> void:
	_arm_shift()
	_start()
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_hurt(tank, 5)
	_think(FIRST + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	assert_int(_army.shifts).is_equal(0)
	# Its hp is on record now: a loss of the new unit is a hit, and the squad is the home squad.
	_hurt(tank)
	_think(FIRST + 30)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([_squads()[0], _squads()[1], tank]))


func test_a_standing_threat_keeps_the_squad_on_it_and_its_losses_are_not_unseen_hits() -> void:
	var def: OpponentDef = _def()
	def.unseen_hit_shift_tiles = SHIFT
	_arm("normal", def)
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [0, 15, 30]:
		_think(FIRST + tick)
	assert_array(_goal()).is_equal([15, 7])
	_hurt(_squads()[0])
	_think(FIRST + 45)
	assert_array(_out).is_empty()
	assert_array(_goal()).is_equal([15, 7])
	# The foe dies: the loss was recorded under the threat, so it is not found afterwards.
	_world.hp[_row_in_world(foe)] = 0
	AiRig.step(_world, _loop)
	_think(FIRST + 60)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_int(_army.shifts).is_equal(0)
	# A loss after that slot, with nothing in sight, is an unseen hit again.
	_think(FIRST + 75)
	_hurt(_squads()[0])
	_think(FIRST + 90)
	assert_int(_army.shifts).is_equal(1)
	assert_array(_goal()).is_equal([14, 14])


func test_a_defence_replaces_a_shifted_goal_and_the_squads_then_go_back() -> void:
	var def: OpponentDef = _def()
	def.unseen_hit_shift_tiles = SHIFT
	_arm("normal", def)
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_array(_goal()).is_equal([14, 14])
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_see_all()
	for tick: int in [30, 45, 60]:
		_think(FIRST + tick)
	assert_array(_goal()).is_equal([15, 7])
	assert_int(_memory.squad_shifted[0]).is_equal(0)
	_world.hp[_row_in_world(foe)] = 0
	AiRig.step(_world, _loop)
	_think(FIRST + 75)
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array([moves[0].target_x, moves[0].target_y]).is_equal([11500, 11500])
	assert_array(_goal()).is_equal([11, 11])


func test_a_shift_the_budget_cannot_pay_changes_nothing_and_the_hit_is_found_again() -> void:
	_arm_shift()
	_start()
	_hurt(_squads()[0])
	var keys: int = _memory.goal_keys()
	_think(FIRST + 15, 0)
	assert_array(_out).is_empty()
	assert_array(_goal()).is_equal([11, 11])
	assert_array([_memory.goal_keys(), _memory.squad_shifted[0], _army.shifts]).is_equal(
		[keys, 0, 0]
	)
	_think(FIRST + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_array(_goal()).is_equal([14, 14])
	# Sent once: the hp is on record now.
	_think(FIRST + 45)
	assert_array(_out).is_empty()


func test_a_shift_the_keys_cannot_hold_is_refused_whole_and_counted() -> void:
	# One key, held by the staging point: the army has no room and nothing to take from the scout.
	_arm_shift(1)
	_start()
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_array(_out).is_empty()
	assert_array(_goal()).is_equal([11, 11])
	assert_int(_memory.goal_keys()).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(1)
	assert_array([_army.starved, _memory.commands_left, _memory.squad_shifted[0]]).is_equal(
		[1, 8, 0]
	)
	_think(FIRST + 30)
	assert_int(_army.starved).is_equal(2)


func test_the_scout_yields_its_key_to_the_shift_at_the_cap() -> void:
	_arm_shift(2)
	_start()
	assert_bool(_memory.add_goal_key(30, 30, AiIntel.TRACKED, AiMemory.Owner.SCOUT)).is_true()
	assert_int(_memory.goal_keys()).is_equal(2)
	_hurt(_squads()[0])
	_think(FIRST + 15)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(0)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(1)


func test_the_shift_works_on_any_squad_index_and_leaves_the_others_alone() -> void:
	_arm_shift()
	_start()
	var ids: PackedInt32Array = _squads()
	# The second rifle squad is squad 1, with its own goal.
	_memory.member_squad[1] = 1
	_memory.squad_role[1] = 0
	_memory.squad_goal_x[1] = 20
	_memory.squad_goal_y[1] = 8
	_hurt(ids[1])
	_think(FIRST + 15)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([ids[1]]))
	# From (20, 8) toward (32, 32): along (12, 24), length 26 -> (2, 4) by rounding to the nearest.
	assert_array(_goal(1)).is_equal([22, 12])
	assert_array(_goal(0)).is_equal([11, 11])
	assert_array([_memory.squad_shifted[0], _memory.squad_shifted[1]]).is_equal([0, 1])


func test_two_hit_squads_shift_one_a_think_the_lowest_first() -> void:
	_arm_shift()
	_start()
	var ids: PackedInt32Array = _squads()
	_memory.member_squad[1] = 1
	_memory.squad_role[1] = 0
	_memory.squad_goal_x[1] = 20
	_memory.squad_goal_y[1] = 8
	_hurt(ids[0])
	_hurt(ids[1])
	_think(FIRST + 15)
	assert_array(_of(Command.Type.ATTACK_MOVE)[0].unit_ids).is_equal(PackedInt32Array([ids[0]]))
	assert_array([_goal(0), _goal(1)]).is_equal([[14, 14], [20, 8]])
	# Squad 1's loss is still on record as unhandled; squad 0's is not found again.
	_think(FIRST + 30)
	assert_array(_of(Command.Type.ATTACK_MOVE)[0].unit_ids).is_equal(PackedInt32Array([ids[1]]))
	assert_array([_goal(0), _goal(1)]).is_equal([[14, 14], [22, 12]])
	_think(FIRST + 45)
	assert_array(_out).is_empty()


func test_refresh_lists_the_own_units_hp_beside_their_ids_and_the_seen_buildings() -> void:
	_arm_shift()
	var building: int = AiRig.give(_world, 2, "barracks", 30, 30)
	var tanker: int = _enemy("harvester", 20500, 20500)
	_settle()
	_see_all()
	_hurt(_squads()[1], 3)
	_intel.refresh(_view(), _memory)
	assert_int(_intel.passes).is_equal(2)
	assert_array(_memory.unit_id).is_equal(_squads())
	var expect: Array[int] = []
	for id: int in _squads():
		expect.append(_world.hp[_row_in_world(id)])
	assert_array(_memory.unit_hp).is_equal(expect)
	# The seen enemy buildings (its base and the new one), no unit.
	assert_int(_memory.seen_site_id.find(building)).is_greater_equal(0)
	assert_int(_memory.seen_site_id.find(tanker)).is_less(0)
	for id: int in _memory.seen_unit_id:
		assert_int(_memory.seen_site_id.find(id)).is_less(0)
	for id: int in _memory.seen_site_id:
		assert_int(_view().type_foot_w[_view().row_type(_view().row_of(id))]).is_greater(0)
