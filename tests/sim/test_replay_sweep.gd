extends GdUnitTestSuite
## A replay through a satellite sweep (plan row P234, ADR 0036 section 11, the P233 "as built"
## note): the shipped space centres on Kestrel Flats, a sweep fired by the Derrick League's, a
## blackout of the Lumen Accord's that pauses it, and `Replay.play` to a checkpoint inside the sweep
## (on) and one inside the pause. The world at each equals the live run at the same tick, by the
## recorded checkpoint hash and by the whole state, and the fog's whole-map stamp is the one a
## rebuild from the hashed state gives. The two buildings start fully charged (`Strike.age_charge`,
## the scenarios' `charge_elapsed_ticks`), so the case does not step 2,700 ticks to a first firing.

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
## The ticks: the sweep is fired by the command of tick FIRE, the blackout by the command of
## tick BLACK. Checkpoints come every 15 ticks, so 30 is inside the sweep and 60 inside the pause.
const FIRE: int = 10
const BLACK: int = 40
const ON_AT: int = 30
const PAUSED_AT: int = 60
const SPACE_TILE: Vector2i = Vector2i(18, 18)
const BLACKOUT_AT: Vector2i = Vector2i(19500, 19500)


## The Kestrel Flats skirmish with player 1's space centre and player 2's blackout building added
## and charged, the way the runner would hold them after their build. The same call makes the live
## world and each replay world, so their states start equal.
func _world() -> World:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	var space: int = world.type_ids.find(&"fossil_space")
	var array: int = world.type_ids.find(&"renew_strike")
	assert_int(space).is_greater(-1)
	assert_int(world.type_strike_kind[space]).is_equal(Strike.Kind.REVEAL)
	assert_int(world.type_charge_ticks[space]).is_equal(2700)
	var site: int = world.add_building(1, space, SPACE_TILE.x, SPACE_TILE.y)
	# The space centre uses 60 power, which the start's plants do not cover: one more plant.
	var plant: int = world.add_building(1, world.type_ids.find(&"power_plant"), 22, 18)
	var blackout: int = world.add_building(2, array, 30, 30)
	assert_int(plant).is_not_equal(0)
	assert_int(site).is_not_equal(0)
	assert_int(blackout).is_not_equal(0)
	Strike.age_charge(world, world.index_of(site), 2700)
	Strike.age_charge(world, world.index_of(blackout), 4500)
	world.credits[1] = 100000
	return world


## The id of player `player`'s building of type `id`.
func _id(world: World, id: StringName, player: int) -> int:
	var type: int = world.type_ids.find(id)
	for row: int in world.unit_id.size():
		if world.type_index[row] == type and world.owner[row] == player:
			return world.unit_id[row]
	return 0


func test_replay_to_a_checkpoint_inside_a_sweep_and_inside_its_pause_matches_the_live_run() -> void:
	var live: World = _world()
	var scenario: ScenarioDef = load(Rig.SKIRMISH_PATH) as ScenarioDef
	var loop: MatchLoop = MatchLoop.create(scenario, Rig.SKIRMISH_PATH, Rig.SEED, live)
	var states: Dictionary[int, PackedInt32Array] = {}
	var array: int = _id(live, &"renew_strike", 2)
	var site: int = _id(live, &"fossil_space", 1)
	while live.tick < PAUSED_AT + 15:
		var commands: Array[Command] = []
		if live.tick == FIRE:
			commands.append(Command.superweapon(1, site, 0, 0))
		if live.tick == BLACK:
			commands.append(Command.superweapon(2, array, BLACKOUT_AT.x, BLACKOUT_AT.y))
		loop.step(live, commands)
		states[live.tick] = live.reveal.duplicate()
		if live.tick == ON_AT or live.tick == PAUSED_AT:
			assert_int(live.dropped_commands).is_equal(0)
	# The live run is what the case claims: on inside the sweep, paused inside the blackout.
	assert_array([states[ON_AT][1], states[PAUSED_AT][1]]).is_equal(
		[Reveal.State.ON, Reveal.State.PAUSED]
	)
	assert_int(live.fog.revealed[0]).is_equal(0)
	loop.replay.finish(live)
	var replay: Replay = loop.replay
	for until: int in [ON_AT, PAUSED_AT, PAUSED_AT + 15]:
		var fresh: World = _world()
		assert_int(Replay.play(replay, fresh, until)).override_failure_message(str(until)).is_equal(
			Replay.PLAY_MATCHED
		)
		assert_int(fresh.tick).is_equal(until)
		assert_array(fresh.reveal).is_equal(states[until])
		assert_int(fresh.fog.revealed[0]).is_equal(1 if states[until][1] == Reveal.State.ON else 0)
		var at: int = replay.checkpoint_ticks.find(until)
		assert_int(at).is_greater(-1)
		assert_int(fresh.state_hash()).is_equal(replay.checkpoint_hashes[at])
	# Played to the end, the world is the live one, part by part.
	var whole: World = _world()
	assert_int(Replay.play(replay, whole, live.tick)).is_equal(Replay.PLAY_MATCHED)
	assert_int(whole.state_hash()).is_equal(replay.final_hash)
	assert_str(HashReport.mismatch(whole, live)).is_empty()
