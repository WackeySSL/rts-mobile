extends GdUnitTestSuite
## The pause menu's Phase 5 behaviour (plan P531, ADR 0043 sections 6 and 8, ADR 0042 section 5):
## the Sound and Music chips set the AudioService steps, How to play opens P527's screen over the
## battle and Back returns to the menu (no banner under it), Settings follows the `settings`
## route, Exit, Restart and Surrender go through MenuFlow when it owns the match (a fake here), the
## app pause and focus out open the menu, Back toggles it, a lesson's Leave tutorial calls no ad
## method (a real MenuFlow with fake ads), and the controls fit at the six sizes of ADR 0015.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"


class FakeFlow:
	extends Node
	var runner: MatchRunner = null
	var setup: MatchSetup = null
	var calls: Array[String] = []

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return setup

	func mark_surrendered() -> void:
		calls.append("mark_surrendered")

	func restart() -> Error:
		calls.append("restart")
		return OK

	func return_to_menu(_screen: StringName = &"") -> void:
		calls.append("return_to_menu")

	func leave_match(_screen: StringName = &"") -> void:
		calls.append("leave_match")


class FakeAds:
	extends Node
	var calls: int = 0

	func take_start_credits_bonus() -> int:
		calls += 1
		return 0

	func note_match_completed(_seconds: int) -> void:
		calls += 1

	func maybe_show_interstitial(_placement: StringName) -> bool:
		calls += 1
		return false


var _window_size_before: Vector2i
var _main: Node
var _menu: PauseMenu
var _state: HudState
var _flow: FakeFlow
var _sound_before: int
var _music_before: int
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_sound_before = AudioService.get_step(AudioService.BUS_SFX)
	_music_before = AudioService.get_step(AudioService.BUS_MUSIC)
	_sent.clear()


func after_test() -> void:
	AudioService.set_sound_step(_sound_before)
	AudioService.set_step(AudioService.BUS_MUSIC, _music_before)
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func _open_main() -> void:
	_main = auto_free(await MatchRig.open(self))
	_menu = _main.get_node("Hud/PauseMenu")
	_state = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	_flow = auto_free(FakeFlow.new())
	add_child(_flow)
	_flow.runner = _main.get_node("MatchRunner")
	_menu.menu_flow = _flow
	var controller: PlayerController = _menu.controller
	controller.command_sink = func(command: Command) -> void:
		_flow.calls.append("command")
		_sent.append(command)


func _press(button_name: StringName) -> void:
	(_menu.find_child(button_name, true, false) as Button).pressed.emit()


func _text(button_name: StringName) -> String:
	return (_menu.find_child(button_name, true, false) as Button).text


## Presses `button_name` and answers the question that opens with yes.
func _confirm(button_name: StringName) -> void:
	_press(button_name)
	for dialog: Node in _menu.find_children("*", "ConfirmDialog", true, false):
		if (dialog as ConfirmDialog).visible:
			dialog.find_child("YesButton", true, false).pressed.emit()
			return


func _open_menu() -> void:
	_state.open(HudState.Unfold.PAUSE)
	await await_idle_frame()


func test_the_sound_and_music_chips_set_the_audio_steps() -> void:
	await _open_main()
	await _open_menu()
	var settings: AudioSettings = AudioService.settings
	AudioService.set_sound_step(settings.default_sfx_step)
	AudioService.set_step(AudioService.BUS_MUSIC, settings.default_music_step)
	_press(&"SoundButton")
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(0)
	assert_int(AudioService.get_step(AudioService.BUS_UI)).is_equal(0)
	assert_str(_text(&"SoundButton")).contains("OFF")
	_press(&"SoundButton")
	assert_int(AudioService.get_step(AudioService.BUS_SFX)).is_equal(settings.default_sfx_step)
	_press(&"MusicButton")
	assert_int(AudioService.get_step(AudioService.BUS_MUSIC)).is_equal(0)
	assert_str(_text(&"MusicButton")).contains("OFF")
	_press(&"MusicButton")
	assert_int(AudioService.get_step(AudioService.BUS_MUSIC)).is_equal(settings.default_music_step)
	assert_str(_text(&"MusicButton")).is_equal("MUSIC")


func test_exit_goes_through_menu_flow_when_it_owns_the_match() -> void:
	await _open_main()
	await _open_menu()
	_confirm(&"ExitButton")
	await await_idle_frame()
	assert_array(_flow.calls).is_equal(["return_to_menu"])


func test_restart_goes_through_menu_flow_when_it_owns_the_match() -> void:
	await _open_main()
	await _open_menu()
	_confirm(&"RestartButton")
	await await_idle_frame()
	assert_array(_flow.calls).is_equal(["restart"])
	assert_bool(is_instance_valid(_main) and _main.is_inside_tree()).is_true()  # No dev route.


func test_surrender_marks_before_it_submits_the_command() -> void:
	await _open_main()
	await _open_menu()
	_confirm(&"SurrenderButton")
	assert_array(_flow.calls).is_equal(["mark_surrendered", "command"])
	assert_int(_sent.size()).is_equal(1)


