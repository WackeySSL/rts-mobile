extends GdUnitTestSuite
## The strike button and its aiming controls in the battle-screen HUD (plan P112, ADR 0023 section
## 10; P120c moved it above BUILD), at the six sizes of ScreenSizes.ALL with the engine's own
## metrics, at every profile of both orientations, also with a cutout, and on a short landscape
## screen. The row of controls (check mark, X and the strike button) is shown only while the local
## player owns a strike building; every part is inside the safe rect, at least 48 dp on both axes
## and clear of every other HUD control (the pill, the scope, the toast and BUILD among them), and
## the HUD does not grow. The button stands 8 dp above BUILD at its 72 dp, in both orientations,
## the check mark and the X to its left where `HudCorners` puts them, and hides with BUILD under the
## drawer and the pause menu. The ring and the foot follow the charge (time left, then "Ready"), a
## tap on a charging button does nothing but nudge it, a tap on a ready one aims (its foot asks "Tap
## map" until a point is placed), the check mark waits for a point and sends exactly one
## SUPERWEAPON, the X, the button's second tap and a turn of the phone leave the aim with no
## Command.
## Player 1 (local) has a Deep Bore, id 1, and a light tank, id 2, which is selected; player 2 has a
## Headquarters. The bore's wait is set in the snapshot (the charge is test_strike_aim's).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const BORE: int = 1
const TANK: int = 2
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
	[1, "rifle_squad", 15, 15],
]
const RIFLE: int = 4  ## The second unit type of the local player (for a two-type selection).
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
## The parts of the row, and the other HUD controls they must clear.
const TAPPABLE: Array[String] = ["StrikeConfirm", "StrikeCancel", "StrikeButton"]
const OTHERS: Array[String] = [
	"EconomyPill", "GroupColumn", "CommandBar", "BuildSidebar", "BuildButton"
]

var _window_size_before: Vector2i
var _main: Node2D
var _aim: StrikeAim
var _controller: PlayerController
var _sent: Array[Command] = []
var _buzzes: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_every_part_is_inside_the_safe_rect_48_dp_clear_of_the_hud_and_the_hud_does_not_grow(
) -> void:
	for screen: Dictionary in _screens_and_short():
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
			others.append(_rect("EconomyPill"))
			others.append(_rect("RadarScope"))  # In both orientations (P121).
			var toast: AttackToast = _hud("AttackToast") as AttackToast
			toast.visible = true  # A cue is up: the toast stands where `HudCorners` puts it.
			toast.place()
			others.append(toast.get_global_rect())
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


## The check mark and the X are 64 dp (plan P112c), the size `touch-ui-rules` gives placement's
## confirm and cancel: the constant, and the plates on every screen and profile, also with a
## cutout. The whole row stays inside the safe rect, its three parts clear of one another (a gap
## between them) and clear of the HUD, and the strike button keeps at least its 72 dp.
func test_the_check_mark_and_the_x_are_64_dp_and_the_row_fits_the_safe_rect_without_overlap(
) -> void:
	assert_float(StrikeControls.ACTION_DP).is_equal(64.0)
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"], true)
		_ready_to_fire()
		_aim.begin()
		await await_idle_frame()
		var why: String = str(screen["label"])
		var safe: Rect2 = UiScale.safe_rect_base()
		var row: Rect2 = _rect("StrikeControls")
		assert_bool(safe.encloses(row)).override_failure_message("%s: %s" % [why, row]).is_true()
		var parts: Array[Rect2] = []
		for part: String in TAPPABLE:
			parts.append(_rect(part))
		for index: int in 2:  # The check mark and the X, not the strike button.
			var size: Vector2 = parts[index].size
			var at: String = "%s: %s is %s" % [why, TAPPABLE[index], size]
			assert_float(size.x).override_failure_message(at).is_equal_approx(
				UiScale.dp(64.0), TOLERANCE_PX
			)
			assert_float(size.y).override_failure_message(at).is_equal_approx(
				UiScale.dp(64.0), TOLERANCE_PX
			)
		# The strike button's foot can make it a little wider than its 72 dp, never narrower.
		var round_size: String = "%s: the strike button %s" % [why, parts[2]]
		var least: float = UiScale.dp(StrikeButton.SIZE_DP) - TOLERANCE_PX
		assert_float(parts[2].size.x).override_failure_message(round_size).is_greater_equal(least)
		assert_float(parts[2].size.y).override_failure_message(round_size).is_greater_equal(least)
		var gap: float = UiScale.dp(8.0) - TOLERANCE_PX
		for index: int in 2:  # The row runs check mark, X, strike button, each a gap from the next.
			var clash: String = "%s: %s, %s" % [why, parts[index], parts[index + 1]]
			(
				assert_float(parts[index + 1].position.x - parts[index].end.x)
				. override_failure_message(clash)
				. is_greater_equal(gap)
			)
		for other: String in OTHERS:
			var control: Control = _hud(other)
			if control.is_visible_in_tree():
				var clash: String = (
					"%s: the row %s, %s %s" % [why, row, other, control.get_global_rect()]
				)
				(
					assert_bool(row.intersects(control.get_global_rect()))
					. override_failure_message(clash)
					. is_false()
				)
		_aim.cancel()


