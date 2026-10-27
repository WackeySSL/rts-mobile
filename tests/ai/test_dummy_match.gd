extends GdUnitTestSuite
## Two dummies against each other on the mirrored start of `ai_rig.gd` (plan row P83, ADR 0020
## sections 4 and 5, in the short form that this row can prove without the driver of row P82):
## players 1 and 2, each on the shipped def, run for 3,600 ticks through the headless loop, twice
## from the same seed, then replayed without any AI. Nothing is dropped, both bases are built,
## each dummy thinks on its own tick, and the runs and the replay agree on every checkpoint.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const TICKS: int = 3600

var _first: World
var _second: World
var _first_loop: MatchLoop
var _second_loop: MatchLoop
var _sent: Array[Command]
var _replayed: int = 0


func before() -> void:
	_first = Rig.start()
	_first_loop = Rig.loop_of(_first)
	_sent = Rig.run(_first, _first_loop, [Rig.dummy(1), Rig.dummy(2)], TICKS)
	_second = Rig.start()
	_second_loop = Rig.loop_of(_second)
	Rig.run(_second, _second_loop, [Rig.dummy(1), Rig.dummy(2)], TICKS)
	_replayed = Replay.play(_first_loop.replay, Rig.start(), _first.tick)


func test_neither_dummy_sends_a_command_the_sim_drops() -> void:
	assert_int(_first.dropped_commands).is_equal(0)
	assert_int(_first.spawn_refused).is_equal(0)
	assert_bool(_sent.is_empty()).is_false()


func test_both_bases_are_built_and_the_match_goes_on() -> void:
	var def: AiDef = Rig.dummy_def()
	var needed: Dictionary[String, int] = {}
	for id: StringName in def.build_order:
		needed[String(id)] = needed.get(String(id), 0) + 1
	for player: int in [1, 2]:
		for id: String in needed:
			assert_int(Rig.count_of(_first, player, id)).is_equal(needed[id])
		assert_int(Rig.count_of(_first, player, "harvester")).is_equal(def.harvesters_wanted)
	assert_array([_first.match_end_tick, _first.winner]).is_equal([0, 0])


func test_each_dummy_commands_on_its_own_tick() -> void:
	var seen: Dictionary[int, bool] = {}
	for command: Command in _sent:
		seen[command.player_id] = true
		# Player 1 thinks at tick % 15 == 6 and player 2 at 7 (think_tick 7 is player 2's).
		assert_int(command.tick % 15).is_equal(5 + command.player_id)
	assert_array(seen.keys()).is_equal([1, 2])


func test_two_runs_of_a_seed_have_the_same_checkpoints_and_commands() -> void:
	# One checkpoint every 15th tick from tick 15: 240 of them by tick 3,600.
	assert_int(_first_loop.replay.checkpoint_ticks.size()).is_equal(240)
	assert_array(Array(_first_loop.replay.checkpoint_hashes)).is_equal(
		Array(_second_loop.replay.checkpoint_hashes)
	)
	assert_array(Array(_first_loop.replay.commands)).is_equal(Array(_second_loop.replay.commands))
	assert_int(_first.state_hash()).is_equal(_second.state_hash())


func test_the_replay_reproduces_the_match_without_the_ai() -> void:
	assert_int(_replayed).is_equal(Replay.PLAY_MATCHED)
	assert_array(Array(_first_loop.replay.commands)).is_not_empty()
