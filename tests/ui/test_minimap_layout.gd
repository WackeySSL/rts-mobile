extends GdUnitTestSuite
## Where the minimap is at the six sizes of ScreenSizes.ALL with the engine's own metrics and at
## every profile of both orientations, also with a cutout (plan P88, ADR 0015 section 5, ADR 0023
## sections 4 and 12). Sideways it fills the floating panel at the top right (`MinimapSlot`, which
## keeps its 148 x 86 dp) with a 2:1 box of at least 120 dp across. Upright it is at the right end
## of the band, beside the tabs and the item row, under the status line (which keeps the band's
## full width): a 2:1 box of at most 40 % of the safe inner width and no higher than the band's
## inner height, inside the safe rect and the band, at least 48 dp on both axes and clear of the
## tabs, the items and the status line. The item row keeps its three whole tiles on the 6-inch
## phone and two at 360 dp. A turn moves the one minimap node between the two homes and it goes on
## jumping the camera. How the rest of the band sits is test_build_sidebar_layout's and
## test_build_sidebar_items_layout's, and the jump itself is test_minimap's.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar
var _minimap: Minimap
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


func test_sideways_the_minimap_fills_the_panel_at_the_top_right_with_a_2_to_1_box() -> void:
	for screen: Dictionary in _screens(false):
		await _open(screen["size"], screen["metrics"])
		var slot: Rect2 = _rect("MinimapSlot")
		var mini: Rect2 = _rect(_minimap)
		var box: Rect2 = _box()
		var safe: Rect2 = UiScale.safe_rect_base()
		var at: String = "%s: slot %s, minimap %s, box %s" % [screen["label"], slot, mini, box]
		assert_object(_minimap.get_parent()).override_failure_message(at).is_same(
			_hud("MinimapSlot")
		)
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(at).is_true()
		assert_bool(slot.grow(TOLERANCE_PX).encloses(mini)).override_failure_message(at).is_true()
		assert_bool(mini.grow(TOLERANCE_PX).encloses(box)).override_failure_message(at).is_true()
		assert_bool(safe.encloses(slot)).override_failure_message(at).is_true()
		# The panel is the slot of P85d, not grown by what is in it.
		var slot_dp: Vector2 = UiScale.dp_vec(HudLayout.SLOT_DP.x, HudLayout.SLOT_DP.y)
		assert_vector(slot.size).override_failure_message(at).is_equal_approx(
			slot_dp, Vector2(1.0, 1.0)
		)
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		assert_float(mini.size.x).override_failure_message(at).is_greater_equal(least)
		assert_float(mini.size.y).override_failure_message(at).is_greater_equal(least)
		assert_float(box.size.x).override_failure_message(at).is_equal_approx(
			box.size.y * 2.0, 0.01
		)
		assert_float(box.size.x).override_failure_message(at).is_greater_equal(
			UiScale.dp(120.0) - TOLERANCE_PX
		)
		assert_array(_sent).is_empty()


func test_upright_the_minimap_is_at_the_bands_right_end_within_its_height_and_40_percent() -> void:
	for screen: Dictionary in _screens(true):
		await _open(screen["size"], screen["metrics"])
		var band: Rect2 = _rect(_sidebar)
		var mini: Rect2 = _rect(_minimap)
		var box: Rect2 = _box()
		var status: Rect2 = _rect("Status")
		var inner: Rect2 = _inner()
		var edge: StyleBox = _sidebar.get_theme_stylebox(&"panel")
		var band_inner: Rect2 = Rect2(
			band.position + Vector2(edge.get_margin(SIDE_LEFT), edge.get_margin(SIDE_TOP)),
			band.size - edge.get_minimum_size()
		)
		var at: String = (
			"%s: band %s (inner %s), minimap %s, status %s, safe inner %s"
			% [screen["label"], band, band_inner, mini, status, inner]
		)
		assert_object(_minimap.get_parent()).override_failure_message(at).is_same(_hud("Body"))
		(
			assert_bool((_hud("MinimapSlot") as Control).visible)
			. override_failure_message(at)
			. is_false()
		)
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(at).is_true()
		assert_bool(UiScale.safe_rect_base().encloses(mini)).override_failure_message(at).is_true()
		assert_bool(band.grow(TOLERANCE_PX).encloses(mini)).override_failure_message(at).is_true()
		# The right end of the band's inner rect, and no higher than it.
		assert_float(mini.end.x).override_failure_message(at).is_equal_approx(band_inner.end.x, 1.5)
		assert_float(mini.size.y).override_failure_message(at).is_less_equal(
			band_inner.size.y + TOLERANCE_PX
		)
		assert_float(mini.size.x).override_failure_message(at).is_less_equal(
			HudLayout.MINIMAP_SHARE * inner.size.x + 1.0
		)
		assert_float(box.size.x).override_failure_message(at).is_equal_approx(
			box.size.y * 2.0, 0.01
		)
		assert_vector(box.size).override_failure_message(at).is_equal_approx(
			mini.size, Vector2(1.0, 1.0)
		)
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		assert_float(mini.size.x).override_failure_message(at).is_greater_equal(least)
		assert_float(mini.size.y).override_failure_message(at).is_greater_equal(least)
		# Under the status line, which stays the band's full width; beside the tabs and the items.
		assert_float(mini.position.y).override_failure_message(at).is_greater_equal(
			status.end.y - TOLERANCE_PX
		)
		assert_float(status.end.x).override_failure_message(at).is_equal_approx(
			band_inner.end.x, 1.5
		)
		for part: String in ["Tabs", "Items"]:
			var rect: Rect2 = _rect(part)
			var beside: String = "%s: %s %s" % [at, part, rect]
			assert_bool(rect.intersects(mini)).override_failure_message(beside).is_false()
			assert_float(rect.end.x).override_failure_message(beside).is_less_equal(
				mini.position.x + TOLERANCE_PX
			)
		assert_bool(status.intersects(mini)).override_failure_message(at).is_false()
		assert_array(_sent).is_empty()


