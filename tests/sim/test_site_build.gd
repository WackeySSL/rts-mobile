extends GdUnitTestSuite
## Construction in PRODUCTION (plan row P128, ADR 0026 section 3): a site gains `PROGRESS_PER_TICK`
## of work in each step, or `low_power_percent` of it on low power; it waits while it is blacked out
## and while its owner is defeated, and goes on when its Headquarters dies; its hit points rise
## with the work, their steps summing to the maximum for a site never hit; and at 0 it is complete
## in the same step (the strike charge starts, a refinery's free harvester comes, `stat_built`
## counts it). A PLACE of tick t is applied in COMMANDS and its site gains its first step in the
## PRODUCTION of the same tick, so a build time of N ticks is complete after N steps. `site_rig.gd`
## has the world; the expected numbers are computed from the World's tables.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const STEP: int = Production.PROGRESS_PER_TICK

## `start + (max - start) * work / done`, the hit points of a site after `work` hundredths of a
## tick, with `start` the percent of the maximum (at least 1): ADR 0026 section 3, written out.
@warning_ignore("integer_division")
func _target(made: World, id: String, work: int) -> int:
	var top: int = SiteRig.hit_points(made, id)
	var start: int = mini(maxi(1, top * made.construct_start_hp_percent / 100), top)
	return start + (top - start) * work / SiteRig.done(made, id)


## Places a plant site at tick 0 (its first step is made) and returns its row.
func _site(made: World) -> int:
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	return SiteRig.last(made)


func test_a_site_gains_one_step_a_tick_and_is_complete_after_its_build_time() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 6)
	var row: int = _site(made)
	var done: int = SiteRig.done(made, "power_plant")
	assert_int(done).is_equal(6 * STEP)
	for step: int in range(1, 6):
		assert_int(made.build_left[row]).override_failure_message("step %d" % step).is_equal(
			done - step * STEP
		)
		assert_array([made.stat_built[1], SiteRig.sites(made)]).is_equal([0, [row]])
		SiteRig.step(made)
	assert_int(made.build_left[row]).is_equal(0)
	assert_array([made.stat_built[1], SiteRig.sites(made)]).is_equal([1, []])
	assert_int(made.hp[row]).is_equal(SiteRig.hit_points(made, "power_plant"))
	# Complete, it stays as it is: no more steps, no second count.
	SiteRig.run(made, 5)
	assert_array([made.build_left[row], made.stat_built[1]]).is_equal([0, 1])
	assert_int(made.unit_count()).is_equal(6)
	assert_int(made.dropped_commands).is_equal(0)


## The shipped numbers: the Power Plant takes 150 steps, so it is a site for 149 steps after the
## placing one and complete at the 150th.
func test_the_shipped_build_time_is_the_number_of_steps() -> void:
	var made: World = SiteRig.world()
	var ticks: int = made.type_build_ticks[SiteRig.type_of(made, "power_plant")]
	assert_int(ticks).is_greater(1)
	var row: int = _site(made)
	SiteRig.run(made, ticks - 2)
	assert_array([made.build_left[row], made.stat_built[1]]).is_equal([STEP, 0])
	SiteRig.step(made)
	assert_array([made.build_left[row], made.stat_built[1]]).is_equal([0, 1])
	assert_int(made.tick).is_equal(ticks)


## The step is `Power.scaled`: `low_power_percent` of 100 on low power, the totals being ECONOMY's
## of the same step (a site adds nothing to them). The goal is never passed: with a rate of 30 and
## 7 ticks of work the last step is the 10 that remain, and the site is complete after 24 steps.
func test_low_power_slows_a_site_by_the_rule_and_never_passes_the_goal() -> void:
	var made: World = SiteRig.world()
	made.type_power[SiteRig.type_of(made, "power_plant")] = 0  # Player 1 makes 20, uses 50.
	made.low_power_percent = 30
	SiteRig.fast(made, "power_plant", 7)
	SiteRig.fast(made, "renew_power", 7)
	var row: int = _site(made)
	assert_bool(Power.is_low(made, 1)).is_true()
	assert_bool(Power.is_low(made, 2)).is_false()
	assert_int(made.build_left[row]).is_equal(700 - 30)
	# Player 2's site, at the full rate beside it.
	SiteRig.step(made, [SiteRig.place(made, "renew_power", SiteRig.SPOT_2, 2)])
	var rival: int = SiteRig.last(made)
	assert_array([made.build_left[row], made.build_left[rival]]).is_equal([700 - 60, 700 - STEP])
	var steps: int = 2
	while made.build_left[row] > 0:
		var before: int = made.build_left[row]
		SiteRig.step(made)
		steps += 1
		assert_int(made.build_left[row]).is_equal(maxi(before - 30, 0))
	assert_int(steps).is_equal(24)  # ceil(700 / 30)
	assert_array([made.stat_built[1], made.stat_built[2]]).is_equal([1, 1])
	assert_int(made.build_left[rival]).is_equal(0)


