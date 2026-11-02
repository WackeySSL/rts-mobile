extends GdUnitTestSuite
## The economy pill's tap areas, its digit slots and its place (plan P119, ADR 0025 sections 2 and
## 3): 48 dp high with credits and power each a tap area of at least 48 dp, digits in fixed slots,
## written only when they change, and the rect `HudCorners.place` gives it at the six sizes of
## ScreenSizes.ALL, at every profile of both orientations and after a turn. The numbers and the
## low-power look are test_economy_pill.gd's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _pill: EconomyPill
var _controller: PlayerController
var _sent: Array[Command] = []
var _tick: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


## The digits keep fixed slots (Chakra Petch has no `tnum`): a digit of any value is as wide as the
## widest, so the same count of digits stands at the same places whatever they are.
func test_digits_keep_fixed_slots_so_the_figures_do_not_jitter() -> void:
	await _open()
	for profile: StringName in [&"android_6in", &"web_phone_portrait", &"web_tablet"]:
		await _turn(profile)
		_publish(1111, 40, 11)
		await await_idle_frame()
		var narrow: Array[Rect2] = _digit_rects(_credits())
		var narrow_power: Array[Rect2] = _digit_rects(_numbers())
		_publish(8888, 88, 88)
		await await_idle_frame()
		var wide: Array[Rect2] = _digit_rects(_credits())
		var wide_power: Array[Rect2] = _digit_rects(_numbers())
		assert_array(narrow).has_size(4)
		assert_array(narrow_power).has_size(5)
		assert_array(wide_power).has_size(5)
		for index: int in narrow.size():
			assert_that(wide[index]).override_failure_message(str(profile)).is_equal(narrow[index])
		for index: int in [0, 1, 3, 4]:  # The digits of "11/40" and "88/88"; index 2 is the slash.
			assert_float(wide_power[index].size.x).is_equal(narrow_power[index].size.x)
			assert_float(wide_power[index].size.x).is_equal(narrow_power[0].size.x)
		assert_float(_credits().get_child(0).size.x).is_equal(_credits().get_child(3).size.x)


## No text is written per frame at rest: the label writes only when the shown number changes.
func test_a_number_is_written_only_when_it_changes() -> void:
	await _open()
	_publish(500, 100, 40)
	var credits: int = _credits().writes
	var numbers: int = _numbers().writes
	for _repeat: int in 5:
		_publish(500, 100, 40)  # New ticks with the same figures.
		await await_idle_frame()
	assert_int(_credits().writes).is_equal(credits)
	assert_int(_numbers().writes).is_equal(numbers)
	_publish(501, 100, 40)
	assert_int(_credits().writes).is_equal(credits + 1)
	assert_int(_numbers().writes).is_equal(numbers)  # The power did not change.
	_publish(501, 100, 41)
	assert_int(_credits().writes).is_equal(credits + 1)
	assert_int(_numbers().writes).is_equal(numbers + 1)


## ADR 0025 section 2: 48 dp high, the credits and the power each a tap area of at least 48 dp, the
## menu button (hidden until the pause menu, P124) as large.
func test_the_pill_is_48_dp_high_with_tap_areas_of_48_dp_and_no_menu_button_yet() -> void:
	await _open()
	for profile: StringName in _every_profile():
		await _turn(profile)
		var least: float = UiScale.dp(48.0) - 0.5
		var why: String = str(profile)
		assert_float(_pill.size.y).override_failure_message(why).is_greater_equal(least)
		assert_float(_pill.size.y).override_failure_message(why).is_less_equal(least + 1.5)
		for area: String in ["CreditsTap", "PowerTap"]:
			var rect: Rect2 = _rect(area)
			assert_float(rect.size.x).override_failure_message(why + area).is_greater_equal(least)
			assert_float(rect.size.y).override_failure_message(why + area).is_greater_equal(least)
			assert_bool(_pill.get_global_rect().grow(0.5).encloses(rect)).is_true()
		var menu: Button = _node("Menu")
		assert_bool(menu.visible).is_false()
		assert_float(menu.custom_minimum_size.x).override_failure_message(why).is_greater_equal(
			least
		)
		assert_float(menu.custom_minimum_size.y).override_failure_message(why).is_greater_equal(
			least
		)
	_pill.set_menu_shown(true)  # What the pause menu row does.
	for profile: StringName in _every_profile():
		await _turn(profile)
		var dp: float = UiScale.base_px_per_dp()
		var menu_rect: Rect2 = _rect("Menu")
		var pill_rect: Rect2 = _pill.get_global_rect()
		var shown: String = "%s: menu %s in pill %s" % [profile, menu_rect, pill_rect]
		assert_bool((_node("Menu") as Control).visible).override_failure_message(shown).is_true()
		assert_bool((_node("Divider") as Control).visible).is_true()
		# The button is 48 x 48 dp (its glyph is capped, not its own 128 px) and so is the pill high.
		assert_float(menu_rect.size.x / dp).override_failure_message(shown).is_between(47.5, 48.5)
		assert_float(menu_rect.size.y / dp).override_failure_message(shown).is_between(47.5, 48.5)
		assert_float(pill_rect.size.y / dp).override_failure_message(shown).is_between(47.5, 49.0)
		(
			assert_bool(pill_rect.grow(0.5).encloses(menu_rect))
			. override_failure_message(shown)
			. is_true()
		)
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		assert_bool(safe.grow(0.5).encloses(pill_rect)).override_failure_message(shown).is_true()
		assert_float(pill_rect.end.x).override_failure_message(shown).is_less_equal(
			safe.end.x - 64.0 * dp + 0.5
		)


