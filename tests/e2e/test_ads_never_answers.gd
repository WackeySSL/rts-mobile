extends GdUnitTestSuite
## P421, the never-answers variant of the ads walk: through Phase 5's flow, a backend that never
## answers costs the player exactly the timeout in the data (`consent_timeout_ms`,
## `fullscreen_timeout_ms`, `fullscreen_late_cap_ms`, `billing_timeout_ms`) and never a stuck menu;
## a backend that opens and never closes holds everything (the timeout does not fire once the ad,
## the form or the sheet showed) until the close. The clocks are injected (`AdServiceHarness`'s
## `clock_ms`, the intro rig's `now`): no wait is real. The happy walk is test_ads_end_to_end.gd.

const AdsWalk: GDScript = preload("res://tests/e2e/support/ads_walk.gd")
const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
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


## The boot with consent unknown and a form required: the intro player runs the real
## `ensure_consent`. `script` sets what the fake UMP does before the call starts.
func _boot(script: Callable) -> IntroPlayer:
	await _walk.open(false)
	_walk.ads._consent_known = false
	var ump: FakeUmp = AdServiceHarness.ump(_walk.ads)
	ump.consent_required = true
	script.call(ump)
	_walk.make_interstitial_due()
	var player: IntroPlayer = _rig.make(
		self, _size, false, false, Callable(_walk.ads, "ensure_consent")
	)
	_rig.loader.finish()
	return player


## A match that ended with an interstitial due, on its result screen.
func _ended_match() -> void:
	_walk.make_interstitial_due()
	var map: MapSelect = await _walk.show_map_select()
	await _walk.start_match(map)
	await _walk.end_match(1)


func _timeout_ms() -> int:
	return _walk.settings.fullscreen_timeout_ms


func test_consent_that_never_answers_returns_at_its_timeout_and_the_boot_goes_on() -> void:
	var player: IntroPlayer = await _boot(func(ump: FakeUmp) -> void: ump.info_never_answers = true)
	var ads: Node = _walk.ads
	var timeout: int = _walk.settings.consent_timeout_ms
	_walk.h.clock_ms = timeout - 1
	await _walk.frames(4)
	assert_bool(player.consent_done()).is_false()
	_rig.at(player, 0)
	_rig.at(player, player.settings.max_ms + 1)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)  # Not before the answer.
	_walk.h.clock_ms = timeout
	await _walk.frames(4)
	assert_bool(player.consent_done()).is_true()
	assert_int(ads.consent_state()).is_equal(AdServiceScript.ConsentState.NO)
	# Not stuck: the intro opens out, and no ad call was made for the missing consent.
	_rig.at(player, player.settings.max_ms + 2)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)
	assert_int(AdServiceHarness.ump(ads).forms_shown).is_equal(0)
	assert_int(_walk.fake.initializations).is_equal(0)
	assert_array(_walk.fake.calls).is_empty()
	assert_bool(await ads.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_bool(ads.rewarded_ready(&"double_xp")).is_false()


func test_a_consent_form_that_never_closes_holds_the_boot_past_the_timeout() -> void:
	var player: IntroPlayer = await _boot(func(ump: FakeUmp) -> void: ump.form_never_closes = true)
	var ads: Node = _walk.ads
	var ump: FakeUmp = AdServiceHarness.ump(ads)
	await _walk.frames(4)
	assert_int(ump.forms_shown).is_equal(1)  # The form is up.
	_walk.h.clock_ms = _walk.settings.consent_timeout_ms * 10  # Far past the timeout.
	await _walk.frames(6)
	assert_bool(player.consent_done()).is_false()  # The timeout does not fire on a shown form.
	assert_int(_walk.fake.initializations).is_equal(0)  # Nothing proceeds under it.
	assert_array(_walk.fake.calls).is_empty()
	_rig.at(player, 0)
	_rig.at(player, player.settings.max_ms + 1)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.SETTLED)
	ump.dismiss(true)  # The close.
	await _walk.until(func() -> bool: return player.consent_done())
	assert_bool(player.consent_done()).is_true()
	assert_int(ads.consent_state()).is_equal(AdServiceScript.ConsentState.YES)
	assert_int(_walk.fake.initializations).is_equal(1)
	_rig.at(player, player.settings.max_ms + 2)
	assert_int(player.phase).is_equal(IntroPlayer.Phase.OPEN)


