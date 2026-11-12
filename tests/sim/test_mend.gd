extends GdUnitTestSuite
## Building repair (plan row P271, ADR 0037 section 4): `MEND` 18 writes an own complete building's
## `cargo` (1 on, 0 off). `Mend.run` (ECONOMY, after `Harvest.run`) lets a mending building act on
## ticks with `(tick + id) % mend_period_ticks == 0`: it gains `mend_hp` (not above the maximum) and
## the owner pays `ceil(price * gained * mend_cost_percent / (100 * max hp))`; with too few credits
## nothing happens; at full health the switch goes back to 0; a Headquarters (price 0) mends free; a
## blackout does not stop it. The rule ints default to inert, `PlayerView.row_mend` is own-only, and
## the state hash of the perf_bases arena does not move. Worlds are `site_rig.gd`'s (ids 1 to 5: the
## Headquarters, a Power Plant, a Barracks and a Refinery of player 1, an enemy Headquarters); the
## rule ints are set by hand to ADR 0037's starting values.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const BASES_PATH: String = "res://data/scenarios/perf_bases.tres"
const HP: int = 10
const PERIOD: int = 15
const PERCENT: int = 30
const PLANT: int = 2
const BARRACKS: int = 3
const HQ: int = 1
const ENEMY_HQ: int = 5


func _world() -> World:
	var made: World = SiteRig.world()
	made.mend_hp = HP
	made.mend_period_ticks = PERIOD
	made.mend_cost_percent = PERCENT
	return made


## Switch on, with `lost` hit points taken off the building `id`.
func _hurt(made: World, id: int, lost: int) -> int:
	var row: int = made.index_of(id)
	made.hp[row] -= lost
	made.cargo[row] = 1
	return row


## The price of `gained` hit points of the building `row`, written out from the tables.
func _price(made: World, row: int, gained: int) -> int:
	var type: int = made.type_index[row]
	var top: int = made.type_max_hp[type]
	var num: int = made.type_cost[type] * gained * PERCENT
	var den: int = 100 * top
	return num / den + (1 if num % den != 0 else 0)


func test_the_command_has_its_number_and_a_factory() -> void:
	assert_int(Command.Type.MEND).is_equal(18)
	var on: Command = Command.mend(1, 7, true)
	assert_array([on.type, on.target_id, Array(on.payload)]).is_equal([18, 7, [1]])
	assert_array(Array(Command.mend(1, 7, false).payload)).is_equal([0])


func test_the_rule_defaults_are_inert() -> void:
	var rules: RulesDef = RulesDef.new()
	assert_array([rules.sell_refund_percent, rules.mend_hp]).is_equal([0, 0])
	var made: World = SiteRig.world()
	var row: int = _hurt(made, PLANT, 50)
	var hp: int = made.hp[row]
	SiteRig.run(made, 3 * PERIOD)
	assert_int(made.hp[row]).is_equal(hp)
	assert_int(made.cargo[row]).is_equal(1)  # Not even a full-health reset: nothing runs.


func test_a_mend_command_switches_an_own_complete_building() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 100)
	made.cargo[row] = 0
	SiteRig.step(made, [Command.mend(1, PLANT, true)])
	assert_int(made.cargo[row]).is_equal(1)
	SiteRig.step(made, [Command.mend(1, PLANT, false)])
	assert_int(made.cargo[row]).is_equal(0)
	# At full health the command is accepted and the switch drops back at the next acting tick.
	var full: World = _world()
	SiteRig.step(full, [Command.mend(1, PLANT, true)])
	assert_int(full.cargo[full.index_of(PLANT)]).is_equal(1)
	assert_int(full.dropped_commands + made.dropped_commands).is_equal(0)


