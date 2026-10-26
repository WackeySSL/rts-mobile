extends GdUnitTestSuite
## Where the dummy places a built structure (plan row P83, ADR 0020 section 4): the first slot of
## the spiral round its Headquarters that `placement` accepts, at most `place_tries` slots asked
## about. The Headquarters of the start of `ai_rig.gd` has its top-left tile at (6, 6); with the
## stride 4 of the shipped def, slot (-1, -1) is the tile (2, 2), (0, -1) is (6, 2) and (1, -1) is
## (10, 2). Each case builds a power plant (2x2, 150 ticks) through a plain QUEUE and thinks when it
## waits to be placed; a PLACE is applied through the loop where the sim's answer matters.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const BUILT_TICKS: int = 160


func test_the_first_slot_is_the_top_left_corner_of_ring_one() -> void:
	var world: World = _waiting()
	Rig.explore_all(world)
	var ai: DummyAi = Rig.dummy(1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_places(sent)).is_equal([Vector2i(2500, 2500)])
	assert_int(ai.placement_tries).is_equal(1)
	Rig.step(world, Rig.loop_of(world), sent)
	assert_array([world.dropped_commands, Rig.count_of(world, 1, "power_plant")]).is_equal([0, 1])


func test_a_unit_on_a_slot_moves_the_building_to_the_next_slot() -> void:
	var world: World = _waiting()
	Rig.explore_all(world)
	Rig.add_unit_of(world, 1, "rifle_squad", 2500, 2500)
	var ai: DummyAi = Rig.dummy(1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_places(sent)).is_equal([Vector2i(6500, 2500)])
	assert_int(ai.placement_tries).is_equal(2)


func test_an_unseen_enemy_unit_on_a_slot_is_asked_about_like_the_sim_does() -> void:
	var world: World = _waiting()
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
	var world: World = _waiting()
	var ai: DummyAi = Rig.dummy(1)
	# The Headquarters sees 7 tiles round its centre: tile (2, 2) is 50 away squared, 49 is the
	# limit; (6, 2) is 26 away. Two slots are asked about, as in the whole build (test_dummy_economy).
	assert_array(_places(_think(world, ai))).is_equal([Vector2i(6500, 2500)])
	assert_int(ai.placement_tries).is_equal(2)


func test_a_base_with_no_free_slot_asks_place_tries_slots_and_places_nothing() -> void:
	var world: World = _waiting(Rig.rows(true))
	Rig.explore_all(world)
	var def: AiDef = Rig.dummy_def()
	var ai: DummyAi = Rig.dummy(1)
	for _think_count: int in 2:
		var sent: Array[Command] = _think(world, ai)
		# Nothing at all is sent: the plant waits, and the refinery behind it has no plant to stand
		# on. The same work again on the next think.
		assert_array(sent).is_empty()
		assert_int(ai.placement_tries).is_equal(def.place_tries)
	assert_bool(PlayerView.of(world, 1).structure_ready()).is_true()


func test_place_tries_bounds_the_slots_asked_about() -> void:
	var world: World = _waiting()
	Rig.explore_all(world)
	Rig.add_unit_of(world, 1, "rifle_squad", 2500, 2500)
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.place_tries = 1
	var ai: DummyAi = Rig.ai_of(def, 1)
	# The one slot it may ask about is taken by the unit: no PLACE, though the next slot is free.
	assert_array(_think(world, ai)).is_empty()
	assert_int(ai.placement_tries).is_equal(1)


func test_the_slots_follow_the_stride_of_the_def() -> void:
	var world: World = _waiting()
	Rig.explore_all(world)
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.place_stride_tiles = 5
	# Slot (-1, -1) is now the tile (1, 1).
	assert_array(_places(_think(world, Rig.ai_of(def, 1)))).is_equal([Vector2i(1500, 1500)])


func test_without_a_headquarters_the_spiral_is_centred_on_the_first_building() -> void:
	var world: World = _waiting()
	Rig.explore_all(world)
	Rig.give(world, 1, "barracks", 20, 6)
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	assert_int(world.defeated_tick[1]).is_equal(0)
	var sent: Array[Command] = _think(world, Rig.dummy(1))
	# The barracks has its top-left tile at (20, 6): its slot (-1, -1) is the tile (16, 2).
	assert_array(_places(sent)).is_equal([Vector2i(16500, 2500)])
	Rig.step(world, loop, sent)
	assert_array([world.dropped_commands, Rig.count_of(world, 1, "power_plant")]).is_equal([0, 1])


## A start of `rows` (the shipped map when empty) whose player 1 has a power plant queued and
## built, waiting to be placed: nothing else is queued, owned or thinking.
func _waiting(rows: Array[String] = []) -> World:
	var world: World = Rig.start(rows)
	var loop: MatchLoop = Rig.loop_of(world)
	var plant: int = Rig.type_of(world, "power_plant")
	Rig.step(world, loop, [Command.queue(1, plant)])
	Rig.run(world, loop, [], BUILT_TICKS)
	assert_bool(PlayerView.of(world, 1).structure_ready()).is_true()
	assert_int(world.dropped_commands).is_equal(0)
	return world


## One think of `ai` on a fresh view of `world`.
func _think(world: World, ai: AiController) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, ai.player_id), sent)
	return sent


## The points (milli-tiles) of the PLACE commands of `sent`.
func _places(sent: Array[Command]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for command: Command in sent:
		if command.type == Command.Type.PLACE:
			found.append(Vector2i(command.target_x, command.target_y))
	return found
