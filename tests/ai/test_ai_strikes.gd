extends "res://tests/ai/support/strike_suite.gd"
## The Deep Bore's rules of `AiStrikes` (plan row P181, ADR 0030 sections 1, 4 and 6) on a
## hand-built World: the point of most enemy value, the minimum, the own rows, the charge and the
## blackout ticks, the pending rupture, the budget, the reaction, the ghosts and the bounds.

const BORE_POINT: Vector2i = Vector2i(31500, 31500)
const BARRACKS_POINT: Vector2i = Vector2i(30000, 34000)


func test_easy_never_fires_and_the_levels_that_use_strikes_are_normal_and_hard() -> void:
	(
		assert_array(
			[
				Rig.level_of("easy").uses_strike,
				Rig.level_of("normal").uses_strike,
				Rig.level_of("hard").uses_strike
			]
		)
		. is_equal([0, 1, 1])
	)
	_arm_strikes("easy", 0)
	_cluster()
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	assert_int(_striker.strikes).is_equal(0)
	assert_int(_memory.commands_left).is_equal(8)


func test_a_charged_deep_bore_fires_on_the_point_of_most_enemy_value() -> void:
	_cluster()
	_fire(READY)
	assert_array(_shots()).is_empty()
	_fire(KNOWN)
	var shots: Array[Command] = _shots()
	assert_int(shots.size()).is_equal(1)
	(
		assert_array(
			[
				shots[0].player_id,
				shots[0].target_id,
				Vector2i(shots[0].target_x, shots[0].target_y),
				shots[0].payload.size()
			]
		)
		. is_equal([1, _strike, BORE_POINT, 0])
	)
	assert_int(_striker.strikes).is_equal(1)
	assert_int(_memory.commands_left).is_equal(7)


func test_the_sim_takes_the_shot_and_lands_it_on_the_point() -> void:
	_cluster()
	_fire(READY)
	_fire(KNOWN)
	# The think of tick `KNOWN` is answered in the step of that tick.
	AiRig.step(_world, _loop, _shots())
	assert_int(_world.dropped_commands).is_equal(0)
	assert_array([_world.strike_x[1], _world.strike_y[1]]).is_equal([BORE_POINT.x, BORE_POINT.y])
	assert_int(_world.strike_tick[1]).is_not_equal(0)


func test_a_denser_cluster_wins_over_a_single_more_valuable_building() -> void:
	# A refinery alone (1,400) against the cluster (2,200): the radius counts, not the one row.
	_enemy_building("refinery", 34, 8)
	_cluster()
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])


func test_the_shot_waits_for_the_minimum_and_a_value_equal_to_it_fires() -> void:
	_cluster()
	_arm_strikes("normal")
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.strike_type = &"fossil_strike"
	def.target_tests_max = TESTS
	var chosen: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	chosen.reaction_ticks = REACTION
	def.strike_min_value = 2201
	_striker = AiStrikes.create(def, chosen, 1)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	def.strike_min_value = 2200
	_striker = AiStrikes.create(def, chosen, 1)
	_fire(KNOWN + 15)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])


func test_an_own_unit_inside_the_radius_moves_the_shot_to_the_next_point() -> void:
	_cluster()
	# 1,000 from the factory's centre: inside the radius of the factory's point only.
	AiRig.add_unit_of(_world, 1, "heavy_tank", 32500, 31500)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([BARRACKS_POINT.x, BARRACKS_POINT.y])
	# An own harvester (not a combat unit) inside the barracks' radius too: no point is clear.
	AiRig.add_unit_of(_world, 1, "harvester", 29000, 35000)
	_fire(KNOWN + 15)
	assert_array(_out).is_empty()


func test_an_own_building_and_the_scout_inside_the_radius_block_a_point_too() -> void:
	_cluster()
	AiRig.give(_world, 1, "power_plant", 32, 31)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([BARRACKS_POINT.x, BARRACKS_POINT.y])
	var scout: int = _scout(29, 34)
	assert_int(scout).is_greater(0)
	_fire(KNOWN + 15)
	assert_array(_out).is_empty()


func test_the_charge_and_the_blackout_gate_the_shot_to_the_tick() -> void:
	_cluster()
	_world.ready_tick[_row_in_world(_strike)] = 5000
	_fire(KNOWN)
	# The sim takes a SUPERWEAPON once the stamp (tick + 1) reaches `ready_tick`.
	_fire(5000 - 2)
	assert_array(_out).is_empty()
	_fire(5000 - 1)
	assert_int(_shots().size()).is_equal(1)
	_world.ready_tick[_row_in_world(_strike)] = 0
	_world.offline_until[_row_in_world(_strike)] = 6000
	_fire(6000 - 2)
	assert_array(_out).is_empty()
	_fire(6000 - 1)
	assert_int(_shots().size()).is_equal(1)


