extends GdUnitTestSuite
## The SelectionPanel in the main scene (P21): one row per unit type with its art, name and count,
## a total for several types, and a place in the safe area between the ArmyBar and the right fifth.
## Fingers are touches through the real GUI, time is a fake clock. Tank n is row n - 1 of the
## 6-column block, and ids 1-30 are the player's.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ART: String = "res://assets/art/svg/units/light_tank_"
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
	for part: String in ["Hull", "Team", "Turret"]:  # The tank's own layers, the owner colour.
		var rect: TextureRect = _node("Rows/Row0/Icon/" + part)
		assert_str(rect.texture.resource_path).is_equal(ART + part.to_lower() + ".svg")
		assert_that(rect.modulate).is_equal(Color("2F80ED") if part == "Team" else Color.WHITE)
	_gesture(GestureEvent.Kind.DOUBLE_TAP, first)
	_expect("double-tap", "×30")
	var tanks_1_to_6: Rect2 = Rect2(first, Vector2.ZERO).expand(layer.unit_screen_position(5))
	_gesture(GestureEvent.Kind.BOX_END, first, tanks_1_to_6.grow(30.0))
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
	_panel.unit_layer = auto_free(UnitLayer.new())
	add_child(_panel)
	_panel.set_selected(PackedInt32Array([1, 2, 3, 4, 5, 999]))  # 999 is no unit.
	assert_array(_texts("Row0")).is_equal(["Light Tank", "×2"])
	assert_array(_texts("Row1")).is_equal(["Scout Test", "×3"])
	assert_str((_node("Rows/Total") as Label).text).is_equal("Total ×5")
	assert_bool(_node("Rows/Total").visible).is_true()
	assert_int(_node("Rows/Total").get_index()).is_equal(2)  # Below the rows.
	assert_object((_node("Rows/Row1/Icon/Hull") as TextureRect).texture).is_null()  # No art.
	await await_idle_frame()
	for row_name: String in ["Row0", "Row1"]:  # Without a band there is no cap.
		var title: Label = _node("Rows/%s/Name" % row_name)
		assert_float(title.size.x).is_greater_equal(_text_px(title))
	var row0: Node = _node("Rows/Row0")
	_panel.set_selected(PackedInt32Array([4]))
	assert_object(_node("Rows/Row0")).is_same(row0)  # Reused, now the scout.
	assert_array(_texts("Row0")).is_equal(["Scout Test", "×1"])
	assert_object((_node("Rows/Row0/Icon/Hull") as TextureRect).texture).is_null()  # Not the tank's.
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


func test_the_panel_is_dp_sized_and_sits_between_the_army_bar_and_the_sidebar_zone() -> void:
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, Vector2i(2424, 1080), Rect2i(152, 0, 2272, 1080)
	)
	var xhdpi: UiMetrics = UiMetrics.create("Android", 320, 1.0, 1.0, Vector2i(1280, 720), Rect2i())
	var cases: Array[UiMetrics] = [michael, xhdpi]  # xhdpi is 2 base px per dp: the tightest fit.
	for profile_name: StringName in UiProfiles.all():
		var m: UiMetrics = UiProfiles.by_name(profile_name)
		var cutout: Rect2i = Rect2i(100, 0, m.window_size.x - 100, m.window_size.y)
		cases.append(m)
		cases.append(UiProfiles.with_safe_area(m, cutout))
	for m: UiMetrics in cases:
		await _open(m)
		_select(range(1, 31))
		await await_idle_frame()
		var rect: Rect2 = _panel.get_global_rect()
		var bar: Rect2 = (_hud("ArmyBar") as Control).get_global_rect()
		var width: float = get_viewport().get_visible_rect().size.x
		var sidebar: float = maxf(width * 0.2, UiScale.dp(200.0))  # 20%, at least 200 dp.
		var why: String = "%s: panel %s, bar %s" % [m.window_size, rect, bar]
		var sizes: Array[int] = []
		for path: String in ["Rows/Row0/Name", "Rows/Row0/Count", "Rows/Total"]:
			sizes.append(_node(path).get_theme_font_size("font_size"))
		var pinned: Array[int] = [_px(16.0), _px(20.0), _px(20.0)]  # Name, count, total.
		assert_array(sizes).override_failure_message(why).is_equal(pinned)
		for part: String in ["", "/Hull", "/Team", "/Turret"]:  # The icon and its drawn layers.
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
	var zone: float = maxf(get_viewport().get_visible_rect().size.x * 0.2, UiScale.dp(200.0))
	assert_int(_panel.get_parent().get_theme_constant("margin_right")).is_equal(ceili(zone))
	assert_int(_node("Rows/Row0/Name").get_theme_font_size("font_size")).is_equal(_px(16.0))
	var title: Label = _node("Rows/Row0/Name")  # The cap is in px, so it is fitted again.
	assert_str(title.text).is_equal("Light Tank")
	assert_float(title.size.x).is_greater_equal(_text_px(title))


