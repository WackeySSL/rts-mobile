extends GdUnitTestSuite
## Phase 4 end to end (plan row P193, the gate's "each level of each computer plays a match"):
## - The dev route of each Skirmish (`DevRoutes.open_skirmish`, the Derrick League against the
##   Lumen Accord's computer and the Lumen Accord against the Derrick League's) builds the computer
##   at each of the three levels, six pairs, and plays 900 ticks with none of its Commands dropped.
## - Two full headless Skirmishes at Normal, once as each faction, with the scripted player of P94
##   as player 1 (`phase4_match.gd`): each runs to its end or `MAX_TICKS` with no dropped Command
##   and replays from its bytes to every checkpoint. The end itself is not asserted.
## The two full matches are the whole of the suite's matches (the token budget). Ticks are counted,
## nothing is timed.

const Match: GDScript = preload("res://tests/e2e/support/phase4_match.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const SkirmishMatch: GDScript = preload("res://tests/e2e/support/skirmish_match.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const FACTIONS: Array[String] = ["fossil", "renew"]
const ROUTE_TICKS: int = 900


func before() -> void:
	for faction: String in FACTIONS:
		Match.played(faction)


func after() -> void:
	Match.forget()


func before_test() -> void:
	MenuRig.begin()


## The scene a test left is freed, and the orders a test queued are dropped.
func after_test() -> void:
	MenuRig.end()
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null
	CommandQueue.clear()


func test_derrick_league_against_the_lumen_computer_at_easy() -> void:
	await _route(DevRoutes.SKIRMISH_DERRICK, DevRoutes.OPPONENT_RENEW, DevRoutes.LEVEL_EASY)


func test_derrick_league_against_the_lumen_computer_at_normal() -> void:
	await _route(DevRoutes.SKIRMISH_DERRICK, DevRoutes.OPPONENT_RENEW, DevRoutes.LEVEL_NORMAL)


func test_derrick_league_against_the_lumen_computer_at_hard() -> void:
	await _route(DevRoutes.SKIRMISH_DERRICK, DevRoutes.OPPONENT_RENEW, DevRoutes.LEVEL_HARD)


func test_lumen_accord_against_the_derrick_computer_at_easy() -> void:
	await _route(DevRoutes.SKIRMISH_LUMEN, DevRoutes.OPPONENT_FOSSIL, DevRoutes.LEVEL_EASY)


func test_lumen_accord_against_the_derrick_computer_at_normal() -> void:
	await _route(DevRoutes.SKIRMISH_LUMEN, DevRoutes.OPPONENT_FOSSIL, DevRoutes.LEVEL_NORMAL)


func test_lumen_accord_against_the_derrick_computer_at_hard() -> void:
	await _route(DevRoutes.SKIRMISH_LUMEN, DevRoutes.OPPONENT_FOSSIL, DevRoutes.LEVEL_HARD)


## Each full match ran to its end or `MAX_TICKS`, the sim dropped no Command of either side, the
## computer of player 2 was an OpponentAi at Normal that commanded and was never cut, and the
## kernels ran where the library loads.
func test_the_full_matches_drop_no_command_and_the_computer_played() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = Match.played(faction)
		assert_object(played).append_failure_message(faction).is_not_null()
		if played == null:
			continue
		var world: World = played.world
		assert_int(world.dropped_commands).append_failure_message(faction).is_equal(0)
		var stopped: bool = world.match_end_tick > 0 or world.tick == Match.MAX_TICKS
		assert_bool(stopped).append_failure_message(faction).is_true()
		_assert_computer(played.computer, Match.ROUTES[faction], faction)
		(
			assert_bool(SimImpls.is_native(world, SimProbe.Phase.FLOW))
			. append_failure_message(faction)
			. is_equal(Match.native_expected())
		)


## Both sides played: the log holds the scripted player's Commands and the computer's.
func test_the_full_matches_log_both_sides() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = Match.played(faction)
		assert_object(played).append_failure_message(faction).is_not_null()
		if played == null:
			continue
		var seen: Dictionary[int, bool] = {}
		for command: Command in SkirmishMatch.Played.log_commands(played.replay):
			seen[command.player_id] = true
		for player: int in [1, 2]:
			var who: String = "%s: player %d" % [faction, player]
			assert_bool(seen.has(player)).append_failure_message(who).is_true()


## The header names the route and the seed; there is at least one checkpoint, one every 15th tick up
## to the end; and the log written to bytes and read back plays from the header's scenario and seed
## with no player and no computer to every checkpoint and to the final hash. With the kernels loaded
## the match ran on them and the replay on the twins, so this is the cross-check of the two.
func test_the_full_matches_replay_to_their_checkpoints() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = Match.played(faction)
		assert_object(played).append_failure_message(faction).is_not_null()
		if played == null:
			continue
		var replay: Replay = played.replay
		var count: int = replay.final_tick / Replay.CHECKPOINT_PERIOD
		assert_int(count).append_failure_message(faction).is_greater(0)
		assert_int(replay.checkpoint_ticks.size()).append_failure_message(faction).is_equal(count)
		for index: int in mini(count, replay.checkpoint_ticks.size()):
			assert_int(replay.checkpoint_ticks[index]).append_failure_message(faction).is_equal(
				(index + 1) * Replay.CHECKPOINT_PERIOD
			)
		var bytes: PackedByteArray = replay.to_bytes()
		var loaded: Replay = Replay.from_bytes(bytes)
		assert_object(loaded).append_failure_message(faction).is_not_null()
		if loaded == null:
			continue
		assert_str(loaded.scenario_path).append_failure_message(faction).is_equal(
			Match.ROUTES[faction]["scenario"]
		)
		assert_int(loaded.seed).append_failure_message(faction).is_equal(Match.SEED)
		var fresh: World = Match.fresh_world(loaded)
		var result: int = Replay.play(loaded, fresh, loaded.final_tick)
		(
			assert_int(result)
			. append_failure_message(
				(
					"%s: Replay.play returned %d (-1 matched, a tick is the first checkpoint that differs)"
					% [faction, result]
				)
			)
			. is_equal(Replay.PLAY_MATCHED)
		)
		assert_int(fresh.tick).append_failure_message(faction).is_equal(played.world.tick)
		# state_hash() must run before StateDiff.first: it refreshes the map digest that StateDiff reads.
		var final_hash: int = fresh.state_hash()
		assert_int(final_hash).append_failure_message(faction).is_equal(loaded.final_hash)
		assert_str(StateDiff.first(fresh, played.world)).append_failure_message(faction).is_empty()


## Opens the dev route of `scenario_path` against the computer `opponent_path` at `level_path`, then
## restarts its match with the clock paused (the frames of the scene change played a few ticks) and
## plays `ROUTE_TICKS` ticks: the computer, player 2, commanded, and nothing dropped.
func _route(scenario_path: String, opponent_path: String, level_path: String) -> void:
	var label: String = "%s vs %s at %s" % [scenario_path, opponent_path, level_path]
	var opened: Error = DevRoutes.open_skirmish(
		get_tree(), scenario_path, opponent_path, level_path
	)
	assert_int(opened).append_failure_message(label).is_equal(OK)
	if opened != OK:
		return
	await await_idle_frame()
	await await_idle_frame()
	var main: Node = get_tree().current_scene
	var runner: MatchRunner = main.get_node("MatchRunner")
	runner.paused = true
	runner.start()
	var computer: OpponentAi = runner._job.controllers[0] as OpponentAi
	runner.run_ticks(ROUTE_TICKS)
	assert_int(runner.world.tick).append_failure_message(label).is_equal(ROUTE_TICKS)
	assert_int(runner.world.dropped_commands).append_failure_message(label).is_equal(0)
	_assert_computer(computer, {"opponent": opponent_path, "level": level_path}, label)
	var stray: String = ""
	var logged: Array[Command] = SkirmishMatch.Played.log_commands(runner.replay)
	for command: Command in logged:
		if command.player_id != 2:
			stray = (
				"player %d, tick %d, %s"
				% [command.player_id, command.tick, Command.Type.find_key(command.type)]
			)
			break
	assert_array(logged).append_failure_message(label).is_not_empty()
	assert_str(stray).append_failure_message(label + ": first Command not of player 2").is_empty()


## `computer` is the OpponentAi of `route`'s opponent at its level, with that level's numbers, and
## it has commanded and never been cut.
func _assert_computer(computer: OpponentAi, route: Dictionary, label: String) -> void:
	assert_object(computer).append_failure_message(label).is_not_null()
	if computer == null:
		return
	var def: AiDef = load(route["opponent"]) as AiDef
	var level: AiDifficultyDef = load(route["level"]) as AiDifficultyDef
	assert_str(str(computer.def_id)).append_failure_message(label).is_equal(str(def.id))
	assert_str(str(computer.level_id)).append_failure_message(label).is_equal(str(level.id))
	assert_int(computer.tier).append_failure_message(label).is_equal(level.build_order_tier)
	assert_int(computer.commands_per_think_max).append_failure_message(label).is_equal(
		level.commands_per_think_max
	)
	assert_int(computer.commands).append_failure_message(label).is_greater(0)
	assert_int(computer.commands_cut).append_failure_message(label).is_equal(0)
