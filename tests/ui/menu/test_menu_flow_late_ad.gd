extends GdUnitTestSuite
## P409: MenuFlow never builds a match while an interstitial is late-pending (it timed out, AdMob
## cannot recall it, and it may still open). It runs on a real AdService (fake backend, fake clock)
## whose post-match interstitial never opens; the scene changes are replaced by counters.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"
const KIND: StringName = AdBackend.KIND_INTERSTITIAL

var _flow: Node
var _ads: Node
var _fake: FakeAdBackend
var _h: AdServiceHarness
var _mains: Array[Node] = []
var _menus: int = 0
var _loading: int = 0


func before_test() -> void:
	MenuRig.begin()
	_mains.clear()
	_menus = 0
	_loading = 0
	_h = AdServiceHarness.new()
	_ads = auto_free(_h.make())
	_fake = AdServiceHarness.fake(_ads)
	AdServiceHarness.play_three_matches(_ads)
	var script: GDScript = load("res://game/ui/menu/menu_flow_service.gd")
	_flow = auto_free(script.new())
	add_child(_flow)
	_flow.ads = _ads
	_flow.switch_to_main = _enter_main
	_flow.switch_to_menu = _enter_menu
	_flow.match_loading.connect(func(_s: MatchSetup) -> void: _loading += 1)


func after_test() -> void:
	_flow.return_to_menu()
	for main: Node in _mains:
		if is_instance_valid(main):
			remove_child(main)
			main.free()
	_h.dispose()
	MenuRig.end()


func _enter_main(main: Node) -> Error:
	_mains.append(main)
	add_child(main)
	return OK


func _enter_menu() -> Error:
	_menus += 1
	return OK


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	return setup


func _frames(count: int = 4) -> void:
	await AdServiceHarness.frames(count)


## A started and ended skirmish whose post-match interstitial never opens and cannot be recalled.
func _ended_match() -> void:
	assert_int(await _flow.start_match(_setup())).is_equal(OK)
	_fake.show_never_opens = true
	_fake.ignore_cancel = true
	CommandQueue.submit(Command.surrender(_flow.current_setup().scenario().local_player))
	_flow.current_runner().run_ticks(1)
	_loading = 0


## Runs `leave` (restart or leave_match then start_match) until the show has timed out, and checks
## that no match was built before and after the 8 s deadline.
func _wait_out_the_timeout(call: Callable) -> Array:
	var out: Array = AdServiceHarness.start(call)
	await _frames(3)
	_assert_nothing_built("before the timeout")
	_h.clock_ms = _ads._settings.fullscreen_timeout_ms
	await _frames(4)
	_assert_nothing_built("after the timeout, ad still late")
	return out


func _assert_nothing_built(when: String) -> void:
	assert_int(_mains.size()).override_failure_message(when + ": main scene").is_equal(1)


func test_restart_builds_the_match_only_after_the_late_ad_closes() -> void:
	await _ended_match()
	var out: Array = await _wait_out_the_timeout(func() -> int: return await _flow.restart())
	assert_array(out).is_empty()
	_fake.open_late()  # Auto close: the pair completes.
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(2)
	assert_int(_loading).is_equal(1)


func test_restart_builds_the_match_after_a_late_show_failure() -> void:
	await _ended_match()
	var out: Array = await _wait_out_the_timeout(func() -> int: return await _flow.restart())
	_fake.show_failed.emit(KIND)
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(2)


func test_restart_builds_the_match_at_the_cap_when_the_backend_never_answers() -> void:
	await _ended_match()
	var out: Array = await _wait_out_the_timeout(func() -> int: return await _flow.restart())
	_h.clock_ms += _ads._settings.fullscreen_late_cap_ms - 1
	await _frames(3)
	_assert_nothing_built("just under the cap")
	_h.clock_ms += 1
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(2)
	# The dropped show holds up no later start: it builds in the same call.
	_loading = 0
	var again: Array = AdServiceHarness.start(
		func() -> int: return await _flow.start_match(_setup())
	)
	assert_int(_loading).override_failure_message("second start waited").is_equal(1)
	await _frames(3)
	assert_array(again).is_equal([OK])