## "Light Tank" is also the capitalised type id, so a name written into the snapshot alone shows
## that the panel takes it from `type_names`. The World is swapped for an empty one after a tick:
## the counts and the names must come from the published snapshot.
func test_names_and_counts_come_from_the_snapshot_and_never_the_world() -> void:
	await _open(UiProfiles.by_name(&"desktop"))
	_runner().paused = true
	_select([1, 2])
	_expect("the data's display name", "×2")
	_runner().run_ticks(1)
	_runner().world = World.new()  # Test-only: an empty World where the match's was.
	_runner().snapshot.type_names[0] = "Ironclad"
	_panel.set_selected(PackedInt32Array([1, 2, 3, 999]))
	assert_bool(_panel.visible).is_true()
	assert_array(_texts("Row0")).is_equal(["Ironclad", "×3"])
	assert_str(_panel.get_node("Rows/Row0/Name").text).is_not_equal("Light Tank")


## A row is at most 40% of the band (the safe area's inner width): a name past that is clipped
## with an ellipsis, and the icon and the count keep their room. "Light Tank" is not clipped.
## web_phone_small is where the sidebar zone gives way to a long name; the cap holds there too.
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


## The row `row_name` is the cap wide, its name clipped, and its icon and count keep their room.
func _assert_capped(row_name: String, why: String) -> void:
	var band_px: float = (_panel.get_parent() as Control).size.x
	var row: Control = _node("Rows/" + row_name)
	var title: Label = _node("Rows/%s/Name" % row_name)
	var count: Label = _node("Rows/%s/Count" % row_name)
	var detail: String = "%s: row %s, band %s" % [why, row.size.x, band_px]
	assert_str(title.text).is_equal(LONG_NAME)  # The text stays whole; the draw clips it.
	assert_float(_text_px(title)).override_failure_message(detail).is_greater(band_px * 0.4)
	# The box layout rounds sizes to whole px, so the row is the cap to within a px or two.
	assert_float(row.size.x).override_failure_message(detail).is_less_equal(band_px * 0.4 + 1.5)
	assert_float(row.size.x).override_failure_message(detail).is_greater_equal(band_px * 0.4 - 1.5)
	assert_float(title.size.x).override_failure_message(detail).is_greater(UiScale.dp(16.0))
	assert_float(count.size.x).override_failure_message(detail).is_greater_equal(
		count.get_combined_minimum_size().x
	)


func _expect(step: String, count: String) -> void:
	assert_bool(_panel.visible).override_failure_message(step).is_true()
	assert_array(_texts("Row0")).override_failure_message(step).is_equal(["Light Tank", count])


func _texts(row: String) -> Array[String]:
	var title: Label = _node("Rows/%s/Name" % row)
	return [title.text, (_node("Rows/%s/Count" % row) as Label).text]


func _node(path: String) -> Node:
	return _panel.get_node(path)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _px(dp: float) -> int:
	return roundi(UiScale.dp(dp))


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
