extends GdUnitTestSuite
## The HUD of the main scene (ADR 0004 section 5): HoldButton, ArmyBar and the SafeAreaMargin around
## them. Fingers are touches through the real GUI, time is a fake clock. Ids 1-30 are the player's.

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
	UiScale.clear_override()


func test_a_tap_emits_tapped_and_a_hold_emits_held_and_not_tapped() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()  # The stretch follows the window, and the theme's px follow the stretch.
	var bar: ArmyBar = auto_free(ArmyBar.new())
	bar.theme = HudThemes.scaled()  # Outside main.tscn nothing is inherited (P58).
	bar.settings = InputSettings.new()
	bar.settings.group_assign_ms = 700  # The hold time is data: the bar hands it to its buttons.
	add_child(bar)
	await await_idle_frame()
	var button: HoldButton = bar.get_node("Group3")
	assert_int(button.get_theme_font_size("font_size")).is_equal(roundi(UiScale.dp(18.0)))
	assert_bool(button.is_processing()).is_false()  # Frames watch the clock only with a finger down.
	assert_bool(button.clock == Callable(Time, &"get_ticks_msec")).is_true()
	button.clock = func() -> int: return _now_ms
	var events: Array[String] = []
	button.tapped.connect(func() -> void: events.append("tapped"))
	button.held.connect(func() -> void: events.append("held"))
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


func test_hud_buttons_have_their_sizes_in_dp_at_every_profile() -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	for profile_name: StringName in profiles:
		await _open(profiles[profile_name])
		var all_army: Vector2 = _rect("AllArmy").size
		assert_vector(all_army).is_equal_approx(UiScale.dp_vec(96.0, 56.0), Vector2.ONE)
		for slot: int in range(1, 4):
			var group: Vector2 = _rect("Group%d" % slot).size
			assert_vector(group).is_equal_approx(UiScale.dp_vec(56.0, 56.0), Vector2.ONE)


func test_hud_stays_inside_the_safe_area_with_a_100_px_cutout_and_on_michaels_phone() -> void:
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, Vector2i(2424, 1080), Rect2i(152, 0, 2272, 1080)
	)
	var cases: Array[UiMetrics] = [michael]
	for profile_name: StringName in UiProfiles.all():
		var m: UiMetrics = UiProfiles.by_name(profile_name)
		var cutout: Rect2i = Rect2i(100, 0, m.window_size.x - 100, m.window_size.y)
		cases.append(UiProfiles.with_safe_area(m, cutout))
	for m: UiMetrics in cases:
		await _open(m)
		var safe: Rect2 = UiScale.safe_rect_base()
		for button_name: String in ["DevButton", "AllArmy", "Group1", "Group2", "Group3"]:
			var why: String = "%s: %s in %s" % [m.window_size, _rect(button_name), safe]
			assert_bool(safe.encloses(_rect(button_name))).override_failure_message(why).is_true()
	await _open(michael)  # 152 px is 101.3 base px, rounded up to 102, plus dp(12) = 21.
	assert_float(_rect("DevButton").position.x).is_equal(123.0)


## Every side counts, a resize recomputes it and a 180 degree turn (the same window, the cutout on
## the other side) changes nothing. Dev is top-left, the army bar bottom-left, on the 1600x720
## canvas of android_6in.
func test_margins_follow_all_four_sides_of_the_safe_area_and_a_window_change() -> void:
	var android: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(UiProfiles.by_name(&"desktop"))
	UiScale.set_override(UiProfiles.with_safe_area(android, Rect2i(100, 30, 2250, 980)))
	get_window().size = android.window_size
	await await_idle_frame()
	# Insets 67, 20, 34 and 47 base px: the larger of each axis plus dp(12) = 21.
	assert_array(_margins()).is_equal([88, 68, 88, 68])
	assert_vector(_rect("DevButton").position).is_equal(Vector2(88, 68))
	assert_float(_rect("ArmyBar").end.y).is_equal(720.0 - 68.0)
	assert_int(_hud("ArmyBar").get_theme_constant("separation")).is_equal(roundi(UiScale.dp(8.0)))
	var font_size: int = (_hud("Group1") as Button).get_theme_font_size("font_size")
	assert_int(font_size).is_equal(roundi(UiScale.dp(18.0)))
	await _open(UiProfiles.with_safe_area(android, Rect2i(50, 70, 2250, 980)))  # Turned.
	assert_array(_margins()).is_equal([88, 68, 88, 68])


