extends GdUnitTestSuite
## The HUD's one Theme (plan row P58): every colour, font size and StyleBox of the HUD's Controls
## resolves from `game/ui/theme.tres`, in dp turned into px by HudTheme, and is what the scripts
## set before the theme existed. The numbers below are those, typed again from the code of main at
## 32bfb89 (ArmyBar.FONT_DP 18, SelectionPanel NAME_FONT_DP 16, NUMBER_FONT_DP 20, PAD_DP 8 and
## BACKDROP, the Dev button's 40 base px, BoxOverlay's Color.WHITE with FeedbackStyle.OUTLINE and
## FILL), so a changed theme value fails here and changes in the same PR as a new look.

const MainSceneTests: GDScript = preload("res://tests/scenes/test_main_scene.gd")
const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARMY_FONT_DP: float = 18.0
const NAME_FONT_DP: float = 16.0
const NUMBER_FONT_DP: float = 20.0
const DEV_FONT_PX: int = 40  ## Base px, not dp.
const PAD_DP: float = 8.0
const BACKDROP: Color = Color(0.06, 0.08, 0.11, 0.78)
const FILL: Color = Color(1.0, 1.0, 1.0, 0.15)
const OUTLINE: Color = Color("1C2127")
const STROKE: Color = Color.WHITE

var _window_size_before: Vector2i
var _main: Node2D


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_the_theme_file_holds_the_hud_look_in_dp_and_marks_what_stays_in_base_px() -> void:
	var theme: Theme = HudThemes.source()
	assert_int(theme.get_font_size("font_size", "Button")).is_equal(18)
	assert_int(theme.get_font_size("font_size", "Label")).is_equal(16)
	assert_int(theme.get_font_size("font_size", "NumberLabel")).is_equal(20)
	assert_int(theme.get_font_size("font_size", "DevButton")).is_equal(DEV_FONT_PX)
	assert_str(str(theme.get_type_variation_base("DevButton"))).is_equal("Button")
	assert_str(str(theme.get_type_variation_base("NumberLabel"))).is_equal("Label")
	assert_str(str(theme.get_type_variation_base("SelectionPanel"))).is_equal("PanelContainer")
	assert_array(theme.get_meta(HudTheme.BASE_PX_META)).is_equal(["DevButton/font_sizes/font_size"])
	var backdrop: StyleBoxFlat = theme.get_stylebox("panel", "SelectionPanel")
	assert_that(backdrop.bg_color).is_equal(BACKDROP)
	for side: int in 4:
		assert_float(backdrop.get_content_margin(side)).is_equal(PAD_DP)
		assert_int(backdrop.get_corner_radius(side)).is_equal(8)
	assert_that(theme.get_color("fill", "BoxOverlay")).is_equal(FILL)
	assert_that(theme.get_color("outline", "BoxOverlay")).is_equal(OUTLINE)
	assert_that(theme.get_color("stroke", "BoxOverlay")).is_equal(STROKE)
	assert_str(theme.resource_path).is_equal(HudThemes.PATH)


