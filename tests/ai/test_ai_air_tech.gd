extends "res://tests/ai/support/air_suite.gd"
## The opponent's air and tech (plan row P250, ADR 0036 section 14): the intel's counts of seen
## aircraft and anti-air, the economy's anti-air per seen aircraft, the production's research
## and aircraft draw, the shipped data and the frozen arena's defs.


func test_intel_counts_the_aircraft_and_the_anti_air_it_sees_and_keeps_the_peak() -> void:
	var world: World = _shipped(RICH)
	var loop: MatchLoop = AiRig.loop_of(world)
	var bomber: int = AiRig.add_unit_of(world, 2, BOMBER, 10500, 7500)
	AiRig.add_unit_of(world, 2, FIGHTER, 11500, 7500)
	AiRig.give(world, 2, "fossil_aa", 11, 9)
	AiRig.settle(world, loop)
	var intel: AiIntel = AiIntel.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1)
	var memory: AiMemory = _memory("fossil")
	intel.run(PlayerView.of(world, 1), memory, _stream(), [] as Array[Command])
	# The bomber and the fighter are aircraft; the fighter's gun and the Burst Stack hit the air.
	assert_array([memory.seen_air, memory.seen_low_air, memory.seen_aa]).is_equal([2, 0, 2])
	assert_int(memory.seen_air_peak).is_equal(2)
	# The bomber leaves the view: the count falls, the peak stays.
	AiRig.kill(world, loop, PlayerView.of(world, 1).row_of(bomber))
	AiRig.settle(world, loop)
	intel.run(PlayerView.of(world, 1), memory, _stream(), [] as Array[Command])
	assert_array([memory.seen_air, memory.seen_air_peak]).is_equal([1, 2])


func test_a_remembered_anti_air_building_counts_and_a_hidden_aircraft_does_not() -> void:
	var world: World = _shipped(RICH)
	# Far from player 1's sight: neither the aircraft nor the building is seen.
	AiRig.add_unit_of(world, 2, BOMBER, 30500, 30500)
	AiRig.give(world, 2, "fossil_aa", 31, 33)
	var memory: AiMemory = _memory("fossil")
	AiIntel.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1).run(
		PlayerView.of(world, 1), memory, _stream(), [] as Array[Command]
	)
	assert_array([memory.seen_air, memory.seen_aa, memory.seen_air_peak]).is_equal([0, 0, 0])


func test_the_view_copies_the_air_and_tech_tables() -> void:
	var world: World = _shipped(RICH)
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(view.type_pads).is_equal(world.type_pads)
	assert_array(view.type_upgrade).is_equal(world.type_upgrade)
	assert_array(view.upgrade_type_first).is_equal(world.upgrade_type_first)
	assert_array(view.upgrade_type_count).is_equal(world.upgrade_type_count)
	assert_array(view.upgrade_types).is_equal(world.upgrade_types)
	assert_int(view.type_pads[AiRig.type_of(world, "fossil_airfield")]).is_equal(4)
	var heavy: int = view.type_upgrade[AiRig.type_of(world, "heavy_bombs")]
	assert_int(heavy).is_greater_equal(0)
	assert_int(view.upgrade_types[view.upgrade_type_first[heavy]]).is_equal(
		AiRig.type_of(world, BOMBER)
	)
	# The copies are the view's own: a write to the World's table does not reach them.
	world.type_pads[AiRig.type_of(world, "fossil_airfield")] = 9
	assert_int(view.type_pads[AiRig.type_of(world, "fossil_airfield")]).is_equal(4)
	var seen: Array[int] = [view.type_upgrade[0], view.upgrade_type_first[0]]
	seen.append_array([view.upgrade_type_count[0], view.upgrade_types[0]])
	world.type_upgrade[0] += 50
	world.upgrade_type_first[0] += 50
	world.upgrade_type_count[0] += 50
	world.upgrade_types[0] += 50
	assert_array([view.type_upgrade[0], view.upgrade_type_first[0]]).is_equal(seen.slice(0, 2))
	assert_array([view.upgrade_type_count[0], view.upgrade_types[0]]).is_equal(seen.slice(2, 4))


# --- Economy: anti-air per seen aircraft ------------------------------------------------------


