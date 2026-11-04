extends GdUnitTestSuite
## The pause menu (plan P124, ADR 0025 section 11; it holds P90's Surrender and its confirm, ADR
## 0019 section 6, question 3): the pill's menu button opens it, the match is paused while it
## shows (`MatchRunner.paused`, no Command), Resume unpauses; Restart, Surrender and Exit ask first
## and only a yes answers; only the Surrender yes sends SURRENDER, once, through the controller's
## sink; the Vibration switch writes `HudPrefs` and every `vibrate` call obeys it; the menu takes
## every touch, does not open over the result screen and carries no ad. At the six sizes and on the
## phone browsers the menu and the dialogs lie inside the safe rect.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MIN_DP: float = 48.0
const BUTTON_DP: float = 64.0
const TOLERANCE_PX: float = 0.5
## Open ground at 1280x720, left of the pill's neighbours and clear of the group column.
const GROUND_POINT: Vector2 = Vector2(80, 300)
const ASKING: Array[String] = ["RestartButton", "SurrenderButton", "ExitButton"]

var _window_size_before: Vector2i
var _main: Node
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


## The override and the queue are static state: leaving them changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func test_the_menu_button_is_in_the_pill_and_at_least_48_dp_at_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open()
		var button: Control = _pill_menu()
		var rect: Rect2 = button.get_global_rect()
		var where: String = "%s: %s" % [size, rect]
		assert_bool(button.is_visible_in_tree()).override_failure_message(where).is_true()
		var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		(
			assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px)
			. override_failure_message(where)
			. is_true()
		)
		(
			assert_bool(UiScale.safe_rect_base().encloses(rect))
			. override_failure_message(where)
			. is_true()
		)
		(
			assert_bool(_pill().get_global_rect().encloses(rect))
			. override_failure_message(where)
			. is_true()
		)
		_main.free()
		await await_idle_frame()


## The Dev stack is gone: no Dev button, no Surrender button on the battle screen, and the pill
## stands in the corner (no other control takes the corner's room) at every size.
func test_the_pill_stands_in_the_corner_and_the_dev_stack_is_gone() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open()
		assert_object(_main.find_child("DevButton", true, false)).is_null()
		assert_object(_main.find_child("TopLeft", true, false)).is_null()
		assert_object(_main.get_node_or_null("Hud/SurrenderDialog")).is_null()
		var rect: Rect2 = _pill().get_global_rect()
		var margin: SafeAreaMargin = _main.get_node("Hud/SafeArea") as SafeAreaMargin
		var corner: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), margin.margin_dp
		)
		assert_vector(rect.position).override_failure_message(str(size)).is_equal_approx(
			corner.position, Vector2(1.5, 1.5)
		)
		_main.free()
		await await_idle_frame()


func test_the_menu_button_pauses_the_match_and_resume_unpauses_it() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	var runner: MatchRunner = _runner()
	var hash_before: int = runner.last_hash
	assert_bool(_menu().visible).is_false()
	assert_bool(runner.paused).is_false()
	_tap(_pill_menu())
	await await_idle_frame()
	assert_bool(_state().is_open(HudState.Unfold.PAUSE)).is_true()
	assert_bool(_menu().visible).is_true()
	assert_bool(runner.paused).is_true()
	assert_array(_sent).is_empty()  # Pausing is no Command.
	var tick: int = runner.snapshot.tick
	await await_idle_frame()
	await await_idle_frame()
	assert_int(runner.snapshot.tick).is_equal(tick)
	assert_int(runner.last_hash).is_equal(hash_before)
	_tap(_button("ResumeButton"))
	await await_idle_frame()
	assert_bool(_menu().visible).is_false()
	assert_bool(runner.paused).is_false()
	assert_bool(_state().is_open(HudState.Unfold.NONE)).is_true()
	assert_array(_sent).is_empty()


## Opening the menu closes every other unfold, and nothing opens behind it.
func test_the_menu_closes_the_other_unfold_and_takes_the_state() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_state().open(HudState.Unfold.DRAWER)
	_pill().menu_pressed.emit()
	assert_bool(_state().is_open(HudState.Unfold.PAUSE)).is_true()
	assert_bool(_state().open(HudState.Unfold.RADAR)).is_false()
	assert_bool(_state().is_open(HudState.Unfold.PAUSE)).is_true()


## The card: SKIRMISH and the map, the objective, the time and the units lost (from the snapshot).
func test_the_card_shows_the_map_the_goal_the_time_and_the_losses() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_runner().run_ticks(Sim.TICK_RATE * 65)
	_pill().menu_pressed.emit()
	var texts: Array[String] = []
	for label: Node in _menu().find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_array(texts).contains(["SKIRMISH", "Kestrel Flats", "Time 1:05", "Units lost 0"])
	assert_array(texts).contains([PauseMenu.OBJECTIVE])
	var lost: int = _runner().snapshot.stat_lost_units[_runner().scenario.local_player]
	assert_int(lost).is_equal(0)


