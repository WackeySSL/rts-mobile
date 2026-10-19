extends GdUnitTestSuite
## The tile a field is keyed on turns to rock while units follow it (P37b fix 5; ADR 0008 sections 2
## and 3). `FlowField.begin` seeds the key at cost 0 whatever its terrain, so on a field keyed on a
## tile that is rock now `best_neighbour` still names the key from every tile next to it. Without
## a rule the unit presses on the rock for good: it never finds "no next tile", so it neither
## takes the field of its own goal nor stalls, and it holds its slot as long as it has its order.
## `Movement._refresh_next` reads a next tile that is the field's key and blocked for the unit's
## class as none (NO_NEXT): a unit whose goal lies elsewhere takes the field of its own goal's tile,
## and a unit whose goal is the key stalls (at any distance) and frees its slot. The hand-set cases
## of that rule are in test_movement_own_field.gd; here the units are ordered by commands and the
## key tile is closed with `set_terrain` while they are on their way. Maps are built in code
## (GridWorld).
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TRACKED: int = World.MoveClass.TRACKED
const IDLE: int = World.Order.IDLE
const FIELD: int = World.NavMode.FIELD
## The terrain index of rock in GridWorld's GROUND string.
const ROCK: int = 2
## The ticks a run may take; every case ends well before.
const BOUND: int = 1500


## Twelve tanks cross a wall (30 x 14, column 12, a gap in rows 6 and 7) to a group target in
## column 22, and that tile turns to rock on tick 10, 20 or 30, while every tank is still FIELD
## west of the wall (a DIRECT unit never checks its line again, so one whose line was clear when
## the tile closed would slide along the rock and stall there). Every unit ends: the eleven whose
## own slot lies on another tile arrive on it (they take the field of their own goal tile), the
## one whose goal is the rock tile stalls short of it. No slot is referenced at the end.
func test_twelve_tanks_end_their_orders_when_the_group_target_tile_turns_to_rock(
	impl: int, _test_parameters := _both()
) -> void:
	for close_at: int in [10, 20, 30]:
		var world: World = _gap_world(impl)
		GridWorld.add_block(world, 12, 4, 3000, 1500, 1000, 0)
		var goals: Array[Vector2i] = _close_and_run(world, 12, 22500, 6500, close_at)
		var label: String = "closed at tick %d" % close_at
		assert_int(world.order.count(IDLE)).override_failure_message(label).is_equal(12)
		var arrived: int = _assert_settled(world, goals, world.cell_of(22500, 6500))
		assert_int(arrived).override_failure_message(label).is_equal(11)


## One tank, a wall across the map except its last row (20 x 10, column 8, rows 0 to 8), the order
## to a point behind the wall whose tile turns to rock on tick 40. The tank's goal is the rock tile:
## it goes round the wall's end, presses on the rock from the south and stalls there, IDLE with no
## field and its slot back in the cache, on open ground.
func test_a_lone_tank_stalls_next_to_its_rock_goal_and_frees_its_slot(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _wall_world(1, impl)
	var goals: Array[Vector2i] = _close_and_run(world, 1, 12500, 2500, 40)
	assert_int(world.order[0]).is_equal(IDLE)
	assert_int(_assert_settled(world, goals, world.cell_of(12500, 2500))).is_equal(0)
	assert_bool(world.is_passable(world.cell_of(world.pos_x[0], world.pos_y[0]), TRACKED)).is_true()
	assert_int(world.pos_x[0]).is_greater(8000)


## Three tanks in the same case: their slots differ, so the ones whose goal tile is open take the
## field of that tile and arrive, and the one whose goal is the rock tile (if the formation gives
## one) stalls. Every unit ends, no slot is referenced.
func test_three_tanks_with_open_slots_arrive_when_the_group_tile_turns_to_rock(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _wall_world(3, impl)
	var goals: Array[Vector2i] = _close_and_run(world, 3, 12500, 2500, 40)
	assert_int(world.order.count(IDLE)).is_equal(3)
	assert_int(_assert_settled(world, goals, world.cell_of(12500, 2500))).is_greater(0)


## An ATTACK unit follows the rule too (its order has no group cell). Two walls (columns 10 and 20
## of a 30 x 14 map, rows 0 to 9, so the way round each is south), a tank at (3500, 5500) and an
## enemy at (19500, 5500): the tank's field is keyed on the enemy's tile. On tick 20 that tile turns
## to rock and the enemy moves to (21500, 5500), behind the second wall and 2000 from the key (no
## re-key). The tank reaches the rock, finds no next tile, takes the field of the enemy's new tile
## and goes round the wall: it ends east of it. Without the rule it presses on the rock at x 18933
## for good, FIELD on the field of the rock key.
func test_an_attack_unit_whose_key_tile_turned_to_rock_still_reaches_a_target_behind_a_second_wall(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(10, row))
		rock.append(Vector2i(20, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl)
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 3500, 5500)
	world.add_unit(2, 0, 19500, 5500)
	var key: int = world.cell_of(19500, 5500)
	for tick: int in 900:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.attack(1, PackedInt32Array([1]), 2), 0))
		if tick == 20:
			assert_int(world.flow.key_goal[world.field[0]]).is_equal(key)
			world.set_terrain(key, ROCK)
			world.pos_x[1] = 21500
		Sim.step(world, commands)
	assert_int(world.pos_x[0]).is_greater(21000)
	assert_int(world.order[0]).is_equal(World.Order.ATTACK)


