extends GdUnitTestSuite
## The group column of the main scene (ADR 0025 sections 2 and 9, plan P122b; ADR 0004 section 5):
## HoldButton, the column and the SafeAreaMargin around it. Fingers are touches through the real
## GUI, time is a fake clock. Ids 1-30 are the player's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _window_size_before: Vector2i
var _now_ms: int = 0
var _main: Node2D
var _controller: PlayerController
var _sent: Array[Command] = []
var _buzzes: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_a_tap_emits_tapped_and_a_hold_emits_held_and_not_tapped() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()  # The stretch follows the window, and the theme's px follow the stretch.
	var column: GroupColumn = auto_free(GroupColumn.new())
	column.theme = HudThemes.scaled()  # Outside main.tscn nothing is inherited (P58).
	column.settings = InputSettings.new()
	column.settings.group_assign_ms = 700  # The hold time is data: the column hands it to its buttons.
	add_child(column)
	await await_idle_frame()
	var button: HoldButton = column.find_child("Group3", true, false)
	assert_int(button.get_theme_font_size("font_size")).is_equal(roundi(UiScale.dp(18.0)))
	assert_bool(button.is_processing()).is_false()  # Frames watch the clock only with a finger down.
	assert_bool(button.clock == Callable(Time, &"get_ticks_msec")).is_true()
	button.clock = func() -> int: return _now_ms
	var events: Array[String] = []
	button.tapped.connect(func() -> void: events.append("tapped"))
	button.held.connect(func() -> void: events.append("held"))
	column.show_groups(PackedInt32Array([0, 0, 4]), false)
	await await_idle_frame()
	for case: Array in [[0, "tapped"], [699, "tapped"], [700, "held"], [2000, "held"]]:
		events.clear()
		_hold(button, case[0])  # No frame runs between the time passing and the release.
		assert_array(events).override_failure_message(str(case)).is_equal([case[1]])
	var at: Vector2 = button.get_global_rect().get_center()
	var off: Vector2 = at + Vector2(500, 300)
	events.clear()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.drag(get_viewport(), 0, off, off - at)  # Sliding off the button cancels the hold.
	_now_ms += 700
	await await_idle_frame()
	TouchEvents.release(get_viewport(), 0, off)
	assert_array(events).is_empty()
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 700
	await await_idle_frame()  # The hold lands on a frame, while the finger still rests.
	assert_array(events).is_equal(["held"])
	TouchEvents.release(get_viewport(), 0, at)
	assert_array(events).is_equal(["held"])
	assert_bool(button.is_processing()).is_false()


func test_buttons_are_56_dp_with_8_dp_gaps_and_an_empty_group_is_not_shown_at_every_screen(
) -> void:
	for screen: Dictionary in _screens():
		await _open(screen["metrics"], screen["size"])
		_save_groups(3)  # Three counted groups and, with a unit selected, no "+" (none free).
		await await_idle_frame()
		var dp: float = UiScale.base_px_per_dp()
		var why: String = str(screen["label"])
		var rects: Array[Rect2] = []
		for button_name: String in ["AllArmy", "Group1", "Group2", "Group3"]:
			var rect: Rect2 = _rect(button_name)
			rects.append(rect)
			var at: String = "%s: %s is %s" % [why, button_name, rect.size]
			assert_vector(rect.size).override_failure_message(at).is_equal_approx(
				Vector2(56.0, 56.0) * dp, Vector2.ONE
			)
		for first: int in rects.size():
			for second: int in range(first + 1, rects.size()):
				var apart: float = maxf(
					maxf(
						rects[first].position.x - rects[second].end.x,
						rects[second].position.x - rects[first].end.x
					),
					maxf(
						rects[first].position.y - rects[second].end.y,
						rects[second].position.y - rects[first].end.y
					)
				)
				var gap: String = (
					"%s: buttons %d and %d are %s px apart" % [why, first, second, apart]
				)
				assert_float(apart).override_failure_message(gap).is_greater_equal(8.0 * dp - 1.0)
		_controller.selection.clear()  # No unit selected: "+" goes too; and an empty group is hidden.
		assert_bool((_hud("AddGroup") as Control).visible).override_failure_message(why).is_false()
	await _open(UiProfiles.by_name(&"android_6in"))
	_select([1])
	assert_bool((_hud("Group3") as Control).visible).is_false()
	assert_vector(_rect("AddGroup").size).is_equal_approx(UiScale.dp_vec(56.0, 56.0), Vector2.ONE)


