extends "res://tests/ai/support/intel_suite.gd"
## `AiIntel`'s scout trips (plan row P177b, ADR 0030 section 6): when it goes, where, home when hit,
## lost, the intel slot of the controller and two running matches.


func test_easy_sends_no_scout() -> void:
	_make("easy")
	_scout(8, 12)
	_settle()
	for tick: int in [0, 1800, 9000, 20000]:
		_run(tick)
	assert_array(_out).is_empty()
	assert_array([_intel.scouts, _memory.scout_id]).is_equal([0, -1])


func test_normal_sends_one_scout_at_the_first_tick_first_to_the_mirror_point() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1799)
	assert_array(_out).is_empty()
	_run(1800)
	assert_int(_out.size()).is_equal(1)
	var command: Command = _out[0]
	assert_int(command.type).is_equal(Command.Type.MOVE)
	assert_array(command.unit_ids).is_equal(PackedInt32Array([id]))
	assert_array([command.target_x, command.target_y]).is_equal([32500, 32500])
	assert_array([_intel.scouts, _memory.scout_id, _memory.scout_waypoint]).is_equal([1, id, 0])
	assert_int(_memory.scout_trip_tick).is_equal(1800)
	# One key, the scout's, on the mirror cell as tracked (a vehicle).
	assert_array(_memory.goal_x).is_equal(PackedInt32Array([32]))
	assert_array(_memory.goal_class).is_equal(PackedInt32Array([AiIntel.TRACKED]))
	assert_int(_memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(1)
	assert_int(_memory.commands_left).is_equal(7)
	assert_int(_memory.scout_wanted).is_equal(-1)


func test_the_first_trip_goes_to_the_mirror_point_even_when_a_producer_is_known() -> void:
	AiRig.give(_world, 2, "barracks", 10, 10)
	_scout(8, 12)
	_settle()
	_run(1800)
	assert_int(_out.size()).is_equal(1)
	assert_array([_out[0].target_x, _out[0].target_y]).is_equal([32500, 32500])
	# The estimate is the producer it sees; the sector of the mirror point is the one picked.
	assert_array([_memory.base_x, _memory.base_y]).is_not_equal([MIRROR.x, MIRROR.y])
	assert_int(_memory.scout_picked[_intel.sector_at(MIRROR.x, MIRROR.y)]).is_equal(1800)


func test_a_scout_that_is_out_is_not_sent_again_while_it_travels() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_world.order[_row(id)] = World.Order.MOVE
	_run(1815)
	assert_array(_out).is_empty()
	assert_int(_intel.scouts).is_equal(1)


func test_an_arrived_scout_goes_to_the_nearest_unexplored_sector_and_each_sector_once() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	# The fixed rig: sector centres are 4, 12, 20, 28, 36 on each axis, and the tank at (8, 12)
	# has explored the discs round its tile and the Headquarters. (12, 12) is explored; of the
	# rest, (4, 20) and (12, 20) are nearest, both at a squared distance of 80: a draw settles them.
	for centre: Vector2i in [Vector2i(4, 20), Vector2i(12, 20), Vector2i(20, 12)]:
		assert_bool(_view().is_explored(centre.y * 40 + centre.x)).is_false()
	assert_bool(_view().is_explored(12 * 40 + 12)).is_true()
	_run(1815)
	assert_int(_out.size()).is_equal(1)
	var first: Vector2i = Vector2i(_out[0].target_x / 1000, _out[0].target_y / 1000)
	assert_bool([Vector2i(4, 20), Vector2i(12, 20)].has(first)).is_true()
	assert_int(_intel.draws).is_equal(1)
	assert_int(_memory.scout_waypoint).is_equal(1)
	assert_array([_memory.goal_keys(), _memory.goal_keys_of(AiMemory.Owner.SCOUT)]).is_equal([1, 1])
	assert_array([_memory.goal_x[0], _memory.goal_y[0]]).is_equal([first.x, first.y])
	# It gets there and that sector is explored: the sectors at 64 from it are next, never the
	# mirror sector or the one just done, and the key moves with the scout.
	_arrive(id, first.x, first.y)
	_run(1830)
	assert_int(_out.size()).is_equal(1)
	var second: Vector2i = Vector2i(_out[0].target_x / 1000, _out[0].target_y / 1000)
	var next_to: Dictionary[Vector2i, Array] = {
		Vector2i(4, 20): [Vector2i(12, 20), Vector2i(4, 28)],
		Vector2i(12, 20): [Vector2i(4, 20), Vector2i(12, 28), Vector2i(20, 20)],
	}
	assert_bool(next_to[first].has(second)).is_true()
	assert_array([_memory.goal_keys(), _memory.goal_keys_of(AiMemory.Owner.SCOUT)]).is_equal([1, 1])
	assert_array([_memory.goal_x[0], _memory.goal_y[0]]).is_equal([second.x, second.y])
	assert_int(_intel.scouts).is_equal(1)


func test_a_sector_that_stays_unexplored_is_not_picked_twice_on_a_trip() -> void:
	_scout(8, 12)
	_settle()
	_run(1800)
	var picked: Array[int] = [_intel.sector_at(MIRROR.x, MIRROR.y)]
	for step: int in 5:
		# The scout never gets anywhere (it stays idle where it stands), so nothing is explored.
		_run(1815 + step * 15)
		assert_int(_out.size()).is_equal(1)
		var sector: int = _intel.sector_at(_out[0].target_x / 1000, _out[0].target_y / 1000)
		assert_bool(picked.has(sector)).is_false()
		picked.append(sector)


func test_the_scout_goes_home_when_hit_and_the_trip_ends_when_it_is_there() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_world.order[_row(id)] = World.Order.MOVE
	_world.hp[_row(id)] -= 10
	_run(1815)
	assert_int(_out.size()).is_equal(1)
	assert_array([_out[0].target_x, _out[0].target_y]).is_equal([7500, 7500])
	assert_int(_memory.scout_waypoint).is_equal(-1)
	assert_array(_memory.goal_x).is_equal(PackedInt32Array([7]))
	# On its way home it is neither re-sent nor ended.
	_world.order[_row(id)] = World.Order.MOVE
	_run(1830)
	assert_array(_out).is_empty()
	assert_int(_memory.scout_id).is_equal(id)
	# Home (idle): the trip is over, the key is free, and the unit is nobody's scout.
	_world.order[_row(id)] = World.Order.IDLE
	_run(1845)
	assert_array(_out).is_empty()
	assert_array([_memory.scout_id, _memory.goal_keys()]).is_equal([-1, 0])


func test_a_hit_the_key_rule_refused_is_not_forgotten() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_world.order[_row(id)] = World.Order.MOVE
	_memory.add_goal_key(20, 20, AiIntel.FOOT, AiMemory.Owner.ARMY)
	_memory.add_goal_key(20, 20, AiIntel.TRACKED, AiMemory.Owner.ARMY)
	_world.hp[_row(id)] -= 10
	_run(1815)
	assert_array(_out).is_empty()
	# The army frees a key: the next think sends the scout home, though it lost no more hp.
	_memory.release_goal_key(1, AiMemory.Owner.ARMY)
	_run(1830)
	assert_int(_out.size()).is_equal(1)
	assert_array([_out[0].target_x, _out[0].target_y]).is_equal([7500, 7500])
	assert_int(_memory.scout_waypoint).is_equal(-1)


func test_an_idle_scout_that_cannot_move_on_lets_go_of_its_key() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_memory.add_goal_key(20, 20, AiIntel.FOOT, AiMemory.Owner.ARMY)
	_memory.add_goal_key(20, 20, AiIntel.TRACKED, AiMemory.Owner.ARMY)
	assert_int(_memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(1)
	_run(1815)
	assert_array(_out).is_empty()
	assert_array([_memory.goal_keys(), _memory.goal_keys_of(AiMemory.Owner.SCOUT)]).is_equal([2, 0])
	assert_int(_memory.scout_id).is_equal(id)
	# It still is the scout and goes on once the key rule allows.
	_memory.release_goal_key(0, AiMemory.Owner.ARMY)
	_run(1830)
	assert_int(_out.size()).is_equal(1)


func test_a_lost_scout_ends_the_trip_and_the_next_waits_for_the_interval() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	AiRig.kill(_world, _loop, _row(id))
	_scout(8, 14)
	_settle()
	_run(1900)
	assert_array([_memory.scout_id, _memory.goal_keys()]).is_equal([-1, 0])
	assert_array(_out).is_empty()
	# 2,700 ticks after the first trip began (Normal's interval) and not before.
	_run(1800 + 2699)
	assert_array(_out).is_empty()
	_run(1800 + 2700)
	assert_int(_out.size()).is_equal(1)
	assert_int(_intel.scouts).is_equal(2)
	assert_int(_memory.scout_trip_tick).is_equal(4500)


func test_a_second_trip_starts_with_every_sector_open_again() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_run(1815)
	assert_bool(_memory.scout_picked.has(1815)).is_true()
	AiRig.kill(_world, _loop, _row(id))
	_scout(8, 14)
	_settle()
	_run(1900)
	_run(4500)
	assert_int(_intel.scouts).is_equal(2)
	# Only the mirror sector is closed on the new trip: the first trip's picks are older than it.
	var closed: int = 0
	for tick: int in _memory.scout_picked:
		if tick >= _memory.scout_trip_tick:
			closed += 1
	assert_int(closed).is_equal(1)


func test_a_sector_picked_but_not_reached_on_trip_one_is_open_on_trip_two() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_run(1815)
	assert_int(_intel.draws).is_equal(1)
	AiRig.kill(_world, _loop, _row(id))
	_scout(8, 12)
	_settle()
	_run(1900)
	_run(4500)
	assert_int(_intel.scouts).is_equal(2)
	_run(4515)
	# (4, 20) and (12, 20) are both open again on trip 2, so they tie and a draw settles them.
	assert_int(_out.size()).is_equal(1)
	assert_int(_intel.draws).is_equal(2)


func test_a_scout_with_nothing_left_to_explore_goes_home() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_run(1800)
	_world.fog.explored.fill(1)
	_run(1815)
	assert_int(_out.size()).is_equal(1)
	assert_array([_out[0].target_x, _out[0].target_y]).is_equal([7500, 7500])
	assert_int(_memory.scout_waypoint).is_equal(-1)
	assert_int(_memory.scout_id).is_equal(id)


func test_only_idle_units_of_the_scout_type_are_picked_lowest_id_first() -> void:
	var busy: int = _scout(8, 12)
	var first: int = _scout(8, 14)
	_scout(8, 16)
	_settle()
	_world.order[_row(busy)] = World.Order.MOVE
	_run(1800)
	assert_int(_memory.scout_id).is_equal(first)


# --- through the controller -----------------------------------------------------------------


func test_the_controller_sends_the_scout_from_the_intel_slot_and_counts_it() -> void:
	var ai: OpponentAi = Rig.opponent("fossil", "normal", 1)
	_scout(8, 12)
	_settle()
	var sent: Array[Command] = []
	# Player 1 thinks on ticks 0 (ECONOMY), 5 (ARMY), 10 (INTEL), ...
	_world.tick = 1800
	ai.think(PlayerView.of(_world, 1), sent)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.ECONOMY)
	_world.tick = 1805
	ai.think(PlayerView.of(_world, 1), sent)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.ARMY)
	assert_int(ai.work).is_equal(3)
	assert_int(_moves_in(sent)).is_equal(0)
	_world.tick = 1810
	ai.think(PlayerView.of(_world, 1), sent)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.INTEL)
	assert_int(ai.work).is_equal(3)
	assert_int(_moves_in(sent)).is_equal(1)
	assert_array([ai.scouts, ai.commands_cut]).is_equal([1, 0])
	assert_int(ai.work_max).is_less_equal(3)
	assert_bool(ai.memory.has_base_estimate()).is_true()


