extends GdUnitTestSuite
## The strike button and its aiming controls in the battle-screen HUD (plan P112, ADR 0023 section
## 10), at the six sizes of ScreenSizes.ALL with the engine's own metrics and at every profile of
## both orientations, also with a cutout. The row of controls (check mark, X and the strike button)
## is shown only while the local player owns a strike building; every part is inside the safe rect,
## at least 48 dp on both axes and clear of every other HUD control, and the HUD does not grow.
## Landscape: the top line, left of the minimap's slot; portrait: the right edge, a gap above the
## ArmyBar. The ring and the foot follow the charge (time left, then "Ready"), a tap on a charging
## button does nothing but nudge it, a tap on a ready one aims (its foot asks "Tap map" until a
## point is placed), the check mark waits for a point and sends exactly one SUPERWEAPON, the X, the
## button's second tap and a turn of the phone leave the aim with no Command.
## Player 1 (local) has a Deep Bore, id 1, and a light tank, id 2, which is selected; player 2 has a
## Headquarters. The bore's wait is set in the snapshot (the charge is test_strike_aim's).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BORE: int = 1
const TANK: int = 2
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
]
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
## The parts of the row, and the other HUD controls they must clear.
const TAPPABLE: Array[String] = ["StrikeConfirm", "StrikeCancel", "StrikeButton"]
const OTHERS: Array[String] = [
	"DevButton", "AllArmy", "Group1", "Group2", "Group3", "SelectionPanel", "BuildSidebar"
]

var _window_size_before: Vector2i
var _main: Node2D
var _aim: StrikeAim
var _controller: PlayerController
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func test_every_part_is_inside_the_safe_rect_48_dp_clear_of_the_hud_and_the_hud_does_not_grow(
) -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"], true)
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		for point: bool in [false, true]:  # Aiming with no point, then with one.
			_ready_to_fire()
			assert_bool(_aim.begin()).override_failure_message(why).is_true()
			if point:
				_aim.place(Vector2i(16500, 16500))
			await await_idle_frame()  # The row is laid out in the frame.
			var others: Array[Rect2] = []
			for other: String in OTHERS:
				var control: Control = _hud(other)
				if control.is_visible_in_tree():
					others.append(control.get_global_rect())
			if not HudLayout.is_portrait():
				others.append(_rect("StatusPill"))
				others.append(_rect("MinimapSlot"))
			for part: String in TAPPABLE:
				var control: Control = _hud(part)
				var at: String = "%s: %s %s, safe %s" % [why, part, control.get_global_rect(), safe]
				assert_bool(control.is_visible_in_tree()).override_failure_message(at).is_true()
				var rect: Rect2 = control.get_global_rect()
				assert_bool(safe.encloses(rect)).override_failure_message(at).is_true()
				var least: float = UiScale.dp(48.0) - TOLERANCE_PX
				assert_float(rect.size.x).override_failure_message(at).is_greater_equal(least)
				assert_float(rect.size.y).override_failure_message(at).is_greater_equal(least)
				for other: Rect2 in others:
					var clash: String = "%s: %s clashes with %s" % [why, rect, other]
					assert_bool(rect.intersects(other)).override_failure_message(clash).is_false()
			var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()
			assert_that(area).override_failure_message(why).is_equal(
				get_viewport().get_visible_rect()
			)
			_aim.cancel()


func test_landscape_has_the_row_on_the_top_line_left_of_the_slot_and_portrait_at_the_right_edge(
) -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"], true)
		_ready_to_fire()
		_aim.begin()
		await await_idle_frame()
		var why: String = str(screen["label"])
		var inner: Rect2 = _inner()
		var row: Rect2 = _rect("StrikeControls")
		var strike: Rect2 = _rect("StrikeButton")
		var gap: float = UiScale.dp(8.0)
		assert_float(strike.end.x).override_failure_message(why).is_equal_approx(row.end.x, 1.0)
		if HudLayout.is_portrait():
			var bar: Rect2 = _rect("ArmyBar")
			assert_float(strike.end.x).override_failure_message(why).is_equal_approx(
				inner.end.x, 1.0
			)
			var at: String = "%s: strike %s, bar %s, gap %s" % [why, strike, bar, gap]
			assert_float(strike.end.y).override_failure_message(at).is_between(
				bar.position.y - gap - 2.5, bar.position.y - gap + TOLERANCE_PX
			)
		else:
			var slot: Rect2 = _rect("MinimapSlot")
			assert_float(strike.position.y).override_failure_message(why).is_equal_approx(
				inner.position.y, 1.0
			)
			assert_float(strike.end.x).override_failure_message(why).is_less_equal(
				slot.position.x - gap + 1.5
			)


func test_the_row_is_shown_only_while_a_strike_building_is_owned() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone, false)
	assert_bool((_hud("StrikeControls") as Control).visible).is_false()
	assert_bool(_aim.owned).is_false()
	await _open(phone.window_size, phone, true)
	assert_bool((_hud("StrikeControls") as Control).visible).is_true()
	assert_bool(_aim.owned).is_true()
	assert_bool((_hud("StrikeButton") as Control).visible).is_true()
	# Only the button, until the player aims.
	for part: String in ["StrikeConfirm", "StrikeCancel"]:
		assert_bool((_hud(part) as Control).visible).override_failure_message(part).is_false()


