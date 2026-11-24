extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The blinking frame (plan row P585, ADR 0048 sections 4 and 7): the period and the low opacity
## come from `data/tutorial/guide_settings.tres`, the colours from the theme's `GuideTokens`, a
## stalled beat doubles the ring in amber, and Reduced effects holds a steady, thicker frame with
## no Tween.

const SETTINGS_PATH: String = "res://data/tutorial/guide_settings.tres"
const THEME_PATH: String = "res://game/ui/theme.tres"
const TOKENS: Array[StringName] = [&"ring", &"ring_stalled", &"hint_fill", &"hint_line"]


func test_the_settings_file_holds_the_schema_of_adr_0048_section_7() -> void:
	var settings: GuideSettingsDef = load(SETTINGS_PATH) as GuideSettingsDef
	assert_object(settings).is_not_null()
	assert_float(settings.card_max_width_dp).is_equal(560.0)
	assert_float(settings.card_wide_dp).is_equal(440.0)
	assert_int(settings.card_max_height_pct).is_equal(45)
	assert_int(settings.blink_period_ms).is_equal(800)
	assert_int(settings.blink_low_alpha_pct).is_equal(25)
	assert_int(settings.hint_cycle_ms).is_equal(1600)
	assert_int(settings.hint_rest_ms).is_equal(800)
	assert_int(settings.hint_idle_ms).is_equal(2000)
	assert_int(settings.hint_tap_ms).is_equal(180)
	assert_int(settings.hint_drag_ms).is_equal(900)
	assert_int(settings.hint_pinch_ms).is_equal(900)
	assert_int(settings.hint_hold_extra_ms).is_equal(400)
	assert_float(settings.hint_size_dp).is_equal(72.0)


func test_the_blink_is_under_three_flashes_a_second_and_never_fully_off() -> void:
	var settings: GuideSettingsDef = load(SETTINGS_PATH) as GuideSettingsDef
	assert_int(settings.blink_period_ms).is_greater_equal(334)  # WCAG 2.3.1.
	assert_int(settings.blink_low_alpha_pct).is_between(1, 99)


func test_the_theme_resolves_the_guide_tokens_and_the_see_through_card() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	for token: StringName in TOKENS:
		assert_bool(theme.has_color(token, &"GuideTokens")).is_true()
	assert_that(theme.get_color(&"ring", &"GuideTokens")).is_equal(
		theme.get_color(&"light", &"AccentRenew")
	)
	assert_that(theme.get_color(&"ring_stalled", &"GuideTokens")).is_equal(
		theme.get_color(&"money", &"HudTokens")
	)
	var through: StyleBoxFlat = theme.get_stylebox(&"panel", &"GuideCardThrough") as StyleBoxFlat
	var plate: StyleBoxFlat = theme.get_stylebox(&"panel", &"PauseCard") as StyleBoxFlat
	assert_float(through.bg_color.a).is_less(plate.bg_color.a)


func test_the_frame_blinks_with_the_settings_period_and_low_opacity() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool(_mark.ring_blinking()).is_true()
	var low: float = _mark.settings.blink_low_alpha_pct / 100.0
	var seen: Array[float] = []
	for _i: int in 30:
		await await_idle_frame()
		seen.append(_mark.ring_alpha())
	assert_float(seen.min()).is_greater_equal(low - 0.001)
	assert_float(seen.max()).is_less_equal(1.0)
	assert_float(seen.max() - seen.min()).is_greater(0.0)  # It moves.
	assert_float(_mark.ring_line_px()).is_equal(UiScale.dp(CoachMark.RING_LINE_DP))


func test_the_period_is_the_one_in_the_data() -> void:
	var slow: GuideSettingsDef = (load(SETTINGS_PATH) as GuideSettingsDef).duplicate()
	slow.blink_period_ms = 4000
	slow.blink_low_alpha_pct = 50
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_mark.hide_mark()
	_mark.settings = slow
	_mark.show_beat(_director.current)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_true()
	for _i: int in 10:
		await await_idle_frame()
		assert_float(_mark.ring_alpha()).is_greater_equal(0.5 - 0.001)


func test_reduced_effects_hold_a_steady_thicker_frame_with_no_tween() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT), false, [], true)
	await await_idle_frame()
	assert_bool(_mark.ring_rect().has_area()).is_true()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_float(_mark.ring_alpha()).is_equal(1.0)
	assert_float(_mark.ring_line_px()).is_equal(UiScale.dp(CoachMark.RING_LINE_DP + 1.0))


func test_a_stalled_beat_keeps_the_double_ring_with_reduced_effects_too() -> void:
	for reduced: bool in [false, true]:
		var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
		beat.budget_s = 2
		await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat, false, [], reduced)
		for _i: int in 2 * Sim.TICK_RATE:
			Rig.step(_world, _loop)
		_runner.snapshot = Lesson.snapshot(_world)
		await await_idle_frame()
		await await_idle_frame()
		assert_bool((_mark.find_child("Hint", true, false) as Label).visible).is_true()  # Stalled.
		assert_bool(_mark.ring_blinking()).is_equal(not reduced)
		_close()
