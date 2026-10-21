extends GdUnitTestSuite
## The FOG kernel against its GDScript twin over long runs (ADR 0013 section 4, plan P46n2).
## Two Worlds are built by one function, the first stepped with the GDScript phases and the second
## with the C++ kernel (SimImpls), each through its own MatchLoop with the same orders, and after
## every tick the state hash and the full state (StateDiff: every column, scalar and helper, the
## fog among them: the visible counts, the explored bytes, the versions, the dirty blocks with their
## counts and flags, and the `listed` marks) are compared.
## The seed-42 perf arena runs for 900 ticks with FOG alone in C++ (so a difference can only be its
## kernel's), with the other ports (FLOW, TARGETING, SEPARATION and INTEGRATE) and with every phase
## the library has; the arena also runs under seeded random waves of MOVE, ATTACK_MOVE, STOP and
## ATTACK, under a seeded random walk of its 150 rows that jumps them to the edges and corners and
## off the map and kills and adds units (so that the dirty blocks overflow), the controls_test
## scenario runs under four seeds, and one run uses changed rules (every rule int +3 and the fog
## cadence moved, so a value written as a C++ literal fails). The orders of the arena are the P27c
## rush (the scenario holds firing lines since P48), MatchScript's eight commands and, from tick
## 160, a seeded wave every 25 ticks (fog_orders.gd). The crafted cases (edges and corners,
## overlapping stamps, a stamp and its removal, a full block, the pad mask, the cadences, a grid
## that is not one, 2 to 4 players on maps that are not square) are in test_fog_lockstep_cases.gd,
## and the seeded random states in test_fog_lockstep_random.gd. That FogUpdate.run hands the phase
## to the kernel at all is pinned by the spy case of tests/sim/test_kernel_dispatch.gd.
##
## What the runs reach, and the lower bounds of the cases. A FogTallyProbe counts what each run
## reached, and works the phase out again from its definition (the in-map tiles within the sight,
## one by one, in a copy of the fog), so that none passes by never meeting a rule and the twin is
## held to the rule: the rig fails a case when an array that the phase writes (visible, explored,
## listed, the dirty blocks and counts and flags, the versions, `fog_cell` and the cells covered)
## is not what the probe leaves. The floors are measured on main at 5984880 (P47p, P46n, P41n2
## and everything before) and set at about two thirds of the figure measured (the way
## test_targeting_lockstep.gd and the other lockstep suites derive their own); the figures are
## beside each floor.
##
## The plain arena run reaches no first stamp (prepare() stamps every row), no block that
## overflows (the 64 x 64 map has a block of 1,024 cells per player, and the flips of one update
## stay below it), no disc cut at the east or the south side or at a corner (a few units get to
## the west and the north edges), no type with no sight entry, no player above 2 and no row off
## the map. The walkers' run reaches all of them, the controls_test runs the east and south
## sides, and the cases of test_fog_lockstep_cases.gd and the states of
## test_fog_lockstep_random.gd reach each on its own.
##
## For P46b, which adds the vision of a candidate to both Targeting versions and so changes what
## the arena's units do (where they go, who dies and when): the floors of the arena runs, the
## waves, the controls and the changed rules are re-derived there, and the crafted cases and the
## random states are not affected, as they do not run Targeting on units that fight.

