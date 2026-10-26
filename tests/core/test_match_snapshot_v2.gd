extends GdUnitTestSuite
## MatchSnapshot v2 (plan row P81, ADR 0017 section 6): the snapshot of a base match carries the
## harvest columns, the Phase 3 type tables, `type_radius`, `move_cost`, `terrain_buildable`,
## `ore_cell`, the player, ore and ghost arrays, the power totals, the end of the match and the
## two rule ints of PlacementInput; `building_rows` and `harvester_rows` stay in the World (ADR
## 0016). The base match is tests/core/support/base_match.gd, seed 42. The P38s cases on the perf
## arena and the coverage of the World's lists are in test_match_snapshot.gd.

const BaseMatch: GDScript = preload("res://tests/core/support/base_match.gd")
const SEED: int = 42


## A runner plays 30 ticks of the base match in SYNC; then the World equals its published snapshot
## in every COPIED array, every COPIED_SCALARS int, the id lists, events, stats and the fog. No
## COPIED array is empty there, and it is a base match: twelve buildings, the ore cells of the map
## at their start amount, a producer owned by both players. The World's derived row lists are
## filled, and the snapshot has neither.
func test_after_30_ticks_of_a_base_match_every_snapshot_array_equals_its_world_array() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = BaseMatch.scenario()
	runner.match_seed = SEED
	runner.start()
	runner.run_ticks(30)
	var snap: MatchSnapshot = runner.snapshot
	var world: World = runner.world
	var differ: Array[StringName] = []
	var empty: Array[StringName] = []
	var names: Array[StringName] = []
	names.append_array(MatchSnapshot.COPIED + MatchSnapshot.COPIED_SCALARS)
	names.append_array(MatchSnapshot.ID_LISTS + [&"events", &"stats"])
	for name: StringName in names:
		if snap.get(name) != world.get(name):
			differ.append(name)
	for name: StringName in MatchSnapshot.COPIED:
		if snap.get(name).is_empty():
			empty.append(name)
	for name: StringName in FogGrid.HASHED + FogGrid.UNHASHED:
		if snap.fog.get(name) != world.fog.get(name):
			differ.append(StringName("fog." + name))
	assert_array(differ).is_empty()
	assert_array(empty).is_empty()
	var buildings: int = 0
	for row: int in snap.unit_count():
		if snap.type_foot_w[snap.type_index[row]] > 0:
			buildings += 1
	var ore: int = "".join(PackedStringArray(BaseMatch.ROWS)).count("o")
	assert_array([snap.tick, buildings, snap.ore_cell.size(), snap.had_producer]).is_equal(
		[30, 12, ore, PackedInt32Array([0, 1, 1])]
	)
	assert_int(snap.ore_amount.count(world.ore_start)).is_equal(ore)
	assert_array([snap.match_end_tick, snap.winner, snap.building_cap]).is_equal([0, 0, 40])
	assert_int(world.building_rows.size()).is_equal(12)
	assert_bool(world.harvester_rows.is_empty()).is_false()
	for name: StringName in [&"building_rows", &"harvester_rows"]:
		assert_that(snap.get(name)).override_failure_message(String(name)).is_null()


## Every COPIED array of a base World after 30 ticks gets values of its own, and the four
## COPIED_SCALARS ints too, before one capture: each snapshot array and int equals its World
## namesake, and no two snapshot arrays are equal, so an array copied from the wrong World column
## (`rally_y` from `rally_x`, which hold the same values in a real match) fails.
func test_every_array_and_scalar_comes_from_its_own_world_column() -> void:
	var world: World = _base_world(30)
	var names: Array[StringName] = MatchSnapshot.COPIED
	for column: int in names.size():
		_mark(world.get(names[column]), column)
	world.match_end_tick = 31
	world.winner = 2
	world.build_reach_tiles = 7
	world.building_cap = 9
	var snap: MatchSnapshot = _capture(world, null)
	var differ: Array[StringName] = []
	for name: StringName in names + MatchSnapshot.COPIED_SCALARS:
		if typeof(snap.get(name)) != typeof(world.get(name)) or snap.get(name) != world.get(name):
			differ.append(name)
	assert_array(differ).is_empty()
	(
		assert_array([snap.match_end_tick, snap.winner, snap.build_reach_tiles, snap.building_cap])
		. is_equal([31, 2, 7, 9])
	)
	var twins: Array[String] = []
	for first: int in names.size():
		for second: int in range(first + 1, names.size()):
			var a: Variant = snap.get(names[first])
			var b: Variant = snap.get(names[second])
			if typeof(a) == typeof(b) and a == b:
				twins.append("%s=%s" % [names[first], names[second]])
	assert_array(twins).is_empty()


