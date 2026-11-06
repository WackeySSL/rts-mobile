extends "res://tests/ai/support/intel_suite.gd"
## `AiIntel`'s scout rules (plan row P177b, ADR 0030 section 4): the goal-key rule and the cap, the
## budget, the draws among equal sectors, and the hand-off to production (`scout_wanted`).

# The hand-off to production: a trip is due and nobody could go.


func test_a_due_trip_with_no_scout_unit_asks_production_for_one_and_sends_nothing() -> void:
	_settle()
	_run(1799)
	assert_int(_memory.scout_wanted).is_equal(-1)
	_run(1800)
	assert_array(_out).is_empty()
	assert_int(_memory.scout_wanted).is_equal(_type("light_tank"))
	assert_int(_intel.scouts).is_equal(0)
	# Once a scout exists the request is gone and the trip starts.
	_scout(8, 12)
	_settle()
	_run(1815)
	assert_int(_memory.scout_wanted).is_equal(-1)
	assert_int(_out.size()).is_equal(1)


func test_no_scout_is_wanted_for_easy_while_one_is_busy_or_while_the_key_rule_refuses() -> void:
	_make("easy")
	_settle()
	_run(9000)
	assert_int(_memory.scout_wanted).is_equal(-1)
	_make("normal")
	var busy: int = _scout(8, 12)
	_settle()
	_world.order[_row(busy)] = World.Order.MOVE
	_run(1800)
	assert_array(_out).is_empty()
	assert_int(_memory.scout_wanted).is_equal(-1)
	_make("normal")
	_memory.add_goal_key(20, 20, AiIntel.FOOT, AiMemory.Owner.ARMY)
	_memory.add_goal_key(20, 20, AiIntel.TRACKED, AiMemory.Owner.ARMY)
	_world.order[_row(busy)] = World.Order.IDLE
	_world.hp[_row(busy)] = 0
	AiRig.step(_world, _loop)
	_run(1900)
	assert_int(_memory.scout_wanted).is_equal(-1)
	# The request waits for the interval too: no second one right after a trip began.
	_make("normal")
	_scout(8, 12)
	_settle()
	_run(1900)
	assert_int(_intel.scouts).is_equal(1)
	AiRig.kill(_world, _loop, _row(_memory.scout_id))
	_run(2000)
	assert_array([_memory.scout_id, _memory.scout_wanted]).is_equal([-1, -1])
	_run(4599)
	assert_int(_memory.scout_wanted).is_equal(-1)
	_run(4600)
	assert_int(_memory.scout_wanted).is_equal(_type("light_tank"))


# The key rule of ADR 0030 section 4.


func test_the_scout_waits_while_the_army_goal_holds_both_classes() -> void:
	_scout(8, 12)
	_settle()
	_memory.add_goal_key(20, 20, AiIntel.FOOT, AiMemory.Owner.ARMY)
	_memory.add_goal_key(20, 20, AiIntel.TRACKED, AiMemory.Owner.ARMY)
	_run(1800)
	assert_array([_out.size(), _intel.scouts, _memory.scout_id]).is_equal([0, 0, -1])
	assert_int(_memory.goal_keys()).is_equal(2)
	# One class only: the scout may go.
	_memory.release_goal_key(0, AiMemory.Owner.ARMY)
	_run(1815)
	assert_array([_out.size(), _intel.scouts]).is_equal([1, 1])
	assert_int(_memory.goal_keys()).is_equal(2)


func test_the_scout_waits_when_its_key_would_pass_the_cap_and_goes_when_one_frees() -> void:
	_scout(8, 12)
	_settle()
	_memory.add_goal_key(1, 1, AiIntel.FOOT, AiMemory.Owner.STAGING)
	_memory.add_goal_key(1, 1, AiIntel.TRACKED, AiMemory.Owner.STAGING)
	_memory.add_goal_key(2, 2, AiIntel.FOOT, AiMemory.Owner.STAGING)
	_memory.add_goal_key(9, 9, AiIntel.FOOT, AiMemory.Owner.ARMY)
	assert_int(_memory.goal_keys()).is_equal(_memory.goal_keys_max)
	_run(1800)
	assert_array([_out.size(), _intel.scouts]).is_equal([0, 0])
	_memory.release_goal_key(2, AiMemory.Owner.STAGING)
	_run(1815)
	assert_array([_out.size(), _intel.scouts]).is_equal([1, 1])
	assert_bool(_memory.goal_keys() <= _memory.goal_keys_max).is_true()


