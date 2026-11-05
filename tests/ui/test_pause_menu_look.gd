extends GdUnitTestSuite
## The look of the pause menu (plan P124b, Michael's design of 2026-11-05): one column of buttons in
## the design's order and looks, the Vibration chip, the objective line, and the foot left free for
## a later ad. The fit at every size is test_pause_menu's.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5
const FOOT_DP: float = 50.0 + 16.0  ## The foot kept free, as the design draws it.
const GLYPH_DP: float = 24.0

var _window_size_before: Vector2i
var _main: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


## The buttons stand in one column in the design's order, Developer menu (a debug build) after Exit
## and the Vibration chip last; Resume is the primary look, Surrender the danger look, the rest
## the secondary look.
func test_the_buttons_are_one_column_in_order_with_their_looks() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open_menu()
	var names: Array[String] = []
	var body: Control = _menu().find_child("Body", true, false) as Control
	var column: Control = _button("ResumeButton").get_parent() as Control
	for node: Node in _menu().find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.is_visible_in_tree() and body.is_ancestor_of(button):
			names.append(str(button.name))
			var rect: Rect2 = button.get_global_rect()
			if button.name != &"VibrationButton":  # The chip is as wide as its words.
				var column_rect: Rect2 = column.get_global_rect()
				assert_float(rect.position.x).is_equal_approx(column_rect.position.x, 0.5)
				assert_float(rect.end.x).is_equal_approx(column_rect.end.x, 0.5)
			assert_object(button.icon).override_failure_message(button.name).is_not_null()
			assert_int(button.get_theme_constant(&"icon_max_width")).is_greater_equal(
				roundi(UiScale.dp(GLYPH_DP))
			)
	var want: Array[String] = ["ResumeButton", "RestartButton", "SurrenderButton", "ExitButton"]
	if DevRoutes.is_enabled():
		want.append("DevMenuButton")
	want.append("VibrationButton")
	assert_array(names).is_equal(want)
	assert_str(_button("SurrenderButton").theme_type_variation).is_equal("PauseDanger")
	for name: String in ["RestartButton", "ExitButton"]:
		assert_str(_button(name).theme_type_variation).is_equal("PauseButton")
	if DevRoutes.is_enabled():
		assert_str(_button("DevMenuButton").theme_type_variation).is_equal("PauseButton")
	# Sound, Music and Settings stay hidden until Phase 5.
	for gone: String in ["SettingsButton", "SoundButton", "MusicButton"]:
		assert_object(_menu().find_child(gone, true, false)).is_null()


## The vibration chip is the accent's while on and muted with the word OFF while off.
func test_the_vibration_chip_dims_when_off() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open_menu()
	var on_look: String = _button("VibrationButton").theme_type_variation
	assert_str(on_look).starts_with("PauseChip")
	assert_str(on_look).is_not_equal("PauseChipOff")
	_button("VibrationButton").pressed.emit()
	assert_str(_button("VibrationButton").theme_type_variation).is_equal("PauseChipOff")
	assert_str(_button("VibrationButton").text).contains("OFF")
	_button("VibrationButton").pressed.emit()
	assert_str(_button("VibrationButton").theme_type_variation).is_equal(on_look)


## Upright, the foot stays free: the menu's content (Body, with the Developer menu in a debug
## build) ends at least 50 dp plus 16 dp above the safe rect's bottom, without a scroll, at every
## portrait size. The card shows the goal as one open checklist line; no ad is in the menu.
func test_the_foot_stays_free_upright() -> void:
	assert_bool(DevRoutes.is_enabled()).is_true()  # The tallest menu is the one measured.
	var profiles: Array[UiMetrics] = []
	profiles.assign(UiProfiles.portrait().values())
	profiles.append(UiProfiles.by_name(&"notch_design_portrait"))
	for profile: UiMetrics in profiles:
		UiScale.set_override(profile)
		get_window().size = profile.window_size
		await await_idle_frame()
		await _open_menu()
		await await_idle_frame()
		var safe: Rect2 = UiScale.safe_rect_base()
		var body: Control = _menu().find_child("Body", true, false) as Control
		assert_object(_button("DevMenuButton")).is_not_null()
		var gap: float = safe.end.y - body.get_global_rect().end.y
		(
			assert_float(gap)
			. override_failure_message("%s: %s px" % [profile.window_size, gap])
			. is_greater_equal(UiScale.dp(FOOT_DP) - TOLERANCE_PX)
		)
		assert_object(_menu().find_child("ObjectiveCircle", true, false)).is_not_null()
		assert_object(_menu().find_child("*Ad*", true, false)).is_null()
		_main.free()
		await await_idle_frame()


