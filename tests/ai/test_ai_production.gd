extends GdUnitTestSuite
## The opponent's production manager (plan row P178, ADR 0030 sections 1, 4, 5 and 6): hand-built
## Worlds read through `PlayerView` for the single rules (both unit queues held at `queue_target`,
## only queueable types drawn, the credits above the economy's reserve, the weighted draw over a
## fixed seed, `counter_percent` and its reaction age, the scout of `scout_wanted`, the Command
## budget), and Normal matches of two `OpponentAi`s for the scout and "no Command is dropped".

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const RICH: int = 100000
const NONE: int = -1
const DRAWS: int = 300
## The roles' fossil types, in `OpponentDef.Role` order.
const ROLE_IDS: Array[String] = ["rifle_squad", "rocket_squad", "heavy_tank", "artillery"]
## The first tick of a Normal match (seed 1, fossil against renew) at which player 1's scout moves:
## the economy takes the whole income for the build order, production spends from tick 4,200.
const SCOUT_MOVE_TICK: int = 4510
const MATCH_TICKS: int = 5400

## The first-draw counts per role of 300 runs of seed 1's stream, per level (fixed by the seed).
const EXPECTED_COUNTS: Dictionary[String, Array] = {
	"easy": [149, 114, 37, 0],
	"normal": [116, 77, 77, 30],
	"hard": [68, 73, 106, 53],
}
const EXPECTED_SHIFTED: Dictionary[String, Array] = {
	"heavy": [67, 150, 61, 22],
	"infantry": [158, 59, 61, 22],
}

# --- The queues -------------------------------------------------------------------------------


func test_both_unit_queues_are_held_at_the_queue_target() -> void:
	var world: World = _world(RICH, true)
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, _memory("fossil"), world)
	var target: int = Rig.def_of("fossil").queue_target
	assert_int(sent.size()).is_equal(2 * target)
	(
		assert_array(
			[_in_tab(sent, world, World.Tab.INFANTRY), _in_tab(sent, world, World.Tab.VEHICLES)]
		)
		. is_equal([target, target])
	)
	assert_int(production.passes).is_equal(1)
	# Applied, both queues are full: the next think sends nothing and makes no pass.
	AiRig.step(world, AiRig.loop_of(world), sent)
	assert_array(_run(production, _memory("fossil"), world)).is_empty()
	assert_int(production.passes).is_equal(0)
	# One finished unit leaves room for one more of its tab.
	world.queue_count[World.TABS + World.Tab.INFANTRY] -= 1
	sent = _run(production, _memory("fossil"), world)
	assert_array([sent.size(), _in_tab(sent, world, World.Tab.INFANTRY)]).is_equal([1, 1])


func test_only_types_that_can_be_queued_are_drawn() -> void:
	# No radar: the artillery's requirement is missing, so it is never drawn, whatever its weight.
	var world: World = _world(RICH, false)
	var production: AiProduction = _production("fossil", "hard")
	var seen: Array[int] = _first_draws(production, world, _memory("fossil"))
	assert_int(seen[3]).is_equal(0)
	assert_int(seen[0] + seen[1] + seen[2]).is_equal(DRAWS)
	# With the radar it is drawn.
	var radar: Array[int] = _first_draws(
		_production("fossil", "hard"), _world(RICH, true), _memory("fossil")
	)
	assert_int(radar[3]).is_greater(0)
	# No barracks: no infantry. No factory: no vehicle. No producer at all: nothing, no pass work
	# beyond the census, and the stream is not touched.
	var no_barracks: World = _world(RICH, true)
	AiRig.kill(no_barracks, AiRig.loop_of(no_barracks), AiRig.row_of(no_barracks, 1, "barracks"))
	var sent: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), no_barracks)
	for id: String in _ids(sent, no_barracks):
		assert_array(["heavy_tank", "artillery"]).contains([id])
	var bare: World = _world(RICH, true)
	var loop: MatchLoop = AiRig.loop_of(bare)
	AiRig.kill(bare, loop, AiRig.row_of(bare, 1, "barracks"))
	AiRig.kill(bare, loop, AiRig.row_of(bare, 1, "vehicle_factory"))
	var stream: DetRandom = _stream()
	var twin: DetRandom = _stream()
	var none: Array[Command] = []
	_production("fossil", "normal").run(
		PlayerView.of(bare, 1), _open(_memory("fossil")), stream, none
	)
	assert_array(none).is_empty()
	assert_array(stream.state()).is_equal(twin.state())


