extends GdUnitTestSuite
## MatchSetup (plan P513, ADR 0042): the dictionary round trip, the refusal of malformed input, and
## `apply` giving the runner the state the old `DevRoutes.open_main_with` field writes gave it. The
## bonus reaches the human seat through the runner (plan P512).

const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = SEED
	setup.local_seat = 1
	setup.local_side = 0
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	setup.first_opponent = 2
	setup.bonus_starting_credits = 500
	setup.map_id = &"kestrel_flats"
	setup.lesson_id = &"lesson_1"
	return setup


func _runner() -> MatchRunner:
	return auto_free(MatchRunner.new())


func test_round_trip_keeps_every_field() -> void:
	var back: MatchSetup = MatchSetup.from_dict(_setup().to_dict())
	assert_object(back).is_not_null()
	assert_str(back.scenario_path).is_equal(SCENARIO)
	assert_int(back.match_seed).is_equal(SEED)
	assert_int(back.local_seat).is_equal(1)
	assert_int(back.local_side).is_equal(0)
	assert_str(back.opponents[0].resource_path).is_equal(DevRoutes.OPPONENT_RENEW)
	assert_str(back.opponent_levels[0].resource_path).is_equal(DevRoutes.LEVEL_HARD)
	assert_int(back.first_opponent).is_equal(2)
	assert_int(back.bonus_starting_credits).is_equal(500)
	assert_str(String(back.map_id)).is_equal("kestrel_flats")
	assert_str(String(back.lesson_id)).is_equal("lesson_1")
	assert_dict(back.to_dict()).is_equal(_setup().to_dict())


func test_whole_floats_are_accepted_as_ints() -> void:
	var data: Dictionary = _setup().to_dict()
	data[MatchSetup.KEY_SEED] = float(SEED)
	data[MatchSetup.KEY_BONUS] = 500.0
	var back: MatchSetup = MatchSetup.from_dict(data)
	assert_object(back).is_not_null()
	assert_int(back.match_seed).is_equal(SEED)
	assert_int(back.bonus_starting_credits).is_equal(500)


func test_malformed_dictionaries_are_refused() -> void:
	assert_object(MatchSetup.from_dict(null)).is_null()
	assert_object(MatchSetup.from_dict([1, 2])).is_null()
	assert_object(MatchSetup.from_dict({})).is_null()
	var bad: Dictionary = {
		MatchSetup.KEY_VERSION: MatchSetup.VERSION + 1,
		MatchSetup.KEY_SEED: -1,
		MatchSetup.KEY_BONUS: -5,
		MatchSetup.KEY_FIRST: 99,
		MatchSetup.KEY_SCENARIO: "res://data/scenarios/missing.tres",
		MatchSetup.KEY_OPPONENTS: ["res://data/ai/missing.tres"],
		MatchSetup.KEY_LEVELS: [DevRoutes.OPPONENT_FOSSIL],
		MatchSetup.KEY_SEAT: 1.5,
		MatchSetup.KEY_SIDE: -1,
		MatchSetup.KEY_MAP: 7,
		MatchSetup.KEY_LESSON: null,
	}
	for key: String in bad:
		var data: Dictionary = _setup().to_dict()
		data[key] = bad[key]
		assert_object(MatchSetup.from_dict(data)).is_null()
	var missing: Dictionary = _setup().to_dict()
	missing.erase(MatchSetup.KEY_LEVELS)
	assert_object(MatchSetup.from_dict(missing)).is_null()


func test_apply_equals_the_old_field_writes() -> void:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.opponents = [load(DevRoutes.DUMMY_RENEW) as AiDef]
	var old: MatchRunner = _runner()
	old.scenario = load(SCENARIO)
	old.opponents = setup.opponents
	old.opponent_levels = setup.opponent_levels
	old.first_opponent = MatchRunner.FIRST_OPPONENT
	var fresh: MatchRunner = _runner()
	assert_int(setup.apply(fresh)).is_equal(OK)
	assert_str(fresh.scenario.resource_path).is_equal(old.scenario.resource_path)
	assert_int(fresh.match_seed).is_equal(old.match_seed)
	assert_array(fresh.opponents).is_equal(old.opponents)
	assert_array(fresh.opponent_levels).is_equal(old.opponent_levels)
	assert_int(fresh.first_opponent).is_equal(old.first_opponent)
	old.start()
	fresh.start()
	old.run_ticks(30)
	fresh.run_ticks(30)
	assert_int(fresh.world.tick).is_equal(30)
	assert_int(fresh.last_hash).is_equal(old.last_hash)
	assert_int(fresh.last_hash).is_not_equal(0)


func test_apply_writes_the_seed_and_refuses_a_missing_scenario() -> void:
	var runner: MatchRunner = _runner()
	assert_int(_setup().apply(runner)).is_equal(OK)
	assert_int(runner.match_seed).is_equal(SEED)
	assert_int(runner.first_opponent).is_equal(2)
	var missing: MatchSetup = MatchSetup.new()
	missing.scenario_path = "res://data/scenarios/missing.tres"
	var untouched: MatchRunner = _runner()
	assert_int(missing.apply(untouched)).is_equal(ERR_FILE_NOT_FOUND)
	assert_object(untouched.scenario).is_null()


