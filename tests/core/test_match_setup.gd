extends GdUnitTestSuite
## MatchSetup (plan P513, ADR 0042): the dictionary round trip, the refusal of malformed input, and
## `apply` giving the runner the state the old `DevRoutes.open_main_with` field writes gave it. The
## bonus is carried and saved, and has no sim effect yet (plan P512).

const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = SEED
	setup.local_seat = 1
	setup.local_side = 2
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
	assert_int(back.local_side).is_equal(2)
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
		MatchSetup.KEY_FIRST: 0,
		MatchSetup.KEY_SCENARIO: "res://data/scenarios/missing.tres",
		MatchSetup.KEY_OPPONENTS: ["res://data/ai/missing.tres"],
		MatchSetup.KEY_LEVELS: [DevRoutes.OPPONENT_FOSSIL],
		MatchSetup.KEY_SEAT: 1.5,
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


func test_bonus_is_carried_with_no_sim_effect_yet() -> void:
	var plain: MatchSetup = _setup()
	plain.bonus_starting_credits = 0
	var rich: MatchSetup = _setup()
	var a: MatchRunner = _runner()
	var b: MatchRunner = _runner()
	plain.apply(a)
	rich.apply(b)
	a.start()
	b.start()
	a.run_ticks(30)
	b.run_ticks(30)
	assert_int(b.world.tick).is_equal(30)
	assert_int(b.last_hash).is_equal(a.last_hash)
	assert_int(MatchSetup.from_dict(rich.to_dict()).bonus_starting_credits).is_equal(500)
