extends GdUnitTestSuite
## The floating panels of the battle screen in landscape (plan P85d, ADR 0023 section 12) and the
## band in portrait, at the six sizes of ScreenSizes.ALL with the engine's own metrics and at every
## profile of both orientations, also with a cutout. Landscape: the status pill is at the top left
## after the Dev button, the minimap's slot at the top right and the build panel at the bottom
## right, each inside the safe rect, at least 48 dp on both axes, the slot above the panel; the
## status line is the pill's, and the cards of the panel carry their names. Portrait: no pill and no
## slot, the status line is the band's first line, the tiles are plain. A turn moves the status line
## and keeps its nodes. A touch on the pill or the slot orders nothing. How every HUD control sits
## among the others is test_hud_layout's, the zone and the tabs are test_build_sidebar_layout's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
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
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_the_pill_the_slot_and_the_panel_are_at_their_corners_in_landscape_at_every_size() -> void:
	for screen: Dictionary in _screens(false):
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var inner: Rect2 = _inner()
		var safe: Rect2 = UiScale.safe_rect_base()
		var dev: Rect2 = _rect("DevButton")
		var pill: Rect2 = _rect("StatusPill")
		var slot: Rect2 = _rect("MinimapSlot")
		var panel: Rect2 = _rect(_sidebar)
		var at: String = (
			"%s: pill %s, slot %s, panel %s, inner %s" % [why, pill, slot, panel, inner]
		)
		for visible_part: String in ["StatusPill", "MinimapSlot"]:
			(
				assert_bool((_hud(visible_part) as Control).visible)
				. override_failure_message(at)
				. is_true()
			)
		# The top left: the pill starts a gap after the Dev button, on the same top line.
		assert_float(pill.position.y).override_failure_message(at).is_equal_approx(
			inner.position.y, TOLERANCE_PX
		)
		assert_float(pill.position.x).override_failure_message(at).is_equal_approx(
			dev.end.x + UiScale.dp(8.0), 1.5
		)
		# The top right, and the bottom right below it.
		assert_float(slot.end.x).override_failure_message(at).is_equal_approx(inner.end.x, 0.5)
		assert_float(slot.position.y).override_failure_message(at).is_equal_approx(
			inner.position.y, TOLERANCE_PX
		)
		assert_float(panel.end.x).override_failure_message(at).is_equal_approx(inner.end.x, 0.5)
		assert_float(panel.end.y).override_failure_message(at).is_equal_approx(inner.end.y, 0.5)
		assert_float(slot.end.y).override_failure_message(at).is_less_equal(panel.position.y)
		var sizes: Dictionary[String, Rect2] = {"pill": pill, "slot": slot, "panel": panel}
		for part: String in sizes:
			var rect: Rect2 = sizes[part]
			var least: float = UiScale.dp(48.0) - TOLERANCE_PX
			assert_bool(safe.encloses(rect)).override_failure_message(at).is_true()
			assert_float(rect.size.x).override_failure_message(at).is_greater_equal(least)
			assert_float(rect.size.y).override_failure_message(at).is_greater_equal(least)
		assert_float(pill.size.x).override_failure_message(at).is_greater_equal(
			UiScale.dp(HudLayout.PILL_DP) - TOLERANCE_PX
		)
		var slot_dp: Vector2 = UiScale.dp_vec(HudLayout.SLOT_DP.x, HudLayout.SLOT_DP.y)
		assert_float(slot.size.x).override_failure_message(at).is_greater_equal(
			slot_dp.x - TOLERANCE_PX
		)
		assert_float(slot.size.y).override_failure_message(at).is_greater_equal(
			slot_dp.y - TOLERANCE_PX
		)
		# The status line is the pill's, and it is whole inside it.
		assert_object(_hud("Status").get_parent()).is_same(_hud("StatusPill"))
		assert_bool(pill.encloses(_rect("Status"))).override_failure_message(at).is_true()


func test_in_portrait_there_is_no_pill_and_no_slot_and_the_status_line_is_the_bands_first() -> void:
	for screen: Dictionary in _screens(true):
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		(
			assert_bool((_hud("StatusPill") as Control).visible)
			. override_failure_message(why)
			. is_false()
		)
		(
			assert_bool((_hud("MinimapSlot") as Control).visible)
			. override_failure_message(why)
			. is_false()
		)
		var status: Node = _hud("Status")
		assert_object(status.get_parent()).override_failure_message(why).is_same(_hud("Stack"))
		assert_int(status.get_index()).override_failure_message(why).is_equal(0)
		(
			assert_bool(_rect(_sidebar).encloses(_rect("Status")))
			. override_failure_message(why)
			. is_true()
		)


## A turn moves the status line between the pill and the band, keeps its nodes (the same credits
## label and bar) and what they show, and sends nothing.
func test_a_turn_moves_the_status_line_between_the_pill_and_the_band_and_keeps_its_nodes() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	var status: Node = _hud("Status")
	var credits: Label = _hud("Credits")
	var bar: ProgressBar = _hud("PowerBar")
	credits.text = "1234"
	for turn: UiMetrics in [portrait, landscape, portrait, landscape]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await await_idle_frame()
		await await_idle_frame()
		var home: Node = _hud("StatusPill") if turn == landscape else _hud("Stack")
		assert_object(_hud("Status")).is_same(status)
		assert_object(status.get_parent()).is_same(home)
		assert_object(_hud("Credits")).is_same(credits)
		assert_object(_hud("PowerBar")).is_same(bar)
		assert_str(credits.text).is_equal("1234")
		assert_bool((_hud("StatusPill") as Control).visible).is_equal(turn == landscape)
		assert_bool((_hud("MinimapSlot") as Control).visible).is_equal(turn == landscape)
	assert_array(_sent).is_empty()


