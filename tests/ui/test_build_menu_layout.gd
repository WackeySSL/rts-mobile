extends GdUnitTestSuite
## The collapsible build menu laid out in both states (plan P85f, ADR 0024 sections 2 to 4 and 9),
## in the main scene at the six sizes of ScreenSizes.ALL with the engine's own metrics and at every
## profile of both orientations, also with a cutout. Upright: the open band, or the 96 dp strip on
## the safe bottom edge (the status line over the Build button and the Ready badge, the minimap at
## its right end in the same size on the phone profiles), the ArmyBar 8 dp above whichever shows,
## the strike row above the ArmyBar's line, the bottom stack within 40 % of the safe height.
## Sideways: the floating panel, or the plate, 56 dp high, at the bottom right with the Build
## button under the right thumb, the pill, the minimap's slot and the SelectionPanel unmoved by the
## collapse. `HudLayout.bottom_zone_dp` is the menu's height and `menu_top_px` its drawn top in both
## states. The slide is test_build_menu_slide.gd's, the triggers are test_build_menu_triggers.gd's.
## Player 1 has a Headquarters, a light tank and a finished power plant in its queue.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ROSTER: Array = ["power_plant", "barracks", "light_tank"]
const TANK: int = 3  ## Its id: the Headquarters is 1, the enemy's 2.
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 1.5
const STACK_LIMIT: float = 0.4
const PHONES: Array[StringName] = [&"android_6in_portrait", &"web_phone_portrait"]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _controller: PlayerController
var _profile: StringName = &""


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


## The override and the statics are global: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF


func test_upright_the_open_band_and_the_strip_stand_on_the_safe_bottom_edge_with_the_bar_on_top(
) -> void:
	for screen: Dictionary in _screens(true):
		await _open(screen["size"], screen["metrics"], screen["profile"])
		var why: String = str(screen["label"])
		var band: Rect2 = _rect(_sidebar)
		var safe_dp: float = UiScale.safe_rect_base().size.y / UiScale.base_px_per_dp()
		var reserved_dp: float = 12.0 + ArmyBar.GAP_DP + ArmyBar.ALL_ARMY_DP.y
		var band_px: float = UiScale.dp(HudLayout.band_dp(safe_dp, reserved_dp))
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()  # A match opens it.
		_expect_zone(why + " open", band, band_px)
		var mini_open: Rect2 = _rect("Minimap")
		_sidebar.collapse()
		await _settle()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		var strip: Rect2 = _rect(_sidebar)
		_expect_zone(why + " collapsed", strip, UiScale.dp(HudLayout.STRIP_DP))
		assert_float(strip.size.y).override_failure_message(why).is_less(band.size.y)
		_expect_strip(why, strip)
		var mini: Rect2 = _rect("Minimap")
		if PHONES.has(_profile):  # The room is the target state's: one size in both states.
			var same: String = "%s: minimap open %s, collapsed %s" % [why, mini_open, mini]
			assert_vector(mini.size).override_failure_message(same).is_equal_approx(
				mini_open.size, Vector2.ONE * TOLERANCE_PX
			)
			assert_float(mini.end.x).override_failure_message(same).is_equal_approx(
				mini_open.end.x, TOLERANCE_PX
			)
		_sidebar.open()
		await _settle()
		assert_vector(_rect(_sidebar).size).override_failure_message(why).is_equal_approx(
			band.size, Vector2.ONE * TOLERANCE_PX
		)
		assert_vector(_rect(_sidebar).position).override_failure_message(why).is_equal_approx(
			band.position, Vector2.ONE * TOLERANCE_PX
		)
		_expect_zone(why + " open again", _rect(_sidebar), band_px)


