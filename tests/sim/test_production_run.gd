extends GdUnitTestSuite
## The PRODUCTION phase for the unit tabs (plan row P73, ADR 0018 section 5): exact tick counts per
## item, the head gaining 100 hundredths per tick, the next item starting from 0, the two tabs and
## two players side by side, the primary producer (the lowest-id building of the tab), a queue that
## waits without a producer, the first order of a new unit (a harvester's SEEK, the rally MOVE) and
## a replay-style determinism check. The world is `production_worlds.gd`'s: a queue made on tick 0
## gains its first 100 in that same tick, so an item of N ticks is there after N steps. Literal
## numbers are the shipped data's: rifle squad 100 credits and 75 ticks, rocket squad 300 and 150,
## light tank 600 and 225, heavy tank 1,000 and 330, harvester 1,200 and 300.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const INFANTRY: int = World.Tab.INFANTRY
const VEHICLES: int = World.Tab.VEHICLES
## The tile centre of the barracks' exit (9, 3) and of the vehicle factory's (18, 4).
const BARRACKS_EXIT: Vector2i = Vector2i(9500, 3500)
const FACTORY_EXIT: Vector2i = Vector2i(18500, 4500)


func _at(world: World, row: int) -> Vector2i:
	return Vector2i(world.pos_x[row], world.pos_y[row])


## Every item of the roster is done after exactly its build ticks: not on the step before, and then
## the queue is empty, the progress 0, the cost paid once and the build counted.
func test_an_item_is_done_after_exactly_its_build_ticks() -> void:
	var cases: Array[Array] = [
		["rifle_squad", 75, 100, BARRACKS_EXIT],
		["rocket_squad", 150, 300, BARRACKS_EXIT],
		["light_tank", 225, 600, FACTORY_EXIT],
		["heavy_tank", 330, 1000, FACTORY_EXIT],
		["harvester", 300, 1200, FACTORY_EXIT],
	]
	for case: Array in cases:
		var id: String = case[0]
		var ticks: int = case[1]
		var world: World = Rig.base()
		Rig.step(world, [Rig.queue(world, 1, id)])
		Rig.run(world, ticks - 2)
		var tab: int = world.type_tab[Worlds.type_of(world, id)]
		var queue: int = Rig.queue_of(1, tab)
		assert_array(Rig.rows_of(world, 1, id)).override_failure_message(id).is_empty()
		assert_int(world.queue_progress[queue]).override_failure_message(id).is_equal(
			(ticks - 1) * 100
		)
		Rig.step(world)
		var rows: Array[int] = Rig.rows_of(world, 1, id)
		assert_array(rows).override_failure_message(id + " rows").has_size(1)
		assert_vector(_at(world, rows[0])).override_failure_message(id).is_equal(case[3])
		assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([0, 0])
		assert_array([world.credits[1], world.stat_built[1]]).is_equal([2000 - case[2], 1])
		assert_int(world.owner[rows[0]]).is_equal(1)
		assert_int(world.hp[rows[0]]).is_equal(world.type_max_hp[world.type_index[rows[0]]])
		assert_int(world.tick).is_equal(ticks)


## The spawn is one SPAWNED record of the new unit, in the step that finished it and no other.
func test_a_spawn_writes_one_spawned_event_in_its_own_step() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	Rig.run(world, 73)
	assert_array(world.events).is_empty()
	Rig.step(world)
	var id: int = world.unit_id[world.unit_count() - 1]
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	assert_array(world.events).is_equal([World.Event.SPAWNED, id, 9500, 3500, rifle, 1, 0, 0])
	Rig.step(world)
	assert_array(world.events).is_empty()


## No carry: the item behind the head starts at 0 when the head is done, and each head needs its
## own ticks (75 for the rifle squad, then 150 for the rocket squad).
func test_the_next_item_starts_from_zero_and_takes_its_own_ticks() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "rocket_squad", 1)])
	var queue: int = Rig.queue_of(1, INFANTRY)
	Rig.run(world, 74)
	assert_int(Rig.rows_of(world, 1, "rifle_squad").size()).is_equal(1)
	assert_int(Rig.rows_of(world, 1, "rocket_squad").size()).is_equal(0)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 0])
	Rig.run(world, 5)
	assert_int(world.queue_progress[queue]).is_equal(500)
	Rig.run(world, 144)
	assert_int(Rig.rows_of(world, 1, "rocket_squad").size()).is_equal(0)
	Rig.step(world)
	assert_int(Rig.rows_of(world, 1, "rocket_squad").size()).is_equal(1)
	assert_array([world.queue_count[queue], world.stat_built[1], world.tick]).is_equal([0, 2, 225])


