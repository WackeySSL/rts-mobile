extends GdUnitTestSuite
## Cancelling a site (plan row P128b, ADR 0026 section 6): `CANCEL_BUILD` 16 names an own row with
## work left (`build_left` above 0). In COMMANDS the credits rise by `construct_refund_percent` of
## the price (integer, from the frozen `data/dev/arena/rules.tres`, whatever the work done or the
## damage taken), the hit
## points fall to 0 and `build_left` becomes -1; the row leaves in the same tick's REMOVE with its
## tiles freed, no loss counted and 1 in the seventh int of its DIED record. Until REMOVE the row
## holds its site slot, its tiles and its reach, so a PLACE of the cancel's tick starts nothing. A
## command for an enemy's row, a complete building, a unit, an unknown id or a row already
## cancelled is dropped and counted and changes nothing else. `cancel_rig.gd` has the world; every
## price and number is read from it. The REMOVE side, the slot, the reach and the derived state are
## in `test_site_cancel_remove.gd`.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const Rig: GDScript = preload("res://tests/sim/support/cancel_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const RULES_PATH: String = "res://data/dev/arena/rules.tres"
const OWN_SITE: int = Rig.OWN_SITE
const ENEMY_SITE: int = Rig.ENEMY_SITE
const OPEN: Array[int] = Rig.OPEN
const BLOCKED: Array[int] = Rig.BLOCKED
const SPOT_CELL: int = Rig.SPOT_CELL


## `command` in one tick of a `Rig.world()` that `change` has altered, against the same world with
## no command: the command is counted once as dropped and nothing else is different (the hash
## differs in the header alone, where `dropped_commands` is).
func _assert_dropped(label: String, command: Command, change: Callable = Callable()) -> void:
	var tried: World = Rig.world()
	var plain: World = Rig.world()
	if change.is_valid():
		change.call(tried)
		change.call(plain)
	Rig.step(tried, [command])
	Rig.step(plain, [])
	(
		assert_array([tried.dropped_commands, plain.dropped_commands])
		. override_failure_message(label)
		. is_equal([plain.dropped_commands + 1, plain.dropped_commands])
	)
	assert_array(Rig.differing(tried, plain)).override_failure_message(label).is_equal(["header"])
	assert_array(tried.build_left).override_failure_message(label).is_equal(plain.build_left)


func test_the_world_of_the_cases_has_the_ids_they_use() -> void:
	var made: World = Rig.world()
	assert_array(SiteRig.sites(made)).is_equal([5, 6])
	assert_array([made.unit_id[5], made.unit_id[6]]).is_equal([OWN_SITE, ENEMY_SITE])
	assert_array([made.owner[5], made.owner[6]]).is_equal([1, 2])
	assert_int(made.construct_refund_percent).is_equal(75)  # Michael's answer 1 B.
	assert_int(made.construct_refund_percent).is_equal(
		(load(RULES_PATH) as RulesDef).construct_refund_percent
	)


## The state CANCEL_BUILD leaves in COMMANDS, before the same tick's REMOVE: the refund is paid, the
## row is marked and has no hit points, but it is still a row and its tiles still block.
@warning_ignore("integer_division")
func test_a_cancel_pays_the_refund_and_marks_the_row_in_commands() -> void:
	var made: World = Rig.world()
	var price: int = SiteRig.cost(made, "power_plant")
	var credits: int = made.credits[1]
	var rows: int = made.unit_count()
	var command: Command = Command.cancel_build(1, OWN_SITE)
	command.tick = made.tick
	assert_bool(Production.apply_cancel_build(made, command)).is_true()
	assert_int(price).is_greater(0)
	assert_int(made.credits[1]).is_equal(credits + price * 75 / 100)
	assert_int(made.credits[2]).is_equal(made.start_credits - SiteRig.cost(made, "renew_power"))
	var row: int = made.index_of(OWN_SITE)
	assert_array([made.hp[row], made.build_left[row], made.owner[row]]).is_equal([0, -1, 1])
	assert_array([made.unit_count(), made.dropped_commands]).is_equal([rows, 0])
	assert_array(Worlds.costs_at(made, SPOT_CELL)).is_equal(BLOCKED)
	assert_array(SiteRig.sites(made)).is_equal([made.index_of(ENEMY_SITE)])  # Only the rival's.


