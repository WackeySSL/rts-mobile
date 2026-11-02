extends GdUnitTestSuite
## The Surrender button and its confirm (plan P90, ADR 0019 section 6, question 3): a button of at
## least 48 dp under the Dev button at the top left; a tap opens a dialog and sends nothing; the
## no button closes it; only the yes button sends SURRENDER, once, through the controller's sink as
## a Command, which the sim takes (the match ends and the result screen follows). The dialog
## covers the HUD and takes every touch (test_modal_input has the wheel and the fingers already
## down). At the six sizes and on the phone browsers the button, the
## dialog and its two buttons lie inside the safe rect.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MIN_DP: float = 48.0
const BUTTON_DP: float = 64.0
const TOLERANCE_PX: float = 0.5
## Open ground at 1280x720, left of the panel and clear of the Dev button and the army bar.
const GROUND_POINT: Vector2 = Vector2(80, 300)
## The HUD controls the button must clear when they show.
const NEIGHBOURS: Array[String] = ["DevButton", "EconomyPill", "RadarScope", "ArmyBar"]

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


func test_the_button_is_at_least_48_dp_under_the_dev_button_and_clear_of_the_rest_at_six_sizes(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open()
		_check_button(str(size))
		_main.free()
		await await_idle_frame()


func test_the_button_and_the_dialog_fit_the_phone_browsers_and_the_cutouts() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	var cases: Dictionary[String, UiMetrics] = {
		"web_phone": UiProfiles.by_name(&"web_phone"),
		"web_phone_portrait": UiProfiles.by_name(&"web_phone_portrait"),
		"landscape cutout": UiProfiles.with_safe_area(landscape, Rect2i(152, 0, 2248, 1080)),
		"portrait cutout": UiProfiles.with_safe_area(portrait, Rect2i(0, 100, 1080, 2237)),
	}
	for label: String in cases:
		UiScale.set_override(cases[label])
		get_window().size = cases[label].window_size
		await await_idle_frame()
		await _open()
		_check_button(label)
		_surrender().pressed.emit()
		await await_idle_frame()
		_check_dialog(label)
		_main.free()
		UiScale.clear_override()
		await await_idle_frame()


## A tap on the button asks and sends nothing; "keep playing" closes the dialog and sends nothing;
## the confirm sends one SURRENDER of the local player and the button goes dim.
func test_only_the_confirm_sends_surrender_and_it_sends_one() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	var dialog: ConfirmDialog = _dialog()
	assert_bool(dialog.visible).is_false()
	_tap(_surrender())
	await await_idle_frame()
	assert_bool(dialog.visible).is_true()
	assert_array(_sent).is_empty()
	_tap(dialog.find_child("NoButton", true, false) as Control)
	assert_bool(dialog.visible).is_false()
	assert_array(_sent).is_empty()
	assert_bool(_surrender().disabled).is_false()
	_tap(_surrender())
	await await_idle_frame()
	assert_array(_sent).is_empty()
	_tap(dialog.find_child("YesButton", true, false) as Control)
	assert_bool(dialog.visible).is_false()
	assert_array(_sent).has_size(1)
	assert_int(_sent[0].type).is_equal(Command.Type.SURRENDER)
	assert_int(_sent[0].player_id).is_equal(1)
	assert_bool(_surrender().disabled).is_true()
	_tap(_surrender())  # A dim button asks nothing.
	assert_bool(dialog.visible).is_false()
	assert_array(_sent).has_size(1)


## Through the real queue the sim takes it: the match ends on the next tick, the other player wins,
## nothing is dropped, and the result screen says Defeat.
func test_the_sim_takes_the_command_and_the_result_screen_follows() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	(_main.get_node("PlayerController") as PlayerController).command_sink = CommandQueue.submit
	_surrender().pressed.emit()
	_dialog().find_child("YesButton", true, false).pressed.emit()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	assert_int(runner.snapshot.match_end_tick).is_equal(0)  # Not before the confirm's tick.
	runner.run_ticks(1)
	assert_int(runner.world.dropped_commands).is_equal(0)
	assert_int(runner.snapshot.match_end_tick).is_greater(0)
	assert_int(runner.snapshot.winner).is_equal(2)
	var result: Control = _main.get_node("Hud/ResultScreen")
	assert_bool(result.visible).is_true()
	assert_bool(_dialog().visible).is_false()


## The dialog covers the HUD and takes every touch: with units selected a tap on the ground orders
## nothing, and a tap on the Dev button beneath it does not press.
func test_the_dialog_takes_every_touch() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	(_main.get_node("PlayerController") as PlayerController).selection.set_ids(
		MatchRig.units_of(_main, 1)
	)
	var dev: Button = _main.find_child("DevButton", true, false)
	var pressed: Array[int] = [0]
	dev.pressed.connect(func() -> void: pressed[0] += 1)
	TouchEvents.press(get_viewport(), 0, GROUND_POINT)  # The control: the same tap moves them.
	TouchEvents.release(get_viewport(), 0, GROUND_POINT)
	await await_idle_frame()
	assert_array(_sent).has_size(1)
	_sent.clear()
	_surrender().pressed.emit()
	await await_idle_frame()
	for at: Vector2 in [GROUND_POINT, dev.get_global_rect().get_center()]:
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		await await_idle_frame()
	assert_array(_sent).is_empty()
	assert_int(pressed[0]).is_equal(0)
	assert_bool(_dialog().visible).is_true()  # A tap beside the panel is not an answer.


## A match that ends under the open dialog (the other side fell) closes it: the result screen
## stands alone, and the button is dim.
func test_a_match_that_ends_under_the_dialog_closes_it() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_surrender().pressed.emit()
	await await_idle_frame()
	assert_bool(_dialog().visible).is_true()
	MatchRig.end(_main, [2])
	assert_bool(_dialog().visible).is_false()
	assert_bool(_surrender().disabled).is_true()
	assert_bool((_main.get_node("Hud/ResultScreen") as Control).visible).is_true()
	assert_array(_sent).is_empty()


## A release build hides the Dev button (dev_menu_button.gd), and the stack then starts with the
## Surrender button: the credits pill (both ways) stands after it and not on it, and the selection
## line (upright, with a selection) stands under it and not on it, at every size.
func test_without_the_dev_button_surrender_is_clear_of_the_pill_and_the_selection_line() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open()
		(_main.find_child("DevButton", true, false) as Control).visible = false
		get_viewport().size_changed.emit()  # Measured again, as a release build measures it.
		(_main.get_node("PlayerController") as PlayerController).selection.set_ids(
			MatchRig.units_of(_main, 1)
		)
		await await_idle_frame()
		await await_idle_frame()
		var rect: Rect2 = _surrender().get_global_rect()
		var where: String = "%s: Surrender %s" % [size, rect]
		(
			assert_bool(UiScale.safe_rect_base().encloses(rect))
			. override_failure_message(where)
			. is_true()
		)
		# The credits pill stands after the Surrender button, sideways and upright alike.
		var pill: Control = _main.find_child("EconomyPill", true, false)
		assert_bool(pill.is_visible_in_tree()).override_failure_message(where).is_true()
		var other: Rect2 = pill.get_global_rect()
		(
			assert_bool(rect.intersects(other))
			. override_failure_message("%s, %s" % [where, other])
			. is_false()
		)
		assert_float(other.position.x).override_failure_message(where).is_equal_approx(
			rect.end.x + UiScale.dp(8.0), 1.5
		)
		# Upright the selection line stands under the Surrender button, not on it: it starts at
		# least 8 dp below its foot (the line is under the top-left row, whichever buttons show).
		if UiScale.is_portrait_size(size):
			var line: Control = _main.find_child("SelectionPanel", true, false)
			assert_bool(line.is_visible_in_tree()).override_failure_message(where).is_true()
			var below: Rect2 = line.get_global_rect()
			var message: String = "%s, selection line %s" % [where, below]
			assert_bool(rect.intersects(below)).override_failure_message(message).is_false()
			assert_float(below.position.y).override_failure_message(message).is_greater_equal(
				rect.end.y + UiScale.dp(8.0) - 0.5
			)
		_main.free()
		await await_idle_frame()


## The button's text and the dialog's words: what the player reads.
func test_the_words_on_the_button_and_the_dialog() -> void:
	await _open()
	assert_str(_surrender().text).is_equal("Surrender")
	assert_str(_dialog().find_child("YesButton", true, false).text).is_equal("SURRENDER")
	assert_str(_dialog().find_child("NoButton", true, false).text).is_equal("KEEP PLAYING")
	assert_str(_dialog().question).is_equal("SURRENDER?")


## A tap opens the dialog with the keyboard focus on KEEP PLAYING, and no focus ring shows.
func test_the_dialog_takes_the_focus_without_a_ring() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	await _open()
	_tap(_surrender())
	await await_idle_frame()
	var no_button: Button = _dialog().find_child("NoButton", true, false) as Button
	assert_bool(no_button.has_focus()).is_true()
	assert_bool(no_button.has_focus(true)).is_false()


## A main scene on the Derrick League's Skirmish whose controller keeps its Commands in `_sent`.
func _open() -> void:
	_main = auto_free(await MatchRig.open(self))
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = func(
		command: Command
	) -> void:
		_sent.append(command)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return 0


func _surrender() -> SurrenderButton:
	return _main.find_child("SurrenderButton", true, false) as SurrenderButton


func _dialog() -> ConfirmDialog:
	return _main.get_node("Hud/SurrenderDialog") as ConfirmDialog


## A finger down and up on the middle of `control`.
func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## The button inside the safe rect, at least 48 dp each way, under the Dev button on the same left
## edge, clear of the other top and bottom controls that show.
func _check_button(label: String) -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	var rect: Rect2 = _surrender().get_global_rect()
	var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
	var where: String = "%s: Surrender %s" % [label, rect]
	assert_bool(_surrender().is_visible_in_tree()).override_failure_message(where).is_true()
	(
		assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px)
		. override_failure_message(where)
		. is_true()
	)
	assert_bool(safe.encloses(rect)).override_failure_message(where).is_true()
	var dev: Rect2 = (_main.find_child("DevButton", true, false) as Control).get_global_rect()
	assert_float(rect.position.x).override_failure_message(where).is_equal_approx(
		dev.position.x, 1.0
	)
	assert_float(rect.position.y).override_failure_message(where).is_greater_equal(dev.end.y)
	assert_bool(rect.intersects(dev)).override_failure_message(where).is_false()
	for neighbour: String in NEIGHBOURS.slice(1):
		var other: Control = _main.find_child(neighbour, true, false) as Control
		if other != null and other.is_visible_in_tree():
			(
				assert_bool(rect.intersects(other.get_global_rect()))
				. override_failure_message("%s overlaps %s" % [where, neighbour])
				. is_false()
			)


