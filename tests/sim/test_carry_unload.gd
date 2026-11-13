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
	Rig.step(world, _unload_command([99], 9500, 2500))
	Rig.step(world, _unload_command([6], 9500, 2500))  # An enemy's.
	Rig.step(world, _unload_command([4], 9500, 2500))
	Rig.step(world, _unload_command([], 9500, 2500))
	Rig.step(world, _unload_command([CARRIER], 9500, 2500, 2))  # Another player's carrier.
	assert_int(world.dropped_commands - before).is_equal(5)
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


## Steps until the table is empty and returns the stats of that tick.
func _unload_tick(world: World) -> int:
	for _tick: int in 10:
		Rig.step(world)
		if world.pass_count == 0:
			return world.stats[World.Stat.EXIT_SCANNED]
	return -1


func _tile_of(world: World, id: int) -> Vector2i:
	var row: int = world.index_of(id)
	return Vector2i(world.pos_x[row] / 1000, world.pos_y[row] / 1000)


## A world with squads 1 and 2 aboard and the carrier standing at (x, y), unloading at once.
func _unloading_at(x: int, y: int, rock: Array = []) -> World:
	var world: World = _loaded(rock)
	var carrier: int = world.index_of(CARRIER)
	world.pos_x[carrier] = x
	world.pos_y[carrier] = y
	world.carry_mode[carrier] = 1
	return world


func test_the_ring_walk_is_turned_to_the_facing_and_counts_the_cells_it_looks_at() -> void:
	# Tile (14, 2) of 24 x 6 faces WEST (one quarter turn), so ring 1, clockwise from its top-left
	# corner (13, 1), starts a quarter ring on, at the top-right corner (15, 1), then (15, 2).
	var world: World = _unloading_at(14500, 2500)
	assert_int(_unload_tick(world)).is_equal(2)
	assert_array([world.pos_x[world.index_of(1)], world.pos_y[world.index_of(1)]]).is_equal(
		[15500, 1500]
	)
	assert_array([world.pos_x[world.index_of(2)], world.pos_y[world.index_of(2)]]).is_equal(
		[15500, 2500]
	)
	# The UNLOADED record: kind, id, x, y, type, owner, carrier, 0.
	assert_array(_unloaded(world)[1]).is_equal([6, 2, 15500, 2500, Rig.RIFLE, 1, CARRIER, 0])


func test_the_walk_goes_on_to_ring_two_in_order() -> void:
	# Ring 1 all rock: the cursor passes its 8 tiles, then ring 2 from (16, 0) (the WEST turn is two
	# of the ring's 16 steps per quarter, four here): (16,0) (16,1) (16,2) (16,3) ... clockwise.
	var rock: Array = []
	for x: int in range(13, 16):
		for y: int in range(1, 4):
			if Vector2i(x, y) != Vector2i(14, 2):
				rock.append(Vector2i(x, y))
	var world: World = _unloading_at(14500, 2500, rock)
	assert_int(_unload_tick(world)).is_equal(8 + 2)
	assert_array([_tile_of(world, 1), _tile_of(world, 2)]).is_equal(
		[Vector2i(16, 0), Vector2i(16, 1)]
	)


func test_the_reach_is_a_ring_count_not_one_more_or_less() -> void:
	# Everything within the columns 11-17 is rock but the carrier's tile and (16, 4), a ring 2 tile.
	var rock: Array = []
	for x: int in range(11, 18):
		for y: int in 6:
			if Vector2i(x, y) != Vector2i(14, 2) and Vector2i(x, y) != Vector2i(16, 4):
				rock.append(Vector2i(x, y))
	var short: World = _unloading_at(14500, 2500, rock)
	short.unload_reach_tiles = 1
	Rig.step(short)  # Stays aboard.
	assert_int(short.pass_count).is_equal(2)
	assert_int(short.stats[World.Stat.EXIT_SCANNED]).is_equal(8)  # Ring 1 fully looked at.
	var enough: World = _unloading_at(14500, 2500, rock)  # unload_reach_tiles 2
	Rig.step(enough)
	assert_int(enough.pass_count).is_equal(1)
	assert_int(_tile_of(enough, 1).x).is_equal(16)
	assert_int(_tile_of(enough, 1).y).is_equal(4)
	# 8 of ring 1, then 5 of ring 2 up to (16, 4); squad 2 then finds the other 11 all rock.
	assert_int(enough.stats[World.Stat.EXIT_SCANNED]).is_equal(24)
	var none: World = _unloading_at(14500, 2500, rock)
	none.unload_reach_tiles = 0
	Rig.step(none)
	assert_int(none.pass_count).is_equal(2)
	assert_int(none.stats[World.Stat.EXIT_SCANNED]).is_equal(0)


