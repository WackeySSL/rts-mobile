extends GdUnitTestSuite
## P433: the StartCreditsOffer widget on its own, on the fake ad backend and a temp-file ledger:
## the grant only in the reward callback (a close before it grants nothing), hidden without a
## loaded ad, the pending state instead of a second offer, rewarded stays with Remove ads, the arm
## delay, and the bonus taken once at match start. The screen's part is
## tests/ui/menu/test_map_select_offer.gd.

var _h: AdServiceHarness
var _service: Node
var _screen: Control
var _clock: int = 0


func before_test() -> void:
	_h = AdServiceHarness.new()
	_service = auto_free(_h.make(true))
	add_child(_service)
	_screen = auto_free(Control.new())
	add_child(_screen)
	_clock = 0


func after_test() -> void:
	_h.dispose()


func _settings() -> AdsSettingsDef:
	return AdsSettingsDef.load_default()


func _offer() -> StartCreditsOffer:
	var offer: StartCreditsOffer = StartCreditsOffer.new()
	offer.use_service(_service)
	offer.now_ms = func() -> int: return _clock
	_screen.add_child(offer)
	return offer


func _button(offer: StartCreditsOffer) -> Button:
	return offer.get_node("OfferButton") as Button


func _fake() -> FakeAdBackend:
	return AdServiceHarness.fake(_service)


func _tap(offer: StartCreditsOffer) -> void:
	_clock += _settings().reward_arm_ms
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)


func test_the_text_and_the_amount_come_from_the_ads_data() -> void:
	var settings: AdsSettingsDef = _settings()
	var offer: StartCreditsOffer = _offer()
	assert_str(_button(offer).text).is_equal(
		(settings.reward_credits_text % settings.reward_start_credits).to_upper()
	)
	assert_str(String(offer.placement)).is_equal("start_credits")
	assert_str(_button(offer).text).is_equal("+500 CREDITS NEXT MATCH")


func test_it_shows_for_a_loaded_ad() -> void:
	assert_bool(_offer().is_offered()).is_true()


func test_it_is_hidden_when_no_ad_is_loaded_and_a_stray_tap_grants_nothing() -> void:
	_fake().fill = false
	var offer: StartCreditsOffer = _offer()
	assert_bool(offer.is_offered()).is_false()
	assert_float(_button(offer).modulate.a).is_equal(0.0)  # Only its space is held.
	_clock += 10000
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_array(_h.events).is_empty()
	assert_int(_service.pending_start_credits()).is_equal(0)


func test_the_grant_happens_in_the_reward_callback_before_the_close() -> void:
	var offer: StartCreditsOffer = _offer()
	var at_close: Array[int] = []
	_service.ad_closed.connect(
		func(_placement: StringName) -> void: at_close.append(_service.pending_start_credits())
	)
	assert_int(_service.pending_start_credits()).is_equal(0)  # Showing it grants nothing.
	await _tap(offer)
	var bonus: int = _settings().reward_start_credits
	assert_int(_service.pending_start_credits()).is_equal(bonus)
	assert_array(at_close).is_equal([bonus])  # Saved before the close was handled.
	assert_array(_h.events).contains(["open:start_credits"])


func test_a_close_before_the_reward_grants_nothing_and_the_offer_stays() -> void:
	var offer: StartCreditsOffer = _offer()
	_fake().grant_reward = false
	await _tap(offer)
	assert_int(_service.pending_start_credits()).is_equal(0)
	assert_bool(offer.is_offered()).is_true()
	assert_bool(offer.is_pending()).is_false()


func test_a_granted_bonus_shows_the_pending_state_and_no_second_offer() -> void:
	var offer: StartCreditsOffer = _offer()
	await _tap(offer)
	var settings: AdsSettingsDef = _settings()
	assert_bool(offer.is_pending()).is_true()
	assert_bool(offer.is_offered()).is_false()
	assert_bool(_button(offer).disabled).is_true()
	assert_float(_button(offer).modulate.a).is_equal(1.0)
	assert_str(_button(offer).text).is_equal(
		(settings.reward_credits_pending_text % settings.reward_start_credits).to_upper()
	)
	var opened: int = _h.events.size()
	_clock += 10000
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_int(_h.events.size()).is_equal(opened)  # No second ad.


func test_a_pending_bonus_from_an_earlier_session_shows_the_pending_state() -> void:
	assert_bool(_service.grant_start_credits_bonus(300)).is_true()
	var offer: StartCreditsOffer = _offer()
	assert_bool(offer.is_pending()).is_true()
	assert_str(_button(offer).text).is_equal("+300 CREDITS READY")


func test_remove_ads_does_not_hide_the_rewarded_offer() -> void:
	_service._ledger.remove_ads = true
	assert_bool(_offer().is_offered()).is_true()


func test_a_tap_inside_the_arm_delay_starts_no_ad_and_one_after_it_does() -> void:
	var offer: StartCreditsOffer = _offer()
	var arm: int = _settings().reward_arm_ms
	_clock += arm - 1
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_array(_h.events).is_empty()
	assert_int(_service.pending_start_credits()).is_equal(0)
	_clock += 1
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_array(_h.events).contains(["open:start_credits"])
	assert_int(_service.pending_start_credits()).is_equal(_settings().reward_start_credits)


func test_the_match_start_takes_the_bonus_once_and_the_pending_state_clears() -> void:
	var offer: StartCreditsOffer = _offer()
	await _tap(offer)
	assert_bool(offer.is_pending()).is_true()
	# What MenuFlow.start_match calls (P523): the bonus once, then 0.
	assert_int(_service.take_start_credits_bonus()).is_equal(_settings().reward_start_credits)
	assert_int(_service.take_start_credits_bonus()).is_equal(0)
	offer.refresh()  # The recheck timer or the screen's return does this.
	assert_bool(offer.is_pending()).is_false()
	assert_bool(offer.is_offered()).is_true()  # Earn the next one.


func test_the_ads_texts_hold_exactly_one_number() -> void:
	for text: String in ["Watch an ad", "%d and %d", "%d%%", "%s %d"]:
		var bad: AdsSettingsDef = _settings().duplicate() as AdsSettingsDef
		bad.reward_credits_text = text
		assert_str("\n".join(bad.validate())).override_failure_message(text).contains("credits")
		bad = _settings().duplicate() as AdsSettingsDef
		bad.reward_credits_pending_text = text
		assert_str("\n".join(bad.validate())).override_failure_message(text).contains("credits")
	assert_array(_settings().validate()).is_empty()
