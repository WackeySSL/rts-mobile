extends GdUnitTestSuite
## The FOG kernel at its boundary (ADR 0013 sections 2 and 4, plan P46n): the names it gets and
## sets, the write cases (the visible counts, the explored bytes, the dirty-list blocks with their
## counts, the `listed` marks, the version and `fog_cell` are written in place and seen through an
## alias, a held copy keeps its old values, the cells covered are added to what the tick has
## counted; also on a worker Thread), the guards that C++ cannot leave to the engine (a grid whose
## sides do not make its cells, a World with no players), the rows the update skips (an owner of 0,
## past player_count or below 0; a `fog_cell` of -1, below -1, equal to the cell, or elsewhere) and
## the range that core/fog.h records (positions at the ends of int32, counts, the version and the
## tick's count at the top of int32). Every case builds two identical Worlds, one running the
## GDScript phase and one the C++ kernel, and compares their full state (StateDiff) as well as the
## values the rule gives. The module's own suites (test_fog.gd, test_fog_edges.gd and
## test_fog_grid.gd) run under both implementations too; the 900-tick lockstep and the crafted
## stamp cases are test_fog_lockstep.gd, test_fog_lockstep_cases.gd and test_fog_lockstep_random.gd.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const HEADER: String = "res://native/sim_kernels/src/bind/world_access.h"
const SOURCE: String = "res://native/sim_kernels/src/bind/kernel_fog.cpp"
const FOG: int = SimProbe.Phase.FOG
const FOG_CELLS: int = World.Stat.FOG_CELLS
const SQUARE: int = 30
## Type indexes: 0 sees 6000 (113 cells), 1 sees 2000 (13 cells).
const SCOUT: int = 0
const POST: int = 1
const INT32_MAX: int = 2147483647
const INT32_MIN: int = -2147483648
## What the kernel gets or sets, in table order: the two ints of the World, the columns that the
## update reads or writes, the sight table (its size is the id of the pad mask) and the grid.
const FOG_NAMES: Array[String] = [
	"WORLD.tick",
	"WORLD.fog_period_ticks",
	"WORLD.unit_id",
	"WORLD.owner",
	"WORLD.type_index",
	"WORLD.pos_x",
	"WORLD.pos_y",
	"WORLD.fog_cell",
	"WORLD.stats",
	"WORLD.type_sight",
	"FOG.cols",
	"FOG.rows",
	"FOG.cells",
	"FOG.player_count",
	"FOG.dirty_capacity",
	"FOG.visible",
	"FOG.explored",
	"FOG.listed",
	"FOG.version",
	"FOG.dirty_count",
	"FOG.dirty_full",
	"FOG.dirty",
	"FOG.mask_start",
	"FOG.mask_radius",
	"FOG.mask_half"
]


## The list of the table is FOG_NAMES, and kernel_fog.cpp names those and no other: a name it
## fetched outside the list would reach the engine without check_world's type test.
func test_fog_gets_and_sets_exactly_the_names_of_its_list() -> void:
	var row: RegEx = RegEx.create_from_string("^\\s*X\\((\\w+), (\\w+), \\w+, \\w+, ([^)]+)\\)")
	var names: Array[String] = []
	for line: String in FileAccess.get_file_as_string(HEADER).split("\n"):
		var found: RegExMatch = row.search(line)
		if found == null:
			continue
		for token: String in found.get_string(3).split("|"):
			if token.strip_edges() in ["PH_G", "PH_ALL"]:
				names.append("%s.%s" % [found.get_string(1), found.get_string(2)])
	assert_array(names).contains_exactly(FOG_NAMES)
	var used: Array[String] = []
	var ids: RegEx = RegEx.create_from_string("\\bID_(WORLD|FOG)_(\\w+)")
	for found: RegExMatch in ids.search_all(FileAccess.get_file_as_string(SOURCE)):
		var name: String = "%s.%s" % [found.get_string(1), found.get_string(2)]
		if not used.has(name):
			used.append(name)
	assert_array(used).contains_exactly_in_any_order(FOG_NAMES)
	# And it asks the table about its own phase: a line copied from another kernel with that
	# kernel's PHASE_ would check another list and leave the names above unchecked.
	var asked: Array[String] = []
	var phase: RegEx = RegEx.create_from_string("access_\\.check\\(world, (\\w+)\\)")
	for found: RegExMatch in phase.search_all(FileAccess.get_file_as_string(SOURCE)):
		asked.append(found.get_string(1))
	assert_array(asked).is_equal(["PHASE_FOG"])


