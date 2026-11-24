extends GdUnitTestSuite
## The dark radar scope (plan P575, ADR 0047 section 8), in the main scene at the six sizes of
## ScreenSizes.ALL, upright and sideways, driven by crafted `radar_dark` and `radar_dark_until`
## entries of the published snapshot: the dark face shows and hides with the flag; the ring's share
## comes from the ticks; a tap nudges the scope and changes no state; an open full map folds and a
## hold on it that is sending units is cancelled; no label holds a status word; the scope's draw
## count at rest is as in the lit state; the crop returns on the next paint after the dark time.
## Player 1 has a Headquarters, two light tanks and a Heavy Yard.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "light_tank"]
const MORE: Array = [["light_tank", 12, 10], ["light_tank", 13, 10]]
const TANK_A: int = 3
const SPAN: int = 150
const WORDS: Array[String] = ["OFFLINE", "ONLINE", "SIGNAL", "DOWN"]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _touch: TouchInput
var _controller: PlayerController
var _camera: RtsCamera
var _state: HudState
var _scope: RadarScope
var _minimap: Minimap
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_the_dark_face_shows_and_hides_with_the_snapshot_flag() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		assert_bool(_scope.is_dark()).override_failure_message(why).is_false()
		var draws: int = _scope.draw_count()
		_go_dark(SPAN)
		await _settle()
		assert_bool(_scope.is_dark()).override_failure_message(why).is_true()
		assert_int(_scope.draw_count()).override_failure_message(why).is_greater(draws)
		draws = _scope.draw_count()
		_light()
		await _settle()
		assert_bool(_scope.is_dark()).override_failure_message(why).is_false()
		assert_int(_scope.draw_count()).override_failure_message(why).is_greater(draws)
		assert_array(_scope.crop_pieces()).override_failure_message(why).is_not_empty()
		# Another player's flag changes nothing here.
		_runner.snapshot.radar_dark[2] = 1
		await _settle()
		assert_bool(_scope.is_dark()).override_failure_message(why).is_false()


func test_the_ring_fraction_comes_from_the_ticks() -> void:
	assert_float(RadarScope.ring_fraction(250, 100, 150)).is_equal(1.0)
	assert_float(RadarScope.ring_fraction(200, 100, 200)).is_equal(0.5)
	assert_float(RadarScope.ring_fraction(100, 100, 150)).is_equal(0.0)
	assert_float(RadarScope.ring_fraction(90, 100, 150)).is_equal(0.0)
	assert_float(RadarScope.ring_fraction(500, 100, 150)).is_equal(1.0)
	assert_float(RadarScope.ring_fraction(500, 100, 0)).is_equal(0.0)
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_go_dark(SPAN)
		await _settle()
		assert_float(_scope.drain_fraction()).override_failure_message(why).is_equal(1.0)
		_runner.snapshot.tick += SPAN / 2
		await _settle()
		assert_float(_scope.drain_fraction()).override_failure_message(why).is_equal(0.5)
		var draws: int = _scope.draw_count()
		_runner.snapshot.tick += SPAN / 3
		await _settle()
		assert_float(_scope.drain_fraction()).override_failure_message(why).is_equal_approx(
			float(SPAN - SPAN / 2 - SPAN / 3) / SPAN, 0.0001
		)
		assert_int(_scope.draw_count()).override_failure_message(why).is_greater(draws)
		# A second strike on top widens the span: the ring starts full again.
		_runner.snapshot.radar_dark_until[1] += SPAN
		await _settle()
		assert_float(_scope.drain_fraction()).override_failure_message(why).is_equal(1.0)
		_runner.snapshot.tick = _runner.snapshot.radar_dark_until[1]
		await _settle()
		assert_float(_scope.drain_fraction()).override_failure_message(why).is_equal(0.0)


