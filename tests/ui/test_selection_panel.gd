extends GdUnitTestSuite
## The SelectionPanel in the main scene (P21): one row per unit type with its art, name and count,
## a total for several types, and a place in the safe area between the ArmyBar and the right fifth.
## Fingers are touches through the real GUI, time is a fake clock. Tank n is row n - 1 of the
## 6-column block, and ids 1-30 are the player's.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ART: String = "res://assets/art/svg/units/light_tank_"

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
	assert_array(_texts("Row0")).is_equal(["Light tank", "×2"])
	assert_array(_texts("Row1")).is_equal(["scout_test", "×3"])
	assert_str((_node("Rows/Total") as Label).text).is_equal("Total ×5")
	assert_bool(_node("Rows/Total").visible).is_true()
	var row0: Node = _node("Rows/Row0")
	_panel.set_selected(PackedInt32Array([4]))
	assert_object(_node("Rows/Row0")).is_same(row0)  # Reused, now the scout.
	assert_array(_texts("Row0")).is_equal(["scout_test", "×1"])
	assert_bool(_node("Rows/Row1").visible).is_false()
	assert_bool(_node("Rows/Total").visible).is_false()
	assert_int(_node("Rows").get_child_count()).is_equal(3)  # Two rows and the total, none new.


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
	var cases: Array[UiMetrics] = [michael]
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
		var centre: float = rect.get_center().x
		var sizes: Array[int] = []
		for path: String in ["Rows/Row0/Name", "Rows/Row0/Count", "Rows/Total"]:
			sizes.append(_node(path).get_theme_font_size("font_size"))
		var pinned: Array[int] = [_px(16.0), _px(20.0), _px(20.0)]  # Name, count, total.
		assert_array(sizes).override_failure_message(why).is_equal(pinned)
		assert_int(sizes[0]).override_failure_message(why).is_greater_equal(_px(14.0))
		assert_int(sizes[1]).override_failure_message(why).is_greater_equal(_px(18.0))
		var icon: Vector2 = (_node("Rows/Row0/Icon") as Control).size
		var icon_dp: Vector2 = UiScale.dp_vec(40.0, 40.0)
		assert_vector(icon).override_failure_message(why).is_equal_approx(icon_dp, Vector2.ONE)
		assert_float(rect.size.y).override_failure_message(why).is_greater_equal(UiScale.dp(48.0))
		assert_bool(UiScale.safe_rect_base().encloses(rect)).override_failure_message(why).is_true()
		assert_bool(rect.intersects(bar)).override_failure_message(why).is_false()
		assert_float(rect.end.x).override_failure_message(why).is_less_equal(width - sidebar)
		var band: Control = _panel.get_parent()  # It reserves the whole zone, not just the panel.
		assert_int(band.get_theme_constant("margin_right")).is_equal(ceili(sidebar))
		assert_float(centre).override_failure_message(why).is_between(width * 0.4, width * 0.65)
		assert_float(rect.end.y).override_failure_message(why).is_equal_approx(bar.end.y, 0.5)


func _expect(step: String, count: String) -> void:
	assert_bool(_panel.visible).override_failure_message(step).is_true()
	assert_array(_texts("Row0")).override_failure_message(step).is_equal(["Light tank", count])


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
