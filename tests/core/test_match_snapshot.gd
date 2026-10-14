extends GdUnitTestSuite
## MatchSnapshot (plan P38s, ADR 0012 section 3, ADR 0011 section 2): the view's copy of a tick.
## The arena (seed 42) is stepped through MatchLoop: player 1 owns ids 1-75, player 2 ids 76-150,
## and both attack-move from tick 0, so units move on every early tick. Before P41, P42b and P46
## the sim writes no target, projectile or fog cell, so the cases write those into the World by
## hand. Every capture gets its match_serial first, as the runner will (plan P38j).

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42

var _world: World
var _loop: MatchLoop
var _queued: Array[Command] = []


func before_test() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	_world = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	_loop = MatchLoop.create(scenario, ARENA_PATH, SEED, _world)


## A death in tick 30 gives the tick a DIED event, so `events` is not empty either, and a terrain
## write (the same terrain) makes map_version 1.
func test_after_30_ticks_every_snapshot_array_equals_its_world_array() -> void:
	_play(29)
	_world.hp[_world.index_of(40)] = 0
	_world.set_terrain(0, _world.terrain[0])
	_play(1)
	var snap: MatchSnapshot = _capture(null, 1)
	var differ: Array[StringName] = []
	for name: StringName in MatchSnapshot.COPIED + [&"events", &"stats"]:
		if snap.get(name) != _world.get(name):
			differ.append(name)
	for name: StringName in FogGrid.HASHED + FogGrid.UNHASHED:
		if snap.fog.get(name) != _world.fog.get(name):
			differ.append(StringName("fog." + name))
	assert_array(differ).is_empty()
	assert_bool(snap.events.is_empty()).is_false()
	assert_bool(snap.fog.visible.is_empty()).is_false()
	(
		assert_array([snap.tick, snap.rows_version, snap.map_version, snap.map_cols, snap.map_rows])
		. is_equal([30, _world.rows_version, 1, _world.map_cols, _world.map_rows])
	)
	assert_int(snap.unit_count()).is_equal(_world.unit_count())
	assert_int(snap.unit_count()).is_equal(149)
	var sizes: Array[int] = []
	for name: StringName in [&"target_row", &"prev_pos_x", &"prev_pos_y"]:
		sizes.append((snap.get(name) as PackedInt32Array).size())
	assert_array(sizes).is_equal([149, 149, 149])


func test_copied_and_not_copied_split_the_world_shape_lists_exactly_once() -> void:
	var shape: PackedStringArray = PackedStringArray()
	for name: StringName in _shape_names():
		shape.append(String(name))
	var union: PackedStringArray = PackedStringArray()
	var both: Array[StringName] = []
	for name: StringName in MatchSnapshot.COPIED + MatchSnapshot.NOT_COPIED:
		union.append(String(name))
	for name: StringName in MatchSnapshot.COPIED:
		if MatchSnapshot.NOT_COPIED.has(name):
			both.append(name)
	shape.sort()
	union.sort()
	assert_array(both).is_empty()
	assert_array(union).is_equal(shape)
	# Every COPIED name is a snapshot property of the World column's type.
	var snap: MatchSnapshot = _capture(null, 1)
	var properties: Array[String] = []
	for property: Dictionary in snap.get_property_list():
		properties.append(property["name"])
	var wrong: Array[StringName] = []
	for name: StringName in MatchSnapshot.COPIED:
		if not properties.has(String(name)) or typeof(snap.get(name)) != typeof(_world.get(name)):
			wrong.append(name)
	assert_array(wrong).is_empty()
	for name: StringName in [&"type_armour", &"weapon_projectile_speed", &"terrain"]:
		assert_bool(MatchSnapshot.COPIED.has(name)).is_true()
	for name: StringName in [&"move_cost", &"terrain_cost"]:
		assert_bool(MatchSnapshot.NOT_COPIED.has(name)).is_true()


