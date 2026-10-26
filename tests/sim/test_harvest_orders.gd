extends GdUnitTestSuite
## HARVEST and the release of a harvester (plan row P75b, ADR 0018 section 3, ADR 0017 section 4):
## the command sends the player's harvesters to the ore cell nearest the point, within
## `harvest_pick_milli` of it, in SEEK with the MOVE to the cell's centre given in the same step;
## no harvester among the ids or no such cell drops it; a unit-group order (MOVE, ATTACK_MOVE, STOP)
## hands a harvester to the player with its cargo, cell and refinery kept. The pick distance and
## the speeds come from the World's rules and tables, not from literals.
##
## The big map is 20 x 12 grass with ore at A (3, 2), B (12, 2) and C (8, 9): cell indexes 0, 1, 2,
## centres (3 500, 2 500), (12 500, 2 500) and (8 500, 9 500). The small map is 12 x 8 with ore at
## (3, 2) and (6, 2), the centres 3 000 apart, and the lone map has the cell (3, 2) only. The
## cells' own cap is 0, so regrowth adds nothing.

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")

const IDLE: int = World.HarvestMode.IDLE
const SEEK: int = World.HarvestMode.SEEK
const MINE: int = World.HarvestMode.MINE
const RETURN: int = World.HarvestMode.RETURN
const UNLOAD: int = World.HarvestMode.UNLOAD
const CENTRE_A: Vector2i = Vector2i(3500, 2500)
const CENTRE_B: Vector2i = Vector2i(12500, 2500)
const CENTRE_C: Vector2i = Vector2i(8500, 9500)


func _map(cols: int, lines: int, ore: Array[Vector2i]) -> World:
	var world: World = Worlds.world(Worlds.grass(cols, lines, ore))
	world.ore_cell_max = 0
	return world


func _big() -> World:
	return _map(20, 12, [Vector2i(3, 2), Vector2i(12, 2), Vector2i(8, 9)])


func _small() -> World:
	return _map(12, 8, [Vector2i(3, 2), Vector2i(6, 2)])


## A HARVEST of `player` for `ids` at the milli point (x, y).
func _harvest(player: int, ids: Array[int], x: int, y: int) -> Command:
	return Command.harvest(player, PackedInt32Array(ids), x, y)


func _goal(world: World, id: int) -> Vector2i:
	var row: int = world.index_of(id)
	return Vector2i(world.goal_x[row], world.goal_y[row])


func test_harvest_sends_the_players_harvesters_to_the_cell_nearest_the_point() -> void:
	var world: World = _big()
	var miner: int = Worlds.add_harvester(world, 1, 3500, 2500, MINE, 0, 0, 100)
	var returner: int = Worlds.add_harvester(world, 1, 6500, 6500, RETURN, 2, 0, 200)
	var rifle: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 5500, 5500)
	# The enemy's harvester waits for a refinery that it has not got: nothing in it changes.
	var enemy: int = Worlds.add_harvester(world, 2, 8500, 9500, RETURN, 2, 0, 50)
	var enemy_before: Array[int] = Worlds.columns_of(world, enemy)
	# 985 from B's centre and 9 400 from A's: B, though both harvesters work elsewhere.
	var ids: Array[int] = [miner, returner, rifle, enemy, 999]
	Worlds.send(world, [_harvest(1, ids, 12900, 3400)])
	assert_int(world.dropped_commands).is_equal(0)
	for id: int in [miner, returner]:
		var row: int = world.index_of(id)
		assert_array([world.harvest_mode[row], world.harvest_slot[row]]).is_equal([SEEK, 1])
		assert_array([world.order[row], world.group_cell[row]]).is_equal([World.Order.MOVE, -1])
		assert_that(_goal(world, id)).is_equal(CENTRE_B)
		assert_int(world.nav_mode[row]).is_equal(World.NavMode.DIRECT)
	assert_array([Worlds.cargo_of(world, miner), Worlds.cargo_of(world, returner)]).is_equal(
		[100, 200]
	)
	assert_int(world.order[world.index_of(rifle)]).is_equal(World.Order.IDLE)
	assert_array(Worlds.columns_of(world, enemy)).is_equal(enemy_before)
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(3)  # One look at the three cells.


func test_the_cell_is_nearest_the_point_not_the_harvester_and_the_order_is_not_re_picked() -> void:
	var world: World = _big()
	var id: int = Worlds.add_harvester(world, 1, 4500, 3500, IDLE)  # 1 414 from A, 8 400 from C.
	Worlds.send(world, [_harvest(1, [id], 8000, 8500)])
	var expected: Array[int] = [SEEK, 2, World.Order.MOVE, CENTRE_C.x, CENTRE_C.y, 0, 0]
	assert_array(Worlds.columns_of(world, id)).is_equal(expected)
	# The order came with the cell, so SEEK reads the walk as under way. With no order it would call
	# the harvester one whose order ended short of C and take A, which it stands next to.
	Worlds.step(world, 3)
	assert_array(Worlds.columns_of(world, id)).is_equal(expected)
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(0)