## Restart, Surrender and Exit each ask first and send or change nothing until the yes; the no
## answer closes the dialog and leaves the menu open and the match paused.
func test_restart_surrender_and_exit_ask_first() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	var scene: Node = get_tree().current_scene
	for name: String in ASKING:
		_pill().menu_pressed.emit()
		await await_idle_frame()
		var dialog: ConfirmDialog = await _dialog_after(name)
		assert_bool(dialog.visible).override_failure_message(name).is_true()
		assert_array(_sent).is_empty()
		_tap(dialog.find_child("NoButton", true, false) as Control)
		assert_bool(dialog.visible).is_false()
		assert_bool(_menu().visible).is_true()
		assert_bool(_runner().paused).is_true()
		assert_array(_sent).is_empty()
		assert_object(get_tree().current_scene).is_same(scene)
		_tap(_button("ResumeButton"))
		await await_idle_frame()


## The Surrender yes resumes the match and sends one SURRENDER of the local player.
func test_only_the_surrender_yes_sends_surrender_and_it_sends_one() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_pill().menu_pressed.emit()
	await await_idle_frame()
	var dialog: ConfirmDialog = await _dialog_after("SurrenderButton")
	assert_bool(dialog.visible).is_true()
	assert_array(_sent).is_empty()
	_tap(dialog.find_child("YesButton", true, false) as Control)
	assert_bool(dialog.visible).is_false()
	assert_array(_sent).has_size(1)
	assert_int(_sent[0].type).is_equal(Command.Type.SURRENDER)
	assert_int(_sent[0].player_id).is_equal(1)
	assert_bool(_menu().visible).is_false()
	assert_bool(_runner().paused).is_false()


## Through the real queue the sim takes it: the match ends on the next tick, the other player wins,
## nothing is dropped, and the result screen says Defeat.
func test_the_sim_takes_the_command_and_the_result_screen_follows() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	(_main.get_node("PlayerController") as PlayerController).command_sink = CommandQueue.submit
	_pill().menu_pressed.emit()
	var dialog: ConfirmDialog = await _dialog_after("SurrenderButton")
	dialog.find_child("YesButton", true, false).pressed.emit()
	var runner: MatchRunner = _runner()
	assert_int(runner.snapshot.match_end_tick).is_equal(0)  # Not before the confirm's tick.
	runner.run_ticks(1)
	assert_int(runner.world.dropped_commands).is_equal(0)
	assert_int(runner.snapshot.match_end_tick).is_greater(0)
	assert_int(runner.snapshot.winner).is_equal(2)
	assert_bool((_main.get_node("Hud/ResultScreen") as Control).visible).is_true()
	assert_bool(dialog.visible).is_false()


## The menu covers the HUD and takes every touch: with units selected a tap on the ground orders
## nothing, and a tap on the pill beneath it does not press its menu button again.
func test_the_menu_takes_every_touch() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	(_main.get_node("PlayerController") as PlayerController).selection.set_ids(
		MatchRig.units_of(_main, 1)
	)
	TouchEvents.press(get_viewport(), 0, GROUND_POINT)  # The control: the same tap moves them.
	TouchEvents.release(get_viewport(), 0, GROUND_POINT)
	await await_idle_frame()
	assert_array(_sent).has_size(1)
	_sent.clear()
	_pill().menu_pressed.emit()
	await await_idle_frame()
	var presses: Array[int] = [0]
	_pill().menu_pressed.connect(func() -> void: presses[0] += 1)
	for at: Vector2 in [GROUND_POINT, _pill_menu().get_global_rect().get_center()]:
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		await await_idle_frame()
	assert_array(_sent).is_empty()
	assert_int(presses[0]).is_equal(0)
	assert_bool(_menu().visible).is_true()


## The result screen covers the HUD at the match's end: the menu does not open over it, and a menu
## that is open when the match ends (the other side fell) gives way, with its dialog closed.
func test_the_menu_does_not_open_over_the_result_and_gives_way_to_it() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_pill().menu_pressed.emit()
	var dialog: ConfirmDialog = await _dialog_after("SurrenderButton")
	assert_bool(dialog.visible).is_true()
	MatchRig.end(_main, [2])
	assert_bool(dialog.visible).is_false()
	assert_bool(_menu().visible).is_false()
	assert_bool(_runner().paused).is_false()
	assert_bool((_main.get_node("Hud/ResultScreen") as Control).visible).is_true()
	_pill().menu_pressed.emit()
	assert_bool(_state().is_open(HudState.Unfold.PAUSE)).is_false()
	assert_bool(_menu().visible).is_false()
	assert_array(_sent).is_empty()


## A new match in the same scene closes the menu and unpauses.
func test_a_new_match_closes_the_menu() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_pill().menu_pressed.emit()
	assert_bool(_runner().paused).is_true()
	_state().reset()
	assert_bool(_menu().visible).is_false()
	assert_bool(_runner().paused).is_false()


