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
