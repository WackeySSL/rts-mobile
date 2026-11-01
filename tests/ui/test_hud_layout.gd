extends GdUnitTestSuite
## The battle-screen HUD in both orientations (plan P61, ADR 0015 section 5), at the six sizes of
## ScreenSizes.ALL with the engine's own metrics and at every profile of both orientations, also
## with a cutout: every HUD control is inside the safe rect, at least 48 dp on each axis and clear
## of every other. In landscape that includes the floating panels (ADR 0023 section 12, P85d): the
## build panel at the bottom right, the status pill at the top left and the minimap's slot at the
## top right; the bottom row (the ArmyBar and the selection panel) stays left of the build panel's
## zone. In portrait none enters the bottom band, which the sidebar sets and the ArmyBar sits above
## (P85). Portrait selects the six MVP types with 3-digit counts. Landscape selects the 30 tanks the
## scene starts with, and again 120 rocket squads (the widest single row) and three types with
## 3-digit counts (not the six: their column is taller than the smallest web phone): a row the
## bottom row has no room for is clipped, never slid under the build panel.

const Roster: GDScript = preload("res://tests/ui/support/mvp_roster.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TANKS: Array[int] = [0, 0, 30]
const SIX_TYPES: Array[int] = [120, 100, 150, 110, 130, 140]
const ROCKETS: Array[int] = [0, 120]  ## "Rocket Squad ×120": the longest name, a 3-digit count.
const THREE_TYPES: Array[int] = [120, 100, 150]  ## Rifle squads, rocket squads, light tanks.
const STACK_LIMIT: float = 0.4  ## The bottom stack's share of the safe height, at most.
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _main: Node2D
var _panel: SelectionPanel


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func test_every_hud_control_is_inside_the_safe_rect_48_dp_and_clear_of_the_others() -> void:
	for screen: Dictionary in _cases():
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var visible_rect: Rect2 = get_viewport().get_visible_rect()
		var big: Dictionary[String, Rect2] = {
			"DevButton": _rect("DevButton"),
			"ArmyBar": _rect("ArmyBar"),
			"Panel": _rect(_panel),
			"Sidebar": _rect("BuildSidebar"),
		}
		if not HudLayout.is_portrait():  # In portrait the pill and the slot are hidden.
			big["Pill"] = _rect("StatusPill")
			big["Slot"] = _rect("MinimapSlot")
		var all: Dictionary[String, Rect2] = big.duplicate()
		for button: String in ["AllArmy", "Group1", "Group2", "Group3"]:
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
		if not HudLayout.is_portrait():  # The bottom row's right end is the build panel's alone.
			var inner_width: float = (
				_inner_right() - _hud("SafeArea").get_theme_constant("margin_left")
			)
			var zone: float = _inner_right() - HudLayout.right_zone_px(inner_width)
			for control: String in all:
				if control == "Sidebar" or control == "Slot":
					continue
				var at: String = "%s: %s %s, zone from %s" % [why, control, all[control], zone]
				assert_float(all[control].end.x).override_failure_message(at).is_less_equal(
					zone + TOLERANCE_PX
				)


## With the sidebar's real band (P85), no other control enters the band, the bar sits a gap above
## it, and nothing else is in the bottom stack. The limit of 40% of the safe height is the plan's,
## for the six sizes and the profiles; a cutout takes height from both ends of the screen
## (SafeAreaMargin gives top and bottom the larger inset), so a case with one is left out of the
## limit, as a phone browser that is only 700 dp tall has no room left for it.
func test_in_portrait_the_bar_is_directly_above_the_sidebars_band_and_nothing_else_is_below_it(
) -> void:
	for screen: Dictionary in _screens(true):
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var gap: float = UiScale.dp(8.0)
		var band: Rect2 = _rect("BuildSidebar")
		var zone_top: float = _inner_bottom() - HudLayout.bottom_zone_px()
		assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_greater(0.0)
		assert_float(band.position.y).override_failure_message(why).is_equal_approx(zone_top, 0.5)
		assert_float(band.end.y).override_failure_message(why).is_equal_approx(_inner_bottom(), 0.5)
		var bar: Rect2 = _rect("ArmyBar")
		assert_float(bar.end.y).override_failure_message(why).is_between(
			zone_top - gap - 1.5, zone_top - gap + TOLERANCE_PX
		)
		for control: String in ["DevButton", "ArmyBar", "AllArmy", "Group1", "Group3"]:
			var at: String = "%s: %s %s, band from %s" % [why, control, _rect(control), zone_top]
			assert_float(_rect(control).end.y).override_failure_message(at).is_less_equal(
				zone_top + TOLERANCE_PX
			)
		assert_float(_rect(_panel).end.y).override_failure_message(why).is_less_equal(
			bar.position.y
		)
		assert_float(_rect("DevButton").end.y).override_failure_message(why).is_less_equal(
			bar.position.y
		)
		assert_bool(safe.encloses(bar)).override_failure_message(why).is_true()
		if not screen["cutout"]:
			var stack: float = safe.end.y - bar.position.y
			var limit: float = STACK_LIMIT * safe.size.y
			var share: String = "%s: stack %s of %s" % [why, stack, safe.size.y]
			assert_float(stack).override_failure_message(share).is_less_equal(limit)


## There is no band in landscape: the sidebar leaves the zone at 0 and the bar is on the bottom
## edge, and the bar lifts for a band only in portrait, whatever zone it is told of.
func test_in_landscape_the_bar_stays_on_the_bottom_edge_whatever_the_zone_it_is_told_of() -> void:
	for screen: Dictionary in _screens(false):
		await _open(screen)
		var why: String = str(screen["label"])
		assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_equal(0.0)
		assert_float(_rect("ArmyBar").end.y).override_failure_message(why).is_equal_approx(
			_inner_bottom(), 0.01
		)
		assert_int(_hud("ArmyBand").get_theme_constant("margin_bottom")).is_equal(0)
		HudLayout.bottom_zone_dp = 200.0  # Not what the sidebar sets: the bar's own rule.
		(_hud("ArmyBar") as ArmyBar)._lift()
		assert_int(_hud("ArmyBand").get_theme_constant("margin_bottom")).is_equal(0)
		HudLayout.bottom_zone_dp = 0.0


## The menu's real top (ADR 0024 section 4, P86c): in portrait the drawn top of the band, whatever
## the safe area's insets (the band stands higher than the safe rect's bottom less its height, by
## the margin and with a top cutout by the cutout too); in landscape the safe rect's bottom, where
## nothing covers the map; nothing (INF) once the sidebar is gone. `map_bottom_px` is the smaller of
## it and the safe rect's bottom.
func test_the_menus_real_top_is_the_bands_drawn_top_and_the_safe_bottom_in_landscape() -> void:
	for screen: Dictionary in _screens():
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		if screen["portrait"]:
			var top: float = _rect("BuildSidebar").position.y
			assert_float(HudLayout.menu_top_px).override_failure_message(why).is_equal_approx(
				top, 1.0
			)
			assert_float(HudLayout.menu_top_px).override_failure_message(why).is_less(
				safe.end.y - HudLayout.bottom_zone_px()
			)
		else:
			assert_float(HudLayout.menu_top_px).override_failure_message(why).is_equal(safe.end.y)
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


## The band is as high as its content needs where that is more than the zone (a head line that
## outgrows it), and the menu's top follows the drawn band, not the zone: with a control in the
## band that makes it a zone taller, the top is a zone higher than the zone alone puts it.
func test_the_menus_top_follows_a_band_its_content_makes_taller_than_the_zone() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	var cut: Rect2i = Rect2i(0, CUTOUT_PX, phone.window_size.x, phone.window_size.y - CUTOUT_PX)
	for metrics: UiMetrics in [phone, UiProfiles.with_safe_area(phone, cut)]:
		var screen: Dictionary = _screen("phone", phone.window_size, metrics, false)
		await _open(screen)
		var sidebar: BuildSidebar = _hud("BuildSidebar")
		var zone: float = HudLayout.bottom_zone_px()
		var why: String = str(metrics.safe_area)
		var rest: float = HudLayout.menu_top_px
		assert_float(rest).override_failure_message(why).is_equal_approx(
			_rect(sidebar).position.y, 1.0
		)
		var extra: Control = Control.new()
		extra.custom_minimum_size = Vector2(0.0, zone)
		sidebar.get_node("Stack").add_child(extra)
		sidebar._apply_dp()  # What a resize does.
		await await_idle_frame()
		await await_idle_frame()
		assert_float(_rect(sidebar).size.y).override_failure_message(why).is_greater(zone + 1.0)
		assert_float(HudLayout.menu_top_px).override_failure_message(why).is_equal_approx(
			_rect(sidebar).position.y, 1.0
		)
		assert_float(HudLayout.menu_top_px).override_failure_message(why).is_less(rest - zone * 0.5)


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own), cutout,
## portrait, counts (its selection)}; `portrait` true or false leaves out the other orientation.
## Each profile comes twice, the second time with a cutout of 100 px on the side where a phone has
## its camera (the left in landscape, the top in portrait).
func _screens(portrait: Variant = null) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append(_screen("size %s" % size, size, null, false))
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
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
		"counts": SIX_TYPES if portrait else TANKS,
	}


## `_screens()` with each landscape screen again for the two long selections.
func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for screen: Dictionary in _screens():
		out.append(screen)
		if screen["portrait"]:
			continue
		for counts: Array[int] in [ROCKETS, THREE_TYPES]:
			var longer: Dictionary = screen.duplicate()
			longer["label"] = "%s, %s" % [screen["label"], counts]
			longer["counts"] = counts
			out.append(longer)
	return out


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
	_panel = _hud("SelectionPanel")
	Roster.select(self, _panel, screen["counts"])
	await await_idle_frame()
