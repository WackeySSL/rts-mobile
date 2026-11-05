extends GdUnitTestSuite
## The battle-screen HUD in both orientations (plan P61, ADR 0015 section 5; P120's interim places,
## P122's command bar), at the six sizes of ScreenSizes.ALL with the engine's own metrics and at
## every profile of both orientations, also with a cutout: every HUD control is inside the safe
## rect, at least 48 dp on each axis and clear of every other. BUILD (P120) is at the bottom right,
## the economy pill (P119) at the top left and the radar scope (P121) at the top right in both
## orientations; in landscape the command bar (bottom left, with all own units selected) stays left
## of BUILD's column or of the open drawer. In portrait, while the drawer is closed, the zone is 0
## (P122b); since Michael's decision of 2026-11-05 the bar stands at the safe bottom left, BUILD in
## the bottom right corner and the group column under the pill, as in landscape.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _main: Node2D
var _panel: CommandBar


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_every_hud_control_is_inside_the_safe_rect_48_dp_and_clear_of_the_others() -> void:
	for screen: Dictionary in _screens():
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var visible_rect: Rect2 = get_viewport().get_visible_rect()
		var big: Dictionary[String, Rect2] = {
			"GroupColumn": _rect("GroupColumn"),
			"Bar": _rect(_panel),
			"Build": _rect("BuildButton"),
		}
		big["Pill"] = _rect("EconomyPill")  # In both orientations (P119).
		big["Scope"] = _rect("RadarScope")  # And the scope (P121).
		var all: Dictionary[String, Rect2] = big.duplicate()
		for button: String in ["AllArmy"]:
			all[button] = _rect(button)
		assert_bool(_panel.visible).override_failure_message(why).is_true()
		for control: String in all:
			var rect: Rect2 = all[control]
			var at: String = "%s: %s %s, safe %s" % [why, control, rect, safe]
			assert_bool(safe.encloses(rect)).override_failure_message(at).is_true()
			var least: float = UiScale.dp(48.0) - TOLERANCE_PX
			assert_float(rect.size.x).override_failure_message(at).is_greater_equal(least)
			assert_float(rect.size.y).override_failure_message(at).is_greater_equal(least)
		var names: Array = big.keys()
		for first: int in names.size():
			for second: int in range(first + 1, names.size()):
				var pair: String = "%s: %s and %s" % [why, names[first], names[second]]
				var overlap: bool = big[names[first]].intersects(big[names[second]])
				assert_bool(overlap).override_failure_message(pair).is_false()
		var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()  # It must not grow.
		assert_that(area).override_failure_message(why).is_equal(visible_rect)


## The open drawer is a HUD control too (plan P120): at every screen, sideways the command bar and
## the group column end before the panel with a gap (`HudCorners` leaves the bar the room beside
## it), upright the sheet covers the bar and the column; and none of the pill, the
## column and the bar overlaps the drawer's rect in either orientation.
func test_the_open_drawer_overlaps_none_of_the_hud_and_the_bar_ends_before_it() -> void:
	for screen: Dictionary in _screens():
		await _open(screen)
		var why: String = str(screen["label"])
		var sidebar: BuildSidebar = _hud("BuildSidebar")
		sidebar.open()
		await await_idle_frame()
		await await_idle_frame()
		var full: Rect2 = get_viewport().get_visible_rect()
		var safe: Rect2 = SafeAreaMargin.rect_inside(full, SafeAreaMargin.DEFAULT_MARGIN_DP)
		var back: Rect2 = _rect("Backdrop")
		var drawer: Rect2
		if HudLayout.is_portrait():
			drawer = Rect2(
				back.position, Vector2(back.size.x, back.size.y - (full.end.y - safe.end.y))
			)
		else:
			drawer = Rect2(
				back.position, Vector2(back.size.x - (full.end.x - safe.end.x), back.size.y)
			)
		# The sheet covers the bar's place upright; beside the side panel it stays.
		assert_bool(_panel.visible).override_failure_message(why).is_equal(
			not HudLayout.is_portrait()
		)
		var parts: Dictionary[String, Rect2] = {"Pill": _rect("EconomyPill")}
		if _panel.visible:
			parts["Bar"] = _rect(_panel)
		if (_hud("GroupColumn") as Control).is_visible_in_tree():  # The sheet covers it upright.
			parts["GroupColumn"] = _rect("GroupColumn")
		for part: String in parts:
			var at: String = "%s: %s %s against the drawer %s" % [why, part, parts[part], drawer]
			assert_bool(parts[part].intersects(drawer)).override_failure_message(at).is_false()
		if not HudLayout.is_portrait():
			var gap: float = UiScale.dp(8.0) - TOLERANCE_PX
			for part: String in ["Bar", "GroupColumn"]:
				var at: String = (
					"%s: %s %s, drawer from %s" % [why, part, parts[part], drawer.position.x]
				)
				assert_float(parts[part].end.x).override_failure_message(at).is_less_equal(
					drawer.position.x - gap
				)
		sidebar.collapse()


