extends GdUnitTestSuite
## Cancelling sites in a played match (plan row P128b, ADR 0026 sections 6, 10 and 11): a scripted
## match with cancels has one state hash in the GDScript phases and in the C++ kernels (REMOVE and
## the commands are GDScript; the kernels read nothing of a cancel, so the choice is never hashed),
## the same hash in two runs, another hash without the cancels, and a replay of it reproduces every
## checkpoint and the final hash, also through bytes. The script (`site_rig.gd`'s world, 150 ticks,
## player 2's three rifle squads standing by the Barracks spot): player 1 starts a Power Plant (tick
## 3) and cancels it (tick 12); starts a Barracks (tick 20), which the rifle squads shoot on ticks
## 22-24 and 37-39, and cancels it in tick 38, with a second cancel of the same site in the same
## tick. A rifle squad hits the site in that very tick (TARGETING and FIRE run before REMOVE), so a
## cancelled row draws fire in its last tick and leaves with its mark all the same. Then player 1
## starts a Power Plant again on the first spot (tick 60), which completes. Player 2 starts a Wind
## Park (tick 8) and keeps it.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 150
const SEED: int = 5
## The ticks of the first cancel (the Power Plant site) and of the second (the Barracks site, under
## fire in that tick, cancelled twice).
const CANCEL_TICKS: Array[int] = [12, 38]


## The site of `player` that is under construction now (the first one), or 0.
func _site_id(made: World, player: int) -> int:
	for row: int in made.unit_count():
		if made.owner[row] == player and made.build_left[row] > 0:
			return made.unit_id[row]
	return 0


## The Commands queued on `tick`, new objects each call: the loop stamps the ones it is given.
func _commands_at(made: World, tick: int, with_cancels: bool) -> Array[Command]:
	var out: Array[Command] = []
	match tick:
		3:
			out.append(SiteRig.place(made, "power_plant", SiteRig.SPOT))
		8:
			out.append(SiteRig.place(made, "renew_power", SiteRig.SPOT_2, 2))
		20:
			out.append(SiteRig.place(made, "barracks", SiteRig.WIDE))
		60:
			out.append(SiteRig.place(made, "power_plant", SiteRig.SPOT))
	if with_cancels and CANCEL_TICKS.has(tick):
		var site: int = _site_id(made, 1)
		out.append(Command.cancel_build(1, site))
		if tick == CANCEL_TICKS[1]:
			var again: Command = Command.cancel_build(1, site)
			again.sequence = 1
			out.append(again)
	return out


func _world() -> World:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 20)
	SiteRig.fast(made, "renew_power", 20)
	SiteRig.fast(made, "barracks", 60)
	var rifle: int = SiteRig.type_of(made, "rifle_squad")
	for unit: int in 3:
		made.add_unit(2, rifle, 8500 + unit * 600, 9000)
	return made


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## One run of the script on `impl`: the world, the loop (its replay holds the log) and what the
## script is there to show.
class Played:
	extends RefCounted
	var world: World
	var loop: MatchLoop
	## SHOT records whose target was a site of player 1 that was under construction as the tick began.
	var shots_at_sites: int = 0
	## SHOT records aimed at the site that a cancel of the tick took, by the tick of the cancel.
	var shots_in_cancel_tick: Dictionary[int, int] = {}
	## The DIED records of the run with the cancel mark, as their unit ids and their ticks.
	var cancelled_ids: Array[int] = []
	var cancelled_at: Array[int] = []
	var dropped_at: Array[int] = []


func _play(impl: int, with_cancels: bool = true) -> Played:
	var played: Played = Played.new()
	played.world = _world()
	assert_array(SimImpls.use(played.world, impl)).is_empty()
	played.loop = MatchLoop.create(null, "", SEED, played.world)
	for _tick: int in TICKS:
		var dropped: int = played.world.dropped_commands
		var tick: int = played.world.tick
		var site: int = _site_id(played.world, 1)
		played.loop.step(played.world, _commands_at(played.world, tick, with_cancels))
		if played.world.dropped_commands != dropped:
			played.dropped_at.append(tick)
		var events: PackedInt32Array = played.world.events
		for at: int in range(0, events.size(), World.EVENT_STRIDE):
			var flag: int = events[at + Production.DIED_CANCEL_FLAG_AT]
			if events[at] == World.Event.DIED and flag == 1:
				played.cancelled_ids.append(events[at + 1])
				played.cancelled_at.append(tick)
			if events[at] == World.Event.SHOT and events[at + 4] == site and site != 0:
				played.shots_at_sites += 1
				if with_cancels and CANCEL_TICKS.has(tick):
					played.shots_in_cancel_tick[tick] = played.shots_in_cancel_tick.get(tick, 0) + 1
	played.loop.replay.finish(played.world)
	return played