func test_an_interstitial_that_never_opens_lets_the_player_on_at_its_timeout() -> void:
	await _walk.open()
	await _ended_match()
	_walk.fake.show_never_opens = true
	_walk.fake.ignore_cancel = true  # AdMob cannot recall a started show.
	await _walk.leave(false)
	await _walk.frames(4)
	assert_int(_walk.menus).is_equal(0)  # The wait is on.
	_walk.h.clock_ms = _timeout_ms() - 1
	await _walk.frames(4)
	assert_int(_walk.menus).is_equal(0)
	_walk.h.clock_ms = _timeout_ms()
	await _walk.until(func() -> bool: return _walk.menus == 1)
	assert_int(_walk.menus).is_equal(1)  # Back at the menu by the timeout.
	assert_int(_walk.h.events.count("open:" + POST_MATCH)).is_equal(0)
	# The late ad holds up the next match, but only until the late cap.
	var map: MapSelect = await _walk.show_map_select()
	await _walk.start_match(map, false)
	await _walk.frames(6)
	assert_int(_walk.mains.size()).is_equal(1)
	assert_object(_walk.flow.current_runner()).is_null()
	var cap: int = _walk.settings.fullscreen_late_cap_ms
	_walk.h.clock_ms = _timeout_ms() + cap - 1
	await _walk.frames(6)
	assert_int(_walk.mains.size()).is_equal(1)  # One ms short of the cap: still held.
	assert_object(_walk.flow.current_runner()).is_null()
	_walk.h.clock_ms = _timeout_ms() + cap
	await _walk.until(func() -> bool: return _walk.mains.size() == 2)
	assert_int(_walk.mains.size()).is_equal(2)
	assert_object(_walk.flow.current_runner()).is_not_null()


func test_a_rewarded_ad_that_never_opens_ends_at_its_timeout_and_pays_nothing() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	var map: MapSelect = await _walk.show_map_select()
	assert_bool(map.offer.is_offered()).is_true()
	_walk.fake.show_never_opens = true
	_walk.fake.ignore_cancel = true
	_walk.press(map.offer._button)
	await _walk.frames(4)
	assert_bool(map.offer.is_running()).is_true()
	_walk.press(map._start)  # START waits for the offer: nothing starts.
	await _walk.frames(4)
	assert_object(_walk.flow.current_runner()).is_null()
	_walk.h.clock_ms = _timeout_ms()
	await _walk.until(func() -> bool: return not map.offer.is_running())
	assert_bool(map.offer.is_running()).is_false()
	assert_int(ads.pending_start_credits()).is_equal(0)
	# Not stuck: START works once the late show is settled or past its cap.
	var cap: int = _walk.settings.fullscreen_late_cap_ms
	_walk.h.clock_ms = _timeout_ms() + cap - 1
	await _walk.start_match(map, false)
	await _walk.frames(6)
	assert_object(_walk.flow.current_runner()).is_null()  # One ms short of the cap: still held.
	_walk.h.clock_ms = _timeout_ms() + cap
	await _walk.start_match(map)
	assert_object(_walk.flow.current_runner()).is_not_null()
	assert_int(_walk.flow.current_setup().bonus_starting_credits).is_equal(0)


func test_billing_that_never_answers_returns_at_its_timeout_and_settings_can_close() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	var store: FakeBilling = AdServiceHarness.billing(ads)
	var screen: SettingsScreen = await _walk.show_settings()
	var rows: RemoveAdsRows = screen.remove_rows
	# The rows showed the price; then the connection drops and the store never answers again.
	store.connect_never_answers = true
	store.connect_store()  # Connecting, and it never ends.
	var timeout: int = _walk.settings.billing_timeout_ms
	for button: Button in [rows.remove_button, rows.restore_button]:
		assert_bool(button.visible).is_true()
		_walk.h.clock_ms += 1  # A fresh deadline for each call.
		_walk.press(button)
		await _walk.frames(4)
		assert_bool(rows.is_busy()).is_true()
		assert_bool(screen.on_back()).is_true()  # Back is refused while a call is open.
		_walk.h.clock_ms += timeout - 1
		await _walk.frames(4)
		assert_bool(rows.is_busy()).is_true()
		_walk.h.clock_ms += 1
		await _walk.until(func() -> bool: return not rows.is_busy())
		assert_bool(rows.is_busy()).is_false()
		assert_bool(screen.on_back()).is_false()  # Not stuck: the screen may close.
		assert_bool(ads.has_remove_ads()).is_false()
		assert_bool(rows.remove_button.disabled).is_false()
		assert_bool(rows.restore_button.disabled).is_false()


