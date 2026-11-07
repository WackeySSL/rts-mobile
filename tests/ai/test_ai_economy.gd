extends GdUnitTestSuite
## The opponent's economy manager (plan row P176, ADR 0030 sections 1, 4 and 6): hand-built Worlds
## read through `PlayerView` for the single rules (the steps and the "had" rule, power before a
## consumer, tankers per refinery per level, a lost building wanted again, the placement budget and
## its resume, the defence's slot, the reserve, the caps), and full matches of two `OpponentAi`s on
## the frozen arena for the loop's caps and for "no Command is dropped by the sim".

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const EconomyOnly: GDScript = preload("res://tests/ai/support/economy_only.gd")

const RICH: int = 100000
const MATCH_TICKS: int = 5400
const SHORT_TICKS: int = 2700
const NONE: int = -1

## One finished match per level, two players (fossil and renew) each, played in `before` by the
## economy alone (production and the army would change the caps and the tankers: units fight, a
## forward defence dies).
var _matches: Dictionary[String, Dictionary] = {}
## A Hard match of the full controllers with 100,000 credits each, for "no Command is dropped".
var _full: Dictionary = {}
## A Normal match from the start credits, 2,700 ticks.
var _natural: Dictionary = {}


func before() -> void:
	for level: String in Rig.LEVELS:
		_matches[level] = _play(level, RICH, MATCH_TICKS, true)
	_full = _play("hard", RICH, MATCH_TICKS)
	_natural = _play("normal", NONE, SHORT_TICKS)


# --- The single rules, on hand-built Worlds --------------------------------------------------


func test_a_step_waits_for_its_requirement_and_is_not_skipped() -> void:
	var world: World = _start()
	var economy: AiEconomy = _economy("fossil", "normal")
	var memory: AiMemory = _memory("fossil")
	var first: Array[Command] = _run(economy, memory, world)
	# The plant is the first step; the refinery needs a finished plant, so the order waits for it
	# (it does not go on to the barracks) and the credits of the refinery are kept.
	assert_array(_queued_ids(first, world)).is_equal(["power_plant"])
	# The refinery's price is kept besides the plant's own spend.
	assert_int(memory.reserve_credits).is_equal(
		_cost(world, "power_plant") + _cost(world, "refinery")
	)
	# Applied, the plant is owned-or-queued: the next think wants the refinery, still waiting.
	AiRig.step(world, AiRig.loop_of(world), first)
	assert_array(_queued_ids(_run(economy, memory, world), world)).is_empty()


func test_each_tiers_order_is_queued_in_order_apart_from_the_added_plants() -> void:
	for level: String in Rig.LEVELS:
		for faction: String in Rig.FACTIONS:
			var order: Array[StringName] = (
				Rig.def_of(faction).build_orders[Rig.level_of(level).build_order_tier].steps
			)
			var queued: Array[String] = _structures_queued(_matches[level], faction)
			var plant: String = "power_plant" if faction == "fossil" else "renew_power"
			var without_power: Array[String] = []
			for id: String in queued:
				if id != plant:
					without_power.append(id)
			var wanted: Array[String] = []
			for id: StringName in order:
				if id != StringName(plant):
					wanted.append(String(id))
			# The order's types come in the order's sequence (a power plant may be added before
			# a consumer); the loop's extras (a refinery, a factory, a defence) come after it.
			assert_array(without_power.slice(0, wanted.size())).is_equal(wanted)
			assert_int(queued.count(plant)).is_greater_equal(order.count(StringName(plant)))


func test_power_is_queued_before_a_consumer_would_leave_the_surplus_under_the_margin() -> void:
	# A plant (100) and the Headquarters (20) make 120; a refinery, a factory and a radar use 100.
	# A barracks (20) would leave 0, under the margin of 20, so a plant comes first; the queued
	# plant counts, so the barracks follows in the same think.
	var tight: World = _tight()
	var def: OpponentDef = _def_with_steps("fossil", ["barracks"])
	var economy: AiEconomy = AiEconomy.create(def, Rig.level_of("normal"), 1)
	var sent: Array[Command] = _run(economy, AiMemory.create(def), tight)
	assert_array(_queued_ids(sent, tight)).is_equal(["power_plant", "barracks"])
	# With no margin the consumer is wanted at once, ahead of any plant (the loop's refinery after
	# it is the one that wants a plant then).
	def.power_margin = 0
	economy = AiEconomy.create(def, Rig.level_of("normal"), 1)
	sent = _run(economy, AiMemory.create(def), tight)
	assert_array(_queued_ids(sent, tight).slice(0, 1)).is_equal(["barracks"])