func test_refusals_are_dropped_and_counted_and_write_nothing() -> void:
	var cases: Array[Command] = [
		Command.mend(1, ENEMY_HQ, true),
		Command.mend(1, 999, true),
		Command.mend(1, PLANT, true),
	]
	cases[2].payload = PackedInt32Array([2])
	var extra: Command = Command.mend(1, PLANT, true)
	extra.payload = PackedInt32Array([1, 1])
	cases.append(extra)
	var empty: Command = Command.mend(1, PLANT, true)
	empty.payload = PackedInt32Array()
	cases.append(empty)
	for command: Command in cases:
		var made: World = _world()
		var before: PackedInt32Array = made.cargo.duplicate()
		SiteRig.step(made, [command])
		assert_int(made.dropped_commands).is_equal(1)
		assert_array(made.cargo).is_equal(before)
	# A site and a unit.
	var rig: World = _world()
	SiteRig.step(rig, [SiteRig.place(rig, "power_plant", SiteRig.SPOT)])
	var site: int = rig.unit_id[SiteRig.sites(rig)[0]]
	var unit: int = rig.add_unit(1, SiteRig.type_of(rig, "rifle_squad"), 3500, 11500)
	SiteRig.step(rig, [Command.mend(1, site, true), Command.mend(1, unit, true)])
	assert_int(rig.dropped_commands).is_equal(2)
	var defeated: World = _world()
	defeated.defeated_tick[1] = 1
	SiteRig.step(defeated, [Command.mend(1, PLANT, true)])
	assert_int(defeated.dropped_commands).is_equal(1)


## Hit points rise by `mend_hp` on exactly the ticks with `(tick + id) % period == 0`, each step
## paid by the price formula; the two buildings (ids 2 and 3) act on different ticks.
func test_steps_are_staggered_by_id_and_priced() -> void:
	var made: World = _world()
	var plant: int = _hurt(made, PLANT, 200)
	var barracks: int = _hurt(made, BARRACKS, 200)
	var acted: Dictionary[int, Array] = {PLANT: [], BARRACKS: []}
	for _step: int in 2 * PERIOD:
		var tick: int = made.tick
		var before: Array[int] = [made.hp[plant], made.hp[barracks], made.credits[1]]
		SiteRig.step(made)
		var paid: int = before[2] - made.credits[1]
		var cost: int = 0
		if made.hp[plant] != before[0]:
			assert_int(made.hp[plant] - before[0]).is_equal(HP)
			acted[PLANT].append(tick)
			cost += _price(made, plant, HP)
		if made.hp[barracks] != before[1]:
			assert_int(made.hp[barracks] - before[1]).is_equal(HP)
			acted[BARRACKS].append(tick)
			cost += _price(made, barracks, HP)
		assert_int(paid).is_equal(cost)
	for id: int in acted:
		var ticks: Array = acted[id]
		assert_int(ticks.size()).is_equal(2)
		for tick: int in ticks:
			assert_int((tick + id) % PERIOD).is_equal(0)
	assert_array(acted[PLANT]).is_not_equal(acted[BARRACKS])


func test_the_price_rounds_up_per_step_on_edge_ints() -> void:
	for case: Array in [
		[1000, 100, 10, 10], [7, 100, 10, 30], [1, 100000, 10, 30], [999, 100, 10, 30]
	]:
		var made: World = _world()
		var type: int = made.type_index[made.index_of(PLANT)]
		made.type_cost[type] = case[0]
		made.type_max_hp[type] = case[1]
		made.mend_hp = case[2]
		made.mend_cost_percent = case[3]
		var row: int = _hurt(made, PLANT, 50)
		made.hp[row] = case[1] - 50
		var credits: int = made.credits[1]
		var expected: int = ceili(float(case[0] * case[2] * case[3]) / float(100 * case[1]))
		# The row acts when (tick + id) % period is 0.
		for _step: int in PERIOD:
			SiteRig.step(made)
		assert_int(credits - made.credits[1]).override_failure_message(str(case)).is_equal(expected)
		assert_int(made.hp[row]).is_equal(case[1] - 50 + case[2])


