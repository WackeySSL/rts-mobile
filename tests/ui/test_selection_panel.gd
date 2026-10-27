extends GdUnitTestSuite
## The SelectionPanel in the main scene (P21): one row per unit type with its art, name and count,
## a total for several types, and a place in the safe area between the ArmyBar and the right fifth.
## Fingers are touches through the real GUI, time is a fake clock. Tank n is row n - 1 of the
## 6-column block, and ids 1-30 are the player's.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const CARD: String = "res://assets/art/iso/icons/item_light_tank.svg"
const LONG_NAME: String = "Heavily Armoured Experimental Siege Tank Destroyer Mark Seven"

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
	UiScale.clear_override()


func test_the_count_follows_every_way_the_selection_changes() -> void:
	await _open(UiProfiles.by_name(&"desktop"))
	var layer: UnitLayer = _main.get_node("UnitLayer")
	var first: Vector2 = layer.unit_screen_position(0)
	assert_bool(_panel.visible).is_false()
	_tap(first)  # A real finger through the GUI and TouchInput.
	_expect("tap", "×1")
	assert_bool(_node("Rows/Total").visible).is_false()  # One type: no total.
	var card: TextureRect = _node("Rows/Row0/Icon/Card")  # The generated item card (P99b).
	assert_str(card.texture.resource_path).is_equal(CARD)
	assert_that(card.modulate).is_equal(Color.WHITE)  # Its colours are its own.
	_gesture(GestureEvent.Kind.DOUBLE_TAP, first)
	_expect("double-tap", "×30")
	# The top of the diamond block under the 2:1 projection (P117): world (-440, 410) to (-200, 490)
	# holds the six tanks 1, 2, 3, 7, 8 and 13 and no other.
	var camera: RtsCamera = _main.get_node("Camera")
	var top_left: Vector2 = camera.world_to_screen(Vector2(-440, 410))
	var top_box: Rect2 = Rect2(top_left, camera.world_to_screen(Vector2(-200, 490)) - top_left)
	_gesture(GestureEvent.Kind.BOX_END, first, top_box)
	_expect("box", "×6")
	_gesture(GestureEvent.Kind.BOX_END, first, Rect2(80, 300, 220, 200))  # No tank in it.
	assert_bool(_panel.visible).override_failure_message("empty box").is_false()
	_tap(_hud("AllArmy").get_global_rect().get_center())
	_expect("All army", "×30")
	_select([1, 2, 3])
	_controller.assign_group(1)
	_select([9])
	_expect("one tank", "×1")
	_controller.tap_group(1)
	_expect("group", "×3")
	_controller.selection.clear()
	assert_bool(_panel.visible).override_failure_message("cleared").is_false()
	assert_array(_sent).is_empty()  # Selecting orders nothing.