func test_equally_near_cells_go_to_the_lowest_index() -> void:
	var world: World = _small()
	var id: int = Worlds.add_harvester(world, 1, 5500, 5500, IDLE)
	Worlds.send(world, [_harvest(1, [id], 5000, 2500)])  # 1 500 from both centres.
	assert_int(world.harvest_slot[world.index_of(id)]).is_equal(0)
	assert_that(_goal(world, id)).is_equal(Vector2i(3500, 2500))


@warning_ignore("integer_division")
func test_a_cell_counts_exactly_within_the_pick_distance_and_not_a_milli_beyond() -> void:
	var pick: int = _small().harvest_pick_milli
	# The offset of the point from the lone cell's centre, whether it is taken and the cell then.
	var cases: Array[Array] = [
		[pick, 0, true, 0],
		[pick + 1, 0, false, -1],
		[0, pick, true, 0],
		[0, -pick - 1, false, -1],
		[pick * 7 / 10, pick * 7 / 10, true, 0],  # 2 100 each way is 2 970 away: within.
		[pick * 3 / 4, pick * 3 / 4, false, -1],  # 2 250 each way is 3 182 away: beyond.
	]
	for case: Array in cases:
		var world: World = _map(12, 8, [Vector2i(3, 2)])
		var id: int = Worlds.add_harvester(world, 1, 1500, 6500, MINE, -1, 0, 75)
		var command: Command = _harvest(1, [id], 3500 + case[0], 2500 + case[1])
		var label: String = "%s" % [case]
		assert_bool(Harvest.apply_harvest(world, command)).override_failure_message(label).is_equal(
			case[2]
		)
		assert_int(world.harvest_slot[world.index_of(id)]).override_failure_message(label).is_equal(
			case[3]
		)
		assert_int(Worlds.mode_of(world, id)).override_failure_message(label).is_equal(
			SEEK if case[2] else MINE
		)


func test_a_cell_without_ore_is_not_taken_and_the_next_one_within_reach_is() -> void:
	var world: World = _small()
	world.ore_amount[0] = 0
	var id: int = Worlds.add_harvester(world, 1, 1500, 6500, IDLE)
	# The point is on the empty cell's centre; the other cell is 3 000 away, the pick distance.
	Worlds.send(world, [_harvest(1, [id], 3500, 2500)])
	assert_array([world.harvest_slot[world.index_of(id)], world.dropped_commands]).is_equal([1, 0])
	world.ore_amount[1] = 0
	Worlds.send(world, [_harvest(1, [id], 3500, 2500)])
	assert_int(world.dropped_commands).is_equal(1)  # No cell with ore at all: dropped.


func test_a_harvest_far_from_ore_is_dropped_and_counted_and_changes_nothing() -> void:
	var twin: World = _big()
	var world: World = _big()
	var id: int = Worlds.add_harvester(twin, 1, 3500, 2500, MINE, 0, 0, 100)
	assert_int(Worlds.add_harvester(world, 1, 3500, 2500, MINE, 0, 0, 100)).is_equal(id)
	# (3 500, 7 500) is 5 000 from A's centre, the nearest, beyond the pick distance.
	Worlds.send(twin, [])
	Worlds.send(world, [_harvest(1, [id], 3500, 7500)])
	assert_array([twin.dropped_commands, world.dropped_commands]).is_equal([0, 1])
	assert_array(Worlds.columns_of(world, id)).is_equal(Worlds.columns_of(twin, id))
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(3)  # The look was made, found none.
	assert_array(world.ore_amount).is_equal(twin.ore_amount)


