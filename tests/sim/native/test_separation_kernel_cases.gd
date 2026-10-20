extends GdUnitTestSuite
## The SEPARATION kernel on crafted states (ADR 0013 section 4, plan P39n): the cases that C++ can
## get wrong where GDScript cannot. The four bound checks of the 3x3 scan (a read outside the grid
## is an error in GDScript and a wrapped or empty read in C++), the caps on looks and neighbours at
## every boundary and in scan order, the fixed push of near-coincident pairs signed by geometry
## from every side, the truncation of the pair push and of the shares for both signs, the pair one
## step inside the reach (a hit with a push of 0) and a negative reach. Every case
## runs on two identical Worlds, one with the GDScript phase and one with the kernel, and compares
## the pushes and the pair count; the values the rule gives are asserted where the case pins one.
## The module's own cases (test_separation*.gd) run under both implementations too; the 900-tick
## lockstep and the random states are test_separation_lockstep*.gd (P39n2). Tanks have radius 400
## (R = 800).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const SEPARATION: int = SimProbe.Phase.SEPARATION
const COLS: int = 20
const ROWS: int = 8
## A radius that makes any two units of the map overlap: a reach of 24000 (the map is 20000 wide).
const HUGE_RADIUS: int = 12000
## Rule values for the caps, around the shipped 8 and 16.
const NEIGHBOURS: Array[int] = [-1, 0, 1, 2, 3, 7, 8, 9, 16]
const LOOKS: Array[int] = [-1, 0, 1, 2, 4, 15, 16, 17, 24]


## A unit next to the edge of the grid scans the cells around its own, and the ones outside the grid
## are skipped, not read: left of column 0 the index would wrap to the last cell of the line above,
## right of the last column to the first cell of the line below, above line 0 it is negative, and
## below the last line it is past the end. C++ reads a wrapped index as another cell and an index
## outside the array as 0, which is row 0 (ArrayView), so each case puts the row that such a read
## would find where it is far away from the unit, with radii that make any two units overlap: a
## missing check shows as a look (SEP_PAIRS) and a push. Row 0 is the far unit and row 1 the one at
## the edge; both runs must count no look at all.
func test_the_four_bound_checks_do_not_wrap_or_read_past_the_grid() -> void:
	# [label, the unit at the edge, the far unit (row 0)]
	var cases: Array[Array] = [
		["left of column 0 reads the line above", Vector2i(500, 3500), Vector2i(19500, 2500)],
		[
			"right of the last column reads the line below",
			Vector2i(19500, 2500),
			Vector2i(500, 3500)
		],
		["above line 0 reads row 0", Vector2i(9500, 500), Vector2i(9500, 5500)],
		["below the last line reads row 0", Vector2i(9500, 7500), Vector2i(9500, 500)],
		["the corner top left reads row 0", Vector2i(500, 500), Vector2i(19500, 7500)],
		["the corner bottom right reads row 0", Vector2i(19500, 7500), Vector2i(500, 500)],
	]
	for case: Array in cases:
		var pair: Array[World] = _pair(_far_world.bind(case[2], case[1]))
		for world: World in pair:
			var near: int = Rig.distance2(world, 0, 1)
			(
				assert_bool(near < 4 * HUGE_RADIUS * HUGE_RADIUS)
				. override_failure_message(case[0])
				. is_true()
			)
			Rig.separate(world)
			var label: String = "%s, native %s" % [case[0], world.native_phases != 0]
			assert_int(world.stats[World.Stat.SEP_PAIRS]).override_failure_message(label).is_equal(
				0
			)
			assert_array(_pushes(world)).override_failure_message(label).is_equal(_zeros(2))
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case[0]).is_empty()