## Phase 1 has one type, so a scenario of its own gives two: a tank (ids 1-2) and a scout (ids 3-5)
## with no display name and no art.
func test_two_types_get_a_row_each_and_a_total_and_the_rows_are_reused() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	var scout: UnitDef = UnitDef.new()
	scout.type_id = &"scout_test"
	for pair: Array in [[load("res://data/units/light_tank.tres"), 2], [scout, 3]]:
		var spawn: SpawnDef = SpawnDef.new()
		spawn.owner = 1
		spawn.unit = pair[0]
		spawn.count = pair[1]
		scenario.spawns.append(spawn)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = scenario
	runner.paused = true
	add_child(runner)
	_panel = auto_free(SelectionPanel.new())
	_panel.runner = runner
	_panel.theme = HudThemes.scaled()  # Outside main.tscn nothing is inherited (P58).
	add_child(_panel)
	_panel.set_selected(PackedInt32Array([1, 2, 3, 4, 5, 999]))  # 999 is no unit.
	assert_array(_texts("Row0")).is_equal(["Flarejack", "×2"])
	assert_array(_texts("Row1")).is_equal(["Scout Test", "×3"])
	assert_str((_node("Rows/Total") as Label).text).is_equal("Total ×5")
	var sizes: Array[int] = []  # The look is the theme's: names 16 dp, counts and total 20 dp.
	for path: String in ["Rows/Row0/Name", "Rows/Row0/Count", "Rows/Total"]:
		sizes.append(_node(path).get_theme_font_size("font_size"))
	assert_array(sizes).is_equal([_px(16.0), _px(20.0), _px(20.0)])
	var backdrop: StyleBoxFlat = _panel.get_theme_stylebox("panel")
	assert_that(backdrop.bg_color).is_equal(Color(0.06, 0.08, 0.11, 0.78))
	assert_bool(_node("Rows/Total").visible).is_true()
	assert_int(_node("Rows/Total").get_index()).is_equal(2)  # Below the rows.
	assert_object((_node("Rows/Row1/Icon/Card") as TextureRect).texture).is_null()  # No card.
	await await_idle_frame()
	for row_name: String in ["Row0", "Row1"]:  # Without a band there is no cap.
		var title: Label = _node("Rows/%s/Name" % row_name)
		assert_float(title.size.x).is_greater_equal(_text_px(title))
	var row0: Node = _node("Rows/Row0")
	_panel.set_selected(PackedInt32Array([4]))
	assert_object(_node("Rows/Row0")).is_same(row0)  # Reused, now the scout.
	assert_array(_texts("Row0")).is_equal(["Scout Test", "×1"])
	assert_object((_node("Rows/Row0/Icon/Card") as TextureRect).texture).is_null()  # Not the tank's.
	assert_bool(_node("Rows/Row1").visible).is_false()
	assert_bool(_node("Rows/Total").visible).is_false()
	assert_int(_node("Rows").get_child_count()).is_equal(3)  # Two rows and the total, none new.
	_panel.set_selected(PackedInt32Array([999]))
	assert_bool(_panel.visible).is_false()  # An unknown id on its own shows nothing.


func test_a_tap_on_the_panel_orders_nothing_and_keeps_the_selection() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	_select([1, 2])
	await await_idle_frame()
	assert_int(_panel.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_tap(_panel.get_global_rect().get_center())
	assert_array(_sent).is_empty()
	assert_array(_controller.selection.selected).is_equal([1, 2])
	_tap(Vector2(1200, 400))  # Plain ground, clear of the tanks and the panel: this does order.
	assert_array(_sent).has_size(1)


func test_the_panel_is_dp_sized_and_sits_in_its_band_in_both_orientations() -> void:
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, Vector2i(2424, 1080), Rect2i(152, 0, 2272, 1080)
	)
	var xhdpi: UiMetrics = UiMetrics.create(
		"Android", 320, 1.0, 1.0, ScreenSizes.LANDSCAPE[0], Rect2i()
	)
	var cases: Array[UiMetrics] = [michael, xhdpi]  # xhdpi is 2 base px per dp: the tightest fit.
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cutout: Rect2i = Rect2i(100, 0, m.window_size.x - 100, m.window_size.y)
		if UiScale.is_portrait_size(m.window_size):  # The camera is at the top.
			cutout = Rect2i(0, 100, m.window_size.x, m.window_size.y - 100)
		cases.append(m)
		cases.append(UiProfiles.with_safe_area(m, cutout))
	for m: UiMetrics in cases:
		await _open(m)
		_select(range(1, 31))
		await await_idle_frame()
		var rect: Rect2 = _panel.get_global_rect()
		var bar: Rect2 = (_hud("ArmyBar") as Control).get_global_rect()
		var width: float = get_viewport().get_visible_rect().size.x
		var sidebar: float = HudLayout.right_zone_px(_inner_width())  # The build panel and a gap.
		var why: String = "%s: panel %s, bar %s" % [m.window_size, rect, bar]
		var sizes: Array[int] = []
		for path: String in ["Rows/Row0/Name", "Rows/Row0/Count", "Rows/Total"]:
			sizes.append(_node(path).get_theme_font_size("font_size"))
		var pinned: Array[int] = [_px(16.0), _px(20.0), _px(20.0)]  # Name, count, total.
		assert_array(sizes).override_failure_message(why).is_equal(pinned)
		for part: String in ["", "/Card"]:  # The icon and its picture.
			var icon: Vector2 = (_node("Rows/Row0/Icon" + part) as Control).size
			var icon_dp: Vector2 = UiScale.dp_vec(40.0, 40.0)
			assert_vector(icon).override_failure_message(why).is_equal_approx(icon_dp, Vector2.ONE)
		assert_float(rect.size.y).override_failure_message(why).is_greater_equal(UiScale.dp(48.0))
		assert_float(rect.size.y).override_failure_message(why).is_less_equal(UiScale.dp(72.0))
		assert_float(rect.size.x).override_failure_message(why).is_less_equal(UiScale.dp(260.0))
		var dev: Rect2 = (_hud("DevButton") as Control).get_global_rect()
		var safe: Rect2 = UiScale.safe_rect_base()
		for hud: Rect2 in [rect, bar, dev]:  # A selection must not push the HUD off the screen.
			assert_bool(safe.encloses(hud)).override_failure_message(why).is_true()
		var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()  # It must not grow.
		assert_that(area).override_failure_message(why).is_equal(get_viewport().get_visible_rect())
		assert_bool(rect.intersects(bar)).override_failure_message(why).is_false()
		if UiScale.is_portrait_size(m.window_size):  # The top line, level with the Dev button.
			assert_float(rect.position.y).override_failure_message(why).is_equal_approx(
				dev.position.y, 0.5
			)
			continue  # The rest is the landscape band (test_selection_panel_portrait has the line).
		assert_float(rect.end.y).override_failure_message(why).is_equal_approx(bar.end.y, 0.5)
		if m == xhdpi:  # No room for the whole zone beside the panel: the zone gives way.
			continue
		assert_float(rect.end.x).override_failure_message(why).is_less_equal(width - sidebar)
		var band: Control = _panel.get_parent()  # It reserves the whole zone, not just the panel.
		assert_int(band.get_theme_constant("margin_right")).is_equal(ceili(sidebar))
		var centre: float = rect.get_center().x
		assert_float(centre).override_failure_message(why).is_between(width * 0.4, width * 0.65)


