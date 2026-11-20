extends GdUnitTestSuite
## The pause menu's Restart while MenuFlow prepares the new match (P442; P409 made `_begin` wait
## for a late full-screen ad): Restart reads "STARTING…" and keeps its width, every other button
## and Back are ignored, the match is built only after the settle, and a refused restart gives the
## buttons back. (Split from test_pause_menu_flow.gd, which is at the public-method limit.)

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const FlowScript: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"
const TOLERANCE_PX: float = 0.5
const OTHERS: Array[StringName] = [
	&"ResumeButton",
	&"SurrenderButton",
	&"HelpButton",
	&"SettingsButton",
	&"ExitButton",
	&"VibrationButton",
	&"SoundButton",
	&"MusicButton",
]


class GatedFlow:
	extends Node
	signal released
	var runner: MatchRunner = null
	var result: Error = OK
	var calls: int = 0

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return null

	func restart() -> Error:
		calls += 1
		await released
		return result


class GatedAds:
	extends Node
	signal released
	var hold: bool = false  ## True: `settle_fullscreen` stays pending until `released`.

	func take_start_credits_bonus() -> int:
		return 0

	func note_match_completed(_seconds: int) -> void:
		pass

	func settle_fullscreen() -> void:
		if hold:
			await released

	func maybe_show_interstitial(_placement: StringName) -> bool:
		return false


