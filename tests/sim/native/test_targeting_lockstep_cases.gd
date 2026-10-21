extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin on built and random states (ADR 0013 section 4,
## plan P41n2), compared like test_targeting_lockstep.gd: the state hash and the full state after
## every tick, or after the phase when a case drives it by hand (targeting_lockstep_rig.gd).
## - Exact-distance ties on a lattice: 60 small fights of the three shipped types at the points of
##   a lattice of 1000 milli, so that several enemies stand at the same squared distance and the
##   same damage percent, and the lowest row has to win wherever the grid meets it (the arena's
##   units are jittered, so it never meets a tie). Half of the fights are left alone (every unit
##   idle) and half get random waves.
## - ATTACK rows whose target dies in the middle of the run fall back to ATTACK_MOVE, scan if due
##   and go on.
## - 1,500 seeded random states, one TARGETING phase each, with garbage in the navigation columns,
##   neutral units, targets that are gone or the unit itself, a weapon index past the tables, a grid
##   of another cell side, a negative tick and cadences from -3 to 9 (half of the states keep the
##   work counts they were built with, as the phase adds to them); and 300 states stepped for 10
##   ticks through Sim.step under random waves.
## - The rig itself: it names a state that differs in the fog, in a row column or in a work count,
##   and a World that does not run TARGETING in C++.
## The floors are measured on main at f1494a5 and set at about two thirds of the figure measured;
## the measurements are beside each one (they hold for every mask: the twin's World is the same).

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/targeting_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const LATTICES: int = 30
const LATTICE_TICKS: int = 120
const PHASE_STATES: int = 1500
const RUN_STATES: int = 300
const RUN_TICKS: int = 10
## The 30 idle lattices together (the even ones on the corners of tiles), measured: 146,873 looks,
## 27,579 candidates, 5,174 scans, 3,667 found, 645 ties (134 swaps: the lower row met after the
## higher one), 29 candidates on the edge of the scan window, 121,218 holding, 3,254 hold starts.
const IDLE_FLOORS: Dictionary[StringName, int] = {
	&"cands": 18000,
	&"scans": 3400,
	&"found": 2400,
	&"ties": 430,
	&"tie_swaps": 89,
	&"window_edge": 19,
	&"holding": 80000,
	&"hold_starts": 2100
}
## The 30 lattices under random waves (the odd ones on the corners of tiles), measured: 14,936
## locked, 331 fallbacks, 1,869 dropped, 5,232 scans, 4,975 found, 450 ties (64 swaps), 16
## candidates on the edge of the scan window, 83,129 holding, 1,722 chasing, 424 chase starts,
## 1,297 line tests, 734 re-tests.
const WAVES_FLOORS: Dictionary[StringName, int] = {
	&"locked": 9900,
	&"fallbacks": 220,
	&"dropped": 1240,
	&"scans": 3480,
	&"found": 3300,
	&"ties": 300,
	&"tie_swaps": 42,
	&"window_edge": 10,
	&"holding": 55000,
	&"chasing": 1140,
	&"chase_starts": 280,
	&"line_checks": 860,
	&"retests": 488
}
## The 1,500 states of one phase, measured: 5,113 locked, 20,750 fallbacks, 15,371 dropped, 11,042
## unarmed rows on their turn, 33,455 due (1,136 kept), 32,319 scans (31,230 found, 1,089 empty),
## 326,451 candidates (75,745 by a smaller distance, 4,001 by a better percent), 168 ties (4 swaps),
## 13 on the edge of the scan window, 35,979 holding (27,503 starts, 12,326 ends), 3,711 chasing
## (539 starts, 17,551 ends), 1,372 line tests (220 re-tests, 758 clear, 614 blocked).
const PHASE_FLOORS: Dictionary[StringName, int] = {
	&"locked": 3400,
	&"fallbacks": 13800,
	&"dropped": 10200,
	&"unarmed": 7360,
	&"due": 22300,
	&"kept": 750,
	&"scans": 21500,
	&"found": 20800,
	&"empty": 720,
	&"cands": 217000,
	&"nearer_wins": 50000,
	&"farther_wins": 2660,
	&"ties": 112,
	&"tie_swaps": 2,
	&"window_edge": 8,
	&"holding": 23900,
	&"hold_starts": 18300,
	&"hold_ends": 8200,
	&"chasing": 2470,
	&"chase_starts": 359,
	&"chase_ends": 11700,
	&"line_checks": 914,
	&"retests": 146,
	&"clear": 505,
	&"blocked": 409
}
## The 300 states stepped 10 ticks, measured: 14,781 locked, 3,921 fallbacks, 4,653 dropped, 20,857
## unarmed, 15,999 scans (13,320 found, 2,679 empty), 129,150 candidates, 28,521 nearer, 1,485
## farther, 36 ties, 8 on the edge of the scan window, 82,935 holding, 7,117 chasing, 11,656 hold
## starts, 4,291 hold ends, 500 chase starts, 4,561 chase ends, 4,237 line tests (1,649 re-tests,
## 2,929 clear, 1,308 blocked).
const RUN_FLOORS: Dictionary[StringName, int] = {
	&"locked": 9800,
	&"fallbacks": 2600,
	&"dropped": 3100,
	&"unarmed": 13900,
	&"scans": 10600,
	&"found": 8880,
	&"empty": 1780,
	&"cands": 86000,
	&"nearer_wins": 19000,
	&"farther_wins": 990,
	&"ties": 24,
	&"window_edge": 5,
	&"holding": 55000,
	&"chasing": 4740,
	&"hold_starts": 7770,
	&"hold_ends": 2860,
	&"chase_starts": 333,
	&"chase_ends": 3040,
	&"line_checks": 2820,
	&"retests": 1090,
	&"clear": 1950,
	&"blocked": 870
}


## Fights at lattice points, every unit idle: IDLE rows scan at their weapon range, so the units
## that stand within it shoot, die and are replaced by the next nearest, over and over.
func test_exact_distance_ties_on_a_lattice_go_to_the_lowest_row() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in LATTICES:
		var rig: RefCounted = Rig.new().setup(
			Worlds.lattice.bind(100 + salt, 24, {}, salt % 2 == 0), Rig.ONLY
		)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(LATTICE_TICKS)
		assert_str(found).override_failure_message("lattice %d" % salt).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, IDLE_FLOORS)