## The strip: the status line over the Build button and the Ready badge, the minimap at the right
## end, all inside it and clear of each other; the Build button 64 x 48 dp, the badge at most 112 dp
## across and 48 dp high, and the word "Ready" in 14 dp type.
func _expect_strip(why: String, strip: Rect2) -> void:
	var inner: Rect2 = _inner()
	var status: Rect2 = _rect("Status")
	var build: Rect2 = _rect("Build")
	var badge: Rect2 = _rect("Ready")
	var mini: Rect2 = _rect("Minimap")
	var dp: float = UiScale.base_px_per_dp()
	assert_bool((_hud("Items") as Control).is_visible_in_tree()).is_false()
	assert_bool((_hud("Tabs") as Control).is_visible_in_tree()).is_false()
	assert_bool((_hud("Status") as Control).is_visible_in_tree()).is_true()
	assert_bool((_hud("Build") as Control).is_visible_in_tree()).is_true()
	assert_bool((_hud("Ready") as Control).is_visible_in_tree()).is_true()  # A structure is ready.
	assert_bool(_minimap().is_visible_in_tree()).override_failure_message(why).is_true()
	var parts: Dictionary[String, Rect2] = {
		"Status": status, "Build": build, "Ready": badge, "Minimap": mini
	}
	for part: String in parts:
		var at: String = "%s: %s %s in the strip %s" % [why, part, parts[part], strip]
		(
			assert_bool(strip.grow(TOLERANCE_PX).encloses(parts[part]))
			. override_failure_message(at)
			. is_true()
		)
		assert_bool(UiScale.safe_rect_base().encloses(parts[part])).is_true()
	var names: Array = parts.keys()
	for first: int in names.size():
		for second: int in range(first + 1, names.size()):
			var pair: String = "%s: %s and %s" % [why, names[first], names[second]]
			var overlap: bool = parts[names[first]].intersects(parts[names[second]])
			assert_bool(overlap).override_failure_message(pair).is_false()
	assert_float(status.end.y).override_failure_message(why).is_less_equal(
		build.position.y + TOLERANCE_PX
	)
	assert_float(build.position.x).override_failure_message(why).is_less(badge.position.x)
	assert_vector(build.size).override_failure_message(why).is_equal_approx(
		Vector2(64.0, 48.0) * dp, Vector2.ONE * TOLERANCE_PX
	)
	assert_float(badge.size.x).override_failure_message(why).is_less_equal(
		112.0 * dp + TOLERANCE_PX
	)
	assert_float(badge.size.y).override_failure_message(why).is_greater_equal(
		48.0 * dp - TOLERANCE_PX
	)
	assert_float(status.size.x).override_failure_message(why).is_greater_equal(
		139.0 * dp - TOLERANCE_PX
	)  # The status line's least width (ADR 0024 section 2).
	assert_float(mini.end.x).override_failure_message(why).is_equal_approx(
		strip.end.x - UiScale.dp(8.0), TOLERANCE_PX
	)
	assert_float(mini.size.x).override_failure_message(why).is_less_equal(
		HudLayout.MINIMAP_SHARE * inner.size.x + TOLERANCE_PX
	)
	assert_float(mini.size.y).override_failure_message(why).is_less_equal(
		UiScale.dp(HudLayout.STRIP_DP) - UiScale.dp(8.0) + TOLERANCE_PX
	)
	assert_float(mini.size.x).override_failure_message(why).is_equal_approx(
		mini.size.y * 2.0, TOLERANCE_PX
	)
	var badge_text: Button = _hud("Ready") as Button
	assert_str(badge_text.text).is_equal("Ready")
	assert_object(badge_text.icon).is_not_null()
	var font_px: int = badge_text.get_theme_font_size(&"font_size")
	assert_int(font_px).is_greater_equal(roundi(14.0 * dp))  # At least 14 sp.


## The zone, the drawn top and what rides on them for a menu of height `height` px whose drawn rect
## is `rect`: on the safe area's inner bottom edge across its width, the zone and the top those of
## the rect, the ArmyBar 8 dp above it, the strike row a bar and a gap above that, the bottom stack
## within 40 % of the safe height.
func _expect_zone(why: String, rect: Rect2, height: float) -> void:
	var inner: Rect2 = _inner()
	var dp: float = UiScale.base_px_per_dp()
	var at: String = "%s: menu %s, inner %s" % [why, rect, inner]
	assert_float(rect.size.y).override_failure_message(at).is_equal_approx(height, TOLERANCE_PX)
	assert_float(rect.end.y).override_failure_message(at).is_equal_approx(inner.end.y, TOLERANCE_PX)
	assert_float(rect.position.x).override_failure_message(at).is_equal_approx(
		inner.position.x, TOLERANCE_PX
	)
	assert_float(rect.size.x).override_failure_message(at).is_equal_approx(
		inner.size.x, TOLERANCE_PX
	)
	assert_bool(UiScale.safe_rect_base().encloses(rect)).override_failure_message(at).is_true()
	assert_float(HudLayout.bottom_zone_dp * dp).override_failure_message(at).is_equal_approx(
		height, 0.01
	)
	assert_float(HudLayout.menu_top_px).override_failure_message(at).is_equal_approx(
		rect.position.y, TOLERANCE_PX
	)
	var bar: Rect2 = _rect("ArmyBar")
	assert_float(bar.end.y + 8.0 * dp).override_failure_message(at).is_equal_approx(
		rect.position.y, TOLERANCE_PX
	)
	var army_margin: int = (_hud("ArmyBand") as MarginContainer).get_theme_constant("margin_bottom")
	var strike_margin: int = (_hud("StrikeBand") as MarginContainer).get_theme_constant(
		"margin_bottom"
	)
	assert_float(float(strike_margin - army_margin)).override_failure_message(at).is_equal_approx(
		ceilf(56.0 * dp) + ceilf(8.0 * dp), 1.0
	)  # The row sits a gap above the bar's line.
	# The stack is the menu, the gap and the bar, and the edge margin that ADR 0015 counts with them.
	var safe: Rect2 = UiScale.safe_rect_base()
	var stack: float = inner.end.y - bar.position.y + 12.0 * dp
	assert_float(stack).override_failure_message(at).is_less_equal(STACK_LIMIT * safe.size.y + 2.0)


