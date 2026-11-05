extends GdUnitTestSuite
## The command bar (plan P122, ADR 0025 sections 1 and 9) in the main scene at the six sizes of
## ScreenSizes.ALL: it shows for a selection and hides without one; Deselect (48 x 64 dp) clears
## units, an own building and an enemy building with no Command; Stop sends one STOP for units and
## a building has no order; there is no Attack button; the bar keeps its slot during placement and
## the strike aim (BUILD, the strike button and its check mark and X stay where they are); upright
## BUILD stands a gap above the bar; Deselect is at the bar's start, mirrored too.
## Player 1 has a Deep Bore (id 1, an own building), a light tank (2), a rifle squad (4) and the
## enemy Headquarters (3).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const PlacementRig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BORE: int = 1
const TANK: int = 2
const ENEMY_HQ: int = 3
const RIFLE: int = 4
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
	[1, "rifle_squad", 15, 15],
]
const TOLERANCE_PX: float = 0.5
## What must not move under the thumb while a mode runs.
const FROZEN: Array[String] = ["BuildButton", "StrikeControls"]

var _window_size_before: Vector2i
var _main: Node2D
var _aim: StrikeAim
var _placement: PlacementController
var _controller: PlayerController
var _bar: CommandBar
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func before_test() -> void:
	MenuRig.begin()


func test_the_bar_shows_for_a_selection_and_hides_without_one_at_every_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		assert_bool(_bar.visible).override_failure_message(why).is_false()
		await _select([TANK])
		assert_bool(_bar.visible).override_failure_message(why).is_true()
		assert_bool(_stop().is_visible_in_tree()).override_failure_message(why).is_true()
		await _select([])
		assert_bool(_bar.visible).override_failure_message(why).is_false()


func test_deselect_is_48_by_64_dp_at_the_bars_start_sideways_and_upright_mirrored_too() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		await _select([TANK])
		var why: String = str(size)
		var clear: Rect2 = _rect("Deselect")
		assert_float(clear.size.x).override_failure_message(why).is_greater_equal(
			UiScale.dp(48.0) - TOLERANCE_PX
		)
		assert_float(clear.size.y).override_failure_message(why).is_greater_equal(
			UiScale.dp(64.0) - TOLERANCE_PX
		)
		var bar: Rect2 = _bar.get_global_rect()
		assert_float(clear.position.x).override_failure_message(why).is_equal_approx(
			bar.position.x, 1.5
		)
		assert_bool(clear.position.x < _rect("Stop").position.x).is_true()
		_bar.mirror = true
		_bar.place()
		await await_idle_frame()
		bar = _bar.get_global_rect()
		clear = _rect("Deselect")
		var mirrored: String = "%s mirrored: clear %s, bar %s" % [why, clear, bar]
		assert_float(clear.end.x).override_failure_message(mirrored).is_equal_approx(bar.end.x, 1.5)
		assert_bool(clear.position.x > _rect("Stop").position.x).is_true()


func test_deselect_clears_units_an_own_building_and_an_enemy_building_with_no_command() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		for ids: Array in [[TANK], [TANK, RIFLE], [BORE], [ENEMY_HQ]]:
			await _select(ids)
			assert_bool(_bar.visible).override_failure_message("%s %s" % [size, ids]).is_true()
			_tap(_hud("Deselect") as Control)
			var why: String = "%s: Deselect with %s" % [size, ids]
			assert_array(_controller.selection.selected).override_failure_message(why).is_empty()
			assert_bool(_bar.visible).override_failure_message(why).is_false()
			assert_array(_sent).override_failure_message(why).is_empty()


func test_stop_sends_one_stop_for_units_and_a_building_has_no_order_and_no_attack_button() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], null)
	await _select([TANK, RIFLE])
	_tap(_stop())
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.STOP)
	assert_array(_sent[0].unit_ids).is_equal([TANK, RIFLE])
	assert_array(_controller.selection.selected).is_equal([TANK, RIFLE])  # Stop keeps it.
	for kind: Array in [[BORE], [ENEMY_HQ]]:
		await _select(kind)
		assert_bool(_bar.visible).is_true()
		assert_bool(_stop().is_visible_in_tree()).override_failure_message(str(kind)).is_false()
	assert_int(_sent.size()).is_equal(1)
	for node: Node in _bar.find_children("*", "Button", true, false):
		assert_bool("attack" in node.name.to_lower()).is_false()
	for order: Dictionary in CommandBar.ORDERS:
		assert_str(str(order["id"])).is_not_equal("attack")