## The cards of the panel are named after the snapshot's display names, under the cost's plate, in
## 14 dp type that is cut with an ellipsis where it does not fit; the plain tiles of the band show
## no name.
func test_the_cards_carry_the_types_names_in_landscape_and_the_band_tiles_do_not() -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"])
		var snap: MatchSnapshot = _publish()
		await await_idle_frame()
		await await_idle_frame()
		var why: String = str(screen["label"])
		var tiles: int = 0
		for node: Node in _sidebar.find_children("Tile_*", "", true, false):
			var tile: ItemTile = node as ItemTile
			var label: Label = tile.find_child("Caption", true, false)
			assert_str(label.text).override_failure_message(why).is_equal(
				snap.type_names[tile.type_index]
			)
			assert_bool(label.visible).override_failure_message(why).is_equal(
				not HudLayout.is_portrait()
			)
			if not tile.visible or HudLayout.is_portrait():
				continue
			tiles += 1
			var rect: Rect2 = tile.get_global_rect()
			var plate: Rect2 = (tile.find_child("Cost", true, false) as Control).get_global_rect()
			var named: Rect2 = label.get_global_rect()
			var at: String = (
				"%s: %s: name %s, plate %s, card %s" % [why, tile.name, named, plate, rect]
			)
			(
				assert_bool(rect.grow(TOLERANCE_PX).encloses(named))
				. override_failure_message(at)
				. is_true()
			)
			assert_float(named.position.y).override_failure_message(at).is_greater_equal(
				plate.end.y - TOLERANCE_PX
			)
			assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
			(
				assert_int(label.get_theme_font_size(&"font_size"))
				. override_failure_message(at)
				. is_greater_equal(roundi(UiScale.dp(14.0)))
			)
		if not HudLayout.is_portrait():
			assert_int(tiles).override_failure_message(why).is_greater(0)


## A touch on the pill or on the slot is the panel's own: with units selected it orders nothing,
## where a tap on the map does.
func test_a_touch_on_the_pill_or_the_slot_orders_nothing_and_a_touch_on_the_map_does() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var controller: PlayerController = _main.get_node("PlayerController")
	controller.selection.set_ids(PackedInt32Array([1, 2]))
	for part: String in ["StatusPill", "MinimapSlot"]:
		var at: Vector2 = _rect(part).get_center()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_array(_sent).override_failure_message(part).is_empty()
	assert_array(controller.selection.selected).is_equal([1, 2])
	var ground: Vector2 = Vector2(300.0, 360.0)  # Clear of the panels, the units and the HUD.
	TouchEvents.press(get_viewport(), 0, ground)
	TouchEvents.release(get_viewport(), 0, ground)
	assert_array(_sent).has_size(1)


## The build panel takes what the bottom row leaves after the ArmyBar (288 dp), the selection
## panel's row (200 dp) and the gaps (8 dp each): at least two whole cards, at most the canvas's
## 372 dp, and exactly three whole cards' worth on the narrowest phone browser (776 dp inside).
func test_the_panel_takes_what_the_bottom_row_leaves_within_two_cards_and_372_dp() -> void:
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # 1 dp is 1 base px.
	assert_float(HudLayout.panel_px(776.0)).is_equal_approx(3.0 * 80.0 + 2.0 * 8.0 + 16.0, 0.01)
	assert_float(HudLayout.panel_px(900.0)).is_equal_approx(372.0, 0.01)
	assert_float(HudLayout.panel_px(5000.0)).is_equal_approx(372.0, 0.01)
	assert_float(HudLayout.panel_px(710.0)).is_equal_approx(206.0, 0.01)  # With a cutout.
	assert_float(HudLayout.panel_px(100.0)).is_equal_approx(2.0 * 80.0 + 8.0 + 16.0, 0.01)
	assert_float(HudLayout.right_zone_px(776.0)).is_equal_approx(272.0 + 8.0, 0.01)
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1.75 base px per dp.
	assert_float(HudLayout.panel_px(1400.0)).is_equal_approx(1400.0 - 504.0 * 1.75, 0.01)


## Publishes the snapshot of a base to the sidebar (it reads a runner of its own: the map's layers
## have no art for a building before P84), reads it at once and returns it.
func _publish() -> MatchSnapshot:
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var snap: MatchSnapshot = Sw.snapshot(world)
	_sidebar.runner.snapshot = snap
	_sidebar.refresh()
	return snap


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}; each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait). `portrait`: only that orientation (true or
## false), or both (null).
func _screens(portrait: Variant) -> Array[Dictionary]:
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
		if portrait == null or UiScale.is_portrait_size(screen["size"]) == portrait:
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


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, the Commands caught, the sidebar reading a runner of its own.
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
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = (func(
		command: Command
	) -> void:
		_sent.append(command))
	await await_idle_frame()
