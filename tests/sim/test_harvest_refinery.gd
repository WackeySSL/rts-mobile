extends GdUnitTestSuite
## The refinery choice and the dock of the harvest loop (plan row P75, ADR 0018 section 3): RETURN
## takes `home` while that refinery exists, else the nearest own refinery (then the lowest id); a
## destroyed refinery sends the harvester to the next one, or it waits; the order goes to the dock
## and UNLOAD starts within `dock_reach_milli` of it. Hand-built worlds: the refineries come from
## `Buildings.add` and the harvesters from `add_unit`.
##
## The map is 20 x 12 grass. Refinery A (player 1, id 1) has the tiles 2..4 x 2..4 (centre
## (3 500, 3 500), dock (3 500, 5 500)), B (player 1, id 2) the tiles 12..14 x 2..4 (centre
## (13 500, 3 500), dock (13 500, 5 500)) and C (player 2, id 3) the tiles 8..10 x 7..9 (centre
## (9 500, 8 500), dock (9 500, 10 500)). The harvesters come after them, from id 4.

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")

const SEEK: int = World.HarvestMode.SEEK
const RETURN: int = World.HarvestMode.RETURN
const UNLOAD: int = World.HarvestMode.UNLOAD
const FULL: int = 500
const DOCK_A: Vector2i = Vector2i(3500, 5500)
const DOCK_B: Vector2i = Vector2i(13500, 5500)
const DOCK_C: Vector2i = Vector2i(9500, 10500)


func _world(with_b: bool = true, with_c: bool = true) -> World:
	var world: World = Worlds.world(Worlds.grass(20, 12))
	Worlds.add_refinery(world, 1, 2, 2)
	if with_b:
		Worlds.add_refinery(world, 1, 12, 2)
	if with_c:
		Worlds.add_refinery(world, 2, 8, 7)
	return world


## A full harvester of `owner` in RETURN at (x, y) whose refinery is `home` (0: none yet).
func _full(world: World, owner: int, x: int, y: int, home: int = 0) -> int:
	return Worlds.add_harvester(world, owner, x, y, RETURN, 0, home, FULL)


func _goal(world: World, id: int) -> Vector2i:
	var row: int = world.index_of(id)
	return Vector2i(world.goal_x[row], world.goal_y[row])


func test_without_a_home_it_takes_the_nearest_own_refinery_on_its_turn_not_an_enemys() -> void:
	var world: World = _world()
	# 7 280 from A, 3 606 from B, and the enemy's C is nearer than both (3 162).
	var id: int = _full(world, 1, 10500, 5500)
	var row: int = world.index_of(id)
	var turn: int = Worlds.turn(0, id, world.harvest_retry_ticks)
	Worlds.step(world, turn)  # The ticks before its turn: it waits, with no order.
	assert_array([world.home[row], world.order[row]]).is_equal([0, World.Order.IDLE])
	Worlds.step(world)
	assert_array([world.home[row], world.order[row]]).is_equal([2, World.Order.MOVE])
	assert_that(_goal(world, id)).is_equal(DOCK_B)
	assert_int(world.group_cell[row]).is_equal(-1)
	assert_int(world.nav_mode[row]).is_equal(World.NavMode.DIRECT)


func test_equally_near_refineries_go_to_the_lowest_id() -> void:
	var world: World = _world()
	var id: int = _full(world, 1, 8500, 8500)  # 5 000 and 5 000 from the centres of A and B.
	Worlds.step(world, Worlds.turn(0, id, world.harvest_retry_ticks) + 1)
	assert_array([world.home[world.index_of(id)]]).is_equal([1])
	assert_that(_goal(world, id)).is_equal(DOCK_A)


func test_a_building_without_a_dock_is_not_a_refinery() -> void:
	var world: World = _world(false, false)
	var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 7, 5)
	var id: int = _full(world, 1, 6500, 6500)  # 1 581 from the plant, 4 243 from A.
	Worlds.step(world, Worlds.turn(0, id, world.harvest_retry_ticks) + 1)
	assert_bool(plant > 0).is_true()
	assert_array([world.home[world.index_of(id)]]).is_equal([1])
	assert_that(_goal(world, id)).is_equal(DOCK_A)


func test_a_refinery_that_still_stands_stays_home_though_another_is_nearer() -> void:
	var world: World = _world()
	var id: int = _full(world, 1, 4500, 6000, 2)  # Next to A, and B is its home.
	Worlds.step(world)  # No wait: its refinery exists.
	assert_array([world.home[world.index_of(id)], world.order[world.index_of(id)]]).is_equal(
		[2, World.Order.MOVE]
	)
	assert_that(_goal(world, id)).is_equal(DOCK_B)