## The dp step: font sizes, content margins and corner radii become px, an entry marked as base px
## and everything else (colours, variations) stays, and the source is not touched.
func test_the_dp_step_scales_the_theme_and_leaves_the_source_and_the_marked_entries() -> void:
	var source: Theme = HudThemes.source()
	var copy: Theme = HudTheme.scaled(source, 1.75)
	assert_int(copy.get_font_size("font_size", "Button")).is_equal(32)  # 31.5 rounds up.
	assert_int(copy.get_font_size("font_size", "Label")).is_equal(28)
	assert_int(copy.get_font_size("font_size", "NumberLabel")).is_equal(35)
	assert_int(copy.get_font_size("font_size", "DevButton")).is_equal(DEV_FONT_PX)  # Base px.
	var backdrop: StyleBoxFlat = copy.get_stylebox("panel", "SelectionPanel")
	var original: StyleBoxFlat = source.get_stylebox("panel", "SelectionPanel")
	assert_object(backdrop).is_not_same(original)
	for side: int in 4:
		assert_float(backdrop.get_content_margin(side)).is_equal_approx(14.0, 0.0001)
		assert_int(backdrop.get_corner_radius(side)).is_equal(14)
		assert_float(original.get_content_margin(side)).is_equal(PAD_DP)  # Not changed.
		assert_int(original.get_corner_radius(side)).is_equal(8)
	assert_int(source.get_font_size("font_size", "Button")).is_equal(18)
	assert_that(backdrop.bg_color).is_equal(BACKDROP)
	assert_that(copy.get_color("fill", "BoxOverlay")).is_equal(FILL)
	assert_str(str(copy.get_type_variation_base("DevButton"))).is_equal("Button")
	assert_object(copy.get_meta(HudTheme.SOURCE_META)).is_same(source)
	assert_array(copy.get_meta(HudTheme.BASE_PX_META)).is_equal(["DevButton/font_sizes/font_size"])
	var again: Theme = HudTheme.scaled(source, 1.0)  # From the source, so nothing compounds.
	assert_int(again.get_font_size("font_size", "Button")).is_equal(18)
	assert_float(again.get_stylebox("panel", "SelectionPanel").get_content_margin(0)).is_equal(8.0)


## "A restyle that adds a type or a variation edits no code": a theme with entries the HUD has not
## got is scaled by the same walk.
func test_the_dp_step_walks_every_type_variation_and_stylebox_of_a_theme() -> void:
	var theme: Theme = Theme.new()
	theme.default_font_size = 10
	theme.set_font_size("font_size", "Toast", 12)
	theme.set_type_variation("Warning", "Toast")
	theme.set_font_size("font_size", "Warning", 14)
	theme.set_font_size("title_size", "Warning", 30)
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.set_content_margin_all(4.0)
	flat.content_margin_top = -1.0  # Not set: stays not set.
	flat.set_corner_radius_all(6)
	theme.set_stylebox("panel", "Toast", flat)
	var line: StyleBoxEmpty = StyleBoxEmpty.new()  # Not a flat box: margins only.
	line.content_margin_left = 3.0
	theme.set_stylebox("normal", "Warning", line)
	var kept: StyleBoxFlat = StyleBoxFlat.new()
	kept.set_content_margin_all(5.0)
	theme.set_stylebox("hint", "Warning", kept)
	theme.set_meta(
		HudTheme.BASE_PX_META,
		PackedStringArray(["Warning/font_sizes/title_size", "Warning/styles/hint"])
	)
	var copy: Theme = HudTheme.scaled(theme, 2.0)
	assert_int(copy.default_font_size).is_equal(20)
	assert_int(copy.get_font_size("font_size", "Toast")).is_equal(24)
	assert_int(copy.get_font_size("font_size", "Warning")).is_equal(28)
	assert_int(copy.get_font_size("title_size", "Warning")).is_equal(30)  # Marked: base px.
	var box: StyleBoxFlat = copy.get_stylebox("panel", "Toast")
	assert_float(box.get_content_margin(SIDE_LEFT)).is_equal(8.0)
	assert_float(box.get_content_margin(SIDE_TOP)).is_equal(-1.0)
	assert_int(box.get_corner_radius(CORNER_BOTTOM_LEFT)).is_equal(12)
	assert_float(copy.get_stylebox("normal", "Warning").get_content_margin(SIDE_LEFT)).is_equal(6.0)
	assert_float(copy.get_stylebox("hint", "Warning").get_content_margin(SIDE_LEFT)).is_equal(5.0)
	assert_float(flat.get_content_margin(SIDE_LEFT)).is_equal(4.0)  # The source is as it was.
	assert_int(theme.default_font_size).is_equal(10)


## What the HUD resolves is what it was: the sizes of the code of main before P58, from the theme,
## with no override left, at the three screen sizes and at every profile of ui_profiles.gd.
func test_the_hud_resolves_the_values_it_had_before_at_the_three_screen_sizes() -> void:
	for size: Vector2i in MainSceneTests.TARGET_SIZES:
		await _open(size)
		_assert_hud_resolves(str(size))


