extends GdUnitTestSuite
## The SEPARATION kernel against its GDScript twin over long runs (ADR 0013 section 4, plan P39n2).
## Two Worlds are built from the seed-42 perf arena, the first stepped with the GDScript phases and
## the second with the C++ kernel (SimImpls), each through its own MatchLoop with the same orders,
## and after every tick the state hash and the full state (StateDiff: every column, scalar and
## helper, the grid and the pushes among them) are compared. The orders keep the units meeting for
## the whole run: the scenario's two attack-moves, MatchScript's eight commands and, from tick 160,
## a seeded wave every 25 ticks (a group of one side sent to a point or at an enemy), so that units
## cross the wall, bunch up at the gaps, stop beside movers and push each other.
## The run repeats with the kernel alone in C++, with SEPARATION and INTEGRATE in C++ (the pushes
## the kernel wrote are what the C++ INTEGRATE adds to the steps) and with every phase the library
## has, on the arena with its 150 units gathered into a pile of 3 x 3 tiles, on changed rules (every
## rule int +3 and the five separation rules moved, so a value written as a C++ literal fails) and
## on six sets of rules that move the five separation rules across their guards (hit caps 1, 3,
## 12 and 20, look caps 1, 5 and 40; an idle share of 150 and -20; a divisor of -3 and 0, each
## beside a push cap and a hit cap that leave the divisor something to do; a push cap below 0).
## The SeparationTallyProbe counts what each run reached, so that none passes by never meeting a
## rule. The crafted crowds, with the rules at the ends of an int, are in
## test_separation_lockstep_cases.gd and the seeded random states in
## test_separation_lockstep_random.gd. That Separation.run hands the phase to the kernel at all is
## pinned by the spy case of tests/sim/test_kernel_dispatch.gd.

const Rig: GDScript = preload("res://tests/sim/support/separation_lockstep_rig.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TICKS: int = 900
const SHORT_TICKS: int = 400
## The waves start at this tick, every WAVE_EVERY ticks, at tick % WAVE_EVERY == WAVE_AT.
const WAVE_FIRST: int = 160
const WAVE_EVERY: int = 25
const WAVE_AT: int = 7
## The pile: all the units within this square of the map, from (PILE_AT, PILE_AT).
const PILE_AT: int = 10000
const PILE_SIDE: int = 3000
## The rule sets of the last case, each a dictionary of World members (the arena's rules are the
## shipped ones: 8 hits, 16 looks, idle share 75, cap 60, divisor 4). A divisor below 1 acts only
## beside a push cap above 0 and a hit cap above 0 (a cap below 0 cuts every push to 0, and a hit
## cap of 0 looks at nobody), so sets 2 and 4 have both.
const RULE_SETS: Array[Dictionary] = [
	{
		&"separation_neighbours": 3,
		&"separation_scan": 5,
		&"separation_idle_share": 90,
		&"separation_push_max": 40,
		&"separation_coincident_divisor": 2
	},
	{
		&"separation_neighbours": 20,
		&"separation_scan": 40,
		&"separation_idle_share": 0,
		&"separation_push_max": 1000,
		&"separation_coincident_divisor": 1
	},
	{
		&"separation_neighbours": 1,
		&"separation_scan": 1,
		&"separation_idle_share": 150,
		&"separation_push_max": 40,
		&"separation_coincident_divisor": -3
	},
	{
		&"separation_neighbours": 8,
		&"separation_scan": 16,
		&"separation_idle_share": -20,
		&"separation_push_max": 250,
		&"separation_coincident_divisor": 7
	},
	{
		&"separation_neighbours": 12,
		&"separation_scan": 16,
		&"separation_idle_share": 100,
		&"separation_push_max": 60,
		&"separation_coincident_divisor": 0
	},
	{
		&"separation_neighbours": 8,
		&"separation_scan": 16,
		&"separation_idle_share": 75,
		&"separation_push_max": -5,
		&"separation_coincident_divisor": 4
	},
]


func test_900_arena_ticks_match_after_every_tick() -> void:
	var rig: RefCounted = Rig.new().setup(_arena)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	assert_int(rig.worlds[0].tick).is_equal(TICKS)
	# The checkpoints of the two replays (the hash after every 15th tick) are the same 60 hashes.
	assert_int(rig.loops[0].replay.checkpoint_hashes.size()).is_equal(60)
	assert_array(rig.loops[1].replay.checkpoint_hashes).is_equal(
		rig.loops[0].replay.checkpoint_hashes
	)
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	# Not vacuous: the arena meets both caps, the fixed push, a pair on one point, movers beside
	# idle units and the edge of the grid.
	_assert_reached(
		rig,
		{
			&"looks": 600000,
			&"hits": 100000,
			&"hit_capped": 200,
			&"look_capped": 10000,
			&"fixed": 2000,
			&"same_point": 50,
			&"mixed": 10000,
			&"edge_rows": 500,
			&"pushed": 40000,
			&"at_cap": 4000
		}
	)
	assert_int(rig.tally()[&"rows"]).is_equal(150 * TICKS)


func test_the_same_run_with_separation_and_integrate_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(_arena, Rig.WITH_INTEGRATE)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == Rig.WITH_INTEGRATE).is_true()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"hits": 100000, &"hit_capped": 200, &"look_capped": 10000})


func test_the_same_run_with_every_phase_the_library_has_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(_arena, Rig.ALL)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == SimImpls.expected_mask()).is_true()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"hits": 100000, &"hit_capped": 200, &"look_capped": 10000})