func test_a_site_that_is_not_complete_does_not_fire() -> void:
	_cluster()
	_world.build_left[_row_in_world(_strike)] = 100
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	_world.build_left[_row_in_world(_strike)] = 0
	_fire(KNOWN + 15)
	assert_int(_shots().size()).is_equal(1)


func test_a_pending_rupture_blocks_a_second_shot() -> void:
	_cluster()
	_fire(READY)
	_fire(KNOWN)
	AiRig.step(_world, _loop, _shots())
	assert_int(_world.strike_tick[1]).is_not_equal(0)
	# A second Deep Bore, charged: the player's rupture is pending, so nothing is sent.
	var second: int = _give_strike("fossil_strike", 16, 2)
	assert_int(second).is_not_equal(_strike)
	_world.tick = KNOWN + 1
	_fire(KNOWN + 15)
	assert_array(_out).is_empty()
	assert_int(_memory.commands_left).is_equal(8)
	assert_int(_striker.strikes).is_equal(1)


func test_a_think_without_budget_sends_nothing_and_changes_nothing() -> void:
	_cluster()
	_fire(READY)
	_fire(KNOWN, 0)
	assert_array(_out).is_empty()
	assert_int(_striker.strikes).is_equal(0)
	assert_int(_memory.strike_wave).is_equal(0)
	_fire(KNOWN + 15, 1)
	assert_int(_shots().size()).is_equal(1)
	assert_int(_memory.commands_left).is_equal(0)


func test_a_sighting_must_be_a_reaction_old_before_it_counts() -> void:
	_cluster()
	_fire(READY)
	_fire(READY + REACTION - 1)
	assert_array(_out).is_empty()
	_fire(READY + REACTION)
	assert_int(_shots().size()).is_equal(1)


func test_nothing_that_is_hidden_counts_and_a_remembered_building_does() -> void:
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("barracks", 29, 33)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	# The sim's own record of a building seen and gone: a ghost the player remembers.
	_ghost(9001, "vehicle_factory", 30, 30)
	_ghost2(9002, "barracks", 29, 33)
	_fire(KNOWN + 15)
	_fire(KNOWN + 15 + REACTION)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])


func test_the_tests_of_a_run_stay_under_the_cap_and_the_richest_thing_is_tried() -> void:
	_see_all()
	for at: int in 20:
		_enemy_building("power_plant", 4 + at % 5 * 7, 16 + at / 5 * 6)
	_enemy_building("vehicle_factory", 30, 30)
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.strike_min_value = 1
	def.target_tests_max = 25
	var chosen: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	chosen.reaction_ticks = REACTION
	_striker = AiStrikes.create(def, chosen, 1)
	_fire(READY)
	_fire(KNOWN)
	# 25 things fit in the cap of 25, one anchor: the most valuable, the factory.
	assert_int(_striker.tests).is_less_equal(25)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])


func test_the_manager_makes_no_pass_and_the_kinds_and_radius_are_the_sims() -> void:
	var source: String = FileAccess.get_file_as_string("res://game/ai/AiStrikes.gd")
	assert_str(source).is_not_empty()
	for name: String in ["own_rows", "seen_rows"]:
		assert_bool(source.contains(name)).is_false()
	_cluster()
	_fire(READY)
	_fire(KNOWN)
	assert_int(_striker.passes).is_equal(0)
	assert_array([AiStrikes.RUPTURE, AiStrikes.BLACKOUT]).is_equal(
		[Strike.Kind.RUPTURE, Strike.Kind.BLACKOUT]
	)
	assert_int(_view().type_strike_radius[_type("fossil_strike")]).is_equal(RADIUS)


func test_the_strike_draws_no_random_number() -> void:
	_cluster()
	var twin: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	_fire(READY)
	_fire(KNOWN)
	# The intel run drew nothing either (no scout trip is due), so the stream is untouched.
	assert_array(_rng.state()).is_equal(twin.state())


## The point of the one SUPERWEAPON of `_out`, as [x, y].
func _target() -> Array[int]:
	var shots: Array[Command] = _shots()
	assert_int(shots.size()).is_equal(1)
	return [shots[0].target_x, shots[0].target_y]


## A second ghost: the suite's helper writes slot 0, this one slot 1.
func _ghost2(id: int, type_id: String, col: int, line: int) -> void:
	var cap: int = _world.ghost_cap
	var cell: int = (line + 1) * _world.map_cols + col + 1
	_world.ghost_id[cap + 1] = id
	_world.ghost_type[cap + 1] = _type(type_id)
	_world.ghost_owner[cap + 1] = 2
	_world.ghost_cell[cap + 1] = cell
	_world.ghost_count[1] = 2
