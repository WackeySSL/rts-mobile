extends GdUnitTestSuite
## The SEPARATION kernel at its boundary (ADR 0013 sections 2 and 4, plan P39n): the names it gets
## and sets, the write cases (the pushes are written in place and seen through an alias, a held
## copy keeps its old values, the pair count is added to what the tick has counted, the grid is not
## rebuilt; also on a worker Thread), the guards that C++ cannot leave to the engine (a grid with
## no cells, a cell side below 1) and the ranges that core/separation.h records (positions of 10^9
## in a map of one cell, the largest divisor of the data's radii, a reach of up to 2 million, and
## the shipped data against the range). Every case builds two identical
## Worlds, one running the GDScript phase and one the C++ kernel, and compares their full state
## (StateDiff) as well as the values the rule gives. The crafted rule cases are in
## test_separation_kernel_cases.gd; the 900-tick lockstep is P39n2's.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const HEADER: String = "res://native/sim_kernels/src/bind/world_access.h"
const SOURCE: String = "res://native/sim_kernels/src/bind/kernel_separation.cpp"
const SEPARATION: int = SimProbe.Phase.SEPARATION
const COLS: int = 20
const ROWS: int = 8
## The side of the position range that core/separation.h records, and a divisor that the data's
## radii (at most 500, a reach of at most 1000) allow: reach * divisor stays at or below 3037000499.
const EDGE: int = 1000000000
const LARGE_DIVISOR: int = 3037000
## The other two limits of the range that core/separation.h records: a reach (the sum of two radii)
## of at most 2^21 - 1, so that reach^3 stays below 2^63, and reach * divisor of at most the
## integer square root of INT64_MAX.
const REACH_MAX: int = 2097151
const PRODUCT_MAX: int = 3037000499
const UNITS_DIR: String = "res://data/units"
const RULES_PATH: String = "res://data/rules.tres"
## What the kernel gets or sets, in table order: the rule ints, the columns of the World that the
## pass reads or writes, and the separation grid.
const SEPARATION_NAMES: Array[String] = [
	"WORLD.separation_neighbours",
	"WORLD.separation_scan",
	"WORLD.separation_idle_share",
	"WORLD.separation_push_max",
	"WORLD.separation_coincident_divisor",
	"WORLD.unit_id",
	"WORLD.type_index",
	"WORLD.pos_x",
	"WORLD.pos_y",
	"WORLD.intent_x",
	"WORLD.intent_y",
	"WORLD.push_x",
	"WORLD.push_y",
	"WORLD.stats",
	"WORLD.type_radius",
	"SEP.cols",
	"SEP.rows",
	"SEP.cell_milli",
	"SEP.head",
	"SEP.next"
]


## The list of the table is SEPARATION_NAMES, and kernel_separation.cpp names those and no other: a
## name it fetched outside the list would reach the engine without check_world's type test.
func test_separation_gets_and_sets_exactly_the_names_of_its_list() -> void:
	var row: RegEx = RegEx.create_from_string("^\\s*X\\((\\w+), (\\w+), \\w+, \\w+, ([^)]+)\\)")
	var names: Array[String] = []
	for line: String in FileAccess.get_file_as_string(HEADER).split("\n"):
		var found: RegExMatch = row.search(line)
		if found == null:
			continue
		for token: String in found.get_string(3).split("|"):
			if token.strip_edges() in ["PH_S", "PH_ALL"]:
				names.append("%s.%s" % [found.get_string(1), found.get_string(2)])
	assert_array(names).contains_exactly_in_any_order(SEPARATION_NAMES)
	var used: Array[String] = []
	var ids: RegEx = RegEx.create_from_string("\\bID_(WORLD|SEP)_(\\w+)")
	for found: RegExMatch in ids.search_all(FileAccess.get_file_as_string(SOURCE)):
		var name: String = "%s.%s" % [found.get_string(1), found.get_string(2)]
		if not used.has(name):
			used.append(name)
	assert_array(used).contains_exactly_in_any_order(SEPARATION_NAMES)


## An array the call writes in place is seen through an alias taken before it, with no copy held
## and with one (a duplicate() keeps its old values; the member forks once and writes in place
## after that), the pair count is added to the count the tick has so far, the grid and the intents
## are the ones the call found, and a second call gives the same pushes and adds the count again.
func test_the_separation_kernel_writes_in_place_and_sets_what_the_twin_sets() -> void:
	for hold: bool in [false, true]:
		var seen: Dictionary = _write_case(_overlapping_pair(), hold)
		assert_dict(seen).override_failure_message("hold %s" % hold).is_equal(_written(hold))


