extends GdUnitTestSuite
## Unloading a carrier (plan row P263b, ADR 0036 section 8). UNLOAD (6) sends the own carriers with
## a squad aboard to a point with `carry_mode` 1; `Carry.run` (ECONOMY, after `Air.run`) puts the
## squads of a stopped carrier back as rows (`World.insert_row`: same id, hp, owner and type) on the
## free FOOT cells of a ring walk within `unload_reach_tiles`, each with an `UNLOADED` event (kind
## 6, the carrier's id at index 6). No cell, or an `insert_row` refusal, keeps a squad aboard. A
## carrier that dies takes its squads with it: DIED records at its point and lost units. Worlds are
## `carry_rig.gd`'s: rifle squads 1 to 3, a tank 4, the carrier 5 at (14500, 2500), an enemy 6.

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const CARRIER: int = 5


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The world with squads 1 and 2 aboard carrier 5 (squad 2 hurt to 60).
func _loaded(rock: Array = []) -> World:
	var world: World = Rig.world(Rig.REACH, 8, rock)
	world.hp[world.index_of(2)] = 60
	Rig.aboard(world, 1, CARRIER)
	Rig.aboard(world, 2, CARRIER)
	return world


func _unload_command(ids: Array, x: int, y: int, player: int = 1) -> Array[Command]:
	return [Command.unload(player, PackedInt32Array(ids), x, y)]


## The UNLOADED records of the last tick, each as an array of its eight ints.
func _unloaded(world: World) -> Array:
	var found: Array = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.UNLOADED:
			found.append(Array(world.events.slice(at, at + World.EVENT_STRIDE)))
		at += World.EVENT_STRIDE
	return found


func test_the_command_has_its_number_and_a_factory() -> void:
	assert_int(Command.Type.UNLOAD).is_equal(6)
	assert_int(World.Event.UNLOADED).is_equal(6)
	var command: Command = Command.unload(2, PackedInt32Array([9, 4]), 3500, 1500)
	assert_array([command.type, command.player_id, command.target_x, command.target_y]).is_equal(
		[6, 2, 3500, 1500]
	)
	assert_array(Array(command.unit_ids)).is_equal([9, 4])
	assert_array(Array(command.payload)).is_empty()


func test_a_bad_unload_is_dropped_and_counted() -> void:
	var world: World = _loaded()
	var before: int = world.dropped_commands
	var bad: Array = [
		[[1], 99],  # No such carrier.
		[[1], 6],  # Not a carrier.
		[[4], 5],  # Not a carrier (a tank).
		[[], 5],  # No carriers.
	]
	Rig.step(world, _unload_command([99], 9500, 2500))
	Rig.step(world, _unload_command([6], 9500, 2500))  # An enemy's.
	Rig.step(world, _unload_command([4], 9500, 2500))
	Rig.step(world, _unload_command([], 9500, 2500))
	Rig.step(world, _unload_command([CARRIER], 9500, 2500, 2))  # Another player's carrier.
	assert_int(world.dropped_commands - before).is_equal(bad.size() + 1)
	# A carrier with nobody aboard is not given the order either.
	var empty: World = Rig.world()
	Rig.step(empty, _unload_command([CARRIER], 9500, 2500))
	assert_int(empty.dropped_commands).is_equal(1)
	assert_int(empty.carry_mode[empty.index_of(CARRIER)]).is_equal(0)


func test_the_carrier_moves_then_puts_the_squads_down_round_itself(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _loaded()
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	Rig.step(world, _unload_command([CARRIER], 9500, 2500))
	var carrier: int = world.index_of(CARRIER)
	assert_array([world.order[carrier], world.carry_mode[carrier]]).is_equal([World.Order.MOVE, 1])
	Rig.run(world, 3)
	assert_int(world.pass_count).is_equal(2)  # Still on the way.
	var version: int = world.rows_version
	var events: Array = []
	for _tick: int in 400:
		Rig.step(world)
		events.append_array(_unloaded(world))
		if world.pass_count == 0:
			break
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.rows_version).is_greater(version)
	carrier = world.index_of(CARRIER)
	assert_int(world.carry_mode[carrier]).is_equal(0)
	assert_int(world.unit_count()).is_equal(6)
	assert_array(Array(world.unit_id)).is_equal([1, 2, 3, 4, 5, 6])  # Ascending, ids kept.
	assert_int(world.hp[world.index_of(1)]).is_equal(100)
	assert_int(world.hp[world.index_of(2)]).is_equal(60)
	assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_greater(0)
	var cells: Array = []
	for id: int in [1, 2]:
		var row: int = world.index_of(id)
		assert_array([world.owner[row], world.type_index[row], world.order[row]]).is_equal(
			[1, Rig.RIFLE, World.Order.IDLE]
		)
		assert_int(world.fog_cell[row]).is_equal(-1)
		assert_bool(world.pos_x[row] % 1000 == 500 and world.pos_y[row] % 1000 == 500).is_true()
		(
			assert_int(
				maxi(
					absi(world.pos_x[row] - world.pos_x[carrier]),
					absi(world.pos_y[row] - world.pos_y[carrier])
				)
			)
			. is_less_equal(2500)
		)
		cells.append(Vector2i(world.pos_x[row], world.pos_y[row]))
	assert_bool(cells[0] != cells[1]).is_true()
	assert_int(events.size()).is_equal(2)
	assert_array([events[0][1], events[1][1]]).is_equal([1, 2])  # In table order.
	assert_array([events[0][0], events[0][5], events[0][6], events[0][7]]).is_equal(
		[6, 1, CARRIER, 0]
	)


