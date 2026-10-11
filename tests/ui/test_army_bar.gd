extends GdUnitTestSuite
## The HUD of the main scene (ADR 0004 section 5): HoldButton, ArmyBar and the SafeAreaMargin around
## them. Fingers are touches through the real GUI, time is a fake clock. Ids 1-30 are the player's.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

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
	get_window().size = Vector2i(1280, 720)
	var bar: ArmyBar = auto_free(ArmyBar.new())
	bar.settings = InputSettings.new()
	bar.settings.group_assign_ms = 700  # The hold time is data: the bar hands it to its buttons.
	add_child(bar)
	await await_idle_frame()
	var button: HoldButton = bar.get_node("Group3")
	button.clock = func() -> int: return _now_ms
	var events: Array[String] = []
	button.tapped.connect(func() -> void: events.append("tapped"))
	button.held.connect(func() -> void: events.append("held"))
	for case: Array in [[0, "tapped"], [699, "tapped"], [700, "held"], [2000, "held"]]:
		events.clear()
		_hold(button, case[0])  # No frame runs between the time passing and the release.
		assert_array(events).override_failure_message(str(case)).is_equal([case[1]])
	var at: Vector2 = button.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	assert_bool(button.is_processing()).is_true()  # Frames watch the clock while a finger is down.
	TouchEvents.release(get_viewport(), 0, at)
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


## Every side counts and a resize recomputes it. Dev is top-left, the army bar bottom-left, on the
## 1600x720 canvas of android_6in.
func test_margins_follow_all_four_sides_of_the_safe_area_and_a_window_change() -> void:
	var android: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(UiProfiles.by_name(&"desktop"))
	UiScale.set_override(UiProfiles.with_safe_area(android, Rect2i(100, 30, 2250, 1000)))
	get_window().size = android.window_size
	await await_idle_frame()
	# Left 66.7 up to 67, top 20, right and bottom 33.3 up to 34, each plus dp(12) = 21.
	assert_array(_margins()).is_equal([88, 41, 55, 55])
	assert_vector(_rect("DevButton").position).is_equal(Vector2(88, 41))
	assert_float(_rect("ArmyBar").position.x).is_equal(88.0)
	assert_float(_rect("ArmyBar").end.y).is_equal(720.0 - 55.0)


func test_all_army_selects_the_30_tanks_off_screen_too_and_skips_units_that_cannot_move() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	_main.get_node("Camera").centre_on(Vector2(2800, 2800))  # Away from the block.
	_select([31, 40])
	_touch_button("AllArmy")
	assert_array(_controller.selection.selected).is_equal(range(1, 31))
	assert_array(_sent).is_empty()  # Selecting orders nothing.
	_main.get_node("MatchRunner").world.type_speed[0] = 0  # Every tank becomes a wall.
	_touch_button("AllArmy")
	assert_array(_controller.selection.selected).is_empty()


func test_hold_assigns_a_group_and_tap_recalls_it_and_the_count_updates() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var selection: SelectionModel = _controller.selection
	_select([5, 3, 4])
	_touch_button("Group2", 500)
	assert_array(selection.group(2)).is_equal([3, 4, 5])
	assert_str((_hud("Group2") as Button).text).is_equal("2\n3")
	assert_array(_buzzes).is_equal([15])
	assert_array(selection.selected).is_equal([3, 4, 5])  # A hold does not recall.
	_select([10])
	_touch_button("Group2", 499)  # Short of 500 ms, a tap.
	assert_array(selection.selected).is_equal([3, 4, 5])
	_select([10])
	_touch_button("Group3")  # An empty group changes nothing, and a tap assigns nothing.
	assert_array(selection.selected).is_equal([10])
	assert_array(selection.group(3)).is_empty()
	_touch_button("Group1", 500)
	assert_array(selection.group(1)).is_equal([10])
	_controller.settings = _controller.settings.duplicate()
	_controller.settings.haptics_enabled = false
	selection.clear()
	_touch_button("Group1", 500)  # The empty selection empties the group, and nothing buzzes.
	assert_str((_hud("Group1") as Button).text).is_equal("1")
	assert_array(_buzzes).has_size(2)
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
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return _now_ms
	for slot: int in range(1, 4):
		(_hud("Group%d" % slot) as HoldButton).clock = func() -> int: return _now_ms
