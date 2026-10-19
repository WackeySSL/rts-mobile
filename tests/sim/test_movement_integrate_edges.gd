extends GdUnitTestSuite
## Edges of what `Movement.run` and `Movement.integrate` read from a FIELD unit (P37b; ADR 0008
## section 2, ADR 0013 section 1), each one a place where the wrong index or bound gives the same
## result on a square map, a one-slot cache or a single unit:
## - the unit's own tile on a map that is wider or taller than it is square (the column bound is
##   `cols - 1`, the row bound `last_row`, the clamp of the position `max_x` and `max_y`);
## - the unit's own slot, not slot 0, decides whether the field is complete (the lookup at a tile
##   entry and the lookup on a turn), when slot 0 is pending and the unit's slot is not;
## - a line-check period of 0 does not divide; a hand-set order with mode NONE is a DIRECT unit
##   that has not started; the x move alone keeps the unit's own y; a unit that finds every slot
##   referenced checks its line once on its turn.
## Maps are built in code (GridWorld).
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.
## The cases that count the twin's `best_neighbour` calls stay on the twin.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FieldCadence: GDScript = preload("res://tests/sim/support/field_cadence.gd")
const MOVE: int = World.Order.MOVE
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD


## 30 x 10 map (wide): wall in column 22, rows 0 to 6, a gap in rows 7 to 9. The tank starts at
## x 11500, east of the map's height (10000), so its tile column exceeds rows - 1 while it follows
## the field to the gap: a cell taken with the row bound for the column would put it in the wrong
## tile, and the lookups would not be at its tile entries.
func test_a_field_unit_east_of_the_map_height_on_a_wide_map_is_in_its_own_tile() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(30, 10, _wall(22, 7, true)))
	world.add_unit(1, 0, 11500, 2500)
	world.flow_cells_per_tick = 25
	var order: Command = Command.move(1, PackedInt32Array([1]), 28500, 2500)
	var found: Dictionary = FieldCadence.run(world, order, 600)
	assert_array(found["violations"]).is_empty()
	assert_int(found["followed"]).is_greater(10)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([28500, 2500, IDLE])


## 10 x 30 map (tall): wall in row 22, columns 0 to 6, a gap in columns 7 to 9. The tank starts at
## y 11500, south of the map's width (10000).
func test_a_field_unit_south_of_the_map_width_on_a_tall_map_is_in_its_own_tile() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(10, 30, _wall(22, 7, false)))
	world.add_unit(1, 0, 2500, 11500)
	world.flow_cells_per_tick = 25
	var order: Command = Command.move(1, PackedInt32Array([1]), 2500, 28500)
	var found: Dictionary = FieldCadence.run(world, order, 600)
	assert_array(found["violations"]).is_empty()
	assert_int(found["followed"]).is_greater(10)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([2500, 28500, IDLE])


## A FIELD unit checks its line when it enters a tile, not every tick: over the run the checks are
## far fewer than the ticks followed (a wrong cell for the unit would re-check on every tick).
func test_a_field_unit_far_from_the_map_origin_checks_on_tile_entries_only(
	impl: int, _test_parameters := _both()
) -> void:
	for wide: bool in [true, false]:
		var world: World = _in(
			GridWorld.from_rows(
				GridWorld.grass(30 if wide else 10, 10 if wide else 30, _wall(22, 7, wide))
			),
			impl
		)
		world.add_unit(1, 0, 11500 if wide else 2500, 2500 if wide else 11500)
		var order: Command = Command.move(
			1, PackedInt32Array([1]), 28500 if wide else 2500, 2500 if wide else 28500
		)
		var checks: int = 0
		var followed: int = 0
		for tick: int in 600:
			var commands: Array[Command] = []
			if tick == 0:
				order.tick = 0
				commands.append(order)
			Sim.step(world, commands)
			checks += world.stats[World.Stat.LINE_CHECKS]
			followed += 1 if world.nav_mode[0] == FIELD else 0
			if world.order[0] == IDLE:
				break
		assert_int(followed).is_greater(40)
		(
			assert_int(checks * 4)
			. override_failure_message("wide %s: %d checks in %d ticks" % [wide, checks, followed])
			. is_less(followed)
		)


