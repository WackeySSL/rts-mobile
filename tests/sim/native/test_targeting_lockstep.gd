extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin over long runs (ADR 0013 section 4, plan P41n2).
## Two Worlds are built by one function, the first stepped with the GDScript phases and the second
## with the C++ kernel (SimImpls), each through its own MatchLoop with the same orders, and after
## every tick the state hash and the full state (StateDiff: every column, scalar and helper, the
## targets, orders, goals and navigation columns among them, both grids and the fog) are compared.
## The seed-42 perf arena runs for 900 ticks with TARGETING alone in C++ (so a difference can only
## be its kernel's), with the ports before FOG (FLOW, SEPARATION and INTEGRATE; FOG runs only in
## ALL) and with every phase the library has; the arena also runs under seeded random waves of
## MOVE, ATTACK_MOVE, STOP and ATTACK, the controls_test scenario runs under four seeds, and one
## run uses changed rules (every rule int +3 and both cadences moved, so a value written as a C++
## literal fails). The
## orders of the arena are the P27c rush (the scenario holds firing lines since P48), MatchScript's
## eight commands and, from tick 160, a seeded wave every 25 ticks (targeting_orders.gd). The
## cadences, the weapon-versus-type roster, the 64 x 64 maps and the empty grid are in
## test_targeting_lockstep_rules.gd; the ties on a lattice and the seeded random states are in
## test_targeting_lockstep_cases.gd. That Targeting.run hands the phase to the kernel at all is
## pinned by the spy case of tests/sim/test_kernel_dispatch.gd.
##
## What the runs reach, and the lower bounds of the cases. A TargetingTallyProbe counts what each
## run reached, so that none passes by never meeting a rule. The floors are measured on the tree of
## P46b (the vision rule of both Targeting versions) and set at about two thirds of the figure
## measured, rounded down to three digits (the way test_integrate_lockstep.gd and
## test_separation_lockstep.gd derive their own); the figures of f1494a5 (P41n, P46, P38w1b and
## everything before) are beside them where they moved. The plain arena run reaches 259,898 rows
## looked at (262,688 at f1494a5), 14,255 candidates (enemies in range with a damage percent that
## the player sees; 14,240), 4,992 locked ATTACK rows (5,046) and 38 fallbacks to ATTACK_MOVE (50),
## 120 MOVE rows that dropped a target (98), 10,589 due rows (10,662; 5,437 kept their target and
## 5,152 scanned, 1,181 of them took one), 2,583 candidates that beat the best by a smaller distance
## at the same percent and 312 by a better percent from farther away, 27,311 unit-ticks in HOLD
## (1,551 starts, 1,335 ends) and 2,906 in CHASE (455 and 448), and 1,314 line tests (173 ATTACK
## re-tests; 970 clear, 344 blocked). It moved because the ATTACK orders of the run (MatchScript's
## and the waves') that name an enemy out of sight are dropped now. It reaches no exact tie (two
## candidates at the same percent and the same squared distance: the units of the arena are
## jittered), no chase line test at exactly the acquire range, and no segment whose `ay * dx` passes
## 2^31 (a chase tests only a target inside its acquire range, and the ATTACK units of the arena
## stand near theirs). It reaches no candidate that the vision rule refuses either (`unseen`,
## `sight_lost` and `sight_drops` are 0: the units see 6,000 and 7,000 milli against acquire ranges
## of 5,000 and 5,500, and an ATTACK is validated against the same fog), so the refusals of the rule
## are the random states' (test_targeting_lockstep_cases.gd) and the short-sighted guns'
## (test_targeting_lockstep_rules.gd). The ties are the lattices', the acquire-range edge is the
## pairs' and the wide segments are the 64 x 64 map's.
##
## For P46b, which added the vision of a candidate to both Targeting versions and re-ran these
## suites: the probe's count() takes the same rule (the rig holds the probe to the phase, so a probe
## that leaves it out fails the case wherever it changes a pick), the floors of this arena are
## re-derived, and so are the floors of every case whose orders can name an enemy out of sight (the
## random waves and the attack-then-kill case send ATTACKs at any enemy, which that PR drops). The
## open field of the rules suite stays in force: its long guns see the whole map and its fog is
## stamped from tick 0, and the case asserts that every far attack names a target in sight.

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/targeting_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 900
const CONTROLS_TICKS: int = 450
## The seeds of the controls_test runs, and the phases that the kernels' World runs in C++ in each.
const CONTROLS_SEEDS: Array[int] = [1, 2, 3, 4]
const CONTROLS_MASKS: Array[int] = [Rig.ONLY, Rig.ONLY, Rig.WITH_PORTED, Rig.ALL]
## The floors of the plain arena run, in two groups: acquisition, then engagement.
const ARENA_ACQUISITION: Dictionary[StringName, int] = {
	&"looks": 173000,
	&"cands": 9500,
	&"locked": 3320,
	&"fallbacks": 25,
	&"dropped": 80,
	&"due": 7050,
	&"kept": 3620,
	&"scans": 3430,
	&"found": 787,
	&"nearer_wins": 1720,
	&"farther_wins": 208
}
const ARENA_ENGAGEMENT: Dictionary[StringName, int] = {
	&"holding": 18200,
	&"hold_starts": 1030,
	&"hold_ends": 890,
	&"chasing": 1930,
	&"chase_starts": 303,
	&"chase_ends": 298,
	&"line_checks": 876,
	&"retests": 115,
	&"clear": 646,
	&"blocked": 229
}
## The arena under random waves (WITH_PORTED), measured: 365,823 looks, 3,865 candidates, 4,043
## locked, 19 fallbacks, 158 dropped, 10,498 scans, 795 found, 17,944 holding, 1,844 chasing, 290
## chase starts, 1,088 line tests, 287 re-tests, 303 blocked (f1494a5: 313,842; 5,445; 10,662; 33;
## 297; 8,585; 803; 17,891; 1,244; 229; 1,171; 495; 328; the waves' ATTACKs on an enemy out of sight
## are dropped now, so the rows that lock are fewer).
const WAVES_FLOORS: Dictionary[StringName, int] = {
	&"looks": 243000,
	&"cands": 2570,
	&"locked": 2690,
	&"fallbacks": 12,
	&"dropped": 105,
	&"scans": 6990,
	&"found": 530,
	&"holding": 11900,
	&"chasing": 1220,
	&"chase_starts": 193,
	&"line_checks": 725,
	&"retests": 191,
	&"blocked": 202
}
## The controls_test runs of the four seeds together, measured: 132,228 looks, 488 candidates,
## 3,341 locked, 8 fallbacks, 71 dropped, 8,088 scans, 181 found, 7,589 holding, 705 chasing, 138
## chase starts, 568 line tests, 344 re-tests, 20 blocked (f1494a5: 102,211; 774; 13,068; 47; 198;
## 6,263; 333; 9,759; 783; 183; 1,634; 1,352; 32: the red tanks start 18 tiles from the block, and
## an ATTACK on one that no blue tank sees is dropped).
const CONTROLS_FLOORS: Dictionary[StringName, int] = {
	&"looks": 88100,
	&"cands": 325,
	&"locked": 2220,
	&"fallbacks": 5,
	&"dropped": 47,
	&"scans": 5390,
	&"found": 120,
	&"holding": 5050,
	&"chasing": 470,
	&"chase_starts": 92,
	&"line_checks": 378,
	&"retests": 229,
	&"blocked": 13
}
## The arena on changed rules, measured: 344,455 looks, 12,878 candidates, 4,415 locked, 29
## fallbacks, 100 dropped, 6,785 scans, 1,056 found, 29,526 holding, 3,335 chasing, 438 chase
## starts, 1,139 line tests, 302 re-tests, 140 blocked (f1494a5: 355,165; 12,995; 8,179; 32; 120;
## 7,436; 1,038; 28,716; 3,302; 411; 1,166; 338; 151).
const CHANGED_FLOORS: Dictionary[StringName, int] = {
	&"looks": 229000,
	&"cands": 8580,
	&"locked": 2940,
	&"fallbacks": 19,
	&"dropped": 66,
	&"scans": 4520,
	&"found": 704,
	&"holding": 19600,
	&"chasing": 2220,
	&"chase_starts": 292,
	&"line_checks": 759,
	&"retests": 201,
	&"blocked": 93
}