## Through the tick: the row is gone, its tiles are free, the map changed once, nothing was built
## or lost, the credits are the refund and no more, and the DIED record carries the cancel mark.
@warning_ignore("integer_division")
func test_a_cancelled_site_leaves_in_the_same_tick_and_counts_no_loss() -> void:
	var made: World = Rig.world()
	var credits: int = made.credits[1]
	var rows: int = made.unit_count()
	var version: int = made.map_version
	var row: int = made.index_of(OWN_SITE)
	var spot: Array[int] = [made.pos_x[row], made.pos_y[row]]
	var plant: int = made.type_index[row]
	Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
	assert_int(made.index_of(OWN_SITE)).is_equal(-1)
	assert_int(made.unit_count()).is_equal(rows - 1)
	assert_int(made.credits[1]).is_equal(credits + SiteRig.cost(made, "power_plant") * 75 / 100)
	assert_array(Worlds.costs_at(made, SPOT_CELL)).is_equal(OPEN)
	assert_int(made.map_version).is_equal(version + 1)
	assert_array([made.stat_lost_buildings[1], made.stat_lost_units[1]]).is_equal([0, 0])
	assert_array([made.stat_built[1], made.dropped_commands]).is_equal([0, 0])
	assert_array(Rig.died(made)).is_equal(
		[[World.Event.DIED, OWN_SITE, spot[0], spot[1], plant, 1, 1, 0]]
	)
	assert_array(SiteRig.sites(made)).is_equal([made.index_of(ENEMY_SITE)])
	# The other player's site and the free slot: nothing of player 2 moved.
	assert_int(made.build_left[made.index_of(ENEMY_SITE)]).is_less(
		SiteRig.done(made, "renew_power")
	)
	assert_array([made.stat_lost_buildings[2], made.stat_lost_units[2]]).is_equal([0, 0])


## A site that is destroyed is a loss with no refund and no cancel mark; so is a finished building
## and a unit. The same hit points 0, so the cancel mark is the only difference.
func test_a_destroyed_site_is_a_loss_and_has_no_cancel_mark() -> void:
	var made: World = Rig.world()
	var credits: int = made.credits[1]
	var site_row: int = made.index_of(OWN_SITE)
	var plant_row: int = made.index_of(SiteRig.PLANT)
	var unit_row: int = made.unit_count() - 1
	made.hp[site_row] = 0
	made.hp[plant_row] = 0
	made.hp[unit_row] = 0
	Rig.step(made, [])
	assert_array([made.stat_lost_buildings[1], made.stat_lost_units[1]]).is_equal([2, 1])
	assert_int(made.credits[1]).is_equal(credits)
	var marks: Array[int] = []
	for record: Array in Rig.died(made):
		marks.append(record[6])
	assert_array(marks).is_equal([0, 0, 0])
	assert_array(Worlds.costs_at(made, SPOT_CELL)).is_equal(OPEN)


## The refund is `type_cost * construct_refund_percent / 100` in integers, from the World: the
## shipped 75, the edges 0 and 100, and percents that truncate a price that is no multiple of 100.
@warning_ignore("integer_division")
func test_the_refund_is_the_priced_percent_in_integers() -> void:
	var rows: Array = [[75, 0], [0, 0], [100, 0], [1, 333], [33, 333], [75, 333], [99, 1], [50, 1]]
	for entry: Array in rows:
		var made: World = Rig.world()
		made.construct_refund_percent = entry[0]
		if entry[1] > 0:
			made.type_cost[SiteRig.type_of(made, "power_plant")] = entry[1]
		var price: int = SiteRig.cost(made, "power_plant")
		var credits: int = made.credits[1]
		Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
		assert_int(made.credits[1]).override_failure_message(str(entry)).is_equal(
			credits + price * entry[0] / 100
		)
		assert_int(made.index_of(OWN_SITE)).override_failure_message(str(entry)).is_equal(-1)
		assert_int(made.dropped_commands).is_equal(0)


## The refund is the share of the price, not of the work done: a site cancelled at once, one at
## the half and one hit down to 1 hit point all pay the same.
@warning_ignore("integer_division")
func test_the_refund_does_not_depend_on_the_work_or_the_damage() -> void:
	var price: int = SiteRig.cost(Rig.world(), "power_plant")
	var refunds: Array[int] = []
	for variant: int in 3:
		var made: World = Rig.world()
		var row: int = made.index_of(OWN_SITE)
		if variant == 1:
			made.build_left[row] = SiteRig.done(made, "power_plant") / 2
		if variant == 2:
			made.hp[row] = 1
		var credits: int = made.credits[1]
		Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
		refunds.append(made.credits[1] - credits)
	assert_array(refunds).is_equal([price * 75 / 100, price * 75 / 100, price * 75 / 100])