func test_the_column_stays_inside_the_safe_area_at_every_screen() -> void:
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, Vector2i(2424, 1080), Rect2i(152, 0, 2272, 1080)
	)
	var screens: Array[Dictionary] = _screens()
	screens.append({"label": "michael", "size": michael.window_size, "metrics": michael})
	for screen: Dictionary in screens:
		await _open(screen["metrics"], screen["size"])
		_save_groups(3)
		await await_idle_frame()
		var safe: Rect2 = UiScale.safe_rect_base()
		var why: String = "%s: %s in %s" % [screen["label"], _column(), safe]
		assert_bool(safe.encloses(_column())).override_failure_message(why).is_true()
		for button_name: String in ["AllArmy", "Group1", "Group2", "Group3"]:
			assert_bool(safe.encloses(_rect(button_name))).override_failure_message(why).is_true()


## Every side counts, a resize recomputes it and a 180 degree turn (the same window, the cutout on
## the other side) changes nothing. Dev is top-left, the column under it, on the 1600x720 canvas of
## android_6in.
func test_margins_follow_all_four_sides_of_the_safe_area_and_a_window_change() -> void:
	var android: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(UiProfiles.by_name(&"desktop"))
	UiScale.set_override(UiProfiles.with_safe_area(android, Rect2i(100, 30, 2250, 980)))
	get_window().size = android.window_size
	await await_idle_frame()
	# Insets 67, 20, 34 and 47 base px: the larger of each axis plus dp(12) = 21.
	assert_array(_margins()).is_equal([88, 68, 88, 68])
	assert_vector(_rect("DevButton").position).is_equal(Vector2(88, 68))
	assert_float(_column().position.x).is_equal(88.0)
	assert_float(_column().position.y).is_greater_equal(_rect("TopLeft").end.y + UiScale.dp(8.0))
	var font_size: int = (_hud("Group1") as Button).get_theme_font_size("font_size")
	assert_int(font_size).is_equal(roundi(UiScale.dp(18.0)))
	await _open(UiProfiles.with_safe_area(android, Rect2i(50, 70, 2250, 980)))  # Turned.
	assert_array(_margins()).is_equal([88, 68, 88, 68])


## The gaps between the buttons belong to the map.
func test_a_tap_in_the_gap_between_two_buttons_orders_the_selection() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	_select([1])  # "All army" and "+" show, a gap between them.
	var gap: Vector2 = Vector2(
		_rect("AllArmy").get_center().x,
		(_rect("AllArmy").end.y + _rect("AddGroup").position.y) * 0.5
	)
	TouchEvents.press(get_viewport(), 0, gap)
	TouchEvents.release(get_viewport(), 0, gap)
	assert_array(_sent).has_size(1)


func test_all_army_selects_the_30_tanks_off_screen_too_and_skips_units_that_cannot_move() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	_main.get_node("Camera").centre_on(Vector2(2800, 2800))  # Away from the block.
	_select([31, 40])
	_touch_button("AllArmy")
	assert_array(_controller.selection.selected).is_equal(range(1, 31))
	assert_array(_sent).is_empty()  # Selecting orders nothing.
	_main.get_node("MatchRunner").world.type_speed[0] = 0  # Every tank becomes a wall.
	_main.get_node("MatchRunner").run_ticks(1)  # The snapshot holds it from the next tick on.
	_touch_button("AllArmy")
	assert_array(_controller.selection.selected).is_empty()


