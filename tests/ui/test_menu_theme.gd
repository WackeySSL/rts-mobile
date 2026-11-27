extends GdUnitTestSuite
## The menu look in `game/ui/theme.tres` (plan row P519, ADR 0043 section 5): each text variation
## reads at 4.5:1 or more on the plate or backdrop it sits on, each Button look is at least 48 dp
## tall at the base scale, and the side names carry their accent's light.

const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const MIN_CONTRAST: float = 4.5
const TOUCH_DP: float = 48.0
const FONT_COLOR: Dictionary[String, StringName] = {
	"normal": &"font_color", "pressed": &"font_pressed_color"
}
## The opaque backdrop of every menu screen (scenes/menu/menu.tscn).
const BACKDROP: Color = Color(0.10980392, 0.12941177, 0.15294118, 1)
const BUTTONS: Array[StringName] = [
	&"MenuToggle",
	&"MenuToggleFossil",
	&"MenuToggleOff",
	&"MenuTab",
	&"MenuTabOn",
	&"MenuItem",
	&"MenuItemOn",
	&"MenuPrimary",
]
## Label looks and the PanelContainer look they sit on (empty: the bare backdrop).
const LABELS: Dictionary[StringName, StringName] = {
	&"MenuTitle": &"",
	&"SideNameRenew": &"",
	&"SideNameFossil": &"",
	&"MenuRankLabel": &"MenuRankBadge",
	&"MenuEyebrow": &"",
}


func test_each_label_look_reads_on_its_plate() -> void:
	for look: StringName in LABELS:
		var plate: StringName = LABELS[look]
		var ground: Color = BACKDROP
		if plate != &"":
			var panel: PanelContainer = _node(PanelContainer.new(), plate) as PanelContainer
			ground = _over(panel.get_theme_stylebox(&"panel") as StyleBoxFlat, BACKDROP)
		_check(look, _node(Label.new(), look).get_theme_color(&"font_color"), ground)


func test_each_button_look_reads_on_every_plate_state() -> void:
	for look: StringName in BUTTONS:
		var button: Control = _node(Button.new(), look)
		for state: String in ["normal", "pressed"]:
			var plate: Color = _over(button.get_theme_stylebox(state) as StyleBoxFlat, BACKDROP)
			var text: Color = button.get_theme_color(FONT_COLOR[state])
			_check(look, text, plate)


func test_each_button_look_is_48_dp_tall_at_the_base_scale() -> void:
	for look: StringName in BUTTONS:
		var button: Button = _node(Button.new(), look) as Button
		button.text = "ON"
		(
			assert_float(button.get_combined_minimum_size().y)
			. override_failure_message("%s %s" % [look, button.get_combined_minimum_size()])
			. is_greater_equal(TOUCH_DP)
		)


func test_every_look_exists_with_the_base_the_screens_rely_on() -> void:
	var theme: Theme = HudThemes.source()
	var bases: Dictionary[StringName, StringName] = {
		&"MenuTitle": &"CapsBigTitle",
		&"SideNameRenew": &"CapsTitle",
		&"SideNameFossil": &"CapsTitle",
		&"MenuSlider": &"HSlider",
		&"MenuSliderFossil": &"HSlider",
		&"MenuSideCard": &"PanelContainer",
		&"MenuSideCardRenew": &"MenuSideCard",
		&"MenuSideCardFossil": &"MenuSideCard",
		&"MenuMapCard": &"PanelContainer",
		&"MenuMapCardOn": &"MenuMapCard",
		&"MenuMapCardLocked": &"MenuMapCard",
		&"MenuToggleRow": &"PanelContainer",
		&"MenuToggle": &"CapsButton",
		&"MenuToggleFossil": &"MenuToggle",
		&"MenuToggleOff": &"MenuToggle",
		&"MenuTab": &"CapsButton",
		&"MenuTabOn": &"MenuTab",
		&"MenuItem": &"CapsButton",
		&"MenuItemOn": &"MenuItem",
		&"MenuPrimary": &"CapsButton",
		&"MenuEyebrow": &"Label",
		&"MenuScrim": &"Control",
		&"MenuRankBadge": &"PanelContainer",
		&"MenuRankLabel": &"CapsTitle",
		&"MenuXpBar": &"ProgressBar",
	}
	for look: StringName in LABELS:
		assert_bool(bases.has(look)).override_failure_message(str(look)).is_true()
	for look: StringName in BUTTONS:
		assert_bool(bases.has(look)).override_failure_message(str(look)).is_true()
	for look: StringName in bases:
		var base: StringName = theme.get_type_variation_base(look)
		assert_str(str(base)).override_failure_message(str(look)).is_equal(str(bases[look]))