func test_a_tap_on_the_dark_scope_nudges_and_changes_no_state() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_go_dark(SPAN)
		await _settle()
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		var home: Vector2 = _camera.position
		var at: Vector2 = _scope.get_global_rect().get_center()
		var nudges: int = _scope.nudges
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(_scope.nudges).override_failure_message(why).is_equal(nudges + 1)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_array(_sent).override_failure_message(why).is_empty()
		assert_vector(_camera.position).override_failure_message(why).is_equal(home)
		assert_array(_controller.selection.selected).override_failure_message(why).is_equal(
			[TANK_A]
		)
		# Lit again, the same tap opens the map and nudges nothing.
		_light()
		await _settle()
		at = _scope.get_global_rect().get_center()  # The nudge's scale is back by now.
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_int(_scope.nudges).override_failure_message(why).is_equal(nudges + 1)


func test_an_open_full_map_closes_and_its_hold_is_cancelled() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_state.pinned = true  # No timer folds it: only the dark scope can.
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		var map: Control = _main.get_node("Hud").find_child("RadarMap", true, false) as Control
		assert_bool(map.visible).override_failure_message(why).is_true()
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		var at: Vector2 = _minimap.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		_go_dark(SPAN)
		await _settle()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(map.visible).override_failure_message(why).is_false()
		_now_ms += 5000
		_minimap._poll_hold()
		TouchEvents.release(get_viewport(), 0, at)
		assert_array(_sent).override_failure_message(why).is_empty()
		_state.pinned = false


func test_no_label_holds_a_status_word_while_the_scope_is_dark() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_go_dark(SPAN)
		await _settle()
		var texts: Array[String] = []
		for node: Node in _main.get_node("Hud").find_children("*", "", true, false):
			if node is Label and (node as Label).is_visible_in_tree():
				texts.append((node as Label).text)
			elif node is Button and (node as Button).is_visible_in_tree():
				texts.append((node as Button).text)
		for text: String in texts:
			for word: String in WORDS:
				(
					assert_bool(text.to_upper().contains(word))
					. override_failure_message("%s: '%s' holds %s" % [size, text, word])
					. is_false()
				)
		assert_int(_scope.get_child_count()).is_equal(0)  # The face has no label of its own.


func test_the_draw_count_at_rest_is_unchanged_while_dark_and_after() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		await _settle()
		var lit: int = _scope.draw_count()
		for frame: int in 20:
			await await_idle_frame()
		assert_int(_scope.draw_count()).override_failure_message(why).is_equal(lit)
		_go_dark(SPAN)
		await _settle()
		var dark: int = _scope.draw_count()
		for frame: int in 20:  # The snapshot does not move: nothing is drawn.
			await await_idle_frame()
		assert_int(_scope.draw_count()).override_failure_message(why).is_equal(dark)
		_light()
		await _settle()
		var back: int = _scope.draw_count()
		for frame: int in 20:
			await await_idle_frame()
		assert_int(_scope.draw_count()).override_failure_message(why).is_equal(back)


## The picture goes on painting while the scope is dark, and the crop is there at once after.
func test_the_picture_keeps_painting_while_dark_and_the_crop_returns() -> void:
	await _open(ScreenSizes.LANDSCAPE[1])
	_go_dark(SPAN)
	await _settle()
	var paints: int = _minimap.redraw_count()
	CommandQueue.submit(Command.move(1, PackedInt32Array([TANK_A]), 24000, 21500))
	_runner.run_ticks(60)  # Every capture is a new snapshot: the sim says the radar is lit.
	_go_dark(SPAN)
	await _settle()
	assert_int(_minimap.redraw_count()).is_greater(paints)
	assert_bool(_scope.is_dark()).is_true()
	_light()
	await _settle()
	assert_array(_scope.crop_pieces()).is_not_empty()


## The local player's entries of the published snapshot, ending `ticks` after its tick.
func _go_dark(ticks: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.radar_dark = PackedInt32Array([0, 1, 0])
	snap.radar_dark_until = PackedInt32Array([0, snap.tick + ticks, 0])


func _light() -> void:
	_runner.snapshot.radar_dark = PackedInt32Array([0, 0, 0])
	_runner.snapshot.radar_dark_until = PackedInt32Array([0, 0, 0])


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _open(size: Vector2i) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", MORE, ROSTER)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_state = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	_scope = _main.get_node("Hud").find_child("RadarScope", true, false) as RadarScope
	_minimap = _main.get_node("Hud").find_child("Minimap", true, false) as Minimap
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_minimap.clock = _touch.clock
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	Rig.explore(_runner.snapshot)
	await _settle()
