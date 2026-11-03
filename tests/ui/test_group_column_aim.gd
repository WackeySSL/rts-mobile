extends GdUnitTestSuite
## The group column while a strike is aimed (plan P122b, ADR 0025 section 2), upright at
## web_phone_portrait with three saved groups: the column holds three items and scrolls under a
## finger; a scroll is neither a tap nor a hold and its flag is per press; a move under
## `tap_slop_dp` is still a tap; outside the aim the column is as before; the gaps belong to the
## map. Player 1 has a Deep Bore (id 1) and a light tank (id 2), as test_strike_controls.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BORE: int = 1
const TANK: int = 2
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
]

var _window_size_before: Vector2i
var _main: Node2D
var _aim: StrikeAim
var _controller: PlayerController
var _sent: Array[Command] = []
var _buzzes: Array[int] = []
var _now_ms: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()
	_now_ms = 0


## Opens the strike scene upright with three saved groups (the tank in each), a ready strike and
## the aim on: the column holds three items and scrolls. The groups' clocks are the fake one.
func _aim_with_three_groups() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(phone.window_size, phone, true)
	for slot: int in range(1, 4):
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_controller.assign_group(slot)
		(_hud("Group%d" % slot) as HoldButton).clock = func() -> int: return _now_ms
	_ready_to_fire()
	assert_bool(_aim.begin()).is_true()
	await await_idle_frame()
	await await_idle_frame()
	var scroll: ScrollContainer = _hud("ColumnScroll")
	assert_int(scroll.vertical_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	_buzzes.clear()


## A press at `at`, moved by `by` in `steps` (a frame between them when `frames`), not yet lifted.
## Returns where the finger is.
func _press_and_move(at: Vector2, by: Vector2, steps: int, frames: bool = false) -> Vector2:
	TouchEvents.press(get_viewport(), 0, at)
	if frames:
		await await_idle_frame()
	for step: int in steps:
		at += by / steps
		TouchEvents.drag(get_viewport(), 0, at, by / steps)
		if frames:
			await await_idle_frame()
	return at


## After a scroll, a tap on an item works again: the spent flag belongs to one press.
func test_a_tap_after_a_scroll_recalls_again() -> void:
	await _aim_with_three_groups()
	var dp: float = UiScale.base_px_per_dp()
	_controller.selection.set_ids(PackedInt32Array([BORE]))
	var start: Vector2 = _rect("Group2").get_center()
	var at: Vector2 = await _press_and_move(start, Vector2(0.0, -dp * 40.0), 4)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_array(_controller.selection.selected).is_equal([BORE])  # The scroll recalled nothing.
	var tap: Vector2 = _rect("Group2").get_center()
	TouchEvents.press(get_viewport(), 0, tap)
	TouchEvents.release(get_viewport(), 0, tap)
	await await_idle_frame()
	assert_array(_controller.selection.selected).is_equal([TANK])


## A scroll that lasts past the hold time is neither a hold (it would assign the selected tank to
## the group and buzz) nor, on the lift, a tap. A frame runs between the drag steps, as on a phone.
func test_a_long_scroll_is_neither_a_hold_nor_a_tap() -> void:
	await _aim_with_three_groups()
	var dp: float = UiScale.base_px_per_dp()
	_controller.selection.set_ids(PackedInt32Array([TANK]))
	var start: Vector2 = _rect("Group2").get_center()
	var at: Vector2 = await _press_and_move(start, Vector2(0.0, -dp * 32.0), 4, true)
	_now_ms += 800  # More than group_assign_ms.
	await await_idle_frame()
	await await_idle_frame()
	assert_array(_buzzes).override_failure_message("a scroll became a hold").is_empty()
	_controller.selection.set_ids(PackedInt32Array([BORE]))
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_array(_controller.selection.selected).override_failure_message("a tap").is_equal([BORE])
	assert_array(_sent).is_empty()


## A press that moves less than `tap_slop_dp` is still a tap, in the aim too.
func test_a_wobble_under_the_slop_in_the_aim_is_still_a_tap() -> void:
	await _aim_with_three_groups()
	var dp: float = UiScale.base_px_per_dp()
	_controller.selection.set_ids(PackedInt32Array([BORE]))
	var slop: float = _controller.settings.tap_slop_dp
	var at: Vector2 = _rect("Group2").get_center()
	var wobble: Vector2 = Vector2(0.0, -dp * slop * 0.5)
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.drag(get_viewport(), 0, at + wobble, wobble)
	TouchEvents.release(get_viewport(), 0, at + wobble)
	await await_idle_frame()
	assert_int((_hud("ColumnScroll") as ScrollContainer).scroll_vertical).is_equal(0)
	assert_array(_controller.selection.selected).is_equal([TANK])


## Outside the aim the column is as before: a wobble beyond the slop that lifts on the plate is a
## tap, and a drag that leaves the plate pans nothing and recalls nothing.
func test_outside_the_aim_a_wobble_taps_and_a_drag_off_the_plate_does_nothing() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(phone.window_size, phone, true)
	for slot: int in range(1, 4):
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_controller.assign_group(slot)
	await await_idle_frame()
	var dp: float = UiScale.base_px_per_dp()
	_controller.selection.set_ids(PackedInt32Array([BORE]))
	var camera: Camera2D = _main.get_node("Camera")
	var before: Vector2 = camera.position
	var start: Vector2 = _rect("Group2").get_center()
	var at: Vector2 = await _press_and_move(start, Vector2(0.0, -dp * 120.0), 6)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_vector(camera.position).is_equal(before)
	assert_array(_controller.selection.selected).is_equal([BORE])
	at = _rect("Group2").get_center()
	var out: Vector2 = Vector2(0.0, -dp * 20.0)  # Beyond the slop, back to the middle.
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.drag(get_viewport(), 0, at + out, out)
	TouchEvents.drag(get_viewport(), 0, at, -out)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_array(_controller.selection.selected).is_equal([TANK])


## The gaps of the limited column belong to the map: a tap in one places the strike point, a drag
## from one pans the camera and leaves the column where it is.
func test_a_gap_of_the_limited_column_belongs_to_the_map() -> void:
	await _aim_with_three_groups()
	var dp: float = UiScale.base_px_per_dp()
	var scroll: ScrollContainer = _hud("ColumnScroll")
	var gap: Vector2 = Vector2(
		_rect("Group1").get_center().x, (_rect("Group1").end.y + _rect("Group2").position.y) * 0.5
	)
	assert_bool(_rect("GroupColumn").has_point(gap)).is_true()
	assert_bool(_aim.has_point).is_false()
	TouchEvents.press(get_viewport(), 0, gap)
	TouchEvents.release(get_viewport(), 0, gap)
	await await_idle_frame()
	assert_bool(_aim.has_point).override_failure_message("the gap tap missed the map").is_true()
	var camera: Camera2D = _main.get_node("Camera")
	var before: Vector2 = camera.position
	var at: Vector2 = await _press_and_move(gap, Vector2(0.0, -dp * 60.0), 6)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_bool(camera.position != before).override_failure_message("no pan").is_true()
	assert_int(scroll.scroll_vertical).is_equal(0)


func _ready_to_fire() -> void:
	_aim.cancel()
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
	_aim.refresh()


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


## A new strike scene at `size` under `metrics`, its match paused, the Commands and buzzes caught,
## the tank selected, and the fake clock on the touch input.
func _open(size: Vector2i, metrics: UiMetrics, _strike: bool) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.set_override(metrics)
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario(spawns)
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_aim = _main.get_node("StrikeAim")
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_buzzes.clear()
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return _now_ms
	_controller.selection.set_ids(PackedInt32Array([TANK]))
	await await_idle_frame()
