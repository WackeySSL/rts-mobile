extends GdUnitTestSuite
## The harvest loop (plan row P75, ADR 0018 section 3): one harvester's trip from SEEK to its
## credits takes the ticks the rules give, and the loop takes its steps on the cadences the rules
## name. The ticks in the comments are the value of `world.tick` during the `Sim.step` that makes
## the change (the step counts up from 0), with the shipped rules (`data/rules.tres`): a look every
## 15 ticks, one ore unit per 3, one unload per tick, reach 1 200 and dock reach 1 500.

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")

const SEEK: int = World.HarvestMode.SEEK
const MINE: int = World.HarvestMode.MINE
const RETURN: int = World.HarvestMode.RETURN
const UNLOAD: int = World.HarvestMode.UNLOAD
## The ore cell of the trip map, and the dock of its refinery: straight south, 2 000 milli apart.
const ORE_AT: Vector2i = Vector2i(3500, 7500)
const DOCK_AT: Vector2i = Vector2i(3500, 5500)


## 12 x 10 tiles with one ore cell at (3, 7) and a refinery (player 1, id 1) whose footprint is the
## tiles 2..4 x 2..4: its dock is the tile (3, 5), centre (3 500, 5 500).
func _trip_world(ore_units: int = 20) -> World:
	var world: World = Worlds.world(Worlds.grass(12, 10, [Vector2i(3, 7)]))
	Worlds.add_refinery(world, 1, 2, 2)
	world.ore_amount[0] = ore_units
	return world


## Runs `ticks` steps and lists each change of harvester `id`'s mode as [tick, mode].
func _changes(world: World, id: int, ticks: int) -> Array[Array]:
	var found: Array[Array] = []
	var mode: int = Worlds.mode_of(world, id)
	for tick: int in ticks:
		Worlds.step(world)
		if Worlds.mode_of(world, id) != mode:
			mode = Worlds.mode_of(world, id)
			found.append([tick, mode])
	return found


func test_a_full_trip_takes_the_ticks_the_rules_give_and_adds_500_credits() -> void:
	var world: World = _trip_world()
	var id: int = Worlds.add_harvester(world, 1, ORE_AT.x, ORE_AT.y, SEEK, -1, 1)
	var type: int = world.type_index[world.index_of(id)]
	var units: int = world.type_harvest[type] / world.credits_per_ore  # 20 units fill the hold
	# No cell yet: the first look is on the tick of the harvester's turn, and it stands in reach of
	# the cell, so it gets no order. The next tick it turns to MINE.
	var look: int = Worlds.turn(0, id, world.harvest_retry_ticks)
	var mining: int = look + 1
	# MINE takes a unit on each of its turns; the 20th fills the hold.
	var first: int = Worlds.turn(mining + 1, id, world.harvest_ticks_per_ore)
	var full: int = first + (units - 1) * world.harvest_ticks_per_ore
	# The tick after, RETURN gives the order to the dock; the trip is 2 000 at the type's speed, and
	# INTEGRATE ends the order on the tick its goal is within one step, so ECONOMY sees it that tick.
	var steps: int = (ORE_AT.y - DOCK_AT.y + world.type_speed[type] - 1) / world.type_speed[type]
	var docked: int = full + 1 + steps
	# UNLOAD pays on each of its turns, from the tick after; the 20th payment empties the hold.
	var unloaded: int = Worlds.turn(docked + 1, id, world.unload_ticks_per_ore)
	unloaded += (units - 1) * world.unload_ticks_per_ore
	var changes: Array[Array] = _changes(world, id, unloaded + 1)
	assert_array(changes).is_equal(
		[[mining, MINE], [full, RETURN], [docked, UNLOAD], [unloaded, SEEK]]
	)
	assert_array([world.credits[1], world.stat_harvested[1]]).is_equal([2500, 500])
	assert_array([world.credits[2], world.stat_harvested[2]]).is_equal([2000, 0])
	assert_array([Worlds.cargo_of(world, id), world.ore_amount[0]]).is_equal([0, 0])
	assert_array([world.pos_x[world.index_of(id)], world.pos_y[world.index_of(id)]]).is_equal(
		[DOCK_AT.x, DOCK_AT.y]
	)


