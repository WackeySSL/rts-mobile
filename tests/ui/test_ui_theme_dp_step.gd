extends GdUnitTestSuite
## The dp step of the HUD's Theme (HudTheme, plan row P58, fix round 1). A HUD root added to the
## Hud after the scene has loaded gets the dp copy as it enters, and every size that a StyleBox
## can carry and that a restyle may add (border widths, expand margins, shadows, a line's
## thickness) is scaled with the font sizes, the content margins and the corner radii.

const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


## The Phase 5 rule (a menu root sets the theme file on itself) holds for a root that is added
## while the game runs, not only for the roots of the scene: the copy is there before the root's
## own children enter the tree, with no frame between.
func test_a_root_added_to_the_hud_later_gets_the_dp_copy_as_it_enters() -> void:
	var main: Node = await _open_main(&"android_6in")  # 1.75 px per dp.
	var hud: Node = main.get_node("Hud")
	var late: Control = Control.new()
	late.name = "LateMenu"
	late.theme = HudThemes.source()
	var label: Label = Label.new()
	var number: Label = Label.new()
	number.theme_type_variation = &"NumberLabel"
	var button: Button = Button.new()
	var dev: Button = Button.new()
	dev.theme_type_variation = &"DevButton"
	for child: Control in [label, number, button, dev]:
		late.add_child(child)
	hud.add_child(late)
	assert_int(button.get_theme_font_size("font_size")).is_equal(32)  # 18 dp.
	assert_int(label.get_theme_font_size("font_size")).is_equal(28)  # 16 dp.
	assert_int(number.get_theme_font_size("font_size")).is_equal(35)  # 20 dp.
	assert_int(dev.get_theme_font_size("font_size")).is_equal(40)  # Base px, as the theme marks.
	var safe_area: Control = hud.get_node("SafeArea")
	assert_object(late.theme).is_same(safe_area.theme)  # One copy per source.
	assert_object(late.theme.get_meta(HudTheme.SOURCE_META)).is_same(HudThemes.source())
	await await_idle_frame()
	assert_int(button.get_theme_font_size("font_size")).is_equal(32)
	assert_object(late.theme).is_same(safe_area.theme)


## A root added later is one of the roots from then on: a resize rescales it with the others.
func test_a_root_added_later_follows_the_next_resize() -> void:
	var main: Node = await _open_main(&"desktop")
	var hud: Node = main.get_node("Hud")
	var late: Control = Control.new()
	late.theme = HudThemes.source()
	var button: Button = Button.new()
	late.add_child(button)
	hud.add_child(late)
	assert_int(button.get_theme_font_size("font_size")).is_equal(18)  # 1.0 px per dp.
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
	assert_int(button.get_theme_font_size("font_size")).is_equal(32)
	assert_object(late.theme).is_same((hud.get_node("SafeArea") as Control).theme)


## A portrait profile gets the sizes of its landscape twin (ADR 0015 section 2: one device, one dp),
## and web_phone_portrait, a phone browser held upright, has 2.0 base px per dp. The window is
## portrait, so the stretch the profile names is the one the engine has with the turned base size.
func test_the_dp_step_at_a_portrait_profile_gives_the_font_sizes_of_its_landscape_twin() -> void:
	var cases: Array[Array] = [
		[&"android_6in_portrait", &"android_6in", 32],  # 18 dp at 1.75 px per dp.
		[&"web_tablet_portrait", &"web_tablet", 23],  # 22.5 px, rounded.
		[&"desktop_portrait", &"desktop", 18],
		[&"web_phone_portrait", &"", 36],  # 2.0 px per dp.
	]
	for case: Array in cases:
		var main: Node = await _open_main(case[0])
		var size: int = (
			(main.get_node("Hud/SafeArea/ArmyBand/ArmyBar/AllArmy") as Button)
			. get_theme_font_size("font_size")
		)
		assert_int(size).override_failure_message(str(case[0])).is_equal(case[2])
		main.get_parent().remove_child(main)
		main.free()
		if case[1] != &"":
			main = await _open_main(case[1])
			var twin_size: int = (
				(main.get_node("Hud/SafeArea/ArmyBand/ArmyBar/AllArmy") as Button)
				. get_theme_font_size("font_size")
			)
			assert_int(twin_size).override_failure_message(str(case[1])).is_equal(case[2])
			main.get_parent().remove_child(main)
			main.free()