func test_the_ring_walk_starts_at_the_top_left_and_counts_the_cells_it_looks_at() -> void:
	var world: World = _loaded()
	Rig.step(world, _unload_command([CARRIER], 14500, 2500))
	Rig.run(world, 2)
	assert_int(world.pass_count).is_equal(0)
	assert_array(Array(world.events)).is_empty()  # The event list is the last tick's.
	# Ring 1 round tile (14, 2), clockwise from (13, 1): the first two are the squads' cells.
	assert_array([world.pos_x[world.index_of(1)], world.pos_y[world.index_of(1)]]).is_equal(
		[13500, 1500]
	)
	assert_array([world.pos_x[world.index_of(2)], world.pos_y[world.index_of(2)]]).is_equal(
		[14500, 1500]
	)


func test_rock_all_round_keeps_the_squads_aboard() -> void:
	var rock: Array = []
	for x: int in range(11, 18):
		for y: int in 6:
			if Vector2i(x, y) != Vector2i(14, 2):
				rock.append(Vector2i(x, y))
	var world: World = _loaded(rock)
	var before: Array = [world.pass_id.duplicate(), world.pass_hp.duplicate(), world.pass_count]
	Rig.step(world, _unload_command([CARRIER], 14500, 2500))
	Rig.run(world, 3)
	assert_int(world.pass_count).is_equal(2)
	assert_array(Array(world.pass_id)).is_equal(Array(before[0]))
	assert_array(Array(world.pass_hp)).is_equal(Array(before[1]))
	assert_int(world.carry_mode[world.index_of(CARRIER)]).is_equal(0)
	assert_int(world.index_of(1)).is_equal(-1)
	assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_equal(0)  # The last tick's stats.


func test_one_free_cell_takes_one_squad_and_the_other_stays_aboard() -> void:
	var rock: Array = []
	for x: int in range(11, 18):
		for y: int in 6:
			if Vector2i(x, y) != Vector2i(14, 2) and Vector2i(x, y) != Vector2i(15, 3):
				rock.append(Vector2i(x, y))
	var world: World = _loaded(rock)
	Rig.step(world, _unload_command([CARRIER], 14500, 2500))
	Rig.run(world, 2)
	assert_int(world.pass_count).is_equal(1)
	assert_int(world.pass_id[0]).is_equal(2)
	assert_int(world.pass_hp[0]).is_equal(60)
	assert_array([world.pos_x[world.index_of(1)], world.pos_y[world.index_of(1)]]).is_equal(
		[15500, 3500]
	)
	assert_int(world.carry_mode[world.index_of(CARRIER)]).is_equal(0)


func test_an_insert_row_refusal_at_max_rows_keeps_the_squads_aboard() -> void:
	var world: World = _loaded()
	world.max_rows = world.unit_count()
	Rig.step(world, _unload_command([CARRIER], 14500, 2500))
	Rig.run(world, 3)
	assert_int(world.pass_count).is_equal(2)
	assert_array([world.pass_id[0], world.pass_id[1]]).is_equal([1, 2])
	assert_int(world.unit_count()).is_equal(4)
	assert_int(world.carry_mode[world.index_of(CARRIER)]).is_equal(0)


func test_a_later_order_cancels_the_unload() -> void:
	var world: World = _loaded()
	Rig.step(world, _unload_command([CARRIER], 3500, 2500))
	Rig.step(world, [Command.move(1, PackedInt32Array([CARRIER]), 20500, 2500)])
	assert_int(world.carry_mode[world.index_of(CARRIER)]).is_equal(0)
	Rig.run(world, 600)
	assert_int(world.pass_count).is_equal(2)
	# A STOP does the same.
	var stopped: World = _loaded()
	Rig.step(stopped, _unload_command([CARRIER], 3500, 2500))
	Rig.step(stopped, [Command.stop(1, PackedInt32Array([CARRIER]))])
	assert_int(stopped.carry_mode[stopped.index_of(CARRIER)]).is_equal(0)
	Rig.run(stopped, 5)
	assert_int(stopped.pass_count).is_equal(2)


