extends GdUnitTestSuite
## Movement v2, part 3 (P37b; ADR 0008 sections 2 and 3): FIELD mode. A blocked line gives a unit
## the flow field of its goal, `nav_next` names the next tile at event cadence, a line that becomes
## clear sends the unit DIRECT again, and a pending field leaves it steering DIRECT. Maps are built
## in code (GridWorld). The stall, the references and the ATTACK fields are in
## test_movement_stall.gd, the checkpoint ticks in test_movement_flow_line.gd.
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.
## The cases that count the twin's `best_neighbour` calls and the one that compares the
## implementations itself stay on the twin.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FieldCadence: GDScript = preload("res://tests/sim/support/field_cadence.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
## The terrain index of rock in GridWorld's GROUND string.
const ROCK: int = 2


## A 30 x 14 map with a wall in tile column 12 and a gap of two tiles in rows 9 and 10. Twelve tanks
## stand north-west of the wall and are ordered to slots north-east of it (the straight lines cross
## the wall, so the way leads through the gap). Every tick no unit centre is on a blocked tile; at
## the end all twelve have arrived on their slots, and the run used FIELD (not vacuous).
func test_twelve_tanks_reach_slots_through_the_gap_and_no_centre_is_on_rock(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _gap_world(impl, false)
	var rows: PackedInt32Array = GridWorld.add_block(world, 12, 4, 3000, 1500, 1000, 0)
	var field_ticks: int = 0
	var slots_used: int = 0
	for tick: int in 600:
		var commands: Array[Command] = []
		if tick == 0:
			var ids: PackedInt32Array = PackedInt32Array(range(1, 13))
			commands.append(_stamped(Command.move(1, ids, 22000, 3000), 0))
		Sim.step(world, commands)
		for row: int in rows:
			var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
			(
				assert_bool(world.is_passable(cell, TRACKED))
				. override_failure_message("tick %d row %d" % [tick, row])
				. is_true()
			)
		field_ticks += world.nav_mode.count(FIELD)
		slots_used = maxi(slots_used, world.flow.status.size() - world.flow.status.count(0))
		if world.order.count(IDLE) == 12:
			break
	assert_int(field_ticks).is_greater(100)
	assert_int(world.order.count(IDLE)).is_equal(12)
	for row: int in rows:
		var here: Array[int] = [world.pos_x[row], world.pos_y[row]]
		assert_array(here).is_equal([world.goal_x[row], world.goal_y[row]])
		assert_int(world.pos_x[row]).is_greater(13000)
	assert_array([world.field.count(-1), world.nav_mode.count(FIELD)]).is_equal([12, 0])
	# One field serves the group (see test_a_group_order_takes_one_field_per_class_keyed_on_...).
	assert_int(slots_used).is_equal(1)


## Scrub is open to infantry and blocked to tanks (data/terrain): a band of scrub across rows 0 to 8
## of a 24 x 12 map, grass below. A tank and an infantry squad are ordered across it along their own
## rows. The infantry's line is clear (the class of the unit is the class the check uses), so it
## never needs a field and walks straight; the tank's line is blocked, so it follows a field south
## around the band and back, and arrives later. No tank centre is ever on scrub.
func test_infantry_crosses_scrub_and_tanks_go_around(
	impl: int, _test_parameters := _both()
) -> void:
	var map: PackedStringArray = GridWorld.grass(24, 12)
	for row: int in 9:
		map[row] = map[row].left(10) + "^^" + map[row].substr(12)
	var world: World = _in(GridWorld.from_rows(map, [TRACKED, FOOT]), impl)
	world.add_unit(1, 0, 3500, 2500)
	world.add_unit(1, 1, 3500, 4500)
	var tank_south: int = 0
	var tank_field: int = 0
	var arrived: Array[int] = [-1, -1]
	for tick: int in 600:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 20500, 2500), 0))
			commands.append(_stamped(Command.move(1, PackedInt32Array([2]), 20500, 4500), 0))
		Sim.step(world, commands)
		assert_int(world.nav_mode[1]).is_not_equal(FIELD)
		assert_int(world.pos_y[1]).is_equal(4500)
		(
			assert_bool(world.is_passable(world.cell_of(world.pos_x[0], world.pos_y[0]), TRACKED))
			. is_true()
		)
		tank_south = maxi(tank_south, world.pos_y[0])
		tank_field += 1 if world.nav_mode[0] == FIELD else 0
		for row: int in 2:
			if world.order[row] == IDLE and arrived[row] == -1:
				arrived[row] = tick
		if world.order.count(IDLE) == 2:
			break
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([20500, 2500])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([20500, 4500])
	assert_int(tank_field).is_greater(50)
	assert_int(tank_south).is_greater(9000)
	assert_int(arrived[1]).is_less(arrived[0])


