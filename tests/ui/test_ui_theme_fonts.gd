extends GdUnitTestSuite
## The fonts, the tokens and the accent pairs of `game/ui/theme.tres` (plan row P118, ADR 0025
## section 13): Chakra Petch for the body and the numbers (500 by default, 600 for a number, 700 for
## a number that sits across a bar or a plate), Big Shoulders Display ExtraBold for buttons and
## titles in three size classes whose tracking is whole base px and so is left alone by the dp step,
## the HUD tokens, and one accent pair per side with the two checks of the ADR for the Derrick
## League's: its hue at least 15 degrees from danger and from money, and the text on the accent at
## contrast 4.5 or more.

const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const CHAKRA: String = "res://assets/art/fonts/chakra-petch/"
const SHOULDERS: String = "res://assets/art/fonts/big-shoulders/BigShouldersDisplay-ExtraBold.ttf"
## The size classes of Big Shoulders as the theme is meant to have them: type, base type, font size
## in dp, tracking in base px. Every test that needs a number reads the theme and compares.
const CLASSES: Array[Dictionary] = [
	{"type": &"CapsButton", "base": &"Button", "dp": 22, "tracking": 4},
	{"type": &"CapsTitle", "base": &"Label", "dp": 28, "tracking": 5},
	{"type": &"CapsBigTitle", "base": &"Label", "dp": 36, "tracking": 6},
]
## ADR 0025 section 13: tracking +6 to +14 % of the size. One tracking in base px cannot hold that
## band at every profile: the dp-to-px ratios run from 1.0 (the desktop window) to 2.37
## (web_phone_small), a ratio of 2.37 where 14 / 6 allows 2.33, and the tracking is a whole number
## of px. It is held on the phones, strictly. The tablet profiles (1.25) sit a little above it and
## the desktop window (1.0) well above it, and the tests pin those two as what they are.
const BAND_LOW: float = 0.06
const BAND_HIGH: float = 0.14
const PHONES: Array[StringName] = [
	&"android_6in",
	&"web_phone",
	&"web_phone_small",
	&"android_6in_portrait",
	&"web_phone_portrait",
]
const TABLETS: Array[StringName] = [&"web_tablet", &"web_tablet_portrait"]
const DESKTOPS: Array[StringName] = [&"desktop", &"desktop_portrait"]
## The shares that the tablet and the desktop window have today (13.3 to 14.3 %, 16.7 to 18.2 %).
const TABLET_SHARE: Array[float] = [0.130, 0.144]
const DESKTOP_SHARE: Array[float] = [0.165, 0.183]
## ADR 0025 section 13's checks of an accent.
const MIN_HUE_DISTANCE: float = 15.0
const MIN_TEXT_CONTRAST: float = 4.5

var _holder: Control


func before_test() -> void:
	_holder = auto_free(Control.new())
	add_child(_holder)


func after_test() -> void:
	UiScale.clear_override()


func test_chakra_petch_is_the_default_font_and_gives_numbers_their_heavier_weights() -> void:
	var theme: Theme = HudThemes.source()
	assert_str(theme.default_font.resource_path).is_equal(CHAKRA + "ChakraPetch-Medium.ttf")
	assert_str(_font_path(&"Label", &"")).is_equal(CHAKRA + "ChakraPetch-Medium.ttf")
	assert_str(_font_path(&"Label", &"NumberLabel")).is_equal(CHAKRA + "ChakraPetch-SemiBold.ttf")
	# The chain of a type variation reaches the weight of its base: ItemCostLow is an ItemCost.
	for variation: StringName in [&"PowerNumber", &"PowerNumberLow", &"ItemCost", &"ItemCostLow"]:
		var found: String = _font_path(&"Label", variation)
		assert_str(found).override_failure_message(variation).is_equal(
			CHAKRA + "ChakraPetch-Bold.ttf"
		)
	assert_str(_font_path(&"Button", &"")).is_equal(CHAKRA + "ChakraPetch-Medium.ttf")


