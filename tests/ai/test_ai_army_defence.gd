extends "res://tests/ai/support/army_suite.gd"
## `AiArmy`'s defence (plan row P179, ADR 0030 sections 2, 4 and 6): a threat within
## `defend_radius_tiles` of a building, the level's reaction delay on exact ticks, one Command for a
## still threat, the return to the staging point, the budget and the goal keys at the cap.

## The first ARMY slot of the suites and the slot before the rest (15 ticks apart).
const FIRST: int = 5
## A spot 8 tiles east of the Headquarters (centre (7.5, 7.5)), inside the radius of 12.
const NEAR: Vector2i = Vector2i(15500, 7500)


func test_a_threat_is_answered_only_after_the_reaction_delay_on_exact_ticks() -> void:
	for level: Array in [["easy", 90], ["normal", 30], ["hard", 15]]:
		_before_trip_world()
		_arm(level[0])
		var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
		_settle()
		_see_all()
		var acted: Array[int] = []
		for tick: int in range(FIRST, FIRST + 120, 15):
			_think(tick)
			if not _of(Command.Type.ATTACK_MOVE).is_empty():
				acted.append(tick)
				assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
				var command: Command = _of(Command.Type.ATTACK_MOVE)[0]
				assert_array(command.unit_ids).is_equal(_squads())
				assert_array([command.target_x, command.target_y]).is_equal([NEAR.x, NEAR.y])
				assert_int(command.player_id).is_equal(1)
		# One order, on the first slot at or after first-seen plus the delay.
		assert_array(acted).is_equal([FIRST + level[1]])
		assert_int(_memory.threat_first_tick).is_equal(FIRST)
		assert_int(_view().row_of(foe)).is_greater_equal(0)


func test_a_threat_that_leaves_before_the_delay_is_forgotten_and_the_delay_starts_again() -> void:
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(FIRST)
	assert_int(_memory.threat_first_tick).is_equal(FIRST)
	_put(foe, 30500, 30500)
	_think(FIRST + 15)
	assert_int(_memory.threat_first_tick).is_equal(-1)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_put(foe, NEAR.x, NEAR.y)
	_think(FIRST + 30)
	assert_int(_memory.threat_first_tick).is_equal(FIRST + 30)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(FIRST + 45)
	assert_array(_of(Command.Type.ATTACK_MOVE)).is_empty()
	_think(FIRST + 60)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)


func test_a_still_threat_costs_one_command_and_a_moved_one_costs_one_more() -> void:
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(FIRST)
	_think(FIRST + 15)
	_think(FIRST + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_army.defences).is_equal(1)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([15, 7])
	for tick: int in [45, 60, 75]:
		_think(FIRST + tick)
		assert_array(_out).is_empty()
	# Within the same tile: still one goal, no Command.
	_put(foe, 15900, 7100)
	_think(FIRST + 90)
	assert_array(_out).is_empty()
	# To another tile: the squads are sent again, once, to the new position.
	_put(foe, 16500, 8500)
	_think(FIRST + 105)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([16500, 8500])
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([16, 8])
	assert_int(_army.defences).is_equal(2)


func test_the_radius_is_from_the_centre_of_any_own_building_and_the_edge_counts() -> void:
	# Exactly 12 tiles from the Headquarters' centre: a threat. A milli-tile farther: not one.
	var foe: int = _enemy("heavy_tank", 19500, 7500)
	_settle()
	_see_all()
	_think(FIRST)
	assert_int(_memory.threat_first_tick).is_equal(FIRST)
	_put(foe, 19501, 7500)
	_think(FIRST + 15)
	assert_int(_memory.threat_first_tick).is_equal(-1)
	# A building far from the Headquarters has its own radius.
	var barracks: int = AiRig.give(_world, 1, "barracks", 30, 6)
	_settle()
	var centre: Vector2i = _view().row_pos(_view().row_of(barracks))
	_put(foe, centre.x, centre.y + 12000)
	_see_all()
	_think(FIRST + 30)
	assert_int(_memory.threat_first_tick).is_equal(FIRST + 30)


func test_only_seen_enemy_combat_units_are_threats() -> void:
	# A harvester, a building and a fogged tank, all within the radius: no threat.
	_enemy("harvester", NEAR.x, NEAR.y)
	AiRig.give(_world, 2, "barracks", 14, 6)
	var hidden: int = _enemy("heavy_tank", 17500, 9500)
	_settle()
	_world.fog.visible.fill(0)
	_think(FIRST)
	assert_int(_view().row_of(hidden)).is_less(0)
	assert_int(_memory.threat_first_tick).is_equal(-1)
	_see_all()
	# Seen now: the harvester and the building still are not, the tank is.
	_think(FIRST + 15)
	assert_int(_memory.threat_first_tick).is_equal(FIRST + 15)
	assert_array(_memory.seen_unit_id).contains([hidden])
	_think(FIRST + 45)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([17500, 9500])


func test_the_most_pressing_threat_is_the_nearest_and_ties_go_to_the_lower_id() -> void:
	var far: int = _enemy("heavy_tank", 17500, 7500)
	var near: int = _enemy("heavy_tank", 13500, 7500)
	_settle()
	_see_all()
	_think(FIRST)
	_think(FIRST + 30)
	assert_array([_out[0].target_x, _out[0].target_y]).is_equal([13500, 7500])
	assert_int(far).is_less(near)
	# Equal distance (north and south of the Headquarters' row): the lower id's position.
	_arm("normal")
	_put(far, 11500, 3500)
	_put(near, 11500, 11500)
	_think(FIRST)
	_think(FIRST + 30)
	assert_array([_out[0].target_x, _out[0].target_y]).is_equal([11500, 3500])


