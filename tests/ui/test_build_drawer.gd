extends GdUnitTestSuite
## The build drawer (plan P120, ADR 0025 sections 5 and 6) in the main scene: at the six sizes of
## ScreenSizes.ALL with the engine's own metrics and at every profile of both orientations, also
## with a cutout. Sideways a side panel at the right edge, 312 to 420 dp wide and the full safe
## height, its backdrop reaching on to the screen's edge and its content inside the safe rect;
## upright a bottom sheet of the full safe width and half the height (at least 312 dp). The close
## button (at the tabs row's end), the tabs (with their names) and the cards are at least 48 dp and
## inside the safe rect; the cards are as many columns as fit on every tab (three upright on the
## 6-inch phone and at 360 dp, four from about 450 dp), and on the smallest web phone the
## grid scrolls vertically. The slide (`menu_slide_ms`) eases out, ends on its target, can be
## reversed, and a turn ends it; the zone and the top follow it (ADR 0024 section 4). The interim
## places: upright the closed drawer's zone is BUILD's own 64 dp, sideways it is 0. The unfold
## rules are test_build_drawer_triggers'.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const CUTOUT_PX: int = 100
const HANDLE_MIN_DP: float = 32.0
const TOLERANCE_PX: float = 1.5
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]
const TABS: Array[String] = ["TabStructures", "TabInfantry", "TabVehicles"]
const NAMES: Array[String] = ["Structures", "Infantry", "Vehicles"]

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar
var _told: Array[Vector2] = []  ## (top, height) of each `zone_changed`.


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func before_test() -> void:
	MenuRig.begin()


func test_the_drawer_fills_its_side_or_its_half_and_its_parts_are_inside_the_safe_rect() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var full: Rect2 = get_viewport().get_visible_rect()
		var safe: Rect2 = SafeAreaMargin.rect_inside(full, SafeAreaMargin.DEFAULT_MARGIN_DP)
		var back: Rect2 = _rect("Backdrop")
		var dp: float = UiScale.dp(1.0)
		assert_bool(_sidebar.visible).override_failure_message(why).is_true()
		if HudLayout.is_portrait():
			assert_float(back.end.y).override_failure_message(why).is_equal_approx(full.end.y, 1.0)
			assert_float(back.position.x).override_failure_message(why).is_equal_approx(
				safe.position.x, 1.0
			)
			assert_float(back.size.x).override_failure_message(why).is_equal_approx(
				safe.size.x, 1.0
			)
			var sheet: float = back.size.y - (full.end.y - safe.end.y)
			var want: float = minf(maxf(safe.size.y * 0.5, 312.0 * dp), safe.size.y)
			assert_float(sheet).override_failure_message(why).is_equal_approx(want, 1.0)
		else:
			assert_float(back.end.x).override_failure_message(why).is_equal_approx(full.end.x, 1.0)
			assert_float(back.position.y).override_failure_message(why).is_equal_approx(
				safe.position.y, 1.0
			)
			assert_float(back.size.y).override_failure_message(why).is_equal_approx(
				safe.size.y, 1.0
			)
			var panel: float = (back.size.x - (full.end.x - safe.end.x)) / dp
			assert_float(panel).override_failure_message(why).is_between(311.5, 420.5)
		# The panel token of ADR 0025 section 13, and the sheet's handle (upright only).
		assert_str(_hud("Backdrop").theme_type_variation).is_equal("HudPanel")
		var handle: Control = _hud("Handle") as Control
		assert_bool(handle.visible).override_failure_message(why).is_equal(HudLayout.is_portrait())
		if handle.visible:
			var grab: Rect2 = _rect("Grab")
			assert_bool(grab.grow(TOLERANCE_PX).encloses(handle.get_global_rect())).is_true()
			assert_float(handle.size.x).is_greater_equal(UiScale.dp(HANDLE_MIN_DP) - TOLERANCE_PX)
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		var parts: Array[Control] = [_hud("Close") as Control]
		for tab: String in TABS:
			parts.append(_hud(tab) as Control)
		for part: Control in parts:
			var at: String = "%s: %s %s, safe %s" % [why, part.name, part.get_global_rect(), safe]
			(
				assert_bool(safe.grow(TOLERANCE_PX).encloses(part.get_global_rect()))
				. override_failure_message(at)
				. is_true()
			)
			assert_float(part.size.x).override_failure_message(at).is_greater_equal(least)
			assert_float(part.size.y).override_failure_message(at).is_greater_equal(least)
		for index: int in TABS.size():
			var tab: Button = _hud(TABS[index]) as Button
			var name_label: Label = tab.find_child("Name", true, false) as Label
			assert_str(name_label.text).is_equal(NAMES[index])
			# The tab is no taller than TAB_DP, and the whole name fits the box it is in.
			var tall: String = "%s: %s is %s high" % [why, TABS[index], tab.size.y]
			assert_float(tab.size.y).override_failure_message(tall).is_less_equal(
				BuildSidebar.TAB_DP * dp + TOLERANCE_PX
			)
			var content: Control = tab.get_node("Content")
			var plate: StyleBox = tab.get_theme_stylebox(&"normal", &"SidebarTab")
			var inner: float = (
				tab.size.y - plate.get_margin(SIDE_TOP) - plate.get_margin(SIDE_BOTTOM)
			)
			var packed: String = (
				"%s: %s's icon and name need %s of %s"
				% [why, TABS[index], content.get_combined_minimum_size().y, inner]
			)
			(
				assert_float(content.get_combined_minimum_size().y)
				. override_failure_message(packed)
				. is_less_equal(inner + 0.5)
			)
			var font: Font = name_label.get_theme_font(&"font")
			var font_size: int = name_label.get_theme_font_size(&"font_size")
			var wide: float = (
				font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			)
			var cut: String = (
				"%s: %s is %s wide in %s" % [why, name_label.text, wide, name_label.size.x]
			)
			assert_float(wide).override_failure_message(cut).is_less_equal(name_label.size.x + 0.5)
			assert_float(float(font_size)).override_failure_message(why).is_greater_equal(
				roundf(14.0 * dp) - 0.5
			)
		var tiles: Array[ItemTile] = _visible_tiles()
		assert_int(tiles.size()).is_greater(0)
		var card: Vector2 = (
			ItemTile.CARD_PORTRAIT_DP if HudLayout.is_portrait() else ItemTile.CARD_DP
		)
		var first: Rect2 = tiles[0].get_global_rect()
		var at_card: String = "%s: first card %s, safe %s" % [why, first, safe]
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(first))
			. override_failure_message(at_card)
			. is_true()
		)
		assert_float(first.size.x).override_failure_message(at_card).is_greater_equal(
			card.x * dp - TOLERANCE_PX
		)
		assert_float(first.size.y).override_failure_message(at_card).is_greater_equal(
			card.y * dp - TOLERANCE_PX
		)
		var grid: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
		assert_int(grid.columns).override_failure_message(why).is_greater_equal(2)
		for tile: ItemTile in tiles:  # The columns are what fits: no card leaves the drawer.
			var rect: Rect2 = tile.get_global_rect()
			assert_float(rect.end.x).override_failure_message(why).is_less_equal(
				_rect("Items").end.x + TOLERANCE_PX
			)


