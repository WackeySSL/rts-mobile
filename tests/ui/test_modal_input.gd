extends GdUnitTestSuite
## A modal takes every touch (plan P90, review round 1): the pause menu (P124; P90 had the
## Surrender dialog) and the result screen cover the HUD, and nothing under them hears a wheel, a
## finger already down or a hold in flight.
## For each modal, each case runs the same input twice: once with the modal still closed, where it
## acts (the positive control), and once with the modal shown, where it does not. The cases are the
## wheel (it zoomed the camera through the modal), a finger resting on the map whose lift sent a
## MOVE and whose drag went on panning, a finger held on the minimap whose hold sent a MOVE, and a
## held group button whose hold assigned a group. A modal that shows ends them all through
## `TouchInput.CANCEL_GROUP`. The plain taps on the modal are test_pause_menu's and
## test_result_screen's.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
## Open ground at 1280x720, clear of every HUD control and of both modals' panels.
const GROUND_POINT: Vector2 = Vector2(80, 300)
## How the modal opens: the pause menu by a tap of a second finger on the pill's menu button, the
## result screen by the match ending (the other side surrenders).
const MODALS: Array[String] = ["pause", "result"]

var _window_size_before: Vector2i
var _main: Node
var _camera: RtsCamera
var _sent: Array[Command] = []
var _gestures: Array[int] = [0]
var _now: Array[int] = [0]


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


func test_the_wheel_does_not_zoom_the_map_through_a_modal() -> void:
	for modal: String in MODALS:
		await _open()
		TouchEvents.wheel(get_viewport(), MOUSE_BUTTON_WHEEL_UP, GROUND_POINT)
		await await_idle_frame()
		var zoomed: float = _camera.zoom.x
		assert_float(zoomed).override_failure_message(modal).is_greater(1.0)  # The control.
		assert_int(_gestures[0]).is_equal(1)
		await _show(modal, false)
		TouchEvents.wheel(get_viewport(), MOUSE_BUTTON_WHEEL_DOWN, GROUND_POINT)
		await await_idle_frame()
		assert_float(_camera.zoom.x).override_failure_message(modal).is_equal(zoomed)
		assert_int(_gestures[0]).override_failure_message(modal).is_equal(1)
		_main.free()


## Finger 0 rests on the map and finger 1 touches something else; finger 0 lifts. Without a modal
## that is a tap and a MOVE goes out; with one, finger 0 was let go when it showed.
func test_a_finger_resting_on_the_map_orders_nothing_when_it_lifts_under_a_modal() -> void:
	for modal: String in MODALS:
		await _open()
		TouchEvents.press(get_viewport(), 0, GROUND_POINT)
		_tap_with_finger_1(_hud("AllArmy"))
		TouchEvents.release(get_viewport(), 0, GROUND_POINT)
		await await_idle_frame()
		assert_array(_sent).override_failure_message(modal).has_size(1)  # The control.
		_sent.clear()
		TouchEvents.press(get_viewport(), 0, GROUND_POINT)
		await _show(modal, true)
		TouchEvents.release(get_viewport(), 0, GROUND_POINT)
		await await_idle_frame()
		assert_array(_sent).override_failure_message(modal).is_empty()
		_main.free()


## The same finger keeps dragging: without a modal it goes on panning, with one it pans no more.
func test_a_finger_dragging_the_map_pans_no_more_under_a_modal() -> void:
	for modal: String in MODALS:
		await _open()
		var step: Vector2 = Vector2(60, 0)
		TouchEvents.press(get_viewport(), 0, GROUND_POINT)
		TouchEvents.drag(get_viewport(), 0, GROUND_POINT + step, step)
		_tap_with_finger_1(_hud("AllArmy"))
		var before: Vector2 = _camera.position
		TouchEvents.drag(get_viewport(), 0, GROUND_POINT + step * 2.0, step)
		assert_vector(_camera.position).override_failure_message(modal).is_not_equal(before)
		TouchEvents.release(get_viewport(), 0, GROUND_POINT + step * 2.0)
		TouchEvents.press(get_viewport(), 0, GROUND_POINT)
		TouchEvents.drag(get_viewport(), 0, GROUND_POINT + step, step)
		await _show(modal, true)
		before = _camera.position
		TouchEvents.drag(get_viewport(), 0, GROUND_POINT + step * 2.0, step)
		await await_idle_frame()
		assert_vector(_camera.position).override_failure_message(modal).is_equal(before)
		TouchEvents.release(get_viewport(), 0, GROUND_POINT + step * 2.0)
		_main.free()


