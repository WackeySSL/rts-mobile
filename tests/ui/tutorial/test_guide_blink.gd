extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The blinking frame (plan row P585, ADR 0048 sections 4 and 7): the period and the low opacity
## come from `data/tutorial/guide_settings.tres`, the colours from the theme's `GuideTokens`, a
## stalled beat doubles the ring in amber, and Reduced effects holds a steady, thicker frame with
## no Tween. The Tween is stepped by hand (`custom_step` on a stopped Tween), never by frames.

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


## Stops the engine from stepping the blink and resets it to its start: the tests step it by hand.
func _hand_blink() -> Tween:
	var blink: Tween = _mark._blink
	blink.stop()
	return blink


func _open_blinking(settings: GuideSettingsDef = null, beat: TutorialBeatDef = null) -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]), beat if beat != null else _control_beat("hit", NEXT)
	)
	if settings != null:
		_mark.settings = settings
		await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_true()


func _stall() -> void:
	for _i: int in 3 * Sim.TICK_RATE:  # Past the 2 s budget.
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world)
	await await_idle_frame()
	await await_idle_frame()


func _stalled_beat() -> TutorialBeatDef:
	var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
	beat.budget_s = 2
	return beat


## `tone` with the opacity the blink has right now in its alpha.
func _with_blink(tone: Color) -> Color:
	tone.a *= _mark.ring_alpha()
	return tone


func _copy(period_ms: int, low_pct: int) -> GuideSettingsDef:
	var copy: GuideSettingsDef = (load(SETTINGS_PATH) as GuideSettingsDef).duplicate()
	copy.blink_period_ms = period_ms
	copy.blink_low_alpha_pct = low_pct
	return copy


func test_the_half_period_and_low_opacity_are_the_stock_settings() -> void:
	await _open_blinking()
	var stock: GuideSettingsDef = load(SETTINGS_PATH) as GuideSettingsDef
	var half: float = stock.blink_period_ms / 2000.0
	var low: float = stock.blink_low_alpha_pct / 100.0
	var blink: Tween = _hand_blink()
	blink.custom_step(half * 0.5)
	assert_float(_mark.ring_alpha()).is_between(low + 0.01, 0.99)  # Not yet at the low.
	blink.custom_step(half * 0.5)
	assert_float(_mark.ring_alpha()).is_equal_approx(low, 0.0001)
	blink.custom_step(half)
	assert_float(_mark.ring_alpha()).is_equal_approx(1.0, 0.0001)


func test_a_swapped_copy_changes_the_period_and_the_low() -> void:
	await _open_blinking(_copy(4000, 50))
	var blink: Tween = _hand_blink()
	blink.custom_step(1.9)  # The stock half period is 0.4 s: this is not yet the low of 2.0 s.
	assert_float(_mark.ring_alpha()).is_greater(0.5)
	blink.custom_step(0.1)
	assert_float(_mark.ring_alpha()).is_equal_approx(0.5, 0.0001)
	blink.custom_step(2.0)
	assert_float(_mark.ring_alpha()).is_equal_approx(1.0, 0.0001)


func test_the_blink_loops_and_never_ends() -> void:
	await _open_blinking()
	var blink: Tween = _hand_blink()
	var half: float = _mark.settings.blink_period_ms / 2000.0
	for _i: int in 4:  # Two periods.
		blink.custom_step(half)
	assert_float(_mark.ring_alpha()).is_equal_approx(1.0, 0.0001)
	assert_bool(_mark.ring_blinking()).is_true()
	blink.custom_step(half)  # A third period has begun: the low again.
	assert_float(_mark.ring_alpha()).is_equal_approx(
		_mark.settings.blink_low_alpha_pct / 100.0, 0.0001
	)
	assert_bool(_mark.ring_blinking()).is_true()


func test_the_blink_reaches_the_drawn_colour() -> void:
	await _open_blinking()
	var theme_tone: Color = _mark.get_theme_color(&"ring", &"GuideTokens")
	var blink: Tween = _hand_blink()
	blink.custom_step(_mark.settings.blink_period_ms / 2000.0)  # The low.
	assert_float(_mark.ring_alpha()).is_less(1.0)
	var tone: Color = _mark.ring_tone()
	assert_float(tone.a).is_equal_approx(theme_tone.a * _mark.ring_alpha(), 0.0001)
	assert_float(tone.r).is_equal_approx(theme_tone.r, 0.0001)


func test_a_stalled_beat_is_amber_and_double_a_calm_one_is_ring_and_single() -> void:
	for reduced: bool in [false, true]:
		await _open(_profile(ScreenSizes.LANDSCAPE[0]), _stalled_beat(), false, [], reduced)
		await await_idle_frame()
		var ring: Color = _mark.get_theme_color(&"ring", &"GuideTokens")
		var amber: Color = _mark.get_theme_color(&"ring_stalled", &"GuideTokens")
		assert_that(_mark.ring_tone()).is_equal(_with_blink(ring))
		assert_int(_mark.ring_count()).is_equal(1)
		await _stall()
		assert_that(_mark.ring_tone()).is_equal(_with_blink(amber))
		assert_int(_mark.ring_count()).is_equal(2)
		assert_bool(_mark.ring_blinking()).is_equal(not reduced)
		_close()


func test_reduced_effects_hold_a_steady_thicker_frame_with_no_tween() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT), false, [], true)
	await await_idle_frame()
	assert_bool(_mark.ring_rect().has_area()).is_true()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_float(_mark.ring_alpha()).is_equal(1.0)
	assert_float(_mark.ring_line_px()).is_equal(UiScale.dp(CoachMark.RING_LINE_DP + 1.0))


func test_hiding_the_mark_stops_the_blink_and_restores_full_opacity() -> void:
	await _open_blinking()
	_hand_blink().custom_step(_mark.settings.blink_period_ms / 2000.0)
	assert_float(_mark.ring_alpha()).is_less(1.0)
	_mark.hide_mark()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_float(_mark.ring_alpha()).is_equal(1.0)


func test_showing_a_beat_twice_leaves_one_tween() -> void:
	await _open_blinking()
	_mark.show_beat(_director.current)
	await await_idle_frame()
	assert_int(get_tree().get_processed_tweens().size()).is_equal(1)


func test_a_switch_or_settings_change_mid_beat_kills_or_recreates_the_tween() -> void:
	await _open_blinking()
	_mark.reduced = true
	assert_bool(_mark.ring_blinking()).is_false()
	assert_float(_mark.ring_alpha()).is_equal(1.0)
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_float(_mark.ring_line_px()).is_equal(UiScale.dp(CoachMark.RING_LINE_DP + 1.0))
	_mark.reduced = false
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_true()
	_mark.settings = _copy(4000, 50)
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_true()
	_hand_blink().custom_step(2.0)
	assert_float(_mark.ring_alpha()).is_equal_approx(0.5, 0.0001)


func test_a_zero_period_runs_no_tween() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT), false, [], true)
	_mark.settings = _copy(0, 25)
	_mark.reduced = false
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_float(_mark.ring_alpha()).is_equal(1.0)
