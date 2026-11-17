extends GdUnitTestSuite
## The starting-credits bonus as a setup value (plan P512, ADR 0042 section 6): `set_bonus_credits`
## adds it to a player's start credits clamped to `bonus_credits_max`, 0 changes nothing, and
## `Replay` FORMAT 3 records it so a replay of a bonus match reproduces its final hash.

const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")

const CAP: int = 500
const SEED: int = 7


## The perf arena's frozen rules (data/dev/arena/rules.tres) hold no cap, so the tests that use
## it set the shipped one on the world, as World.from_scenario would from data/rules.tres.
func _world() -> World:
	var world: World = MatchScript.world(SEED)
	world.bonus_credits_max = CAP
	return world


func test_the_shipped_cap_is_the_phase_6_grant() -> void:
	var rules: RulesDef = load("res://data/rules.tres") as RulesDef
	assert_int(rules.bonus_credits_max).is_equal(CAP)
	var world: World = _world()
	world.prepare()
	assert_array(world.bonus_credits).is_equal([0, 0, 0])


func test_the_bonus_adds_to_one_players_credits_only() -> void:
	var world: World = _world()
	world.prepare()
	var start: int = world.start_credits
	WorldLoad.set_bonus_credits(world, 1, 300)
	assert_array(world.credits).is_equal([0, start + 300, start])
	assert_array(world.bonus_credits).is_equal([0, 300, 0])


func test_a_bonus_above_the_cap_is_clamped_and_a_negative_one_is_zero() -> void:
	var world: World = _world()
	world.prepare()
	WorldLoad.set_bonus_credits(world, 1, CAP + 1)
	assert_int(world.bonus_credits[1]).is_equal(CAP)
	assert_int(world.credits[1]).is_equal(world.start_credits + CAP)
	WorldLoad.set_bonus_credits(world, 2, CAP)
	assert_int(world.bonus_credits[2]).is_equal(CAP)
	WorldLoad.set_bonus_credits(world, 2, -50)
	assert_array(world.bonus_credits).is_equal([0, CAP, 0])
	assert_int(world.credits[2]).is_equal(world.start_credits)


func test_setting_again_replaces_the_bonus_it_does_not_stack() -> void:
	var world: World = _world()
	world.prepare()
	WorldLoad.set_bonus_credits(world, 1, 400)
	WorldLoad.set_bonus_credits(world, 1, 100)
	assert_int(world.credits[1]).is_equal(world.start_credits + 100)


func test_before_prepare_the_bonus_is_stored_and_the_start_includes_it() -> void:
	var world: World = _world()
	WorldLoad.set_bonus_credits(world, 2, 250)
	world.prepare()
	assert_int(world.credits[2]).is_equal(world.start_credits + 250)
	assert_int(world.credits[1]).is_equal(world.start_credits)


func test_the_neutral_player_and_a_player_past_the_count_are_refused() -> void:
	var world: World = _world()
	world.prepare()
	var before: PackedInt32Array = world.credits.duplicate()
	var hash_before: int = world.defs_hash()
	WorldLoad.set_bonus_credits(world, 0, 100)
	WorldLoad.set_bonus_credits(world, 3, 100)
	WorldLoad.set_bonus_credits(world, -1, 100)
	assert_array(world.credits).is_equal(before)
	assert_array(world.bonus_credits).is_equal([0, 0, 0])
	assert_int(world.defs_hash()).is_equal(hash_before)


func test_a_world_with_no_rule_cap_grants_nothing() -> void:
	var world: World = _world()
	world.bonus_credits_max = 0
	world.prepare()
	WorldLoad.set_bonus_credits(world, 1, 100)
	assert_int(world.credits[1]).is_equal(world.start_credits)


func test_at_zero_the_state_hash_and_the_credits_are_what_they_were() -> void:
	var plain: World = _world()
	var zero: World = _world()
	WorldLoad.set_bonus_credits(zero, 1, 0)
	WorldLoad.set_bonus_credits(zero, 2, 0)
	assert_int(zero.state_hash()).is_equal(plain.state_hash())
	var a: MatchLoop = MatchScript.loop(plain, SEED)
	var b: MatchLoop = MatchScript.loop(zero, SEED)
	MatchScript.play(plain, a, 45)
	MatchScript.play(zero, b, 45)
	assert_int(zero.state_hash()).is_equal(plain.state_hash())
	assert_array(zero.credits).is_equal(plain.credits)


func test_a_bonus_moves_the_state_hash() -> void:
	var plain: World = _world()
	var rich: World = _world()
	WorldLoad.set_bonus_credits(rich, 1, 100)
	assert_int(rich.state_hash()).is_not_equal(plain.state_hash())


func test_the_loop_records_the_bonus_in_the_replay() -> void:
	var world: World = _world()
	WorldLoad.set_bonus_credits(world, 1, 500)
	var loop: MatchLoop = MatchScript.loop(world, SEED)
	assert_array(loop.replay.bonus_credits).is_equal([0, 500, 0])


func test_a_replay_of_a_bonus_match_reproduces_its_final_hash() -> void:
	var recorded: World = _world()
	WorldLoad.set_bonus_credits(recorded, 1, 500)
	var loop: MatchLoop = MatchScript.loop(recorded, SEED)
	MatchScript.play(recorded, loop, 90)
	loop.replay.finish(recorded)
	var replay: Replay = Replay.from_bytes(loop.replay.to_bytes())
	assert_object(replay).is_not_null()
	assert_array(replay.bonus_credits).is_equal([0, 500, 0])
	var fresh: World = _world()
	replay.apply_setup(fresh)
	assert_int(Replay.play(replay, fresh, 90)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)
	# Without the setup the world differs: the defs hash covers the bonus.
	var bare: World = _world()
	assert_int(Replay.play(replay, bare, 90)).is_equal(Replay.PLAY_DEFS_DIFFER)


func test_a_replay_bonus_above_the_cap_plays_clamped() -> void:
	var recorded: World = _world()
	WorldLoad.set_bonus_credits(recorded, 1, CAP)
	var loop: MatchLoop = MatchScript.loop(recorded, SEED)
	MatchScript.play(recorded, loop, 30)
	loop.replay.finish(recorded)
	var replay: Replay = loop.replay
	replay.bonus_credits[1] = CAP * 10
	var fresh: World = _world()
	replay.apply_setup(fresh)
	assert_int(fresh.bonus_credits[1]).is_equal(CAP)
	assert_int(Replay.play(replay, fresh, 30)).is_not_equal(Replay.PLAY_BAD_LOG)


func test_a_format_2_replay_is_refused() -> void:
	var data: Dictionary = bytes_to_var(Replay.begin("", 0, 0).to_bytes())
	assert_int(data["format"]).is_equal(3)
	assert_object(Replay.from_bytes(var_to_bytes(data))).is_not_null()
	data["format"] = 2
	data.erase("bonus_credits")
	assert_object(Replay.from_bytes(var_to_bytes(data))).is_null()
	data["bonus_credits"] = PackedInt32Array()
	assert_object(Replay.from_bytes(var_to_bytes(data))).is_null()