## A tap on the credits or on the power says so; the pill takes the touch, so with units selected it
## orders nothing, and a tap on the map beside it does.
func test_a_tap_on_the_credits_or_the_power_is_the_pills_and_orders_nothing() -> void:
	await _open()
	_controller.selection.set_ids(PackedInt32Array([1, 2]))
	var taps: Array[int] = [0]
	_pill.economy_pressed.connect(func() -> void: taps[0] += 1)
	var menus: Array[int] = [0]
	_pill.menu_pressed.connect(func() -> void: menus[0] += 1)
	for area: String in ["CreditsTap", "PowerTap"]:
		var at: Vector2 = _rect(area).get_center()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
	assert_int(taps[0]).is_equal(2)
	# The pill's right padding (no tap area is there) eats the touch too: it orders nothing, where
	# the same point is ground, and orders a MOVE, once the pill is out of the way.
	var rect: Rect2 = _pill.get_global_rect()
	var padding: Vector2 = Vector2(rect.end.x - 1.0, rect.get_center().y)
	TouchEvents.press(get_viewport(), 0, padding)
	TouchEvents.release(get_viewport(), 0, padding)
	assert_array(_sent).override_failure_message("the padding let a touch through").is_empty()
	_pill.visible = false
	TouchEvents.press(get_viewport(), 0, padding)
	TouchEvents.release(get_viewport(), 0, padding)
	assert_array(_sent).override_failure_message("the control point is no ground").has_size(1)
	_sent.clear()
	_pill.visible = true
	var away: Vector2 = _rect("CreditsTap").get_center()  # Down on it, up beside it: no tap.
	TouchEvents.press(get_viewport(), 0, away)
	TouchEvents.release(get_viewport(), 0, away + Vector2(400.0, 300.0))
	assert_int(taps[0]).is_equal(2)
	assert_int(menus[0]).is_equal(0)
	assert_array(_sent).is_empty()
	assert_array(_controller.selection.selected).is_equal([1, 2])
	var ground: Vector2 = Vector2(300.0, 360.0)  # Clear of the HUD and the units.
	TouchEvents.press(get_viewport(), 0, ground)
	TouchEvents.release(get_viewport(), 0, ground)
	assert_array(_sent).has_size(1)


