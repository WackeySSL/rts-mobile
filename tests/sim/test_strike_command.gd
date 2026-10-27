extends GdUnitTestSuite
## The charge of a strike building and the SUPERWEAPON command (plan row P110, ADR 0023 section 10):
## a strike building fires exactly `type_charge_ticks` after it was placed and not a tick earlier,
## firing restarts the charge and writes the player's pending strike, and each invalid case (not
## the player's own, not a strike building, charging, offline, a defeated player, after the end, a
## payload, the blackout kind before P111, and a rupture already pending) is dropped and counted
## with nothing else changed. The rig (`strike_worlds.gd`) has the world, its rows and its numbers;
## every expected tick, radius and cost is read from the World's tables. The landing is
## test_strike_rupture's.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const UNIT: int = 6  # The id of the first row a case adds to the rig's world.


## A strike building starts charging when it is placed (here at tick 0, as a scenario places it):
## its ready_tick is the tick that step produces plus the charge, a building without a strike stays
## at 0, and the first SUPERWEAPON accepted is the one stamped `charge` ticks after the placement.
func test_a_strike_building_fires_exactly_its_charge_after_placement_and_not_a_tick_earlier(
) -> void:
	var world: World = Strikes.world()
	var charge: int = Strikes.charge_of(world, "bore")
	assert_int(charge).is_greater(2)
	for id: int in [Strikes.BORE_A, Strikes.BORE_B]:
		assert_int(world.ready_tick[world.index_of(id)]).is_equal(1 + charge)
	assert_int(world.ready_tick[world.index_of(Strikes.ARRAY)]).is_equal(
		1 + Strikes.charge_of(world, "array")
	)
	for id: int in [Strikes.HQ_1, Strikes.HQ_2]:
		assert_int(world.ready_tick[world.index_of(id)]).is_equal(0)
	Strikes.run_to(world, charge - 1)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_array([world.dropped_commands, world.strike_tick[1]]).is_equal([1, 0])
	assert_int(Strikes.fire_tick(world, Strikes.BORE_A)).is_equal(charge)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.strike_tick[1]).is_not_equal(0)


## The charge starts when a PLACE puts the building on the map, at that step's tick: queue the bore
## at the headquarters, wait until it is ready, place it, and it fires exactly `charge` ticks after
## the PLACE.
func test_a_building_placed_by_a_place_command_charges_from_that_step() -> void:
	var world: World = Strikes.world()
	var bore: int = Strikes.type_of(world, "bore")
	var charge: int = world.type_charge_ticks[bore]
	Strikes.step(world, [Command.queue(1, bore)])
	for _tick: int in world.type_build_ticks[bore] - 1:
		Strikes.step(world)
	var placed_at: int = world.tick
	Strikes.step(world, [Command.place(1, 6700, 8300)])  # The tile (6, 8), next to the headquarters.
	assert_int(world.dropped_commands).is_equal(0)
	var id: int = world.unit_id[world.unit_count() - 1]
	assert_int(world.type_index[world.index_of(id)]).is_equal(bore)
	assert_int(world.ready_tick[world.index_of(id)]).is_equal(placed_at + 1 + charge)
	Strikes.run_to(world, placed_at + charge - 1)
	Strikes.step(world, [Strikes.fire(id)])
	assert_array([world.dropped_commands, world.strike_tick[1]]).is_equal([1, 0])
	Strikes.step(world, [Strikes.fire(id)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.strike_tick[1]).is_not_equal(0)


## A valid SUPERWEAPON writes the player's pending strike (the point and the landing tick, the
## stamp plus the warning), restarts the building's charge from the stamp and touches no other
## building or player.
func test_a_valid_superweapon_writes_the_pending_strike_and_restarts_the_charge() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	var other: int = world.ready_tick[world.index_of(Strikes.BORE_B)]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500))])
	assert_int(world.dropped_commands).is_equal(0)
	var landing: int = tick + 1 + Strikes.delay_of(world, "bore")
	assert_array([world.strike_x[1], world.strike_y[1], world.strike_tick[1]]).is_equal(
		[12500, 9500, landing]
	)
	assert_int(world.ready_tick[world.index_of(Strikes.BORE_A)]).is_equal(
		tick + 1 + Strikes.charge_of(world, "bore")
	)
	assert_int(world.ready_tick[world.index_of(Strikes.BORE_B)]).is_equal(other)
	assert_array([world.strike_x[2], world.strike_y[2], world.strike_tick[2]]).is_equal([0, 0, 0])