func test_a_type_over_the_unit_cap_is_not_queued() -> void:
	var world: World = _world(RICH, true)
	var def: OpponentDef = Rig.def_of("fossil")
	# Two rifle squads live. With the cap at them plus the room left for the economy's units,
	# nothing is queued; one more place is one more unit.
	var units: int = AiRig.count_of(world, 1, "rifle_squad")
	world.unit_cap = units + def.queue_target
	assert_array(_run(_production("fossil", "normal"), _memory("fossil"), world)).is_empty()
	world.unit_cap += 1
	assert_int(_run(_production("fossil", "normal"), _memory("fossil"), world).size()).is_equal(1)


# --- The draw ----------------------------------------------------------------------------------


func test_the_role_draw_follows_the_weights_over_a_fixed_seed() -> void:
	var def: OpponentDef = Rig.def_of("fossil")
	for level: String in Rig.LEVELS:
		var tier: int = Rig.level_of(level).build_order_tier
		var counts: Array[int] = _first_draws(
			_production("fossil", level), _world(RICH, true), _memory("fossil")
		)
		var total: int = 0
		for role: int in 4:
			total += def.role_weight(tier, role)
		var line: Array[int] = []
		for role: int in 4:
			var share: int = DRAWS * def.role_weight(tier, role) / total
			line.append(counts[role])
			# Within 8 percentage points of the def's share (the draw is random, the seed fixed).
			assert_int(counts[role]).is_between(maxi(share - 24, 0), share + 24)
		assert_array(line).is_equal(EXPECTED_COUNTS[level])
	# The weak tier never builds artillery: its weight is 0.
	assert_int(EXPECTED_COUNTS["easy"][3]).is_equal(0)


func test_the_same_seed_draws_the_same_units_and_a_draw_uses_the_ai_stream_only() -> void:
	var world: World = _world(RICH, true)
	var first: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	var again: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_array(_ids(first, world)).is_equal(_ids(again, world))
	var other: Array[String] = []
	for seed: int in range(2, 12):
		var out: Array[Command] = []
		_production("fossil", "normal").run(
			PlayerView.of(world, 1),
			_open(_memory("fossil")),
			DetRandom.create(seed, DetRandom.STREAM_AI_BASE + 1),
			out
		)
		other.append(",".join(_ids(out, world)))
	assert_int(other.size()).is_equal(10)
	# Ten other seeds do not all draw alike.
	var distinct: Dictionary[String, bool] = {}
	for line: String in other:
		distinct[line] = true
	assert_int(distinct.size()).is_greater(1)
	var production: AiProduction = _production("fossil", "normal")
	for property: Dictionary in production.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = production.get(property["name"])
		assert_bool(value is Resource or value is Node).is_false()


# --- Counters ----------------------------------------------------------------------------------