func test_the_loop_queues_power_while_the_surplus_is_under_the_margin() -> void:
	var world: World = _base()
	var view: PlayerView = PlayerView.of(world, 1)
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.power_margin = view.power_made - view.power_used + 1
	var economy: AiEconomy = AiEconomy.create(def, Rig.level_of("normal"), 1)
	var sent: Array[Command] = _run(economy, AiMemory.create(def), world)
	assert_array(_queued_ids(sent, world)).is_equal(["power_plant"])
	assert_int(economy.passes).is_equal(1)
	def.power_margin -= 1  # At the margin: nothing (the rule is `<`).
	economy = AiEconomy.create(def, Rig.level_of("normal"), 1)
	var memory: AiMemory = AiMemory.create(def)
	memory.reserve_credits = 77
	sent = _run(economy, memory, world)
	assert_array(_queued_ids(sent, world)).is_empty()
	# A finished base wants nothing and keeps no credits.
	assert_int(memory.reserve_credits).is_equal(0)


func test_tankers_per_refinery_follow_the_level() -> void:
	# (level, refineries, tankers owned); the vehicle queue holds `queue_target` items.
	var cases: Array = [
		["easy", 1, 0],
		["normal", 1, 0],
		["normal", 1, 1],
		["normal", 1, 2],
		["hard", 2, 2],
		["hard", 2, 4]
	]
	for row: Array in cases:
		# The base has two refineries; a case with one leaves the first of them out.
		var world: World = _base(int(row[2]), ["refinery"] if int(row[1]) == 1 else [])
		var per: int = Rig.level_of(row[0]).harvesters_per_refinery
		var wanted: int = clampi(
			per * int(row[1]) - int(row[2]), 0, Rig.def_of("fossil").queue_target
		)
		var sent: Array[Command] = _run(_economy("fossil", row[0]), _memory("fossil"), world)
		var tankers: int = _queued_ids(sent, world).count("harvester")
		assert_int(tankers).override_failure_message("%s: %s" % [row, tankers]).is_equal(wanted)


func test_a_lost_building_is_wanted_again_at_its_place_in_the_order() -> void:
	var world: World = _base(4, ["barracks"])
	var sent: Array[Command] = _run(_economy("fossil", "normal"), _memory("fossil"), world)
	# Every other step is owned; the barracks, the third step, is the one missing.
	assert_array(_queued_ids(sent, world)).is_equal(["barracks"])
	# A lost second power plant is wanted again too, and that wish is first in the list.
	world = _base(4, ["power_plant"])
	sent = _run(_economy("fossil", "normal"), _memory("fossil"), world)
	assert_array(_queued_ids(sent, world)).is_equal(["power_plant"])


func test_the_reserve_is_what_the_economy_queued_plus_the_price_it_keeps() -> void:
	var world: World = _start()
	var memory: AiMemory = _memory("fossil")
	var plant: int = _cost(world, "power_plant")
	world.credits[1] = plant - 200
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world)
	assert_array(sent).is_empty()
	assert_int(memory.reserve_credits).is_equal(_cost(world, "power_plant"))
	# With a finished plant, money pays the refinery and the barracks (queued: 1,800); the next
	# step, a second plant, waits for the queue's room while the head is being built, and 300 is
	# kept for it. Production must leave 1,800 + 300, so nothing is left for it.
	world = _start()
	AiRig.give(world, 1, "power_plant", 10, 2)
	Power.run(world)
	sent = _run(_economy("fossil", "normal"), memory, world)
	assert_array(_queued_ids(sent, world)).is_equal(["refinery", "barracks"])
	var view: PlayerView = PlayerView.of(world, 1)
	var queued: int = _cost(world, "refinery") + _cost(world, "barracks")
	assert_int(memory.reserve_credits).is_equal(queued + plant)
	assert_int(view.credits - memory.reserve_credits).is_equal(2000 - 1800 - 300)


