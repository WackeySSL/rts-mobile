extends GdUnitTestSuite
## The crafted crowds of the SEPARATION lockstep (ADR 0013 section 4, plan P39n2): small Worlds
## built to reach one rule of Separation.run, each built twice (the GDScript twin and the C++
## kernel, through tests/sim/support/separation_lockstep_rig.gd) and compared after the phase and
## after every tick of a run: the state hash and the full state of StateDiff. The arena runs are in
## test_separation_lockstep.gd and the seeded random states in test_separation_lockstep_random.gd.
## A case that knows what its crowd must do asserts the counts of the rig's SeparationTallyProbe
## after the first phase (so that it cannot pass by never meeting its rule) and compares the run
## that follows.
##
## The cases: a pile that fills the cap on hits and a lattice that fills the cap on looks (the
## scan stops in the middle of a cell, with the caps in either order); near-coincident pairs at 59
## offsets in every direction, with the lower id on either side, one pair on one point and pairs a
## little inside and outside the limit; units at the four edges and corners of the map, and
## outside it; a map with no cells and a cell side below 1; types of radius 0, 1 and 1000 and a
## negative one; the five rules at the ends of their range and at the edges of their guards; wide
## and tall maps; a table of 256 rows (the capacity); rows that die in the middle of the run.

const Rig: GDScript = preload("res://tests/sim/support/separation_lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TRACKED: int = World.MoveClass.TRACKED
const INT64_MAX: int = 9223372036854775807
const INT64_MIN: int = -9223372036854775808
const INT32_MAX: int = 2147483647
## The offsets, in milli-tiles, of the second unit of a pair from the first: every one of the 49
## from -3 to 3 on both axes, and ten more around the edge of the fixed push (the limit is R / 4 =
## 200 for tanks, R = 800): inside it (141, 141) and (-141, 141) at d2 = 39762, (199, 0) and (0,
## -199); outside it (142, 142) and (-142, -142) at 40328, (200, 0) and (0, 200) at exactly 40000
## (not below the limit), (-201, 1) and (1, 201).
const EDGE_OFFSETS: Array[Vector2i] = [
	Vector2i(141, 141),
	Vector2i(-141, 141),
	Vector2i(142, 142),
	Vector2i(-142, -142),
	Vector2i(199, 0),
	Vector2i(0, -199),
	Vector2i(200, 0),
	Vector2i(0, 200),
	Vector2i(-201, 1),
	Vector2i(1, 201)
]
## The pairs of that list that take the fixed push: 49 near ones, (141, 141), (-141, 141), (199, 0)
## and (0, -199).
const FIXED_OFFSETS: int = 53
## The pairs of the offsets' world stand 2000 apart, 12 to a row, on a map of 24 x 20 tiles.
const PAIR_STEP: int = 2000
const PAIRS_PER_ROW: int = 12
## Rule values around the shipped ones and at the ends of the range of an int. The divisor stops at
## 3,037,000, where reach * divisor (2.4 * 10^9 for tanks) is still inside the recorded range of
## core/separation.h: a larger divisor overflows d2 * divisor * divisor for a pair that is apart.
const SWEEP: Dictionary[StringName, Array] = {
	&"separation_neighbours": [INT64_MIN, -1, 0, 1, 2, 7, 8, 9, 15, 16, 17, 39, 40, INT64_MAX],
	&"separation_scan": [INT64_MIN, -1, 0, 1, 2, 7, 8, 9, 15, 16, 17, 39, 40, INT64_MAX],
	&"separation_idle_share": [INT64_MIN, -1, 0, 1, 74, 75, 99, 100, 101, 1000, INT64_MAX],
	&"separation_push_max": [INT64_MIN, -1, 0, 1, 59, 60, 61, 1000, INT32_MAX, INT64_MAX],
	&"separation_coincident_divisor": [INT64_MIN, -1, 0, 1, 2, 3, 4, 5, 800, 801, 3037000],
}


## 40 tanks within 100 milli of (5000, 4000) overlap one another, so a row stops at the cap on
## hits, or on looks when that is the smaller (the first ones by id, whichever cell they are in).
## Every cap pair gives min(hits cap, looks cap, 39) looks per row; the shipped caps (8 and 16) stop
## every row on hits. The run that follows sends the even ids away, so the pile comes apart with a
## mover beside idle units.
func test_a_pile_fills_the_cap_on_hits_or_on_looks_whichever_is_smaller() -> void:
	# [the cap on hits, the cap on looks]
	for caps: Array in [[8, 16], [3, 5], [16, 8], [1, 1], [39, 39], [40, 100], [2, 1]]:
		var label: String = "caps %d and %d" % caps
		var rig: RefCounted = Rig.new().setup(_pile.bind(caps[0], caps[1]))
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).override_failure_message(label).is_empty()
		var per_row: int = mini(mini(caps[0], caps[1]), 39)
		assert_int(rig.tally()[&"looks"]).override_failure_message(label).is_equal(40 * per_row)
		(
			assert_str(rig.run(60, _send_evens.bind(9000, 7000)))
			. override_failure_message(label)
			. is_empty()
		)
	var shipped: RefCounted = Rig.new().setup(_pile.bind(8, 16))
	shipped.once()
	assert_int(shipped.tally()[&"hits"]).is_equal(320)
	assert_int(shipped.tally()[&"hit_capped"]).is_equal(40)
	assert_int(shipped.tally()[&"look_capped"]).is_equal(0)


