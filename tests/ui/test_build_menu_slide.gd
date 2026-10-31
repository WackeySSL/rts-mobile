extends GdUnitTestSuite
## The build menu's slide (plan P85f, ADR 0024 sections 4 and 8), in the main scene. With no slide
## in the settings the target shows at once; with `menu_slide_ms` 160 and stepped frames the
## height eases out monotonically and ends on the target at 160 ms, a reversal continues from the
## height the menu has, at every step the zone is the drawn height of the holder and the menu's top
## its drawn top with the ArmyBar 8 dp above it, the minimap keeps its size, a press on the Build
## button mid-slide is taken, and a press under the holder's clip edge reaches no hidden control
## (the `clip_contents` picking fact, proven here on the engine in use). A slide frame asks
## `UiScale` nothing: the lifts use the dp, the orientation and the safe area cached on the last
## resize, and the whole thing is view only (the state hash of a match is the one of a run with no
## menu action). The slide is stepped by hand (`BuildSidebar.advance`) and only here is the
## override of the shared test rig (0 ms) replaced by another duration; the loaded
## `input_settings.tres` is never written. Player 1 has a Headquarters and a finished power plant.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SLIDE_MS: int = 160
const STEP_S: float = 0.016  ## Ten steps make the 160 ms.
const TOLERANCE_PX: float = 1.5
const ROSTER: Array = ["power_plant", "barracks", "light_tank"]
const HASH_TICKS: int = 60

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _touch: TouchInput
var _placement: PlacementController
var _controller: PlayerController
var _now_ms: int = 0
var _sent: Array[Command] = []
var _told: Array[Vector2] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()


func test_with_no_slide_the_target_shows_at_once_in_both_orientations() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		var dp: float = UiScale.base_px_per_dp()
		var told: Array[Vector2] = _tell()
		_sidebar.collapse()  # No frame passes between the call and the reading.
		if HudLayout.is_portrait():
			(
				assert_float(HudLayout.bottom_zone_dp * dp)
				. override_failure_message(why)
				. is_equal_approx(HudLayout.STRIP_DP * dp, 0.01)
			)
			(
				assert_float(_sidebar.custom_minimum_size.y)
				. override_failure_message(why)
				. is_equal_approx(HudLayout.STRIP_DP * dp, 0.01)
			)
			assert_array(told).override_failure_message(why).has_size(1)
			assert_float(told[0].y).is_equal_approx(HudLayout.STRIP_DP * dp, 0.01)
			assert_float(told[0].x).is_equal_approx(HudLayout.menu_top_px, 0.01)
		else:
			(
				assert_float(_sidebar.custom_minimum_size.y)
				. override_failure_message(why)
				. is_equal_approx(HudLayout.PLATE_DP * dp, 0.01)
			)
		_sidebar.open()
		assert_bool(_sidebar.is_open()).is_true()
		assert_float(_sidebar.custom_minimum_size.y).override_failure_message(why).is_greater(
			HudLayout.PLATE_DP * dp
		)


func test_the_height_eases_out_monotonically_and_ends_on_the_target_at_160_ms() -> void:
	for size: Vector2i in [ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0]]:
		await _open(size, null)
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		var why: String = str(size)
		var open_h: float = _sidebar.custom_minimum_size.y
		var told: Array[Vector2] = _tell()
		_sidebar.collapse()
		assert_float(_sidebar.custom_minimum_size.y).override_failure_message(why).is_equal(open_h)
		var heights: Array[float] = []
		var widths: Array[float] = []
		for step: int in 10:
			_sidebar.advance(STEP_S)
			heights.append(_sidebar.custom_minimum_size.y)
			widths.append(_sidebar.custom_minimum_size.x)
		if not HudLayout.is_portrait():  # The plate narrows at the end of the collapse, not before.
			var panel: float = HudLayout.panel_px(_inner_width())
			for step: int in 9:
				assert_float(widths[step]).override_failure_message(why).is_equal_approx(
					panel, 0.01
				)
			assert_float(widths[9]).override_failure_message(why).is_less(panel)
		var low: float = UiScale.dp(
			HudLayout.STRIP_DP if HudLayout.is_portrait() else HudLayout.PLATE_DP
		)
		assert_float(heights[9]).override_failure_message(why).is_equal(low)  # Exactly the target.
		for step: int in range(1, 10):
			assert_float(heights[step]).override_failure_message(why).is_less_equal(
				heights[step - 1]
			)
		assert_float(heights[9]).is_less(heights[8])  # Still moving on the last step.
		# Eased out: the first step covers more than a tenth of the way.
		assert_float(open_h - heights[0]).override_failure_message(why).is_greater(
			(open_h - low) / 10.0
		)
		if HudLayout.is_portrait():
			assert_int(told.size()).override_failure_message(why).is_equal(10)
		_sidebar.advance(STEP_S)  # Nothing more to do: it is there.
		assert_float(_sidebar.custom_minimum_size.y).is_equal(low)
		# And the way back: opening is the same ease from the strip or the plate.
		_sidebar.open()
		if not HudLayout.is_portrait():  # The panel is as wide as it will be from the first frame.
			assert_float(_sidebar.custom_minimum_size.x).is_equal_approx(
				HudLayout.panel_px(_inner_width()), 0.01
			)
		for step: int in 10:
			_sidebar.advance(STEP_S)
		assert_float(_sidebar.custom_minimum_size.y).override_failure_message(why).is_equal(open_h)


