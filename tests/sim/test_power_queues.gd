extends GdUnitTestSuite
## Low power slows production (plan row P74, ADR 0018 sections 4 and 5): the head of a player's
## queue gains `low_power_percent` of the normal 100 hundredths per tick while that player's power
## used is above its power made, on every tab (the STRUCTURES head too, which stops at its goal and
## waits there), and only that player's queues. The totals are ECONOMY's of the same step, so a
## change of power counts from the PRODUCTION phase of the step that made it. The expected steps and
## ticks come from the World's tables (`low_power_percent`, `type_build_ticks`), and the shipped
## value is pinned once: low power halves the rate exactly.
##
## `Rig.base()` has player 1 with enough power (a plant against a barracks, a refinery and a
## factory) and player 2 on low power from the start (a barracks and no plant).

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const INFANTRY: int = World.Tab.INFANTRY
const VEHICLES: int = World.Tab.VEHICLES
const STRUCTURES: int = World.Tab.STRUCTURES

## The hundredths a head gains per tick on low power, from the rule.
@warning_ignore("integer_division")
func _low_step(world: World) -> int:
	return Production.PROGRESS_PER_TICK * world.low_power_percent / 100


## The progress at which the item `id` is done.
func _done(world: World, id: String) -> int:
	return world.type_build_ticks[Worlds.type_of(world, id)] * Production.PROGRESS_PER_TICK


## The number of ticks `done` takes at `step` per tick: the first tick that reaches it.
@warning_ignore("integer_division")
func _ticks(done: int, step: int) -> int:
	return (done + step - 1) / step


func _count(world: World, player: int, id: String) -> int:
	return Rig.rows_of(world, player, id).size()


func _progress(world: World, player: int, tab: int) -> int:
	return world.queue_progress[Rig.queue_of(player, tab)]


func test_the_shipped_rule_halves_the_rate_and_the_step_comes_from_it() -> void:
	var world: World = Rig.base()
	assert_int(_low_step(world) * 2).is_equal(Production.PROGRESS_PER_TICK)
	world.low_power_percent = 30
	assert_int(_low_step(world)).is_equal(30)


func test_low_power_halves_progress_exactly_and_only_for_the_player_on_low_power() -> void:
	var world: World = Rig.base()
	var step: int = _low_step(world)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 2, "rifle_squad", 1)])
	assert_bool(Power.is_low(world, 1)).is_false()
	assert_bool(Power.is_low(world, 2)).is_true()
	# The queue of tick 0 gains in that same tick, the totals being built before PRODUCTION.
	assert_int(_progress(world, 1, INFANTRY)).is_equal(Production.PROGRESS_PER_TICK)
	assert_int(_progress(world, 2, INFANTRY)).is_equal(step)
	var normal: int = _ticks(_done(world, "rifle_squad"), Production.PROGRESS_PER_TICK)
	var slow: int = _ticks(_done(world, "rifle_squad"), step)
	assert_int(slow).is_equal(2 * normal)
	Rig.run(world, normal - 2)
	assert_array([_count(world, 1, "rifle_squad"), _count(world, 2, "rifle_squad")]).is_equal(
		[0, 0]
	)
	assert_int(_progress(world, 2, INFANTRY)).is_equal((normal - 1) * step)
	Rig.step(world)
	assert_array([_count(world, 1, "rifle_squad"), _count(world, 2, "rifle_squad")]).is_equal(
		[1, 0]
	)
	assert_int(_progress(world, 2, INFANTRY)).is_equal(normal * step)  # Half of the goal.
	Rig.run(world, slow - normal - 1)
	assert_int(_count(world, 2, "rifle_squad")).is_equal(0)
	Rig.step(world)
	assert_int(_count(world, 2, "rifle_squad")).is_equal(1)
	assert_int(world.tick).is_equal(slow)
	var spent: int = world.start_credits - world.type_cost[Worlds.type_of(world, "rifle_squad")]
	assert_array([world.credits[1], world.credits[2]]).is_equal([spent, spent])
	assert_array([world.stat_built[1], world.stat_built[2]]).is_equal([1, 1])


func test_every_queue_of_a_player_on_low_power_runs_at_the_low_rate() -> void:
	var world: World = Rig.base()
	world.add_building(1, Worlds.type_of(world, "barracks"), 8, 6)  # Uses more than the plant makes.
	var step: int = _low_step(world)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 1, "light_tank", 1)])
	assert_bool(Power.is_low(world, 1)).is_true()
	var rifle: int = _ticks(_done(world, "rifle_squad"), step)
	var tank: int = _ticks(_done(world, "light_tank"), step)
	assert_array([_progress(world, 1, INFANTRY), _progress(world, 1, VEHICLES)]).is_equal(
		[step, step]
	)
	Rig.run(world, rifle - 2)
	assert_int(_count(world, 1, "rifle_squad")).is_equal(0)
	Rig.step(world)
	assert_int(_count(world, 1, "rifle_squad")).is_equal(1)
	assert_int(_progress(world, 1, VEHICLES)).is_equal(rifle * step)
	Rig.run(world, tank - rifle - 1)
	assert_int(_count(world, 1, "light_tank")).is_equal(0)
	Rig.step(world)
	assert_int(_count(world, 1, "light_tank")).is_equal(1)
	assert_int(world.tick).is_equal(tank)


