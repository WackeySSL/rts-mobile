extends GdUnitTestSuite
## QUEUE and CANCEL (plan row P73, ADR 0018 section 5): the cost is paid when an item joins the
## queue and comes back whole on a cancel, the validity rules (unit tab, producer, requirement,
## room, credits), the shift of the later items, and the `_playing` gate of `Sim._apply` (P70b's
## follow-up: a defeated player's QUEUE and CANCEL are dropped and counted although the module
## would accept them). Literal numbers are the shipped data's: rifle squad 100, rocket squad 300,
## light tank 600, 2,000 starting credits and 5 queue slots.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const INFANTRY: int = World.Tab.INFANTRY
const VEHICLES: int = World.Tab.VEHICLES


func _rifle(world: World) -> int:
	return Worlds.type_of(world, "rifle_squad")


func _rocket(world: World) -> int:
	return Worlds.type_of(world, "rocket_squad")


## The commands of `ids` for player 1, ordered within one tick by their position.
func _queues(world: World, ids: Array[String]) -> Array[Command]:
	var commands: Array[Command] = []
	for index: int in ids.size():
		commands.append(Rig.queue(world, 1, ids[index], index))
	return commands


func test_a_queue_pays_at_once_and_the_item_joins_the_end() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_int(world.credits[1]).is_equal(1900)
	assert_array(Rig.items(world, 1, INFANTRY)).is_equal([_rifle(world)])
	Rig.step(world, [Rig.queue(world, 1, "rocket_squad")])
	assert_int(world.credits[1]).is_equal(1600)
	assert_array(Rig.items(world, 1, INFANTRY)).is_equal([_rifle(world), _rocket(world)])
	var base: int = Rig.queue_of(1, INFANTRY) * world.queue_slots
	assert_array(world.queue_type.slice(base, base + 5)).is_equal(
		[_rifle(world), _rocket(world), -1, -1, -1]
	)
	assert_int(world.credits[2]).is_equal(2000)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_queue_the_player_cannot_pay_is_dropped_and_credits_never_go_below_zero() -> void:
	var world: World = Rig.base()
	world.credits[1] = 99
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_array([world.credits[1], world.queue_count[Rig.queue_of(1, INFANTRY)]]).is_equal([99, 0])
	assert_int(world.dropped_commands).is_equal(1)
	world.credits[1] = 100
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_array([world.credits[1], world.queue_count[Rig.queue_of(1, INFANTRY)]]).is_equal([0, 1])
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_array([world.credits[1], world.queue_count[Rig.queue_of(1, INFANTRY)]]).is_equal([0, 1])
	assert_int(world.dropped_commands).is_equal(2)


func test_a_queue_holds_queue_slots_items_and_the_next_is_dropped_unpaid() -> void:
	var world: World = Rig.base()
	world.credits[1] = 100000
	var six: Array[String] = []
	six.resize(6)
	six.fill("rifle_squad")
	Rig.step(world, _queues(world, six))
	assert_int(world.queue_count[Rig.queue_of(1, INFANTRY)]).is_equal(5)
	assert_int(world.credits[1]).is_equal(100000 - 500)
	assert_int(world.dropped_commands).is_equal(1)
	# Another tab's queue has its own room.
	Rig.step(world, [Rig.queue(world, 1, "light_tank")])
	assert_int(world.queue_count[Rig.queue_of(1, VEHICLES)]).is_equal(1)


func test_a_tab_needs_a_producer_of_its_own() -> void:
	var world: World = Rig.base()
	# Player 2 has a barracks and no vehicle factory.
	Rig.step(world, [Rig.queue(world, 2, "rifle_squad"), Rig.queue(world, 2, "light_tank", 1)])
	assert_array(Rig.items(world, 2, INFANTRY)).is_equal([_rifle(world)])
	assert_array(Rig.items(world, 2, VEHICLES)).is_empty()
	assert_array([world.credits[2], world.dropped_commands]).is_equal([1900, 1])
	# Player 1 loses its barracks (REMOVE takes it out of the rows): nothing joins the infantry
	# queue any more, and the vehicle factory's queue is not affected.
	world.hp[world.index_of(Rig.BARRACKS)] = 0
	Rig.step(world)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "light_tank", 1)])
	assert_array(Rig.items(world, 1, INFANTRY)).is_empty()
	assert_array(Rig.items(world, 1, VEHICLES)).is_equal([Worlds.type_of(world, "light_tank")])
	assert_array([world.credits[1], world.dropped_commands]).is_equal([1400, 2])


