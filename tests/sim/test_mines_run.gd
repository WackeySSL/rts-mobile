extends "res://tests/sim/support/mine_suite.gd"
## Mines over whole runs (plan row P287, ADR 0037 sections 8 and 16): `mine_at` against a rebuild
## and the `MINE_CHECKS` bound after every step, a run under the twin and the kernels, two mines
## in one tick, a rupture through `Strike.run`, the formation slots and the small guards. The rig is
## `support/mine_suite.gd`.


func test_mine_at_equals_a_rebuild_and_mine_checks_is_bounded_after_every_step() -> void:
	var world: World = _world()
	_scenario(world)
	assert_bool(world.credits[1] == 20).is_true()  # Two mines paid, the third refused.


func test_a_run_with_lays_and_blasts_is_the_same_under_the_twin_and_the_kernels() -> void:
	var runs: Array[PackedInt64Array] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = _world()
		assert_array(SimImpls.use(world, impl)).is_empty()
		var hashes: PackedInt64Array = PackedInt64Array()
		_scenario(world, hashes)
		runs.append(hashes)
	assert_array(Array(runs[0])).is_equal(Array(runs[1]))
	assert_int(runs[0].size()).is_equal(16)


func test_two_mines_blast_in_one_tick_in_ascending_id_and_a_row_in_both_radii_is_hurt_twice(
) -> void:
	var world: World = _world()
	_put(world, 1, 5, 5)
	_put(world, 1, 9, 5)
	_put(world, 1, 6, 5)  # One cell from the first: its blast covers cell 5.
	var a: int = _add(world, 2, TANK, 5, 5)
	var b: int = _add(world, 2, TANK, 9, 5)
	var c: int = _add(world, 2, TANK, 6, 5)
	var middle: int = _add(world, 2, SQUAD, 5, 5)
	world.pos_x[middle] = 5999  # In cell 5, 501 from cell 6's centre: inside both radii.
	_checked(world)
	var blasts: Array[PackedInt32Array] = _blasts(world)
	assert_int(blasts.size()).is_equal(3)
	# [MINE_BLAST, id, x, y, weapon, owner, 0, 0]: x is the column, y the line (9 != 5).
	assert_array(Array(blasts[0])).is_equal([7, 1, 5500, 5500, 0, 1, 0, 0])
	assert_array(Array(blasts[1])).is_equal([7, 2, 9500, 5500, 0, 1, 0, 0])
	assert_array(Array(blasts[2])).is_equal([7, 3, 6500, 5500, 0, 1, 0, 0])
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.mine_at.count(0)).is_equal(COLS * 12)
	assert_int(world.hp[middle]).is_equal(200 - 60 - 60)  # Infantry 100 percent, twice.
	assert_int(world.hp[b]).is_equal(170)
	assert_int(world.hp[a]).is_equal(200 - 30 - 30)  # Light: its own mine and the next one's.
	assert_int(world.hp[c]).is_equal(200 - 30 - 30)
	var vertical: World = _world()
	_put(vertical, 1, 3, 8)
	_add(vertical, 2, TANK, 3, 8)
	_step(vertical)
	assert_array(Array(_blasts(vertical)[0]).slice(2, 4)).is_equal([3500, 8500])


func test_a_rupture_through_strike_run_clears_mines_in_its_radius_with_no_blast() -> void:
	var world: World = Strikes.world()
	for column_name: StringName in World.MINE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column.resize(4)
	var radius: int = Strikes.radius_of(world, "bore")
	var inside: int = 10 * Strikes.COLS + 15  # The point's own cell, (15, 10).
	var outside: int = 10 * Strikes.COLS + 15 + (radius / 1000) + 2
	for entry: Array in [[1, inside], [2, outside]]:
		var at: int = world.mine_count
		world.mine_id[at] = world.next_mine_id
		world.mine_owner[at] = entry[0]
		world.mine_cell[at] = entry[1]
		world.mine_armed_tick[at] = 1
		world.mine_at[entry[1]] = at + 1
		world.next_mine_id += 1
		world.mine_count += 1
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	var landing: int = world.strike_tick[1]
	var blasts: int = 0
	while world.tick < landing:
		Strikes.step(world)
		blasts += _blasts(world).size()
		assert_array(world.mine_at).is_equal(_rebuilt(world))
	assert_int(world.mine_count).is_equal(1)
	assert_array([world.mine_owner[0], world.mine_cell[0]]).is_equal([2, outside])
	assert_int(blasts).is_equal(0)


