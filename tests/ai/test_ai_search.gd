extends "res://tests/ai/support/intel_suite.gd"
## The close-out search (plan row P250c): with no enemy producer seen or remembered and the mirror
## estimate explored, the base estimate names the nearest unexplored sector of the enemy half; a
## producer that is seen gone leaves the memory; off (0) and the frozen copies keep the mirror.
## The rig's map is 40 x 40 tiles in sectors of 8 (5 x 5), player 1's Headquarters on tile (7, 7).

const HOME: Vector2i = Vector2i(7, 7)


func _explore_mirror() -> void:
	_world.fog.explored[MIRROR.y * 40 + MIRROR.x] = 1


func _base() -> Vector2i:
	return Vector2i(_memory.base_x, _memory.base_y)


func _sector_of(tile: Vector2i) -> int:
	return _intel.sector_at(tile.x, tile.y)


## The wave squad is out (marching), as `AiArmy` leaves it.
func _march() -> void:
	_memory.squad_role[AiArmy.WAVE] = AiArmy.ROLE_WAVE
	_memory.squad_state[AiArmy.WAVE] = AiMemory.SquadState.WAVE


func test_a_search_goal_is_picked_when_no_producer_is_known() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	# The sector (4, 4) holds the mirror point and its centre (36, 36) is unexplored: the nearest.
	assert_array([_base()]).is_equal([Vector2i(36, 36)])
	assert_int(_intel.search.picks).is_equal(1)
	assert_bool(_view().is_explored(36 * 40 + 36)).is_false()


func test_the_nearest_tie_goes_to_the_same_offset_for_both_seats() -> void:
	_settle()
	_explore_mirror()
	# The mirror sector's centre is explored: its three neighbours at an equal distance tie.
	_world.fog.explored[36 * 40 + 36] = 1
	_run(10)
	var first: int = _sector_of(_base())
	# Player 2 with its Headquarters on the point mirror of player 1's, in the same situation, picks
	# the mirrored sector.
	var hq: int = _type("headquarters")
	var mine: int = -1
	var theirs: int = -1
	for row: int in _world.unit_count():
		if _world.type_index[row] == hq:
			if _world.owner[row] == 1:
				mine = row
			elif _world.owner[row] == 2:
				theirs = row
	_world.pos_x[theirs] = 40000 - _world.pos_x[mine]
	_world.pos_y[theirs] = 40000 - _world.pos_y[mine]
	var def: OpponentDef = Rig.def_of("fossil")
	var intel2: AiIntel = AiIntel.create(def, Rig.level_of("normal"), 2)
	var memory2: AiMemory = AiMemory.create(def)
	var cells: int = 40 * 40
	_world.fog.explored[cells + HOME.y * 40 + HOME.x] = 1
	_world.fog.explored[cells + 4 * 40 + 4] = 1
	_memory.commands_left = 8
	memory2.commands_left = 8
	var out2: Array[Command] = []
	intel2.run(PlayerView.of(_world, 2), memory2, _rng, out2)
	var second: int = intel2.sector_at(memory2.base_x, memory2.base_y)
	assert_int(first + second).is_equal(24)
	assert_bool(first != second).is_true()


func test_the_goal_stays_until_explored_then_the_next_is_picked() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	var first: Vector2i = _base()
	_run(40)
	assert_array([_base()]).is_equal([first])
	assert_int(_intel.search.picks).is_equal(1)
	_world.fog.explored[first.y * 40 + first.x] = 1
	_run(70)
	assert_bool(_base() != first).is_true()
	assert_int(_intel.search.picks).is_equal(2)


func test_the_hold_runs_only_while_the_wave_marches() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	var first: Vector2i = _base()
	var hold: int = _intel.search.hold_ticks
	# No wave out: any time passes and the goal is kept.
	_run(10 + hold + 500)
	assert_array([_base()]).is_equal([first])
	# The wave marches: the hold counts from here, and the goal goes when it has run out.
	_march()
	_run(20 + hold + 500)
	assert_array([_base()]).is_equal([first])
	_run(20 + hold + 500 + hold - 11)
	assert_array([_base()]).is_equal([first])
	_run(20 + hold + 500 + hold - 10)
	assert_bool(_base() != first).is_true()
	assert_int(_memory.search_skipped[_sector_of(first)]).is_equal(1)


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
	AiRig.kill(_world, _loop, _row_in_world(id))
	_settle()
	assert_int(_view().ghost_count).is_equal(0)
	# The record is gone and the mirror is still unexplored: the estimate is the mirror again.
	_run(60)
	assert_array([_base()]).is_equal([MIRROR])