@warning_ignore("integer_division")
func test_the_shipped_low_power_rate_halves_the_step() -> void:
	var made: World = SiteRig.world()
	made.type_power[SiteRig.type_of(made, "power_plant")] = 0
	assert_int(made.low_power_percent).is_equal(50)
	var row: int = _site(made)
	assert_int(made.build_left[row]).is_equal(SiteRig.done(made, "power_plant") - STEP / 2)


## A blacked-out site (`offline_until` above the stamp, `world.tick + 1`) keeps its work and its
## hit points, and goes on at the stamp that reaches `offline_until`.
func test_a_blacked_out_site_waits_until_the_stamp_that_reaches_offline_until() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 20)
	var row: int = _site(made)
	SiteRig.run(made, 2)
	var left: int = made.build_left[row]
	var hit_points: int = made.hp[row]
	assert_int(left).is_equal(17 * STEP)
	made.offline_until[row] = made.tick + 4  # Steps with stamps tick + 1 .. tick + 3 are offline.
	for step: int in 3:
		SiteRig.step(made)
		(
			assert_array([made.build_left[row], made.hp[row]])
			. override_failure_message("step %d" % step)
			. is_equal([left, hit_points])
		)
	SiteRig.step(made)
	assert_int(made.build_left[row]).is_equal(left - STEP)
	assert_int(made.hp[row]).is_greater(hit_points)


func test_the_sites_of_a_defeated_player_stop_and_the_others_go_on() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 30)
	SiteRig.fast(made, "renew_power", 30)
	var row: int = _site(made)
	SiteRig.step(made, [SiteRig.place(made, "renew_power", SiteRig.SPOT_2, 2)])
	var rival: int = SiteRig.last(made)
	made.defeated_tick[1] = made.tick + 1
	var left: int = made.build_left[row]
	var hit_points: int = made.hp[row]
	var rival_left: int = made.build_left[rival]
	SiteRig.run(made, 5)
	assert_array([made.build_left[row], made.hp[row]]).is_equal([left, hit_points])
	assert_int(made.build_left[rival]).is_equal(rival_left - 5 * STEP)


## ADR 0026 question 4, answer A: the site is paid for and on the map, so it goes on when the
## Headquarters dies, as long as the player has a complete producer left (the barracks). Without a
## Headquarters no new site can start.
func test_a_site_goes_on_when_its_headquarters_dies() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "refinery", 12)
	SiteRig.step(made, [SiteRig.place(made, "refinery", SiteRig.WIDE)])
	var row: int = SiteRig.last(made)
	var site_id: int = made.unit_id[row]
	SiteRig.run(made, 3)
	var left: int = made.build_left[row]
	made.hp[made.index_of(SiteRig.HQ)] = 0
	SiteRig.step(made)
	assert_int(made.index_of(SiteRig.HQ)).is_equal(-1)
	assert_int(made.defeated_tick[1]).is_equal(0)  # The barracks stands.
	row = made.index_of(site_id)  # The rows moved up behind the Headquarters.
	assert_int(made.build_left[row]).is_equal(left - STEP)
	var dropped: int = made.dropped_commands
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	assert_int(made.dropped_commands).is_equal(dropped + 1)  # No Headquarters, no new site.
	SiteRig.run(made, 10)
	assert_array([made.build_left[row], made.stat_built[1]]).is_equal([0, 1])
	assert_int(made.defeated_tick[1]).is_equal(0)


