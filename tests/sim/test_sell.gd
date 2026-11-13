extends GdUnitTestSuite
## Selling a building (plan row P271, ADR 0037 section 3): `SELL` 17 names an own complete building
## with a price. In COMMANDS the owner gets `floor(price * sell_refund_percent * hp / (100 * max
## hp))`, the hit points fall to 0 and `build_left` becomes `Production.SOLD` (-3); REMOVE takes the
## row out in the same tick with DIED flag 3, no loss counted and its tiles free. The Headquarters
## (price 0), a site, a unit, an enemy's building and a payload are refused. The flag mapping of
## `remove_dead` is -1 to 1, -2 to 2, -3 to 3, anything else 0. Worlds are `cancel_rig.gd`'s (two
## sites, ids 6 and 7, a rifle squad, id 8) and `site_rig.gd`'s (ids 1 to 5); the percent is set by
## hand, because the rule's default is inert (0). Every number is computed from the World's tables.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const Rig: GDScript = preload("res://tests/sim/support/cancel_rig.gd")
const PERCENT: int = 50


## A cancel_rig world one tick old, with the sale percent set.
func _world() -> World:
	var made: World = Rig.world()
	made.sell_refund_percent = PERCENT
	# A priced, complete building of player 2 (the Headquarters of either side costs 0).
	made.add_building(2, SiteRig.type_of(made, "power_plant"), 20, 2)
	return made


func _id(made: World, id: String, owner: int = 1) -> int:
	return made.unit_id[SiteRig.rows_of(made, owner, id)[0]]


@warning_ignore("integer_division")
func _expected(made: World, id: String, hit_points: int) -> int:
	var type: int = SiteRig.type_of(made, id)
	return made.type_cost[type] * PERCENT * hit_points / (100 * made.type_max_hp[type])


func _assert_dropped(label: String, command: Command, change: Callable = Callable()) -> void:
	var made: World = _world()
	if change.is_valid():
		change.call(made)
	var credits: int = made.credits[1]
	var rows: int = made.unit_count()
	var dropped: int = made.dropped_commands
	Rig.step(made, [command])
	assert_int(made.dropped_commands).override_failure_message(label).is_equal(dropped + 1)
	assert_int(made.credits[1]).override_failure_message(label).is_equal(credits)
	assert_int(made.unit_count()).override_failure_message(label).is_equal(rows)


func test_the_command_has_its_number_and_a_factory() -> void:
	assert_int(Command.Type.SELL).is_equal(17)
	var command: Command = Command.sell(2, 9)
	assert_array([command.type, command.player_id, command.target_id]).is_equal([17, 2, 9])
	assert_bool(command.payload.is_empty()).is_true()


func test_the_rule_default_is_inert() -> void:
	assert_int(RulesDef.new().sell_refund_percent).is_equal(0)
	assert_int(Rig.world().sell_refund_percent).is_equal(0)


## At full health, at half and at 1 hit point: the credits rise by the formula and the row is
## marked in COMMANDS (before the tick's REMOVE).
func test_a_sale_pays_by_health_and_marks_the_row() -> void:
	var top: int = SiteRig.hit_points(_world(), "power_plant")
	for hit_points: int in [top, top / 2, 1]:
		var made: World = _world()
		var id: int = _id(made, "power_plant")
		var row: int = made.index_of(id)
		made.hp[row] = hit_points
		var before: int = made.credits[1]
		var command: Command = Command.sell(1, id)
		command.tick = made.tick
		made.prepare()
		assert_bool(Production.apply_sell(made, command)).is_true()
		assert_int(made.credits[1] - before).is_equal(_expected(made, "power_plant", hit_points))
		assert_array([made.hp[row], made.build_left[row]]).is_equal([0, Production.SOLD])
	assert_int(_expected(_world(), "power_plant", 1)).is_less(
		_expected(_world(), "power_plant", top)
	)


func test_the_row_leaves_in_the_same_tick_with_flag_3_and_no_loss() -> void:
	var made: World = _world()
	var id: int = _id(made, "power_plant")
	var row: int = made.index_of(id)
	var cell: int = made.cell_of(made.pos_x[row], made.pos_y[row])
	var lost: int = made.stat_lost_buildings[1]
	assert_int(made.move_cost[cell]).is_equal(0)  # The footprint blocks.
	Rig.step(made, [Command.sell(1, id)])
	assert_int(made.index_of(id)).is_equal(-1)
	var records: Array[Array] = Rig.died(made)
	assert_int(records.size()).is_equal(1)
	assert_int(records[0][1]).is_equal(id)
	assert_int(records[0][Removal.DIED_FLAG_AT]).is_equal(3)
	assert_int(made.stat_lost_buildings[1]).is_equal(lost)
	assert_int(made.credits[1]).is_greater(0)
	assert_int(made.move_cost[cell]).is_not_equal(0)  # Unblocked by REMOVE.
	# A building shot to 0 hit points counts, for contrast.
	var other: World = _world()
	other.hp[other.index_of(_id(other, "power_plant"))] = 0
	Rig.step(other, [])
	assert_int(other.stat_lost_buildings[1]).is_equal(lost + 1)
	assert_int(Rig.died(other)[0][Removal.DIED_FLAG_AT]).is_equal(0)


