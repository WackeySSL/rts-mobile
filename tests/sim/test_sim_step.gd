extends GdUnitTestSuite
## Sim.step (ADR 0003 sections 3 to 5). Hand-built worlds use literal stats (type 0: speed 120,
## type 1: speed 0, type 2: speed 60), so no data file can agree with a wrong rule. A push_error
## would fail verify, which scans the log.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const MAP: int = 48000


func test_constants_match_the_contract_and_world() -> void:
	assert_int(Sim.TICK_RATE).is_equal(15)
	assert_int(Sim.MILLI_PER_TILE).is_equal(1000)
	assert_int(Sim.MILLI_PER_TILE).is_equal(World.MILLI_PER_TILE)


## Offsets from the start after every tick, as x, y pairs. The last pair is the snap.
func test_a_unit_moves_exactly_its_speed_per_tick_on_axes_and_diagonals() -> void:
	assert_array(_walk(500, 0, 5)).is_equal([120, 0, 240, 0, 360, 0, 480, 0, 500, 0])
	assert_array(_walk(-500, 0, 5)).is_equal([-120, 0, -240, 0, -360, 0, -480, 0, -500, 0])
	assert_array(_walk(0, -400, 4)).is_equal([0, -120, 0, -240, 0, -360, 0, -400])
	# A 3-4-5 diagonal moves (72, 96) per tick.
	assert_array(_walk(300, 400, 5)).is_equal([72, 96, 144, 192, 216, 288, 288, 384, 300, 400])
	# (-300, 100) is 316 long: -113.9 and 37.97 truncate toward zero, not to -114 or 38.
	assert_array(_walk(-300, 100, 1)).is_equal([-113, 37])
	# Type 2 has speed 60, so the speed comes from the unit's own type.
	assert_array(_walk(500, 0, 2, 2)).is_equal([60, 0, 120, 0])


## A goal exactly one step away is reached in one tick. One milli further takes a second tick, and
## so does (1, 120): d2 = 14401 is over 120 squared, although its rounded-down distance is 120.
func test_a_goal_one_step_away_snaps_and_goes_idle() -> void:
	for far: Vector2i in [Vector2i(120, 0), Vector2i(121, 0), Vector2i(1, 120)]:
		var world: World = _make_world()
		world.add_unit(1, 0, 10000, 10000)
		var arrived: bool = far == Vector2i(120, 0)
		Sim.step(world, [_move(1, [1], 0, 10000 + far.x, 10000 + far.y)])
		assert_int(world.order[0]).is_equal(0 if arrived else World.Order.ATTACK_MOVE)
		assert_int(world.pos_x[0]).is_equal(10000 + mini(far.x, 120))
		Sim.step(world, [])
		assert_int(world.order[0]).is_equal(World.Order.IDLE)
		assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([10000 + far.x, 10000 + far.y])


func test_thirty_tanks_reach_distinct_slots_and_enemies_never_move() -> void:
	var world: World = _scenario_world()
	var enemies: PackedInt32Array = world.pos_x.slice(30) + world.pos_y.slice(30)
	Sim.step(world, [_move(1, range(1, 31), 0, 22250, 22250)])
	for _t: int in 9:
		Sim.step(world, [])
	assert_int(world.order.count(World.Order.ATTACK_MOVE)).is_equal(30)
	for _t: int in 140:
		Sim.step(world, [])
	assert_int(world.tick).is_equal(150)
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	var slots: Dictionary[Vector2i, bool] = {}
	for row: int in 30:
		slots[Vector2i(world.pos_x[row], world.pos_y[row])] = true
	assert_int(slots.size()).is_equal(30)
	assert_array(world.pos_x.slice(30) + world.pos_y.slice(30)).is_equal(enemies)


## The world is at tick 7. Each bad command is dropped, counted once, and moves nothing.
func test_invalid_commands_are_dropped_and_counted() -> void:
	var cases: Dictionary[String, Command] = {
		"future tick": _move(1, [1, 2], 8),
		"past tick": _move(1, [1, 2], 6),
		"unstamped": _move(1, [1, 2], -1),
		"unknown type": _move(1, [1, 2], 7, 20000, 20000, 0, 99),
		"type none": _move(1, [1, 2], 7, 20000, 20000, 0, Command.Type.NONE),
		"only enemy ids": _move(1, [31, 32], 7),
		"other player's ids": _move(2, [1, 2], 7),
		# Player 2 owns the last row, so an unguarded row -1 would pass the owner check.
		"unknown ids": _move(2, [0, -3, 41, 999], 7),
		"no ids": _move(1, [], 7),
		"null": null,
	}
	for label: String in cases:
		var world: World = _scenario_world()
		world.tick = 7
		Sim.step(world, [cases[label]])
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
		assert_int(world.order.count(World.Order.IDLE)).override_failure_message(label).is_equal(40)
		assert_int(world.tick).is_equal(8)


