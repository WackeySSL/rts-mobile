extends GdUnitTestSuite
## Repair on the pad (plan row P241b, ADR 0036 section 6, `Air.run`): an aircraft within
## `repair_reach_milli` of its pad, with its airfield complete and online, gains `repair_hp` on
## ticks with `tick % repair_period_ticks == 0`, not above its maximum, and the owner pays
## `ceil(cost * gained * repair_cost_percent / (100 * max_hp))`; with too few credits nothing is
## repaired. The rig's airfield repairs 10 hp per 15 ticks for 40 percent, a jet has 100 hp and
## costs 100.

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func _hurt_jet(world: World, hp: int) -> int:
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.hp[jet] = hp
	world.credits[1] = 1000
	return jet


func test_a_hurt_aircraft_on_its_pad_gains_repair_hp_each_period_and_pays_for_it(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	var jet: int = _hurt_jet(world, 50)
	var seen: Array[int] = []
	for _tick: int in 31:
		Worlds.step(world)
		if seen.is_empty() or seen[-1] != world.hp[jet]:
			seen.append(world.hp[jet])
	assert_array(seen).is_equal([60, 70, 80])  # Ticks 0, 15 and 30.
	assert_int(world.credits[1]).is_equal(1000 - 3 * 4)  # ceil(100 * 10 * 40 / (100 * 100)) = 4.


func test_the_last_step_stops_at_the_maximum_and_a_full_aircraft_pays_nothing() -> void:
	var world: World = Worlds.world()
	var jet: int = _hurt_jet(world, 96)
	Worlds.run(world, 31)
	assert_int(world.hp[jet]).is_equal(100)
	# Gained 4 of 10: ceil(100 * 4 * 40 / 10000) = 2.
	assert_int(world.credits[1]).is_equal(1000 - 2)


func test_the_price_is_rounded_up_per_step() -> void:
	var world: World = Worlds.world()
	var jet: int = _hurt_jet(world, 50)
	world.type_cost[world.type_index[jet]] = 101
	Worlds.step(world)
	assert_int(world.credits[1]).is_equal(1000 - 5)  # ceil(101 * 10 * 40 / 10000) = ceil(4.04).


func test_no_repair_while_the_player_cannot_pay() -> void:
	var world: World = Worlds.world()
	var jet: int = _hurt_jet(world, 50)
	world.credits[1] = 3
	Worlds.run(world, 31)
	assert_array([world.hp[jet], world.credits[1]]).is_equal([50, 3])
	world.credits[1] = 4
	Worlds.run(world, 14)  # Ticks 31 to 44: the next period is tick 45.
	assert_int(world.hp[jet]).is_equal(50)
	Worlds.run(world, 1)
	assert_array([world.hp[jet], world.credits[1]]).is_equal([60, 0])


func test_a_repair_needs_the_pad_reach_and_an_online_complete_airfield() -> void:
	var field_row: int = 0
	for case: String in ["far", "blackout", "building"]:
		var world: World = Worlds.world()
		var jet: int = _hurt_jet(world, 50)
		field_row = world.index_of(Worlds.FIELD)
		world.type_speed[world.type_index[jet]] = 0
		match case:
			"far":
				world.pos_x[jet] += Worlds.REACH + 1
				world.order[jet] = World.Order.MOVE
				world.goal_x[jet] = 20000
				world.goal_y[jet] = 14000
			"blackout":
				world.offline_until[field_row] = 1000
			"building":
				world.build_left[field_row] = 500
		Worlds.run(world, 16)
		assert_int(world.hp[jet]).override_failure_message(case).is_equal(50)


## Reach is inclusive: exactly `repair_reach_milli` from the pad is repaired, one more is not.
func test_the_repair_reach_includes_its_edge_and_stops_one_milli_beyond() -> void:
	for gap: int in [Worlds.REACH, Worlds.REACH + 1]:
		var world: World = Worlds.world()
		var jet: int = _hurt_jet(world, 50)
		world.type_speed[world.type_index[jet]] = 0
		world.pos_x[jet] += gap
		world.order[jet] = World.Order.MOVE
		world.goal_x[jet] = 20000
		world.goal_y[jet] = 14000
		Worlds.step(world)
		var want: int = 60 if gap == Worlds.REACH else 50
		assert_int(world.hp[jet]).override_failure_message(str(gap)).is_equal(want)


func test_a_defeated_owner_is_not_repaired_or_charged() -> void:
	var world: World = Worlds.world()
	var jet: int = _hurt_jet(world, 50)
	world.defeated_tick[1] = 1
	Worlds.step(world)
	assert_array([world.hp[jet], world.credits[1]]).is_equal([50, 1000])


func test_a_fighter_with_no_ammo_limit_is_repaired_too() -> void:
	var world: World = Worlds.world()
	var fighter: int = Worlds.add_homed(world, "fighter", Worlds.FIELD)
	world.hp[fighter] = 40
	world.credits[1] = 1000
	Worlds.step(world)
	assert_int(world.hp[fighter]).is_equal(50)


func test_the_role_mask_decides_and_a_zero_repair_hp_repairs_nothing() -> void:
	for case: String in ["no air bit", "no hp"]:
		var world: World = Worlds.world()
		var jet: int = _hurt_jet(world, 50)
		var kind: int = world.type_index[world.index_of(Worlds.FIELD)]
		if case == "no air bit":
			world.type_repair_classes[kind] = 7
		else:
			world.type_repair_hp[kind] = 0
		Worlds.run(world, 16)
		assert_int(world.hp[jet]).override_failure_message(case).is_equal(50)