## An array the call writes in place is seen through an alias taken before it, with no copy held and
## with one (a duplicate() keeps its old values; the member forks once and writes in place after
## that), the count is added to what the tick has counted so far, and a second call on the state it
## left changes nothing and adds nothing.
func test_the_fog_kernel_writes_in_place_and_sets_what_the_twin_sets() -> void:
	for hold: bool in [false, true]:
		var seen: Dictionary = _write_case(_moving_pair(), hold)
		assert_dict(seen).override_failure_message("hold %s" % hold).is_equal(_written(hold))


func test_the_fog_write_cases_give_the_same_observations_on_a_worker_thread() -> void:
	for hold: bool in [false, true]:
		var thread: Thread = Thread.new()
		assert_int(thread.start(_write_case.bind(_moving_pair(), hold))).is_equal(OK)
		assert_dict(thread.wait_to_finish()).is_equal(_written(hold))


## A grid whose sides do not make its cells (a column less, a row more, none of either, no rows
## and so no cells, 905 cells on 30 columns) is no fog: C++ could not divide by a side of 0, and the
## twin takes the same test so that the two agree. The scout moves a tile at its player's turn and
## nothing is stamped, listed or counted. A World whose rows have no player in it stamps nothing
## either.
func test_a_grid_that_is_not_one_and_a_world_with_no_players_stamp_nothing() -> void:
	var cases: Array[String] = [
		"one column less",
		"one row more",
		"no columns",
		"no rows",
		"sides of -30",
		"no rows, no cells",
		"cells that 30 columns do not divide"
	]
	for case: String in cases:
		var pair: Array[World] = _moving_pair()
		for world: World in pair:
			var before: int = world.fog_cell[0]
			_bend(world.fog, case)
			world.stats[FOG_CELLS] = 4
			FogUpdate.run(world)
			var label: String = "%s, native %s" % [case, world.native_phases != 0]
			assert_int(world.fog_cell[0]).override_failure_message(label).is_equal(before)
			assert_int(world.stats[FOG_CELLS]).override_failure_message(label).is_equal(4)
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(case).is_empty()
	for impl: int in SimImpls.IMPLS:
		var world: World = World.new()
		world.map_w = SQUARE * 1000
		world.map_h = SQUARE * 1000
		world.add_unit(0, 0, 4500, 4500)
		world.prepare()
		_in(world, impl)
		world.pos_x[0] = 6500
		FogUpdate.run(world)
		assert_array([world.fog.player_count, world.fog_cell[0]]).is_equal([0, -1])


