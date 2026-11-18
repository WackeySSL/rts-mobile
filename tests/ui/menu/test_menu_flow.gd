extends GdUnitTestSuite
## MenuFlow (plan P523, ADR 0043 section 6): the start, the match end and the way out, with a fake
## AdService that counts the three Phase 6 match methods. The scene changes are replaced, so the
## main scene is added to the suite and the "menu" is a counter.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"
const LIFE_PATH: String = "res://data/life_settings.tres"
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
var _was_auto_close: bool = false


func before_test() -> void:
	MenuRig.begin()
	_was_auto_close = AdService.fake_auto_close
	_menus = 0
	_mains.clear()
	_ads = auto_free(FakeAds.new())
	add_child(_ads)
	var script: GDScript = load("res://game/ui/menu/menu_flow_service.gd")
	_flow = auto_free(script.new())
	add_child(_flow)
	_flow.ads = _ads
	_flow.seed_source = func() -> int: return FRESH_SEED
	_flow.switch_to_main = _enter_main
	_flow.switch_to_menu = _enter_menu


func after_test() -> void:
	_flow.return_to_menu()
	for main: Node in _mains:
		if is_instance_valid(main):
			remove_child(main)
			main.free()
	# The real AdService is a shared autoload: its auto-close switch is restored. Its in-memory
	# ledger has no reset seam; the one test that uses it records a match in the suite's own save
	# file (MenuRig's PrefsRig), which is discarded with it.
	AdService.fake_auto_close = _was_auto_close
	MenuRig.end()


func _enter_main(main: Node) -> Error:
	_mains.append(main)
	add_child(main)
	return OK


func _enter_menu() -> Error:
	_menus += 1
	return OK


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


func _frames(count: int = 4) -> void:
	for _i: int in count:
		await await_idle_frame()


func test_start_seeds_takes_the_bonus_once_and_emits_before_the_scene() -> void:
	_ads.pending_bonus = BONUS
	var order: Array[String] = []
	_flow.match_loading.connect(func(_s: MatchSetup) -> void: order.append("loading"))
	_flow.switch_to_main = func(main: Node) -> Error:
		order.append("scene")
		return _enter_main(main)
	var setup: MatchSetup = _setup()
	assert_int(await _flow.start_match(setup)).is_equal(OK)
	assert_array(order).is_equal(["loading", "scene"])
	assert_int(setup.match_seed).is_equal(FRESH_SEED)
	assert_int(setup.bonus_starting_credits).is_equal(BONUS)
	assert_object(_flow.current_setup()).is_same(setup)
	assert_int(_flow.current_runner().match_seed).is_equal(FRESH_SEED)
	assert_int(_ads.bonus_calls).is_equal(1)


func test_a_match_start_puts_the_saved_reduced_switch_on_life_settings() -> void:
	var life: LifeSettings = load(LIFE_PATH) as LifeSettings
	var life_before: bool = life.reduced
	MenuPrefs.set_reduced_effects(true)
	assert_int(await _flow.start_match(_setup())).is_equal(OK)
	assert_bool(life.reduced).is_true()
	MenuPrefs.set_reduced_effects(false)  # A change while the match runs waits for the next one.
	assert_bool(life.reduced).is_true()
	assert_int(await _flow.restart()).is_equal(OK)
	assert_bool(life.reduced).is_false()
	life.reduced = life_before