## A unit beyond the right or the bottom edge is listed in the last column or line of the grid, so
## it scans the cells around that one and finds the unit two cells inside (tanks 2500 and 3000
## apart do not overlap, but each looks at the other: 2 looks). The cell of the unit is clamped to
## the last column and line, not past them, or the unit would scan one cell too far out.
func test_units_beyond_the_far_edges_scan_from_the_last_column_and_line() -> void:
	# [label, the unit beyond the edge, the unit two cells inside]
	var cases: Array[Array] = [
		["right", Vector2i(21000, 3500), Vector2i(18500, 3500)],
		["bottom", Vector2i(9500, 9500), Vector2i(9500, 6500)],
		["far corner", Vector2i(24000, 11000), Vector2i(18500, 6500)],
	]
	for case: Array in cases:
		var points: Array[Vector2i] = [case[1], case[2]]
		var pair: Array[World] = _pair(_tanks.bind(points))
		for world: World in pair:
			Rig.separate(world)
			var label: String = "%s, native %s" % [case[0], world.native_phases != 0]
			assert_int(world.stats[World.Stat.SEP_PAIRS]).override_failure_message(label).is_equal(
				2
			)
			assert_array(_pushes(world)).override_failure_message(label).is_equal(_zeros(2))
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case[0]).is_empty()


## The caps at every boundary, on a crowd of 24 units in the 16 cells from (4000, 3000) to (8000,
## 7000), a third of them moving: for every number of neighbours and of looks around the shipped 8
## and 16 (and the values below 1), the kernel's pushes and its count of looks are the twin's. The
## caps cut the scan in the middle of a cell's list and between cells, so the order of the scan
## matters too: the cells row by row, each list by ascending id. A second crowd with a reach of
## 6000 overlaps everywhere, so every cap bites; the sweep sees the pushes change with the caps.
func test_the_caps_on_neighbours_and_looks_agree_with_the_twin_at_every_boundary() -> void:
	for radius: int in [400, 3000]:
		var pair: Array[World] = _pair(_crowd.bind(radius))
		var differ: Array[String] = []
		var distinct: Dictionary[String, bool] = {}
		for neighbours: int in NEIGHBOURS:
			for looks: int in LOOKS:
				for world: World in pair:
					world.separation_neighbours = neighbours
					world.separation_scan = looks
				var found: String = _run_both(pair)
				if found != "":
					differ.append("radius %d, caps %d/%d: %s" % [radius, neighbours, looks, found])
				distinct[str(pair[1].push_x.slice(0, 24))] = true
		assert_array(differ).is_empty()
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
		assert_int(distinct.size()).override_failure_message("radius %d" % radius).is_greater(6)


