extends GdUnitTestSuite
## AI determinism (plan row P188, ADR 0031 section 7, ADR 0030 section 5): two opponents play the
## same short match twice from one seed, on the implementation AUTO picks and once more on the
## GDScript twin, and the three agree on the Commands, on the state hash at every checkpoint and
## on the record. The log of the first replays without any AI to the same checkpoints. A fourth
## case seats an `OpponentAi` on player 1 of `dev_strikes.tres`, which fires its Deep Bore within
## 900 ticks, drops nothing, and replays to the same hashes. Three AI matches of 2,700 ticks and
## one of 900 in all; each prints its `flow_full_ticks` (ADR 0030 section 4).
##
## The matches are played by `tests/smoke/smoke_run.gd`, the loop of `MatchRunner` without the
## Node, so this suite and the smoke run cannot drift. No clock is read: the `determinism-arm64`
## job runs this suite too (plan exception 21), where the hashes must be the x86_64 ones.
## No case asserts a winner or a length.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const Impls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")

const SEED: int = 1
const TICKS: int = 2700
const LEVELS: Array[String] = ["normal", "hard"]
const STRIKE_PATH: String = "res://data/scenarios/dev_strikes.tres"
const STRIKE_TICKS: int = 900

var _first: Dictionary = {}
var _again: Dictionary = {}
var _twin: Dictionary = {}


func before() -> void:
	_first = _play("")
	_again = _play("")
	_twin = _play(Smoke.IMPL_GDSCRIPT)
	var labels: Array[String] = ["AUTO", "AUTO again", "GDScript"]
	var plays: Array[Dictionary] = [_first, _again, _twin]
	for at: int in plays.size():
		print(
			(
				"AI-DET flow_full_ticks=%d match=normal-hard seed=%d ticks=%d impl=%s"
				% [plays[at]["counter"].flow_full_ticks, SEED, TICKS, labels[at]]
			)
		)


func test_the_library_ran_the_first_two_matches_when_it_is_built() -> void:
	var native: bool = Smoke.impl_name() == Smoke.IMPL_NATIVE
	assert_bool(Impls.is_native(_first["world"], SimProbe.Phase.FLOW)).is_equal(native)
	assert_bool(Impls.is_native(_again["world"], SimProbe.Phase.FLOW)).is_equal(native)
	assert_bool(Impls.is_native(_twin["world"], SimProbe.Phase.FLOW)).is_false()


