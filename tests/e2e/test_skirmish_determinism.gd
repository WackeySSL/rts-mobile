extends GdUnitTestSuite
## Phase 3 end to end, the hashes (plan row P94, CLAUDE.md rule 2 and the qa-engineer rules): the
## full matches of `skirmish_match.gd` end in the same state however they are played again.
## - The GDScript twins and the C++ kernels (ADR 0013) play each match, scripted player, dummy and
##   all, through a MatchRunner to the same checkpoint at every 15th tick, the same log and the
##   same final state; P71's lockstep suites compare one phase on a hand-built World each, this is
##   the whole simulation over 8,500 ticks of a real Skirmish.
## - A recorded log replays from the seed to every checkpoint and the final hash with no AI and no
##   player, from the bytes that a file would hold.
## - Two dummies on the same route, played twice from one seed, give the same checkpoints (ADR 0020
##   section 5; P83d's suite does it on its own 40 x 40 start, the smoke run on the first route).
## A difference in any of them is a simulation bug, never a case to relax.

const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
const Match: GDScript = preload("res://tests/e2e/support/skirmish_match.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const FACTIONS: Array[String] = ["fossil", "renew"]
## Ticks of a dummy-vs-dummy match, the smoke run's.
const DUMMY_TICKS: int = 1800


func before() -> void:
	for faction: String in FACTIONS:
		Match.played(self, faction, SimImpls.Impl.GDSCRIPT)
		Match.played(self, faction, SimImpls.Impl.NATIVE)


func test_the_kernels_play_each_match_to_the_twins_state_at_every_checkpoint() -> void:
	for faction: String in FACTIONS:
		var twin: Match.Played = Match.played(self, faction, SimImpls.Impl.GDSCRIPT)
		var native: Match.Played = Match.played(self, faction, SimImpls.Impl.NATIVE)
		# Not the same run twice: the kernels ran the phases in the one, the twins in the other.
		for phase: int in SimImpls.EXPECTED_PHASES:
			assert_bool(SimImpls.is_native(native.world, phase)).is_true()
			assert_bool(SimImpls.is_native(twin.world, phase)).is_false()
		assert_array(Array(native.replay.checkpoint_ticks)).is_equal(
			Array(twin.replay.checkpoint_ticks)
		)
		assert_str(_first_difference(native.replay, twin.replay)).is_empty()
		assert_array(Array(native.replay.commands)).override_failure_message(faction).is_equal(
			Array(twin.replay.commands)
		)
		assert_int(native.replay.final_hash).override_failure_message(faction).is_equal(
			twin.replay.final_hash
		)
		(
			assert_str(StateDiff.first(native.world, twin.world))
			. override_failure_message(faction)
			. is_empty()
		)
		assert_str(HashReport.mismatch(native.world, twin.world)).is_empty()
		# And so the same end, strike and result screen.
		assert_array([native.world.winner, native.world.match_end_tick]).is_equal(
			[twin.world.winner, twin.world.match_end_tick]
		)
		assert_int(native.player.strike_tick).is_equal(twin.player.strike_tick)
		assert_array(native.screen_cells).is_equal(twin.screen_cells)


## The checkpoints are one every 15th tick from tick 15 to the tick that ended the match, each a new
## state: a run that stood still would match anything.
func test_the_matches_have_a_checkpoint_every_15_ticks_and_each_is_a_new_state() -> void:
	for faction: String in FACTIONS:
		var replay: Replay = Match.played(self, faction, SimImpls.Impl.GDSCRIPT).replay
		var count: int = replay.final_tick / Replay.CHECKPOINT_PERIOD
		assert_int(replay.checkpoint_ticks.size()).override_failure_message(faction).is_equal(count)
		for index: int in count:
			assert_int(replay.checkpoint_ticks[index]).is_equal(
				(index + 1) * Replay.CHECKPOINT_PERIOD
			)
		var seen: Dictionary[int, bool] = {}
		for hash_value: int in replay.checkpoint_hashes:
			seen[hash_value] = true
		assert_int(seen.size()).override_failure_message(faction).is_equal(count)


## The log, written to bytes and read back, plays from the seed with no AI and no player to every
## checkpoint and to the final hash of the match.
func test_a_recorded_match_replays_from_its_bytes_to_every_checkpoint() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = Match.played(self, faction, SimImpls.Impl.GDSCRIPT)
		var bytes: PackedByteArray = played.replay.to_bytes()
		var loaded: Replay = Replay.from_bytes(bytes)
		assert_object(loaded).override_failure_message(faction).is_not_null()
		assert_array(Array(loaded.to_bytes())).override_failure_message(faction).is_equal(
			Array(bytes)
		)
		var fresh: World = Match.fresh_world(faction)
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
		assert_array([fresh.winner, fresh.match_end_tick]).is_equal(
			[played.world.winner, played.world.match_end_tick]
		)
		# The log is the match: the player's orders and the dummy's are in it, and it needed no more.
		assert_array(played.commands()).is_not_empty()


## Two dummies, the Derrick League's and the Lumen Accord's, on each route's start (the player's
## side swapped between the two), played twice from seed 42: the same checkpoints, the same log and
## the same final state, nothing dropped, both bases going up; and the two routes are two matches.
func test_two_dummies_on_each_route_play_twice_to_the_same_hashes() -> void:
	var finals: Array[int] = []
	for faction: String in FACTIONS:
		var first: Array = _dummies_play(faction)
		var second: Array = _dummies_play(faction)
		var one: World = first[0]
		var two: World = second[0]
		var one_loop: MatchLoop = first[1]
		var two_loop: MatchLoop = second[1]
		assert_int(one_loop.replay.checkpoint_ticks.size()).is_equal(DUMMY_TICKS / 15)
		assert_str(_first_difference(one_loop.replay, two_loop.replay)).is_empty()
		assert_array(Array(one_loop.replay.commands)).is_equal(Array(two_loop.replay.commands))
		assert_int(one.state_hash()).override_failure_message(faction).is_equal(two.state_hash())
		assert_int(one.dropped_commands).override_failure_message(faction).is_equal(0)
		assert_int(one.stat_built[1]).override_failure_message(faction).is_greater(0)
		assert_int(one.stat_built[2]).override_failure_message(faction).is_greater(0)
		finals.append(one.state_hash())
	assert_int(finals[0]).is_not_equal(finals[1])


## "" when the checkpoints of the two replays are the same ticks and hashes, else the first tick at
## which they differ.
func _first_difference(a: Replay, b: Replay) -> String:
	if a.checkpoint_ticks != b.checkpoint_ticks:
		return "the checkpoint ticks differ"
	for index: int in a.checkpoint_hashes.size():
		if a.checkpoint_hashes[index] != b.checkpoint_hashes[index]:
			return "first checkpoint that differs: tick %d" % a.checkpoint_ticks[index]
	return ""


## The World and the loop of a route's start played for `DUMMY_TICKS` by the dummy of each side's
## faction as MatchRunner makes them (the player 1 dummy is the one of the faction the player has).
func _dummies_play(faction: String) -> Array:
	var route: Dictionary = Match.ROUTES[faction]
	var world: World = Match.fresh_world(faction)
	var loop: MatchLoop = MatchLoop.create(
		load(route["scenario"]) as ScenarioDef, route["scenario"], Match.SEED, world
	)
	var defs: Array[String] = [Match.ROUTES[route["dummy_faction"]]["dummy"], route["dummy"]]
	var controllers: Array[AiController] = []
	for index: int in defs.size():
		var rng: DetRandom = DetRandom.create(Match.SEED, DetRandom.STREAM_AI_BASE + index + 1)
		controllers.append(DummyAi.create(load(defs[index]) as AiDef, index + 1, rng))
	SmokeRun.run(world, loop, controllers, DUMMY_TICKS)
	return [world, loop]
