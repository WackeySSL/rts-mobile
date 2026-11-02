extends GdUnitTestSuite
## What an unfinished building is (plan row P128, ADR 0026 section 4): a row with `build_left` above
## 0 blocks its tiles, sees, can be targeted and destroyed, takes a rally point, and does nothing
## for its owner until it is complete: it makes and uses no power, is no producer, meets no
## requirement, fires no gun or strike, takes no tanker and keeps no player alive. The cases set the
## state by hand (`SiteRig.unfinish`, the column the rules read) so that each rule is proven alone;
## `test_site_place` and `test_site_build` make the sites through PLACE. `site_rig.gd` has the
## world.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const INFANTRY: int = World.Tab.INFANTRY
const STRUCTURES: int = World.Tab.STRUCTURES


func _row(made: World, id: int) -> int:
	return made.index_of(id)


## The totals ECONOMY builds, after one step.
func _power(made: World) -> Array[int]:
	SiteRig.step(made)
	return [made.power_made[1], made.power_used[1]]


func test_a_site_makes_and_uses_no_power_until_it_is_complete() -> void:
	var made: World = SiteRig.world()
	assert_array(_power(made)).is_equal([120, 50])  # HQ 20 + plant 100; barracks 20 + refinery 30.
	SiteRig.unfinish(made, _row(made, SiteRig.PLANT))
	assert_array(_power(made)).is_equal([20, 50])
	assert_bool(Power.is_low(made, 1)).is_true()
	made.build_left[_row(made, SiteRig.PLANT)] = 0
	SiteRig.unfinish(made, _row(made, SiteRig.BARRACKS))
	assert_array(_power(made)).is_equal([120, 30])
	assert_bool(Power.is_low(made, 1)).is_false()
	made.build_left[_row(made, SiteRig.BARRACKS)] = 0
	assert_array(_power(made)).is_equal([120, 50])


## `producer_row` finds the lowest-id complete producer, so a site with a lower id is passed over,
## and a player whose only barracks is a site has no infantry producer: QUEUE is dropped.
func test_a_site_is_no_producer_and_the_queue_is_dropped_without_a_complete_one() -> void:
	var made: World = SiteRig.world()
	var barracks: int = SiteRig.type_of(made, "barracks")
	var rifle: int = SiteRig.type_of(made, "rifle_squad")
	assert_int(Production.producer_row(made, 1, INFANTRY)).is_equal(_row(made, SiteRig.BARRACKS))
	SiteRig.unfinish(made, _row(made, SiteRig.BARRACKS))
	assert_int(Production.producer_row(made, 1, INFANTRY)).is_equal(-1)
	var credits: int = made.credits[1]
	SiteRig.step(made, [Command.queue(1, rifle)])
	assert_array([made.dropped_commands, made.credits[1], made.queue_count[3 + INFANTRY]]).is_equal(
		[1, credits, 0]
	)
	# A complete barracks with a higher id is the producer, though the site comes first.
	var second: int = made.add_building(1, barracks, 14, 14)
	assert_int(Production.producer_row(made, 1, INFANTRY)).is_equal(_row(made, second))
	SiteRig.step(made, [Command.queue(1, rifle)])
	assert_int(made.queue_count[3 + INFANTRY]).is_equal(1)
	# The STRUCTURES tab: a Headquarters that is a site starts no queue either.
	SiteRig.unfinish(made, _row(made, SiteRig.HQ))
	assert_int(Production.producer_row(made, 1, STRUCTURES)).is_equal(-1)
	var plant: int = SiteRig.type_of(made, "power_plant")
	var dropped: int = made.dropped_commands
	SiteRig.step(made, [Command.queue(1, plant)])
	assert_int(made.dropped_commands).is_equal(dropped + 1)


## A queue whose only producer turns out to be a site waits: no progress, no unit, no refund.
func test_a_queue_waits_while_its_only_producer_is_a_site() -> void:
	var made: World = SiteRig.world()
	var rifle: int = SiteRig.type_of(made, "rifle_squad")
	SiteRig.step(made, [Command.queue(1, rifle)])
	SiteRig.run(made, 4)
	var queue: int = 3 + INFANTRY
	var progress: int = made.queue_progress[queue]
	assert_int(progress).is_equal(5 * Production.PROGRESS_PER_TICK)
	SiteRig.unfinish(made, _row(made, SiteRig.BARRACKS))
	SiteRig.run(made, 6)
	assert_array([made.queue_progress[queue], made.queue_count[queue]]).is_equal([progress, 1])
	assert_array(SiteRig.rows_of(made, 1, "rifle_squad")).is_empty()
	made.build_left[_row(made, SiteRig.BARRACKS)] = 0
	SiteRig.step(made)
	assert_int(made.queue_progress[queue]).is_equal(progress + Production.PROGRESS_PER_TICK)