func test_the_flag_mapping_is_1_2_3_and_0_for_anything_else() -> void:
	(
		assert_array(
			[
				Removal.died_flag(Production.CANCELLED),
				Removal.died_flag(Carry.BOARDED),
				Removal.died_flag(Production.SOLD),
				Removal.died_flag(0),
				Removal.died_flag(100),
				Removal.died_flag(-4),
			]
		)
		. is_equal([1, 2, 3, 0, 0, 0])
	)
	assert_array([Production.CANCELLED, Carry.BOARDED, Production.SOLD]).is_equal([-1, -2, -3])
	# A cancelled site still gives 1 through the real REMOVE.
	var made: World = Rig.world()
	Rig.step(made, [Command.cancel_build(1, Rig.OWN_SITE)])
	assert_int(Rig.died(made)[0][Removal.DIED_FLAG_AT]).is_equal(1)


func test_the_refusals_are_dropped_and_counted() -> void:
	var made: World = _world()
	var plant: int = _id(made, "power_plant")
	var hq: int = _id(made, "headquarters")
	assert_int(SiteRig.cost(made, "headquarters")).is_equal(0)
	_assert_dropped("headquarters", Command.sell(1, hq))
	_assert_dropped("site", Command.sell(1, Rig.OWN_SITE))
	_assert_dropped("enemy site", Command.sell(1, Rig.ENEMY_SITE))
	_assert_dropped("unit", Command.sell(1, 8))
	_assert_dropped("enemy building", Command.sell(1, _id(made, "power_plant", 2)))
	_assert_dropped("enemy headquarters", Command.sell(1, _id(made, "renew_hq", 2)))
	_assert_dropped("unknown id", Command.sell(1, 999))
	var payload: Command = Command.sell(1, plant)
	payload.payload = PackedInt32Array([1])
	_assert_dropped("payload", payload)
	_assert_dropped(
		"defeated", Command.sell(1, plant), func(w: World) -> void: w.defeated_tick[1] = 1
	)
	# Sold once, the second command of one tick finds no building.
	var twice: World = _world()
	Rig.step(twice, [Command.sell(1, plant), Command.sell(1, plant)])
	assert_int(twice.dropped_commands).is_equal(1)


func test_a_sale_keeps_the_queue_and_its_paid_items() -> void:
	var made: World = _world()
	Rig.step(made, [SiteRig.Rig.queue(made, 1, "rifle_squad")])
	var tab: int = World.Tab.INFANTRY
	var count: int = made.queue_count[1 * World.TABS + tab]
	assert_int(count).is_equal(1)
	var credits: int = made.credits[1]
	Rig.step(made, [Command.sell(1, _id(made, "barracks"))])
	assert_int(made.queue_count[1 * World.TABS + tab]).is_equal(count)
	# Exactly the building's refund: nothing for the queue.
	assert_int(made.credits[1]).is_equal(
		credits + _expected(made, "barracks", _full_barracks_hp(made))
	)


## The last production building: HQ gone, then the barracks sold, and the player loses.
func test_selling_the_last_producer_defeats_the_player() -> void:
	var made: World = _world()
	made.hp[made.index_of(_id(made, "headquarters"))] = 0
	Rig.step(made, [])
	assert_int(made.defeated_tick[1]).is_equal(0)
	Rig.step(made, [Command.sell(1, _id(made, "barracks"))])
	assert_int(made.defeated_tick[1]).is_greater(0)


func test_two_runs_of_one_script_hash_alike() -> void:
	var hashes: Array[int] = []
	for _run: int in 2:
		var made: World = _world()
		Rig.step(made, [Command.sell(1, _id(made, "power_plant"))])
		SiteRig.run(made, 20)
		hashes.append(made.state_hash())
	assert_int(hashes[0]).is_equal(hashes[1])


## The queue test's barracks was at full health.
func _full_barracks_hp(made: World) -> int:
	return SiteRig.hit_points(made, "barracks")