## A tank west of a wall (column 8, rows 0 to 6 of a 20 x 12 map) is ordered east of it along row 2:
## the blocked line gives it a field, which leads south around the wall's end. Once it is past the
## end its line is clear: on the tile entry that finds it clear the unit is DIRECT with `field` -1
## and `nav_next` -1, it never checks again, the cache's reference count falls to 0 at the next
## recount, and it arrives. Not vacuous: it was FIELD before, with a next tile.
func test_a_unit_whose_line_becomes_clear_switches_to_direct_and_drops_its_field(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 7:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, rock)), impl)
	world.add_unit(1, 0, 3500, 2500)
	var first_field: int = -1
	var switched: int = -1
	var seen_next: bool = false
	var checks_after: int = 0
	for tick: int in 400:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 13500, 2500), 0))
		Sim.step(world, commands)
		if world.nav_mode[0] == FIELD:
			first_field = tick if first_field == -1 else first_field
			seen_next = seen_next or world.nav_next[0] >= 0
		elif first_field != -1 and switched == -1 and world.order[0] != IDLE:
			switched = tick
			assert_array([world.field[0], world.nav_next[0]]).is_equal([-1, -1])
			assert_int(world.nav_mode[0]).is_equal(DIRECT)
			assert_int(world.nav_cell[0]).is_not_equal(-1)
			assert_int(world.stats[World.Stat.LINE_CHECKS]).is_equal(1)
		elif switched != -1:
			checks_after += world.stats[World.Stat.LINE_CHECKS]
			assert_int(world.nav_mode[0]).is_not_equal(FIELD)
		if world.order[0] == IDLE:
			break
	assert_int(first_field).is_greater(-1)
	assert_int(switched).is_greater(first_field)
	assert_bool(seen_next).is_true()
	assert_int(checks_after).is_equal(0)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([13500, 2500, IDLE])
	FlowCache.run(world, 0)
	assert_int(world.flow.refs(0)).is_equal(0)


## A pending field leaves units steering DIRECT: with `flow_cells_per_tick` 0 the field of a blocked
## line is never integrated, and the unit that holds it (FIELD, `nav_next` -1) moves tick by tick
## exactly like a DIRECT unit of the same order on a twin world (marked as checked, so it never asks
## for a field). Both slide along the wall. Then the budget comes back and the same unit follows
## the field: it was not stuck waiting for it.
func test_a_pending_field_leaves_units_steering_direct(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 9:
		rock.append(Vector2i(8, row))
	var held: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, rock)), impl)
	var plain: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, rock)), impl)
	held.flow_cells_per_tick = 0
	for world: World in [held, plain]:
		world.add_unit(1, 0, 3500, 2500)
		world.order[0] = MOVE
		world.goal_x[0] = 13500
		world.goal_y[0] = 4500
	plain.nav_mode[0] = DIRECT
	plain.nav_cell[0] = plain.cell_of(3500, 2500)
	for tick: int in 60:
		Sim.step(held, [])
		Sim.step(plain, [])
		var label: String = "tick %d" % tick
		assert_array([held.pos_x[0], held.pos_y[0]]).override_failure_message(label).is_equal(
			[plain.pos_x[0], plain.pos_y[0]]
		)
		assert_int(held.stats[World.Stat.FLOW_CELLS]).is_equal(0)
	assert_array([held.nav_mode[0], held.field[0], held.nav_next[0]]).is_equal([FIELD, 0, -1])
	assert_bool(held.flow.field(0).complete).is_false()
	assert_int(plain.nav_mode[0]).is_equal(DIRECT)
	assert_int(held.pos_x[0]).is_between(7000, 8000)
	held.flow_cells_per_tick = 512
	for _tick: int in 400:
		Sim.step(held, [])
		if held.order[0] == IDLE:
			break
	assert_array([held.pos_x[0], held.pos_y[0], held.order[0]]).is_equal([13500, 4500, IDLE])
	assert_int(held.pos_y[0]).is_equal(4500)