## The open dialog: its panel and both buttons inside the safe rect, the buttons 64 dp high and
## apart, the dialog over the whole window.
func _check_dialog(label: String) -> void:
	var dialog: ConfirmDialog = _dialog()
	var safe: Rect2 = UiScale.safe_rect_base()
	var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
	assert_bool(dialog.visible).override_failure_message(label).is_true()
	assert_bool(dialog.get_rect().is_equal_approx(get_viewport().get_visible_rect())).is_true()
	var panel: Rect2 = dialog.column.get_parent().get_global_rect()
	assert_bool(safe.encloses(panel)).override_failure_message("%s: %s" % [label, panel]).is_true()
	var rects: Array[Rect2] = []
	for button_name: String in ["NoButton", "YesButton"]:
		var rect: Rect2 = (dialog.find_child(button_name, true, false) as Control).get_global_rect()
		var where: String = "%s: %s %s" % [label, button_name, rect]
		assert_bool(rect.size.x >= floor_px).override_failure_message(where).is_true()
		assert_float(rect.size.y).override_failure_message(where).is_greater_equal(
			UiScale.dp(BUTTON_DP) - TOLERANCE_PX
		)
		assert_bool(safe.encloses(rect)).override_failure_message(where).is_true()
		rects.append(rect)
	assert_bool(rects[0].intersects(rects[1])).override_failure_message(label).is_false()
