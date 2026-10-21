extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin over long runs (ADR 0013 section 4, plan P41n2).
## Two Worlds are built by one function, the first stepped with the GDScript phases and the second
## with the C++ kernel (SimImpls), each through its own MatchLoop with the same orders, and after
## every tick the state hash and the full state (StateDiff: every column, scalar and helper, the
## targets, orders, goals and navigation columns among them, both grids and the fog) are compared.
## The seed-42 perf arena runs for 900 ticks with TARGETING alone in C++ (so a difference can only
## be its kernel's), with the other ports that have merged (FLOW, SEPARATION and INTEGRATE) and with
## every phase the library has; the arena also runs under seeded random waves of MOVE, ATTACK_MOVE,
## STOP and ATTACK, the controls_test scenario runs under four seeds, and one run uses changed rules
## (every rule int +3 and both cadences moved, so a value written as a C++ literal fails). The
## orders of the arena are the P27c rush (the scenario holds firing lines since P48), MatchScript's
## eight commands and, from tick 160, a seeded wave every 25 ticks (targeting_orders.gd). The
## cadences, the weapon-versus-type roster, the 64 x 64 maps and the empty grid are in
## test_targeting_lockstep_rules.gd; the ties on a lattice and the seeded random states are in
## test_targeting_lockstep_cases.gd. That Targeting.run hands the phase to the kernel at all is
## pinned by the spy case of tests/sim/test_kernel_dispatch.gd.
##
## What the runs reach, and the lower bounds of the cases. A TargetingTallyProbe counts what each
## run reached, so that none passes by never meeting a rule. The floors are measured on main at
## f1494a5 (P41n, P46, P38w1b and everything before) and set at about two thirds of the figure
## measured (the way test_integrate_lockstep.gd and test_separation_lockstep.gd derive their own).
## The plain arena run reaches 262,688 rows looked at, 14,240 candidates (enemies in range with a
## damage percent), 5,046 locked ATTACK rows and 50 fallbacks to ATTACK_MOVE, 98 MOVE rows that
## dropped a target, 10,662 due rows (5,439 kept their target; 5,223 scanned and 1,200 took one),
## 4,770 candidates that beat the best by a smaller distance and 317 by a better percent from
## farther away, 27,578 unit-ticks in HOLD (1,561 starts, 1,357 ends) and 2,995 in CHASE (468 and
## 456), and 1,339 line tests (171 ATTACK re-tests; 996 clear, 343 blocked). It reaches no exact tie
## (two candidates at the same percent and the same squared distance: the units of the arena are
## jittered) and no segment whose `ay * dx` passes 2^31 (a chase tests only a target inside its
## acquire range, and the ATTACK units of the arena stand near theirs). Those two are the lattice's
## and the 64 x 64 map's, in the other two suites, so a later change to the arena (P47, P46b)
## re-derives the floors here and leaves those alone.

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
	&"looks": 175000,
	&"cands": 9500,
	&"locked": 3300,
	&"fallbacks": 33,
	&"dropped": 65,
	&"due": 7100,
	&"kept": 3600,
	&"scans": 3400,
	&"found": 800,
	&"nearer_wins": 3100,
	&"farther_wins": 210
}
const ARENA_ENGAGEMENT: Dictionary[StringName, int] = {
	&"holding": 18000,
	&"hold_starts": 1000,
	&"hold_ends": 900,
	&"chasing": 2000,
	&"chase_starts": 300,
	&"chase_ends": 300,
	&"line_checks": 890,
	&"retests": 110,
	&"clear": 660,
	&"blocked": 220
}
## The arena under random waves (WITH_PORTED), measured: 313,842 looks, 5,445 candidates, 10,662
## locked, 33 fallbacks, 297 dropped, 8,585 scans, 803 found, 17,891 holding, 1,244 chasing, 229
## chase starts, 1,171 line tests, 495 re-tests, 328 blocked.
const WAVES_FLOORS: Dictionary[StringName, int] = {
	&"looks": 200000,
	&"cands": 3600,
	&"locked": 7000,
	&"fallbacks": 22,
	&"dropped": 195,
	&"scans": 5700,
	&"found": 530,
	&"holding": 11900,
	&"chasing": 830,
	&"chase_starts": 150,
	&"line_checks": 780,
	&"retests": 330,
	&"blocked": 218
}
## The controls_test runs of the four seeds together, measured: 102,211 looks, 774 candidates,
## 13,068 locked, 47 fallbacks, 198 dropped, 6,263 scans, 333 found, 9,759 holding, 783 chasing, 183
## chase starts, 1,634 line tests, 1,352 re-tests, 32 blocked.
const CONTROLS_FLOORS: Dictionary[StringName, int] = {
	&"looks": 68000,
	&"cands": 515,
	&"locked": 8700,
	&"fallbacks": 31,
	&"dropped": 132,
	&"scans": 4100,
	&"found": 222,
	&"holding": 6500,
	&"chasing": 520,
	&"chase_starts": 122,
	&"line_checks": 1089,
	&"retests": 900,
	&"blocked": 21
}
## The arena on changed rules, measured: 355,165 looks, 12,995 candidates, 8,179 locked, 32
## fallbacks, 120 dropped, 7,436 scans, 1,038 found, 28,716 holding, 3,302 chasing, 411 chase
## starts, 1,166 line tests, 338 re-tests, 151 blocked.
const CHANGED_FLOORS: Dictionary[StringName, int] = {
	&"looks": 236000,
	&"cands": 8600,
	&"locked": 5400,
	&"fallbacks": 21,
	&"dropped": 80,
	&"scans": 4900,
	&"found": 690,
	&"holding": 19000,
	&"chasing": 2200,
	&"chase_starts": 274,
	&"line_checks": 777,
	&"retests": 225,
	&"blocked": 100
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
## targets are dropped and taken again all the time. The other ports run in C++ too.
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