func test_the_columns_are_three_upright_on_the_phone_and_four_on_a_wide_screen() -> void:
	for name: StringName in [&"android_6in_portrait", &"web_phone_portrait"]:
		var metrics: UiMetrics = UiProfiles.by_name(name)
		await _open(metrics.window_size, metrics)
		var grid: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
		assert_int(grid.columns).override_failure_message(str(name)).is_equal(3)
	var wide: UiMetrics = UiProfiles.by_name(&"web_tablet_portrait")
	await _open(wide.window_size, wide)
	var tablet: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
	assert_int(tablet.columns).is_greater_equal(4)
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var side: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
	assert_int(side.columns).is_equal(3)


func test_on_the_smallest_web_phone_the_grid_scrolls_vertically() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"web_phone_small")
	await _open(metrics.window_size, metrics)
	var items: ScrollContainer = _hud("Items")
	var bar: VScrollBar = items.get_v_scroll_bar()
	assert_float(bar.max_value).is_greater(bar.page + 1.0)  # More than the room shows.
	assert_int(items.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	# The top of the first card shows, and the drawer's content stays inside the safe height.
	var first: Rect2 = _visible_tiles()[0].get_global_rect()
	assert_float(first.position.y).is_greater_equal(items.get_global_rect().position.y - 0.5)
	assert_float(first.position.y).is_less(items.get_global_rect().end.y)
	var safe: Rect2 = SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	assert_bool(safe.grow(TOLERANCE_PX).encloses(items.get_global_rect())).is_true()


## Michael, 2026-11-05: the head row and the queue row are gone; the close button ends the tabs row
## (the pill is not in the drawer), and the cards fill the drawer's width.
func test_the_close_button_ends_the_tabs_row_and_the_cards_fill_the_width() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		(
			assert_object(_sidebar.find_child("Head", true, false))
			. override_failure_message(why)
			. is_null()
		)
		assert_object(_sidebar.find_child("QueueRow", true, false)).is_null()
		assert_object(_sidebar.find_child("Economy", true, false)).is_null()
		var tabs: Rect2 = _rect("Tabs")
		var close: Rect2 = _rect("Close")
		var last: Rect2 = _rect(TABS[TABS.size() - 1])
		assert_float(close.position.x).override_failure_message(why).is_greater_equal(
			last.end.x - 1.0
		)
		assert_float(close.end.x).override_failure_message(why).is_equal_approx(tabs.end.x, 1.0)
		assert_float(close.position.y).override_failure_message(why).is_equal_approx(
			tabs.position.y, 1.0
		)
		assert_float(close.size.x).override_failure_message(why).is_greater_equal(
			UiScale.dp(48.0) - TOLERANCE_PX
		)
		# The grid has the room between the tabs row and the drawer's foot, edge to edge.
		var items: Rect2 = _rect("Items")
		assert_float(items.position.y).is_greater_equal(tabs.end.y - 1.0)
		assert_float(items.size.x).override_failure_message(why).is_equal_approx(tabs.size.x, 1.0)
		# Every tab's name lies inside its own tab, whatever the width (the narrowest panel is 312 dp).
		for tab_name: String in TABS:
			var tab_rect: Rect2 = _rect(tab_name)
			var name_rect: Rect2 = (
				((_hud(tab_name) as Control).find_child("Name", true, false) as Control)
				. get_global_rect()
			)
			var inside: String = "%s: %s %s in %s" % [why, tab_name, name_rect, tab_rect]
			(
				assert_bool(tab_rect.grow(0.5).encloses(name_rect))
				. override_failure_message(inside)
				. is_true()
			)
		var widths: Array[float] = []
		for tab: int in TABS.size():
			_sidebar.select_tab(tab)
			await await_idle_frame()
			await await_idle_frame()
			var cards: Array[ItemTile] = _visible_tiles()
			assert_bool(cards.is_empty()).override_failure_message(why).is_false()
			var left: float = 1e9
			var right: float = -1e9
			for card: ItemTile in cards:
				left = minf(left, card.get_global_rect().position.x)
				right = maxf(right, card.get_global_rect().end.x)
				var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
				assert_float(card.size.x).override_failure_message(why).is_greater_equal(floor_px)
			var gap: String = (
				"%s, tab %d: cards %s..%s in items %s" % [why, tab, left, right, items]
			)
			assert_float(left - items.position.x).override_failure_message(gap).is_less_equal(1.5)
			widths.append(cards[0].size.x)
			# One width on every tab, however many cards the tab has.
			var spread: float = absf(widths[-1] - widths[0])
			var allowed: float = BuildSidebar.CARD_SLACK_PX + 2.0
			assert_float(spread).override_failure_message(gap).is_less_equal(allowed)
			# A full row ends at the right edge, like the left margin (a short row leaves the rest).
			var columns: int = (
				(_sidebar.find_children("*", "GridContainer", true, false)[0] as GridContainer)
				. columns
			)
			if cards.size() >= columns:
				assert_float(items.end.x - right).override_failure_message(gap).is_between(
					-0.5, 1.5
				)


func test_the_zone_is_zero_while_closed_upright_and_sideways() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"], false)
		var why: String = str(screen["label"])
		assert_bool(_sidebar.visible).override_failure_message(why).is_false()
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal(0.0)
		assert_bool(is_inf(HudLayout.menu_top_px)).override_failure_message(why).is_true()
	assert_float(HudLayout.BUILD_ROW_DP).is_equal(HudCorners.BUILD_DP + HudCorners.GAP_DP)


func test_the_slide_eases_out_ends_on_the_target_and_the_zone_follows_it() -> void:
	for name: StringName in [&"android_6in", &"android_6in_portrait"]:
		var metrics: UiMetrics = UiProfiles.by_name(name)
		await _open(metrics.window_size, metrics, false)
		BuildSidebar.set_slide_ms_override(160)
		var portrait: bool = HudLayout.is_portrait()
		_sidebar.open()
		var seen: Array[float] = []
		var step: float = 0.016
		for frame: int in 12:
			_sidebar.advance(step)
			seen.append(_sidebar.size.y if portrait else _sidebar.size.x)
			if portrait:
				var zone: float = HudLayout.bottom_zone_px()
				var top: float = HudLayout.menu_top_px
				assert_float(_sidebar.position.y).is_equal_approx(top, 1.0)
				assert_float(zone).is_greater_equal(UiScale.dp(64.0) - 0.01)
		for index: int in range(1, seen.size()):
			assert_float(seen[index]).is_greater_equal(seen[index - 1])
		var back: Rect2 = _rect("Backdrop")
		assert_float(seen[-1]).is_equal_approx(back.size.y if portrait else back.size.x, 1.0)
		assert_float(seen[0]).is_less(seen[-1] * 0.7)  # Eases out: the first steps are the longest.
		if portrait:
			assert_array(_told).is_not_empty()
		else:
			assert_array(_told).is_empty()
		BuildSidebar.set_slide_ms_override(0)


func _visible_tiles() -> Array[ItemTile]:
	var tiles: Array[ItemTile] = []
	for node: Node in _sidebar.find_children("Tile_*", "", true, false):
		if (node as Control).visible:
			tiles.append(node as ItemTile)
	return tiles


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}. Each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait).
func _screens() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
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


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, with a snapshot of a base for the sidebar (which reads a runner of its own), the drawer
## open when `drawer`.
func _open(size: Vector2i, metrics: UiMetrics, drawer: bool = true) -> void:
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
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _hud("BuildSidebar")
	_sidebar.runner = runner
	var world: World = Sw.world()
	Sw.own(world, BASE)
	runner.snapshot = Sw.snapshot(world)
	_sidebar.refresh()
	_told.clear()
	_sidebar.zone_changed.connect(
		func(top: float, height: float) -> void: _told.append(Vector2(top, height))
	)
	if drawer:
		_sidebar.open()
	await _settle()