## The foot shows the time left until the strike can fire (m:ss, whole seconds up), the ring the
## charge so far; ready, the foot says "Ready", the ring is full and the time is gone.
func test_the_ring_and_the_foot_follow_the_charge_and_then_say_ready() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone, true)
	var button: StrikeButton = _hud("StrikeButton")
	var charge: int = _main.get_node("MatchRunner").snapshot.type_charge_ticks[_aim.type_index]
	for wait: int in [charge * 3 / 5, 15, 16, 1]:
		_wait(wait)
		var seconds: int = ceili(wait / 15.0)
		var note: String = "wait %d" % wait
		assert_str((_hud("StrikeTime") as Label).text).override_failure_message(note).is_equal(
			"%d:%02d" % [seconds / 60, seconds % 60]
		)
		assert_bool((_hud("StrikeTime") as Label).visible).override_failure_message(note).is_true()
		(
			assert_bool((_hud("StrikeReady") as Label).visible)
			. override_failure_message(note)
			. is_false()
		)
		assert_float(button.charge).override_failure_message(note).is_equal_approx(
			1.0 - float(wait) / charge, 0.001
		)
		assert_bool(button.fires).override_failure_message(note).is_false()
	_wait(0)
	assert_bool((_hud("StrikeTime") as Label).visible).is_false()
	assert_bool((_hud("StrikeReady") as Label).visible).is_true()
	assert_str((_hud("StrikeReady") as Label).text).is_equal("Ready")
	assert_float(button.charge).is_equal_approx(1.0, 0.001)
	assert_bool(button.fires).is_true()


func test_a_tap_on_a_charging_button_only_nudges_and_a_tap_on_a_ready_one_aims() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone, true)
	var button: StrikeButton = _hud("StrikeButton")
	_wait(900)
	_tap(button)
	assert_array([button.nudges, _aim.active, button.button_pressed]).is_equal([1, false, false])
	_wait(0)
	_tap(button)
	await await_idle_frame()
	assert_array([button.nudges, _aim.active, button.button_pressed]).is_equal([1, true, true])
	assert_str((_hud("StrikeReady") as Label).text).is_equal("Tap map")  # Until a point is placed.
	assert_bool((_hud("StrikeConfirm") as Button).disabled).is_true()  # No point yet.
	assert_array(_sent).is_empty()
	_tap(button)  # The pressed button is a cancel.
	assert_array([_aim.active, button.button_pressed]).is_equal([false, false])
	assert_array(_sent).is_empty()


func test_the_check_mark_waits_for_a_point_and_sends_exactly_one_superweapon() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone, true)
	_wait(0)
	_tap(_hud("StrikeButton"))
	await await_idle_frame()
	_tap(_hud("StrikeConfirm"))  # Dimmed, no point: a tap is nothing.
	assert_array(_sent).is_empty()
	assert_bool(_aim.active).is_true()
	_aim.place(Vector2i(9500, 21500))
	await await_idle_frame()
	assert_bool((_hud("StrikeConfirm") as Button).disabled).is_false()
	assert_str((_hud("StrikeReady") as Label).text).is_equal("Ready")
	_tap(_hud("StrikeConfirm"))
	assert_array(_sent).has_size(1)
	var command: Command = _sent[0]
	assert_array([command.type, command.player_id, command.target_id]).is_equal(
		[Command.Type.SUPERWEAPON, 1, BORE]
	)
	assert_array([command.target_x, command.target_y]).is_equal([9500, 21500])
	assert_bool(_aim.active).is_false()
	assert_bool((_hud("StrikeConfirm") as Control).visible).is_false()


func test_the_x_leaves_the_aim_with_no_command() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone, true)
	_wait(0)
	_tap(_hud("StrikeButton"))
	_aim.place(Vector2i(9500, 21500))
	await await_idle_frame()
	_tap(_hud("StrikeCancel"))
	assert_array([_aim.active, _aim.has_point]).is_equal([false, false])
	assert_bool((_hud("StrikeCancel") as Control).visible).is_false()
	assert_bool((_hud("StrikeButton") as StrikeButton).button_pressed).is_false()
	assert_array(_sent).is_empty()


## A turn of the phone ends the aim (ADR 0015 section 3), also with a point placed, and sends
## nothing; the strike button is there in the other layout, ready, and aims again.
func test_a_turn_of_the_phone_leaves_the_aim_with_no_command() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape, true)
	for turn: UiMetrics in [portrait, landscape, portrait]:
		_wait(0)
		_aim.begin()
		_aim.place(Vector2i(9500, 21500))
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await await_idle_frame()
		await await_idle_frame()
		assert_array([_aim.active, _aim.has_point]).is_equal([false, false])
		assert_bool((_hud("StrikeConfirm") as Control).visible).is_false()
		assert_bool((_hud("StrikeButton") as Control).is_visible_in_tree()).is_true()
	assert_array(_sent).is_empty()
	# A resize that keeps the orientation is no turn.
	_wait(0)
	_aim.begin()
	get_window().size = Vector2i(portrait.window_size.x, portrait.window_size.y - 100)
	await await_idle_frame()
	assert_bool(_aim.active).is_true()


## Player 1's bore waits `wait` ticks from the published snapshot's stamp, and the aim reads it.
func _wait(wait: int) -> void:
	var snap: MatchSnapshot = _main.get_node("MatchRunner").snapshot
	snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1 + wait
	_aim.refresh()


func _ready_to_fire() -> void:
	_aim.cancel()
	_wait(0)


## A tap on the middle of a control, with the touch events a finger sends.
func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


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


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, the Commands caught, the tank selected; with `strike`, player 1 owns the Deep Bore.
func _open(size: Vector2i, metrics: UiMetrics, strike: bool) -> void:
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
	if strike:
		var spawns: Array[SpawnDef] = []
		for entry: Array in SPAWNS:
			spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
		(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario(spawns)
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_aim = _main.get_node("StrikeAim")
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	if strike:
		_controller.selection.set_ids(PackedInt32Array([TANK]))
	await await_idle_frame()
