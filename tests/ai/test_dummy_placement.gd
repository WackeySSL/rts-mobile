extends GdUnitTestSuite
## Where the dummy places a structure (plan rows P83 and P129, ADR 0020 section 4, ADR 0026 section
## 8): the first slot of the spiral round its Headquarters that `placement` accepts for the type it
## wants, at most `place_tries` slots asked about, in one `PLACE [type]` that starts a site. The
## Headquarters of the start of `ai_rig.gd` has its top-left tile at (6, 6); with the stride 4 of
## the shipped def, slot (-1, -1) is the tile (2, 2), (0, -1) is (6, 2) and (1, -1) is (10, 2). Each
## case thinks on the start (the first wish of the build order is the power plant, 2x2, 300
## credits, with 2,000 in hand); a PLACE is applied through the loop where the sim's answer matters.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")


func test_the_first_slot_is_the_top_left_corner_of_ring_one() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	var ai: DummyAi = Rig.dummy(1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_places(sent)).is_equal([Vector2i(2500, 2500)])
	assert_int(ai.placement_tries).is_equal(1)
	Rig.step(world, Rig.loop_of(world), sent)
	assert_array([world.dropped_commands, Rig.count_of(world, 1, "power_plant")]).is_equal([0, 1])


func test_a_place_names_its_type_and_starts_a_site_that_is_paid_at_once() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	var sent: Array[Command] = _think(world, Rig.dummy(1))
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.PLACE)
	assert_array(Array(sent[0].payload)).is_equal([Rig.type_of(world, "power_plant")])
	Rig.step(world, Rig.loop_of(world), sent)
	var row: int = Rig.row_of(world, 1, "power_plant")
	# A site: work left, the starting hit points, the whole price taken (the loop's tick ends with
	# one tick of work and the start credits less 300).
	assert_int(world.build_left[row]).is_between(1, 150 * Production.PROGRESS_PER_TICK)
	assert_int(world.hp[row]).is_less(world.type_max_hp[Rig.type_of(world, "power_plant")])
	assert_int(world.credits[1]).is_equal(2000 - 300)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_unit_on_a_slot_moves_the_building_to_the_next_slot() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.add_unit_of(world, 1, "rifle_squad", 2500, 2500)
	var ai: DummyAi = Rig.dummy(1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_places(sent)).is_equal([Vector2i(6500, 2500)])
	assert_int(ai.placement_tries).is_equal(2)


func test_an_unseen_enemy_unit_on_a_slot_is_asked_about_like_the_sim_does() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	# Player 1 does not see tile (2, 2), and the sim would refuse a PLACE on it all the same.
	Rig.add_unit_of(world, 2, "rifle_squad", 2500, 2500)
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_places(sent)).is_equal([Vector2i(6500, 2500)])
	Rig.step(world, loop, sent)
	assert_array([world.dropped_commands, Rig.count_of(world, 1, "power_plant")]).is_equal([0, 1])


func test_a_slot_that_is_not_explored_is_passed_over() -> void:
	var world: World = Rig.start()
	var ai: DummyAi = Rig.dummy(1)
	# The Headquarters sees 7 tiles round its centre: tile (2, 2) is 50 away squared, 49 is the
	# limit; (6, 2) is 26 away. Two slots are asked about, as in the whole build (test_dummy_economy).
	assert_array(_places(_think(world, ai))).is_equal([Vector2i(6500, 2500)])
	assert_int(ai.placement_tries).is_equal(2)


func test_a_base_with_no_free_slot_asks_place_tries_slots_and_places_nothing() -> void:
	var world: World = Rig.start(Rig.rows(true))
	Rig.explore_all(world)
	var def: AiDef = Rig.dummy_def()
	var ai: DummyAi = Rig.dummy(1)
	for _think_count: int in 2:
		var sent: Array[Command] = _think(world, ai)
		# Nothing at all is sent: the plant has no slot, and the refinery behind it has no plant to
		# stand on. The same work again on the next think.
		assert_array(sent).is_empty()
		assert_int(ai.placement_tries).is_equal(def.place_tries)
	# Nothing was paid: the price is taken only when a site starts.
	assert_int(world.credits[1]).is_equal(2000)


func test_place_tries_bounds_the_slots_asked_about() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.add_unit_of(world, 1, "rifle_squad", 2500, 2500)
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.place_tries = 1
	var ai: DummyAi = Rig.ai_of(def, 1)
	# The one slot it may ask about is taken by the unit: no PLACE, though the next slot is free.
	assert_array(_think(world, ai)).is_empty()
	assert_int(ai.placement_tries).is_equal(1)


func test_the_slots_follow_the_stride_of_the_def() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.place_stride_tiles = 5
	# Slot (-1, -1) is now the tile (1, 1).
	assert_array(_places(_think(world, Rig.ai_of(def, 1)))).is_equal([Vector2i(1500, 1500)])


func test_the_slot_is_asked_about_for_the_footprint_of_the_type_wanted() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.give(world, 1, "power_plant", 10, 2)
	# The refinery (3x3) is the wish, not a plant (2x2). At the first slot (2, 2) it covers the
	# tiles 2 to 4, a tile short of the Headquarters at (6, 6): free, so it is the slot.
	var refinery: AiDef = Rig.def_with(["refinery"])
	var sent: Array[Command] = _think(world, Rig.ai_of(refinery, 1))
	assert_array(Array(sent[0].payload)).is_equal([Rig.type_of(world, "refinery")])
	assert_array(_places(sent)).is_equal([Vector2i(2500, 2500)])
	# A rifle squad on the 3x3's far corner, tile (4, 4), blocks it but not a 2x2 plant there.
	Rig.add_unit_of(world, 1, "rifle_squad", 4500, 4500)
	var ai: DummyAi = Rig.ai_of(refinery, 1)
	assert_array(_places(_think(world, ai))).is_equal([Vector2i(6500, 2500)])
	assert_int(ai.placement_tries).is_equal(2)
	var plant: AiDef = Rig.def_with(["power_plant", "power_plant"])
	assert_array(_places(_think(world, Rig.ai_of(plant, 1)))).is_equal([Vector2i(2500, 2500)])


func test_the_spiral_is_centred_on_the_type_the_def_names() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.give(world, 1, "barracks", 20, 6)
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.hq_type = &"barracks"
	# The barracks has its top-left tile at (20, 6): its slot (-1, -1) is the tile (16, 2).
	assert_array(_places(_think(world, Rig.ai_of(def, 1)))).is_equal([Vector2i(16500, 2500)])


func test_without_a_headquarters_nothing_is_placed_and_nothing_is_dropped() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.give(world, 1, "barracks", 20, 6)
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	assert_int(world.defeated_tick[1]).is_equal(0)
	# The barracks keeps the player in the match, but no complete building produces structures: the
	# sim would drop a PLACE (ADR 0026 section 2, rule 2), so the dummy sends none.
	var sent: Array[Command] = _think(world, Rig.dummy(1))
	assert_array(sent).is_empty()
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)


## One think of `ai` on a fresh view of `world`: its economy commands (the ATTACK_MOVE of the
## defence are judged in test_dummy_defence.gd).
func _think(world: World, ai: AiController) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, ai.player_id), sent)
	return Rig.economy(sent)


## The points (milli-tiles) of the PLACE commands of `sent`.
func _places(sent: Array[Command]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for command: Command in sent:
		if command.type == Command.Type.PLACE:
			found.append(Vector2i(command.target_x, command.target_y))
	return found