## Each tab and each player has its own queue and its own producer; one finishing leaves the
## others as they were.
func test_the_queues_of_the_tabs_and_the_players_run_side_by_side() -> void:
	var world: World = Rig.base()
	Rig.add_plant(world, 2, 2, 12)  # Player 2's barracks needs power to run at the normal rate.
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "light_tank", 1)])
	Rig.run(world, 9)
	Rig.step(world, [Rig.queue(world, 2, "rifle_squad")])
	Rig.run(world, 64)
	assert_int(world.tick).is_equal(75)
	assert_int(Rig.rows_of(world, 1, "rifle_squad").size()).is_equal(1)
	assert_int(Rig.rows_of(world, 2, "rifle_squad").size()).is_equal(0)
	assert_int(world.queue_progress[Rig.queue_of(1, VEHICLES)]).is_equal(7500)
	assert_int(world.queue_progress[Rig.queue_of(2, INFANTRY)]).is_equal(6500)
	Rig.run(world, 10)
	var enemy: Array[int] = Rig.rows_of(world, 2, "rifle_squad")
	assert_array(enemy).has_size(1)
	assert_vector(_at(world, enemy[0])).is_equal(Vector2i(9500, 14500))
	assert_array([world.stat_built[1], world.stat_built[2]]).is_equal([1, 1])
	assert_array([world.credits[1], world.credits[2]]).is_equal([2000 - 700, 1900])


## The primary producer of a tab is the player's lowest-id building that produces it (a second
## barracks adds no speed and no exit); when it dies the next one takes over with the progress kept.
func test_the_primary_producer_is_the_lowest_id_building_of_the_tab() -> void:
	var world: World = Rig.base()
	Rig.add_plant(world, 1, 20, 6)  # A second barracks would put player 1 on low power.
	var second: int = world.add_building(1, Worlds.type_of(world, "barracks"), 8, 6)
	assert_int(second).is_greater(Rig.ENEMY_BARRACKS)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "rifle_squad", 1)])
	Rig.run(world, 74)
	var first_rifle: Array[int] = Rig.rows_of(world, 1, "rifle_squad")
	assert_array(first_rifle).has_size(1)
	assert_vector(_at(world, first_rifle[0])).is_equal(BARRACKS_EXIT)
	Rig.run(world, 30)
	world.hp[world.index_of(Rig.BARRACKS)] = 0
	Rig.run(world, 44)
	assert_int(Rig.rows_of(world, 1, "rifle_squad").size()).is_equal(1)
	Rig.step(world)
	var rifles: Array[int] = Rig.rows_of(world, 1, "rifle_squad")
	assert_array(rifles).has_size(2)
	assert_vector(_at(world, rifles[1])).is_equal(Vector2i(9500, 8500))
	assert_int(world.tick).is_equal(150)


## A queue with no producer of its tab keeps its progress and its credits and gains nothing; a new
## producer lets it go on from where it was.
func test_a_queue_without_a_producer_waits_and_goes_on_with_a_new_one() -> void:
	var world: World = Rig.base()
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	Rig.run(world, 9)
	var queue: int = Rig.queue_of(1, INFANTRY)
	assert_int(world.queue_progress[queue]).is_equal(1000)
	world.hp[world.index_of(Rig.BARRACKS)] = 0
	Rig.run(world, 40)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 1000])
	assert_array([world.credits[1], world.unit_count()]).is_equal([1900, 4])
	world.add_building(1, Worlds.type_of(world, "barracks"), 4, 6)
	Rig.run(world, 64)
	assert_int(Rig.rows_of(world, 1, "rifle_squad").size()).is_equal(0)
	Rig.step(world)
	var rifles: Array[int] = Rig.rows_of(world, 1, "rifle_squad")
	assert_array(rifles).has_size(1)
	assert_vector(_at(world, rifles[0])).is_equal(Vector2i(5500, 8500))


