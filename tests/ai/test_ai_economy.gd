extends GdUnitTestSuite
## The opponent's economy manager (plan row P176, ADR 0030 sections 1, 4 and 6): hand-built Worlds
## read through `PlayerView` for the single rules (the steps and the "had" rule, power before a
## consumer, tankers per refinery per level, a lost building wanted again, the placement budget and
## its resume, the defence's slot, the reserve, the caps), and full matches of two `OpponentAi`s on
## the frozen arena for the loop's caps and for "no Command is dropped by the sim".

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const RICH: int = 100000
const MATCH_TICKS: int = 5400
const SHORT_TICKS: int = 2700
const NONE: int = -1

## One finished match per level, two players (fossil and renew) each, played in `before`.
var _matches: Dictionary[String, Dictionary] = {}
## A Normal match from the start credits, 2,700 ticks.
var _natural: Dictionary = {}


func before() -> void:
	for level: String in Rig.LEVELS:
		_matches[level] = _play(level, RICH, MATCH_TICKS)
	_natural = _play("normal", NONE, SHORT_TICKS)


# --- The single rules, on hand-built Worlds --------------------------------------------------


func test_a_step_waits_for_its_requirement_and_is_not_skipped() -> void:
	var world: World = _start()
	var economy: AiEconomy = _economy("fossil", "normal")
	var memory: AiMemory = _memory("fossil")
	var first: Array[Command] = _run(economy, memory, world, 1)
	# The plant is the first step; the refinery needs a finished plant, so the order waits for it
	# (it does not go on to the barracks) and the credits of the refinery are kept.
	assert_array(_queued_ids(first, world)).is_equal(["power_plant"])
	assert_int(memory.reserve_credits).is_equal(1400)
	# Applied, the plant is owned-or-queued: the next think wants the refinery, still waiting.
	AiRig.step(world, AiRig.loop_of(world), first)
	assert_array(_queued_ids(_run(economy, memory, world, 1), world)).is_empty()


func test_each_tiers_order_is_queued_in_order_with_power_ahead_of_consumers() -> void:
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
	var def: OpponentDef = _def_with_steps("fossil", ["barracks"])
	var economy: AiEconomy = AiEconomy.create(def, Rig.level_of("normal"), 1)
	var sent: Array[Command] = _run(economy, AiMemory.create(def), _tight(), 1)
	assert_array(_queued_ids(sent, _tight())).is_equal(["power_plant", "barracks"])
	# With no margin the consumer is wanted at once, ahead of any plant (the loop's refinery after
	# it is the one that wants a plant then).
	def.power_margin = 0
	economy = AiEconomy.create(def, Rig.level_of("normal"), 1)
	sent = _run(economy, AiMemory.create(def), _tight(), 1)
	assert_array(_queued_ids(sent, _tight()).slice(0, 1)).is_equal(["barracks"])


func test_tankers_per_refinery_follow_the_level() -> void:
	# (level, refineries, tankers owned, tankers wanted queued now); the vehicle queue holds two.
	var cases: Array = [
		["easy", 1, 0, 1],
		["normal", 1, 0, 2],
		["normal", 1, 1, 1],
		["normal", 1, 2, 0],
		["hard", 2, 2, 2],
		["hard", 2, 4, 0],
	]
	for row: Array in cases:
		# The base has two refineries; a case with one leaves the first of them out.
		var world: World = _base(int(row[2]), ["refinery"] if int(row[1]) == 1 else [])
		var sent: Array[Command] = _run(_economy("fossil", row[0]), _memory("fossil"), world, 1)
		var tankers: int = _queued_ids(sent, world).count("harvester")
		assert_int(tankers).override_failure_message("%s: %s" % [row, tankers]).is_equal(
			int(row[3])
		)


func test_a_lost_building_is_wanted_again_at_its_place_in_the_order() -> void:
	var world: World = _base(4, ["barracks"])
	var sent: Array[Command] = _run(_economy("fossil", "normal"), _memory("fossil"), world, 1)
	# Every other step is owned; the barracks, the third step, is the one missing.
	assert_array(_queued_ids(sent, world)).is_equal(["barracks"])
	# A lost second power plant is wanted again too, and that wish is first in the list.
	world = _base(4, ["power_plant"])
	sent = _run(_economy("fossil", "normal"), _memory("fossil"), world, 1)
	assert_array(_queued_ids(sent, world)).is_equal(["power_plant"])


