extends GdUnitTestSuite
## The SEPARATION kernel on crafted states (ADR 0013 section 4, plan P39n): the cases that C++ can
## get wrong where GDScript cannot. The four bound checks of the 3x3 scan (a read outside the grid
## is an error in GDScript and a wrapped or empty read in C++), the caps on looks and neighbours at
## every boundary and in scan order, the fixed push of near-coincident pairs signed by geometry
## from every side, and the truncation of the pair push and of the shares for both signs. Every case
## runs on two identical Worlds, one with the GDScript phase and one with the kernel, and compares
## the pushes and the pair count; the values the rule gives are asserted where the case pins one.
## The module's own cases (test_separation*.gd) run under both implementations too; the 900-tick
## lockstep and the random states are P39n2's. Tanks have radius 400 (R = 800).

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


## Row 0 of the far unit and row 1 of the unit at the edge, on a map of COLS x ROWS tiles whose
## units all have a radius that makes them overlap.
func _far_world(far: Vector2i, edge: Vector2i) -> World:
	var world: World = _tanks([far, edge])
	world.type_radius[0] = HUGE_RADIUS
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