## A lattice of 10 x 10 units of radius 50 at 300 apart overlaps nobody (a reach of 100), and
## every unit has more than 16 others in the 3 x 3 cells around its own, so every row stops at the
## cap on looks with no hit: 16 looks each. The cells hold 11 units, so the cap cuts the scan in the
## middle of a cell's list and, from the corners of the lattice, between cells. With tanks (a
## reach of 800) and 450 apart, 7 x 7 units meet both caps. Both are stepped on, the even ids
## moving.
func test_a_lattice_fills_the_cap_on_looks_with_no_hit_and_a_tight_one_meets_both_caps() -> void:
	var sparse: RefCounted = Rig.new().setup(_lattice.bind(10, 300, 50))
	assert_array(sparse.problems).is_empty()
	assert_str(sparse.once()).is_empty()
	assert_int(sparse.tally()[&"looks"]).is_equal(100 * 16)
	assert_int(sparse.tally()[&"hits"]).is_equal(0)
	assert_int(sparse.tally()[&"look_capped"]).is_equal(100)
	assert_str(sparse.run(80, _send_evens.bind(8000, 6000))).is_empty()
	var tight: RefCounted = Rig.new().setup(_lattice.bind(7, 450, 400))
	assert_array(tight.problems).is_empty()
	assert_str(tight.once()).is_empty()
	assert_str(tight.run(80, _send_evens.bind(9000, 7000))).is_empty()
	assert_int(tight.tally()[&"hit_capped"]).is_greater(10)
	assert_int(tight.tally()[&"look_capped"]).is_greater(10)


## 118 pairs of tanks, 59 offsets (EDGE_OFFSETS and the 49 from -3 to 3) each with the lower id at
## the anchor and the higher one at the offset, then the other way round. Every pair overlaps; 53
## offsets are inside the limit of the fixed push, so 106 pairs take it, each seen from both of its
## units: 212 fixed pushes, 236 hits, and the pairs on one point (offset 0, 0) give 4 of them. The
## fixed push is signed by the geometry whichever unit has the lower id. A third of the pairs have
## the lower unit moving and a third the higher one, so a mover and an idle unit share a pair push
## 25 / 75 either way; the run follows for 40 ticks while they come apart.
func test_near_coincident_pairs_at_every_offset_with_either_unit_first_match() -> void:
	var rig: RefCounted = Rig.new().setup(_pairs_world)
	assert_array(rig.problems).is_empty()
	assert_int(rig.worlds[0].unit_count()).is_equal(2 * 118)
	assert_str(rig.once()).is_empty()
	assert_int(rig.tally()[&"hits"]).is_equal(236)
	assert_int(rig.tally()[&"fixed"]).is_equal(2 * 2 * FIXED_OFFSETS)
	assert_int(rig.tally()[&"same_point"]).is_equal(4)
	assert_str(rig.run(40, _move_pair_members)).is_empty()
	assert_int(rig.tally()[&"mixed"]).is_greater(100)