func test_the_hud_resolves_the_values_it_had_before_at_every_profile() -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	for profile_name: StringName in profiles:
		await _open(profiles[profile_name].window_size, profiles[profile_name])
		_assert_hud_resolves(str(profile_name))


func test_a_resize_gives_the_hud_the_new_dp_values_before_its_scripts_read_them() -> void:
	await _open(Vector2i(1280, 720), UiProfiles.by_name(&"desktop"))
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
	_assert_hud_resolves("after a resize")
	assert_int(_hud("AllArmy").get_theme_font_size("font_size")).is_equal(roundi(18.0 * 1.75))
	# The panel fits the name to its text when the viewport changes size, in the same signal:
	# that reads the font size of the new theme only if HudTheme ran first.
	var title: Label = _hud("Name")
	var font_px: int = title.get_theme_font_size("font_size")
	var text_px: float = (
		title
		. get_theme_font("font")
		. get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px)
		. x
	)
	assert_int(font_px).is_equal(28)
	assert_float(title.custom_minimum_size.x).is_equal(ceilf(text_px))
	assert_bool(_main.get_node("Hud").get_child(0) is HudTheme).is_true()


func test_every_control_that_is_a_child_of_the_hud_has_the_hud_theme() -> void:
	await _open(Vector2i(1280, 720))
	var hud: Node = _main.get_node("Hud")
	assert_array(_without_hud_theme(hud)).is_empty()
	for root: Control in _roots(hud):
		assert_object(root.theme).is_not_null()
		assert_object(root.theme.get_meta(HudTheme.SOURCE_META)).is_not_null()  # A dp copy.
	(
		assert_array(_roots(hud).map(func(root: Control) -> String: return str(root.name)))
		. contains_exactly(["BoxOverlay", "SafeArea"])
	)
	assert_object(_roots(hud)[0].theme).is_same(_roots(hud)[1].theme)  # One copy for both.
	# The case fails on a HUD root added without the theme, or with a theme that is not the HUD's.
	var fixture: CanvasLayer = auto_free(CanvasLayer.new())
	for pair: Array in [["Bare", null], ["Foreign", Theme.new()], ["Themed", HudThemes.source()]]:
		var root: Control = Control.new()
		root.name = pair[0]
		root.theme = pair[1]
		fixture.add_child(root)
	fixture.add_child(Node2D.new())  # Not a Control: no theme needed.
	assert_array(_without_hud_theme(fixture)).is_equal(["Bare", "Foreign"])
	var scaled: Control = Control.new()  # A scaled copy counts, as HudTheme leaves it.
	scaled.theme = HudThemes.scaled()
	fixture.add_child(scaled)
	assert_array(_without_hud_theme(fixture)).is_equal(["Bare", "Foreign"])


func test_the_dp_step_gives_each_root_its_own_scaled_copy_and_leaves_what_has_no_theme() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1.75 px per dp.
	var first: Theme = Theme.new()
	first.set_font_size("font_size", "Label", 10)
	var second: Theme = Theme.new()
	second.set_font_size("font_size", "Label", 20)
	get_window().size = Vector2i(2400, 1080)  # The resize below must be a change.
	await await_idle_frame()
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	layer.add_child(HudTheme.new())
	var roots: Array[Control] = []
	for theme: Theme in [first, first, second, null]:
		var root: Control = Control.new()
		root.theme = theme
		layer.add_child(root)
		roots.append(root)
	add_child(layer)
	await await_idle_frame()
	assert_int(roots[0].theme.get_font_size("font_size", "Label")).is_equal(roundi(10 * 1.75))
	assert_object(roots[0].theme).is_same(roots[1].theme)  # The same source: one copy.
	assert_int(roots[2].theme.get_font_size("font_size", "Label")).is_equal(35)
	assert_object(roots[3].theme).is_null()
	assert_int(first.get_font_size("font_size", "Label")).is_equal(10)  # The sources stay in dp.
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # A resize starts from the source again.
	get_window().size = Vector2i(1280, 720)
	await await_idle_frame()
	assert_int(roots[0].theme.get_font_size("font_size", "Label")).is_equal(10)
	assert_int(roots[2].theme.get_font_size("font_size", "Label")).is_equal(20)