## "A site cannot keep a beaten player in the match": the player's only complete producers die while
## a barracks site (a producer type) rises; Outcome defeats it in the same PRODUCTION step, and a
## defeated player's sites stop.
func test_a_site_does_not_keep_its_owner_in_the_match() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "barracks", 40)
	SiteRig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	var site_id: int = made.unit_id[SiteRig.last(made)]
	assert_int(made.defeated_tick[1]).is_equal(0)
	made.hp[made.index_of(SiteRig.HQ)] = 0
	made.hp[made.index_of(SiteRig.BARRACKS)] = 0
	var stamp: int = made.tick + 1
	SiteRig.step(made)
	assert_int(made.defeated_tick[1]).is_equal(stamp + 0)
	assert_array([made.match_end_tick, made.winner]).is_equal([stamp, 2])
	var row: int = made.index_of(site_id)
	var left: int = made.build_left[row]
	assert_int(left).is_greater(0)
	SiteRig.run(made, 4)
	assert_int(made.build_left[row]).is_equal(left)


func test_hit_points_rise_with_the_work_and_their_steps_sum_to_the_maximum() -> void:
	# (max hit points, build ticks, start percent): the shipped plant, awkward divisions, a type
	# with 1 hit point, and the whole work in one step.
	var cases: Array = [[800, 150, 10], [1001, 7, 10], [999, 13, 33], [1, 5, 10], [2000, 1, 10]]
	for config: Array in cases:
		var made: World = SiteRig.world()
		var plant: int = SiteRig.type_of(made, "power_plant")
		made.type_max_hp[plant] = config[0]
		made.type_build_ticks[plant] = config[1]
		made.construct_start_hp_percent = config[2]
		var label: String = str(config)
		var done: int = SiteRig.done(made, "power_plant")
		assert_bool(SiteRig.apply(made, SiteRig.place(made, "power_plant", SiteRig.SPOT))).is_true()
		var row: int = SiteRig.last(made)
		var hit_points: int = made.hp[row]
		assert_int(hit_points).override_failure_message(label).is_equal(
			_target(made, "power_plant", 0)
		)
		var total: int = hit_points
		for step: int in range(1, config[1] + 1):
			SiteRig.step(made)
			var gained: int = made.hp[row] - hit_points
			(
				assert_int(gained)
				. override_failure_message("%s step %d" % [label, step])
				. is_greater_equal(0)
			)
			total += gained
			hit_points = made.hp[row]
			assert_int(hit_points).override_failure_message("%s step %d" % [label, step]).is_equal(
				_target(made, "power_plant", step * STEP)
			)
		assert_int(made.build_left[row]).override_failure_message(label).is_equal(0)
		assert_int(hit_points).override_failure_message(label).is_equal(config[0])
		assert_int(total).override_failure_message(label).is_equal(config[0])
		assert_int(done).is_equal(config[1] * STEP)


## On low power the work per step is smaller, and the hit points follow the work, not the tick.
func test_hit_points_follow_the_work_on_low_power() -> void:
	var made: World = SiteRig.world()
	made.type_power[SiteRig.type_of(made, "power_plant")] = 0
	made.low_power_percent = 30
	SiteRig.fast(made, "power_plant", 9)
	var row: int = _site(made)
	var done: int = SiteRig.done(made, "power_plant")
	while made.build_left[row] > 0:
		var work: int = done - made.build_left[row]
		assert_int(made.hp[row]).override_failure_message("work %d" % work).is_equal(
			_target(made, "power_plant", work)
		)
		SiteRig.step(made)
	assert_int(made.hp[row]).is_equal(SiteRig.hit_points(made, "power_plant"))


## Damage taken stays taken: the steps add the work's share, the site never heals back.
func test_damage_a_site_takes_stays_taken() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 20)
	var row: int = _site(made)
	SiteRig.run(made, 9)  # 10 steps made.
	var before: int = made.hp[row]
	assert_int(before).is_equal(_target(made, "power_plant", 10 * STEP))
	made.hp[row] -= 40
	SiteRig.step(made)
	assert_int(made.hp[row]).is_equal(_target(made, "power_plant", 11 * STEP) - 40)
	SiteRig.run(made, 9)
	assert_int(made.build_left[row]).is_equal(0)
	assert_int(made.hp[row]).is_equal(SiteRig.hit_points(made, "power_plant") - 40)