## `integrate` reads the completion of the unit's own slot. 30 x 14 map, wall in column 12 (rows 0
## to 10, a gap in rows 11 to 13), a cache of 2 slots. Unit 2 takes slot 0 and unit 1 slot 1 (goals
## 5000 apart). At tick 40 unit 2 is stopped and unit 3 asks for a new key: it recycles slot 0,
## which at 5 cells a tick is pending for about 80 ticks while unit 1 (slot 1, complete) keeps
## entering tiles. Unit 4, ordered at tick 50 to the point unit 1 was ordered to (the same group
## target, so the same key), shares slot 1 and must get its next tile when it joins, though slot 0
## is pending. Every tile unit 1 enters has the lookup of slot 1 in `nav_next`.
func test_a_unit_follows_its_own_slot_while_another_slot_is_pending(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, _wall(12, 11, true))), impl)
	world.flow_cache_size = 2
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 2)
	world.add_unit(1, 0, 3500, 1500)
	world.add_unit(1, 0, 3500, 5500)
	world.add_unit(1, 0, 3500, 3500)
	world.add_unit(1, 0, 3500, 6500)
	var last_cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
	var entries: int = 0
	var pending_ticks: int = 0
	var joined: bool = false
	for tick: int in 130:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 20500, 1500), tick))
			commands.append(_stamped(Command.move(1, PackedInt32Array([2]), 20500, 6500), tick))
		if tick == 39:
			world.flow_cells_per_tick = 5
		if tick == 40:
			commands.append(_stamped(Command.stop(1, PackedInt32Array([2])), tick))
			commands.append(_stamped(Command.move(1, PackedInt32Array([3]), 20500, 12500), tick))
		if tick == 50:
			commands.append(_stamped(Command.move(1, PackedInt32Array([4]), 20500, 1500), tick))
		Sim.step(world, commands)
		var cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
		var slot0_pending: bool = not world.flow.field(0).complete
		pending_ticks += 1 if slot0_pending and tick > 41 else 0
		if (
			slot0_pending
			and world.nav_mode[0] == FIELD
			and world.field[0] == 1
			and world.flow.field(1).complete
			and cell != last_cell
		):
			entries += 1
			var named: int = world.flow.field(1).best_neighbour(cell)
			var expected: int = named if named >= 0 else Movement.NO_NEXT
			(
				assert_int(world.nav_next[0])
				. override_failure_message("tick %d: entered cell %d" % [tick, cell])
				. is_equal(expected)
			)
		last_cell = cell
		if tick >= 51 and not joined and world.field[3] == 1:
			joined = true
			(
				assert_bool(slot0_pending)
				. override_failure_message("slot 0 should still be pending")
				. is_true()
			)
			(
				assert_int(world.nav_next[3])
				. override_failure_message("tick %d: unit 4 joined slot 1" % tick)
				. is_not_equal(-1)
			)
	assert_int(pending_ticks).is_greater(40)
	assert_int(entries).is_greater(5)
	assert_bool(joined).is_true()


## A unit that finds every slot referenced checks its line once on its turn, not twice. A cache of
## 1 slot (20 x 12 map, wall in column 8, rows 0 to 10); unit 2 (turn on tick 3) takes it, unit 1's
## first check (tick 4) finds none: one more line check, the unit stays DIRECT and unchecked.
func test_a_starved_unit_checks_its_line_once_per_turn(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, _wall(8, 11, true))), impl)
	world.flow_cache_size = 1
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 1)
	world.add_unit(1, 0, 3500, 2500)
	world.add_unit(1, 0, 3500, 8500)
	var goals: Array[Vector2i] = [Vector2i(14500, 2500), Vector2i(14500, 8500)]
	for row: int in 2:
		world.order[row] = MOVE
		world.goal_x[row] = goals[row].x
		world.goal_y[row] = goals[row].y
	Movement.reset_nav(world, PackedInt32Array([0, 1]), DIRECT)
	world.tick = 3
	Movement.run(world)
	assert_array([world.nav_mode[1], world.field[1], world.nav_mode[0]]).is_equal(
		[FIELD, 0, DIRECT]
	)
	var before: int = world.stats[World.Stat.LINE_CHECKS]
	world.tick = 4
	Movement.run(world)
	assert_int(world.stats[World.Stat.LINE_CHECKS] - before).is_equal(1)
	assert_array([world.nav_mode[0], world.field[0], world.nav_cell[0]]).is_equal([DIRECT, -1, -1])


## A hand-set order (mode NONE) is a DIRECT unit that has not started: its first check waits for
## its turn like any other, and the unit is DIRECT, not FIELD, until then.
func test_a_hand_set_order_waits_for_its_turn_to_check(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, _wall(8, 11, true))), impl)
	world.add_unit(1, 0, 3500, 2500)
	world.order[0] = MOVE
	world.goal_x[0] = 14500
	world.goal_y[0] = 2500
	world.tick = 0
	Movement.run(world)
	assert_int(world.stats[World.Stat.LINE_CHECKS]).is_equal(0)
	assert_array([world.nav_mode[0], world.field[0], world.nav_cell[0]]).is_equal([DIRECT, -1, -1])


