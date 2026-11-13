extends GdUnitTestSuite
## Loading a carrier (plan row P263, ADR 0036 section 8). LOAD (5) sends the carrier and the valid
## squads (own, FOOT by the carrier's `type_carry_classes`, the lowest ids up to the free slots) to
## the lowest-id squad's point and marks each squad's `order_target` with the carrier. `Carry.board`
## (in the REMOVE mark, after `FogUpdate.begin`) moves a marked squad within `load_reach_milli` of a
## living carrier with a free slot into the passenger table: `hp` 0 and `build_left`
## `Carry.BOARDED`, so REMOVE writes DIED with flag 2 at index 6, and no loss is counted. The squads
## aboard count toward `unit_cap`. Nothing moves with the reach or the table at 0. Types: 0 a rifle
## squad (FOOT), 1 a tank (TRACKED), 2 a carrier (WHEELED) of 2 slots that takes FOOT.

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func test_the_command_has_its_number_and_a_factory() -> void:
	assert_int(Command.Type.LOAD).is_equal(5)
	var command: Command = Command.board(2, PackedInt32Array([4, 3]), 9)
	assert_array([command.type, command.player_id, command.target_id]).is_equal([5, 2, 9])
	assert_array(Array(command.unit_ids)).is_equal([4, 3])
	assert_array(Array(command.payload)).is_empty()
	assert_int(Carry.BOARDED).is_equal(-2)


func test_load_sends_the_carrier_and_the_lowest_ids_to_the_first_squad_and_marks_them() -> void:
	var world: World = Rig.world()
	world.carry_mode[world.index_of(5)] = 1
	# The ids out of order, one twice, a tank among them. Applied without a step, so that the first
	# squad, already at G, has not yet ended its order.
	var command: Command = Rig.load_command([3, 4, 2, 1, 2], 5)[0]
	assert_bool(Carry.apply_load(world, command)).is_true()
	for id: int in [1, 2]:
		var row: int = world.index_of(id)
		assert_int(world.order[row]).is_equal(World.Order.MOVE)
		assert_int(world.order_target[row]).is_equal(5)
	# The slots are 2: squad 3 and the tank (the wrong class) were left alone.
	for id: int in [3, 4]:
		assert_int(world.order[world.index_of(id)]).is_equal(World.Order.IDLE)
		assert_int(world.order_target[world.index_of(id)]).is_equal(0)
	var carrier: int = world.index_of(5)
	(
		assert_array([world.order[carrier], world.order_target[carrier], world.carry_mode[carrier]])
		. is_equal([World.Order.MOVE, 0, 0])
	)
	# G is the lowest-id squad's point: the carrier's goal is within a formation slot of (2500, 2500).
	assert_int(absi(world.goal_x[carrier] - 2500)).is_less(1500)
	assert_int(absi(world.goal_y[carrier] - 2500)).is_less(1500)


func test_a_bad_load_is_dropped_and_counted() -> void:
	var world: World = Rig.world()
	var before: int = world.dropped_commands
	var bad: Array[Array] = [
		[[1], 99],  # No such carrier.
		[[1], 6],  # Not a carrier (a rifle squad).
		[[1], 1],  # Not a carrier (a rifle squad of one's own).
		[[4], 5],  # A tank: its class is not in the mask.
		[[6], 5],  # An enemy squad.
		[[99], 5],  # No such squad.
		[[5], 5],  # The carrier itself.
		[[], 5],  # No squads.
	]
	for case: Array in bad:
		Rig.step(world, Rig.load_command(case[0], case[1]))
	assert_int(world.dropped_commands - before).is_equal(bad.size())
	# Another player's carrier, a defeated player's order and an over-long list.
	var again: World = Rig.world()
	Rig.step(again, Rig.load_command([6], 5, 2))
	var long: Array = []
	for id: int in Command.MAX_UNITS + 1:
		long.append(id + 1)
	Rig.step(again, Rig.load_command(long, 5))
	assert_int(again.dropped_commands).is_equal(2)
	for row: int in again.unit_count():
		assert_int(again.order[row]).is_equal(World.Order.IDLE)