## The band and the text follow a window change, as on a phone browser's toolbar or a turn.
func test_the_band_and_the_text_follow_a_window_resize() -> void:
	await _open(UiProfiles.by_name(&"desktop"))
	_select([1])
	var android: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(android)
	get_window().size = android.window_size
	await await_idle_frame()
	var zone: float = HudLayout.right_zone_px(_inner_width())
	assert_int(_panel.get_parent().get_theme_constant("margin_right")).is_equal(ceili(zone))
	assert_int(_node("Rows/Row0/Name").get_theme_font_size("font_size")).is_equal(_px(16.0))
	var title: Label = _node("Rows/Row0/Name")  # The cap is in px, so it is fitted again.
	assert_str(title.text).is_equal("Flarejack")
	assert_float(title.size.x).is_greater_equal(_text_px(title))


## The data's name ("Flarejack") is no capitalised type id ("Light Tank"), so a name written
## into the snapshot alone shows that the panel takes it from `type_names`. The World is swapped
## for an empty one after a tick: the counts and the names must come from the published snapshot.
func test_names_and_counts_come_from_the_snapshot_and_never_the_world() -> void:
	await _open(UiProfiles.by_name(&"desktop"))
	_runner().paused = true
	_select([1, 2])
	_expect("the data's display name", "×2")
	_runner().run_ticks(1)
	_runner().world = World.new()  # Test-only: an empty World where the match's was.
	assert_int(_runner().world.unit_count()).is_equal(0)
	_runner().snapshot.type_names[0] = "Ironclad"
	_panel.set_selected(PackedInt32Array([1, 2, 3, 999]))
	assert_bool(_panel.visible).is_true()
	assert_array(_texts("Row0")).is_equal(["Ironclad", "×3"])
	assert_str(_panel.get_node("Rows/Row0/Name").text).is_not_equal("Flarejack")


