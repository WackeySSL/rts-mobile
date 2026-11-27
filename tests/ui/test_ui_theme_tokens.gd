extends GdUnitTestSuite
## The Treadline tokens (plan row P604, ADR 0049 section 5, ADR 0025 section 13): every token of
## the HUD, accent and guide types resolves, each accent keeps its hue apart from danger and money
## (15 degrees; Ironward's orange 25 from danger), and text on each accent reads at 4.5:1.

const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const HUD: Array[StringName] = [
	&"action_wash",
	&"border",
	&"danger",
	&"ground",
	&"ground_deep",
	&"info",
	&"money",
	&"ok",
	&"panel",
	&"panel_raised",
	&"text",
	&"text_dim",
	&"text_mute",
	&"touch",
	&"warning",
]
const ACCENT: Array[StringName] = [&"accent", &"light", &"on_accent"]
const SIDES: Array[StringName] = [&"AccentRenew", &"AccentFossil"]
const GUIDE: Array[StringName] = [&"hint_fill", &"hint_line", &"ring", &"ring_stalled"]
const MIN_HUE: float = 15.0
const MIN_ORANGE_FROM_DANGER: float = 25.0
const MIN_CONTRAST: float = 4.5


func test_every_token_resolves() -> void:
	var theme: Theme = HudThemes.source()
	for token: StringName in HUD:
		(
			assert_bool(theme.has_color(token, &"HudTokens"))
			. override_failure_message(str(token))
			. is_true()
		)
	for side: StringName in SIDES:
		for token: StringName in ACCENT:
			assert_bool(theme.has_color(token, side)).override_failure_message(str(token)).is_true()
	for token: StringName in GUIDE:
		(
			assert_bool(theme.has_color(token, &"GuideTokens"))
			. override_failure_message(str(token))
			. is_true()
		)
	assert_bool(theme.has_stylebox(&"panel", &"HudPanel")).is_true()


func test_each_accent_is_apart_from_danger_and_money() -> void:
	var theme: Theme = HudThemes.source()
	var danger: float = _hue(theme.get_color(&"danger", &"HudTokens"))
	var money: float = _hue(theme.get_color(&"money", &"HudTokens"))
	for side: StringName in SIDES:
		for item: StringName in [&"accent", &"light"]:
			var hue: float = _hue(theme.get_color(item, side))
			var why: String = "%s %s hue %.1f" % [side, item, hue]
			assert_float(_apart(hue, danger)).override_failure_message(why).is_greater_equal(
				MIN_HUE
			)
			assert_float(_apart(hue, money)).override_failure_message(why).is_greater_equal(MIN_HUE)


func test_ironward_orange_is_far_from_danger_red() -> void:
	var theme: Theme = HudThemes.source()
	var danger: float = _hue(theme.get_color(&"danger", &"HudTokens"))
	for item: StringName in [&"accent", &"light"]:
		var gap: float = _apart(_hue(theme.get_color(item, &"AccentFossil")), danger)
		assert_float(gap).override_failure_message("%s %.1f" % [item, gap]).is_greater_equal(
			MIN_ORANGE_FROM_DANGER
		)


func test_text_on_each_accent_has_contrast() -> void:
	var theme: Theme = HudThemes.source()
	for side: StringName in SIDES:
		var text: Color = theme.get_color(&"on_accent", side)
		for item: StringName in [&"accent", &"light"]:
			var ratio: float = _contrast(text, theme.get_color(item, side))
			(
				assert_float(ratio)
				. override_failure_message("%s %s %.2f" % [side, item, ratio])
				. is_greater_equal(MIN_CONTRAST)
			)


func test_danger_reads_on_the_panel() -> void:
	var theme: Theme = HudThemes.source()
	var panel: Color = theme.get_color(&"panel", &"HudTokens")
	panel.a = 1.0
	var ratio: float = _contrast(theme.get_color(&"danger", &"HudTokens"), panel)
	assert_float(ratio).is_greater_equal(MIN_CONTRAST)


func _hue(colour: Color) -> float:
	return colour.h * 360.0


func _apart(a: float, b: float) -> float:
	var gap: float = absf(a - b)
	return minf(gap, 360.0 - gap)


func _luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4)


func _contrast(a: Color, b: Color) -> float:
	var one: float = _luminance(a)
	var other: float = _luminance(b)
	return (maxf(one, other) + 0.05) / (minf(one, other) + 0.05)


## P662: the pairs the menu looks use that the token list does not already cover. The menu item and
## the eyebrow sit on the ground; the selected item on action_wash; the primary button's word on
## its amber fill. The muted text is left out on purpose (3.5:1, numbers and hints only).
func test_menu_token_pairs_have_contrast() -> void:
	var theme: Theme = HudThemes.source()
	var text: Color = theme.get_color(&"text", &"HudTokens")
	var dim: Color = theme.get_color(&"text_dim", &"HudTokens")
	var money: Color = theme.get_color(&"money", &"HudTokens")
	var ground: Color = theme.get_color(&"ground", &"HudTokens")
	var deep: Color = theme.get_color(&"ground_deep", &"HudTokens")
	var raised: Color = theme.get_color(&"panel_raised", &"HudTokens")
	var wash: Color = theme.get_color(&"action_wash", &"HudTokens")
	var pairs: Dictionary[String, Array] = {
		"text on ground": [text, ground],
		"text on raised": [text, raised],
		"text on wash": [text, wash],
		"text_dim on ground": [dim, ground],
		"eyebrow money on ground": [money, ground],
		"money on wash": [money, wash],
		"ground_deep on money": [deep, money],
	}
	for key: String in pairs:
		var ratio: float = _contrast(pairs[key][0], pairs[key][1])
		assert_float(ratio).override_failure_message("%s %.2f" % [key, ratio]).is_greater_equal(
			MIN_CONTRAST
		)