func test_the_saved_switch_reaches_intro_and_stack_nodes_and_life_settings() -> void:
	var life: LifeSettings = load(LIFE_PATH) as LifeSettings
	var life_before: bool = life.reduced
	MenuPrefs.set_reduced_effects(true)
	_flow.apply_reduced()
	assert_bool(life.reduced).is_true()
	# Not in the tree: an IntroPlayer would run the whole intro there.
	var intro: IntroPlayer = auto_free(IntroPlayer.new())
	var stack: MenuStack = auto_free(MenuStack.new())
	_flow.apply_reduced_to(intro)
	_flow.apply_reduced_to(stack)
	assert_bool(intro.reduced).is_true()
	assert_bool(stack.reduced).is_true()
	var entered: MenuStack = auto_free(MenuStack.new())
	add_child(entered)  # The boot path: node_added reaches apply_reduced_to.
	assert_bool(entered.reduced).is_true()
	MenuPrefs.set_reduced_effects(false)
	_flow.apply_reduced()
	assert_bool(life.reduced).is_false()
	var later: IntroPlayer = auto_free(IntroPlayer.new())
	var kept: MenuStack = auto_free(MenuStack.new())
	kept.reduced = true  # A node that switched itself on stays on.
	_flow.apply_reduced_to(later)
	_flow.apply_reduced_to(kept)
	assert_bool(later.reduced).is_false()
	assert_bool(kept.reduced).is_true()
	life.reduced = life_before


func test_the_scene_is_built_a_frame_after_match_loading() -> void:
	var frame: Signal = get_tree().process_frame
	_flow.loading_frame = func() -> Signal: return frame
	var loading: Array[int] = []
	_flow.match_loading.connect(func(_s: MatchSetup) -> void: loading.append(_mains.size()))
	_flow.start_match(_setup())
	assert_array(_mains).is_empty()
	await _frames(2)
	assert_array(loading).is_equal([0])
	assert_int(_mains.size()).is_equal(1)


func test_a_missing_scenario_changes_nothing() -> void:
	var setup: MatchSetup = _setup()
	setup.scenario_path = "res://data/scenarios/missing.tres"
	assert_int(await _flow.start_match(setup)).is_equal(ERR_FILE_NOT_FOUND)
	assert_int(_ads.bonus_calls).is_equal(0)
	assert_array(_mains).is_empty()
	assert_object(_flow.current_runner()).is_null()


func test_an_ended_match_is_scored_once_and_reaches_the_menu() -> void:
	await _flow.start_match(_setup())
	var scored: Array[Array] = []
	_flow.match_scored.connect(
		func(summary: MatchSummary, award: XpAward) -> void: scored.append([summary, award])
	)
	_flow.mark_surrendered()
	_surrender_local()
	_flow.current_runner().run_ticks(1)
	assert_int(scored.size()).is_equal(1)
	var summary: MatchSummary = _flow.last_summary()
	assert_object(summary).is_same(scored[0][0])
	assert_object(_flow.last_award()).is_same(scored[0][1])
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
	assert_object(_flow.current_setup()).is_null()


func test_a_defeat_without_surrender_is_a_loss() -> void:
	await _flow.start_match(_setup())
	_surrender_local()
	assert_str(_flow.last_summary().outcome).is_equal(MatchSummary.OUTCOME_LOSS)


func test_leave_match_twice_counts_and_switches_once() -> void:
	await _flow.start_match(_setup())
	_surrender_local()
	_flow.leave_match()
	await _flow.leave_match()
	await _frames()
	assert_int(_ads.completed_calls).is_equal(1)
	assert_int(_ads.interstitial_calls).is_equal(1)
	assert_int(_menus).is_equal(1)


func test_a_new_match_during_the_interstitial_is_refused() -> void:
	await _flow.start_match(_setup())
	_surrender_local()
	_flow.leave_match()
	assert_int(await _flow.start_match(_setup())).is_equal(ERR_BUSY)
	assert_int(await _flow.restart()).is_equal(ERR_BUSY)
	assert_int(await _flow.continue_match()).is_equal(ERR_BUSY)
	await _frames()
	assert_int(_mains.size()).is_equal(1)
	assert_int(_menus).is_equal(1)
	assert_int(_ads.bonus_calls).is_equal(1)


