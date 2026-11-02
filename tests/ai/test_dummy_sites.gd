extends GdUnitTestSuite
## The dummy and the sites it builds (plan row P129, ADR 0026 sections 4, 5 and 8). A structure is
## placed first and rises on the spot, so the dummy must treat a site as the sim does: it counts
## for the build order (a site is not placed twice, a lost one is wanted again), fills one of the
## `construction_sites_max` places, and counts for nothing else: not a requirement that is owned,
## not a producer, not a refinery. The sim drops a Command that breaks one of these, so each case
## also checks `dropped_commands` where it goes through the loop. The placement itself is in
## test_dummy_placement.gd and the whole build in test_dummy_economy.gd.
##
## A site made by hand is a given building whose `build_left` is set: the view reads that column and
## nothing else (the cases that need the sim's own progress place the site through a PLACE).

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
## The rig's map argument for "the shipped map" (a typed array: the rig is reached through a
## preloaded script, so an untyped literal would not match its parameter).
const NO_ROWS: Array[String] = []


func test_a_second_site_waits_until_the_first_is_finished() -> void:
	var world: World = Rig.start()
	world.credits[1] = 20000
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant", "power_plant", "power_plant"]), 1)
	var places: Array[int] = []
	for _step: int in 600:
		var sites: int = _sites(world, 1)
		for command: Command in Rig.tick(world, loop, [ai]):
			if command.type == Command.Type.PLACE:
				# Nothing was under way when it was sent.
				assert_int(sites).is_equal(0)
				places.append(world.tick)
	assert_int(places.size()).is_equal(3)
	# Each plant takes its build time (150 ticks) before the next one is placed.
	assert_int(places[1] - places[0]).is_greater_equal(150)
	assert_int(places[2] - places[1]).is_greater_equal(150)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(3)


func test_the_limit_is_the_rules_number_and_a_think_sends_one_place() -> void:
	var world: World = Rig.start(NO_ROWS, _rules_with_sites(2))
	Rig.explore_all(world)
	world.credits[1] = 20000
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant", "power_plant", "power_plant"]), 1)
	# Two sites may be under way, but one PLACE a think: the view does not show the site that this
	# think starts, so a second PLACE would ask about the slot of the first.
	var first: Array[Command] = _think(world, ai)
	assert_int(first.size()).is_equal(1)
	Rig.step(world, loop, first)
	var second: Array[Command] = _think(world, ai)
	assert_int(second.size()).is_equal(1)
	assert_bool(_places(first)[0] != _places(second)[0]).is_true()
	Rig.step(world, loop, second)
	assert_int(_sites(world, 1)).is_equal(2)
	assert_array(_think(world, ai)).is_empty()
	assert_int(world.dropped_commands).is_equal(0)


func test_a_limit_of_zero_places_nothing() -> void:
	var world: World = Rig.start(NO_ROWS, _rules_with_sites(0))
	assert_int(PlayerView.of(world, 1).construction_sites_max).is_equal(0)
	assert_array(_think(world, Rig.dummy(1))).is_empty()


func test_a_site_is_not_placed_twice_and_a_destroyed_one_is_wanted_again() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant"]), 1)
	Rig.step(world, loop, _think(world, ai))
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(1)
	# The plant is had as a site: nothing more, think after think.
	for _again: int in 3:
		assert_array(_think(world, ai)).is_empty()
		Rig.run(world, loop, [], 15)
	# Destroyed while it rises: lost with its price, and wanted again at its place in the order.
	Rig.kill(world, loop, Rig.row_of(world, 1, "power_plant"))
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(0)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_places(sent)).is_not_empty()
	Rig.step(world, loop, sent)
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(1)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_site_is_had_though_the_limit_would_allow_another() -> void:
	# Room for two sites and one plant in the order: only "a site is had" stops a second plant.
	var world: World = Rig.start(NO_ROWS, _rules_with_sites(2))
	Rig.explore_all(world)
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant"]), 1)
	Rig.step(world, loop, _think(world, ai))
	assert_int(_sites(world, 1)).is_equal(1)
	assert_array(_think(world, ai)).is_empty()
	Rig.run(world, loop, [], 15)
	assert_array(_think(world, ai)).is_empty()
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(1)


