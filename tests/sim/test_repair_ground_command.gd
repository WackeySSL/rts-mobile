extends GdUnitTestSuite
## REPAIR (7) for a ground repair building (plan row P277, ADR 0037 section 6): the valid units get
## MOVE to `Buildings.aim`'s approach point, the ones the classes do not serve are skipped, and an
## unfinished, dead, enemy or pad-less target, or a defeated player, drops the command. Plus the
## ground half of the shared repair-role contract (the data test that reach covers every ring
## point is in test_repair_reach.gd). The rig is test_repair_run.gd's: a shed (2 x 2, classes 6,
## reach 2700) at tile (2, 2), centre (3000, 3000).

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const SHED: Vector2i = Vector2i(2, 2)  # Its footprint centre is (3000, 3000).
const SHED_ID: int = 1


func _unit(id: String, move_class: int, speed: int) -> UnitDef:
	var def: UnitDef = Rig.unit(StringName(id), 6000, 5000, 0, 0, [])
	def.move_class = move_class
	def.speed = speed
	def.cost = 100
	return def


func _world() -> World:
	var shed: BuildingDef = BuildingDef.new()
	shed.type_id = &"shed"
	shed.max_hp = 1000
	shed.armour = World.Armour.BUILDING
	shed.footprint = Vector2i(2, 2)
	shed.sight_range = 4000
	shed.repair_classes = 6
	shed.repair_hp = 30
	shed.repair_period_ticks = 15
	shed.repair_cost_percent = 25
	shed.repair_reach_milli = 2700
	shed.repair_slots = 2
	var hq: BuildingDef = BuildingDef.new()
	hq.type_id = &"hq"
	hq.max_hp = 1000
	hq.armour = World.Armour.BUILDING
	hq.footprint = Vector2i(3, 3)
	hq.sight_range = 4000
	var medic: UnitDef = _unit("medic", World.MoveClass.FOOT, 67)
	medic.repair_classes = 1
	medic.repair_hp = 6
	medic.repair_period_ticks = 15
	medic.repair_cost_percent = 0
	medic.repair_reach_milli = 1500
	medic.repair_slots = 1
	medic.repair_seek_milli = 4000
	var units: Array[UnitDef] = [
		shed,
		hq,
		medic,
		_unit("tank", World.MoveClass.TRACKED, 67),
		_unit("squad", 0, 67),
		_unit("drone", World.MoveClass.AIR, 67)
	]
	var made: World = Rig.world_of(units, 24, 16, true, 2)
	made.add_building(1, Worlds.type_of(made, "shed"), SHED.x, SHED.y)
	made.add_building(1, Worlds.type_of(made, "hq"), 10, 10)
	made.add_building(2, Worlds.type_of(made, "hq"), 20, 12)
	made.credits[1] = 1000
	return made


func _add(world: World, player: int, id: String, x: int, y: int, hp: int = 100) -> int:
	var row: int = Worlds.add(world, player, id, x, y)
	world.hp[row] = hp
	return row


func _repair(world: World, ids: Array, target: int = SHED_ID, player: int = 1) -> void:
	Worlds.step(world, [Command.repair(player, PackedInt32Array(ids), target)])


func _goal(world: World, row: int) -> Vector2i:
	return Vector2i(world.goal_x[row], world.goal_y[row])


func test_a_vehicle_is_sent_to_the_approach_point_and_is_repaired_there() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 9000, 3000, 50)
	world.order[tank] = World.Order.ATTACK_MOVE
	_repair(world, [world.unit_id[tank]])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.order[tank]).is_equal(World.Order.MOVE)
	# The ring tile nearest the tank: the tile right of the footprint, (4, 2), centre (4500, 2500).
	var goal: Vector2i = _goal(world, tank)
	assert_array([goal.x % 1000, goal.y % 1000]).is_equal([500, 500])
	assert_int(goal.x).is_equal(4500)
	for _tick: int in 600:
		Worlds.step(world)
	assert_bool(world.hp[tank] > 50).is_true()
	assert_int(world.hp[tank]).is_equal(100)
	assert_int(world.order[tank]).is_equal(World.Order.IDLE)


