extends GdUnitTestSuite
## P431: RewardedOffer on a real AdService with the fake backend (the service is injected).
## Hidden unless a rewarded ad is ready, the reward only through the callback (none on a cancel,
## one after a late open or a freed screen), one offer per screen, the button at least 48 dp and
## inside its parent at the six sizes, no spinner and no per-frame polling.

const PLACEMENT: StringName = &"double_xp"
const REWARD_TEXT: String = "Watch an ad for double XP"
const COUNTING: String = "res://tests/ui/ads/support/counting_service.gd"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

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


func test_hidden_when_no_ad_is_ready() -> void:
	_fake().fill = false
	var offer: RewardedOffer = _offer()
	assert_bool(offer.visible).is_false()
	assert_bool(offer.is_offered()).is_false()


func test_hidden_without_consent() -> void:
	_service = auto_free(_h.make(false))
	assert_bool(_offer().visible).is_false()


func test_shows_the_exact_reward_text_in_upper_case_when_ready() -> void:
	var offer: RewardedOffer = _offer()
	assert_bool(offer.is_offered()).is_true()
	assert_str(_button(offer).text).is_equal(REWARD_TEXT.to_upper())
	assert_str(_button(offer).theme_type_variation).is_equal("CapsButton")


func test_comes_back_when_an_ad_loads_later_on_the_timer_or_a_service_signal() -> void:
	_fake().fill = false
	var offer: RewardedOffer = _offer()
	_fake().fill = true
	_past_retry()
	(offer.get_node("RecheckTimer") as Timer).timeout.emit()
	assert_bool(offer.visible).is_true()
	_fake().fill = false
	_fake().request_load(FakeAdBackend.KIND_REWARDED)
	_service.ad_closed.emit(&"other")
	assert_bool(offer.visible).is_false()


func test_polls_on_a_timer_not_every_frame() -> void:
	_service = auto_free(_h.make(true, COUNTING))
	var offer: RewardedOffer = _offer()
	var timer: Timer = offer.get_node("RecheckTimer") as Timer
	assert_float(timer.wait_time).is_equal(RewardedOffer.RECHECK_INTERVAL_S)
	assert_bool(timer.is_stopped()).is_false()
	var before_calls: int = _service.ready_calls
	await AdServiceHarness.frames(5)
	assert_int(_service.ready_calls).is_equal(before_calls)
	timer.timeout.emit()
	assert_int(_service.ready_calls).is_equal(before_calls + 1)


func test_reward_is_granted_only_in_the_callback_and_before_the_close() -> void:
	var offer: RewardedOffer = _offer()
	var order: Array[String] = []
	offer.on_reward = func() -> void: order.append("grant")
	_service.ad_closed.connect(func(_p: StringName) -> void: order.append("close"))
	monitor_signals(offer)
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_array(order).is_equal(["grant", "close"])
	assert_bool(offer.visible).is_false()
	await assert_signal(offer).is_emitted("granted")
	assert_bool((offer.get_node("RecheckTimer") as Timer).is_stopped()).is_true()


func test_a_cancel_grants_nothing_and_the_offer_comes_back() -> void:
	var offer: RewardedOffer = _offer()
	_fake().grant_reward = false
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_int(_grants).is_equal(0)
	assert_bool(offer.visible).is_true()
	assert_bool(_button(offer).disabled).is_false()


func test_a_grant_is_not_repeated_after_the_offer_hides() -> void:
	var offer: RewardedOffer = _offer()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_int(_grants).is_equal(1)
	offer.refresh()
	assert_bool(offer.visible).is_false()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(3)
	assert_int(_grants).is_equal(1)
	assert_int(_fake().shows.size()).is_equal(1)


func test_a_reward_after_the_deadline_hides_the_offer_and_a_second_press_shows_nothing() -> void:
	var offer: RewardedOffer = _offer()
	_fake().show_never_opens = true
	_fake().ignore_cancel = true
	_button(offer).pressed.emit()
	_h.clock_ms = _service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(0)
	_fake().open_late()
	assert_int(_grants).is_equal(1)
	await AdServiceHarness.frames(2)
	assert_bool(offer.visible).is_false()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_int(_fake().shows.size()).is_equal(1)
	assert_int(_grants).is_equal(1)