func test_the_mix_shifts_toward_the_counter_of_the_armour_most_seen() -> void:
	# Seen: heavy armour, old enough. The rocket (anti-vehicle role 1) does 100 against it, the most.
	var world: World = _world(RICH, true)
	world.tick = 1000
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	var memory: AiMemory = _seen(world, {"heavy_tank": 5}, 0)
	var shifted: Array[int] = _first_draws(_production("fossil", "normal"), world, memory)
	var def: OpponentDef = Rig.def_of("fossil")
	var level: AiDifficultyDef = Rig.level_of("normal")
	var total: int = 0
	for role: int in 4:
		total += def.role_weight(level.build_order_tier, role)
	var base: int = def.role_weight(level.build_order_tier, 1)
	var expected: int = (
		DRAWS
		* (base * (100 - level.counter_percent) + total * level.counter_percent)
		/ (100 * total)
	)
	assert_int(shifted[1]).is_greater(plain[1])
	assert_int(shifted[1]).is_between(expected - 24, expected + 24)
	assert_array(shifted).is_equal(EXPECTED_SHIFTED["heavy"])
	# Infantry seen: the rifle does 100 against it (role 0).
	memory = _seen(world, {"rifle_squad": 5}, 0)
	var infantry: Array[int] = _first_draws(_production("fossil", "normal"), world, memory)
	assert_int(infantry[0]).is_greater(plain[0])
	assert_array(infantry).is_equal(EXPECTED_SHIFTED["infantry"])
	# The class most seen wins: three rifles against one tank counts infantry.
	memory = _seen(world, {"rifle_squad": 3, "heavy_tank": 1}, 0)
	assert_array(_first_draws(_production("fossil", "normal"), world, memory)).is_equal(infantry)
	# Hard shifts more than Normal.
	var hard: Array[int] = _first_draws(
		_production("fossil", "hard"), world, _seen(world, {"heavy_tank": 5}, 0)
	)
	var hard_plain: Array[int] = _first_draws(
		_production("fossil", "hard"), world, _memory("fossil")
	)
	assert_int(hard[1] - hard_plain[1]).is_greater(shifted[1] - plain[1])


func test_equal_counters_go_to_the_lower_role() -> void:
	# Light armour seen: the rocket (role 1) and the heavy cannon (role 2) both do 100 against it.
	var world: World = _world(RICH, true)
	world.tick = 1000
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	var seen: Array[int] = _first_draws(
		_production("fossil", "normal"), world, _seen(world, {"light_tank": 5}, 0)
	)
	assert_int(seen[1]).is_greater(plain[1])
	assert_int(seen[2]).is_less(plain[2])


func test_a_sighting_younger_than_the_reaction_age_does_not_shift_the_mix() -> void:
	var world: World = _world(RICH, true)
	var level: AiDifficultyDef = Rig.level_of("normal")
	world.tick = 1000
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	# First seen one tick short of the age: the mix is the plain one, exactly.
	var young: AiMemory = _seen(world, {"heavy_tank": 5}, world.tick - level.reaction_ticks + 1)
	assert_array(_first_draws(_production("fossil", "normal"), world, young)).is_equal(plain)
	# At the age it counts.
	var old: AiMemory = _seen(world, {"heavy_tank": 5}, world.tick - level.reaction_ticks)
	assert_array(_first_draws(_production("fossil", "normal"), world, old)).is_not_equal(plain)
	# A young sighting of the other class does not outvote an old one: the old tank decides.
	var mixed: AiMemory = _seen(world, {"heavy_tank": 1, "rifle_squad": 9}, 0)
	mixed.seen_first_tick[world.type_ids.find(&"rifle_squad")] = world.tick
	assert_array(_first_draws(_production("fossil", "normal"), world, mixed)).is_equal(
		_first_draws(_production("fossil", "normal"), world, _seen(world, {"heavy_tank": 1}, 0))
	)


func test_easy_draws_on_the_plain_weights_whatever_it_has_seen() -> void:
	var world: World = _world(RICH, true)
	world.tick = 1000
	var plain: Array[int] = _first_draws(_production("fossil", "easy"), world, _memory("fossil"))
	var seen: Array[int] = _first_draws(
		_production("fossil", "easy"), world, _seen(world, {"heavy_tank": 9}, 0)
	)
	assert_array(seen).is_equal(plain)
	assert_int(Rig.level_of("easy").counter_percent).is_equal(0)