func test_sideways_the_plate_is_56_dp_at_the_bottom_right_and_the_pill_slot_and_panel_stay(
) -> void:
	for screen: Dictionary in _screens(false):
		await _open(screen["size"], screen["metrics"], screen["profile"])
		var why: String = str(screen["label"])
		var dp: float = UiScale.base_px_per_dp()
		var inner: Rect2 = _inner()
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		await _settle()
		(
			assert_bool((_hud("SelectionPanel") as Control).visible)
			. override_failure_message(why)
			. is_true()
		)
		var panel: Rect2 = _rect(_sidebar)
		var open_parts: Array[Rect2] = _fixed()
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal(0.0)
		assert_float(HudLayout.menu_top_px).override_failure_message(why).is_equal_approx(
			UiScale.safe_rect_base().end.y, TOLERANCE_PX
		)
		_sidebar.collapse()
		await _settle()
		var plate: Rect2 = _rect(_sidebar)
		var at: String = "%s: plate %s, panel %s, inner %s" % [why, plate, panel, inner]
		assert_float(plate.size.y).override_failure_message(at).is_equal_approx(
			56.0 * dp, TOLERANCE_PX
		)
		assert_float(plate.end.y).override_failure_message(at).is_equal_approx(
			panel.end.y, TOLERANCE_PX
		)
		assert_float(plate.end.x).override_failure_message(at).is_equal_approx(
			panel.end.x, TOLERANCE_PX
		)
		assert_float(plate.size.x).override_failure_message(at).is_less_equal(
			(8.0 + 112.0 + 8.0 + 64.0 + 8.0) * dp + TOLERANCE_PX
		)
		assert_bool(UiScale.safe_rect_base().encloses(plate)).override_failure_message(at).is_true()
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(at).is_equal(0.0)
		assert_float(HudLayout.menu_top_px).override_failure_message(at).is_equal_approx(
			UiScale.safe_rect_base().end.y, TOLERANCE_PX
		)
		# The Build button is the rightmost part, 64 x 48 dp, with the Ready badge left of it.
		var build: Rect2 = _rect("Build")
		var badge: Rect2 = _rect("Ready")
		assert_bool(plate.grow(TOLERANCE_PX).encloses(build)).override_failure_message(at).is_true()
		assert_bool(plate.grow(TOLERANCE_PX).encloses(badge)).override_failure_message(at).is_true()
		assert_float(build.end.x).override_failure_message(at).is_equal_approx(
			plate.end.x - 8.0 * dp, TOLERANCE_PX
		)
		assert_vector(build.size).override_failure_message(at).is_equal_approx(
			Vector2(64.0, 48.0) * dp, Vector2.ONE * TOLERANCE_PX
		)
		assert_float(badge.end.x).override_failure_message(at).is_less_equal(build.position.x)
		assert_float(badge.size.x).override_failure_message(at).is_less_equal(
			112.0 * dp + TOLERANCE_PX
		)
		assert_float(badge.size.y).override_failure_message(at).is_greater_equal(
			48.0 * dp - TOLERANCE_PX
		)
		assert_bool((_hud("Items") as Control).is_visible_in_tree()).is_false()
		assert_bool((_hud("Status") as Control).is_visible_in_tree()).is_true()  # In the pill.
		assert_object(_hud("Status").get_parent()).is_same(_hud("StatusPill"))
		assert_object(_minimap().get_parent()).is_same(_hud("MinimapSlot"))
		# The pill, the minimap's slot and the SelectionPanel do not move with the collapse.
		var now: Array[Rect2] = _fixed()
		for index: int in now.size():
			var moved: String = (
				"%s: part %d was %s, is %s" % [why, index, open_parts[index], now[index]]
			)
			assert_vector(now[index].position).override_failure_message(moved).is_equal_approx(
				open_parts[index].position, Vector2.ONE * TOLERANCE_PX
			)
			assert_vector(now[index].size).override_failure_message(moved).is_equal_approx(
				open_parts[index].size, Vector2.ONE * TOLERANCE_PX
			)
		# The plate is as wide as its row: when the badge goes it narrows to the Build button, and
		# when it comes back it widens again; the badge and the button are inside it each time.
		var with_badge: Rect2 = _rect(_sidebar)
		_runner.snapshot.queue_count[World.TABS + World.Tab.STRUCTURES] = 0
		_sidebar.refresh()
		await _settle()
		var bare: Rect2 = _rect(_sidebar)
		assert_bool((_hud("Ready") as Control).is_visible_in_tree()).is_false()
		assert_float(bare.size.x).override_failure_message(why).is_less(
			with_badge.size.x - 8.0 * dp
		)
		assert_float(bare.end.x).override_failure_message(why).is_equal_approx(
			with_badge.end.x, TOLERANCE_PX
		)
		(
			assert_bool(bare.grow(TOLERANCE_PX).encloses(_rect("Build")))
			. override_failure_message(why)
			. is_true()
		)
		Rig.make_ready(_runner.snapshot)
		_sidebar.refresh()
		await _settle()
		var back: Rect2 = _rect(_sidebar)
		assert_vector(back.size).override_failure_message(why).is_equal_approx(
			with_badge.size, Vector2.ONE * TOLERANCE_PX
		)
		(
			assert_bool(back.grow(TOLERANCE_PX).encloses(_rect("Ready")))
			. override_failure_message(why)
			. is_true()
		)
		(
			assert_bool(back.grow(TOLERANCE_PX).encloses(_rect("Build")))
			. override_failure_message(why)
			. is_true()
		)
		_sidebar.open()
		await _settle()
		assert_vector(_rect(_sidebar).size).override_failure_message(why).is_equal_approx(
			panel.size, Vector2.ONE * TOLERANCE_PX
		)
		assert_float(_rect(_sidebar).end.x).override_failure_message(why).is_equal_approx(
			panel.end.x, TOLERANCE_PX
		)