func test_900_arena_ticks_match_after_every_tick() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == Rig.ONLY).is_true()
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	assert_int(rig.worlds[0].tick).is_equal(TICKS)
	# The checkpoints of the two replays (the hash after every 15th tick) are the same 60 hashes.
	assert_int(rig.loops[0].replay.checkpoint_hashes.size()).is_equal(60)
	assert_array(rig.loops[1].replay.checkpoint_hashes).is_equal(
		rig.loops[0].replay.checkpoint_hashes
	)
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	# Every row of every tick was seen: the rows the twin held when the tick began (fewer than
	# 150 * TICKS since P42a, when units die).
	assert_int(rig.tally()[&"rows"]).is_equal(rig.rows_stepped)
	assert_int(rig.rows_stepped).is_less_equal(150 * TICKS)
	_assert_reached(rig.tally(), ARENA_ACQUISITION)
	_assert_reached(rig.tally(), ARENA_ENGAGEMENT)


func test_the_same_run_with_the_other_ported_phases_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.WITH_PORTED)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == Rig.WITH_PORTED).is_true()
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	_assert_reached(rig.tally(), ARENA_ACQUISITION)
	_assert_reached(rig.tally(), ARENA_ENGAGEMENT)


## The mask that the library reports is the one of the case before and FOG: the vision rule reads
## the fog that the FOG kernel writes, so this is the run where both run in C++.
func test_the_same_run_with_every_phase_the_library_has_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.ALL)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == SimImpls.expected_mask()).is_true()
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	_assert_reached(rig.tally(), ARENA_ACQUISITION)
	_assert_reached(rig.tally(), ARENA_ENGAGEMENT)