## The fixed push of a near-coincident pair is signed by the geometry of the pair, whichever unit
## has the lower id, on every side: the two units 0 to 3 milli apart on each axis (a pair on one
## point among them), a pair on a diagonal, and pairs a little inside and outside the limit C =
## R / 4 = 200 (d2 = 39762 is inside, 40328 outside). Inside the limit and idle, each unit takes 30
## on each axis on which the two differ, away from the other; on one point the lower id takes -30
## along x, the higher 30; outside the limit the formula's push is the twin's. Built with the east
## or south unit first and last.
func test_near_coincident_pairs_are_signed_by_geometry_whichever_unit_has_the_lower_id() -> void:
	var offsets: Array[Vector2i] = []
	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			offsets.append(Vector2i(x, y))
	offsets.append_array([Vector2i(141, 141), Vector2i(-141, 141), Vector2i(142, 142)])
	offsets.append_array([Vector2i(-142, -142), Vector2i(199, 0), Vector2i(0, -199)])
	offsets.append_array([Vector2i(200, 0), Vector2i(0, 200), Vector2i(-201, 1), Vector2i(1, 201)])
	var pair: Array[World] = _pair(_tanks.bind(_pair_of_tanks()))
	var differ: Array[String] = []
	var wrong: Array[String] = []
	var from: Vector2i = Vector2i(5000, 4000)
	for offset: Vector2i in offsets:
		for lower_is_first: bool in [true, false]:
			var first: Vector2i = from if lower_is_first else from + offset
			var second: Vector2i = from + offset if lower_is_first else from
			for world: World in pair:
				_place(world, first, second)
			var found: String = _run_both(pair)
			var label: String = "offset %s, lower first %s" % [offset, lower_is_first]
			if found != "":
				differ.append("%s: %s" % [label, found])
			var d2: int = offset.x * offset.x + offset.y * offset.y
			if d2 * 16 < 800 * 800:
				# From the first unit to the second: the unit at `from` is pushed away from the
				# other, so the first is pushed along (sign) of its own offset to the second.
				var away: Vector2i = Vector2i(signi(first.x - second.x), signi(first.y - second.y))
				var wanted: Vector2i = away * 30
				if d2 == 0:
					wanted = Vector2i(-30, 0)
				if Vector2i(pair[1].push_x[0], pair[1].push_y[0]) != wanted:
					wrong.append("%s: first %s" % [label, _pushes(pair[1])[0]])
				if Vector2i(pair[1].push_x[1], pair[1].push_y[1]) != -wanted:
					wrong.append("%s: second %s" % [label, _pushes(pair[1])[1]])
	assert_array(differ).is_empty()
	assert_array(wrong).is_empty()
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The pair push and the shares truncate toward zero for both signs: a pair 1 to 799 apart along x
## (to the east and to the west, so the push is negative for one unit and positive for the other),
## with a y offset of 0, 1, -37 and 150, in each of the four states of the intents (both idle, the
## first moving, the second moving, both moving: the shares are 50/50, 25/75, 75/25 and 50/50). The
## pushes are the twin's, with the shipped cap of 60 and, in a second pass, with the cap lifted to
## 1000 so that the whole range of the formula and of the fixed push shows.
func test_the_pair_push_and_the_shares_truncate_toward_zero_for_both_signs() -> void:
	var gaps: Array[int] = []
	for gap: int in range(1, 261):
		gaps.append(gap)
	for gap: int in range(261, 800, 7):
		gaps.append(gap)
	var pair: Array[World] = _pair(_tanks.bind(_pair_of_tanks()))
	var differ: Array[String] = []
	var most: int = 0
	for cap: int in [60, 1000]:
		for world: World in pair:
			world.separation_push_max = cap
		for gap: int in gaps:
			for sign_x: int in [1, -1]:
				for y: int in [0, 1, -37, 150]:
					for moving: int in 4:
						var offset: Vector2i = Vector2i(sign_x * gap, y)
						for world: World in pair:
							_place(world, Vector2i(5000, 4000), Vector2i(5000, 4000) + offset)
							world.intent_x[0] = 120 if (moving & 1) == 1 else 0
							world.intent_y[1] = -60 if (moving & 2) == 2 else 0
						var found: String = _run_both(pair)
						if found != "":
							differ.append(
								"gap %s, intents %d, cap %d: %s" % [offset, moving, cap, found]
							)
						most = maxi(most, absi(pair[1].push_x[1]))
	assert_array(differ).is_empty()
	assert_int(most).is_greater(60)  # With the cap lifted, a share goes past the shipped cap.
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A pair a hair inside the reach is a hit, and one that touches is not. Two radii of 400 and 401
## make R = 801 and R*R = 641601, and 800 along one axis with 40 along the other makes d2 =
## 641600, one less. (For an even R, as the shipped radii give, R*R - 1 is 3 modulo 4, which no sum
## of two squares is: only an odd R has such a pair.) The pair push is 0 (weight 1, truncated), so
## only the count of hits shows it: with one neighbour, the unit at the origin (row 0) finds that
## pair first, uses up its neighbour and is not pushed, and the third unit (row 2, 100 away, which
## would push it by 30) is not used. A pair that touches (801 apart on one axis) is no hit, so the
## unit takes the fixed push from row 2, -30 along y. The twin and the kernel agree on the pushes
## and on the looks in all 12 placements.
func test_a_pair_one_step_inside_the_reach_is_a_hit_with_a_push_of_zero() -> void:
	# [offset of row 1 from row 0, whether it is a hit]
	var cases: Array[Array] = []
	for sign_x: int in [1, -1]:
		for sign_y: int in [1, -1]:
			cases.append([Vector2i(800 * sign_x, 40 * sign_y), true])
			cases.append([Vector2i(40 * sign_x, 800 * sign_y), true])
		cases.append([Vector2i(801 * sign_x, 0), false])
		cases.append([Vector2i(0, 801 * sign_x), false])
	var differ: Array[String] = []
	for case: Array in cases:
		var pair: Array[World] = _pair(_edge_world.bind(case[0]))
		var d2: int = Rig.distance2(pair[0], 0, 1)
		assert_int(d2).override_failure_message("offset %s" % case[0]).is_equal(
			641600 if case[1] else 641601
		)
		var found: String = _run_both(pair)
		if found != "":
			differ.append("offset %s: %s" % [case[0], found])
		for world: World in pair:
			var label: String = "offset %s, native %s" % [case[0], world.native_phases != 0]
			var wanted: Vector2i = Vector2i.ZERO if case[1] else Vector2i(0, -30)
			assert_object(_pushes(world)[0]).override_failure_message(label).is_equal(wanted)
	assert_array(differ).is_empty()


