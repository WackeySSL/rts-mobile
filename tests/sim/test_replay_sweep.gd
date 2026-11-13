extends GdUnitTestSuite
## A replay through a satellite sweep (plan row P234, ADR 0036 section 11, the P233 "as built"
## note). `dev_sweep.tres` holds the shipped Skyrig for the Derrick League and the shipped Dusk
## Array for the Lumen Accord, both fully charged by `charge_elapsed_ticks`, with the plants that
## keep the Skyrig off low power. The match is recorded on the C++ kernels: player 1 fires the
## sweep, player 2 blacks the space centre out. `Replay.play` then runs the log on the GDScript
## twin, on a world made from `PATH` and `SEED` (the replay's own, asserted equal), to a checkpoint
## inside the sweep (on) and two inside the pause (the blackout lasts 450 ticks). A light tank of
## player 1 is moved after the sweep starts, so the FOG kernel stamps under it; the live run is
## held to the row rebuild at each checkpoint. At each the world equals the recording by
## the checkpoint hash, `reveal` and the fog's whole-map flag are as recorded, `visible` is the
## rebuild of the rows (`fog_derivation.gd`), and a rebuild of `visible` from the hashed state
## (`WorldLoad.stamp_fog`, as the live code does it for a fresh World) gives the same counts.

const Derivation: GDScript = preload("res://tests/sim/support/fog_derivation.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const PATH: String = "res://data/scenarios/dev_sweep.tres"
const SEED: int = 42
## The command of tick FIRE fires the sweep, the command of tick BLACK blacks the space centre out.
## Checkpoints come every 15 ticks: 30 is inside the sweep, 60 and 75 inside the pause (the
## blackout lasts `strike_ticks` of the Dusk Array, 450). The tank moves two tiles at FIRE + 1.
const FIRE: int = 10
const BLACK: int = 40
const CHECKS: Array[int] = [30, 60, 75]
## The middle of the space centre's 3x3 footprint at tile (4, 14), in milli-tiles.
const TANK_TO: Vector2i = Vector2i(10500, 20500)
const OVER_SPACE: Vector2i = Vector2i(5500, 15500)


## The scenario's World as `Replay.play` and the recorder make it, on `impl`.
func _world(impl: int) -> World:
	var scenario: ScenarioDef = load(PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	assert_array(SimImpls.use(world, impl)).is_empty()
	return world


## The id of player `player`'s building of type `id`.
func _id(world: World, id: StringName, player: int) -> int:
	var type: int = world.type_ids.find(id)
	for row: int in world.unit_id.size():
		if world.type_index[row] == type and world.owner[row] == player:
			return world.unit_id[row]
	return 0


## `world`'s `visible` after a rebuild from its hashed state alone: a fresh grid with `explored`
## kept, then `WorldLoad.stamp_fog` (what `prepare()` does), as test_reveal_fog does it.
func _rebuilt_visible(world: World) -> PackedInt32Array:
	var fresh: FogGrid = FogGrid.new()
	fresh.configure(world.fog.cols, world.fog.rows, world.fog.player_count)
	fresh.explored = world.fog.explored.duplicate()
	world.fog = fresh
	WorldLoad.stamp_fog(world)
	return world.fog.visible.duplicate()


func test_replay_to_a_checkpoint_inside_a_sweep_and_inside_its_pause_matches_the_live_run() -> void:
	var live: World = _world(SimImpls.Impl.NATIVE)
	var scenario: ScenarioDef = load(PATH) as ScenarioDef
	var loop: MatchLoop = MatchLoop.create(scenario, PATH, SEED, live)
	var site: int = _id(live, &"fossil_space", 1)
	var array: int = _id(live, &"renew_strike", 2)
	var tank: int = _id(live, &"light_tank", 1)
	assert_array([site, array, tank]).not_contains([0])
	for building: int in [site, array]:
		var ready: int = live.ready_tick[live.index_of(building)]
		(
			assert_int(ready)
			. override_failure_message(
				(
					"the charge of row %d is not spent: raise charge_elapsed_ticks in dev_sweep.tres"
					% building
				)
			)
			. is_less_equal(1)
		)
	var states: Dictionary[int, PackedInt32Array] = {}
	while live.tick < CHECKS[-1]:
		var commands: Array[Command] = []
		if live.tick == FIRE:
			commands.append(Command.superweapon(1, site, 0, 0))
		if live.tick == BLACK:
			commands.append(Command.superweapon(2, array, OVER_SPACE.x, OVER_SPACE.y))
		if live.tick == FIRE + 1:
			commands.append(Command.move(1, PackedInt32Array([tank]), TANK_TO.x, TANK_TO.y))
		loop.step(live, commands)
		states[live.tick] = live.reveal.duplicate()
		if live.tick in CHECKS:
			var problem: String = Derivation.mismatch(live)
			assert_str(problem).override_failure_message("live, tick %d" % live.tick).is_empty()
	assert_int(live.dropped_commands).is_equal(0)
	# The live run is what the case claims: on inside the sweep, paused inside the blackout, and
	# the blackout (450 ticks) still on at the last checkpoint.
	assert_array([states[30][1], states[60][1], states[75][1]]).is_equal(
		[Reveal.State.ON, Reveal.State.PAUSED, Reveal.State.PAUSED]
	)
	loop.replay.finish(live)
	var replay: Replay = loop.replay
	assert_array([replay.scenario_path, replay.seed]).is_equal([PATH, SEED])
	for until: int in CHECKS:
		var fresh: World = _world(SimImpls.Impl.GDSCRIPT)
		replay.apply_setup(fresh)
		var label: String = "tick %d" % until
		assert_int(Replay.play(replay, fresh, until)).override_failure_message(label).is_equal(
			Replay.PLAY_MATCHED
		)
		assert_int(fresh.tick).is_equal(until)
		assert_array(fresh.reveal).override_failure_message(label).is_equal(states[until])
		var on: bool = states[until][1] == Reveal.State.ON
		assert_int(fresh.fog.revealed[0]).override_failure_message(label).is_equal(1 if on else 0)
		var at: int = replay.checkpoint_ticks.find(until)
		assert_int(at).is_greater(-1)
		assert_int(fresh.state_hash()).is_equal(replay.checkpoint_hashes[at])
		if until == CHECKS[-1]:
			assert_int(fresh.state_hash()).is_equal(replay.final_hash)
			assert_str(HashReport.mismatch(fresh, live)).is_empty()
		assert_str(Derivation.mismatch(fresh)).override_failure_message(label).is_empty()
		# Last: the rebuild replaces the fog and rewrites the hashed `fog_cell`.
		var visible: PackedInt32Array = fresh.fog.visible.duplicate()
		assert_array(_rebuilt_visible(fresh)).override_failure_message(label).is_equal(visible)
