extends GdUnitTestSuite
## P430b: the ad banner band follows its visibility in the tree. A band that is hidden, or whose
## ancestor is hidden, gives its show back and reserves 0 height; shown again it takes one. A show
## and a hide are never counted twice (enter + visible, hidden then exit, exit while hidden, enter
## under a hidden ancestor). Counted on the fake backend through AdService's `_banner_requests`.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const HudThemeSupport: GDScript = preload("res://tests/support/hud_theme.gd")

var _window_size_before: Vector2i
var _service: Node
var _host: VBoxContainer
var _harness: RefCounted


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	var size: Vector2i = ScreenSizes.ALL[0]
	var landscape: Vector2i = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	var base: Vector2i = UiScale.base_size_for(size, landscape)
	var stretch: float = minf(float(size.x) / float(base.x), float(size.y) / float(base.y))
	var metrics: UiMetrics = UiMetrics.create("Android", 420, 1.0, stretch, size, Rect2i())
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	UiScale.clear_override()
	if _harness != null:
		_harness.dispose()
		_harness = null


func test_hiding_the_band_releases_its_show_and_showing_takes_it_again() -> void:
	_make_service()
	var fake: FakeAdBackend = _service._backend as FakeAdBackend
	var band: AdBannerBand = await _add_band()
	band.visible = false
	await await_idle_frame()
	assert_int(_service._banner_requests).is_equal(0)
	assert_bool(fake.banner_visible).is_false()
	_assert_collapsed(band, "hidden")
	band.visible = true
	await await_idle_frame()
	assert_int(_service._banner_requests).is_equal(1)
	assert_bool(fake.banner_visible).is_true()
	assert_float(band.size.y).is_greater(0.0)


func test_an_ancestor_hidden_and_shown_moves_the_band_too() -> void:
	_make_service()
	var band: AdBannerBand = await _add_band()
	_host.visible = false
	assert_int(_service._banner_requests).is_equal(0)
	_host.visible = false  # Again: nothing is released twice.
	assert_int(_service._banner_requests).is_equal(0)
	_assert_collapsed(band, "ancestor hidden")
	_host.visible = true
	assert_int(_service._banner_requests).is_equal(1)
	_host.visible = true
	assert_int(_service._banner_requests).is_equal(1)


func test_exit_while_hidden_does_not_release_twice() -> void:
	_make_service()
	var second: AdBannerBand = await _add_band()
	var other: AdBannerBand = await _second_band()
	assert_int(_service._banner_requests).is_equal(2)
	second.visible = false
	assert_int(_service._banner_requests).is_equal(1)
	_host.remove_child(second)
	assert_int(_service._banner_requests).is_equal(1)  # The other band's show is untouched.
	assert_object(other).is_not_null()
	_host.add_child(second)  # Still hidden: no show.
	assert_int(_service._banner_requests).is_equal(1)


func test_enter_under_a_hidden_ancestor_shows_nothing_until_it_is_shown() -> void:
	_make_service()
	var band: AdBannerBand = await _add_band()
	_host.remove_child(band)
	await await_idle_frame()
	assert_int(_service._banner_requests).is_equal(0)
	_host.visible = false
	_host.add_child(band)
	assert_int(_service._banner_requests).is_equal(0)
	_assert_collapsed(band, "entered hidden")
	_host.visible = true
	assert_int(_service._banner_requests).is_equal(1)
	_host.remove_child(band)
	assert_int(_service._banner_requests).is_equal(0)


func _assert_collapsed(band: AdBannerBand, label: String) -> void:
	# A hidden control is not laid out, so only the reserved minimum is checked.
	assert_float(band.custom_minimum_size.y).append_failure_message(label).is_equal(0.0)


func _make_service() -> void:
	_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
	_service = auto_free(_harness.make(true))
	_service.fake_auto_close = false
	add_child(_service)
	_host = auto_free(VBoxContainer.new())
	_fill_safe_rect(_host)
	add_child(_host)


func _add_band(parent: Control = _host) -> AdBannerBand:
	var band: AdBannerBand = auto_free(AdBannerBand.new())
	band.service = _service
	parent.add_child(band)
	await await_idle_frame()
	await await_idle_frame()
	return band


func _second_band() -> AdBannerBand:
	var other: VBoxContainer = auto_free(VBoxContainer.new())
	_fill_safe_rect(other)
	add_child(other)
	return await _add_band(other)


## The column covers the safe rect with a filler on top, so its band sits at the safe bottom.
func _fill_safe_rect(column: VBoxContainer) -> void:
	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	column.theme = HudThemeSupport.scaled()
	column.position = UiScale.safe_rect_base().position
	column.size = UiScale.safe_rect_base().size