func test_a_home_that_is_not_a_refinery_is_replaced_like_one_that_is_gone() -> void:
	var world: World = _world(false, false)
	var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 7, 5)
	var id: int = _full(world, 1, 6500, 6500, plant)  # Its home is a power plant: no dock.
	Worlds.step(world)
	assert_array([world.home[world.index_of(id)]]).is_equal([1])
	assert_that(_goal(world, id)).is_equal(DOCK_A)


func test_a_harvester_never_returns_to_the_refinery_of_another_player() -> void:
	var world: World = _world()
	var id: int = _full(world, 2, 9500, 6000, 1)  # Player 2's harvester, player 1's A as its home.
	Worlds.step(world)  # A stale home is replaced at once: the nearest of its own is C.
	assert_array([world.home[world.index_of(id)]]).is_equal([3])
	assert_that(_goal(world, id)).is_equal(DOCK_C)


func test_a_refinery_destroyed_mid_trip_sends_the_harvester_to_the_next_one() -> void:
	var world: World = _world(true, false)
	var id: int = _full(world, 1, 9500, 5500, 2)  # B's dock is 4 000 away, A's 6 000.
	var row: int = world.index_of(id)
	Worlds.step(world, 10)
	assert_that(_goal(world, id)).is_equal(DOCK_B)
	assert_int(world.pos_x[row]).is_greater(9500)  # Under way.
	world.hp[world.index_of(2)] = 0
	Worlds.step(world)
	assert_int(world.index_of(2)).is_equal(-1)
	row = world.index_of(id)
	assert_array([world.home[row], world.order[row]]).is_equal([1, World.Order.MOVE])
	assert_that(_goal(world, id)).is_equal(DOCK_A)
	var guard: int = 600
	while world.credits[1] < 2000 + FULL and guard > 0:
		Worlds.step(world)
		guard -= 1
	assert_array([world.credits[1], world.stat_harvested[1]]).is_equal([2000 + FULL, FULL])
	assert_int(world.home[world.index_of(id)]).is_equal(1)  # It unloaded at the next refinery.


func test_with_no_refinery_left_the_harvester_waits_and_looks_every_retry_period() -> void:
	var world: World = _world(false, false)
	var id: int = _full(world, 1, 3500, 8500, 1)
	Worlds.step(world, 5)
	world.hp[world.index_of(1)] = 0
	Worlds.step(world)
	var row: int = world.index_of(id)
	# The stale home is gone at once; now it has none, waits in RETURN and keeps its cargo.
	assert_array([world.home[row], Worlds.mode_of(world, id), Worlds.cargo_of(world, id)]).is_equal(
		[0, RETURN, FULL]
	)
	Worlds.step(world, 40)
	assert_array([world.home[row], world.credits[1]]).is_equal([0, 2000])
	var made: int = Worlds.add_refinery(world, 1, 12, 2)
	var turn: int = Worlds.turn(world.tick, id, world.harvest_retry_ticks)
	Worlds.step(world, turn - world.tick)  # Up to the tick before its turn: it has not looked.
	assert_int(world.home[row]).is_equal(0)
	Worlds.step(world)
	assert_array([world.home[row], world.order[row]]).is_equal([made, World.Order.MOVE])
	assert_that(_goal(world, id)).is_equal(DOCK_B)
	var guard: int = 600
	while world.credits[1] < 2000 + FULL and guard > 0:
		Worlds.step(world)
		guard -= 1
	assert_int(world.credits[1]).is_equal(2000 + FULL)


func test_unloading_starts_within_the_dock_reach_and_the_order_is_given_beyond_it() -> void:
	var world: World = _world(false, false)
	var reach: int = world.dock_reach_milli
	var near: int = _full(world, 1, DOCK_A.x + reach, DOCK_A.y, 1)  # Exactly in reach.
	var far: int = _full(world, 1, DOCK_A.x - reach - 1, DOCK_A.y, 1)  # One milli beyond it.
	Worlds.step(world)
	assert_array([Worlds.mode_of(world, near), world.order[world.index_of(near)]]).is_equal(
		[UNLOAD, World.Order.IDLE]
	)
	assert_array([Worlds.mode_of(world, far), world.order[world.index_of(far)]]).is_equal(
		[RETURN, World.Order.MOVE]
	)
	assert_that(_goal(world, far)).is_equal(DOCK_A)


func test_four_harvesters_empty_into_one_refinery_though_they_crowd_its_dock() -> void:
	var world: World = _world(false, false)
	var ids: Array[int] = []
	for k: int in 4:
		ids.append(_full(world, 1, 2500 + k * 1500, 9500 + k % 2 * 1200, 1))
	var guard: int = 1500
	while world.credits[1] < 2000 + 4 * FULL and guard > 0:
		Worlds.step(world)
		guard -= 1
	assert_int(world.credits[1]).is_equal(2000 + 4 * FULL)
	assert_int(world.stat_harvested[1]).is_equal(4 * FULL)
	for id: int in ids:
		assert_int(Worlds.cargo_of(world, id)).is_equal(0)