## Stop is a HUD tap: during the strike aim it sends one STOP too, with the buzz.
func test_stop_works_during_the_aim_and_buzzes() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], null)
	var buzzes: Array[int] = []
	_controller.vibrate = func(ms: int) -> void: buzzes.append(ms)
	await _select([TANK])
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
	_aim.refresh()
	assert_bool(_aim.begin()).is_true()
	await await_idle_frame()
	assert_bool(_stop().is_visible_in_tree()).is_true()
	_tap(_stop())
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.STOP)
	assert_int(buzzes.size()).is_equal(1)


## Michael, 2026-11-05: upright BUILD stays in the bottom right corner, whether the bar shows or
## not, and the bar ends a gap short of it.
func test_upright_build_stays_in_the_corner_and_the_bar_ends_short_of_it() -> void:
	for size: Vector2i in ScreenSizes.PORTRAIT:
		await _open(size, null)
		var empty: Rect2 = _rect("BuildButton")
		await _select([TANK])
		var bar: Rect2 = _bar.get_global_rect()
		var gap: float = UiScale.dp(8.0)
		var build: Rect2 = _rect("BuildButton")
		assert_that(build).override_failure_message(str(size)).is_equal(empty)
		assert_float(bar.end.x).override_failure_message(str(size)).is_less_equal(
			build.position.x - gap + 1.5
		)
		assert_float(bar.end.y).override_failure_message(str(size)).is_equal_approx(
			build.end.y, 1.5
		)


## Placement keeps the bar's slot: a group tap that fills or empties the selection moves neither
## BUILD nor the strike button, and Deselect leaves an empty plate; the layout follows the
## selection again when the mode ends.
func test_placement_freezes_the_slot_and_the_bottom_layout() -> void:
	for portrait: bool in [false, true]:
		for shown_at_start: bool in [false, true]:
			await _open(
				Vector2i.ZERO,
				UiProfiles.by_name(&"android_6in_portrait" if portrait else &"android_6in")
			)
			var why: String = "portrait %s, bar at start %s" % [portrait, shown_at_start]
			await _select([TANK] if shown_at_start else [])
			_make_ready()
			var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
			(
				assert_bool(_placement.begin(PlacementRig.plant(snap)))
				. override_failure_message(why)
				. is_true()
			)
			await await_idle_frame()
			await _check_frozen(why, shown_at_start)
			_placement.cancel()
			await await_idle_frame()
			await await_idle_frame()
			_assert_released(why, portrait)


func test_the_strike_aim_freezes_the_slot_and_the_bottom_layout() -> void:
	for portrait: bool in [false, true]:
		for shown_at_start: bool in [false, true]:
			await _open(
				Vector2i.ZERO,
				UiProfiles.by_name(&"android_6in_portrait" if portrait else &"android_6in")
			)
			var why: String = "aim, portrait %s, bar at start %s" % [portrait, shown_at_start]
			await _select([TANK] if shown_at_start else [])
			var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
			snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
			_aim.refresh()
			assert_bool(_aim.begin()).override_failure_message(why).is_true()
			await await_idle_frame()
			await await_idle_frame()
			await _check_frozen(why, shown_at_start)
			_aim.cancel()
			await await_idle_frame()
			await await_idle_frame()
			_assert_released(why, portrait)


## A placement that begins during the strike aim ends the aim, but the bar's slot holds through the
## swap: Deselect in the aim, then the placement, and nothing moves.
func test_a_placement_that_begins_during_the_aim_keeps_the_frozen_layout() -> void:
	for profile: StringName in [&"android_6in", &"android_6in_portrait"]:
		await _open(Vector2i.ZERO, UiProfiles.by_name(profile))
		await _select([TANK])
		var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
		snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
		_aim.refresh()
		assert_bool(_aim.begin()).is_true()
		await await_idle_frame()
		_tap(_hud("Deselect") as Control)
		await await_idle_frame()
		await await_idle_frame()
		var build: Rect2 = _rect("BuildButton")
		var plate: Rect2 = _bar.get_global_rect()
		_make_ready()
		assert_bool(_placement.begin(PlacementRig.plant(snap))).is_true()
		await await_idle_frame()
		await await_idle_frame()
		assert_that(_rect("BuildButton")).override_failure_message(str(profile)).is_equal(build)
		assert_that(_bar.get_global_rect()).override_failure_message(str(profile)).is_equal(plate)
		assert_bool(_bar.visible).override_failure_message(str(profile)).is_true()