func test_the_box_overlay_draws_with_the_three_colours_of_its_theme_type() -> void:
	await _open(Vector2i(1280, 720))
	var box: BoxOverlay = _main.get_node("Hud/BoxOverlay")
	var colors: Dictionary[StringName, Color] = box.draw_colors()
	assert_array(colors.keys()).contains_exactly([&"fill", &"outline", &"stroke"])
	assert_that(colors[&"fill"]).is_equal(FILL)
	assert_that(colors[&"outline"]).is_equal(OUTLINE)
	assert_that(colors[&"stroke"]).is_equal(STROKE)
	# One place: a theme with other colours changes all three, and nothing else is read.
	var other: Theme = HudThemes.scaled()
	other.set_color("fill", "BoxOverlay", Color(0.1, 0.2, 0.3, 0.4))
	other.set_color("outline", "BoxOverlay", Color(0.5, 0.6, 0.7, 0.8))
	other.set_color("stroke", "BoxOverlay", Color(0.9, 0.8, 0.7, 0.6))
	box.theme = other
	colors = box.draw_colors()
	assert_that(colors[&"fill"]).is_equal(Color(0.1, 0.2, 0.3, 0.4))
	assert_that(colors[&"outline"]).is_equal(Color(0.5, 0.6, 0.7, 0.8))
	assert_that(colors[&"stroke"]).is_equal(Color(0.9, 0.8, 0.7, 0.6))
	# What it paints is read through the plan (tests/ui/test_box_overlay_plan.gd pins the shapes):
	# each shape's colour is one of the three new ones, in the order of the plan.
	box.show_anchor(Vector2(300, 200))
	box.show_rect(Rect2(300, 200, 100, 80))
	var painted: Array[Color] = []
	for step: BoxOverlay.Step in box.draw_plan():
		painted.append(colors[step.item])
	(
		assert_array(painted)
		. is_equal(
			[
				colors[&"fill"],
				colors[&"outline"],
				colors[&"stroke"],
				colors[&"fill"],
				colors[&"outline"],
				colors[&"stroke"],
			]
		)
	)
	await await_idle_frame()  # `_draw` plays the plan once.
	assert_bool(box.is_showing()).is_true()


## A restyle changes the theme only: the panel, the labels and the buttons follow, and no script
## holds a copy of the look.
func test_a_theme_with_another_look_restyles_the_whole_hud_from_the_file_alone() -> void:
	await _open(Vector2i(1280, 720))
	var other: Theme = HudThemes.scaled()
	var backdrop: StyleBoxFlat = other.get_stylebox("panel", "SelectionPanel")
	backdrop.bg_color = Color(0.9, 0.1, 0.1, 0.5)
	other.set_font_size("font_size", "Button", 31)
	other.set_font_size("font_size", "Label", 23)
	other.set_font_size("font_size", "NumberLabel", 27)
	for root: Control in _roots(_main.get_node("Hud")):
		root.theme = other
	var shown: StyleBoxFlat = _hud("SelectionPanel").get_theme_stylebox("panel")
	assert_that(shown.bg_color).is_equal(Color(0.9, 0.1, 0.1, 0.5))
	assert_int(_hud("Group2").get_theme_font_size("font_size")).is_equal(31)
	assert_int(_hud("Name").get_theme_font_size("font_size")).is_equal(23)
	assert_int(_hud("Count").get_theme_font_size("font_size")).is_equal(27)
	assert_int(_hud("Total").get_theme_font_size("font_size")).is_equal(27)
	assert_int(_hud("DevButton").get_theme_font_size("font_size")).is_equal(DEV_FONT_PX)  # Its own.


func test_the_override_check_sees_a_colour_font_size_or_style_and_lets_a_constant_pass() -> void:
	var button: Button = auto_free(Button.new())
	assert_array(_overrides(button)).is_empty()
	button.add_theme_constant_override("h_separation", 3)  # Layout, not look: allowed.
	assert_array(_overrides(button)).is_empty()
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.RED)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	assert_array(_overrides(button)).is_equal(
		[
			"theme_override_colors/font_color",
			"theme_override_font_sizes/font_size",
			"theme_override_styles/normal"
		]
	)