func test_buildings_seen_do_not_count_toward_the_armour_class() -> void:
	var world: World = _world(RICH, true)
	world.tick = 1000
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	var seen: Array[int] = _first_draws(
		_production("fossil", "normal"), world, _seen(world, {"headquarters": 9, "barracks": 9}, 0)
	)
	assert_array(seen).is_equal(plain)


# --- Credits and Commands ----------------------------------------------------------------------


func test_production_spends_at_most_the_credits_above_the_reserve() -> void:
	var world: World = _world(0, true)
	var rifle: int = _cost(world, "rifle_squad")
	var memory: AiMemory = _memory("fossil")
	# Credits equal to the reserve: nothing, however cheap a unit is.
	world.credits[1] = 700
	memory.reserve_credits = 700
	assert_array(_run(_production("fossil", "normal"), memory, world)).is_empty()
	# Credits under the reserve: the same (never a negative budget).
	memory.reserve_credits = 900
	assert_array(_run(_production("fossil", "normal"), memory, world)).is_empty()
	# One unit of room above it: at most that is spent, and only a unit that fits is drawn.
	for room: int in [100, 250, 400, 1000, 5000]:
		world.credits[1] = 700 + room
		memory.reserve_credits = 700
		var sent: Array[Command] = _run(_production("fossil", "normal"), memory, world)
		var spent: int = 0
		for command: Command in sent:
			spent += world.type_cost[command.payload[0]]
		(
			assert_int(spent)
			. override_failure_message("room %d spent %d" % [room, spent])
			. is_less_equal(room)
		)
	world.credits[1] = 700 + rifle
	assert_array(_ids(_run(_production("fossil", "normal"), memory, world), world)).is_equal(
		["rifle_squad"]
	)
	# The economy's reserve with its own queue: a case where it queued in the same think.
	world = _world(2000, true)
	memory.reserve_credits = 2000 - rifle
	assert_array(_ids(_run(_production("fossil", "normal"), memory, world), world)).is_equal(
		["rifle_squad"]
	)


func test_every_queue_checks_the_command_budget_before_it_is_sent() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	memory.commands_left = 1
	var sent: Array[Command] = _run(_production("fossil", "normal"), memory, world, false)
	assert_int(sent.size()).is_equal(1)
	assert_int(memory.commands_left).is_equal(0)
	memory.commands_left = 0
	assert_array(_run(_production("fossil", "normal"), memory, world, false)).is_empty()
	# The scout checks it too, before anything is recorded.
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var production: AiProduction = _production("fossil", "normal")
	assert_array(_run(production, memory, world, false)).is_empty()
	assert_int(production.scouts_queued).is_equal(0)


# --- The scout ---------------------------------------------------------------------------------


func test_a_wanted_scout_is_queued_ahead_of_the_draw_and_counts_toward_the_queue() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world, true)
	var ids: Array[String] = _ids(sent, world)
	assert_str(ids[0]).is_equal("light_tank")
	assert_int(ids.count("light_tank")).is_equal(1)
	assert_int(production.scouts_queued).is_equal(1)
	# The vehicle tab has queue_target places: the scout takes one, so one more vehicle at most.
	var target: int = Rig.def_of("fossil").queue_target
	assert_int(_in_tab(sent, world, World.Tab.VEHICLES)).is_equal(target)
	assert_int(sent.size()).is_equal(2 * target)


func test_a_queued_scout_with_the_field_still_set_gets_no_second_scout() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	var scout: int = AiRig.type_of(world, "light_tank")
	memory.scout_wanted = scout
	var loop: MatchLoop = AiRig.loop_of(world)
	var production: AiProduction = _production("fossil", "normal")
	AiRig.step(world, loop, _run(production, memory, world))
	# The scout is in the vehicle queue and the field is still set (it does not live yet).
	assert_int(production.scouts_queued).is_equal(1)
	for _think: int in 5:
		var sent: Array[Command] = _run(production, memory, world)
		assert_int(_ids(sent, world).count("light_tank")).is_equal(0)
		AiRig.step(world, loop, sent)
	assert_int(production.scouts_queued).is_equal(1)
	# Even with a draw that could pick it: no role holds the scout type.
	assert_array(production.role_queued).is_not_equal(PackedInt32Array([0, 0, 0, 0]))