## A negative reach (a unit file with a negative radius: the data holds none, but RulesDef and
## UnitDef have no @export_range) divides toward zero in `reach / divisor`, as the twin does:
## -18 / 4 is -4, not -5. Two idle-share-0 units 3 and 2 apart, with radius -9 each (R = -18, R*R
## = 324, d2 = 13, so the pair is near-coincident for the divisor 4): the fixed push is min(-4,
## 60) = -4 on each axis, signed by the geometry, so the moving unit (which takes the whole of it
## next to an idle one with a share of 0) gets 4 on both axes and the idle one 0.
func test_a_negative_reach_divides_toward_zero_for_the_fixed_push() -> void:
	var pair: Array[World] = _pair(_negative_world)
	var found: String = _run_both(pair)
	assert_str(found).is_empty()
	for world: World in pair:
		var label: String = "native %s" % (world.native_phases != 0)
		assert_array(_pushes(world)).override_failure_message(label).is_equal(
			[Vector2i(4, 4), Vector2i.ZERO]
		)
		assert_int(world.stats[World.Stat.SEP_PAIRS]).override_failure_message(label).is_equal(2)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The fixed push is `reach / divisor` truncated toward zero, and it shows when the cap does not
## bind and the divisor does not divide the reach: the radii 400 and 403 make R = 803 (the shipped
## data gives 600 to 800, which every shipped divisor of 4 divides, under a cap of 60 that always
## binds). With the cap lifted to 1000, 803 / 4 is 200 (not the 201 of a rounded quotient or of a
## ceiling), 803 / 3 is 267 (not 268), 803 / 2 is 401 (not 402), 803 / 1 is 803 and 803 / 7 is 114
## (not 115). Unit 0 moves and unit 1 is idle 100 east of it with an idle share of 100, so the idle
## unit takes the whole pair push, away from the mover along +x, and the mover none of it: the share
## is exact, so it cannot hide a difference of 1 as the 50 percent of two idle units would
## (803 / 4 = 200 or 201 is 100 after the share either way).
func test_the_fixed_push_is_the_reach_truncated_for_a_divisor_that_does_not_divide_it() -> void:
	# [divisor, the push of the idle unit]
	var cases: Array[Array] = [[4, 200], [3, 267], [2, 401], [1, 803], [7, 114]]
	for case: Array in cases:
		var pair: Array[World] = _pair(_uneven_world.bind(case[0]))
		for world: World in pair:
			var d2: int = Rig.distance2(world, 0, 1)
			var reach: int = world.type_radius[0] + world.type_radius[1]
			# Near-coincident for this divisor, or the formula would give the push.
			assert_bool(d2 * case[0] * case[0] < reach * reach).is_true()
		var found: String = _run_both(pair)
		assert_str(found).override_failure_message("divisor %d" % case[0]).is_empty()
		for world: World in pair:
			var label: String = "divisor %d, native %s" % [case[0], world.native_phases != 0]
			assert_int(world.push_x[1]).override_failure_message(label).is_equal(case[1])
			assert_int(world.push_x[0]).override_failure_message(label).is_equal(0)
			assert_int(world.push_y[0] + world.push_y[1]).override_failure_message(label).is_equal(
				0
			)
		(
			assert_str(StateDiff.first(pair[0], pair[1]))
			. override_failure_message("divisor %d" % case[0])
			. is_empty()
		)