func test_each_big_shoulders_class_has_its_own_font_variation_with_the_tracking_in_base_px(
) -> void:
	var theme: Theme = HudThemes.source()
	var kept: PackedStringArray = theme.get_meta(HudTheme.BASE_PX_META)
	var variations: Array[FontVariation] = []
	var sizes: Array[int] = []
	var trackings: Array[int] = []
	for spec: Dictionary in CLASSES:
		var type: StringName = spec["type"]
		assert_str(str(theme.get_type_variation_base(type))).is_equal(str(spec["base"]))
		assert_int(theme.get_font_size(&"font_size", type)).is_equal(spec["dp"])
		var font: Font = theme.get_font(&"font", type)
		assert_object(font).override_failure_message(str(type)).is_instanceof(FontVariation)
		var variation: FontVariation = font as FontVariation
		assert_str(variation.base_font.resource_path).is_equal(SHOULDERS)
		assert_int(variation.spacing_glyph).override_failure_message(str(type)).is_equal(
			spec["tracking"]
		)
		assert_array(kept).override_failure_message(str(type)).contains(["%s/fonts/font" % type])
		variations.append(variation)
		sizes.append(theme.get_font_size(&"font_size", type))
		trackings.append(variation.spacing_glyph)
	# One FontVariation per class: three objects, not one shared.
	assert_bool(variations[0] != variations[1] and variations[1] != variations[2]).is_true()
	# The size and the tracking grow with the class, as the theme has them.
	var sizes_grow: bool = sizes[0] < sizes[1] and sizes[1] < sizes[2]
	assert_bool(sizes_grow).override_failure_message("sizes %s" % [sizes]).is_true()
	var tracking_grows: bool = trackings[0] < trackings[1] and trackings[1] < trackings[2]
	assert_bool(tracking_grows).override_failure_message("tracking %s" % [trackings]).is_true()


## The dp step turns the font size into px and leaves the tracking: the copy holds the very same
## FontVariation, at every factor, and the size is the rounded dp size.
func test_the_dp_step_scales_the_class_sizes_and_leaves_the_tracking() -> void:
	var source: Theme = HudThemes.source()
	for factor: float in [1.0, 1.25, 1.75, 2.0, 2.37]:
		var copy: Theme = HudTheme.scaled(source, factor)
		for spec: Dictionary in CLASSES:
			var type: StringName = spec["type"]
			var want_px: int = roundi(float(spec["dp"]) * factor)
			(
				assert_int(copy.get_font_size(&"font_size", type))
				. override_failure_message("%s at %s" % [type, factor])
				. is_equal(want_px)
			)
			var variation: FontVariation = copy.get_font(&"font", type) as FontVariation
			assert_object(variation).is_same(source.get_font(&"font", type))
			assert_int(variation.spacing_glyph).is_equal(spec["tracking"])
	# The default font and the weights are not touched either.
	var copy: Theme = HudTheme.scaled(source, 1.75)
	assert_object(copy.default_font).is_same(source.default_font)
	assert_object(copy.get_font(&"font", &"NumberLabel")).is_same(
		source.get_font(&"font", &"NumberLabel")
	)


## The band of ADR 0025 section 13 on the phones, strictly: each class's tracking as the scaled
## copy of the theme holds it, over its font size in px after the dp step. No slack.
func test_the_tracking_stays_within_six_to_fourteen_percent_at_every_phone_profile() -> void:
	for profile: StringName in PHONES:
		for share: Dictionary in _shares(profile):
			var why: String = (
				"%s %s: %d px of %d px is %.2f %%"
				% [profile, share["type"], share["spacing"], share["px"], share["share"] * 100.0]
			)
			assert_float(share["share"]).override_failure_message(why).is_between(
				BAND_LOW, BAND_HIGH
			)