## ADR 0025 section 10: the button is 8 dp above BUILD at its 72 dp, flush with BUILD's right edge,
## in both orientations; aiming, the check mark and the X stand to its left, a gap from it and from
## each other, centred on it, clear of BUILD, and the rects are the ones `HudCorners.place` gives.
func test_the_button_stands_8_dp_above_build_with_the_row_to_its_left_in_both_orientations(
) -> void:
	for screen: Dictionary in _screens_and_short():
		await _open(screen["size"], screen["metrics"], true)
		_ready_to_fire()
		await await_idle_frame()
		var why: String = str(screen["label"])
		var dp: float = UiScale.dp(1.0)
		var build: Rect2 = _rect("BuildButton")
		var strike: Rect2 = _rect("StrikeButton")
		var at: String = "%s: strike %s, BUILD %s" % [why, strike, build]
		assert_float(strike.end.x).override_failure_message(at).is_equal_approx(build.end.x, 1.0)
		assert_float(strike.end.y).override_failure_message(at).is_equal_approx(
			build.position.y - 8.0 * dp, 1.5
		)
		assert_float(strike.size.x).override_failure_message(at).is_equal_approx(72.0 * dp, 1.5)
		assert_float(strike.size.y).override_failure_message(at).is_equal_approx(72.0 * dp, 1.5)
		_aim.begin()
		await await_idle_frame()
		var shown: HudCorners.Shown = HudCorners.Shown.new()
		shown.strike = true
		shown.aim = true
		_state().fill_bar(shown)  # A selected tank: the bar lifts BUILD upright.
		var wanted: Dictionary[StringName, Rect2] = HudCorners.place(
			SafeAreaMargin.rect_inside(
				get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
			),
			HudLayout.is_portrait(),
			dp,
			false,
			shown
		)
		var confirm: Rect2 = _rect("StrikeConfirm")
		var cancel: Rect2 = _rect("StrikeCancel")
		strike = _rect("StrikeButton")
		var row: Rect2 = confirm.merge(cancel)
		var pair: String = "%s: strike %s, row %s, wanted %s" % [why, strike, row, wanted]
		(
			assert_bool(_near(strike, wanted[HudCorners.STRIKE]))
			. override_failure_message(pair)
			. is_true()
		)
		(
			assert_bool(_near(row, wanted[HudCorners.STRIKE_ROW]))
			. override_failure_message(pair)
			. is_true()
		)
		assert_float(confirm.end.x + 8.0 * dp).override_failure_message(pair).is_equal_approx(
			cancel.position.x, 1.0
		)
		assert_float(cancel.end.x + 8.0 * dp).override_failure_message(pair).is_equal_approx(
			strike.position.x, 1.0
		)
		for part: Rect2 in [confirm, cancel]:
			assert_float(part.get_center().y).override_failure_message(pair).is_equal_approx(
				strike.get_center().y, 1.0
			)
			assert_bool(part.intersects(build)).override_failure_message(pair).is_false()
		assert_bool(confirm.intersects(cancel)).override_failure_message(pair).is_false()
		_aim.cancel()


## The column stands under the drawer's panel (sideways) or its sheet (upright) and under the pause
## menu, as BUILD does: the whole row hides with it and comes back when it closes, aim or not.
func test_the_row_hides_with_build_under_the_drawer_and_the_pause_menu() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null, true)
		var why: String = str(size)
		var feed: HudStateFeed = _main.get_node("Hud/HudStateFeed")
		var row: Control = _hud("StrikeControls") as Control
		var build: Control = _hud("BuildButton") as Control
		assert_bool(row.is_visible_in_tree()).override_failure_message(why).is_true()
		for unfold: HudState.Unfold in [HudState.Unfold.DRAWER, HudState.Unfold.PAUSE]:
			feed.state.open(unfold)
			assert_bool(row.visible).override_failure_message(why).is_equal(build.visible)
			assert_bool(row.visible).override_failure_message(why).is_false()
			feed.state.close(unfold)
			assert_bool(row.visible).override_failure_message(why).is_true()
		_wait(0)
		_aim.begin()
		await await_idle_frame()
		feed.state.open(HudState.Unfold.PAUSE)
		assert_bool(row.visible).override_failure_message(why).is_false()
		feed.state.close(HudState.Unfold.PAUSE)
		assert_bool((_hud("StrikeConfirm") as Control).is_visible_in_tree()).is_true()
		_aim.cancel()