func test_the_separation_write_cases_give_the_same_observations_on_a_worker_thread() -> void:
	for hold: bool in [false, true]:
		var thread: Thread = Thread.new()
		assert_int(thread.start(_write_case.bind(_overlapping_pair(), hold))).is_equal(OK)
		assert_dict(thread.wait_to_finish()).is_equal(_written(hold))


## A grid with no cells (an empty map, or one whose rows or columns are gone) leaves every push at 0
## and counts nothing, and so does a cell side below 1, which C++ could only divide by: SpatialGrid
## keeps it at 1 or more, and the twin and the kernel both return before the first division. Two
## tanks 100 apart that would push 30 each way on a grid of cells.
func test_a_grid_with_no_cells_or_a_cell_side_below_1_gives_zero_pushes() -> void:
	# [label, what to do to the grid]
	var cases: Array[Array] = [
		["side 0", func(grid: SpatialGrid) -> void: grid.cell_milli = 0],
		["side -5", func(grid: SpatialGrid) -> void: grid.cell_milli = -5],
		["no columns", _emptied.bind(0, ROWS)],
		["no rows", _emptied.bind(COLS, 0)],
		["no cells", _emptied.bind(0, 0)],
	]
	for case: Array in cases:
		var pair: Array[World] = _pair(_close_pair)
		for world: World in pair:
			world.stats.fill(0)
			world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
			case[1].call(world.sep_grid)
			world.push_x.fill(99)
			world.push_y.fill(-99)
			Separation.run(world)
			var label: String = "%s, native %s" % [case[0], world.native_phases != 0]
			assert_array(_pushes(world)).override_failure_message(label).is_equal(_zeros(2))
			assert_int(world.stats[World.Stat.SEP_PAIRS]).override_failure_message(label).is_equal(
				0
			)
			assert_int(world.push_x[world.max_rows - 1]).is_equal(0)
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case[0]).is_empty()
	# The same pair on the grid as it is: the push the cases above would have left.
	for world: World in _pair(_close_pair):
		Rig.separate(world)
		assert_array(_pushes(world)).is_equal([Vector2i(-30, 0), Vector2i(30, 0)])


## A cell side of 1 milli is a grid like any other (the guard is a side below 1): on a map of one
## tile cut into 1,000,000 cells, two tanks 1 milli apart are in neighbouring cells, find each other
## and take the fixed push of 30 each way.
func test_a_cell_side_of_1_milli_is_a_grid_of_its_own() -> void:
	var pair: Array[World] = _pair(_tiny_world)
	for world: World in pair:
		world.sep_grid.configure(world.map_w, world.map_h, 1, world.max_rows)
		assert_int(world.sep_grid.cols).is_equal(1000)
		Rig.separate(world)
		assert_array(_pushes(world)).is_equal([Vector2i(-30, 0), Vector2i(30, 0)])
		assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(2)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The positions of the recorded range (core/separation.h): in a map of one cell, units at the four
## corners of the square of side 2 * 10^9 are all in the one list of the grid, so each looks at the
## others at distances up to 2.8 * 10^9, and d2 reaches 8 * 10^18, below 2^63. Those four overlap no
## one. Two more units stand 100 from two of the corners (rows 4 and 5): each pair pushes, away from
## each other, 30 each along x. The sanitizer build of the library (no -fwrapv) aborts on an
## overflow, so this case is the recorded range's own check.
func test_units_ten_to_the_ninth_apart_do_not_overflow_the_squared_distance() -> void:
	var pair: Array[World] = _pair(_corner_world)
	for world: World in pair:
		Rig.separate(world)
		# Each of the 6 units looks at the other 5.
		assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(6 * 5)
		var wanted: Array[Vector2i] = _zeros(6)
		wanted[0] = Vector2i(-30, 0)
		wanted[3] = Vector2i(30, 0)
		wanted[4] = Vector2i(30, 0)
		wanted[5] = Vector2i(-30, 0)
		assert_array(_pushes(world)).is_equal(wanted)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The largest divisor of the recorded range for the data's radii (500, a reach of 1000): the
