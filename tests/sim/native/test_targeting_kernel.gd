extends GdUnitTestSuite
## The TARGETING kernel at its boundary (ADR 0013 sections 2 and 4, plan P41n): the names it gets
## and sets, the write cases (the target, the order, the goal and the six navigation columns are
## written in place and seen through an alias, a held copy keeps its old values, the two counts are
## added to what the tick has counted, the grid is not rebuilt; also on a worker Thread), the
## guards that C++ cannot leave to the engine (a grid with no cells, no rows of cells or a cell
## side below 1) and the range that core/targeting.h records (positions of 10^9 and reaches of
## 2 * 10^9). Every case builds two identical Worlds, one running the GDScript phase and one the
## C++ kernel, and compares their full state (StateDiff) as well as the values the rule gives. The
## crafted rule cases are in test_targeting_kernel_cases.gd, the line tests in
## test_targeting_kernel_lines.gd; the 900-tick lockstep is P41n2. The module's own suites
## (test_targeting*.gd, test_engagement*.gd) run under both implementations too.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const HEADER: String = "res://native/sim_kernels/src/bind/world_access.h"
const SOURCE: String = "res://native/sim_kernels/src/bind/kernel_targeting.cpp"
const TARGETING: int = SimProbe.Phase.TARGETING
const RIFLE: int = 0
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const CHASE: int = World.NavMode.CHASE
const CANDIDATES: int = World.Stat.TARGET_CANDIDATES
const LINE_CHECKS: int = World.Stat.LINE_CHECKS
## The side of the position range that core/targeting.h records, and the reach that makes two
## units on opposite sides of it exactly in reach: 2 * EDGE, whose square is 4 * 10^18.
const EDGE: int = 1000000000
## What the kernel gets or sets, in table order: the ints, the columns of the World that the pass
## reads or writes, the type and weapon tables, and the targeting grid.
const TARGETING_NAMES: Array[String] = [
	"WORLD.map_cols",
	"WORLD.map_rows",
	"WORLD.tick",
	"WORLD.retarget_period_ticks",
	"WORLD.line_check_period_ticks",
	"WORLD.unit_id",
	"WORLD.owner",
	"WORLD.type_index",
	"WORLD.pos_x",
	"WORLD.pos_y",
	"WORLD.goal_x",
	"WORLD.goal_y",
	"WORLD.order",
	"WORLD.order_target",
	"WORLD.target",
	"WORLD.nav_mode",
	"WORLD.field",
	"WORLD.nav_cell",
	"WORLD.nav_next",
	"WORLD.best_dist",
	"WORLD.stall",
	"WORLD.stats",
	"WORLD.move_cost",
	"WORLD.type_armour",
	"WORLD.type_move_class",
	"WORLD.type_acquire",
	"WORLD.type_weapon",
	"WORLD.weapon_range",
	"WORLD.weapon_min_range",
	"WORLD.weapon_vs_armour",
	"TARGET.cols",
	"TARGET.rows",
	"TARGET.cell_milli",
	"TARGET.head",
	"TARGET.next"
]


## The list of the table is TARGETING_NAMES, and kernel_targeting.cpp names those and no other: a
## name it fetched outside the list would reach the engine without check_world's type test.
func test_targeting_gets_and_sets_exactly_the_names_of_its_list() -> void:
	var row: RegEx = RegEx.create_from_string("^\\s*X\\((\\w+), (\\w+), \\w+, \\w+, ([^)]+)\\)")
	var names: Array[String] = []
	for line: String in FileAccess.get_file_as_string(HEADER).split("\n"):
		var found: RegExMatch = row.search(line)
		if found == null:
			continue
		for token: String in found.get_string(3).split("|"):
			if token.strip_edges() in ["PH_T", "PH_ALL"]:
				names.append("%s.%s" % [found.get_string(1), found.get_string(2)])
	assert_array(names).contains_exactly_in_any_order(TARGETING_NAMES)
	var used: Array[String] = []
	var ids: RegEx = RegEx.create_from_string("\\bID_(WORLD|TARGET)_(\\w+)")
	for found: RegExMatch in ids.search_all(FileAccess.get_file_as_string(SOURCE)):
		var name: String = "%s.%s" % [found.get_string(1), found.get_string(2)]
		if not used.has(name):
			used.append(name)
	assert_array(used).contains_exactly_in_any_order(TARGETING_NAMES)


## An array the call writes in place is seen through an alias taken before it, with no copy held and
## with one (a duplicate() keeps its old values; the member forks once and writes in place after
## that), the two counts are added to what the tick has counted so far, the grid is the one the call
## found, and a second call gives the same state and adds only what it did again.
func test_the_targeting_kernel_writes_in_place_and_sets_what_the_twin_sets() -> void:
	for hold: bool in [false, true]:
		var seen: Dictionary = _write_case(_chasing_pair(), hold)
		assert_dict(seen).override_failure_message("hold %s" % hold).is_equal(_written(hold))