## With one or two unit types selected the command bar stays clear of the Ready chip and the aim's
## row at every screen, the short and the narrow short ones included (`HudCorners` leaves the bar
## the room beside BUILD and the chip; upright BUILD, the chip and the row stand above the bar).
func test_the_command_bar_stays_clear_of_the_ready_chip_and_the_aim_row() -> void:
	var screens: Array[Dictionary] = _screens_and_short()
	var narrow: UiMetrics = RadarRig.narrow_short_landscape()
	screens.append({"label": "narrow short", "size": narrow.window_size, "metrics": narrow})
	for screen: Dictionary in screens:
		await _open(screen["size"], screen["metrics"], true)
		var why: String = str(screen["label"])
		_make_ready()
		var chip: Control = _hud("ReadyChip") as Control
		assert_bool(chip.visible).override_failure_message(why).is_true()
		var panel: Control = _hud("CommandBar") as Control
		for ids: Array in [[TANK], [TANK, RIFLE]]:
			for aiming: bool in [false, true]:
				_aim.cancel()
				_controller.selection.set_ids(PackedInt32Array(ids))
				_wait(0)
				if aiming:
					assert_bool(_aim.begin()).is_true()
				for frame: int in 3:
					await await_idle_frame()
				var at: String = (
					"%s: %d types, aiming %s: panel %s"
					% [why, ids.size(), aiming, panel.get_global_rect()]
				)
				assert_bool(panel.is_visible_in_tree()).override_failure_message(at).is_true()
				var rect: Rect2 = panel.get_global_rect()
				var parts: Array[Control] = [chip, _hud("StrikeControls") as Control]
				for part: Control in parts:
					var gap: String = "%s, %s %s" % [at, part.name, part.get_global_rect()]
					(
						assert_bool(rect.intersects(part.get_global_rect()))
						. override_failure_message(gap)
						. is_false()
					)
		_aim.cancel()


## The aim's reserved room goes with the row: lost the strike building during
## the aim, or covered by the drawer and lost then, the zone is BUILD's 72 dp again (no stale 224).
func test_the_aim_gives_its_room_back_when_the_building_is_lost_during_the_aim() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	for covered: bool in [false, true]:
		await _open(phone.window_size, phone, true)
		var feed: HudStateFeed = _main.get_node("Hud/HudStateFeed")
		var told: Array[int] = [0]
		(_hud("StrikeControls") as StrikeControls).reserved_changed.connect(
			func() -> void: told[0] += 1
		)
		_wait(0)
		assert_bool(_aim.begin()).is_true()
		await await_idle_frame()
		assert_float(HudLayout.aim_zone_dp).is_greater(HudLayout.BUILD_ROW_DP)
		if covered:
			feed.state.open(HudState.Unfold.DRAWER)
		_aim.owned = false  # The Deep Bore is gone.
		_aim.changed.emit()
		if covered:
			feed.state.close(HudState.Unfold.DRAWER)
		await await_idle_frame()
		var why: String = "covered %s" % covered
		assert_float(HudLayout.aim_zone_dp).override_failure_message(why).is_equal(0.0)
		assert_float(HudLayout.right_zone_px(0.0)).override_failure_message(why).is_equal_approx(
			UiScale.dp(HudLayout.BUILD_ROW_DP), 0.01
		)
		assert_int(told[0]).override_failure_message(why).is_greater(0)
		assert_bool((_hud("StrikeControls") as Control).visible).is_false()


## The rooms the chip and the row reserve are given back when their nodes leave the tree.
func test_the_reserved_rooms_are_reset_when_the_hud_leaves_the_tree() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone, true)
	_make_ready()
	_wait(0)
	assert_bool(_aim.begin()).is_true()
	await await_idle_frame()
	assert_float(HudLayout.chip_zone_dp).is_greater(0.0)
	assert_float(HudLayout.aim_zone_dp).is_greater(0.0)
	remove_child(_main)
	_main.free()
	assert_float(HudLayout.chip_zone_dp).is_equal(0.0)
	assert_float(HudLayout.aim_zone_dp).is_equal(0.0)


