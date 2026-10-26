extends GdUnitTestSuite
## A harvester built by a factory, from the QUEUE to its first credits (the interaction of plan rows
## P73 and P75, the review of 2026-10-26): the unit that `ProductionSpawn` puts on the map in SEEK
## with no home gets into the harvest loop one tick after its spawn, looks for ore on its retry turn
## (and not before), takes the nearest cell, makes the refinery its home when it returns, and adds
## one full hold to the credits after its first unload.
##
## The map is 24 x 14 grass: a power plant (id 1) at (1, 1), a refinery (id 2, tiles 5..7 x 1..3,
## dock (6, 4)) and a vehicle factory (id 3, tiles 12..14 x 1..3, exit (13, 4)) of player 1, and two
## ore cells: (2, 8), cell index 0, 11 000 west and 4 000 south of the exit, and (13, 11), index 1,
## 7 000 south of it. The nearest cell is not the lowest index. The cells' own cap is 0.

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")

const SEEK: int = World.HarvestMode.SEEK
const EXIT: Vector2i = Vector2i(13500, 4500)
const NEAR_CELL: Vector2i = Vector2i(13500, 11500)


func _world() -> World:
	var rows: Array[String] = Worlds.grass(24, 14, [Vector2i(2, 8), Vector2i(13, 11)])
	var world: World = Worlds.world(rows, ["vehicle_factory"])
	world.ore_cell_max = 0
	world.add_building(1, Worlds.type_of(world, "power_plant"), 1, 1)
	Worlds.add_refinery(world, 1, 5, 1)
	world.add_building(1, Worlds.type_of(world, "vehicle_factory"), 12, 1)
	return world


func test_a_factory_harvester_looks_on_its_retry_turn_takes_the_nearest_cell_and_pays_500() -> void:
	var world: World = _world()
	var harvester: int = Worlds.type_of(world, "harvester")
	var cost: int = world.type_cost[harvester]
	var build_ticks: int = world.type_build_ticks[harvester]
	var refinery: int = 2
	Worlds.send(world, [Command.queue(1, harvester)])
	assert_int(world.credits[1]).is_equal(world.start_credits - cost)
	# The item is done after exactly its build ticks: it spawns in PRODUCTION of tick build_ticks - 1.
	Worlds.step(world, build_ticks - 2)
	assert_int(world.unit_count()).is_equal(3)  # The three buildings and no harvester yet.
	Worlds.step(world)
	var spawned: int = world.tick - 1
	assert_int(world.unit_count()).is_equal(4)
	var id: int = world.unit_id[world.unit_count() - 1]
	var row: int = world.index_of(id)
	assert_int(spawned).is_equal(build_ticks - 1)
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([EXIT.x, EXIT.y])
	assert_array(Worlds.columns_of(world, id)).is_equal(
		[SEEK, -1, World.Order.IDLE, EXIT.x, EXIT.y, 0, 0]
	)
	# ECONOMY of the spawn tick has run, so the loop sees it from the next tick on, and a harvester
	# with no cell looks only on the ticks with (tick + id) % harvest_retry_ticks == 0.
	var look: int = Worlds.turn(spawned + 1, id, world.harvest_retry_ticks)
	for tick: int in range(spawned + 1, look):
		Worlds.step(world)
		(
			assert_int(world.stats[World.Stat.ORE_SCANNED])
			. override_failure_message("tick %d" % tick)
			. is_equal(0)
		)
		assert_int(world.harvest_slot[row]).is_equal(-1)
	Worlds.step(world)
	assert_int(world.tick - 1).is_equal(look)
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(world.ore_cell.size())
	assert_array(Worlds.columns_of(world, id)).is_equal(
		[SEEK, 1, World.Order.MOVE, NEAR_CELL.x, NEAR_CELL.y, 0, 0]
	)
	# The trip: the cell, a full hold, the refinery that becomes its home, one unload.
	var full: int = world.type_harvest[harvester]
	var guard: int = 900
	while world.stat_harvested[1] < full and guard > 0:
		Worlds.step(world)
		guard -= 1
	assert_int(guard).is_greater(0)
	assert_int(world.home[row]).is_equal(refinery)
	assert_array([world.credits[1], world.stat_harvested[1]]).is_equal(
		[world.start_credits - cost + full, full]
	)
	assert_array([Worlds.cargo_of(world, id), Worlds.mode_of(world, id)]).is_equal([0, SEEK])
	assert_int(world.ore_amount[1]).is_equal(0)  # The near cell gave its 20 units.
	assert_int(world.ore_amount[0]).is_equal(world.ore_start)  # The far one was left alone.
	assert_int(world.credits[2]).is_equal(world.start_credits)