func test_a_unit_wish_behind_a_rising_site_is_queued_in_a_later_think() -> void:
	var world: World = _barracks_start()
	var loop: MatchLoop = Rig.loop_of(world)
	var order: Array[String] = ["power_plant", "power_plant", "rifle_squad", "rifle_squad"]
	order.append("rifle_squad")
	var ai: DummyAi = Rig.ai_of(Rig.def_with(order), 1)
	# The credits pay the second plant and not the squad behind it; the site rises, and a think
	# later the credits are there. The plant is had (a site), so the squad is next, not the plant.
	world.credits[1] = 300
	var first: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(first))).is_equal(["power_plant"])
	Rig.step(world, loop, first)
	assert_int(_sites(world, 1)).is_equal(1)
	world.credits[1] = 1000
	var later: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(later))).is_equal(["rifle_squad"])
	Rig.step(world, loop, later)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_structure_that_finds_no_slot_holds_the_units_behind_it() -> void:
	var world: World = _barracks_start()
	Rig.explore_all(world)
	# One slot may be asked about, and a tanker stands on it: the plant has no place to go.
	Rig.add_unit_of(world, 1, "harvester", 2500, 2500)
	var def: AiDef = Rig.def_with(["power_plant", "power_plant", "rifle_squad", "rifle_squad"])
	def.build_order.append(&"rifle_squad")
	def.place_tries = 1
	var ai: DummyAi = Rig.ai_of(def, 1)
	# The order holds: the squad behind the plant is waited for, not queued in its stead.
	assert_array(_think(world, ai)).is_empty()
	assert_int(ai.placement_tries).is_equal(1)
	# The tanker drives off: the plant is placed and the squad follows in the same think.
	world.pos_x[world.index_of(Rig.ids_of(world, 1, "harvester")[0])] = 30000
	var sent: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(sent))).is_equal(["power_plant", "rifle_squad"])
	Rig.step(world, Rig.loop_of(world), sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_queue_target_of_zero_still_places_structures() -> void:
	var world: World = Rig.start()
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.queue_target = 0
	# The target is the size of a unit queue: structures have none, and are placed one at a time.
	var sent: Array[Command] = _think(world, Rig.ai_of(def, 1))
	assert_array(_names(world, _starts(sent))).is_equal(["power_plant"])
	Rig.step(world, Rig.loop_of(world), sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_requirement_is_owned_only_once_its_site_is_finished() -> void:
	# Room for two sites, so that the site limit is not what holds the refinery back.
	var world: World = Rig.start(NO_ROWS, _rules_with_sites(2))
	world.credits[1] = 20000
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant", "refinery"]), 1)
	Rig.step(world, loop, _think(world, ai))
	var plant: int = Rig.row_of(world, 1, "power_plant")
	Rig.run(world, loop, [], 100)
	assert_int(world.build_left[plant]).is_greater(0)
	assert_int(_sites(world, 1)).is_less(world.construction_sites_max)
	# The refinery needs a power plant; the plant is a site, and the credits are there.
	assert_array(_think(world, ai)).is_empty()
	Rig.run(world, loop, [], 60)
	assert_int(world.build_left[plant]).is_equal(0)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(sent))).is_equal(["refinery"])
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_barracks_site_is_no_producer() -> void:
	var world: World = _barracks_start()
	var barracks: int = Rig.row_of(world, 1, "barracks")
	world.build_left[barracks] = 300
	var squads: Array[String] = ["rifle_squad", "rifle_squad", "rifle_squad"]
	var ai: DummyAi = Rig.ai_of(Rig.def_with(squads), 1)
	# The sim drops a QUEUE with no complete producer, so the dummy sends none (and no tank either).
	assert_array(_think(world, ai)).is_empty()
	world.build_left[barracks] = 0
	assert_array(_names(world, _starts(_think(world, ai)))).is_equal(["rifle_squad"])


func test_a_vehicle_factory_site_builds_no_harvester() -> void:
	var world: World = _economy_start()
	var factory: int = Rig.row_of(world, 1, "vehicle_factory")
	world.build_left[factory] = 300
	var ai: DummyAi = Rig.ai_of(Rig.def_with([]), 1)
	assert_array(_think(world, ai)).is_empty()
	world.build_left[factory] = 0
	assert_array(_names(world, _starts(_think(world, ai)))).is_equal(["harvester", "harvester"])


func test_a_refinery_site_wants_no_harvester() -> void:
	var world: World = _economy_start()
	var refinery: int = Rig.row_of(world, 1, "refinery")
	world.build_left[refinery] = 300
	var ai: DummyAi = Rig.ai_of(Rig.def_with([]), 1)
	# A site takes no tanker (ADR 0026 section 4): harvesters queued for it would idle and cost the
	# credits that the next structure needs.
	assert_array(_think(world, ai)).is_empty()
	world.build_left[refinery] = 0
	assert_array(_names(world, _starts(_think(world, ai)))).is_equal(["harvester", "harvester"])


