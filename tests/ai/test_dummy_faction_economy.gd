extends GdUnitTestSuite
## The dummy's economy for each faction (plan rows P83d and P129, ADR 0020 section 4, ADR 0023
## section 6, ADR 0026 section 8): the start test of `test_dummy_economy.gd` run for the Derrick
## League and for the Lumen Accord. One dummy as player 1 of the faction start of `faction_rig.gd`
## (its Headquarters, two rifle squads, the rules' start credits, ore near, real fog; player 2
## passive and of the other faction, so the World holds both rosters), run once per faction for
## 3,600 ticks through the headless loop. Each faction's whole build order stands finished within a
## bound of ticks (counted), the sim drops nothing, the dummy places and queues only types of its
## own faction, one site at a time, and its harvesters bring ore in.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Factions: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const TICKS: int = 3600
## The ticks the wrongly paired dummy runs for.
const WRONG_TICKS: int = 900
## The ticks in which the whole build order must stand finished, per faction (measured 2,856 and
## 2,751 on the shipped defs, rules and rosters; the old queue path took 3,112 and 2,767). Each
## bound leaves room for a rebalance of a few percent and nothing more, so a dummy that dithers
## fails it.
const DONE_BOUND: Dictionary[String, int] = {"fossil": 3000, "renew": 2900}

var _runs: Dictionary[String, Run] = {}


## What one faction's run left: the World, the def, every Command sent and the counts below.
class Run:
	var world: World
	var def: AiDef
	var sent: Array[Command] = []
	## The tick at which the build order first stood finished, the most slots one think asked
	## about, the most items one unit queue held and the most sites under way at once.
	var done_tick: int = -1
	var max_tries: int = 0
	var max_queue: int = 0
	var max_sites: int = 0
	## The tile of the first PLACE and the slots the think that sent it asked about (-1, -1 and 0
	## while none was sent).
	var first_place: Vector2i = Vector2i(-1, -1)
	var first_place_slots: int = 0


func before() -> void:
	for faction: String in Factions.FACTIONS:
		_runs[faction] = _play(faction)