## A row is at most 40% of the band (the safe area's inner width) and at most what the ArmyBar and
## the build panel's zone leave of it: a name past that is clipped with an ellipsis, and the icon
## and the count keep their room. "Flarejack" is not clipped. On the phones the second limit is
## the lower one, and the zone keeps its whole width: the panel ends before the build panel's gap.
func test_a_long_name_is_clipped_at_the_cap_and_light_tank_is_not() -> void:
	for profile: StringName in [&"desktop", &"android_6in", &"web_tablet", &"web_phone_small"]:
		await _open(UiProfiles.by_name(profile))
		_runner().paused = true
		_select([1])
		await await_idle_frame()
		var title: Label = _node("Rows/Row0/Name")
		assert_int(title.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		assert_float(title.size.x).override_failure_message(str(profile)).is_greater_equal(
			_text_px(title)
		)
		_runner().snapshot.type_names[0] = LONG_NAME
		_panel.set_selected(PackedInt32Array([1]))
		await await_idle_frame()
		_assert_capped("Row0", str(profile))
		(
			assert_bool(_panel.get_global_rect().intersects(_hud("ArmyBar").get_global_rect()))
			. is_false()
		)
		var zone: float = HudLayout.right_zone_px(_inner_width())
		assert_int(_panel.get_parent().get_theme_constant("margin_right")).is_equal(ceili(zone))
		var edge: float = get_viewport().get_visible_rect().end.x
		var zone_start: float = edge - _hud("SafeArea").get_theme_constant("margin_right") - zone
		var panel_end: float = _panel.get_global_rect().end.x
		assert_float(panel_end).override_failure_message(str(profile)).is_less_equal(
			zone_start + 0.5
		)


## The cap is per row. The scenario gets a second type, the rifle squad (units 41 and 42), and the
## names are written into the snapshot: both long, then only the second, then only the first.
func test_every_row_is_capped_and_a_short_name_on_either_row_is_not() -> void:
	await _open(UiProfiles.by_name(&"android_6in"))
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = load("res://data/units/rifle_squad.tres")
	spawn.count = 2
	spawn.origin_tile = Vector2i(8, 14)
	var scenario: ScenarioDef = _runner().scenario.duplicate()
	scenario.spawns = scenario.spawns.duplicate()
	scenario.spawns.append(spawn)
	_runner().scenario = scenario
	_runner().paused = true
	_runner().start()
	await await_idle_frame()
	var snap: MatchSnapshot = _runner().snapshot
	for names: Array in [
		[LONG_NAME, LONG_NAME], ["Light Tank", LONG_NAME], [LONG_NAME, "Rifle Squad"]
	]:
		snap.type_names[0] = names[0]
		snap.type_names[1] = names[1]
		_panel.set_selected(PackedInt32Array([1, 41, 42]))
		await await_idle_frame()
		assert_bool(_node("Rows/Total").visible).is_true()
		assert_str(_texts("Row1")[1]).is_equal("×2")
		for at: int in 2:
			var row_name: String = "Row%d" % at
			var why: String = "%s, %s" % [names, row_name]
			if names[at] == LONG_NAME:
				_assert_capped(row_name, why)
				continue
			var title: Label = _node("Rows/%s/Name" % row_name)
			assert_str(title.text).is_equal(names[at])
			assert_float(title.size.x).override_failure_message(why).is_greater_equal(
				_text_px(title)
			)


func test_the_count_drops_when_a_selected_tank_dies_and_the_panel_hides_with_the_last() -> void:
	await _open(UiProfiles.by_name(&"desktop"))
	_runner().paused = true
	_select([1, 2, 3])
	_expect("three", "×3")
	_runner().world.hp[0] = 0  # Tank 1 dies in the next tick.
	_runner().run_ticks(1)
	_expect("tank 1 dead", "×2")
	assert_array(_controller.selection.selected).is_equal([2, 3])
	_runner().world.hp[0] = 0
	_runner().world.hp[1] = 0
	_runner().run_ticks(1)
	assert_bool(_panel.visible).override_failure_message("all dead").is_false()
	assert_array(_sent).is_empty()


## With no snapshot to count from the panel hides, also when it was showing: a runner that has not
## started a match (no scenario) has published none, and a panel may have no runner at all.
func test_with_no_snapshot_to_count_from_the_panel_hides() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())  # No scenario: start() never runs.
	add_child(runner)
	assert_object(runner.snapshot).is_null()
	_panel = auto_free(SelectionPanel.new())
	_panel.runner = runner
	_panel.theme = HudThemes.scaled()  # Outside main.tscn nothing is inherited (P58).
	add_child(_panel)
	_panel.visible = true
	_panel.set_selected(PackedInt32Array([1]))
	assert_bool(_panel.visible).override_failure_message("no snapshot").is_false()
	_panel.runner = null
	_panel.visible = true
	_panel.set_selected(PackedInt32Array([1]))
	assert_bool(_panel.visible).override_failure_message("no runner").is_false()


