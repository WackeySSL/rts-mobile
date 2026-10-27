extends GdUnitTestSuite
## The two dummies against each other, one per faction (plan row P83d, ADR 0020 section 5, ADR 0023
## section 6): P83's `test_dummy_match.gd` with the Derrick League's dummy as player 1 and the Lumen
## Accord's as player 2 on the faction start of `faction_rig.gd`. They run for 3,600 ticks through
## the headless loop, twice from the same seed, then replayed without any AI. Nothing is dropped,
## both bases are built from each side's own types, each dummy thinks on its own tick, and the runs
## and the replay agree on every checkpoint.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Factions: GDScript = preload("res://tests/ai/support/faction_rig.gd")
const TICKS: int = 3600
const FIRST: String = "fossil"
const SECOND: String = "renew"

var _first: World
var _second: World
var _first_loop: MatchLoop
var _second_loop: MatchLoop
var _sent: Array[Command]
var _replayed: int = 0


func before() -> void:
	_first = Factions.start(FIRST, SECOND)
	_first_loop = Rig.loop_of(_first)
	_sent = Rig.run(_first, _first_loop, _dummies(), TICKS)
	_second = Factions.start(FIRST, SECOND)
	_second_loop = Rig.loop_of(_second)
	Rig.run(_second, _second_loop, _dummies(), TICKS)
	_replayed = Replay.play(_first_loop.replay, Factions.start(FIRST, SECOND), _first.tick)


func test_neither_dummy_sends_a_command_the_sim_drops() -> void:
	assert_int(_first.dropped_commands).is_equal(0)
	assert_int(_first.spawn_refused).is_equal(0)
	assert_bool(_sent.is_empty()).is_false()


func test_both_bases_are_built_from_their_own_faction_and_the_match_goes_on() -> void:
	for player: int in [1, 2]:
		var faction: String = [FIRST, SECOND][player - 1]
		var def: AiDef = Factions.def_of(faction)
		var needed: Dictionary[String, int] = {}
		for id: StringName in def.build_order:
			needed[String(id)] = needed.get(String(id), 0) + 1
		for id: String in needed:
			assert_int(Rig.count_of(_first, player, id)).is_equal(needed[id])
		assert_int(Rig.count_of(_first, player, String(def.harvester_type))).is_equal(
			def.harvesters_wanted
		)
		assert_bool(Factions.owns_only(_first, player, faction)).is_true()
	assert_array([_first.match_end_tick, _first.winner]).is_equal([0, 0])


func test_no_dummy_queues_a_type_of_the_other_faction() -> void:
	var queued: Dictionary[int, int] = {}
	for command: Command in _sent:
		if command.type == Command.Type.QUEUE:
			queued[command.player_id] = queued.get(command.player_id, 0) + 1
			var faction: String = Factions.faction_of(_first, command.payload[0])
			assert_str(faction).is_equal([FIRST, SECOND][command.player_id - 1])
	# Each queued its build order and the harvester the refinery did not bring, and nothing else.
	for player: int in [1, 2]:
		var def: AiDef = Factions.def_of([FIRST, SECOND][player - 1])
		assert_int(queued[player]).is_equal(def.build_order.size() + def.harvesters_wanted - 1)


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


## A new pair of controllers of the same seed: the Derrick League's as player 1, the Lumen
## Accord's as player 2.
func _dummies() -> Array:
	return [Factions.dummy(FIRST, 1), Factions.dummy(SECOND, 2)]