func test_restart_after_an_end_counts_it_awaits_the_ad_and_zeroes_the_bonus() -> void:
	_ads.pending_bonus = BONUS
	await _flow.start_match(_setup())
	_flow.mark_surrendered()  # A surrender plus a restart still counts the match once.
	_surrender_local()
	_flow.current_runner().run_ticks(1)
	var ticks: int = _flow.last_summary().ticks
	assert_int(await _flow.restart()).is_equal(OK)
	assert_int(_ads.completed_calls).is_equal(1)
	assert_int(_ads.last_seconds).is_equal(ticks / Sim.TICK_RATE)
	assert_int(_ads.interstitial_calls).is_equal(1)
	assert_str(_ads.last_placement).is_equal("post_match")  # AdCaps allows only this name.
	assert_int(_ads.bonus_calls).is_equal(1)
	assert_int(_mains.size()).is_equal(2)
	assert_int(_flow.current_setup().bonus_starting_credits).is_equal(0)
	assert_int(_flow.current_setup().match_seed).is_equal(FRESH_SEED)
	# The new match, left before its end, counts nothing more.
	await _flow.leave_match()
	assert_int(_ads.completed_calls).is_equal(1)
	assert_int(_menus).is_equal(1)


func test_restart_mid_match_counts_nothing_and_keeps_the_bonus() -> void:
	_ads.pending_bonus = BONUS
	await _flow.start_match(_setup())
	assert_int(await _flow.restart()).is_equal(OK)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	assert_int(_ads.bonus_calls).is_equal(1)
	assert_int(_flow.current_setup().bonus_starting_credits).is_equal(BONUS)
	assert_int(_mains.size()).is_equal(2)


func test_a_lesson_calls_none_of_the_three_match_methods() -> void:
	_ads.pending_bonus = BONUS
	var setup: MatchSetup = _setup(&"lesson_one")
	await _flow.start_match(setup)
	assert_int(setup.match_seed).is_equal(FIXED_SEED)
	assert_int(setup.bonus_starting_credits).is_equal(0)
	_surrender_local()
	assert_int(await _flow.restart()).is_equal(OK)
	assert_int(_flow.current_setup().match_seed).is_equal(FIXED_SEED)
	_surrender_local()
	await _flow.leave_match()
	assert_int(_ads.bonus_calls).is_equal(0)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	assert_int(_ads.pending_bonus).is_equal(BONUS)
	assert_int(_menus).is_equal(1)


func test_an_abandoned_match_goes_straight_to_the_menu() -> void:
	await _flow.start_match(_setup())
	_flow.return_to_menu()
	assert_int(_menus).is_equal(1)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	# Leaving a match that never ended counts nothing either.
	await _flow.start_match(_setup())
	await _flow.leave_match()
	assert_int(_menus).is_equal(2)
	assert_int(_ads.completed_calls).is_equal(0)
	assert_int(_ads.interstitial_calls).is_equal(0)
	assert_object(_flow.last_award()).is_null()


func test_the_requested_screen_is_taken_once() -> void:
	assert_str(_flow.take_pending_screen()).is_equal("")
	await _flow.start_match(_setup())
	_flow.return_to_menu(&"lessons")
	assert_str(_flow.take_pending_screen()).is_equal("lessons")
	assert_str(_flow.take_pending_screen()).is_equal("")
	await _flow.start_match(_setup())
	await _flow.leave_match(&"skirmish")
	assert_str(_flow.take_pending_screen()).is_equal("skirmish")


func test_continue_match_is_a_stub_until_the_restorer() -> void:
	assert_int(await _flow.continue_match()).is_equal(ERR_UNAVAILABLE)


func test_the_real_ad_service_with_auto_close_reaches_the_menu() -> void:
	AdService.fake_auto_close = true
	_flow.ads = AdService
	await _flow.start_match(_setup())
	_surrender_local()
	await _flow.leave_match()
	assert_int(_menus).is_equal(1)


func test_the_menu_scene_is_the_one_the_intro_hands_over_to() -> void:
	var settings: IntroSettings = load("res://data/intro_settings.tres") as IntroSettings
	assert_str(MenuFlow.MENU_SCENE).is_equal(settings.menu_path)
	assert_str(settings.menu_path).is_equal("res://scenes/menu/main_menu.tscn")