## A turn during a slide ends it at its target: the layout is the orientation's and the state's, so
## the strip or the plate of the new orientation shows at once and no frame moves it on.
func test_a_turn_during_a_slide_ends_it_at_its_target() -> void:
	for pair: Array in [
		[ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]],
		[ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1]],
	]:
		await _open(pair[0], null)
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		var why: String = str(pair)
		var open_h: float = _sidebar.custom_minimum_size.y
		_sidebar.collapse()
		for step: int in 3:
			_sidebar.advance(STEP_S)
		assert_float(_sidebar.custom_minimum_size.y).override_failure_message(why).is_less(open_h)
		get_window().size = pair[1]  # The turn.
		await _settle()
		var target: float = UiScale.dp(
			HudLayout.STRIP_DP if HudLayout.is_portrait() else HudLayout.PLATE_DP
		)
		assert_float(_sidebar.custom_minimum_size.y).override_failure_message(why).is_equal_approx(
			target, 1.5
		)
		var at: float = _sidebar.custom_minimum_size.y
		_sidebar.advance(0.5)  # No slide is left to run.
		assert_float(_sidebar.custom_minimum_size.y).override_failure_message(why).is_equal(at)
		assert_bool(_sidebar.is_open()).is_false()
		(
			assert_float(_sidebar.get_global_rect().size.y)
			. override_failure_message(why)
			. is_equal_approx(target, 1.5)
		)


## The frames of the game move the slide: `_process` is what runs `advance`, with the frame's time.
func test_the_frames_of_the_game_run_the_slide() -> void:
	await _open(ScreenSizes.PORTRAIT[0], null)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	var open_h: float = _sidebar.custom_minimum_size.y
	_sidebar.collapse()
	_sidebar._process(STEP_S)
	assert_float(_sidebar.custom_minimum_size.y).is_less(open_h)
	for step: int in 9:
		_sidebar._process(STEP_S)
	assert_float(_sidebar.custom_minimum_size.y).is_equal(UiScale.dp(HudLayout.STRIP_DP))


## A request mid-slide restarts the slide from the height the menu has, for the share of the 160 ms
## that the distance left needs.
func test_a_reversal_mid_slide_continues_from_the_current_height_for_its_share_of_the_time(
) -> void:
	await _open(ScreenSizes.PORTRAIT[0], null)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	var open_h: float = _sidebar.custom_minimum_size.y
	var strip: float = UiScale.dp(HudLayout.STRIP_DP)
	_sidebar.collapse()
	for step: int in 5:
		_sidebar.advance(STEP_S)
	var middle: float = _sidebar.custom_minimum_size.y
	assert_float(middle).is_between(strip + 1.0, open_h - 1.0)
	_sidebar.open()  # Back up: from `middle`, with no jump.
	assert_float(_sidebar.custom_minimum_size.y).is_equal(middle)
	var share: float = (open_h - middle) / (open_h - strip)
	var need: float = SLIDE_MS * share / 1000.0
	_sidebar.advance(need * 0.5)
	assert_float(_sidebar.custom_minimum_size.y).is_between(middle + 0.01, open_h - 0.01)
	_sidebar.advance(need * 0.5 + 0.0001)
	assert_float(_sidebar.custom_minimum_size.y).is_equal(open_h)
	# A request to the state it is going to changes nothing, one to the state it is in neither.
	_sidebar.collapse()
	_sidebar.advance(STEP_S)
	var moving: float = _sidebar.custom_minimum_size.y
	_sidebar.collapse()
	assert_float(_sidebar.custom_minimum_size.y).is_equal(moving)


