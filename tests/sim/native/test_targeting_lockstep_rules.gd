extends GdUnitTestSuite
## The TARGETING kernel against its GDScript twin on the cases that the plain arena does not reach
## (ADR 0013 section 4, plan P41n2), each compared after every tick like test_targeting_lockstep.gd:
## - the two cadences at every pair of -3, 0, 1, 4 and 9 (a period below 1 is 1, and the two periods
##   meet at the same ticks or never), on a lattice in a fight and on the arena;
## - the weapon-versus-type roster of test_targeting_kernel_indexes.gd, an unarmed scout first so
##   that type_weapon is [-1, 0, 1] and no weapon index is a type index, in four runs with random
##   waves (the scouts are due and unarmed all the time; the guns are wheeled and tracked, so a line
##   test for the wrong class or a weapon table read by the wrong index ends in another state);
## - 64 x 64 tiles with sparse rock, 30 units a side in the first and last two columns of the lower
##   fifth of the map, ordered to attack each other from across the map: an ATTACK unit with a clear
##   line re-tests it on its turn however far its target is, so the segments are up to 63 tiles long
##   and `ay * dx` of FixedMath.line_clear passes 2^31 (a 32-bit product would wrap); six units a
##   side have a gun of 60,000 milli, whose scans look at units 3.6 * 10^9 squared milli away. The
##   guns also see 91,000 milli (the map's diagonal is 90,510), so that every ATTACK across the map
##   names a target within sight, as the fog PR (P46b) will want, and the case stays in force;
## - the empty grid: a grid with no cells for a whole run, and grids with no rows of cells or a cell
##   side below 1 in the middle of a fight (a due row that keeps no target writes 0 without a scan;
##   the rest of the pass, the ATTACK lock and the engagement, still runs).
## The floors are measured on the tree of P46b (the vision rule) and set at about two thirds of the
## figure measured, rounded down to three digits; the measurements are beside each one. The lattice
## figures, the open-field figures and the 64 x 64 figures are those of f1494a5 unchanged: the
## fights there stand inside the sight of the units. The seeds and the maps are listed in
## tests/sim/support/targeting_worlds.gd, the orders in targeting_orders.gd.

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/targeting_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const PERIODS: Array[int] = [-3, 0, 1, 4, 9]
## The pairs [retarget_period_ticks, line_check_period_ticks] that the arena runs: a period below 1
## on either side, equal periods, and a long one.
const ARENA_PAIRS: Array[Array] = [[-3, 9], [0, 4], [1, 1], [4, 0], [9, -3]]
const LATTICE_TICKS: int = 150
const ARENA_TICKS: int = 300
const SCOUT_TICKS: int = 400
const SHORT_TICKS: int = 300
const OPEN_TICKS: int = 600
const FAR_WAVES: int = 15
## The 25 lattice runs together (the points of a lattice are corners of tiles in the even ones),
## measured: 152,863 looks, 44,165 candidates, 4,727 scans, 4,462 found, 653 ties (79 swaps), 31
## candidates on the edge of the scan window, 139 fallbacks, 1,122 dropped, 103,138 holding, 2,182
## chasing, 640 chase starts, 3,398 line tests, 1,633 re-tests, no blocked line.
const LATTICE_FLOORS: Dictionary[StringName, int] = {
	&"looks": 101000,
	&"cands": 29500,
	&"scans": 3150,
	&"found": 2970,
	&"ties": 435,
	&"tie_swaps": 52,
	&"window_edge": 20,
	&"fallbacks": 92,
	&"dropped": 748,
	&"holding": 68700,
	&"chasing": 1450,
	&"chase_starts": 420,
	&"line_checks": 2260,
	&"retests": 1080
}
## The five arena runs together, measured: 2,848,661 looks, 50,483 candidates, 42,245 scans, 3,952
## found, 46 fallbacks, 89,941 holding, 10,085 chasing, 2,153 chase starts, 10,203 line tests, 80
## re-tests, 2,789 blocked (f1494a5: 2,847,323; 50,457; 42,219; 3,942; 46; 89,863; 10,114; 2,153;
## 10,317; 165 re-tests; 2,789: the ATTACKs on an enemy out of sight are dropped now).
const ARENA_FLOORS: Dictionary[StringName, int] = {
	&"looks": 1890000,
	&"cands": 33600,
	&"scans": 28100,
	&"found": 2630,
	&"fallbacks": 30,
	&"holding": 59900,
	&"chasing": 6720,
	&"chase_starts": 1430,
	&"line_checks": 6800,
	&"retests": 53,
	&"blocked": 1850
}
## The four scout runs together, measured: 2,012 unarmed rows on their turn, 32,748 looks, 664
## candidates, 2,771 scans, 308 found, 76 fallbacks (11 for a target out of sight), 1,097 holding,
## 801 chasing, 113 chase starts, 557 line tests, 99 re-tests, 260 blocked (f1494a5: 1,891; 26,283;
## 713; 2,306; 279; 42; 1,114; 598; 84; 503; 133; 227).
const SCOUT_FLOORS: Dictionary[StringName, int] = {
	&"unarmed": 1340,
	&"looks": 21800,
	&"cands": 442,
	&"scans": 1840,
	&"found": 205,
	&"fallbacks": 50,
	&"holding": 731,
	&"chasing": 534,
	&"chase_starts": 75,
	&"line_checks": 371,
	&"retests": 66,
	&"blocked": 173
}
## The six short-sighted runs together (Worlds.short_sighted: guns that see 3,000 and 2,000 milli
## and reach 5,000 and 4,500; new with P46b), measured: 43,632 looks, 793 candidates, 2,917 enemies
## in reach and out of sight that the rule refused (`unseen`), 5,998 scans, 580 found, 173 locked,
## 22 fallbacks (13 of them for a target out of sight), 44 held targets let go because they left
## sight, 3,302 holding, 497 chasing and 154 line tests.
const SHORT_FLOORS: Dictionary[StringName, int] = {
	&"unseen": 1940,
	&"sight_lost": 8,
	&"sight_drops": 29,
	&"cands": 520,
	&"found": 380,
	&"locked": 115,
	&"fallbacks": 14,
	&"scans": 3990,
	&"holding": 2200,
	&"chasing": 330,
	&"line_checks": 100
}
## The three open-field runs together, measured: 951 segments with `ay * dx` over 2^31 and 8,521
## rows looked at over 2^31 squared milli apart (the long guns), 3,201 line tests (3,097 re-tests,
## 40 blocked), 55,956 locked rows, 553 fallbacks, 22,558 holding, 7,825 candidates.
const OPEN_FLOORS: Dictionary[StringName, int] = {
	&"wide_lines": 634,
	&"wide_d2": 5680,
	&"line_checks": 2130,
	&"retests": 2060,
	&"blocked": 26,
	&"locked": 37300,
	&"fallbacks": 368,
	&"holding": 15000,
	&"cands": 5200
}
## The ATTACK commands that the open-field runs checked for sight (see _seen_far_attacks()).
var _attacks_seen: int = 0


