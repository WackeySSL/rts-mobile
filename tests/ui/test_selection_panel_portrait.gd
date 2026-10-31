extends GdUnitTestSuite
## The SelectionPanel in portrait (plan P61, ADR 0015 section 5): the top line, right of the Dev
## button, one row high, with four fit levels, and never wider than its line. The mixed selections
## come from tests/ui/support/mvp_roster.gd. The line is changed with a cutout in the safe area, so
## a case can put it between the widths of two levels whatever the font measures.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Roster: GDScript = preload("res://tests/ui/support/mvp_roster.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LONG_NAME: String = "Heavily Armoured Experimental Siege Tank Destroyer Mark Seven"
## Rifle squads, rocket squads and light tanks: three types, the second row the shortest.
const THREE_TYPES: Array[int] = [12, 5, 7]
## The six MVP types with 3-digit counts: the worst case of the plan.
const SIX_TYPES: Array[int] = [120, 100, 150, 110, 130, 140]
## A portrait window wide enough for the first level of three types, at 1 px per dp (the stretch is
## 1.0: the base size turns to 720x1280 and the window is as high).
const WIDE_WINDOW: Vector2i = Vector2i(1000, 1280)
## A cutout shrinks the line by this much more than the widest case needs, in px: the least gap
## between two levels' widths that the cases may rely on.
const CASE_MARGIN_PX: float = 6.0

var _window_size_before: Vector2i
var _now_ms: int = 0
var _main: Node2D
var _controller: PlayerController
var _panel: SelectionPanel
var _sent: Array[Command] = []


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


func test_the_panel_is_one_row_in_the_top_line_right_of_the_dev_button_at_every_portrait_profile(
) -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.portrait()
	for profile_name: StringName in profiles:
		await _open(profiles[profile_name])
		var dev: Rect2 = _rect("DevButton")
		var bar: Rect2 = _rect("ArmyBar")
		var safe: Rect2 = UiScale.safe_rect_base()
		var screen: Rect2 = get_viewport().get_visible_rect()
		var right: float = (
			screen.end.x - (_hud("SafeArea") as Control).get_theme_constant("margin_right")
		)
		for types: int in [1, 2, 3, 6]:
			var counts: Array[int] = []
			counts.resize(types)
			counts.fill(7)
			Roster.select(self, _panel, counts)
			await await_idle_frame()
			var rect: Rect2 = _panel.get_global_rect()
			var why: String = "%s, %d types: panel %s" % [profile_name, types, rect]
			assert_bool(_panel.visible).override_failure_message(why).is_true()
			assert_bool(_panel._list.vertical).override_failure_message(why).is_false()
			assert_float(rect.size.y).override_failure_message(why).is_between(
				UiScale.dp(48.0), UiScale.dp(72.0)
			)
			var centres: Array[float] = _centres()
			assert_float(centres.max() - centres.min()).override_failure_message(why).is_less(2.0)
			assert_float(rect.position.y).override_failure_message(why).is_equal_approx(
				dev.position.y, 0.5
			)
			var gap: float = rect.position.x - dev.end.x  # 8 dp, rounded up to a whole px.
			assert_float(gap).override_failure_message(why).is_between(
				UiScale.dp(8.0) - 0.5, UiScale.dp(8.0) + 1.5
			)
			assert_float(rect.end.x).override_failure_message(why).is_less_equal(right + 0.5)
			assert_bool(safe.encloses(rect)).override_failure_message(why).is_true()
			assert_bool(rect.intersects(dev)).override_failure_message(why).is_false()
			assert_bool(rect.intersects(bar)).override_failure_message(why).is_false()
			var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()  # It must not grow.
			assert_that(area).override_failure_message(why).is_equal(screen)