func test_each_id_list_is_an_equal_typed_copy_of_the_worlds() -> void:
	assert_array(MatchSnapshot.ID_LISTS).is_equal([&"type_ids", &"weapon_ids", &"terrain_ids"])
	# Declared typed: a new snapshot already holds an empty Array[StringName] under each name.
	var fresh: MatchSnapshot = MatchSnapshot.new()
	for name: StringName in MatchSnapshot.ID_LISTS:
		assert_int((fresh.get(name) as Array).get_typed_builtin()).is_equal(TYPE_STRING_NAME)
	_play(1)
	var snap: MatchSnapshot = _capture(null, 1)
	var shape: Array[StringName] = _shape_names()
	for name: StringName in MatchSnapshot.ID_LISTS:
		var mine: Variant = snap.get(name)
		var theirs: Variant = _world.get(name)
		assert_bool(shape.has(name)).is_false()
		assert_int(typeof(mine)).is_equal(TYPE_ARRAY)
		assert_int((mine as Array).get_typed_builtin()).is_equal(TYPE_STRING_NAME)
		assert_bool((mine as Array).is_empty()).is_false()
		assert_array(mine as Array).is_equal(theirs as Array)
		assert_bool(is_same(mine, theirs)).is_false()


## Units 100 and 150 (the highest id) die in the tick, which is captured with a previous snapshot
## of the same match; the targets are written by hand (the sim sets none before P41). Rows: id 1
## -> 76 (row 75), id 2 -> 149 (the last row, 147), id 80 -> 1 (row 0), ids 3 and 81 -> 100 (gone,
## inside the id range), id 4 -> 150 (gone, above every id), every other unit -> 0 (none).
func test_target_row_is_the_target_row_here_and_minus_one_for_none_or_gone() -> void:
	_play(10)
	var previous: MatchSnapshot = _capture(null, 1)
	var targets: PackedInt32Array = _world.target
	targets[_world.index_of(1)] = 76
	targets[_world.index_of(2)] = 149
	targets[_world.index_of(80)] = 1
	targets[_world.index_of(3)] = 100
	targets[_world.index_of(81)] = 100
	targets[_world.index_of(4)] = 150
	_world.hp[_world.index_of(100)] = 0
	_world.hp[_world.index_of(150)] = 0
	_play(1)
	var snap: MatchSnapshot = _capture(previous, 1)
	assert_array([snap.unit_count(), snap.index_of(100), snap.index_of(150)]).is_equal(
		[148, -1, -1]
	)
	var expected: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		expected.append(snap.index_of(snap.target[row]))
	assert_array(snap.target_row).is_equal(expected)
	var seen: Array[int] = []
	for id: int in [1, 2, 80, 3, 81, 4, 5]:
		seen.append(snap.target_row[snap.index_of(id)])
	assert_array(seen).is_equal([75, 147, 0, -1, -1, -1, -1])
	assert_int(snap.target_row.count(-1)).is_equal(snap.unit_count() - 3)


## The arena's square map, open grass of 7 x 5 and of 5 x 7 tiles (a square map cannot tell a
## column clamp from a row clamp), and a world with no map (map_cols == 0), where every point is
## cell 0. The points are the corners, the edge midpoints, one inside and six outside the map.
func test_cell_of_is_the_world_formula_clamped_and_zero_without_a_map() -> void:
	var worlds: Array[World] = [_world, _grass(7000, 5000), _grass(5000, 7000), _grass(0, 0)]
	var mine: Array = []
	var theirs: Array = []
	for world: World in worlds:
		var snap: MatchSnapshot = MatchSnapshot.new()
		snap.capture(world, null)
		var cells: Array[int] = []
		var expected: Array[int] = []
		for p: Vector2i in _cell_points(world.map_w, world.map_h):
			cells.append(snap.cell_of(p.x, p.y))
			expected.append(world.cell_of(p.x, p.y))
		mine.append(cells)
		theirs.append(expected)
	assert_array(mine).is_equal(theirs)
	# The 7 x 5 map: (6999, 4999) is the last cell, x 7000 clamps to column 6, y 5000 to row 4.
	assert_array((mine[1] as Array).slice(3, 4)).is_equal([34])
	assert_array((mine[1] as Array).slice(9, 13)).is_equal([0, 0, 6, 28])
	assert_int(worlds[3].map_cols).is_equal(0)
	var none: Array = mine[3]
	assert_int(none.count(0)).is_equal(none.size())