## A requirement is owned when the item is queued; losing the building later leaves the queue as
## it was (ADR 0018 section 5). The shipped units require nothing, so the heavy tank is given the
## refinery.
func test_a_requirement_is_checked_when_the_item_is_queued_and_not_after() -> void:
	var world: World = Rig.base()
	var heavy: int = Worlds.type_of(world, "heavy_tank")
	world.type_requires[heavy] = Worlds.type_of(world, "refinery")
	Rig.step(world, [Rig.queue(world, 1, "heavy_tank")])
	assert_array(Rig.items(world, 1, VEHICLES)).is_equal([heavy])
	world.hp[world.index_of(Rig.REFINERY)] = 0
	Rig.step(world)
	assert_array(Rig.items(world, 1, VEHICLES)).is_equal([heavy])
	Rig.step(world, [Rig.queue(world, 1, "heavy_tank")])
	assert_array(Rig.items(world, 1, VEHICLES)).is_equal([heavy])
	assert_array([world.credits[1], world.dropped_commands]).is_equal([1000, 1])


## A type that is not buildable (the headquarters has no tab), a type index outside the table and a
## payload that is not one int are refused. Player 1 has a headquarters, so the STRUCTURES tab has
## a producer and the gate that refuses the headquarters is its own missing tab alone.
func test_only_buildable_types_can_be_queued() -> void:
	var world: World = Rig.base()
	Rig.add_headquarters(world)
	assert_int(Production.producer_row(world, 1, World.Tab.STRUCTURES)).is_greater_equal(0)
	var types: Array[int] = [
		Worlds.type_of(world, "headquarters"),
		-1,
		world.type_ids.size(),
		1000000,
	]
	for type: int in types:
		assert_bool(Production.apply_queue(world, Command.queue(1, type))).is_false()
	var none: Command = Command.queue(1, _rifle(world))
	none.payload = PackedInt32Array()
	var two: Command = Command.queue(1, _rifle(world))
	two.payload = PackedInt32Array([_rifle(world), _rifle(world)])
	assert_bool(Production.apply_queue(world, none)).is_false()
	assert_bool(Production.apply_queue(world, two)).is_false()
	assert_int(world.credits[1]).is_equal(2000)
	assert_array(world.queue_count).is_equal([0, 0, 0, 0, 0, 0, 0, 0, 0])


## P73b opens the STRUCTURES tab: a structure pays and joins the structures queue, and only a
## player with a headquarters (the producer of the tab) can queue one. The requirement is the same
## rule as for units: owned when the item is queued.
func test_a_structure_joins_the_structures_queue_when_the_player_has_a_producer_and_the_requirement(
) -> void:
	var world: World = Rig.base()
	var plant: int = Worlds.type_of(world, "power_plant")
	var barracks: int = Worlds.type_of(world, "barracks")
	# No headquarters, no producer of the tab: nothing joins and nothing is paid.
	Rig.step(world, [Rig.queue(world, 1, "power_plant")])
	assert_array([world.credits[1], world.dropped_commands]).is_equal([world.start_credits, 1])
	Rig.add_headquarters(world)
	Rig.step(world, [Rig.queue(world, 1, "power_plant"), Rig.queue(world, 1, "barracks", 1)])
	assert_array(Rig.items(world, 1, World.Tab.STRUCTURES)).is_equal([plant, barracks])
	assert_int(world.credits[1]).is_equal(
		world.start_credits - world.type_cost[plant] - world.type_cost[barracks]
	)
	assert_array(Rig.items(world, 1, INFANTRY)).is_empty()
	assert_int(world.dropped_commands).is_equal(1)
	# Player 2 has no headquarters, the producer of the tab.
	Rig.step(world, [Rig.queue(world, 2, "power_plant")])
	assert_array([world.credits[2], world.dropped_commands]).is_equal([world.start_credits, 2])
	# Player 1 loses its power plant: a barracks is refused, the power plant (needs the headquarters)
	# is not.
	world.hp[world.index_of(Rig.PLANT)] = 0
	Rig.step(world)
	var credits: int = world.credits[1]
	Rig.step(world, [Rig.queue(world, 1, "barracks"), Rig.queue(world, 1, "power_plant", 1)])
	assert_array(Rig.items(world, 1, World.Tab.STRUCTURES)).is_equal([plant, barracks, plant])
	assert_array([world.credits[1], world.dropped_commands]).is_equal(
		[credits - world.type_cost[plant], 3]
	)