## Firing restarts the charge: after the rupture has landed, the same building is refused until the
## stamp reaches the new ready_tick, `charge` ticks after the firing tick, and fires then.
func test_a_building_that_fired_charges_again_from_its_firing_tick() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	var charge: int = Strikes.charge_of(world, "bore")
	Strikes.run_to(world, tick)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.run_to(world, tick + Strikes.delay_of(world, "bore") + 1)
	assert_int(world.strike_tick[1]).is_equal(0)  # Landed, so nothing is pending any more.
	Strikes.run_to(world, tick + charge - 1)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_array([world.dropped_commands, world.strike_tick[1]]).is_equal([1, 0])
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.strike_tick[1]).is_equal(tick + charge + 1 + Strikes.delay_of(world, "bore"))


## The point is clamped to the map as RALLY clamps its point: a point outside, however far, ends
## on the nearest edge, so that the landing's squared distances stay small and the point fits its
## int32 column.
func test_the_point_is_clamped_to_the_map() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(-5000, 99999999))])
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([0, world.map_h - 1])
	Strikes.run_to(world, world.strike_tick[1])  # Landed.
	Strikes.step(world, [Command.superweapon(1, Strikes.BORE_B, 1 << 40, -(1 << 40))])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([world.map_w - 1, 0])


## Not the player's own, not a strike building and not a row at all: dropped and counted, and the
## state is that of a tick with no command (only the header's dropped count differs).
func test_a_building_that_is_not_the_players_own_strike_building_is_dropped() -> void:
	var rifle: Callable = func(w: World) -> void: Strikes.add(w, 1, "rifle", 5500, 15500)
	_assert_dropped("player 2 fires player 1's bore", func() -> Command: return Strikes.fire(1, 2))
	_assert_dropped("a headquarters", func() -> Command: return Strikes.fire(Strikes.HQ_1))
	_assert_dropped("a unit", func() -> Command: return Strikes.fire(UNIT), rifle)
	_assert_dropped("an id with no row", func() -> Command: return Strikes.fire(999))
	_assert_dropped("id 0", func() -> Command: return Strikes.fire(0))
	_assert_dropped("a negative id", func() -> Command: return Strikes.fire(-1))


## Charging, offline, a defeated player, the end of the match, a payload, a player that does not
## exist and the blackout building (its effect is P111's, so its command is dropped until then).
func test_charging_offline_defeat_the_end_and_the_other_invalid_cases_are_dropped() -> void:
	var offline: Callable = func(w: World) -> void:
		w.offline_until[w.index_of(Strikes.BORE_A)] = w.tick + 2
	var defeated: Callable = func(w: World) -> void: w.defeated_tick[1] = 3
	var ended: Callable = func(w: World) -> void: w.match_end_tick = 5
	var bore: Callable = func() -> Command: return Strikes.fire(Strikes.BORE_A)
	_assert_dropped("still charging", bore, Callable(), 1)
	_assert_dropped("offline", bore, offline)
	_assert_dropped("defeated", bore, defeated)
	_assert_dropped("after the end", bore, ended)
	_assert_dropped(
		"a payload",
		func() -> Command:
			var command: Command = Strikes.fire(Strikes.BORE_A)
			command.payload = PackedInt32Array([1])
			return command
	)
	_assert_dropped("a player past the table", func() -> Command: return Strikes.fire(1, 3))
	_assert_dropped("the blackout kind", func() -> Command: return Strikes.fire(Strikes.ARRAY))