func test_at_the_map_edge_only_on_map_tiles_are_looked_at_and_used() -> void:
	# Tile (0, 0) faces EAST (three quarter turns). Ring 1 clockwise from (-1,-1): (0,-1) (1,-1)
	# (1,0) (1,1) (0,1) (-1,1) (-1,0) (-1,-1); the walk starts at index 6.
	var corner: World = _unloading_at(500, 500)
	assert_int(_unload_tick(corner)).is_equal(2)  # (1, 0) then (1, 1); off-map tiles not counted.
	assert_array([_tile_of(corner, 1), _tile_of(corner, 2)]).is_equal(
		[Vector2i(1, 0), Vector2i(1, 1)]
	)
	# Column 0, row 2: the left column of the ring is off the map.
	var edge: World = _unloading_at(500, 2500)
	var scanned: int = _unload_tick(edge)
	for id: int in [1, 2]:
		var row: int = edge.index_of(id)
		assert_bool(edge.pos_x[row] > 0 and edge.pos_y[row] > 0).is_true()
	assert_int(scanned).is_equal(2)
	# The last row, the last column.
	var far: World = _unloading_at(23500, 5500)
	assert_int(_unload_tick(far)).is_greater(0)
	for id: int in [1, 2]:
		var row: int = far.index_of(id)
		assert_bool(far.pos_x[row] < 24000 and far.pos_y[row] < 6000).is_true()


func test_a_half_turn_of_the_carrier_mirrors_the_cells() -> void:
	# The map is 24 x 6 tiles. The image of (x, y) milli-tiles is (24000 - x, 6000 - y); a carrier
	# on a tile border is included, which `World.cell_of` puts in the tile before it.
	for point: Vector2i in [
		Vector2i(4500, 1500), Vector2i(5000, 1500), Vector2i(7500, 2000), Vector2i(500, 500)
	]:
		var first: World = _unloading_at(point.x, point.y)
		var second: World = _unloading_at(24000 - point.x, 6000 - point.y)
		_unload_tick(first)
		_unload_tick(second)
		for id: int in [1, 2]:
			var mirrored: Vector2i = Vector2i(23, 5) - _tile_of(first, id)
			(
				assert_vector(_tile_of(second, id))
				. override_failure_message("point %s id %d" % [point, id])
				. is_equal(mirrored)
			)


func test_attack_ends_a_pending_unload() -> void:
	var world: World = _loaded()
	world.type_weapon[Rig.TRUCK] = 0  # Armed enough for `_own_rows` (no weapon tables: unarmed).
	Rig.step(world, _unload_command([CARRIER], 3500, 2500))
	assert_int(world.carry_mode[world.index_of(CARRIER)]).is_equal(1)
	Rig.step(world, [Command.attack(1, PackedInt32Array([CARRIER]), 6)])
	var carrier: int = world.index_of(CARRIER)
	assert_array([world.order[carrier], world.carry_mode[carrier]]).is_equal(
		[World.Order.ATTACK, 0]
	)


func test_an_attack_move_ends_a_pending_unload() -> void:
	var world: World = _loaded()
	Rig.step(world, _unload_command([CARRIER], 3500, 2500))
	Rig.step(world, [Command.attack_move(1, PackedInt32Array([CARRIER]), 20500, 2500)])
	assert_int(world.carry_mode[world.index_of(CARRIER)]).is_equal(0)


func test_a_carrier_that_dies_on_an_unloading_tick_unloads_nothing() -> void:
	var world: World = _unloading_at(14500, 2500)
	world.hp[world.index_of(CARRIER)] = 0
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)
	assert_array(_unloaded(world)).is_empty()
	assert_int(world.index_of(1)).is_equal(-1)
	assert_int(world.unit_count()).is_equal(3)  # 1, 2 gone with it; 3, 4, 6 stay.


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
	var world: World = _unloading_at(14500, 2500, rock)
	Rig.step(world)
	assert_int(world.pass_count).is_equal(1)
	assert_int(world.pass_id[0]).is_equal(2)
	assert_int(world.pass_hp[0]).is_equal(60)
	assert_array([world.pass_carrier[1], world.pass_id[1], world.pass_hp[1]]).is_equal([0, 0, 0])
	# (15,1) (15,2) then (15,3) for squad 1; squad 2 passes the other 5 of ring 1 and all 16 of ring 2.
	assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_equal(24)
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
	# The building is row 4 (id 7) before the unload and row 6 after it: two squads of lower id
	# are inserted above it. Without `Buildings.rebuild_lists` after the inserts, Mend would
	# read row 4, the carrier.
	var world: World = GridWorld.from_rows(
		GridWorld.grass(24, 6),
		[
			World.MoveClass.FOOT,
			World.MoveClass.TRACKED,
			World.MoveClass.WHEELED,
			World.MoveClass.TRACKED,
			World.MoveClass.WHEELED
		]
	)
	world.player_count = 2
	for type: int in 5:
		world.type_max_hp[type] = 100
	world.type_carry_slots[2] = 2
	world.type_carry_classes[2] = 1
	world.type_harvest[4] = 100  # Type 4 is a harvester; the tank (id 4) is an aircraft.
	world.type_layer_bit[Rig.TANK] = World.Layer.AIR
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
	world.add_unit(1, 4, 9500, 4500)  # 8: the harvester.
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
	# The other derived lists are current too: equal to a fresh rebuild, and not empty.
	var harvesters: Array = Array(world.harvester_rows)
	var air: Array = Array(world.air_rows)
	world._lists_version = -1
	Buildings.rebuild_lists(world)
	assert_array(harvesters).is_equal(Array(world.harvester_rows))
	assert_array(air).is_equal(Array(world.air_rows))
	assert_array(harvesters).is_equal([world.index_of(8)])
	assert_array(air).is_equal([world.index_of(4)])


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