## Piles of five tanks on the four corners and the four edge middles of a map of 12 x 8 tiles, the
## corner ones on the very last milli-tile (11,999 and 7,999) where the grid has its last cell, are
## scanned from a cell at the edge of the grid. A second world has the same piles a little outside
## the map: the grid lists such a unit in the cell nearest it, the scan reads the cells of the
## block that exist and no other, and the unit comes back onto the map as it moves. The even ids
## are sent to the middle of the map.
func test_units_at_the_four_edges_and_corners_and_outside_the_map_match() -> void:
	for outside: int in [0, 350]:
		var label: String = "outside by %d" % outside
		var rig: RefCounted = Rig.new().setup(_edges_world.bind(outside))
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).override_failure_message(label).is_empty()
		if outside == 0:
			assert_int(rig.tally()[&"edge_rows"]).is_equal(40)
		assert_int(rig.tally()[&"hits"]).is_greater(100)
		var found: String = rig.run(80, _send_evens.bind(6000, 4000))
		assert_str(found).override_failure_message(label).is_empty()
		assert_int(rig.tally()[&"edge_rows"]).override_failure_message(label).is_greater(100)


## A map with no cells (nothing to scan: zero pushes and zero looks, the units stand wherever they
## are) and, on a map of cells, a grid whose cell side was set to 0 or below 1 after the rebuild, or
## whose rows or columns were taken away, as the module tests do for one call. Here the whole
## state is compared (hash included) after the phase, and the empty map after 20 ticks as well.
func test_a_map_with_no_cells_and_a_grid_that_cannot_be_scanned_match() -> void:
	var empty: RefCounted = Rig.new().setup(_empty_world)
	assert_array(empty.problems).is_empty()
	assert_int(empty.worlds[0].sep_grid.cols).is_equal(0)
	assert_str(empty.once()).is_empty()
	assert_int(empty.worlds[1].stats[World.Stat.SEP_PAIRS]).is_equal(0)
	assert_array(empty.worlds[1].push_x.slice(0, 5)).is_equal([0, 0, 0, 0, 0])
	assert_str(empty.run(20, _send_evens.bind(5000, 5000))).is_empty()
	assert_int(empty.tally()[&"looks"]).is_equal(0)
	# [label, what to do to the grid after the rebuild]
	var cases: Array[Array] = [
		["side 0", func(grid: SpatialGrid) -> void: grid.cell_milli = 0],
		["side -5", func(grid: SpatialGrid) -> void: grid.cell_milli = -5],
		["no columns", _emptied.bind(0, 8)],
		["no rows", _emptied.bind(20, 0)],
	]
	for case: Array in cases:
		var rig: RefCounted = Rig.new().setup(_lattice.bind(6, 300, 400))
		assert_array(rig.problems).is_empty()
		for world: World in rig.worlds:
			world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
			case[1].call(world.sep_grid)
			world.push_x.fill(99)
			world.push_y.fill(-99)
			world.stats.fill(0)
			Separation.run(world)
		assert_str(rig.compare("the phase")).override_failure_message(case[0]).is_empty()
		assert_int(rig.worlds[1].stats[World.Stat.SEP_PAIRS]).is_equal(0)
		assert_int(rig.worlds[1].push_x.count(0)).is_equal(rig.worlds[1].max_rows)


## A cell side of 1 milli is a grid like any other (the guard is a side below 1): on a map of one
## tile, 1,000 x 1,000 cells, six tanks stand a milli apart in a row, each in a cell of its own, and
## each finds the ones in the cells next to it (the 3 x 3 block is 3 milli wide): 10 looks, all
## hits, the fixed push for each pair. The row is stepped on, with the even ids moving.
func test_a_cell_side_of_1_milli_is_a_grid_of_its_own() -> void:
	var rig: RefCounted = Rig.new().setup(_milli_world)
	assert_array(rig.problems).is_empty()
	assert_int(rig.worlds[1].sep_grid.cols).is_equal(1000)
	assert_str(rig.once()).is_empty()
	assert_int(rig.tally()[&"looks"]).is_equal(10)
	assert_int(rig.tally()[&"hits"]).is_equal(10)
	assert_int(rig.tally()[&"fixed"]).is_equal(10)
	assert_str(rig.run(10, _send_evens.bind(900, 500))).is_empty()