## The collapsed menu at every screen: each visible control is inside the safe rect, each that is
## tapped at least 48 dp across, and no two overlap (the Dev button, the ArmyBar, the selection
## panel, the Build button and the badge, the status line or the pill, the minimap).
func test_collapsed_every_visible_hud_control_is_48_dp_inside_the_safe_rect_and_clear() -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"], screen["profile"])
		var why: String = str(screen["label"])
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_sidebar.collapse()
		await _settle()
		var shown: Array[String] = ["DevButton", "AllArmy", "Group1", "Group2", "Group3"]
		shown.append_array(["SelectionPanel", "Build", "Ready", "Minimap"])
		var tapped: Array[String] = shown.duplicate()
		shown.append("StatusPill" if not HudLayout.is_portrait() else "Status")
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		var rects: Dictionary[String, Rect2] = {}
		for part: String in shown:
			var control: Control = _hud(part) as Control
			(
				assert_bool(control.is_visible_in_tree())
				. override_failure_message("%s: %s" % [why, part])
				. is_true()
			)
			rects[part] = control.get_global_rect()
			var at: String = "%s: %s %s" % [why, part, rects[part]]
			(
				assert_bool(UiScale.safe_rect_base().encloses(rects[part]))
				. override_failure_message(at)
				. is_true()
			)
			if tapped.has(part):
				assert_float(rects[part].size.x).override_failure_message(at).is_greater_equal(
					least
				)
				assert_float(rects[part].size.y).override_failure_message(at).is_greater_equal(
					least
				)
		for first: int in shown.size():
			for second: int in range(first + 1, shown.size()):
				var pair: String = "%s: %s and %s" % [why, shown[first], shown[second]]
				var a: Rect2 = rects[shown[first]]
				var b: Rect2 = rects[shown[second]]
				(
					assert_bool(a.grow(-0.5).intersects(b.grow(-0.5)))
					. override_failure_message(pair)
					. is_false()
				)


## The parts that a collapse leaves where they are in landscape: the pill, the minimap's slot and
## the SelectionPanel.
func _fixed() -> Array[Rect2]:
	return [_rect("StatusPill"), _rect("MinimapSlot"), _rect("SelectionPanel")]


func _minimap() -> Control:
	return _hud("Minimap") as Control


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}; each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait). `portrait`: only that orientation, or both
## (null).
func _screens(portrait: Variant) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null, "profile": &""})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, m.window_size.x - CUTOUT_PX, m.window_size.y)
		all.append(
			{
				"label": str(profile_name),
				"size": m.window_size,
				"metrics": m,
				"profile": profile_name
			}
		)
		all.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": UiProfiles.with_safe_area(m, cut),
				"profile": &""
			}
		)
	var out: Array[Dictionary] = []
	for screen: Dictionary in all:
		if portrait == null or UiScale.is_portrait_size(screen["size"]) == portrait:
			out.append(screen)
	return out


## The safe area's inner rect, where the HUD may reach.
func _inner() -> Rect2:
	var area: Control = _hud("SafeArea") as Control
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


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, the plant ready and the sidebar showing it.
func _open(size: Vector2i, metrics: UiMetrics, profile_name: StringName) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	_profile = profile_name
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", [["light_tank", 8, 10]], ROSTER)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	Rig.make_ready(_runner.snapshot)
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_controller = _main.get_node("PlayerController")
	_sidebar.refresh()
	await _settle()