const Rig: GDScript = preload("res://tests/sim/support/fog_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/fog_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 900
const CONTROLS_TICKS: int = 450
## The seeds of the controls_test runs, and the phases that the kernels' World runs in C++ in each.
const CONTROLS_SEEDS: Array[int] = [1, 2, 3, 4]
const CONTROLS_MASKS: Array[int] = [Rig.ONLY, Rig.ONLY, Rig.WITH_PORTED, Rig.ALL]
## The plain arena run (the same figures with the other ports, and with the library, in C++),
## measured: 25,855 turns, 21,397 stays, 4,458 restamps, 4,458 unstamps, 1,168,008 covered,
## 578,260 overlap_stamps, 579,332 overlap_unstamps, 5,744 flips_on, 4,672 flips_off, 2,270
## explored_new, 10,224 listed, 192 relisted, 2,451 version_flips, 6,465 quiet_stamps, 101
## deaths, 101 deaths_stamped, 34 death_on_turn, 102 clipped, 88 clip_w, 14 clip_n.
const ARENA_FLOORS: Dictionary[StringName, int] = {
	&"turns": 17000,
	&"stays": 14000,
	&"restamps": 2900,
	&"unstamps": 2900,
	&"covered": 770000,
	&"overlap_stamps": 380000,
	&"overlap_unstamps": 380000,
	&"flips_on": 3800,
	&"flips_off": 3100,
	&"explored_new": 1500,
	&"listed": 6800,
	&"relisted": 120,
	&"version_flips": 1600,
	&"quiet_stamps": 4300,
	&"deaths": 67,
	&"deaths_stamped": 67,
	&"death_on_turn": 22,
	&"clipped": 68,
	&"clip_w": 58,
	&"clip_n": 9
}
## The arena under random waves, measured: 34,588 turns, 28,429 stays, 6,159 restamps, 6,159
## unstamps, 1,610,454 covered, 799,407 overlap_stamps, 800,486 overlap_unstamps, 5,820 flips_on,
## 4,741 flips_off, 2,265 explored_new, 10,411 listed, 150 relisted, 2,567 version_flips, 9,751
## quiet_stamps, 79 deaths, 79 deaths_stamped, 27 death_on_turn.
const WAVES_FLOORS: Dictionary[StringName, int] = {
	&"turns": 23000,
	&"stays": 18000,
	&"restamps": 4100,
	&"unstamps": 4100,
	&"covered": 1000000,
	&"overlap_stamps": 530000,
	&"overlap_unstamps": 530000,
	&"flips_on": 3800,
	&"flips_off": 3100,
	&"explored_new": 1500,
	&"listed": 6900,
	&"relisted": 100,
	&"version_flips": 1700,
	&"quiet_stamps": 6500,
	&"deaths": 52,
	&"deaths_stamped": 52,
	&"death_on_turn": 18
}
## The controls_test runs of the four seeds together, measured: 23,359 turns, 16,987 stays, 6,372
## restamps, 6,372 unstamps, 1,893,855 covered, 934,354 overlap_stamps, 935,559 overlap_unstamps,
## 12,575 flips_on, 11,367 flips_off, 5,266 explored_new, 23,677 listed, 265 relisted, 5,023
## version_flips, 7,721 quiet_stamps, 19 deaths, 19 deaths_stamped, 7 death_on_turn, 400 clipped,
## 328 clip_w, 28 clip_e, 42 clip_n, 2 clip_s.
const CONTROLS_FLOORS: Dictionary[StringName, int] = {
	&"turns": 15000,
	&"stays": 11000,
	&"restamps": 4200,
	&"unstamps": 4200,
	&"covered": 1200000,
	&"overlap_stamps": 620000,
	&"overlap_unstamps": 620000,
	&"flips_on": 8300,
	&"flips_off": 7500,
	&"explored_new": 3500,
	&"listed": 15000,
	&"relisted": 170,
	&"version_flips": 3300,
	&"quiet_stamps": 5100,
	&"deaths": 12,
	&"deaths_stamped": 12,
	&"death_on_turn": 4,
	&"clipped": 260,
	&"clip_w": 210,
	&"clip_e": 18,
	&"clip_n": 28,
	&"clip_s": 1
}
## The arena on changed rules, measured: 19,474 turns, 15,068 stays, 4,406 restamps, 4,406
## unstamps, 1,146,880 covered, 568,886 overlap_stamps, 569,690 overlap_unstamps, 4,554 flips_on,
## 3,750 flips_off, 1,751 explored_new, 8,089 listed, 215 relisted, 2,153 version_flips, 6,659
## quiet_stamps, 100 deaths, 100 deaths_stamped, 25 death_on_turn, 80 clipped, 80 clip_w.
const CHANGED_FLOORS: Dictionary[StringName, int] = {
	&"turns": 12000,
	&"stays": 10000,
	&"restamps": 2900,
	&"unstamps": 2900,
	&"covered": 760000,
	&"overlap_stamps": 370000,
	&"overlap_unstamps": 370000,
	&"flips_on": 3000,
	&"flips_off": 2500,
	&"explored_new": 1100,
	&"listed": 5300,
	&"relisted": 140,
	&"version_flips": 1400,
	&"quiet_stamps": 4400,
	&"deaths": 66,
	&"deaths_stamped": 66,
	&"death_on_turn": 16,
	&"clipped": 53,
	&"clip_w": 53
}
## The arena under random walkers, measured: 16,032 turns, 3,596 stays, 12,236 restamps, 12,236
## unstamps, 2,303,958 covered, 821,005 overlap_stamps, 821,667 overlap_unstamps, 335,165
## flips_on, 326,121 flips_off, 7,376 explored_new, 501,783 listed, 49,517 relisted, 15,781
## version_flips, 8,891 quiet_stamps, 342 deaths, 341 deaths_stamped, 133 death_on_turn, 14,764
## clipped, 7,089 clip_w, 4,722 clip_e, 7,199 clip_n, 4,795 clip_s, 9,041 clip_corner, 109,986
## overflows, 296 full_blocks, 200 first_stamps, 799 off_map.
const WALKERS_FLOORS: Dictionary[StringName, int] = {
	&"turns": 10000,
	&"stays": 2300,
	&"restamps": 8100,
	&"unstamps": 8100,
	&"covered": 1500000,
	&"overlap_stamps": 540000,
	&"overlap_unstamps": 540000,
	&"flips_on": 220000,
	&"flips_off": 210000,
	&"explored_new": 4900,
	&"listed": 330000,
	&"relisted": 33000,
	&"version_flips": 10000,
	&"quiet_stamps": 5900,
	&"deaths": 220,
	&"deaths_stamped": 220,
	&"death_on_turn": 88,
	&"clipped": 9800,
	&"clip_w": 4700,
	&"clip_e": 3100,
	&"clip_n": 4700,
	&"clip_s": 3100,
	&"clip_corner": 6000,
	&"overflows": 73000,
	&"full_blocks": 190,
	&"first_stamps": 130,
	&"off_map": 530
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
	_assert_rows(rig)
	_assert_reached(rig.tally(), ARENA_FLOORS, "arena")


func test_the_same_run_with_the_other_ported_phases_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.WITH_PORTED)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == Rig.WITH_PORTED).is_true()
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	_assert_rows(rig)
	_assert_reached(rig.tally(), ARENA_FLOORS, "arena with the ports")