## The widths come from the panel itself at each level, and the line of each case is set just
## above one of them with a cutout (the safe area's inset), so the case does not depend on what
## the font measures. The panel starts wide enough for the first level.
func test_each_fit_level_is_reached_by_a_case_built_for_it() -> void:
	var wide: UiMetrics = UiMetrics.create("Linux", 96, 1.0, 1.0, WIDE_WINDOW, Rect2i())
	await _open(wide)
	Roster.select(self, _panel, THREE_TYPES)
	await await_idle_frame()
	assert_int(_panel._level).is_equal(SelectionPanel.LEVEL_NAMED)
	var band: Control = _panel.get_parent()
	var left: int = band.get_theme_constant("margin_left")
	var steps: Array[Array] = [  # [level, rows] and what is shown: names, total, chip text.
		[SelectionPanel.LEVEL_NAMED, 3],
		[SelectionPanel.LEVEL_ICONS, 3],
		[SelectionPanel.LEVEL_NO_TOTAL, 3],
		[SelectionPanel.LEVEL_CHIP, 2],
		[SelectionPanel.LEVEL_CHIP, 1],
	]
	var shown: Array[Array] = [
		[true, true, ""],
		[false, true, ""],
		[false, false, ""],
		[false, false, "+1"],
		[false, false, "+2"],
	]
	var need: Array[float] = []
	for step: Array in steps:
		_panel._show_level(step[0], step[1])
		need.append(_panel.get_combined_minimum_size().x)
	for index: int in range(1, need.size()):  # Each level is narrower, by more than the margin.
		var why: String = "level width %d: %s" % [index, need]
		assert_float(need[index - 1] - need[index]).override_failure_message(why).is_greater(
			2.0 * CASE_MARGIN_PX
		)
	var screen_px: float = get_viewport().get_visible_rect().size.x
	var gap: int = roundi(UiScale.dp(12.0))
	for index: int in steps.size():
		var inset: int = floori((screen_px - left - (need[index] + CASE_MARGIN_PX)) / 2.0) - gap
		var cutout: Rect2i = Rect2i(inset, 0, wide.window_size.x - inset, wide.window_size.y)
		await _open(UiProfiles.with_safe_area(wide, cutout))
		Roster.select(self, _panel, THREE_TYPES)
		await await_idle_frame()
		var line: float = screen_px - 2.0 * (inset + gap) - left
		var label: String = (
			"case %d (level %d, %d rows), line %.1f, widths %s"
			% [index, steps[index][0], steps[index][1], line, need]
		)
		assert_int(_panel._level).override_failure_message(label).is_equal(steps[index][0])
		assert_array(_shown_rows()).override_failure_message(label).has_size(steps[index][1])
		assert_bool(_shown_rows()[0].title.visible).override_failure_message(label).is_equal(
			shown[index][0]
		)
		assert_bool(_panel._total.visible).override_failure_message(label).is_equal(shown[index][1])
		var chip: String = (
			"" if _panel._chip == null or not _panel._chip.visible else _panel._chip.text
		)
		assert_str(chip).override_failure_message(label).is_equal(shown[index][2])
		assert_float(_panel.size.x).override_failure_message(label).is_less_equal(line + 0.5)
		(
			assert_float(_panel.get_combined_minimum_size().x)
			. override_failure_message(label)
			. is_between(need[index] - 0.5, line + 0.5)
		)


## The plan's worst case: six types with 3-digit counts on a 360 dp wide phone with the Dev
## button. The panel keeps its line, shows a row or more and says how many types it left out; a
## smaller selection brings the first level back.
func test_six_types_with_3_digit_counts_fit_the_line_of_a_360_dp_phone_with_a_chip() -> void:
	await _open(UiProfiles.by_name(&"web_phone_portrait"))
	var dev: Rect2 = _rect("DevButton")
	var safe: Rect2 = UiScale.safe_rect_base()
	Roster.select(self, _panel, SIX_TYPES)
	await await_idle_frame()
	var rect: Rect2 = _panel.get_global_rect()
	var chip: Label = _panel._chip
	var rows: int = _shown_rows().size()
	assert_int(_panel._level).is_equal(SelectionPanel.LEVEL_CHIP)
	assert_int(rows).is_between(1, 5)
	assert_bool(chip != null and chip.visible).is_true()
	assert_str(chip.text).is_equal("+%d" % (6 - rows))
	assert_bool(_panel._total.visible).is_false()
	assert_bool(safe.encloses(rect)).override_failure_message(str(rect)).is_true()
	assert_bool(rect.intersects(dev)).override_failure_message(str(rect)).is_false()
	assert_bool(rect.intersects(_rect("ArmyBar"))).override_failure_message(str(rect)).is_false()
	assert_float(rect.size.y).is_less_equal(UiScale.dp(72.0))
	for row: SelectionPanel.Row in _shown_rows():  # Icon and count only.
		assert_bool(row.title.visible).is_false()
		assert_bool(row.count.text.begins_with("×1")).is_true()
	var one: Array[int] = [7]
	Roster.select(self, _panel, one)  # A smaller selection starts again at the first level.
	await await_idle_frame()
	assert_int(_panel._level).is_equal(SelectionPanel.LEVEL_NAMED)
	assert_bool(chip.visible).is_false()
	assert_bool(_shown_rows()[0].title.visible).is_true()
	assert_bool(_panel._total.visible).is_false()  # One type.


