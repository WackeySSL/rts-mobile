extends GdUnitTestSuite
## What a blackout does to the power totals (plan row P111, ADR 0023 section 10, ADR 0016): a
## building whose `offline_until` is above the stamp of the step (`world.tick + 1`) counts neither
## its output nor its use in that step's ECONOMY, so the totals of the blacked-out player fall for
## exactly `type_strike_ticks` steps, from the firing step's own, and come back at the stamp that
## reaches `offline_until`. The totals stay derived: in no hash section, and rebuilt from the rows
## at every checkpoint of a match with blackouts, the last offline stamp on a checkpoint included.
## The rig is `strike_worlds.gd` with its array (radius, length and charge from the World's tables)
## and these buildings at the rig's point `POINT` (15500, 10500): player 2's plant and shed in the
## radius, a plant and a shed of player 2 far outside it, and player 1's own plant in the radius.
## The shed uses `SHED_USE` power (the rig's types have no other consumer).

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const SHED_USE: int = 30


## The rig world with the five extra buildings and the shed's power set, at tick 0.
func _world() -> World:
	var world: World = Strikes.world()
	world.type_power[Strikes.type_of(world, "shed")] = -SHED_USE
	var plant: int = Strikes.type_of(world, "plant")
	var shed: int = Strikes.type_of(world, "shed")
	world.add_building(2, plant, 14, 9)  # Id 6: centre (15500, 10500), in the radius.
	world.add_building(2, shed, 17, 10)  # Id 7: 2000 east of the point, in the radius.
	world.add_building(2, plant, 24, 2)  # Id 8: 10000 east of the point, outside.
	world.add_building(2, shed, 24, 8)  # Id 9: outside.
	world.add_building(1, plant, 12, 12)  # Id 10: player 1's own, 2000 and 3000 from the point.
	return world


## What a plant makes, from the World's table.
func _plant_power(world: World) -> int:
	return world.type_power[Strikes.type_of(world, "plant")]


## The totals of `player` as the last step's ECONOMY built them: [made, used].
func _totals(world: World, player: int) -> Array[int]:
	return [world.power_made[player], world.power_used[player]]


## What a scan of the rows gives for `player` for the step that just ended: its stamp is
## `world.tick` now (the tick moved on at the end of the step), and a building whose `offline_until`
## is above it counts for nothing.
func _scan(world: World, player: int) -> Array[int]:
	var made: int = 0
	var used: int = 0
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.owner[row] != player or world.type_foot_w[type] == 0:
			continue
		if world.offline_until[row] > world.tick:
			continue
		if world.type_power[type] > 0:
			made += world.type_power[type]
		else:
			used -= world.type_power[type]
	return [made, used]


## Wipes the totals and builds them again from the rows as the ECONOMY of the step that just ended
## did: that step ran with the tick one back, so the call does too (a `Power.run` called after the
## step takes the next step's stamp, and differs on a building whose last offline stamp it was).
func _rebuild(world: World) -> void:
	world.power_made.fill(-1)
	world.power_used.fill(-1)
	world.tick -= 1
	Power.run(world)
	world.tick += 1


## Steps, after `commands`, and returns player 2's totals.
func _step(world: World, commands: Array = []) -> Array[int]:
	Strikes.step(world, commands)
	return _totals(world, 2)


## The totals fall in the firing step's own ECONOMY (a tick earlier they are whole), stay down for
## exactly the length of the blackout and are whole again on the stamp that reaches `offline_until`;
## the firing player's own plant in the radius counts throughout. The fallen totals are the ones of
## the buildings outside the radius, from the tables.
func test_the_totals_fall_for_exactly_the_length_of_the_blackout() -> void:
	var world: World = _world()
	var length: int = world.type_strike_ticks[Strikes.type_of(world, "array")]
	var plant: int = _plant_power(world)
	var whole: Array[int] = [2 * plant, 2 * SHED_USE]
	var fallen: Array[int] = [plant, SHED_USE]
	var tick: int = Strikes.fire_tick(world, Strikes.ARRAY)
	Strikes.run_to(world, tick - 1)
	assert_array(_step(world)).is_equal(whole)  # The step before the command.
	assert_array(_totals(world, 1)).is_equal([plant, 0])
	var down: int = 0
	var totals: Array[int] = _step(world, [Strikes.fire(Strikes.ARRAY)])
	while totals == fallen:
		down += 1
		assert_array(_totals(world, 1)).is_equal([plant, 0])
		totals = _step(world)
	assert_int(down).is_equal(length)
	assert_int(world.tick).is_equal(tick + 1 + length)  # The step with the stamp offline_until.
	assert_array(totals).is_equal(whole)
	for _again: int in 10:
		assert_array(_step(world)).is_equal(whole)