func test_a_tanker_that_waits_for_money_keeps_its_price() -> void:
	var world: World = _base(0, ["refinery"])
	world.credits[1] = 1000
	var memory: AiMemory = _memory("fossil")
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world)
	assert_array(sent).is_empty()
	assert_int(memory.reserve_credits).is_equal(_cost(world, "harvester"))
	# With money for one tanker: it is queued and counts in the reserve, besides the second's price.
	world.credits[1] = _cost(world, "harvester") + 300
	sent = _run(_economy("fossil", "normal"), memory, world)
	assert_array(_queued_ids(sent, world)).is_equal(["harvester"])
	assert_int(memory.reserve_credits).is_equal(2 * _cost(world, "harvester"))


func test_a_full_queue_keeps_credits_for_the_next_structure_only_while_its_head_builds() -> void:
	# Plant given and a queue of two (a ready plant, a barracks): the refinery waits for room.
	# Ready head that cannot be placed (rock): nothing is kept, the credits would sit idle.
	var blocked: World = _queue_of_two(true)
	var memory: AiMemory = _memory("fossil")
	assert_array(_run(_economy("fossil", "normal"), memory, blocked)).is_empty()
	assert_int(memory.reserve_credits).is_equal(0)
	# Ready head that is placed in this run: the view is stale, the room comes next tick, so the
	# refinery's price is kept.
	var open: World = _queue_of_two(false)
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, open)
	assert_int(_of_type(sent, Command.Type.PLACE).size()).is_equal(1)
	assert_int(memory.reserve_credits).is_equal(_cost(open, "refinery"))


func test_without_a_producer_nothing_is_sent_and_a_missing_requirement_keeps_nothing() -> void:
	var world: World = _start()
	var loop: MatchLoop = AiRig.loop_of(world)
	AiRig.kill(world, loop, AiRig.row_of(world, 1, FactionRig.HQ["fossil"]))
	var memory: AiMemory = _memory("fossil")
	memory.reserve_credits = 5
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world)
	assert_array(sent).is_empty()
	assert_int(memory.reserve_credits).is_equal(0)
	# A barracks lives but the Headquarters, which a plant needs, is neither owned nor queued: the
	# plant's price is not kept (nothing could ever be built for it).
	AiRig.give(world, 1, "barracks", 2, 2)
	memory.reserve_credits = 5
	assert_array(_run(_economy("fossil", "normal"), memory, world)).is_empty()
	assert_int(memory.reserve_credits).is_equal(0)


func test_the_rules_caps_hold_back_what_could_not_be_placed_or_spawned() -> void:
	var world: World = _start()
	world.building_cap = 1
	assert_array(_run(_economy("fossil", "normal"), _memory("fossil"), world)).is_empty()
	# Two refineries and two tankers: Normal wants two more. A cap of units + 2 allows none, units
	# + 3 allows one (the run counts what it queued).
	for room: int in [2, 3]:
		world = _base(2)
		var units: int = AiRig.count_of(world, 1, "rifle_squad") + 2
		world.unit_cap = units + room - 2
		var sent: Array[Command] = _run(_economy("fossil", "normal"), _memory("fossil"), world)
		assert_int(_queued_ids(sent, world).count("harvester")).is_equal(room - 2)


func test_no_command_is_sent_past_the_think_budget() -> void:
	var world: World = _start()
	var memory: AiMemory = _memory("fossil")
	memory.commands_left = 1
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world, false)
	assert_int(sent.size()).is_equal(1)
	assert_int(memory.commands_left).is_equal(0)
	memory.commands_left = 0
	assert_array(_run(_economy("fossil", "normal"), memory, world, false)).is_empty()
	# A ready head is not placed without budget either.
	AiRig.explore_all(world)
	_ready_head(world, 1, "power_plant")
	assert_array(_run(_economy("fossil", "normal"), memory, world, false)).is_empty()


# --- Placement -------------------------------------------------------------------------------


