extends "res://tests/ai/support/army_suite.gd"
## `AiArmy`'s staging point, its RALLY, the home squad and the lists `AiIntel.refresh` fills for it
## (plan row P179, ADR 0030 sections 3, 4 and 6) on hand-built Worlds read through `PlayerView`.


func test_refresh_fills_the_lists_the_army_reads_in_its_two_passes() -> void:
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 9500, 9500)
	var scout: int = _scout(9, 12)
	var harvester: int = AiRig.add_unit_of(_world, 1, "harvester", 10500, 9500)
	var barracks: int = AiRig.give(_world, 1, "barracks", 12, 6)
	var foe: int = _enemy("rifle_squad", 12500, 12500)
	_enemy("harvester", 13500, 12500)
	AiRig.give(_world, 2, "barracks", 14, 14)
	_settle()
	_see_all()
	var view: PlayerView = _view()
	_intel.refresh(view, _memory)
	# One pass over the own rows and one over the seen rows, nothing more.
	assert_int(_intel.passes).is_equal(2)
	var squads: PackedInt32Array = _squads()
	var expected: PackedInt32Array = squads.duplicate()
	expected.append(tank)
	assert_array(_memory.unit_id).is_equal(expected)
	# The scout type and the harvester are not combat units of the army.
	assert_bool(_memory.unit_id.has(scout)).is_false()
	assert_bool(_memory.unit_id.has(harvester)).is_false()
	# Seen enemy combat units only: no harvester, no building.
	var seen: PackedInt32Array = AiRig.ids_of(_world, 2, "rifle_squad")
	assert_bool(seen.has(foe)).is_true()
	assert_array(_memory.seen_unit_id).is_equal(seen)
	# The buildings, ascending, with their centres; the Headquarters' tile.
	assert_bool(_memory.site_id.has(barracks)).is_true()
	assert_int(_memory.site_id.size()).is_equal(2)
	assert_array([_memory.home_x, _memory.home_y]).is_equal([7, 7])
	var at_barracks: int = _memory.site_id.find(barracks)
	var centre: Vector2i = view.row_pos(view.row_of(barracks))
	assert_array([_memory.site_x[at_barracks], _memory.site_y[at_barracks]]).is_equal(
		[centre.x, centre.y]
	)


func test_the_lists_are_rebuilt_not_summed_and_the_headquarters_goes_with_its_row() -> void:
	_think(5)
	assert_array([_memory.home_x, _memory.home_y]).is_equal([7, 7])
	var count: int = _memory.site_id.size()
	_think(20)
	assert_int(_memory.site_id.size()).is_equal(count)
	assert_int(_memory.unit_id.size()).is_equal(2)
	var hq: int = _row_in_world(AiRig.ids_of(_world, 1, "headquarters")[0])
	_world.hp[hq] = 0
	AiRig.step(_world, _loop)
	_think(35)
	assert_array([_memory.home_x, _memory.home_y]).is_equal([-1, -1])
	assert_int(_memory.site_id.size()).is_equal(0)


func test_the_staging_point_is_the_offset_from_the_headquarters_toward_the_mirror_point() -> void:
	_think(5)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([STAGING.x, STAGING.y])
	assert_bool(_memory.has_staging()).is_true()
	# With no producer there is nothing to rally.
	assert_array(_of(Command.Type.RALLY)).is_empty()
	assert_int(_army.rallies).is_equal(0)


func test_the_staging_point_follows_the_base_estimate() -> void:
	# An estimate due south of the Headquarters: 6 tiles straight south.
	_memory.base_x = 7
	_memory.base_y = 37
	_think(5)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([7, 13])
	# Due west and east (the map edge clamps nothing here), and an estimate on the Headquarters.
	_memory.base_x = 37
	_memory.base_y = 7
	_think(20)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([13, 7])
	_memory.base_x = 7
	_memory.base_y = 7
	_think(35)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([7, 7])