## Lead decision (P122b): upright, during the aim, the group column holds three items in one column
## (the rest scroll), so it keeps 8 dp or more from the check mark and the X, at every screen with
## all three groups saved. Against the strike button's and the row's real rects (P120c: 8 dp above
## BUILD, `HudCorners.STRIKE_ROW`). Outside the aim the strike button alone stands
## there.
func test_the_group_column_keeps_clear_of_the_strike_row_during_the_aim() -> void:
	var gap: float = 0.0
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"], true)
		var why: String = str(screen["label"])
		_make_ready()  # The Ready chip stands beside BUILD: the column leaves it its width too.
		var tank: Array = [2]
		for slot: int in range(1, 4):
			_controller.selection.set_ids(PackedInt32Array(tank))
			_controller.assign_group(slot)
		for aiming: bool in [false, true]:
			_ready_to_fire()
			if aiming:
				assert_bool(_aim.begin()).override_failure_message(why).is_true()
			await await_idle_frame()
			await await_idle_frame()
			var column: Rect2 = _rect("GroupColumn")
			var near: float = UiScale.dp(8.0) - TOLERANCE_PX
			var parts: Array[Rect2] = []
			for part: String in TAPPABLE:
				parts.append(_rect(part))
			parts.append(_rect("ReadyChip"))
			var shown: HudCorners.Shown = HudCorners.Shown.new()
			shown.groups = 4
			shown.ready = true
			shown.strike = true
			shown.aim = aiming
			_state().fill_bar(shown)
			var dp: float = UiScale.base_px_per_dp()
			var margin: float = (_hud("SafeArea") as SafeAreaMargin).margin_dp
			var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin)
			var placed: Dictionary[StringName, Rect2] = HudCorners.place(
				safe, HudLayout.is_portrait(), dp, false, shown
			)
			if aiming:
				parts.append(placed[HudCorners.STRIKE_ROW])
			for rect: Rect2 in parts:
				var at: String = "%s, aim %s: column %s, part %s" % [why, aiming, column, rect]
				assert_bool(column.intersects(rect)).override_failure_message(at).is_false()
				if aiming:
					gap = maxf(column.position.x - rect.end.x, rect.position.x - column.end.x)
					gap = maxf(
						gap, maxf(column.position.y - rect.end.y, rect.position.y - column.end.y)
					)
					assert_float(gap).override_failure_message(at).is_greater_equal(near)
			if aiming and HudLayout.is_portrait():
				var three: float = dp * (3.0 * 56.0 + 2.0 * 8.0)
				var tall: String = "%s: column %s holds more than three" % [why, column]
				assert_float(column.size.y).override_failure_message(tall).is_less_equal(
					three + 1.5
				)
				assert_float(column.size.x).override_failure_message(tall).is_less_equal(
					dp * 56.0 + 1.5
				)
				# The fourth item is reached by scrolling.
				var scroll: ScrollContainer = _hud("ColumnScroll")
				assert_int(scroll.vertical_scroll_mode).is_not_equal(
					ScrollContainer.SCROLL_MODE_DISABLED
				)
				assert_int(scroll.scroll_vertical).is_equal(0)
				_buzzes.clear()
				_controller.selection.set_ids(PackedInt32Array([BORE]))  # A spurious tap would recall.
				var camera_before: Vector2 = (_main.get_node("Camera") as Camera2D).position
				# Out and back to the start of the press: a drag, so neither a tap nor a hold.
				await _drag_item("Group1", Vector2(0.0, -dp * 30.0), true)
				assert_int(scroll.scroll_vertical).override_failure_message(tall).is_between(0, 3)
				await _drag_item("Group1", Vector2(0.0, -dp * 40.0))  # A finger moves the items.
				var moved: float = scroll.scroll_vertical  # By as much as the finger went.
				assert_float(moved).override_failure_message(tall).is_equal_approx(dp * 40.0, 3.0)
				await _drag_item("Group1", Vector2(0.0, -dp * 160.0))
				var last: Rect2 = _rect("Group3")
				var reached: bool = (
					last.end.y <= column.end.y + 1.5 and last.position.y >= column.position.y - 1.5
				)
				assert_bool(scroll.scroll_vertical > 0).override_failure_message(tall).is_true()
				assert_bool(reached).override_failure_message(tall).is_true()
				_assert_drag_did_nothing(camera_before, why)
			_aim.cancel()


