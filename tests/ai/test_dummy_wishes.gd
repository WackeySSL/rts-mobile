extends GdUnitTestSuite
## What the dummy queues at one think (plan row P83, ADR 0020 section 4): the next wish of the build
## order, the harvesters it wants, the room of a queue and the credits. Each case is a think on a
## start of `ai_rig.gd` that the case changed (a building given, credits set), and where it matters
## the Commands are applied through the loop to show the sim keeps every one (`dropped_commands` 0).

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const VEHICLES: int = World.Tab.VEHICLES
const INFANTRY: int = World.Tab.INFANTRY
const STRUCTURES: int = World.Tab.STRUCTURES


func test_the_first_think_queues_only_the_power_plant() -> void:
	var world: World = Rig.start()
	var sent: Array[Command] = _think(world, Rig.dummy(1))
	assert_array(_queued(world, sent)).is_equal(["power_plant"])
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].player_id).is_equal(1)
	Rig.step(world, Rig.loop_of(world), sent)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.credits[1]).is_equal(2000 - 300)


func test_a_wish_the_credits_do_not_cover_waits() -> void:
	var world: World = Rig.start()
	world.credits[1] = 299
	assert_array(_think(world, Rig.dummy(1))).is_empty()
	world.credits[1] = 300
	assert_array(_queued(world, _think(world, Rig.dummy(1)))).is_equal(["power_plant"])


func test_a_wish_the_credits_do_not_cover_keeps_them_from_a_cheaper_one_behind_it() -> void:
	var world: World = Rig.start()
	Rig.give(world, 1, "power_plant", 10, 2)
	world.credits[1] = 1000
	# The refinery (1,400) is next and its power plant stands; the barracks (400) must not take
	# the credits first.
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["refinery", "barracks"]), 1)
	assert_array(_think(world, ai)).is_empty()
	world.credits[1] = 1500
	assert_array(_queued(world, _think(world, ai))).is_equal(["refinery"])


func test_a_wish_whose_requirement_is_missing_is_waited_for_not_skipped() -> void:
	var world: World = Rig.start()
	# The barracks needs a power plant that the player does not own, and the plant behind it in the
	# order is affordable: the order holds, nothing is queued.
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["barracks", "power_plant"]), 1)
	assert_array(_think(world, ai)).is_empty()


func test_a_queued_item_counts_as_had_and_a_requirement_must_be_owned() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	Rig.step(world, loop, _think(world, ai))
	# The plant is queued, not placed: the refinery behind it has no power plant to stand on yet.
	assert_array(_think(world, ai)).is_empty()


func test_a_lost_building_is_wanted_again_at_its_place_in_the_order() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	for _step: int in 3000:
		Rig.tick(world, loop, [ai])
		if Rig.count_of(world, 1, "power_plant") == 2 and Rig.count_of(world, 1, "barracks") == 1:
			break
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(2)
	Rig.kill(world, loop, Rig.row_of(world, 1, "power_plant"))
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(1)
	var next: Array[String] = []
	for _step: int in 600:
		next = _queued(world, Rig.tick(world, loop, [ai]))
		if not next.is_empty():
			break
	# The second plant of the order comes before the vehicle factory that is next after it.
	assert_array(next).is_equal(["power_plant"])
	assert_int(world.dropped_commands).is_equal(0)


func test_it_asks_for_the_harvesters_it_lacks_per_refinery() -> void:
	var world: World = _economy_start()
	# One refinery wants 2 harvesters (the shipped def); the player has 0, the queue room is 2.
	var ai: DummyAi = _harvest_ai()
	assert_array(_queued(world, _think(world, ai))).is_equal(["harvester", "harvester"])
	Rig.add_unit_of(world, 1, "harvester", 4500, 12500)
	assert_array(_queued(world, _think(world, ai))).is_equal(["harvester"])
	Rig.add_unit_of(world, 1, "harvester", 5500, 12500)
	assert_array(_queued(world, _think(world, ai))).is_empty()
	# A second refinery doubles the want.
	Rig.give(world, 1, "refinery", 20, 10)
	assert_array(_queued(world, _think(world, ai))).is_equal(["harvester", "harvester"])


func test_a_queued_harvester_counts_and_the_sim_keeps_what_was_sent() -> void:
	var world: World = _economy_start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = _harvest_ai()
	Rig.step(world, loop, _think(world, ai))
	assert_int(world.queue_count[1 * World.TABS + VEHICLES]).is_equal(2)
	assert_array(_think(world, ai)).is_empty()
	assert_int(world.dropped_commands).is_equal(0)