## At every step of a stepped slide, after the layout has run: the zone is the holder's drawn
## height, the menu's top its drawn top, the ArmyBar 8 dp above it, and the minimap one size.
func test_at_every_step_the_zone_and_the_top_are_the_drawn_menu_and_the_bar_and_minimap_follow(
) -> void:
	for size: Vector2i in ScreenSizes.PORTRAIT:
		await _open(size, null)
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		var dp: float = UiScale.base_px_per_dp()
		var why: String = str(size)
		_sidebar.collapse()
		await await_idle_frame()
		var mini: Vector2 = (_hud("Minimap") as Control).get_global_rect().size  # The target's.
		for step: int in 11:
			await await_idle_frame()  # The layout of the height the step set.
			var holder: Rect2 = _sidebar.get_global_rect()
			var at: String = "%s step %d: holder %s" % [why, step, holder]
			assert_float(holder.size.y).override_failure_message(at).is_equal_approx(
				HudLayout.bottom_zone_dp * dp, TOLERANCE_PX
			)
			assert_float(HudLayout.menu_top_px).override_failure_message(at).is_equal_approx(
				holder.position.y, TOLERANCE_PX
			)
			var bar: Rect2 = (_hud("ArmyBar") as Control).get_global_rect()
			assert_float(bar.end.y + 8.0 * dp).override_failure_message(at).is_equal_approx(
				holder.position.y, TOLERANCE_PX
			)
			(
				assert_vector((_hud("Minimap") as Control).get_global_rect().size)
				. override_failure_message(at)
				. is_equal_approx(mini, Vector2.ONE * TOLERANCE_PX)
			)
			_sidebar.advance(STEP_S)


## The strike row rides on the menu too: its band's margin follows the zone through the slide.
func test_the_strike_row_rides_on_the_menu_through_the_slide() -> void:
	await _open(ScreenSizes.PORTRAIT[0], null)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	var dp: float = UiScale.base_px_per_dp()
	var strike: MarginContainer = _hud("StrikeBand") as MarginContainer
	var army: MarginContainer = _hud("ArmyBand") as MarginContainer
	_sidebar.collapse()
	var last: int = 1 << 30
	for step: int in 11:
		var zone: float = HudLayout.bottom_zone_dp * dp
		assert_int(army.get_theme_constant("margin_bottom")).is_equal(ceili(zone + 8.0 * dp))
		assert_int(strike.get_theme_constant("margin_bottom")).is_equal(
			ceili(zone + 8.0 * dp) + ceili(56.0 * dp) + ceili(8.0 * dp)
		)
		assert_int(strike.get_theme_constant("margin_bottom")).is_less_equal(last)
		last = strike.get_theme_constant("margin_bottom")
		_sidebar.advance(STEP_S)


func test_a_press_on_the_build_button_in_mid_slide_is_taken() -> void:
	for size: Vector2i in [ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0]]:
		await _open(size, null)
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		_sidebar.collapse()
		for step: int in 3:
			_sidebar.advance(STEP_S)
		await _settle()
		assert_bool(_sidebar.is_open()).is_false()
		var build: Control = _hud("Build") as Control
		var holder: Rect2 = _sidebar.get_global_rect()
		var at: Vector2 = build.get_global_rect().get_center()
		assert_bool(holder.has_point(at)).override_failure_message(str(size)).is_true()
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_bool(_sidebar.is_open()).override_failure_message(str(size)).is_true()
		assert_array(_told).is_empty()  # A HUD touch: the map was not touched.


