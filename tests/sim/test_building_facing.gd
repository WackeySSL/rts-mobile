extends GdUnitTestSuite
## Docks and exits face the map centre (plan row P195c-1, ADR 0033 sections 1, 2 and 6): the facing
## is a pure function of a building's position and the map size, `turned` turns the data's south
## offsets with it, and the four places that read a dock or an exit (`ProductionSpawn.spawn`,
## `exit_tile`, `spawn_free` and `Harvest._dock`) use the turned tile.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const HWorlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")
const RosterCells: GDScript = preload("res://tests/sim/support/roster_cells.gd")

const SOUTH: int = Buildings.Facing.SOUTH
const WEST: int = Buildings.Facing.WEST
const NORTH: int = Buildings.Facing.NORTH
const EAST: int = Buildings.Facing.EAST
const SIDE: int = 20
## Origins of 3x3 buildings on the 20 x 20 map, one on each side of the centre and each well off
## the diagonals: top, right, bottom, left, and the facing each one has.
const SITES: Array[Array] = [
	[Vector2i(8, 2), SOUTH],
	[Vector2i(15, 8), WEST],
	[Vector2i(8, 15), NORTH],
	[Vector2i(2, 8), EAST],
]
## The data offset (1, 3) of a 3x3 building turned to each facing, and (1, 2) of a 2x2 one.
const TURNED_3: Array[Vector2i] = [Vector2i(1, 3), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(3, 1)]
const TURNED_2: Array[Vector2i] = [Vector2i(1, 2), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(2, 0)]


func test_the_facing_is_the_side_nearest_to_the_map_centre() -> void:
	assert_int(Buildings.facing(64, 64, 32000, 10000)).is_equal(SOUTH)
	assert_int(Buildings.facing(64, 64, 54000, 32000)).is_equal(WEST)
	assert_int(Buildings.facing(64, 64, 32000, 54000)).is_equal(NORTH)
	assert_int(Buildings.facing(64, 64, 10000, 32000)).is_equal(EAST)
	# A wide map: the larger distance to the centre picks the axis.
	assert_int(Buildings.facing(64, 40, 12000, 14000)).is_equal(EAST)
	assert_int(Buildings.facing(64, 40, 30000, 3000)).is_equal(SOUTH)


## A diagonal tie takes the side one quarter turn clockwise from the diagonal (y grows down).
func test_a_diagonal_tie_and_the_exact_centre_have_their_sides() -> void:
	assert_int(Buildings.facing(64, 64, 10000, 10000)).is_equal(SOUTH)
	assert_int(Buildings.facing(64, 64, 54000, 10000)).is_equal(WEST)
	assert_int(Buildings.facing(64, 64, 54000, 54000)).is_equal(NORTH)
	assert_int(Buildings.facing(64, 64, 10000, 54000)).is_equal(EAST)
	assert_int(Buildings.facing(64, 64, 32000, 32000)).is_equal(SOUTH)
	# Half a tile off the centre on one axis only is not a tie.
	assert_int(Buildings.facing(64, 64, 32500, 32000)).is_equal(WEST)


## A quarter turn of a square map turns the facing by one quarter turn, a half turn of any map by
## two, ties included, for every footprint centre of 2x2 and 3x3 buildings.
func test_the_facing_turns_with_the_building_on_every_site() -> void:
	for cols: int in [64, 63]:
		for wide: int in [2, 3]:
			for col: int in cols - wide + 1:
				for line: int in cols - wide + 1:
					var x: int = col * 1000 + wide * 500
					var y: int = line * 1000 + wide * 500
					if x * 2 == cols * 1000 and y * 2 == cols * 1000:
						continue  # The exact centre of the map is its own turn: SOUTH at any turn.
					var at: int = Buildings.facing(cols, cols, x, y)
					var label: String = "%d %d %d" % [cols, x, y]
					(
						assert_int(Buildings.facing(cols, cols, cols * 1000 - y, x))
						. override_failure_message(label)
						. is_equal((at + 1) % 4)
					)
					(
						assert_int(Buildings.facing(cols, cols, cols * 1000 - x, cols * 1000 - y))
						. override_failure_message(label)
						. is_equal((at + 2) % 4)
					)
	for col: int in 62:
		for line: int in 38:
			var x: int = col * 1000 + 1500
			var y: int = line * 1000 + 1500
			var turned: int = Buildings.facing(64, 40, 64000 - x, 40000 - y)
			assert_int(turned).is_equal((Buildings.facing(64, 40, x, y) + 2) % 4)


