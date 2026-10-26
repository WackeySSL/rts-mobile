extends GdUnitTestSuite
## The ore of the harvest loop (plan row P75, ADR 0018 sections 2 and 3): regrowth up to the cap,
## the look of SEEK (the nearest cell with ore, the lowest index on a tie, every cell counted in
## `Stat.ORE_SCANNED`, a look every `harvest_retry_ticks` while there is none), two harvesters on
## one cell, and the harvester whose order ended short of its cell. The harvester of the cases has
## no refinery: none of them fills a hold. The cells' own cap is 0 where a case needs the ore to
## stay as the case sets it (regrowth would otherwise add 1 on tick 0, `0 % 150 == 0`).

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")

const SEEK: int = World.HarvestMode.SEEK
const MINE: int = World.HarvestMode.MINE


## The ore of `world` as a plain array.
func _ore(world: World) -> Array[int]:
	var found: Array[int] = []
	found.assign(world.ore_amount)
	return found


func test_ore_regrows_one_unit_per_cell_each_regrow_period_and_stops_at_the_cap() -> void:
	var world: World = Worlds.world(
		Worlds.grass(10, 6, [Vector2i(2, 2), Vector2i(5, 2), Vector2i(8, 2)])
	)
	world.ore_amount[0] = 17
	world.ore_amount[1] = 0
	world.ore_amount[2] = 20
	assert_int(world.ore_regrow_ticks).is_equal(150)
	Worlds.step(world)  # Tick 0 is a regrowth tick.
	assert_array(_ore(world)).is_equal([18, 1, 20])
	Worlds.step(world, 149)  # Ticks 1 to 149: nothing grows between the periods.
	assert_array(_ore(world)).is_equal([18, 1, 20])
	Worlds.step(world)  # Tick 150.
	assert_array(_ore(world)).is_equal([19, 2, 20])
	Worlds.step(world, 150)  # Tick 300.
	assert_array(_ore(world)).is_equal([20, 3, 20])
	Worlds.step(world, 150 * 3)  # Ticks 450 to 750: the full cell stays at the cap.
	assert_array(_ore(world)).is_equal([20, 6, 20])
	assert_array(world.ore_cell).is_equal([22, 25, 28])  # Regrowth never touches the cell list.


func test_regrowth_reads_its_period_and_cap_from_the_rules() -> void:
	var world: World = Worlds.world(
		Worlds.grass(10, 6, [Vector2i(2, 2), Vector2i(5, 2), Vector2i(8, 2)])
	)
	world.ore_regrow_ticks = 10
	world.ore_cell_max = 3
	world.ore_amount[0] = 0
	world.ore_amount[1] = 3
	world.ore_amount[2] = 5  # Above the cap (a hand-set world): left alone, not cut down.
	var grown: Array[Array] = []
	for _period: int in 5:
		Worlds.step(world, 10)
		grown.append(_ore(world))
	assert_array(grown).is_equal([[1, 3, 5], [2, 3, 5], [3, 3, 5], [3, 3, 5], [3, 3, 5]])


func test_a_look_counts_every_ore_cell_and_a_harvester_with_no_cell_looks_each_retry_period(
) -> void:
	var ore: Array[Vector2i] = [Vector2i(1, 1), Vector2i(8, 1), Vector2i(1, 4), Vector2i(8, 4)]
	var world: World = Worlds.world(Worlds.grass(10, 6, ore))
	world.ore_cell_max = 0
	world.ore_amount.fill(0)  # Nothing to take: the harvester keeps looking.
	var id: int = Worlds.add_harvester(world, 1, 5500, 3500)
	var looks: Array[int] = []
	for tick: int in 46:
		Worlds.step(world)
		if world.stats[World.Stat.ORE_SCANNED] > 0:
			looks.append(tick)
			assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(4)  # Every cell, even empty.
	var period: int = world.harvest_retry_ticks
	assert_array(looks).is_equal(
		[
			Worlds.turn(0, id, period),
			Worlds.turn(0, id, period) + period,
			Worlds.turn(0, id, period) + 2 * period
		]
	)
	assert_int(world.harvest_slot[world.index_of(id)]).is_equal(-1)
	world.ore_amount[3] = 1  # Ore appears: the next look finds it, and counts the cells once more.
	var next: int = Worlds.turn(world.tick, id, period)
	Worlds.step(world, next - world.tick + 1)
	(
		assert_array([world.stats[World.Stat.ORE_SCANNED], world.harvest_slot[world.index_of(id)]])
		. is_equal([4, 3])
	)


func test_seek_takes_the_nearest_cell_with_ore_and_the_lowest_index_on_a_tie() -> void:
	# Cells 0, 1 and 2 are the tiles (2, 1), (6, 1) and (4, 4); the harvester at (4 500, 1 500) is
	# 2 000 from cells 0 and 1 and 3 000 from cell 2. Case: the ore of the three, the cell taken.
	var cases: Array[Array] = [[[5, 5, 5], 0], [[0, 5, 5], 1], [[0, 0, 5], 2], [[5, 5, 0], 0]]
	for case: Array in cases:
		var ore: Array[Vector2i] = [Vector2i(2, 1), Vector2i(6, 1), Vector2i(4, 4)]
		var world: World = Worlds.world(Worlds.grass(10, 6, ore))
		world.ore_cell_max = 0
		for cell: int in 3:
			world.ore_amount[cell] = case[0][cell]
		var id: int = Worlds.add_harvester(world, 1, 4500, 1500)
		Worlds.step(world, Worlds.turn(0, id, world.harvest_retry_ticks) + 1)
		(
			assert_int(world.harvest_slot[world.index_of(id)])
			. override_failure_message(str(case))
			. is_equal(case[1])
		)