func test_the_two_cadences_at_every_pair_of_values_match_on_a_lattice_in_a_fight() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for retarget: int in PERIODS.size():
		for line: int in PERIODS.size():
			var members: Dictionary = {
				&"retarget_period_ticks": PERIODS[retarget],
				&"line_check_period_ticks": PERIODS[line]
			}
			var salt: int = 40 + retarget * PERIODS.size() + line
			var rig: RefCounted = Rig.new().setup(
				Worlds.lattice.bind(salt, 24, members, salt % 2 == 0)
			)
			assert_array(rig.problems).is_empty()
			var label: String = "periods %d and %d" % [PERIODS[retarget], PERIODS[line]]
			assert_int(rig.worlds[1].retarget_period_ticks).is_equal(PERIODS[retarget])
			assert_int(rig.worlds[1].line_check_period_ticks).is_equal(PERIODS[line])
			var found: String = rig.run(LATTICE_TICKS, Orders.random_waves.bind(5, 7))
			assert_str(found).override_failure_message(label).is_empty()
			Rig.add_to(total, rig.tally())
	_assert_reached(total, LATTICE_FLOORS)


func test_the_cadences_on_the_arena_match() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for pair: Array in ARENA_PAIRS:
		var members: Dictionary = {
			&"retarget_period_ticks": pair[0], &"line_check_period_ticks": pair[1]
		}
		var rig: RefCounted = Rig.new().setup(Worlds.arena.bind(null, members))
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(ARENA_TICKS, Orders.arena)
		assert_str(found).override_failure_message("periods %s" % [pair]).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, ARENA_FLOORS)


