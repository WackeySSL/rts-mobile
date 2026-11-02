extends GdUnitTestSuite
## The dummy and a blacked-out Headquarters (plan row P129, ADR 0020 section 5, ADR 0023 section 10,
## ADR 0026 section 2 rule 2). The sim drops a PLACE while the structures producer it judges by (the
## lowest-id finished one) is blacked out, so the dummy, which never sends a Command the sim drops,
## must see it: `PlayerView.row_offline`, an own column, is the sim's own test. A QUEUE is accepted
## at a blacked-out producer, so the unit tabs are not held back. The rest of the rules of a site
## are in test_dummy_sites.gd.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")


func test_a_blacked_out_headquarters_places_nothing_until_it_is_back() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	world.offline_until[Rig.row_of(world, 1, "headquarters")] = world.tick + 200
	# The sim drops a PLACE while the producer is blacked out (ADR 0026 section 2, rule 2), so the
	# dummy sends none, think after think, and nothing is dropped or paid.
	for _again: int in 3:
		var sent: Array[Command] = _think(world, ai)
		assert_array(sent).is_empty()
		Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.credits[1]).is_equal(2000)
	# Back online (the blackout ended at tick 200): the PLACE goes out and the sim keeps it.
	Rig.run(world, loop, [], 200)
	var back: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(back))).is_equal(["power_plant"])
	Rig.step(world, loop, back)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(1)


func test_the_dummy_and_the_sim_agree_on_the_edge_of_a_blackout() -> void:
	# `offline_until` is the tick the Headquarters is back. A Command of this think is applied in
	# tick t and judged by the stamp t + 1: blacked out when `offline_until` is above it. Two ticks
	# ahead is out; one tick ahead (back at the stamp) is in.
	var edge: Dictionary[int, bool] = {0: true, 1: true, 2: false, 3: false}
	for ahead: int in edge:
		var sim_keeps: bool = _sim_keeps_a_place(_blackout_world([ahead]))
		var dummy_places: bool = not (
			_places(_think(_blackout_world([ahead]), Rig.dummy(1))).is_empty()
		)
		assert_bool(sim_keeps).override_failure_message("sim, ahead %d" % ahead).is_equal(
			edge[ahead]
		)
		assert_bool(dummy_places).override_failure_message("dummy, ahead %d" % ahead).is_equal(
			sim_keeps
		)


func test_only_the_headquarters_the_sim_judges_by_counts_for_a_blackout() -> void:
	# The sim judges a PLACE by the lowest-id finished structures producer (`producer_row`): the
	# first Headquarters. A blackout of a later one changes nothing, one of the first stops it.
	var cases: Array[Vector2i] = [Vector2i(200, 0), Vector2i(0, 200), Vector2i(200, 200)]
	cases.append(Vector2i(0, 0))
	for blackouts: Vector2i in cases:
		var sim_keeps: bool = _sim_keeps_a_place(_blackout_world([blackouts.x, blackouts.y]))
		var world: World = _blackout_world([blackouts.x, blackouts.y])
		var dummy_places: bool = not _places(_think(world, Rig.dummy(1))).is_empty()
		assert_bool(sim_keeps).override_failure_message(str(blackouts)).is_equal(blackouts.x == 0)
		assert_bool(dummy_places).override_failure_message(str(blackouts)).is_equal(sim_keeps)


func test_a_blacked_out_producer_still_gets_its_units_queued() -> void:
	var world: World = _barracks_start()
	var loop: MatchLoop = Rig.loop_of(world)
	for id: String in ["headquarters", "barracks"]:
		world.offline_until[Rig.row_of(world, 1, id)] = world.tick + 200
	var squads: Array[String] = ["rifle_squad", "rifle_squad", "rifle_squad", "rifle_squad"]
	# A QUEUE is accepted at a blacked-out producer (the queue waits for it): only a PLACE is not.
	var sent: Array[Command] = _think(world, Rig.ai_of(Rig.def_with(squads), 1))
	assert_array(_names(world, _starts(sent))).is_equal(["rifle_squad", "rifle_squad"])
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.queue_count[1 * World.TABS + World.Tab.INFANTRY]).is_equal(2)


## A start where player 1 has one finished Headquarters per entry of `ahead` (the first is the
## start's, the others are given at (20, 6)), entry i blacked out for `ahead[i]` ticks from now
## (0 = not at all), and every tile explored.
func _blackout_world(ahead: Array[int]) -> World:
	var world: World = Rig.start()
	Rig.explore_all(world)
	for at: int in ahead.size():
		var row: int = Rig.row_of(world, 1, "headquarters")
		if at > 0:
			row = world.index_of(Rig.give(world, 1, "headquarters", 20, 6))
		world.offline_until[row] = world.tick + ahead[at]
	return world


## Whether the sim keeps a PLACE of a power plant at the first spiral slot, (2,500, 2,500), sent by
## hand in the next tick of `world`.
func _sim_keeps_a_place(world: World) -> bool:
	var plant: int = Rig.type_of(world, "power_plant")
	Rig.step(world, Rig.loop_of(world), [Command.place(1, 2500, 2500, plant)])
	return world.dropped_commands == 0


## One think of `ai` on a fresh view of its player: its economy commands.
func _think(world: World, ai: AiController) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, ai.player_id), sent)
	return Rig.economy(sent)


## The PLACE commands of `sent`: their points (milli-tiles).
func _places(sent: Array[Command]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for command: Command in sent:
		if command.type == Command.Type.PLACE:
			found.append(Vector2i(command.target_x, command.target_y))
	return found


## The QUEUE and PLACE commands of `sent`: what the think started, in order.
func _starts(sent: Array[Command]) -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE or command.type == Command.Type.PLACE:
			found.append(command)
	return found


## The type ids that the commands of `started` name, in order.
func _names(world: World, started: Array[Command]) -> Array[String]:
	var found: Array[String] = []
	for command: Command in started:
		found.append(String(world.type_ids[command.payload[0]]))
	return found


## The start with plenty of credits and, for player 1, a power plant and a barracks beside the
## Headquarters (given, finished: no rule is asked).
func _barracks_start() -> World:
	var world: World = Rig.start()
	Rig.give(world, 1, "power_plant", 10, 2)
	Rig.give(world, 1, "barracks", 24, 2)
	world.credits[1] = 20000
	return world