func test_a_mixed_selection_sends_only_the_served_rows() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 9000, 3000, 50)
	var squad: int = _add(world, 1, "squad", 9000, 3500, 50)
	var drone: int = _add(world, 1, "drone", 9000, 4000, 50)
	var foe: int = _add(world, 2, "tank", 9000, 4500, 50)
	var dead: int = _add(world, 1, "tank", 9000, 5000, 0)
	var young: int = _add(world, 1, "tank", 9000, 5500, 50)
	world.build_left[young] = 5
	var unserved: Array[int] = []
	for row: int in [squad, drone, foe, young]:
		unserved.append(world.unit_id[row])
	var tank_id: int = world.unit_id[tank]
	var ids: Array = unserved.duplicate()
	ids.append(world.unit_id[dead])
	ids.append(SHED_ID)  # A building in the selection is not a unit to send.
	ids.append(tank_id)
	ids.append(tank_id)  # A repeated id.
	_repair(world, ids)  # The dead row is removed in this tick: look rows up by id.
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.order[world.index_of(tank_id)]).is_equal(World.Order.MOVE)
	for id: int in unserved:
		assert_int(world.order[world.index_of(id)]).is_equal(World.Order.IDLE)
	assert_int(world.order[world.index_of(SHED_ID)]).is_equal(World.Order.IDLE)


func test_the_new_order_replaces_an_attack_and_clears_its_target() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 9000, 3000, 50)
	var foe: int = _add(world, 2, "tank", 14000, 3000)
	world.order[tank] = World.Order.ATTACK
	world.order_target[tank] = world.unit_id[foe]
	world.group_cell[tank] = 7
	_repair(world, [world.unit_id[tank]])
	assert_int(world.order[tank]).is_equal(World.Order.MOVE)
	assert_int(world.group_cell[tank]).is_equal(-1)


func test_nothing_valid_drops_the_command_and_counts_it() -> void:
	var cases: Dictionary = {}
	var world: World = _world()
	var squad: int = _add(world, 1, "squad", 9000, 3000, 50)
	var tank: int = _add(world, 1, "tank", 9000, 3500, 50)
	var foe: int = _add(world, 2, "tank", 9000, 4000, 50)
	var hq_id: int = world.unit_id[world.index_of(2)]  # Player 1's headquarters (no role).
	var tank_id: PackedInt32Array = PackedInt32Array([world.unit_id[tank]])
	cases["only an unserved class"] = Command.repair(1, PackedInt32Array([world.unit_id[squad]]), 1)
	cases["a building with no role"] = Command.repair(1, tank_id, hq_id)
	cases["an enemy's unit"] = Command.repair(2, PackedInt32Array([world.unit_id[foe]]), 1)
	cases["no units"] = Command.repair(1, PackedInt32Array(), 1)
	cases["no such building"] = Command.repair(1, tank_id, 999)
	cases["a unit as the target"] = Command.repair(1, tank_id, world.unit_id[squad])
	cases["too many units"] = Command.repair(
		1, PackedInt32Array(range(1, Command.MAX_UNITS + 2)), 1
	)
	var dropped: int = 0
	for label: String in cases:
		var made: Command = cases[label]
		made.tick = world.tick
		Sim.step(world, [made])
		dropped += 1
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(dropped)
		for row: int in [squad, tank, foe]:
			assert_int(world.order[row]).override_failure_message(label).is_equal(World.Order.IDLE)