func test_a_store_sheet_that_never_shows_returns_at_the_billing_timeout() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	AdServiceHarness.billing(ads).sheet_never_shows = true
	var screen: SettingsScreen = await _walk.show_settings()
	var rows: RemoveAdsRows = screen.remove_rows
	_walk.press(rows.remove_button)
	await _walk.frames(4)
	assert_bool(rows.is_busy()).is_true()
	_walk.h.clock_ms = _walk.settings.billing_timeout_ms - 1
	await _walk.frames(4)
	assert_bool(rows.is_busy()).is_true()  # One ms short of the timeout: still waiting.
	_walk.h.clock_ms = _walk.settings.billing_timeout_ms
	await _walk.until(func() -> bool: return not rows.is_busy())
	assert_bool(rows.is_busy()).is_false()
	assert_bool(ads.has_remove_ads()).is_false()
	assert_bool(rows.remove_button.visible).is_true()  # Still on offer: no entitlement was made up.


func test_a_store_sheet_that_never_closes_holds_the_purchase_until_it_closes() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	var store: FakeBilling = AdServiceHarness.billing(ads)
	store.sheet_never_closes = true
	var screen: SettingsScreen = await _walk.show_settings()
	var rows: RemoveAdsRows = screen.remove_rows
	_walk.press(rows.remove_button)
	await _walk.frames(4)
	_walk.h.clock_ms = _walk.settings.billing_timeout_ms * 10  # Far past the timeout.
	await _walk.frames(6)
	assert_bool(rows.is_busy()).is_true()  # The timeout does not fire on a shown sheet.
	assert_bool(screen.on_back()).is_true()
	assert_bool(ads.has_remove_ads()).is_false()
	store.finish_sheet(BillingBackend.Outcome.PURCHASED)  # The close.
	await _walk.until(func() -> bool: return not rows.is_busy())
	assert_bool(rows.is_busy()).is_false()
	assert_bool(ads.has_remove_ads()).is_true()


func test_an_interstitial_that_opens_and_never_closes_holds_the_flow_under_it() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	await _ended_match()
	_walk.fake.show_never_closes = true
	await _walk.leave(false)
	await _walk.until(func() -> bool: return _walk.h.events.has("open:" + POST_MATCH))
	assert_bool(_walk.h.events.has("open:" + POST_MATCH)).is_true()
	_walk.h.clock_ms = _timeout_ms() * 10  # Far past the timeout.
	await _walk.frames(6)
	assert_int(_walk.menus).is_equal(0)  # Nothing proceeds under the ad.
	assert_int(_walk.h.events.count("close:" + POST_MATCH)).is_equal(0)
	var settled: Array = AdServiceHarness.start(
		func() -> bool:
			await ads.settle_fullscreen()
			return true
	)
	var started: Array = AdServiceHarness.start(
		func() -> int: return await _walk.flow.start_match(_walk.make_setup())
	)
	await _walk.frames(6)
	assert_array(settled).is_empty()
	assert_array(started).is_equal([ERR_BUSY])  # The flow is busy leaving the result screen.
	assert_int(_walk.mains.size()).is_equal(1)
	_walk.fake.finish_show()  # The close.
	await _walk.until(func() -> bool: return _walk.menus == 1)
	assert_int(_walk.menus).is_equal(1)
	assert_int(_walk.h.events.count("close:" + POST_MATCH)).is_equal(1)
	assert_array(settled).is_equal([true])