func test_the_staging_point_is_the_offset_along_the_diagonal_toward_a_corner() -> void:
	# From (7, 7) toward (0, 0): the way is (-7, -7), its length isqrt(98) = 9, so 6 * -7 / 9 = -4.
	_memory.base_x = 0
	_memory.base_y = 0
	_think(5)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([3, 3])


func test_a_long_offset_is_cut_to_the_map() -> void:
	var def: OpponentDef = _def()
	def.staging_offset_tiles = 12
	_arm("normal", def)
	_memory.base_x = 0
	_memory.base_y = 0
	_think(5)
	# 12 tiles toward (0, 0) from (7, 7) is (-2, -2): tile 0 on both axes.
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([0, 0])


func test_one_rally_per_tab_to_the_staging_point_and_again_only_when_it_moves() -> void:
	var barracks: int = AiRig.give(_world, 1, "barracks", 12, 6)
	var factory: int = AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_settle()
	_think(5)
	var rallies: Array[Command] = _of(Command.Type.RALLY)
	assert_int(rallies.size()).is_equal(2)
	var target: Vector2i = _centre(STAGING)
	var by_building: Dictionary[int, Vector2i] = {}
	for command: Command in rallies:
		assert_int(command.player_id).is_equal(1)
		by_building[command.target_id] = Vector2i(command.target_x, command.target_y)
	assert_array(by_building.keys()).contains_exactly_in_any_order([barracks, factory])
	assert_vector(by_building[barracks]).is_equal(target)
	assert_vector(by_building[factory]).is_equal(target)
	# Two RALLYs and the squads' first MOVE to the staging point.
	assert_int(_memory.commands_left).is_equal(5)
	assert_int(_army.rallies).is_equal(2)
	# The sim takes them: the rally point of the infantry and vehicle tabs is the staging point.
	AiRig.step(_world, _loop, rallies)
	assert_int(_world.dropped_commands).is_equal(0)
	var view: PlayerView = _view()
	for tab: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES]:
		assert_array([view.rally_x[tab], view.rally_y[tab]]).is_equal([target.x, target.y])
	# Nothing again while it stays.
	_think(20)
	assert_array(_of(Command.Type.RALLY)).is_empty()
	# It moves with the base estimate: one RALLY per tab again, to the new point.
	_memory.base_x = 7
	_memory.base_y = 37
	_think(35)
	rallies = _of(Command.Type.RALLY)
	assert_int(rallies.size()).is_equal(2)
	for command: Command in rallies:
		assert_array([command.target_x, command.target_y]).is_equal([7500, 13500])


func test_the_rally_goes_through_the_lowest_finished_producer_and_not_a_site() -> void:
	var first: int = AiRig.give(_world, 1, "barracks", 12, 6)
	var second: int = AiRig.give(_world, 1, "barracks", 16, 6)
	_settle()
	_think(5)
	assert_int(_of(Command.Type.RALLY).size()).is_equal(1)
	assert_int(_of(Command.Type.RALLY)[0].target_id).is_equal(first)
	# A building still under construction does not produce yet: no rally through it.
	_arm("normal")
	_world.build_left[_row_in_world(first)] = 5000
	_world.build_left[_row_in_world(second)] = 5000
	_think(5)
	assert_array(_of(Command.Type.RALLY)).is_empty()


func test_the_rally_is_all_or_nothing_within_the_budget_and_the_memory_waits() -> void:
	AiRig.give(_world, 1, "barracks", 12, 6)
	AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_settle()
	_think(5, 1)
	assert_array(_out).is_empty()
	assert_int(_memory.commands_left).is_equal(1)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([-1, -1])
	assert_int(_army.rallies).is_equal(0)
	_think(20, 2)
	assert_int(_out.size()).is_equal(2)
	assert_int(_memory.commands_left).is_equal(0)
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([STAGING.x, STAGING.y])