## `integrate` on a World whose line-check period is 0 does not divide by it (the guard is the
## same as `run`'s): a FIELD unit with a lookup due takes its step.
func test_integrate_guards_a_line_check_period_of_zero(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	world.flow_cache_size = 2
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 2)
	assert_int(world.flow.acquire(0, World.MoveClass.TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, 100000)
	world.line_check_period_ticks = 0
	world.add_unit(1, 0, 2950, 4500)
	world.order[0] = MOVE
	world.goal_x[0] = 15500
	world.goal_y[0] = 4500
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.nav_next[0] = 4 * 20 + 3
	world.nav_cell[0] = world.cell_of(2950, 4500)
	world.intent_x[0] = 100
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([3050, 4500])


## When the diagonal step ends on rock, the x move alone keeps the unit's own y. Rock at (5, 4), a
## unit at (4900, 3900) steps (+100, +100) to (5000, 4000), which is rock; the x move alone ends in
## tile (5, 3), which is open, and y stays 3900 (not 4000).
func test_the_x_only_slide_keeps_the_units_own_y(impl: int, _test_parameters := _both()) -> void:
	var rock: Array[Vector2i] = [Vector2i(5, 4)]
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(12, 8, rock)), impl)
	world.add_unit(1, 0, 4900, 3900)
	world.intent_x[0] = 100
	world.intent_y[0] = 100
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([5000, 3900])


## A map of one tile is a map: the position is clamped to it (999 at most on either axis), where a
## World with no map has no upper bound.
func test_a_map_of_one_tile_clamps_the_position(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(1, 1)), impl)
	world.add_unit(1, 0, 500, 500)
	world.intent_x[0] = 700
	world.intent_y[0] = 900
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([999, 999])


## A tile that is rock blocks a map of one tile too: the unit stays where it is.
func test_a_map_of_one_rock_tile_stops_a_unit_with_a_step(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(1, 1, [Vector2i(0, 0)])), impl)
	world.add_unit(1, 0, 500, 500)
	world.intent_x[0] = 100
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([500, 500])


## A FIELD unit on a map of one tile has its lookup: the field of the only tile names no next tile,
## so `nav_next` goes from -1 to NO_NEXT (the unit's goal is in the same tile, 400 away).
func test_a_field_unit_on_a_map_of_one_tile_has_its_lookup(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(1, 1)), impl)
	world.add_unit(1, 0, 500, 500)
	world.order[0] = MOVE
	world.goal_x[0] = 900
	world.goal_y[0] = 500
	Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
	world.nav_mode[0] = FIELD
	world.field[0] = world.flow.acquire(0, World.MoveClass.TRACKED, world.map_version, 0)
	FlowCache.run(world, 100000)
	assert_bool(world.flow.field(0).complete).is_true()
	Movement.integrate(world)
	assert_int(world.nav_next[0]).is_equal(Movement.NO_NEXT)


## A unit of speed 1 stalls like any other (only speed 0 does not): in range of its goal (2000 away,
## range 2400), a checked DIRECT line, no progress for `stall_ticks` (3) ends the order.
func test_a_unit_of_speed_one_stalls(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	world.type_speed[0] = 1
	world.add_unit(1, 0, 5000, 2000)
	world.order[0] = MOVE
	world.goal_x[0] = 7000
	world.goal_y[0] = 2000
	world.nav_mode[0] = DIRECT
	world.nav_cell[0] = world.cell_of(5000, 2000)
	world.stall_ticks = 3
	for _call: int in 4:
		Movement.integrate(world)
	assert_array([world.order[0], world.nav_mode[0]]).is_equal([IDLE, World.NavMode.NONE])


## A unit that does not move is left alone, also when it stands on rock (a changed map): `integrate`
## tests the destination only for a unit with a step, and a DIRECT unit that the rock stops dead has
## its line checked again, so one with no step at all keeps the cell of its last check. Rock under
## the unit at (4500, 3500), a DIRECT order with a checked line and no intent or push.
func test_a_unit_with_no_step_on_rock_keeps_its_checked_line(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(12, 8)), impl)
	world.add_unit(1, 0, 4500, 3500)
	world.order[0] = MOVE
	world.goal_x[0] = 10500
	world.goal_y[0] = 3500
	Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
	world.nav_cell[0] = world.cell_of(4500, 3500)
	world.set_terrain(world.cell_of(4500, 3500), 2)
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0], world.nav_cell[0]]).is_equal(
		[4500, 3500, world.cell_of(4500, 3500)]
	)


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command


## A wall `length` tiles long at index `at`: in column `at` from row 0 when `vertical`, else in row
## `at` from column 0.
func _wall(at: int, length: int, vertical: bool) -> Array[Vector2i]:
	var rock: Array[Vector2i] = []
	for k: int in length:
		rock.append(Vector2i(at, k) if vertical else Vector2i(k, at))
	return rock


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	return world
