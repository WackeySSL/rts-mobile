extends GdUnitTestSuite
## P430: the ad banner band (ADR 0039 section 5, ADR 0025 section 12, ADR 0015 sections 5 and 6).
## At the six sizes of ScreenSizes.ALL and at the short and inset profiles the band, at the foot of
## a safe-rect column with a real Button above it, lines up with the fake banner's strip, keeps the
## gap (16 dp, 48 dp on the start page), collapses to 0 without a banner, pairs show and hide with
## the tree (a reparent keeps the banner) and lays out again on `banner_changed` and after a turn.

const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const HudThemeSupport: GDScript = preload("res://tests/support/hud_theme.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
## A 6-inch phone's density at every size; the stretch follows the window.
const PHONE_DPI: int = 420
## The ones with a short window, an upright one and the ones with a bottom inset.
const PROFILES: Array[StringName] = [
	&"web_phone",
	&"web_phone_small",
	&"web_phone_portrait",
	&"notch_design",
	&"notch_design_portrait",
]

var _window_size_before: Vector2i
var _service: Node
var _host: VBoxContainer
var _above: Button


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	UiScale.clear_override()


func test_lines_up_with_the_banner_at_the_six_sizes() -> void:
	var gap: float = float(AdsSettingsDef.load_default().banner_gap_dp)
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(_phone(size))
		var band: AdBannerBand = await _place()
		AdBandAsserts.assert_lines_up(self, band, _service, _above, gap, str(size))


func test_lines_up_at_short_and_inset_profiles() -> void:
	var gap: float = float(AdsSettingsDef.load_default().banner_gap_dp)
	for profile: StringName in PROFILES:
		await _turn(UiProfiles.by_name(profile))
		var band: AdBannerBand = await _place()
		AdBandAsserts.assert_lines_up(self, band, _service, _above, gap, str(profile))


func test_policy_floor_16_dp_above_the_banner() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(_phone(size))
		var band: AdBannerBand = await _place()
		AdBandAsserts.assert_lines_up(self, band, _service, _above, 16.0, str(size))
		var air: float = AdBandAsserts.strip_of(_service).get_global_rect().position.y
		air -= _above.get_global_rect().end.y
		assert_float(air).append_failure_message(str(size)).is_greater_equal(UiScale.dp(16.0))


func test_policy_floor_48_dp_on_the_start_page() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(_phone(size))
		var band: AdBannerBand = await _place(true)
		AdBandAsserts.assert_lines_up(self, band, _service, _above, 48.0, str(size))


func test_start_page_can_be_set_after_the_band_is_ready() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	var band: AdBannerBand = await _place()
	var before_px: float = band.size.y
	band.start_page = true
	await await_idle_frame()
	await await_idle_frame()
	var data: AdsSettingsDef = AdsSettingsDef.load_default()
	AdBandAsserts.assert_lines_up(
		self, band, _service, _above, float(data.start_banner_gap_dp), "start page"
	)
	assert_float(band.size.y).is_greater(before_px)


func test_the_caption_says_advertisement_in_the_theme_look() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	var band: AdBannerBand = await _place()
	var caption: Label = band.get_node("Caption")
	assert_str(caption.text).is_equal("Advertisement")
	assert_str(caption.theme_type_variation).is_equal("AdCaption")
	assert_int(caption.get_theme_font_size(&"font_size")).is_greater_equal(roundi(UiScale.dp(14.0)))
	assert_int(band.get_child_count()).is_equal(1)


func test_a_band_off_the_safe_bottom_fails_the_check() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	_make_service()
	var holder: Control = auto_free(Control.new())
	add_child(holder)
	var band: AdBannerBand = AdBannerBand.new()
	band.service = _service
	holder.add_child(band)
	band.position = Vector2.ZERO
	band.size = Vector2(UiScale.safe_rect_base().size.x, UiScale.dp(120.0))
	assert_bool(band.is_at_safe_bottom()).is_false()
	band.position.y = UiScale.safe_rect_base().end.y - band.size.y
	assert_bool(band.is_at_safe_bottom()).is_true()
	# Gone before idle, so the deferred check never reports the first position as a host bug.
	holder.remove_child(band)
	auto_free(band)


func test_collapses_to_zero_without_consent() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(_phone(size))
		var band: AdBannerBand = await _place(false, false)
		_assert_collapsed(band, str(size))


func test_collapses_to_zero_without_a_fill() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn(_phone(size))
		var band: AdBannerBand = await _place(false, true, false)
		_assert_collapsed(band, str(size))


func test_collapses_when_remove_ads_is_bought_while_shown() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	var band: AdBannerBand = await _place()
	assert_float(band.size.y).is_greater(0.0)
	_service._ledger.remove_ads = true
	_service._refresh_banner()
	await await_idle_frame()
	await await_idle_frame()
	_assert_collapsed(band, "remove ads")


func test_show_on_enter_tree_and_hide_on_exit_tree() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	_make_service()
	var fake: FakeAdBackend = _service._backend as FakeAdBackend
	assert_bool(fake.banner_visible).is_false()
	var band: AdBannerBand = await _add_band(false)
	assert_bool(fake.banner_visible).is_true()
	assert_int(_service._banner_requests).is_equal(1)
	_host.remove_child(band)
	await await_idle_frame()
	assert_bool(fake.banner_visible).is_false()
	assert_int(_service._banner_requests).is_equal(0)
	assert_int(_service.banner_height_dp()).is_equal(0)
	_host.add_child(band)
	assert_bool(fake.banner_visible).is_true()
	assert_int(_service._banner_requests).is_equal(1)


func test_two_bands_share_one_banner_until_both_leave() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	_make_service()
	var first: AdBannerBand = await _add_band(false)
	var second: AdBannerBand = await _second_band()
	var fake: FakeAdBackend = _service._backend as FakeAdBackend
	_host.remove_child(first)
	await await_idle_frame()
	assert_bool(fake.banner_visible).is_true()
	second.get_parent().remove_child(second)
	await await_idle_frame()
	assert_bool(fake.banner_visible).is_false()


func test_a_reparent_keeps_the_banner() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	_make_service()
	var heights: Array[int] = []
	_service.banner_changed.connect(func(height_dp: int) -> void: heights.append(height_dp))
	var band: AdBannerBand = await _add_band(false)
	var fake: FakeAdBackend = _service._backend as FakeAdBackend
	var strip: Control = AdBandAsserts.strip_of(_service)
	heights.clear()
	var other: VBoxContainer = auto_free(VBoxContainer.new())
	_host.add_child(other)
	band.reparent(other)
	assert_bool(fake.banner_visible).is_true()
	assert_int(_service._banner_requests).is_equal(1)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(fake.banner_visible).is_true()
	assert_int(_service._banner_requests).is_equal(1)
	assert_object(AdBandAsserts.strip_of(_service)).is_same(strip)
	assert_array(heights).is_empty()


func test_queue_free_while_in_the_tree_releases_the_banner() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	_make_service()
	var band: AdBannerBand = await _add_band(false)
	assert_int(_service._banner_requests).is_equal(1)
	band.queue_free()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_service._banner_requests).is_equal(0)
	assert_bool((_service._backend as FakeAdBackend).banner_visible).is_false()