func test_the_targeting_write_cases_give_the_same_observations_on_a_worker_thread() -> void:
	for hold: bool in [false, true]:
		var thread: Thread = Thread.new()
		assert_int(thread.start(_write_case.bind(_chasing_pair(), hold))).is_equal(OK)
		assert_dict(thread.wait_to_finish()).is_equal(_written(hold))


## A grid with no cells (an empty map), no rows of cells or a cell side below 1 finds nobody: a due
## row that keeps no target writes 0 without a scan, and C++ could not divide by a side of 0. The
## rest of the pass still runs (no early return): the ATTACK row keeps its lock and its goal, the
## MOVE row drops its target. The idle rifle squad holds a target that is gone, so its keep check
## fails and it would scan: on the grid as it is it takes enemy 3, the nearer.
func test_a_grid_with_no_cells_or_a_cell_side_below_1_finds_nobody() -> void:
	# [label, what to do to the grid]
	var cases: Array[Array] = [
		["side 0", func(grid: SpatialGrid) -> void: grid.cell_milli = 0],
		["side -5", func(grid: SpatialGrid) -> void: grid.cell_milli = -5],
		["no columns", _emptied.bind(0, 3)],
		["no rows", _emptied.bind(5, 0)],
		["no cells", _emptied.bind(0, 0)],
	]
	for case: Array in cases:
		var pair: Array[World] = _pair(_scan_world)
		for world: World in pair:
			# The grid is rebuilt first and then taken apart: its own rebuild divides by the side.
			world.prepare()
			world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
			case[1].call(world.target_grid)
			Targeting.run(world)
			var label: String = "%s, native %s" % [case[0], world.native_phases != 0]
			assert_array(world.target.slice(0, 5)).override_failure_message(label).is_equal(
				[0, 0, 0, 0, 3]
			)
			assert_int(world.stats[CANDIDATES]).override_failure_message(label).is_equal(0)
			assert_array([world.order[4], world.goal_x[4]]).is_equal([World.Order.ATTACK, 11000])
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case[0]).is_empty()
	# The same World on the grid as it is: the scan finds the nearer enemy.
	for world: World in _pair(_scan_world):
		Rig.acquire(world)
		assert_array(world.target.slice(0, 5)).is_equal([3, 0, 0, 0, 3])
		assert_int(world.stats[CANDIDATES]).is_equal(2)


## The positions of the recorded range (core/targeting.h): four units at the corners of the square
## of side 2 * 10^9, in a map of one tile (the grid has one cell, which clamps them all into it).
## Each is attack-moving with an acquire range of 2 * 10^9 and sees the unit across an edge exactly
## at its reach (d2 = 4 * 10^18, inclusive), the unit across the diagonal not at all (d2 = 8 *
## 10^18, below 2^63). The first unit has two candidates at the same distance and the same percent,
## and takes the lower id; the others take the first. The chase line test runs on clamped points.
## The sanitizer build of the library (no -fwrapv) aborts on an overflow, so this case is the
## recorded range's own check.
func test_units_ten_to_the_ninth_apart_do_not_overflow_the_squared_distance() -> void:
	var pair: Array[World] = _pair(_corner_world)
	for world: World in pair:
		Rig.acquire(world)
		var label: String = "native %s" % (world.native_phases != 0)
		assert_array(world.target).override_failure_message(label).is_equal([2, 1, 1, 0])
		# Each of the 4 units looks at the other 3.
		assert_int(world.stats[CANDIDATES]).override_failure_message(label).is_equal(4 * 3)
		# The three that have a target are out of weapon range (1000) and in acquire range.
		assert_array(world.nav_mode.slice(0, 4)).override_failure_message(label).is_equal(
			[CHASE, CHASE, CHASE, World.NavMode.NONE]
		)
		assert_int(world.stats[LINE_CHECKS]).override_failure_message(label).is_equal(3)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## What `_write_case` finds when the kernel writes in place: every observation true, and only a held
## copy keeps its old values.
func _written(hold: bool) -> Dictionary:
	var seen: Dictionary = {"alias": true, "member": true, "scalars": true, "grid": true}
	seen.merge({"tables": true, "again": true, "copy_kept": hold})
	return seen