## Destroyed while it goes up, a site is a lost building: it leaves in REMOVE, its tiles open again,
## the loss is counted, nothing is refunded and none of the completion effects happen.
func test_a_site_destroyed_while_it_rises_is_lost_with_its_price() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "refinery", 30)
	SiteRig.step(made, [SiteRig.place(made, "refinery", SiteRig.WIDE)])
	var row: int = SiteRig.last(made)
	var credits: int = made.credits[1]
	var lost: int = made.stat_lost_buildings[1]
	SiteRig.run(made, 4)
	assert_array(Worlds.costs_at(made, 10 * SiteRig.COLS + 7)).is_equal([0, 0, 0])
	made.hp[row] = 0
	SiteRig.step(made)
	assert_int(made.unit_count()).is_equal(5)
	assert_array(SiteRig.sites(made)).is_empty()
	assert_int(made.stat_lost_buildings[1]).is_equal(lost + 1)
	assert_array([made.credits[1], made.stat_built[1]]).is_equal([credits, 0])
	assert_array(Worlds.costs_at(made, 10 * SiteRig.COLS + 7)).is_equal([10, 10, 10])
	assert_array(SiteRig.rows_of(made, 1, "harvester")).is_empty()
	SiteRig.run(made, 40)  # Nothing is left to finish.
	assert_array([made.stat_built[1], made.unit_count()]).is_equal([0, 5])


## The step order of `Production.run` (ADR 0026 section 3): the construction walk comes before the
## queues, so a barracks that completes in a step serves its queue in that same step. The rifle
## squad queued at the first barracks waits while there is none (it died), the site's steps leave
## the progress alone, and the completing step moves it by one step.
func test_a_barracks_that_completes_serves_its_queue_in_the_same_step() -> void:
	var made: World = SiteRig.world()
	var queue: int = 1 * World.TABS + World.Tab.INFANTRY
	SiteRig.step(made, [Command.queue(1, SiteRig.type_of(made, "rifle_squad"))])
	assert_int(made.queue_progress[queue]).is_equal(STEP)
	made.hp[made.index_of(SiteRig.BARRACKS)] = 0
	SiteRig.step(made)
	assert_int(made.index_of(SiteRig.BARRACKS)).is_equal(-1)
	var before: int = made.queue_progress[queue]
	assert_int(before).is_equal(STEP)  # The queue waited in the step the barracks died.
	SiteRig.fast(made, "barracks", 3)
	SiteRig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	var row: int = SiteRig.last(made)
	assert_array([made.build_left[row], made.queue_progress[queue]]).is_equal([2 * STEP, before])
	SiteRig.step(made)
	assert_array([made.build_left[row], made.queue_progress[queue]]).is_equal([STEP, before])
	SiteRig.step(made)  # The completing step.
	assert_int(made.build_left[row]).is_equal(0)
	assert_int(made.queue_progress[queue]).is_equal(before + STEP)
	assert_int(Production.producer_row(made, 1, World.Tab.INFANTRY)).is_equal(row)