## What the step has nothing to scale it for stays as it was: no theme, no Control, a theme that
## is not the HUD's (it is scaled like any other; the check of the roots names it).
func test_a_late_node_without_a_theme_or_a_control_is_left_alone() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	layer.add_child(HudTheme.new())
	add_child(layer)
	await await_idle_frame()
	var bare: Control = Control.new()
	var foreign: Control = Control.new()
	var other: Theme = Theme.new()
	other.set_font_size("font_size", "Label", 10)
	foreign.theme = other
	layer.add_child(bare)
	layer.add_child(foreign)
	layer.add_child(Node2D.new())
	assert_object(bare.theme).is_null()
	assert_int(foreign.theme.get_font_size("font_size", "Label")).is_equal(roundi(10 * 1.75))
	assert_int(other.get_font_size("font_size", "Label")).is_equal(10)  # The source stays in dp.


## Every size a StyleBox carries in px is scaled, whatever the class, by the same walk. The
## texture margins of a StyleBoxTexture cut the picture and stay in texture px.
func test_the_dp_step_scales_every_size_a_stylebox_can_carry() -> void:
	var theme: Theme = Theme.new()
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.border_width_left = 1
	flat.border_width_top = 2
	flat.border_width_right = 3
	flat.border_width_bottom = 4
	flat.expand_margin_left = 1.0
	flat.expand_margin_top = 2.0
	flat.expand_margin_right = 3.0
	flat.expand_margin_bottom = 4.0
	flat.shadow_size = 3
	flat.shadow_offset = Vector2(2.0, -4.0)
	flat.set_corner_radius_all(5)
	flat.set_content_margin_all(6.0)
	flat.bg_color = Color(0.2, 0.4, 0.6, 0.8)
	flat.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	flat.border_color = Color(1.0, 0.0, 0.0, 1.0)
	theme.set_stylebox("panel", "Window", flat)
	var texture: StyleBoxTexture = StyleBoxTexture.new()
	texture.set_texture_margin_all(10.0)
	texture.set_expand_margin_all(2.0)
	texture.set_content_margin(SIDE_TOP, 3.0)
	theme.set_stylebox("normal", "Button", texture)
	var line: StyleBoxLine = StyleBoxLine.new()
	line.thickness = 3
	line.grow_begin = -2.0
	line.grow_end = 4.0
	line.color = Color(0.5, 0.5, 0.5, 1.0)
	theme.set_stylebox("separator", "HSeparator", line)
	var copy: Theme = HudTheme.scaled(theme, 2.0)
	var box: StyleBoxFlat = copy.get_stylebox("panel", "Window")
	assert_array([box.border_width_left, box.border_width_top]).is_equal([2, 4])
	assert_array([box.border_width_right, box.border_width_bottom]).is_equal([6, 8])
	assert_array([box.expand_margin_left, box.expand_margin_top]).is_equal([2.0, 4.0])
	assert_array([box.expand_margin_right, box.expand_margin_bottom]).is_equal([6.0, 8.0])
	assert_int(box.shadow_size).is_equal(6)
	assert_that(box.shadow_offset).is_equal(Vector2(4.0, -8.0))
	assert_int(box.get_corner_radius(CORNER_TOP_LEFT)).is_equal(10)
	assert_float(box.get_content_margin(SIDE_LEFT)).is_equal(12.0)
	assert_that(box.bg_color).is_equal(Color(0.2, 0.4, 0.6, 0.8))  # Colours are not sizes.
	assert_that(box.shadow_color).is_equal(Color(0.0, 0.0, 0.0, 0.5))
	assert_that(box.border_color).is_equal(Color(1.0, 0.0, 0.0, 1.0))
	var picture: StyleBoxTexture = copy.get_stylebox("normal", "Button")
	assert_float(picture.get_texture_margin(SIDE_LEFT)).is_equal(10.0)  # Texture px: not scaled.
	assert_float(picture.get_expand_margin(SIDE_RIGHT)).is_equal(4.0)
	assert_float(picture.get_content_margin(SIDE_TOP)).is_equal(6.0)
	assert_float(picture.get_content_margin(SIDE_LEFT)).is_equal(-1.0)  # Not set: stays so.
	var rule: StyleBoxLine = copy.get_stylebox("separator", "HSeparator")
	assert_int(rule.thickness).is_equal(6)
	assert_float(rule.grow_begin).is_equal(-4.0)
	assert_float(rule.grow_end).is_equal(8.0)
	assert_that(rule.color).is_equal(Color(0.5, 0.5, 0.5, 1.0))
	# The source is as it was.
	assert_int(flat.border_width_left).is_equal(1)
	assert_int(flat.shadow_size).is_equal(3)
	assert_that(flat.shadow_offset).is_equal(Vector2(2.0, -4.0))
	assert_int(line.thickness).is_equal(3)
	assert_float(line.grow_begin).is_equal(-2.0)


