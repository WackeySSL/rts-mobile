extends GdUnitTestSuite
## P433: the map select's starting-credits offer in its `OfferSlot`. At the six sizes of ADR 0015
## section 6 the offer's button is at least 48 dp and inside the safe area, and nothing moves when
## the ad loads late, when the bonus is granted, or when it is taken. The widget alone is
## tests/ui/ads/test_start_credits_offer.gd.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _menu: Control
var _screen: MapSelect
var _progression: Node
var _flow: Node
var _h: AdServiceHarness
var _service: Node
var _clock: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_progression = FakeRank.new()
	_flow = FakeFlow.new()
	_h = AdServiceHarness.new()
	_clock = 0


func after_test() -> void:
	UiScale.clear_override()
	_close()
	for node: Node in [_progression, _flow]:
		if is_instance_valid(node):
			node.free()
	_h.dispose()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	if is_instance_valid(_service):
		_service.free()
		_service = null


func _open(size: Vector2i, fill: bool, consent: Variant = true) -> void:
	var profile: UiMetrics = _profile_with_window(size)
	UiScale.set_override(profile)
	get_window().size = size
	await await_idle_frame()
	# A fresh service per size: the loaded ad is part of its state.
	_service = _h.make(consent != false)
	add_child(_service)
	if consent == null:
		_service._consent_known = false  # Consent has not answered yet.
	AdServiceHarness.fake(_service).fill = fill
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	var stack: MenuStack = _menu.get_node("MenuStack") as MenuStack
	stack.slide_ms = 0
	_screen = MapSelect.new()
	_screen.progression = _progression
	_screen.flow = _flow
	stack.push(_screen)
	_screen.offer.use_service(_service)
	_screen.offer.now_ms = func() -> int: return _clock
	_clock = 1 << 40  # Past the arm time the offer took on the real clock while it opened.
	for _frame: int in range(3):
		await await_idle_frame()


## The rects of everything in the column, the offer slot included.
func _rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node: Node in _screen.column.get_children():
		if node is Control:
			out.append((node as Control).get_global_rect())
	return out


func _button() -> Button:
	return _screen.offer.get_node("OfferButton") as Button


func test_the_offer_sits_in_the_slot_owned_by_the_screen() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], true)
	var slot: OfferSlot = _screen.offer.get_parent() as OfferSlot
	assert_object(slot).is_not_null()
	assert_object(slot.owner).is_same(_screen)
	assert_int(slot.get_child_count()).is_equal(1)


func test_the_button_is_48_dp_inside_the_safe_area_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, true)
		var label: String = str(size)
		assert_bool(_screen.offer.is_offered()).override_failure_message(label).is_true()
		_screen.scroll.ensure_control_visible(_button())
		await await_idle_frame()
		var rect: Rect2 = _button().get_global_rect()
		var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
		assert_bool(safe.encloses(rect)).override_failure_message(label).is_true()
		assert_float(rect.size.y).override_failure_message(label).is_greater_equal(
			UiScale.dp(48.0) - TOLERANCE_PX
		)
		var column_rect: Rect2 = _screen.column.get_global_rect()
		assert_float(column_rect.end.x).override_failure_message(label).is_less_equal(safe.end.x)
		assert_float(column_rect.position.x).override_failure_message(label).is_greater_equal(
			safe.position.x
		)
		_close()
		UiScale.clear_override()


func test_nothing_moves_when_the_ad_loads_late_is_granted_or_taken() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, false)
		var label: String = str(size)
		assert_bool(_screen.offer.is_offered()).override_failure_message(label).is_false()
		var before_rects: Array[Rect2] = _rects()
		AdServiceHarness.fake(_service).fill = true  # The ad loads after the screen opened.
		_service._backend.request_load(&"rewarded")
		_screen.offer.refresh()
		await await_idle_frame()
		assert_bool(_screen.offer.is_offered()).override_failure_message(label).is_true()
		assert_array(_rects()).override_failure_message(label).is_equal(before_rects)
		_clock += AdsSettingsDef.load_default().reward_arm_ms
		_button().pressed.emit()
		await AdServiceHarness.frames(3)
		assert_bool(_screen.offer.is_pending()).override_failure_message(label).is_true()
		assert_array(_rects()).override_failure_message(label).is_equal(before_rects)
		_service.take_start_credits_bonus()
		_screen.offer.refresh()
		await await_idle_frame()
		assert_bool(_screen.offer.is_pending()).override_failure_message(label).is_false()
		assert_array(_rects()).override_failure_message(label).is_equal(before_rects)
		_close()
		UiScale.clear_override()


func test_start_waits_while_the_credits_ad_runs_and_then_takes_the_bonus() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], true)
	AdServiceHarness.fake(_service).show_never_closes = true
	_clock += AdsSettingsDef.load_default().reward_arm_ms
	_button().pressed.emit()
	await AdServiceHarness.frames(3)
	assert_bool(_screen.offer.is_running()).is_true()
	_screen._on_start()  # START while the ad is still open.
	assert_array(_flow.started).is_empty()  # No match was begun.
	AdServiceHarness.fake(_service).finish_show()
	await AdServiceHarness.frames(3)
	assert_bool(_screen.offer.is_pending()).is_true()
	_screen._on_start()
	assert_int(_flow.started.size()).is_equal(1)
	# The fake flow does not take the bonus, so this checks that it is still pending, not that
	# MatchSetup carries it.
	assert_int(_service.take_start_credits_bonus()).is_equal(
		AdsSettingsDef.load_default().reward_start_credits
	)


func test_a_hidden_and_shown_screen_clears_the_pending_state_by_itself() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], true)
	_clock += AdsSettingsDef.load_default().reward_arm_ms
	_button().pressed.emit()
	await AdServiceHarness.frames(3)
	assert_bool(_screen.offer.is_pending()).is_true()
	_screen.hide()
	_service.take_start_credits_bonus()
	_screen.show()
	await await_idle_frame()  # No manual refresh: the visibility binding does it.
	assert_bool(_screen.offer.is_pending()).is_false()


func test_consent_that_said_no_collapses_the_band_and_unknown_consent_reserves_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var label: String = str(size)
		await _open(size, true, false)
		assert_bool(_screen.offer.visible).override_failure_message(label).is_false()
		assert_float(_screen.offer.get_parent().size.y).override_failure_message(label).is_equal(
			0.0
		)
		var collapsed: Array[Rect2] = _rects()
		_service._set_can_request(true)  # A late yes: nothing moves while visible.
		_screen.offer.refresh()
		await await_idle_frame()
		assert_array(_rects()).override_failure_message(label).is_equal(collapsed)
		_close()
		UiScale.clear_override()
		await _open(size, true, null)
		assert_bool(_screen.offer.visible).override_failure_message(label).is_true()
		var reserved: Array[Rect2] = _rects()
		_service._set_can_request(false)  # A late no: nothing moves either.
		_screen.offer.refresh()
		await await_idle_frame()
		assert_array(_rects()).override_failure_message(label).is_equal(reserved)
		_close()
		UiScale.clear_override()


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