func test_an_enemy_building_and_an_unfinished_or_dead_one_are_refused() -> void:
	var enemy: World = _world()
	enemy.add_building(2, Worlds.type_of(enemy, "shed"), 14, 2)
	var enemy_shed: int = enemy.unit_id[enemy.unit_count() - 1]
	var tank: int = _add(enemy, 1, "tank", 9000, 3000, 50)
	_repair(enemy, [enemy.unit_id[tank]], enemy_shed)
	assert_array([enemy.dropped_commands, enemy.order[tank]]).is_equal([1, World.Order.IDLE])
	for case: String in ["incomplete", "dead"]:
		var world: World = _world()
		tank = _add(world, 1, "tank", 9000, 3000, 50)
		var shed: int = world.index_of(SHED_ID)
		if case == "incomplete":
			world.build_left[shed] = 300
		else:
			world.hp[shed] = 0
		var tank_id: int = world.unit_id[tank]
		_repair(world, [tank_id])  # A dead shed is removed in this tick: look the tank up by id.
		assert_int(world.dropped_commands).override_failure_message(case).is_equal(1)
		var idle: int = World.Order.IDLE
		assert_int(world.order[world.index_of(tank_id)]).override_failure_message(case).is_equal(
			idle
		)


func test_a_blacked_out_shed_takes_the_order_but_repairs_nothing_until_it_is_back() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 9000, 3000, 50)
	world.offline_until[world.index_of(SHED_ID)] = world.tick + 100
	_repair(world, [world.unit_id[tank]])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.order[tank]).is_equal(World.Order.MOVE)
	for _tick: int in 60:
		Worlds.step(world)
	assert_int(world.hp[tank]).is_equal(50)
	for _tick: int in 200:
		Worlds.step(world)
	assert_int(world.hp[tank]).is_equal(100)


func test_a_defeated_player_cannot_send_units() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 9000, 3000, 50)
	world.defeated_tick[1] = 1
	_repair(world, [world.unit_id[tank]])
	assert_array([world.dropped_commands, world.order[tank]]).is_equal([1, World.Order.IDLE])


func test_a_ring_tile_that_is_blocked_is_skipped_and_a_unit_with_none_is_left_out() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 9000, 3000, 50)
	var ring: Array[Vector2i] = []
	for col: int in range(1, 5):
		for line: int in range(1, 5):
			if col < 2 or col > 3 or line < 2 or line > 3:
				ring.append(Vector2i(col, line))
	var cells: int = world.map_cols * world.map_rows
	var wheel: int = World.MoveClass.TRACKED
	for tile: Vector2i in ring:
		world.move_cost[wheel * cells + tile.y * world.map_cols + tile.x] = 0
	_repair(world, [world.unit_id[tank]])
	assert_array([world.dropped_commands, world.order[tank]]).is_equal([1, World.Order.IDLE])


func test_every_ring_tile_is_within_the_sheds_reach_of_its_centre() -> void:
	# Each ring tile of the 2 x 2 shed, taken as the tank's own tile, is the point it is sent to;
	# the shed's reach (2700) covers it from the footprint centre.
	var reach: int = 2700
	for col: int in range(1, 5):
		for line: int in range(1, 5):
			if col >= 2 and col <= 3 and line >= 2 and line <= 3:
				continue
			var world: World = _world()
			var at: Vector2i = Vector2i(col * 1000 + 500, line * 1000 + 500)
			var tank: int = _add(world, 1, "tank", at.x, at.y, 50)
			_repair(world, [world.unit_id[tank]])
			var goal: Vector2i = _goal(world, tank)
			var gap: Vector2i = goal - Vector2i(3000, 3000)
			assert_array([goal.x, goal.y]).is_equal([at.x, at.y])
			assert_bool(gap.x * gap.x + gap.y * gap.y <= reach * reach).is_true()


func test_the_command_is_replayable_and_the_same_run_gives_the_same_hash() -> void:
	var hashes: Array[int] = []
	for _run: int in 2:
		var world: World = _world()
		var tank: int = _add(world, 1, "tank", 9000, 3000, 40)
		_repair(world, [world.unit_id[tank]])
		for _tick: int in 200:
			Worlds.step(world)
		hashes.append(WorldHash.state_hash(world))
	assert_int(hashes[0]).is_equal(hashes[1])


func test_air_apply_repair_still_serves_a_padded_airfield_and_never_a_ground_building() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add(world, 1, "jet", 14000, 9000)
	Worlds.step(world, [Command.repair(1, PackedInt32Array([world.unit_id[jet]]), Worlds.FIELD)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.home[jet]).is_equal(Worlds.FIELD)