func test_lays_out_again_on_banner_changed() -> void:
	await _turn(_phone(ScreenSizes.ALL[0]))
	var band: AdBannerBand = await _place()
	var before_px: float = band.size.y
	_service.banner_changed.emit(90)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(band.size.y).is_greater(before_px)
	assert_float(band.banner_rect().size.y).is_equal_approx(UiScale.dp(90.0), 1.0)
	_service.banner_changed.emit(0)
	await await_idle_frame()
	await await_idle_frame()
	_assert_collapsed(band, "emitted 0")


func test_lines_up_again_after_a_turn() -> void:
	var gap: float = float(AdsSettingsDef.load_default().banner_gap_dp)
	await _turn(_phone(ScreenSizes.LANDSCAPE[0]))
	var band: AdBannerBand = await _place()
	for size: Vector2i in [
		ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[2], ScreenSizes.PORTRAIT[0]
	]:
		await _turn(_phone(size))
		_fit_host()
		await await_idle_frame()
		await await_idle_frame()
		AdBandAsserts.assert_lines_up(self, band, _service, _above, gap, "turned to %s" % size)


## The shell of every Phase 5 menu keeps the battle screen free of the band; P435 allows it under
## PauseMenu alone and replaces this with a scene-tree check of "not in the HUD outside PauseMenu".
func test_the_band_is_not_in_the_battle_scene() -> void:
	var text: String = FileAccess.get_file_as_string("res://scenes/main.tscn")
	assert_bool(text.contains("AdBannerBand")).is_false()
	assert_bool(text.contains("game/ui/ads")).is_false()