## product d2 * divisor * divisor for a pair 999 apart, the farthest overlap, is about 9.2 * 10^18
## and fits. With such a divisor the fixed push is min(1000 / divisor, cap) = 0, so the pair on one
## point does not push, and the formula applies at every other distance: 500 apart the pair push is
## 187 and each unit takes 93 (the cap is lifted to 1000 so that it shows), 999 apart it truncates
## to 0. With the divisor of the rules, 4, the pair on one point takes the fixed push of 250, 125
## each, and the formula's pairs are the same.
func test_the_largest_divisor_of_the_recorded_range_applies_the_formula_to_every_pair() -> void:
	# The divisor, then the push of each of the two units on one point.
	for case: Array in [[LARGE_DIVISOR, 0], [3000000, 0], [4, 125]]:
		var pair: Array[World] = _pair(_squads.bind(case[0]))
		for world: World in pair:
			Rig.separate(world)
			var found: Array[Vector2i] = _pushes(world)
			var label: String = "divisor %d, native %s" % [case[0], world.native_phases != 0]
			assert_array(found.slice(0, 2)).override_failure_message(label).is_equal(
				[Vector2i(-93, 0), Vector2i(93, 0)]
			)
			assert_array(found.slice(2, 4)).override_failure_message(label).is_equal(_zeros(2))
			assert_array(found.slice(4)).override_failure_message(label).is_equal(
				[Vector2i(-case[1], 0), Vector2i(case[1], 0)]
			)
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The reach of the recorded range, far above what the data's radii give (a reach of 1000): units
## of radius 40,000 to 1,048,575 (a reach of 80,000 to 2,097,150, the top of the range) in a map of
## one cell, with the cap lifted to 2 * 10^9 and the divisors 1, 2, 4 and 1000. Squared, a reach
## above 46,341 does not fit 32 bits, and the weight R*R - d2 and the products with the divisor and
## with the distance are wider still, so a pass that narrowed any of them gives other pushes than
## the twin. Nothing here overflows 64 bits (the sanitizer build of the library checks that). Seven
## units: four at the corners of a 1,200,000 x 1,500,000 box, two on one point and a third 100 east
## of them, the second unit moving. Not vacuous: all 7 * 6 looks are made and something is pushed.
func test_a_reach_far_above_32768_gives_the_pushes_of_the_twin() -> void:
	# [radius, divisor]
	var cases: Array[Array] = [
		[1000000, 4],
		[1000000, 1],
		[60000, 4],
		[40000, 4],
		[1000000, 1000],
		[1048575, 2],
	]
	for case: Array in cases:
		var label: String = "radius %d, divisor %d" % case
		var pair: Array[World] = _pair(_wide_world.bind(case[0], case[1]))
		for world: World in pair:
			Rig.separate(world)
			assert_int(world.stats[World.Stat.SEP_PAIRS]).override_failure_message(label).is_equal(
				7 * 6
			)
		assert_array(pair[1].push_x).override_failure_message(label).is_equal(pair[0].push_x)
		assert_array(pair[1].push_y).override_failure_message(label).is_equal(pair[0].push_y)
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(label).is_empty()
		var pushed: bool = Array(pair[0].push_x).any(func(push: int) -> bool: return push != 0)
		assert_bool(pushed).override_failure_message("%s pushes nothing" % label).is_true()


## The recorded range against the shipped data (core/separation.h): the largest reach any two units
## of data/units can make, and that reach times the rule's coincident divisor. test_defs_data keeps
## every radius in 1..500 and pins the rule at 4; this is the relation the sanitizer build would
## otherwise be the only one to check, so a rule or a unit file that leaves the range fails here.
func test_the_shipped_radii_and_divisor_stay_inside_the_recorded_range() -> void:
	var rules: RulesDef = load(RULES_PATH)
	var largest: int = 0
	var files: Array[String] = FileScan.list_files(UNITS_DIR, ".tres")
	for path: String in files:
		var unit: UnitDef = load(path)
		largest = maxi(largest, unit.radius)
	assert_int(files.size()).is_greater_equal(3)
	var reach: int = 2 * largest
	assert_int(reach).is_between(1, REACH_MAX)
	assert_int(rules.separation_coincident_divisor).is_greater(0)
	assert_int(reach * rules.separation_coincident_divisor).is_less_equal(PRODUCT_MAX)


## What `_write_case` finds when the kernel writes in place: every observation true, and only a
## held copy keeps its old values.
func _written(hold: bool) -> Dictionary:
	var seen: Dictionary = {"alias": true, "member": true, "scalars": true, "grid": true}
	seen.merge({"tables": true, "again": true, "copy_kept": hold})
	return seen