@warning_ignore("integer_division")
func test_the_script_cancels_two_sites_one_of_them_under_fire() -> void:
	var played: Played = _play(SimImpls.Impl.GDSCRIPT)
	var made: World = played.world
	assert_array(played.cancelled_at).is_equal(CANCEL_TICKS)
	assert_array(played.dropped_at).is_equal([CANCEL_TICKS[1]])  # The second cancel of the Barracks.
	# The Barracks site was shot while it rose and in the very tick it was cancelled.
	assert_int(played.shots_at_sites).is_greater(1)
	assert_int(played.shots_in_cancel_tick.get(CANCEL_TICKS[1], 0)).is_greater(0)
	# Player 1 built the second plant only; the Barracks stayed a site until it was cancelled, and
	# nothing was lost: a cancel is no loss, and the rifles did not kill the site first.
	assert_array([made.stat_built[1], made.stat_lost_buildings[1]]).is_equal([1, 0])
	assert_int(SiteRig.rows_of(made, 1, "power_plant").size()).is_equal(2)  # Shipped + the new one.
	assert_array(SiteRig.rows_of(made, 1, "barracks")).has_size(1)  # The shipped one.
	assert_array(SiteRig.sites(made)).is_empty()
	# Three prices paid, two refunds of the shipped 75 % (each truncated on its own).
	var plant: int = SiteRig.cost(made, "power_plant")
	var barracks: int = SiteRig.cost(made, "barracks")
	assert_int(made.credits[1]).is_equal(
		made.start_credits - 2 * plant - barracks + plant * 75 / 100 + barracks * 75 / 100
	)


func test_a_scripted_match_with_cancels_has_one_hash_in_both_implementations(
	impl: int, _test_parameters := _both()
) -> void:
	var reference: Played = _play(SimImpls.Impl.GDSCRIPT)
	var played: Played = _play(impl)
	assert_int(played.world.state_hash()).is_equal(reference.world.state_hash())
	assert_array(played.loop.replay.checkpoint_hashes).is_equal(
		reference.loop.replay.checkpoint_hashes
	)
	assert_array(played.cancelled_ids).is_equal(reference.cancelled_ids)
	assert_array(played.cancelled_at).is_equal(CANCEL_TICKS)
	# The cancelled Barracks site drew fire in its last tick under this implementation too.
	assert_int(played.shots_in_cancel_tick.get(CANCEL_TICKS[1], 0)).is_greater(0)
	assert_dict(played.shots_in_cancel_tick).is_equal(reference.shots_in_cancel_tick)
	assert_int(played.world.native_phases).is_equal(
		SimImpls.expected_mask() if impl == SimImpls.Impl.NATIVE else 0
	)


func test_two_runs_agree_and_the_cancels_are_part_of_the_state() -> void:
	var first: Played = _play(SimImpls.Impl.GDSCRIPT)
	var second: Played = _play(SimImpls.Impl.GDSCRIPT)
	assert_int(first.world.state_hash()).is_equal(second.world.state_hash())
	assert_array(first.loop.replay.checkpoint_hashes).is_equal(second.loop.replay.checkpoint_hashes)
	var bare: Played = _play(SimImpls.Impl.GDSCRIPT, false)
	assert_int(bare.world.state_hash()).is_not_equal(first.world.state_hash())
	# The first checkpoint is at tick 15, after the first cancel (tick 12): it already differs.
	var at: int = first.loop.replay.checkpoint_ticks.find(15)
	assert_int(at).is_greater_equal(0)
	assert_int(bare.loop.replay.checkpoint_hashes[at]).is_not_equal(
		first.loop.replay.checkpoint_hashes[at]
	)


func test_a_replay_of_a_match_with_cancels_reproduces_every_checkpoint() -> void:
	var played: Played = _play(SimImpls.Impl.GDSCRIPT)
	var replay: Replay = played.loop.replay
	assert_array([replay.final_tick, replay.checkpoint_ticks.size()]).is_equal([TICKS, 10])
	var fresh: World = _world()
	assert_int(Replay.play(replay, fresh, TICKS)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)
	# Through bytes, as the runner would save it.
	var loaded: Replay = Replay.from_bytes(replay.to_bytes())
	assert_object(loaded).is_not_null()
	var again: World = _world()
	assert_int(Replay.play(loaded, again, TICKS)).is_equal(Replay.PLAY_MATCHED)
	assert_int(again.state_hash()).is_equal(replay.final_hash)
	# The three cancels are in the log, with no payload and the site in the target id.
	var cancels: Array[int] = []
	var data: PackedInt32Array = replay.commands
	var at: int = 0
	while at < data.size():
		var command: Command = Command.new()
		at = Command.decode(data, at, command)
		assert_int(at).is_greater(0)
		if command.type == Command.Type.CANCEL_BUILD:
			assert_bool(command.payload.is_empty()).is_true()
			cancels.append(command.target_id)
	assert_int(cancels.size()).is_equal(3)
	assert_int(cancels[1]).is_equal(cancels[2])