## The queues of the step in which a site completes run on ECONOMY's totals (the `Production.run`
## header); the closing `Power.run` is for the checkpoint and the next step. Player 1 is on low
## power until a plant site completes, so the site itself rises at the low rate too: its rifle
## squad gains the low step in every step up to and including the completing one, and the full step
## in the next.
@warning_ignore("integer_division")
func test_the_queues_of_the_completing_step_run_on_the_totals_of_economy() -> void:
	var made: World = SiteRig.world()
	made.type_power[SiteRig.type_of(made, "barracks")] = -150  # Player 1 makes 120, uses 180.
	SiteRig.fast(made, "power_plant", 3)
	var queue: int = 1 * World.TABS + World.Tab.INFANTRY
	var low: int = STEP * made.low_power_percent / 100
	assert_bool(low > 0 and low < STEP).is_true()
	var steps: int = (SiteRig.done(made, "power_plant") + low - 1) / low  # 6 steps at 50 of 300.
	SiteRig.step(
		made,
		[
			Command.queue(1, SiteRig.type_of(made, "rifle_squad")),
			SiteRig.place(made, "power_plant", SiteRig.SPOT)
		]
	)
	var row: int = SiteRig.last(made)
	for step: int in range(1, steps):
		assert_bool(Power.is_low(made, 1)).override_failure_message("step %d" % step).is_true()
		assert_array([made.build_left[row] > 0, made.queue_progress[queue]]).is_equal(
			[true, step * low]
		)
		SiteRig.step(made)
	# The completing step: the head still gains the low step.
	assert_int(made.build_left[row]).is_equal(0)
	assert_int(made.queue_progress[queue]).is_equal(steps * low)
	assert_bool(Power.is_low(made, 1)).is_false()  # The closing sum holds the new plant's power.
	assert_array([made.power_made[1], made.power_used[1]]).is_equal([220, 180])
	SiteRig.step(made)  # The next step: ECONOMY's totals are not low, the head gains the full step.
	assert_int(made.queue_progress[queue]).is_equal(steps * low + STEP)


## Completion, ADR 0026 section 3: a refinery site gives its free harvester (its `home` the
## refinery) when it is complete and not before.
func test_a_refinery_site_gives_its_free_harvester_at_completion() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "refinery", 5)
	SiteRig.step(made, [SiteRig.place(made, "refinery", SiteRig.WIDE)])
	var site: int = SiteRig.last(made)
	var site_id: int = made.unit_id[site]
	SiteRig.run(made, 3)
	assert_array(SiteRig.rows_of(made, 1, "harvester")).is_empty()
	SiteRig.step(made)
	assert_int(made.build_left[site]).is_equal(0)
	var harvesters: Array[int] = SiteRig.rows_of(made, 1, "harvester")
	assert_int(harvesters.size()).is_equal(1)
	assert_array([made.home[harvesters[0]], made.harvest_mode[harvesters[0]]]).is_equal(
		[site_id, World.HarvestMode.SEEK]
	)
	assert_int(made.stat_built[1]).is_equal(1)


## A strike building charges from its completion, not from its placement (ADR 0026 question 3):
## `ready_tick` is 0 while it rises and the stamp of the completing step plus the charge after it,
## and the SUPERWEAPON is accepted from the tick whose stamp reaches it.
func test_a_strike_site_starts_its_charge_at_completion() -> void:
	var made: World = SiteRig.world()
	made.add_building(1, SiteRig.type_of(made, "fossil_radar"), 9, 5)
	made.credits[1] = 5000
	var strike: int = SiteRig.type_of(made, "fossil_strike")
	made.type_charge_ticks[strike] = 10
	SiteRig.fast(made, "fossil_strike", 5)
	SiteRig.step(made, [SiteRig.place(made, "fossil_strike", SiteRig.FAR)])
	var row: int = SiteRig.last(made)
	var id: int = made.unit_id[row]
	assert_int(made.dropped_commands).is_equal(0)
	assert_int(made.ready_tick[row]).is_equal(0)
	SiteRig.run(made, 3)
	assert_array([made.build_left[row], made.ready_tick[row]]).is_equal([STEP, 0])
	SiteRig.step(made)  # The completing step: the stamp is the tick it leaves behind.
	assert_int(made.build_left[row]).is_equal(0)
	var stamp: int = made.tick
	assert_int(made.ready_tick[row]).is_equal(stamp + 10)
	# Charged: the command of tick ready_tick - 1 (stamp = ready_tick) is the first one accepted.
	var first: int = made.ready_tick[row] - 1
	while made.tick < first - 1:
		SiteRig.step(made)
	var dropped: int = made.dropped_commands
	SiteRig.step(made, [Command.superweapon(1, id, 15500, 8500)])
	assert_int(made.dropped_commands).is_equal(dropped + 1)
	assert_int(made.tick).is_equal(first)
	SiteRig.step(made, [Command.superweapon(1, id, 15500, 8500)])
	assert_array([made.dropped_commands, made.strike_tick[1] > 0]).is_equal([dropped + 1, true])