## "+" saves the units in the lowest free group and shows it (with the buzz), a tap recalls a group,
## a hold overwrites it; "+" goes with the selection and when no group is free. No Command at all.
func test_plus_saves_into_the_lowest_free_group_tap_recalls_and_hold_overwrites() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var selection: SelectionModel = _controller.selection
	var column: GroupColumn = _hud("GroupColumn")
	assert_object(column.settings).is_same(load("res://data/input_settings.tres"))
	_controller.settings = _controller.settings.duplicate()
	_controller.settings.haptic_ms = 25  # Not the default: a hardcoded buzz fails.
	assert_bool((_hud("AddGroup") as Control).visible).is_false()  # Nothing selected.
	assert_array(_badges()).is_empty()
	_select([5, 3, 4])
	assert_bool((_hud("AddGroup") as Control).visible).is_true()
	_touch_button("AddGroup")
	assert_array(selection.group(1)).is_equal([3, 4, 5])
	assert_array(_badges()).is_equal(["1\n3"])
	assert_array(_buzzes).is_equal([25])
	_select([10])
	_touch_button("AddGroup")  # The next free one.
	assert_array(selection.group(2)).is_equal([10])
	assert_array(_badges()).is_equal(["1\n3", "2\n1"])
	_select([11, 12])
	_touch_button("Group1", 500)  # Hold: overwrite group 1, not group 3.
	assert_array(selection.group(1)).is_equal([11, 12])
	assert_array(selection.group(3)).is_empty()
	assert_array(_badges()).is_equal(["1\n2", "2\n1"])
	_touch_button("Group2", 499)  # Short of 500 ms, a tap: it recalls.
	assert_array(selection.selected).is_equal([10])
	assert_array(_buzzes).has_size(3)
	_touch_button("AddGroup")  # Third group.
	assert_array(selection.group(3)).is_equal([10])
	assert_bool((_hud("AddGroup") as Control).visible).is_false()  # None free.
	assert_array(_badges()).is_equal(["1\n2", "2\n1", "3\n1"])
	_controller.save_group()  # A call with no group free changes nothing.
	assert_array(_buzzes).has_size(4)
	_controller.settings.haptics_enabled = false
	selection.clear()
	assert_bool((_hud("AddGroup") as Control).visible).is_false()  # Nothing selected.
	_touch_button("Group3", 500)  # A hold with no unit selected changes nothing, and is silent.
	assert_array(selection.group(3)).is_equal([10])
	assert_array(_badges()).is_equal(["1\n2", "2\n1", "3\n1"])
	assert_array(_buzzes).has_size(4)
	assert_array(_sent).is_empty()


## "+" shows only while units are selected (a group free), and neither "+" nor a hold nor
## `save_group` does anything with no unit selected: the groups stay and the phone stays quiet.
func test_plus_and_a_hold_do_nothing_without_a_unit_selected() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var selection: SelectionModel = _controller.selection
	_select([1, 2])
	_touch_button("AddGroup")  # Group 1; groups 2 and 3 are free.
	assert_array(selection.group(1)).is_equal([1, 2])
	assert_bool((_hud("AddGroup") as Control).visible).is_true()
	assert_array(_buzzes).has_size(1)
	selection.clear()
	assert_bool((_hud("AddGroup") as Control).visible).is_false()  # Free groups, no unit.
	_controller.save_group()  # Nothing selected: the free group stays empty, no buzz.
	assert_array(selection.group(2)).is_empty()
	assert_array(_buzzes).has_size(1)
	_touch_button("Group1", 500)  # A hold with nothing selected: unchanged, silent.
	assert_array(selection.group(1)).is_equal([1, 2])
	assert_array(_buzzes).has_size(1)
	assert_array(_badges()).is_equal(["1\n2"])
	assert_array(_sent).is_empty()


## The badge shows the units a group still has, and a group that lost its last unit leaves the
## column. Nothing is selected when the first units die, so a refresh that waited for a selection
## change fails.
func test_a_groups_badge_shows_the_live_count_and_an_empty_group_leaves_the_column() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.paused = true  # Only run_ticks() moves time.
	_select(range(1, 31))
	_controller.assign_group(1)
	_select([1, 2, 21])
	_controller.assign_group(2)
	_select([1, 21, 25])
	_controller.assign_group(3)
	_controller.selection.clear()  # No selection to lose a unit: the badges follow the deaths alone.
	assert_array(_badges()).is_equal(["1\n30", "2\n3", "3\n3"])
	for row: int in 20:  # Tanks 1-20 die in the next tick.
		runner.world.hp[row] = 0
	runner.run_ticks(1)
	assert_array(_badges()).is_equal(["1\n10", "2\n1", "3\n2"])
	assert_array(_controller.selection.group(1)).is_equal(range(21, 31))
	_controller.tap_group(1)  # A recalled group holds the survivors only.
	assert_array(_controller.selection.selected).is_equal(range(21, 31))
	for row: int in 10:  # The other ten tanks of the group die, group 2's last one with them.
		runner.world.hp[row] = 0
	runner.run_ticks(1)
	assert_array(_badges()).is_empty()
	assert_array(_controller.selection.selected).is_empty()
	assert_array(_sent).is_empty()