func test_a_finished_base_wants_nothing_and_keeps_no_credits() -> void:
	var world: World = _base()
	var memory: AiMemory = _memory("fossil")
	memory.reserve_credits = 77
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world, 1)
	assert_array(_queued_ids(sent, world)).is_empty()
	assert_int(memory.reserve_credits).is_equal(0)


func test_the_credits_for_a_wish_that_waits_for_money_or_for_the_head_are_kept() -> void:
	var world: World = _start()
	var memory: AiMemory = _memory("fossil")
	world.credits[1] = 100
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world, 1)
	assert_array(sent).is_empty()
	assert_int(memory.reserve_credits).is_equal(300)
	# With a finished plant, money pays the refinery and the barracks; the next step, a second
	# plant, waits for the queue's room while the head is being built.
	world = _start()
	AiRig.give(world, 1, "power_plant", 10, 2)
	Power.run(world)
	sent = _run(_economy("fossil", "normal"), memory, world, 1)
	assert_array(_queued_ids(sent, world)).is_equal(["refinery", "barracks"])
	assert_int(memory.reserve_credits).is_equal(300)


func test_a_player_with_no_producer_sends_nothing() -> void:
	var world: World = _start()
	var loop: MatchLoop = AiRig.loop_of(world)
	AiRig.kill(world, loop, AiRig.row_of(world, 1, FactionRig.HQ["fossil"]))
	var memory: AiMemory = _memory("fossil")
	memory.reserve_credits = 5
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world, 1)
	assert_array(sent).is_empty()
	assert_int(memory.reserve_credits).is_equal(0)


func test_the_rules_caps_stop_a_queue_that_would_be_refused() -> void:
	var world: World = _start()
	world.building_cap = 1
	assert_array(_run(_economy("fossil", "normal"), _memory("fossil"), world, 1)).is_empty()
	world = _base()
	world.unit_cap = AiRig.count_of(world, 1, "rifle_squad")
	var sent: Array[Command] = _run(_economy("fossil", "normal"), _memory("fossil"), world, 1)
	assert_int(_queued_ids(sent, world).count("harvester")).is_equal(0)


func test_no_command_is_sent_past_the_think_budget() -> void:
	var world: World = _start()
	var memory: AiMemory = _memory("fossil")
	memory.commands_left = 1
	var sent: Array[Command] = _run(_economy("fossil", "normal"), memory, world, 1, false)
	assert_int(sent.size()).is_equal(1)
	assert_int(memory.commands_left).is_equal(0)
	memory.commands_left = 0
	assert_array(_run(_economy("fossil", "normal"), memory, world, 1, false)).is_empty()


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
		var sent: Array[Command] = _run(economy, memory, world, 1)
		# The rock leaves no slot: nothing is placed, and a search asks 8 slots and no more.
		assert_array(sent).is_empty()
		assert_int(economy.placement_tries).is_equal(def.place_tries_per_think)
		resumes.append(memory.spiral_resume)
	assert_array(resumes).is_equal([8, 16, 24, 32, 40, 48, 56, 0, 8, 16])
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
		places = _of_type(_run(economy, memory, world, 1), Command.Type.PLACE)
		thinks += 1
	# Slots 24 to 63 are out of reach of a lone Headquarters, so the search wraps to ring 1.
	assert_int(thinks).is_equal(6)
	assert_int(places.size()).is_equal(1)
	var view: PlayerView = PlayerView.of(world, 1)
	var head: int = view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots]
	assert_array(_tile_of(places[0])).is_equal(_nearest_ok(view, head, 24, Vector2i(NONE, NONE)))
	assert_int(memory.spiral_resume).is_equal(0)
	assert_int(economy.placed).is_equal(1)