## Units far apart in the one cell of a map of one tile (the grid lists them all in one list, so
## each looks at the other seven), at distances whose square does not fit 32 bits: 46,341 (the
## first square above 2^31, 2,147,488,281), 65,536 (its square is 2^32, which a 32-bit int reads as
## 0: the pair would be a pair on one point), 131,072 and 65,537, on x, on y and on both. No pair of
## tanks overlaps, so nothing is pushed. The sanitizer build of the library checks that no square
## overflows 64 bits.
func test_units_far_apart_in_one_cell_do_not_overlap_whatever_their_square_wraps_to() -> void:
	var rig: RefCounted = Rig.new().setup(_far_apart_world)
	assert_array(rig.problems).is_empty()
	assert_str(rig.once()).is_empty()
	assert_int(rig.tally()[&"looks"]).is_equal(8 * 7)
	assert_int(rig.tally()[&"hits"]).is_equal(0)
	assert_int(rig.worlds[1].push_x.count(0)).is_equal(rig.worlds[1].max_rows)
	assert_str(rig.run(5)).is_empty()


## Seven types of radius 0, 1, 150, 400, 500, 1000 and -100 (a reach below 0 for a pair with a
## small one, and 0 for the pairs of two units of radius 0), 70 units of them, 10 of each, in a
## square of 3000 milli: the pair of a radius 0 and a 1 reach 1 (a hit at distance 0 only), a
## negative reach pushes by a negative fixed push, a reach of 2000 and the pairs of every other
## size. Run for 60 ticks with a third of the units moving, on the shipped rules and on a cap of
## 1000 with a divisor of 1.
func test_types_of_every_radius_including_zero_and_negative_match() -> void:
	for lifted: bool in [false, true]:
		var rig: RefCounted = Rig.new().setup(_radii_world.bind(lifted))
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).override_failure_message("lifted %s" % lifted).is_empty()
		var found: String = rig.run(60, _send_thirds)
		assert_str(found).override_failure_message("lifted %s" % lifted).is_empty()
		assert_int(rig.tally()[&"hits"]).is_greater(500)
		assert_int(rig.tally()[&"fixed"]).is_greater(20)
		assert_int(rig.tally()[&"mixed"]).is_greater(100)


## Each of the five rules at the ends of an int and at the edges of its guard, one at a time on a
## crowd of 36 tanks in a lattice of 350 with six near-coincident pairs among them, 12 ticks each:
## the caps at -1, 0, 1 and around 8 and 16, the idle share at -1, 0, 100, 101 and the ends, the
## push cap at -1, 0, 1, 60 and the ends, the divisor at -1, 0, 1 and up to 3,037,000. Then every
## rule at once at the top of its range and at the bottom (the divisor stays 1 there: past the
## recorded range the squared product overflows, which the sanitizer build aborts on).
func test_each_rule_at_the_ends_of_its_range_and_at_the_edges_of_its_guard_matches() -> void:
	var settings: Array[Dictionary] = []
	for rule: StringName in SWEEP:
		for value: int in SWEEP[rule]:
			settings.append({rule: value})
	settings.append(
		{
			&"separation_neighbours": INT64_MAX,
			&"separation_scan": INT64_MAX,
			&"separation_idle_share": INT64_MAX,
			&"separation_push_max": INT64_MAX,
			&"separation_coincident_divisor": 1
		}
	)
	settings.append(
		{
			&"separation_neighbours": INT64_MIN,
			&"separation_scan": INT64_MIN,
			&"separation_idle_share": INT64_MIN,
			&"separation_push_max": INT64_MIN,
			&"separation_coincident_divisor": INT64_MIN
		}
	)
	var hits: int = 0
	var capped: int = 0
	for setting: Dictionary in settings:
		var rig: RefCounted = Rig.new().setup(_rules_world.bind(setting))
		assert_array(rig.problems).override_failure_message(str(setting)).is_empty()
		assert_str(rig.once()).override_failure_message(str(setting)).is_empty()
		(
			assert_str(rig.run(12, _send_evens.bind(7000, 5000)))
			. override_failure_message(str(setting))
			. is_empty()
		)
		hits += rig.tally()[&"hits"]
		capped += rig.tally()[&"at_cap"]
	assert_int(settings.size()).is_equal(14 + 14 + 11 + 10 + 11 + 2)
	assert_int(hits).is_greater(50000)
	assert_int(capped).is_greater(500)