func test_the_cargo_and_the_credits_move_on_the_ticks_of_the_loop_not_before() -> void:
	var world: World = _trip_world()
	var id: int = Worlds.add_harvester(world, 1, ORE_AT.x, ORE_AT.y, MINE, 0, 1)
	var period: int = world.harvest_ticks_per_ore
	var value: int = world.credits_per_ore
	var taken: int = 0
	for tick: int in 12:
		Worlds.step(world)
		if (tick + id) % period == 0:
			taken += 1
		(
			assert_array([Worlds.cargo_of(world, id), world.ore_amount[0]])
			. override_failure_message("tick %d" % tick)
			. is_equal([taken * value, 20 - taken])
		)
	assert_int(world.credits[1]).is_equal(2000)  # Mining pays nothing; only unloading does.


func test_a_harvester_that_unloads_pays_its_own_player_credits_per_ore_each_tick() -> void:
	var world: World = _trip_world()
	var refinery: int = Worlds.add_refinery(world, 2, 7, 2)
	var id: int = Worlds.add_harvester(world, 2, 8500, 5500, UNLOAD, 0, refinery, 100)
	var value: int = world.credits_per_ore
	for step: int in 4:
		Worlds.step(world)
		(
			assert_array([world.credits[2], world.stat_harvested[2], Worlds.cargo_of(world, id)])
			. is_equal([2000 + (step + 1) * value, (step + 1) * value, 100 - (step + 1) * value])
		)
	assert_array([world.credits[1], world.stat_harvested[1]]).is_equal([2000, 0])
	assert_int(Worlds.mode_of(world, id)).is_equal(SEEK)  # The 4th payment emptied the hold.


func test_an_odd_hold_pays_what_is_left_on_its_last_turn() -> void:
	var world: World = _trip_world()
	var id: int = Worlds.add_harvester(world, 1, DOCK_AT.x, DOCK_AT.y, UNLOAD, 0, 1, 60)
	var paid: Array[int] = []
	for _tick: int in 3:
		var before: int = world.credits[1]
		Worlds.step(world)
		paid.append(world.credits[1] - before)
	assert_array(paid).is_equal([25, 25, 10])
	assert_array([Worlds.cargo_of(world, id), world.stat_harvested[1]]).is_equal([0, 60])
	assert_int(Worlds.mode_of(world, id)).is_equal(SEEK)


func test_mining_starts_exactly_within_the_reach_of_the_cell_and_not_a_milli_beyond() -> void:
	var cases: Array[Array] = [[0, MINE, 0], [1, SEEK, -1]]  # Beyond reach, the lone cell is skipped.
	for case: Array in cases:
		var world: World = _trip_world()
		var x: int = ORE_AT.x + world.harvest_reach_milli + case[0]
		var id: int = Worlds.add_harvester(world, 1, x, ORE_AT.y, SEEK, 0, 1)
		Worlds.step(world)
		assert_array([Worlds.mode_of(world, id), world.harvest_slot[world.index_of(id)]]).is_equal(
			[case[1], case[2]]
		)


func test_a_harvester_back_from_unloading_returns_to_its_cell_while_it_has_ore() -> void:
	var world: World = _trip_world(40)  # Two trips' worth.
	world.ore_cell_max = 0  # No regrowth on tick 150.
	var id: int = Worlds.add_harvester(world, 1, DOCK_AT.x, DOCK_AT.y, UNLOAD, 0, 1, 25)
	Worlds.step(world)  # The one unit pays and empties the hold.
	var row: int = world.index_of(id)
	assert_array([Worlds.mode_of(world, id), world.harvest_slot[row]]).is_equal([SEEK, 0])
	# The order to the cell's centre is given in the same step, so SEEK reads it as under way.
	assert_array([world.order[row], world.goal_x[row], world.goal_y[row]]).is_equal(
		[World.Order.MOVE, ORE_AT.x, ORE_AT.y]
	)
	assert_int(world.nav_mode[row]).is_equal(World.NavMode.DIRECT)
	assert_int(world.group_cell[row]).is_equal(-1)
	# It mines the 20 units that its cell has for the first trip, unloads them, and heads back for
	# the 20 that are left, with no look in between (the cell still has ore).
	var guard: int = 300
	while world.stat_harvested[1] < 25 + 500 and guard > 0:
		Worlds.step(world)
		guard -= 1
	assert_array([world.ore_amount[0], world.credits[1]]).is_equal([20, 2000 + 25 + 500])
	assert_array([Worlds.mode_of(world, id), world.order[row]]).is_equal([SEEK, World.Order.MOVE])
	Worlds.step(world, 200)
	assert_array([world.ore_amount[0], world.stat_harvested[1]]).is_equal([0, 25 + 1000])
	assert_int(world.credits[1]).is_equal(2000 + 25 + 1000)


