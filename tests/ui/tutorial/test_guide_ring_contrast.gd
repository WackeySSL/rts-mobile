extends GdUnitTestSuite
## The frame's dim phase stays readable on the dark HUD panel (plan row P591, Michael's phone test:
## the dark frame barely showed on the strike button). Every colour is read from the theme and the
## blink floor from `guide_settings.tres`; nothing is a literal here. The dim phase is the ring's
## colour at the blink's low alpha over the panel; its contrast against the panel (WCAG relative
## luminance) must be at least 3:1, the floor for non-text UI parts.

const THEME: String = "res://game/ui/theme.tres"
const SETTINGS: String = "res://data/tutorial/guide_settings.tres"
const LEAST_RATIO: float = 3.0


func test_the_dim_phase_of_the_frame_has_three_to_one_against_the_hud_panel() -> void:
	var theme: Theme = load(THEME) as Theme
	var settings: GuideSettingsDef = load(SETTINGS) as GuideSettingsDef
	var low: float = settings.blink_low_alpha_pct / 100.0
	var panel: Color = theme.get_color(&"panel", &"HudTokens")
	panel.a = 1.0  # The panel is the ground the frame is judged on; its own opacity is not.
	for token: StringName in [&"ring", &"ring_stalled"]:
		var ring: Color = theme.get_color(token, &"GuideTokens")
		var dim: Color = panel.lerp(ring, low * ring.a)
		var ratio: float = _contrast(dim, panel)
		(
			assert_float(ratio)
			. override_failure_message(
				(
					"%s at %d%% is %.2f:1 on the HUD panel, under %.1f:1"
					% [token, low * 100.0, ratio, LEAST_RATIO]
				)
			)
			. is_greater_equal(LEAST_RATIO)
		)


func test_the_blink_floor_is_not_a_full_off_and_not_a_steady_light() -> void:
	var settings: GuideSettingsDef = load(SETTINGS) as GuideSettingsDef
	assert_int(settings.blink_low_alpha_pct).is_between(1, 99)


## WCAG 2.x contrast ratio of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4)
