extends GdUnitTestSuite
## The map reveal of the space centre (plan row P233, ADR 0036 section 11): a SUPERWEAPON on a
## REVEAL building sets `reveal_site` and `reveal`, `Reveal.run` (REMOVE) keeps the whole-map +1 of
## `fog.visible` in line with the building, a blackout and low power pause it, and a sweep never
## blocks or waits for a rupture. The rig is `reveal_worlds.gd`; the key cases run in the GDScript
## phases and in the C++ kernels (`_both`), because the kernels stamp and unstamp discs on the same
## counts the sweep adds to.

const Reveals: GDScript = preload("res://tests/sim/support/reveal_worlds.gd")
const Derivation: GDScript = preload("res://tests/sim/support/fog_derivation.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const STRIKE: int = World.Event.STRIKE
const REVEAL: int = Strike.Kind.REVEAL


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The rig world on `impl`, run to the tick SPACE_A may fire in.
func _ready_world(impl: int) -> World:
	var world: World = Reveals.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	while world.tick < Reveals.fire_tick(world, Reveals.SPACE_A):
		Reveals.step(world)
	return world


func _unexplored(world: World, player: int) -> int:
	var base: int = (player - 1) * world.fog.cells
	return world.fog.explored.slice(base, base + world.fog.cells).count(0)


func test_the_kind_is_three() -> void:
	assert_int(Strike.Kind.REVEAL).is_equal(3)


func test_a_sweep_turns_the_fog_off_for_its_owner_only(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _ready_world(impl)
	var row: int = world.index_of(Reveals.SPACE_A)
	var ready: int = world.ready_tick[row]
	assert_int(_unexplored(world, 1)).is_greater(0)
	var other: PackedInt32Array = world.fog.visible.slice(world.fog.cells)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.reveal_site[1], world.reveal[1], world.reveal_stamped[1]]).is_equal(
		[Reveals.SPACE_A, 1, 1]
	)
	assert_array([world.reveal_site[2], world.reveal[2], world.reveal_stamped[2]]).is_equal(
		[0, 0, 0]
	)
	var own: PackedInt32Array = world.fog.visible.slice(0, world.fog.cells)
	assert_int(own.count(0)).is_equal(0)
	assert_int(_unexplored(world, 1)).is_equal(0)
	assert_str(Derivation.mismatch(world)).is_empty()
	assert_bool(world.fog.visible.slice(world.fog.cells) == other).is_true()
	# One charge, no recharge: the building keeps its ready tick, and no strike is pending.
	assert_int(world.ready_tick[row]).is_equal(ready)
	assert_int(world.strike_tick[1]).is_equal(0)
	assert_array(Array(world.events)).is_equal([STRIKE, Reveals.SPACE_A, 0, 0, REVEAL, 1, 0, 0])


func test_a_fire_is_dropped_before_the_charge_for_another_owner_and_with_a_payload() -> void:
	var world: World = Reveals.world()
	var tick: int = Reveals.fire_tick(world, Reveals.SPACE_A)
	while world.tick < tick - 1:
		Reveals.step(world)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	assert_array([world.dropped_commands, world.reveal[1]]).is_equal([1, 0])
	var wrong_owner: Command = Reveals.fire(Reveals.SPACE_A, 2)
	var loaded: Command = Reveals.fire(Reveals.SPACE_A)
	loaded.payload = PackedInt32Array([1])
	Reveals.step(world, [wrong_owner, loaded])
	assert_array([world.dropped_commands, world.reveal[1], world.reveal_site[1]]).is_equal(
		[3, 0, 0]
	)
	assert_int(world.events.size()).is_equal(0)


func test_a_second_fire_and_a_spare_centre_are_dropped_while_the_sweep_stands() -> void:
	var world: World = _ready_world(SimImpls.Impl.GDSCRIPT)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A), Reveals.fire(Reveals.SPACE_B)])
	assert_int(world.dropped_commands).is_equal(2)
	assert_array([world.reveal_site[1], world.reveal[1]]).is_equal([Reveals.SPACE_A, 1])
	assert_int(world.events.size()).is_equal(0)


## A rupture pending does not stop a sweep, and a sweep does not stop a rupture: in either order in
## one tick and across ticks. A second rupture-kind fire (the blackout) is still refused while the
## rupture is pending, so the pending-rupture rule is intact for kinds 1 and 2.
func test_a_sweep_fires_while_a_rupture_is_pending_and_does_not_block_one() -> void:
	for sweep_first: bool in [false, true]:
		var world: World = _ready_world(SimImpls.Impl.GDSCRIPT)
		var rupture: Command = Reveals.fire(Reveals.BORE)
		var sweep: Command = Reveals.fire(Reveals.SPACE_A)
		rupture.sequence = 2 if sweep_first else 1
		sweep.sequence = 1 if sweep_first else 2
		Reveals.step(world, [rupture, sweep])
		assert_int(world.dropped_commands).is_equal(0)
		assert_int(world.strike_tick[1]).is_not_equal(0)
		assert_array([world.reveal_site[1], world.reveal[1]]).is_equal([Reveals.SPACE_A, 1])
	var world: World = _ready_world(SimImpls.Impl.GDSCRIPT)
	Reveals.step(world, [Reveals.fire(Reveals.BORE)])
	var landing: int = world.strike_tick[1]
	assert_int(landing).is_not_equal(0)
	Reveals.step(world, [Reveals.fire(Reveals.ARRAY_1)])
	assert_int(world.dropped_commands).is_equal(1)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_array([world.reveal[1], world.strike_tick[1]]).is_equal([1, landing])
	assert_array(Array(world.events)).is_equal([STRIKE, Reveals.SPACE_A, 0, 0, REVEAL, 1, 0, 0])