func test_prev_is_current_for_another_match_and_the_old_positions_for_the_same() -> void:
	_play(5)
	var first: MatchSnapshot = _capture(null, 1)
	_play(1)
	var other: MatchSnapshot = _capture(first, 2)
	assert_int(other.rows_version).is_equal(first.rows_version)
	assert_bool(other.pos_x == first.pos_x).is_false()
	assert_array(other.prev_pos_x).is_equal(other.pos_x)
	assert_array(other.prev_pos_y).is_equal(other.pos_y)
	var same: MatchSnapshot = _capture(first, 1)
	assert_array(same.prev_pos_x).is_equal(first.pos_x)
	assert_array(same.prev_pos_y).is_equal(first.pos_y)
	var moved: int = 0
	for row: int in same.unit_count():
		if same.prev_pos_x[row] != same.pos_x[row]:
			moved += 1
	assert_int(moved).is_greater(0)


## One more step moves the World's units and rewrites its events and stats; then every copied
## column, id list and the fog of the World are written by hand too. The snapshot keeps the
## values it had at capture.
func test_a_snapshot_never_changes_after_its_capture() -> void:
	_play(20)
	var previous: MatchSnapshot = _capture(null, 1)
	_play(1)
	var snap: MatchSnapshot = _capture(previous, 1)
	var names: Array[StringName] = [
		&"target_row", &"prev_pos_x", &"prev_pos_y", &"prev_proj_id", &"prev_proj_x", &"events"
	]
	names.append_array(MatchSnapshot.COPIED + MatchSnapshot.ID_LISTS + [&"prev_proj_y", &"stats"])
	var kept: Dictionary = {}
	for name: StringName in names:
		kept[name] = snap.get(name).duplicate()
	var fog_kept: Dictionary = {}
	for name: StringName in FogGrid.HASHED + FogGrid.UNHASHED:
		var value: Variant = snap.fog.get(name)
		fog_kept[name] = value if typeof(value) == TYPE_INT else value.duplicate()
	var cell: int = _world.cell_of(_world.pos_x[0], _world.pos_y[0])
	var reads: Array = _fog_reads(snap.fog, cell)
	_play(1)
	var unchanged_world: Array[StringName] = _scribble(_world, snap, cell)
	assert_array(unchanged_world).is_empty()
	var changed: Array[StringName] = []
	for name: StringName in names:
		if snap.get(name) != kept[name]:
			changed.append(name)
	for name: StringName in fog_kept:
		if snap.fog.get(name) != fog_kept[name]:
			changed.append(StringName("fog." + name))
	assert_array(changed).is_empty()
	assert_array(_fog_reads(snap.fog, cell)).is_equal(reads)
	assert_array(_fog_reads(_world.fog, cell)).is_not_equal(reads)