func test_a_key_another_owner_already_holds_is_shared_not_added() -> void:
	_scout(8, 12)
	_settle()
	_memory.add_goal_key(32, 32, AiIntel.TRACKED, AiMemory.Owner.STAGING)
	_run(1800)
	assert_int(_out.size()).is_equal(1)
	assert_int(_memory.goal_keys()).is_equal(1)
	assert_int(_memory.goal_owner[0]).is_equal(
		(1 << AiMemory.Owner.STAGING) | (1 << AiMemory.Owner.SCOUT)
	)
	# When the scout is lost and its trip ends, the staging owner keeps the key.
	AiRig.kill(_world, _loop, _row(_memory.scout_id))
	_run(1815)
	assert_array([_memory.goal_keys(), _memory.goal_owner[0]]).is_equal(
		[1, 1 << AiMemory.Owner.STAGING]
	)


func test_the_scout_sends_nothing_without_budget_and_changes_no_state() -> void:
	_scout(8, 12)
	_settle()
	_run(1800, 0)
	assert_array(_out).is_empty()
	assert_array([_intel.scouts, _memory.scout_id, _memory.goal_keys()]).is_equal([0, -1, 0])
	assert_int(_memory.scout_trip_tick).is_equal(-1)
	_run(1815, 1)
	assert_int(_out.size()).is_equal(1)
	assert_int(_memory.commands_left).is_equal(0)


func test_the_scouts_own_key_does_not_count_against_the_cap_when_it_moves_on() -> void:
	var id: int = _scout(8, 12)
	_settle()
	_memory.add_goal_key(1, 1, AiIntel.FOOT, AiMemory.Owner.STAGING)
	_memory.add_goal_key(1, 1, AiIntel.TRACKED, AiMemory.Owner.STAGING)
	_memory.add_goal_key(9, 9, AiIntel.FOOT, AiMemory.Owner.ARMY)
	_run(1800)
	# Staging 2, army 1 and the scout's: the cap of 4 is full.
	assert_array([_memory.goal_keys(), _memory.goal_keys_of(AiMemory.Owner.SCOUT)]).is_equal([4, 1])
	_arrive(id, 32, 32)
	_run(1815)
	assert_int(_out.size()).is_equal(1)
	assert_array([_memory.goal_keys(), _memory.goal_keys_of(AiMemory.Owner.SCOUT)]).is_equal([4, 1])


func test_a_think_that_cannot_move_the_scout_draws_nothing() -> void:
	var id: int = _scout(20, 20)
	_settle()
	_world.fog.explored.fill(1)
	for centre: Vector2i in [Vector2i(12, 20), Vector2i(28, 20)]:
		_world.fog.explored[centre.y * 40 + centre.x] = 0
	_start_trip(id)
	var state: PackedInt64Array = _rng.state()
	_run(1815, 0)
	assert_array(_out).is_empty()
	assert_int(_intel.draws).is_equal(0)
	assert_array(_rng.state()).is_equal(state)
	_run(1830, 1)
	assert_int(_out.size()).is_equal(1)
	assert_int(_intel.draws).is_equal(1)


# Draws.


func test_a_draw_is_made_only_among_sectors_at_an_equal_distance() -> void:
	# Two unexplored sectors, centres (12, 20) and (28, 20), and the scout midway on (20, 20).
	var id: int = _scout(20, 20)
	_settle()
	_world.fog.explored.fill(1)
	for centre: Vector2i in [Vector2i(12, 20), Vector2i(28, 20)]:
		_world.fog.explored[centre.y * 40 + centre.x] = 0
	_start_trip(id)
	var targets: Dictionary[int, bool] = {}
	for seed: int in range(1, 13):
		_make("normal", -1, seed)
		_start_trip(id)
		_world.tick = 1815
		_out = []
		_memory.commands_left = 8
		_intel.run(_view(), _memory, _rng, _out)
		assert_int(_intel.draws).is_equal(1)
		targets[_out[0].target_x / 1000] = true
	# Both equal sectors are chosen by some seed and nothing else is.
	assert_array(targets.keys()).contains_exactly_in_any_order([12, 28])
	# A unique nearest sector needs no draw and leaves the stream where it was.
	_make("normal")
	_world.fog.explored[20 * 40 + 28] = 1
	_start_trip(id)
	var state: PackedInt64Array = _rng.state()
	_world.tick = 1815
	_memory.commands_left = 8
	_out = []
	_intel.run(_view(), _memory, _rng, _out)
	assert_int(_intel.draws).is_equal(0)
	assert_array(_rng.state()).is_equal(state)
	assert_int(_out[0].target_x / 1000).is_equal(12)


func test_the_same_seed_gives_the_same_trip() -> void:
	var trips: Array[Array] = []
	for _run_of: int in 2:
		_before_trip_world()
		_make("normal", 0, 5)
		var picks: Array[int] = []
		var id: int = _scout(8, 12)
		_settle()
		_run(0)
		for step: int in 8:
			_run(15 + step * 15)
			for command: Command in _out:
				picks.append(command.target_x * 100 + command.target_y)
			_world.order[_row(id)] = World.Order.IDLE
		trips.append(picks)
	assert_array(trips[0]).is_equal(trips[1])
	assert_bool(trips[0].size() > 1).is_true()