## Maps whose width and height differ, with 150 tanks in three clusters (at the two ends and in the
## middle): the grid is 40 cells wide and 4 high, then 4 wide and 40 high, so a pass that reads the
## columns for the rows, or a cell index of `line * rows + column`, finds the wrong lists. The even
## ids are sent to the far end.
func test_wide_and_tall_maps_match() -> void:
	for size: Vector2i in [Vector2i(40, 4), Vector2i(4, 40), Vector2i(1, 30), Vector2i(30, 1)]:
		var rig: RefCounted = Rig.new().setup(_clusters_world.bind(size))
		var label: String = "map %s" % size
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).override_failure_message(label).is_empty()
		var far: Vector2i = (size - Vector2i.ONE) * 1000
		var found: String = rig.run(80, _send_evens.bind(far.x, far.y))
		assert_str(found).override_failure_message(label).is_empty()
		assert_int(rig.tally()[&"hits"]).override_failure_message(label).is_greater(1000)
		assert_int(rig.tally()[&"hit_capped"]).override_failure_message(label).is_greater(0)


## The table at its capacity: 256 tanks (max_rows) in a lattice of 16 x 16 at 450 apart, four more
## refused by add_unit. The kernel's views end exactly at the last row. Then the same table with
## the units standing on 9 points only, 28 or 29 on each (the caps stop every row long before the
## end of its lists).
func test_a_table_of_256_rows_matches() -> void:
	for stacked: bool in [false, true]:
		var rig: RefCounted = Rig.new().setup(_full_world.bind(stacked))
		assert_array(rig.problems).is_empty()
		assert_int(rig.worlds[0].unit_count()).is_equal(256)
		assert_int(rig.worlds[0].spawn_refused).is_equal(4)
		assert_str(rig.once()).override_failure_message("stacked %s" % stacked).is_empty()
		assert_int(rig.tally()[&"rows"]).is_equal(256)
		var found: String = rig.run(40, _send_evens.bind(5000, 5000))
		assert_str(found).override_failure_message("stacked %s" % stacked).is_empty()
		assert_int(rig.tally()[&"hit_capped"]).is_greater(100)


## Rows that die in the middle of the run: every 4th tick from tick 3 three units of a crowd of 64
## are left with no hit points, and the tick removes them (the rows close up, the ids no longer run
## 1 to n, and the grid is rebuilt from the rows that are left). The comparison goes on after each
## removal, with movers and idle units among the survivors.
func test_rows_that_die_in_the_middle_of_the_run_match() -> void:
	var rig: RefCounted = Rig.new().setup(_lattice.bind(8, 400, 400))
	assert_array(rig.problems).is_empty()
	assert_int(rig.worlds[0].unit_count()).is_equal(64)
	assert_str(rig.run(60, _kill_and_send)).is_empty()
	# 14 times three rows, some drawn twice in one tick.
	assert_int(rig.worlds[0].unit_count()).is_between(64 - 42, 64 - 30)
	assert_int(rig.tally()[&"hits"]).is_greater(500)


## A World with the table prepared and the types made, on an open map of `cols` x `rows` tiles, one
## type for each radius.
func _map(cols: int, rows: int, radii: Array[int] = [400]) -> World:
	var classes: Array = []
	for _radius: int in radii:
		classes.append(TRACKED)
	var world: World = GridWorld.from_rows(GridWorld.grass(cols, rows), classes)
	for type: int in radii.size():
		world.type_radius[type] = radii[type]
	return world


## 40 tanks within 100 milli of (5000, 4000), the caps `neighbours` and `looks`.
func _pile(neighbours: int, looks: int) -> World:
	var world: World = _map(20, 8)
	var rng: DetRandom = DetRandom.create(39, 31)
	for _unit: int in 40:
		world.add_unit(1, 0, 5000 + rng.next_int(100), 4000 + rng.next_int(100))
	world.separation_neighbours = neighbours
	world.separation_scan = looks
	return world


## `side` x `side` units of radius `radius`, `step` apart from (3000, 2000), row by row, on a map of
## 20 x 8 tiles.
@warning_ignore("integer_division")
func _lattice(side: int, step: int, radius: int) -> World:
	var world: World = _map(20, 8, [radius])
	for unit: int in side * side:
		world.add_unit(1, 0, 3000 + unit % side * step, 2000 + unit / side * step)
	return world