func test_a_step_never_goes_above_full_and_the_switch_goes_back_to_0() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 4)
	var top: int = made.type_max_hp[made.type_index[row]]
	var credits: int = made.credits[1]
	SiteRig.run(made, PERIOD)
	assert_int(made.hp[row]).is_equal(top)
	assert_int(made.cargo[row]).is_equal(0)
	assert_int(credits - made.credits[1]).is_equal(_price(made, row, 4))
	var after: int = made.credits[1]
	SiteRig.run(made, 2 * PERIOD)
	assert_int(made.credits[1]).is_equal(after)
	# A switch on at full health is reset at the row's next acting tick.
	made.cargo[row] = 1
	SiteRig.run(made, PERIOD)
	assert_array([made.cargo[row], made.credits[1]]).is_equal([0, after])


func test_with_too_few_credits_nothing_happens_and_the_switch_stays() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 100)
	var hp: int = made.hp[row]
	made.credits[1] = 0
	SiteRig.run(made, 2 * PERIOD)
	assert_array([made.hp[row], made.cargo[row], made.credits[1]]).is_equal([hp, 1, 0])
	made.credits[1] = 10000
	SiteRig.run(made, PERIOD)
	assert_int(made.hp[row]).is_greater(hp)


func test_a_headquarters_mends_free() -> void:
	var made: World = _world()
	assert_int(SiteRig.cost(made, "headquarters")).is_equal(0)
	var row: int = _hurt(made, HQ, 100)
	var hp: int = made.hp[row]
	var credits: int = made.credits[1]
	SiteRig.run(made, PERIOD)
	assert_int(made.hp[row]).is_equal(hp + HP)
	assert_int(made.credits[1]).is_equal(credits)


func test_a_blacked_out_building_keeps_mending() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 100)
	made.offline_until[row] = made.tick + 1000
	var hp: int = made.hp[row]
	SiteRig.run(made, PERIOD)
	assert_int(made.hp[row]).is_equal(hp + HP)


func test_a_building_that_is_not_complete_does_not_mend() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 100)
	var hp: int = made.hp[row]
	made.tick = PERIOD - PLANT  # An acting tick for id 2.
	Buildings.rebuild_lists(made)  # Power.run does it before Mend.run.
	made.build_left[row] = Production.CANCELLED
	Mend.run(made)
	assert_array([made.hp[row], made.cargo[row]]).is_equal([hp, 1])
	made.build_left[row] = 0
	Mend.run(made)
	assert_int(made.hp[row]).is_equal(hp + HP)


## `row_mend` reads an own building's switch; an enemy's switch, which the snapshot holds, reads
## MISSING.
func test_the_view_reads_only_the_own_switch() -> void:
	var made: World = _world()
	var own: int = _hurt(made, PLANT, 100)
	var enemy: int = made.index_of(ENEMY_HQ)
	made.cargo[enemy] = 1
	var view: PlayerView = PlayerView.of(made, 1)
	assert_int(view.row_mend(view.row_of(PLANT))).is_equal(1)
	assert_int(view.row_mend(view.row_of(BARRACKS))).is_equal(0)
	assert_int(view.row_mend(view.row_of(ENEMY_HQ))).is_equal(PlayerView.MISSING)
	assert_int(PlayerView.of(made, 2).row_mend(view.row_of(PLANT))).is_equal(PlayerView.MISSING)
	assert_int(own).is_equal(made.index_of(PLANT))