func test_a_cancelled_row_holds_a_place_among_the_sites_until_it_leaves() -> void:
	# The sim counts a row marked -1 (CANCEL_BUILD, P128b) against the limit until REMOVE takes it
	# out, so the dummy does too. The view never shows one today (the AI thinks before `loop.step`,
	# and a cancel and its REMOVE happen in one step): this is the rule for the day it does.
	var world: World = Rig.start()
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant", "power_plant"]), 1)
	Rig.give(world, 1, "power_plant", 10, 2)
	# One plant stands and the second is wanted: placed.
	assert_array(_names(world, _starts(_think(world, ai)))).is_equal(["power_plant"])
	# Marked -1, the standing one is neither finished nor gone: it holds the place of a site, so the
	# second plant waits. (Counted as finished, or not counted, it would be placed at once.)
	world.build_left[Rig.row_of(world, 1, "power_plant")] = -1
	assert_array(_think(world, ai)).is_empty()


func test_a_site_goes_on_without_the_headquarters_and_the_dummy_sends_nothing_more() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.give(world, 1, "barracks", 20, 6)
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(Rig.def_with(["power_plant", "power_plant"]), 1)
	Rig.step(world, loop, _think(world, ai))
	# The dead Headquarters leaves the table, so the site is followed by its id, not its row.
	var plant: int = world.unit_id[Rig.row_of(world, 1, "power_plant")]
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	assert_int(world.defeated_tick[1]).is_equal(0)
	assert_int(world.build_left[world.index_of(plant)]).is_greater(0)
	# No complete building produces structures now, and the plant's own requirement, the
	# Headquarters, is gone too (`test_no_headquarters_with_the_requirement_met_places_nothing`
	# isolates the producer rule).
	assert_array(_think(world, ai)).is_empty()
	# Low power (the barracks draws, the plant is still a site) halves the pace: 300 ticks, and 250
	# more cover it.
	var sent: Array[Command] = Rig.run(world, loop, [ai], 550)
	assert_array(Rig.economy(sent)).is_empty()
	# The site went on (ADR 0026, Michael's answer 4 A) and was finished; the dummy sent nothing.
	assert_int(world.build_left[world.index_of(plant)]).is_equal(0)
	assert_int(Rig.count_of(world, 1, "power_plant")).is_equal(1)
	assert_int(world.dropped_commands).is_equal(0)


func test_no_headquarters_with_the_requirement_met_places_nothing() -> void:
	var world: World = Rig.start()
	Rig.explore_all(world)
	Rig.give(world, 1, "power_plant", 10, 2)
	Rig.give(world, 1, "barracks", 20, 6)
	world.credits[1] = 20000
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	assert_int(world.defeated_tick[1]).is_equal(0)
	# The refinery is next, its requirement (a finished power plant) is owned and the credits are
	# there: only the missing structures producer stops the PLACE, which the sim would drop
	# (ADR 0026 section 2, rule 2).
	var sent: Array[Command] = _think(
		world, Rig.ai_of(Rig.def_with(["power_plant", "refinery"]), 1)
	)
	assert_array(sent).is_empty()
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_player_left_with_only_a_producer_site_is_defeated_and_sends_nothing() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var barracks: int = Rig.give(world, 1, "barracks", 20, 6)
	world.build_left[world.index_of(barracks)] = 5000
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	# A barracks that is still a site produces nothing and keeps nobody alive; the dummy counts it
	# as no producer either, so not even its defence orders its squads.
	assert_int(world.defeated_tick[1]).is_greater(0)
	var sent: Array[Command] = _think(world, Rig.dummy(1), true)
	assert_array(sent).is_empty()
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_think_that_needs_every_pass_starts_them_all() -> void:
	var world: World = _economy_start()
	Rig.explore_all(world)
	Rig.give(world, 1, "barracks", 24, 2)
	var order: Array[String] = ["power_plant", "power_plant", "rifle_squad", "rifle_squad"]
	order.append_array(["rifle_squad", "rifle_squad"])
	var def: AiDef = Rig.def_with(order)
	def.harvesters_wanted = 3
	var sent: Array[Command] = _think(world, Rig.ai_of(def, 1))
	# The most one think can start: the vehicle queue's room in tankers (2 of the 3 wanted), the one
	# PLACE (the second plant) and the infantry queue's room in squads (2 of the 4 the order lists,
	# the start has two).
	var expected: Array[String] = ["harvester", "harvester", "power_plant"]
	expected.append_array(["rifle_squad", "rifle_squad"])
	assert_array(_names(world, _starts(sent))).is_equal(expected)
	Rig.step(world, Rig.loop_of(world), sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_unit_wish_behind_the_structure_just_placed_is_queued_in_the_same_think() -> void:
	var world: World = _barracks_start()
	var loop: MatchLoop = Rig.loop_of(world)
	# The plant and the barracks are owned, and so are two rifle squads: the order wants a second
	# plant and a third squad.
	var order: Array[String] = ["power_plant", "power_plant", "rifle_squad", "rifle_squad"]
	order.append("rifle_squad")
	var ai: DummyAi = Rig.ai_of(Rig.def_with(order), 1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(sent))).is_equal(["power_plant", "rifle_squad"])
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(_think(world, ai)).is_empty()


