extends GdUnitTestSuite
## The map reveal (ADR 0036 section 11) and the target layers (section 5) together (plan row P241,
## from the P233 and P238 interaction review), under both implementations: with the sweep on, a
## ground gun takes a ground target and never an aircraft, an anti-air weapon (mask 6) takes the
## aircraft and drops it when the sweep pauses; a ground gun's ATTACK on an aircraft that only the
## sweep shows is dropped and counted; a rupture that destroys the space centre ends the sweep in
## the same step and leaves an AIR row at the strike point at its hit points. The world is
## `sweep_layer_worlds.gd`'s: an enemy outside the sight of every player 1 row is shown by the
## sweep only.

const Worlds: GDScript = preload("res://tests/sim/support/sweep_layer_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The world on `impl`, run until the sweep stands (the tick after the SUPERWEAPON) and a few
## ticks more, so that every row has had its turn at TARGETING.
func _swept(impl: int) -> World:
	var world: World = Worlds.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	while world.tick < Worlds.fire_tick(world, Worlds.SPACE):
		Worlds.step(world)
	Worlds.step(world, [Command.superweapon(1, Worlds.SPACE, 0, 0)])
	assert_int(world.reveal[1]).is_equal(Reveal.State.ON)
	return world


func _target(world: World, id: int) -> int:
	return world.target[world.index_of(id)]


func test_without_a_sweep_nothing_is_seen_and_with_one_each_weapon_takes_its_layer(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	for _tick: int in 12:
		Worlds.step(world)
	assert_array([_target(world, Worlds.GUN), _target(world, Worlds.FLAK)]).is_equal([0, 0])
	world = _swept(impl)
	for _tick: int in 12:
		Worlds.step(world)
	assert_int(_target(world, Worlds.GUN)).is_equal(Worlds.DUMMY)  # Not the nearer jet.
	assert_int(_target(world, Worlds.FLAK)).is_equal(Worlds.JET)


func test_the_anti_air_weapon_drops_the_aircraft_when_the_sweep_pauses(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _swept(impl)
	for _tick: int in 12:
		Worlds.step(world)
	assert_int(_target(world, Worlds.FLAK)).is_equal(Worlds.JET)
	Worlds.drain(world)
	for _tick: int in 20:
		Worlds.step(world)
	assert_int(world.reveal[1]).is_equal(Reveal.State.PAUSED)
	assert_array([_target(world, Worlds.GUN), _target(world, Worlds.FLAK)]).is_equal([0, 0])


func test_a_ground_gun_attack_on_an_aircraft_only_the_sweep_shows_is_dropped_and_counted(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _swept(impl)
	var dropped: int = world.dropped_commands
	var gun: int = world.index_of(Worlds.GUN)
	Worlds.step(world, [Command.attack(1, PackedInt32Array([Worlds.GUN]), Worlds.JET)])
	assert_int(world.dropped_commands).is_equal(dropped + 1)
	assert_int(world.order[gun]).is_not_equal(World.Order.ATTACK)
	# The enemy is visible to the player, so the same command on the ground mark and the anti-air
	# command on the aircraft are taken.
	Worlds.step(world, [Command.attack(1, PackedInt32Array([Worlds.GUN]), Worlds.DUMMY)])
	assert_int(world.order[gun]).is_equal(World.Order.ATTACK)
	Worlds.step(world, [Command.attack(1, PackedInt32Array([Worlds.FLAK]), Worlds.JET)])
	assert_int(world.order[world.index_of(Worlds.FLAK)]).is_equal(World.Order.ATTACK)
	assert_int(world.dropped_commands).is_equal(dropped + 1)


func test_a_rupture_that_destroys_the_space_centre_ends_the_sweep_and_spares_air(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _swept(impl)
	# A flyer and a ground row of player 2 at the strike point; the centre dies of one hit.
	world.hp[world.index_of(Worlds.SPACE)] = 5
	var jet: int = world.index_of(Worlds.JET)
	world.pos_x[jet] = Worlds.SPACE_POINT.x
	world.pos_y[jet] = Worlds.SPACE_POINT.y
	var dummy: int = world.index_of(Worlds.DUMMY)
	world.pos_x[dummy] = Worlds.SPACE_POINT.x
	world.pos_y[dummy] = Worlds.SPACE_POINT.y
	var jet_hp: int = world.hp[jet]
	var dummy_hp: int = world.hp[dummy]
	while world.tick < Worlds.fire_tick(world, Worlds.BORE):
		Worlds.step(world)
	var at: Vector2i = Worlds.SPACE_POINT
	Worlds.step(world, [Command.superweapon(2, Worlds.BORE, at.x, at.y)])
	var ended: bool = false
	for _tick: int in 20:
		Worlds.step(world)
		if world.index_of(Worlds.SPACE) < 0:
			assert_array([world.reveal_site[1], world.reveal[1]]).is_equal([0, 0])
			assert_int(world.fog.revealed[0]).is_equal(0)
			ended = true
			break
	assert_bool(ended).is_true()
	assert_int(world.hp[world.index_of(Worlds.JET)]).is_equal(jet_hp)
	assert_int(world.hp[world.index_of(Worlds.DUMMY)]).is_less(dummy_hp)
