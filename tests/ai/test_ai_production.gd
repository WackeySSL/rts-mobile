extends "res://tests/ai/support/production_suite.gd"
## The opponent's production manager (plan row P178, ADR 0030 sections 1, 4, 5 and 6): hand-built
## Worlds read through `PlayerView` for the single rules (both unit queues held at `queue_target`,
## only queueable types drawn, the credits above the economy's reserve, the weighted draw over a
## fixed seed, `counter_percent` and its reaction age, the Command budget). The scout, the
## economy's QUEUEs of the same think and the match are in `test_ai_production_scout.gd`. The exact
## draw pins run on defs whose role weights and counter percents the suite owns, so a tuning row
## of `data/ai/` does not move them.

## The first-draw counts per role of 300 runs of seed 1's stream, per level (fixed by the seed).
const EXPECTED_COUNTS: Dictionary[String, Array] = {
	"easy": [149, 114, 37, 0],
	"normal": [102, 81, 80, 37],
	"hard": [57, 76, 102, 65],
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
	var target: int = _def().queue_target
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
	assert_int(seen[ARTILLERY]).is_equal(0)
	assert_int(seen[ANTI_INFANTRY] + seen[ANTI_VEHICLE] + seen[TANK]).is_equal(DRAWS)
	# With the radar it is drawn.
	var radar: Array[int] = _first_draws(
		_production("fossil", "hard"), _world(RICH, true), _memory("fossil")
	)
	assert_int(radar[ARTILLERY]).is_greater(0)
	# No barracks: no infantry, the vehicle queue is filled. No producer at all: nothing, and the
	# stream is not touched.
	var no_barracks: World = _world(RICH, true)
	AiRig.kill(no_barracks, AiRig.loop_of(no_barracks), AiRig.row_of(no_barracks, 1, "barracks"))
	var sent: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), no_barracks)
	assert_int(sent.size()).is_equal(_def().queue_target)
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
	# Two rifle squads live. With the cap at them nothing is queued; one more place is one more unit.
	var units: int = AiRig.count_of(world, 1, "rifle_squad")
	world.unit_cap = units
	assert_array(_run(_production("fossil", "normal"), _memory("fossil"), world)).is_empty()
	world.unit_cap += 1
	assert_int(_run(_production("fossil", "normal"), _memory("fossil"), world).size()).is_equal(1)


# --- The draw ----------------------------------------------------------------------------------


func test_the_role_draw_follows_the_weights_over_a_fixed_seed() -> void:
	var def: OpponentDef = _def()
	for level: String in Rig.LEVELS:
		var tier: int = _level(level).build_order_tier
		var counts: Array[int] = _first_draws(
			_production("fossil", level), _world(RICH, true), _memory("fossil")
		)
		var total: int = 0
		for role: int in OpponentDef.ROLES:
			total += def.role_weight(tier, role)
		for role: int in OpponentDef.ROLES:
			var share: int = DRAWS * def.role_weight(tier, role) / total
			# Within 8 percentage points of the def's share (the draw is random, the seed fixed);
			# a role of weight 0 is never drawn.
			assert_int(counts[role]).is_between(maxi(share - 24, 0), share + 24)
			if def.role_weight(tier, role) == 0:
				assert_int(counts[role]).is_equal(0)
		assert_array(counts).is_equal(EXPECTED_COUNTS[level])