## The rows the update skips or treats alike. Seven rows (period 1: every player's turn), six of
## them a tile to the right of where they were stamped: an owner of 0, of 3 (past player_count) and
## of -1 are never moved; a `fog_cell` of -5 only stamps (no unstamp of a cell that is no cell), one
## of another cell moves from there; a row already on its cell does nothing. The grid is stamped as
## the `fog_cell` values say, so no count goes below 0. Compared with the twin's.
func test_rows_of_no_player_and_rows_stamped_nowhere_or_elsewhere() -> void:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = _world()
		world.fog_period_ticks = 1
		for tile: int in 6:
			world.add_unit(1 + tile % 2, POST, _centre(4 * tile + 2), _centre(10))
		world.add_unit(2, POST, _centre(25), _centre(25))
		world.prepare()
		world.owner[2] = 0
		world.owner[3] = 3
		world.owner[4] = -1
		world.fog.stamp(1, 10 * SQUARE + 2, POST, -1)  # Row 0 is stamped nowhere (-5).
		world.fog_cell[0] = -5
		world.fog.stamp(2, 10 * SQUARE + 6, POST, -1)  # Row 1 is stamped on (7, 7) instead.
		world.fog.stamp(2, 7 * SQUARE + 7, POST, 1)
		world.fog_cell[1] = 7 * SQUARE + 7
		for row: int in 6:
			world.pos_x[row] += 1000
		_in(world, impl)
		FogUpdate.run(world)
		var label: String = "native %s" % (world.native_phases != 0)
		var expected: Array = [10 * SQUARE + 3, 10 * SQUARE + 7, 10 * SQUARE + 10]
		expected.append_array(
			[10 * SQUARE + 14, 10 * SQUARE + 18, 10 * SQUARE + 23, 25 * SQUARE + 25]
		)
		assert_array(world.fog_cell).override_failure_message(label).is_equal(expected)
		assert_int(_negatives(world.fog.visible)).override_failure_message(label).is_equal(0)
		pair.append(world)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The ends of the ranges that core/fog.h records, with the sanitizer build (no -fwrapv) as the
## judge of any overflow: positions at both ends of int32 (clamped to the nearest edge cell, the
## way World.cell_of does), and a visible count, the version and the tick's count at the top of
## int32, which wrap as the twin's Packed arrays do. A stamp at the count INT32_MAX adds 1 to it
## in 64 bits, so the cell stays visible (explored, not flipped), and the unstamp that follows
## reads the stored INT32_MIN and stores INT32_MAX again.
func test_positions_and_counts_at_the_ends_of_int32_behave_as_the_twin() -> void:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = _world()
		world.fog_period_ticks = 1
		for tile: int in 4:
			world.add_unit(1, POST, _centre(4 * tile + 2), _centre(10))
		world.add_unit(1, SCOUT, _centre(10), _centre(20))
		world.prepare()
		world.fog.begin_update(1)
		_in(world, impl)
		world.pos_x[0] = INT32_MAX
		world.pos_y[0] = INT32_MAX
		world.pos_x[1] = INT32_MIN
		world.pos_y[1] = INT32_MIN
		world.pos_x[2] = INT32_MAX
		world.pos_y[2] = INT32_MIN
		world.pos_x[3] = INT32_MIN
		world.pos_y[3] = INT32_MAX
		# The scout moves to (11, 20); the cell it moves onto is at INT32_MAX in both discs.
		world.pos_x[4] = _centre(11)
		world.fog.visible[20 * SQUARE + 11] = INT32_MAX
		# A cell that only the old disc covers, seen once and not explored (a state the sim never
		# makes): its unstamp turns it dark and leaves the byte alone, as only a count above 0 sets it.
		world.fog.explored[20 * SQUARE + 4] = 0
		world.fog.version[0] = INT32_MAX
		world.stats[FOG_CELLS] = INT32_MAX - 100
		FogUpdate.run(world)
		var label: String = "native %s" % (world.native_phases != 0)
		var corners: Array = [SQUARE * SQUARE - 1, 0, SQUARE - 1, SQUARE * (SQUARE - 1)]
		corners.append(20 * SQUARE + 11)
		assert_array(world.fog_cell).override_failure_message(label).is_equal(corners)
		# Four posts: a disc of 13 cells that is whole before, and 6 at a corner after; the scout's
		# two discs of 113 are whole. The sum wraps at int32.
		var covered: int = 4 * (13 + 6) + 2 * 113
		assert_int(world.stats[FOG_CELLS]).override_failure_message(label).is_equal(
			INT32_MAX - 100 + covered - (1 << 32)
		)
		assert_int(world.fog.visible[20 * SQUARE + 11]).override_failure_message(label).is_equal(
			INT32_MAX
		)
		assert_int(world.fog.version[0]).override_failure_message(label).is_less(0)
		assert_int(world.fog.visible[20 * SQUARE + 4]).override_failure_message(label).is_equal(0)
		assert_int(world.fog.explored[20 * SQUARE + 4]).override_failure_message(label).is_equal(0)
		pair.append(world)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A type past the sight table takes the pad mask (sight 0, its own cell), the mask that follows