## Rig.acquire on both Worlds of `_chasing_pair` (the first runs the twin, the second the kernel),
## observed on the Thread that calls it. `hold` keeps a duplicate() of `target` across the call.
static func _write_case(pair: Array[World], hold: bool) -> Dictionary:
	var twin: World = pair[0]
	var world: World = pair[1]
	var alias: PackedInt32Array = world.target
	var modes: PackedInt32Array = world.nav_mode
	var copy: PackedInt32Array = world.target.duplicate() if hold else PackedInt32Array()
	# Own storage: a duplicate() shares its buffer with `copy` until one of them is written.
	var old_values: Array = Array(copy)
	var seen: Dictionary = {}
	for each: World in pair:
		each.stats[CANDIDATES] = 5
		each.stats[LINE_CHECKS] = 3
	Rig.acquire(twin)
	Rig.acquire(world)
	seen["alias"] = alias == twin.target and alias[0] == 2 and modes[0] == CHASE
	seen["member"] = world.target == twin.target and world.nav_mode == twin.nav_mode
	# One row looked at, one line checked, on top of what the tick had counted.
	seen["scalars"] = world.stats == twin.stats
	seen["scalars"] = seen["scalars"] and world.stats[CANDIDATES] == 5 + 1
	seen["scalars"] = seen["scalars"] and world.stats[LINE_CHECKS] == 3 + 1
	var heads: PackedInt32Array = world.target_grid.head.duplicate()
	var links: PackedInt32Array = world.target_grid.next.duplicate()
	seen["tables"] = StateDiff.first(world, twin) == ""
	# Kept only if the write forked: a write through the held buffer would change `copy` as well.
	seen["copy_kept"] = hold and Array(copy) == old_values and copy != world.target
	# A second call on the grid it found: the target is kept (no scan), the chase is checked again.
	Targeting.run(twin)
	Targeting.run(world)
	seen["again"] = StateDiff.first(world, twin) == "" and world.target == alias
	seen["again"] = seen["again"] and world.stats[CANDIDATES] == 5 + 1
	seen["again"] = seen["again"] and world.stats[LINE_CHECKS] == 3 + 2
	seen["grid"] = world.target_grid.head == heads and world.target_grid.next == links
	return seen


## Two Worlds from the same builder, the first running the GDScript phase and the second the kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		pair.append(_in(build.call(), impl))
	return pair


func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
	return world


## An attack-moving rifle squad (id 1) 4800 from an idle one (id 2), at tick 4, its turn: it takes
## the enemy (one row looked at) and chases (one line check). Rifle: range 4000, acquire 5000.
func _chasing_pair() -> Array[World]:
	return _pair(_chasing_world)


func _chasing_world() -> World:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 4000, 6000)
	world.add_unit(2, RIFLE, 8800, 6000)
	world.order[0] = ATTACK_MOVE
	world.tick = Rig.due_tick_for(world, 1)
	return world


## Five units on the 20 x 12 map (5 x 3 cells of 4000) at tick 4, where only id 1 is due: an idle
## rifle squad (id 1, row 0) holding the target 99, which is gone, with enemies 2 (12000, 6000) and
## 3 (11000, 6000) around it (on the grid as it is it takes the nearer, 3); a MOVE row (id 4) that
## holds a stale target (cleared); and an ATTACK row (id 5) locked on enemy 3, whose lock and goal
## do not depend on the grid.
func _scan_world() -> World:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 12000, 6000)
	world.add_unit(2, RIFLE, 11000, 6000)
	world.add_unit(1, RIFLE, 2000, 2000)
	world.add_unit(1, RIFLE, 2000, 9000)
	world.target[0] = 99
	world.order[3] = World.Order.MOVE
	world.target[3] = 2
	world.order[4] = World.Order.ATTACK
	world.order_target[4] = 3
	world.tick = Rig.due_tick_for(world, 1)
	return world


## One tile, four armed units at the corners of the square of side 2 * EDGE (top left, top right,
## bottom left, bottom right). Owners 1, 2, 2, 2 with an acquire range of 2 * EDGE and a weapon
## range of 1000; every unit is due, and on its line-check turn, on every tick.
func _corner_world() -> World:
	var gun: UnitDef = Rig.unit(&"gun", 8000, 2 * EDGE, 1000, 0, [100, 100, 100, 100])
	var world: World = Rig.world_of([gun], 1, 1)
	world.retarget_period_ticks = 1
	world.line_check_period_ticks = 1
	var corners: Array[Vector2i] = [
		Vector2i(-EDGE, -EDGE), Vector2i(EDGE, -EDGE), Vector2i(-EDGE, EDGE), Vector2i(EDGE, EDGE)
	]
	for index: int in 4:
		world.add_unit(1 if index == 0 else 2, 0, corners[index].x, corners[index].y)
		world.order[index] = ATTACK_MOVE
	return world


func _emptied(grid: SpatialGrid, cols: int, rows: int) -> void:
	grid.cols = cols
	grid.rows = rows
	grid.head.resize(cols * rows)
	grid.head.fill(-1)