func test_the_roster_with_an_unarmed_scout_first_matches() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in 4:
		var mask: int = Rig.ALL if salt % 2 == 1 else Rig.ONLY
		var rig: RefCounted = Rig.new().setup(Worlds.scouts.bind(salt + 1), mask)
		assert_array(rig.problems).is_empty()
		assert_array(rig.worlds[1].type_weapon).is_equal([-1, 0, 1])
		assert_array(rig.worlds[1].weapon_range).is_equal([4000, 3000])
		var found: String = rig.run(SCOUT_TICKS, Orders.random_waves.bind(salt + 1, 6))
		assert_str(found).override_failure_message("run %d" % salt).is_empty()
		assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
		Rig.add_to(total, rig.tally())
	_assert_reached(total, SCOUT_FLOORS)


func test_a_map_of_64_by_64_tiles_with_sparse_rock_matches_segments_that_pass_2_to_the_31() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in 3:
		var mask: int = Rig.ALL if salt == 2 else Rig.ONLY
		var rig: RefCounted = Rig.new().setup(Worlds.open_field.bind(salt + 1), mask)
		assert_array(rig.problems).is_empty()
		assert_int(rig.worlds[1].map_cols).is_equal(64)
		assert_int(rig.worlds[1].map_rows).is_equal(64)
		assert_str(rig.run(OPEN_TICKS, _seen_far_attacks)).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, OPEN_FLOORS)
	# Orders.far_attacks sends an ATTACK of each side every 40 ticks from tick 0 (15 times in 600
	# ticks), to each of the two Worlds of the three runs: 180 commands, all of which were checked.
	assert_int(_attacks_seen).is_equal(FAR_WAVES * 2 * 2 * 3)


## Orders.far_attacks, with each ATTACK checked first: its target stands in a cell that its player
## sees. That is the authoring rule of the fog PR (row P46b: an ATTACK on an unseen enemy is
## dropped), and the long guns of the open field have the sight that keeps the far side in view, so
## after P46b the far attacks are still issued and the lines still cross the map.
func _seen_far_attacks(world: World, tick: int) -> Array[Command]:
	world.prepare()
	var out: Array[Command] = Orders.far_attacks(world, tick)
	for command: Command in out:
		var row: int = world.index_of(command.target_id)
		var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
		(
			assert_bool(world.fog.is_visible(command.player_id, cell))
			. override_failure_message(
				(
					"tick %d: player %d attacks unit %d, which it does not see"
					% [tick, command.player_id, command.target_id]
				)
			)
			. is_true()
		)
		_attacks_seen += 1
	return out


## Guns that see less than they reach (Worlds.short_sighted), under random waves of every order,
## the FOG kernel in C++ next to the TARGETING kernel in every other run: the vision rule refuses
## candidates in reach, lets go of held targets and ends ATTACK locks all through the run, in the
## kernel as in the twin.
func test_guns_that_see_less_than_they_reach_match_under_random_waves() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in 6:
		var mask: int = Rig.ALL if salt % 2 == 1 else Rig.ONLY
		var rig: RefCounted = Rig.new().setup(Worlds.short_sighted.bind(salt + 1), mask)
		assert_array(rig.problems).is_empty()
		var found: String = rig.run(SHORT_TICKS, Orders.random_waves.bind(salt + 20, 6))
		assert_str(found).override_failure_message("run %d" % salt).is_empty()
		assert_int(rig.loops[1].last_hash).is_equal(rig.loops[0].last_hash)
		Rig.add_to(total, rig.tally())
	_assert_reached(total, SHORT_FLOORS)


## A grid with no cells for the whole run (no columns: the rebuild inserts nothing, every tick): a
## due row that keeps no target writes 0 without a scan, so nobody acquires a target. The rest of
## the pass still runs: ATTACK rows lock their target and hold or walk to it, MOVE rows drop theirs.
func test_a_grid_with_no_cells_finds_nobody_for_a_whole_run() -> void:
	var rig: RefCounted = Rig.new().setup(_without_cells)
	assert_array(rig.problems).is_empty()
	for world: World in rig.worlds:
		assert_int(world.target_grid.cols).is_equal(0)
	assert_str(rig.run(400, Orders.random_waves.bind(4, 4))).is_empty()
	var tally: Dictionary[StringName, int] = rig.tally()
	assert_int(tally[&"due"]).is_greater(5800)
	assert_int(tally[&"scans"]).is_equal(0)
	assert_int(tally[&"looks"]).is_equal(0)
	assert_int(tally[&"found"]).is_equal(0)
	# 5,376 locked, 8,718 due, 2,212 holding and 434 re-tests in the run that measured these (wave
	# seed 4; with the vision rule of P46b the ATTACKs of seed 9 on an enemy out of sight are
	# dropped, and its run holds nobody, so the seed moved; at f1494a5 seed 9 gave 5,379 locked,
	# 7,420 due, 122 holding and 225 re-tests): the ATTACK commands still lock, hold and test their
	# line.
	assert_int(tally[&"locked"]).is_greater(3500)
	assert_int(tally[&"holding"]).is_greater(1400)
	assert_int(tally[&"retests"]).is_greater(280)


