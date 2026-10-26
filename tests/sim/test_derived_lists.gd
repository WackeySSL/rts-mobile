extends GdUnitTestSuite
## The derived row lists (plan row P71, ADR 0017 sections 3 and 7, ADR 0016): `building_rows` (rows
## of a type with a footprint) and `harvester_rows` (mobile rows of a type with a cargo capacity)
## are rebuilt in ECONOMY (`Power.run`) when `rows_version` has moved, equal a scan of the rows
## after every step, and are in no hash section: a rebuild from the hashed state restores them.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")


## The base: a rifle, a Headquarters, a harvester, a turret and another harvester, in that row
## order, so that the two lists interleave with the units between them.
func _base() -> World:
	var world: World = Worlds.open(24, 14)
	world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 7500, 3500)
	world.add_building(1, Worlds.type_of(world, "headquarters"), 2, 2)
	world.add_unit(1, Worlds.type_of(world, "harvester"), 6500, 8500)
	world.add_building(2, Worlds.type_of(world, "defence_turret"), 15, 5)
	world.add_unit(2, Worlds.type_of(world, "harvester"), 17500, 6500)
	world.add_unit(2, Worlds.type_of(world, "light_tank"), 18500, 9500)
	return world


## The lists a scan of the rows gives: a footprint above 0 is a building, a mobile row with a cargo
## capacity is a harvester.
func _scan(world: World) -> Array[PackedInt32Array]:
	var buildings: PackedInt32Array = PackedInt32Array()
	var harvesters: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.type_foot_w[type] > 0 and world.type_foot_h[type] > 0:
			buildings.append(row)
		elif world.type_speed[type] > 0 and world.type_harvest[type] > 0:
			harvesters.append(row)
	return [buildings, harvesters]


func _step(world: World) -> void:
	Sim.step(world, [] as Array[Command])


func _matches_a_scan(world: World, where: String) -> void:
	var scan: Array[PackedInt32Array] = _scan(world)
	assert_array(world.building_rows).override_failure_message(where).is_equal(scan[0])
	assert_array(world.harvester_rows).override_failure_message(where).is_equal(scan[1])


func test_the_lists_start_empty_and_economy_fills_them_in_ascending_row_order() -> void:
	var world: World = _base()
	assert_array(world.building_rows).is_empty()
	assert_array(world.harvester_rows).is_empty()
	_step(world)
	assert_array(world.building_rows).is_equal([1, 3])
	assert_array(world.harvester_rows).is_equal([2, 4])


func test_a_rebuild_happens_only_when_the_rows_version_moved() -> void:
	var world: World = _base()
	assert_bool(Buildings.rebuild_lists(world)).is_true()
	assert_bool(Buildings.rebuild_lists(world)).is_false()
	_step(world)
	assert_bool(Buildings.rebuild_lists(world)).is_false()  # Nothing joined or left in the step.
	world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 3500, 9500)
	assert_array(world.building_rows).is_equal([1, 3])  # Stale until ECONOMY: the lists are derived.
	assert_bool(Buildings.rebuild_lists(world)).is_true()
	assert_bool(Buildings.rebuild_lists(world)).is_false()


func test_the_lists_equal_a_scan_after_every_step_through_joins_and_deaths() -> void:
	var world: World = _base()
	for tick: int in 40:
		if tick == 5:  # A building and a harvester join; the rows after them keep their order.
			world.add_building(1, Worlds.type_of(world, "power_plant"), 6, 2)
			world.add_unit(1, Worlds.type_of(world, "harvester"), 9500, 9500)
		if tick == 12:  # The row before the first building dies: every later row moves down one.
			world.hp[0] = 0
		if tick == 20:  # A harvester and a building (ids 3 and 2) die on one tick.
			world.hp[world.index_of(3)] = 0
			world.hp[world.index_of(2)] = 0
		_step(world)
		_matches_a_scan(world, "tick %d" % tick)
	assert_int(world.unit_count()).is_equal(5)
	assert_array(world.building_rows).is_equal([0, 3])  # The turret and the power plant.
	assert_array(world.harvester_rows).is_equal([1, 4])  # The harvesters of player 2 and 1.


func test_a_row_with_a_cargo_capacity_that_cannot_move_is_not_a_harvester() -> void:
	var world: World = _base()
	var type: int = Worlds.type_of(world, "harvester")
	world.type_speed[type] = 0
	_step(world)
	assert_array(world.harvester_rows).is_empty()
	assert_array(world.building_rows).is_equal([1, 3])


func test_the_lists_are_out_of_the_hash_and_a_rebuild_from_the_state_restores_them() -> void:
	var world: World = _base()
	var twin: World = _base()
	for tick: int in 20:
		_step(world)
		_step(twin)
	assert_int(world.state_hash()).is_equal(twin.state_hash())
	assert_array(world.building_rows).is_equal(twin.building_rows)
	twin.building_rows.append(99)
	twin.harvester_rows.clear()
	assert_int(twin.state_hash()).is_equal(world.state_hash())  # Derived: no section reads them.
	assert_array(twin.hash_parts()).is_equal(world.hash_parts())
	twin._lists_version = -1
	assert_bool(Buildings.rebuild_lists(twin)).is_true()
	assert_array(twin.building_rows).is_equal(world.building_rows)
	assert_array(twin.harvester_rows).is_equal(world.harvester_rows)


func test_the_derived_names_are_in_the_derived_list_and_not_in_the_hash_sections() -> void:
	for name: StringName in [&"building_rows", &"harvester_rows"]:
		assert_bool(World.DERIVED_ARRAYS.has(name)).is_true()
		assert_bool(World.ROW_ARRAYS.has(name)).is_false()
		assert_bool(World.hash_section_names().has(String(name))).is_false()