## `nav_next` is set at event cadence, in INTEGRATE (ADR 0013 section 1). A counting slot shows it:
## the unit crosses a wall through a gap (20 x 12 map, wall in column 8, rows 0 to 8) and
## `best_neighbour` is asked once on the tick its field completes (`nav_next` -1 and the field
## complete, before the step), once on the tick the step takes it into a new tile (for the new
## tile), and once on its line-check turn ((tick + id) % 5, the refresh for a map that changed under
## it); on every other tick not at all, and `nav_next` keeps its value (FieldCadence holds the
## rule).
## On the asked ticks `nav_next` equals `best_neighbour(cell)` of the tile the unit is in after the
## step. Each kind of event happens in the run. Over the whole run the asks are fewer than the
## ticks followed.
func test_nav_next_is_set_at_event_cadence_only() -> void:
	var rock: Array[Vector2i] = []
	for row: int in 9:
		rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock))
	world.add_unit(1, 0, 3500, 2500)
	world.flow_cells_per_tick = 25
	var order: Command = Command.move(1, PackedInt32Array([1]), 14500, 2500)
	var found: Dictionary = FieldCadence.run(world, order, 400)
	assert_array(found["violations"]).is_empty()
	assert_array([found["entry"] > 5, found["turn"] > 3, found["completion"]]).is_equal(
		[true, true, 1]
	)
	assert_int(found["lookups"]).is_less(found["followed"] / 2)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([14500, 2500, IDLE])


## Arrival clears the whole navigation state, also of a unit that follows a field: a FIELD unit
## with a next tile, a field, a best distance and a stall count, whose goal is within one step,
## is IDLE after the tick with no mode, no field, no next tile, no checked cell and fresh stall
## columns. (Such a unit is rare, since a clear line sends it DIRECT first, so the state is set by
## hand; the unit steers at its next tile, so it does not land on the goal, and arrival is only
## the end of the order.)
func test_arrival_clears_the_navigation_state_and_the_field(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	world.add_unit(1, 0, 3500, 4500)
	world.order[0] = MOVE
	world.goal_x[0] = 3560
	world.goal_y[0] = 4500
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.nav_next[0] = 4 * 20 + 6
	world.nav_cell[0] = world.cell_of(3500, 4500)
	world.best_dist[0] = 700
	world.stall[0] = 6
	Sim.step(world, [])
	assert_array([world.order[0], world.nav_mode[0], world.field[0]]).is_equal([IDLE, 0, -1])
	assert_array([world.nav_next[0], world.nav_cell[0], world.stall[0]]).is_equal([-1, -1, 0])
	assert_int(world.best_dist[0]).is_equal(FlowField.UNREACHED)


## A new order resets `nav_next` to -1 and drops the field, whatever the unit was doing; the next
## order's check makes its own. The tick is chosen so that no unit checks on it ((tick + 1) % 5).
func test_a_new_order_resets_nav_next_and_the_field(impl: int, _test_parameters := _both()) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 9:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, rock)), impl)
	world.add_unit(1, 0, 3500, 2500)
	var tick: int = 0
	while world.nav_next[0] == -1 and tick < 200:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 14500, 2500), 0))
		Sim.step(world, commands)
		tick += 1
	assert_int(world.nav_next[0]).is_greater(-1)
	assert_int(world.field[0]).is_equal(0)
	while (world.tick + 1) % 5 == 0:
		Sim.step(world, [])
	world.best_dist[0] = 700
	world.stall[0] = 6
	var again: Command = _stamped(Command.move(1, PackedInt32Array([1]), 15500, 2500), world.tick)
	Sim.step(world, [again])
	assert_array([world.nav_next[0], world.field[0], world.nav_cell[0]]).is_equal([-1, -1, -1])
	assert_array([world.nav_mode[0], world.best_dist[0], world.stall[0]]).is_equal(
		[DIRECT, FlowField.UNREACHED, 0]
	)


