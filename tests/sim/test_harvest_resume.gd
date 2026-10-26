extends GdUnitTestSuite
## The auto-resume of a harvester the player left alone (plan row P75b, ADR 0018 section 3, "IDLE"):
## on a tick with `(tick + id) % harvest_resume_ticks == 0` an IDLE harvester whose order has ended
## turns to SEEK, with the cell it had while that has ore, else the cell nearest to it, and the MOVE
## to that cell's centre comes in the same step (`harvest_resume_ticks` 0 turns the rule off). The
## ticks are `world.tick` during the step that makes the change; the stagger comes from
## `Worlds.turn`, the speeds from the World's tables.
##
## The map is 20 x 12 grass with ore at A (3, 2) and D (16, 9): cell indexes 0 and 1, centres
## (3 500, 2 500) and (16 500, 9 500). The cells' own cap is 0, so regrowth adds nothing.

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")

const IDLE: int = World.HarvestMode.IDLE
const SEEK: int = World.HarvestMode.SEEK
const MINE: int = World.HarvestMode.MINE
const RETURN: int = World.HarvestMode.RETURN
const UNLOAD: int = World.HarvestMode.UNLOAD
const CENTRE_A: Vector2i = Vector2i(3500, 2500)
const CENTRE_D: Vector2i = Vector2i(16500, 9500)


func _world() -> World:
	var world: World = Worlds.world(Worlds.grass(20, 12, [Vector2i(3, 2), Vector2i(16, 9)]))
	world.ore_cell_max = 0
	return world


func _goal(world: World, id: int) -> Vector2i:
	var row: int = world.index_of(id)
	return Vector2i(world.goal_x[row], world.goal_y[row])


## Steps until unit `id` is in `mode` and returns the tick of that step; -1 after `limit` steps.
func _until(world: World, id: int, mode: int, limit: int) -> int:
	for _step: int in limit:
		Worlds.step(world)
		if Worlds.mode_of(world, id) == mode:
			return world.tick - 1
	return -1


@warning_ignore("integer_division")
func test_a_harvester_the_player_moved_resumes_on_its_turn_once_its_order_has_ended() -> void:
	var world: World = _world()
	var id: int = Worlds.add_harvester(world, 1, CENTRE_A.x, CENTRE_A.y, MINE, 0, 0, 100)
	var row: int = world.index_of(id)
	var speed: int = world.type_speed[world.type_index[row]]
	var ended: int = (6000 + speed - 1) / speed - 1  # The order is given in COMMANDS of tick 0.
	var resume: int = Worlds.turn(ended, id, world.harvest_resume_ticks)
	assert_int(resume).is_greater(ended)  # The turn is a later tick than the end of the walk.
	Worlds.send(world, [Command.move(1, PackedInt32Array([id]), 9500, 2500)])
	assert_array([Worlds.mode_of(world, id), world.order[row]]).is_equal([IDLE, World.Order.MOVE])
	assert_that(_goal(world, id)).is_equal(Vector2i(9500, 2500))
	for tick: int in range(1, resume):
		Worlds.step(world)
		var message: String = "tick %d" % tick
		assert_int(Worlds.mode_of(world, id)).override_failure_message(message).is_equal(IDLE)
		var order: int = World.Order.IDLE if tick >= ended else World.Order.MOVE
		assert_int(world.order[row]).override_failure_message(message).is_equal(order)
	Worlds.step(world)
	# Back to the cell it had, with the cargo, and the order that sends it there in the same step.
	assert_array(Worlds.columns_of(world, id)).is_equal(
		[SEEK, 0, World.Order.MOVE, CENTRE_A.x, CENTRE_A.y, 100, 0]
	)
	assert_int(world.group_cell[row]).is_equal(-1)
	assert_int(world.nav_mode[row]).is_equal(World.NavMode.DIRECT)