## The chip asks for its text: a building's name and a 3-digit count are not cut to the health
## bar's width, and the bar grows to them (landscape: its width; upright: the chip stays inside).
func test_the_chip_is_as_wide_as_its_text() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		await _select([BORE])
		var label: Label = _bar.find_child("Count", true, false) as Label
		assert_str(label.text).is_equal("Deep Bore")
		_assert_label_fits(label, str(size))
		for text: String in ["×120", "×30"] + _building_names():
			label.text = text
			_bar._fit_label()
			await await_idle_frame()
			await await_idle_frame()
			_assert_label_fits(label, "%s: %s" % [size, text])


func _assert_label_fits(label: Label, why: String) -> void:
	var font: Font = label.get_theme_font(&"font")
	var px: int = label.get_theme_font_size(&"font_size")
	var text_px: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var wanted: float = minf(text_px, UiScale.dp(CommandBar.LABEL_MAX_DP))
	assert_float(label.custom_minimum_size.x).override_failure_message(why).is_greater_equal(
		wanted - 0.5
	)
	assert_float(label.size.x).override_failure_message(why + ": laid out").is_greater_equal(
		wanted - 1.5
	)
	(
		assert_bool(_bar.get_global_rect().grow(1.0).encloses(_rect("Chip")))
		. override_failure_message(
			"%s: chip %s in the bar %s" % [why, _rect("Chip"), _bar.get_global_rect()]
		)
		. is_true()
	)


## The display names of every structure of both factions in data/units.
func _building_names() -> Array[String]:
	var names: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data/units"):
		if not file.ends_with(".tres"):
			continue
		var def: UnitDef = load("res://data/units/%s" % file) as UnitDef
		if def != null and def.speed == 0 and def.display_name.length() > 8:
			names.append(def.display_name)
	return names


## A selected enemy building the fog hides shows no health, one the player sees does.
func test_a_fogged_enemy_building_shows_no_health() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], null)
	await _select([ENEMY_HQ])
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	var fog: FogGrid = snap.fog
	var health: Control = _bar.find_child("Health", true, false) as Control
	for seen: bool in [true, false]:
		for cell: int in fog.cells:
			fog.visible[cell] = 1 if seen else 0  # Player 1's slice is the first.
		_bar._fill(_controller.selection.selected)
		assert_bool(health.visible).override_failure_message("seen %s" % seen).is_equal(seen)


## The content stays inside the bar: a building and then a unit, and one type on web_phone (dp
## 2.028 asked half a dp more than the bar had), keep Deselect, the chip and Stop in its rect and
## the row at the bar's height.
func test_the_content_stays_inside_the_bar() -> void:
	var cases: Array[Array] = [
		[&"android_6in", [BORE], [TANK]],
		[&"web_phone", [TANK], [TANK, RIFLE]],
		[&"web_phone_small", [BORE], [TANK, RIFLE]],
		[&"web_phone_portrait", [BORE], [TANK]]
	]
	for entry: Array in cases:
		await _open(Vector2i.ZERO, UiProfiles.by_name(entry[0]))
		for ids: Array in [entry[1], entry[2]]:
			await _select(ids)
			var bar: Rect2 = _bar.get_global_rect()
			var why: String = "%s %s" % [entry[0], ids]
			for part: String in ["Deselect", "Chip"]:
				(
					assert_bool(bar.grow(0.5).encloses(_rect(part)))
					. override_failure_message("%s: %s %s in %s" % [why, part, _rect(part), bar])
					. is_true()
				)
			if _stop().is_visible_in_tree():
				(
					assert_bool(bar.grow(0.5).encloses(_rect("Stop")))
					. override_failure_message("%s: Stop %s in %s" % [why, _rect("Stop"), bar])
					. is_true()
				)
			var row: Control = _bar.get_node("Row")
			assert_float(row.size.y).override_failure_message(why).is_less_equal(bar.size.y + 0.5)