## A requirement is met by a complete row only (`_owns`): the queue path and the new path alike.
func test_a_site_meets_no_requirement() -> void:
	var made: World = SiteRig.world()
	var barracks: int = SiteRig.type_of(made, "barracks")  # Requires the Power Plant.
	SiteRig.unfinish(made, _row(made, SiteRig.PLANT))
	var credits: int = made.credits[1]
	SiteRig.step(made, [Command.queue(1, barracks)])
	assert_array([made.dropped_commands, made.credits[1]]).is_equal([1, credits])
	made.build_left[_row(made, SiteRig.PLANT)] = 0
	SiteRig.step(made, [Command.queue(1, barracks)])
	assert_array([made.dropped_commands, made.queue_count[3 + STRUCTURES]]).is_equal([1, 1])


## A site keeps its target (TARGETING is unchanged) but fires nothing; the same turret, complete,
## fires on the first FIRE after, with no wind-up.
func test_a_defence_site_picks_a_target_and_does_not_shoot() -> void:
	var made: World = SiteRig.world()
	var turret: int = made.add_building(1, SiteRig.type_of(made, "defence_turret"), 6, 5)
	var foe: int = made.add_unit(2, SiteRig.type_of(made, "rifle_squad"), 10500, 6000)
	var row: int = _row(made, turret)
	var target: int = _row(made, foe)
	made.hp[target] = 100000
	SiteRig.unfinish(made, row)
	var shots: int = 0
	for _tick: int in 40:
		SiteRig.step(made)
		for at: int in range(0, made.events.size(), World.EVENT_STRIDE):
			if made.events[at] == World.Event.SHOT and made.events[at + 1] == turret:
				shots += 1
	assert_int(shots).is_equal(0)
	assert_int(made.target[row]).is_equal(foe)  # Still picks its target.
	assert_int(made.hp[target]).is_equal(100000)
	made.build_left[row] = 0
	SiteRig.step(made)
	for at: int in range(0, made.events.size(), World.EVENT_STRIDE):
		if made.events[at] == World.Event.SHOT and made.events[at + 1] == turret:
			shots += 1
	assert_int(shots).is_equal(1)
	SiteRig.run(made, 10)  # The shell is in flight for a few ticks.
	assert_int(made.hp[target]).is_less(100000)


## `SUPERWEAPON` of a site is dropped although its `ready_tick` is 0 and so "charged"; complete, it
## is accepted. `Buildings.add` with `complete` false starts no charge, the default does.
func test_a_strike_site_cannot_fire_and_a_site_starts_no_charge() -> void:
	var made: World = SiteRig.world()
	var strike: int = SiteRig.type_of(made, "fossil_strike")
	var kept: int = made.add_building(1, strike, 12, 8)
	assert_int(made.ready_tick[_row(made, kept)]).is_greater(0)
	var plain: int = Buildings.add(made, 1, strike, 16, 8, false)
	assert_int(made.ready_tick[_row(made, plain)]).is_equal(0)
	var explicit: int = Buildings.add(made, 1, strike, 20, 8, true)
	assert_int(made.ready_tick[_row(made, explicit)]).is_greater(0)
	var row: int = _row(made, kept)
	made.ready_tick[row] = 0  # What a site has: 0, so the charge check alone would let it fire.
	SiteRig.unfinish(made, row)
	SiteRig.step(made, [Command.superweapon(1, kept, 15500, 4500)])
	assert_array([made.dropped_commands, made.strike_tick[1]]).is_equal([1, 0])
	made.build_left[row] = 0
	SiteRig.step(made, [Command.superweapon(1, kept, 15500, 4500)])
	assert_array([made.dropped_commands, made.strike_tick[1] > 0]).is_equal([1, true])


## ADR 0026 section 1: CANCEL_BUILD (P128b) writes -1 into `build_left` and 0 into `hp`, and the row
## leaves in REMOVE, after FIRE and after the commands of its own tick. Every "is it complete" test
## reads `build_left == 0`, so a cancelled row, hand-set here, fires no last shot and its strike
## building accepts no SUPERWEAPON in that window.
func test_a_cancelled_row_fires_no_gun_and_no_strike_before_it_leaves() -> void:
	var made: World = SiteRig.world()
	var turret: int = made.add_building(1, SiteRig.type_of(made, "defence_turret"), 6, 5)
	made.add_unit(2, SiteRig.type_of(made, "rifle_squad"), 10500, 6000)
	var row: int = _row(made, turret)
	SiteRig.unfinish(made, row)  # A site picks its target and holds it (the case above).
	SiteRig.run(made, 10)
	assert_int(made.target[row]).is_not_equal(0)
	assert_int(made.cooldown[row]).is_equal(0)
	made.build_left[row] = -1
	made.hp[row] = 0
	SiteRig.step(made)
	for at: int in range(0, made.events.size(), World.EVENT_STRIDE):
		var shot: bool = made.events[at] == World.Event.SHOT
		assert_bool(shot and made.events[at + 1] == turret).is_false()
	assert_int(made.index_of(turret)).is_equal(-1)  # Removed in the same tick.
	# The strike building: ready_tick is 0 (as a site's), build_left -1, hp 0.
	var other: World = SiteRig.world()
	var strike: int = other.add_building(1, SiteRig.type_of(other, "fossil_strike"), 12, 8)
	var strike_row: int = _row(other, strike)
	other.ready_tick[strike_row] = 0
	other.build_left[strike_row] = -1
	other.hp[strike_row] = 0
	SiteRig.step(other, [Command.superweapon(1, strike, 15500, 4500)])
	assert_array([other.dropped_commands, other.strike_tick[1]]).is_equal([1, 0])