## The exact centre is its own half turn and quarter turn, so it is SOUTH whatever the turn: the
## one point where the equivariance above does not hold (the skip in that case), on any map.
func test_the_exact_centre_is_south_on_square_and_wide_maps() -> void:
	assert_int(Buildings.facing(64, 64, 32000, 32000)).is_equal(SOUTH)
	assert_int(Buildings.facing(63, 63, 31500, 31500)).is_equal(SOUTH)
	assert_int(Buildings.facing(64, 40, 32000, 20000)).is_equal(SOUTH)
	assert_int(Buildings.facing(64, 40, 64000 - 32000, 40000 - 20000)).is_equal(SOUTH)


func test_turned_gives_the_table_and_four_turns_are_the_identity() -> void:
	for facing: int in 4:
		assert_that(Buildings.turned(Vector2i(1, 3), 3, facing)).is_equal(TURNED_3[facing])
		assert_that(Buildings.turned(Vector2i(1, 2), 2, facing)).is_equal(TURNED_2[facing])
	assert_that(Buildings.turned(Vector2i(1, 3), 3, 4)).is_equal(Vector2i(1, 3))
	var offset: Vector2i = Vector2i(2, -1)
	var around: Vector2i = offset
	for _turn: int in 4:
		around = Buildings.turned(around, 3, 1)
	assert_that(around).is_equal(offset)


## Every shipped type with a dock or an exit has a square footprint and its offset on the ring
## around it, and the offset stays on the ring at every facing. The world holds the types of both
## factions in the cross scenario.
func test_every_shipped_dock_and_exit_is_on_the_ring_of_a_square_footprint() -> void:
	var world: World = SmokeRun.world_of(1, SmokeRun.FLATS_MIRRORED)
	var checked: int = 0
	for type: int in world.type_ids.size():
		var width: int = world.type_foot_w[type]
		if width <= 0:
			continue
		var offsets: Array[Vector2i] = []
		if world.type_dock_x[type] != 0 or world.type_dock_y[type] != 0:
			offsets.append(Vector2i(world.type_dock_x[type], world.type_dock_y[type]))
		if world.type_produces[type] >= World.Tab.INFANTRY:
			offsets.append(Vector2i(world.type_exit_x[type], world.type_exit_y[type]))
		for offset: Vector2i in offsets:
			var label: String = "%s %s" % [world.type_names[type], offset]
			assert_int(world.type_foot_h[type]).override_failure_message(label).is_equal(width)
			for facing: int in 4:
				var turned: Vector2i = Buildings.turned(offset, width, facing)
				assert_bool(RosterCells.touches_footprint(Vector2i(width, width), turned)).is_true()
			checked += 1
	assert_int(checked).is_greater(4)


## A factory on each side of the centre makes its first unit on the turned exit tile.
func test_a_factory_in_each_quadrant_spawns_its_first_unit_on_the_turned_exit() -> void:
	for site: Array in SITES:
		var origin: Vector2i = site[0]
		var world: World = _square()
		var factory: int = world.index_of(
			world.add_building(1, _type(world, "vehicle_factory"), origin.x, origin.y)
		)
		assert_that(Buildings.turned_at(world, factory, Vector2i(1, 3))).is_equal(TURNED_3[site[1]])
		assert_bool(ProductionSpawn.spawn(world, 1, _type(world, "light_tank"), factory)).is_true()
		var tile: Vector2i = origin + TURNED_3[site[1]]
		assert_array(_last_tile(world)).override_failure_message(str(site)).is_equal(
			[tile.x, tile.y]
		)
		assert_array([world.stats[World.Stat.EXIT_SCANNED]]).is_equal([1])
		assert_that(ProductionSpawn.exit_tile(world, factory, World.MoveClass.TRACKED)).is_equal(
			tile
		)