## A harvester from a factory starts in SEEK with no home and no cargo and ignores the rally point;
## the other units start IDLE (ADR 0018 section 3, section 5).
func test_a_harvester_starts_in_seek_and_ignores_the_rally_point() -> void:
	var world: World = Rig.base()
	world.rally_x[Rig.queue_of(1, VEHICLES)] = 15500
	world.rally_y[Rig.queue_of(1, VEHICLES)] = 9500
	Rig.step(world, [Rig.queue(world, 1, "harvester")])
	Rig.run(world, 299)
	var harvesters: Array[int] = Rig.rows_of(world, 1, "harvester")
	assert_array(harvesters).has_size(1)
	var row: int = harvesters[0]
	var here: Vector2i = _at(world, row)
	assert_array([world.harvest_mode[row], world.cargo[row], world.harvest_slot[row]]).is_equal(
		[World.HarvestMode.SEEK, 0, -1]
	)
	assert_int(world.home[row]).is_equal(0)
	assert_int(world.order[row]).is_equal(World.Order.IDLE)
	assert_array([world.goal_x[row], world.goal_y[row]]).is_equal([here.x, here.y])
	assert_int(world.group_cell[row]).is_equal(-1)
	for other: int in world.unit_count():
		if other != row:
			assert_int(world.harvest_mode[other]).is_equal(World.HarvestMode.IDLE)


## The rally point of the tab sends the new unit away by a one-unit MOVE: an open point is the goal
## itself, a point on rock the centre of the first open tile of the ring around it (row by row from
## the top-left tile, Formation's rule), and the unit then walks. The other tab's point and the
## other player's do not apply.
func test_a_new_unit_goes_to_the_rally_point_by_the_rule_of_a_one_unit_move() -> void:
	var world: World = Rig.base([Vector2i(15, 9)])
	Rig.add_plant(world, 2, 2, 12)
	world.rally_x[Rig.queue_of(1, INFANTRY)] = 15500
	world.rally_y[Rig.queue_of(1, INFANTRY)] = 9500
	world.rally_x[Rig.queue_of(1, VEHICLES)] = 20500
	world.rally_y[Rig.queue_of(1, VEHICLES)] = 12500
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 2, "rifle_squad", 0)])
	Rig.run(world, 74)
	var rifles: Array[int] = Rig.rows_of(world, 1, "rifle_squad")
	assert_array(rifles).has_size(1)
	var row: int = rifles[0]
	assert_int(world.order[row]).is_equal(World.Order.MOVE)
	assert_int(world.nav_mode[row]).is_equal(World.NavMode.DIRECT)
	assert_array([world.goal_x[row], world.goal_y[row]]).is_equal([14500, 8500])
	assert_int(world.group_cell[row]).is_equal(8 * Rig.COLS + 14)
	assert_array([world.nav_cell[row], world.field[row], world.nav_next[row]]).is_equal(
		[-1, -1, -1]
	)
	var spawned: Vector2i = _at(world, row)
	var other: Array[int] = Rig.rows_of(world, 2, "rifle_squad")
	assert_array(other).has_size(1)
	assert_int(world.order[other[0]]).is_equal(World.Order.IDLE)
	Rig.run(world, 20)
	assert_int(_at(world, row).x).is_greater(spawned.x)
	assert_int(_at(world, row).y).is_greater(spawned.y)


func test_an_open_rally_point_is_the_goal_and_an_empty_one_leaves_the_unit_idle() -> void:
	var world: World = Rig.base()
	world.rally_x[Rig.queue_of(1, INFANTRY)] = 15500
	world.rally_y[Rig.queue_of(1, INFANTRY)] = 9500
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "light_tank", 1)])
	Rig.run(world, 74)
	var rifle: int = Rig.rows_of(world, 1, "rifle_squad")[0]
	assert_array([world.goal_x[rifle], world.goal_y[rifle]]).is_equal([15500, 9500])
	assert_int(world.group_cell[rifle]).is_equal(9 * Rig.COLS + 15)
	# The light tank is not done yet; when it is, its tab has no point and it stays where it is.
	Rig.run(world, 150)
	var tank: int = Rig.rows_of(world, 1, "light_tank")[0]
	assert_int(world.order[tank]).is_equal(World.Order.IDLE)
	assert_array([world.goal_x[tank], world.goal_y[tank]]).is_equal(
		[_at(world, tank).x, _at(world, tank).y]
	)
	assert_int(world.group_cell[tank]).is_equal(-1)