## With a mode running: select, empty and select again (by Deselect and by ids); the bar's slot and
## the frozen parts' rects stay; after the mode the slot follows the selection.
func _check_frozen(why: String, shown_at_start: bool) -> void:
	var before: Dictionary[String, Rect2] = _frozen_rects()
	var plate: Rect2 = _bar.get_global_rect()
	assert_bool(_bar.visible).override_failure_message(why).is_equal(shown_at_start)
	await _select([RIFLE] if not shown_at_start else [])
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_bar.visible).override_failure_message(why + ": after a change").is_equal(
		shown_at_start
	)
	await _select([TANK])
	if _bar.visible:
		_tap(_hud("Deselect") as Control)
	else:
		_controller.deselect()
	await await_idle_frame()
	await await_idle_frame()
	assert_array(_controller.selection.selected).override_failure_message(why).is_empty()
	assert_bool(_bar.visible).override_failure_message(why + ": after Deselect").is_equal(
		shown_at_start
	)
	var after: Dictionary[String, Rect2] = _frozen_rects()
	for key: String in before:
		assert_that(after[key]).override_failure_message("%s: %s moved" % [why, key]).is_equal(
			before[key]
		)
	if shown_at_start:  # An empty plate: no chip, no order, the same place.
		assert_float(_bar.get_global_rect().position.y).is_equal_approx(plate.position.y, 1.5)
		assert_bool(_stop().is_visible_in_tree()).override_failure_message(why).is_false()
	assert_bool(_bar.has_slot()).override_failure_message(why).is_equal(shown_at_start)
	assert_array(_sent).override_failure_message(why).is_empty()  # Deselect is no Command.


## The mode ended with nothing selected: the bar follows the selection again (hidden, no slot) and,
## upright, BUILD is back at its unlifted place on the safe bottom.
func _assert_released(why: String, portrait: bool) -> void:
	assert_bool(_bar.has_slot()).override_failure_message(why + ": slot after the mode").is_false()
	assert_bool(_bar.visible).override_failure_message(why + ": bar after the mode").is_false()
	if portrait:
		var low: float = _rect("BuildButton").end.y
		var margin: float = (_hud("SafeArea") as SafeAreaMargin).margin_dp
		var inner: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin)
		(
			assert_float(low)
			. override_failure_message(
				"%s: BUILD after the mode, %s of %s" % [why, low, inner.end.y]
			)
			. is_equal_approx(inner.end.y, 1.5)
		)


func _frozen_rects() -> Dictionary[String, Rect2]:
	var out: Dictionary[String, Rect2] = {}
	for node_name: String in FROZEN:
		var node: Control = _hud(node_name) as Control
		if node.is_visible_in_tree():
			out[node_name] = node.get_global_rect()
	for node_name: String in ["StrikeConfirm", "StrikeCancel"]:
		var node: Control = _hud(node_name) as Control
		if node != null and node.is_visible_in_tree():
			out[node_name] = node.get_global_rect()
	return out


func _make_ready() -> void:
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	PlacementRig.make_ready(snap)
	snap.tick += 1
	(_hud("BuildButton") as BuildButton).refresh(snap)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()  # The bar publishes its slot on a deferred call, then places.
	await await_idle_frame()


func _stop() -> Button:
	return _bar.order_button(&"stop")


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


## A tap on the middle of a control, with the touch events a finger sends.
func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A new scene at `size` (or under `metrics`, when given), its match paused, the Commands caught.
func _open(size: Vector2i, metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
		size = metrics.window_size
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var scenario: ScenarioDef = Rig.scenario(spawns)
	for unit: String in ["power_plant", "barracks"]:
		scenario.roster.append(load("res://data/units/%s.tres" % unit) as UnitDef)
	(_main.get_node("MatchRunner") as MatchRunner).scenario = scenario
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_aim = _main.get_node("StrikeAim")
	_placement = _main.get_node("PlacementController")
	_controller = _main.get_node("PlayerController")
	_bar = _hud("CommandBar") as CommandBar
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	await await_idle_frame()
