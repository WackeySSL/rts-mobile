extends GdUnitTestSuite
## REPAIR (7) for the airfield role (plan row P241b, ADR 0036 section 7, ADR 0037 section 2), and
## the part of the shared repair-role contract that the airfield owns: the classes mask, a free
## pad, re-homing, the MOVE to the pad, drops, and `Air.run` serving only AIR rows. Worlds are
## `air_worlds.gd`'s (two pads per airfield).

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")


func _repair(world: World, ids: Array, field: int, player: int = 1) -> void:
	var units: PackedInt32Array = PackedInt32Array(ids)
	Worlds.step(world, [Command.repair(player, units, field)])


func _pad(world: World, field: int, pad: int) -> Vector2i:
	return Air.pad_point(world, world.index_of(field), pad)


func test_an_aircraft_is_sent_to_its_pad_and_is_reloaded_and_repaired_there() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add(world, 1, "jet", 14000, 9000)
	world.home[jet] = Worlds.FIELD
	world.hp[jet] = 50
	world.ammo[jet] = 0
	world.credits[1] = 1000
	world.order[jet] = World.Order.ATTACK_MOVE
	_repair(world, [world.unit_id[jet]], Worlds.FIELD)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.order[jet]).is_equal(World.Order.MOVE)
	var pad: Vector2i = _pad(world, Worlds.FIELD, 0)
	assert_array([world.goal_x[jet], world.goal_y[jet]]).is_equal([pad.x, pad.y])
	Worlds.run(world, 400)
	assert_array([world.pos_x[jet], world.pos_y[jet]]).is_equal([pad.x, pad.y])
	assert_array([world.hp[jet], world.ammo[jet]]).is_equal([100, Worlds.AMMO])
	assert_int(world.order[jet]).is_equal(World.Order.IDLE)


func test_a_homeless_aircraft_is_homed_by_repair_and_takes_the_next_pad() -> void:
	var world: World = Worlds.world()
	var one: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var two: int = Worlds.add(world, 1, "fighter", 14000, 9000)
	_repair(world, [world.unit_id[two]], Worlds.FIELD)
	assert_int(world.home[two]).is_equal(Worlds.FIELD)
	var pad: Vector2i = _pad(world, Worlds.FIELD, 1)
	assert_array([world.goal_x[two], world.goal_y[two]]).is_equal([pad.x, pad.y])
	assert_int(world.order[one]).is_equal(World.Order.IDLE)


func test_with_one_pad_free_the_lowest_id_takes_it_and_the_others_are_skipped() -> void:
	var world: World = Worlds.world()
	Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var late: int = Worlds.add(world, 1, "fighter", 14000, 9000)
	var early: int = Worlds.add(world, 1, "fighter", 15000, 9000)
	var ids: Array = [world.unit_id[early], world.unit_id[late]]
	_repair(world, ids, Worlds.FIELD)
	assert_array([world.home[late], world.home[early]]).is_equal([Worlds.FIELD, 0])
	assert_int(world.order[early]).is_equal(World.Order.IDLE)
	assert_int(world.dropped_commands).is_equal(0)


func test_an_aircraft_that_is_already_home_there_keeps_its_pad_with_the_field_full() -> void:
	var world: World = Worlds.world()
	var one: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var two: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 1)
	world.pos_x[two] += 4000
	_repair(world, [world.unit_id[one], world.unit_id[two]], Worlds.FIELD)
	assert_int(world.dropped_commands).is_equal(0)
	var pad: Vector2i = _pad(world, Worlds.FIELD, 1)
	assert_array([world.goal_x[two], world.goal_y[two]]).is_equal([pad.x, pad.y])


func test_repair_moves_an_aircraft_home_from_another_airfield() -> void:
	var world: World = Worlds.world(true)
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	_repair(world, [world.unit_id[jet]], Worlds.FIELD_2)
	assert_int(world.home[jet]).is_equal(Worlds.FIELD_2)
	var pad: Vector2i = _pad(world, Worlds.FIELD_2, 0)
	assert_array([world.goal_x[jet], world.goal_y[jet]]).is_equal([pad.x, pad.y])