## The words the player reads, and a Developer menu entry in a debug build.
func test_the_words_on_the_buttons_and_the_dialogs() -> void:
	await _open()
	assert_str(_button("ResumeButton").text).is_equal("RESUME")
	assert_str(_button("RestartButton").text).is_equal("RESTART")
	assert_str(_button("SurrenderButton").text).is_equal("SURRENDER")
	assert_str(_button("ExitButton").text).is_equal("EXIT TO MENU")
	assert_bool(_menu().find_child("DevMenuButton", true, false) != null).is_equal(
		DevRoutes.is_enabled()
	)
	var dialog: ConfirmDialog = await _dialog_after("SurrenderButton")
	assert_str(dialog.find_child("YesButton", true, false).text).is_equal("SURRENDER")
	assert_str(dialog.find_child("NoButton", true, false).text).is_equal("KEEP PLAYING")
	assert_str(dialog.question).is_equal("SURRENDER?")


## A dialog opens with the keyboard focus on KEEP PLAYING, and no focus ring shows.
func test_the_dialog_takes_the_focus_without_a_ring() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_pill().menu_pressed.emit()
	var dialog: ConfirmDialog = await _dialog_after("SurrenderButton")
	var no_button: Button = dialog.find_child("NoButton", true, false) as Button
	assert_bool(no_button.has_focus()).is_true()
	assert_bool(no_button.has_focus(true)).is_false()


## The menu, its buttons (64 dp high, 48 dp at the least) and the dialog lie inside the safe rect at
## the six sizes, the phone browsers and the cutouts.
func test_the_menu_and_the_dialog_fit_every_size_and_the_cutouts() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	var cases: Dictionary[String, UiMetrics] = {
		"web_phone": UiProfiles.by_name(&"web_phone"),
		"web_phone_portrait": UiProfiles.by_name(&"web_phone_portrait"),
		"landscape cutout": UiProfiles.with_safe_area(landscape, Rect2i(152, 0, 2248, 1080)),
		"portrait cutout": UiProfiles.with_safe_area(portrait, Rect2i(0, 100, 1080, 2237)),
	}
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open()
		await _check_menu(str(size))
		_main.free()
		await await_idle_frame()
	for label: String in cases:
		UiScale.set_override(cases[label])
		get_window().size = cases[label].window_size
		await await_idle_frame()
		await _open()
		await _check_menu(label)
		_main.free()
		UiScale.clear_override()
		await await_idle_frame()


## A main scene on the Derrick League's Skirmish whose controller keeps its Commands in `_sent`.
func _open() -> void:
	_main = auto_free(await MatchRig.open(self))
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = func(
		command: Command
	) -> void:
		_sent.append(command)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return 0


func _runner() -> MatchRunner:
	return _main.get_node("MatchRunner") as MatchRunner


func _pill() -> EconomyPill:
	return _main.get_node("Hud/EconomyPill") as EconomyPill


func _pill_menu() -> Control:
	return _pill().find_child("Menu", true, false) as Control


func _menu() -> PauseMenu:
	return _main.get_node("Hud/PauseMenu") as PauseMenu


func _state() -> HudState:
	return (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state


func _button(button_name: String) -> Button:
	return _menu().find_child(button_name, true, false) as Button


## Taps `button_name` of the open menu (a Restart, Surrender or Exit) and returns the dialog that
## answers: the one that is visible.
func _dialog_after(button_name: String) -> ConfirmDialog:
	var button: Button = _button(button_name)
	if not _menu().visible:
		_pill().menu_pressed.emit()
	button.pressed.emit()
	for dialog: Node in _menu().find_children("*", "ConfirmDialog", true, false):
		if (dialog as ConfirmDialog).visible:
			await await_idle_frame()  # Its layout.
			return dialog as ConfirmDialog
	return null


## A finger down and up on the middle of `control`.
func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## The open menu: the panel and every button inside the safe rect, the buttons at least 64 dp
## high; then the Surrender dialog inside it too.
func _check_menu(label: String) -> void:
	_pill().menu_pressed.emit()
	await await_idle_frame()
	var safe: Rect2 = UiScale.safe_rect_base()
	assert_bool(_menu().visible).override_failure_message(label).is_true()
	assert_bool(_menu().get_rect().is_equal_approx(get_viewport().get_visible_rect())).is_true()
	var buttons: Array[Control] = []
	for node: Node in _menu().find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree():
			buttons.append(node as Control)
	assert_int(buttons.size()).is_greater_equal(5)
	for button: Control in buttons:
		var rect: Rect2 = button.get_global_rect()
		var where: String = "%s: %s %s" % [label, button.name, rect]
		assert_bool(safe.encloses(rect)).override_failure_message(where).is_true()
		assert_float(rect.size.y).override_failure_message(where).is_greater_equal(
			UiScale.dp(BUTTON_DP) - TOLERANCE_PX
		)
	var dialog: ConfirmDialog = await _dialog_after("SurrenderButton")
	assert_bool(dialog.visible).override_failure_message(label).is_true()
	for button_name: String in ["NoButton", "YesButton"]:
		var rect: Rect2 = (dialog.find_child(button_name, true, false) as Control).get_global_rect()
		var where: String = "%s: %s %s" % [label, button_name, rect]
		assert_bool(safe.encloses(rect)).override_failure_message(where).is_true()
		assert_float(rect.size.y).override_failure_message(where).is_greater_equal(
			UiScale.dp(BUTTON_DP) - TOLERANCE_PX
		)