## The pill stands where `HudCorners.place` puts it: at the safe rect's top, a gap after the Dev
## button, at least 200 dp wide, clear of the scope's corner; at the six sizes of ScreenSizes.ALL,
## at every profile of both orientations and after a turn, and the same node in both orientations.
func test_the_pill_takes_its_rect_from_the_layout_at_every_size_and_after_a_turn() -> void:
	await _open()
	var seen: EconomyPill = _pill
	var places: Array[Callable] = []
	for size: Vector2i in ScreenSizes.ALL:
		places.append(_to_size.bind(size))
	for profile: StringName in _every_profile():
		places.append(_turn.bind(profile))
	for place: Callable in places:
		await place.call()
		var dp: float = UiScale.base_px_per_dp()
		var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 12.0)
		var dev: Rect2 = _rect("DevButton")
		var rect: Rect2 = _pill.get_global_rect()
		var why: String = "%s: pill %s, safe %s, dev %s" % [get_window().size, rect, safe, dev]
		assert_object(_node("EconomyPill")).is_same(seen)
		assert_bool(_pill.visible).override_failure_message(why).is_true()
		assert_bool(safe.grow(0.5).encloses(rect)).override_failure_message(why).is_true()
		assert_float(rect.position.y).override_failure_message(why).is_equal_approx(
			safe.position.y, 0.5
		)
		assert_float(rect.position.x).override_failure_message(why).is_equal_approx(
			dev.end.x + 8.0 * dp, 1.0
		)
		assert_float(rect.size.x).override_failure_message(why).is_greater_equal(200.0 * dp - 0.5)
		assert_float(rect.end.x).override_failure_message(why).is_less_equal(
			safe.end.x - 64.0 * dp + 0.5
		)
		assert_bool(rect.intersects(dev)).override_failure_message(why).is_false()
		var planned: Rect2 = (
			HudCorners
			. place(safe, HudLayout.is_portrait(), dp, false, _shown_like_the_pill(dp))[
				HudCorners.PILL
			]
		)
		assert_float(rect.size.x).override_failure_message(why).is_equal_approx(planned.size.x, 0.5)
		assert_float(rect.position.x).override_failure_message(why).is_equal_approx(
			planned.position.x, 0.5
		)


## The credits line (plan P85c, now the pill's): the glyph, the number, the bolt and the bar sit
## inside the pill, clear of each other, and the glyphs are at least 24 dp.
func test_the_pills_parts_are_inside_it_clear_of_each_other_and_the_glyphs_24_dp() -> void:
	await _open()
	for profile: StringName in _every_profile():
		await _turn(profile)
		var pill: Rect2 = _pill.get_global_rect()
		var line: Array[String] = ["CreditsGlyph", "Credits", "PowerGlyph", "PowerBar"]
		for index: int in line.size():
			var rect: Rect2 = _rect(line[index])
			var inside: String = "%s: %s %s in the pill %s" % [profile, line[index], rect, pill]
			assert_bool(pill.grow(0.5).encloses(rect)).override_failure_message(inside).is_true()
			for later: int in range(index + 1, line.size()):
				var pair: String = "%s: %s and %s" % [profile, line[index], line[later]]
				var overlap: bool = rect.intersects(_rect(line[later]))
				assert_bool(overlap).override_failure_message(pair).is_false()
		for glyph: String in ["CreditsGlyph", "PowerGlyph"]:
			var size: Vector2 = _rect(glyph).size
			var small: String = "%s: %s is %s" % [profile, glyph, size]
			var least: float = UiScale.dp(24.0) - 0.5
			assert_float(size.x).override_failure_message(small).is_greater_equal(least)
			assert_float(size.y).override_failure_message(small).is_greater_equal(least)


func _shown_like_the_pill(dp: float) -> HudCorners.Shown:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.left_taken = (_node("DevButton") as Control).get_combined_minimum_size().x / dp
	shown.pill_width = _pill.get_combined_minimum_size().x / dp
	return shown


func _digit_rects(row: DigitRow) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child: Node in row.get_children():
		if (child as Control).visible:
			rects.append((child as Control).get_global_rect())
	return rects


## The window at one of the six sizes with the engine's own metrics.
func _to_size(size: Vector2i) -> void:
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	await await_idle_frame()


## Publishes a crafted tick (the local player is player 1) and reads it at once.
func _publish(credits: int, made: int, used: int) -> void:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.credits = PackedInt32Array([0, credits, 0])
	snap.power_made = PackedInt32Array([0, made, 0])
	snap.power_used = PackedInt32Array([0, used, 0])
	_tick += 1
	snap.tick = _tick
	_runner.snapshot = snap
	_pill.refresh()


func _rect(node_name: String) -> Rect2:
	return (_node(node_name) as Control).get_global_rect()


## Every device profile, landscape and then portrait.
func _every_profile() -> Array[StringName]:
	var names: Array[StringName] = []
	for profile: StringName in UiProfiles.all():
		names.append(profile)
	for profile: StringName in UiProfiles.portrait():
		names.append(profile)
	return names


func _credits() -> DigitRow:
	return _node("Credits")


func _numbers() -> DigitRow:
	return _node("PowerText")


## By name from the HUD.
func _node(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## Turns the window to a profile's size, with its metrics, and lets the handlers and the
## containers settle: a turn runs its handlers twice and the containers sort a frame later.
func _turn(profile_name: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile_name)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	await await_idle_frame()


## A new main scene on the 6-inch phone, its match paused, with the Commands caught.
func _open() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_pill = _main.get_node("Hud/EconomyPill")
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