## A name is cut at the line and not at 40% of the whole width: "Flarejack" shows whole on a 360 dp
## phone, and a very long name still keeps the panel inside its line.
func test_a_name_is_cut_at_the_line_and_light_tank_is_whole_on_a_360_dp_phone() -> void:
	await _open(UiProfiles.by_name(&"web_phone_portrait"))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.paused = true
	_panel.set_selected(PackedInt32Array([1, 2]))
	await await_idle_frame()
	var title: Label = _panel.get_node("Rows/Row0/Name")
	assert_str(title.text).is_equal("Flarejack")
	assert_float(title.size.x).is_greater_equal(_text_px(title))
	assert_int(_panel._level).is_equal(SelectionPanel.LEVEL_NAMED)
	runner.snapshot.type_names[0] = LONG_NAME
	_panel.set_selected(PackedInt32Array([1, 2]))
	await await_idle_frame()
	var right: float = _hud("SafeArea").get_global_rect().end.x
	right -= (_hud("SafeArea") as Control).get_theme_constant("margin_right")
	assert_str(title.text).is_equal(LONG_NAME)  # The text stays whole; the draw clips it.
	assert_float(_text_px(title)).is_greater(title.size.x)
	assert_float(_panel.get_global_rect().end.x).is_less_equal(right + 0.5)
	assert_int(_panel._level).is_equal(SelectionPanel.LEVEL_NAMED)  # One row: the name gives way.


## Without a Dev button (a release build hides it) the line starts at the safe area's left edge.
func test_without_the_dev_button_the_line_starts_at_the_left_edge() -> void:
	await _open(UiProfiles.by_name(&"android_6in_portrait"))
	Roster.select(self, _panel, THREE_TYPES)
	await await_idle_frame()
	var with_dev: float = _panel.get_global_rect().position.x
	(_hud("DevButton") as Control).visible = false
	_panel.set_selected(PackedInt32Array(range(1, 25)))
	await await_idle_frame()
	var edge: float = _hud("SafeArea").get_global_rect().position.x
	edge += (_hud("SafeArea") as Control).get_theme_constant("margin_left")
	assert_float(_panel.get_global_rect().position.x).is_equal_approx(edge, 0.5)
	assert_float(with_dev).is_greater(edge + UiScale.dp(48.0))


## The panel keeps its touches in its new place: a tap on it orders nothing and keeps the selection,
## and a tap on plain ground beside it still moves the units.
func test_a_tap_on_the_portrait_panel_orders_nothing_and_a_tap_on_the_ground_does() -> void:
	await _open(UiProfiles.by_name(&"android_6in_portrait"))
	_controller.selection.set_ids(PackedInt32Array([1, 2]))
	await await_idle_frame()
	assert_int(_panel.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_tap(_panel.get_global_rect().get_center())
	assert_array(_sent).is_empty()
	assert_array(_controller.selection.selected).is_equal([1, 2])
	_tap(Vector2(690, 1000))  # Plain ground, clear of the tanks, the panel, the army bar and the band.
	assert_array(_sent).has_size(1)


## The rows that show, in the panel's order.
func _shown_rows() -> Array[SelectionPanel.Row]:
	var out: Array[SelectionPanel.Row] = []
	for row: SelectionPanel.Row in _panel._rows:
		if row.visible:
			out.append(row)
	return out


## The vertical centres of what the line shows (rows, total, chip), in px: within a px or two of
## each other when it is one line (a label centres itself in the line, a row fills it).
func _centres() -> Array[float]:
	var centres: Array[float] = []
	for child: Node in _panel._list.get_children():
		var control: Control = child as Control
		if control.visible:
			centres.append(control.get_global_rect().get_center().y)
	return centres


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


## The width of the label's whole text at its font size: what it would need without a cap.
func _text_px(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var font_px: int = label.get_theme_font_size(&"font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x


## A new main scene at `metrics`, its SelectionPanel shown in `_panel`.
func _open(metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_sent.clear()
	_controller = _main.get_node("PlayerController")
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return _now_ms
	_panel = _hud("SelectionPanel")