func test_a_rupture_fired_after_a_sweep_is_taken() -> void:
	var world: World = _ready_world(SimImpls.Impl.GDSCRIPT)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	Reveals.step(world, [Reveals.fire(Reveals.BORE)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.strike_tick[1]).is_not_equal(0)


## The site's destruction ends the sweep: `visible` falls back to the discs, `explored` stays, and
## the spare centre may fire the next tick.
func test_destroying_the_site_ends_the_sweep_and_a_spare_may_fire(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _ready_world(impl)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	for _i: int in 5:
		Reveals.step(world)
		assert_str(Derivation.mismatch(world)).is_empty()
	world.hp[world.index_of(Reveals.SPACE_A)] = 0
	Reveals.step(world)
	assert_array([world.reveal_site[1], world.reveal[1], world.reveal_stamped[1]]).is_equal(
		[0, 0, 0]
	)
	assert_str(Derivation.mismatch(world)).is_empty()
	assert_int(world.fog.visible.slice(0, world.fog.cells).count(0)).is_greater(0)
	assert_int(_unexplored(world, 1)).is_equal(0)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_B)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.reveal_site[1], world.reveal[1]]).is_equal([Reveals.SPACE_B, 1])
	assert_str(Derivation.mismatch(world)).is_empty()


## A blackout on the space centre pauses the sweep for exactly the blackout's steps and it comes
## back by itself: after every step `reveal` is 2 while the building is offline at the step's stamp
## and 1 otherwise, the stamp follows, `visible` is what the rows and the sweep say, `explored`
## keeps what the sweep showed and the ghosts it recorded stay. The enemy reads the state through
## PlayerView.
func test_a_blackout_pauses_the_sweep_and_it_resumes_by_itself(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _ready_world(impl)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	for _i: int in 3:
		Reveals.step(world)
	var ghosts: int = world.ghost_count[1]
	assert_int(ghosts).is_greater(0)
	var row: int = world.index_of(Reveals.SPACE_A)
	var seen: Dictionary[int, int] = {}
	Reveals.step(world, [Reveals.fire(Reveals.ARRAY_2, 2, Reveals.OVER_A)])
	assert_int(world.dropped_commands).is_equal(0)
	var offline_until: int = world.offline_until[row]
	assert_int(offline_until).is_greater(world.tick)
	for _i: int in 110:
		var want: int = 2 if world.offline_until[row] > world.tick else 1
		assert_int(world.reveal[1]).is_equal(want)
		assert_int(world.reveal_stamped[1]).is_equal(1 if want == 1 else 0)
		assert_str(Derivation.mismatch(world)).is_empty()
		assert_int(PlayerView.of(world, 2).reveal_state(1)).is_equal(want)
		seen[want] = seen.get(want, 0) + 1
		assert_int(_unexplored(world, 1)).is_equal(0)
		assert_int(world.ghost_count[1]).is_greater_equal(ghosts)
		assert_int(world.reveal_site[1]).is_equal(Reveals.SPACE_A)
		Reveals.step(world)
	# Offline from the command's own step for `type_strike_ticks` steps, on again at the stamp that
	# reaches the end: that many paused observations (the first after the command's step).
	assert_int(seen[2]).is_equal(world.type_strike_ticks[Reveals.type_of(world, "array")])
	assert_int(seen[1]).is_greater(0)
	assert_int(world.reveal[1]).is_equal(1)
	assert_int(world.dropped_commands).is_equal(0)


## Cutting the owner's power pauses the sweep, restoring it resumes it, and a fire is dropped while
## the owner is on low power (the single charge is not spent into a sweep that would pause at once).
func test_low_power_pauses_the_sweep_and_drops_a_fire(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Reveals.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	var drain: int = Reveals.drain(world, 20, 12)
	while world.tick < Reveals.fire_tick(world, Reveals.SPACE_A):
		Reveals.step(world)
	assert_bool(Power.is_low(world, 1)).is_true()
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	assert_array([world.dropped_commands, world.reveal[1], world.reveal_site[1]]).is_equal(
		[1, 0, 0]
	)
	world.hp[world.index_of(drain)] = 0
	Reveals.step(world)
	Reveals.step(world)
	assert_bool(Power.is_low(world, 1)).is_false()
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.reveal[1]).is_equal(1)
	var seen: Dictionary[int, int] = {}
	for tick: int in 40:
		if tick == 5 or tick == 20:
			drain = Reveals.drain(world, 20, 12)
		if tick == 12:
			world.hp[world.index_of(drain)] = 0
		# Reveal.run reads the totals that the step before left (the ones Combat.fire reads).
		var low: bool = Power.is_low(world, 1)
		Reveals.step(world)
		var want: int = 2 if low else 1
		seen[want] = seen.get(want, 0) + 1
		assert_int(world.reveal[1]).is_equal(want)
		assert_int(world.reveal_stamped[1]).is_equal(1 if want == 1 else 0)
		assert_str(Derivation.mismatch(world)).is_empty()
	assert_int(seen.get(2, 0)).is_greater(0)
	assert_int(seen.get(1, 0)).is_greater(0)
	assert_int(world.reveal_site[1]).is_equal(Reveals.SPACE_A)


## A rebuild of `visible` from the hashed state (what `World.prepare` does on a fresh World:
## `WorldLoad.stamp_fog`) stamps the sweep exactly when `reveal` is 1: on, paused and ended; and a
## second run of the same script has the same hash at every checkpoint inside the sweep.
func test_a_rebuild_across_a_pause_equals_the_live_fog(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _ready_world(impl)
	var twin: World = _ready_world(SimImpls.Impl.GDSCRIPT)
	var script: Dictionary = {
		0: [Reveals.fire(Reveals.SPACE_A)],
		4: [Reveals.fire(Reveals.ARRAY_2, 2, Reveals.OVER_A)],
	}
	var states: Dictionary[int, int] = {}
	for at: int in 130:
		for each: World in [world, twin]:
			var commands: Array = []
			for command: Command in script.get(at, []):
				commands.append(
					Command.superweapon(
						command.player_id, command.target_id, command.target_x, command.target_y
					)
				)
			Reveals.step(each, commands)
		assert_array(world.hash_parts()).is_equal(twin.hash_parts())
		if at % 10 == 9 or at == 5:
			states[world.reveal[1]] = states.get(world.reveal[1], 0) + 1
			assert_array(_rebuilt(world)).is_equal(Array(world.fog.visible))
	assert_bool(states.has(1) and states.has(2)).is_true()
	world.hp[world.index_of(Reveals.SPACE_A)] = 0
	Reveals.step(world)
	assert_int(world.reveal[1]).is_equal(0)
	assert_array(_rebuilt(world)).is_equal(Array(world.fog.visible))


## `visible` as a fresh World would stamp it: a copy of the fog reset and `WorldLoad.stamp_fog` run
## again over the rows and the `reveal` of the World, which is what `prepare` does. The World is
## left as it was.
func _rebuilt(world: World) -> Array:
	var live: FogGrid = world.fog
	var kept_stamps: PackedInt32Array = world.reveal_stamped.duplicate()
	var kept_cells: PackedInt32Array = world.fog_cell.duplicate()
	var fresh: FogGrid = FogGrid.new()
	fresh.configure(live.cols, live.rows, live.player_count)
	world.fog = fresh
	world.reveal_stamped.fill(0)
	WorldLoad.stamp_fog(world)
	var rebuilt: Array = Array(fresh.visible)
	world.fog = live
	world.reveal_stamped = kept_stamps
	world.fog_cell = kept_cells
	return rebuilt


func test_reveal_state_is_public_and_a_copy() -> void:
	var world: World = _ready_world(SimImpls.Impl.GDSCRIPT)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	var view: PlayerView = PlayerView.of(world, 2)
	assert_array([view.reveal_state(1), view.reveal_state(2), view.reveal_state(0)]).is_equal(
		[1, 0, 0]
	)
	assert_array([view.reveal_state(-1), view.reveal_state(9)]).is_equal([0, 0])
	assert_int(PlayerView.of(world, 1).reveal_state(1)).is_equal(1)
	world.reveal[1] = 2
	assert_int(view.reveal_state(1)).is_equal(1)


func test_the_derived_stamp_is_out_of_the_hash_and_the_snapshot() -> void:
	assert_bool(World.DERIVED_ARRAYS.has(&"reveal_stamped")).is_true()
	var world: World = _ready_world(SimImpls.Impl.GDSCRIPT)
	var before: PackedInt64Array = world.hash_parts()
	world.reveal_stamped[1] = 1
	assert_array(world.hash_parts()).is_equal(before)
	world.reveal_stamped[1] = 0
	world.reveal[1] = 1
	assert_array(world.hash_parts()).is_not_equal(before)


func test_a_world_without_a_sweep_runs_the_step_unchanged() -> void:
	var world: World = Reveals.world()
	for _i: int in 30:
		Reveals.step(world)
	assert_array(Array(world.reveal)).is_equal([0, 0, 0])
	assert_array(Array(world.reveal_stamped)).is_equal([0, 0, 0])
	assert_str(Derivation.mismatch(world)).is_empty()