func test_a_command_that_names_no_own_site_is_dropped_and_changes_nothing() -> void:
	_assert_dropped("the enemy's site", Command.cancel_build(1, ENEMY_SITE))
	_assert_dropped("the site of the rival's, by the rival", Command.cancel_build(2, OWN_SITE))
	_assert_dropped("a complete building", Command.cancel_build(1, SiteRig.PLANT))
	_assert_dropped("the headquarters", Command.cancel_build(1, SiteRig.HQ))
	_assert_dropped("a unit", Command.cancel_build(1, 8))
	_assert_dropped("id 0", Command.cancel_build(1, 0))
	_assert_dropped("a negative id", Command.cancel_build(1, -6))
	_assert_dropped("an id past every row", Command.cancel_build(1, 9999))
	var payload: Command = Command.cancel_build(1, OWN_SITE)
	payload.payload = PackedInt32Array([0])
	_assert_dropped("a payload", payload)
	_assert_dropped("player 0", Command.cancel_build(0, OWN_SITE))
	_assert_dropped("a player past player_count", Command.cancel_build(3, OWN_SITE))


## An id that names no row finds none (-1), which must not index the last row: here the last row is
## the player's own site, the one a stray -1 would cancel.
func test_an_unknown_id_never_reaches_the_last_row() -> void:
	for id: int in [0, -1, -6, 7, 9999]:
		var made: World = SiteRig.world()
		Rig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
		var row: int = SiteRig.last(made)
		assert_int(made.unit_id[row]).is_equal(6)
		var left: int = made.build_left[row]
		var credits: int = made.credits[1]
		Rig.step(made, [Command.cancel_build(1, id)])
		(
			assert_array([made.dropped_commands, made.credits[1], made.hp[row] > 0])
			. override_failure_message("id %d" % id)
			. is_equal([1, credits, true])
		)
		assert_int(made.build_left[row]).is_equal(left - Production.PROGRESS_PER_TICK)
		assert_int(made.index_of(6)).is_equal(row)


## A finished building is not a site, also the tick after it was a site's last: the cancel of the
## tick after completion is dropped and the building stands.
func test_a_site_that_has_completed_cannot_be_cancelled() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 3)
	Rig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	SiteRig.run(made, 2)
	var row: int = SiteRig.last(made)
	assert_array([made.build_left[row], made.stat_built[1]]).is_equal([0, 1])
	var credits: int = made.credits[1]
	Rig.step(made, [Command.cancel_build(1, made.unit_id[row])])
	assert_array([made.dropped_commands, made.credits[1], made.hp[row]]).is_equal(
		[1, credits, SiteRig.hit_points(made, "power_plant")]
	)
	assert_int(made.index_of(made.unit_id[row])).is_equal(row)


func test_a_defeated_player_and_an_ended_match_cancel_nothing() -> void:
	var gone: Callable = func(made: World) -> void: made.defeated_tick[1] = 1
	_assert_dropped("defeated", Command.cancel_build(1, OWN_SITE), gone)
	var over: Callable = func(made: World) -> void: made.match_end_tick = 1
	_assert_dropped("ended", Command.cancel_build(1, OWN_SITE), over)
	# The controls: the same command applies when the player plays and the match runs.
	var made: World = Rig.world()
	var credits: int = made.credits[1]
	Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
	assert_array([made.dropped_commands, made.credits[1] > credits]).is_equal([0, true])


## A site that was destroyed in an earlier tick is gone: its cancel finds no row, the loss stays
## one and the price is not refunded.
func test_a_site_destroyed_the_tick_before_cannot_be_cancelled() -> void:
	var made: World = Rig.world()
	made.hp[made.index_of(OWN_SITE)] = 0
	Rig.step(made, [])
	assert_int(made.index_of(OWN_SITE)).is_equal(-1)
	var credits: int = made.credits[1]
	Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
	assert_array([made.dropped_commands, made.credits[1]]).is_equal([1, credits])
	assert_array([made.stat_lost_buildings[1], Rig.died(made).size()]).is_equal([1, 0])