func test_the_same_seed_twice_gives_the_same_commands_and_hashes_every_15_ticks() -> void:
	var a: Replay = _first["loop"].replay
	var b: Replay = _again["loop"].replay
	assert_int(a.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	assert_array(b.checkpoint_ticks).is_equal(a.checkpoint_ticks)
	(
		assert_array(b.checkpoint_hashes)
		. override_failure_message(HashReport.mismatch(_first["world"], _again["world"]))
		. is_equal(a.checkpoint_hashes)
	)
	assert_array(b.commands).is_equal(a.commands)
	assert_dict(_record(_again)).is_equal(_record(_first))
	assert_int(b.final_hash).is_equal(a.final_hash)


func test_the_match_is_not_vacuous_both_players_acted_and_every_checkpoint_differs() -> void:
	var replay: Replay = _first["loop"].replay
	var by_player: Dictionary[int, int] = {}
	for command: Command in _commands(replay):
		by_player[command.player_id] = by_player.get(command.player_id, 0) + 1
	assert_int(by_player.get(1, 0)).is_greater(5)
	assert_int(by_player.get(2, 0)).is_greater(5)
	var distinct: Dictionary[int, bool] = {}
	for hash_value: int in replay.checkpoint_hashes:
		distinct[hash_value] = true
	assert_int(distinct.size()).is_equal(replay.checkpoint_hashes.size())
	for played: Dictionary in [_first, _again, _twin]:
		assert_int(played["world"].dropped_commands).is_equal(0)
		assert_int(played["world"].tick).is_equal(TICKS)
		assert_int(played["world"].match_end_tick).is_equal(0)


func test_the_log_replays_without_any_ai_to_the_same_checkpoints() -> void:
	var replay: Replay = _first["loop"].replay
	var world: World = Smoke.world_of(SEED, Smoke.scenario_path(Smoke.KIND_CROSS, SEED))
	assert_array(Smoke.attach_impl(world)).is_empty()
	assert_int(Replay.play(replay, world, TICKS)).is_equal(Replay.PLAY_MATCHED)
	assert_int(world.tick).is_equal(TICKS)
	assert_int(world.state_hash()).is_equal(replay.final_hash)
	assert_int(world.dropped_commands).is_equal(0)


func test_the_gdscript_twin_plays_the_match_to_the_same_hashes() -> void:
	var a: Replay = _first["loop"].replay
	var b: Replay = _twin["loop"].replay
	(
		assert_array(b.checkpoint_hashes)
		. override_failure_message(HashReport.mismatch(_first["world"], _twin["world"]))
		. is_equal(a.checkpoint_hashes)
	)
	assert_array(b.commands).is_equal(a.commands)
	assert_int(b.final_hash).is_equal(a.final_hash)
	assert_dict(_record(_twin)).is_equal(_record(_first))
	# The controllers made the same decisions, not only the sim the same steps.
	assert_int(_twin["counter"].flow_full_ticks).is_equal(_first["counter"].flow_full_ticks)


func test_an_opponent_on_player_one_fires_the_deep_bore_within_900_ticks_and_it_replays() -> void:
	var scenario: ScenarioDef = load(STRIKE_PATH) as ScenarioDef
	var world: World = Smoke.world_of(SEED, STRIKE_PATH)
	assert_array(Smoke.attach_impl(world)).is_empty()
	var loop: MatchLoop = Smoke.loop_of(world, SEED, STRIKE_PATH)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(world)
	var stream: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + 1)
	var level: AiDifficultyDef = Rig.level_of("normal")
	var ai: AiController = AiFactory.create(Rig.def_of("fossil"), level, 1, stream)
	var controllers: Array[AiController] = [ai]
	var bore: int = _first_row(world, &"fossil_strike")
	var bore_id: int = world.unit_id[bore]
	var charged_at: int = world.ready_tick[bore]
	assert_int(world.owner[bore]).is_equal(1)
	assert_int(charged_at).is_less_equal(world.tick + 1)
	Smoke.run(world, loop, controllers, STRIKE_TICKS, counter)
	loop.replay.finish(world)
	print(
		(
			"AI-DET flow_full_ticks=%d match=dev_strikes seed=%d ticks=%d impl=AUTO"
			% [counter.flow_full_ticks, SEED, STRIKE_TICKS]
		)
	)
	assert_int(world.tick).is_equal(STRIKE_TICKS)
	assert_int(world.dropped_commands).is_equal(0)
	var shots: Array[Command] = []
	for command: Command in _commands(loop.replay):
		if command.type == Command.Type.SUPERWEAPON:
			shots.append(command)
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].player_id).is_equal(1)
	assert_int(shots[0].target_id).is_equal(bore_id)
	assert_int(shots[0].tick).is_less(STRIKE_TICKS)
	# The sim took it: the Deep Bore charges again from the tick it fired.
	assert_int(world.ready_tick[world.index_of(bore_id)]).is_greater(shots[0].tick)
	assert_int(world.ready_tick[world.index_of(bore_id)]).is_not_equal(charged_at)
	var replayed: World = Smoke.world_of(SEED, STRIKE_PATH)
	assert_array(Smoke.attach_impl(replayed)).is_empty()
	assert_int(Replay.play(loop.replay, replayed, STRIKE_TICKS)).is_equal(Replay.PLAY_MATCHED)
	assert_int(replayed.state_hash()).is_equal(loop.replay.final_hash)
	assert_int(scenario.player_count).is_equal(2)


## Plays the match of `impl` ("" for AUTO) on the cross scenario of `SEED` for `TICKS` ticks and
## returns what the cases read: the world, the loop (its replay finished), the counter and the
## controllers and seats of the record.
func _play(impl: String) -> Dictionary:
	var played: Dictionary = Smoke.start(SEED, Smoke.KIND_CROSS, LEVELS)
	if not impl.is_empty():
		assert_array(Smoke.attach_impl(played["world"], impl)).is_empty()
	var controllers: Array[AiController] = played["controllers"]
	Smoke.run(played["world"], played["loop"], controllers, TICKS, played["counter"])
	played["loop"].replay.finish(played["world"])
	return played


func _record(played: Dictionary) -> Dictionary:
	var seats: Array[Dictionary] = played["seats"]
	var controllers: Array[AiController] = played["controllers"]
	return Smoke.record_of(
		played["world"], SEED, played["path"], seats, controllers, played["counter"]
	)


## The Commands of `replay`, in the order they were recorded.
func _commands(replay: Replay) -> Array[Command]:
	var found: Array[Command] = []
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		assert_int(at).is_greater(0)
		found.append(command)
	return found


func _first_row(world: World, id: StringName) -> int:
	var type: int = world.type_ids.find(id)
	for row: int in world.unit_count():
		if world.type_index[row] == type:
			return row
	return -1