func test_a_cell_that_runs_empty_sends_the_harvester_on_with_its_cargo_to_the_next_cell() -> void:
	var rows: Array[String] = Worlds.grass(12, 10, [Vector2i(3, 7), Vector2i(8, 7)])
	var world: World = Worlds.world(rows)
	Worlds.add_refinery(world, 1, 2, 2)
	world.ore_cell_max = 0
	world.ore_amount[0] = 2
	var id: int = Worlds.add_harvester(world, 1, ORE_AT.x, ORE_AT.y, MINE, 0, 1)
	var seen: Array[int] = []
	for _tick: int in 100:
		Worlds.step(world)
		if seen.is_empty() or seen[-1] != Worlds.mode_of(world, id):
			seen.append(Worlds.mode_of(world, id))
	# MINE emptied cell 0 after 2 units, SEEK took cell 1 with the 50 credits still on board, and
	# the harvester walked the 5 tiles to it and mines there.
	assert_array(seen).is_equal([MINE, SEEK, MINE])
	var row: int = world.index_of(id)
	assert_int(world.harvest_slot[row]).is_equal(1)
	assert_bool(Worlds.cargo_of(world, id) > 50).is_true()
	assert_int(world.ore_amount[0]).is_equal(0)
	assert_int(world.ore_amount[1]).is_equal(20 - (Worlds.cargo_of(world, id) - 50) / 25)


func test_a_full_load_goes_home_before_more_ore() -> void:
	var world: World = _trip_world()
	var id: int = Worlds.add_harvester(world, 1, ORE_AT.x, ORE_AT.y, SEEK, 0, 1, 500)
	Worlds.step(world)
	assert_int(Worlds.mode_of(world, id)).is_equal(RETURN)
	assert_int(world.ore_amount[0]).is_equal(20)


func test_a_harvester_far_from_its_cell_walks_there_before_it_mines() -> void:
	var world: World = _trip_world()
	var id: int = Worlds.add_harvester(world, 1, ORE_AT.x + 4000, ORE_AT.y)  # SEEK, no cell yet.
	var row: int = world.index_of(id)
	var look: int = Worlds.turn(0, id, world.harvest_retry_ticks)
	Worlds.step(world, look + 1)
	# The look picked the cell and gave the order, the same step.
	assert_int(world.harvest_slot[row]).is_equal(0)
	assert_array([world.order[row], world.goal_x[row], world.goal_y[row]]).is_equal(
		[World.Order.MOVE, ORE_AT.x, ORE_AT.y]
	)
	var arrived: int = -1
	for tick: int in 120:
		Worlds.step(world)
		if arrived < 0 and Worlds.mode_of(world, id) == MINE:
			arrived = look + 1 + tick
			assert_array([world.pos_x[row], world.order[row]]).is_equal(
				[ORE_AT.x, World.Order.IDLE]
			)
	# 4 000 milli at the type's speed: the walk ends on the tick of the last step, MINE the same tick.
	var speed: int = world.type_speed[world.type_index[row]]
	assert_int(arrived).is_equal(look + (4000 + speed - 1) / speed)


func test_the_trip_is_the_same_state_in_both_implementations() -> void:
	var hashes: Array[int] = []
	var credits: Array[int] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = _trip_world()
		Worlds.add_harvester(world, 1, ORE_AT.x, ORE_AT.y, SEEK, -1, 1)
		assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
		Worlds.step(world, 140)
		hashes.append(world.state_hash())
		credits.append(world.credits[1])
	assert_array(credits).is_equal([2500, 2500])
	assert_int(hashes[1]).is_equal(hashes[0])


func test_a_harvester_that_a_scenario_spawns_starts_in_seek_with_no_home() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(10, 6)
	scenario.player_count = 2
	for id: String in ["harvester", "rifle_squad"]:
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.count = 2
		spawn.unit = load(Worlds.UNIT_DIR + id + ".tres") as UnitDef
		spawn.origin_tile = Vector2i(1, 1 if id == "harvester" else 3)
		scenario.spawns.append(spawn)
	var world: World = World.from_scenario(scenario)
	var modes: Array[int] = []
	modes.assign(world.harvest_mode)
	assert_array(modes).is_equal([SEEK, SEEK, World.HarvestMode.IDLE, World.HarvestMode.IDLE])
	assert_array(world.harvest_slot).is_equal([-1, -1, -1, -1])
	assert_array(world.home).is_equal([0, 0, 0, 0])
	assert_array(world.cargo).is_equal([0, 0, 0, 0])
