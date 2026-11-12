extends GdUnitTestSuite
## The map reveal against the fog and its readers (plan row P233, ADR 0036 section 11), beside
## test_reveal.gd's rules: the dirty list on the owner's fog turn (the view redraws from it), a
## `prepare()` of a World that holds a standing sweep, a rebuild across a low-power pause, and the
## claim that no kernel and no reader needs a further change: an armed unit acquires an enemy that
## only the sweep shows, loses it while the sweep is paused, and `PlayerView.seen_rows` follows.
## The rigs are `reveal_worlds.gd` and `fog_worlds.gd`; the cases run in the GDScript phases and in
## the C++ kernels.

const Reveals: GDScript = preload("res://tests/sim/support/reveal_worlds.gd")
const Derivation: GDScript = preload("res://tests/sim/support/fog_derivation.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func _on(world: World, impl: int) -> World:
	assert_array(SimImpls.use(world, impl)).is_empty()
	return world


## Steps until the World's tick is at least `tick` and a multiple of the fog period (player 1's
## turn is `tick % period == 0`, FogUpdate.begin's rule).
func _to_turn(world: World, tick: int) -> void:
	while world.tick < tick or world.tick % world.fog_period_ticks != 0:
		Reveals.step(world)


## One step with `commands`; returns [dirty_full of player 1, the growth of its version].
func _step_dirty(world: World, commands: Array = []) -> Array:
	var version: int = world.fog.version_of(1)
	Reveals.step(world, commands)
	return [world.fog.dirty_overflowed(1), world.fog.version_of(1) - version]


## The flips of a sweep that turns on, pauses and resumes on the owner's own fog turn stay in its
## dirty list: `Reveal.run` comes after `FogUpdate.begin`, which empties the list on that turn. The
## whole map flips, so the block overflows and the view redraws all of it. At the period of 1 every
## step is the owner's turn; at the shipped 3 the fire and the blackout are chosen on it, and the
## resume lands on it too because the rig's 90-tick blackout is a multiple of 3.
func test_the_flips_of_a_sweep_reach_the_owners_dirty_list_on_its_turn(
	impl: int, _test_parameters := _both()
) -> void:
	for period: int in [1, 3]:
		var world: World = _on(Reveals.world(), impl)
		world.fog_period_ticks = period
		_to_turn(world, Reveals.fire_tick(world, Reveals.SPACE_A))
		var label: String = "period %d" % period
		var turn_on: Array = _step_dirty(world, [Reveals.fire(Reveals.SPACE_A)])
		assert_array(turn_on).override_failure_message(label + ", on").is_equal([true, 1])
		_to_turn(world, world.tick + 3)
		var array: Command = Reveals.fire(Reveals.ARRAY_2, 2, Reveals.OVER_A)
		var pause: Array = _step_dirty(world, [array])
		assert_int(world.reveal[1]).is_equal(Reveal.State.PAUSED)
		assert_array(pause).override_failure_message(label + ", pause").is_equal([true, 1])
		var resumed: Array = []
		while world.reveal[1] != Reveal.State.ON:
			resumed = _step_dirty(world)
		assert_array(resumed).override_failure_message(label + ", resume").is_equal([true, 1])
		assert_str(Derivation.mismatch(world)).is_empty()


## A World that holds a standing sweep of each player when it is prepared (a rebuild from hashed
## state) has the +1 and the flag at once, once: a second stamp by `Reveal.run` would leave a pause
## with one +1 still in. It then runs across a pause with `visible` equal to the rows and the sweep
## every step.
func test_a_prepared_world_with_a_standing_sweep_is_stamped_once_and_pauses_cleanly(
	impl: int, _test_parameters := _both()
) -> void:
	var members: Dictionary = {
		&"reveal_site": PackedInt32Array([0, 1, 2]), &"reveal": PackedInt32Array([0, 1, 1])
	}
	var units: Array = [
		[1, 0, Worlds.centre(5), Worlds.centre(5)], [2, 0, Worlds.centre(20), Worlds.centre(10)]
	]
	var world: World = _on(Worlds.field(30, 20, 2, [4000], units, members), impl)
	assert_array(Array(world.fog.revealed)).is_equal([1, 1])
	assert_int(world.fog.visible.count(0)).is_equal(0)
	assert_str(Derivation.mismatch(world)).is_empty()
	var seen: Dictionary[int, int] = {}
	for step: int in 24:
		if step == 6:
			world.offline_until[0] = world.tick + 1 + 8
		Reveals.step(world)
		seen[world.reveal[1]] = seen.get(world.reveal[1], 0) + 1
		assert_str(Derivation.mismatch(world)).override_failure_message("step %d" % step).is_empty()
	assert_array([seen.get(1, 0) > 0, seen.get(2, 0)]).is_equal([true, 8])
	assert_int(world.fog.visible.count(0)).is_equal(0)


## What a World with the standing low-power pause is after step 3: the rig run to the sweep, the
## drain added and three steps.
func _paused_by_power(impl: int) -> World:
	var world: World = _on(Reveals.world(), impl)
	while world.tick < Reveals.fire_tick(world, Reveals.SPACE_A):
		Reveals.step(world)
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	Reveals.drain(world, 20, 12)
	for _i: int in 3:
		Reveals.step(world)
	assert_int(world.reveal[1]).is_equal(Reveal.State.PAUSED)
	return world


## A mid-match rebuild: a fresh fog stamped by `WorldLoad.stamp_fog` (keeping `explored`, which is
## history) and, with `power`, the totals rebuilt as the last step left them (`Power.run` at that
## step's stamp, as test_power_blackout.gd does). Without them the totals are the 0 that `prepare`
## leaves.
func _rebuild(world: World, power: bool) -> void:
	var fresh: FogGrid = FogGrid.new()
	fresh.configure(world.fog.cols, world.fog.rows, world.fog.player_count)
	fresh.explored = world.fog.explored.duplicate()
	world.fog = fresh
	WorldLoad.stamp_fog(world)
	world.power_made.fill(0)
	world.power_used.fill(0)
	if power:
		world.tick -= 1
		Power.run(world)
		world.tick += 1


## The low-power pause reads the derived power totals, so a rebuild that restores `visible` and the
## totals steps like the live World (same hash after the next step), and one that leaves the totals
## at 0 does not: its sweep resumes at once.
func test_a_rebuild_across_a_low_power_pause_needs_the_power_totals(
	impl: int, _test_parameters := _both()
) -> void:
	var live: World = _paused_by_power(impl)
	var rebuilt: World = _paused_by_power(SimImpls.Impl.GDSCRIPT)
	var bare: World = _paused_by_power(SimImpls.Impl.GDSCRIPT)
	assert_array(live.hash_parts()).is_equal(rebuilt.hash_parts())
	_rebuild(rebuilt, true)
	_rebuild(bare, false)
	assert_array(Array(rebuilt.fog.visible)).is_equal(Array(live.fog.visible))
	Reveals.step(live)
	Reveals.step(rebuilt)
	Reveals.step(bare)
	assert_array(rebuilt.hash_parts()).is_equal(live.hash_parts())
	assert_int(rebuilt.reveal[1]).is_equal(Reveal.State.PAUSED)
	assert_int(bare.reveal[1]).is_equal(Reveal.State.ON)
	assert_array(bare.hash_parts()).is_not_equal(live.hash_parts())


## The ids of the rows in `seen_rows` of player `player`'s view.
func _seen_ids(world: World, player: int) -> Array[int]:
	var view: PlayerView = PlayerView.of(world, player)
	var ids: Array[int] = []
	for row: int in view.seen_rows:
		ids.append(view.row_id(row))
	return ids


## The claim "TARGETING, `Targeting.sees`, `PlayerView.seen_rows` and the ghosts follow with no
## further change": an armed tank that cannot see the sturdy enemy 4 tiles away has no target and
## the view lists no such row; once the sweep is on it acquires it and the view lists it; while a
## blackout pauses the sweep it drops it again and the row leaves the view; when the sweep comes
## back it acquires it again.
func test_an_armed_unit_acquires_what_only_the_sweep_shows_and_loses_it_on_a_pause(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _on(Reveals.armed_world(), impl)
	var tank: int = world.index_of(Reveals.TANK)
	while world.tick < Reveals.fire_tick(world, Reveals.SPACE_A):
		Reveals.step(world)
		assert_int(world.target[tank]).is_equal(0)
	assert_bool(_seen_ids(world, 1).has(Reveals.DUMMY)).is_false()
	Reveals.step(world, [Reveals.fire(Reveals.SPACE_A)])
	assert_bool(_seen_ids(world, 1).has(Reveals.DUMMY)).is_true()
	for _i: int in 24:
		Reveals.step(world)
	assert_int(world.target[tank]).is_equal(Reveals.DUMMY)
	Reveals.step(world, [Reveals.fire(Reveals.ARRAY_2, 2, Reveals.OVER_A)])
	assert_int(world.reveal[1]).is_equal(Reveal.State.PAUSED)
	assert_bool(_seen_ids(world, 1).has(Reveals.DUMMY)).is_false()
	for _i: int in 30:
		Reveals.step(world)
	assert_int(world.reveal[1]).is_equal(Reveal.State.PAUSED)
	assert_int(world.target[tank]).is_equal(0)
	while world.reveal[1] != Reveal.State.ON:
		Reveals.step(world)
	assert_bool(_seen_ids(world, 1).has(Reveals.DUMMY)).is_true()
	for _i: int in 24:
		Reveals.step(world)
	assert_int(world.target[tank]).is_equal(Reveals.DUMMY)