## A unit is moving when its intent is not 0 on either axis, whatever the sign: a unit driving west
## or north is moving, as one driving east or south is. Two tanks 780 apart along x (R = 800, d2 =
## 608400, so the formula gives a pair push of 19) split it 25/75 when one moves and the other is
## idle (the mover takes 100 - 75 percent): 4 and 14 after the truncation, against the 9 and 9 of
## two idle units. Each case sets one intent on the mover, row 0 or row 1. A test of `> 0` on the
## intent, on the unit's own or on the other unit's, reads a west or north mover as idle and shows
## as 9 and 9 (the intent 120 east and 60 south are in the cases too).
func test_a_unit_moving_by_a_negative_intent_is_moving() -> void:
	# [mover, intent_x, intent_y, push_x of row 0, push_x of row 1]
	var cases: Array[Array] = [
		[0, -120, 0, -4, 14],
		[1, -120, 0, -14, 4],
		[0, 0, -60, -4, 14],
		[1, 0, -60, -14, 4],
		[0, 120, 0, -4, 14],
		[1, 120, 0, -14, 4],
		[0, 0, 60, -4, 14],
		[1, 0, 60, -14, 4],
	]
	var points: Array[Vector2i] = [Vector2i(5000, 4000), Vector2i(5780, 4000)]
	for case: Array in cases:
		var pair: Array[World] = _pair(_tanks.bind(points))
		for world: World in pair:
			assert_int(world.separation_idle_share).is_equal(75)
			world.intent_x[case[0]] = case[1]
			world.intent_y[case[0]] = case[2]
		var label: String = "mover %d, intent (%d, %d)" % [case[0], case[1], case[2]]
		assert_str(_run_both(pair)).override_failure_message(label).is_empty()
		for world: World in pair:
			var which: String = "%s, native %s" % [label, world.native_phases != 0]
			assert_int(world.push_x[0]).override_failure_message(which).is_equal(case[3])
			assert_int(world.push_x[1]).override_failure_message(which).is_equal(case[4])
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(label).is_empty()


## The cell a unit is scanned from, at the edge of a cell and at the clamp bounds. A tank scans the
## 3x3 cells around its own, so two tanks 1500 apart (radius 400, they never overlap, so no push
## shows) look at each other when their cells are neighbours (2 looks, one each) and not when they
## are two cells apart (0), and the count of looks, stats[SEP_PAIRS], is all that shows it: a
## unit at 3999 is in cell 3 and one at 4000 in cell 4, on x and on y; a unit in the last column or
## line or in column or line 0 scans from there, not one cell further in; a unit one whole cell or
## more outside the map on the left or the top scans from column or line 0, not from -1 (the
## integration clamps positions to the map, so only a test places one there). The map is 20 x 8
## tiles. The twin and the kernel agree on the looks and on the whole state.
func test_the_cell_a_unit_is_scanned_from_is_pinned_at_every_cell_edge_and_clamp_bound() -> void:
	# [label, unit A, unit B, the looks of both together]
	var cases: Array[Array] = [
		["y 3999 and cell 2 above", Vector2i(9500, 3999), Vector2i(9500, 2500), 2],
		["y 3999 and cell 5 below", Vector2i(9500, 3999), Vector2i(9500, 5500), 0],
		["y 4000 and cell 5 below", Vector2i(9500, 4000), Vector2i(9500, 5500), 2],
		["y 4000 and cell 2 above", Vector2i(9500, 4000), Vector2i(9500, 2500), 0],
		["x 3999 and cell 2 left", Vector2i(3999, 4000), Vector2i(2500, 4000), 2],
		["x 3999 and cell 5 right", Vector2i(3999, 4000), Vector2i(5500, 4000), 0],
		["x 4000 and cell 5 right", Vector2i(4000, 4000), Vector2i(5500, 4000), 2],
		["x 4000 and cell 2 left", Vector2i(4000, 4000), Vector2i(2500, 4000), 0],
		["last column", Vector2i(19500, 4000), Vector2i(17500, 4000), 0],
		["last line", Vector2i(9500, 7500), Vector2i(9500, 5500), 0],
		["first column", Vector2i(500, 4000), Vector2i(2500, 4000), 0],
		["first line", Vector2i(9500, 500), Vector2i(9500, 2500), 0],
		["a whole cell left of the map", Vector2i(-1000, 4000), Vector2i(1500, 4000), 2],
		["two and a half cells left of the map", Vector2i(-2500, 4000), Vector2i(1500, 4000), 2],
		["a whole cell above the map", Vector2i(9500, -1000), Vector2i(9500, 1500), 2],
		["two and a half cells above the map", Vector2i(9500, -2500), Vector2i(9500, 1500), 2],
	]
	for case: Array in cases:
		var points: Array[Vector2i] = [case[1], case[2]]
		var pair: Array[World] = _pair(_tanks.bind(points))
		assert_str(_run_both(pair)).override_failure_message(case[0]).is_empty()
		for world: World in pair:
			var label: String = "%s, native %s" % [case[0], world.native_phases != 0]
			assert_int(world.stats[World.Stat.SEP_PAIRS]).override_failure_message(label).is_equal(
				case[3]
			)
			assert_array(_pushes(world)).override_failure_message(label).is_equal(_zeros(2))
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case[0]).is_empty()