## ADR 0015 section 5's budget: the minimap takes at most 40 % of the inner width, which leaves the
## item row three whole 64 dp tiles on the 6-inch phone and two at 360 dp, and the three tabs 48 dp.
func test_the_item_row_keeps_three_whole_tiles_on_the_6_inch_phone_and_two_at_360_dp() -> void:
	for case: Array in [[&"android_6in_portrait", 3], [&"web_phone_portrait", 2]]:
		var metrics: UiMetrics = UiProfiles.by_name(case[0])
		await _open(metrics.window_size, metrics)
		var items: Rect2 = _rect("Items")
		var whole: int = 0
		for node: Node in _sidebar.find_children("Tile_*", "", true, false):
			var tile: Control = node as Control
			whole += 1 if tile.visible and items.encloses(tile.get_global_rect().grow(-1.0)) else 0
		var why: String = "%s: %d whole tiles in %s" % [case[0], whole, items]
		assert_int(whole).override_failure_message(why).is_greater_equal(case[1])
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		for tab: String in ["TabStructures", "TabInfantry", "TabVehicles"]:
			assert_float(_rect(tab).size.x).override_failure_message(why).is_greater_equal(least)


## A turn moves the one node between the slot and the band, keeps it and its picture, and the
## minimap goes on centring the camera where it is touched; it sends no Command.
func test_a_turn_moves_the_one_minimap_between_the_slot_and_the_band_and_it_goes_on_jumping(
) -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	var camera: RtsCamera = _main.get_node("Camera")
	var picture: MinimapImage = _minimap.picture()
	var target: Vector2 = IsoProjection.ground_to_px(30000, 18000)
	for turn: UiMetrics in [portrait, landscape, portrait, landscape]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		var home: Node = _hud("MinimapSlot") if turn == landscape else _hud("Body")
		var why: String = "%s: minimap in %s" % [turn.window_size, _minimap.get_parent().name]
		assert_object(_hud("Minimap")).override_failure_message(why).is_same(_minimap)
		assert_object(_minimap.get_parent()).override_failure_message(why).is_same(home)
		assert_object(_minimap.picture()).is_same(picture)
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(UiScale.safe_rect_base().encloses(_rect(_minimap))).is_true()
		camera.centre_on(Vector2.ZERO)
		var at: Vector2 = _rect(_minimap).position + _minimap.world_to_local(target)
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_vector(camera.position).override_failure_message(why).is_equal_approx(
			target, Vector2(0.1, 0.1)
		)
	assert_array(_sent).is_empty()


## The minimap's 2:1 box in base px on the screen.
func _box() -> Rect2:
	var box: Rect2 = _minimap.box_rect()
	return Rect2(_rect(_minimap).position + box.position, box.size)


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}; each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait). `portrait`: only that orientation.
func _screens(portrait: bool) -> Array[Dictionary]:
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
	var out: Array[Dictionary] = []
	for screen: Dictionary in all:
		if UiScale.is_portrait_size(screen["size"]) == portrait:
			out.append(screen)
	return out


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


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, the Commands caught, the sidebar reading a runner of its own with a base for its tiles
## (the map's layers have no art for a building before P84).
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
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _hud("BuildSidebar")
	_sidebar.runner = runner
	var world: World = Sw.world()
	Sw.own(world, BASE)
	runner.snapshot = Sw.snapshot(world)
	_sidebar.refresh()
	_minimap = _hud("Minimap")
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = (func(
		command: Command
	) -> void:
		_sent.append(command))
	await _settle()