func test_a_search_asks_at_most_the_budget_and_resumes_where_it_stopped() -> void:
	var def: OpponentDef = Rig.def_of("fossil")
	var scenario: ScenarioDef = FactionRig.scenario("fossil", "renew")
	scenario.map.rows = PackedStringArray(AiRig.rows(true))
	var world: World = World.from_scenario(scenario)
	_ready_head(world, 1, "power_plant")
	var economy: AiEconomy = _economy("fossil", "normal")
	var memory: AiMemory = _memory("fossil")
	var resumes: Array[int] = []
	for _think: int in 10:
		var sent: Array[Command] = _run(economy, memory, world)
		# The rock leaves no slot: nothing is placed, and a search asks 8 slots and no more.
		assert_array(sent).is_empty()
		assert_int(economy.placement_tries).is_equal(def.place_tries_per_think)
		resumes.append(memory.spiral_resume)
	var expected: Array[int] = []
	for think: int in 10:
		expected.append((think + 1) * def.place_tries_per_think % def.spiral_slots)
	assert_array(resumes).is_equal(expected)
	assert_int(economy.placed).is_equal(0)


func test_a_place_goes_to_the_first_free_slot_and_the_next_search_starts_again_there() -> void:
	var world: World = _start()
	AiRig.explore_all(world)
	_ready_head(world, 1, "power_plant")
	var memory: AiMemory = _memory("fossil")
	memory.spiral_resume = 24
	var economy: AiEconomy = _economy("fossil", "normal")
	var places: Array[Command] = []
	var thinks: int = 0
	while places.is_empty() and thinks < 12:
		places = _of_type(_run(economy, memory, world), Command.Type.PLACE)
		thinks += 1
	# Slots 24 to 63 are out of reach of a lone Headquarters, so the search wraps to ring 1.
	var tries: int = Rig.def_of("fossil").place_tries_per_think
	var span: int = Rig.def_of("fossil").spiral_slots - 24
	assert_int(thinks).is_equal((span + tries - 1) / tries + 1)
	assert_int(places.size()).is_equal(1)
	var view: PlayerView = PlayerView.of(world, 1)
	var head: int = view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots]
	assert_array(_tile_of(places[0])).is_equal(_nearest_ok(view, head, 24, Vector2i(NONE, NONE)))
	assert_int(memory.spiral_resume).is_equal(0)
	assert_int(economy.placed).is_equal(1)
	# A search that places in its first think starts over at slot 0 as well (slots 4 to 11 hold
	# ring 1's last cells).
	memory.spiral_resume = 4
	_ready_head(world, 1, "power_plant")
	economy = _economy("fossil", "normal")
	places = _of_type(_run(economy, memory, world), Command.Type.PLACE)
	assert_int(places.size()).is_equal(1)
	assert_int(memory.spiral_resume).is_equal(0)


func test_a_defence_goes_to_the_free_slot_nearest_the_staging_point() -> void:
	var near: Array[int] = _place_with("defence_turret", Vector2i(22, 6))
	var first: Array[int] = _place_with("defence_turret", Vector2i(NONE, NONE))
	# The Headquarters' top-left tile is (6, 6): slot (1, 0) is (10, 6), slot (-1, -1) is (2, 2).
	assert_array(near).is_equal([10, 6])
	assert_array(first).is_equal([2, 2])
	assert_array(near).is_equal(_oracle("defence_turret", Vector2i(22, 6)))
	# Only a defence goes toward the staging point: a plant still takes the first free slot.
	assert_array(_place_with("power_plant", Vector2i(22, 6))).is_equal([2, 2])
	# The base is round the first Headquarters, even with a second one later in the rows.
	assert_array(_place_with("power_plant", Vector2i(NONE, NONE), true)).is_equal([2, 2])


func test_a_new_search_order_starts_at_its_first_slot() -> void:
	# Two searches on rock under one staging point leave the resume index at 16.
	var scenario: ScenarioDef = FactionRig.scenario("fossil", "renew")
	scenario.map.rows = PackedStringArray(AiRig.rows(true))
	var rock: World = World.from_scenario(scenario)
	_ready_head(rock, 1, "defence_turret")
	var memory: AiMemory = _memory("fossil")
	memory.staging_x = 2
	memory.staging_y = 22
	var economy: AiEconomy = _economy("fossil", "normal")
	for _think: int in 2:
		_run(economy, memory, rock)
	assert_int(memory.spiral_resume).is_equal(16)
	# The staging point moves on the open start: the nearest slot is found from the new order's
	# first slot, not from index 16 of the old one.
	var world: World = _start()
	AiRig.explore_all(world)
	_ready_head(world, 1, "defence_turret")
	memory.staging_x = 22
	memory.staging_y = 6
	var places: Array[Command] = []
	for _think: int in 20:
		places = _of_type(_run(economy, memory, world), Command.Type.PLACE)
		if not places.is_empty():
			break
	assert_int(places.size()).is_equal(1)
	assert_array(_tile_of(places[0])).is_equal([10, 6])


