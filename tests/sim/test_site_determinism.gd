extends GdUnitTestSuite
## Sites and determinism (plan row P128, ADR 0026 sections 10 and 11): a scripted match with sites
## has one state hash in the GDScript phases and in the C++ kernels (no kernel reads a site, so the
## choice of implementation is never hashed), the same hash in two runs, another hash without the
## PLACE commands, and a replay of it reproduces every checkpoint and the final hash, also through
## bytes. The script (`site_rig.gd`'s world, 150 ticks): player 1 starts a Power Plant (tick 3), a
## second PLACE of tick 12 is dropped by the site limit, a Barracks follows at tick 40 beside the
## old path (a QUEUE and its PLACE of an empty payload at 50 and 90), player 2 starts a Wind Park
## (tick 8), and three of player 2's rifle squads attack the Barracks site while it rises.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 150
const SEED: int = 5


## The Commands queued on `tick`, new objects each call: the loop stamps the ones it is given.
func _commands_at(made: World, tick: int, with_sites: bool) -> Array[Command]:
	var out: Array[Command] = []
	if with_sites:
		match tick:
			3:
				out.append(SiteRig.place(made, "power_plant", SiteRig.SPOT))
			8:
				out.append(SiteRig.place(made, "renew_power", SiteRig.SPOT_2, 2))
			12:
				out.append(SiteRig.place(made, "barracks", SiteRig.WIDE))  # Dropped: the limit.
			40:
				out.append(SiteRig.place(made, "barracks", SiteRig.WIDE))
	if tick == 50:
		out.append(Command.queue(1, SiteRig.type_of(made, "power_plant")))
	if tick == 90 and with_sites:
		out.append(Command.place(1, 9700, 5300))  # The old path: the ready head, no type.
	return out


func _world() -> World:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 20)
	SiteRig.fast(made, "renew_power", 20)
	SiteRig.fast(made, "barracks", 30)
	var rifle: int = SiteRig.type_of(made, "rifle_squad")
	for unit: int in 3:
		made.add_unit(2, rifle, 8500 + unit * 600, 9000)
	return made


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## One run of the script on `impl`: the world, the loop (its replay holds the log).
class Played:
	extends RefCounted
	var world: World
	var loop: MatchLoop


func _play(impl: int, with_sites: bool = true) -> Played:
	var played: Played = Played.new()
	played.world = _world()
	assert_array(SimImpls.use(played.world, impl)).is_empty()
	played.loop = MatchLoop.create(null, "", SEED, played.world)
	for _tick: int in TICKS:
		played.loop.step(played.world, _commands_at(played.world, played.world.tick, with_sites))
	played.loop.replay.finish(played.world)
	return played


func test_the_script_exercises_sites_drops_and_both_paths() -> void:
	var played: Played = _play(SimImpls.Impl.GDSCRIPT)
	var made: World = played.world
	assert_int(made.dropped_commands).is_equal(1)  # Only the second PLACE of tick 12.
	# The plant and the Wind Park finished (the count includes the old path's plant, placed at 90).
	assert_int(made.stat_built[2]).is_equal(1)
	assert_int(made.stat_built[1]).is_greater_equal(2)
	var plants: Array[int] = SiteRig.rows_of(made, 1, "power_plant")
	assert_int(plants.size()).is_equal(3)  # The shipped one, the site's and the old path's.
	assert_int(made.credits[1]).is_less(made.start_credits)


func test_a_scripted_match_with_sites_has_one_hash_in_both_implementations(
	impl: int, _test_parameters := _both()
) -> void:
	var reference: Played = _play(SimImpls.Impl.GDSCRIPT)
	var played: Played = _play(impl)
	assert_int(played.world.state_hash()).is_equal(reference.world.state_hash())
	assert_array(played.loop.replay.checkpoint_hashes).is_equal(
		reference.loop.replay.checkpoint_hashes
	)
	assert_array(played.world.build_left).is_equal(reference.world.build_left)
	assert_int(played.world.native_phases).is_equal(
		SimImpls.expected_mask() if impl == SimImpls.Impl.NATIVE else 0
	)


func test_two_runs_agree_and_the_sites_are_part_of_the_state() -> void:
	var first: Played = _play(SimImpls.Impl.GDSCRIPT)
	var second: Played = _play(SimImpls.Impl.GDSCRIPT)
	assert_int(first.world.state_hash()).is_equal(second.world.state_hash())
	assert_array(first.loop.replay.checkpoint_hashes).is_equal(second.loop.replay.checkpoint_hashes)
	var bare: Played = _play(SimImpls.Impl.GDSCRIPT, false)
	assert_int(bare.world.state_hash()).is_not_equal(first.world.state_hash())
	# The first checkpoint after the first PLACE (tick 3) already differs: build_left and the
	# credits are hashed.
	var at: int = first.loop.replay.checkpoint_ticks.find(15)
	assert_int(at).is_greater_equal(0)
	assert_int(bare.loop.replay.checkpoint_hashes[at]).is_not_equal(
		first.loop.replay.checkpoint_hashes[at]
	)


func test_a_replay_of_a_match_with_sites_reproduces_every_checkpoint() -> void:
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
	# The typed PLACE is in the log with its payload.
	var typed: int = 0
	var data: PackedInt32Array = replay.commands
	var at: int = 0
	while at < data.size():
		var command: Command = Command.new()
		at = Command.decode(data, at, command)
		assert_int(at).is_greater(0)
		if command.type == Command.Type.PLACE and command.payload.size() == 1:
			typed += 1
	assert_int(typed).is_equal(4)