## A whole-number size is whole px after the step, rounded like a font size or a corner radius:
## 2 dp at 1.75 px per dp is 3.5, which is 4 px, and 3 dp is 5.25, which is 5 px.
func test_a_whole_number_stylebox_size_is_rounded_to_whole_px() -> void:
	var theme: Theme = Theme.new()
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.border_width_left = 2
	flat.border_width_top = 3
	flat.shadow_size = 2
	flat.set_corner_radius_all(2)
	theme.set_stylebox("panel", "Window", flat)
	var line: StyleBoxLine = StyleBoxLine.new()
	line.thickness = 2
	theme.set_stylebox("separator", "HSeparator", line)
	var copy: Theme = HudTheme.scaled(theme, 1.75)
	var box: StyleBoxFlat = copy.get_stylebox("panel", "Window")
	assert_array([box.border_width_left, box.border_width_top]).is_equal([4, 5])
	assert_int(box.shadow_size).is_equal(4)
	assert_int(box.get_corner_radius(CORNER_TOP_RIGHT)).is_equal(4)
	assert_int((copy.get_stylebox("separator", "HSeparator") as StyleBoxLine).thickness).is_equal(4)


## A StyleBox property that is not a size in px stays as it is: a shear ratio draws the same angle
## on every screen (scaled, a `skew` of 0.25 was 0.17 at 0.667 px per dp and 0.33 at 1.333), a count
## is a count, and the soft edge of a shape is a sharpness setting, 1 px at any scale.
func test_the_dp_step_keeps_the_stylebox_properties_that_are_not_sizes() -> void:
	var theme: Theme = Theme.new()
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.skew = Vector2(0.25, -0.125)
	flat.corner_detail = 5
	flat.anti_aliasing_size = 1.5
	flat.anti_aliasing = false
	flat.draw_center = false
	flat.border_blend = true
	flat.set_corner_radius_all(4)  # A size next to them: this one is scaled.
	theme.set_stylebox("panel", "Window", flat)
	for px_per_dp: float in [0.667, 1.0, 1.75, 2.0]:
		var box: StyleBoxFlat = HudTheme.scaled(theme, px_per_dp).get_stylebox("panel", "Window")
		var why: String = "at %s px per dp" % px_per_dp
		assert_that(box.skew).override_failure_message(why).is_equal(Vector2(0.25, -0.125))
		assert_int(box.corner_detail).override_failure_message(why).is_equal(5)
		assert_float(box.anti_aliasing_size).override_failure_message(why).is_equal(1.5)
		assert_bool(box.anti_aliasing).override_failure_message(why).is_false()
		assert_bool(box.draw_center).override_failure_message(why).is_false()
		assert_bool(box.border_blend).override_failure_message(why).is_true()
		assert_int(box.get_corner_radius(CORNER_TOP_LEFT)).is_equal(roundi(4 * px_per_dp))