## The tablet and the desktop window are above the band, and the test says by how much: a tablet by
## up to 0.3 points, the desktop window (the dev window, not a phone) well above. Every profile of
## ui_profiles.gd is in exactly one of the three lists, so a new one has to be put in one.
func test_the_tablet_and_the_desktop_window_are_pinned_above_the_phones_band() -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	var listed: Array[StringName] = []
	listed.append_array(PHONES)
	listed.append_array(TABLETS)
	listed.append_array(DESKTOPS)
	listed.sort()
	var known: Array[StringName] = []
	known.assign(profiles.keys())
	known.sort()
	assert_array(listed).is_equal(known)
	for profile: StringName in TABLETS:
		for share: Dictionary in _shares(profile):
			var why: String = "%s %s: %.2f %%" % [profile, share["type"], share["share"] * 100.0]
			assert_float(share["share"]).override_failure_message(why).is_between(
				TABLET_SHARE[0], TABLET_SHARE[1]
			)
	for profile: StringName in DESKTOPS:
		for share: Dictionary in _shares(profile):
			var why: String = "%s %s: %.2f %%" % [profile, share["type"], share["share"] * 100.0]
			assert_float(share["share"]).override_failure_message(why).is_between(
				DESKTOP_SHARE[0], DESKTOP_SHARE[1]
			)


func test_the_hud_tokens_are_the_values_of_the_adr() -> void:
	var theme: Theme = HudThemes.source()
	assert_str(_hex(theme, &"border", &"HudTokens")).is_equal("2c383e")
	assert_str(_hex(theme, &"money", &"HudTokens")).is_equal("f2c14e")
	assert_str(_hex(theme, &"danger", &"HudTokens")).is_equal("ff5a3c")
	assert_str(_hex(theme, &"ok", &"HudTokens")).is_equal("6edc5f")
	assert_str(_hex(theme, &"text", &"HudTokens")).is_equal("ffffff")
	var panel: Color = theme.get_color(&"panel", &"HudTokens")
	assert_str(panel.to_html(false)).is_equal("0a0e11")
	assert_float(panel.a).is_equal_approx(0.84, 0.0001)
	# The panel as a StyleBox: the same colour, flat (no shadow, no blur), a 1 dp edge, 8 dp corners.
	var box: StyleBoxFlat = theme.get_stylebox(&"panel", &"HudPanel") as StyleBoxFlat
	assert_object(box).is_not_null()
	assert_that(box.bg_color).is_equal(panel)
	assert_str(box.border_color.to_html(false)).is_equal("2c383e")
	assert_int(box.shadow_size).is_equal(0)
	for side: int in 4:
		assert_int(box.get_border_width(side)).is_equal(1)
		assert_int(box.get_corner_radius(side)).is_equal(8)
	assert_str(str(theme.get_type_variation_base(&"HudPanel"))).is_equal("PanelContainer")
	# The design's fixed enemy colour, #FF9446, is not a token.
	for name: String in theme.get_color_list(&"HudTokens"):
		assert_str(theme.get_color(name, &"HudTokens").to_html(false)).is_not_equal("ff9446")


func test_the_lumen_accord_accent_is_the_designs_cyan_pair() -> void:
	var theme: Theme = HudThemes.source()
	assert_str(_hex(theme, &"accent", &"AccentRenew")).is_equal("1fa6c8")
	assert_str(_hex(theme, &"light", &"AccentRenew")).is_equal("62d6ee")
	assert_str(_hex(theme, &"on_accent", &"AccentRenew")).is_equal("05202a")


func test_the_derrick_league_accent_is_an_orange_pair() -> void:
	var theme: Theme = HudThemes.source()
	assert_str(_hex(theme, &"accent", &"AccentFossil")).is_equal("e07628")
	assert_str(_hex(theme, &"light", &"AccentFossil")).is_equal("ffa25c")
	assert_str(_hex(theme, &"on_accent", &"AccentFossil")).is_equal("2a1405")