func test_a_defence_goes_to_the_free_slot_nearest_the_staging_point() -> void:
	var staging: Vector2i = Vector2i(22, 6)
	var world: World = _start()
	AiRig.explore_all(world)
	_ready_head(world, 1, "defence_turret")
	var view: PlayerView = PlayerView.of(world, 1)
	var head: int = view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots]
	var memory: AiMemory = _memory("fossil")
	memory.staging_x = staging.x
	memory.staging_y = staging.y
	var near: Array[int] = _nearest_ok(view, head, 0, staging)
	var first: Array[int] = _nearest_ok(view, head, 0, Vector2i(NONE, NONE))
	assert_array(near).is_not_equal(first)
	var economy: AiEconomy = _economy("fossil", "normal")
	var found: Array[Command] = []
	var thinks: int = 0
	while found.is_empty() and thinks < 20:
		found = _of_type(_run(economy, memory, world, 1), Command.Type.PLACE)
		thinks += 1
	assert_int(found.size()).is_equal(1)
	assert_array(_tile_of(found[0])).is_equal(near)
	# Every search asks at most the budget, so the slot is found within as many thinks as it takes.
	assert_int(thinks).is_less_equal(8)
	# With no staging point the same head takes the first free slot of the spiral.
	var plain: AiMemory = _memory("fossil")
	var other: AiEconomy = _economy("fossil", "normal")
	found = []
	thinks = 0
	while found.is_empty() and thinks < 20:
		found = _of_type(_run(other, plain, world, 1), Command.Type.PLACE)
		thinks += 1
	assert_array(_tile_of(found[0])).is_equal(first)


# --- Matches ---------------------------------------------------------------------------------


func test_no_command_is_dropped_in_a_2700_tick_match_and_the_bases_grow() -> void:
	var world: World = _natural["world"]
	assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])
	for player: int in [1, 2]:
		assert_array([_natural["cut"][player - 1], _natural["work_max"][player - 1]]).is_equal(
			[0, 2]
		)
		assert_int(_natural["commands"][player - 1]).is_greater(8)
	assert_int(AiRig.count_of(world, 1, "power_plant")).is_greater(0)
	assert_int(AiRig.count_of(world, 2, "renew_refinery")).is_greater(0)


func test_no_command_is_dropped_in_a_full_match_at_any_level() -> void:
	for level: String in Rig.LEVELS:
		var world: World = _matches[level]["world"]
		assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])
		assert_array(_matches[level]["cut"]).is_equal([0, 0])


func test_the_loop_stops_at_the_levels_caps() -> void:
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


func test_the_tankers_follow_the_refineries_at_each_level() -> void:
	for level: String in Rig.LEVELS:
		var per: int = Rig.level_of(level).harvesters_per_refinery
		var world: World = _matches[level]["world"]
		var refineries: int = AiRig.count_of(world, 1, "refinery")
		assert_int(AiRig.count_of(world, 1, "harvester")).is_equal(per * refineries)
		refineries = AiRig.count_of(world, 2, "renew_refinery")
		assert_int(AiRig.count_of(world, 2, "renew_tanker")).is_equal(per * refineries)


func test_the_economy_holds_no_resource_and_draws_no_random_number() -> void:
	var economy: AiEconomy = _economy("renew", "hard")
	for property: Dictionary in economy.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = economy.get(property["name"])
		assert_bool(value is Resource or value is Node).is_false()
	var world: World = FactionRig.start("renew", "fossil")
	var memory: AiMemory = _memory("renew")
	var stream: DetRandom = DetRandom.create(5, DetRandom.STREAM_AI_BASE + 1)
	var twin: DetRandom = DetRandom.create(5, DetRandom.STREAM_AI_BASE + 1)
	economy.run(PlayerView.of(world, 1), memory, stream, [] as Array[Command])
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


func _economy(faction: String, level: String) -> AiEconomy:
	return AiEconomy.create(Rig.def_of(faction), Rig.level_of(level), 1)


func _memory(faction: String) -> AiMemory:
	return AiMemory.create(Rig.def_of(faction))


## One economy run on a fresh view of `world` for `player`; the memory's budget is the level's
## largest unless `open` is false (the caller set it).
func _run(
	economy: AiEconomy, memory: AiMemory, source: Variant, player: int, open: bool = true
) -> Array[Command]:
	var view: PlayerView = (
		source as PlayerView if source is PlayerView else PlayerView.of(source as World, player)
	)
	if open:
		memory.commands_left = 99
	var out: Array[Command] = []
	economy.run(view, memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + player), out)
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
## its tankers (`full`), minus one of each type in `lacking`, with 100,000 credits.
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
## `credits` each (NONE: the start credits). Returns the World and what the suites read.
func _play(level: String, credits: int, ticks: int) -> Dictionary:
	var world: World = _start()
	if credits != NONE:
		world.credits[1] = credits
		world.credits[2] = credits
	var loop: MatchLoop = AiRig.loop_of(world)
	var controllers: Array = [
		Rig.opponent("fossil", level, 1, 1),
		Rig.opponent("renew", level, 2, 1),
	]
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
