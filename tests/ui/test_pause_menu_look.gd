extends GdUnitTestSuite
## The look of the pause menu (plan P124b, Michael's design of 2026-11-05): one column of buttons in
## the design's order and looks, the Vibration chip, the objective line, and the foot left free for
## Phase 5's banner ad. The fit at every size is test_pause_menu's.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5
const BANNER_DP: float = 50.0 + 16.0  ## The foot kept free for Phase 5's banner ad.

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
	var looks: Array[String] = []
	var xs: Array[float] = []
	var body: Node = _menu().find_child("Body", true, false)
	for node: Node in _menu().find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.is_visible_in_tree() and body.is_ancestor_of(button):
			names.append(str(button.name))
			looks.append(str(button.theme_type_variation))
			xs.append(button.get_global_rect().position.x)
	var want: Array[String] = ["ResumeButton", "RestartButton", "SurrenderButton", "ExitButton"]
	if DevRoutes.is_enabled():
		want.append("DevMenuButton")
	assert_array(names.slice(0, want.size())).is_equal(want)
	assert_str(names[names.size() - 1]).is_equal("VibrationButton")
	assert_str(_button("ResumeButton").theme_type_variation).is_equal("PausePrimary")
	assert_str(_button("SurrenderButton").theme_type_variation).is_equal("PauseDanger")
	for name: String in ["RestartButton", "ExitButton"]:
		assert_str(_button(name).theme_type_variation).is_equal("PauseButton")
	if DevRoutes.is_enabled():
		assert_str(_button("DevMenuButton").theme_type_variation).is_equal("PauseButton")
	assert_array(looks).is_not_empty()
	for x: float in xs.slice(0, want.size()):
		assert_float(x).is_equal_approx(xs[0], 0.5)  # One column, one left edge.
	# Sound, Music and Settings stay hidden until Phase 5.
	for gone: String in ["SettingsButton", "SoundButton", "MusicButton"]:
		assert_object(_menu().find_child(gone, true, false)).is_null()


## The vibration chip is the accent's while on and muted with the word OFF while off.
func test_the_vibration_chip_dims_when_off() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open_menu()
	assert_str(_button("VibrationButton").theme_type_variation).is_equal("PauseChip")
	_button("VibrationButton").pressed.emit()
	assert_str(_button("VibrationButton").theme_type_variation).is_equal("PauseChipOff")
	assert_str(_button("VibrationButton").text).contains("OFF")
	_button("VibrationButton").pressed.emit()
	assert_str(_button("VibrationButton").theme_type_variation).is_equal("PauseChip")


## Upright, the foot stays free for Phase 5's banner ad: the last control ends at least 50 dp
## plus 16 dp above the safe rect's bottom, without a scroll, on the phone browser held upright.
## The card shows the goal as one open checklist line; no ad code is in the menu.
func test_the_foot_stays_free_for_the_banner_upright() -> void:
	var profile: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	await _open_menu()
	await await_idle_frame()
	var safe: Rect2 = UiScale.safe_rect_base()
	var last: Control = _button("VibrationButton")
	var gap: float = safe.end.y - last.get_global_rect().end.y
	assert_float(gap).override_failure_message("gap %s px" % gap).is_greater_equal(
		UiScale.dp(BANNER_DP) - TOLERANCE_PX
	)
	assert_object(_menu().find_child("ObjectiveCircle", true, false)).is_not_null()
	assert_object(_menu().find_child("*Ad*", true, false)).is_null()


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