func test_one_anti_air_building_is_wanted_per_aa_per_seen_aircraft_up_to_the_cap() -> void:
	var level: AiDifficultyDef = Rig.level_of("normal")
	assert_array([level.aa_per_seen_aircraft, level.aa_max]).is_equal([2, 3])
	# One think queues what the structure queue has room for (two); the cap is three in all.
	var wanted: Dictionary[int, int] = {0: 0, 1: 1, 2: 1, 3: 2, 5: 2, 9: 2}
	for peak: int in wanted:
		var world: World = _base()
		var memory: AiMemory = _memory("fossil")
		memory.seen_air_peak = peak
		var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), level, 1)
		var sent: Array[Command] = _economy_run(economy, memory, world, 1)
		var queued: int = _ids(sent, world).count("fossil_aa")
		assert_int(queued).override_failure_message("peak %d" % peak).is_equal(wanted[peak])
	# Two stand already: the third is the last, whatever was seen.
	var held: World = _base()
	AiRig.give(held, 1, "fossil_aa", 22, 8)
	AiRig.give(held, 1, "fossil_aa", 22, 10)
	var memory: AiMemory = _memory("fossil")
	memory.seen_air_peak = 9
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), level, 1)
	assert_int(_ids(_economy_run(economy, memory, held, 1), held).count("fossil_aa")).is_equal(1)


func test_the_anti_air_goes_ahead_of_the_order_but_waits_for_its_requirement() -> void:
	var world: World = _base()
	var memory: AiMemory = _memory("fossil")
	memory.seen_air_peak = 2
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1)
	var sent: Array[Command] = _economy_run(economy, memory, world, 1)
	assert_str(_ids_in_tab(sent, world, World.Tab.STRUCTURES)[0]).is_equal("fossil_aa")
	# No barracks: the Burst Stack cannot be queued, so the economy's own wish is left alone.
	var bare: World = _base()
	AiRig.kill(bare, AiRig.loop_of(bare), AiRig.row_of(bare, 1, "barracks"))
	var other: AiMemory = _memory("fossil")
	other.seen_air_peak = 2
	var again: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1)
	assert_bool(_ids(_economy_run(again, other, bare, 1), bare).has("fossil_aa")).is_false()


func test_a_level_without_the_ratio_builds_no_anti_air() -> void:
	var world: World = _base()
	var memory: AiMemory = _memory("fossil")
	memory.seen_air_peak = 9
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.aa_per_seen_aircraft = 0
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), level, 1)
	assert_bool(_ids(_economy_run(economy, memory, world, 6), world).has("fossil_aa")).is_false()


# --- Production: the aircraft -----------------------------------------------------------------


func test_one_aircraft_is_queued_a_think_while_the_airfield_has_a_free_pad() -> void:
	var world: World = _air_base()
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, _memory("fossil"), world)
	var flight: Array[String] = _in_flight(sent, world)
	assert_int(flight.size()).is_equal(1)
	assert_array([BOMBER, FIGHTER]).contains(flight)
	assert_int(production.air_queued).is_equal(1)
	# The FLIGHT queue holds it now; the next think queues no second one at once (one at a time per
	# think, and the pads hold four).
	AiRig.step(world, AiRig.loop_of(world), sent)
	assert_int(world.queue_count[World.TABS + World.Tab.FLIGHT]).is_equal(1)


func test_no_aircraft_without_a_free_pad() -> void:
	var world: World = _air_base()
	for at: int in 4:
		AiRig.add_unit_of(world, 1, FIGHTER, 20500 + at * 500, 16500)
	var out: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_in_flight(out, world)).is_empty()
	# Without an airfield nothing is queued either.
	var bare: World = _shipped(RICH)
	AiRig.give(bare, 1, "barracks", 2, 2)
	AiRig.give(bare, 1, "vehicle_factory", 2, 12)
	(
		assert_array(
			_in_flight(_run(_production("fossil", "normal"), _memory("fossil"), bare), bare)
		)
		. is_empty()
	)


func test_the_weak_tier_draws_no_aircraft_and_the_fighter_weight_grows_with_the_aircraft_seen(
) -> void:
	var base: World = _air_base()
	var easy: Array[String] = _in_flight(
		_run(_production("fossil", "easy"), _memory("fossil"), base), base
	)
	assert_array(easy).is_empty()
	var plain: Dictionary[String, int] = _air_draws(0)
	var seen: Dictionary[String, int] = _air_draws(20)
	# 70 bomber to 30 fighter without sightings, 70 to 230 with 20 aircraft seen.
	assert_int(plain[BOMBER]).is_greater(plain[FIGHTER])
	assert_int(seen[FIGHTER]).is_greater(seen[BOMBER] * 2)


func test_a_pick_that_cannot_be_paid_is_held_and_its_price_kept_from_the_ground_draw() -> void:
	# Only the bomber is in the mix (the fighter's weight is 0), so the pick is the bomber.
	var def: OpponentDef = _def()
	def.air_weights = PackedInt32Array([0, 0, 70, 0, 60, 0])
	var production: AiProduction = AiProduction.create(def, _level("normal"), 1)
	var world: World = _air_base()
	var memory: AiMemory = _memory("fossil")
	var bomber_cost: int = _cost(world, BOMBER)
	world.credits[1] = bomber_cost - 200
	# Short of the price: no aircraft, and the ground draw gets none of the credits either.
	assert_array(_run(production, memory, world)).is_empty()
	assert_array(_run(production, memory, world)).is_empty()
	# Paid at last: the held bomber goes first, ahead of any ground unit.
	world.credits[1] = RICH
	var sent: Array[Command] = _run(production, memory, world)
	assert_array(_in_flight(sent, world)).is_equal([BOMBER])
	assert_int(production.air_queued).is_equal(1)