## The gaps between the buttons belong to the map.
func test_a_tap_in_the_gap_between_two_buttons_orders_the_selection() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	_select([1])
	var gap: Vector2 = Vector2(_rect("Group1").end.x + 1.0, _rect("Group1").get_center().y)
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


func test_hold_assigns_a_group_and_tap_recalls_it_and_the_count_updates() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var selection: SelectionModel = _controller.selection
	var bar: ArmyBar = _hud("ArmyBar")
	assert_object(bar.settings).is_same(load("res://data/input_settings.tres"))
	_controller.settings = _controller.settings.duplicate()
	_controller.settings.haptic_ms = 25  # Not the default: a hardcoded buzz fails.
	var recalls: Array[int] = []
	bar.group_tapped.connect(func(slot: int) -> void: recalls.append(slot))
	_select([5, 3, 4])
	_touch_button("Group3", 500)
	assert_array(selection.group(3)).is_equal([3, 4, 5])
	assert_str((_hud("Group3") as Button).text).is_equal("3\n3")
	assert_array(_buzzes).is_equal([25])
	assert_array(recalls).is_empty()  # A hold does not recall.
	_select([10])
	_touch_button("Group3", 499)  # Short of 500 ms, a tap.
	assert_array(selection.selected).is_equal([3, 4, 5])
	_select([10])
	_touch_button("Group1")  # An empty group changes nothing, and a tap assigns nothing.
	assert_array(selection.selected).is_equal([10])
	assert_array(selection.group(1)).is_empty()
	_touch_button("Group1", 500)
	assert_array(selection.group(1)).is_equal([10])
	assert_str((_hud("Group1") as Button).text).is_equal("1\n1")
	_controller.settings.haptics_enabled = false
	selection.clear()
	_touch_button("Group1", 500)  # The empty selection empties the group, and nothing buzzes.
	assert_str((_hud("Group1") as Button).text).is_equal("1")
	assert_array(_buzzes).has_size(2)
	assert_array(_sent).is_empty()


## The badge shows the units a group still has, and an empty group only its number. Nothing is
## selected when the first units die, so a badge refresh that waited for a selection change fails.
func test_a_groups_badge_shows_the_live_count_and_an_empty_group_only_its_number() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.paused = true  # Only run_ticks() moves time.
	_select(range(1, 31))
	_touch_button("Group1", 500)
	_select([1, 2, 21])
	_touch_button("Group2", 500)
	_select([1, 21, 25])
	_touch_button("Group3", 500)
	_controller.selection.clear()  # No selection to lose a unit: the badges follow the deaths alone.
	assert_array(_badges()).is_equal(["1\n30", "2\n3", "3\n3"])
	for row: int in 20:  # Tanks 1-20 die in the next tick.
		runner.world.hp[row] = 0
	runner.run_ticks(1)
	assert_array(_badges()).is_equal(["1\n10", "2\n1", "3\n2"])
	assert_array(_controller.selection.group(1)).is_equal(range(21, 31))
	assert_array(_controller.selection.group(2)).is_equal([21])
	assert_array(_controller.selection.group(3)).is_equal([21, 25])
	_controller.tap_group(1)  # A recalled group holds the survivors only.
	assert_array(_controller.selection.selected).is_equal(range(21, 31))
	for row: int in 10:  # The other ten tanks of the group die, group 2's last one with them.
		runner.world.hp[row] = 0
	runner.run_ticks(1)
	assert_array(_badges()).is_equal(["1", "2", "3"])
	assert_array(_controller.selection.selected).is_empty()
	assert_array(_sent).is_empty()


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


## A new main scene at `metrics` with the fake clock, and the Commands and buzzes caught. Earlier
## ones stay until the test ends.
func _open(metrics: UiMetrics) -> void:
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
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


## The text of the three group buttons.
func _badges() -> Array[String]:
	var texts: Array[String] = []
	for slot: int in range(1, 4):
		texts.append((_hud("Group%d" % slot) as Button).text)
	return texts