## A resize while the drawer is open (the phone's window changes size, a turn) places the bar again
## beside the new panel width: it ends a gap before the drawer, not where the old drawer began.
func test_a_resize_with_the_drawer_open_refits_the_bar_to_the_new_width() -> void:
	var first: UiMetrics = UiProfiles.by_name(&"android_6in")
	var wide: UiMetrics = UiProfiles.by_name(&"web_tablet")
	await _open({"label": "phone", "size": first.window_size, "metrics": first})
	var sidebar: BuildSidebar = _hud("BuildSidebar")
	sidebar.open()
	await await_idle_frame()
	await await_idle_frame()
	UiScale.set_override(wide)
	get_window().size = wide.window_size
	await await_idle_frame()
	await await_idle_frame()
	assert_float(HudLayout.drawer_side_dp).is_greater(0.0)
	var drawer_x: float = _rect("Backdrop").position.x
	assert_bool(_panel.visible).is_true()
	assert_float(_rect(_panel).end.x).is_less_equal(drawer_x - UiScale.dp(8.0) + TOLERANCE_PX)


## Michael, 2026-11-05: upright the group column stands at the left edge under the pill, BUILD in
## the bottom right corner (not lifted over the bar) and the bar bottom left, short of BUILD.
func test_in_portrait_the_corners_are_the_landscape_corners() -> void:
	for screen: Dictionary in _screens(true):
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var gap: float = UiScale.dp(8.0)
		var build: Rect2 = _rect("BuildButton")
		assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_equal(0.0)
		var bar: Rect2 = _rect(_panel)
		assert_bool(_panel.visible).override_failure_message(why).is_true()
		assert_float(bar.end.y).override_failure_message(why).is_equal_approx(_inner_bottom(), 1.0)
		assert_float(build.end.y).override_failure_message(why).is_equal_approx(
			_inner_bottom(), 1.0
		)
		assert_float(bar.end.x).override_failure_message(why).is_less_equal(
			build.position.x - gap + TOLERANCE_PX
		)
		var column: Rect2 = _rect("GroupColumn")
		var pill: Rect2 = _rect("EconomyPill")
		assert_float(column.position.y).override_failure_message(why).is_greater_equal(
			pill.end.y + gap - TOLERANCE_PX - 1.5
		)
		var inner_left: float = _hud("SafeArea").get_theme_constant("margin_left")
		assert_float(column.position.x).override_failure_message(why).is_equal_approx(
			inner_left, 1.0
		)
		assert_bool(safe.encloses(column)).override_failure_message(why).is_true()


## There is no band in landscape: the sidebar leaves the zone at 0 and the column stands at the left
## edge under the pill, whatever zone it is told of.
func test_in_landscape_the_group_column_stands_under_the_pill_whatever_the_zone() -> void:
	for screen: Dictionary in _screens(false):
		await _open(screen)
		var why: String = str(screen["label"])
		assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_equal(0.0)
		var column: Rect2 = _rect("GroupColumn")
		var pill: Rect2 = _rect("EconomyPill")
		# The pill is 48 dp plus the px its containers round up (up to 1.5 px, test_economy_pill_layout).
		assert_float(column.position.y).override_failure_message(why).is_greater_equal(
			pill.end.y + UiScale.dp(8.0) - TOLERANCE_PX - 1.5
		)
		var before: Rect2 = column
		HudLayout.bottom_zone_dp = 200.0  # Not what the sidebar sets: nothing reads it here.
		(_hud("GroupColumn") as GroupColumn).place()
		assert_that(_rect("GroupColumn")).override_failure_message(why).is_equal(before)
		HudLayout.bottom_zone_dp = 0.0