func test_layers_sent_to_one_point_get_distinct_formation_slots() -> void:
	var world: World = _world()
	var ids: PackedInt32Array = PackedInt32Array()
	for column: int in 3:
		ids.append(world.unit_id[_add(world, 1, LAYER, 2 + column, 2)])
	assert_bool(Mines.apply_lay(world, Command.lay_mine(1, ids, 9500, 7500))).is_true()
	var goals: Dictionary[Vector2i, bool] = {}
	for id: int in ids:
		var row: int = world.index_of(id)
		goals[Vector2i(world.goal_x[row], world.goal_y[row])] = true
	assert_int(goals.size()).is_equal(3)


func test_neutral_rows_do_not_trigger_or_take_damage_and_an_aware_row_takes_the_blast() -> void:
	var world: World = _world()
	_put(world, 1, 5, 5)
	var neutral: int = _add(world, 0, TANK, 5, 5)
	_steps(world, 3)
	assert_int(world.mine_count).is_equal(1)  # A neutral row never triggers it.
	var aware: int = _add(world, 2, AWARE, 6, 5)  # Takes damage though it cannot trigger.
	_add(world, 2, TANK, 5, 5)
	_step(world)
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.hp[neutral]).is_equal(200)
	assert_int(world.hp[aware]).is_equal(200 - 60)


func test_a_lay_is_dropped_with_no_cap_and_an_aircraft_is_not_a_layer() -> void:
	var world: World = _world(0)
	var layer: int = _add(world, 1, LAYER, 2, 2)
	var before: int = world.dropped_commands
	_step(world, [_lay([world.unit_id[layer]])])
	assert_int(world.dropped_commands - before).is_equal(1)
	assert_int(world.carry_mode[layer]).is_equal(0)
	var capped: World = _world()
	var jet: int = _add(capped, 1, JET, 2, 2)
	capped.type_mine_weapon[JET] = capped.type_mine_weapon[LAYER]
	assert_bool(Mines.apply_lay(capped, _lay([capped.unit_id[jet]]))).is_false()
	assert_int(capped.ready_tick[jet]).is_equal(0)


func test_repair_and_unload_also_end_a_pending_lay() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, 2, 2)
	var shed: int = world.add_building(1, SHED, 6, 6)
	world.carry_mode[layer] = Mines.LAYING
	_step(world, [Command.repair(1, PackedInt32Array([world.unit_id[layer]]), shed)])
	assert_int(world.carry_mode[layer]).is_equal(0)
	var carrying: World = _world()
	var carrier: int = _add(carrying, 1, CARRIER, 3, 3)
	var squad: int = _add(carrying, 1, SQUAD, 3, 3)
	var carrier_id: int = carrying.unit_id[carrier]
	_step(carrying, [Command.board(1, PackedInt32Array([carrying.unit_id[squad]]), carrier_id)])
	_steps(carrying, 3)
	assert_int(Carry.aboard(carrying, carrier_id)).is_greater(0)
	carrying.carry_mode[carrying.index_of(carrier_id)] = Mines.LAYING
	_step(carrying, [Command.unload(1, PackedInt32Array([carrier_id]), 8500, 8500)])
	assert_int(carrying.carry_mode[carrying.index_of(carrier_id)]).is_equal(1)


## Both coordinates are borders past the middle of the map: `World.cell_of` puts the point in the
## tile before them, and the mark pass's inlined lookup has to agree on each axis.
func test_a_trigger_on_a_border_past_the_middle_is_in_the_tile_before_it() -> void:
	var world: World = _world()
	_put(world, 1, 8, 6)
	var tank: int = _add(world, 2, TANK, 2, 2)
	world.pos_x[tank] = 9000
	world.pos_y[tank] = 7000
	assert_int(world.cell_of(9000, 7000)).is_equal(6 * COLS + 8)
	_step(world)
	assert_int(world.mine_count).is_equal(0)
	assert_int(_blasts(world).size()).is_equal(1)