func test_a_harvester_that_stands_in_reach_of_the_cell_it_picks_gets_no_order() -> void:
	var world: World = Worlds.world(Worlds.grass(10, 6, [Vector2i(2, 1), Vector2i(8, 4)]))
	var near: int = Worlds.add_harvester(world, 1, 2500 + 1100, 1500)  # 1 100 from the first cell.
	var far: int = Worlds.add_harvester(world, 1, 5500, 3500)  # 3 606 from cell 0, 3 162 from cell 1.
	var row_near: int = world.index_of(near)
	var row_far: int = world.index_of(far)
	Worlds.step(world, world.harvest_retry_ticks)  # Both have had their look.
	assert_array([world.harvest_slot[row_near], world.order[row_near]]).is_equal(
		[0, World.Order.IDLE]
	)
	assert_array([world.harvest_slot[row_far], world.order[row_far]]).is_equal(
		[1, World.Order.MOVE]
	)
	assert_array([world.goal_x[row_far], world.goal_y[row_far]]).is_equal([8500, 4500])


func test_two_harvesters_share_a_cell_and_never_take_more_than_it_holds() -> void:
	var world: World = Worlds.world(Worlds.grass(8, 6, [Vector2i(3, 2)]))
	world.ore_cell_max = 0
	var first: int = Worlds.add_harvester(world, 1, 3300, 2500, MINE, 0)
	var second: int = Worlds.add_harvester(world, 1, 3700, 2500, MINE, 0)
	for tick: int in 50:
		Worlds.step(world)
		var taken: int = Worlds.cargo_of(world, first) + Worlds.cargo_of(world, second)
		assert_int(world.ore_amount[0]).override_failure_message("tick %d" % tick).is_greater_equal(
			0
		)
		assert_int(taken).override_failure_message("tick %d" % tick).is_equal(
			(20 - world.ore_amount[0]) * world.credits_per_ore
		)
	# Their turns are one tick apart: 10 units each empty the 20, and both go on to look.
	assert_array([Worlds.cargo_of(world, first), Worlds.cargo_of(world, second)]).is_equal(
		[250, 250]
	)
	assert_array([Worlds.mode_of(world, first), Worlds.mode_of(world, second)]).is_equal(
		[SEEK, SEEK]
	)
	assert_int(world.ore_amount[0]).is_equal(0)


func test_a_harvester_with_no_order_far_from_its_cell_is_one_whose_order_ended_short() -> void:
	var ore: Array[Vector2i] = [Vector2i(2, 2), Vector2i(9, 5)]
	var world: World = Worlds.world(Worlds.grass(12, 8, ore))
	var id: int = Worlds.add_harvester(world, 1, 6500, 3500, SEEK, 0)  # 4 000 from cell 0, no order.
	var row: int = world.index_of(id)
	Worlds.step(world)  # Tick 0: no wait, the cell is not a new look but a cell it already had.
	assert_array([world.harvest_slot[row], world.order[row]]).is_equal([1, World.Order.MOVE])
	assert_array([world.goal_x[row], world.goal_y[row]]).is_equal([9500, 5500])
	assert_int(world.stats[World.Stat.ORE_SCANNED]).is_equal(2)


func test_a_lone_cell_that_was_left_is_tried_again_after_the_retry_wait() -> void:
	var world: World = Worlds.world(Worlds.grass(12, 8, [Vector2i(2, 2)]))
	var id: int = Worlds.add_harvester(world, 1, 6500, 3500, SEEK, 0)
	var row: int = world.index_of(id)
	Worlds.step(world)  # Ended short: no other cell, so it waits.
	assert_array([world.harvest_slot[row], world.order[row]]).is_equal([-1, World.Order.IDLE])
	var look: int = Worlds.turn(1, id, world.harvest_retry_ticks)
	Worlds.step(world, look - 1)
	assert_int(world.harvest_slot[row]).is_equal(-1)  # Still waiting on the tick before its turn.
	Worlds.step(world)
	assert_array([world.harvest_slot[row], world.order[row]]).is_equal([0, World.Order.MOVE])


func test_an_order_that_stalls_short_of_an_enclosed_cell_sends_the_harvester_to_the_next_cell(
) -> void:
	var rows: Array[String] = [
		"..............",
		"..............",
		"..###.........",
		"..#o#.........",
		"..###.........",
		"..............",
		"..............",
		".........o....",
		"..............",
	]
	var world: World = Worlds.world(rows)
	assert_array(world.ore_cell).is_equal([45, 107])
	var id: int = Worlds.add_harvester(world, 1, 7500, 3500)  # 4 000 from the cell inside the rock.
	var row: int = world.index_of(id)
	var first: int = Worlds.turn(0, id, world.harvest_retry_ticks)
	Worlds.step(world, first + 1)
	assert_array([world.harvest_slot[row], world.order[row]]).is_equal([0, World.Order.MOVE])
	var mining: int = -1
	for tick: int in 600:
		Worlds.step(world)
		if mining < 0 and Worlds.mode_of(world, id) == MINE:
			mining = tick
			# The order stalled outside the rock, and the look after it skipped the cell it could
			# not reach: the harvester walked to the other one and mines at its centre.
			assert_array([world.harvest_slot[row], world.pos_x[row], world.pos_y[row]]).is_equal(
				[1, 9500, 7500]
			)
	assert_bool(mining >= 0).is_true()
	assert_int(world.ore_amount[0]).is_equal(20)