func test_a_rewarded_ad_that_opens_and_never_closes_holds_the_next_match_until_it_pays() -> void:
	await _walk.open()
	var ads: Node = _walk.ads
	var map: MapSelect = await _walk.show_map_select()
	_walk.fake.show_never_closes = true
	_walk.press(map.offer._button)
	await _walk.until(func() -> bool: return _walk.h.events.has("open:start_credits"))
	_walk.h.clock_ms = _timeout_ms() * 10  # Far past the timeout.
	await _walk.frames(6)
	assert_bool(map.offer.is_running()).is_true()
	assert_int(ads.pending_start_credits()).is_equal(0)  # The reward comes with the close.
	var started: Array = AdServiceHarness.start(
		func() -> int: return await _walk.flow.start_match(map.build_setup())
	)
	await _walk.frames(8)
	assert_array(started).is_empty()
	assert_int(_walk.mains.size()).is_equal(0)  # No match is built under the ad.
	_walk.fake.finish_show()  # The close: the reward first, then the close.
	await _walk.until(func() -> bool: return _walk.mains.size() == 1)
	assert_array(started).is_equal([OK])
	assert_int(_walk.flow.current_setup().bonus_starting_credits).is_equal(
		_walk.settings.reward_start_credits
	)
	assert_int(ads.pending_start_credits()).is_equal(0)


## Settings with a returning EEA user: consent has run, so the Privacy options row is there.
func _privacy_settings() -> SettingsScreen:
	await _walk.open()
	var ump: FakeUmp = AdServiceHarness.ump(_walk.ads)
	ump.consent_required = true
	await _walk.ads.ensure_consent()
	var screen: SettingsScreen = await _walk.show_settings()
	assert_bool(screen.privacy_button.visible).is_true()
	return screen


func test_privacy_options_that_fail_to_show_return_at_once_and_the_row_works_again() -> void:
	var screen: SettingsScreen = await _privacy_settings()
	var ump: FakeUmp = AdServiceHarness.ump(_walk.ads)
	var base: int = ump.forms_shown  # The consent form of the setup.
	ump.show_fails = true
	_walk.press(screen.privacy_button)
	await _walk.frames(4)
	assert_int(ump.forms_shown).is_equal(base + 1)
	ump.show_fails = false  # The row is not stuck: a second tap asks again and the form closes.
	_walk.press(screen.privacy_button)
	await _walk.frames(4)
	assert_int(ump.forms_shown).is_equal(base + 2)


func test_a_privacy_options_form_that_never_closes_holds_consent_until_it_closes() -> void:
	var screen: SettingsScreen = await _privacy_settings()
	var ads: Node = _walk.ads
	var ump: FakeUmp = AdServiceHarness.ump(ads)
	var base: int = ump.forms_shown
	ump.form_never_closes = true
	_walk.press(screen.privacy_button)
	await _walk.frames(4)
	assert_int(ump.forms_shown).is_equal(base + 1)
	# There is no timeout on a shown form (ConsentFlow): far past the consent timeout it holds.
	_walk.h.clock_ms = _walk.settings.consent_timeout_ms * 10
	await _walk.frames(6)
	_walk.press(screen.privacy_button)  # One form at a time: no second form.
	await _walk.frames(2)
	assert_int(ump.forms_shown).is_equal(base + 1)
	var waiting: Array = AdServiceHarness.start(func() -> bool: return await ads.ensure_consent())
	await _walk.frames(6)
	assert_array(waiting).is_empty()  # A consent call waits for the open form.
	ump.dismiss(true)  # The close.
	await _walk.until(func() -> bool: return not waiting.is_empty())
	assert_array(waiting).is_equal([true])
	assert_int(ump.forms_shown).is_equal(base + 1)


func test_a_double_xp_ad_that_never_opens_ends_at_its_timeout_and_the_flow_goes_on() -> void:
	await _walk.open()
	var map: MapSelect = await _walk.show_map_select()
	await _walk.start_match(map)
	await _walk.end_match(1)
	var offer: DoubleXpOffer = _walk.result().offer
	assert_bool(offer.is_offered()).is_true()
	_walk.fake.show_never_opens = true
	_walk.fake.ignore_cancel = true
	_walk.press(offer._button)
	await _walk.frames(4)
	assert_bool(offer._button.disabled).is_true()  # The show is awaited.
	_walk.h.clock_ms = _timeout_ms() - 1
	await _walk.frames(4)
	assert_bool(offer._button.disabled).is_true()
	_walk.h.clock_ms = _timeout_ms()
	await _walk.until(func() -> bool: return not offer._button.disabled)
	assert_bool(offer._button.disabled).is_false()
	assert_int(_walk.rewarded()).is_equal(1)  # It was asked for,
	assert_bool(_walk.flow.last_award().bonus_applied).is_false()  # and paid nothing.
	await _walk.leave()  # Back is not stuck.
	assert_int(_walk.menus).is_equal(1)