func test_harvesters_stopped_together_resume_on_the_turns_of_their_own_ids() -> void:
	var world: World = _world()
	var first: int = Worlds.add_harvester(world, 1, CENTRE_A.x, CENTRE_A.y, MINE, 0, 0, 100)
	var second: int = Worlds.add_harvester(world, 1, CENTRE_A.x, CENTRE_A.y, UNLOAD, 0, 0, 50)
	var period: int = world.harvest_resume_ticks
	var turns: Dictionary[int, int] = {
		first: Worlds.turn(0, first, period), second: Worlds.turn(0, second, period)
	}
	assert_int(turns[first]).is_not_equal(turns[second])
	Worlds.send(world, [Command.stop(1, PackedInt32Array([first, second]))])
	var seen: Dictionary[int, int] = {}
	for tick: int in range(1, period):
		Worlds.step(world)
		for id: int in turns:
			if not seen.has(id) and Worlds.mode_of(world, id) == SEEK:
				seen[id] = tick
				# On its turn it has the cell it had, the order to it and the cargo it carried.
				var cargo: int = 100 if id == first else 50
				assert_array(Worlds.columns_of(world, id)).is_equal(
					[SEEK, 0, World.Order.MOVE, CENTRE_A.x, CENTRE_A.y, cargo, 0]
				)
	assert_dict(seen).is_equal(turns)


func test_a_harvester_stopped_on_its_turn_resumes_in_the_same_step() -> void:
	var world: World = _world()
	world.harvest_resume_ticks = 10  # The harvester still mines on its turn, before it is full.
	var id: int = Worlds.add_harvester(world, 1, CENTRE_A.x, CENTRE_A.y, MINE, 0, 0, 100)
	var turn: int = Worlds.turn(1, id, world.harvest_resume_ticks)
	Worlds.step(world, turn)  # No command, so no release: it mines on.
	assert_int(Worlds.mode_of(world, id)).is_equal(MINE)
	Worlds.send(world, [Command.stop(1, PackedInt32Array([id]))])
	assert_int(world.tick - 1).is_equal(turn)
	assert_int(Worlds.mode_of(world, id)).is_equal(SEEK)  # Released and resumed in tick `turn`.


func test_resume_ticks_of_0_turn_the_rule_off_and_1_makes_every_tick_a_turn() -> void:
	var off: World = _world()
	off.harvest_resume_ticks = 0
	var id: int = Worlds.add_harvester(off, 1, CENTRE_A.x, CENTRE_A.y, MINE, 0, 0, 100)
	Worlds.send(off, [Command.stop(1, PackedInt32Array([id]))])
	Worlds.step(off, 3 * 75)
	assert_array(Worlds.columns_of(off, id)).is_equal(
		[IDLE, 0, World.Order.IDLE, CENTRE_A.x, CENTRE_A.y, 100, 0]
	)
	var every: World = _world()
	every.harvest_resume_ticks = 1
	id = Worlds.add_harvester(every, 1, CENTRE_A.x, CENTRE_A.y, MINE, 0, 0, 100)
	Worlds.send(every, [Command.stop(1, PackedInt32Array([id]))])
	assert_int(Worlds.mode_of(every, id)).is_equal(SEEK)


@warning_ignore("integer_division")
func test_a_harvester_that_is_still_walking_does_not_resume_on_its_turn() -> void:
	var world: World = _world()
	var id: int = Worlds.add_harvester(world, 1, 1500, 10500, IDLE, 0)
	var row: int = world.index_of(id)
	var speed: int = world.type_speed[world.type_index[row]]
	Worlds.walk_to(world, id, 18500, 10500)  # 17 000 away: the walk outlasts several turns.
	var ended: int = (17000 + speed - 1) / speed - 1
	var resume: int = Worlds.turn(ended, id, world.harvest_resume_ticks)
	var turns: int = 0
	for tick: int in range(0, resume):
		Worlds.step(world)
		if (tick + id) % world.harvest_resume_ticks == 0:
			turns += 1
			assert_array([world.harvest_mode[row], world.order[row]]).is_equal(
				[IDLE, World.Order.MOVE]
			)
	assert_int(turns).is_greater(1)
	assert_int(Worlds.mode_of(world, id)).is_equal(IDLE)
	Worlds.step(world)
	assert_array([world.harvest_mode[row], world.harvest_slot[row]]).is_equal([SEEK, 0])


func test_a_resumed_harvester_keeps_its_cell_though_another_is_nearer() -> void:
	var world: World = _world()
	# 2 236 from D and far from A, which still has ore: the harvester goes back to A.
	var id: int = Worlds.add_harvester(world, 1, 14500, 8500, IDLE, 0)
	var resume: int = Worlds.turn(0, id, world.harvest_resume_ticks)
	Worlds.step(world, resume + 1)
	var expected: Array[int] = [SEEK, 0, World.Order.MOVE, CENTRE_A.x, CENTRE_A.y, 0, 0]
	assert_array(Worlds.columns_of(world, id)).is_equal(expected)
	# The order came with the cell, so SEEK reads the walk as under way. With no order it would call
	# the harvester one whose order ended short of A and take D, the cell it stands next to.
	Worlds.step(world, 3)
	assert_array(Worlds.columns_of(world, id)).is_equal(expected)


