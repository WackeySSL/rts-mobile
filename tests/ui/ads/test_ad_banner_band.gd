extends GdUnitTestSuite
## P430: the ad banner band (ADR 0039 section 5, ADR 0025 section 12, ADR 0015 sections 5 and 6).
## At the six sizes of ScreenSizes.ALL it reserves the banner's height plus the gap and the caption
## inside the safe rect, keeps 16 dp (48 dp on the start page) above the banner, collapses to 0
## without a banner, pairs show and hide with the tree and lays out again on `banner_changed`.

const AdServiceHarness: GDScript = preload("res://tests/ads/ad_service_harness.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const BAND_SCENE: String = "res://game/ui/ads/AdBannerBand.tscn"
## A 6-inch phone's density (420 dpi) at every size; only the stretch follows the window.
const PHONE_DPI: int = 420
const TOLERANCE_PX: float = 1.1

var _window_size_before: Vector2i
var _harness: AdServiceHarness
var _service: Node
var _host: VBoxContainer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	UiScale.clear_override()


func test_reserves_banner_height_plus_gap_and_caption_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(size)
		var band: AdBannerBand = await _place(true)
		var gap: float = float(AdsSettingsDef.load_default().banner_gap_dp)
		var banner: float = float(_service.banner_height_dp())
		assert_int(int(banner)).is_greater(0)
		var expected: float = UiScale.dp(gap + AdBannerBand.CAPTION_HEIGHT_DP + banner)
		assert_float(band.size.y).override_failure_message(str(size)).is_equal_approx(
			expected, TOLERANCE_PX
		)
		assert_float(band.reserved_px()).is_equal_approx(expected, TOLERANCE_PX)
		var safe: Rect2 = UiScale.safe_rect_base()
		var rect: Rect2 = Rect2(band.global_position, band.size)
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(rect))
			. override_failure_message("%s %s outside %s" % [size, rect, safe])
			. is_true()
		)
		_clear()


func test_banner_keeps_16_dp_below_the_controls_above() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(size)
		var band: AdBannerBand = await _place(true)
		var min_gap: float = UiScale.dp(16.0)
		var gap_to_banner: float = band.banner_rect().position.y
		assert_float(gap_to_banner).override_failure_message(str(size)).is_greater_equal(
			min_gap - TOLERANCE_PX
		)
		assert_float(band.get_node("Caption").position.y).is_greater_equal(min_gap - TOLERANCE_PX)
		_clear()


func test_start_page_keeps_48_dp() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(size)
		var band: AdBannerBand = await _place(true, true)
		var air: float = UiScale.dp(48.0)
		(
			assert_float(band.get_node("Caption").position.y)
			. override_failure_message(str(size))
			. is_greater_equal(air - TOLERANCE_PX)
		)
		assert_float(band.banner_rect().position.y).is_greater_equal(air - TOLERANCE_PX)
		var banner: float = float(_service.banner_height_dp())
		assert_float(band.size.y).is_equal_approx(
			UiScale.dp(48.0 + AdBannerBand.CAPTION_HEIGHT_DP + banner), TOLERANCE_PX
		)
		_clear()


func test_the_caption_says_advertisement_and_has_no_frame() -> void:
	await _turn(ScreenSizes.ALL[0])
	var band: AdBannerBand = await _place(true)
	var caption: Label = band.get_node("Caption")
	assert_str(caption.text).is_equal("Advertisement")
	assert_bool(caption.visible).is_true()
	assert_bool(caption.has_theme_stylebox_override("normal")).is_false()
	assert_int(band.get_children().size()).is_equal(1)


func test_collapses_to_zero_without_a_banner() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(size)
		var band: AdBannerBand = await _place(false)
		assert_float(band.size.y).override_failure_message(str(size)).is_equal(0.0)
		assert_float(band.custom_minimum_size.y).is_equal(0.0)
		assert_bool((band.get_node("Caption") as Label).visible).is_false()
		_clear()


func test_collapses_when_remove_ads_is_owned() -> void:
	await _turn(ScreenSizes.ALL[0])
	_make_service(true)
	_service._ledger.remove_ads = true
	var band: AdBannerBand = await _add_band(false)
	assert_float(band.size.y).is_equal(0.0)
	assert_bool((band.get_node("Caption") as Label).visible).is_false()