## A finger drag on an item of the limited column scrolls it and spends the press: no recall, no
## assign, no Command, no buzz, and the camera stays (web_phone_portrait and the other upright
## screens are walked by the test above).
func _assert_drag_did_nothing(camera_before: Vector2, why: String) -> void:
	assert_array(_controller.selection.selected).override_failure_message(why).is_equal([BORE])
	for slot: int in range(1, 4):
		assert_array(_controller.selection.group(slot)).override_failure_message(why).is_equal(
			[TANK]
		)
	assert_array(_sent).override_failure_message(why).is_empty()
	assert_array(_buzzes).override_failure_message(why).is_empty()
	(
		assert_vector((_main.get_node("Camera") as Camera2D).position)
		. override_failure_message(why)
		. is_equal(camera_before)
	)


## A finger down on the middle of the item `name`, moved by `by` in small steps, and lifted.
func _drag_item(item: String, by: Vector2, and_back: bool = false) -> void:
	var at: Vector2 = (_hud(item) as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	var steps: int = 6
	for step: int in steps:
		at += by / steps
		TouchEvents.drag(get_viewport(), 0, at, by / steps)
	if and_back:
		for step: int in steps:
			at -= by / steps
			TouchEvents.drag(get_viewport(), 0, at, -by / steps)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()


## The charge counts down tick by tick (the aim's `changed` fires on each): the column is not laid
## out again for it, only once when the aim begins.
func test_the_charge_countdown_does_not_lay_the_column_out_again() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(phone.window_size, phone, true)
	for slot: int in range(1, 4):
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_controller.assign_group(slot)
	_wait(40)
	await await_idle_frame()
	var column: GroupColumn = _hud("GroupColumn")
	var laid: Array[int] = [0]
	column.laid_out.connect(func() -> void: laid[0] += 1)
	column.place()  # Placing again where nothing moved tells nobody.
	column.place()
	assert_int(laid[0]).is_equal(0)
	for wait: int in range(39, 0, -1):  # 39 ticks of the countdown.
		_wait(wait)
	assert_int(laid[0]).is_equal(0)
	_wait(0)
	assert_int(laid[0]).is_equal(0)
	assert_bool(_aim.begin()).is_true()  # The strike owned and the aim on: four items, three shown.
	assert_int(laid[0]).is_equal(1)
	_aim.cancel()
	assert_int(laid[0]).is_equal(2)  # And back.


## "+" and a hold need units: with the Deep Bore (a building) selected "+" hides, `save_group` and a
## hold change nothing and make no sound.
func test_a_building_selected_hides_plus_and_a_hold_changes_nothing() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(phone.window_size, phone, true)
	_controller.selection.set_ids(PackedInt32Array([TANK]))
	_controller.assign_group(1)  # Group 1 holds the tank; groups 2 and 3 are free.
	assert_bool((_hud("AddGroup") as Control).visible).is_true()
	_buzzes.clear()
	_controller.selection.set_ids(PackedInt32Array([BORE]))
	assert_bool((_hud("AddGroup") as Control).visible).is_false()
	_controller.save_group()
	_controller.assign_group(1)
	assert_array(_controller.selection.group(1)).is_equal([TANK])
	assert_array(_controller.selection.group(2)).is_empty()
	assert_array(_buzzes).is_empty()
	assert_array(_sent).is_empty()


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


## The player's Structures queue holds a finished power plant, and BUILD has read it: the Ready
## chip shows.
func _make_ready() -> void:
	var runner: MatchRunner = _main.get_node("MatchRunner")
	var snap: MatchSnapshot = runner.snapshot
	var plant: int = snap.type_ids.find("power_plant")
	var slots: int = BuildSidebar._queue_slots(snap)
	var queue: int = runner.scenario.local_player * World.TABS + World.Tab.STRUCTURES
	snap.queue_count[queue] = 1
	snap.queue_type[queue * slots] = plant
	snap.queue_progress[queue] = snap.type_build_ticks[plant] * Production.PROGRESS_PER_TICK
	snap.tick += 1
	(_hud("BuildButton") as BuildButton).refresh(snap)


func _state() -> HudState:
	return (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state


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


## The rects agree to the few pixels that the plates' rounding up to whole pixels allows.
func _near(a: Rect2, b: Rect2) -> bool:
	var apart: Vector2 = (a.position - b.position).abs().max((a.end - b.end).abs())
	return maxf(apart.x, apart.y) <= 4.0


## `_screens(null)` and the short landscape screen of the radar suites.
func _screens_and_short() -> Array[Dictionary]:
	var all: Array[Dictionary] = _screens(null)
	var short: UiMetrics = RadarRig.short_landscape()
	all.append({"label": "short landscape", "size": short.window_size, "metrics": short})
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
	_buzzes.clear()
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	if strike:
		_controller.selection.set_ids(PackedInt32Array([TANK]))
	await await_idle_frame()