func test_unit_types_in_the_order_are_queued_on_their_tab() -> void:
	var world: World = _barracks_start()
	# The start has two rifle squads; the order wants three.
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["rifle_squad", "rifle_squad", "rifle_squad"]), 1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_queued(world, sent)).is_equal(["rifle_squad"])
	Rig.step(world, Rig.loop_of(world), sent)
	assert_int(world.queue_count[1 * World.TABS + INFANTRY]).is_equal(1)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_queue_holds_queue_target_items_and_never_more_than_it_has_slots() -> void:
	var world: World = _barracks_start()
	var turrets: Array[String] = ["defence_turret", "defence_turret", "defence_turret"]
	var sent: Array[Command] = _think(world, Rig.ai_of(Rig.def_with(turrets), 1))
	assert_array(_queued(world, sent)).is_equal(["defence_turret", "defence_turret"])
	# A target above the rules' 5 slots is cut to the slots.
	var many: AiDef = Rig.def_with(["defence_turret", "defence_turret", "defence_turret"])
	many.queue_target = 9
	many.build_order.append_array([&"defence_turret", &"defence_turret", &"defence_turret"])
	var loop: MatchLoop = Rig.loop_of(world)
	var big: Array[Command] = _think(world, Rig.ai_of(many, 1))
	assert_int(big.size()).is_equal(world.queue_slots)
	Rig.step(world, loop, big)
	assert_int(world.queue_count[1 * World.TABS + STRUCTURES]).is_equal(world.queue_slots)
	assert_int(world.dropped_commands).is_equal(0)


func test_one_think_queues_no_more_than_the_credits_pay() -> void:
	var world: World = Rig.start()
	var def: AiDef = Rig.def_with(["power_plant", "power_plant", "power_plant"])
	def.queue_target = 5
	world.credits[1] = 650
	var sent: Array[Command] = _think(world, Rig.ai_of(def, 1))
	assert_array(_queued(world, sent)).is_equal(["power_plant", "power_plant"])
	Rig.step(world, Rig.loop_of(world), sent)
	assert_array([world.credits[1], world.dropped_commands]).is_equal([50, 0])


func test_an_id_the_roster_lacks_and_a_type_no_tab_builds_are_left_out() -> void:
	var world: World = Rig.start()
	var order: Array[String] = ["flying_pig", "headquarters", "power_plant"]
	var ai: DummyAi = Rig.ai_of(Rig.def_with(order), 1)
	assert_array(_queued(world, _think(world, ai))).is_equal(["power_plant"])


func test_a_player_with_no_producer_sends_nothing() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	assert_int(world.defeated_tick[1]).is_greater(0)
	assert_array(_think(world, Rig.dummy(1))).is_empty()


func test_a_player_the_view_has_no_queues_for_sends_nothing() -> void:
	var world: World = Rig.start()
	for player: int in [0, 3]:
		assert_array(_think(world, Rig.dummy(1), player)).is_empty()


## One think of `ai` on a fresh view of `world` (of `player` when given, else the ai's own).
func _think(world: World, ai: AiController, player: int = -1) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, ai.player_id if player < 0 else player), sent)
	return sent


## The type ids that the QUEUE commands of `sent` name, in order.
func _queued(world: World, sent: Array[Command]) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


## A dummy of player 1 that wants harvesters and nothing else (an empty build order).
func _harvest_ai() -> DummyAi:
	return Rig.ai_of(Rig.def_with([]), 1)


## The start with plenty of credits and, for player 1, a power plant and a barracks beside the
## Headquarters (given, not placed): the two buildings that a unit or a turret in the order needs.
func _barracks_start() -> World:
	var world: World = Rig.start()
	Rig.give(world, 1, "power_plant", 10, 2)
	Rig.give(world, 1, "barracks", 24, 2)
	world.credits[1] = 20000
	return world


## The start with plenty of credits and, for player 1, a power plant, a refinery and a vehicle
## factory beside the Headquarters (given, not placed: no rule is asked) and no harvester.
func _economy_start() -> World:
	var world: World = Rig.start()
	Rig.give(world, 1, "power_plant", 10, 2)
	Rig.give(world, 1, "refinery", 10, 10)
	Rig.give(world, 1, "vehicle_factory", 2, 14)
	world.credits[1] = 20000
	return world