## The HUD's controls are gone while PAUSE shows (the pill, the scope, the group column, BUILD, the
## command bar) and are back after Resume; the menu itself stays.
func test_the_hud_is_hidden_under_the_menu_and_back_after_resume() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	var names: Array[String] = [
		"EconomyPill", "RadarScope", "GroupColumn", "BuildButton", "CommandBar"
	]
	for node_name: String in names:
		assert_float(_hud(node_name).modulate.a).override_failure_message(node_name).is_equal(1.0)
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await await_idle_frame()
	for node_name: String in names:
		assert_float(_hud(node_name).modulate.a).override_failure_message(node_name).is_equal(0.0)
	assert_bool(_menu().visible).is_true()
	assert_float(_menu().modulate.a).is_equal(1.0)
	_button("ResumeButton").pressed.emit()
	await await_idle_frame()
	for node_name: String in names:
		assert_float(_hud(node_name).modulate.a).override_failure_message(node_name).is_equal(1.0)


func _hud(node_name: String) -> Control:
	return _main.get_node("Hud/" + node_name) as Control


## The Derrick League's player sees its own emblem and the orange; the Lumen Accord's the cyan.
func test_the_derrick_route_wears_the_fossil_emblem_and_accent() -> void:
	await _check_side(MatchRig.DERRICK, "fossil", &"AccentFossil", "Fossil")


func test_the_lumen_route_wears_the_renew_emblem_and_accent() -> void:
	await _check_side(MatchRig.LUMEN, "renew", &"AccentRenew", "")


## The card of `route` in landscape: the badge's picture is `emblem_<id>.svg`, and Resume's fill,
## the badge's ring and the ON chip are that side's accent (the type's values, not a copy).
func _check_side(route: String, id: String, accent: StringName, suffix: String) -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self, route))
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await await_idle_frame()
	var snap: MatchSnapshot = (_main.get_node("MatchRunner") as MatchRunner).snapshot
	var own: String = ""  # The first row of player 1 names the side, from the snapshot's own ids.
	for row: int in snap.unit_id.size():
		if snap.owner[row] == 1:
			own = snap.faction_ids[snap.type_faction[snap.type_index[row]]]
			break
	assert_str(own).is_equal(id)
	var badge: PanelContainer = _menu().find_child("Badge", true, false) as PanelContainer
	assert_str(badge.theme_type_variation).is_equal("PauseBadge" + suffix)
	var emblem: TextureRect = badge.find_child("Emblem", false, false) as TextureRect
	assert_str(emblem.texture.resource_path).is_equal(PauseMenu.EMBLEM_ART % id)
	assert_str(_button("ResumeButton").theme_type_variation).is_equal("PausePrimary" + suffix)
	assert_str(_button("VibrationButton").theme_type_variation).is_equal("PauseChip" + suffix)
	var fill: StyleBoxFlat = _button("ResumeButton").get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_object(fill.bg_color).is_equal(_menu().get_theme_color(&"accent", accent))
	var ring: StyleBoxFlat = badge.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_object(ring.border_color).is_equal(_menu().get_theme_color(&"accent", accent))
	var resume: Button = _button("ResumeButton")
	assert_object(resume.get_theme_color(&"font_color")).is_equal(
		_menu().get_theme_color(&"on_accent", accent)
	)
	assert_object(_button("VibrationButton").get_theme_color(&"font_color")).is_equal(
		_menu().get_theme_color(&"light", accent)
	)
	assert_object(_button("SurrenderButton").get_theme_color(&"font_color")).is_equal(
		_menu().get_theme_color(&"danger", &"HudTokens")
	)


## A main scene with the pause menu open.
func _open_menu() -> void:
	_main = auto_free(await MatchRig.open(self))
	(_main.get_node("PlayerController") as PlayerController).command_sink = func(
		_command: Command
	) -> void:
		pass
	_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	await await_idle_frame()
	await await_idle_frame()


func _menu() -> PauseMenu:
	return _main.get_node("Hud/PauseMenu") as PauseMenu


func _button(button_name: String) -> Button:
	return _menu().find_child(button_name, true, false) as Button