func test_sale_refund_clamps_and_matches_the_formula() -> void:
	assert_int(Production.sale_refund(200, 50, 100, 100)).is_equal(100)
	assert_int(Production.sale_refund(200, 50, 1, 100)).is_equal(1)
	assert_int(Production.sale_refund(200, 50, 50, 100)).is_equal(50)
	assert_int(Production.sale_refund(200, 50, 500, 100)).is_equal(100)  # hp held to max.
	assert_int(Production.sale_refund(200, 50, -5, 100)).is_equal(0)
	assert_int(Production.sale_refund(200, 50, 10, 0)).is_equal(100)  # max_hp held to 1, hp to 1.
	assert_int(Production.sale_refund(200, 0, 100, 100)).is_equal(0)
	assert_int(Production.sale_refund(7, 50, 99, 100)).is_equal(3)  # Floor.


## A sold row never held a site slot: with one site allowed, a SELL and a PLACE of one tick place.
func test_a_sale_and_a_place_of_one_tick_both_work_with_one_site_allowed() -> void:
	var made: World = SiteRig.world()
	made.sell_refund_percent = PERCENT
	made.construction_sites_max = 1
	var sell: Command = Command.sell(1, _id(made, "refinery"))
	var place: Command = SiteRig.place(made, "power_plant", SiteRig.SPOT)
	sell.sequence = 0
	place.sequence = 1
	Rig.step(made, [sell, place])
	assert_int(made.dropped_commands).is_equal(0)
	assert_int(SiteRig.sites(made).size()).is_equal(1)
	# A cancelled row still holds its slot (the P128b rule is unchanged).
	var cancel: World = Rig.world()
	cancel.construction_sites_max = 1
	var again: Command = SiteRig.place(cancel, "barracks", SiteRig.WIDE)
	Rig.step(cancel, [Command.cancel_build(1, Rig.OWN_SITE), again])
	assert_int(cancel.dropped_commands).is_equal(1)


## A turret that fires in a tick fires nothing in the tick it is sold (FIRE runs before REMOVE and
## skips a row with `build_left` not 0).
func test_a_sold_turret_fires_nothing_in_its_last_tick() -> void:
	var first_shot: int = -1
	var control: World = _turret_world()
	var turret: int = _id(control, "defence_turret")
	for _tick: int in 60:
		var tick: int = control.tick
		SiteRig.step(control)
		if _shots_of(control, turret) > 0:
			first_shot = tick
			break
	assert_int(first_shot).is_greater(-1)
	var sold: World = _turret_world()
	SiteRig.run(sold, first_shot - sold.tick)
	assert_int(sold.tick).is_equal(first_shot)
	SiteRig.step(sold, [Command.sell(1, turret)])
	assert_int(_shots_of(sold, turret)).is_equal(0)
	assert_int(sold.index_of(turret)).is_equal(-1)


func _turret_world() -> World:
	var made: World = _world()
	made.add_building(1, SiteRig.type_of(made, "defence_turret"), 8, 8)
	made.add_unit(2, SiteRig.type_of(made, "rifle_squad"), 12500, 9500)
	return made


func _shots_of(made: World, shooter: int) -> int:
	var found: int = 0
	for at: int in range(0, made.events.size(), World.EVENT_STRIDE):
		if made.events[at] == World.Event.SHOT and made.events[at + 1] == shooter:
			found += 1
	return found


## SELL and MEND go through MatchLoop (stamped and recorded), are encoded in the log, decoded by
## Replay.play and give the checkpoints and the final hash again.
func test_a_sale_and_a_mend_replay_to_the_same_hash() -> void:
	var made: World = _replay_world()
	var loop: MatchLoop = MatchLoop.create(null, "", 1, made)
	var plant: int = _id(made, "power_plant")
	var barracks: int = _id(made, "barracks")
	for tick: int in range(made.tick, 45):
		var queued: Array[Command] = []
		if tick == 2:
			queued.append(Command.mend(1, plant, true))
		if tick == 20:
			queued.append(Command.sell(1, barracks))
		loop.step(made, queued)
	loop.replay.finish(made)
	var types: Array[int] = []
	var data: PackedInt32Array = loop.replay.commands
	var at: int = 0
	while at < data.size():
		var decoded: Command = Command.new()
		at = Command.decode(data, at, decoded)
		types.append(decoded.type)
	assert_array(types).is_equal([Command.Type.MEND, Command.Type.SELL])
	assert_int(made.dropped_commands).is_equal(0)
	assert_int(made.hp[made.index_of(plant)]).is_greater(
		SiteRig.hit_points(made, "power_plant") - 100
	)
	assert_int(made.index_of(barracks)).is_equal(-1)
	var played: World = _replay_world()
	assert_int(Replay.play(Replay.from_bytes(loop.replay.to_bytes()), played, made.tick)).is_equal(
		Replay.PLAY_MATCHED
	)
	assert_int(played.state_hash()).is_equal(loop.replay.final_hash)


func _replay_world() -> World:
	var made: World = _world()
	made.mend_hp = 10
	made.mend_period_ticks = 15
	made.mend_cost_percent = 30
	made.hp[made.index_of(_id(made, "power_plant"))] -= 100
	return made
