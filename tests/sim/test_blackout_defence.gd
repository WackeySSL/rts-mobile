extends GdUnitTestSuite
## A blacked-out defence and the units around it (plan row P111, ADR 0023 section 10): a building
## row whose `offline_until` is above the stamp keeps the target TARGETING gave it and does not
## shoot, its cooldown counts down, and it fires on the stamp that reaches `offline_until` with no
## wind-up (`Combat.fire`, GDScript only: no kernel runs it); the units in the area move and fire as
## if nothing had happened. The rig is `blackout_worlds.gd`: player 2's two turrets and the array's
## point, with the length read from the World's table. Every case runs a twin world with no
## blackout beside the real one, so that "as if nothing had happened" is a comparison.

const Rig: GDScript = preload("res://tests/sim/support/blackout_worlds.gd")
## The tick the array is fired in these cases: after the turrets have found and shot their targets.
const FIRE_AT: int = 60


## Two rig worlds at `FIRE_AT`: the one that will black out and its twin.
func _pair() -> Array[World]:
	var world: World = Rig.world()
	var twin: World = Rig.world()
	assert_int(FIRE_AT).is_greater_equal(Rig.fire_tick(world))
	return [world, twin]


## The shots of `id` in the last step's events.
func _shots(world: World, id: int) -> int:
	return Rig.shooters(world).count(id)


## The shots of everyone but `id` in the last step's events, in order.
func _others(world: World, id: int) -> Array[int]:
	var found: Array[int] = []
	for shooter: int in Rig.shooters(world):
		if shooter != id:
			found.append(shooter)
	return found


func _hp(world: World, id: int) -> int:
	return world.hp[world.index_of(id)]


## The turret in the radius keeps its target and fires no shot for exactly the length of the
## blackout (the firing step's own FIRE included, a tick after the command was applied in its
## COMMANDS), while its twin keeps shooting; the turret outside the radius shoots exactly as in the
## twin. Player 2 is not on low power at any step, so the blackout alone silences the turret. On the
## stamp that reaches `offline_until` the turret fires at once: its cooldown ran down while offline.
func test_a_blacked_out_defence_keeps_its_target_and_is_silent_for_exactly_the_length() -> void:
	var worlds: Array[World] = _pair()
	var world: World = worlds[0]
	var twin: World = worlds[1]
	var length: int = Rig.length_of(world)
	Rig.run_to(world, FIRE_AT)
	Rig.run_to(twin, FIRE_AT)
	var turret: int = world.index_of(Rig.TURRET_IN)
	assert_int(world.target[turret]).is_equal(Rig.TARGET_IN)
	var held: int = _hp(world, Rig.TARGET_IN)
	var twin_shots: int = 0
	var far_shots: int = 0
	for at: int in length:
		Rig.step(world, [Rig.fire()] if at == 0 else [])
		Rig.step(twin)
		assert_int(world.dropped_commands).is_equal(0)
		assert_int(_shots(world, Rig.TURRET_IN)).override_failure_message("step %d" % at).is_equal(
			0
		)
		assert_int(world.target[turret]).override_failure_message("step %d" % at).is_equal(
			Rig.TARGET_IN
		)
		assert_int(_hp(world, Rig.TARGET_IN)).is_equal(held)
		assert_bool(Power.is_low(world, 2)).is_false()
		assert_array(_others(world, Rig.TURRET_IN)).is_equal(_others(twin, Rig.TURRET_IN))
		twin_shots += _shots(twin, Rig.TURRET_IN)
		far_shots += _shots(world, Rig.TURRET_OUT)
	var cooldown: int = world.weapon_cooldown[world.type_weapon[world.type_index[turret]]]
	assert_int(twin_shots).is_greater_equal(length / cooldown)  # It would have shot, had it power.
	assert_int(_hp(twin, Rig.TARGET_IN)).is_less(held)
	assert_int(far_shots).is_greater_equal(length / cooldown)  # The one outside kept shooting.
	Rig.step(world)
	assert_int(world.tick).is_equal(FIRE_AT + 1 + length)  # The stamp that reaches offline_until.
	assert_int(_shots(world, Rig.TURRET_IN)).is_equal(1)
	assert_int(world.cooldown[turret]).is_equal(cooldown)
	assert_int(_hp(world, Rig.TARGET_IN)).is_less(held)
	for _later: int in cooldown - 1:
		Rig.step(world)
		assert_int(_shots(world, Rig.TURRET_IN)).is_equal(0)
	Rig.step(world)
	assert_int(_shots(world, Rig.TURRET_IN)).is_equal(1)  # And then on its own cadence.


## Units are not affected: a gunner of player 2 inside the radius, with a target in range, shoots
## exactly as often as in the twin, a second one inside the radius that is given a MOVE order in
## the firing step walks exactly the twin's path, and neither is blacked out.
func test_units_in_the_area_move_and_fire_as_if_nothing_had_happened() -> void:
	var worlds: Array[World] = _pair()
	var ids: Array[int] = []
	for each: World in worlds:
		var gunner: int = Rig.type_of(each, "gunner")
		(
			ids
			. assign(
				[
					each.add_unit(2, gunner, 32000, 3000),  # A shooter, 2000 below its dummy.
					each.add_unit(2, gunner, 32500, 5500),  # The walker.
					each.add_unit(1, Rig.type_of(each, "dummy"), 32000, 1000),
				]
			)
		)
	var world: World = worlds[0]
	var twin: World = worlds[1]
	Rig.run_to(world, FIRE_AT)
	Rig.run_to(twin, FIRE_AT)
	var length: int = Rig.length_of(world)
	var walk: Command = Command.move(2, PackedInt32Array([ids[1]]), 36500, 5500)
	var twin_walk: Command = Command.move(2, PackedInt32Array([ids[1]]), 36500, 5500)
	var walker: int = world.index_of(ids[1])
	var start: int = world.pos_x[walker]
	var shots: int = 0
	for at: int in length:
		Rig.step(world, [Rig.fire(), walk] if at == 0 else [])
		Rig.step(twin, [twin_walk] if at == 0 else [])
		for id: int in [ids[0], ids[1]]:
			var row: int = world.index_of(id)
			var twin_row: int = twin.index_of(id)
			assert_array([world.pos_x[row], world.pos_y[row], world.hp[row]]).is_equal(
				[twin.pos_x[twin_row], twin.pos_y[twin_row], twin.hp[twin_row]]
			)
			assert_int(world.offline_until[row]).is_equal(0)
		assert_int(_shots(world, ids[0])).is_equal(_shots(twin, ids[0]))
		shots += _shots(world, ids[0])
		if at == 20:
			assert_int(world.pos_x[walker]).is_greater(start)  # It is walking.
	var cooldown: int = world.weapon_cooldown[world.type_weapon[world.type_index[walker]]]
	assert_int(shots).is_greater_equal(length / cooldown)
