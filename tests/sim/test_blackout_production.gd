extends GdUnitTestSuite
## A blacked-out producer's queue (plan row P111, ADR 0023 section 10): `Production.run` does not
## advance the queue whose producer (the lowest-id building of its tab, ADR 0018 section 5) has an
## `offline_until` above the stamp: the head keeps its progress, nothing spawns, and it goes on from
## there at the stamp that reaches `offline_until`, so a unit comes exactly `type_strike_ticks`
## later than in a twin world with no blackout. A queue whose producer is outside the radius is not
## touched. The rig is `blackout_worlds.gd`: player 2's barracks in the array's radius (a gunner
## queue) and its factory outside it (a jeep queue), the power never low, the length read from the
## World's table; the twin takes the same queue commands and no blackout.

const Rig: GDScript = preload("res://tests/sim/support/blackout_worlds.gd")
const INFANTRY: int = 2 * World.TABS + World.Tab.INFANTRY  # Player 2's queue indexes.
const VEHICLES: int = 2 * World.TABS + World.Tab.VEHICLES


## Two rig worlds, each with a gunner and a jeep queued by player 2 in tick 0 (so it is stepped
## once), at the tick the array may fire: the one that will black out and its twin.
func _pair() -> Array[World]:
	var worlds: Array[World] = [Rig.world(), Rig.world()]
	for each: World in worlds:
		var orders: Array[Command] = [
			Command.queue(2, Rig.type_of(each, "gunner")),
			Command.queue(2, Rig.type_of(each, "jeep"))
		]
		orders[1].sequence = 1
		Rig.step(each, orders)
		Rig.run_to(each, Rig.fire_tick(each))
	return worlds


## The tick `world.tick` has when player 2 first has a unit of the type `id`, stepping from where
## it is, with `commands` in the first step; -1 when none comes in `limit` steps.
func _tick_of_first(world: World, id: String, commands: Array = [], limit: int = 400) -> int:
	for at: int in limit:
		Rig.step(world, commands if at == 0 else [])
		if Rig.count_of(world, 2, id) > 0:
			return world.tick
	return -1


## The gunner queue stands still for exactly the length of the blackout, from the firing step's
## own PRODUCTION, while the twin's queue advances every step until its gunner is out and the jeep
## queue (its factory is outside the radius) advances as in the twin; at the stamp that reaches
## `offline_until` the gunner queue gains one step again.
func test_the_queue_of_a_blacked_out_producer_waits_for_exactly_the_length() -> void:
	var worlds: Array[World] = _pair()
	var world: World = worlds[0]
	var twin: World = worlds[1]
	var length: int = Rig.length_of(world)
	var tick: int = Rig.fire_tick(world)
	var step: int = Production.PROGRESS_PER_TICK
	var done: int = world.type_build_ticks[Rig.type_of(world, "gunner")] * step
	var frozen: int = world.queue_progress[INFANTRY]
	assert_int(frozen).is_greater(0)
	assert_int(frozen).is_less(done)
	assert_int(world.queue_progress[INFANTRY]).is_equal(twin.queue_progress[INFANTRY])
	for at: int in length:
		Rig.step(world, [Rig.fire()] if at == 0 else [])
		Rig.step(twin)
		assert_int(world.dropped_commands).is_equal(0)
		(
			assert_int(world.queue_progress[INFANTRY])
			. override_failure_message("step %d" % at)
			. is_equal(frozen)
		)
		var expected: int = frozen + (at + 1) * step
		if expected < done:
			assert_int(twin.queue_progress[INFANTRY]).is_equal(expected)
		else:
			assert_int(Rig.count_of(twin, 2, "gunner")).is_equal(1)  # The twin's gunner is out.
		assert_int(world.queue_progress[VEHICLES]).is_equal(twin.queue_progress[VEHICLES])
		assert_int(Rig.count_of(world, 2, "gunner")).is_equal(0)
	Rig.step(world)
	assert_int(world.tick).is_equal(tick + 1 + length)  # The stamp that reaches offline_until.
	assert_int(world.queue_progress[INFANTRY]).is_equal(frozen + step)


## A unit comes exactly the length of the blackout later than in the twin, and the credits are
## the twin's: nothing is spawned by the blacked-out producer meanwhile and nothing is refunded or
## lost.
func test_a_unit_comes_exactly_the_length_later_than_in_the_twin() -> void:
	var worlds: Array[World] = _pair()
	var world: World = worlds[0]
	var twin: World = worlds[1]
	var gunner: int = _tick_of_first(world, "gunner", [Rig.fire()])
	var twin_gunner: int = _tick_of_first(twin, "gunner")
	assert_int(twin_gunner).is_greater(Rig.fire_tick(world))  # It was still being built.
	assert_int(gunner).is_equal(twin_gunner + Rig.length_of(world))
	assert_int(world.credits[2]).is_equal(twin.credits[2])
	assert_int(world.stat_built[2]).is_equal(twin.stat_built[2])


## The jeep, from a factory outside the radius, comes on the same tick whether or not the other
## producer is blacked out, and the gunner of the blacked-out barracks is not there yet.
func test_the_queue_of_a_producer_outside_the_radius_is_not_touched() -> void:
	var worlds: Array[World] = _pair()
	var world: World = worlds[0]
	var twin: World = worlds[1]
	var jeep: int = _tick_of_first(world, "jeep", [Rig.fire()])
	var twin_jeep: int = _tick_of_first(twin, "jeep")
	assert_int(twin_jeep).is_greater(Rig.fire_tick(world))
	assert_int(jeep).is_equal(twin_jeep)
	assert_array([Rig.count_of(world, 2, "gunner"), Rig.count_of(twin, 2, "gunner")]).is_equal(
		[0, 1]
	)


## The queue belongs to its tab's primary producer, the lowest-id building that produces the tab
## (ADR 0018 section 5), and it waits while that one is blacked out even when a second producer
## of the tab stands outside the radius: the second barracks is not the queue's producer, so
## nothing is spawned there either.
func test_the_queue_waits_for_its_primary_producer_even_with_a_second_one_outside() -> void:
	var worlds: Array[World] = [Rig.world(), Rig.world()]
	for each: World in worlds:
		each.add_building(2, Rig.type_of(each, "barracks"), 36, 14)  # Outside the radius, a later id.
		Rig.step(each, [Command.queue(2, Rig.type_of(each, "gunner"))])
		Rig.run_to(each, Rig.fire_tick(each))
	var world: World = worlds[0]
	var twin: World = worlds[1]
	var frozen: int = world.queue_progress[INFANTRY]
	for at: int in Rig.length_of(world):
		Rig.step(world, [Rig.fire()] if at == 0 else [])
		Rig.step(twin)
		assert_int(world.queue_progress[INFANTRY]).is_equal(frozen)
	assert_array([Rig.count_of(world, 2, "gunner"), Rig.count_of(twin, 2, "gunner")]).is_equal(
		[0, 1]
	)
