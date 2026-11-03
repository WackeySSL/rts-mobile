extends GdUnitTestSuite
## The drawer's slide and what rides on it (plan P120, ADR 0025 section 5, ADR 0024 sections 4, 8
## and 10), in the main scene: the game's frames run the slide (`_process` calls `advance`); a
## reversal mid-slide takes the share of `menu_slide_ms` that the distance left needs; a turn
## during a slide ends it at its target at once; a press under the holder's clip edge reaches no
## hidden control; upright, the ArmyBar stays a gap above the drawer's top at every step; the
## per-frame functions name no `UiScale` and no engine query; and a whole match with drawer actions
## ends in the state hash of one without, with no Command made.

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


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()


func before_test() -> void:
	MenuRig.begin()


## The frames of the game run the slide: a frame's `_process` moves the extent on by its delta and
## the slide reaches its target, with the test calling nothing but `_process`.
func test_the_games_frames_run_the_slide() -> void:
	for name: StringName in [&"android_6in", &"android_6in_portrait"]:
		var metrics: UiMetrics = UiProfiles.by_name(name)
		await _open(metrics.window_size, metrics)
		_sidebar.set_process(true)
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		_sidebar.open()
		assert_float(_sidebar._extent).is_equal(0.0)
		_sidebar._process(0.05)
		var part: float = _sidebar._extent
		assert_float(part).override_failure_message(str(name)).is_greater(0.0)
		assert_float(part).override_failure_message(str(name)).is_less(_sidebar._open_px)
		_sidebar._process(0.2)
		assert_float(_sidebar._extent).override_failure_message(str(name)).is_equal(
			_sidebar._open_px
		)
		BuildSidebar.set_slide_ms_override(0)


## A reversal mid-slide continues from the extent the drawer has and takes the share of
## `menu_slide_ms` that the distance left needs, not the whole of it: a quarter of the way back is
## 40 ms of 160, so it is shut a little after that and not before.
func test_a_reversal_takes_the_share_of_the_slide_the_distance_left_needs() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(metrics.window_size, metrics)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	_sidebar.open()
	_sidebar.advance(0.024)  # Early in the ease: well under half way.
	var extent: float = _sidebar._extent
	var share: float = extent / _sidebar._open_px
	assert_float(share).is_between(0.05, 0.5)
	_sidebar.collapse()
	var needs_ms: float = SLIDE_MS * share
	_sidebar.advance((needs_ms - 4.0) / 1000.0)
	assert_bool(_sidebar.visible).override_failure_message("still sliding").is_true()
	assert_float(_sidebar._extent).is_greater(0.0)
	_sidebar.advance(8.0 / 1000.0)  # Past the share's end: shut.
	assert_bool(_sidebar.visible).override_failure_message("shut by its share").is_false()
	assert_float(_sidebar._extent).is_equal(0.0)
	BuildSidebar.set_slide_ms_override(0)


## A turn ends a slide at its target at once, on the resize, with no frame of the slide between
## (the frames are off here): the extent is the orientation's open extent straight away.
func test_a_turn_during_a_slide_ends_it_at_its_target_at_once() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	_sidebar.open()
	_sidebar.advance(0.03)
	assert_float(_sidebar._extent).is_less(_sidebar._open_px)  # Mid-slide.
	for turn: UiMetrics in [portrait, landscape]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		assert_float(_sidebar._extent).is_equal(_sidebar._open_px)
		assert_bool(_sidebar.is_open()).is_true()
	_sidebar.collapse()
	_sidebar.advance(0.03)
	UiScale.set_override(portrait)
	get_window().size = portrait.window_size
	await _settle()
	assert_float(_sidebar._extent).is_equal(0.0)
	assert_bool(_sidebar.visible).is_false()
	BuildSidebar.set_slide_ms_override(0)


## A press under the holder's clip edge reaches no hidden control: while the drawer slides, a card
## straddles the holder's edge; a tap on its part inside is the card's, a tap on its part outside
## is a tap on the map (which closes the drawer) and reaches the card not at all.
func test_a_press_under_the_holders_clip_edge_reaches_no_hidden_control() -> void:
	for size: Vector2i in [ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0]]:
		await _open(size, null)
		BuildSidebar.set_slide_ms_override(SLIDE_MS)
		var portrait: bool = HudLayout.is_portrait()
		var why: String = str(size)
		_sidebar.open()
		var card: ItemTile = _sidebar.find_child("Tile_barracks", true, false) as ItemTile
		assert_int(card.state).is_equal(ItemTile.State.LOCKED)
		card.clock = func() -> int: return _now_ms
		var under: Vector2 = Vector2.ZERO
		var inside: Vector2 = Vector2.ZERO
		var found: bool = false
		for step: int in 80:  # The clip edge sweeps over the card once.
			_sidebar.advance(0.002)
			await _settle()
			var holder: Rect2 = _sidebar.get_global_rect()
			var rect: Rect2 = card.get_global_rect()
			var edge: float = holder.position.y if portrait else holder.position.x
			var near: float = UiScale.dp(3.0)
			under = (
				Vector2(rect.get_center().x, edge - near)
				if portrait
				else Vector2(edge - near, rect.get_center().y)
			)
			inside = (
				Vector2(rect.get_center().x, edge + near)
				if portrait
				else Vector2(edge + near, rect.get_center().y)
			)
			if (
				rect.has_point(under)
				and rect.has_point(inside)
				and not _sidebar.get_global_rect().has_point(under)
			):
				found = true
				break
		assert_bool(found).override_failure_message(why + ": no step straddled the edge").is_true()
		var shakes: int = card.shakes
		_tap(inside)
		assert_int(card.shakes).override_failure_message(why).is_equal(shakes + 1)  # The card's.
		assert_array(_told).override_failure_message(why).is_empty()  # A HUD touch.
		assert_bool(_sidebar.is_open()).is_true()
		_tap(under)  # The map's: a tap, which closes the drawer.
		assert_int(card.shakes).override_failure_message(why).is_equal(shakes + 1)
		assert_array(_told).override_failure_message(why).has_size(1)
		assert_bool(_sidebar.is_open()).is_false()
		BuildSidebar.set_slide_ms_override(0)