## Units 1 (the first row) and 60 die in tick 11, and units 151 and 152 are added after it: the
## rows change, their count (150) does not. The previous snapshot has a previous of its own, whose
## positions differ from its pos_*, so a walk over the wrong prev source fails.
func test_prev_positions_follow_the_ids_across_deaths_and_spawns() -> void:
	_play(9)
	var older: MatchSnapshot = _capture(null, 1)
	_play(1)
	var previous: MatchSnapshot = _capture(older, 1)
	assert_bool(previous.prev_pos_x == previous.pos_x).is_false()
	_world.hp[_world.index_of(1)] = 0
	_world.hp[_world.index_of(60)] = 0
	_play(1)
	assert_int(_world.add_unit(2, 0, 30500, 20500)).is_equal(151)
	assert_int(_world.add_unit(1, 0, 31500, 21500)).is_equal(152)
	var snap: MatchSnapshot = _capture(previous, 1)
	assert_int(snap.rows_version).is_not_equal(previous.rows_version)
	assert_array([snap.unit_count(), snap.index_of(1), snap.index_of(60)]).is_equal([150, -1, -1])
	var expected_x: PackedInt32Array = PackedInt32Array()
	var expected_y: PackedInt32Array = PackedInt32Array()
	var moved: int = 0
	for row: int in snap.unit_count():
		var old: int = previous.index_of(snap.unit_id[row])
		expected_x.append(previous.pos_x[old] if old >= 0 else snap.pos_x[row])
		expected_y.append(previous.pos_y[old] if old >= 0 else snap.pos_y[row])
		if old >= 0 and previous.pos_x[old] != snap.pos_x[row]:
			moved += 1
	assert_array(snap.prev_pos_x).is_equal(expected_x)
	assert_array(snap.prev_pos_y).is_equal(expected_y)
	assert_int(moved).is_greater(0)
	# Unit 2 moved up to row 0; the new units start where they stand.
	assert_array([snap.prev_pos_x[0], snap.prev_pos_y[0]]).is_equal(
		[previous.pos_x[1], previous.pos_y[1]]
	)
	var spawned: Array[int] = [
		snap.prev_pos_x[148], snap.prev_pos_y[148], snap.prev_pos_x[149], snap.prev_pos_y[149]
	]
	assert_array(spawned).is_equal([30500, 20500, 31500, 21500])
	# The rows stay the same in the next tick: the prev arrays are the old snapshot's (no copy),
	# and target_row still has a row per unit.
	_play(1)
	var next: MatchSnapshot = _capture(snap, 1)
	assert_int(next.rows_version).is_equal(snap.rows_version)
	assert_bool(is_same(next.prev_pos_x, snap.pos_x)).is_true()
	assert_bool(is_same(next.prev_pos_y, snap.pos_y)).is_true()
	assert_int(next.target_row.size()).is_equal(next.unit_count())


## Three captures of one match. Slot 0 keeps projectile 7, which moves from (500, 1500) to
## (1000, 2000) to (1500, 2600); slot 1 holds projectile 6, then 8, then 9. The rows stay the
## same up to the second capture; unit 5 dies in the third tick, so the third capture takes the
## rows-changed path.
func test_projectile_prevs_are_the_previous_snapshots_slots() -> void:
	_play(2)
	_put_projectile(0, 7, 500, 1500)
	_put_projectile(1, 6, 2000, 3000)
	var older: MatchSnapshot = _capture(null, 1)
	_play(1)
	_put_projectile(0, 7, 1000, 2000)
	_put_projectile(1, 8, 3000, 4000)
	var previous: MatchSnapshot = _capture(older, 1)
	assert_int(previous.rows_version).is_equal(older.rows_version)
	assert_array([previous.prev_proj_id[1], previous.prev_proj_x[0]]).is_equal([6, 500])
	_world.hp[_world.index_of(5)] = 0
	_play(1)
	_put_projectile(0, 7, 1500, 2600)
	_put_projectile(1, 9, 5000, 6000)
	var snap: MatchSnapshot = _capture(previous, 1)
	assert_int(snap.rows_version).is_not_equal(previous.rows_version)
	assert_array([snap.proj_id[0], snap.prev_proj_id[0]]).is_equal([7, 7])
	# The previous snapshot's position: not the one before it (500, 1500), not the current one.
	assert_array([snap.prev_proj_x[0], snap.prev_proj_y[0]]).is_equal([1000, 2000])
	assert_array([snap.proj_x[0], snap.proj_y[0]]).is_equal([1500, 2600])
	assert_array([snap.proj_id[1], snap.prev_proj_id[1]]).is_equal([9, 8])
	assert_bool(is_same(snap.prev_proj_id, previous.proj_id)).is_true()
	assert_bool(is_same(snap.prev_proj_x, previous.proj_x)).is_true()
	assert_bool(is_same(snap.prev_proj_y, previous.proj_y)).is_true()
	# A previous snapshot of another match counts as none.
	var other: MatchSnapshot = _capture(previous, 2)
	assert_array(other.prev_proj_id).is_equal(other.proj_id)
	assert_array(other.prev_proj_x).is_equal(other.proj_x)
	assert_array(other.prev_proj_y).is_equal(other.proj_y)