## A closed turned exit hands the unit to the next ring tile clockwise from it, counted by
## `EXIT_SCANNED`: down the right column for the east side, along the top row for the north one.
func test_a_closed_turned_exit_walks_clockwise_from_the_turned_tile() -> void:
	var cases: Array[Array] = [
		[Vector2i(2, 8), Vector2i(5, 9), Vector2i(5, 10)],
		[Vector2i(8, 15), Vector2i(9, 14), Vector2i(10, 14)],
	]
	for case: Array in cases:
		var world: World = _square()
		var blocked: Vector2i = case[1]
		world.set_terrain(blocked.y * SIDE + blocked.x, 2)  # '#' of GridWorld.GROUND.
		var factory: int = world.index_of(
			world.add_building(1, _type(world, "vehicle_factory"), case[0].x, case[0].y)
		)
		assert_bool(ProductionSpawn.spawn(world, 1, _type(world, "light_tank"), factory)).is_true()
		assert_array(_last_tile(world)).override_failure_message(str(case)).is_equal(
			[case[2].x, case[2].y]
		)
		assert_int(world.stats[World.Stat.EXIT_SCANNED]).is_equal(2)


## The free harvester of a refinery appears at the turned dock, with `home` set.
func test_the_free_harvester_appears_at_the_turned_dock() -> void:
	for site: Array in SITES:
		var origin: Vector2i = site[0]
		var world: World = _square()
		var refinery: int = world.index_of(
			world.add_building(1, _type(world, "refinery"), origin.x, origin.y)
		)
		assert_bool(ProductionSpawn.spawn_free(world, refinery)).is_true()
		var tile: Vector2i = origin + TURNED_3[site[1]]
		assert_array(_last_tile(world)).override_failure_message(str(site)).is_equal(
			[tile.x, tile.y]
		)


## SEEK's full load (`_go_home`), RETURN's choice (`_choose`) and RETURN's reach check (`run`) all
## use the turned dock: a refinery on each side, a harvester with a full load, the order goes to
## the dock tile's centre, and a harvester standing there starts to unload.
func test_the_harvest_loop_orders_and_unloads_at_the_turned_dock() -> void:
	for site: Array in SITES:
		var origin: Vector2i = site[0]
		var dock: Vector2i = (origin + TURNED_3[site[1]]) * 1000 + Vector2i(500, 500)
		var far: Vector2i = Vector2i(500, 500) if site[1] != EAST else Vector2i(19500, 19500)
		# SEEK with a full load and a home: `_go_home`.
		var world: World = _harvest_square()
		var refinery: int = HWorlds.add_refinery(world, 1, origin.x, origin.y)
		var seeker: int = HWorlds.add_harvester(
			world, 1, far.x, far.y, World.HarvestMode.SEEK, 0, refinery, 500
		)
		HWorlds.step(world)
		var row: int = world.index_of(seeker)
		assert_int(world.harvest_mode[row]).is_equal(World.HarvestMode.RETURN)
		(
			assert_array([world.goal_x[row], world.goal_y[row]])
			. override_failure_message(str(site))
			. is_equal([dock.x, dock.y])
		)
		# RETURN with no home: `_choose`.
		world = _harvest_square()
		HWorlds.add_refinery(world, 1, origin.x, origin.y)
		var chooser: int = HWorlds.add_harvester(
			world, 1, far.x, far.y, World.HarvestMode.RETURN, 0, 0, 500
		)
		HWorlds.step(world, HWorlds.turn(0, chooser, world.harvest_retry_ticks) + 1)  # Its turn.
		row = world.index_of(chooser)
		(
			assert_array([world.goal_x[row], world.goal_y[row]])
			. override_failure_message(str(site))
			. is_equal([dock.x, dock.y])
		)
		# RETURN standing on the turned dock: within reach, so it unloads at once.
		world = _harvest_square()
		refinery = HWorlds.add_refinery(world, 1, origin.x, origin.y)
		var docked: int = HWorlds.add_harvester(
			world, 1, dock.x, dock.y, World.HarvestMode.RETURN, 0, refinery, 500
		)
		HWorlds.step(world)
		(
			assert_int(world.harvest_mode[world.index_of(docked)])
			. override_failure_message(str(site))
			. is_equal(World.HarvestMode.UNLOAD)
		)


