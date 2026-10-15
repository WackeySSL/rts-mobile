extends GdUnitTestSuite
## Units that cannot reach their goals must not starve the others of a field (P37b; ADR 0008
## sections 2, 3 and 5). A group sent into a pocket of rock that nothing can enter holds a field of
## the cache for as long as it holds its order; its field names no next tile (NO_NEXT) from the
## first lookup on, so the units steer at the goal and press on the first wall. They stall there at
## any distance (the lead's decision of 2026-10-15) and their slots go back to the cache. Without
## that the pockets hold every slot for good and the units behind them never get a field.
## The map: a wall in column 12 with a gap in rows 9 and 10, west of it the tanks, east of it the
## goals, and further east the pockets (eight rock tiles around one open tile each). Maps are built
## in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
## The tick the tanks behind the pockets are ordered on: every pocket group has its slot by then.
const REACHABLE_TICK: int = 6
const REACHABLE: int = 6


## A cache of two slots and two pockets, one tank for each: the pockets hold both slots. Six tanks
## ordered one by one (so six keys) at tick 6 find every slot referenced and wait. The pocket tanks
## end their orders where they stop gaining on their goals, and all six others arrive on theirs.
func test_two_pocket_tanks_do_not_starve_six_others_of_two_slots() -> void:
	var played: Dictionary = _play(2, 2, 1)
	assert_int(played["waiting"]).is_greater(0)
	assert_int(played["last_idle"]).is_between(REACHABLE_TICK, 899)
	_assert_outcome(played["world"], 2, 1)


## A cache of eight slots and eight pocket groups of two tanks each: every group holds a slot (its
## tanks share the pocket's field), the cache is full, and the six tanks ordered at tick 6 wait for
## a slot. They get one as the pocket tanks stall and free theirs, and all arrive.
func test_eight_pocket_groups_do_not_starve_six_others_of_eight_slots() -> void:
	var played: Dictionary = _play(8, 8, 2)
	assert_int(played["waiting"]).is_greater(0)
	assert_int(played["last_idle"]).is_between(REACHABLE_TICK, 899)
	_assert_outcome(played["world"], 8, 2)


## Runs the scenario for 900 ticks. Returns "world", "waiting" (the most tanks behind the pockets
## that wait for a slot on a tick on which the cache has no free slot) and "last_idle" (the first
## tick on which every unit is IDLE, -1 if none).
func _play(slots: int, pockets: int, per_pocket: int) -> Dictionary:
	var world: World = _pocket_world(slots, pockets)
	var pocket_count: int = pockets * per_pocket
	GridWorld.add_block(world, pocket_count, 1, 3500, 500, 1000, 0)
	GridWorld.add_block(world, REACHABLE, 1, 5500, 500, 1000, 0)
	var waiting: int = 0
	var last_idle: int = -1
	var sequence: int = 0
	for tick: int in 900:
		var commands: Array[Command] = []
		if tick == 0:
			for pocket: int in pockets:
				var ids: PackedInt32Array = PackedInt32Array()
				for k: int in per_pocket:
					ids.append(pocket * per_pocket + k + 1)
				var order: Command = Command.move(1, ids, _pocket_x(pocket), _pocket_y(pocket))
				order.tick = tick
				order.sequence = sequence
				sequence += 1
				commands.append(order)
		if tick == REACHABLE_TICK:
			for k: int in REACHABLE:
				var order: Command = Command.move(
					1, PackedInt32Array([pocket_count + k + 1]), 20500, 2500 + k * 1000
				)
				order.tick = tick
				order.sequence = sequence
				sequence += 1
				commands.append(order)
		Sim.step(world, commands)
		if world.flow.status.count(FlowCache.Status.FREE) == 0:
			var here: int = 0
			for row: int in range(pocket_count, pocket_count + REACHABLE):
				if (
					world.order[row] != IDLE
					and world.nav_mode[row] == DIRECT
					and world.nav_cell[row] == -1
				):
					here += 1
			waiting = maxi(waiting, here)
		if last_idle == -1 and world.order.count(IDLE) == world.unit_count():
			last_idle = tick
	return {"world": world, "waiting": waiting, "last_idle": last_idle}


## The pocket tanks are IDLE, none inside a pocket, with no field and no group cell; the others
## stand on their goals; no slot is referenced.
func _assert_outcome(world: World, pockets: int, per_pocket: int) -> void:
	var pocket_count: int = pockets * per_pocket
	for row: int in pocket_count:
		assert_array([world.order[row], world.field[row], world.group_cell[row]]).is_equal(
			[IDLE, -1, -1]
		)
		for pocket: int in pockets:
			var inside: int = world.cell_of(_pocket_x(pocket), _pocket_y(pocket))
			assert_int(world.cell_of(world.pos_x[row], world.pos_y[row])).is_not_equal(inside)
	for row: int in range(pocket_count, pocket_count + REACHABLE):
		assert_array([world.pos_x[row], world.pos_y[row], world.order[row]]).is_equal(
			[world.goal_x[row], world.goal_y[row], IDLE]
		)
	assert_int(world.field.count(-1)).is_equal(world.unit_count())
	FlowCache.run(world, 0)
	for slot: int in world.flow.status.size():
		assert_int(world.flow.refs(slot)).is_equal(0)


## 32 x 17 tiles: a wall in column 12 except rows 9 and 10, and `pockets` pockets in two columns of
## them, the interior tiles at (x, y) of `_pocket_x` and `_pocket_y`. A cache of `slots` fields.
@warning_ignore("integer_division")
func _pocket_world(slots: int, pockets: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 17:
		if row != 9 and row != 10:
			rock.append(Vector2i(12, row))
	for pocket: int in pockets:
		var left: int = 24 + (pocket % 2) * 4
		var top: int = 1 + (pocket / 2) * 4
		for dx: int in 3:
			rock.append(Vector2i(left + dx, top))
			rock.append(Vector2i(left + dx, top + 2))
		rock.append(Vector2i(left, top + 1))
		rock.append(Vector2i(left + 2, top + 1))
	var world: World = GridWorld.from_rows(GridWorld.grass(32, 17, rock))
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), slots)
	return world


## The centre of the open tile of pocket `pocket`.
func _pocket_x(pocket: int) -> int:
	return (25 + (pocket % 2) * 4) * 1000 + 500


@warning_ignore("integer_division")
func _pocket_y(pocket: int) -> int:
	return (2 + (pocket / 2) * 4) * 1000 + 500