func test_a_resumed_harvester_whose_cell_ran_empty_takes_the_cell_nearest_to_it() -> void:
	var world: World = _world()
	world.ore_amount[0] = 0
	var id: int = Worlds.add_harvester(world, 1, 14500, 8500, IDLE, 0)
	var resume: int = Worlds.turn(0, id, world.harvest_resume_ticks)
	Worlds.step(world, resume)
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(0)  # No look before its turn.
	Worlds.step(world)
	assert_array(Worlds.columns_of(world, id)).is_equal(
		[SEEK, 1, World.Order.MOVE, CENTRE_D.x, CENTRE_D.y, 0, 0]
	)
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(2)  # One look at the two cells.


func test_a_resumed_harvester_with_no_ore_anywhere_waits_in_seek_and_looks_each_retry_period(
) -> void:
	var world: World = _world()
	world.ore_amount.fill(0)
	var id: int = Worlds.add_harvester(world, 1, 14500, 8500, IDLE, 0, 0, 25)
	var resume: int = Worlds.turn(0, id, world.harvest_resume_ticks)
	Worlds.step(world, resume + 1)
	assert_array(Worlds.columns_of(world, id)).is_equal(
		[SEEK, -1, World.Order.IDLE, 14500, 8500, 25, 0]
	)
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(2)
	var look: int = Worlds.turn(resume + 1, id, world.harvest_retry_ticks)
	for tick: int in range(resume + 1, look + 1):
		Worlds.step(world)
		var scanned: int = 2 if tick == look else 0
		(
			assert_int(world.stats[World.Stat.ORE_SCANNED])
			. override_failure_message("tick %d" % tick)
			. is_equal(scanned)
		)


@warning_ignore("integer_division")
func test_a_resumed_harvester_in_reach_of_its_cell_walks_to_the_centre_and_mines() -> void:
	var world: World = _world()
	var id: int = Worlds.add_harvester(world, 1, CENTRE_A.x + 800, CENTRE_A.y, IDLE, 0)
	var speed: int = world.type_speed[world.type_index[world.index_of(id)]]
	var resume: int = Worlds.turn(0, id, world.harvest_resume_ticks)
	Worlds.step(world, resume + 1)
	# Within reach of the cell, but the order to its centre comes all the same.
	assert_array(Worlds.columns_of(world, id)).is_equal(
		[SEEK, 0, World.Order.MOVE, CENTRE_A.x, CENTRE_A.y, 0, 0]
	)
	# The order is given in ECONOMY, so the walk starts the next tick; MINE comes on its last step.
	var steps: int = (800 + speed - 1) / speed
	assert_int(_until(world, id, MINE, 30)).is_equal(resume + steps)


func test_a_full_harvester_the_player_moved_goes_home_and_unloads_what_it_carries() -> void:
	var world: World = _world()
	var refinery: int = Worlds.add_refinery(world, 1, 8, 6)  # Dock (9, 9), centre (9 500, 9 500).
	var full: int = world.type_harvest[Worlds.type_of(world, "harvester")]
	var id: int = Worlds.add_harvester(world, 1, 14500, 9500, IDLE, 0, refinery, full)
	var resume: int = Worlds.turn(0, id, world.harvest_resume_ticks)
	var modes: Array[Array] = []
	var mode: int = IDLE
	while world.stat_harvested[1] < full and world.tick < resume + 600:
		Worlds.step(world)
		if Worlds.mode_of(world, id) != mode:
			mode = Worlds.mode_of(world, id)
			modes.append([world.tick - 1, mode])
	# SEEK on its turn, RETURN on the next tick (SEEK sends a full load home), then the dock.
	assert_array(modes.slice(0, 2)).is_equal([[resume, SEEK], [resume + 1, RETURN]])
	(
		assert_array(modes.map(func(change: Array) -> int: return change[1]))
		. is_equal([SEEK, RETURN, UNLOAD, SEEK])
	)
	assert_array([world.credits[1], world.stat_harvested[1]]).is_equal(
		[world.start_credits + full, full]
	)
	assert_array([world.credits[2], Worlds.cargo_of(world, id)]).is_equal([world.start_credits, 0])