func test_a_side_name_is_its_accents_light() -> void:
	var theme: Theme = HudThemes.source()
	assert_str(theme.get_color(&"font_color", &"SideNameRenew").to_html(false)).is_equal(
		theme.get_color(&"light", &"AccentRenew").to_html(false)
	)
	assert_str(theme.get_color(&"font_color", &"SideNameFossil").to_html(false)).is_equal(
		theme.get_color(&"light", &"AccentFossil").to_html(false)
	)


func _node(node: Control, look: StringName) -> Control:
	node.theme = HudThemes.source()
	node.theme_type_variation = look
	add_child(node)
	return auto_free(node) as Control


func _check(look: StringName, text: Color, ground: Color) -> void:
	var ratio: float = _contrast(text, ground)
	assert_float(ratio).override_failure_message("%s: %.2f:1" % [look, ratio]).is_greater_equal(
		MIN_CONTRAST
	)


func _over(box: StyleBoxFlat, ground: Color) -> Color:
	return ground.lerp(Color(box.bg_color, 1.0), box.bg_color.a)


func _luminance(colour: Color) -> float:
	var parts: Array[float] = []
	for channel: float in [colour.r, colour.g, colour.b]:
		parts.append(channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


func _contrast(a: Color, b: Color) -> float:
	var one: float = _luminance(a)
	var other: float = _luminance(b)
	return (maxf(one, other) + 0.05) / (minf(one, other) + 0.05)


## P662: the eyebrow is at least 14 sp (the floor of touch-ui-rules).
func test_the_eyebrow_is_at_least_14_sp() -> void:
	var size: int = HudThemes.source().get_font_size(&"font_size", &"MenuEyebrow")
	assert_int(size).is_greater_equal(14)


## P662: the menu plates are square, but for the emblem and the check circle (shapes, not plates).
func test_menu_and_pause_plates_are_square() -> void:
	var theme: Theme = HudThemes.source()
	var looks: Array[Array] = [
		[&"MenuItem", &"normal"],
		[&"MenuItem", &"pressed"],
		[&"MenuItemOn", &"normal"],
		[&"MenuPrimary", &"normal"],
		[&"MenuPrimary", &"pressed"],
		[&"MenuToggle", &"normal"],
		[&"MenuTab", &"normal"],
		[&"PauseButton", &"normal"],
		[&"PausePrimary", &"normal"],
		[&"PauseChip", &"normal"],
	]
	for look: Array in looks:
		var box: StyleBoxFlat = theme.get_stylebox(look[1], look[0]) as StyleBoxFlat
		(
			assert_int(box.corner_radius_top_left + box.corner_radius_bottom_right)
			. override_failure_message(str(look))
			. is_equal(0)
		)
	for plate: StringName in [&"MenuSideCard", &"MenuMapCard", &"MenuToggleRow", &"PauseCard"]:
		var card: StyleBoxFlat = theme.get_stylebox(&"panel", plate) as StyleBoxFlat
		assert_int(card.corner_radius_top_left).override_failure_message(str(plate)).is_equal(0)


## P662: the scrim's three stops are the ground token at 96, 65 and 0 percent.
func test_the_scrim_gradient_is_the_ground_token() -> void:
	var theme: Theme = HudThemes.source()
	var ground: Color = theme.get_color(&"ground", &"HudTokens")
	var texture: GradientTexture2D = theme.get_icon(&"shade", &"MenuScrim") as GradientTexture2D
	var stops: PackedColorArray = texture.gradient.colors
	var alphas: Array[float] = [0.96, 0.65, 0.0]
	assert_int(stops.size()).is_equal(3)
	for i: int in 3:
		assert_str(Color(stops[i], 1.0).to_html(false)).is_equal(ground.to_html(false))
		assert_float(stops[i].a).is_equal_approx(alphas[i], 0.001)


## P663: text over the scrim drawn over a white pixel reads (4.5:1) where the scrim is not clear, so
## the test holds for any picture. The clear stop carries no text.
func test_text_over_the_scrim_over_white_reads() -> void:
	var theme: Theme = HudThemes.source()
	var text: Color = theme.get_color(&"text", &"HudTokens")
	var texture: GradientTexture2D = theme.get_icon(&"shade", &"MenuScrim") as GradientTexture2D
	for stop: int in 2:
		var shade: Color = texture.gradient.colors[stop]
		var over_white: Color = Color.WHITE.lerp(Color(shade, 1.0), shade.a)
		var ratio: float = _contrast(text, over_white)
		(
			assert_float(ratio)
			. override_failure_message("stop %d: %.2f:1" % [stop, ratio])
			. is_greater_equal(MIN_CONTRAST)
		)