func test_a_double_tap_while_the_ad_is_open_shows_and_grants_once() -> void:
	_service.fake_auto_close = false
	var offer: RewardedOffer = _offer()
	_button(offer).pressed.emit()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_int(_fake().shows.size()).is_equal(1)
	_fake().finish_show()
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(1)


func test_the_reward_still_arrives_when_the_screen_is_freed_while_the_ad_is_open() -> void:
	_service.fake_auto_close = false
	var offer: RewardedOffer = _offer()
	_button(offer).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_int(_fake().shows.size()).is_equal(1)
	_screen.remove_child(offer)
	offer.free()
	_fake().finish_show()
	await AdServiceHarness.frames(2)
	assert_int(_grants).is_equal(1)


func test_the_slot_takes_the_buttons_minimum_size_and_none_while_hidden() -> void:
	var slot: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(slot)
	_fake().fill = false
	var offer: RewardedOffer = RewardedOffer.new()
	offer.configure(_service, PLACEMENT, REWARD_TEXT, _grant, slot)
	slot.add_child(offer)
	await await_idle_frame()
	assert_float(slot.get_combined_minimum_size().y).is_equal(0.0)
	_fake().fill = true
	_past_retry()
	offer.refresh()
	await await_idle_frame()
	assert_float(slot.get_combined_minimum_size().y).is_greater_equal(UiScale.dp(48.0))


func test_the_button_is_at_least_48_dp_and_inside_its_parent_at_the_six_sizes() -> void:
	var slot: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(slot)
	var offer: RewardedOffer = RewardedOffer.new()
	offer.configure(_service, PLACEMENT, REWARD_TEXT + " and a great many more words", _grant, slot)
	slot.add_child(offer)
	var android: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	var upright: Dictionary[StringName, UiMetrics] = UiProfiles.portrait()
	for size: Vector2i in ScreenSizes.ALL:
		var portrait: bool = UiScale.is_portrait_size(size)
		var profile: StringName = &"android_6in_portrait" if portrait else &"android_6in"
		UiScale.set_override(upright[profile] if portrait else android[profile])
		get_window().size = size
		await await_idle_frame()
		var view: Vector2 = get_viewport().get_visible_rect().size
		slot.size = view
		offer.refresh()
		await await_idle_frame()
		var button: Button = _button(offer)
		var min_px: float = UiScale.dp(48.0)
		var label: String = "%s at %s" % [profile, size]
		assert_bool(offer.visible).override_failure_message(label).is_true()
		assert_float(button.custom_minimum_size.x).override_failure_message(label).is_greater_equal(
			min_px
		)
		assert_float(button.custom_minimum_size.y).override_failure_message(label).is_greater_equal(
			min_px
		)
		assert_float(button.size.x).override_failure_message(label).is_greater_equal(min_px - 0.5)
		assert_float(button.size.y).override_failure_message(label).is_greater_equal(min_px - 0.5)
		assert_float(button.size.x).override_failure_message(label).is_less_equal(view.x + 0.5)


func test_no_spinner_node() -> void:
	var offer: RewardedOffer = _offer()
	var stack: Array[Node] = [offer]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var is_spinner: bool = (
			node is ProgressBar
			or node is TextureProgressBar
			or node is AnimatedSprite2D
			or node.name.to_lower().contains("spinner")
		)
		assert_bool(is_spinner).is_false()
		stack.append_array(node.get_children())


func test_the_relay_is_freed_after_a_cancel_and_after_a_late_reward() -> void:
	var offer: RewardedOffer = _offer()
	_fake().grant_reward = false
	var relay: RewardRelay = RewardRelay.new(offer, _grant)
	var ref: WeakRef = weakref(relay)
	relay.run(_service, PLACEMENT, Callable())
	relay = null
	await AdServiceHarness.frames(3)
	assert_bool(ref.get_ref() == null).is_true()
	_fake().grant_reward = true
	_fake().show_never_opens = true
	_fake().ignore_cancel = true
	relay = RewardRelay.new(offer, _grant)
	ref = weakref(relay)
	relay.run(_service, PLACEMENT, Callable())
	relay = null
	_h.clock_ms = _service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(3)
	assert_bool(ref.get_ref() != null).is_true()
	_fake().open_late()
	await AdServiceHarness.frames(3)
	assert_int(_grants).is_equal(1)
	assert_bool(ref.get_ref() == null).is_true()
