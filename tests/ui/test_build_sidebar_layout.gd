extends GdUnitTestSuite
## The build sidebar's zone and its controls in both orientations (plan P85, ADR 0015 section 5
## and ADR 0019 section 1): at the six sizes of ScreenSizes.ALL with the engine's own metrics and at
## every profile of both orientations, also with a cutout. The sidebar fills its zone inside the
## safe rect, its tabs are at least 48 dp and clear of each other, the item slot keeps its 64 dp,
## the portrait band is what HudLayout says (and gives way first on a short screen), the tabs show
## names only where they fit and never in the band, and the band's height is the HUD's one place for
## it: 0 in landscape and once the sidebar is gone. How the ArmyBar and the other HUD parts sit
## around it is tests/ui/test_hud_layout.gd's.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
const TABS: Array[String] = ["TabStructures", "TabInfantry", "TabVehicles"]
const NAMES: Array[String] = ["Structures", "Infantry", "Vehicles"]
## The edge margin (SafeAreaMargin's default), the gap and the bar: what the stack takes besides
## the band, in dp (BuildSidebar._place).
const RESERVED_DP: float = 12.0 + 8.0 + 56.0
const STACK_LIMIT: float = 0.4

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


func test_the_sidebar_fills_its_zone_inside_the_safe_rect_with_its_controls_clear_of_each_other(
) -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var visible_rect: Rect2 = get_viewport().get_visible_rect()
		var inner: Rect2 = _inner()
		var rect: Rect2 = _rect(_sidebar)
		var at: String = "%s: sidebar %s, inner %s, safe %s" % [why, rect, inner, safe]
		assert_bool(safe.encloses(rect)).override_failure_message(at).is_true()
		if HudLayout.is_portrait():
			_assert_edges(rect, [inner.position.x, inner.end.x, inner.end.y], [0, 2, 3], at)
			assert_float(rect.size.y).override_failure_message(at).is_equal_approx(
				HudLayout.bottom_zone_px(), 1.0
			)
			var safe_dp: float = safe.size.y / UiScale.base_px_per_dp()
			assert_float(HudLayout.bottom_zone_dp).override_failure_message(at).is_equal_approx(
				HudLayout.band_dp(safe_dp, RESERVED_DP), 0.01
			)
		else:
			_assert_edges(rect, [inner.end.x, inner.position.y, inner.end.y], [2, 1, 3], at)
			assert_float(rect.size.x).override_failure_message(at).is_equal_approx(
				HudLayout.right_zone_px(visible_rect.size.x), 1.0
			)
			assert_float(HudLayout.bottom_zone_dp).override_failure_message(at).is_equal(0.0)
		var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()  # It must not grow.
		assert_that(area).override_failure_message(why).is_equal(visible_rect)
		var parts: Dictionary[String, Rect2] = {}
		for part: String in ["Status", "Items"] + TABS:
			parts[part] = _rect(part)
			var inside: String = "%s: %s %s in %s" % [why, part, parts[part], rect]
			assert_bool(rect.encloses(parts[part])).override_failure_message(inside).is_true()
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		for tab: String in TABS:
			assert_float(parts[tab].size.x).override_failure_message(why).is_greater_equal(least)
			assert_float(parts[tab].size.y).override_failure_message(why).is_greater_equal(least)
		assert_float(parts["Items"].size.y).override_failure_message(why).is_greater_equal(
			UiScale.dp(64.0) - TOLERANCE_PX
		)
		var names: Array = parts.keys()
		for first: int in names.size():
			for second: int in range(first + 1, names.size()):
				var pair: String = "%s: %s and %s" % [why, names[first], names[second]]
				var overlap: bool = parts[names[first]].intersects(parts[names[second]])
				assert_bool(overlap).override_failure_message(pair).is_false()


## ADR 0015 section 5: 20% of the safe height and at least 200 dp; where the band and the ArmyBar
## line would take more than 40%, the band gives way, down to what its contents need.
func test_the_band_is_a_fifth_of_the_height_and_gives_way_first_on_a_short_screen() -> void:
	assert_float(HudLayout.band_dp(914.0, RESERVED_DP)).is_equal_approx(200.0, 0.001)  # 6-inch.
	assert_float(HudLayout.band_dp(700.0, RESERVED_DP)).is_equal_approx(200.0, 0.001)  # 360 dp.
	assert_float(HudLayout.band_dp(1024.0, RESERVED_DP)).is_equal_approx(204.8, 0.001)  # 20%.
	assert_float(HudLayout.band_dp(2400.0, RESERVED_DP)).is_equal_approx(480.0, 0.001)
	assert_float(HudLayout.band_dp(650.0, RESERVED_DP)).is_equal_approx(184.0, 0.001)  # Gives way.
	assert_float(HudLayout.band_dp(560.0, RESERVED_DP)).is_equal_approx(172.0, 0.001)  # The floor.
	assert_float(HudLayout.band_dp(100.0, RESERVED_DP)).is_equal_approx(172.0, 0.001)
	# The same on screen: a 650 dp phone browser keeps the stack within 40%, a 560 dp one reaches
	# the floor, and neither shrinks the ArmyBar, a tab or the 64 dp item slot.
	for case: Array in [[1950, 184.0], [1680, 172.0]]:
		var stretch: float = minf(1080.0 / 720.0, float(case[0]) / 1280.0)
		var metrics: UiMetrics = UiMetrics.create(
			"Web", 288, 3.0, stretch, Vector2i(1080, case[0]), Rect2i()
		)
		await _open(metrics.window_size, metrics)
		var why: String = "%d px tall" % case[0]
		var safe: Rect2 = UiScale.safe_rect_base()
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal_approx(
			case[1], 0.01
		)
		var bar: Rect2 = _rect("ArmyBar")
		var stack: float = safe.end.y - bar.position.y
		if case[1] > HudLayout.BAND_FLOOR_DP:
			assert_float(stack).override_failure_message(why).is_less_equal(
				STACK_LIMIT * safe.size.y + 2.0
			)
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		assert_float(bar.size.y).override_failure_message(why).is_greater_equal(least)
		for tab: String in TABS:
			assert_float(_rect(tab).size.y).override_failure_message(why).is_greater_equal(least)
		assert_float(_rect("Items").size.y).override_failure_message(why).is_greater_equal(
			UiScale.dp(64.0) - TOLERANCE_PX
		)
		(
			assert_float(_sidebar.get_combined_minimum_size().y)
			. override_failure_message(why)
			. is_less_equal(_rect(_sidebar).size.y + TOLERANCE_PX)
		)
		var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()
		assert_that(area).override_failure_message(why).is_equal(get_viewport().get_visible_rect())