## The row `row_name` is the cap wide, its name clipped, and its icon and count keep their room.
func _assert_capped(row_name: String, why: String) -> void:
	var band_px: float = (_panel.get_parent() as Control).size.x
	var cap: float = _row_cap(band_px)
	var row: Control = _node("Rows/" + row_name)
	var title: Label = _node("Rows/%s/Name" % row_name)
	var count: Label = _node("Rows/%s/Count" % row_name)
	var detail: String = "%s: row %s, cap %s, band %s" % [why, row.size.x, cap, band_px]
	assert_str(title.text).is_equal(LONG_NAME)  # The text stays whole; the draw clips it.
	assert_float(_text_px(title)).override_failure_message(detail).is_greater(cap)
	# The box layout rounds sizes to whole px, so the row is the cap to within a px or two.
	assert_float(row.size.x).override_failure_message(detail).is_less_equal(cap + 1.5)
	assert_float(row.size.x).override_failure_message(detail).is_greater_equal(cap - 1.5)
	assert_float(title.size.x).override_failure_message(detail).is_greater(UiScale.dp(16.0))
	assert_float(count.size.x).override_failure_message(detail).is_greater_equal(
		count.get_combined_minimum_size().x
	)


## The widest a row may be in landscape: 40% of the band, or what the ArmyBar and the build panel's
## zone leave of it less the backdrop's padding, whichever is less.
func _row_cap(band_px: float) -> float:
	var left: float = ceilf(_hud("ArmyBar").get_combined_minimum_size().x + UiScale.dp(8.0))
	var room: float = band_px - left - ceilf(HudLayout.right_zone_px(band_px))
	return minf(band_px * 0.4, room - _panel.get_theme_stylebox(&"panel").get_minimum_size().x)


func _expect(step: String, count: String) -> void:
	assert_bool(_panel.visible).override_failure_message(step).is_true()
	assert_array(_texts("Row0")).override_failure_message(step).is_equal(["Flarejack", count])


func _texts(row: String) -> Array[String]:
	var title: Label = _node("Rows/%s/Name" % row)
	return [title.text, (_node("Rows/%s/Count" % row) as Label).text]


func _node(path: String) -> Node:
	return _panel.get_node(path)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _px(dp: float) -> int:
	return roundi(UiScale.dp(dp))


## The safe area's inner width, which the build panel's zone is a share of (HudLayout.panel_px).
func _inner_width() -> float:
	var area: Control = _hud("SafeArea")
	var margins: float = area.get_theme_constant("margin_left")
	return (
		get_viewport().get_visible_rect().size.x - margins - area.get_theme_constant("margin_right")
	)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## What TouchInput hands the PlayerController: a selection gesture.
func _gesture(kind: int, at: Vector2, rect: Rect2 = Rect2()) -> void:
	var e: GestureEvent = GestureEvent.new(kind)
	e.position = at
	e.rect = rect
	_controller.handle_gesture(e)


## A new main scene at `metrics` with the fake clock and the Commands caught.
func _open(metrics: UiMetrics) -> void:
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_sent.clear()
	_controller = _main.get_node("PlayerController")
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_panel = _hud("SelectionPanel")
	var touch: TouchInput = _main.get_node("TouchInput")
	touch.clock = func() -> int: return _now_ms


func _runner() -> MatchRunner:
	return _main.get_node("MatchRunner")


## The width of the label's whole text at its font size: what it would need without a cap.
func _text_px(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var font_px: int = label.get_theme_font_size(&"font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