## one per type, and not whatever the tables hold at its own index: with the sights 6500 and 2500
## the first row of the first mask is 2 tiles wide, which a row of the type 7 would show if the
## kernel took a mask id past the tables (reads give 0 outside them, so its radius would be 0 and
## its first half-width the first mask's). Type 2, the id of the pad mask itself, sees one cell too.
@warning_ignore("integer_division")
func test_a_type_past_the_sight_table_takes_the_pad_mask() -> void:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = World.new()
		world.map_w = SQUARE * 1000
		world.map_h = SQUARE * 1000
		world.type_ids.append_array([&"scout", &"post"])
		world.type_sight.append_array([6500, 2500])
		world.fog_period_ticks = 1
		world.add_unit(1, 7, _centre(10), _centre(10))
		world.add_unit(1, 2, _centre(20), _centre(20))
		world.add_unit(1, 1, _centre(5), _centre(25))
		world.prepare()
		_in(world, impl)
		assert_array(world.fog.mask_radius).is_equal([6, 2, 0])
		world.pos_x[0] = _centre(11)
		world.pos_x[1] = _centre(21)
		world.pos_x[2] = _centre(6)
		FogUpdate.run(world)
		var label: String = "native %s" % (world.native_phases != 0)
		var seen: PackedInt32Array = PackedInt32Array()
		for cell: int in world.fog.cells:
			if world.fog.visible[cell] > 0 and absi(cell / SQUARE - 25) > 2:
				seen.append(cell)
		assert_array(seen).override_failure_message(label).is_equal(
			[10 * SQUARE + 11, 20 * SQUARE + 21]
		)
		pair.append(world)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## What `_write_case` finds when the kernel writes in place: every observation true, and only a held
## copy keeps its old values.
func _written(hold: bool) -> Dictionary:
	var seen: Dictionary = {"alias": true, "member": true, "scalars": true, "blocks": true}
	seen.merge({"marks": true, "again": true, "copy_kept": hold})
	return seen


## FogUpdate.run on both Worlds of `_moving_pair` (the first runs the twin, the second the kernel),
## observed on the Thread that calls it. `hold` keeps a duplicate() of `visible` across the call.
static func _write_case(pair: Array[World], hold: bool) -> Dictionary:
	var twin: World = pair[0]
	var world: World = pair[1]
	var fog: FogGrid = world.fog
	var counts: PackedInt32Array = fog.visible
	var explored: PackedByteArray = fog.explored
	var marks: PackedByteArray = fog.listed
	var cells: PackedInt32Array = world.fog_cell
	var copy: PackedInt32Array = fog.visible.duplicate() if hold else PackedInt32Array()
	# Own storage: a duplicate() shares its buffer with `copy` until one of them is written.
	var old_values: Array = Array(copy)
	var before: PackedInt32Array = fog.visible.duplicate()
	var seen: Dictionary = {}
	for each: World in pair:
		each.stats[FOG_CELLS] = 7
		each.fog.begin_update(1)
		each.fog.begin_update(2)
	FogUpdate.run(twin)
	FogUpdate.run(world)
	seen["alias"] = counts == twin.fog.visible and counts != before
	seen["alias"] = seen["alias"] and explored == twin.fog.explored and cells == twin.fog_cell
	seen["alias"] = seen["alias"] and cells[0] == 10 * SQUARE + 11
	seen["member"] = world.fog.visible == twin.fog.visible and world.fog_cell == twin.fog_cell
	# The scout's two discs of 113 cells, on top of what the tick had counted.
	seen["scalars"] = world.stats == twin.stats and world.stats[FOG_CELLS] == 7 + 2 * 113
	seen["scalars"] = seen["scalars"] and world.fog.version == twin.fog.version
	seen["scalars"] = seen["scalars"] and world.fog.version_of(1) == twin.fog.version_of(1)
	# 13 cells came into view and 13 went out: the block of player 1 holds 26, once each.
	seen["blocks"] = (
		world.fog.dirty_count == twin.fog.dirty_count and world.fog.dirty_count[0] == 26
	)
	seen["blocks"] = seen["blocks"] and world.fog.dirty == twin.fog.dirty
	seen["blocks"] = seen["blocks"] and world.fog.dirty_full == twin.fog.dirty_full
	seen["marks"] = marks == twin.fog.listed and marks.count(1) == 26
	seen["marks"] = seen["marks"] and StateDiff.first(world, twin) == ""
	# Kept only if the write forked: a write through the held buffer would change `copy` as well.
	seen["copy_kept"] = hold and Array(copy) == old_values and copy != world.fog.visible
	# A second call on the state it left: the row is on its cell, so nothing moves or counts.
	FogUpdate.run(twin)
	FogUpdate.run(world)
	seen["again"] = StateDiff.first(world, twin) == "" and counts == twin.fog.visible
	seen["again"] = seen["again"] and world.stats[FOG_CELLS] == 7 + 2 * 113
	seen["again"] = seen["again"] and world.fog.dirty_count[0] == 26
	return seen