func test_easy_through_the_controller_never_scouts_in_a_match() -> void:
	var ai: OpponentAi = Rig.opponent("fossil", "easy", 1)
	_scout(8, 12)
	_settle()
	var sent: Array[Command] = []
	for tick: int in range(0, 4000, 5):
		_world.tick = tick
		ai.think(PlayerView.of(_world, 1), sent)
	assert_int(_moves_in(sent)).is_equal(0)
	assert_int(ai.scouts).is_equal(0)


func test_a_scout_in_a_running_match_walks_the_sectors_and_the_sim_drops_nothing() -> void:
	# Player 2's two rifle squads are gone (its Headquarters stays, so the match goes on and has
	# no weapon), so nothing shoots the scout on its way.
	for id: int in AiRig.ids_of(_world, 2, "rifle_squad"):
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)
	var ai: OpponentAi = _opponent(3)
	_scout(8, 12)
	_settle()
	var moves: Array[Vector2i] = []
	for _tick: int in 1200:
		for command: Command in AiRig.tick(_world, _loop, [ai]):
			if _scout_move(command):
				moves.append(Vector2i(command.target_x / 1000, command.target_y / 1000))
		assert_bool(ai.memory.goal_keys() <= ai.memory.goal_keys_max).is_true()
		assert_bool(ai.memory.goal_keys_of(AiMemory.Owner.SCOUT) <= 1).is_true()
	# The mirror point first, then at least two other sectors, each only once.
	assert_array([moves[0].x, moves[0].y]).is_equal([MIRROR.x, MIRROR.y])
	assert_int(moves.size()).is_greater(2)
	var sectors: Array[int] = []
	for target: Vector2i in moves:
		var sector: int = ai.intel.sector_at(target.x, target.y)
		assert_bool(sectors.has(sector)).is_false()
		sectors.append(sector)
	assert_int(_world.dropped_commands).is_equal(0)
	# One trip in 1,200 ticks. It ends at home with the key released, or is still on its way.
	assert_int(ai.scouts).is_equal(1)
	assert_int(ai.memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(
		0 if ai.memory.scout_id == -1 else 1
	)


func test_a_scout_that_meets_the_enemy_base_comes_home_with_the_estimate() -> void:
	var ai: OpponentAi = _opponent(3)
	var id: int = _scout(8, 12)
	_settle()
	var first: Vector2i = Vector2i(-1, -1)
	for _tick: int in 1500:
		for command: Command in AiRig.tick(_world, _loop, [ai]):
			if first.x < 0 and _scout_move(command):
				first = Vector2i(command.target_x / 1000, command.target_y / 1000)
	# On its way to the mirror point (inside player 2's base) it saw the base and was shot at: the
	# estimate is the enemy producer it saw, and the trip ended at home with its key released.
	assert_array([first.x, first.y]).is_equal([MIRROR.x, MIRROR.y])
	assert_array([ai.memory.base_x, ai.memory.base_y]).is_not_equal([MIRROR.x, MIRROR.y])
	var hq: int = _row_in_world(AiRig.ids_of(_world, 2, "headquarters")[0])
	assert_array([ai.memory.base_x, ai.memory.base_y]).is_equal(
		[_world.pos_x[hq] / 1000, _world.pos_y[hq] / 1000]
	)
	# The army's staging keys stay; the scout's are released.
	assert_array([ai.memory.scout_id, ai.memory.goal_keys_of(AiMemory.Owner.SCOUT)]).is_equal(
		[-1, 0]
	)
	assert_int(_world.dropped_commands).is_equal(0)
	assert_int(_row(id)).is_greater_equal(0)
	assert_int(ai.scouts).is_equal(1)


## A Normal controller for player 1 whose scout may go at tick 0.
func _opponent(seed: int) -> OpponentAi:
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.scout_first_tick = 0
	var stream: DetRandom = DetRandom.create(seed, DetRandom.STREAM_AI_BASE + 1)
	return OpponentAi.create(Rig.def_of("fossil"), level, 1, stream)
