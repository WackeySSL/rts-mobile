extends GdUnitTestSuite
## P432: the DoubleXpOffer widget on its own, with a real Progression on a temp save and the fake
## ad backend: shown only for a loaded ad and a live award, the bonus only in the reward callback,
## once per award id, rewarded stays with Remove ads. The screen's part is
## tests/ui/test_result_screen_offer.gd.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5

var _h: AdServiceHarness
var _service: Node
var _progression: ProgressionScript
var _screen: Control
var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_h = AdServiceHarness.new()
	_service = auto_free(_h.make(true))
	add_child(_service)
	_progression = auto_free(ProgressionScript.new())
	_progression.bind(_h.save_service(), null)
	_screen = auto_free(Control.new())
	add_child(_screen)


func after_test() -> void:
	UiScale.clear_override()
	_h.dispose()


func _award() -> XpAward:
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = MatchSummary.OUTCOME_WIN
	summary.level = &"normal"
	summary.ticks = 0
	return _progression.award_match(summary)


func _offer(award: XpAward) -> DoubleXpOffer:
	var offer: DoubleXpOffer = DoubleXpOffer.new()
	offer.use_service(_service)
	_screen.add_child(offer)
	offer.set_award(award, _progression)
	return offer


func _button(offer: DoubleXpOffer) -> Button:
	return offer.get_node("OfferButton") as Button


func _fake() -> FakeAdBackend:
	return AdServiceHarness.fake(_service)


func _tap(offer: DoubleXpOffer) -> void:
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)


func test_the_text_and_the_multiplier_come_from_the_ads_data() -> void:
	var settings: AdsSettingsDef = AdsSettingsDef.load_default()
	var offer: DoubleXpOffer = _offer(_award())
	assert_str(_button(offer).text).is_equal(
		(settings.reward_xp_text % settings.reward_xp_multiplier).to_upper()
	)
	assert_str(String(offer.placement)).is_equal("double_xp")


func test_it_shows_for_a_loaded_ad_and_an_award_and_the_button_is_48_dp() -> void:
	var offer: DoubleXpOffer = _offer(_award())
	assert_bool(offer.is_offered()).is_true()
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		var button: Button = _button(offer)
		var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		var rect: Rect2 = button.get_global_rect()
		assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px).is_true()


func test_hidden_without_an_award_for_a_lesson_award_and_when_no_ad_is_loaded() -> void:
	_fake().fill = false  # Before the first ask: nothing is loaded.
	var offer: DoubleXpOffer = _offer(null)
	assert_bool(offer.visible).is_false()
	var lesson: XpAward = XpAward.new()  # A lesson's award has the empty id.
	lesson.base_xp = 50
	offer.set_award(lesson, _progression)
	assert_bool(offer.visible).is_false()
	var award: XpAward = _award()
	var before_xp: int = _progression.xp()
	offer.set_award(award, _progression)
	assert_bool(offer.visible).is_false()
	_button(offer).pressed.emit()  # Even a tap that gets through shows no ad and grants nothing.
	await AdServiceHarness.frames(3)
	assert_int(_progression.xp()).is_equal(before_xp)
	assert_bool(award.bonus_applied).is_false()


func test_the_bonus_is_applied_only_in_the_reward_callback_and_before_the_close() -> void:
	var award: XpAward = _award()
	var before_xp: int = _progression.xp()
	var offer: DoubleXpOffer = _offer(award)
	var at_close: Array[int] = []
	_service.ad_closed.connect(
		func(_placement: StringName) -> void: at_close.append(_progression.xp())
	)
	assert_int(_progression.xp()).is_equal(before_xp)  # Showing it grants nothing.
	await _tap(offer)
	var doubled: int = before_xp + award.base_xp
	assert_int(_progression.xp()).is_equal(doubled)
	assert_array(at_close).is_equal([doubled])  # Saved before the close was handled.
	assert_bool(award.bonus_applied).is_true()
	assert_bool(offer.visible).is_false()


func test_a_cancel_or_a_failed_show_grants_nothing_and_the_offer_stays() -> void:
	var award: XpAward = _award()
	var before_xp: int = _progression.xp()
	var offer: DoubleXpOffer = _offer(award)
	_fake().grant_reward = false
	await _tap(offer)
	assert_int(_progression.xp()).is_equal(before_xp)
	assert_bool(award.bonus_applied).is_false()
	assert_bool(offer.visible).is_true()


func test_a_late_award_shows_the_offer_then() -> void:
	var offer: DoubleXpOffer = _offer(null)
	assert_bool(offer.visible).is_false()
	offer.set_award(_award(), _progression)
	assert_bool(offer.visible).is_true()


func test_one_grant_per_award_id_after_a_re_show_a_late_score_or_a_second_callback() -> void:
	var award: XpAward = _award()
	var offer: DoubleXpOffer = _offer(award)
	await _tap(offer)
	var once: int = _progression.xp()
	offer.set_award(award, _progression)  # The same award again, as a late score does.
	assert_bool(offer.visible).is_false()
	assert_bool(offer.on_reward.call()).is_false()  # A second callback is refused by Progression.
	assert_int(_progression.xp()).is_equal(once)
	offer.queue_free()
	await await_idle_frame()
	var again: DoubleXpOffer = _offer(award)  # A re-shown screen builds a new offer.
	assert_bool(again.visible).is_false()  # The award took its bonus: nothing to offer.
	assert_int(_progression.xp()).is_equal(once)
	again.set_award(_award(), _progression)  # Another match, another award: offered again.
	assert_bool(again.visible).is_true()


func test_remove_ads_does_not_hide_the_rewarded_offer() -> void:
	_service._ledger.remove_ads = true
	assert_bool(_offer(_award()).visible).is_true()