## The step turns sizes into px and writes no colour, font, icon or constant: they come out as they
## went in, and no entry is added or dropped. The scan cannot see a write through a variable, so
## this is the case that sees one in `scaled()`.
func test_the_dp_step_keeps_every_colour_font_icon_and_constant_of_the_source() -> void:
	var theme: Theme = Theme.new()
	var font: Font = auto_free(FontVariation.new())
	var other_font: Font = auto_free(SystemFont.new())
	var icon: Texture2D = auto_free(PlaceholderTexture2D.new())
	theme.default_font = font
	theme.set_color("font_color", "Label", Color(0.1, 0.2, 0.3, 0.4))
	theme.set_color("font_outline_color", "Label", Color(0.4, 0.3, 0.2, 0.1))
	theme.set_color("fill", "BoxOverlay", Color(0.5, 0.6, 0.7, 0.8))
	theme.set_color("outline", "BoxOverlay", Color(0.9, 0.8, 0.7, 0.6))
	theme.set_font("font", "Label", other_font)
	theme.set_font("font", "Button", font)
	theme.set_icon("icon", "Button", icon)
	theme.set_constant("separation", "HBoxContainer", 7)
	theme.set_constant("outline_size", "Label", 3)
	theme.set_font_size("font_size", "Label", 10)  # The one thing here that is a size.
	var copy: Theme = HudTheme.scaled(theme, 2.0)
	assert_int(copy.get_font_size("font_size", "Label")).is_equal(20)
	assert_object(copy.default_font).is_same(font)
	assert_array(copy.get_type_list()).contains_exactly_in_any_order(theme.get_type_list())
	for type: String in theme.get_type_list():
		var at: String = "type %s" % type
		(
			assert_array(copy.get_color_list(type))
			. override_failure_message(at)
			. contains_exactly_in_any_order(theme.get_color_list(type))
		)
		(
			assert_array(copy.get_font_list(type))
			. override_failure_message(at)
			. contains_exactly_in_any_order(theme.get_font_list(type))
		)
		(
			assert_array(copy.get_icon_list(type))
			. override_failure_message(at)
			. contains_exactly_in_any_order(theme.get_icon_list(type))
		)
		(
			assert_array(copy.get_constant_list(type))
			. override_failure_message(at)
			. contains_exactly_in_any_order(theme.get_constant_list(type))
		)
		for item: String in theme.get_color_list(type):
			assert_that(copy.get_color(item, type)).is_equal(theme.get_color(item, type))
		for item: String in theme.get_font_list(type):
			assert_object(copy.get_font(item, type)).is_same(theme.get_font(item, type))
		for item: String in theme.get_icon_list(type):
			assert_object(copy.get_icon(item, type)).is_same(theme.get_icon(item, type))
		for item: String in theme.get_constant_list(type):
			assert_int(copy.get_constant(item, type)).is_equal(theme.get_constant(item, type))
	assert_int(copy.get_constant("separation", "HBoxContainer")).is_equal(7)  # Not scaled.
	assert_object(copy.get_font("font", "Label")).is_same(other_font)


## An entry marked as base px keeps all of its sizes, not only its margins.
func test_a_stylebox_marked_as_base_px_keeps_its_border_and_shadow() -> void:
	var theme: Theme = Theme.new()
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.set_border_width_all(3)
	flat.shadow_size = 5
	flat.set_content_margin_all(4.0)
	theme.set_stylebox("panel", "Window", flat)
	theme.set_meta(HudTheme.BASE_PX_META, PackedStringArray(["Window/styles/panel"]))
	var box: StyleBoxFlat = HudTheme.scaled(theme, 2.0).get_stylebox("panel", "Window")
	assert_int(box.border_width_left).is_equal(3)
	assert_int(box.shadow_size).is_equal(5)
	assert_float(box.get_content_margin(SIDE_LEFT)).is_equal(4.0)


## A main scene at a profile, with the HUD as it comes out of main.tscn.
func _open_main(profile: StringName) -> Node:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	var main: Node = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	add_child(main)
	await await_idle_frame()
	return main