## The menu's real top (ADR 0024 section 4, P86c): INF while the drawer is closed (BUILD is an
## island the ghost's buttons keep clear of) and in landscape, where the panel is at the side; open
## upright,
## the sheet's drawn top, whatever the safe area's insets; INF once the sidebar is gone.
## `map_bottom_px` is the smaller of it and the safe rect's bottom.
func test_the_menus_real_top_is_the_sheets_top_while_open_upright_and_nothing_else() -> void:
	for screen: Dictionary in _screens():
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		assert_bool(is_inf(HudLayout.menu_top_px)).override_failure_message(why).is_true()
		var sidebar: BuildSidebar = _hud("BuildSidebar")
		sidebar.open()
		if screen["portrait"]:
			assert_float(HudLayout.menu_top_px).override_failure_message(why).is_equal_approx(
				_rect(sidebar).position.y, 1.0
			)
			assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_equal_approx(
				_inner_bottom() - HudLayout.menu_top_px, 1.0
			)
		else:
			assert_bool(is_inf(HudLayout.menu_top_px)).override_failure_message(why).is_true()
			assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_equal(0.0)
		assert_float(HudLayout.map_bottom_px(safe)).override_failure_message(why).is_equal(
			minf(HudLayout.menu_top_px, safe.end.y)
		)
	remove_child(_main)
	_main.free()
	assert_bool(is_inf(HudLayout.menu_top_px)).is_true()  # No sidebar, no menu.
	var safe_rect: Rect2 = Rect2(10.0, 20.0, 300.0, 400.0)
	assert_float(HudLayout.map_bottom_px(safe_rect)).is_equal(420.0)
	HudLayout.menu_top_px = 300.0
	assert_float(HudLayout.map_bottom_px(safe_rect)).is_equal(300.0)
	HudLayout.menu_top_px = 500.0  # Below the safe rect: it still ends the map there.
	assert_float(HudLayout.map_bottom_px(safe_rect)).is_equal(420.0)


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own), cutout,
## portrait}; `portrait` true or false leaves out the other orientation.
## Each profile comes twice, the second time with a cutout of 100 px on the side where a phone has
## its camera (the left in landscape, the top in portrait).
func _screens(portrait: Variant = null) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append(_screen("size %s" % size, size, null, false))
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var w: int = m.window_size.x
		var h: int = m.window_size.y
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, w, h - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, w - CUTOUT_PX, h)
		var label: String = "%s with a cutout" % profile_name
		all.append(_screen(str(profile_name), m.window_size, m, false))
		all.append(_screen(label, m.window_size, UiProfiles.with_safe_area(m, cut), true))
	var out: Array[Dictionary] = []
	for screen: Dictionary in all:
		if portrait == null or screen["portrait"] == portrait:
			out.append(screen)
	return out


func _screen(label: String, size: Vector2i, metrics: UiMetrics, cutout: bool) -> Dictionary:
	var portrait: bool = UiScale.is_portrait_size(size)
	return {
		"label": label,
		"size": size,
		"metrics": metrics,
		"cutout": cutout,
		"portrait": portrait,
	}


## The bottom of the safe area's inner rect, where the HUD may reach.
func _inner_bottom() -> float:
	var safe_area: Control = _hud("SafeArea")
	return get_viewport().get_visible_rect().end.y - safe_area.get_theme_constant("margin_bottom")


## The right edge of the safe area's inner rect.
func _inner_right() -> float:
	var safe_area: Control = _hud("SafeArea")
	return get_viewport().get_visible_rect().end.x - safe_area.get_theme_constant("margin_right")


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## The rect of a HUD Control, by name or itself.
func _rect(control: Variant) -> Rect2:
	var node: Control = control if control is Control else _hud(control as String)
	return node.get_global_rect()


## A new main scene on `screen` with its selection (`counts`).
func _open(screen: Dictionary) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if screen["metrics"] != null:
		UiScale.set_override(screen["metrics"])
	else:
		UiScale.clear_override()
	get_window().size = screen["size"]
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_panel = _hud("CommandBar")
	var controller: PlayerController = _main.get_node("PlayerController")
	controller.selection.set_ids(MatchRig.units_of(_main, 1))  # The bar shows for a selection.
	await await_idle_frame()
	await await_idle_frame()