func test_a_new_combat_unit_joins_the_home_squad_and_a_dead_one_leaves() -> void:
	_think(5)
	var squads: PackedInt32Array = _squads()
	assert_array(_memory.member_id).is_equal(squads)
	assert_array(_memory.member_squad).is_equal(PackedInt32Array([0, 0]))
	assert_array([_memory.squad_role[0], _memory.squad_state[0]]).is_equal(
		[AiArmy.ROLE_HOME, AiMemory.SquadState.HOME]
	)
	var tank: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 9500, 9500)
	_think(20)
	assert_array(_memory.member_id).is_equal(PackedInt32Array([squads[0], squads[1], tank]))
	assert_array(_memory.member_squad).is_equal(PackedInt32Array([0, 0, 0]))
	AiRig.kill(_world, _loop, _row_in_world(squads[0]))
	_think(35)
	assert_array(_memory.member_id).is_equal(PackedInt32Array([squads[1], tank]))
	assert_array(_memory.member_squad).is_equal(PackedInt32Array([0, 0]))


func test_every_unit_of_the_scout_type_is_left_to_intel_with_or_without_an_id() -> void:
	var fresh: int = _scout(9, 12)
	var out: int = _scout(9, 14)
	_settle()
	# `out` is the scout of a trip (it has an id in the memory), `fresh` waits for one (none yet).
	_memory.scout_id = out
	_think(5)
	for id: int in [fresh, out]:
		assert_bool(_memory.member_id.has(id)).is_false()
		assert_bool(_memory.unit_id.has(id)).is_false()
	# The return order of the first think names the two squads and no scout.
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array(moves[0].unit_ids).is_equal(_squads())
	# The home squad keeps no id of the scout type however many turns pass.
	_think(20)
	assert_bool(_memory.member_id.has(fresh) or _memory.member_id.has(out)).is_false()


func test_the_first_order_sends_the_home_squad_to_the_staging_point_once() -> void:
	_think(5)
	var moves: Array[Command] = _of(Command.Type.MOVE)
	assert_int(moves.size()).is_equal(1)
	assert_array(moves[0].unit_ids).is_equal(_squads())
	assert_array([moves[0].target_x, moves[0].target_y]).is_equal([11500, 11500])
	assert_int(_memory.commands_left).is_equal(7)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([11, 11])
	assert_int(_army.returns).is_equal(1)
	# The staging point's key: foot (infantry), owner STAGING.
	assert_array([_memory.goal_x, _memory.goal_y]).is_equal(
		[PackedInt32Array([11]), PackedInt32Array([11])]
	)
	assert_array(_memory.goal_class).is_equal(PackedInt32Array([AiIntel.FOOT]))
	assert_array(_memory.goal_owner).is_equal(PackedInt32Array([1 << AiMemory.Owner.STAGING]))
	# Again: nothing, the goal is the staging point.
	_think(20)
	assert_array(_out).is_empty()
	# The staging point moves: the squad goes to the new one.
	_memory.base_x = 7
	_memory.base_y = 37
	_think(35)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([7, 13])
	assert_array([_memory.goal_x, _memory.goal_y]).is_equal(
		[PackedInt32Array([7]), PackedInt32Array([13])]
	)


func test_an_order_that_cannot_be_sent_changes_nothing_and_is_asked_again() -> void:
	_think(5, 0)
	assert_array(_out).is_empty()
	assert_int(_memory.commands_left).is_equal(0)
	assert_array([_memory.squad_goal_x[0], _memory.squad_goal_y[0]]).is_equal([-1, -1])
	assert_int(_memory.goal_keys()).is_equal(0)
	assert_int(_army.returns).is_equal(0)
	_think(20)
	assert_int(_of(Command.Type.MOVE).size()).is_equal(1)