func test_restart_waits_for_a_rewarded_run_that_is_still_active() -> void:
	await _ended_match()
	AdServiceHarness.start(
		func() -> bool: return await _ads.show_rewarded(&"double_xp", Callable())
	)
	await _frames(2)
	var out: Array = AdServiceHarness.start(func() -> int: return await _flow.restart())
	await _frames(4)
	assert_array(out).is_empty()
	_assert_nothing_built("rewarded run active")
	_fake.open_late(AdBackend.KIND_REWARDED)  # Auto close.
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(2)


func test_start_match_after_leave_match_waits_for_the_late_ad() -> void:
	await _ended_match()
	var left: Array = await _wait_out_the_timeout(
		func() -> bool:
			await _flow.leave_match()
			return true
	)
	# leave_match carries on to the menu after the timeout; the late ad is still pending.
	assert_array(left).is_equal([true])
	assert_int(_menus).is_equal(1)
	var out: Array = AdServiceHarness.start(func() -> int: return await _flow.start_match(_setup()))
	await _frames(4)
	_assert_nothing_built("start after leave")
	_fake.open_late()
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(2)


func test_with_nothing_pending_nothing_extra_is_awaited() -> void:
	var setup: MatchSetup = _setup()
	var out: Array = AdServiceHarness.start(func() -> int: return await _flow.start_match(setup))
	assert_int(_loading).override_failure_message("emitted in the same frame").is_equal(1)
	await _frames(3)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(1)


func test_a_late_credits_ad_that_pays_during_the_settle_counts_for_this_match() -> void:
	await _frames(3)  # Let the rewarded ad load.
	_fake.show_never_opens = true
	_fake.ignore_cancel = true
	var credits: int = _ads._settings.reward_start_credits
	var shown: Array = AdServiceHarness.start(
		func() -> bool:
			return await _ads.show_rewarded(
				&"start_credits", _ads.grant_start_credits_bonus.bind(credits)
			)
	)
	await _frames(3)
	_h.clock_ms = _ads._settings.fullscreen_timeout_ms  # The show times out and stays pending.
	await _frames(4)
	assert_array(shown).is_not_empty()
	assert_int(_ads.pending_start_credits()).is_equal(0)  # Not paid yet.
	var out: Array = AdServiceHarness.start(func() -> int: return await _flow.start_match(_setup()))
	await _frames(4)
	assert_array(out).is_empty()
	assert_int(_mains.size()).override_failure_message("no main while the ad is late").is_equal(0)
	assert_int(_loading).is_equal(1)  # P450: the card shows while the settle waits.
	_fake.open_late(AdBackend.KIND_REWARDED)  # It opens and pays during the settle.
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_flow.current_setup().bonus_starting_credits).is_equal(credits)
	assert_int(_ads.pending_start_credits()).is_equal(0)


func test_a_never_settling_ad_still_starts_the_match_within_the_bound() -> void:
	# P450: a run that never answers (the web preview's hang) holds the start only up to the bound.
	_ads._settings = _ads._settings.duplicate()
	_ads._settings.start_settle_bound_ms = 50
	_ads._settings.fullscreen_late_cap_ms = 600000
	await _frames(3)
	_fake.show_never_opens = true
	_fake.ignore_cancel = true
	AdServiceHarness.start(
		func() -> bool: return await _ads.show_rewarded(&"double_xp", Callable())
	)
	await _frames(3)
	_h.clock_ms = _ads._settings.fullscreen_timeout_ms  # Timed out, still late, never settles.
	await _frames(3)
	var begun: int = _h.clock_ms
	var out: Array = AdServiceHarness.start(func() -> int: return await _flow.start_match(_setup()))
	assert_int(_loading).override_failure_message("card at once").is_equal(1)
	await _frames(4)
	assert_array(out).override_failure_message("still inside the bound").is_empty()
	_h.clock_ms = begun + _ads._settings.start_settle_bound_ms
	await _frames(4)
	assert_array(out).is_equal([OK])
	assert_int(_mains.size()).is_equal(1)