func test_a_structure_wish_held_back_by_the_site_limit_holds_the_order() -> void:
	var world: World = _barracks_start()
	var loop: MatchLoop = Rig.loop_of(world)
	# A third plant is wanted behind the second, and the squads behind that: while the second rises
	# the third is waited for, not skipped, so the squads wait too (ADR 0020 section 4: the order
	# holds). The first think places the second plant and, with the third held back by the site
	# limit, queues no squad.
	var order: Array[String] = ["power_plant", "power_plant", "power_plant", "rifle_squad"]
	order.append("rifle_squad")
	order.append("rifle_squad")
	var ai: DummyAi = Rig.ai_of(Rig.def_with(order), 1)
	var sent: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(sent))).is_equal(["power_plant"])
	Rig.step(world, loop, sent)
	assert_array(_think(world, ai)).is_empty()
	# The second plant is finished: the third is placed, and the squads, no longer behind a wish
	# that waits, are queued in the same think.
	Rig.run(world, loop, [], 160)
	assert_int(_sites(world, 1)).is_equal(0)
	var next: Array[Command] = _think(world, ai)
	assert_array(_names(world, _starts(next))).is_equal(["power_plant", "rifle_squad"])
	Rig.step(world, loop, next)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_seen_enemy_site_is_a_threat_like_any_enemy_building() -> void:
	var world: World = Rig.start()
	Rig.give(world, 2, "defence_turret", 11, 7)
	world.build_left[Rig.row_of(world, 2, "defence_turret")] = 500
	Rig.settle(world, Rig.loop_of(world))
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.defend_radius_tiles = 5
	var found: Array[Vector2i] = []
	for command: Command in _think(world, Rig.ai_of(def, 1), true):
		if command.type == Command.Type.ATTACK_MOVE:
			found.append(Vector2i(command.target_x, command.target_y))
	# The turret stands on the tile (11, 7): the point is its centre.
	assert_array(found).is_equal([Vector2i(11500, 7500)])


## The shipped rules with `count` as `construction_sites_max` (a copy: the shipped file is not
## touched).
func _rules_with_sites(count: int) -> RulesDef:
	var rules: RulesDef = (load(Rig.RULES_PATH) as RulesDef).duplicate() as RulesDef
	rules.construction_sites_max = count
	return rules


## One think of `ai` on a fresh view of its player: its economy commands, or with `all` every
## command (the ATTACK_MOVE of the defence are judged in test_dummy_defence.gd).
func _think(world: World, ai: AiController, all: bool = false) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, ai.player_id), sent)
	return sent if all else Rig.economy(sent)


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


## How many sites (rows with work left) `player` has.
func _sites(world: World, player: int) -> int:
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == player and world.build_left[row] > 0:
			found += 1
	return found


## The start with plenty of credits and, for player 1, a power plant and a barracks beside the
## Headquarters (given, finished: no rule is asked).
func _barracks_start() -> World:
	var world: World = Rig.start()
	Rig.give(world, 1, "power_plant", 10, 2)
	Rig.give(world, 1, "barracks", 24, 2)
	world.credits[1] = 20000
	return world


## The start with plenty of credits and, for player 1, a power plant, a refinery and a vehicle
## factory beside the Headquarters (given, finished) and no harvester.
func _economy_start() -> World:
	var world: World = Rig.start()
	Rig.give(world, 1, "power_plant", 10, 2)
	Rig.give(world, 1, "refinery", 10, 10)
	Rig.give(world, 1, "vehicle_factory", 2, 14)
	world.credits[1] = 20000
	return world
