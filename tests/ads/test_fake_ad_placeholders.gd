extends GdUnitTestSuite
## P403: the fake backend's "Test ad" placeholders: dp sizes, the safe area, a recompute when the
## viewport changes, and Close ending the show.

## A 3 px per dp phone with a notch: the safe rect is smaller than the window.
const WINDOW: Vector2i = Vector2i(1280, 720)
const SAFE: Rect2i = Rect2i(60, 30, 1160, 660)


func after_test() -> void:
	UiScale.clear_override()


func _metrics(dpi: int) -> UiMetrics:
	return UiMetrics.create("Android", dpi, 1.0, 1.0, WINDOW, SAFE)


func _add_host() -> Node:
	var host: Node = auto_free(Node.new())
	add_child(host)
	return host


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_the_placeholder_waits_for_its_close_button_then_rewards_and_closes() -> void:
	var host: Node = _add_host()
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.host = host
	fake.auto_close = false
	fake.draw_placeholders = true
	var seen: Array[String] = []
	fake.opened.connect(func(_kind: StringName) -> void: seen.append("opened"))
	fake.reward_earned.connect(func(_kind: StringName) -> void: seen.append("reward"))
	fake.closed.connect(func(_kind: StringName) -> void: seen.append("closed"))
	fake.request_load(AdBackend.KIND_REWARDED)
	fake.show_ad(AdBackend.KIND_REWARDED)
	assert_array(seen).contains_exactly(["opened"])
	var layer: Node = host.get_node("FakeTestAd")
	assert_int(layer.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	var close: Button = layer.find_child("Close", true, false) as Button
	assert_str(close.text).is_equal("Close")
	close.pressed.emit()
	assert_array(seen).contains_exactly(["opened", "reward", "closed"])
	await _frame()
	assert_bool(host.has_node("FakeTestAd")).is_false()


func test_auto_close_draws_no_placeholder() -> void:
	var host: Node = _add_host()
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.host = host
	fake.request_load(AdBackend.KIND_INTERSTITIAL)
	fake.show_ad(AdBackend.KIND_INTERSTITIAL)
	assert_int(host.get_child_count()).is_equal(0)


func test_the_close_button_is_at_least_48_dp_on_both_sides_under_a_dp_ratio_above_one() -> void:
	UiScale.set_override(_metrics(480))
	assert_float(UiScale.base_px_per_dp()).is_greater(1.0)
	var host: Node = _add_host()
	var layer: FakeAdPlaceholders = FakeAdPlaceholders.build_fullscreen(func() -> void: pass)
	host.add_child(layer)
	var close: Button = layer.find_child("Close", true, false) as Button
	assert_float(close.custom_minimum_size.x).is_greater_equal(UiScale.dp(48))
	assert_float(close.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))


func test_the_box_sits_inside_the_safe_rect_centred_and_follows_a_viewport_change() -> void:
	UiScale.set_override(_metrics(480))
	var host: Node = _add_host()
	var layer: FakeAdPlaceholders = FakeAdPlaceholders.build_fullscreen(func() -> void: pass)
	host.add_child(layer)
	var area: Control = layer.get_node("SafeArea") as Control
	var safe: Rect2 = UiScale.safe_rect_base()
	assert_object(Rect2(area.position, area.size)).is_equal(safe)
	assert_object(layer.find_child("Center", true, false)).is_not_null()
	# A turn changes the factor; the viewport's size_changed lays the content out again.
	UiScale.set_override(_metrics(240))
	host.get_viewport().size_changed.emit()
	var close: Button = layer.find_child("Close", true, false) as Button
	assert_float(close.custom_minimum_size.y).is_equal(
		UiScale.dp(FakeAdPlaceholders.CLOSE_MIN_DP.y)
	)
	assert_float(close.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))


func test_the_banner_strip_is_in_dp_on_the_bottom_edge_of_the_safe_rect() -> void:
	UiScale.set_override(_metrics(480))
	var host: Node = _add_host()
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.host = host
	fake.draw_placeholders = true
	fake.show_banner()
	fake.show_banner()
	assert_int(host.get_child_count()).is_equal(1)
	var strip: Control = host.get_node("FakeTestBanner").get_child(0) as Control
	var safe: Rect2 = UiScale.safe_rect_base()
	var height: float = UiScale.dp(float(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP))
	assert_float(strip.size.y).is_equal(height)
	assert_float(strip.position.y + strip.size.y).is_equal(safe.end.y)
	assert_float(strip.position.x).is_equal(safe.position.x)
	assert_float(strip.size.x).is_equal(safe.size.x)
	fake.hide_banner()
	await _frame()
	assert_int(host.get_child_count()).is_equal(0)