## `set_terrain` while units are on their way: a wall in column 12 of a 30 x 14 map has gaps in rows
## 2 and 3 (near) and 10 and 11 (far). A tank in row 6 follows the field to the near gap; at x 9000
## both near-gap tiles turn to rock, with the budget cut to 10 cells a tick so that the cache
## re-integrates for a long time. Meanwhile the unit keeps its field and its old next tile (the
## field is still complete, serving the old costs), presses against the new rock and never has its
## centre on it. When the new field swaps in, the unit re-routes through the far gap at its next
## line-check turn and arrives.
func test_set_terrain_mid_move_keeps_the_old_field_until_the_new_one_swaps_in(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 14:
		if not row in [2, 3, 10, 11]:
			rock.append(Vector2i(12, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl)
	world.add_unit(1, 0, 3500, 6500)
	var closed: bool = false
	var pressed: bool = false
	var swapped_at: int = -1
	var low_row: int = 0
	var slot: int = -1
	for tick: int in 900:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 22500, 6500), 0))
		Sim.step(world, commands)
		var cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
		(
			assert_bool(world.is_passable(cell, TRACKED))
			. override_failure_message("tick %d" % tick)
			. is_true()
		)
		low_row = maxi(low_row, cell / world.map_cols)
		if not closed and world.pos_x[0] > 9000 and world.nav_next[0] >= 0:
			slot = world.field[0]
			assert_int(world.nav_next[0] / world.map_cols).is_less(6)
			world.flow_cells_per_tick = 10
			world.set_terrain(2 * 30 + 12, ROCK)
			world.set_terrain(3 * 30 + 12, ROCK)
			closed = true
			continue
		if closed and swapped_at == -1:
			var old: FlowField = world.flow.field(slot)
			assert_array([world.nav_mode[0], world.field[0]]).is_equal([FIELD, slot])
			assert_bool(old.complete).is_true()
			pressed = pressed or world.nav_next[0] % world.map_cols == 12
			if old.pending == 0 and world.flow.status[slot] == FlowCache.Status.ACTIVE:
				swapped_at = tick
		if world.order[0] == IDLE:
			break
	assert_bool(closed).is_true()
	assert_bool(pressed).is_true()
	assert_int(swapped_at).is_greater(0)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([22500, 6500, IDLE])
	assert_int(low_row).is_greater(9)