func test_the_bonus_reaches_the_human_seat_and_moves_the_hash() -> void:
	var plain: MatchSetup = _setup()
	plain.bonus_starting_credits = 0
	var rich: MatchSetup = _setup()
	rich.lesson_id = &""
	var a: MatchRunner = _runner()
	var b: MatchRunner = _runner()
	plain.apply(a)
	rich.apply(b)
	assert_array([b.bonus_credits, b.bonus_seat]).is_equal([500, 1])
	a.start()
	b.start()
	assert_int(b.world.credits[1]).is_equal(a.world.credits[1] + 500)
	assert_int(b.world.credits[2]).is_equal(a.world.credits[2])
	assert_array(b.replay.bonus_credits).is_equal([0, 500, 0])
	a.run_ticks(30)
	b.run_ticks(30)
	assert_int(b.world.tick).is_equal(30)
	assert_int(b.last_hash).is_not_equal(a.last_hash)
	assert_int(MatchSetup.from_dict(rich.to_dict()).bonus_starting_credits).is_equal(500)


func test_a_lesson_takes_no_bonus() -> void:
	var setup: MatchSetup = _setup()
	setup.lesson_id = &"lesson_1"
	var runner: MatchRunner = _runner()
	assert_int(setup.apply(runner)).is_equal(OK)
	assert_int(runner.bonus_credits).is_equal(0)
	assert_int(setup.bonus_starting_credits).is_equal(500)


func test_an_ai_seat_takes_no_bonus() -> void:
	var setup: MatchSetup = _setup()
	setup.lesson_id = &""
	setup.local_seat = 1
	setup.first_opponent = 1  # AI-vs-AI: the computer plays seat 1.
	var runner: MatchRunner = _runner()
	assert_int(setup.apply(runner)).is_equal(OK)
	assert_int(runner.bonus_credits).is_equal(0)
	var human: MatchRunner = _runner()
	var plain: MatchSetup = _setup()
	plain.lesson_id = &""
	assert_int(plain.apply(human)).is_equal(OK)
	assert_int(human.bonus_credits).is_equal(500)


func test_null_entries_round_trip() -> void:
	var fossil: AiDef = load(DevRoutes.OPPONENT_FOSSIL) as AiDef
	var level: AiDifficultyDef = load(DevRoutes.LEVEL_EASY) as AiDifficultyDef
	var setup: MatchSetup = _setup()
	setup.opponents = [null, fossil]
	setup.opponent_levels = [null, level]
	var back: MatchSetup = MatchSetup.from_dict(setup.to_dict())
	assert_object(back).is_not_null()
	assert_object(back.opponents[0]).is_null()
	assert_object(back.opponents[1]).is_same(fossil)
	assert_object(back.opponent_levels[0]).is_null()
	assert_object(back.opponent_levels[1]).is_same(level)
	setup.opponents = [null]
	setup.opponent_levels = []
	back = MatchSetup.from_dict(setup.to_dict())
	assert_int(back.opponents.size()).is_equal(1)
	assert_object(back.opponents[0]).is_null()
	var data: Dictionary = setup.to_dict()
	data[MatchSetup.KEY_OPPONENTS] = [null]
	assert_object(MatchSetup.from_dict(data)).is_not_null()


func test_only_res_paths_of_the_right_type_load() -> void:
	var keys: Array[String] = [
		MatchSetup.KEY_SCENARIO, MatchSetup.KEY_OPPONENTS, MatchSetup.KEY_LEVELS
	]
	var user_path: String = "user://resume_probe.tres"
	for key: String in keys:
		var data: Dictionary = _setup().to_dict()
		data[key] = user_path if key == MatchSetup.KEY_SCENARIO else [user_path]
		assert_object(MatchSetup.from_dict(data)).is_null()
	var wrong: Dictionary = _setup().to_dict()
	wrong[MatchSetup.KEY_OPPONENTS] = [SCENARIO]
	assert_object(MatchSetup.from_dict(wrong)).is_null()
	var absolute: Dictionary = _setup().to_dict()
	absolute[MatchSetup.KEY_SCENARIO] = ProjectSettings.globalize_path(SCENARIO)
	assert_object(MatchSetup.from_dict(absolute)).is_null()


func test_more_levels_than_opponents_are_refused() -> void:
	var data: Dictionary = _setup().to_dict()
	data[MatchSetup.KEY_LEVELS] = [DevRoutes.LEVEL_EASY, DevRoutes.LEVEL_HARD]
	assert_object(MatchSetup.from_dict(data)).is_null()


func test_the_scenario_cache_follows_the_path() -> void:
	var setup: MatchSetup = _setup()
	var first: ScenarioDef = setup.scenario()
	assert_object(first).is_not_null()
	setup.scenario_path = DevRoutes.SKIRMISH_LUMEN
	assert_str(setup.scenario().resource_path).is_equal(DevRoutes.SKIRMISH_LUMEN)
	setup.scenario_path = "res://data/scenarios/missing.tres"
	assert_object(setup.scenario()).is_null()


func test_apply_refuses_another_seat_or_side_and_copies_the_arrays() -> void:
	var setup: MatchSetup = _setup()
	var scenario: ScenarioDef = setup.scenario()
	setup.local_seat = scenario.local_player + 1
	var refused: MatchRunner = _runner()
	assert_int(setup.apply(refused)).is_equal(ERR_UNAVAILABLE)
	assert_object(refused.scenario).is_null()
	setup.local_seat = scenario.local_player
	setup.local_side = 1
	assert_int(setup.apply(refused)).is_equal(ERR_UNAVAILABLE)
	setup.local_side = 0
	var runner: MatchRunner = _runner()
	assert_int(setup.apply(runner)).is_equal(OK)
	assert_bool(runner.opponents == setup.opponents).is_true()
	runner.opponents.clear()
	assert_int(setup.opponents.size()).is_equal(1)