func test_the_aircraft_waits_for_credits_and_the_unit_cap() -> void:
	var poor: World = _air_base()
	poor.credits[1] = _cost(poor, FIGHTER) - 1
	(
		assert_array(
			_in_flight(_run(_production("fossil", "normal"), _memory("fossil"), poor), poor)
		)
		. is_empty()
	)
	var full: World = _air_base()
	full.unit_cap = 2  # The two rifle squads.
	(
		assert_array(
			_in_flight(_run(_production("fossil", "normal"), _memory("fossil"), full), full)
		)
		. is_empty()
	)


# --- Production: the research -----------------------------------------------------------------


func test_the_first_upgrade_that_changes_an_owned_unit_is_researched_one_at_a_time() -> void:
	var world: World = _research_base()
	AiRig.add_unit_of(world, 1, BOMBER, 31500, 14500)
	var sent: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	var research: Array[String] = _ids_in_tab(sent, world, World.Tab.RESEARCH)
	assert_array(research).is_equal(["heavy_bombs"])
	# Queued: the next think adds none while it researches.
	AiRig.step(world, AiRig.loop_of(world), sent)
	(
		assert_array(
			_ids_in_tab(
				_run(_production("fossil", "normal"), _memory("fossil"), world),
				world,
				World.Tab.RESEARCH
			)
		)
		. is_empty()
	)
	# Researched: the next one in data order.
	world.queue_count.fill(0)
	world.upgrades[1] |= 1
	var next: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_ids_in_tab(next, world, World.Tab.RESEARCH)).is_equal(["plated_hull"])


func test_no_research_without_an_owned_unit_it_changes_a_floor_or_a_level_that_allows_it() -> void:
	var world: World = _research_base()
	var normal: AiProduction = _production("fossil", "normal")
	(
		assert_array(_ids_in_tab(_run(normal, _memory("fossil"), world), world, World.Tab.RESEARCH))
		. is_empty()
	)
	AiRig.add_unit_of(world, 1, BOMBER, 31500, 14500)
	# The credits left must stay above the floor (400): the price is 800.
	world.credits[1] = 800 + 400
	(
		assert_array(
			_ids_in_tab(
				_run(_production("fossil", "normal"), _memory("fossil"), world),
				world,
				World.Tab.RESEARCH
			)
		)
		. is_empty()
	)
	world.credits[1] = 800 + 401
	var paid: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_ids_in_tab(paid, world, World.Tab.RESEARCH)).is_equal(["heavy_bombs"])
	# A level with no floor (Easy) never researches.
	world.queue_count.fill(0)
	world.credits[1] = RICH
	var easy: Array[Command] = _run(_production("fossil", "easy"), _memory("fossil"), world)
	assert_array(_ids_in_tab(easy, world, World.Tab.RESEARCH)).is_empty()


# --- Layer-aware counters ---------------------------------------------------------------------


func test_seen_aircraft_move_the_draw_only_to_a_role_that_hits_the_air() -> void:
	var world: World = _shipped(RICH)
	world.tick = 1000
	AiRig.give(world, 1, "barracks", 2, 2)
	AiRig.give(world, 1, "vehicle_factory", 2, 12)
	AiRig.give(world, 1, "fossil_radar", 22, 2)
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	var bombers: Array[int] = _first_draws(
		_production("fossil", "normal"), world, _seen(world, {BOMBER: 6}, 0)
	)
	# The rocket squad is the one role whose gun hits the air layer: it gains, no other role does.
	assert_int(bombers[ANTI_VEHICLE]).is_greater(plain[ANTI_VEHICLE])
	for role: int in [ANTI_INFANTRY, TANK, ARTILLERY]:
		assert_int(bombers[role]).is_less_equal(plain[role])
	# Ground units seen keep the armour counter on the ground weapons, as before.
	var heavy: Array[int] = _first_draws(
		_production("fossil", "normal"), world, _seen(world, {"heavy_tank": 6}, 0)
	)
	assert_int(heavy[ANTI_VEHICLE]).is_greater(plain[ANTI_VEHICLE])