func test_a_unit_that_joins_during_a_defence_gets_the_order_and_the_squad_does_not() -> void:
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [0, 15, 30]:
		_think(FIRST + tick)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_think(FIRST + 45)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([NEAR.x, NEAR.y])
	_think(FIRST + 60)
	assert_array(_out).is_empty()


func test_the_squads_go_back_to_the_staging_point_once_when_the_threat_is_gone() -> void:
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [0, 15, 30]:
		_think(FIRST + tick)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_greater(0)
	_world.hp[_row_in_world(foe)] = 0
	AiRig.step(_world, _loop)
	_think(FIRST + 45)
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array(moves[0].unit_ids).is_equal(_squads())
	assert_array([moves[0].target_x, moves[0].target_y]).is_equal([11500, 11500])
	assert_int(_memory.threat_first_tick).is_equal(-1)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([11, 11])
	assert_int(_army.returns).is_equal(1)
	# The army goal's keys are released; the staging point's stay.
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(0)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(1)
	_think(FIRST + 60)
	assert_array(_out).is_empty()


func test_a_defence_the_budget_cannot_pay_changes_nothing_and_is_asked_again() -> void:
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(FIRST)
	_think(FIRST + 15)
	var keys: int = _memory.goal_keys()
	_think(FIRST + 30, 0)
	assert_array(_out).is_empty()
	assert_int(_memory.commands_left).is_equal(0)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([-1, -1])
	assert_int(_memory.goal_keys()).is_equal(keys)
	assert_int(_army.defences).is_equal(0)
	_think(FIRST + 45)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.commands_left).is_equal(7)


func test_the_army_goal_is_one_cell_with_a_key_per_class() -> void:
	AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	var foe: int = _enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [0, 15, 30]:
		_think(FIRST + tick)
	# Infantry and a tank: foot and tracked, both on the threat's cell, owner ARMY.
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	var classes: Array[int] = []
	for at: int in _memory.goal_keys():
		if _memory.goal_owner[at] & (1 << AiMemory.Owner.ARMY) != 0:
			assert_array([_memory.goal_x[at], _memory.goal_y[at]]).is_equal([15, 7])
			classes.append(_memory.goal_class[at])
	assert_array(classes).contains_exactly_in_any_order([AiIntel.FOOT, AiIntel.TRACKED])
	# A new goal replaces the cell: the old keys are gone, never added to.
	_put(foe, 16500, 9500)
	_think(FIRST + 45)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	for at: int in _memory.goal_keys():
		if _memory.goal_owner[at] & (1 << AiMemory.Owner.ARMY) != 0:
			assert_array([_memory.goal_x[at], _memory.goal_y[at]]).is_equal([16, 9])


func test_the_army_has_precedence_over_the_scout_which_yields_at_the_cap() -> void:
	# Staging holds foot and tracked (two keys) and the scout one: three of four. A mixed defence
	# needs two more: the scout's key goes, the army and the staging point keep theirs.
	AiRig.give(_world, 1, "barracks", 12, 6)
	AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(FIRST)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(2)
	assert_bool(_memory.add_goal_key(30, 30, AiIntel.TRACKED, AiMemory.Owner.SCOUT)).is_true()
	assert_int(_memory.goal_keys()).is_equal(3)
	_think(FIRST + 15)
	_think(FIRST + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(0)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.ARMY)).is_equal(2)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.STAGING)).is_equal(2)
	assert_int(_memory.goal_keys()).is_equal(_memory.goal_keys_max)


func test_the_scout_keeps_its_key_when_there_is_room_for_the_army() -> void:
	# Staging two keys, the scout one, the army one (infantry only): four, nobody yields.
	AiRig.give(_world, 1, "barracks", 12, 6)
	AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(FIRST)
	assert_bool(_memory.add_goal_key(30, 30, AiIntel.TRACKED, AiMemory.Owner.SCOUT)).is_true()
	_think(FIRST + 15)
	_think(FIRST + 30)
	assert_int(_of(Command.Type.ATTACK_MOVE).size()).is_equal(1)
	(
		assert_array(
			[
				_memory.goal_keys_of(AiMemory.Owner.SCOUT),
				_memory.goal_keys_of(AiMemory.Owner.ARMY),
				_memory.goal_keys()
			]
		)
		. is_equal([1, 1, 4])
	)


func test_an_order_the_keys_cannot_hold_even_with_the_scout_gone_is_refused_whole() -> void:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.goal_keys_max = 1
	_memory = AiMemory.create(def)
	_army = AiArmy.create(def, Rig.level_of("normal"), 1)
	AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	_think(FIRST)
	_think(FIRST + 15)
	assert_array(_out).is_empty()
	# The defence needs two keys (foot, tracked) and the cap is one: refused, nothing changed.
	_think(FIRST + 30)
	assert_array(_out).is_empty()
	assert_int(_memory.goal_keys()).is_equal(0)
	assert_int(_memory.commands_left).is_equal(8)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([-1, -1])
	assert_int(_army.starved).is_equal(1)
	_think(FIRST + 45)
	assert_array(_out).is_empty()
	assert_int(_army.starved).is_equal(2)
	assert_int(_memory.goal_keys()).is_less_equal(1)