## The backdrop check compares every stored property of the box: an in-place write on any of them
## (a border, its colour, a shadow, an expand margin, a flag) differs from the theme's own box,
## and a box made the same way does not.
func test_the_backdrop_check_sees_an_in_place_write_on_any_stored_property() -> void:
	assert_array(_stored_differences(_scaled_backdrop(), _scaled_backdrop())).is_empty()
	var writes: Dictionary[String, Callable] = {
		"border_width_left": func(box: StyleBoxFlat) -> void: box.set_border_width_all(6),
		"border_color": func(box: StyleBoxFlat) -> void: box.border_color = Color.RED,
		"bg_color": func(box: StyleBoxFlat) -> void: box.bg_color.a = 0.5,
		"expand_margin_top": func(box: StyleBoxFlat) -> void: box.set_expand_margin_all(3.0),
		"shadow_size": func(box: StyleBoxFlat) -> void: box.shadow_size = 4,
		"corner_detail": func(box: StyleBoxFlat) -> void: box.corner_detail = 3,
		"corner_radius_top_left": func(box: StyleBoxFlat) -> void: box.set_corner_radius_all(1),
		"content_margin_left": func(box: StyleBoxFlat) -> void: box.content_margin_left = 1.0,
		"anti_aliasing": func(box: StyleBoxFlat) -> void: box.anti_aliasing = false,
		"draw_center": func(box: StyleBoxFlat) -> void: box.draw_center = false,
		"skew": func(box: StyleBoxFlat) -> void: box.skew = Vector2(0.1, 0.0),
	}
	for key: String in writes:
		var box: StyleBoxFlat = _scaled_backdrop()
		writes[key].call(box)
		(
			assert_array(_stored_differences(box, _scaled_backdrop()))
			. override_failure_message(key)
			. contains([key])
		)
	assert_array(_stored_differences(StyleBoxEmpty.new(), _scaled_backdrop())).is_equal(["class"])


## The Controls under `hud` resolve every font size and the panel's StyleBox as the theme says,
## which is what the code of main set before the theme existed (the numbers at the top).
func _assert_hud_resolves(why: String) -> void:
	var hud: Node = _main.get_node("Hud")
	var theme: Theme = (hud.get_node("SafeArea") as Control).theme
	for node_name: String in ["AllArmy", "Group1", "Group2", "Group3"]:
		var font_px: int = _hud(node_name).get_theme_font_size("font_size")
		var where: String = "%s %s" % [why, node_name]
		assert_int(font_px).override_failure_message(where).is_equal(_px(ARMY_FONT_DP))
		assert_int(font_px).is_equal(theme.get_font_size("font_size", "Button"))
	var dev: Button = _hud("DevButton")
	assert_int(dev.get_theme_font_size("font_size")).override_failure_message(why).is_equal(
		DEV_FONT_PX
	)
	assert_int(dev.get_theme_font_size("font_size")).is_equal(
		theme.get_font_size("font_size", "DevButton")
	)
	var sizes: Array[int] = []
	for node_name: String in ["Name", "Count", "Total"]:
		sizes.append(_hud(node_name).get_theme_font_size("font_size"))
	var pinned: Array[int] = [_px(NAME_FONT_DP), _px(NUMBER_FONT_DP), _px(NUMBER_FONT_DP)]
	assert_array(sizes).override_failure_message(why).is_equal(pinned)
	var panel: SelectionPanel = _hud("SelectionPanel")
	var backdrop: StyleBoxFlat = panel.get_theme_stylebox("panel")
	assert_object(backdrop).override_failure_message(why).is_same(
		theme.get_stylebox("panel", "SelectionPanel")
	)
	assert_that(backdrop.bg_color).override_failure_message(why).is_equal(BACKDROP)
	for side: int in 4:
		(
			assert_float(backdrop.get_content_margin(side))
			. override_failure_message(why)
			. is_equal_approx(UiScale.dp(PAD_DP), 0.0001)
		)
		assert_int(backdrop.get_corner_radius(side)).override_failure_message(why).is_equal(
			_px(PAD_DP)
		)
	# Every stored property, not the few above: the HUD shares this box with every script that gets
	# it from get_theme_stylebox, so a write in place on it changes the look outside the theme.
	var differing: Array[String] = _stored_differences(backdrop, _scaled_backdrop())
	(
		assert_array(differing)
		. override_failure_message(
			"%s: the backdrop differs from the theme's own in %s" % [why, differing]
		)
		. is_empty()
	)
	var box: BoxOverlay = _main.get_node("Hud/BoxOverlay")
	assert_that(box.draw_colors()[&"fill"]).override_failure_message(why).is_equal(FILL)
	assert_that(box.draw_colors()[&"outline"]).is_equal(OUTLINE)
	assert_that(box.draw_colors()[&"stroke"]).is_equal(STROKE)
	var overrides: Array[String] = []
	for control: Control in hud.find_children("*", "Control", true, false):
		for override: String in _overrides(control):
			overrides.append("%s: %s" % [control.get_path(), override])
	assert_array(overrides).override_failure_message(why).is_empty()
	assert_array(_without_hud_theme(hud)).override_failure_message(why).is_empty()