## Makes the grid of `fog` (30 x 30, 900 cells) say something that configure() never does.
func _bend(fog: FogGrid, how: String) -> void:
	match how:
		"one column less":
			fog.cols = SQUARE - 1
		"one row more":
			fog.rows = SQUARE + 1
		"no columns":
			fog.cols = 0
		"no rows":
			fog.rows = 0
		"no rows, no cells":
			fog.configure(SQUARE, 0, 2)
		"cells that 30 columns do not divide":
			_resize_blocks(fog, SQUARE * SQUARE + 5)
		_:
			fog.cols = -SQUARE
			fog.rows = -SQUARE


## Gives the grid `cells` cells with the arrays that its checked sizes ask for (player_count blocks
## of cells, and of a quarter of them for the dirty lists), whatever its sides are.
@warning_ignore("integer_division")
func _resize_blocks(fog: FogGrid, cells: int) -> void:
	fog.cells = cells
	fog.dirty_capacity = cells / 4
	fog.visible.resize(fog.player_count * cells)
	fog.explored.resize(fog.player_count * cells)
	fog.listed.resize(fog.player_count * cells)
	fog.dirty.resize(fog.player_count * fog.dirty_capacity)


## Two Worlds from the same builder, the first running the GDScript phase and the second the kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		pair.append(_in(build.call(), impl))
	return pair


func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, FOG)).is_empty()
	return world


func _moving_pair() -> Array[World]:
	return _pair(_moving_world)


## A scout of player 1 (sight 6000) that has moved one tile since prepare() stamped it, and a post
## of player 2, on the 30 x 30 map at tick 0, which is player 1's turn: the update moves the scout's
## disc (113 cells) one tile along its row.
func _moving_world() -> World:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(2, POST, _centre(20), _centre(20))
	world.prepare()
	world.pos_x[0] = _centre(11)
	return world


## A World of 30 x 30 tiles with two players' types: a scout (sight 6000) and a post (2000).
func _world() -> World:
	var world: World = World.new()
	world.map_w = SQUARE * 1000
	world.map_h = SQUARE * 1000
	world.type_ids.append_array([&"scout", &"post"])
	world.type_sight.append_array([6000, 2000])
	return world


## The middle of tile `tile` in milli-tiles.
func _centre(tile: int) -> int:
	return tile * 1000 + 500


## How many counts are below 0.
func _negatives(counts: PackedInt32Array) -> int:
	var below: int = 0
	for count: int in counts:
		if count < 0:
			below += 1
	return below