## A whole trip to an east-facing refinery: the 22 x 10 map makes the refinery at (2, 2) face east,
## its dock the tile (5, 3); the ore lies 4 tiles beyond it. The tanker mines, drives to that dock,
## unloads there (500 credits) and goes back to the ore.
func test_a_full_trip_to_an_east_facing_refinery_pays_and_returns_to_ore() -> void:
	var world: World = HWorlds.world(HWorlds.grass(22, 10, [Vector2i(9, 3)]))
	var refinery: int = HWorlds.add_refinery(world, 1, 2, 2)
	world.ore_amount[0] = 20
	var ore: Vector2i = Vector2i(9500, 3500)
	var dock: Vector2i = Vector2i(5500, 3500)
	assert_int(Buildings.facing(22, 10, 3500, 3500)).is_equal(EAST)
	var id: int = HWorlds.add_harvester(
		world, 1, ore.x, ore.y, World.HarvestMode.SEEK, -1, refinery
	)
	var row: int = world.index_of(id)
	var docked: bool = false
	for _tick: int in 900:
		HWorlds.step(world)
		if HWorlds.mode_of(world, id) == World.HarvestMode.UNLOAD and not docked:
			docked = true
			assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([dock.x, dock.y])
	assert_bool(docked).is_true()
	assert_array([world.credits[1], world.stat_harvested[1]]).is_equal([2500, 500])
	# After the unload it is back at the cell, SEEK or MINE, within the harvest reach of it.
	(
		assert_bool(
			[World.HarvestMode.SEEK, World.HarvestMode.MINE].has(HWorlds.mode_of(world, id))
		)
		. is_true()
	)
	var dx: int = world.pos_x[row] - ore.x
	var dy: int = world.pos_y[row] - ore.y
	assert_int(dx * dx + dy * dy).is_less_equal(
		world.harvest_reach_milli * world.harvest_reach_milli
	)


## The home refinery dies: the tanker picks another one, at another facing, and its order goes to
## that one's turned dock. The first refinery faces south, the second east.
func test_a_new_home_after_the_old_one_dies_uses_its_own_turned_dock() -> void:
	var world: World = _harvest_square()
	var first: int = HWorlds.add_refinery(world, 1, 8, 2)
	HWorlds.add_refinery(world, 1, 2, 8)
	var id: int = HWorlds.add_harvester(
		world, 1, 12500, 12500, World.HarvestMode.RETURN, 0, first, 500
	)
	world.hp[world.index_of(first)] = 0
	HWorlds.step(world, world.harvest_retry_ticks + 2)
	var row: int = world.index_of(id)  # The dead refinery's row is gone: look the row up again.
	var second_id: int = world.home[row]
	assert_int(second_id).is_not_equal(first)
	assert_int(second_id).is_not_equal(0)
	assert_array([world.goal_x[row], world.goal_y[row]]).is_equal([5500, 9500])


## A 2x2 barracks on the east side and one on the north side each make a squad on their turned
## exit, (1, 2) turned to (2, 0) and to (0, -1): through the queue and the production phase.
func test_a_barracks_on_a_non_south_side_makes_its_squad_on_the_turned_exit() -> void:
	for site: Array in [[Vector2i(2, 9), Vector2i(4, 9)], [Vector2i(9, 16), Vector2i(9, 15)]]:
		var world: World = _square()
		world.add_building(1, _type(world, "barracks"), site[0].x, site[0].y)
		Rig.add_plant(world, 1, 16, 2)
		Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
		Rig.run(world, 80)
		var rifles: Array[int] = Rig.rows_of(world, 1, "rifle_squad")
		assert_array(rifles).override_failure_message(str(site)).has_size(1)
		var tile: Vector2i = site[1]
		assert_array([world.pos_x[rifles[0]], world.pos_y[rifles[0]]]).is_equal(
			[tile.x * 1000 + 500, tile.y * 1000 + 500]
		)


func _square() -> World:
	return Worlds.world(GridWorld.grass(SIDE, SIDE), Rig.IDS)


func _harvest_square() -> World:
	return HWorlds.world(HWorlds.grass(SIDE, SIDE, [Vector2i(10, 10)]))


func _type(world: World, id: String) -> int:
	return Worlds.type_of(world, id)


## The tile (x, y) of the newest row, as a two-element array of tile coordinates.
@warning_ignore("integer_division")
func _last_tile(world: World) -> Array[int]:
	var row: int = world.unit_id.size() - 1
	return [world.pos_x[row] / 1000, world.pos_y[row] / 1000]