func test_a_full_carrier_refuses_a_load() -> void:
	var world: World = Rig.world()
	for id: int in [1, 2]:
		Rig.aboard(world, id, 5)
	Rig.step(world, Rig.load_command([3], 5))
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.order[world.index_of(3)]).is_equal(World.Order.IDLE)


func test_the_squads_board_on_arrival_and_leave_the_row_table(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Rig.world()
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var rows_before: int = world.unit_count()
	world.hp[world.index_of(2)] = 60
	Rig.step(world, Rig.load_command([1, 2], 5))
	var flags: Array[int] = []
	var boarded_at: int = -1
	for tick: int in 200:
		Rig.step(world)
		flags.append_array(Rig.died_flags(world))
		if world.pass_count == 2 and boarded_at < 0:
			boarded_at = tick
	assert_int(boarded_at).is_greater(0)
	assert_array(flags).is_equal([2, 2])
	# The records, in boarding order (ascending row order within a tick): id, type, hp, owner.
	var seen: Array = []
	for at: int in world.pass_count:
		seen.append(
			[world.pass_id[at], world.pass_type[at], world.pass_hp[at], world.pass_owner[at]]
		)
	seen.sort()
	assert_array(seen).is_equal([[1, Rig.RIFLE, 100, 1], [2, Rig.RIFLE, 60, 1]])
	assert_array([world.pass_carrier[0], world.pass_carrier[1]]).is_equal([5, 5])
	assert_int(world.unit_count()).is_equal(rows_before - 2)
	assert_int(world.index_of(1)).is_equal(-1)
	assert_int(world.index_of(2)).is_equal(-1)
	assert_int(world.index_of(5)).is_greater_equal(0)
	# No loss, for a player who has a producer or none.
	assert_array([world.stat_lost_units[1], world.stat_lost_units[2]]).is_equal([0, 0])


func test_boarding_counts_no_loss_even_with_a_producer() -> void:
	var world: World = Rig.world()
	world.had_producer[1] = 1
	Rig.step(world, Rig.load_command([1], 5))
	Rig.run(world, 200)
	assert_int(world.pass_count).is_equal(1)
	assert_int(world.stat_lost_units[1]).is_equal(0)
	# A squad killed instead counts, so the control is live.
	world.hp[world.index_of(3)] = 0
	Rig.step(world)
	assert_int(world.stat_lost_units[1]).is_equal(1)


func test_the_event_is_a_died_record_with_flag_2_at_the_carriers_squad_point() -> void:
	var world: World = Rig.world()
	var row: int = world.index_of(1)
	world.order_target[row] = 5
	world.pos_x[world.index_of(5)] = world.pos_x[row] + 1000
	world.pos_y[world.index_of(5)] = world.pos_y[row]
	Rig.step(world)
	var died: Array = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.DIED:
			died.append(Array(world.events.slice(at, at + World.EVENT_STRIDE)))
		at += World.EVENT_STRIDE
	assert_int(died.size()).is_equal(1)
	assert_int(died[0][1]).is_equal(1)  # The squad's id.
	assert_int(died[0][Rig.DIED_FLAG_AT]).is_equal(2)
	assert_int(died[0][7]).is_equal(0)


func test_a_squad_out_of_reach_a_dead_carrier_or_a_zero_reach_does_not_board() -> void:
	var far: World = Rig.world()
	far.order_target[far.index_of(1)] = 5  # 12 tiles away, not moving: out of reach.
	Rig.run(far, 5)
	assert_int(far.pass_count).is_equal(0)
	assert_int(far.order_target[far.index_of(1)]).is_equal(5)
	var dead: World = Rig.world()
	dead.order_target[dead.index_of(1)] = 5
	dead.pos_x[dead.index_of(5)] = 3000
	dead.hp[dead.index_of(5)] = 0
	Rig.step(dead)
	assert_int(dead.pass_count).is_equal(0)
	assert_int(dead.index_of(1)).is_greater_equal(0)
	for inert: World in [Rig.world(0), Rig.world(Rig.REACH, 0)]:
		inert.order_target[inert.index_of(1)] = 5
		inert.pos_x[inert.index_of(5)] = 3000
		Rig.run(inert, 3)
		assert_int(inert.pass_count).is_equal(0)
		assert_int(inert.unit_count()).is_equal(6)


func test_a_carrier_with_no_free_slot_takes_no_more_and_frees_the_squad_to_move() -> void:
	var world: World = Rig.world()
	world.pos_x[world.index_of(5)] = 3500
	for id: int in [1, 2, 3]:
		world.order_target[world.index_of(id)] = 5  # Three marked, two slots.
	Rig.step(world)
	assert_int(world.pass_count).is_equal(2)
	assert_array([world.pass_id[0], world.pass_id[1]]).is_equal([1, 2])
	assert_int(world.order_target[world.index_of(3)]).is_equal(0)
	assert_int(world.unit_count()).is_equal(4)
	Rig.run(world, 5)
	assert_int(world.pass_count).is_equal(2)


func test_a_plain_move_or_attack_move_takes_the_mark_off_and_an_enemy_target_stays() -> void:
	var world: World = Rig.world()
	Rig.step(world, Rig.load_command([1, 2], 5))
	Rig.step(world, [Command.move(1, PackedInt32Array([1]), 2500, 4500)])
	Rig.step(world, [Command.attack_move(1, PackedInt32Array([2]), 2500, 4500)])
	assert_int(world.order_target[world.index_of(1)]).is_equal(0)
	assert_int(world.order_target[world.index_of(2)]).is_equal(0)
	# An enemy id left from an ATTACK survives a MOVE: it names no own row.
	world.order_target[world.index_of(3)] = 6
	Rig.step(world, [Command.move(1, PackedInt32Array([3]), 2500, 4500)])
	assert_int(world.order_target[world.index_of(3)]).is_equal(6)
	# A STOP clears it as before.
	Rig.step(world, Rig.load_command([3], 5))
	Rig.step(world, [Command.stop(1, PackedInt32Array([3]))])
	assert_int(world.order_target[world.index_of(3)]).is_equal(0)
	# The squad that was moved away does not board as it passes the carrier.
	world.pos_x[world.index_of(5)] = 2500
	world.pos_y[world.index_of(5)] = 4500
	Rig.run(world, 20)
	assert_int(world.pass_count).is_equal(0)


func test_squads_aboard_count_toward_unit_cap() -> void:
	var world: World = Rig.world()
	Rig.aboard(world, 1, 5)
	Rig.aboard(world, 2, 5)
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(5)  # 3 on the map, 2 aboard.
	assert_int(Carry.passengers_of(world, 1)).is_equal(2)
	assert_int(Carry.passengers_of(world, 2)).is_equal(0)
	assert_int(Carry.aboard(world, 5)).is_equal(2)
	assert_int(ProductionSpawn.mobile_rows(world, 2)).is_equal(1)
	# At the cap the spawn is refused: 3 on the map plus 2 aboard fill a cap of 5.
	world.unit_cap = 6
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_less(world.unit_cap)
	world.unit_cap = 5
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_greater_equal(world.unit_cap)


func test_two_runs_of_a_load_hash_alike_and_the_passengers_are_in_the_hash() -> void:
	var hashes: Array[int] = []
	for _run_number: int in 2:
		var world: World = Rig.world()
		Rig.step(world, Rig.load_command([1, 2], 5))
		Rig.run(world, 120)
		hashes.append(world.state_hash())
		assert_int(world.pass_count).is_equal(2)
	assert_int(hashes[1]).is_equal(hashes[0])
	var other: World = Rig.world()
	Rig.run(other, 121)
	assert_int(other.state_hash()).is_not_equal(hashes[0])