## A finger resting on the minimap moves the selected units after `long_press_ms`; a modal that
## shows under it ends that finger, and no MOVE comes.
func test_a_hold_on_the_minimap_orders_nothing_under_a_modal() -> void:
	for modal: String in MODALS:
		await _open()
		var mini: Minimap = _main.find_child("Minimap", true, false)
		(_main.get_node("Hud/HudStateFeed") as HudStateFeed).state.open(HudState.Unfold.RADAR)
		await await_idle_frame()
		mini.clock = func() -> int: return _now[0]
		var at: Vector2 = mini.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		_now[0] += 5000
		await await_idle_frame()
		assert_array(_sent).override_failure_message(modal).has_size(1)  # The control.
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		TouchEvents.release(get_viewport(), 0, at)
		_sent.clear()
		TouchEvents.press(get_viewport(), 0, at)
		await _show(modal, false)
		_now[0] += 5000
		for frame: int in 3:
			await await_idle_frame()
		assert_array(_sent).override_failure_message(modal).is_empty()
		TouchEvents.release(get_viewport(), 0, at)
		_main.free()


## A hold button (a group button here, an item tile is the same class) assigns its group once
## the finger has rested for `hold_ms`; under a modal the press is spent: no hold and no tap.
func test_a_hold_button_does_not_hold_or_tap_under_a_modal() -> void:
	for modal: String in MODALS:
		await _open()
		var controller: PlayerController = _main.get_node("PlayerController")
		controller.assign_group(1)  # An empty group is not shown: save the units `_open` selected.
		var group: HoldButton = _hud("Group1") as HoldButton
		group.clock = func() -> int: return _now[0]
		var counts: Dictionary[String, int] = {"held": 0, "tapped": 0}
		group.held.connect(func() -> void: counts["held"] += 1)
		group.tapped.connect(func() -> void: counts["tapped"] += 1)
		var at: Vector2 = group.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		_now[0] += group.hold_ms + 100
		await await_idle_frame()
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(counts["held"]).override_failure_message(modal).is_equal(1)  # The control.
		TouchEvents.press(get_viewport(), 0, at)
		await _show(modal, false)
		_now[0] += group.hold_ms + 100
		for frame: int in 3:
			await await_idle_frame()
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(counts["held"]).override_failure_message(modal).is_equal(1)
		assert_int(counts["tapped"]).override_failure_message(modal).is_equal(0)
		_main.free()


## The economy pill takes a tap on its credits or its power (`economy_pressed`). A modal ends a
## finger that went down there before it showed (no tap when it lifts), and a tap while it shows
## lands on the modal: the pill stands under it in the HUD's order.
func test_a_tap_on_the_pill_is_spent_or_taken_by_a_modal() -> void:
	for modal: String in MODALS:
		await _open()
		var pill: EconomyPill = _main.get_node("Hud/EconomyPill")
		var taps: Array[int] = [0]
		pill.economy_pressed.connect(func() -> void: taps[0] += 1)
		var at: Vector2 = (
			(pill.find_child("CreditsTap", true, false) as Control).get_global_rect().get_center()
		)
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(taps[0]).override_failure_message(modal).is_equal(1)  # The control.
		TouchEvents.press(get_viewport(), 0, at)
		await _show(modal, false)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(taps[0]).override_failure_message(modal).is_equal(1)  # The finger was spent.
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(taps[0]).override_failure_message(modal).is_equal(1)  # The modal took this one.
		assert_array(_sent).override_failure_message(modal).is_empty()
		_main.free()


## A main scene on the Derrick League's Skirmish with the units selected, Commands and the
## `map_gesture` count caught, the clock fixed (no long-press by itself) and the zoom instant.
func _open() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	_sent.clear()
	_gestures[0] = 0
	_now[0] = 0
	_camera = _main.get_node("Camera")
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	var controller: PlayerController = _main.get_node("PlayerController")
	controller.command_sink = func(command: Command) -> void: _sent.append(command)
	controller.selection.set_ids(MatchRig.units_of(_main, 1))
	var touch: TouchInput = _main.get_node("TouchInput")
	touch.clock = func() -> int: return 0
	touch.map_gesture.connect(func() -> void: _gestures[0] += 1)


## Shows `modal`. The pause menu by a tap of finger 1 on the menu button (`with_finger`) or a press
## signal; the result screen by the other side's surrender.
func _show(modal: String, with_finger: bool) -> void:
	if modal == "pause":
		if with_finger:
			_tap_with_finger_1(_hud("Menu"))
		else:
			(_hud("Menu") as Button).pressed.emit()
	else:
		MatchRig.end(_main, [2])
	await await_idle_frame()
	var shown: Control = _main.get_node("Hud/PauseMenu" if modal == "pause" else "Hud/ResultScreen")
	assert_bool(shown.visible).override_failure_message(modal).is_true()


## A second finger down and up on the middle of `control`.
func _tap_with_finger_1(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 1, at)
	TouchEvents.release(get_viewport(), 1, at)


func _hud(node_name: String) -> Control:
	return _main.get_node("Hud").find_child(node_name, true, false) as Control