## `clip_contents` also stops the picking: while the open layout is only partly uncovered, a press
## on the part of a card that lies under the holder's edge (the hidden part, in the safe margin
## below it) reaches no card and goes on to the map, and one on the part inside the edge shakes the
## card (it is locked).
func test_a_press_under_the_holders_clip_edge_reaches_no_hidden_control() -> void:
	for size: Vector2i in [ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0]]:
		await _open(size, null)
		BuildSidebar.set_slide_ms_override(0)  # Down at once, then the slide is the test's.
		_sidebar.collapse()
		await _settle()
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		_sidebar.open()
		_sidebar.advance(STEP_S)  # A little more than a quarter of the way.
		await _settle()
		var why: String = str(size)
		var card: ItemTile = _sidebar.find_child("Tile_barracks", true, false) as ItemTile
		assert_int(card.state).is_equal(ItemTile.State.LOCKED)
		card.clock = func() -> int: return _now_ms
		var holder: Rect2 = _sidebar.get_global_rect()
		var card_rect: Rect2 = card.get_global_rect()
		var under: Vector2 = Vector2(card_rect.get_center().x, holder.end.y + UiScale.dp(3.0))
		var inside: Vector2 = Vector2(card_rect.get_center().x, holder.end.y - UiScale.dp(3.0))
		var at: String = "%s: card %s, holder %s" % [why, card_rect, holder]
		assert_bool(card_rect.has_point(under)).override_failure_message(at).is_true()  # Its hidden part.
		assert_bool(card_rect.has_point(inside)).override_failure_message(at).is_true()
		assert_bool(get_viewport().get_visible_rect().has_point(under)).is_true()
		assert_bool(_sidebar.get_global_rect().has_point(under)).is_false()
		var shakes: int = card.shakes
		_tap(inside)
		assert_int(card.shakes).override_failure_message(at).is_equal(shakes + 1)  # The card's.
		assert_array(_told).override_failure_message(at).is_empty()  # A HUD touch.
		assert_bool(_sidebar.is_open()).is_true()
		_tap(under)  # The map's: a tap, which collapses the menu.
		assert_int(card.shakes).override_failure_message(at).is_equal(shakes + 1)
		assert_array(_told).override_failure_message(at).has_size(1)
		assert_bool(_sidebar.is_open()).is_false()


## A slide frame asks `UiScale` for nothing: the request that starts a slide reads the dp and the
## layout once, then another dp in force (no resize) changes nothing of the ten frames, which take
## the cached dp for the zone and both lifts. Nothing is allocated by them either.
func test_a_slide_frame_uses_the_metrics_cached_at_the_last_resize() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(phone.window_size, phone)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	var dp: float = UiScale.base_px_per_dp()
	var army: MarginContainer = _hud("ArmyBand") as MarginContainer
	var strike: MarginContainer = _hud("StrikeBand") as MarginContainer
	_sidebar.collapse()
	UiScale.set_override(UiProfiles.by_name(&"web_tablet_portrait"))  # Another dp: no resize.
	assert_float(UiScale.base_px_per_dp()).is_not_equal(dp)
	var heights: Array[float] = []
	var zones: Array[float] = []
	var lifts: Array[Vector2i] = []
	heights.resize(10)
	zones.resize(10)
	lifts.resize(10)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for step: int in 10:
		_sidebar.advance(STEP_S)
		heights[step] = _sidebar.custom_minimum_size.y
		zones[step] = HudLayout.bottom_zone_dp
		lifts[step] = Vector2i(
			army.get_theme_constant("margin_bottom"), strike.get_theme_constant("margin_bottom")
		)
	var made: float = Performance.get_monitor(Performance.OBJECT_COUNT) - objects
	assert_float(made).is_equal(0.0)  # No object made by ten frames.
	for step: int in 10:
		var at: String = "step %d: height %f" % [step, heights[step]]
		assert_float(zones[step] * dp).override_failure_message(at).is_equal_approx(
			heights[step], 0.01
		)  # The cached dp.
		assert_int(lifts[step].x).override_failure_message(at).is_equal(
			ceili(heights[step] + 8.0 * dp)
		)
		assert_int(lifts[step].y).override_failure_message(at).is_equal(
			ceili(heights[step] + 8.0 * dp) + ceili(56.0 * dp) + ceili(8.0 * dp)
		)
		if step > 0:
			assert_float(heights[step]).override_failure_message(at).is_less_equal(
				heights[step - 1]
			)
	assert_float(heights[9]).is_equal(HudLayout.STRIP_DP * dp)
	UiScale.set_override(phone)