## The idle share is clamped to 0..100 percent before it is used. Two tanks of radius 600 (R =
## 1200) 400 apart give a pair push of 177 (d2 = 160000, the formula) under the cap lifted to 1000,
## and the mover (row 0) and the idle unit (row 1) split it by the share: with a share of 0 or
## below the mover takes all of it (-177), with 100 or above the idle unit does (177), and in
## range each takes its part truncated toward zero (75: -44 and 132). A bound one off (the share
## clamped to -1..100 or to 0..101) shows only at -1 and 101, and only for a pair push of 100 or
## more: a share of -1 gives the idle unit -1 and the mover -178, and one of 101 gives 178 and 1.
func test_the_idle_share_is_clamped_to_zero_and_a_hundred_percent() -> void:
	# [the rule, push_x of the mover (row 0), push_x of the idle unit (row 1)]
	var cases: Array[Array] = [
		[-1000, -177, 0],
		[-1, -177, 0],
		[0, -177, 0],
		[75, -44, 132],
		[100, 0, 177],
		[101, 0, 177],
		[1000, 0, 177],
	]
	var points: Array[Vector2i] = [Vector2i(5000, 4000), Vector2i(5400, 4000)]
	for case: Array in cases:
		var pair: Array[World] = _pair(_tanks.bind(points))
		for world: World in pair:
			world.type_radius[0] = 600
			world.separation_push_max = 1000
			world.separation_idle_share = case[0]
			world.intent_x[0] = 120
		var label: String = "idle share %d" % case[0]
		assert_str(_run_both(pair)).override_failure_message(label).is_empty()
		for world: World in pair:
			var which: String = "%s, native %s" % [label, world.native_phases != 0]
			assert_int(world.push_x[0]).override_failure_message(which).is_equal(case[1])
			assert_int(world.push_x[1]).override_failure_message(which).is_equal(case[2])
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(label).is_empty()


## Row 0 of the far unit and row 1 of the unit at the edge, on a map of COLS x ROWS tiles whose
## units all have a radius that makes them overlap.
func _far_world(far: Vector2i, edge: Vector2i) -> World:
	var world: World = _tanks([far, edge])
	world.type_radius[0] = HUGE_RADIUS
	return world


## Row 0 (radius 400) at (5000, 4000), row 1 (radius 401) at `offset` from it and row 2 (radius
## 401) 100 south of row 0, one neighbour and the shipped rules otherwise.
func _edge_world(offset: Vector2i) -> World:
	var world: World = GridWorld.from_rows(
		GridWorld.grass(COLS, ROWS), [World.MoveClass.TRACKED, World.MoveClass.TRACKED]
	)
	world.type_radius[1] = 401
	world.add_unit(1, 0, 5000, 4000)
	world.add_unit(1, 1, 5000 + offset.x, 4000 + offset.y)
	world.add_unit(1, 1, 5000, 4100)
	world.separation_neighbours = 1
	return world