func test_a_scout_that_cannot_be_paid_yet_holds_the_credits_and_goes_when_they_are_there() -> void:
	var world: World = _world(0, true)
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var cost: int = _cost(world, "light_tank")
	world.credits[1] = cost - 1
	var production: AiProduction = _production("fossil", "normal")
	# Cheap units would be affordable, but the scout comes first: nothing is spent on them.
	assert_array(_run(production, memory, world)).is_empty()
	world.credits[1] = cost
	assert_array(_ids(_run(production, memory, world), world)).is_equal(["light_tank"])
	# The reserve is respected for the scout as for any unit.
	memory.reserve_credits = 1
	assert_array(_run(_production("fossil", "normal"), memory, world)).is_empty()


func test_a_scout_is_not_queued_without_a_factory_and_the_draw_goes_on() -> void:
	var world: World = _world(RICH, true)
	AiRig.kill(world, AiRig.loop_of(world), AiRig.row_of(world, 1, "vehicle_factory"))
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world)
	assert_int(production.scouts_queued).is_equal(0)
	assert_int(sent.size()).is_equal(Rig.def_of("fossil").queue_target)
	for id: String in _ids(sent, world):
		assert_array(["rifle_squad", "rocket_squad"]).contains([id])


func test_a_scout_waiting_in_a_queue_with_room_left_gets_no_second_scout() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	var scout: int = AiRig.type_of(world, "light_tank")
	memory.scout_wanted = scout
	# One scout waits in the vehicle queue (room for one more): the field is still set, so
	# no second scout is queued, and the draw fills the room with a role's unit.
	var queue: int = World.TABS + World.Tab.VEHICLES
	world.queue_type[queue * world.queue_slots] = scout
	world.queue_count[queue] = 1
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world)
	assert_int(_ids(sent, world).count("light_tank")).is_equal(0)
	assert_int(production.scouts_queued).is_equal(0)
	assert_int(_in_tab(sent, world, World.Tab.VEHICLES)).is_equal(1)


func test_no_scout_is_queued_when_the_field_is_none_or_a_structure() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	var production: AiProduction = _production("fossil", "normal")
	assert_int(_ids(_run(production, memory, world), world).count("light_tank")).is_equal(0)
	memory.scout_wanted = AiRig.type_of(world, "barracks")
	assert_int(_ids(_run(production, memory, world), world).count("barracks")).is_equal(0)
	memory.scout_wanted = 9999
	assert_int(_run(production, memory, world).size()).is_equal(4)
	assert_int(production.scouts_queued).is_equal(0)


# --- Matches -----------------------------------------------------------------------------------


func test_a_normal_match_scouts_once_and_the_sim_drops_nothing() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	Power.run(world)
	var loop: MatchLoop = AiRig.loop_of(world)
	var controllers: Array = [
		Rig.opponent("fossil", "normal", 1, 1), Rig.opponent("renew", "normal", 2, 1)
	]
	var first_move: int = NONE
	var kinds: Dictionary[int, bool] = {}
	for _tick: int in MATCH_TICKS:
		var tick: int = world.tick
		var sent: Array[Command] = AiRig.tick(world, loop, controllers)
		for command: Command in sent:
			if command.type == Command.Type.MOVE and command.player_id == 1 and first_move == NONE:
				first_move = tick
			if (
				command.type == Command.Type.QUEUE
				and world.type_tab[command.payload[0]] != World.Tab.STRUCTURES
			):
				kinds[command.payload[0]] = true
	assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])
	for controller: OpponentAi in controllers:
		assert_int(controller.commands_cut).is_equal(0)
		assert_int(controller.work_max).is_less_equal(3)
		assert_int(controller.production.queued).is_greater(5)
	assert_int((controllers[0] as OpponentAi).scouts).is_equal(1)
	assert_int(first_move).is_equal(SCOUT_MOVE_TICK)
	assert_int(kinds.size()).is_greater(3)