## The state hash does not see the rule ints, and no building of the arena has its switch on, so
## setting every sale and mend int leaves the hash where it was. The arena is `perf_bases`: it has
## buildings (hurt by hand: nothing shoots them in 150 ticks) and harvesters whose `cargo` (the
## column the switch shares) is above 0, so `Mend.run` has rows to read and must leave every one
## alone.
func test_the_state_hash_is_neutral_to_the_new_rules_on_an_arena_with_buildings() -> void:
	var scenario: ScenarioDef = load(BASES_PATH) as ScenarioDef
	var plain: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	var tuned: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	tuned.sell_refund_percent = 50
	tuned.mend_hp = HP
	tuned.mend_period_ticks = PERIOD
	tuned.mend_cost_percent = PERCENT
	assert_int(tuned.defs_hash()).is_not_equal(plain.defs_hash())
	for world: World in [plain, tuned]:
		for row: int in world.unit_count():  # Nothing shoots a building here: hurt them by hand.
			if world.type_foot_w[world.type_index[row]] > 0:
				world.hp[row] -= 50
	var plain_loop: MatchLoop = MatchLoop.create(scenario, BASES_PATH, 42, plain)
	var tuned_loop: MatchLoop = MatchLoop.create(scenario, BASES_PATH, 42, tuned)
	var none: Array[Command] = []
	var loaded: bool = false
	var damaged: bool = false
	for _tick: int in 150:
		plain_loop.step(plain, none)
		tuned_loop.step(tuned, none)
		assert_int(tuned.state_hash()).is_equal(plain.state_hash())
		for row: int in tuned.unit_count():
			var type: int = tuned.type_index[row]
			if tuned.type_foot_w[type] > 0:
				damaged = damaged or tuned.hp[row] < tuned.type_max_hp[type]
				assert_int(tuned.cargo[row]).is_equal(0)  # Nobody switched a mend on.
			else:
				loaded = loaded or tuned.cargo[row] > 0
	assert_int(tuned.building_rows.size()).is_greater(0)
	assert_bool(loaded).is_true()
	assert_bool(damaged).is_true()
	var sale: Array[StringName] = [
		&"sell_refund_percent", &"mend_hp", &"mend_period_ticks", &"mend_cost_percent"
	]
	for list: Array[StringName] in [World.RULE_SCALARS, World.UNHASHED_SCALARS]:
		var at: int = list.find(&"sell_refund_percent")  # Found by name: later rules move nothing.
		assert_array(list.slice(at, at + sale.size())).is_equal(sale)


func test_the_step_price_is_the_exact_boundary_for_the_credits() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 100)
	var hp: int = made.hp[row]
	var price: int = _price(made, row, HP)
	assert_int(price).is_greater(0)
	made.credits[1] = price - 1
	SiteRig.run(made, PERIOD)
	assert_array([made.hp[row], made.credits[1]]).is_equal([hp, price - 1])
	made.credits[1] = price
	SiteRig.run(made, PERIOD)
	assert_array([made.hp[row], made.credits[1]]).is_equal([hp + HP, 0])


func test_a_headquarters_mends_free_with_no_credits() -> void:
	var made: World = _world()
	var row: int = _hurt(made, HQ, 100)
	var hp: int = made.hp[row]
	made.credits[1] = 0
	SiteRig.run(made, PERIOD)
	assert_array([made.hp[row], made.credits[1]]).is_equal([hp + HP, 0])


func test_a_period_of_0_with_hit_points_set_mends_nothing_and_does_not_divide_by_it() -> void:
	var made: World = _world()
	made.mend_period_ticks = 0
	var row: int = _hurt(made, PLANT, 100)
	var hp: int = made.hp[row]
	SiteRig.run(made, 2 * PERIOD)
	assert_array([made.hp[row], made.cargo[row]]).is_equal([hp, 1])


func test_a_defeated_players_buildings_do_not_mend() -> void:
	var made: World = _world()
	var row: int = _hurt(made, PLANT, 100)
	var hp: int = made.hp[row]
	made.defeated_tick[1] = 1
	var credits: int = made.credits[1]
	SiteRig.run(made, 2 * PERIOD)
	assert_array([made.hp[row], made.credits[1]]).is_equal([hp, credits])


## `cargo` is a harvester's load, not a switch: `row_mend` answers MISSING for a row with no
## footprint.
func test_the_view_answers_missing_for_a_row_that_is_not_a_building() -> void:
	var made: World = _world()
	var unit: int = made.add_unit(1, SiteRig.type_of(made, "harvester"), 3500, 11500)
	made.cargo[made.index_of(unit)] = 500
	var view: PlayerView = PlayerView.of(made, 1)
	assert_int(view.row_mend(view.row_of(unit))).is_equal(PlayerView.MISSING)