var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _main: Node
var _menu: PauseMenu
var _state: HudState


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func _attach(main: Node) -> void:
	_menu = main.get_node("Hud/PauseMenu")
	_state = (main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	_state.open(HudState.Unfold.PAUSE)


func _button(button_name: StringName) -> Button:
	return _menu.find_child(button_name, true, false) as Button


func _confirm_restart() -> void:
	_button(&"RestartButton").pressed.emit()
	for dialog: Node in _menu.find_children("*", "ConfirmDialog", true, false):
		if (dialog as ConfirmDialog).visible:
			var yes: Button = dialog.find_child("YesButton", true, false) as Button
			yes.grab_focus()  # As a tap would: the focus is on the question, not on Resume.
			yes.pressed.emit()
			return


## The rig's match with a flow whose `restart` stays pending until `released`.
func _gated_flow() -> GatedFlow:
	_main = auto_free(await MatchRig.open(self))
	_attach(_main)
	var flow: GatedFlow = auto_free(GatedFlow.new())
	add_child(flow)
	flow.runner = _main.get_node("MatchRunner")
	_menu.menu_flow = flow
	await await_idle_frame()
	return flow


func test_restart_shows_starting_and_ignores_the_other_buttons_and_back() -> void:
	var flow: GatedFlow = await _gated_flow()
	var settings_off: bool = _button(&"SettingsButton").disabled  # No route in the rig.
	_confirm_restart()
	await await_idle_frame()
	assert_str(_button(&"RestartButton").text).is_equal(tr(MapSelectText.STARTING))
	assert_str(_button(&"RestartButton").text).is_equal("STARTING…")
	for other: StringName in OTHERS:
		assert_bool(_button(other).disabled).is_true()
	# Disabled (no click, no pressed plate), with the look that keeps the word at full contrast.
	assert_bool(_button(&"RestartButton").disabled).is_true()
	assert_str(_button(&"RestartButton").theme_type_variation).is_equal("PauseStarting")
	_menu._on_back()  # Android Back: swallowed, the menu stays open.
	_button(&"RestartButton").pressed.emit()  # A second Restart: no question opens.
	_menu._restart()  # Nor does a second confirmed restart reach the flow.
	await await_idle_frame()
	assert_bool(_state.is_open(HudState.Unfold.PAUSE)).is_true()
	for dialog: Node in _menu.find_children("*", "ConfirmDialog", true, false):
		assert_bool((dialog as ConfirmDialog).visible).is_false()
	assert_int(flow.calls).is_equal(1)
	flow.released.emit()
	await await_idle_frame()
	assert_str(_button(&"RestartButton").text).is_equal("RESTART")
	assert_str(_button(&"RestartButton").theme_type_variation).is_equal("PauseButton")
	assert_bool(_button(&"RestartButton").disabled).is_false()
	for other: StringName in OTHERS:
		var expected: bool = settings_off if other == &"SettingsButton" else false
		assert_bool(_button(other).disabled).override_failure_message(str(other)).is_equal(expected)


func test_nothing_moves_while_restart_reads_starting_at_the_six_sizes() -> void:
	await _gated_flow()
	var gaps_checked: int = 0
	var portrait_gaps_checked: int = 0
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		for _i: int in 5:
			await await_idle_frame()
		var label: String = "at %s" % size
		var before: Array[Rect2] = _rects()
		_menu._set_starting(true)
		for _i: int in 5:
			await await_idle_frame()
		assert_array(_rects()).override_failure_message(label).is_equal(before)
		var band: Control = _menu._band
		if band != null and band.visible:
			var gap: float = (
				band.get_global_rect().position.y - _menu._toggles.get_global_rect().end.y
			)
			assert_float(gap).override_failure_message(label).is_greater_equal(
				UiScale.dp(16.0) - TOLERANCE_PX
			)
			gaps_checked += 1
			portrait_gaps_checked += 1 if size.y > size.x else 0
		_menu._set_starting(false)
		for _i: int in 2:
			await await_idle_frame()
		assert_array(_rects()).override_failure_message(label).is_equal(before)
	# The banner stands upright only: the gap check must have run on a portrait size at least.
	assert_int(portrait_gaps_checked).is_greater_equal(1)
	assert_int(gaps_checked).is_equal(portrait_gaps_checked)


## Column, Restart button and foot band; an empty rect stands for no band.
func _rects() -> Array[Rect2]:
	var band: Control = _menu._band
	return [
		_menu.column.get_global_rect(),
		_button(&"RestartButton").get_global_rect(),
		band.get_global_rect() if band != null and band.visible else Rect2(),
	]


func test_a_refused_restart_gives_the_buttons_back() -> void:
	var flow: GatedFlow = await _gated_flow()
	flow.result = ERR_BUSY
	_confirm_restart()
	await await_idle_frame()
	assert_str(_button(&"RestartButton").text).is_equal("STARTING…")
	await (
		assert_error(func() -> void: flow.released.emit())
		. is_push_warning("PauseMenu: restart refused (Busy)")
	)
	await await_idle_frame()
	assert_str(_button(&"RestartButton").text).is_equal("RESTART")
	assert_bool(_button(&"RestartButton").disabled).is_false()
	assert_bool(_button(&"ResumeButton").disabled).is_false()
	assert_bool(_button(&"ExitButton").disabled).is_false()
	assert_object(_menu.get_viewport().gui_get_focus_owner()).is_same(_button(&"ResumeButton"))
	_menu._on_back()  # Back works again: it closes the menu.
	assert_bool(_state.is_open(HudState.Unfold.PAUSE)).is_false()


func test_restart_builds_the_match_only_after_the_late_ad_settles() -> void:
	var ads: GatedAds = auto_free(GatedAds.new())
	add_child(ads)
	var flow: Node = auto_free(FlowScript.new())
	add_child(flow)
	flow.ads = ads
	var builds: Array[int] = [0]
	flow.switch_to_main = func(main: Node) -> Error:
		builds[0] += 1
		add_child(main)
		return OK
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	assert_int(await flow.start_match(setup)).is_equal(OK)
	assert_int(builds[0]).is_equal(1)
	_attach(flow.current_runner().get_parent())
	_menu.menu_flow = flow
	await await_idle_frame()
	ads.hold = true
	_confirm_restart()
	for _i: int in 3:
		await await_idle_frame()
	assert_str(_button(&"RestartButton").text).is_equal("STARTING…")
	assert_int(builds[0]).is_equal(1)  # The settle is still pending: nothing is built.
	ads.released.emit()
	for _i: int in 5:
		await await_idle_frame()
	assert_int(builds[0]).is_equal(2)