## The 59 offsets of the pairs: the 49 from -3 to 3 on both axes, then EDGE_OFFSETS.
func _offsets() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			found.append(Vector2i(x, y))
	found.append_array(EDGE_OFFSETS)
	return found


## The anchor of pair `k`.
@warning_ignore("integer_division")
func _anchor(k: int) -> Vector2i:
	return Vector2i(1000 + k % PAIRS_PER_ROW * PAIR_STEP, 1000 + k / PAIRS_PER_ROW * PAIR_STEP)


## The 118 pairs of the offsets' case: pairs 0 to 58 have the lower id at the anchor, pairs 59 to
## 117 the higher one.
func _pairs_world() -> World:
	var world: World = _map(24, 20)
	var offsets: Array[Vector2i] = _offsets()
	for k: int in 118:
		var anchor: Vector2i = _anchor(k)
		var other: Vector2i = anchor + offsets[k % 59]
		if k < 59:
			world.add_unit(1, 0, anchor.x, anchor.y)
			world.add_unit(1, 0, other.x, other.y)
		else:
			world.add_unit(1, 0, other.x, other.y)
			world.add_unit(1, 0, anchor.x, anchor.y)
	return world


## Eight piles of five tanks, 100 milli across: the four corners at the last milli-tile, then the
## four edge middles; each `outside` milli further out of the map.
@warning_ignore("integer_division")
func _edges_world(outside: int) -> World:
	var world: World = _map(12, 8)
	var right: int = world.map_w - 1
	var bottom: int = world.map_h - 1
	var anchors: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(right, 0),
		Vector2i(0, bottom),
		Vector2i(right, bottom),
		Vector2i(right / 2, 0),
		Vector2i(right / 2, bottom),
		Vector2i(0, bottom / 2),
		Vector2i(right, bottom / 2)
	]
	var rng: DetRandom = DetRandom.create(39, 33)
	for anchor: Vector2i in anchors:
		var out: Vector2i = Vector2i(
			signi(anchor.x * 2 - right) if anchor.x in [0, right] else 0,
			signi(anchor.y * 2 - bottom) if anchor.y in [0, bottom] else 0
		)
		for _unit: int in 5:
			var at: Vector2i = (
				anchor + out * outside + Vector2i(rng.next_int(100), rng.next_int(100))
			)
			world.add_unit(1, 0, at.x, at.y)
	return world


## A map of 0 x 0 tiles (a grid with no cells) and eight tanks that overlap in pairs.
@warning_ignore("integer_division")
func _empty_world() -> World:
	var world: World = World.new()
	world.type_ids.append(&"tank")
	world.type_speed.append(120)
	world.type_radius.append(400)
	world.type_selection_radius.append(500)
	world.type_spacing.append(1200)
	world.player_count = 1
	world.prepare()
	for unit: int in 8:
		world.add_unit(1, 0, 5000 + unit / 2 * 3000, 4000 + unit % 2 * 100)
	return world


func _emptied(grid: SpatialGrid, cols: int, rows: int) -> void:
	grid.cols = cols
	grid.rows = rows
	grid.head.resize(cols * rows)
	grid.head.fill(-1)


## A map of one tile with eight tanks 46,341, 65,536 and further apart, on a line and on a diagonal.
func _far_apart_world() -> World:
	var world: World = _map(1, 1)
	for at: Vector2i in [
		Vector2i(0, 0),
		Vector2i(46341, 0),
		Vector2i(65536, 0),
		Vector2i(131072, 0),
		Vector2i(0, 65536),
		Vector2i(65537, 65536),
		Vector2i(131072, 131072),
		Vector2i(262144, 65536)
	]:
		world.add_unit(1, 0, at.x, at.y)
	return world


## A map of one tile with a grid of cells 1 milli wide and six tanks at (500, 500) to (505, 500).
func _milli_world() -> World:
	var world: World = _map(1, 1)
	world.sep_grid.configure(world.map_w, world.map_h, 1, world.max_rows)
	for unit: int in 6:
		world.add_unit(1, 0, 500 + unit, 500)
	return world