## Unknown, foreign and immobile ids are skipped silently. The command is dropped only when
## no valid unit is left.
func test_ids_that_cannot_be_ordered_are_skipped_without_dropping_the_command() -> void:
	var world: World = _make_world()
	for k: int in 4:
		world.add_unit(2 if k == 2 else 1, 1 if k == 1 else 0, 10000 + k * 2000, 10000)
	Sim.step(world, [_move(1, [3, 2, 999, 4, 1, 4], 0)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(world.order).is_equal([1, 0, 0, 1])
	assert_array(world.goal_x.slice(1, 3)).is_equal([12000, 14000])
	Sim.step(world, [_move(1, [2], 1)])
	assert_int(world.dropped_commands).is_equal(1)


func test_a_duplicate_id_is_used_once() -> void:
	var once: World = _scenario_world()
	var many: World = _scenario_world()
	Sim.step(once, [_move(1, [1, 2, 3], 0)])
	Sim.step(many, [_move(1, [3, 1, 1, 2, 3, 1], 0)])
	assert_array(many.goal_x).is_equal(once.goal_x)
	assert_array(many.goal_y).is_equal(once.goal_y)


## Drops add up and do not stop later commands: stale, valid, wrong player, future, and a null.
func test_a_dropped_command_does_not_block_the_next_ones() -> void:
	var world: World = _scenario_world()
	world.tick = 7
	Sim.step(world, [_move(1, [1], 8), _move(2, [1], 7), null, _move(1, [2], 7), _move(1, [1], 6)])
	assert_int(world.dropped_commands).is_equal(4)
	assert_array([world.order[0], world.order[1]]).is_equal([0, 1])


func test_a_target_outside_the_map_is_clamped() -> void:
	var world: World = _make_world()
	world.add_unit(1, 0, 10000, 10000)
	Sim.step(world, [_move(1, [1], 0, -5000, 90000)])
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([400, MAP - 400])


func test_a_second_command_retargets_a_moving_unit_from_where_it_is() -> void:
	var world: World = _make_world()
	world.add_unit(1, 0, 10000, 10000)
	Sim.step(world, [_move(1, [1], 0, 12000, 10000)])
	Sim.step(world, [])
	Sim.step(world, [_move(1, [1], 2, 10240, 9000)])
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([10240, 9880])
	assert_array([world.goal_x[0], world.goal_y[0], world.order[0]]).is_equal([10240, 9000, 1])


## The list order must not matter: the later sequence wins, and the list ends up sorted.
func test_commands_apply_in_tick_player_sequence_order() -> void:
	var world: World = _scenario_world()
	var late: Command = _move(1, [1], 0, 30000, 30000, 2)
	var early: Command = _move(1, [1], 0, 20000, 20000, 1)
	var enemy: Command = _move(2, [31], 0)
	var list: Array[Command] = [enemy, late, early]
	Sim.step(world, list)
	assert_array(list).is_equal([early, late, enemy])
	assert_array([world.goal_x[0], world.goal_y[0], world.order[30]]).is_equal([30000, 30000, 1])


func test_runs_are_identical_whatever_order_the_commands_are_listed_in() -> void:
	var first: World = _scenario_world()
	var second: World = _scenario_world()
	var forward: Array[Command] = _script()
	var backward: Array[Command] = _script()
	backward.reverse()
	for _t: int in 80:
		Sim.step(first, _due(forward, first.tick))
		Sim.step(second, _due(backward, second.tick))
		assert_array(_state(second)).is_equal(_state(first))
	# Not vacuous: the units moved, and the one wrong-player command was dropped.
	assert_int(first.pos_x[0]).is_not_equal(8500)
	assert_int(first.dropped_commands).is_equal(1)


## Tick 0: two overlapping groups (the later sequence wins) and an enemy order. Tick 25: a
## re-order, and the same order from the wrong player, which is dropped.
func _script() -> Array[Command]:
	return [
		_move(1, range(1, 16), 0, 20000, 20000, 0),
		_move(1, range(10, 31), 0, 30000, 30000, 1),
		_move(2, range(31, 35), 0, 30000, 12000, 0),
		_move(1, range(1, 31), 25, 5000, 5000, 2),
		_move(2, range(1, 31), 25, 5000, 5000, 1),
	]


func _due(list: Array[Command], tick: int) -> Array[Command]:
	var due: Array[Command] = []
	due.assign(list.filter(func(c: Command) -> bool: return c.tick == tick))
	return due


func _scenario_world() -> World:
	return World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)


## Type 0: tank (speed 120, radius 400, spacing 1200). Type 1 cannot move. Type 2 has speed 60.
func _make_world() -> World:
	var world: World = World.new()
	world.map_w = MAP
	world.map_h = MAP
	for speed: int in [120, 0, 60]:
		world.type_ids.append(&"type")
		world.type_speed.append(speed)
		world.type_radius.append(400)
		world.type_selection_radius.append(500)
		world.type_spacing.append(1200)
	return world


## An attack-move stamped for `tick`. `ids` is an Array of ints.
func _move(
	player: int,
	ids: Array,
	tick: int,
	x: int = 20000,
	y: int = 20000,
	sequence: int = 0,
	type: int = Command.Type.ATTACK_MOVE
) -> Command:
	var command: Command = Command.attack_move(player, PackedInt32Array(ids), x, y)
	command.tick = tick
	command.sequence = sequence
	command.type = type
	return command


## A unit of `type` at (10000, 10000) is ordered to move by (dx, dy). Returns its offset per tick.
func _walk(dx: int, dy: int, ticks: int, type: int = 0) -> PackedInt32Array:
	var world: World = _make_world()
	world.add_unit(1, type, 10000, 10000)
	var offsets: PackedInt32Array = PackedInt32Array()
	for t: int in ticks:
		var commands: Array[Command] = []
		if t == 0:
			commands.append(_move(1, [1], 0, 10000 + dx, 10000 + dy))
		Sim.step(world, commands)
		offsets.append(world.pos_x[0] - 10000)
		offsets.append(world.pos_y[0] - 10000)
	return offsets


func _state(world: World) -> Array:
	return [
		world.pos_x, world.pos_y, world.goal_x, world.goal_y, world.order, world.dropped_commands
	]