# --- Matches ---------------------------------------------------------------------------------


func test_no_command_is_dropped_in_a_2700_tick_match_and_the_bases_grow() -> void:
	var world: World = _natural["world"]
	assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])
	for player: int in [1, 2]:
		assert_int(_natural["cut"][player - 1]).is_equal(0)
		# The view's pass and the economy's (later slots add their own passes).
		assert_int(_natural["work_max"][player - 1]).is_between(2, 3)
		assert_int(_natural["commands"][player - 1]).is_greater(8)
	assert_int(AiRig.count_of(world, 1, "power_plant")).is_greater(0)
	assert_int(AiRig.count_of(world, 2, "renew_refinery")).is_greater(0)
	# The full controllers with production and a rich start drop nothing either.
	var rich: World = _full["world"]
	assert_array([rich.dropped_commands, rich.spawn_refused]).is_equal([0, 0])
	assert_array(_full["cut"]).is_equal([0, 0])


func test_the_loop_stops_at_the_levels_caps_and_no_command_is_dropped() -> void:
	for level: String in Rig.LEVELS:
		var played: World = _matches[level]["world"]
		assert_array([played.dropped_commands, played.spawn_refused]).is_equal([0, 0])
		assert_array(_matches[level]["cut"]).is_equal([0, 0])
	var ids: Dictionary[String, Dictionary] = {
		"fossil":
		{"refinery": "refinery", "factory": "vehicle_factory", "defence": "defence_turret"},
		"renew":
		{"refinery": "renew_refinery", "factory": "renew_factory", "defence": "renew_defence"},
	}
	for level: String in Rig.LEVELS:
		var level_def: AiDifficultyDef = Rig.level_of(level)
		var world: World = _matches[level]["world"]
		for at: int in 2:
			var faction: String = Rig.FACTIONS[at]
			var order: Array[StringName] = (
				Rig.def_of(faction).build_orders[level_def.build_order_tier].steps
			)
			var caps: Array[int] = [
				level_def.refineries_max, level_def.factories_max, level_def.defences_max
			]
			var roles: Array[String] = ["refinery", "factory", "defence"]
			for role: int in 3:
				var id: String = ids[faction][roles[role]]
				var expected: int = maxi(caps[role], order.count(StringName(id)))
				var built: int = AiRig.count_of(world, at + 1, id)
				(
					assert_int(built)
					. override_failure_message(
						"%s %s %s: %d of %d" % [level, faction, id, built, expected]
					)
					. is_equal(expected)
				)
			# The tankers follow the refineries: the level's number for each.
			var tanker: String = "harvester" if faction == "fossil" else "renew_tanker"
			var refineries: int = AiRig.count_of(world, at + 1, ids[faction]["refinery"])
			assert_int(AiRig.count_of(world, at + 1, tanker)).is_equal(
				level_def.harvesters_per_refinery * refineries
			)


func test_the_economy_holds_no_resource_and_draws_no_random_number() -> void:
	var economy: AiEconomy = _economy("renew", "hard")
	for property: Dictionary in economy.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = economy.get(property["name"])
		assert_bool(value is Resource or value is Node).is_false()
	var world: World = FactionRig.start("renew", "fossil")
	var memory: AiMemory = _memory("renew")
	memory.commands_left = 8
	var stream: DetRandom = DetRandom.create(5, DetRandom.STREAM_AI_BASE + 1)
	var twin: DetRandom = DetRandom.create(5, DetRandom.STREAM_AI_BASE + 1)
	var out: Array[Command] = []
	economy.run(PlayerView.of(world, 1), memory, stream, out)
	assert_array(out).is_not_empty()
	assert_array(stream.state()).is_equal(twin.state())


# --- Helpers ---------------------------------------------------------------------------------


## The fossil-against-renew start with the power totals the first tick would give.
func _start() -> World:
	var world: World = FactionRig.start("fossil", "renew")
	Power.run(world)
	return world