## A full tanker returns to the nearest complete refinery: the site that stands nearer is skipped,
## and with no complete refinery at all the tanker finds no home and waits.
func test_a_refinery_site_takes_no_tanker() -> void:
	var made: World = SiteRig.world()
	var near: int = made.add_building(1, SiteRig.type_of(made, "refinery"), 6, 9)
	SiteRig.unfinish(made, _row(made, near))
	var tanker: int = made.add_unit(1, SiteRig.type_of(made, "harvester"), 7500, 8000)
	var row: int = _row(made, tanker)
	made.harvest_mode[row] = World.HarvestMode.RETURN
	made.cargo[row] = made.type_harvest[SiteRig.type_of(made, "harvester")]
	SiteRig.run(made, 2 * made.harvest_retry_ticks)
	assert_int(made.home[row]).is_equal(SiteRig.REFINERY)
	assert_int(made.home[row]).is_not_equal(near)
	# Only sites left: nothing to return to, the cargo stays.
	var alone: World = SiteRig.world()
	SiteRig.unfinish(alone, _row(alone, SiteRig.REFINERY))
	var lone: int = alone.add_unit(1, SiteRig.type_of(alone, "harvester"), 7500, 8000)
	var lone_row: int = _row(alone, lone)
	alone.harvest_mode[lone_row] = World.HarvestMode.RETURN
	alone.cargo[lone_row] = alone.type_harvest[SiteRig.type_of(alone, "harvester")]
	SiteRig.run(alone, 2 * alone.harvest_retry_ticks)
	assert_array([alone.home[lone_row], alone.cargo[lone_row] > 0]).is_equal([0, true])
	alone.build_left[_row(alone, SiteRig.REFINERY)] = 0
	SiteRig.run(alone, 2 * alone.harvest_retry_ticks)
	assert_int(alone.home[lone_row]).is_equal(SiteRig.REFINERY)


## ADR 0018 section 7: a player with no complete producer is defeated in the PRODUCTION step; a
## site of a producer type does not count, a complete producer does.
func test_a_site_keeps_no_player_alive() -> void:
	var held: World = SiteRig.world()
	var rival: int = held.index_of(SiteRig.HQ_2)
	SiteRig.run(held, 3)
	assert_int(held.defeated_tick[2]).is_equal(0)
	SiteRig.unfinish(held, rival)
	var stamp: int = held.tick + 1
	SiteRig.step(held)
	assert_int(held.defeated_tick[2]).is_equal(stamp)
	assert_array([held.match_end_tick, held.winner]).is_equal([stamp, 1])
	# Player 1 loses its Headquarters to a site, but its barracks stands.
	var made: World = SiteRig.world()
	SiteRig.unfinish(made, _row(made, SiteRig.HQ))
	SiteRig.run(made, 3)
	assert_array([made.defeated_tick[1], made.match_end_tick]).is_equal([0, 0])
	SiteRig.unfinish(made, _row(made, SiteRig.BARRACKS))
	SiteRig.step(made)
	assert_int(made.defeated_tick[1]).is_greater(0)


## `RALLY` names an own producer: a site takes it, and the point is kept per tab (ADR 0018 s. 6).
func test_a_site_takes_a_rally_point() -> void:
	var made: World = SiteRig.world()
	SiteRig.unfinish(made, _row(made, SiteRig.BARRACKS))
	SiteRig.step(made, [Command.rally(1, SiteRig.BARRACKS, 11500, 6500)])
	assert_int(made.dropped_commands).is_equal(0)
	var queue: int = 1 * World.TABS + INFANTRY
	assert_array([made.rally_x[queue], made.rally_y[queue]]).is_equal([11500, 6500])


## Seen, targeted and destroyed: a site is stamped into its owner's fog and listed as a building.
func test_a_site_sees_and_is_a_building_row() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "refinery", 40)
	SiteRig.step(made, [SiteRig.place(made, "refinery", SiteRig.WIDE)])
	var row: int = SiteRig.last(made)
	SiteRig.run(made, 2 * made.fog_period_ticks)
	assert_int(made.fog_cell[row]).is_greater_equal(0)  # Its sight is stamped.
	assert_bool(made.building_rows.has(row)).is_true()
	assert_array(SiteRig.sites(made)).is_equal([row])