func test_show_on_enter_tree_and_hide_on_exit_tree() -> void:
	await _turn(ScreenSizes.ALL[0])
	_make_service(true)
	var fake: FakeAdBackend = AdServiceHarness.fake(_service)
	assert_bool(fake.banner_visible).is_false()
	var band: AdBannerBand = await _add_band(false)
	assert_bool(fake.banner_visible).is_true()
	assert_int(_service._banner_requests).is_equal(1)
	_host.remove_child(band)
	assert_bool(fake.banner_visible).is_false()
	assert_int(_service._banner_requests).is_equal(0)
	assert_int(_service.banner_height_dp()).is_equal(0)
	_host.add_child(band)
	assert_bool(fake.banner_visible).is_true()
	assert_int(_service._banner_requests).is_equal(1)


func test_two_bands_share_one_banner_until_both_leave() -> void:
	await _turn(ScreenSizes.ALL[0])
	_make_service(true)
	var first: AdBannerBand = await _add_band(false)
	var second: AdBannerBand = await _add_band(false)
	var fake: FakeAdBackend = AdServiceHarness.fake(_service)
	_host.remove_child(first)
	assert_bool(fake.banner_visible).is_true()
	_host.remove_child(second)
	assert_bool(fake.banner_visible).is_false()
	first.free()
	second.free()


func test_lays_out_again_on_banner_changed() -> void:
	await _turn(ScreenSizes.ALL[0])
	var band: AdBannerBand = await _place(true)
	var before_px: float = band.size.y
	_service.banner_changed.emit(90)
	await await_idle_frame()
	var expected: float = UiScale.dp(16.0 + AdBannerBand.CAPTION_HEIGHT_DP + 90.0)
	assert_float(band.size.y).is_greater(before_px)
	assert_float(band.size.y).is_equal_approx(expected, TOLERANCE_PX)
	_service.banner_changed.emit(0)
	await await_idle_frame()
	assert_float(band.size.y).is_equal(0.0)
	assert_bool((band.get_node("Caption") as Label).visible).is_false()


func test_lays_out_again_after_a_turn() -> void:
	await _turn(ScreenSizes.LANDSCAPE[0])
	var band: AdBannerBand = await _place(true)
	var banner: float = float(_service.banner_height_dp())
	for size: Vector2i in [
		ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[2], ScreenSizes.PORTRAIT[0]
	]:
		await _turn(size)
		_host.size = UiScale.safe_rect_base().size
		await await_idle_frame()
		var expected: float = UiScale.dp(16.0 + AdBannerBand.CAPTION_HEIGHT_DP + banner)
		assert_float(band.size.y).override_failure_message(str(size)).is_equal_approx(
			expected, TOLERANCE_PX
		)
		assert_float(band.size.x).is_equal_approx(_host.size.x, TOLERANCE_PX)


func test_no_band_in_the_battle_scene() -> void:
	var text: String = FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_bool(text.contains("AdBannerBand")).is_false()
	assert_bool(text.contains("game/ui/ads")).is_false()


## The window at `size` with a 6-inch phone's metrics (the stretch follows the window).
func _turn(size: Vector2i) -> void:
	var base: Vector2 = Vector2(1280.0, 720.0)
	if size.y > size.x:
		base = Vector2(720.0, 1280.0)
	var stretch: float = minf(float(size.x) / base.x, float(size.y) / base.y)
	UiScale.set_override(UiMetrics.create("Android", PHONE_DPI, 1.0, stretch, size, Rect2i()))
	get_window().size = size
	await await_idle_frame()
	await await_idle_frame()


func _make_service(consent: bool) -> void:
	_harness = AdServiceHarness.new()
	_service = auto_free(_harness.make(consent))
	add_child(_service)
	_host = auto_free(VBoxContainer.new())
	var safe: Rect2 = UiScale.safe_rect_base()
	_host.position = safe.position
	_host.size = safe.size
	add_child(_host)


func _add_band(start_page: bool) -> AdBannerBand:
	var band: AdBannerBand = (load(BAND_SCENE) as PackedScene).instantiate()
	band.service = _service
	band.start_page = start_page
	_host.add_child(band)
	await await_idle_frame()
	await await_idle_frame()
	return band


func _place(consent: bool, start_page: bool = false) -> AdBannerBand:
	_make_service(consent)
	return await _add_band(start_page)


func _clear() -> void:
	if is_instance_valid(_host):
		_host.free()
	if is_instance_valid(_service):
		_service.free()