## The same as a source scan: the functions a slide frame runs name no `UiScale`, no orientation
## function and no engine query. `read_metrics` (a resize's) is where the lifts ask.
func test_the_per_frame_functions_name_no_ui_scale_and_no_engine_query() -> void:
	var frame: Dictionary[String, Array] = {
		"res://game/ui/BuildSidebar.gd": ["advance", "_apply_height", "_publish_top"],
		"res://game/ui/ArmyBar.gd": ["_lift", "_on_zone_changed"],
		"res://game/ui/StrikeControls.gd": ["_lift", "_on_zone_changed"],
	}
	var banned: RegEx = RegEx.create_from_string(
		r"UiScale|is_portrait|DisplayServer|get_viewport|get_tree|\.new\(|\bload\(|\bpreload\("
	)
	for path: String in frame:
		var source: String = FileAccess.get_file_as_string(path)
		for name: String in frame[path]:
			var body: String = _function(source, name)
			assert_str(body).override_failure_message("%s %s" % [path, name]).is_not_empty()
			var code: String = "\n".join(
				Array(body.split("\n")).map(
					func(line: String) -> String: return line.get_slice("#", 0)
				)
			)
			var hit: RegExMatch = banned.search(code)
			assert_object(hit).override_failure_message("%s %s: %s" % [path, name, code]).is_null()
	assert_object(banned.search("var m = UiScale.current()")).is_not_null()  # The scan sees it.


## A whole match with collapses, openings, slides, map gestures and a placement ends in the state
## hash of the same match with no menu action, and no Command is made: the menu is view only.
func test_the_menu_is_view_only_the_state_hash_is_that_of_a_run_without_it() -> void:
	var idle: Dictionary = await _play(false)
	assert_int(idle["hash"]).is_not_equal(0)
	var busy: Dictionary = await _play(true)
	assert_that(busy["hash"]).is_equal(idle["hash"])
	assert_that(busy["commands"]).is_equal(0)
	assert_that(busy["pending"]).is_equal(0)
	assert_int(busy["told"]).is_greater(0)  # The gestures did reach the menu.


## 60 ticks of a new main scene; at tick 20 the menu is worked: map gestures, a collapse and an
## opening with the slide stepped by hand, a placement begun and cancelled, a placement begun and
## left to the tick that finds the structure not ready.
func _play(menu: bool) -> Dictionary:
	await _open(ScreenSizes.PORTRAIT[0], null)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	_runner.run_ticks(20)
	if menu:
		var map: Vector2 = Vector2(360.0, 400.0)
		TouchEvents.press(get_viewport(), 0, map)
		TouchEvents.drag(get_viewport(), 0, map + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
		TouchEvents.release(get_viewport(), 0, map + Vector2(60.0, 0.0))
		for step: int in 4:
			_sidebar.advance(STEP_S)
		_sidebar.open()
		for step: int in 12:
			_sidebar.advance(STEP_S)
		Rig.make_ready(_runner.snapshot)
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		_sidebar.advance(STEP_S)
		_placement.cancel()
		_sidebar.advance(STEP_S)
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_runner.run_ticks(HASH_TICKS - 20)
	var left: Dictionary = {
		"hash": _runner.last_hash,
		"commands": _sent.size(),
		"pending": CommandQueue.pending(),
		"told": _told.size(),
	}
	remove_child(_main)
	_main.free()
	return left


## The source of function `name` in `source`: from its `func` line to the next function.
func _function(source: String, name: String) -> String:
	var start: int = source.find("func %s(" % name)
	if start < 0:
		return ""
	var end: int = source.find("\nfunc ", start + 1)
	return source.substr(start, (end if end > 0 else source.length()) - start)


## The safe area's inner width, base px.
func _inner_width() -> float:
	var area: Control = _hud("SafeArea") as Control
	return (
		get_viewport().get_visible_rect().size.x
		- area.get_theme_constant("margin_left")
		- area.get_theme_constant("margin_right")
	)


## Records every `zone_changed` as (top, height).
func _tell() -> Array[Vector2]:
	var told: Array[Vector2] = []
	_sidebar.zone_changed.connect(
		func(top: float, height: float) -> void: told.append(Vector2(top, height))
	)
	return told


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A tap at `at` (base px) through the real GUI, on the suite's clock.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## A new main scene at `size` (under `metrics`, a profile; null for the engine's own), the match
## paused, the Commands caught, the plant ready and the sidebar showing it. Gestures are counted in
## `_told` and run on the suite's clock.
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
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", [], ROSTER)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	Rig.make_ready(_runner.snapshot)
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_now_ms = 0
	_sent.clear()
	_told.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.map_gesture.connect(func() -> void: _told.append(Vector2.ZERO))
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_sidebar.refresh()
	_sidebar.set_process(false)  # The slide runs on the test's steps, not on the frames' time.
	await _settle()