func test_the_focus_search_skips_a_target_the_group_cannot_hit() -> void:
	var world: World = _shipped(RICH)
	var loop: MatchLoop = AiRig.loop_of(world)
	var tank: int = AiRig.add_unit_of(world, 1, "heavy_tank", 9500, 9500)
	var bomber: int = AiRig.add_unit_of(world, 2, BOMBER, 10500, 9500)
	var foe: int = AiRig.add_unit_of(world, 2, "heavy_tank", 11500, 9500)
	AiRig.settle(world, loop)
	var view: PlayerView = PlayerView.of(world, 1)
	var ids: PackedInt32Array = PackedInt32Array([bomber, foe])
	var mine: int = AiEnemyScan.hit_mask(view, view.row_type(view.row_of(tank)))
	assert_int(mine & PlayerView.Layer.AIR).is_equal(0)
	# The bomber has fewer hit points (500 against the tank's), but the tank's gun is ground only.
	var ground: Vector3i = AiEnemyScan.weakest(view, ids, Vector2i(10000, 9500), 5000, mine, 0, 99)
	assert_int(view.row_id(ground.x)).is_equal(foe)
	# A group that hits the air (any mask with the air bit) may take the bomber.
	var all: Vector3i = AiEnemyScan.weakest(view, ids, Vector2i(10000, 9500), 5000, 7, 0, 99)
	assert_int(view.row_id(all.x)).is_equal(
		bomber if view.row_hp(view.row_of(bomber)) < view.row_hp(view.row_of(foe)) else foe
	)
	# A group with no weapon at all (mask 0) takes nothing.
	assert_int(AiEnemyScan.weakest(view, ids, Vector2i(10000, 9500), 5000, 0, 0, 99).x).is_equal(-1)


func test_the_shipped_orders_carry_the_tech_for_normal_and_hard_and_not_for_easy() -> void:
	for faction: String in Rig.FACTIONS:
		var orders: Array[AiBuildOrderDef] = Rig.def_of(faction).build_orders
		var tech: Array[StringName] = [
			StringName(faction + "_airfield"),
			StringName(faction + "_engineering"),
			StringName(faction + "_space")
		]
		(
			assert_array(orders[0].steps.filter(func(id: StringName) -> bool: return tech.has(id)))
			. is_empty()
		)
		for tier: int in [1, 2]:
			var steps: Array[StringName] = orders[tier].steps
			var at: Array[int] = [steps.find(tech[0]), steps.find(tech[1]), steps.find(tech[2])]
			assert_array(at).is_equal([at[0], at[0] + 1, at[0] + 2])
			assert_int(at[0]).is_greater(steps.find(StringName(faction + "_radar")))


func test_every_air_and_tech_type_the_defs_name_is_a_type_of_the_shipped_roster() -> void:
	for faction: String in Rig.FACTIONS:
		var def: OpponentDef = Rig.def_of(faction)
		var roster: FactionDef = load("res://data/factions/%s.tres" % faction) as FactionDef
		var ids: Array[StringName] = []
		for unit: UnitDef in roster.roster:
			ids.append(unit.type_id)
		for id: StringName in [def.aa_type, def.fighter_type, def.bomber_type]:
			assert_bool(ids.has(id)).override_failure_message(String(id)).is_true()
		assert_int(def.air_weights.size()).is_equal(OpponentDef.TIERS * 2)
		# The weak tier builds no airfield, so it draws no aircraft.
		assert_array([def.air_weight(0, false), def.air_weight(0, true)]).is_equal([0, 0])
		assert_array(def.build_orders[0].steps).is_not_empty()


func test_the_level_fields_default_off_and_easy_researches_nothing() -> void:
	var fresh: AiDifficultyDef = AiDifficultyDef.new()
	assert_array([fresh.aa_per_seen_aircraft, fresh.aa_max, fresh.research_floor]).is_equal(
		[0, 0, 0]
	)
	assert_int(Rig.level_of("easy").research_floor).is_equal(0)
	assert_int(Rig.level_of("normal").research_floor).is_greater(0)
	assert_int(Rig.level_of("hard").aa_per_seen_aircraft).is_less(
		Rig.level_of("normal").aa_per_seen_aircraft
	)


func test_the_frozen_arena_defs_switch_the_air_and_tech_off() -> void:
	for faction: String in Rig.FACTIONS:
		var def: OpponentDef = load("res://data/dev/arena/ai_4b/opponent_%s.tres" % faction)
		assert_array([def.aa_type, def.fighter_type, def.bomber_type]).is_equal([&"", &"", &""])
		assert_int(def.air_weights.size()).is_equal(6)
		for weight: int in def.air_weights:
			assert_int(weight).is_equal(0)
	for level: String in Rig.LEVELS:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_array([copy.aa_per_seen_aircraft, copy.aa_max, copy.research_floor]).is_equal(
			[0, 0, 0]
		)