func test_a_cancel_refunds_the_whole_cost_and_moves_the_later_items_up() -> void:
	var world: World = Rig.base()
	Rig.step(world, _queues(world, ["rifle_squad", "rocket_squad", "rifle_squad"]))
	assert_int(world.credits[1]).is_equal(1500)
	Rig.run(world, 9)
	var queue: int = Rig.queue_of(1, INFANTRY)
	assert_int(world.queue_progress[queue]).is_equal(1000)
	# A later item: the head keeps its progress.
	assert_bool(Production.apply_cancel(world, Command.cancel(1, INFANTRY, 1))).is_true()
	assert_int(world.credits[1]).is_equal(1800)
	assert_array(Rig.items(world, 1, INFANTRY)).is_equal([_rifle(world), _rifle(world)])
	assert_int(world.queue_progress[queue]).is_equal(1000)
	# The head: its progress is lost and the next item starts from 0.
	assert_bool(Production.apply_cancel(world, Command.cancel(1, INFANTRY, 0))).is_true()
	assert_int(world.credits[1]).is_equal(1900)
	assert_array(Rig.items(world, 1, INFANTRY)).is_equal([_rifle(world)])
	assert_int(world.queue_progress[queue]).is_equal(0)


func test_cancelling_the_last_item_leaves_an_empty_queue_and_the_credits_it_began_with() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "light_tank")])
	Rig.run(world, 5)
	Rig.step(world, [Command.cancel(1, VEHICLES, 0)])
	var queue: int = Rig.queue_of(1, VEHICLES)
	var base: int = queue * world.queue_slots
	assert_int(world.credits[1]).is_equal(2000)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([0, 0])
	assert_array(world.queue_type.slice(base, base + 5)).is_equal([-1, -1, -1, -1, -1])
	assert_int(world.dropped_commands).is_equal(0)


func test_a_cancel_that_names_no_item_is_dropped() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	var cases: Array[Command] = [
		Command.cancel(1, INFANTRY, 1),
		Command.cancel(1, INFANTRY, -1),
		Command.cancel(1, VEHICLES, 0),
		Command.cancel(1, World.TABS, 0),
		Command.cancel(1, -1, 0),
		Command.cancel(2, INFANTRY, 0),
	]
	for command: Command in cases:
		assert_bool(Production.apply_cancel(world, command)).is_false()
	var none: Command = Command.cancel(1, INFANTRY, 0)
	none.payload = PackedInt32Array([INFANTRY])
	assert_bool(Production.apply_cancel(world, none)).is_false()
	assert_array([world.credits[1], world.credits[2]]).is_equal([1900, 2000])
	assert_array(Rig.items(world, 1, INFANTRY)).is_equal([_rifle(world)])
	Rig.step(world, [Command.cancel(1, INFANTRY, 3)])
	assert_int(world.dropped_commands).is_equal(1)


## P70b's follow-up: the gate is Sim's, not the module's. The same Commands that the module
## accepts for a defeated player are dropped and counted by `Sim.step`, with no change to credits
## or queue.
func test_a_defeated_players_queue_and_cancel_are_dropped_by_the_gate() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	var queue: int = Rig.queue_of(1, INFANTRY)
	world.defeated_tick[1] = 1
	Rig.step(world, [Rig.queue(world, 1, "rocket_squad"), Command.cancel(1, INFANTRY, 0)])
	assert_int(world.dropped_commands).is_equal(2)
	assert_array([world.credits[1], world.queue_count[queue]]).is_equal([1900, 1])
	assert_array(Rig.items(world, 1, INFANTRY)).is_equal([_rifle(world)])
	# The module itself would take both: the drop above is the gate's.
	assert_bool(Production.apply_queue(world, Rig.queue(world, 1, "rocket_squad"))).is_true()
	assert_bool(Production.apply_cancel(world, Command.cancel(1, INFANTRY, 0))).is_true()
	assert_array([world.credits[1], world.queue_count[queue]]).is_equal([1600 + 100, 1])
	# The other player is still playing. With player 1 defeated by hand that player is the only one
	# left, so the first step above ended the match (plan row P76), and an ended match drops every
	# Command: this case is the gate's alone, so the end is taken back.
	assert_array([world.match_end_tick, world.winner]).is_equal([2, 2])
	world.match_end_tick = 0
	world.winner = 0
	Rig.step(world, [Rig.queue(world, 2, "rifle_squad")])
	assert_int(world.dropped_commands).is_equal(2)
	assert_int(world.credits[2]).is_equal(1900)


## A queue changes the credits and the queue arrays, which are the `players` section of the hash,
## and nothing else.
func test_a_queue_and_a_cancel_move_only_the_players_section_of_the_hash() -> void:
	var world: World = Rig.base()
	var names: PackedStringArray = World.hash_section_names()
	var before: PackedInt64Array = world.hash_parts()
	assert_bool(Production.apply_queue(world, Rig.queue(world, 1, "rifle_squad"))).is_true()
	var changed: Array[String] = []
	var after: PackedInt64Array = world.hash_parts()
	for index: int in names.size():
		if before[index] != after[index]:
			changed.append(names[index])
	assert_array(changed).is_equal(["players"])
	assert_bool(Production.apply_cancel(world, Command.cancel(1, INFANTRY, 0))).is_true()
	assert_array(world.hash_parts()).is_equal(before)