func test_the_same_seed_draws_the_same_units_and_another_seed_may_not() -> void:
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
	var def: OpponentDef = _def()
	var level: AiDifficultyDef = _level("normal")
	var total: int = 0
	for role: int in OpponentDef.ROLES:
		total += def.role_weight(level.build_order_tier, role)
	var base: int = def.role_weight(level.build_order_tier, ANTI_VEHICLE)
	var expected: int = (
		DRAWS
		* (base * (100 - level.counter_percent) + total * level.counter_percent)
		/ (100 * total)
	)
	assert_int(shifted[ANTI_VEHICLE]).is_greater(plain[ANTI_VEHICLE])
	assert_int(shifted[ANTI_VEHICLE]).is_between(expected - 24, expected + 24)
	assert_array(shifted).is_equal(EXPECTED_SHIFTED["heavy"])
	# Infantry seen: the rifle does 100 against it (role 0).
	memory = _seen(world, {"rifle_squad": 5}, 0)
	var infantry: Array[int] = _first_draws(_production("fossil", "normal"), world, memory)
	assert_int(infantry[ANTI_INFANTRY]).is_greater(plain[ANTI_INFANTRY])
	assert_array(infantry).is_equal(EXPECTED_SHIFTED["infantry"])
	# The class most seen wins: three rifles against one tank counts infantry.
	memory = _seen(world, {"rifle_squad": 3, "heavy_tank": 1}, 0)
	assert_array(_first_draws(_production("fossil", "normal"), world, memory)).is_equal(infantry)
	# The reverse: one rifle against three tanks counts the heavy class, though it is not the lowest.
	memory = _seen(world, {"rifle_squad": 1, "heavy_tank": 3}, 0)
	assert_array(_first_draws(_production("fossil", "normal"), world, memory)).is_equal(shifted)
	# Equal counts: the lower armour class (infantry) wins.
	memory = _seen(world, {"rifle_squad": 2, "heavy_tank": 2}, 0)
	assert_array(_first_draws(_production("fossil", "normal"), world, memory)).is_equal(infantry)
	# Hard shifts more than Normal.
	var hard: Array[int] = _first_draws(
		_production("fossil", "hard"), world, _seen(world, {"heavy_tank": 5}, 0)
	)
	var hard_plain: Array[int] = _first_draws(
		_production("fossil", "hard"), world, _memory("fossil")
	)
	assert_int(hard[ANTI_VEHICLE] - hard_plain[ANTI_VEHICLE]).is_greater(
		shifted[ANTI_VEHICLE] - plain[ANTI_VEHICLE]
	)


func test_equal_counters_go_to_the_lower_role() -> void:
	# Light armour seen: the rocket (role 1) and the heavy cannon (role 2) both do 100 against it.
	var world: World = _world(RICH, true)
	world.tick = 1000
	var plain: Array[int] = _first_draws(_production("fossil", "normal"), world, _memory("fossil"))
	var seen: Array[int] = _first_draws(
		_production("fossil", "normal"), world, _seen(world, {"light_tank": 5}, 0)
	)
	assert_int(seen[ANTI_VEHICLE]).is_greater(plain[ANTI_VEHICLE])
	assert_int(seen[TANK]).is_less(plain[TANK])


func test_a_counter_role_without_weight_is_not_the_counter_and_a_full_shift_without_one_is_plain(
) -> void:
	var world: World = _world(RICH, true)
	world.tick = 1000
	# The anti-vehicle role has weight 0: heavy armour seen moves the mix to the next best
	# counter (the heavy cannon, role TANK), never to the role without weight.
	var def: OpponentDef = _def()
	def.role_weights[1 * OpponentDef.ROLES + ANTI_VEHICLE] = 0
	var level: AiDifficultyDef = _level("normal")
	var plain: Array[int] = _first_draws(
		AiProduction.create(def, level, 1), world, _memory("fossil")
	)
	var seen: Array[int] = _first_draws(
		AiProduction.create(def, level, 1), world, _seen(world, {"heavy_tank": 5}, 0)
	)
	assert_int(seen[ANTI_VEHICLE]).is_equal(0)
	assert_int(seen[TANK]).is_greater(plain[TANK])
	# At 100 percent with nothing seen the weights stay plain: units are queued, not none.
	level.counter_percent = 100
	var full: Array[int] = _first_draws(
		AiProduction.create(def, level, 1), world, _memory("fossil")
	)
	assert_int(full[ANTI_INFANTRY] + full[ANTI_VEHICLE] + full[TANK] + full[ARTILLERY]).is_equal(
		DRAWS
	)


func test_a_sighting_younger_than_the_reaction_age_does_not_shift_the_mix() -> void:
	var world: World = _world(RICH, true)
	var level: AiDifficultyDef = _level("normal")
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
	assert_int(_level("easy").counter_percent).is_equal(0)


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
	# The economy runs first on the same view and memory, as the ECONOMY slot does: what it queued
	# and keeps is out of production's reach, so nothing sent in the think passes the credits.
	world = _world(2000, true)
	AiRig.give(world, 1, "refinery", 10, 10)
	Power.run(world)
	memory = _memory("fossil")
	var out: Array[Command] = []
	var view: PlayerView = PlayerView.of(world, 1)
	var economy: AiEconomy = AiEconomy.create(_def(), _level("normal"), 1)
	economy.run(view, memory, _stream(), out)
	var economy_sent: int = out.size()
	assert_int(economy_sent).is_greater(0)
	_production("fossil", "normal").run(view, memory, _stream(), out)
	var total: int = 0
	for command: Command in out:
		total += world.type_cost[command.payload[0]]
	assert_int(total).is_less_equal(2000)


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
