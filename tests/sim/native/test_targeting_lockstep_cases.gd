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
## - Pairs of units with the target exactly at a reach (the acquire range of an attack-moving unit,
##   the weapon range of an idle one), in all eight 3-4-5 directions and on the four axes, one milli
##   inside it and one beyond: the inclusive `<=` of the scan, the hold and the chase line test. No
##   run meets a chase line test at exactly the acquire range (the arena, the lattices and the
##   random states count 0 of them), so these pairs are the only lockstep case that pins it.
## - 1,500 seeded random states, one TARGETING phase each, with garbage in the navigation columns,
##   neutral units, targets that are gone or the unit itself, a weapon index past the tables, a grid
##   of another cell side, a negative tick and cadences from -3 to 9 (half of the states keep the
##   work counts they were built with, as the phase adds to them); and 300 states stepped for 10
##   ticks through Sim.step under random waves. Every state starts with work counts above 0, so a
##   phase that overwrote them instead of adding to them ends in another state in half of them.
## - The rig itself: it names a state that differs in the fog, in a row column or in a work count,
##   and a World that does not run TARGETING in C++; and the probe names a phase that leaves other
##   than the rule says in a column.
## The floors are measured on the tree of P46b (the vision rule) and set at about two thirds of the
## figure measured, rounded down to three digits; the measurements are beside each one (they hold
## for every mask: the twin's World is the same). The idle-lattice and attack-then-kill figures are
## those of f1494a5 unchanged (the fights stand inside the sight of the units, and the attack-then-
## kill orders name enemies that the fog shows); the random states are new draws (their fog is
## stamped for a share of the rows only, so that the rule refuses candidates, held targets and
## locks), and the lattices under waves moved a little (ATTACKs on an enemy out of sight are
## dropped).

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/targeting_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const LATTICES: int = 30
const LATTICE_TICKS: int = 120
const PHASE_STATES: int = 1500
const RUN_STATES: int = 300
const RUN_TICKS: int = 10
## The pairs of the reach cases: the shipped types, and the exact offsets per reach (the eight
## diagonals of 3-4-5 and the four axes, see Worlds.offsets_at()).
const TYPES: int = 3
const EXACT_OFFSETS: int = 12
## The 30 idle lattices together (the even ones on the corners of tiles), measured: 146,873 looks,
## 27,579 candidates, 5,174 scans, 3,667 found, 399 ties (77 swaps: the lower row met after the
## higher one; a candidate at the same distance but a lower percent is no tie), 29 candidates on the
## edge of the scan window, 121,218 holding, 3,254 hold starts.
const IDLE_FLOORS: Dictionary[StringName, int] = {
	&"cands": 18000,
	&"scans": 3400,
	&"found": 2400,
	&"ties": 266,
	&"tie_swaps": 51,
	&"window_edge": 19,
	&"holding": 80000,
	&"hold_starts": 2100
}
## The 30 lattices under random waves (the odd ones on the corners of tiles), measured: 14,766
## locked, 331 fallbacks, 1,857 dropped, 5,236 scans, 4,976 found, 274 ties (48 swaps), 16
## candidates on the edge of the scan window, 83,119 holding, 1,752 chasing, 428 chase starts,
## 1,288 line tests, 717 re-tests (f1494a5: 14,936; 331; 1,869; 5,232; 4,975; 274; 48; 16; 83,129;
## 1,722; 424; 1,297; 734).
const WAVES_FLOORS: Dictionary[StringName, int] = {
	&"locked": 9840,
	&"fallbacks": 220,
	&"dropped": 1230,
	&"scans": 3490,
	&"found": 3310,
	&"ties": 182,
	&"tie_swaps": 32,
	&"window_edge": 10,
	&"holding": 55400,
	&"chasing": 1160,
	&"chase_starts": 285,
	&"line_checks": 858,
	&"retests": 478
}
## The 1,500 states of one phase, measured: 4,242 locked, 21,621 fallbacks (871 for a target out of
## sight), 15,371 dropped, 11,160 unarmed rows on their turn, 33,875 due (936 kept; 200 more held a
## target that was out of sight and scanned), 32,939 scans (25,672 found, 7,267 empty), 272,444
## candidates that the row's player sees (43,636 by a smaller distance at the same percent, 3,274 by
## a better percent) and 61,242 more in range that it does not see, 110 ties (3 swaps), 10 on the
## edge of the scan window, 30,236 holding (22,995 starts, 13,561 ends), 3,492 chasing (475 starts,
## 17,706 ends), 1,208 line tests (180 re-tests, 660 clear, 548 blocked). The states are new draws
## since P46b: their fog is stamped for every row in one state in four and for a share of 0, 25, 50
## or 75 in 100 of the rows in the others (Worlds.random), so the rule has candidates to refuse. At
## f1494a5, with every row blind to the rule, they reached 5,113 locked, 20,750 fallbacks, 31,230
## found and 326,451 candidates.
const PHASE_FLOORS: Dictionary[StringName, int] = {
	&"locked": 2820,
	&"fallbacks": 14400,
	&"dropped": 10200,
	&"unarmed": 7440,
	&"due": 22500,
	&"kept": 624,
	&"scans": 21900,
	&"found": 17100,
	&"empty": 4840,
	&"cands": 181000,
	&"nearer_wins": 29000,
	&"farther_wins": 2180,
	&"ties": 73,
	&"tie_swaps": 2,
	&"window_edge": 6,
	&"holding": 20100,
	&"hold_starts": 15300,
	&"hold_ends": 9040,
	&"chasing": 2320,
	&"chase_starts": 316,
	&"chase_ends": 11800,
	&"line_checks": 805,
	&"retests": 120,
	&"clear": 440,
	&"blocked": 365,
	&"unseen": 40800,
	&"sight_lost": 580,
	&"sight_drops": 133
}
## The 300 states stepped 10 ticks, measured: 12,927 locked, 4,098 fallbacks (181 for a target out
## of sight), 4,616 dropped, 21,175 unarmed, 18,109 scans (13,304 found, 4,805 empty), 129,366
## candidates that the row's player sees and 22,996 that it does not (the rule refused them), 44,174
## kept targets and 47 more let go for sight, 21,234 nearer, 1,476 farther, 29 ties, 7 on the edge
## of the scan window, 80,843 holding, 6,880 chasing, 11,795 hold starts, 4,514 hold ends, 505
## chase starts, 4,606 chase ends, 4,063 line tests (1,512 re-tests, 2,783 clear, 1,280 blocked)
## (f1494a5: 14,781 locked, 3,921 fallbacks, 15,999 scans, 129,150 candidates, 4,237 line tests).
const RUN_FLOORS: Dictionary[StringName, int] = {
	&"locked": 8610,
	&"fallbacks": 2730,
	&"dropped": 3070,
	&"unarmed": 14100,
	&"scans": 12000,
	&"found": 8860,
	&"empty": 3200,
	&"cands": 86200,
	&"nearer_wins": 14100,
	&"farther_wins": 984,
	&"ties": 19,
	&"window_edge": 4,
	&"holding": 53800,
	&"chasing": 4580,
	&"hold_starts": 7860,
	&"hold_ends": 3000,
	&"chase_starts": 336,
	&"chase_ends": 3070,
	&"line_checks": 2700,
	&"retests": 1000,
	&"clear": 1850,
	&"blocked": 853,
	&"unseen": 15300,
	&"sight_lost": 120,
	&"sight_drops": 31
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
	# took a target, the same at f1494a5 and with the vision rule (the orders name an enemy that the
	# fog shows): the floors are two thirds of them.
	assert_int(total[&"fallbacks"]).is_greater(119)
	assert_int(total[&"locked"]).is_greater(839)
	assert_int(total[&"scans"]).is_greater(480)


## Pairs of units, one of each player, the other at a point `dx`, `dy` from it: attack-moving
## (reach: the acquire range, which is above the weapon range for the three types, so a target
## at it is chased) and idle (reach: the weapon range, so a target at it is held). At or inside
## the reach the pair takes each other as targets and does that; beyond it, one milli beyond,
## neither scans the other in nor tests a line, and nothing happens. The twin is held to this
## as well as the kernel to the twin.
func test_a_target_exactly_at_a_reach_is_taken_and_one_milli_beyond_is_not() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	var exact_chases: int = 0
	var engaged_pairs: int = 0
	for type: int in TYPES:
		var shipped: World = Worlds.pair(type, World.Order.IDLE, 0, 0)
		var range_milli: int = shipped.weapon_range[shipped.type_weapon[type]]
		assert_int(shipped.type_acquire[type]).is_greater(range_milli)
		for order: int in [World.Order.ATTACK_MOVE, World.Order.IDLE]:
			var chasing: bool = order == World.Order.ATTACK_MOVE
			var reach: int = shipped.type_acquire[type] if chasing else range_milli
			for offset: Vector2i in Worlds.offsets_at(reach):
				var label: String = "type %d order %d at %s" % [type, order, offset]
				var rig: RefCounted = Rig.new().setup(
					Worlds.pair.bind(type, order, offset.x, offset.y), Rig.ONLY
				)
				assert_array(rig.problems).is_empty()
				assert_str(rig.once()).override_failure_message(label).is_empty()
				var squared: int = offset.x * offset.x + offset.y * offset.y
				var engaged: bool = squared <= reach * reach
				var mode: int = World.NavMode.CHASE if chasing else World.NavMode.HOLD
				if not engaged:
					mode = World.NavMode.DIRECT if chasing else World.NavMode.NONE
				var world: World = rig.worlds[0]
				for row: int in 2:
					assert_int(world.nav_mode[row]).override_failure_message(label).is_equal(mode)
					assert_int(world.target[row]).override_failure_message(label).is_equal(
						world.unit_id[1 - row] if engaged else 0
					)
				engaged_pairs += int(engaged)
				exact_chases += 2 * int(chasing and squared == reach * reach)
				Rig.add_to(total, rig.tally())
	# Per type and order, 17 offsets: the 12 exact ones and the point one milli short on the axis
	# and the one beside the diagonal are in reach, the other 3 are one milli beyond.
	assert_int(engaged_pairs).is_equal(TYPES * 2 * (EXACT_OFFSETS + 2))
	# The chase line tests at exactly the acquire range: 3 types x 12 exact offsets x 2 rows.
	assert_int(exact_chases).is_equal(TYPES * EXACT_OFFSETS * 2)
	assert_int(total[&"chase_edge"]).is_equal(exact_chases)
	# One line test per chasing row in reach (the idle rows hold and test none).
	assert_int(total[&"line_checks"]).is_equal(TYPES * (EXACT_OFFSETS + 2) * 2)


## The probe holds the phase to the rule: a column that the acquisition pass writes, changed by
## one after the phase, is a mismatch that names the column and the unit, in the target, the
## order, the order's target and the two goal columns; the phase as it ran is none.
func test_the_probe_names_a_column_that_the_rule_does_not_leave() -> void:
	var world: World = Worlds.lattice(1, 24, {&"retarget_period_ticks": 1})
	var probe: RefCounted = Rig.TallyProbe.new(world)
	probe.before()
	world.prepare()
	world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	Targeting.run(world)
	probe.count()
	assert_int(probe.last_mismatches).is_equal(0)
	assert_str(probe.first_mismatch).is_empty()
	assert_int(probe.tally[&"found"]).is_greater(10)
	var columns: Array[StringName] = [&"target", &"order", &"order_target", &"goal_x", &"goal_y"]
	for column: StringName in columns:
		var values: PackedInt32Array = world.get(column)
		values[5] += 1
		world.set(column, values)
		probe.count()
		assert_int(probe.last_mismatches).override_failure_message(column).is_equal(1)
		assert_str(probe.first_mismatch).override_failure_message(column).contains(column)
		assert_str(probe.first_mismatch).contains("unit %d" % world.unit_id[5])
		values[5] -= 1
		world.set(column, values)
		probe.count()
		assert_int(probe.last_mismatches).override_failure_message(column).is_equal(0)


func test_random_states_match_after_one_phase() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for index: int in PHASE_STATES:
		var rig: RefCounted = Rig.new().setup(Worlds.random.bind(index, true), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		var counts: PackedInt32Array = rig.worlds[0].stats
		var candidates_before: int = counts[World.Stat.TARGET_CANDIDATES]
		assert_int(candidates_before).is_greater(0)
		assert_int(counts[World.Stat.LINE_CHECKS]).is_greater(0)
		var keep: bool = index % 2 == 1
		assert_str(rig.once(keep)).override_failure_message("state %d" % index).is_empty()
		# The phase adds the rows it looked at to the count it finds (a tick clears it first).
		assert_int(counts[World.Stat.TARGET_CANDIDATES]).is_equal(
			rig.probe.last_looks + (candidates_before if keep else 0)
		)
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
## sent at the lowest-numbered unit of side 2 that side 1 sees (the authoring rule of the fog PR,
## P46b: an ATTACK on an enemy that is not seen is dropped) and that is not yet someone's target,
## and at tick 6 every unit of side 2 that an ATTACK row of side 1 names has its hit points set to 0
## (the same on both Worlds).
@warning_ignore("integer_division")
func _attack_then_kill(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		var mine: PackedInt32Array = LockstepRig.ids_of(world, 1)
		var seen: PackedInt32Array = PackedInt32Array()
		for id: int in LockstepRig.ids_of(world, 2):
			var row: int = world.index_of(id)
			if Targeting.sees(world, 1, world.pos_x[row], world.pos_y[row]):
				seen.append(id)
		var groups: int = mini((mine.size() + 7) / 8, seen.size())
		for group: int in groups:
			var ids: PackedInt32Array = mine.slice(group * 8, group * 8 + 8)
			out.append(Command.attack(1, ids, seen[group]))
	elif tick == 6:
		for row: int in world.unit_count():
			var named: int = world.index_of(world.order_target[row])
			if world.owner[row] == 1 and world.order[row] == World.Order.ATTACK and named >= 0:
				world.hp[named] = 0
	return out


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int]
) -> void:
	for name: StringName in least:
		assert_int(tally[name]).override_failure_message("reached %s" % name).is_greater(
			least[name] - 1
		)
