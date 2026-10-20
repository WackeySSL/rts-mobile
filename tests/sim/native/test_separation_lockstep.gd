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
## has, on the arena with its 150 units gathered into a pile of 3 x 3 tiles (in the middle of the
## map, and in the corner of it against the first column and line of the grid), on changed rules
## (every rule int +3 and the five separation rules moved, so a value written as a C++ literal
## fails) and on six sets of rules that move the five separation rules across their guards (hit
## caps 1, 3, 12 and 20, look caps 1, 5 and 40; an idle share of 150 and -20; a divisor of -3 and
## 0, each beside a push cap and a hit cap that leave the divisor something to do; a push cap below
## 0). The SeparationTallyProbe counts what each run reached, so that none passes by never meeting a
## rule. The crafted crowds, with the rules at the ends of an int, are in
## test_separation_lockstep_cases.gd and the seeded random states in
## test_separation_lockstep_random.gd. That Separation.run hands the phase to the kernel at all is
## pinned by the spy case of tests/sim/test_kernel_dispatch.gd.
##
## What the arena reaches, and the lower bounds of the cases. Since P41b the units that meet hold
## (HOLD) instead of passing through one another, so crowds of 8 overlapping units are rare and no
## row reaches the edge of the grid. Since P42a (FIRE) the units that hold also fire and die (46 of
## the 150 are left at tick 900 in the plain run), so the rows, the looks and the overlaps drop to
## about half and below. The plain run reaches, on main (P41, P41b, P39n) and with P42a: 135,000 and
## 72,891 rows, 1,075,551 and 442,425 looks, 178,780 and 76,542 overlaps, 29 and 1 rows at the cap
## on hits, 22,787 and 7,178 at the cap on looks, 1,090 and 285 fixed pushes, and on both no pair
## on one point and no row at the edge of the grid. These figures change with P42a's deaths. Each
## lower bound below is about two thirds of the lower of the two (the way test_integrate_lockstep.gd
## derives its own), so that it holds on both trees. The three counts that the plain run does not
## reach on both are asserted by the arena cases that do: the cap on hits and the pair on one
## point by the pile (389 and 47 on main, 277 and 12 with P42a, 262 and 1 with P42b) and the rows
## at the edge of the grid by the pile in the corner of the map (10,375 and 4,107 in 400 ticks).
## The pile now meets the pair on one point once, so its floor is 1 and has no margin: a later arena
## change may take it to 0. The crafted cases of test_separation_lockstep_cases.gd pin the same
## three whatever the arena does: a pile that fills the cap on hits, near-coincident pairs with one
## pair on one point, and units at the four edges and corners of the map. They are the real guard
## of `same_point`, so when the pile drops it, its floor moves to the crafted case and the arena is
## not tuned to bring the pair back. The rows that the probe scans are checked against the rows
## that the rig stepped, so that a unit that dies is not counted as a row.

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
	# Not vacuous: the arena looks at units, meets overlaps, the cap on looks, the fixed push, movers
	# beside idle units, pushes and the cap on them (the cap on hits, the pair on one point and the
	# edge of the grid are the pile's, see the header; the bounds are two thirds of the lower of main
	# and main with P42a: 442,425 looks, 76,542 hits, 7,178 at the cap on looks, 285 fixed, 17,189
	# mixed, 34,602 pushed, 2,163 at the cap).
	_assert_reached(
		rig,
		{
			&"looks": 290000,
			&"hits": 51000,
			&"look_capped": 4700,
			&"fixed": 190,
			&"mixed": 11000,
			&"pushed": 23000,
			&"at_cap": 1400
		}
	)
	# Every row of every tick was scanned: the rows the twin held when the tick began (fewer than
	# 150 * TICKS since P42a, when units die).
	assert_int(rig.tally()[&"rows"]).is_equal(rig.rows_stepped)
	assert_int(rig.rows_stepped).is_less_equal(150 * TICKS)


func test_the_same_run_with_separation_and_integrate_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(_arena, Rig.WITH_INTEGRATE)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == Rig.WITH_INTEGRATE).is_true()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	# The pushes of the kernel are what the C++ INTEGRATE adds to the steps: it has to meet some.
	_assert_reached(rig, {&"hits": 51000, &"look_capped": 4700, &"pushed": 23000})


func test_the_same_run_with_every_phase_the_library_has_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(_arena, Rig.ALL)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == SimImpls.expected_mask()).is_true()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"hits": 51000, &"look_capped": 4700, &"pushed": 23000})


