extends GdUnitTestSuite
## Removal and events (plan P31a, ADR 0007 sections 3 and 10): remove_dead() compacts every
## ROW_ARRAYS column in id order, writes one DIED record per dead row and counts the rows that
## moved; Sim.step clears events and stats first and removes last. Numbers are literals.


## Removing rows 2 and 5 of 8. Every column has its own number in every row, so a column that is
## skipped, shifted or compacted before another one read hp shows.
func test_removing_rows_2_and_5_of_8_keeps_the_others_in_id_order() -> void:
	var world: World = _marked_world(8)
	world.hp[2] = 0
	world.hp[5] = -3
	world.remove_dead()
	for column_name: StringName in World.ROW_ARRAYS:
		var expected: Array[int] = []
		for row: int in [0, 1, 3, 4, 6, 7]:
			expected.append(_value(column_name, row))
		assert_array(world.get(column_name)).override_failure_message(column_name).is_equal(
			expected
		)
	assert_array(world.unit_id).is_equal([1, 2, 4, 5, 7, 8])
	for row: int in 6:
		assert_int(world.index_of(world.unit_id[row])).is_equal(row)
	for gone: int in [3, 6, 0, 9]:
		assert_int(world.index_of(gone)).override_failure_message(str(gone)).is_equal(-1)
	assert_int(world.rows_version).is_equal(9)
	assert_int(world.stats[World.Stat.ROWS_COMPACTED]).is_equal(4)
	# The 8 SPAWNED records stay; the two DIED ones follow them, in row order.
	assert_array(world.events.slice(64)).is_equal(_died(2) + _died(5))
	# Ids are never reused, so the next unit is the last row.
	assert_int(world.add_unit(0, 0, 5, 5)).is_equal(9)
	assert_int(world.index_of(9)).is_equal(6)


## Four units, hp 1 (alive) or 0 and below: the dead rows, the ids left and the rows that moved
## (the survivors after the first dead row). No death leaves everything, rows_version included.
func test_dead_rows_at_the_ends_next_to_each_other_and_everywhere() -> void:
	var cases: Array[Array] = [
		[[], [1, 2, 3, 4], 0],
		[[0], [2, 3, 4], 3],
		[[3], [1, 2, 3], 0],
		[[1, 2], [1, 4], 1],
		[[0, 1, 2, 3], [], 0],
	]
	for item: Array in cases:
		var world: World = _marked_world(4)
		var dead: Array = item[0]
		world.hp.fill(1)
		for row: int in dead:
			world.hp[row] = -(row % 2)
		world.remove_dead()
		var label: String = str(dead)
		assert_array(world.unit_id).override_failure_message(label).is_equal(item[1])
		for column_name: StringName in World.ROW_ARRAYS:
			var size: int = world.get(column_name).size()
			assert_int(size).override_failure_message(label + column_name).is_equal(item[1].size())
		var moved: int = world.stats[World.Stat.ROWS_COMPACTED]
		assert_array([moved, world.events.size()]).is_equal([item[2], 32 + 8 * dead.size()])
		assert_int(world.rows_version).is_equal(4 + mini(dead.size(), 1))


## A unit that dies this tick still moves first and writes its DIED record at the position it ended
## on (remove_dead is last). The SPAWNED records and a stale stat are gone after the first tick,
## and the next tick has no events at all.
func test_sim_step_clears_events_and_stats_and_removes_last() -> void:
	var world: World = World.new()
	world.map_w = 48000
	world.map_h = 48000
	world.type_ids.append(&"type")
	world.type_speed.append(120)
	world.add_unit(1, 0, 10000, 10000)
	world.add_unit(1, 0, 10000, 20000)
	world.add_unit(2, 0, 30000, 30000)
	world.prepare()
	world.stats[World.Stat.LINE_CHECKS] = 9
	world.hp[1] = 0
	var order: Command = Command.attack_move(1, PackedInt32Array([2]), 15000, 20000)
	order.tick = 0
	var commands: Array[Command] = [order]
	Sim.step(world, commands)
	assert_array(world.unit_id).is_equal([1, 3])
	assert_array(world.events).is_equal([World.Event.DIED, 2, 10120, 20000, 0, 1, 0, 0])
	assert_array(world.stats).is_equal([0, 0, 0, 0, 0, 0, 1])
	assert_array([world.tick, world.dropped_commands, world.rows_version]).is_equal([1, 0, 4])
	Sim.step(world, [])
	assert_array(world.events).is_empty()
	assert_array(world.stats).is_equal([0, 0, 0, 0, 0, 0, 0])


## remove_dead() prepares a hand-built world itself (ADR 0007 section 2: World.new() is a valid
## world), so a test can call it before any Sim.step: stats is sized and the dead row is counted.
func test_remove_dead_on_a_hand_built_world_prepares_it_first() -> void:
	var world: World = World.new()
	world.add_unit(1, 0, 1000, 1000)
	world.add_unit(1, 0, 2000, 1000)
	world.add_unit(2, 0, 3000, 1000)
	assert_bool(world.prepared).is_false()
	world.hp[0] = 0
	world.remove_dead()
	assert_bool(world.prepared).is_true()
	assert_array(world.unit_id).is_equal([2, 3])
	assert_int(world.stats[World.Stat.ROWS_COMPACTED]).is_equal(2)
	assert_array(world.events.slice(24)).is_equal([World.Event.DIED, 1, 1000, 1000, 0, 1, 0, 0])


## A definition built by hand, with no max_hp set, keeps its unit alive through the removal at the
## end of each tick.
func test_a_world_from_a_hand_built_unit_def_survives_ten_steps() -> void:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = &"plain"
	unit.speed = 100
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = unit
	spawn.count = 2
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.spawns.append(spawn)
	var world: World = World.from_scenario(scenario)
	for _t: int in 10:
		Sim.step(world, [])
	assert_array([world.unit_count(), world.tick]).is_equal([2, 10])
	assert_array(world.hp).is_equal([1, 1])


## A prepared hand-built world of `count` units whose every ROW_ARRAYS column holds
## `_value(column, row)`.
func _marked_world(count: int) -> World:
	var world: World = World.new()
	world.prepare()
	for _i: int in count:
		world.add_unit(0, 0, 0, 0)
	for column_name: StringName in World.ROW_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		for row: int in count:
			column[row] = _value(column_name, row)
	return world


## The number `_marked_world` puts in `column_name` of `row`: 100 per column, plus the row. The
## ids are the ones add_unit gave (1..count) and hp is 10 + row, alive.
func _value(column_name: StringName, row: int) -> int:
	if column_name == &"unit_id":
		return row + 1
	if column_name == &"hp":
		return 10 + row
	return 100 * (World.ROW_ARRAYS.find(column_name) + 1) + row


## The DIED record of `row` of a marked world: id, position, type, owner.
func _died(row: int) -> Array[int]:
	var record: Array[int] = [World.Event.DIED, row + 1]
	for column_name: StringName in [&"pos_x", &"pos_y", &"type_index", &"owner"]:
		record.append(_value(column_name, row))
	record.append_array([0, 0])
	return record