func test_the_command_is_dropped_and_counted_when_nothing_is_valid() -> void:
	var cases: Dictionary = {}
	var world: World = Worlds.world(true)
	var jet: int = Worlds.add(world, 1, "jet", 14000, 9000)
	var ground: int = Worlds.add(world, 1, "dummy", 14000, 9000)
	var drone: int = Worlds.add(world, 1, "drone", 14000, 9000)
	var enemy: int = Worlds.add(world, 2, "jet", 14000, 9000)
	var hq_id: int = world.unit_id[world.index_of(Worlds.HQ_2)]
	var jet_id: int = world.unit_id[jet]
	cases["a ground unit"] = Command.repair(1, PackedInt32Array([world.unit_id[ground]]), 1)
	cases["a drone squad"] = Command.repair(1, PackedInt32Array([world.unit_id[drone]]), 1)
	cases["an enemy aircraft"] = Command.repair(1, PackedInt32Array([world.unit_id[enemy]]), 1)
	cases["an enemy airfield"] = Command.repair(2, PackedInt32Array([jet_id]), Worlds.FIELD)
	cases["a building with no pads"] = Command.repair(2, PackedInt32Array([jet_id]), hq_id)
	cases["no such building"] = Command.repair(1, PackedInt32Array([jet_id]), 999)
	cases["no units"] = Command.repair(1, PackedInt32Array(), Worlds.FIELD)
	cases["a unit as the target"] = Command.repair(1, PackedInt32Array([jet_id]), jet_id)
	cases["too many units"] = Command.repair(
		1, PackedInt32Array(range(1, Command.MAX_UNITS + 2)), Worlds.FIELD
	)
	var dropped: int = 0
	for label: String in cases:
		var made: Command = cases[label]
		made.tick = world.tick
		Sim.step(world, [made])
		dropped += 1
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(dropped)
		assert_int(world.order[jet]).override_failure_message(label).is_equal(World.Order.IDLE)


func test_an_airfield_still_under_construction_is_refused() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add(world, 1, "jet", 14000, 9000)
	world.build_left[world.index_of(Worlds.FIELD)] = 300
	_repair(world, [world.unit_id[jet]], Worlds.FIELD)
	assert_array([world.dropped_commands, world.order[jet]]).is_equal([1, World.Order.IDLE])


func test_a_repair_with_a_class_mask_that_leaves_air_out_is_refused() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add(world, 1, "jet", 14000, 9000)
	world.type_repair_classes[world.type_index[world.index_of(Worlds.FIELD)]] = 7
	_repair(world, [world.unit_id[jet]], Worlds.FIELD)
	assert_array([world.dropped_commands, world.order[jet]]).is_equal([1, World.Order.IDLE])


func test_air_run_serves_air_rows_only_a_ground_row_on_the_pad_is_never_repaired() -> void:
	var world: World = Worlds.world()
	var pad: Vector2i = _pad(world, Worlds.FIELD, 0)
	var ground: int = Worlds.add(world, 1, "dummy", pad.x, pad.y)
	world.hp[ground] = 50
	world.home[ground] = Worlds.FIELD
	world.credits[1] = 1000
	Worlds.run(world, 31)
	assert_array([world.hp[ground], world.credits[1]]).is_equal([50, 1000])


func test_the_command_is_replayable_and_the_same_run_gives_the_same_hash() -> void:
	var hashes: Array[int] = []
	for _run: int in 2:
		var world: World = Worlds.world()
		var jet: int = Worlds.add(world, 1, "jet", 14000, 9000)
		world.hp[jet] = 40
		world.credits[1] = 500
		_repair(world, [world.unit_id[jet]], Worlds.FIELD)
		Worlds.run(world, 200)
		hashes.append(WorldHash.state_hash(world))
	assert_int(hashes[0]).is_equal(hashes[1])