## The mask that the library reports is the one of the case before until a sixth kernel merges.
func test_the_same_run_with_every_phase_the_library_has_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.ALL)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == SimImpls.expected_mask()).is_true()
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	_assert_rows(rig)
	_assert_reached(rig.tally(), ARENA_FLOORS, "arena with the library")


## The arena under a seeded wave every 6 ticks from tick 1: 1 to 24 consecutive ids of a side get a
## MOVE (3 in 10), an ATTACK_MOVE (4), a STOP (1) or an ATTACK at an enemy (2; one in ten names a
## unit of its own side, which Sim.step drops), to a point anywhere on the map or off it. The units
## keep changing course, so the rows that step to a new tile are not the rush's.
func test_900_ticks_of_random_command_waves_match() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.ALL)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, Orders.random_waves.bind(7))).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	_assert_rows(rig)
	_assert_reached(rig.tally(), WAVES_FLOORS, "waves")


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
		_assert_rows(rig)
		Rig.add_to(total, rig.tally())
	_assert_reached(total, CONTROLS_FLOORS, "controls")


## Every rule int of the data +3, and the cadence of the fog on 4 (the shipped one is 3, and the
## data's +3 is 6): the players take their turns on ticks 0, 4, 8 and 1, 5, 9, so a 3 written in
## C++ fails.
func test_the_same_run_on_changed_rules_matches() -> void:
	var rules: RulesDef = (load("res://data/rules.tres") as RulesDef).duplicate() as RulesDef
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and info["type"] == TYPE_INT:
			rules.set(info["name"], int(rules.get(info["name"])) + 3)
	rules.fog_period_ticks = 4
	var rig: RefCounted = Rig.new().setup(Worlds.arena.bind(rules), Rig.ONLY)
	assert_array(rig.problems).is_empty()
	assert_int(rig.worlds[1].fog_period_ticks).is_equal(4)
	assert_str(rig.run(TICKS, Orders.arena)).is_empty()
	_assert_rows(rig)
	_assert_reached(rig.tally(), CHANGED_FLOORS, "changed rules")


## The arena's 150 rows walk at random (fog_orders.gd): they step a tile, jump anywhere on the map,
## to its edges and corners and off it, stack on one tile, die and are replaced by new units. The
## 64 x 64 map has a dirty block of 1,024 cells per player, which the jumps overflow at almost
## every update, so this is the run that reaches the full blocks, the corners and all four sides
## of the map, the rows stamped for the first time and the rows past the map, with the other ports
## in C++ as well.
func test_900_ticks_of_random_walkers_on_the_arena_match() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.arena, Rig.ALL)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, Orders.walkers.bind(11, 4, 4))).is_empty()
	assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
	_assert_rows(rig)
	_assert_reached(rig.tally(), WALKERS_FLOORS, "walkers")


## The orders of a run need units to send and, for an ATTACK, an enemy to hit. With every unit of
## side 2 dead (a side can be wiped out in a run) the waves of side 2 send nothing, the waves of
## side 1 send a MOVE, an ATTACK_MOVE or a STOP but never an ATTACK, and none indexes past the ids
## (an out-of-bounds read in a helper would end the whole suite in a script error).
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


## Every row of every tick was seen: the rows the twin held when the tick began are the rows the
## FOG phase saw plus the rows that the removal took out first.
func _assert_rows(rig: RefCounted) -> void:
	assert_int(rig.tally()[&"rows"] + rig.tally()[&"deaths"]).is_equal(rig.rows_stepped)


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int], label: String
) -> void:
	for name: StringName in least:
		var message: String = "%s: reached %s" % [label, name]
		assert_int(tally[name]).override_failure_message(message).is_greater(least[name] - 1)