## A tab shows its name where all three fit the zone with theirs, in landscape. The 6-inch phone's
## zone is 200 dp, so there the tabs are icons, as in every portrait band.
func test_the_tabs_show_their_names_only_where_they_fit_and_never_in_the_band() -> void:
	var wide: UiMetrics = UiMetrics.create(
		"Linux", 96, 1.0, 1.5, ScreenSizes.LANDSCAPE[1], Rect2i()
	)  # 480 dp of zone.
	await _open(wide.window_size, wide)
	assert_array(_texts()).is_equal(NAMES)
	assert_array(_alignments()).is_equal(
		[HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT]
	)
	var row: Control = _hud("Tabs")
	assert_float(row.get_combined_minimum_size().x).is_less_equal(row.size.x + TOLERANCE_PX)
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	assert_array(_texts()).is_equal(["", "", ""])
	assert_array(_alignments()).is_equal(
		[HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER]
	)
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.portrait()
	for profile_name: StringName in profiles:
		await _open(profiles[profile_name].window_size, profiles[profile_name])
		assert_array(_texts()).override_failure_message(str(profile_name)).is_equal(["", "", ""])


## The one place the ArmyBar reads is 0 in landscape and while no sidebar is in the tree, and the
## band's height in portrait; a turn moves it and the bar with it.
func test_the_bands_height_follows_a_turn_and_goes_with_the_sidebar() -> void:
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(portrait.window_size, portrait)
	var band: Control = _hud("ArmyBand")
	var lift: int = ceili(HudLayout.bottom_zone_px() + UiScale.dp(8.0))
	assert_float(HudLayout.bottom_zone_dp).is_equal_approx(200.0, 0.01)
	assert_int(band.get_theme_constant("margin_bottom")).is_equal(lift)
	UiScale.set_override(landscape)
	get_window().size = landscape.window_size
	await await_idle_frame()
	assert_float(HudLayout.bottom_zone_dp).is_equal(0.0)
	assert_int(band.get_theme_constant("margin_bottom")).is_equal(0)
	assert_int(_sidebar.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_END)
	UiScale.set_override(portrait)
	get_window().size = portrait.window_size
	await await_idle_frame()
	assert_float(HudLayout.bottom_zone_dp).is_equal_approx(200.0, 0.01)
	assert_int(band.get_theme_constant("margin_bottom")).is_equal(lift)
	assert_int(_sidebar.size_flags_vertical).is_equal(Control.SIZE_SHRINK_END)
	remove_child(_main)
	_main.free()
	assert_float(HudLayout.bottom_zone_dp).is_equal(0.0)


## Each of `edges` (the edge values) is on the side of `rect` named by `sides` (0 left, 1 top,
## 2 right, 3 bottom).
func _assert_edges(rect: Rect2, edges: Array, sides: Array, why: String) -> void:
	var of_rect: Array[float] = [rect.position.x, rect.position.y, rect.end.x, rect.end.y]
	for index: int in edges.size():
		assert_float(of_rect[sides[index]]).override_failure_message(why).is_equal_approx(
			edges[index], TOLERANCE_PX
		)


func _texts() -> Array[String]:
	var out: Array[String] = []
	for tab: String in TABS:
		out.append((_hud(tab) as Button).text)
	return out


func _alignments() -> Array[int]:
	var out: Array[int] = []
	for tab: String in TABS:
		out.append((_hud(tab) as Button).icon_alignment)
	return out


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own),
## cutout}. Each profile comes twice, the second time with a cutout of 100 px on the side where a
## phone has its camera (the left in landscape, the top in portrait).
func _screens() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, m.window_size.x - CUTOUT_PX, m.window_size.y)
		all.append({"label": str(profile_name), "size": m.window_size, "metrics": m})
		var with_cutout: UiMetrics = UiProfiles.with_safe_area(m, cut)
		all.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": with_cutout
			}
		)
	return all


## The safe area's inner rect, where the HUD may reach.
func _inner() -> Rect2:
	var area: Control = _hud("SafeArea")
	var full: Rect2 = get_viewport().get_visible_rect()
	var left: float = area.get_theme_constant("margin_left")
	var top: float = area.get_theme_constant("margin_top")
	var right: float = area.get_theme_constant("margin_right")
	var bottom: float = area.get_theme_constant("margin_bottom")
	return Rect2(left, top, full.size.x - left - right, full.size.y - top - bottom)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## The rect of a HUD Control, by name or itself.
func _rect(control: Variant) -> Rect2:
	var node: Control = control if control is Control else _hud(control as String)
	return node.get_global_rect()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own).
func _open(size: Vector2i, metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_sidebar = _hud("BuildSidebar")
