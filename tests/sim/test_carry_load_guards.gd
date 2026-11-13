extends GdUnitTestSuite
## The guards of loading (plan row P263, ADR 0036 section 8; the rules are in test_carry_load): the
## reach boundary, who may board (FOOT of the own player only, whatever the mask says), a new order
## to the carrier letting go of the marks, a squad killed on the boarding tick, ATTACK rows,
## `release`, a part-full carrier and a recorded command log replayed.

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")


func test_the_reach_is_inclusive_at_exactly_load_reach_milli() -> void:
	var at: World = Rig.world()
	Rig.near(at, 1, Rig.REACH)
	Carry.board(at)  # Without a step: separation would move the rows by a unit or more.
	assert_int(at.pass_count).is_equal(1)
	var past: World = Rig.world()
	Rig.near(past, 1, Rig.REACH + 1)
	Carry.board(past)
	assert_int(past.pass_count).is_equal(0)


func test_a_tank_or_an_enemy_squad_marked_to_the_carrier_does_not_board() -> void:
	var tank: World = Rig.world()
	Rig.near(tank, 4, 500)
	Rig.step(tank)
	assert_int(tank.pass_count).is_equal(0)
	assert_int(tank.index_of(4)).is_greater_equal(0)
	var enemy: World = Rig.world()
	Rig.near(enemy, 6, 500)
	Rig.step(enemy)
	assert_int(enemy.pass_count).is_equal(0)
	assert_int(enemy.index_of(6)).is_greater_equal(0)


func test_only_foot_boards_whatever_the_mask_says() -> void:
	var world: World = Rig.world()
	world.type_carry_classes[Rig.TRUCK] = 15  # Every class bit.
	Rig.step(world, Rig.load_command([4], 5))  # A tank.
	assert_int(world.dropped_commands).is_equal(1)
	world.add_unit(1, Rig.TRUCK, 3000, 3000)  # A second carrier, id 7.
	Rig.step(world, Rig.load_command([7], 5))
	assert_int(world.dropped_commands).is_equal(2)
	Rig.near(world, 4, 500)
	world.order_target[world.index_of(7)] = 5
	world.pos_x[world.index_of(7)] = world.pos_x[world.index_of(5)]
	world.pos_y[world.index_of(7)] = world.pos_y[world.index_of(5)]
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)
	# A carrier loading itself is dropped as well.
	Rig.step(world, Rig.load_command([5], 5))
	assert_int(world.dropped_commands).is_equal(3)


func test_a_new_order_to_the_carrier_lets_go_of_the_squads_waiting_for_it() -> void:
	for order: String in ["move", "attack_move", "stop"]:
		var world: World = Rig.world()
		Rig.step(world, Rig.load_command([1, 2], 5))
		var ids: PackedInt32Array = PackedInt32Array([5])
		var command: Command = Command.stop(1, ids)
		if order == "move":
			command = Command.move(1, ids, 20500, 2500)
		elif order == "attack_move":
			command = Command.attack_move(1, ids, 20500, 2500)
		Rig.step(world, [command])
		for id: int in [1, 2]:
			(
				assert_int(world.order_target[world.index_of(id)])
				. override_failure_message(order)
				. is_equal(0)
			)
		# The carrier now passes the idle squads: nobody boards.
		world.pos_x[world.index_of(5)] = world.pos_x[world.index_of(1)] + 500
		world.pos_y[world.index_of(5)] = world.pos_y[world.index_of(1)]
		Rig.run(world, 3)
		assert_int(world.pass_count).override_failure_message(order).is_equal(0)


func test_a_squad_killed_on_the_boarding_tick_dies_and_does_not_board() -> void:
	var world: World = Rig.world()
	world.had_producer[1] = 1
	Rig.near(world, 1, 500)
	world.hp[world.index_of(1)] = 0
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)
	assert_array(Rig.died_flags(world)).is_equal([0])
	assert_int(world.stat_lost_units[1]).is_equal(1)


func test_an_attack_order_on_an_own_carrier_is_dropped_and_an_attack_row_does_not_board() -> void:
	var world: World = Rig.world()
	Rig.step(world, [Command.attack(1, PackedInt32Array([1]), 5)])
	assert_int(world.dropped_commands).is_equal(1)
	Rig.near(world, 1, 500)
	world.order[world.index_of(1)] = World.Order.ATTACK
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)


func test_release_clears_an_own_mark_and_keeps_an_enemy_id() -> void:
	var world: World = Rig.world()
	world.order_target[world.index_of(1)] = 5
	world.order_target[world.index_of(2)] = 6
	Carry.release(world, PackedInt32Array([world.index_of(1), world.index_of(2)]))
	assert_array([world.order_target[0], world.order_target[1]]).is_equal([0, 6])


func test_a_part_full_carrier_takes_only_its_free_slots() -> void:
	var world: World = Rig.world()
	Rig.aboard(world, 1, 5)
	Rig.step(world, Rig.load_command([2, 3], 5))
	assert_int(world.order_target[world.index_of(2)]).is_equal(5)
	assert_int(world.order_target[world.index_of(3)]).is_equal(0)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_recorded_command_log_replays_to_the_same_hash() -> void:
	var live: World = Rig.world()
	var log: PackedInt32Array = PackedInt32Array()
	for command: Command in Rig.load_command([1, 2], 5):
		command.tick = 0
		command.encode(log)
	var again: Array[Command] = []
	var at: int = 0
	while at >= 0 and at < log.size():
		var decoded: Command = Command.new()
		at = Command.decode(log, at, decoded)
		again.append(decoded)
	Rig.step(live, Rig.load_command([1, 2], 5))
	Rig.run(live, 119)
	var replayed: World = Rig.world()
	Sim.step(replayed, again)
	Rig.run(replayed, 119)
	assert_int(replayed.pass_count).is_equal(2)
	assert_int(replayed.state_hash()).is_equal(live.state_hash())