func test_a_known_producer_resets_the_goal_and_the_hold() -> void:
	var id: int = AiRig.give(_world, 2, "barracks", 10, 10)
	AiRig.add_unit_of(_world, 1, "rifle_squad", 12500, 10500)
	_settle()
	_explore_mirror()
	_march()
	_world.tick = 3
	LastSeen.run(_world)
	# The barracks is a seen producer: the estimate is its tile and no search goal stands.
	_run(10)
	assert_int(_memory.search_sector).is_equal(AiMemory.NONE)
	AiRig.kill(_world, _loop, _row_in_world(id))
	_settle()
	assert_int(_view().ghost_count).is_equal(0)
	_run(20)
	var goal: Vector2i = _base()
	var sector: int = _sector_of(goal)
	assert_int(_intel.search.picks).is_equal(1)
	# A producer is seen again and stays known for longer than the hold: the old goal is no longer
	# held, so when it is gone the same sector is picked afresh and was never given up.
	var again: int = AiRig.give(_world, 2, "barracks", 10, 10)
	_settle()
	_world.tick = 25
	LastSeen.run(_world)
	_run(30)
	assert_bool(again > 0 and _base() != goal).is_true()
	_run(30 + _intel.search.hold_ticks + 50)
	AiRig.kill(_world, _loop, _row_in_world(again))
	_settle()
	_run(40 + _intel.search.hold_ticks + 200)
	assert_array([_base()]).is_equal([goal])
	assert_int(_memory.search_skipped[sector]).is_equal(0)


func test_the_goal_is_in_the_enemy_half_only() -> void:
	_settle()
	# A first run sizes the sector grid (the mirror is still unexplored, so nothing is picked).
	_run(5)
	_explore_mirror()
	# Every sector centre on the enemy side (x + y of the centre tile from 39 up) is explored; those
	# of the own half, such as (4, 28), are not.
	for sector: int in _intel.sector_count():
		var centre: Vector2i = _intel.centre_of(_view(), sector)
		if centre.x + centre.y >= 39:
			_world.fog.explored[centre.y * 40 + centre.x] = 1
	assert_bool(_view().is_explored(28 * 40 + 4)).is_false()
	_run(10)
	assert_array([_base()]).is_equal([MIRROR])
	assert_int(_intel.search.picks).is_equal(0)


func test_the_search_uses_only_view_data() -> void:
	_settle()
	_explore_mirror()
	_run(10)
	# The goal is a function of the explored cells and the own Headquarters alone: moving the
	# hidden enemy rows changes nothing.
	var goal: Vector2i = _base()
	for row: int in _world.unit_count():
		if _world.owner[row] == 2:
			_world.pos_x[row] = 500
			_world.pos_y[row] = 39500
	_make("normal")
	_settle()
	_run(10)
	assert_array([_base()]).is_equal([goal])


func test_off_keeps_the_mirror_estimate() -> void:
	_make("easy")
	_settle()
	_explore_mirror()
	_run(10)
	assert_array([_base()]).is_equal([MIRROR])
	assert_int(_intel.search.picks).is_equal(0)
	_make("normal")
	_intel.search.hold_ticks = 0
	_run(20)
	assert_array([_base()]).is_equal([MIRROR])


func test_the_mirror_stays_while_it_is_unexplored() -> void:
	_settle()
	_run(10)
	assert_array([_base()]).is_equal([MIRROR])
	assert_int(_intel.search.picks).is_equal(0)


func test_the_levels_and_the_frozen_copies() -> void:
	assert_int(Rig.level_of("easy").search_hold_ticks).is_equal(0)
	assert_int(Rig.level_of("normal").search_hold_ticks).is_greater(0)
	assert_int(Rig.level_of("hard").search_hold_ticks).is_greater(0)
	for level: String in ["easy", "normal", "hard"]:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_int(copy.search_hold_ticks).is_equal(0)