## A start whose player 1 has a finished plant and three consumers: surplus 20.
func _tight() -> World:
	var world: World = _start()
	AiRig.explore_all(world)
	world.credits[1] = RICH
	for row: Array in [
		["power_plant", 10, 2],
		["refinery", 10, 10],
		["vehicle_factory", 2, 12],
		["fossil_radar", 22, 2]
	]:
		AiRig.give(world, 1, row[0], row[1], row[2])
	for at: int in 2:
		AiRig.add_unit_of(world, 1, "harvester", 12000 + at * 600, 14000)
	Power.run(world)
	return world


## The price of the type `id` in `world`.
func _cost(world: World, id: String) -> int:
	return world.type_cost[AiRig.type_of(world, id)]


## A start where player 1 owns a finished plant and its STRUCTURES queue holds a ready plant and a
## barracks (room for no more); on rock, nothing can be placed.
func _queue_of_two(blocked: bool) -> World:
	var scenario: ScenarioDef = FactionRig.scenario("fossil", "renew")
	if blocked:
		scenario.map.rows = PackedStringArray(AiRig.rows(true))
	var world: World = World.from_scenario(scenario)
	AiRig.explore_all(world)
	world.credits[1] = RICH
	AiRig.give(world, 1, "power_plant", 10, 2)
	_ready_head(world, 1, "power_plant")
	var queue: int = World.TABS + World.Tab.STRUCTURES
	world.queue_type[queue * world.queue_slots + 1] = AiRig.type_of(world, "barracks")
	world.queue_count[queue] = 2
	Power.run(world)
	return world


## The tile a ready `id` head is placed on, with the staging point set unless it is (-1, -1).
func _place_with(id: String, staging: Vector2i, second_hq: bool = false) -> Array[int]:
	var world: World = _start()
	if second_hq:
		AiRig.give(world, 1, "headquarters", 30, 10)
	AiRig.explore_all(world)
	_ready_head(world, 1, id)
	var memory: AiMemory = _memory("fossil")
	if staging.x >= 0:
		memory.staging_x = staging.x
		memory.staging_y = staging.y
	var economy: AiEconomy = _economy("fossil", "normal")
	var found: Array[Command] = []
	for _think: int in 20:
		found = _of_type(_run(economy, memory, world), Command.Type.PLACE)
		if not found.is_empty():
			break
	assert_int(found.size()).is_equal(1)
	return _tile_of(found[0])


## What the rule says for an `id` head: `_nearest_ok` on a fresh view.
func _oracle(id: String, staging: Vector2i) -> Array[int]:
	var world: World = _start()
	AiRig.explore_all(world)
	_ready_head(world, 1, id)
	var view: PlayerView = PlayerView.of(world, 1)
	return _nearest_ok(
		view, view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots], 0, staging
	)


func _economy(faction: String, level: String) -> AiEconomy:
	return AiEconomy.create(Rig.def_of(faction), Rig.level_of(level), 1)


func _memory(faction: String) -> AiMemory:
	return AiMemory.create(Rig.def_of(faction))


## One economy run on a fresh view of `world` for player 1; the memory's budget is 99 Commands
## unless `open` is false (the caller set it).
func _run(economy: AiEconomy, memory: AiMemory, world: World, open: bool = true) -> Array[Command]:
	if open:
		memory.commands_left = 99
	var out: Array[Command] = []
	economy.run(
		PlayerView.of(world, 1), memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1), out
	)
	return out


## A copy of `faction`'s opponent def whose three build orders are `steps`.
func _def_with_steps(faction: String, steps: Array) -> OpponentDef:
	var def: OpponentDef = Rig.def_of(faction).duplicate() as OpponentDef
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	for id: String in steps:
		order.steps.append(StringName(id))
	var orders: Array[AiBuildOrderDef] = [order, order, order]
	def.build_orders = orders
	return def


## The type ids of the QUEUE commands in `sent`, in order.
func _queued_ids(sent: Array[Command], world: World) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


func _of_type(sent: Array[Command], type: int) -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in sent:
		if command.type == type:
			found.append(command)
	return found


## The tile that a PLACE names, as [column, line].
@warning_ignore("integer_division")
func _tile_of(command: Command) -> Array[int]:
	return [
		command.target_x / PlayerView.MILLI_PER_TILE, command.target_y / PlayerView.MILLI_PER_TILE
	]