## A Headquarters (+20) and a refinery (-30) and no plant: player 1 uses more than it makes.
func _structures_world() -> World:
	var world: World = Worlds.world(GridWorld.grass(24, 16), Rig.IDS)
	world.add_building(1, Worlds.type_of(world, "headquarters"), 2, 5)
	world.add_building(1, Worlds.type_of(world, "refinery"), 12, 1)
	return world


func test_a_structure_head_gains_the_low_rate_and_waits_ready_at_its_goal() -> void:
	for percent: int in [50, 33, 7]:  # The last two do not divide the goal: the cap is exact.
		var world: World = _structures_world()
		world.low_power_percent = percent
		var step: int = _low_step(world)
		var done: int = _done(world, "power_plant")
		Rig.step(world, [Rig.queue(world, 1, "power_plant")])
		assert_bool(Power.is_low(world, 1)).override_failure_message("%d %%" % percent).is_true()
		assert_int(_progress(world, 1, STRUCTURES)).is_equal(step)
		var ready: int = _ticks(done, step)
		Rig.run(world, ready - 2)
		assert_int(_progress(world, 1, STRUCTURES)).is_equal((ready - 1) * step)
		assert_int(_progress(world, 1, STRUCTURES)).is_less(done)
		Rig.step(world)
		(
			assert_int(_progress(world, 1, STRUCTURES))
			. override_failure_message("%d %%: the cap" % percent)
			. is_equal(done)
		)
		Rig.run(world, 10)  # Ready: it waits, whatever the power does.
		assert_int(_progress(world, 1, STRUCTURES)).is_equal(done)
		assert_int(world.queue_count[Rig.queue_of(1, STRUCTURES)]).is_equal(1)
		var cost: int = world.type_cost[Worlds.type_of(world, "power_plant")]
		assert_int(world.credits[1]).is_equal(world.start_credits - cost)


func test_the_normal_rate_returns_with_the_power_and_nothing_is_made_up() -> void:
	var world: World = Rig.base()
	var step: int = _low_step(world)
	Rig.step(world, [Rig.queue(world, 2, "rifle_squad")])
	Rig.run(world, 19)  # Twenty ticks at the low rate.
	assert_int(_progress(world, 2, INFANTRY)).is_equal(20 * step)
	Rig.add_plant(world, 2, 2, 12)  # Counts in ECONOMY of the next step, before its PRODUCTION.
	Rig.step(world)
	assert_bool(Power.is_low(world, 2)).is_false()
	var rest: int = _done(world, "rifle_squad") - 20 * step
	var finish: int = 20 + _ticks(rest, Production.PROGRESS_PER_TICK)
	assert_int(_progress(world, 2, INFANTRY)).is_equal(20 * step + Production.PROGRESS_PER_TICK)
	Rig.run(world, finish - 22)
	assert_int(_count(world, 2, "rifle_squad")).is_equal(0)
	Rig.step(world)
	assert_int(_count(world, 2, "rifle_squad")).is_equal(1)
	assert_int(world.tick).is_equal(finish)


func test_power_lost_mid_item_slows_the_rest_of_it_from_the_step_that_lost_it() -> void:
	var world: World = Rig.base()
	var step: int = _low_step(world)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	Rig.run(world, 29)  # Thirty ticks at the normal rate.
	var normal: int = Production.PROGRESS_PER_TICK
	assert_int(_progress(world, 1, INFANTRY)).is_equal(30 * normal)
	world.hp[world.index_of(Rig.PLANT)] = 0  # REMOVE then ECONOMY of the next step see it.
	Rig.step(world)
	assert_bool(Power.is_low(world, 1)).is_true()
	assert_int(_progress(world, 1, INFANTRY)).is_equal(30 * normal + step)
	var finish: int = 31 + _ticks(_done(world, "rifle_squad") - 30 * normal - step, step)
	Rig.run(world, finish - 32)
	assert_int(_count(world, 1, "rifle_squad")).is_equal(0)
	Rig.step(world)
	assert_int(_count(world, 1, "rifle_squad")).is_equal(1)
	assert_int(world.tick).is_equal(finish)


func test_a_percent_of_zero_stops_the_queue_on_low_power_and_leaves_the_others_alone() -> void:
	var world: World = Rig.base()
	world.low_power_percent = 0
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 2, "rifle_squad", 1)])
	Rig.run(world, 29)
	assert_int(_progress(world, 1, INFANTRY)).is_equal(30 * Production.PROGRESS_PER_TICK)
	assert_int(_progress(world, 2, INFANTRY)).is_equal(0)
	assert_int(world.queue_count[Rig.queue_of(2, INFANTRY)]).is_equal(1)


@warning_ignore("integer_division")
func test_scaled_gives_all_of_it_or_the_percent_of_it_rounded_toward_zero() -> void:
	var world: World = Rig.base()
	Rig.step(world)
	assert_int(Power.scaled(world, 1, 100)).is_equal(100)
	assert_int(Power.scaled(world, 0, 100)).is_equal(100)  # The neutral player is never low.
	assert_int(Power.scaled(world, 2, 100)).is_equal(world.low_power_percent)
	assert_int(Power.scaled(world, 2, 7)).is_equal(7 * world.low_power_percent / 100)
	assert_int(Power.scaled(world, 2, 1)).is_equal(1 * world.low_power_percent / 100)