## Orders units 1 to `count` (already placed) to (x, y) on tick 0 and turns the tile of that point
## into rock on tick `close_at`, when every unit follows the field and has its group target. Runs
## until every unit is IDLE or `BOUND` ticks. Returns the goals the formation gave, read after the
## first step (a stalled unit's goal is rewritten to where it stands).
func _close_and_run(world: World, count: int, x: int, y: int, close_at: int) -> Array[Vector2i]:
	var key: int = world.cell_of(x, y)
	var goals: Array[Vector2i] = []
	for tick: int in BOUND:
		var commands: Array[Command] = []
		if tick == 0:
			var ids: PackedInt32Array = PackedInt32Array(range(1, count + 1))
			commands.append(_stamped(Command.move(1, ids, x, y), 0))
		if tick == close_at:
			assert_int(world.nav_mode.count(FIELD)).is_equal(count)
			assert_int(world.group_cell[0]).is_equal(key)
			world.set_terrain(key, ROCK)
		Sim.step(world, commands)
		if tick == 0:
			goals = GridWorld.goals(world, PackedInt32Array(range(count)))
		if world.order.count(IDLE) == world.unit_count():
			break
	return goals


## Checks every unit: IDLE with no field and no group cell; a unit whose goal tile is `key` (the
## rock) is not standing on rock, any other unit stands on its goal. No slot is referenced at the
## end. Returns the number of units that stand on their goals.
func _assert_settled(world: World, goals: Array[Vector2i], key: int) -> int:
	var arrived: int = 0
	for row: int in goals.size():
		var label: String = "row %d goal %s" % [row, goals[row]]
		(
			assert_array([world.order[row], world.field[row], world.group_cell[row]])
			. override_failure_message(label)
			. is_equal([IDLE, -1, -1])
		)
		var here: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row])
		if world.cell_of(goals[row].x, goals[row].y) == key:
			assert_int(world.cell_of(here.x, here.y)).override_failure_message(label).is_not_equal(
				key
			)
		else:
			assert_object(here).override_failure_message(label).is_equal(goals[row])
			arrived += 1
	FlowCache.run(world, 0)
	for slot: int in world.flow.status.size():
		assert_int(world.flow.refs(slot)).is_equal(0)
	return arrived


## 30 x 14 with a wall in column 12 and a gap of two tiles in rows 6 and 7.
func _gap_world(impl: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 14:
		if row != 6 and row != 7:
			rock.append(Vector2i(12, row))
	return _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl)


## 20 x 10 with a wall in column 8, rows 0 to 8, and `count` tanks stacked in column 3.
func _wall_world(count: int, impl: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 9:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	for k: int in count:
		world.add_unit(1, 0, 3500, 1500 + k * 1200)
	return world


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	return world
