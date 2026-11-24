extends GdUnitTestSuite
## P404: the consent form placeholder: dp sizes, the safe area under a notch in one landscape and
## one portrait size of ScreenSizes, a re-layout on a viewport change, and the buttons' names.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const INSET: Vector2i = Vector2i(60, 30)


func after_test() -> void:
	UiScale.clear_override()


## A 3 px per dp phone with a notch: the safe rect is the window less INSET on every side.
func _metrics(window: Vector2i, dpi: int) -> UiMetrics:
	var safe: Rect2i = Rect2i(INSET, window - INSET * 2)
	return UiMetrics.create("Android", dpi, 1.0, 1.0, window, safe)


func _build() -> FakeConsentForm:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var layer: FakeConsentForm = FakeConsentForm.build(
		true, func() -> void: pass, func() -> void: pass, func() -> void: pass
	)
	host.add_child(layer)
	return layer


func _check(layer: FakeConsentForm, label: String) -> void:
	var area: Control = layer.get_node("SafeArea") as Control
	var safe: Rect2 = UiScale.safe_rect_base()
	assert_object(Rect2(area.position, area.size)).override_failure_message(label).is_equal(safe)
	for caption: String in ["Accept", "Decline", "Close"]:
		var button: Button = layer.find_child(caption, true, false) as Button
		var expected: Vector2 = UiScale.dp_vec(160, 64)
		(
			assert_object(button.custom_minimum_size)
			. override_failure_message(label + " " + caption)
			. is_equal(expected)
		)
		assert_float(button.custom_minimum_size.x).is_greater_equal(UiScale.dp(48))
		assert_float(button.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))


func test_the_layout_fits_a_landscape_phone_with_a_notch() -> void:
	UiScale.set_override(_metrics(ScreenSizes.LANDSCAPE[1], 480))
	var layer: FakeConsentForm = _build()
	_check(layer, "landscape")
	assert_object(layer.find_child("Center", true, false)).is_not_null()


func test_the_layout_fits_a_portrait_phone_with_a_notch() -> void:
	UiScale.set_override(_metrics(ScreenSizes.PORTRAIT[1], 480))
	_check(_build(), "portrait")


func test_a_viewport_change_lays_the_form_out_again() -> void:
	UiScale.set_override(_metrics(ScreenSizes.LANDSCAPE[1], 480))
	var layer: FakeConsentForm = _build()
	UiScale.set_override(_metrics(ScreenSizes.PORTRAIT[1], 240))
	layer.get_viewport().size_changed.emit()
	_check(layer, "after the turn")


func test_close_exists_only_for_the_privacy_options_form() -> void:
	var layer: FakeConsentForm = FakeConsentForm.build(
		false, func() -> void: pass, func() -> void: pass, func() -> void: pass
	)
	auto_free(layer)
	assert_object(layer.find_child("Accept", true, false)).is_not_null()
	assert_object(layer.find_child("Close", true, false)).is_null()


func _luminance(c: Color) -> float:
	var channels: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		channels.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _ratio(a: Color, b: Color) -> float:
	var hi: float = maxf(_luminance(a), _luminance(b))
	var lo: float = minf(_luminance(a), _luminance(b))
	return (hi + 0.05) / (lo + 0.05)


func test_the_buttons_stand_out_from_the_backdrop_and_hold_a_readable_label() -> void:
	# P450: they were dark grey on near-black. WCAG ratios: text on fill, and border on backdrop.
	var text_on_fill: float = _ratio(FakeConsentForm.BUTTON_TEXT, FakeConsentForm.BUTTON_FILL)
	var border_on_backdrop: float = _ratio(FakeConsentForm.BUTTON_BORDER, FakeConsentForm.BACKDROP)
	assert_float(text_on_fill).is_greater_equal(4.5)
	var text_on_pressed: float = _ratio(FakeConsentForm.BUTTON_TEXT, FakeConsentForm.BUTTON_PRESSED)
	assert_float(text_on_pressed).override_failure_message("pressed state").is_greater_equal(4.5)
	assert_float(border_on_backdrop).is_greater_equal(4.5)
	var layer: FakeConsentForm = _build()
	for caption: String in ["Accept", "Decline", "Close"]:
		var button: Button = layer.find_child(caption, true, false) as Button
		var fill: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_object(fill).is_not_null()
		assert_object(fill.bg_color).is_equal(FakeConsentForm.BUTTON_FILL)
		assert_object(button.get_theme_color("font_color")).is_equal(FakeConsentForm.BUTTON_TEXT)
		assert_int(fill.border_width_left).is_greater_equal(1)
		var pressed: StyleBoxFlat = button.get_theme_stylebox("pressed") as StyleBoxFlat
		assert_object(pressed.bg_color).is_equal(FakeConsentForm.BUTTON_PRESSED)
		assert_object(button.get_theme_color("font_pressed_color")).is_equal(
			FakeConsentForm.BUTTON_TEXT
		)


func test_the_button_height_is_at_least_48_dp() -> void:
	UiScale.set_override(_metrics(ScreenSizes.PORTRAIT[1], 480))
	var layer: FakeConsentForm = _build()
	for caption: String in ["Accept", "Decline"]:
		var button: Button = layer.find_child(caption, true, false) as Button
		assert_float(button.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))


func test_the_border_and_corners_follow_dp() -> void:
	UiScale.set_override(_metrics(ScreenSizes.PORTRAIT[1], 480))  # 3 px per dp.
	var layer: FakeConsentForm = _build()
	var button: Button = layer.find_child("Accept", true, false) as Button
	var style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_int(style.border_width_left).is_equal(roundi(UiScale.dp(FakeConsentForm.BORDER_DP)))
	assert_int(style.corner_radius_top_left).is_equal(roundi(UiScale.dp(FakeConsentForm.RADIUS_DP)))