## Upright, what rides on the drawer follows the slide, a gap above its top at every step: the
## ArmyBar's band lifts by the zone and a gap (the strike button stands over BUILD, placed by
## `HudCorners` since P120c: it no longer rides on the drawer). The zone is BUILD's height at the
## least (the closed drawer: 8 dp above BUILD, not 16), the sheet's extent above that. Settled, the
## bar stands a gap above the sheet's top.
func test_upright_the_riders_stay_a_gap_above_the_drawer_at_every_step() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(metrics.window_size, metrics)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	var dp: float = UiScale.dp(1.0)
	var army: MarginContainer = _hud("ArmyBand") as MarginContainer
	# Closed: a gap above BUILD, whose own height is the zone.
	var safe_end: float = (
		SafeAreaMargin
		. rect_inside(get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP)
		. end
		. y
	)
	await _settle()
	assert_int(army.get_theme_constant("margin_bottom")).is_equal(ceili(64.0 * dp + 8.0 * dp))
	assert_float((_hud("ArmyBar") as Control).get_global_rect().end.y).is_equal_approx(
		safe_end - 64.0 * dp - 8.0 * dp, TOLERANCE_PX
	)
	_sidebar.open()
	for step: int in 12:
		_sidebar.advance(STEP_S)
		var zone: float = maxf(_sidebar._extent, 64.0 * dp)
		var why: String = "step %d, zone %s" % [step, zone]
		assert_int(army.get_theme_constant("margin_bottom")).override_failure_message(why).is_equal(
			ceili(zone + 8.0 * dp)
		)
	await _settle()
	assert_float(HudLayout.menu_top_px).is_less(safe_end)
	assert_float((_hud("ArmyBar") as Control).get_global_rect().end.y).is_equal_approx(
		HudLayout.menu_top_px - 8.0 * dp, TOLERANCE_PX
	)
	BuildSidebar.set_slide_ms_override(0)


## A slide frame asks `UiScale` for nothing and makes nothing: the functions a frame runs name no
## `UiScale`, no orientation function and no engine query (the metrics are cached on a resize).
func test_the_per_frame_functions_name_no_ui_scale_and_no_engine_query() -> void:
	var frame: Dictionary[String, Array] = {
		"res://game/ui/BuildSidebar.gd": ["advance", "_apply_extent", "_process"],
		"res://game/ui/BuildButton.gd": ["_process", "_draw"],
		"res://game/ui/ArmyBar.gd": ["_lift", "_on_zone_changed"],
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


## A whole match with the drawer opened, closed and slid, map gestures and a placement ends in the
## state hash of the same match with no drawer action, and no Command is made: view only.
func test_the_drawer_is_view_only_the_state_hash_is_that_of_a_run_without_it() -> void:
	var idle: Dictionary = await _play(false)
	assert_int(idle["hash"]).is_not_equal(0)
	var busy: Dictionary = await _play(true)
	assert_that(busy["hash"]).is_equal(idle["hash"])
	assert_that(busy["commands"]).is_equal(0)
	assert_that(busy["pending"]).is_equal(0)
	assert_int(busy["told"]).is_greater(0)  # The gestures did reach the HUD.


## 60 ticks of a new main scene; at tick 20 the drawer is worked: a map gesture, an opening and a
## closing with the slide stepped by hand, a placement begun and cancelled, a placement begun and
## left to the tick that finds the structure not ready.
func _play(drawer: bool) -> Dictionary:
	await _open(ScreenSizes.PORTRAIT[0], null)
	BuildSidebar.set_slide_ms_override(SLIDE_MS)
	_runner.run_ticks(20)
	if drawer:
		var map: Vector2 = Vector2(360.0, 400.0)
		TouchEvents.press(get_viewport(), 0, map)
		TouchEvents.drag(get_viewport(), 0, map + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
		TouchEvents.release(get_viewport(), 0, map + Vector2(60.0, 0.0))
		_sidebar.open()
		for step: int in 12:
			_sidebar.advance(STEP_S)
		_sidebar.collapse()
		for step: int in 4:
			_sidebar.advance(STEP_S)
		_sidebar.open()
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
## paused, the Commands caught, the plant ready and the drawer closed (`_sidebar.open()` opens it).
## Gestures are counted in `_told` and run on the suite's clock; the drawer's frames are off, the
## slide runs on the test's steps.
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