## Units 1, 2, 77 and 150 die, so the rows hold ids 3-76 and 78-149.
func test_index_of_finds_rows_across_gaps_and_minus_one_for_absent_ids() -> void:
	for id: int in [1, 2, 77, 150]:
		_world.hp[_world.index_of(id)] = 0
	_play(1)
	var snap: MatchSnapshot = _capture(null, 1)
	assert_int(snap.unit_count()).is_equal(146)
	var found: Array[int] = []
	for id: int in [3, 76, 78, 149, 0, 1, 2, 77, 150, 151, -4]:
		found.append(snap.index_of(id))
	assert_array(found).is_equal([0, 73, 74, 145, -1, -1, -1, -1, -1, -1, -1])
	var misses: int = 0
	for row: int in snap.unit_count():
		if snap.index_of(snap.unit_id[row]) != row:
			misses += 1
	assert_int(misses).is_equal(0)


func test_a_capture_without_previous_gives_prev_equal_current() -> void:
	_play(4)
	_put_projectile(2, 5, 7000, 8000)
	var snap: MatchSnapshot = _capture(null, 1)
	assert_int(snap.prev_pos_x.size()).is_equal(150)
	assert_array(snap.prev_pos_x).is_equal(snap.pos_x)
	assert_array(snap.prev_pos_y).is_equal(snap.pos_y)
	assert_array(snap.prev_proj_id).is_equal(snap.proj_id)
	assert_array(snap.prev_proj_x).is_equal(snap.proj_x)
	assert_array(snap.prev_proj_y).is_equal(snap.proj_y)
	assert_int(snap.prev_proj_x[2]).is_equal(7000)
	# Equal, not the same arrays: a test that writes the current ones to set up a view case (ADR
	# 0012 section 3) leaves the prev alone.
	var prev: Array[int] = [
		snap.prev_pos_x[0],
		snap.prev_pos_y[0],
		snap.prev_proj_id[2],
		snap.prev_proj_x[2],
		snap.prev_proj_y[2],
	]
	snap.pos_x[0] += 400
	snap.pos_y[0] += 400
	snap.proj_id[2] = 6
	snap.proj_x[2] += 400
	snap.proj_y[2] += 400
	var after: Array[int] = [
		snap.prev_pos_x[0],
		snap.prev_pos_y[0],
		snap.prev_proj_id[2],
		snap.prev_proj_x[2],
		snap.prev_proj_y[2],
	]
	assert_array(after).is_equal(prev)
	assert_int(snap.pos_x[0]).is_equal(prev[0] + 400)


## capture() sets neither header field that the World does not hold: match_serial and last_hash
## stay what the creator set (plan P38j), with no previous and with one of the same match.
func test_capture_leaves_match_serial_and_last_hash_alone() -> void:
	_play(2)
	var previous: MatchSnapshot = _capture(null, 5)
	_play(1)
	var headers: Array = []
	var befores: Array[MatchSnapshot] = [null, previous]
	for before: MatchSnapshot in befores:
		var snap: MatchSnapshot = MatchSnapshot.new()
		snap.match_serial = 5
		snap.last_hash = 123456
		snap.capture(_world, before)
		headers.append([snap.match_serial, snap.last_hash, snap.tick])
	assert_array(headers).is_equal([[5, 123456, 3], [5, 123456, 3]])


