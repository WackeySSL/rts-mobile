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
const FACTIONS: Array[String] = ["fossil", "renew"]
const ROUTE_TICKS: int = 900


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


## Each full match ran to its end or `MAX_TICKS`, and the sim dropped no Command of either side.
func test_the_full_matches_drop_no_command() -> void:
	for faction: String in FACTIONS:
		var world: World = Match.played(faction).world
		assert_int(world.dropped_commands).override_failure_message(faction).is_equal(0)
		var stopped: bool = world.match_end_tick > 0 or world.tick == Match.MAX_TICKS
		assert_bool(stopped).override_failure_message(faction).is_true()
		assert_int(world.tick).override_failure_message(faction).is_less_equal(Match.MAX_TICKS)


## Both sides played: the log holds the scripted player's Commands and the computer's.
func test_the_full_matches_log_both_sides() -> void:
	for faction: String in FACTIONS:
		var seen: Dictionary[int, bool] = {}
		for command: Command in _commands(Match.played(faction).replay):
			seen[command.player_id] = true
		for player: int in [1, 2]:
			var who: String = "%s: player %d" % [faction, player]
			assert_bool(seen.has(player)).override_failure_message(who).is_true()


## One checkpoint every 15th tick, each a new state, and the log written to bytes and read back
## plays from the seed with no player and no computer to every checkpoint and to the final hash.
func test_the_full_matches_replay_to_their_checkpoints() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = Match.played(faction)
		var replay: Replay = played.replay
		var count: int = replay.final_tick / Replay.CHECKPOINT_PERIOD
		assert_int(replay.checkpoint_ticks.size()).override_failure_message(faction).is_equal(count)
		var seen: Dictionary[int, bool] = {}
		for hash_value: int in replay.checkpoint_hashes:
			seen[hash_value] = true
		assert_int(seen.size()).override_failure_message(faction).is_equal(count)
		var bytes: PackedByteArray = replay.to_bytes()
		var loaded: Replay = Replay.from_bytes(bytes)
		assert_object(loaded).override_failure_message(faction).is_not_null()
		var fresh: World = Match.fresh_world(faction, loaded)
		var result: int = Replay.play(loaded, fresh, loaded.final_tick)
		(
			assert_int(result)
			. override_failure_message(
				"%s: first checkpoint that differs: tick %d" % [faction, result]
			)
			. is_equal(Replay.PLAY_MATCHED)
		)
		assert_int(fresh.tick).override_failure_message(faction).is_equal(played.world.tick)
		assert_int(fresh.state_hash()).override_failure_message(faction).is_equal(loaded.final_hash)


## Opens the dev route of `scenario_path` against the computer `opponent_path` at `level_path`, then
## restarts its match with the clock paused (the frames of the scene change played a few ticks) and
## plays `ROUTE_TICKS` ticks: the computer, player 2, commanded, and nothing dropped.
func _route(scenario_path: String, opponent_path: String, level_path: String) -> void:
	var label: String = "%s vs %s at %s" % [scenario_path, opponent_path, level_path]
	(
		assert_int(DevRoutes.open_skirmish(get_tree(), scenario_path, opponent_path, level_path))
		. is_equal(OK)
	)
	await await_idle_frame()
	await await_idle_frame()
	var main: Node = get_tree().current_scene
	var runner: MatchRunner = main.get_node("MatchRunner")
	assert_str(str(runner.opponents[0].id)).override_failure_message(label).is_equal(
		str(load(opponent_path).id)
	)
	assert_str(str(runner.opponent_levels[0].id)).override_failure_message(label).is_equal(
		str(load(level_path).id)
	)
	runner.paused = true
	runner.start()
	runner.run_ticks(ROUTE_TICKS)
	assert_int(runner.world.tick).override_failure_message(label).is_equal(ROUTE_TICKS)
	assert_int(runner.world.dropped_commands).override_failure_message(label).is_equal(0)
	var commands: Array[Command] = _commands(runner.replay)
	assert_array(commands).override_failure_message(label).is_not_empty()
	for command: Command in commands:
		assert_int(command.player_id).override_failure_message(label).is_equal(2)


## Every Command of `replay`'s log, decoded, in the order it was recorded.
func _commands(replay: Replay) -> Array[Command]:
	var found: Array[Command] = []
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		if at <= 0:
			break
		found.append(command)
	return found