## The arena under a seeded wave every 6 ticks from tick 1: 1 to 24 consecutive ids of a side get a
## MOVE (3 in 10), an ATTACK_MOVE (4), a STOP (1) or an ATTACK at an enemy (2; one in ten names a
## unit of its own side, which Sim.step drops), to a point anywhere on the map or off it. The orders
## keep changing under the units, so rows go from ATTACK to ATTACK_MOVE and from MOVE to IDLE, and
## targets are dropped and taken again all the time. The ports before FOG run in C++ too.
func test_900_ticks_of_random_command_waves_match() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.WITH_PORTED)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, Orders.random_waves.bind(7))).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	assert_int(rig.tally()[&"rows"]).is_equal(rig.rows_stepped)
	_assert_reached(rig.tally(), WAVES_FLOORS)


func test_the_controls_test_scenario_under_four_seeds_matches() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for index: int in CONTROLS_SEEDS.size():
		var seed_value: int = CONTROLS_SEEDS[index]
		var build: Callable = Worlds.controls.bind(seed_value)
		var rig: RefCounted = Rig.new().setup(build, CONTROLS_MASKS[index])
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(CONTROLS_TICKS, Orders.random_waves.bind(seed_value, 8))
		assert_str(found).override_failure_message("seed %d" % seed_value).is_empty()
		assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
		Rig.add_to(total, rig.tally())
	_assert_reached(total, CONTROLS_FLOORS)


func test_the_same_run_on_changed_rules_matches() -> void:
	var rules: RulesDef = (load("res://data/rules.tres") as RulesDef).duplicate() as RulesDef
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and info["type"] == TYPE_INT:
			rules.set(info["name"], int(rules.get(info["name"])) + 3)
	# The two rules of the phase move far from the data: a literal of the data fails on both.
	rules.retarget_period_ticks = 3
	rules.line_check_period_ticks = 7
	var rig: RefCounted = Rig.new().setup(Worlds.arena.bind(rules), Rig.ONLY)
	assert_array(rig.problems).is_empty()
	assert_int(rig.worlds[1].retarget_period_ticks).is_equal(3)
	assert_int(rig.worlds[1].line_check_period_ticks).is_equal(7)
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	_assert_reached(rig.tally(), CHANGED_FLOORS)


## The orders of a run need units to send and, for an ATTACK, an enemy to hit. With every unit of
## side 2 dead (since P42a a side can be wiped out in a run) the waves of side 2 send nothing, the
## waves of side 1 send a MOVE, an ATTACK_MOVE or a STOP but never an ATTACK, and none indexes past
## the ids (an out-of-bounds read in a helper would end the whole suite in a script error).
func test_the_waves_send_no_order_that_they_have_no_unit_or_no_enemy_for() -> void:
	var world: World = Worlds.arena()
	for row: int in world.unit_count():
		if world.owner[row] == 2:
			world.hp[row] = 0
	world.remove_dead()
	var none: int = 0
	var types: Array[int] = []
	for tick: int in range(1, 400):
		var command: Command = Orders.random_wave(world, tick, 7)
		if command == null:
			none += 1
		else:
			assert_int(command.player_id).is_equal(1)
			types.append(command.type)
	assert_int(none).is_greater(50)
	assert_int(types.count(Command.Type.ATTACK)).is_equal(0)
	for type: int in [Command.Type.MOVE, Command.Type.ATTACK_MOVE, Command.Type.STOP]:
		assert_int(types.count(type)).is_greater(10)
	# The arena wave likewise: no ATTACK, and none of side 2.
	var arena_types: Array[int] = []
	for tick: int in range(167, 167 + 60 * 25, 25):
		var wave: Command = Orders.wave(world, tick)
		if wave != null:
			assert_int(wave.player_id).is_equal(1)
			arena_types.append(wave.type)
	assert_int(arena_types.size()).is_greater(10)
	assert_int(arena_types.count(Command.Type.ATTACK)).is_equal(0)
	# With side 1 gone as well, nothing is sent at all.
	for row: int in world.unit_count():
		world.hp[row] = 0
	world.remove_dead()
	assert_int(world.unit_count()).is_equal(0)
	for tick: int in range(0, 100):
		assert_object(Orders.random_wave(world, tick, 7)).is_null()
		assert_object(Orders.wave(world, tick)).is_null()
		assert_array(Orders.far_attacks(world, tick)).is_empty()


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int]
) -> void:
	for name: StringName in least:
		assert_int(tally[name]).override_failure_message("reached %s" % name).is_greater(
			least[name] - 1
		)