func test_a_harvest_without_a_harvester_among_the_ids_is_dropped_before_any_look() -> void:
	var world: World = _big()
	var rifle: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 3500, 2500)
	var enemy: int = Worlds.add_harvester(world, 2, 3500, 2500, MINE, 0)
	var mine: int = Worlds.add_harvester(world, 1, 3500, 2500, MINE, 0)
	var many: Array[int] = []
	many.resize(Command.MAX_UNITS + 1)
	many.fill(mine)
	var cases: Dictionary[String, Command] = {
		"rifle squad only": _harvest(1, [rifle], 3500, 2500),
		"enemy harvester only": _harvest(1, [enemy], 3500, 2500),
		"unknown id": _harvest(1, [999], 3500, 2500),
		"no ids": _harvest(1, [], 3500, 2500),
		"too many ids": _harvest(1, many, 3500, 2500),
		"another player's harvester": _harvest(2, [mine], 3500, 2500),
	}
	for label: String in cases:
		var before: int = world.dropped_commands
		Worlds.send(world, [cases[label]])
		assert_int(world.dropped_commands - before).override_failure_message(label).is_equal(1)
		assert_int(world.stats[World.Stat.ORE_SCANNED]).override_failure_message(label).is_equal(0)
		assert_int(Worlds.mode_of(world, mine)).override_failure_message(label).is_equal(MINE)


@warning_ignore("integer_division")
func test_a_harvester_walks_to_the_chosen_cell_and_turns_to_mine_when_its_order_ends() -> void:
	var world: World = _big()
	var id: int = Worlds.add_harvester(world, 1, 3500, 8500, IDLE)
	var row: int = world.index_of(id)
	var speed: int = world.type_speed[world.type_index[row]]
	var steps: int = (8500 - CENTRE_A.y + speed - 1) / speed  # Straight north, 6 000 away.
	Worlds.send(world, [_harvest(1, [id], 3000, 3000)])
	# The order is given in COMMANDS, so the first step of the walk is the same tick's INTEGRATE and
	# the last is tick `steps - 1`, where ECONOMY sees the ended order within reach and turns to MINE.
	var mining: int = -1
	for tick: int in range(1, steps + 3):
		Worlds.step(world)
		if mining < 0 and Worlds.mode_of(world, id) == MINE:
			mining = tick
	assert_int(mining).is_equal(steps - 1)
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([CENTRE_A.x, CENTRE_A.y])
	assert_int(world.harvest_slot[row]).is_equal(0)
	assert_int(world.cargo[row]).is_greater(0)


func test_release_hands_each_harvester_of_the_rows_to_the_player_and_keeps_its_columns() -> void:
	var world: World = _big()
	var ids: Array[int] = []
	for mode: int in [SEEK, MINE, RETURN, UNLOAD]:
		ids.append(Worlds.add_harvester(world, 1, 3500, 2500, mode, 1, 77, 100 + mode))
	var rifle: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 5500, 5500)
	var bystander: int = Worlds.add_harvester(world, 1, 3500, 2500, MINE, 1, 77, 5)
	var rows: PackedInt32Array = PackedInt32Array([world.index_of(rifle)])
	var before: Array[Array] = []
	for id: int in ids:
		rows.append(world.index_of(id))
		before.append(Worlds.columns_of(world, id))
	Harvest.release(world, rows)
	for at: int in ids.size():
		var expected: Array[int] = []
		expected.assign(before[at])
		expected[0] = IDLE  # The mode only: the cell (1), the home (77) and the cargo stay.
		assert_array(Worlds.columns_of(world, ids[at])).is_equal(expected)
	assert_int(Worlds.mode_of(world, bystander)).is_equal(MINE)  # Not among the rows.
	assert_int(world.harvest_mode[world.index_of(rifle)]).is_equal(IDLE)
	Harvest.release(world, PackedInt32Array())  # No rows: nothing to do.
	assert_int(Worlds.mode_of(world, bystander)).is_equal(MINE)


func test_move_attack_move_and_stop_release_the_harvesters_among_the_units_through_sim() -> void:
	var world: World = _big()
	var rifle: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 5500, 5500)
	for order: int in [World.Order.MOVE, World.Order.ATTACK_MOVE]:
		var id: int = Worlds.add_harvester(world, 1, 3500, 2500, MINE, 0, 77, 150)
		var ids: PackedInt32Array = PackedInt32Array([id, rifle])
		if order == World.Order.MOVE:
			Worlds.send(world, [Command.move(1, ids, 7500, 5500)])
		else:
			Worlds.send(world, [Command.attack_move(1, ids, 7500, 5500)])
		var row: int = world.index_of(id)
		assert_int(world.dropped_commands).is_equal(0)
		assert_array([world.harvest_mode[row], world.order[row]]).is_equal([IDLE, order])
		assert_array([world.harvest_slot[row], world.home[row], world.cargo[row]]).is_equal(
			[0, 77, 150]
		)
	var stopped: int = Worlds.add_harvester(world, 1, 3500, 2500, UNLOAD, 0, 77, 150)
	Worlds.send(world, [Command.stop(1, PackedInt32Array([stopped]))])
	assert_array(Worlds.columns_of(world, stopped)).is_equal(
		[IDLE, 0, World.Order.IDLE, 3500, 2500, 150, 77]
	)