## 70 units of the seven radii (type = unit % 7) in a square of 3000 milli at (4000, 3000). With
## `lifted` the push cap is 1000 and the divisor 1.
func _radii_world(lifted: bool) -> World:
	var world: World = _map(12, 8, [0, 1, 150, 400, 500, 1000, -100])
	var rng: DetRandom = DetRandom.create(39, 35)
	for unit: int in 70:
		world.add_unit(1, unit % 7, 4000 + rng.next_int(3000), 3000 + rng.next_int(3000))
	if lifted:
		world.separation_push_max = 1000
		world.separation_coincident_divisor = 1
	return world


## 36 tanks in a lattice of 6 x 6 at 350 from (4000, 3000), and six pairs on top of one another
## (50 apart, or on one point), with the rules of `setting` (World member -> value).
func _rules_world(setting: Dictionary) -> World:
	var world: World = _lattice(6, 350, 400)
	for pair: int in 6:
		var at: Vector2i = Vector2i(10000 + pair * 1500, 3000)
		world.add_unit(1, 0, at.x, at.y)
		world.add_unit(1, 0, at.x + pair % 3 * 50, at.y + pair % 2 * 50)
	for member: StringName in setting:
		world.set(member, setting[member])
	return world


## 150 tanks on a map of `size` tiles in three clusters (at the first end, in the middle and at the
## far end of the longer side), each spread over 800 milli in both directions.
@warning_ignore("integer_division")
func _clusters_world(size: Vector2i) -> World:
	var world: World = _map(size.x, size.y)
	var rng: DetRandom = DetRandom.create(39, 41)
	var length: int = maxi(size.x, size.y) * 1000
	for unit: int in 150:
		var along: int = [1500, length / 2, length - 1500][unit % 3] + rng.next_int(800)
		var across: int = mini(size.x, size.y) * 500 + rng.next_int(800) - 400
		world.add_unit(
			1, 0, along if size.x >= size.y else across, across if size.x >= size.y else along
		)
	return world


## 256 tanks in a lattice of 16 x 16 at 450, or with `stacked` on nine points 300 apart.
@warning_ignore("integer_division")
func _full_world(stacked: bool) -> World:
	var world: World = _map(12, 12)
	for unit: int in 260:
		if stacked:
			world.add_unit(1, 0, 3000 + unit % 3 * 300, 3000 + unit / 3 % 3 * 300)
		else:
			world.add_unit(1, 0, 1000 + unit % 16 * 450, 1000 + unit / 16 * 450)
	return world


## At tick 0 the even ids go to (x, y); the odd ones stay where they are.
func _send_evens(world: World, tick: int, x: int, y: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		var ids: PackedInt32Array = PackedInt32Array()
		for row: int in world.unit_count():
			if world.unit_id[row] % 2 == 0:
				ids.append(world.unit_id[row])
		out.append(Command.move(1, ids, x, y))
	return out


## At tick 0 the ids that are 1 or 2 more than a multiple of 3 are sent to different places (the
## ones that are 1 more to the east, the others to the south), the rest stand.
func _send_thirds(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		var east: PackedInt32Array = PackedInt32Array()
		var south: PackedInt32Array = PackedInt32Array()
		for row: int in world.unit_count():
			match world.unit_id[row] % 3:
				1:
					east.append(world.unit_id[row])
				2:
					south.append(world.unit_id[row])
		out.append(Command.move(1, east, 9000, 4500))
		out.append(Command.move(1, south, 5500, 6500))
	return out


## At tick 0 one unit of every third pair walks 800 milli north-east: the lower one of pairs 1, 4,
## ..., the higher one of pairs 2, 5, ... (the ids of pair k are 2k + 1 and 2k + 2).
func _move_pair_members(_world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		for k: int in 118:
			if k % 3 != 0:
				var id: int = 2 * k + 1 + (k % 3 - 1)
				var to: Vector2i = _anchor(k) + Vector2i(800, -800)
				out.append(Command.move(1, PackedInt32Array([id]), to.x, to.y))
	return out


## `_send_evens` towards (6000, 6500) at tick 0; on ticks 3, 7, 11, ... three rows, drawn from a
## stream of the tick, have no hit points left.
func _kill_and_send(world: World, tick: int) -> Array[Command]:
	if tick % 4 == 3 and tick < 59:
		var rng: DetRandom = DetRandom.create(39, 100 + tick)
		for _death: int in 3:
			world.hp[rng.next_int(world.unit_count())] = 0
	return _send_evens(world, tick, 6000, 6500)
