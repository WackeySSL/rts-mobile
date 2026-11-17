extends "res://tests/ai/support/air_suite.gd"
## The layer rules of the air and tech row (plan row P250): the counter choices, the holds and
## the census of finished buildings, the army's ground-only counts and the own aircraft that
## join no ground squad.


func test_a_counter_never_goes_to_a_role_that_cannot_hit_the_layer_even_if_its_percent_is_best(
) -> void:
	var world: World = _shipped(RICH)
	world.tick = 1000
	AiRig.give(world, 1, "barracks", 2, 2)
	AiRig.give(world, 1, "vehicle_factory", 2, 12)
	AiRig.give(world, 1, "fossil_radar", 22, 2)
	# The heavy tank's gun does 500 percent against the bomber's armour class: unfiltered it would
	# win the counter, but its gun hits the ground only, so the rocket squad (the one role that
	# hits the air) gets the shift.
	var weapon: int = world.type_weapon[AiRig.type_of(world, "heavy_tank")]
	world.weapon_vs_armour[weapon * 4 + world.type_armour[AiRig.type_of(world, BOMBER)]] = 500
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	var bombers: Array[int] = _first_draws(
		_production("fossil", "normal"), world, _seen(world, {BOMBER: 6}, 0)
	)
	assert_int(bombers[ANTI_VEHICLE]).is_greater(plain[ANTI_VEHICLE])
	assert_int(bombers[TANK]).is_less_equal(plain[TANK])


func test_no_research_and_no_aircraft_while_the_scout_waits_for_credits() -> void:
	var world: World = _research_base()
	AiRig.add_unit_of(world, 1, BOMBER, 31500, 14500)
	# The scout costs more than the credits; research and the aircraft would both be paid.
	var scout: int = AiRig.type_of(world, "light_tank")
	world.type_cost[scout] = 5000
	world.credits[1] = 3000
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = scout
	var sent: Array[Command] = _run(_production("fossil", "normal"), memory, world)
	assert_array(_ids_in_tab(sent, world, World.Tab.RESEARCH)).is_empty()
	assert_array(_in_flight(sent, world)).is_empty()
	# The same world with no scout wanted queues the research.
	var free: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_ids_in_tab(free, world, World.Tab.RESEARCH)).is_equal(["heavy_bombs"])


func test_an_unfinished_airfield_or_engineering_centre_is_no_producer_pad_or_requirement() -> void:
	var world: World = _research_base()
	AiRig.add_unit_of(world, 1, BOMBER, 31500, 14500)
	var field: int = AiRig.row_of(world, 1, "fossil_airfield")
	var works: int = AiRig.row_of(world, 1, "fossil_engineering")
	world.build_left[field] = 100
	world.build_left[works] = 100
	var sent: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_in_flight(sent, world)).is_empty()
	assert_array(_ids_in_tab(sent, world, World.Tab.RESEARCH)).is_empty()
	# Finished, both are used.
	world.build_left[field] = 0
	world.build_left[works] = 0
	var done: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_ids_in_tab(done, world, World.Tab.RESEARCH)).is_equal(["heavy_bombs"])
	assert_int(_in_flight(done, world).size()).is_equal(1)


func test_the_army_counts_only_enemies_that_can_hit_the_ground() -> void:
	var world: World = _shipped(RICH)
	var loop: MatchLoop = AiRig.loop_of(world)
	var fighter: int = AiRig.add_unit_of(world, 2, FIGHTER, 10500, 7500)
	var tank: int = AiRig.add_unit_of(world, 2, "heavy_tank", 11500, 7500)
	var stack: int = AiRig.give(world, 2, "fossil_aa", 11, 9)
	AiRig.settle(world, loop)
	var view: PlayerView = PlayerView.of(world, 1)
	var at: Vector2i = Vector2i(11000, 8000)
	var units: Vector2i = AiEnemyScan.value_in(view, [fighter], at, 9000, false, 0, 99)
	assert_array([units.x, units.y]).is_equal([0, 0])
	var sites: Vector2i = AiEnemyScan.value_in(view, [stack], at, 9000, true, 0, 99)
	assert_array([sites.x, sites.y]).is_equal([0, 0])
	var ground: Vector2i = AiEnemyScan.value_in(view, [tank], at, 9000, false, 0, 99)
	assert_int(ground.x).is_greater(0)
	assert_int(ground.y).is_equal(1)


func test_own_aircraft_join_no_ground_squad_but_seen_enemy_aircraft_stay_listed() -> void:
	var world: World = _shipped(RICH)
	var loop: MatchLoop = AiRig.loop_of(world)
	var mine: int = AiRig.add_unit_of(world, 1, FIGHTER, 9500, 9500)
	var tank: int = AiRig.add_unit_of(world, 1, "heavy_tank", 9500, 10500)
	var foe: int = AiRig.add_unit_of(world, 2, BOMBER, 11500, 9500)
	AiRig.settle(world, loop)
	var memory: AiMemory = _memory("fossil")
	var intel: AiIntel = AiIntel.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1)
	intel.refresh(PlayerView.of(world, 1), memory)
	assert_bool(memory.unit_id.has(tank)).is_true()
	assert_bool(memory.unit_id.has(mine)).is_false()
	assert_bool(memory.seen_unit_id.has(foe)).is_true()

# --- The data ---------------------------------------------------------------------------------