## A mover of type 0 (radius 400) at (5000, 4000) and an idle unit of type 1 (radius 403) at (5100,
## 4000), R = 803, with the push cap lifted to 1000, an idle share of 100 and the given divisor.
func _uneven_world(divisor: int) -> World:
	var world: World = GridWorld.from_rows(
		GridWorld.grass(COLS, ROWS), [World.MoveClass.TRACKED, World.MoveClass.TRACKED]
	)
	world.type_radius[1] = 403
	world.add_unit(1, 0, 5000, 4000)
	world.add_unit(1, 1, 5100, 4000)
	world.intent_x[0] = 120
	world.separation_push_max = 1000
	world.separation_idle_share = 100
	world.separation_coincident_divisor = divisor
	return world


## Two units of radius -9 at (5000, 4000) and (5003, 4002), the first moving, with an idle share
## of 0 and the shipped divisor of 4.
func _negative_world() -> World:
	var world: World = _tanks([Vector2i(5000, 4000), Vector2i(5003, 4002)])
	world.type_radius[0] = -9
	world.separation_idle_share = 0
	world.intent_x[0] = 120
	return world


## 24 units of radius `radius` in the 4 x 4 cells from (4000, 3000) to (8000, 7000), from a stream
## of the test, one in three moving.
func _crowd(radius: int) -> World:
	var rng: DetRandom = DetRandom.create(39, 5)
	var points: Array[Vector2i] = []
	for _unit: int in 24:
		points.append(Vector2i(4000 + rng.next_int(4000), 3000 + rng.next_int(4000)))
	var world: World = _tanks(points)
	world.type_radius[0] = radius
	for row: int in 24:
		if row % 3 == 0:
			world.intent_x[row] = 120
			world.intent_y[row] = row * 7 - 80
	return world


## Both Worlds of the pair at the same state: the work counts cleared, the grid rebuilt and
## `Separation.run` called (the first with the twin, the second with the kernel). "" when the pushes
## and the count of looks are the same, else what differs.
func _run_both(pair: Array[World]) -> String:
	for world: World in pair:
		world.stats.fill(0)
		world.push_x.fill(99)
		world.push_y.fill(-99)
		Rig.separate(world)
	if pair[0].push_x != pair[1].push_x:
		return "push_x %s against %s" % [pair[0].push_x.slice(0, 4), pair[1].push_x.slice(0, 4)]
	if pair[0].push_y != pair[1].push_y:
		return "push_y %s against %s" % [pair[0].push_y.slice(0, 4), pair[1].push_y.slice(0, 4)]
	if pair[0].stats != pair[1].stats:
		return "looks %s against %s" % [pair[0].stats, pair[1].stats]
	return ""


## The two units of a pair-world at the given points, both idle.
func _place(world: World, first: Vector2i, second: Vector2i) -> void:
	world.pos_x[0] = first.x
	world.pos_y[0] = first.y
	world.pos_x[1] = second.x
	world.pos_y[1] = second.y
	world.intent_x.fill(0)
	world.intent_y.fill(0)


## Two Worlds from the same builder, the first running the GDScript phase and the second the kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		pair.append(_in(build.call(), impl))
	return pair


func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SEPARATION)).is_empty()
	return world


## Two tanks on one point, for the cases that place them afterwards.
func _pair_of_tanks() -> Array[Vector2i]:
	return [Vector2i(5000, 4000), Vector2i(5000, 4000)]


## A prepared open map of COLS x ROWS tiles with a tank (type 0, radius 400) at each point.
func _tanks(points: Array[Vector2i]) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	for point: Vector2i in points:
		world.add_unit(1, 0, point.x, point.y)
	return world


func _pushes(world: World) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		found.append(Vector2i(world.push_x[row], world.push_y[row]))
	return found


func _zeros(count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	found.resize(count)
	found.fill(Vector2i.ZERO)
	return found