## ADR 0025 section 2: four items (All army and three groups) take two columns on web_phone_small
## (2 to a column under the Dev stack). Upright, with no command bar yet (P122), the room is the 40
## %
## line down to the safe bottom, 270 dp at web_phone_portrait: 4 to a column, so one column; the
## two columns of the ADR's table come with the bar's 72 dp (test_hud_corners pins them).
func test_four_items_take_two_columns_on_the_small_phone_and_one_upright_without_the_bar() -> void:
	for profile_name: StringName in [&"web_phone_small", &"web_phone_portrait"]:
		await _open(UiProfiles.by_name(profile_name))
		assert_float(_column().size.x).is_equal_approx(UiScale.dp(56.0), 1.0)  # "All army" alone.
		_save_groups(3)
		await await_idle_frame()
		var xs: Dictionary = {}
		for button_name: String in ["AllArmy", "Group1", "Group2", "Group3"]:
			xs[snappedf(_rect(button_name).position.x, 1.0)] = true
		var want: int = 1 if profile_name == &"web_phone_portrait" else 2
		assert_int(xs.size()).override_failure_message(str(profile_name)).is_equal(want)
		var width: float = 56.0 if want == 1 else 120.0
		assert_float(_column().size.x).is_equal_approx(UiScale.dp(width), 1.5)


## At every screen, with the toast and the pill on, the column is clear of the pill, the attack
## toast, the Dev stack, the scope and BUILD, however many groups it holds.
func test_the_column_is_clear_of_the_pill_the_toast_the_stack_the_scope_and_build() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["metrics"], screen["size"])
		_save_groups(3)
		var toast: AttackToast = _hud("AttackToast")
		toast.visible = true
		toast.place()
		await await_idle_frame()
		var why: String = str(screen["label"])
		var column: Rect2 = _column()
		for other: String in ["EconomyPill", "RadarScope", "BuildButton", "TopLeft", "AttackToast"]:
			var rect: Rect2 = _rect(other)
			var at: String = "%s: column %s and %s %s" % [why, column, other, rect]
			assert_bool(column.intersects(rect)).override_failure_message(at).is_false()


## A finger on `control` for `held_ms` through the real GUI. With `frame`, a frame runs before it
## lifts, as it does while a finger rests.
func _hold(control: Control, held_ms: int, frame: bool = false) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += held_ms
	if frame and control is HoldButton:
		(control as HoldButton)._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)


func _touch_button(button_name: String, held_ms: int = 50) -> void:
	_hold(_hud(button_name) as Control, held_ms, true)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


## The SafeArea margins: left, top, right, bottom.
func _margins() -> Array[int]:
	var out: Array[int] = []
	for side: String in ["left", "top", "right", "bottom"]:
		out.append(_main.get_node("Hud/SafeArea").get_theme_constant("margin_" + side))
	return out


## A new main scene at `metrics` (null: the engine's own at `size`) with the fake clock, and the
## Commands and buzzes caught. Earlier ones stay until the test ends.
func _open(metrics: UiMetrics, size: Vector2i = Vector2i.ZERO) -> void:
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size if metrics == null else metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_sent.clear()
	_buzzes.clear()
	_controller = _main.get_node("PlayerController")
	assert_bool(_controller.vibrate == Callable(Input, &"vibrate_handheld")).is_true()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return _now_ms
	for slot: int in range(1, 4):
		(_hud("Group%d" % slot) as HoldButton).clock = func() -> int: return _now_ms


## The text of the group buttons that show.
func _badges() -> Array[String]:
	var texts: Array[String] = []
	for slot: int in range(1, 4):
		var button: Button = _hud("Group%d" % slot)
		if button.visible:
			texts.append((_hud("GroupColumn") as GroupColumn).badge_text(slot))
	return texts


## Saves group 1..`count` (units slot and slot + 10 each) and leaves one unit selected.
func _save_groups(count: int) -> void:
	for slot: int in range(1, count + 1):
		_select([slot, slot + 10])
		_controller.assign_group(slot)
	_select([1])


## The column's rect: the bounding box of the buttons that show.
func _column() -> Rect2:
	return _rect("GroupColumn")


## Screens: the six sizes with the engine's metrics, every profile of both orientations, each also
## with a cutout on the side of a phone's camera: {label, size, metrics}.
func _screens() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		out.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, 100, m.window_size.x, m.window_size.y - 100)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(100, 0, m.window_size.x - 100, m.window_size.y)
		out.append({"label": str(profile_name), "size": m.window_size, "metrics": m})
		out.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": UiProfiles.with_safe_area(m, cut)
			}
		)
	return out