## Grids taken apart or shrunk in the middle of a fight, on a lattice of 30 units a side (the
## rebuild divides by the side, so it cannot run on a grid with a side below 1): a cell side of 0
## or below, no rows of cells, no columns, no cells, which find nobody, and a cell side of 1 and 2
## (a grid of 100 x 100 cells, with the units clamped into its edge cells), which are grids like
## any other. Every target is cleared first, so each due row would scan: on the
## grid as it is and on the small grids they find enemies, on the others they write 0. Six phases,
## one per tick.
func test_a_grid_with_no_rows_or_a_cell_side_below_1_finds_nobody_in_a_fight() -> void:
	# [label, what to do to the World's grid, whether the rows find enemies]
	var cases: Array[Array] = [
		["as it is", Callable(), true],
		["side 1", _tiny_grid.bind(1), true],
		["side 2", _tiny_grid.bind(2), true],
		["side 0", _set_side.bind(0), false],
		["side -5", _set_side.bind(-5), false],
		["no columns", _emptied.bind(0, 3), false],
		["no rows", _emptied.bind(5, 0), false],
		["no cells", _emptied.bind(0, 0), false],
	]
	for item: Array in cases:
		var label: String = item[0]
		var rig: RefCounted = Rig.new().setup(Worlds.lattice.bind(11, 30), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		assert_str(rig.run(30, Orders.random_waves.bind(2, 3))).is_empty()
		for world: World in rig.worlds:
			if item[1].is_valid():
				item[1].call(world)
			world.target.fill(0)
		var before: Dictionary[StringName, int] = rig.tally().duplicate()
		for _phase: int in 6:
			assert_str(rig.once(false, true)).override_failure_message(label).is_empty()
			for world: World in rig.worlds:
				world.tick += 1
		var tally: Dictionary[StringName, int] = rig.tally()
		var due: int = tally[&"due"] - before[&"due"]
		var scans: int = tally[&"scans"] - before[&"scans"]
		var looks: int = tally[&"looks"] - before[&"looks"]
		var found: int = tally[&"found"] - before[&"found"]
		# 48 rows were due in each case (48 live units over six ticks): two thirds of them is 32.
		assert_int(due).override_failure_message(label).is_greater(32)
		if item[2]:
			assert_int(scans).override_failure_message(label).is_greater(26)
			assert_int(found).override_failure_message(label).is_greater(26)
		else:
			assert_int(scans).override_failure_message(label).is_equal(0)
			assert_int(looks).override_failure_message(label).is_equal(0)
			assert_int(found).override_failure_message(label).is_equal(0)


## The arena with the targeting grid taken apart before the first tick: no columns, three rows.
func _without_cells() -> World:
	var world: World = Worlds.arena()
	world.prepare()
	Worlds.emptied(world.target_grid, 0, 3)
	return world


## The World's targeting grid with a cell side of `side`: 100 x 100 cells, rebuilt from the rows.
func _tiny_grid(world: World, side: int) -> void:
	world.target_grid.configure(100 * side, 100 * side, side, world.max_rows)
	world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())


## The World's targeting grid with its cell side set to `side` and nothing else.
func _set_side(world: World, side: int) -> void:
	world.target_grid.cell_milli = side


## The World's targeting grid taken apart to `cols` x `rows` cells (see Worlds.emptied()).
func _emptied(world: World, cols: int, rows: int) -> void:
	Worlds.emptied(world.target_grid, cols, rows)


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int]
) -> void:
	for name: StringName in least:
		assert_int(tally[name]).override_failure_message("reached %s" % name).is_greater(
			least[name] - 1
		)
