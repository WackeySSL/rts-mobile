extends GdUnitTestSuite
## MenuFlow (plan P523, ADR 0043 section 6): the start, the match end and the way out, with a fake
## AdService that counts the three Phase 6 match methods. The scene changes are replaced, so the
## main scene is added to the suite and the "menu" is a counter.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"
const BONUS: int = 500
const FIXED_SEED: int = 4242
const FRESH_SEED: int = 777


class FakeAds:
	extends Node
	var bonus_calls: int = 0
	var completed_calls: int = 0
	var interstitial_calls: int = 0
	var pending_bonus: int = 0
	var last_seconds: int = -1
	var last_placement: StringName = &""

	func take_start_credits_bonus() -> int:
		bonus_calls += 1
		var taken: int = pending_bonus
		pending_bonus = 0
		return taken

	func note_match_completed(play_seconds: int) -> void:
		completed_calls += 1
		last_seconds = play_seconds

	func maybe_show_interstitial(placement: StringName) -> bool:
		interstitial_calls += 1
		last_placement = placement
		await get_tree().process_frame
		return true


var _flow: Node
var _ads: FakeAds
var _menus: int = 0
var _mains: Array[Node] = []


func before_test() -> void:
	MenuRig.begin()
	_menus = 0
	_mains.clear()
	_ads = auto_free(FakeAds.new())
	add_child(_ads)
	var script: GDScript = load("res://game/ui/menu/menu_flow_service.gd")
	_flow = auto_free(script.new())
	_flow.ads = _ads
	_flow.seed_source = func() -> int: return FRESH_SEED
	_flow.switch_to_main = _enter_main
	_flow.switch_to_menu = func() -> void: _menus += 1


func after_test() -> void:
	_flow.return_to_menu()
	for main: Node in _mains:
		if is_instance_valid(main):
			remove_child(main)
			main.free()
	MenuRig.end()


func _enter_main(main: Node) -> void:
	_mains.append(main)
	add_child(main)


func _setup(lesson: StringName = &"") -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	setup.lesson_id = lesson
	setup.match_seed = FIXED_SEED
	return setup


## Ends the match as the local player's defeat: the player surrenders and a tick plays.
func _surrender_local() -> void:
	var runner: MatchRunner = _flow.current_runner()
	CommandQueue.submit(Command.surrender(_flow.current_setup().scenario().local_player))
	runner.run_ticks(1)


func test_start_seeds_takes_the_bonus_once_and_emits_before_the_scene() -> void:
	_ads.pending_bonus = BONUS
	var order: Array[String] = []
	_flow.match_loading.connect(func(_s: MatchSetup) -> void: order.append("loading"))
	_flow.switch_to_main = func(main: Node) -> void:
		order.append("scene")
		_enter_main(main)
	var setup: MatchSetup = _setup()
	assert_int(_flow.start_match(setup)).is_equal(OK)
	assert_array(order).is_equal(["loading", "scene"])
	assert_int(setup.match_seed).is_equal(FRESH_SEED)
	assert_int(setup.bonus_starting_credits).is_equal(BONUS)
	assert_object(_flow.current_setup()).is_same(setup)
	assert_int(_flow.current_runner().match_seed).is_equal(FRESH_SEED)
	assert_int(_ads.bonus_calls).is_equal(1)
	# A restart does not take (or carry) the bonus a second time.
	assert_int(_flow.restart()).is_equal(OK)
	assert_int(_ads.bonus_calls).is_equal(1)
	assert_int(_flow.current_setup().bonus_starting_credits).is_equal(0)


func test_a_missing_scenario_changes_nothing() -> void:
	var setup: MatchSetup = _setup()
	setup.scenario_path = "res://data/scenarios/missing.tres"
	assert_int(_flow.start_match(setup)).is_equal(ERR_FILE_NOT_FOUND)
	assert_int(_ads.bonus_calls).is_equal(0)
	assert_array(_mains).is_empty()
	assert_object(_flow.current_runner()).is_null()


func test_an_ended_match_is_scored_counted_and_reaches_the_menu() -> void:
	_flow.start_match(_setup())
	_flow.mark_surrendered()
	_surrender_local()
	var summary: MatchSummary = _flow.last_summary()
	assert_object(summary).is_not_null()
	assert_str(summary.outcome).is_equal(MatchSummary.OUTCOME_SURRENDER)
	assert_str(summary.level).is_equal("hard")
	var ticks: int = summary.ticks
	await _flow.leave_match()
	assert_int(_ads.completed_calls).is_equal(1)
	assert_int(_ads.last_seconds).is_equal(ticks / Sim.TICK_RATE)
	assert_int(_ads.interstitial_calls).is_equal(1)
	assert_str(_ads.last_placement).is_equal("post_match")
	assert_int(_menus).is_equal(1)
	assert_object(_flow.current_runner()).is_null()


func test_a_defeat_without_surrender_is_a_loss() -> void:
	_flow.start_match(_setup())
	_surrender_local()
	assert_str(_flow.last_summary().outcome).is_equal(MatchSummary.OUTCOME_LOSS)


func test_an_abandoned_match_goes_straight_to_the_menu() -> void:
	_flow.start_match(_setup())
	_flow.return_to_menu()
	assert_int(_menus).is_equal(1)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	# Leaving a match that never ended counts nothing either.
	_flow.start_match(_setup())
	await _flow.leave_match()
	assert_int(_menus).is_equal(2)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	assert_object(_flow.last_award()).is_null()


func test_a_lesson_calls_none_of_the_three_match_methods() -> void:
	_ads.pending_bonus = BONUS
	var setup: MatchSetup = _setup(&"lesson_one")
	_flow.start_match(setup)
	assert_int(setup.match_seed).is_equal(FIXED_SEED)
	assert_int(setup.bonus_starting_credits).is_equal(0)
	_surrender_local()
	await _flow.leave_match()
	assert_int(_ads.bonus_calls).is_equal(0)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	assert_int(_ads.pending_bonus).is_equal(BONUS)
	assert_int(_menus).is_equal(1)


func test_continue_match_is_a_stub_until_the_restorer() -> void:
	assert_int(_flow.continue_match()).is_equal(ERR_UNAVAILABLE)


func test_the_real_ad_service_with_auto_close_reaches_the_menu() -> void:
	AdService.fake_auto_close = true
	_flow.ads = AdService
	_flow.start_match(_setup())
	_surrender_local()
	await _flow.leave_match()
	assert_int(_menus).is_equal(1)
