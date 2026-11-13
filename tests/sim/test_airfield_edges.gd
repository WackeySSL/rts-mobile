extends GdUnitTestSuite
## Two edges of `Air.run` (plan row P241, ADR 0036 section 6): its counts in the scratch columns
## are cleared before use, and the failed re-home memo is per owner. Worlds are `air_worlds.gd`'s.

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")


## `Air.run` clears its counts in the scratch columns itself: stale values on the airfield's row
## (what SEPARATION's pushes leave there) must not move the pads or stop the reload.
func test_the_counts_are_cleared_before_use() -> void:
	var world: World = Worlds.world()
	var one: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var two: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 1)
	world.ammo[one] = 0
	world.ammo[two] = 0
	Buildings.rebuild_lists(world)
	var field: int = world.index_of(Worlds.FIELD)
	world.push_x[field] = 5
	world.push_y[field] = 5
	Air.run(world)
	assert_array([world.ammo[one], world.ammo[two]]).is_equal([1, 1])
	# The totals too: a homeless aircraft still finds the airfield whose total is stale.
	world.push_x[field] = 5
	var lost: int = Worlds.add(world, 1, "fighter", 9000, 9000)
	Buildings.rebuild_lists(world)
	world.home[one] = 0
	world.home[two] = 0
	world.home[lost] = 0
	world.push_x[field] = 5
	Air.run(world)
	assert_int(world.home[one]).is_equal(Worlds.FIELD)


## The failed re-home memo is per owner: player 1 has no complete airfield, and player 2's homeless
## aircraft, later in the rows, still finds its own.
func test_a_failed_re_home_of_one_owner_does_not_stop_another_owner() -> void:
	var world: World = Worlds.world()
	world.build_left[world.index_of(Worlds.FIELD)] = 500
	var theirs: int = world.add_building(2, Worlds.type_of(world, "field"), 14, 8)
	var mine: int = Worlds.add(world, 1, "fighter", 9000, 9000)
	var rival: int = Worlds.add(world, 2, "fighter", 12000, 9000)
	Worlds.step(world)
	assert_array([world.home[mine], world.home[rival]]).is_equal([0, theirs])