## Rig.separate on both Worlds of `_overlapping_pair` (the first runs the twin, the second the
## kernel), observed on the Thread that calls it. `hold` keeps a duplicate() of `push_x` across the
## call.
static func _write_case(pair: Array[World], hold: bool) -> Dictionary:
	var twin: World = pair[0]
	var world: World = pair[1]
	var alias: PackedInt32Array = world.push_x
	var copy: PackedInt32Array = world.push_x.duplicate() if hold else PackedInt32Array()
	# Own storage: a duplicate() shares its buffer with `copy` until one of them is written.
	var old_values: Array = Array(copy)
	var seen: Dictionary = {}
	twin.stats[World.Stat.SEP_PAIRS] = 5
	world.stats[World.Stat.SEP_PAIRS] = 5
	Rig.separate(twin)
	Rig.separate(world)
	seen["alias"] = alias == twin.push_x and alias[0] == -60 and alias[1] == 60
	seen["member"] = world.push_x == twin.push_x and world.push_y == twin.push_y
	seen["scalars"] = world.stats == twin.stats and world.stats[World.Stat.SEP_PAIRS] == 5 + 2
	var heads: PackedInt32Array = world.sep_grid.head.duplicate()
	var links: PackedInt32Array = world.sep_grid.next.duplicate()
	seen["tables"] = StateDiff.first(world, twin) == ""
	# Kept only if the write forked: a write through the held buffer would change `copy` as well.
	seen["copy_kept"] = hold and Array(copy) == old_values and copy != world.push_x
	# A second call on the grid it found: the same pushes, the count added again, no grid change.
	var pushes: PackedInt32Array = world.push_x.duplicate()
	Separation.run(world)
	seen["again"] = world.push_x == pushes and world.stats[World.Stat.SEP_PAIRS] == 5 + 4
	seen["grid"] = world.sep_grid.head == heads and world.sep_grid.next == links
	return seen


## Two Worlds from the same builder, the first running the GDScript phase and the second the kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		pair.append(_in(build.call(), impl))
	return pair


func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SEPARATION)).is_empty()
	return world


## Two tanks 600 apart: the pair push of 131 is cut to 60 for each.
func _overlapping_pair() -> Array[World]:
	return _pair(_close_pair.bind(600))


## Two tanks `gap` apart along x (100: the fixed push of 30 each way).
func _close_pair(gap: int = 100) -> World:
	return _tanks([Vector2i(5000, 4000), Vector2i(5000 + gap, 4000)])


## A prepared open map of COLS x ROWS tiles with a tank (type 0, radius 400) at each point.
func _tanks(points: Array[Vector2i]) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	for point: Vector2i in points:
		world.add_unit(1, 0, point.x, point.y)
	return world


## A map of one tile with two tanks 1 milli apart, for the grid of 1-milli cells.
func _tiny_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(1, 1))
	world.add_unit(1, 0, 500, 500)
	world.add_unit(1, 0, 501, 500)
	return world


## A map of one tile: a grid of one cell, in which units anywhere in the int32 range are listed.
## Rows 0 to 3 stand at the corners of the square of side 2 * EDGE (top left, top right, bottom
## left, bottom right); row 4 stands 100 east of the first, row 5 100 west of the last.
func _corner_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(1, 1))
	for corner: Vector2i in [
		Vector2i(-EDGE, -EDGE),
		Vector2i(EDGE, -EDGE),
		Vector2i(-EDGE, EDGE),
		Vector2i(EDGE, EDGE),
		Vector2i(-EDGE + 100, -EDGE),
		Vector2i(EDGE - 100, EDGE)
	]:
		world.add_unit(1, 0, corner.x, corner.y)
	return world


## Seven units of radius `radius` in a map of one cell (so that all are in one list), with the
## cap, the neighbours and the looks lifted: rows 0 to 3 at the corners of a 1,200,000 x 1,500,000
## box, rows 4 and 5 on one point (300000, 300000) and row 6 100 east of them; row 1 is moving.
func _wide_world(radius: int, divisor: int) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(1, 1))
	for point: Vector2i in [
		Vector2i(0, 0),
		Vector2i(1200000, 0),
		Vector2i(0, 1500000),
		Vector2i(1200000, 1500000),
		Vector2i(300000, 300000),
		Vector2i(300000, 300000),
		Vector2i(300100, 300000)
	]:
		world.add_unit(1, 0, point.x, point.y)
	world.type_radius[0] = radius
	world.separation_push_max = 2000000000
	world.separation_neighbours = 1000
	world.separation_scan = 1000
	world.separation_coincident_divisor = divisor
	world.intent_x[1] = 120
	return world


## Tanks of radius 500 on the map of COLS x ROWS tiles, with `divisor` as the rule and the cap
## lifted to 1000: a pair 500 apart, a pair 999 apart (the farthest overlap) and a pair on one
## point, each alone.
func _squads(divisor: int) -> World:
	var world: World = _tanks(
		[
			Vector2i(2000, 2000),
			Vector2i(2500, 2000),
			Vector2i(8000, 2000),
			Vector2i(8999, 2000),
			Vector2i(14000, 5000),
			Vector2i(14000, 5000)
		]
	)
	world.type_radius[0] = 500
	world.separation_coincident_divisor = divisor
	world.separation_push_max = 1000
	return world


func _emptied(grid: SpatialGrid, cols: int, rows: int) -> void:
	grid.cols = cols
	grid.rows = rows
	grid.head.resize(cols * rows)
	grid.head.fill(-1)


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
