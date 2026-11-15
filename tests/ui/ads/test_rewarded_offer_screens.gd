extends GdUnitTestSuite
## P431: RewardedOffer's screens: one offer per screen (data), the slot's screen as the default
## scope, re-entry, hidden screens, `configure` and the autoload fallback.

const PLACEMENT: StringName = &"double_xp"
const REWARD_TEXT: String = "Watch an ad for double XP"

var _h: AdServiceHarness
var _service: Node
var _screen: Control
var _grants: int = 0
var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_h = AdServiceHarness.new()
	_service = auto_free(_h.make(true))
	_screen = auto_free(Control.new())
	add_child(_screen)
	_grants = 0


func after_test() -> void:
	UiScale.clear_override()


func _grant() -> void:
	_grants += 1


func _offer(scope: Node = _screen) -> RewardedOffer:
	var offer: RewardedOffer = RewardedOffer.new()
	offer.configure(_service, PLACEMENT, REWARD_TEXT, _grant, scope)
	_screen.add_child(offer)
	return offer


func _button(offer: RewardedOffer) -> Button:
	return offer.get_node("OfferButton") as Button


func _fake() -> FakeAdBackend:
	return AdServiceHarness.fake(_service)


func _past_retry() -> void:
	_h.clock_ms += _service._settings.banner_reload_min_ms


func test_a_second_offer_on_the_same_screen_is_refused() -> void:
	var first: RewardedOffer = _offer()
	var second: RewardedOffer = _offer()
	assert_bool(first.visible).is_true()
	assert_bool(second.visible).is_false()
	second.refresh()
	assert_bool(second.visible).is_false()


func test_a_refused_offer_takes_the_slot_once_the_first_is_freed() -> void:
	var first: RewardedOffer = _offer()
	var second: RewardedOffer = _offer()
	assert_bool(second.visible).is_false()
	_screen.remove_child(first)
	first.free()
	second.refresh()
	assert_bool(second.visible).is_true()


func test_the_limit_comes_from_data() -> void:
	var limit: int = AdsSettingsDef.load_default().rewarded_offers_per_screen
	var shown: int = 0
	for _i: int in limit + 1:
		if _offer().visible:
			shown += 1
	assert_int(shown).is_equal(limit)


func test_the_default_scope_is_the_slots_screen() -> void:
	var first: RewardedOffer = RewardedOffer.new()
	first.configure(_service, PLACEMENT, REWARD_TEXT, _grant)
	var second: RewardedOffer = RewardedOffer.new()
	second.configure(_service, PLACEMENT, REWARD_TEXT, _grant)
	var other: Control = auto_free(Control.new())
	add_child(other)
	var third: RewardedOffer = RewardedOffer.new()
	third.configure(_service, PLACEMENT, REWARD_TEXT, _grant)
	_screen.add_child(first)
	_screen.add_child(second)
	other.add_child(third)
	assert_bool(first.visible).is_true()
	assert_bool(second.visible).is_false()
	assert_bool(third.visible).is_true()


func test_another_screen_has_its_own_offer() -> void:
	var other: Control = auto_free(Control.new())
	add_child(other)
	assert_bool(_offer().visible).is_true()
	assert_bool(_offer(other).visible).is_true()


func test_an_offer_that_leaves_and_re_enters_the_tree_is_offered_again() -> void:
	var offer: RewardedOffer = _offer()
	_screen.remove_child(offer)
	_screen.add_child(offer)
	assert_bool(offer.visible).is_true()
	var second: RewardedOffer = _offer()
	assert_bool(second.visible).is_false()


func test_a_hidden_screen_holds_no_slot() -> void:
	var offer: RewardedOffer = _offer()
	_screen.visible = false
	assert_bool(offer.is_offered()).is_false()
	var other: RewardedOffer = _offer()
	assert_bool(other.is_offered()).is_false()
	_screen.visible = true
	offer.refresh()
	other.refresh()
	assert_int([offer.is_offered(), other.is_offered()].count(true)).is_equal(1)


func test_configure_after_ready_applies_at_once() -> void:
	var offer: RewardedOffer = RewardedOffer.new()
	_screen.add_child(offer)
	assert_bool(offer.visible).is_false()
	offer.configure(_service, PLACEMENT, REWARD_TEXT, _grant, _screen)
	assert_bool(offer.visible).is_true()
	assert_str(_button(offer).text).is_equal(REWARD_TEXT.to_upper())


func test_configure_while_the_ad_runs_is_ignored() -> void:
	_service.fake_auto_close = false
	var offer: RewardedOffer = _offer()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	offer.configure(_service, &"other", "Other", _grant, _screen)
	assert_str(offer.placement).is_equal(String(PLACEMENT))
	_fake().finish_show()
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(1)


func test_without_a_service_it_uses_the_autoload() -> void:
	var offer: RewardedOffer = RewardedOffer.new()
	offer.configure(null, PLACEMENT, REWARD_TEXT, _grant, _screen)
	_screen.add_child(offer)
	var autoload: Node = get_tree().root.get_node("AdService")
	var bound: bool = false
	for connection: Dictionary in autoload.ad_closed.get_connections():
		bound = bound or (connection["callable"] as Callable).get_object() == offer
	assert_bool(bound).is_true()
