extends GdUnitTestSuite
## P431: RewardedOffer on a real AdService with the fake backend (the service is injected).
## Hidden unless a rewarded ad is ready, the reward only through the callback (none on a cancel),
## one offer per screen, the button at least 48 dp at the six sizes, and no spinner node.

const OFFER_SCENE: String = "res://game/ui/ads/RewardedOffer.tscn"
const PLACEMENT: StringName = &"double_xp"
const REWARD_TEXT: String = "Watch an ad for double XP"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

var _h: AdServiceHarness = AdServiceHarness.new()
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


func _offer(scope: Node = null) -> RewardedOffer:
	var offer: RewardedOffer = (load(OFFER_SCENE) as PackedScene).instantiate() as RewardedOffer
	offer.configure(_service, PLACEMENT, REWARD_TEXT, _grant, scope if scope != null else _screen)
	_screen.add_child(offer)
	return offer


func _button(offer: RewardedOffer) -> Button:
	return offer.get_node("OfferButton") as Button


func test_hidden_when_no_ad_is_ready() -> void:
	AdServiceHarness.fake(_service).fill = false
	var offer: RewardedOffer = _offer()
	assert_bool(offer.visible).is_false()
	assert_bool(offer.is_offered()).is_false()


func test_hidden_without_consent_then_shown_once_ready() -> void:
	_service._can_request_ads = false
	var offer: RewardedOffer = _offer()
	assert_bool(offer.visible).is_false()
	_service._can_request_ads = true
	offer.refresh()
	assert_bool(offer.visible).is_true()


func test_shows_the_exact_reward_text_when_ready() -> void:
	var offer: RewardedOffer = _offer()
	assert_bool(offer.visible).is_true()
	assert_str(_button(offer).text).is_equal(REWARD_TEXT)


func test_periodic_recheck_is_throttled() -> void:
	var offer: RewardedOffer = _offer()
	var fake: FakeAdBackend = AdServiceHarness.fake(_service)
	fake.fill = false
	fake._states[FakeAdBackend.KIND_REWARDED] = AdBackend.LoadState.IDLE
	offer._process(RewardedOffer.RECHECK_INTERVAL_S * 0.5)
	assert_bool(offer.visible).is_true()
	offer._process(RewardedOffer.RECHECK_INTERVAL_S)
	assert_bool(offer.visible).is_false()


func test_reward_is_granted_only_in_the_callback_and_before_the_close() -> void:
	var offer: RewardedOffer = _offer()
	var order: Array[String] = []
	offer.on_reward = func() -> void: order.append("grant")
	_service.ad_closed.connect(func(_p: StringName) -> void: order.append("close"))
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_array(order).is_equal(["grant", "close"])
	assert_bool(offer.visible).is_false()


func test_a_cancel_grants_nothing_and_the_offer_comes_back() -> void:
	var offer: RewardedOffer = _offer()
	AdServiceHarness.fake(_service).grant_reward = false
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(0)
	assert_bool(offer.visible).is_true()
	assert_bool(_button(offer).disabled).is_false()


func test_a_grant_is_not_repeated_after_the_offer_hides() -> void:
	var offer: RewardedOffer = _offer()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(1)
	offer.refresh()
	assert_bool(offer.visible).is_false()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(1)


func test_a_second_offer_on_the_same_screen_is_refused() -> void:
	var first: RewardedOffer = _offer()
	var second: RewardedOffer = _offer()
	assert_bool(first.visible).is_true()
	assert_bool(second.visible).is_false()
	second.refresh()
	assert_bool(second.visible).is_false()


func test_the_limit_comes_from_data_and_a_freed_offer_gives_its_slot_back() -> void:
	var limit: int = AdsSettingsDef.load_default().rewarded_offers_per_screen
	var offers: Array[RewardedOffer] = []
	for i: int in limit + 1:
		offers.append(_offer())
	(
		assert_int(offers.filter(func(o: RewardedOffer) -> bool: return o.visible).size())
		. is_equal(limit)
	)
	_screen.remove_child(offers[0])
	offers[0].free()
	var late: RewardedOffer = _offer()
	assert_bool(late.visible).is_true()


func test_another_screen_has_its_own_offer() -> void:
	var other: Control = auto_free(Control.new())
	add_child(other)
	var first: RewardedOffer = _offer()
	var second: RewardedOffer = _offer(other)
	assert_bool(first.visible).is_true()
	assert_bool(second.visible).is_true()


func test_the_button_is_at_least_48_dp_at_the_six_sizes() -> void:
	var offer: RewardedOffer = _offer()
	var android: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	var upright: Dictionary[StringName, UiMetrics] = UiProfiles.portrait()
	for size: Vector2i in ScreenSizes.ALL:
		var metrics: UiMetrics = (
			upright[&"android_6in_portrait"]
			if UiScale.is_portrait_size(size)
			else android[&"android_6in"]
		)
		UiScale.set_override(metrics)
		get_window().size = size
		await await_idle_frame()
		offer.refresh()
		await await_idle_frame()
		var button: Button = _button(offer)
		var min_px: float = UiScale.dp(48.0)
		assert_bool(offer.visible).is_true()
		assert_float(button.custom_minimum_size.x).is_greater_equal(min_px)
		assert_float(button.custom_minimum_size.y).is_greater_equal(min_px)
		assert_float(button.size.y).is_greater_equal(min_px - 0.5)


func test_no_spinner_node() -> void:
	var offer: RewardedOffer = _offer()
	var stack: Array[Node] = [offer]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		(
			assert_bool(
				node is ProgressBar or node is TextureProgressBar or node is AnimatedSprite2D
			)
			. is_false()
		)
		assert_bool(node.name.to_lower().contains("spinner")).is_false()
		stack.append_array(node.get_children())
