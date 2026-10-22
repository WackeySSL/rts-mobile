extends GdUnitTestSuite
## The battle-screen HUD in both orientations (plan P61, ADR 0015 section 5), at the six sizes of
## ScreenSizes.ALL with the engine's own metrics and at every profile of both orientations, also
## with a cutout: every HUD control is inside the safe rect, at least 48 dp on each axis and clear
## of every other, and none enters the zone that the build sidebar will take (the right fifth in
## landscape; in portrait the bottom band, which is 0 high today and has a stand-in here). Landscape
## selects the 30 tanks the scene starts with, portrait the six MVP types with 3-digit counts.

const Roster: GDScript = preload("res://tests/ui/support/mvp_roster.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TANKS: Array[int] = [0, 0, 30]
const SIX_TYPES: Array[int] = [120, 100, 150, 110, 130, 140]
## A stand-in for the sidebar row's band height, in dp (ADR 0015 section 5: at least 200 dp).
const BAND_DP: float = 200.0
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


func test_every_hud_control_is_inside_the_safe_rect_48_dp_and_clear_of_the_others_in_the_zone(
) -> void:
	for screen: Dictionary in _screens():
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var visible_rect: Rect2 = get_viewport().get_visible_rect()
		var big: Dictionary[String, Rect2] = {
			"DevButton": _rect("DevButton"), "ArmyBar": _rect("ArmyBar"), "Panel": _rect(_panel)
		}
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
		if not HudLayout.is_portrait():  # The right zone stays free (today's rule).
			var zone: float = visible_rect.size.x - HudLayout.right_zone_px(visible_rect.size.x)
			for control: String in all:
				var at: String = "%s: %s %s, zone from %s" % [why, control, all[control], zone]
				assert_float(all[control].end.x).override_failure_message(at).is_less_equal(
					zone + TOLERANCE_PX
				)


func test_in_portrait_the_army_bar_is_on_the_bottom_edge_while_the_zone_is_0() -> void:
	for screen: Dictionary in _screens(true):
		await _open(screen)
		var why: String = str(screen["label"])
		assert_float(HudLayout.bottom_zone_px()).override_failure_message(why).is_equal(0.0)
		var bar: Rect2 = _rect("ArmyBar")
		var inner_bottom: float = _inner_bottom()
		assert_float(bar.end.y).override_failure_message(why).is_equal_approx(inner_bottom, 0.01)
		assert_bool(UiScale.safe_rect_base().encloses(bar)).override_failure_message(why).is_true()
		assert_int(_hud("ArmyBand").get_theme_constant("margin_bottom")).is_equal(0)


## With a band of 200 dp as the sidebar row will have it, no control enters the band, the bar sits
## a gap above it, and nothing else is in the bottom stack. The limit of 40% of the safe height is
## the plan's, for the six sizes and the profiles; a cutout takes height from both ends of the
## screen (SafeAreaMargin gives top and bottom the larger inset), so a case with one is left out
## of the limit, as a phone browser that is only 700 dp tall has no room left for it.
func test_in_portrait_a_stand_in_band_keeps_the_controls_out_and_the_bar_directly_above() -> void:
	HudLayout.bottom_zone_dp = BAND_DP
	for screen: Dictionary in _screens(true):
		await _open(screen)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var gap: float = UiScale.dp(8.0)
		var zone_top: float = _inner_bottom() - UiScale.dp(BAND_DP)
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


## A band height does nothing in landscape: the zone there is the right fifth.
func test_in_landscape_the_bar_stays_on_the_bottom_edge_whatever_the_band_height() -> void:
	HudLayout.bottom_zone_dp = BAND_DP
	for screen: Dictionary in _screens(false):
		await _open(screen)
		var why: String = str(screen["label"])
		assert_float(_rect("ArmyBar").end.y).override_failure_message(why).is_equal_approx(
			_inner_bottom(), 0.01
		)
		assert_int(_hud("ArmyBand").get_theme_constant("margin_bottom")).is_equal(0)


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own), cutout,
## portrait}; `portrait` true or false leaves out the other orientation. Each profile comes twice,
## the second time with a cutout of 100 px on the side where a phone has its camera (the left in
## landscape, the top in portrait).
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
	return {
		"label": label,
		"size": size,
		"metrics": metrics,
		"cutout": cutout,
		"portrait": UiScale.is_portrait_size(size),
	}


## The bottom of the safe area's inner rect, where the HUD may reach.
func _inner_bottom() -> float:
	var safe_area: Control = _hud("SafeArea")
	return get_viewport().get_visible_rect().end.y - safe_area.get_theme_constant("margin_bottom")


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## The rect of a HUD Control, by name or itself.
func _rect(control: Variant) -> Rect2:
	var node: Control = control if control is Control else _hud(control as String)
	return node.get_global_rect()


## A new main scene on `screen` with a mixed selection the size of its orientation.
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
	Roster.select(self, _panel, SIX_TYPES if screen["portrait"] else TANKS)
	await await_idle_frame()