func _assert_collapsed(band: AdBannerBand, label: String) -> void:
	assert_float(band.size.y).append_failure_message(label).is_equal(0.0)
	assert_float(band.custom_minimum_size.y).append_failure_message(label).is_equal(0.0)
	(
		assert_bool((band.get_node("Caption") as Label).visible)
		. append_failure_message(label)
		. is_false()
	)


## A 6-inch phone's metrics at `size`; the stretch follows the window (ADR 0015 section 2).
func _phone(size: Vector2i) -> UiMetrics:
	var base: Vector2i = UiScale.base_size_for(size, _landscape_base())
	var stretch: float = minf(float(size.x) / float(base.x), float(size.y) / float(base.y))
	return UiMetrics.create("Android", PHONE_DPI, 1.0, stretch, size, Rect2i())


func _turn(metrics: UiMetrics) -> void:
	UiScale.set_override(metrics)
	if is_instance_valid(_host):
		_fit_host()  # The menu's host follows the safe rect at once, as an anchored one does.
	get_window().size = metrics.window_size
	await await_idle_frame()
	await await_idle_frame()


## A fake-mode service (placeholders drawn) and the safe-rect column that hosts the band: an
## expanding filler, a real Button, then the band.
func _make_service(consent: bool = true, fill: bool = true) -> void:
	var harness: RefCounted = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
	_service = auto_free(harness.make(consent))
	_service.fake_auto_close = false
	(_service._backend as FakeAdBackend).fill = fill
	add_child(_service)
	_host = auto_free(VBoxContainer.new())
	_host.add_theme_constant_override("separation", 0)
	_host.theme = HudThemeSupport.scaled()
	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.add_child(filler)
	_above = Button.new()
	_above.text = "Settings"
	_above.custom_minimum_size = UiScale.dp_vec(48.0, 48.0)
	_host.add_child(_above)
	add_child(_host)
	_fit_host()


func _fit_host() -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	_host.theme = HudThemeSupport.scaled()
	_host.position = safe.position
	_host.size = safe.size


func _add_band(start_page: bool) -> AdBannerBand:
	var band: AdBannerBand = auto_free(AdBannerBand.new())
	band.service = _service
	band.start_page = start_page
	_host.add_child(band)
	await await_idle_frame()
	await await_idle_frame()
	return band


func _place(start_page: bool = false, consent: bool = true, fill: bool = true) -> AdBannerBand:
	await _drop()
	_make_service(consent, fill)
	return await _add_band(start_page)


## The last case's service and host leave the tree, so a stale band is never checked again.
func _drop() -> void:
	if is_instance_valid(_host):
		_host.queue_free()
	if is_instance_valid(_service):
		_service.queue_free()
	await await_idle_frame()


## A second host on the same safe rect, its band at the foot, for the tests that need two bands.
func _second_band() -> AdBannerBand:
	var other: VBoxContainer = auto_free(VBoxContainer.new())
	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	other.add_child(filler)
	other.theme = HudThemeSupport.scaled()
	add_child(other)
	other.position = UiScale.safe_rect_base().position
	other.size = UiScale.safe_rect_base().size
	var band: AdBannerBand = auto_free(AdBannerBand.new())
	band.service = _service
	other.add_child(band)
	await await_idle_frame()
	await await_idle_frame()
	return band


## The project's base size (landscape), from the settings.
func _landscape_base() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