## A group order takes one field per move class, keyed on the group target (ADR 0008 section 3), not
## one per slot: eight tanks and four foot soldiers are ordered over a wall (30 x 14, wall in column
## 12 down to row 11) to a point on the far side. Their twelve slots lie on twelve different tiles,
## `group_cell` is the same cell for all of them (the cell of Formation's centre), and after the
## first line checks the cache holds exactly two fields, both keyed on that cell, one per class.
func test_a_group_order_takes_one_field_per_class_keyed_on_the_group_target(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 12:
		rock.append(Vector2i(12, row))
	var world: World = _in(
		GridWorld.from_rows(GridWorld.grass(30, 14, rock), [TRACKED, FOOT]), impl
	)
	GridWorld.add_block(world, 8, 4, 3000, 1500, 1000, 0)
	GridWorld.add_block(world, 4, 4, 3000, 4500, 1000, 1)
	var given: Array[Command] = [
		_stamped(Command.move(1, PackedInt32Array(range(1, 13)), 22000, 3500), 0)
	]
	var none: Array[Command] = []
	for _tick: int in 6:
		Sim.step(world, given if world.tick == 0 else none)
	var centre: int = world.cell_of(22000, 3500)
	var tiles: Dictionary = {}
	for row: int in 12:
		tiles[world.cell_of(world.goal_x[row], world.goal_y[row])] = true
	assert_int(tiles.size()).is_equal(12)
	assert_array(world.group_cell.slice(0, 12)).is_equal(
		[
			centre,
			centre,
			centre,
			centre,
			centre,
			centre,
			centre,
			centre,
			centre,
			centre,
			centre,
			centre
		]
	)
	assert_int(world.nav_mode.count(FIELD)).is_equal(12)
	var used: Array[int] = []
	for slot: int in world.flow.status.size():
		if world.flow.status[slot] != FlowCache.Status.FREE:
			used.append(world.flow.key_goal[slot] * 10 + world.flow.key_class[slot])
	assert_array(used).is_equal([centre * 10 + TRACKED, centre * 10 + FOOT])


## A group whose slots reach farther than `attack_rekey_milli` from the group target still shares
## one field, MOVE and ATTACK_MOVE alike: the re-key distance is for ATTACK units only (ADR 0008
## section 3), and a group unit's slot is as far from the target as the formation puts it. Sixty
## tanks west of a wall with a gap (30 x 14, column 12, rows 6 and 7 open) are ordered to a point
## east of it; the formation lays their slots on a lattice of 1200 around the centre, so the outer
## ones are more than 4000 from it (every other group test has twelve units or fewer, within
## 3400). After the first ticks every FIELD unit holds the one field, slot 0, keyed on the group
## cell, and the cache holds no other.
@warning_ignore("integer_division")
func test_a_group_wider_than_the_rekey_distance_shares_one_field(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 14:
		if row != 6 and row != 7:
			rock.append(Vector2i(12, row))
	var ids: PackedInt32Array = PackedInt32Array(range(1, 61))
	for attack_move: bool in [false, true]:
		var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl)
		GridWorld.add_block(world, 60, 10, 1500, 1500, 1000, 0)
		var order: Command = Command.move(1, ids, 22500, 6500)
		if attack_move:
			order = Command.attack_move(1, ids, 22500, 6500)
		var given: Array[Command] = [_stamped(order, 0)]
		var none: Array[Command] = []
		for _tick: int in 20:
			Sim.step(world, given if world.tick == 0 else none)
		var label: String = "attack-move %s" % attack_move
		var key: int = world.cell_of(22500, 6500)
		var limit: int = world.attack_rekey_milli
		var far: int = 0
		for row: int in 60:
			var dx: int = world.goal_x[row] - (key % 30 * 1000 + 500)
			var dy: int = world.goal_y[row] - (key / 30 * 1000 + 500)
			if dx * dx + dy * dy > limit * limit:
				far += 1
		assert_int(far).override_failure_message(label).is_greater(0)
		assert_int(world.nav_mode.count(FIELD)).override_failure_message(label).is_greater(20)
		var slots: Dictionary = {}
		for row: int in 60:
			if world.nav_mode[row] == FIELD:
				slots[world.field[row]] = true
		assert_array(slots.keys()).override_failure_message(label).is_equal([0])
		assert_int(world.flow.key_goal[0]).override_failure_message(label).is_equal(key)
		var used: int = world.flow.status.size() - world.flow.status.count(FlowCache.Status.FREE)
		assert_int(used).override_failure_message(label).is_equal(1)


## The group target is the order's: two orders to points 3000 apart take a field each, and a third
## order to the first point shares the first one (the cache is keyed on the cell, whoever asks).
## `group_cell` follows the command: a unit given a new order has the new cell.
func test_orders_to_different_points_take_a_field_each_and_the_same_point_shares(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _gap_world(impl)
	GridWorld.add_block(world, 3, 3, 3000, 1500, 1000, 0)
	GridWorld.add_block(world, 3, 3, 3000, 4500, 1000, 0)
	GridWorld.add_block(world, 3, 3, 3000, 7500, 1000, 0)
	var first: Command = _stamped(Command.move(1, PackedInt32Array([1, 2, 3]), 22000, 3000), 0)
	var second: Command = _stamped(Command.move(1, PackedInt32Array([4, 5, 6]), 22000, 6000), 0)
	second.sequence = 1
	var both: Array[Command] = [first, second]
	var none: Array[Command] = []
	for _tick: int in 8:
		Sim.step(world, both if world.tick == 0 else none)
	assert_int(world.flow.status.count(FlowCache.Status.FREE)).is_equal(6)
	assert_array([world.group_cell[0], world.group_cell[3]]).is_equal(
		[world.cell_of(22000, 3000), world.cell_of(22000, 6000)]
	)
	var third: Array[Command] = [
		_stamped(Command.move(1, PackedInt32Array([7, 8, 9]), 22000, 3000), world.tick)
	]
	for _tick: int in 8:
		Sim.step(world, third if world.tick == third[0].tick else none)
	assert_int(world.flow.status.count(FlowCache.Status.FREE)).is_equal(6)
	assert_int(world.field[6]).is_equal(world.field[0])


## A unit whose slot is behind a wall from the group target takes a field of its own tile: twelve
## tanks are ordered to a point just west of a one tile thick wall (column 20, rows 0 to 9; the way
## round is south of it), so part of the formation lies east of the wall. The group field leads
## every unit to the group target; there the units with a slot across the wall find no next tile
## (NO_NEXT) on a field keyed on another tile, and take the field of their own slot's tile. All
## twelve arrive on their slots, and the cache held more than the group's field at some point.
func test_a_unit_whose_slot_is_across_a_wall_from_the_group_target_takes_a_field_of_its_own(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _thin_wall_world(8, impl, false)
	var slots_used: int = 0
	for tick: int in 700:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(
				_stamped(Command.move(1, PackedInt32Array(range(1, 13)), 19500, 5500), 0)
			)
		Sim.step(world, commands)
		slots_used = maxi(slots_used, world.flow.status.size() - world.flow.status.count(0))
		if world.order.count(IDLE) == 12:
			break
	assert_int(world.order.count(IDLE)).is_equal(12)
	for row: int in 12:
		assert_array([world.pos_x[row], world.pos_y[row]]).is_equal(
			[world.goal_x[row], world.goal_y[row]]
		)
	assert_int(slots_used).is_greater(1)


## ATTACK_MOVE follows the same fields: the thin-wall case with the order ATTACK_MOVE (Formation
## gives it a group target like MOVE). Every tank ends on its own slot, east of the wall or not; the
## goals are read after the first step, since a stalled unit's goal is rewritten to where it stands
## and would hide a tank that stopped short.
func test_attack_move_units_across_a_thin_wall_take_their_own_field(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _thin_wall_world(8, impl, false)
	var goals: Array[Vector2i] = []
	for tick: int in 700:
		var commands: Array[Command] = []
		if tick == 0:
			var ids: PackedInt32Array = PackedInt32Array(range(1, 13))
			commands.append(_stamped(Command.attack_move(1, ids, 19500, 5500), 0))
		Sim.step(world, commands)
		if tick == 0:
			goals = GridWorld.goals(world, PackedInt32Array(range(12)))
		if world.order.count(IDLE) == 12:
			break
	assert_int(world.order.count(IDLE)).is_equal(12)
	var east: int = 0
	for row: int in 12:
		assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([goals[row].x, goals[row].y])
		east += 1 if goals[row].x > 20000 else 0
	assert_int(east).is_greater(0)


## Two runs of the thin-wall case give the same state hash at every checkpoint tick, as MatchLoop
## takes them (every `Replay.CHECKPOINT_PERIOD` ticks): the own-field switch and the stall that
## follow a group field are decided by the World's columns alone. Not vacuous: units took a field of
## their own (more than the group's slot was in use) and the hashes differ from checkpoint to
## checkpoint.
func test_the_thin_wall_run_gives_the_same_hashes_twice(
	impl: int, _test_parameters := _both()
) -> void:
	var first: Dictionary = _thin_wall_hashes(impl)
	var second: Dictionary = _thin_wall_hashes(impl)
	assert_array(second["hashes"]).is_equal(first["hashes"])
	assert_int(first["slots_used"]).is_greater(1)
	assert_int(first["hashes"].size()).is_equal(20)
	var distinct: Dictionary = {}
	for hashed: int in first["hashes"]:
		distinct[hashed] = true
	assert_int(distinct.size()).is_equal(20)


## With every slot referenced a unit cannot take a field of its own tile, and it does not wait for
## one for good: it keeps the group field, finds no next tile, and with no progress for
## `stall_ticks` its order ends where it stands and frees the slot, at any distance from its goal.
## A cache of one slot, the thin wall, two tanks side by side given the same group target west of
## the wall (set by hand, as a command would) and slots 4000 and 5000 east of it, far out of the
## stall range of 2400: both reach the group target, each holds the only slot against the other's
## switch, and both end their orders on the west side, `stall_ticks` after their last gain on the
## goal: they find no next tile on entering the key tile and still gain for the 9 ticks (at most)
## it takes to cross the 1000 from the tile's west edge to the wall.
func test_with_every_slot_referenced_units_across_the_wall_end_their_orders_and_free_the_slot(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(20, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl, false)
	world.flow_cache_size = 1
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 1)
	GridWorld.add_block(world, 2, 2, 3500, 5500, 1000, 0)
	for row: int in 2:
		world.order[row] = MOVE
		world.goal_x[row] = 23500 + row * 1000
		world.goal_y[row] = 5500
	Movement.reset_nav(world, PackedInt32Array([0, 1]), DIRECT)
	world.group_cell.fill(world.cell_of(19500, 5500))
	var pressed_at: Array[int] = [-1, -1]
	var idle_at: Array[int] = [-1, -1]
	for tick: int in 400:
		Sim.step(world, [])
		for row: int in 2:
			if pressed_at[row] == -1 and world.nav_next[row] == Movement.NO_NEXT:
				pressed_at[row] = tick
			if idle_at[row] == -1 and world.order[row] == IDLE:
				idle_at[row] = tick
		if world.order.count(IDLE) == 2:
			break
	assert_int(world.order.count(IDLE)).is_equal(2)
	for row: int in 2:
		assert_int(pressed_at[row]).is_greater(0)
		assert_int(idle_at[row] - pressed_at[row]).is_between(
			world.stall_ticks, world.stall_ticks + 10
		)
	assert_bool(world.pos_x[0] < 20000 and world.pos_x[1] < 20000).is_true()
	assert_array([world.field[0], world.field[1], world.group_cell[0]]).is_equal([-1, -1, -1])
	FlowCache.run(world, 0)
	assert_int(world.flow.refs(0)).is_equal(0)


## A unit whose mode was set to FIELD by hand, with no slot (-1) or with a number that is no slot
## (the first number past the slots, a larger one), is a DIRECT unit that has not checked: it steers
## at its goal, checks on its turn and goes on from there (here the line is clear, so it is DIRECT
## with its cell written). Nothing indexes the cache with the bad number.
func test_a_field_mode_without_a_slot_steers_direct_and_checks_again(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 3, 1, 2500, 1500, 3000, 0)
	var numbers: Array[int] = [-1, world.flow.fields.size(), 99]
	for row: int in 3:
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.goal_x[row] = 12500
		world.goal_y[row] = world.pos_y[row]
		world.nav_cell[row] = 7
		world.field[row] = numbers[row]
	Sim.step(world, [])
	assert_array(world.nav_mode.slice(0, 3)).is_equal([DIRECT, DIRECT, DIRECT])
	assert_array(world.intent_x.slice(0, 3)).is_equal([120, 120, 120])
	assert_array(world.nav_cell.slice(0, 3)).is_equal([-1, -1, -1])
	for _tick: int in 6:
		Sim.step(world, [])
	for row: int in 3:
		assert_int(world.nav_cell[row]).is_not_equal(-1)


## Two runs of the gap scenario give the same hash after every tick, and so does the run with the
## ported phases in C++ (`SimImpls.use` turns on every phase the library has: the FLOW, TARGETING,
## SEPARATION and INTEGRATE kernels do the recount, the scan (nobody to find), the pushes, the
## integration and the look-ups; the units' first acquire() is GDScript's). Not vacuous: the units
## used a field, and the hashes are not all one value.
func test_the_gap_run_gives_the_same_hashes_twice_and_under_both_flow_implementations() -> void:
	var first: PackedInt64Array = _gap_hashes(SimImpls.Impl.GDSCRIPT)
	var second: PackedInt64Array = _gap_hashes(SimImpls.Impl.GDSCRIPT)
	var native: PackedInt64Array = _gap_hashes(SimImpls.Impl.NATIVE)
	assert_int(first.size()).is_equal(300)
	assert_array(second).is_equal(first)
	assert_array(native).is_equal(first)
	var distinct: Dictionary = {}
	for hashed: int in first:
		distinct[hashed] = true
	assert_int(distinct.size()).is_greater(250)


## 300 ticks of the gap scenario with six tanks; leaves nothing behind but the hash of each tick.
func _gap_hashes(impl: int) -> PackedInt64Array:
	var world: World = _gap_world(SimImpls.Impl.GDSCRIPT)
	GridWorld.add_block(world, 6, 3, 3000, 1500, 1000, 0)
	assert_array(SimImpls.use(world, impl)).is_empty()
	var hashes: PackedInt64Array = PackedInt64Array()
	var fields_used: int = 0
	for tick: int in 300:
		var commands: Array[Command] = []
		if tick == 0:
			var ids: PackedInt32Array = PackedInt32Array(range(1, 7))
			commands.append(_stamped(Command.move(1, ids, 22000, 3000), 0))
		Sim.step(world, commands)
		fields_used += world.nav_mode.count(FIELD)
		hashes.append(world.state_hash())
	assert_int(fields_used).is_greater(100)
	return hashes


func _gap_world(impl: int, pushes: bool = true) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 14:
		if row != 9 and row != 10:
			rock.append(Vector2i(12, row))
	return _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl, pushes)


## 300 ticks of the thin-wall case (twelve tanks, eight slots) with the hash at each checkpoint:
## "hashes" and "slots_used" (the most slots in use at once).
func _thin_wall_hashes(impl: int) -> Dictionary:
	var world: World = _thin_wall_world(8, impl)
	var hashes: PackedInt64Array = PackedInt64Array()
	var slots_used: int = 0
	for tick: int in 300:
		var commands: Array[Command] = []
		if tick == 0:
			var ids: PackedInt32Array = PackedInt32Array(range(1, 13))
			commands.append(_stamped(Command.move(1, ids, 19500, 5500), 0))
		Sim.step(world, commands)
		slots_used = maxi(slots_used, world.flow.status.size() - world.flow.status.count(0))
		if (tick + 1) % Replay.CHECKPOINT_PERIOD == 0:
			hashes.append(world.state_hash())
	return {"hashes": hashes, "slots_used": slots_used}


## 30 x 14, a one tile thick wall in column 20 (rows 0 to 9), twelve tanks west of it, a cache of
## `slots` fields.
func _thin_wall_world(slots: int, impl: int, pushes: bool = true) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(20, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl, pushes)
	world.flow_cache_size = slots
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), slots)
	GridWorld.add_block(world, 12, 4, 3000, 1500, 1000, 0)
	return world


## A wall in column 8, rows 0 to `rows` - 1.
func _wall(rows: int) -> Array[Vector2i]:
	var rock: Array[Vector2i] = []
	for row: int in rows:
		rock.append(Vector2i(8, row))
	return rock


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for, with
## the tick's separation as the rules have it. A case that pins the exact positions where a crowd
## settles (the pushes of the tick move the units a little: test_separation_tick.gd covers the crowd
## with the real pushes) asks for `pushes` false, which sets `separation_push_max` to 0.
func _in(world: World, impl: int, pushes: bool = true) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	if not pushes:
		world.separation_push_max = 0
	return world