## ADR 0025 section 13, check one: a hue at least 15 degrees from danger (about 9) and from money
## (about 42), for the accent and for its light. Both sides, so that a later pair of Lumen Accord
## cannot drift toward a token either.
func test_each_accent_and_its_light_keep_their_hue_apart_from_danger_and_money() -> void:
	var theme: Theme = HudThemes.source()
	var danger_hue: float = theme.get_color(&"danger", &"HudTokens").h * 360.0
	var money_hue: float = theme.get_color(&"money", &"HudTokens").h * 360.0
	assert_float(danger_hue).is_equal_approx(9.2, 0.1)
	assert_float(money_hue).is_equal_approx(42.1, 0.1)
	for side: StringName in [&"AccentRenew", &"AccentFossil"]:
		for item: StringName in [&"accent", &"light"]:
			var hue: float = theme.get_color(item, side).h * 360.0
			var from_danger: float = _hue_distance(hue, danger_hue)
			var from_money: float = _hue_distance(hue, money_hue)
			var why: String = (
				"%s %s hue %.1f: %.1f from danger, %.1f from money"
				% [side, item, hue, from_danger, from_money]
			)
			assert_float(from_danger).override_failure_message(why).is_greater_equal(
				MIN_HUE_DISTANCE
			)
			assert_float(from_money).override_failure_message(why).is_greater_equal(
				MIN_HUE_DISTANCE
			)


## Check two: the text on the accent at contrast 4.5 or more (WCAG), and on its light too.
func test_the_text_on_each_accent_has_contrast_of_four_and_a_half_to_one() -> void:
	var theme: Theme = HudThemes.source()
	for side: StringName in [&"AccentRenew", &"AccentFossil"]:
		var text: Color = theme.get_color(&"on_accent", side)
		for item: StringName in [&"accent", &"light"]:
			var ratio: float = _contrast(text, theme.get_color(item, side))
			(
				assert_float(ratio)
				. override_failure_message("%s text on %s: %.2f:1" % [side, item, ratio])
				. is_greater_equal(MIN_TEXT_CONTRAST)
			)
		# The light is the lighter of the pair, so that a pressed or lit part reads as lit.
		assert_float(_luminance(theme.get_color(&"light", side))).is_greater(
			_luminance(theme.get_color(&"accent", side))
		)


## Accent never carries meaning alone, and the two sides' accents are told apart by hue.
func test_the_two_sides_accents_are_far_apart_in_hue() -> void:
	var theme: Theme = HudThemes.source()
	var renew: float = theme.get_color(&"accent", &"AccentRenew").h * 360.0
	var fossil: float = theme.get_color(&"accent", &"AccentFossil").h * 360.0
	assert_float(_hue_distance(renew, fossil)).is_greater(90.0)


## For each class: the type, the font size in px and the tracking that the scaled copy of the theme
## holds at `profile` (the dp step as the HUD gets it), and the tracking's share of the size.
func _shares(profile: StringName) -> Array[Dictionary]:
	var factor: float = UiScale.base_px_per_dp_for(UiProfiles.by_name(profile))
	var copy: Theme = HudTheme.scaled(HudThemes.source(), factor)
	var found: Array[Dictionary] = []
	for spec: Dictionary in CLASSES:
		var type: StringName = spec["type"]
		var px: int = copy.get_font_size(&"font_size", type)
		var spacing: int = (copy.get_font(&"font", type) as FontVariation).spacing_glyph
		found.append(
			{"type": type, "px": px, "spacing": spacing, "share": float(spacing) / float(px)}
		)
	return found


## The path of the font that a Control of `base_type` with the type variation `variation` resolves
## from the HUD theme (the variation's chain of base types, then the default font).
func _font_path(base_type: StringName, variation: StringName) -> String:
	var control: Control = auto_free(Label.new() if base_type == &"Label" else Button.new())
	control.theme = HudThemes.source()
	control.theme_type_variation = variation
	_holder.add_child(control)
	var font: Font = control.get_theme_font(&"font")
	assert_object(font).is_not_null()
	return font.resource_path


func _hex(theme: Theme, item: StringName, type: StringName) -> String:
	return theme.get_color(item, type).to_html(false)


## The distance of two hues on the colour wheel, in degrees (0 to 180).
func _hue_distance(a: float, b: float) -> float:
	var apart: float = absf(a - b)
	return minf(apart, 360.0 - apart)


func _luminance(colour: Color) -> float:
	return 0.2126 * _linear(colour.r) + 0.7152 * _linear(colour.g) + 0.0722 * _linear(colour.b)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4)


## The WCAG contrast ratio of two colours.
func _contrast(a: Color, b: Color) -> float:
	var one: float = _luminance(a)
	var other: float = _luminance(b)
	return (maxf(one, other) + 0.05) / (minf(one, other) + 0.05)