## The 150 units start in a square of 3 x 3 tiles (the cells of the grid are one tile), so that
## the first ticks are crowds on top of each other, scanned from the cells of a corner, and then
## spread by the pushes and the orders.
func test_900_ticks_of_the_arena_gathered_into_a_pile_match() -> void:
	var rig: RefCounted = Rig.new().setup(_arena.bind(true))
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	# 164,635 hits, 389 at the cap on hits, 30,721 at the cap on looks, 2,603 fixed, 47 pairs on one
	# point, 35,833 mixed and 6,483 at the cap on main; 53,729, 277, 10,714, 1,070, 12, 11,074 and
	# 4,047 with P42a; 47,779, 262, 10,900, 1,113, 1, 11,295 and 3,952 with P42b (a hit lands a
	# flight time after the shot, so the pile thins out later). The pair on one point is met once
	# now: its floor is 1, the least above 0, where the others stay at two thirds of P42a's.
	_assert_reached(rig, {&"hits": 35000, &"hit_capped": 180, &"look_capped": 7100})
	_assert_reached(rig, {&"fixed": 710, &"same_point": 1, &"mixed": 7300, &"at_cap": 2600})
	var again: RefCounted = Rig.new().setup(_arena.bind(true), Rig.WITH_INTEGRATE)
	assert_array(again.problems).is_empty()
	assert_str(again.run(SHORT_TICKS, _orders)).is_empty()


## The 150 units start in a square of 3 x 3 tiles in the corner of the map (from (0, 0)), so that
## the rows stand in the first column and the first line of the grid and the pushes press them
## against the border of the map; SEPARATION and INTEGRATE run in C++. The plain arena has not
## reached the edge of the grid since P41b (the units hold), so this is the arena case that does,
## on main and with P42a alike.
func test_the_arena_gathered_into_the_corner_of_the_map_matches() -> void:
	var rig: RefCounted = Rig.new().setup(_arena.bind(true, null, {}, 0), Rig.WITH_INTEGRATE)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(SHORT_TICKS, _orders)).is_empty()
	# 10,375 rows at the edge, 85,669 hits, 286 at the cap on hits and 34,742 pushed in 400 ticks on
	# main; 4,107, 40,060, 229 and 15,900 with P42a.
	_assert_reached(rig, {&"edge_rows": 2700, &"hits": 26000, &"hit_capped": 150, &"pushed": 10000})


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
	# 148,363 hits, 1,783 at the cap on hits, 58,444 at the cap on looks, 4,479 fixed, 37,421 mixed and
	# 9,623 at the cap on main; 64,864, 457, 16,463, 981, 11,799 and 5,018 with P42a.
	_assert_reached(rig, {&"hits": 43000, &"hit_capped": 300, &"look_capped": 10000})
	_assert_reached(rig, {&"fixed": 650, &"mixed": 7800, &"at_cap": 3300})


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
	# The six sets sum to 419,329 hits, 10,611 at the cap on hits, 168,291 at the cap on looks, 101,841
	# mixed and 109,755 fixed on main; 282,328, 9,342, 107,679, 66,894 and 74,673 with P42a.
	assert_int(reached[&"hits"]).is_greater(188000)
	assert_int(reached[&"hit_capped"]).is_greater(6200)
	assert_int(reached[&"look_capped"]).is_greater(71000)
	assert_int(reached[&"mixed"]).is_greater(44000)
	assert_int(reached[&"fixed"]).is_greater(49000)


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(rig: RefCounted, least: Dictionary) -> void:
	for name: StringName in least:
		assert_int(rig.tally()[name]).override_failure_message("reached %s" % name).is_greater(
			int(least[name]) - 1
		)


## The seed-42 arena (the jitter drawn as the runner draws it) with `rules` (null: data/rules.tres),
## then with the members of `members` set on the World, and, with `pile`, the 150 units gathered
## into a square of PILE_SIDE milli-tiles (their goals follow them: they stand idle there).
func _arena(
	pile: bool = false, rules: RulesDef = null, members: Dictionary = {}, pile_at: int = PILE_AT
) -> World:
	var scenario: ScenarioDef = (load(ARENA_PATH) as ScenarioDef).duplicate() as ScenarioDef
	if rules != null:
		scenario.rules = rules
	var world: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	for member: StringName in members:
		world.set(member, members[member])
	if pile:
		var rng: DetRandom = DetRandom.create(42, 11)
		for row: int in world.unit_count():
			world.pos_x[row] = pile_at + rng.next_int(PILE_SIDE)
			world.pos_y[row] = pile_at + rng.next_int(PILE_SIDE)
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
		var wave: Command = _wave(world, tick)
		if wave != null:
			out.append(wave)
	return out


## One seeded order of a side: 6 to 20 consecutive ids of its units, sent (MOVE or ATTACK_MOVE) to
## a point anywhere on the map, rock and wall included, or (ATTACK) at one unit of the other side.
## Units die since P42a, so a side may have no unit left to send, or the other side none to attack:
## null (no order) then, never an index past the ids. A side with fewer units than the group sends
## all it has.
func _wave(world: World, tick: int) -> Command:
	var rng: DetRandom = DetRandom.create(42, 500 + tick)
	var player: int = 1 + rng.next_int(2)
	var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
	var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
	if mine.is_empty():
		return null
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
	if theirs.is_empty():
		return null
	return Command.attack(player, group, theirs[rng.next_int(theirs.size())])