# --- Helpers -----------------------------------------------------------------------------------


## A fossil start: player 1 owns a barracks and a vehicle factory (and the radar when `radar`),
## `credits`, the fog open.
func _world(credits: int, radar: bool) -> World:
	var world: World = FactionRig.start("fossil", "renew")
	AiRig.explore_all(world)
	AiRig.give(world, 1, "power_plant", 10, 2)
	AiRig.give(world, 1, "barracks", 2, 2)
	AiRig.give(world, 1, "vehicle_factory", 2, 12)
	if radar:
		AiRig.give(world, 1, "fossil_radar", 22, 2)
	Power.run(world)
	world.credits[1] = credits
	return world


func _cost(world: World, id: String) -> int:
	return world.type_cost[AiRig.type_of(world, id)]


func _production(faction: String, level: String) -> AiProduction:
	return AiProduction.create(Rig.def_of(faction), Rig.level_of(level), 1)


func _memory(faction: String) -> AiMemory:
	return _open(AiMemory.create(Rig.def_of(faction)))


## The memory with a Command budget of 99.
func _open(memory: AiMemory) -> AiMemory:
	memory.commands_left = 99
	return memory


func _stream(seed: int = 1) -> DetRandom:
	return DetRandom.create(seed, DetRandom.STREAM_AI_BASE + 1)


## One production run on a fresh view of `world` for player 1 with seed 1's stream; the memory's
## budget is 99 Commands unless `open` is false (the caller set it).
func _run(
	production: AiProduction, memory: AiMemory, world: World, open: bool = true
) -> Array[Command]:
	if open:
		memory.commands_left = 99
	var out: Array[Command] = []
	production.run(PlayerView.of(world, 1), memory, _stream(), out)
	return out


## The role of each of the 300 first draws of one stream: the unit of the first QUEUE of a run on
## `world` whose queues are emptied again after each run, so each run's first draw is over all
## the roles. Returns the counts per `OpponentDef.Role`.
func _first_draws(production: AiProduction, world: World, memory: AiMemory) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	var stream: DetRandom = _stream()
	for _run_at: int in DRAWS:
		world.queue_count.fill(0)
		var out: Array[Command] = []
		memory.commands_left = 99
		production.run(PlayerView.of(world, 1), memory, stream, out)
		var role: int = ROLE_IDS.find(String(world.type_ids[out[0].payload[0]]))
		assert_int(role).is_greater_equal(0)
		counts[role] += 1
	return counts


## A memory whose sightings are `seen` (type id -> count), all first seen at `first`.
func _seen(world: World, seen: Dictionary, first: int) -> AiMemory:
	var memory: AiMemory = _memory("fossil")
	var types: int = world.type_cost.size()
	memory.seen_count.resize(types)
	memory.seen_count.fill(0)
	memory.seen_first_tick.resize(types)
	memory.seen_first_tick.fill(NONE)
	memory.seen_last_tick.resize(types)
	memory.seen_last_tick.fill(NONE)
	for id: String in seen:
		var type: int = AiRig.type_of(world, id)
		memory.seen_count[type] = seen[id]
		memory.seen_first_tick[type] = first
	return memory


func _ids(sent: Array[Command], world: World) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


func _in_tab(sent: Array[Command], world: World, tab: int) -> int:
	var found: int = 0
	for command: Command in sent:
		if world.type_tab[command.payload[0]] == tab:
			found += 1
	return found