## A structure's head gains progress like a unit's and stops at 100 % (plan row P73b, ADR 0018
## section 5): nothing spawns, nothing is paid again, the queue keeps it and the item behind it
## does not start. Ticks and costs are the World's tables'.
func test_a_finished_structure_waits_ready_at_the_head_of_the_structures_queue() -> void:
	var world: World = Rig.base()
	Rig.add_headquarters(world)
	var plant: int = Worlds.type_of(world, "power_plant")
	var barracks: int = Worlds.type_of(world, "barracks")
	var queue: int = Rig.queue_of(1, World.Tab.STRUCTURES)
	var goal: int = world.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	var rows: int = world.unit_count()
	Rig.step(world, [Rig.queue(world, 1, "power_plant"), Rig.queue(world, 1, "barracks", 1)])
	var paid: int = world.start_credits - world.type_cost[plant] - world.type_cost[barracks]
	Rig.run(world, world.type_build_ticks[plant] - 2)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([2, goal - 100])
	Rig.step(world)
	assert_int(world.queue_progress[queue]).is_equal(goal)
	Rig.run(world, 200)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([2, goal])
	assert_array(Rig.items(world, 1, World.Tab.STRUCTURES)).is_equal([plant, barracks])
	assert_array([world.credits[1], world.unit_count(), world.stat_built[1]]).is_equal(
		[paid, rows, 0]
	)
	# Other tabs and the other player's queue are not held by it.
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_int(world.queue_progress[Rig.queue_of(1, INFANTRY)]).is_equal(100)


## Without a producer of the tab the STRUCTURES queue waits like the others, and goes on from where
## it was when a headquarters is there again.
func test_a_structures_queue_without_a_headquarters_waits_and_goes_on_with_a_new_one() -> void:
	var world: World = Rig.base()
	var headquarters: int = Rig.add_headquarters(world)
	var queue: int = Rig.queue_of(1, World.Tab.STRUCTURES)
	Rig.step(world, [Rig.queue(world, 1, "power_plant")])
	Rig.run(world, 9)
	assert_int(world.queue_progress[queue]).is_equal(1000)
	world.hp[world.index_of(headquarters)] = 0
	Rig.run(world, 40)
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, 1000])
	world.add_building(1, Worlds.type_of(world, "headquarters"), 2, 9)
	Rig.step(world)
	assert_int(world.queue_progress[queue]).is_equal(1100)


## The same commands on the same data give the same checkpoints and the same units, and a world
## that was not given the commands differs (MatchLoop is the tick driver of a replay).
func test_production_is_deterministic_over_a_replay_style_run() -> void:
	var hashes: Array[PackedInt64Array] = []
	var finals: Array[PackedInt32Array] = []
	for _attempt: int in 2:
		var world: World = Rig.base()
		var loop: MatchLoop = MatchLoop.create(null, "", 1, world)
		for tick: int in 400:
			var commands: Array[Command] = []
			if tick == 0:
				commands.append(Rig.queue(world, 1, "rifle_squad", 0))
				commands.append(Rig.queue(world, 1, "rocket_squad", 1))
				commands.append(Rig.queue(world, 1, "light_tank", 2))
			elif tick == 5:
				commands.append(Rig.queue(world, 2, "rifle_squad", 0))
			elif tick == 40:
				commands.append(Command.cancel(1, INFANTRY, 1))
			loop.step(world, commands)
		hashes.append(loop.replay.checkpoint_hashes)
		finals.append(world.unit_id)
	assert_int(hashes[0].size()).is_equal(26)
	assert_array(hashes[0]).is_equal(hashes[1])
	assert_array(finals[0]).is_equal(finals[1])
	assert_int(finals[0].size()).is_equal(5 + 3)
	var idle: World = Rig.base()
	var loop: MatchLoop = MatchLoop.create(null, "", 1, idle)
	for _tick: int in 400:
		loop.step(idle, [])
	assert_array(loop.replay.checkpoint_hashes).is_not_equal(hashes[0])