func test_a_dying_carrier_takes_its_squads_with_it_and_they_count_as_lost() -> void:
	var world: World = _loaded()
	Rig.aboard(world, 3, CARRIER)  # Not a slot check: the table is set by hand.
	world.had_producer[1] = 1  # After the helper's own remove_dead, which counts a loss.
	var carrier: int = world.index_of(CARRIER)
	world.pos_x[carrier] = 7500
	world.pos_y[carrier] = 3500
	world.hp[carrier] = 0
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)
	var died: Array = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.DIED:
			died.append(Array(world.events.slice(at, at + World.EVENT_STRIDE)))
		at += World.EVENT_STRIDE
	assert_int(died.size()).is_equal(4)  # Three squads, then the carrier's own record.
	for index: int in 3:
		assert_array([died[index][1], died[index][2], died[index][3], died[index][5]]).is_equal(
			[index + 1, 7500, 3500, 1]
		)
		assert_array([died[index][4], died[index][Rig.DIED_FLAG_AT]]).is_equal([Rig.RIFLE, 0])
	assert_int(died[3][1]).is_equal(CARRIER)
	assert_int(world.stat_lost_units[1]).is_equal(4)
	assert_int(world.index_of(1)).is_equal(-1)


func test_a_carrier_that_lives_keeps_its_squads_and_the_other_carriers_squads() -> void:
	var world: World = _loaded()
	world.hp[world.index_of(6)] = 0  # Somebody else dies.
	Rig.step(world)
	assert_int(world.pass_count).is_equal(2)
	# Two carriers: only the dead one's squads go, and the table keeps its order.
	var two: World = _loaded()
	two.add_unit(1, Rig.TRUCK, 16500, 2500)  # Carrier 7.
	Rig.aboard(two, 3, 7)
	two.hp[two.index_of(CARRIER)] = 0
	Rig.step(two)
	assert_int(two.pass_count).is_equal(1)
	assert_array([two.pass_id[0], two.pass_carrier[0]]).is_equal([3, 7])
	assert_array([two.pass_id[1], two.pass_hp[1], two.pass_owner[1]]).is_equal([0, 0, 0])


func test_a_mend_and_an_unload_on_the_same_tick_read_the_right_building_row(
	impl: int, _test_parameters := _both()
) -> void:
	# The building is row 6 (id 7) before the unload and row 8 after it: two squads of lower id
	# are inserted above it. Without `Buildings.rebuild_lists` after the inserts, Mend would
	# read row 6.
	var world: World = GridWorld.from_rows(
		GridWorld.grass(24, 6),
		[
			World.MoveClass.FOOT,
			World.MoveClass.TRACKED,
			World.MoveClass.WHEELED,
			World.MoveClass.TRACKED
		]
	)
	world.player_count = 2
	for type: int in 4:
		world.type_max_hp[type] = 100
	world.type_carry_slots[2] = 2
	world.type_carry_classes[2] = 1
	world.type_foot_w[3] = 1
	world.type_foot_h[3] = 1
	world.type_speed[3] = 0
	world.passenger_cap = 8
	world.load_reach_milli = Rig.REACH
	world.unload_reach_tiles = 2
	world.unit_cap = 75
	world.mend_hp = 10
	world.mend_period_ticks = 15
	world.mend_cost_percent = 30
	WorldLoad.size_match_state(world)
	for x: int in [2500, 3500, 4500]:
		world.add_unit(1, Rig.RIFLE, x, 2500)  # Ids 1 to 3.
	world.add_unit(1, Rig.TANK, 2500, 4500)  # 4
	world.add_unit(1, Rig.TRUCK, 14500, 2500)  # 5
	world.add_unit(2, Rig.RIFLE, 20500, 4500)  # 6
	world.add_unit(1, 3, 8500, 4500)  # 7: the building.
	Rig.aboard(world, 1, CARRIER)
	Rig.aboard(world, 2, CARRIER)
	var building: int = world.index_of(7)
	world.hp[building] = 50
	world.cargo[building] = 1
	world.carry_mode[world.index_of(CARRIER)] = 1
	world.tick = 8  # (8 + 7) % 15 == 0: the building mends this tick.
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.index_of(7)).is_equal(building + 2)
	assert_int(world.hp[world.index_of(7)]).is_equal(60)
	assert_array(Array(world.building_rows)).is_equal([building + 2])


func test_two_runs_of_load_and_unload_cycles_hash_alike() -> void:
	var hashes: Array[int] = []
	for _run_number: int in 2:
		var world: World = Rig.world()
		for _cycle: int in 3:
			Rig.step(world, Rig.load_command([1, 2], CARRIER))
			Rig.run(world, 150)
			Rig.step(world, _unload_command([CARRIER], 12500, 2500))
			Rig.run(world, 150)
		hashes.append(world.state_hash())
		assert_int(world.pass_count).is_equal(0)
	assert_int(hashes[1]).is_equal(hashes[0])
	assert_int(hashes[0]).is_not_equal(Rig.world().state_hash())