func test_a_dev_route_match_does_not_mark_through_menu_flow() -> void:
	await _open_main()
	_flow.runner = null  # MenuFlow does not own this match.
	await _open_menu()
	_confirm(&"SurrenderButton")
	assert_array(_flow.calls).is_equal(["command"])


func test_app_pause_and_focus_out_open_the_menu_and_pause_the_match() -> void:
	await _open_main()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	for what: int in [
		Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT
	]:
		_state.close(HudState.Unfold.PAUSE)
		await await_idle_frame()
		assert_bool(_menu.visible).is_false()
		_menu.propagate_notification(what)
		await await_idle_frame()
		assert_bool(_menu.visible).override_failure_message(str(what)).is_true()
		assert_bool(runner.paused).is_true()


func test_back_opens_and_closes_the_menu_and_closes_a_question_first() -> void:
	await _open_main()
	_menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_bool(_menu.visible).is_true()
	_press(&"ExitButton")  # A question stands.
	_menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_bool(_menu.visible).is_true()  # The question closed, the menu stays.
	assert_array(_flow.calls).is_empty()
	_menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_bool(_menu.visible).is_false()


func test_the_menu_does_not_open_over_a_result() -> void:
	await _open_main()
	MatchRig.end(_main, [1])
	await await_idle_frame()
	_menu.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_bool(_menu.visible).is_false()


func test_how_to_play_opens_over_the_menu_and_back_returns_to_it() -> void:
	await _open_main()
	await _open_menu()
	_press(&"HelpButton")
	await await_idle_frame()
	var overlay: MenuStack = _menu.find_child("HelpOverlay", true, false) as MenuStack
	assert_object(overlay).is_not_null()
	assert_object(overlay.current()).is_instanceof(HowToPlayScreen)
	assert_bool(_menu.find_child("Foot", true, false) == null).is_true()  # No banner under it.
	_menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_menu.visible).is_true()  # The stack took Back, not the pause menu.
	assert_bool(_menu.find_child("HelpOverlay", true, false) == null).is_true()
	assert_bool(_state.is_open(HudState.Unfold.PAUSE)).is_true()


func test_settings_is_disabled_without_a_route_and_opens_with_one() -> void:
	await _open_main()
	_menu.routes = MenuRoutes.new()
	await _open_menu()
	assert_bool((_menu.find_child("SettingsButton", true, false) as Button).disabled).is_true()
	_state.close(HudState.Unfold.PAUSE)
	_menu.routes.register(MenuRoutes.SETTINGS, func() -> MenuScreen: return MenuScreen.new())
	await _open_menu()
	assert_bool((_menu.find_child("SettingsButton", true, false) as Button).disabled).is_false()
	_press(&"SettingsButton")
	await await_idle_frame()
	assert_object(_menu.find_child("HelpOverlay", true, false)).is_not_null()


## A lesson through the real MenuFlow: Leave tutorial reaches the menu and no ad method runs.
func test_leave_tutorial_calls_no_ad_method() -> void:
	var ads: FakeAds = auto_free(FakeAds.new())
	add_child(ads)
	var flow: Node = auto_free((load("res://game/ui/menu/menu_flow_service.gd") as GDScript).new())
	add_child(flow)
	flow.ads = ads
	var menus: Array[int] = [0]
	flow.switch_to_menu = func() -> Error:
		menus[0] += 1
		return OK
	flow.switch_to_main = func(main: Node) -> Error:
		add_child(main)
		return OK
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	setup.lesson_id = &"lesson_test"
	assert_int(await flow.start_match(setup)).is_equal(OK)
	_main = flow.current_runner().get_parent()
	_menu = _main.get_node("Hud/PauseMenu")
	_menu.menu_flow = flow
	_state = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	await _open_menu()
	assert_str(_text(&"ExitButton")).is_equal("LEAVE TUTORIAL")
	_confirm(&"ExitButton")
	await await_idle_frame()
	assert_int(menus[0]).is_equal(1)
	assert_int(ads.calls).is_equal(0)


func test_the_new_controls_fit_and_are_big_enough_at_the_six_sizes() -> void:
	await _open_main()
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		await _open_menu()
		var safe: Rect2 = UiScale.safe_rect_base()
		for button_name: StringName in [
			&"HelpButton", &"SettingsButton", &"SoundButton", &"MusicButton"
		]:
			var button: Button = _menu.find_child(button_name, true, false) as Button
			var label: String = "%s at %s" % [button_name, size]
			var rect: Rect2 = button.get_global_rect()
			assert_float(rect.size.y).override_failure_message(label).is_greater_equal(
				UiScale.dp(MIN_DP) - TOLERANCE_PX
			)
			assert_float(rect.end.x).override_failure_message(label).is_less_equal(
				safe.end.x + TOLERANCE_PX
			)
			assert_float(rect.position.x).override_failure_message(label).is_greater_equal(
				safe.position.x - TOLERANCE_PX
			)
		_state.close(HudState.Unfold.PAUSE)