## Report only (plan P38s): the cost of one capture on the arena at tick 450, with the previous
## snapshot of the same match.
func test_print_the_capture_cost_at_tick_450() -> void:
	_play(449)
	var previous: MatchSnapshot = _capture(null, 1)
	_play(1)
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = 1
	var started: int = Time.get_ticks_usec()
	snap.capture(_world, previous)
	var spent: int = Time.get_ticks_usec() - started
	print("SNAPSHOT capture_us=%d tick=%d rows=%d" % [spent, snap.tick, snap.unit_count()])
	assert_int(snap.tick).is_equal(450)


func _play(ticks: int) -> void:
	for _i: int in ticks:
		_loop.step(_world, _queued)


## A new snapshot with `serial` set before the capture, as the runner sets it.
func _capture(previous: MatchSnapshot, serial: int) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = serial
	snap.capture(_world, previous)
	return snap


## A hand-built open-grass world of `map_w` x `map_h` milli-tiles (0 x 0 gives no map).
func _grass(map_w: int, map_h: int) -> World:
	var world: World = World.new()
	world.map_w = map_w
	world.map_h = map_h
	world.prepare()
	return world


## The cell_of probes for a map of `w` x `h` milli-tiles: corners 0-3, edge midpoints 4-7, one
## inside (8), then outside: (-1, -1), (-5000, 0), (w, 0), (0, h), beyond both, and a far mix.
func _cell_points(w: int, h: int) -> Array[Vector2i]:
	return [
		Vector2i(0, 0),
		Vector2i(w - 1, 0),
		Vector2i(0, h - 1),
		Vector2i(w - 1, h - 1),
		Vector2i(w / 2, 0),
		Vector2i(0, h / 2),
		Vector2i(w - 1, h / 2),
		Vector2i(w / 2, h - 1),
		Vector2i(w / 3, h / 3),
		Vector2i(-1, -1),
		Vector2i(-5000, 0),
		Vector2i(w, 0),
		Vector2i(0, h),
		Vector2i(w + 5000, h + 5000),
		Vector2i(999999, -999999),
	]


func _put_projectile(slot: int, id: int, x: int, y: int) -> void:
	_world.proj_id[slot] = id
	_world.proj_x[slot] = x
	_world.proj_y[slot] = y


## The names of the World's five shape lists, in list order.
func _shape_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(World.ROW_ARRAYS)
	names.append_array(World.TYPE_ARRAYS)
	names.append_array(World.WEAPON_ARRAYS)
	names.append_array(World.PROJECTILE_ARRAYS)
	names.append_array(World.MAP_ARRAYS)
	return names


## What the view asks a fog: player 1's visibility, explored mark, version, dirty list and flag.
func _fog_reads(fog: FogGrid, cell: int) -> Array:
	return [
		fog.is_visible(1, cell),
		fog.is_explored(1, cell),
		fog.version_of(1),
		fog.dirty_cells(1),
		fog.dirty_overflowed(1),
	]


## Writes entry 0 of every copied World column and of `stats`, appends to `events` and to every id
## list, and stamps the fog of player 1 at `cell`. Returns the names whose World value still
## equals the snapshot's, which must be none: the writes reached the World.
func _scribble(world: World, snap: MatchSnapshot, cell: int) -> Array[StringName]:
	for name: StringName in MatchSnapshot.COPIED + [&"stats"]:
		var column: Variant = world.get(name)
		if typeof(column) == TYPE_PACKED_STRING_ARRAY:
			column[0] = column[0] + "!"
		else:
			column[0] = column[0] + 1
	world.events.append(World.Event.SPAWNED)
	for name: StringName in MatchSnapshot.ID_LISTS:
		(world.get(name) as Array).append(&"scribble")
	world.fog.stamp(1, cell, world.fog.add_mask(3000), 1)
	var same: Array[StringName] = []
	for name: StringName in MatchSnapshot.COPIED + MatchSnapshot.ID_LISTS + [&"events", &"stats"]:
		if world.get(name) == snap.get(name):
			same.append(name)
	return same