func test_every_building_of_the_build_order_stands_within_the_bound(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	assert_int(run.done_tick).is_greater(0)
	assert_int(run.done_tick).is_less_equal(DONE_BOUND[faction])
	# Exactly the build order: no building more.
	for id: String in _counts(run.def):
		assert_int(Rig.count_of(run.world, 1, id)).is_equal(_counts(run.def)[id])


func test_it_never_sends_a_command_the_sim_drops(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	assert_bool(run.sent.is_empty()).is_false()
	assert_int(run.world.dropped_commands).is_equal(0)
	assert_int(run.world.spawn_refused).is_equal(0)


func test_structures_are_placed_in_the_order_of_the_def_and_never_queued(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	var placed: Array[String] = []
	for command: Command in run.sent:
		var id: String = ""
		if command.payload.size() == 1:
			id = String(run.world.type_ids[command.payload[0]])
		if command.type == Command.Type.PLACE:
			placed.append(id)
		elif command.type == Command.Type.QUEUE:
			assert_str(id).is_equal(String(run.def.harvester_type))
	var expected: Array[String] = []
	expected.assign(run.def.build_order)
	assert_array(placed).is_equal(expected)


func test_one_site_is_under_way_at_a_time(faction: String, _test_parameters := _each()) -> void:
	var run: Run = _runs[faction]
	assert_int(run.max_sites).is_equal(1)
	assert_int(run.max_sites).is_equal(run.world.construction_sites_max)


func test_it_places_queues_and_owns_only_types_of_its_own_faction(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	# Both rosters are in the World, so a type of the other faction was there to be picked.
	assert_array(run.world.faction_ids).contains_exactly_in_any_order([&"fossil", &"renew"])
	var started: int = 0
	for command: Command in run.sent:
		if command.type == Command.Type.QUEUE or command.type == Command.Type.PLACE:
			started += 1
			assert_str(Factions.faction_of(run.world, command.payload[0])).is_equal(faction)
	assert_int(started).is_greater(run.def.build_order.size())
	assert_bool(Factions.owns_only(run.world, 1, faction)).is_true()


func test_it_keeps_two_harvesters_for_its_one_refinery_and_they_harvest(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	var harvester: String = String(run.def.harvester_type)
	var refinery: String = String(run.def.build_order[1])
	assert_int(Rig.count_of(run.world, 1, refinery)).is_equal(1)
	assert_int(Rig.count_of(run.world, 1, harvester)).is_equal(run.def.harvesters_wanted)
	# The refinery brought one; the dummy asked for the other and for no more.
	var asked: int = 0
	for command: Command in run.sent:
		if command.type == Command.Type.QUEUE:
			if String(run.world.type_ids[command.payload[0]]) == harvester:
				asked += 1
	assert_int(asked).is_equal(run.def.harvesters_wanted - 1)
	assert_int(run.world.stat_harvested[1]).is_greater(0)
	assert_int(run.world.stat_harvested[2]).is_equal(0)


func test_a_think_asks_about_no_more_slots_than_place_tries_and_no_queue_overfills(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	assert_int(run.max_tries).is_between(1, run.def.place_tries)
	# Units only: the one tanker the refinery did not bring, so this run never fills a queue (the pin
	# on the bound is `test_dummy_wishes::test_a_queue_holds_queue_target_items...`). The structures
	# tab has no queue to fill.
	assert_int(run.max_queue).is_between(1, run.def.queue_target)


func test_the_first_slot_that_placement_accepts_is_used(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	# Both Headquarters have their top-left tile at (6, 6), a 3 x 3 footprint and 7 tiles of sight
	# from the centre. The first slot, (2, 2), is not explored yet, the second, (6, 2), is: two slots
	# asked, and the dummy takes that one, not a later slot of the lattice.
	assert_object(run.first_place).is_equal(Vector2i(6, 2))
	assert_int(run.first_place_slots).is_equal(2)


@warning_ignore("integer_division")
func test_every_place_is_a_slot_of_the_lattice_round_the_headquarters(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	var places: Array[Vector2i] = []
	for command: Command in run.sent:
		if command.type == Command.Type.PLACE:
			places.append(Vector2i(command.target_x / 1000, command.target_y / 1000))
	assert_int(places.size()).is_equal(run.def.build_order.size())
	for tile: Vector2i in places:
		var from_hq: Vector2i = tile - Rig.HQ_1
		assert_int(from_hq.x % run.def.place_stride_tiles).is_equal(0)
		assert_int(from_hq.y % run.def.place_stride_tiles).is_equal(0)
		assert_bool(from_hq == Vector2i.ZERO).is_false()


func test_buildings_keep_a_free_tile_between_them(
	faction: String, _test_parameters := _each()
) -> void:
	var run: Run = _runs[faction]
	var world: World = run.world
	var rects: Array[Rect2i] = []
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_foot_w[world.type_index[row]] > 0:
			var size: Vector2i = Vector2i(
				world.type_foot_w[world.type_index[row]], world.type_foot_h[world.type_index[row]]
			)
			rects.append(Rect2i(world.footprint_origin(row), size))
	assert_int(rects.size()).is_equal(1 + run.def.build_order.size())
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			assert_bool(rects[first].grow(1).intersects(rects[second])).is_false()


func test_a_def_paired_with_the_other_factions_start_is_inert_and_sends_nothing_dropped() -> void:
	# The Skirmish route must pair a def with its own faction; a wrong pairing still must not send a
	# Command the sim drops: the dummy waits for a requirement it never owns (the other faction's
	# Headquarters) and only its defence may order its units.
	for faction: String in Factions.FACTIONS:
		var world: World = Factions.start(faction, Factions.other(faction))
		var loop: MatchLoop = Rig.loop_of(world)
		var wrong: DummyAi = Factions.dummy(Factions.other(faction), 1)
		var sent: Array[Command] = Rig.run(world, loop, [wrong], WRONG_TICKS)
		assert_array(Rig.economy(sent)).is_empty()
		assert_int(world.dropped_commands).is_equal(0)
		assert_bool(Factions.owns_only(world, 1, faction)).is_true()
		assert_int(_buildings(world, 1)).is_equal(1)


## gdUnit4's parameter sets: one case per faction (a method, since gdUnit4 writes into the sets).
func _each() -> Array[Array]:
	return [["fossil"], ["renew"]]


## One dummy of `faction` as player 1 for TICKS ticks.
@warning_ignore("integer_division")
func _play(faction: String) -> Run:
	var run: Run = Run.new()
	run.world = Factions.start(faction, Factions.other(faction))
	run.def = Factions.def_of(faction)
	var loop: MatchLoop = Rig.loop_of(run.world)
	var ai: DummyAi = Factions.dummy(faction, 1)
	for _step: int in TICKS:
		var sent: Array[Command] = Rig.tick(run.world, loop, [ai])
		run.sent.append_array(sent)
		run.max_tries = maxi(run.max_tries, ai.placement_tries)
		for command: Command in sent:
			if command.type == Command.Type.PLACE and run.first_place_slots == 0:
				run.first_place = Vector2i(command.target_x / 1000, command.target_y / 1000)
				run.first_place_slots = ai.placement_tries
		for queue: int in range(World.TABS + 1, World.TABS * 2):
			run.max_queue = maxi(run.max_queue, run.world.queue_count[queue])
		run.max_sites = maxi(run.max_sites, _sites(run.world))
		if run.done_tick < 0 and _stands(run):
			run.done_tick = run.world.tick
	return run


## How many buildings (rows with a footprint) `player` owns.
func _buildings(world: World, player: int) -> int:
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_foot_w[world.type_index[row]] > 0:
			found += 1
	return found


## How many of each type id the build order lists.
func _counts(def: AiDef) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for id: StringName in def.build_order:
		counts[String(id)] = counts.get(String(id), 0) + 1
	return counts


## How many sites (rows with work left) player 1 has.
func _sites(world: World) -> int:
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.build_left[row] > 0:
			found += 1
	return found


## Whether player 1 owns at least as many finished buildings of each type as the build order lists
## (a site is not one).
func _stands(run: Run) -> bool:
	var counts: Dictionary[String, int] = _counts(run.def)
	for id: String in counts:
		var type: int = Rig.type_of(run.world, id)
		var finished: int = 0
		for row: int in run.world.unit_count():
			if (
				run.world.owner[row] == 1
				and run.world.type_index[row] == type
				and run.world.build_left[row] == 0
			):
				finished += 1
		if finished < counts[id]:
			return false
	return true