## The theme's own backdrop in base px at the current dp factor, made again from the file (not
## from the resource cache, which a write in place would reach too): what the HUD roots hold.
func _scaled_backdrop() -> StyleBoxFlat:
	var scaled: Theme = HudTheme.scaled(HudThemes.pristine(), UiScale.base_px_per_dp())
	return scaled.get_stylebox("panel", "SelectionPanel") as StyleBoxFlat


## The names of the stored properties in which `shown` is not `expected`, or "class" alone when
## they are of two classes.
func _stored_differences(shown: Resource, expected: Resource) -> Array[String]:
	var differing: Array[String] = []
	if shown.get_class() != expected.get_class():
		differing.append("class")
		return differing
	for property: Dictionary in expected.get_property_list():
		var key: String = property["name"]
		var stored: bool = ((property["usage"] as int) & PROPERTY_USAGE_STORAGE) != 0
		if stored and shown.get(key) != expected.get(key):
			differing.append(key)
	return differing


## The theme overrides of `control` that are a colour, a font, a font size or a StyleBox, as the
## names of the properties that the scene file would store. A constant is layout and is allowed.
func _overrides(control: Control) -> Array[String]:
	var found: Array[String] = []
	for property: Dictionary in control.get_property_list():
		var key: String = property["name"]
		var stored: bool = ((property["usage"] as int) & PROPERTY_USAGE_STORAGE) != 0
		if stored and key.begins_with("theme_override_") and not key.contains("_constants/"):
			found.append(key)
	return found


## The names of the Controls that are direct children of `hud` without the HUD theme: none at all,
## or a theme that is not `theme.tres` or a scaled copy of it (HudTheme.SOURCE_META).
func _without_hud_theme(hud: Node) -> Array[String]:
	var missing: Array[String] = []
	for root: Control in _roots(hud):
		var source: Theme = null
		if root.theme != null:
			source = root.theme.get_meta(HudTheme.SOURCE_META, root.theme)
		if source == null or source.resource_path != HudThemes.PATH:
			missing.append(str(root.name))
	return missing


func _roots(hud: Node) -> Array[Control]:
	var roots: Array[Control] = []
	for child: Node in hud.get_children():
		if child is Control:
			roots.append(child)
	return roots


func _hud(node_name: String) -> Control:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _px(dp: float) -> int:
	return roundi(UiScale.dp(dp))


## A new main scene with all 30 tanks selected, so that the panel shows its row. `metrics` is the
## UiScale override (a profile); without it the engine's own numbers count, as in test_main_scene.
func _open(size: Vector2i, metrics: UiMetrics = null) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	var controller: PlayerController = _main.get_node("PlayerController")
	controller.command_sink = func(_command: Command) -> void: pass
	controller.selection.set_ids(PackedInt32Array(range(1, 31)))
	await await_idle_frame()