## A cancel asks for the site and its owner, nothing else: a blacked-out site, a site of a player
## whose Headquarters is gone and a site on low power cancel like any other.
@warning_ignore("integer_division")
func test_a_blacked_out_site_or_one_without_a_headquarters_can_be_cancelled() -> void:
	var made: World = Rig.world()
	made.offline_until[made.index_of(OWN_SITE)] = made.tick + 50
	var credits: int = made.credits[1]
	Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
	assert_int(made.credits[1]).is_equal(credits + SiteRig.cost(made, "power_plant") * 75 / 100)
	assert_array([made.dropped_commands, made.index_of(OWN_SITE)]).is_equal([0, -1])
	var orphan: World = Rig.world()
	orphan.hp[orphan.index_of(SiteRig.HQ)] = 0
	Rig.step(orphan, [])
	assert_int(orphan.index_of(SiteRig.HQ)).is_equal(-1)
	var before: int = orphan.credits[1]
	Rig.step(orphan, [Command.cancel_build(1, OWN_SITE)])
	assert_int(orphan.credits[1]).is_equal(before + SiteRig.cost(orphan, "power_plant") * 75 / 100)
	assert_array([orphan.dropped_commands, orphan.index_of(OWN_SITE)]).is_equal([0, -1])


## Two cancels of one site in one tick: the first pays and marks it, the second finds a row with
## no work left (-1) and is dropped, so one refund, one record, one removal.
@warning_ignore("integer_division")
func test_two_cancels_in_one_tick_pay_once() -> void:
	var made: World = Rig.world()
	var credits: int = made.credits[1]
	var second: Command = Command.cancel_build(1, OWN_SITE)
	second.sequence = 1
	Rig.step(made, [Command.cancel_build(1, OWN_SITE), second])
	assert_int(made.credits[1]).is_equal(credits + SiteRig.cost(made, "power_plant") * 75 / 100)
	assert_array([made.dropped_commands, Rig.died(made).size()]).is_equal([1, 1])
	assert_int(made.index_of(OWN_SITE)).is_equal(-1)
	# And the same command a tick later names no row at all.
	Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
	assert_int(made.dropped_commands).is_equal(2)


## Two players cancel in one tick: each gets its own share, the records follow the rows' order.
@warning_ignore("integer_division")
func test_each_player_cancels_its_own_site_in_one_tick() -> void:
	var made: World = Rig.world()
	var own: int = made.credits[1]
	var rival: int = made.credits[2]
	Rig.step(made, [Command.cancel_build(2, ENEMY_SITE), Command.cancel_build(1, OWN_SITE)])
	assert_int(made.credits[1]).is_equal(own + SiteRig.cost(made, "power_plant") * 75 / 100)
	assert_int(made.credits[2]).is_equal(rival + SiteRig.cost(made, "renew_power") * 75 / 100)
	var ids: Array[int] = []
	for record: Array in Rig.died(made):
		ids.append(record[1])
		assert_array([record[0], record[6], record[7]]).is_equal([World.Event.DIED, 1, 0])
	assert_array(ids).is_equal([OWN_SITE, ENEMY_SITE])
	assert_array([made.dropped_commands, SiteRig.sites(made).size()]).is_equal([0, 0])


## The cancel of the tick that would have completed the site: COMMANDS runs before PRODUCTION, so
## the site never completes. A refinery site pays no free harvester and counts no `stat_built`, and
## the control without the cancel completes in the same tick.
@warning_ignore("integer_division")
func test_a_cancel_in_the_last_tick_of_the_work_stops_the_completion() -> void:
	var control: World = SiteRig.world()
	var made: World = SiteRig.world()
	for each: World in [control, made]:
		SiteRig.fast(each, "refinery", 4)
		Rig.step(each, [SiteRig.place(each, "refinery", SiteRig.WIDE)])
		SiteRig.run(each, 2)
		assert_int(each.build_left[SiteRig.last(each)]).is_equal(Production.PROGRESS_PER_TICK)
	var id: int = made.unit_id[SiteRig.last(made)]
	var credits: int = made.credits[1]
	Rig.step(control, [])
	assert_array([control.stat_built[1], SiteRig.rows_of(control, 1, "harvester").size()]).is_equal(
		[1, 1]
	)
	Rig.step(made, [Command.cancel_build(1, id)])
	assert_array([made.stat_built[1], made.dropped_commands]).is_equal([0, 0])
	assert_array(SiteRig.rows_of(made, 1, "harvester")).is_empty()
	assert_int(made.index_of(id)).is_equal(-1)
	assert_int(made.credits[1]).is_equal(credits + SiteRig.cost(made, "refinery") * 75 / 100)
	assert_int(made.unit_count()).is_equal(control.unit_count() - 2)  # The site and its harvester.
	assert_array(Worlds.costs_at(made, 9 * SiteRig.COLS + 7)).is_equal(OPEN)
