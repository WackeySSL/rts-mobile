extends "res://tests/ai/support/intel_suite.gd"
## The close-out search (plan row P250c): with no enemy producer seen or remembered and the mirror
## estimate explored, the base estimate names the nearest unexplored sector of the enemy half; a
## producer that is seen gone leaves the memory; off (0) and the frozen copies keep the mirror.


func _explore_mirror() -> void:
	_world.fog.explored[MIRROR.y * 40 + MIRROR.x] = 1


func _base() -> Vector2i:
	return Vector2i(_memory.base_x, _memory.base_y)


func test_a_search_goal_is_picked_when_no_producer_is_known() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	var goal: Vector2i = _base()
	assert_bool(goal != MIRROR).is_true()
	assert_int(_intel.sweep.picks).is_equal(1)
	# An unexplored centre, on the enemy side, and the nearest such one to the mirror.
	var view: PlayerView = _view()
	assert_bool(view.is_explored(goal.y * 40 + goal.x)).is_false()
	assert_bool(AiIntel._distance(goal, MIRROR) < AiIntel._distance(goal, Vector2i(7, 7))).is_true()
	for sector: int in _intel.sector_count():
		var centre: Vector2i = AiSweep._centre(view, sector, 8, _intel.sector_cols)
		if view.is_explored(centre.y * 40 + centre.x):
			continue
		if AiIntel._distance(centre, MIRROR) >= AiIntel._distance(centre, Vector2i(7, 7)):
			continue
		assert_bool(AiIntel._distance(goal, MIRROR) <= AiIntel._distance(centre, MIRROR)).is_true()


func test_the_goal_stays_until_explored_then_the_next_is_picked() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	var first: Vector2i = _base()
	_run(40)
	assert_array([_base()]).is_equal([first])
	assert_int(_intel.sweep.picks).is_equal(1)
	_world.fog.explored[first.y * 40 + first.x] = 1
	_run(70)
	assert_bool(_base() != first).is_true()
	assert_int(_intel.sweep.picks).is_equal(2)


func test_an_unreached_goal_is_given_up_after_the_hold_and_never_again() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	var first: Vector2i = _base()
	_run(10 + _intel.sweep.hold_ticks - 1)
	assert_array([_base()]).is_equal([first])
	_run(10 + _intel.sweep.hold_ticks)
	assert_bool(_base() != first).is_true()
	assert_int(_memory.sweep_skipped[_sector_of(first)]).is_equal(1)


func _sector_of(tile: Vector2i) -> int:
	return _intel.sector_at(tile.x, tile.y)


func test_a_producer_that_is_seen_gone_leaves_the_memory() -> void:
	var id: int = AiRig.give(_world, 2, "barracks", 10, 10)
	# An own unit beside it sees it fall.
	AiRig.add_unit_of(_world, 1, "rifle_squad", 12500, 10500)
	_settle()
	_world.tick = 3
	LastSeen.run(_world)
	assert_int(_view().ghost_count).is_equal(1)
	_run(30)
	assert_bool(_base() != MIRROR).is_true()
	# The player watches it fall: the record goes with it, and the estimate is no longer its tile.
	AiRig.kill(_world, _loop, _row_in_world(id))
	_settle()
	assert_int(_view().ghost_count).is_equal(0)
	_run(60)
	assert_bool(_base() == Vector2i(10, 10)).is_false()
	assert_bool(_base() != Vector2i(9, 9)).is_true()


func test_the_search_uses_only_view_data() -> void:
	# The enemy base is hidden and unexplored but for the mirror point: the goal never names it.
	_settle()
	_explore_mirror()
	_run(10)
	var enemy: Vector2i = Vector2i(MIRROR.x, MIRROR.y)
	for row: int in _world.unit_count():
		if _world.owner[row] == 2:
			enemy = Vector2i(_world.pos_x[row] / 1000, _world.pos_y[row] / 1000)
	# The goal is a function of the explored cells and the own Headquarters alone: hiding or moving
	# the hidden enemy rows changes nothing.
	var goal: Vector2i = _base()
	for row: int in _world.unit_count():
		if _world.owner[row] == 2:
			_world.pos_x[row] = 500
			_world.pos_y[row] = 39500
	_make("normal")
	_settle()
	_run(10)
	assert_array([_base()]).is_equal([goal])
	assert_bool(enemy.x >= 0).is_true()


func test_off_keeps_the_mirror_estimate() -> void:
	_make("easy")
	_settle()
	_explore_mirror()
	_run(10)
	assert_array([_base()]).is_equal([MIRROR])
	assert_int(_intel.sweep.picks).is_equal(0)
	_make("normal")
	_intel.sweep.hold_ticks = 0
	_run(20)
	assert_array([_base()]).is_equal([MIRROR])


func test_the_mirror_stays_while_it_is_unexplored() -> void:
	_settle()
	_run(10)
	assert_array([_base()]).is_equal([MIRROR])
	assert_int(_intel.sweep.picks).is_equal(0)


func test_the_levels_and_the_frozen_copies() -> void:
	assert_int(Rig.level_of("easy").sweep_hold_ticks).is_equal(0)
	assert_int(Rig.level_of("normal").sweep_hold_ticks).is_greater(0)
	assert_int(Rig.level_of("hard").sweep_hold_ticks).is_greater(0)
	for level: String in ["easy", "normal", "hard"]:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_int(copy.sweep_hold_ticks).is_equal(0)