## A player whose only plant is blacked out is on low power exactly as long as the blackout lasts:
## the plant outside the radius is gone, so the plant in the radius is the one that makes power,
## and while it is offline the player makes 0 against the shed outside the radius, which uses 30.
func test_a_player_whose_only_plant_goes_offline_is_low_for_exactly_the_length() -> void:
	var world: World = _world()
	var length: int = world.type_strike_ticks[Strikes.type_of(world, "array")]
	world.hp[world.index_of(8)] = 0  # The plant outside the radius is gone after the first step.
	var tick: int = Strikes.fire_tick(world, Strikes.ARRAY)
	Strikes.run_to(world, tick - 1)
	_step(world)
	assert_bool(Power.is_low(world, 2)).is_false()
	_step(world, [Strikes.fire(Strikes.ARRAY)])
	var low: int = 0
	while Power.is_low(world, 2):
		low += 1
		assert_array(_totals(world, 2)).is_equal([0, SHED_USE])
		_step(world)
	assert_int(low).is_equal(length)
	assert_array(_totals(world, 2)).is_equal([_plant_power(world), 2 * SHED_USE])


## A second blackout while the first one lasts (the array is charged again after its charge, which
## is shorter than the length in the rig) moves `offline_until` to the later value: the totals fall
## from the first stamp to the last one of the second blackout, with no gap and no early end.
func test_a_second_blackout_inside_the_first_extends_it() -> void:
	var world: World = _world()
	var array: int = Strikes.type_of(world, "array")
	var length: int = world.type_strike_ticks[array]
	var charge: int = world.type_charge_ticks[array]
	assert_int(charge).is_less(length)
	var first: int = Strikes.fire_tick(world, Strikes.ARRAY)
	var second: int = first + charge
	Strikes.run_to(world, first)
	var down: int = 0
	for tick: int in range(first, first + 3 * length):
		var orders: Array = [Strikes.fire(Strikes.ARRAY)] if tick in [first, second] else []
		Strikes.step(world, orders)
		if world.power_made[2] < 2 * _plant_power(world):
			down += 1
		else:
			break
	assert_int(down).is_equal(charge + length)
	assert_int(world.offline_until[world.index_of(6)]).is_equal(second + 1 + length)
	assert_int(world.dropped_commands).is_equal(0)


## The totals are derived: a rebuild from the rows, with the stamp of the step that built them,
## restores them whatever was in the arrays, and the state hash does not read them.
func test_the_blacked_out_totals_are_derived_from_the_rows() -> void:
	var world: World = _world()
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	var held: Array[int] = _totals(world, 2)
	assert_array(held).is_equal([_plant_power(world), SHED_USE])
	var hash_before: int = world.state_hash()
	_rebuild(world)
	assert_array(_totals(world, 2)).is_equal(held)
	assert_int(world.state_hash()).is_equal(hash_before)
	world.power_made.fill(777)
	world.power_used.fill(555)
	assert_int(world.state_hash()).is_equal(hash_before)


## One match with two blackouts of player 2's cluster, the first from the stamp 45 (a checkpoint)
## and the second until the stamp 300 (a checkpoint too, as its last offline stamp). At every
## checkpoint the totals equal a scan of the rows and a rebuild from the rows (wiped, run again with
## the step's stamp), and the state hash is the same before and after the rebuild. At the checkpoint
## that is the last offline stamp, a `Power.run` that took the next stamp would have given the
## totals of a player that is already back: the totals are a function of the step they were
## built in.
func test_every_checkpoint_of_a_match_with_blackouts_equals_a_rebuild_from_the_rows() -> void:
	var world: World = _world()
	var length: int = world.type_strike_ticks[Strikes.type_of(world, "array")]
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	var firing: Array[int] = [44, 300 - length]  # The ticks of the two commands.
	var seen: Dictionary[String, int] = {"checkpoints": 0, "down": 0, "boundary": 0}
	for tick: int in 450:
		var orders: Array[Command] = []
		if firing.has(tick):
			orders.append(Strikes.fire(Strikes.ARRAY))
		loop.step(world, orders)
		if world.tick % Replay.CHECKPOINT_PERIOD != 0:
			continue
		seen["checkpoints"] += 1
		var hash_before: int = world.state_hash()
		for player: int in [1, 2]:
			(
				assert_array(_totals(world, player))
				. override_failure_message(
					"tick %d, player %d against a scan" % [world.tick, player]
				)
				. is_equal(_scan(world, player))
			)
		var held: Array[int] = _totals(world, 2)
		if held[0] < 2 * _plant_power(world):
			seen["down"] += 1
		_rebuild(world)
		(
			assert_array(_totals(world, 2))
			. override_failure_message("tick %d, a rebuild from the rows" % world.tick)
			. is_equal(held)
		)
		assert_int(world.state_hash()).is_equal(hash_before)
		if world.offline_until[world.index_of(6)] == world.tick + 1:
			seen["boundary"] += 1
			Power.run(world)  # The next step's stamp: the plant is already back.
			assert_array(_totals(world, 2)).is_not_equal(held)
			_rebuild(world)
	assert_int(seen["checkpoints"]).is_equal(30)
	assert_int(seen["down"]).is_greater_equal(10)
	assert_int(seen["boundary"]).is_equal(1)