## The same lattices under random waves (and the other ports in C++ on every other one): units
## walk off the lattice and meet in a crowd, ATTACK rows lock and fall back.
func test_the_lattices_under_random_waves_match() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in LATTICES:
		var mask: int = Rig.WITH_PORTED if salt % 2 == 1 else Rig.ONLY
		var rig: RefCounted = Rig.new().setup(
			Worlds.lattice.bind(200 + salt, 24, {}, salt % 2 == 1), mask
		)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(LATTICE_TICKS, Orders.random_waves.bind(salt, 5))
		assert_str(found).override_failure_message("lattice %d" % salt).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, WAVES_FLOORS)


## Every unit of side 1 is sent at the lowest enemy it can see (one ATTACK per group of 8), and at
## tick 6 those enemies are killed (hit points 0, removed at the end of that tick). The ATTACK rows
## find their target gone on the next tick: the order becomes ATTACK_MOVE with the goal where the
## target stood, the row scans if it is due and goes on, in both implementations.
func test_attack_rows_whose_target_dies_fall_back_to_attack_move() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in 6:
		var rig: RefCounted = Rig.new().setup(Worlds.lattice.bind(300 + salt, 30), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(60, _attack_then_kill)
		assert_str(found).override_failure_message("lattice %d" % salt).is_empty()
		Rig.add_to(total, rig.tally())
	# 1,260 ATTACK rows locked and 180 fell back in the six runs that measured these, and 726 scans
	# took a target: the floors are two thirds of them.
	assert_int(total[&"fallbacks"]).is_greater(119)
	assert_int(total[&"locked"]).is_greater(839)
	assert_int(total[&"scans"]).is_greater(480)


func test_random_states_match_after_one_phase() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for index: int in PHASE_STATES:
		var rig: RefCounted = Rig.new().setup(Worlds.random.bind(index, true), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		assert_str(rig.once(index % 2 == 1)).override_failure_message("state %d" % index).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, PHASE_FLOORS)


func test_random_states_match_after_every_tick_of_a_short_run() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for index: int in RUN_STATES:
		var mask: int = Rig.ONLY if index % 2 == 0 else Rig.WITH_PORTED
		var rig: RefCounted = Rig.new().setup(Worlds.random.bind(5000 + index, false), mask)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(RUN_TICKS, Orders.random_waves.bind(index, 3))
		assert_str(found).override_failure_message("state %d" % index).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, RUN_FLOORS)


## The rig is only worth its name if it sees what it compares: a difference of one in the fog, in a
## row column, in a work count or in the targeting grid is named, and a mask without TARGETING is
## reported as a problem instead of running the twin twice.
func test_the_rig_names_a_difference_in_the_fog_a_column_a_count_or_the_grid() -> void:
	var rig: RefCounted = Rig.new().setup(Worlds.lattice.bind(1), Rig.ONLY)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(8, Orders.random_waves.bind(1, 3))).is_empty()
	var kernels: World = rig.worlds[1]
	kernels.fog.explored[0] += 1
	assert_str(rig.compare("fog")).contains("explored")
	kernels.fog.explored[0] -= 1
	assert_str(rig.compare("fog")).is_empty()
	kernels.target[0] += 1
	assert_str(rig.compare("column")).contains("target")
	kernels.target[0] -= 1
	kernels.stats[World.Stat.TARGET_CANDIDATES] += 1
	assert_str(rig.compare("count")).contains("stats")
	kernels.stats[World.Stat.TARGET_CANDIDATES] -= 1
	kernels.target_grid.next[0] += 1
	assert_str(rig.compare("grid")).contains("target_grid")
	kernels.target_grid.next[0] -= 1
	assert_str(rig.compare("grid")).is_empty()
	var found: Array[String] = []
	Rig.pair(Worlds.lattice.bind(1), 1 << SimProbe.Phase.FLOW, found)
	assert_array(found).is_equal(["TARGETING is not in the mask 2"])


## The orders of the ATTACK-then-kill case: at tick 0 every group of 8 units of side 1 (by id) is
## sent at the lowest-numbered unit of side 2 that is not yet someone's target, and at tick 6 every
## unit of side 2 that was named has its hit points set to 0 (the same on both Worlds).
@warning_ignore("integer_division")
func _attack_then_kill(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	var mine: PackedInt32Array = LockstepRig.ids_of(world, 1)
	var theirs: PackedInt32Array = LockstepRig.ids_of(world, 2)
	var groups: int = mini((mine.size() + 7) / 8, theirs.size())
	for group: int in groups:
		if tick == 0:
			var ids: PackedInt32Array = mine.slice(group * 8, group * 8 + 8)
			out.append(Command.attack(1, ids, theirs[group]))
		elif tick == 6:
			world.hp[world.index_of(theirs[group])] = 0
	return out


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int]
) -> void:
	for name: StringName in least:
		assert_int(tally[name]).override_failure_message("reached %s" % name).is_greater(
			least[name] - 1
		)
