extends GdUnitTestSuite
## P421: the ads walk end to end in fake mode, through Phase 5's menu flow (plan Phase 6, Test plan
## "End to end"): consent first, the menu band, five matches with the interstitial caps, the start
## bonus granted once and taken once, a Remove ads purchase and what stays. Every number comes from
## `data/ads_settings.tres`. The clocks are injected (`AdsWalk`, `AdServiceHarness`), nothing waits
## for real time. The same flow under a backend that never answers is test_ads_never_answers.gd.

const AdsWalk: GDScript = preload("res://tests/e2e/support/ads_walk.gd")
const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
const MATCHES: int = 5
const POST_MATCH: StringName = &"post_match"

var _walk: RefCounted
var _rig: IntroRig = IntroRig.new()
var _size: Vector2 = Vector2(1280, 720)


func before_test() -> void:
	_walk = AdsWalk.new(self)
	_rig.setup(self, load(MENU_PATH) as PackedScene, _size)


func after_test() -> void:
	_rig.teardown(self)
	_walk.close()


func test_consent_is_asked_first_and_no_ad_call_comes_before_it() -> void:
	await _walk.open(false)
	var ads: Node = _walk.ads
	ads._consent_known = false  # Consent has not answered yet.
	var ump: FakeUmp = AdServiceHarness.ump(ads)
	ump.consent_required = true
	ump.info_never_answers = true
	AdServiceHarness.play_three_matches(ads)  # The caps would allow an interstitial.
	# The boot: the intro awaits the real `ensure_consent`; a menu with its band is already up.
	var player: IntroPlayer = _rig.make(self, _size, false, false, Callable(ads, "ensure_consent"))
	_rig.loader.finish()
	await _walk.show(_walk.main_menu())
	# Asked: the info update ran. Nothing else did.
	assert_int(ump.info_updates).is_equal(1)
	assert_int(ump.forms_shown).is_equal(0)
	assert_bool(player.consent_done()).is_false()
	assert_int(ads.consent_state()).is_equal(AdServiceScript.ConsentState.UNKNOWN)
	assert_int(_walk.fake.initializations).is_equal(0)
	assert_bool(ads.rewarded_ready(&"double_xp")).is_false()
	assert_bool(await ads.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_array(_walk.fake.calls).is_empty()  # No load, no show, no banner, no initialise.
	assert_int(ads.banner_height_dp()).is_equal(0)
	assert_float(_walk.band().reserved_px()).is_equal(0.0)
	# The intro does not leave while the consent is open, however long it waits.
	_rig.at(player, 0)
	_rig.at(player, player.settings.max_ms + 1)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	# The answer: the form shows, is accepted, and only then does the SDK start.
	ump.answer_info()
	await _walk.until(func() -> bool: return player.consent_done())
	assert_bool(player.consent_done()).is_true()
	assert_int(ump.forms_shown).is_equal(1)
	assert_int(ads.consent_state()).is_equal(AdServiceScript.ConsentState.YES)
	assert_int(_walk.fake.initializations).is_equal(1)
	assert_str(_walk.fake.calls[0]).is_equal("initialize")
	assert_int(_walk.fake.calls.find("banner")).is_greater(0)  # Only after the initialise.
	_rig.at(player, player.settings.max_ms + 2)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_a_menu_band_shows_in_the_menu_and_follows_the_screen() -> void:
	await _walk.open()
	var main: MainMenu = _walk.main_menu()
	await _walk.show(main)
	var band: AdBannerBand = _walk.band()
	assert_object(band).is_not_null()
	assert_bool(band.is_visible_in_tree()).is_true()
	assert_int(_walk.ads.banner_height_dp()).is_equal(_walk.fake.banner_height)
	assert_bool(_walk.fake.banner_visible).is_true()
	assert_float(band.reserved_px()).is_greater(0.0)
	assert_float(main.slot.get_combined_minimum_size().y).is_greater(0.0)
	assert_bool((band.get_node("Caption") as Label).visible).is_true()
	# The menu is left (the match map select replaces it): the band drops its request.
	await _walk.show_map_select()
	await _walk.frames(3)
	assert_object(_walk.band()).is_null()
	assert_bool(_walk.fake.banner_visible).is_false()
	# And back: the band shows again.
	await _walk.show(_walk.main_menu())
	assert_bool(_walk.fake.banner_visible).is_true()
	assert_float(_walk.band().reserved_px()).is_greater(0.0)


func test_five_matches_show_an_interstitial_only_where_the_caps_allow() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	var ticks: Array[int] = _durations()
	var expected: Array[bool] = _expected_shows(ticks)
	assert_bool(expected.has(true) and expected.has(false)).is_true()  # Both kinds are played.
	var shown_before: int = 0
	for index: int in MATCHES:
		var label: String = "match %d" % (index + 1)
		var map: MapSelect = await _walk.show_map_select()
		await _walk.start_match(map)
		assert_object(_walk.flow.current_runner()).override_failure_message(label).is_not_null()
		shown_before = _walk.interstitials()
		await _walk.end_match(ticks[index])
		# Never during the match or on its result screen: only after Back, between matches.
		assert_int(_walk.interstitials()).override_failure_message(label).is_equal(shown_before)
		await _walk.leave()
		var delta: int = _walk.interstitials() - shown_before
		assert_int(delta).override_failure_message(label).is_equal(1 if expected[index] else 0)
		if expected[index]:  # Once for a match: a second ask is refused.
			assert_bool(await ads.maybe_show_interstitial(POST_MATCH)).is_false()
			assert_int(_walk.interstitials()).is_equal(shown_before + 1)
		assert_bool(await ads.maybe_show_interstitial(&"pause")).is_false()  # Not any other place.
	assert_int(_walk.menus).is_equal(MATCHES)
	var total: int = expected.count(true)
	assert_int(_walk.interstitials()).is_equal(total)
	assert_int(_walk.h.events.count("open:" + POST_MATCH)).is_equal(total)
	assert_int(_walk.h.events.count("close:" + POST_MATCH)).is_equal(total)


func test_the_start_bonus_is_granted_once_and_taken_once_by_the_next_match() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	var credits: int = _walk.settings.reward_start_credits
	var map: MapSelect = await _walk.show_map_select()
	assert_int(ads.pending_start_credits()).is_equal(0)
	assert_bool(map.offer.is_offered()).is_true()
	assert_bool(map.offer.is_pending()).is_false()
	# Granted: the rewarded ad, its reward callback, the ledger.
	_walk.press(map.offer._button)
	await _walk.until(func() -> bool: return ads.pending_start_credits() > 0)
	assert_int(_walk.rewarded()).is_equal(1)
	assert_int(ads.pending_start_credits()).is_equal(credits)
	assert_int(credits).is_less_equal(_walk.settings.start_credits_bonus_max)
	await _walk.frames(2)
	assert_bool(map.offer.is_pending()).is_true()  # "+N credits ready": no second ad is offered.
	assert_bool(map.offer.is_offered()).is_false()
	_walk.press(map.offer._button)
	await _walk.frames(3)
	assert_int(_walk.rewarded()).is_equal(1)
	assert_bool(ads.grant_start_credits_bonus(credits)).is_false()  # No stacking either.
	# Taken: by the next match's setup and runner, once.
	await _walk.start_match(map)
	assert_int(_walk.flow.current_setup().bonus_starting_credits).is_equal(credits)
	assert_int(_walk.flow.current_runner().bonus_credits).is_equal(credits)
	assert_int(ads.pending_start_credits()).is_equal(0)
	assert_int(ads.take_start_credits_bonus()).is_equal(0)
	# Then 0: the match after it gets nothing.
	await _walk.end_match(1)
	await _walk.leave()
	var again: MapSelect = await _walk.show_map_select()
	await _walk.start_match(again)
	assert_int(_walk.flow.current_setup().bonus_starting_credits).is_equal(0)
	assert_int(_walk.flow.current_runner().bonus_credits).is_equal(0)
	assert_int(ads.pending_start_credits()).is_equal(0)


func test_remove_ads_ends_the_band_and_the_interstitial_and_keeps_the_rewarded_offers() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	AdServiceHarness.play_three_matches(ads)  # Interstitials are due.
	await _walk.show(_walk.main_menu())
	assert_float(_walk.band().reserved_px()).is_greater(0.0)
	# The control: with the entitlement missing, a finished match shows its interstitial.
	var map: MapSelect = await _walk.show_map_select()
	await _walk.start_match(map)
	await _walk.end_match(1)
	await _walk.leave()
	assert_int(_walk.interstitials()).is_equal(1)
	# The purchase, through the Settings row.
	AdServiceHarness.billing(ads).next_outcome = BillingBackend.Outcome.PURCHASED
	var settings_screen: SettingsScreen = await _walk.show_settings()
	var rows: RemoveAdsRows = settings_screen.remove_rows
	assert_bool(rows.remove_button.visible).is_true()
	_walk.press(rows.remove_button)
	await _walk.until(func() -> bool: return ads.has_remove_ads())
	assert_bool(ads.has_remove_ads()).is_true()
	await _walk.frames(3)
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_true()
	# No band: the menu reserves nothing and the backend's banner is gone.
	var main: MainMenu = _walk.main_menu()
	await _walk.show(main)
	await _walk.frames(3)
	assert_int(ads.banner_height_dp()).is_equal(0)
	assert_bool(_walk.fake.banner_visible).is_false()
	assert_float(_walk.band().reserved_px()).is_equal(0.0)
	assert_float(main.slot.get_combined_minimum_size().y).is_equal(0.0)
	# No interstitial: the caps' own conditions hold again, a match ends, nothing shows.
	ads.note_match_completed(_walk.settings.interstitial_min_play_s)
	var shown: int = _walk.interstitials()
	var second: MapSelect = await _walk.show_map_select()
	# The rewarded offer of the map select is still there, and still pays.
	assert_bool(second.offer.is_offered()).is_true()
	_walk.press(second.offer._button)
	await _walk.until(func() -> bool: return ads.pending_start_credits() > 0)
	assert_int(_walk.rewarded()).is_equal(1)
	assert_int(ads.pending_start_credits()).is_equal(_walk.settings.reward_start_credits)
	await _walk.start_match(second)
	await _walk.end_match(1)
	# The Double XP offer of the result screen is still there.
	assert_bool(_walk.result().offer.is_offered()).is_true()
	await _walk.leave()
	assert_int(_walk.interstitials()).is_equal(shown)
	assert_bool(await ads.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_int(_walk.fake.calls.count("show:" + AdBackend.KIND_INTERSTITIAL)).is_equal(shown)


## The ticks each of the five matches runs: long where the caps can show one (the first match past
## `interstitial_free_matches`, then again after one short match), short everywhere else.
func _durations() -> Array[int]:
	var settings: AdsSettingsDef = _walk.settings
	var long_ticks: int = settings.interstitial_min_play_s * Sim.TICK_RATE
	var out: Array[int] = []
	for number: int in range(1, MATCHES + 1):
		var long: bool = (
			number == settings.interstitial_free_matches + 1
			or number == settings.interstitial_free_matches + 3
		)
		out.append(long_ticks if long else 1)
	return out


## What the caps' rule says, worked out here from the data and the play times (the plan's table:
## nothing until `interstitial_free_matches` matches are done, then one after
## `interstitial_min_play_s` of play, which starts the count again).
func _expected_shows(ticks: Array[int]) -> Array[bool]:
	var settings: AdsSettingsDef = _walk.settings
	var out: Array[bool] = []
	var completed: int = 0
	var played_s: int = 0
	for match_ticks: int in ticks:
		completed += 1
		@warning_ignore("integer_division")
		played_s += match_ticks / Sim.TICK_RATE
		var due: bool = (
			completed > settings.interstitial_free_matches
			and played_s >= settings.interstitial_min_play_s
		)
		out.append(due)
		if due:
			played_s = 0
	return out