## A building is offline while `offline_until` is above the stamp and back at the stamp itself: the
## value P111 writes is the first tick it works again.
func test_a_building_is_back_when_the_stamp_reaches_offline_until() -> void:
	var back: World = Strikes.world()
	var tick: int = Strikes.fire_tick(back, Strikes.BORE_A)
	Strikes.run_to(back, tick)
	back.offline_until[back.index_of(Strikes.BORE_A)] = tick + 1
	Strikes.step(back, [Strikes.fire(Strikes.BORE_A)])
	assert_array([back.dropped_commands, back.strike_tick[1] != 0]).is_equal([0, true])
	var off: World = Strikes.world()
	Strikes.run_to(off, tick)
	off.offline_until[off.index_of(Strikes.BORE_A)] = tick + 2
	Strikes.step(off, [Strikes.fire(Strikes.BORE_A)])
	assert_array([off.dropped_commands, off.strike_tick[1]]).is_equal([1, 0])


## While a player's one rupture is pending, a further SUPERWEAPON of that player is dropped and
## counted, a ready building of the player's included (lead decision of 2026-10-26, an ADR 0023
## section 10 note): at the next tick, and at the landing step itself, whose COMMANDS come before
## the landing. The tick after the landing the player may fire again. Nothing of the first strike
## or of the second building changes in between.
func test_a_pending_rupture_drops_a_further_superweapon_of_its_player_until_it_lands() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	var delay: int = Strikes.delay_of(world, "bore")
	Strikes.run_to(world, tick)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500))])
	var second: int = world.ready_tick[world.index_of(Strikes.BORE_B)]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_B, 1, Vector2i(4500, 4500))])
	assert_int(world.dropped_commands).is_equal(1)
	Strikes.run_to(world, tick + delay)  # The landing step, the last with the strike pending.
	assert_int(world.strike_tick[1]).is_equal(tick + 1 + delay)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_B, 1, Vector2i(4500, 4500))])
	assert_int(world.dropped_commands).is_equal(2)
	assert_int(world.strike_tick[1]).is_equal(0)  # It landed in that step.
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([12500, 9500])
	assert_int(world.ready_tick[world.index_of(Strikes.BORE_B)]).is_equal(second)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_B, 1, Vector2i(4500, 4500))])
	assert_int(world.dropped_commands).is_equal(2)
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([4500, 4500])
	assert_int(world.strike_tick[1]).is_equal(tick + delay + 2 + delay)


## The pending strike is per player: player 2, who owns a bore of its own, fires while player 1's
## strike is in the air, and each keeps its own point and tick.
func test_each_player_has_its_own_pending_rupture() -> void:
	var world: World = Strikes.world()
	var bore: int = Strikes.type_of(world, "bore")
	var enemy: int = world.add_building(2, bore, 20, 2)
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500))])
	Strikes.step(world, [Strikes.fire(enemy, 2, Vector2i(2500, 15500))])
	assert_int(world.dropped_commands).is_equal(0)
	var delay: int = Strikes.delay_of(world, "bore")
	assert_array([world.strike_x[1], world.strike_y[1], world.strike_tick[1]]).is_equal(
		[12500, 9500, tick + 1 + delay]
	)
	assert_array([world.strike_x[2], world.strike_y[2], world.strike_tick[2]]).is_equal(
		[2500, 15500, tick + 2 + delay]
	)


## Runs `make`'s command (a Callable, because a command is stamped in place and cannot be shared by
## two Worlds) in a rig world at the first tick the bore may fire (`early` ticks before it), after
## `prepare` changed the World, and checks that it is dropped and counted and that nothing else of
## the state differs from a twin that took a tick with no command. A third world, unprepared and on
## time, takes the plain SUPERWEAPON of the bore and must accept it, so the case's one fault is
## what drops the command.
func _assert_dropped(
	label: String, make: Callable, prepare: Callable = Callable(), early: int = 0
) -> void:
	var world: World = Strikes.world()
	var twin: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A) - early
	var both: Array[World] = [world, twin]
	for each: World in both:
		Strikes.run_to(each, tick)
		if prepare.is_valid():
			prepare.call(each)
	Strikes.step(world, [make.call()])
	Strikes.step(twin)
	assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
	assert_array(Strikes.differing(world, twin)).override_failure_message(label).is_equal(
		["header"]
	)
	var fine: World = Strikes.world()
	Strikes.run_to(fine, Strikes.fire_tick(fine, Strikes.BORE_A))
	Strikes.step(fine, [Strikes.fire(Strikes.BORE_A)])
	assert_array([fine.dropped_commands, fine.strike_tick[1] != 0]).is_equal([0, true])