## A fossil World whose player 1 owns every building of the Normal order, an extra refinery, and
## `tankers` tankers, minus one of each type in `lacking`, with 100,000 credits.
func _base(tankers: int = 4, lacking: Array = []) -> World:
	var world: World = _start()
	AiRig.explore_all(world)
	world.credits[1] = RICH
	var spots: Array = [
		["power_plant", 10, 2],
		["power_plant", 13, 2],
		["power_plant", 16, 2],
		["refinery", 10, 10],
		["barracks", 2, 2],
		["vehicle_factory", 2, 12],
		["fossil_radar", 22, 2],
		["defence_turret", 22, 8],
		["defence_turret", 22, 12],
		["fossil_strike", 22, 20],
		["refinery", 30, 2],
	]
	var skipped: Array[String] = []
	for row: Array in spots:
		var id: String = row[0]
		if lacking.has(id) and not skipped.has(id):
			skipped.append(id)
			continue
		# The first of a repeated type is the one that stays missing; a lost plant leaves two.
		AiRig.give(world, 1, id, row[1], row[2])
	for at: int in tankers:
		AiRig.add_unit_of(world, 1, "harvester", 12000 + at * 600, 14000)
	Power.run(world)
	return world


## Makes the head of `player`'s STRUCTURES queue `id`, built and waiting for a PLACE.
func _ready_head(world: World, player: int, id: String) -> void:
	var type: int = AiRig.type_of(world, id)
	var queue: int = player * World.TABS + World.Tab.STRUCTURES
	world.queue_type[queue * world.queue_slots] = type
	world.queue_count[queue] = 1
	world.queue_progress[queue] = world.type_build_ticks[type] * Production.PROGRESS_PER_TICK


## The [column, line] of the first slot, from slot `from`, that `view` accepts for `head`, or with a
## staging point (not (-1, -1)) the accepted slot nearest it, the lower slot first among equals.
@warning_ignore("integer_division")
func _nearest_ok(view: PlayerView, head: int, from: int, staging: Vector2i) -> Array[int]:
	var def: OpponentDef = Rig.def_of("fossil")
	var cells: PackedInt32Array = PlacementSpiral.cells(def.spiral_slots)
	var origin: Vector2i = AiRig.HQ_1
	var best: Array[int] = []
	var least: int = -1
	var count: int = cells.size() / 2
	for step: int in count:
		var slot: int = (from + step) % count if staging.x < 0 else step
		var col: int = origin.x + cells[slot * 2] * def.place_stride_tiles
		var line: int = origin.y + cells[slot * 2 + 1] * def.place_stride_tiles
		if view.placement(head, col, line) != Placement.Reason.OK:
			continue
		if staging.x < 0:
			return [col, line]
		var distance: int = (
			(col - staging.x) * (col - staging.x) + (line - staging.y) * (line - staging.y)
		)
		if least < 0 or distance < least:
			least = distance
			best = [col, line]
	return best


## The structure types player of `faction` queued, in order, over the whole match of `played`.
func _structures_queued(played: Dictionary, faction: String) -> Array[String]:
	return played["structures"][Rig.FACTIONS.find(faction)]


## Plays fossil (player 1) against renew (player 2), both on `level`, for `ticks` ticks with
## `credits` each (NONE: the start credits), the economy alone when `economy_only`. Returns the
## World and what the suites read.
func _play(level: String, credits: int, ticks: int, economy_only: bool = false) -> Dictionary:
	var world: World = _start()
	if credits != NONE:
		world.credits[1] = credits
		world.credits[2] = credits
	var loop: MatchLoop = AiRig.loop_of(world)
	var controllers: Array = [
		Rig.opponent("fossil", level, 1, 1),
		Rig.opponent("renew", level, 2, 1),
	]
	if economy_only:
		for at: int in 2:
			var alone: Variant = EconomyOnly.new()
			alone.copy_from(controllers[at])
			controllers[at] = alone
	var sent: Array[Command] = AiRig.run(world, loop, controllers, ticks)
	var structures: Array = [[] as Array[String], [] as Array[String]]
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			var type: int = command.payload[0]
			if world.type_tab[type] == World.Tab.STRUCTURES:
				structures[command.player_id - 1].append(String(world.type_ids[type]))
	var found: Dictionary = {
		"world": world,
		"structures": structures,
		"cut": [],
		"work_max": [],
		"commands": [],
	}
	for controller: OpponentAi in controllers:
		found["cut"].append(controller.commands_cut)
		found["work_max"].append(controller.work_max)
		found["commands"].append(controller.commands)
	return found