func test_orders_go_only_to_own_unit_ids_of_the_view() -> void:
	var foe: int = _enemy("heavy_tank", 20500, 20500)
	AiRig.add_unit_of(_world, 1, "heavy_tank", 9500, 9500)
	_settle()
	_see_all()
	_think(5)
	var own: Dictionary[int, bool] = {}
	for id: int in AiRig.ids_of(_world, 1, "rifle_squad") + AiRig.ids_of(_world, 1, "heavy_tank"):
		own[id] = true
	for command: Command in _out:
		assert_int(command.player_id).is_equal(1)
		for id: int in command.unit_ids:
			assert_bool(own.has(id)).is_true()
			assert_int(id).is_not_equal(foe)


func test_without_a_headquarters_there_is_no_staging_point_and_no_rally() -> void:
	AiRig.give(_world, 1, "barracks", 12, 6)
	var hq: int = _row_in_world(AiRig.ids_of(_world, 1, "headquarters")[0])
	_world.hp[hq] = 0
	AiRig.step(_world, _loop)
	_settle()
	_think(5)
	assert_array(_out).is_empty()
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([-1, -1])


func test_the_army_draws_only_the_wave_jitter_and_the_refresh_keeps_its_two_passes() -> void:
	_seed_crowd()
	# The army on a level that owns its jitter (40 ticks); the reference stream makes the one draw
	# the army owns: the first wave's start jitter.
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.wave_jitter_ticks = 40
	_army = AiArmy.create(_def(), level, 1)
	var reference: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	reference.next_int(41)
	var expected: int = reference.next_int(1000)
	_think(5)
	assert_int(_intel.passes).is_equal(2)
	# One draw at the first think, none after.
	_think(20)
	assert_int(_rng.next_int(1000)).is_equal(expected)


func test_the_army_source_names_no_row_list_of_the_view() -> void:
	# A loop over the view's rows in the army would be an uncounted pass (ADR 0030 section 4).
	var source: String = FileAccess.get_file_as_string("res://game/ai/AiArmy.gd")
	assert_str(source).is_not_empty()
	for name: String in ["own_rows", "seen_rows", "ghost_count"]:
		assert_bool(source.contains(name)).is_false()


func test_the_headquarters_with_the_lowest_id_is_the_home() -> void:
	AiRig.give(_world, 1, "headquarters", 30, 30)
	_settle()
	_think(5)
	assert_array([_memory.home_x, _memory.home_y]).is_equal([7, 7])


func test_a_rally_goes_only_to_the_tab_whose_point_is_not_at_the_staging_point() -> void:
	var barracks: int = AiRig.give(_world, 1, "barracks", 12, 6)
	_settle()
	_think(5)
	AiRig.step(_world, _loop, _of(Command.Type.RALLY))
	var factory: int = AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_settle()
	_think(20)
	var rallies: Array[Command] = _of(Command.Type.RALLY)
	assert_int(rallies.size()).is_equal(1)
	assert_int(rallies[0].target_id).is_equal(factory)
	assert_int(rallies[0].target_id).is_not_equal(barracks)
	assert_int(_army.rallies).is_equal(2)


func test_a_rally_the_keys_cannot_hold_is_not_sent_and_the_staging_point_waits() -> void:
	var def: OpponentDef = _def()
	def.goal_keys_max = 1
	_arm("normal", def)
	AiRig.give(_world, 1, "barracks", 12, 6)
	AiRig.give(_world, 1, "vehicle_factory", 12, 10)
	_settle()
	_think(5)
	# Foot and tracked need two keys and the cap is one: no RALLY, no new point, no key.
	assert_array(_out).is_empty()
	assert_array([_memory.staging_x, _memory.staging_y]).is_equal([-1, -1])
	assert_array([_memory.goal_keys(), _memory.commands_left, _army.rallies]).is_equal([0, 8, 0])


## A crowd: tanks of both sides.
func _seed_crowd() -> void:
	for index: int in 12:
		AiRig.add_unit_of(_world, 1, "heavy_tank", 8500 + index * 500, 12500)
		_enemy("heavy_tank", 20500 + index * 500, 12500)
	_settle()
	_see_all()
