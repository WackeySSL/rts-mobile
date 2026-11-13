extends GdUnitTestSuite
## The return and the reload of an aircraft (plan row P241, ADR 0036 section 6, `Air.run`): at ammo
## 0 with a home it gets MOVE to its pad and drops its target; on the pad, within the airfield's
## `repair_reach_milli`, with the airfield complete and online, it gains 1 ammo every
## `max(1, rearm_ticks / ammo)` ticks up to the cap, the next gain stamped in `ready_tick`; a
## fighter (no ammo limit) never returns on its own. Worlds are `air_worlds.gd`'s.

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const MOVE: int = World.Order.MOVE


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func _pad(world: World, pad: int = 0) -> Vector2i:
	return Air.pad_point(world, world.index_of(Worlds.FIELD), pad)


## The ticks, counted from the first step, after which the row's ammo was one more than before.
func _gain_ticks(world: World, row: int, ticks: int) -> Array[int]:
	var found: Array[int] = []
	var ammo: int = world.ammo[row]
	for tick: int in ticks:
		Worlds.step(world)
		if world.ammo[row] > ammo:
			found.append(tick)
		ammo = world.ammo[row]
	return found


func test_an_empty_aircraft_with_a_home_gets_move_to_its_pad_in_the_same_tick() -> void:
	var world: World = Worlds.world()
	var pad: Vector2i = _pad(world)
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.pos_x[jet] = 14000
	world.pos_y[jet] = 9000
	world.ammo[jet] = 0
	Worlds.step(world)
	assert_int(world.order[jet]).is_equal(MOVE)
	assert_array([world.goal_x[jet], world.goal_y[jet]]).is_equal([pad.x, pad.y])
	assert_int(world.order_target[jet]).is_equal(0)


func test_an_aircraft_that_empties_its_guns_returns_drops_its_target_and_reloads_to_the_cap(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	var pad: Vector2i = _pad(world)
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.pos_x[jet] = 11000
	world.pos_y[jet] = 6000
	var dummy: int = Worlds.add(world, 2, "dummy", 13000, 6000)
	world.order[jet] = World.Order.ATTACK_MOVE
	world.goal_x[jet] = 11000
	world.goal_y[jet] = 6000
	var returned: int = -1
	for tick: int in 400:
		Worlds.step(world)
		if returned < 0 and world.order[jet] == MOVE:
			returned = tick
			assert_int(world.ammo[jet]).is_equal(0)
	assert_int(returned).is_greater(0)
	assert_int(world.target[jet]).is_equal(0)  # Dropped, and not taken again with no ammo.
	assert_int(world.hp[dummy]).is_less(100000)
	assert_array([world.pos_x[jet], world.pos_y[jet]]).is_equal([pad.x, pad.y])
	assert_int(world.ammo[jet]).is_equal(Worlds.AMMO)


func test_the_reload_gains_one_every_rearm_over_cap_ticks_and_stops_at_the_cap() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.ammo[jet] = 0
	var interval: int = world.type_rearm_ticks[world.type_index[jet]] / Worlds.AMMO
	assert_int(interval).is_equal(10)
	var gains: Array[int] = _gain_ticks(world, jet, 60)
	assert_array(gains).is_equal([0, 10, 20])
	assert_int(world.ammo[jet]).is_equal(Worlds.AMMO)
	assert_int(world.ready_tick[jet]).is_equal(21 + interval)  # The stamp (tick + 1) of the gain.


func test_a_rearm_time_below_the_cap_gains_one_every_tick() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.type_rearm_ticks[world.type_index[jet]] = 2
	world.ammo[jet] = 0
	assert_array(_gain_ticks(world, jet, 6)).is_equal([0, 1, 2])
	assert_int(world.ready_tick[jet]).is_equal(3 + 1)


## Reach is inclusive: a jet exactly `repair_reach_milli` from its pad reloads, one milli further
## does not. The jets are held on a MOVE that never ends (speed 0), so nothing seats or moves them.
func test_the_reload_reach_includes_its_edge_and_stops_one_milli_beyond() -> void:
	for gap: int in [Worlds.REACH, Worlds.REACH + 1]:
		var world: World = Worlds.world()
		var pad: Vector2i = _pad(world)
		var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
		world.type_speed[world.type_index[jet]] = 0
		world.pos_x[jet] = pad.x + gap
		world.ammo[jet] = 1
		world.order[jet] = MOVE
		world.goal_x[jet] = 20000
		world.goal_y[jet] = 14000
		Worlds.run(world, 3)
		assert_int(world.ammo[jet]).is_equal(2 if gap == Worlds.REACH else 1)


## The second jet of a field reloads on pad 1 (rank 1), the pad it holds.
func test_two_jets_reload_on_their_two_pads() -> void:
	var world: World = Worlds.world()
	var one: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var two: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 1)
	world.ammo[one] = 0
	world.ammo[two] = 0
	assert_array(_gain_ticks(world, two, 25)).is_equal([0, 10, 20])
	assert_int(world.ammo[one]).is_equal(Worlds.AMMO)


func test_an_airfield_that_is_offline_does_not_reload_and_resumes_when_back() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.ammo[jet] = 0
	world.offline_until[world.index_of(Worlds.FIELD)] = 30
	# Judged at the stamp (tick + 1): the step of tick 29 is the first online one.
	Worlds.run(world, 29)
	assert_int(world.ammo[jet]).is_equal(0)
	Worlds.step(world)
	assert_int(world.ammo[jet]).is_equal(1)


func test_a_homeless_aircraft_does_not_reload_and_a_fighter_never_goes_home_on_its_own() -> void:
	var world: World = Worlds.world()
	var lost: int = Worlds.add(world, 2, "jet", 14000, 9000)  # Player 2 owns no airfield.
	world.ammo[lost] = 0
	var fighter: int = Worlds.add(world, 1, "fighter", 14000, 9500)
	world.home[fighter] = Worlds.FIELD
	Worlds.run(world, 30)
	assert_array([world.ammo[lost], world.order[lost], world.home[lost]]).is_equal([0, 0, 0])
	assert_array([world.order[fighter], world.pos_x[fighter]]).is_equal([0, 14000])


func test_an_empty_aircraft_already_ordered_to_move_keeps_its_goal_until_it_stops() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.pos_x[jet] = 14000
	world.pos_y[jet] = 9000
	world.ammo[jet] = 0
	world.order[jet] = MOVE
	world.goal_x[jet] = 18000
	world.goal_y[jet] = 9000
	Worlds.run(world, 5)
	assert_int(world.goal_x[jet]).is_equal(18000)
	# On arrival it idles, and the next step sends it home.
	Worlds.run(world, 90)
	assert_int(world.goal_x[jet]).is_not_equal(18000)