## A snapshot of a base World at tick 21, captured with the one of tick 20 as previous, keeps every
## COPIED array and COPIED_SCALARS int after the World plays another tick and then has entry 0 of
## every copied array and each of the four ints written by hand: the writes reach the World only.
func test_a_base_snapshot_never_changes_after_its_capture() -> void:
	var world: World = _base_world(20)
	var none: Array[Command] = []
	var previous: MatchSnapshot = _capture(world, null)
	Sim.step(world, none)
	var snap: MatchSnapshot = _capture(world, previous)
	var kept: Dictionary = {}
	for name: StringName in MatchSnapshot.COPIED:
		kept[name] = snap.get(name).duplicate()
	for name: StringName in MatchSnapshot.COPIED_SCALARS:
		kept[name] = snap.get(name)
	Sim.step(world, none)
	for name: StringName in MatchSnapshot.COPIED:
		var column: Variant = world.get(name)
		if typeof(column) == TYPE_PACKED_STRING_ARRAY:
			column[0] = column[0] + "!"
		else:
			column[0] = column[0] + 1
	for name: StringName in MatchSnapshot.COPIED_SCALARS:
		world.set(name, int(world.get(name)) + 1)
	var reached: Array[StringName] = []
	var changed: Array[StringName] = []
	for name: StringName in kept:
		if world.get(name) == snap.get(name):
			reached.append(name)
		if snap.get(name) != kept[name]:
			changed.append(name)
	assert_array(reached).is_empty()
	assert_array(changed).is_empty()


## Placement.reason over the snapshot's PlacementInput gives what it gives over the World's
## (PlacementInput.of_world), for both players, every building type and every origin tile of the
## base World after 30 ticks with its real fog: every Reason but CAP occurs. With `building_cap` 6
## (each player owns six buildings) it agrees again, and CAP takes the place of every OK.
func test_the_snapshot_judges_placement_as_the_world_does() -> void:
	var world: World = _base_world(30)
	var first: Array[int] = _agreeing_reasons(world)
	for reason: int in Placement.Reason.values():
		var found: bool = first.count(reason) > 0
		assert_bool(found).override_failure_message(str(reason)).is_equal(
			reason != Placement.Reason.CAP
		)
	world.building_cap = 6
	var capped: Array[int] = _agreeing_reasons(world)
	assert_int(capped.count(Placement.Reason.OK)).is_equal(0)
	assert_int(capped.count(Placement.Reason.CAP)).is_equal(first.count(Placement.Reason.OK))


## The reasons for both players, every building type and every origin tile of `world`, over the
## World and over a fresh snapshot's input, which must agree at every call; -1 marks a call where
## they differ.
func _agreeing_reasons(world: World) -> Array[int]:
	var mine: PlacementInput = _capture(world, null).placement_input()
	var theirs: PlacementInput = PlacementInput.of_world(world)
	var reasons: Array[int] = []
	for player: int in [1, 2]:
		for type: int in world.type_ids.size():
			if world.type_foot_w[type] <= 0:
				continue
			for line: int in world.map_rows:
				for col: int in world.map_cols:
					var reason: int = Placement.reason(theirs, player, type, col, line)
					var same: bool = Placement.reason(mine, player, type, col, line) == reason
					reasons.append(reason if same else -1)
	assert_int(reasons.count(-1)).is_equal(0)
	return reasons


## The base match's World after `ticks` steps with no Command.
func _base_world(ticks: int) -> World:
	var world: World = World.from_scenario(
		BaseMatch.scenario(), DetRandom.create(SEED, DetRandom.STREAM_SIM)
	)
	var none: Array[Command] = []
	for _i: int in ticks:
		Sim.step(world, none)
	return world


## A new snapshot of `world` with match_serial 1 set before the capture, as the runner sets it.
func _capture(world: World, previous: MatchSnapshot) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = 1
	snap.capture(world, previous)
	return snap


## Writes values of its own into `column` (a World array, shared, so the World gets them): entry
## `j` of the column numbered `number` becomes `number * 100000 + j + 1`, in a byte array
## `(number * 37 + j) % 251 + 1`, and in a string array "number.j".
func _mark(column: Variant, number: int) -> void:
	for j: int in column.size():
		match typeof(column):
			TYPE_PACKED_STRING_ARRAY:
				column[j] = "%d.%d" % [number, j]
			TYPE_PACKED_BYTE_ARRAY:
				column[j] = (number * 37 + j) % 251 + 1
			_:
				column[j] = number * 100000 + j + 1