## The 150 units start in a square of 3 x 3 tiles (the cells of the grid are one tile), so that
## the first ticks are crowds on top of each other, scanned from the cells of a corner, and then
## spread by the pushes and the orders.
func test_900_ticks_of_the_arena_gathered_into_a_pile_match() -> void:
	var rig: RefCounted = Rig.new().setup(_arena.bind(true))
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"hits": 100000, &"hit_capped": 100, &"look_capped": 10000})
	_assert_reached(rig, {&"fixed": 2000, &"mixed": 10000, &"at_cap": 4000})
	var again: RefCounted = Rig.new().setup(_arena.bind(true), Rig.WITH_INTEGRATE)
	assert_array(again.problems).is_empty()
	assert_str(again.run(SHORT_TICKS, _orders)).is_empty()


func test_the_same_run_on_changed_rules_matches() -> void:
	var rules: RulesDef = (load("res://data/rules.tres") as RulesDef).duplicate() as RulesDef
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and info["type"] == TYPE_INT:
			rules.set(info["name"], int(rules.get(info["name"])) + 3)
	# The five rules of the phase move far from the data: a literal of the data fails on each.
	rules.separation_neighbours = 5
	rules.separation_scan = 11
	rules.separation_idle_share = 60
	rules.separation_push_max = 45
	rules.separation_coincident_divisor = 3
	var rig: RefCounted = Rig.new().setup(_arena.bind(false, rules))
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"hits": 80000, &"hit_capped": 400, &"look_capped": 2000})
	_assert_reached(rig, {&"fixed": 1000, &"mixed": 8000, &"at_cap": 4000})


func test_the_rule_sets_that_move_every_separation_rule_and_the_guards_match() -> void:
	var reached: Dictionary[StringName, int] = {}
	for index: int in RULE_SETS.size():
		var rig: RefCounted = Rig.new().setup(_arena.bind(false, null, RULE_SETS[index]))
		assert_array(rig.problems).override_failure_message("set %d" % index).is_empty()
		(
			assert_str(rig.run(SHORT_TICKS, _orders))
			. override_failure_message("set %d" % index)
			. is_empty()
		)
		for name: StringName in rig.tally():
			reached[name] = reached.get(name, 0) + rig.tally()[name]
	# The guards change what the phase does: a push cap below 0 is 0, a divisor of 0 or -3 is 1 (sets
	# 2 and 4 have a push cap and a hit cap for it to act on), an idle share past 100 is 100.
	assert_int(reached[&"hits"]).is_greater(100000)
	assert_int(reached[&"hit_capped"]).is_greater(1000)
	assert_int(reached[&"look_capped"]).is_greater(10000)
	assert_int(reached[&"mixed"]).is_greater(10000)
	assert_int(reached[&"fixed"]).is_greater(1000)


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(rig: RefCounted, least: Dictionary) -> void:
	for name: StringName in least:
		assert_int(rig.tally()[name]).override_failure_message("reached %s" % name).is_greater(
			int(least[name]) - 1
		)


## The seed-42 arena (the jitter drawn as the runner draws it) with `rules` (null: data/rules.tres),
## then with the members of `members` set on the World, and, with `pile`, the 150 units gathered
## into a square of PILE_SIDE milli-tiles (their goals follow them: they stand idle there).
func _arena(pile: bool = false, rules: RulesDef = null, members: Dictionary = {}) -> World:
	var scenario: ScenarioDef = (load(ARENA_PATH) as ScenarioDef).duplicate() as ScenarioDef
	if rules != null:
		scenario.rules = rules
	var world: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	for member: StringName in members:
		world.set(member, members[member])
	if pile:
		var rng: DetRandom = DetRandom.create(42, 11)
		for row: int in world.unit_count():
			world.pos_x[row] = PILE_AT + rng.next_int(PILE_SIDE)
			world.pos_y[row] = PILE_AT + rng.next_int(PILE_SIDE)
			world.goal_x[row] = world.pos_x[row]
			world.goal_y[row] = world.pos_y[row]
	return world


## The commands of `tick` for one World of the arena run (a fresh Command each call).
func _orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		# The two orders of the scenario: each side attack-moves to the other's side of the wall.
		out.append(Command.attack_move(1, LockstepRig.ids_of(world, 1), 39500, 32500))
		out.append(Command.attack_move(2, LockstepRig.ids_of(world, 2), 24500, 32500))
	out.append_array(MatchScript.commands_at(tick))
	if tick >= WAVE_FIRST and tick % WAVE_EVERY == WAVE_AT:
		out.append(_wave(world, tick))
	return out


## One seeded order of a side: 6 to 20 consecutive ids of its units, sent (MOVE or ATTACK_MOVE) to
## a point anywhere on the map, rock and wall included, or (ATTACK) at one unit of the other side.
func _wave(world: World, tick: int) -> Command:
	var rng: DetRandom = DetRandom.create(42, 500 + tick)
	var player: int = 1 + rng.next_int(2)
	var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
	var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
	var count: int = 6 + rng.next_int(15)
	var first: int = rng.next_int(mine.size() - count)
	var group: PackedInt32Array = mine.slice(first, first + count)
	var x: int = rng.next_int(world.map_w)
	var y: int = rng.next_int(world.map_h)
	match rng.next_int(3):
		0:
			return Command.move(player, group, x, y)
		1:
			return Command.attack_move(player, group, x, y)
	return Command.attack(player, group, theirs[rng.next_int(theirs.size())])
