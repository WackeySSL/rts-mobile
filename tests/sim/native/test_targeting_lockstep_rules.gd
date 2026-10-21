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
##   side have a gun of 60,000 milli, whose scans look at units 3.6 * 10^9 squared milli away;
## - the empty grid: a grid with no cells for a whole run, and grids with no rows of cells or a cell
##   side below 1 in the middle of a fight (a due row that keeps no target writes 0 without a scan;
##   the rest of the pass, the ATTACK lock and the engagement, still runs).
## The floors are measured on main at f1494a5 and set at about two thirds of the figure measured;
## the measurements are beside each one. The seeds and the maps are listed in tests/sim/support/
## targeting_worlds.gd, the orders in targeting_orders.gd.

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
const OPEN_TICKS: int = 600
## The 25 lattice runs together (the points of a lattice are corners of tiles in the even ones),
## measured: 152,863 looks, 44,165 candidates, 4,727 scans, 4,462 found, 1,093 ties (142 swaps), 31
## candidates on the edge of the scan window, 139 fallbacks, 1,122 dropped, 103,138 holding, 2,182
## chasing, 640 chase starts, 3,398 line tests, 1,633 re-tests, no blocked line.
const LATTICE_FLOORS: Dictionary[StringName, int] = {
	&"looks": 101000,
	&"cands": 29500,
	&"scans": 3150,
	&"found": 2970,
	&"ties": 728,
	&"tie_swaps": 94,
	&"window_edge": 20,
	&"fallbacks": 92,
	&"dropped": 748,
	&"holding": 68700,
	&"chasing": 1450,
	&"chase_starts": 420,
	&"line_checks": 2260,
	&"retests": 1080
}
## The five arena runs together, measured: 2,847,323 looks, 50,457 candidates, 42,219 scans, 3,942
## found, 46 fallbacks, 89,863 holding, 10,114 chasing, 2,153 chase starts, 10,317 line tests, 165
## re-tests, 2,789 blocked.
const ARENA_FLOORS: Dictionary[StringName, int] = {
	&"looks": 1900000,
	&"cands": 33000,
	&"scans": 28000,
	&"found": 2600,
	&"fallbacks": 30,
	&"holding": 59000,
	&"chasing": 6700,
	&"chase_starts": 1435,
	&"line_checks": 6800,
	&"retests": 110,
	&"blocked": 1850
}
## The four scout runs together, measured: 1,891 unarmed rows on their turn, 26,283 looks, 713
## candidates, 2,306 scans, 279 found, 42 fallbacks, 1,114 holding, 598 chasing, 84 chase starts,
## 503 line tests, 133 re-tests, 227 blocked.
const SCOUT_FLOORS: Dictionary[StringName, int] = {
	&"unarmed": 1260,
	&"looks": 17500,
	&"cands": 475,
	&"scans": 1530,
	&"found": 186,
	&"fallbacks": 28,
	&"holding": 740,
	&"chasing": 398,
	&"chase_starts": 56,
	&"line_checks": 335,
	&"retests": 88,
	&"blocked": 151
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
		assert_str(rig.run(OPEN_TICKS, Orders.far_attacks)).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, OPEN_FLOORS)


## A grid with no cells for the whole run (no columns: the rebuild inserts nothing, every tick): a
## due row that keeps no target writes 0 without a scan, so nobody acquires a target. The rest of
## the pass still runs: ATTACK rows lock their target and hold or walk to it, MOVE rows drop theirs.
func test_a_grid_with_no_cells_finds_nobody_for_a_whole_run() -> void:
	var rig: RefCounted = Rig.new().setup(_without_cells)
	assert_array(rig.problems).is_empty()
	for world: World in rig.worlds:
		assert_int(world.target_grid.cols).is_equal(0)
	assert_str(rig.run(400, Orders.random_waves.bind(9, 4))).is_empty()
	var tally: Dictionary[StringName, int] = rig.tally()
	assert_int(tally[&"due"]).is_greater(4900)
	assert_int(tally[&"scans"]).is_equal(0)
	assert_int(tally[&"looks"]).is_equal(0)
	assert_int(tally[&"found"]).is_equal(0)
	# 5,379 locked, 7,420 due (4 kept), 122 holding and 225 re-tests in the run that measured these:
	# the ATTACK commands still lock, hold and test their line.
	assert_int(tally[&"locked"]).is_greater(3500)
	assert_int(tally[&"holding"]).is_greater(80)
	assert_int(tally[&"retests"]).is_greater(150)


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
