extends GdUnitTestSuite
## Phase 1 controls end to end (plan P20): the main scene on a 6-inch Android phone (2400x1080) and
## a phone browser (2400x932). Fingers are window-px touches pushed into the viewport, through
## TouchInput, the GestureRecognizer and the PlayerController (HUD buttons through the GUI). Time is
## a fake clock, only run_ticks() moves the sim and Commands go through the real CommandQueue. Tank
## n is row n - 1 of the 6-column block, ids 1-30 are blue (the player's), 31-40 red. No map touch
## starts on the SelectionPanel, the ArmyBar or the Dev button: they keep their touches. Timings,
## buzzes and the formation bound come from the data. The zoom levels and the scenario are pins.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PROFILES: Array = [["android_6in"], ["web_phone"]]
## Base px across the view at each profile (720 high, the window's aspect ratio).
const VIEW_WIDTH: Dictionary[String, float] = {"android_6in": 1600.0, "web_phone": 1854.0}
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
## World px with no unit near it: milli (20016, 21516), where 20015.625 rounds up.
const GROUND: Vector2 = Vector2(1281, 1377)
const RED: Color = Color("E5484D")
const IDLE: int = World.Order.IDLE

var _window_size_before: Vector2i
var _now_ms: int = 0
var _main: Node2D
var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _panel: SelectionPanel
var _scan: LogScan
var _sent: Array[Command] = []
var _buzzes: Array[int] = []


## The errors the engine logs while a test plays, the lines scripts/verify.sh scans for (SCRIPT
## ERROR, ERROR:, Parse Error). Warnings are not in that scan.
class LogScan:
	extends Logger

	var hits: PackedStringArray = PackedStringArray()

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			hits.append("%s:%d %s %s" % [file, line, code, rationale])


func before() -> void:
	_window_size_before = get_window().size


func before_test() -> void:
	_scan = LogScan.new()
	OS.add_logger(_scan)


## Nothing in the log matches the error scan. The override, queue, window size and logger are global
## and must not outlive the test. The scene goes first, so no live HUD sees the resize.
func after_test() -> void:
	assert_array(_scan.hits).is_empty()
	OS.remove_logger(_scan)
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_first_tap_selects_a_lone_tank(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	assert_bool(_panel.visible).is_false()
	await _tap(_layer.unit_screen_position(0))
	assert_array(_controller.selection.selected).is_equal([1])
	_assert_panel("×1")
	await _tap(_layer.unit_screen_position(7))  # Tank 8: the selection moves, it does not grow.
	assert_array(_controller.selection.selected).is_equal([8])
	assert_array(_sent).is_empty()  # Selecting orders nothing.


func test_tap_ground_450_ticks_idle_slots(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	await _double_tap(_layer.unit_screen_position(0))
	await _tap(_camera.world_to_screen(GROUND))
	assert_array(_sent).has_size(1)
	var command: Command = _sent[0]
	assert_int(command.type).is_equal(Command.Type.ATTACK_MOVE)
	assert_int(command.player_id).is_equal(1)
	assert_array(command.unit_ids).is_equal(range(1, 31))
	assert_int(command.target_x).is_equal(20016)
	assert_int(command.target_y).is_equal(21516)
	assert_int(CommandQueue.pending()).is_equal(1)
	_runner.run_ticks(450)
	var world: World = _runner.world
	assert_int(world.tick).is_equal(450)
	assert_int(CommandQueue.pending()).is_equal(0)
	assert_int(world.dropped_commands).is_equal(0)
	var spacing: float = (load("res://data/units/light_tank.tres") as UnitDef).formation_spacing
	var spots: Array[Vector2] = []
	for id: int in command.unit_ids:
		var row: int = world.index_of(id)
		assert_int(world.order[row]).override_failure_message("tank %d" % id).is_equal(IDLE)
		spots.append(Vector2(world.pos_x[row], world.pos_y[row]))
		# The nearest 30 slots of a lattice reach sqrt(10) * spacing, here 3795 milli.
		assert_float(spots[-1].distance_to(Vector2(20016, 21516))).is_less(spacing * 3.17)
	for a: int in 30:
		for b: int in range(a + 1, 30):
			# P39b: separation settles tanks just under their radii sum (800), not on the lattice;
			# the bound is 90% of that sum, 720 milli (ADR 0008 section 4).
			assert_float(spots[a].distance_to(spots[b])).is_greater_equal(720.0)
	assert_int(world.pos_x[30]).is_equal(34500)  # The red tanks were not ordered.


## The type filter is proven in tests/input/test_player_controller.gd until a second type exists.
func test_double_tap_selects_visible_tanks(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	await _double_tap(_layer.unit_screen_position(0))
	assert_array(_controller.selection.selected).is_equal(range(1, 31))
	_assert_panel("×30")
	# Drag the map left by 784 px: columns 0-2 (x 544, 640, 736) leave the screen, 3-5 stay.
	await _drag(Vector2(VIEW_WIDTH[profile] - 60.0, 400.0), Vector2(-784.0, 0.0))
	assert_float(_layer.unit_screen_position(0).x).is_less(0.0)
	await _double_tap(_layer.unit_screen_position(3))  # Tank 4, column 3 of row 0.
	var visible_columns: Array = [4, 5, 6, 10, 11, 12, 16, 17, 18, 22, 23, 24, 28, 29, 30]
	assert_array(_controller.selection.selected).is_equal(visible_columns)
	_assert_panel("×15")
	assert_array(_sent).is_empty()


func test_long_press_box_selects_its_tanks(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	_controller.selection.set_ids(PackedInt32Array([20]))
	var first_row: Rect2 = Rect2(_layer.unit_screen_position(0), Vector2.ZERO)
	first_row = first_row.expand(_layer.unit_screen_position(5)).grow(30.0)  # Tanks 1-6.
	await _box(first_row.position, first_row.end)
	assert_array(_controller.selection.selected).is_equal([1, 2, 3, 4, 5, 6])
	_assert_panel("×6")
	assert_array(_buzzes).is_equal([_touch.settings.haptic_ms])  # The long-press, once.
	await _box(Vector2(80, 300), Vector2(300, 500))  # Left of the block: no tank in it.
	assert_array(_controller.selection.selected).is_empty()
	assert_bool(_panel.visible).is_false()
	assert_array(_sent).is_empty()


func test_all_army_then_groups_1_to_3(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	var hold: int = _touch.settings.group_assign_ms
	_press_hud("AllArmy")
	assert_array(_controller.selection.selected).is_equal(range(1, 31))
	_assert_panel("×30")  # Rows/Row0/Count.
	_press_hud("Group1", hold)  # A hold assigns the 30.
	var corner: Vector2 = Vector2(30, 30)
	await _box(_layer.unit_screen_position(0) - corner, _layer.unit_screen_position(5) + corner)
	_press_hud("Group2", hold)  # Tanks 1-6.
	await _tap(_layer.unit_screen_position(2))
	_press_hud("Group3", hold)  # Tank 3.
	for label: Array in [["Group1", "1\n30"], ["Group2", "2\n6"], ["Group3", "3\n1"]]:
		assert_str((_hud(label[0]) as Button).text).is_equal(label[1])
	var buzz: int = _touch.settings.haptic_ms
	assert_array(_buzzes).is_equal([buzz, buzz, buzz, buzz])  # Three assigns, the box's long-press.
	var recalled: Array = [[range(1, 31), "×30"], [[1, 2, 3, 4, 5, 6], "×6"], [[3], "×1"]]
	for slot: int in [1, 2, 3, 2]:  # A tap recalls, whatever is selected now.
		_press_hud("Group%d" % slot)
		assert_array(_controller.selection.selected).is_equal(recalled[slot - 1][0])
		_assert_panel(recalled[slot - 1][1])
	assert_array(_sent).is_empty()  # Neither selecting nor recalling orders.


func test_pinch_levels_then_tap_at_0_75(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	await _tap(_layer.unit_screen_position(0))
	assert_float(_camera.zoom.x).is_equal(1.0)
	var middle: Vector2 = Vector2(1200, 300)  # Clear of the tanks and the HUD.
	# Finger half-distances before and after, and the level the lift snaps to: x1.7 is 1.7, then
	# 0.997 and 0.7 on the way down. None is a level, so only the snap puts the zoom on one.
	for step: Array in [[100.0, 170.0, 1.5, 2], [170.0, 113.0, 1.0, 1], [100.0, 70.0, 0.75, 0]]:
		await _pinch(middle, step[0], step[1])
		assert_float(_camera.zoom.x).override_failure_message(str(step)).is_equal(step[2])
		assert_int(_camera.zoom_level_index()).override_failure_message(str(step)).is_equal(step[3])
	await _tap(_layer.unit_screen_position(1))  # Tank 2 at 0.75.
	assert_array(_controller.selection.selected).is_equal([2])
	_assert_panel("×1")
	await _tap(_camera.world_to_screen(GROUND))  # The same world point as at zoom 1.0.
	assert_array(_sent).has_size(1)
	assert_array(_sent[0].unit_ids).is_equal([2])
	assert_int(_sent[0].target_x).is_equal(20016)
	assert_int(_sent[0].target_y).is_equal(21516)


## The case deferred from the P15 and P21 reviews: nothing in the input path, the order or the panel
## may assume the player is 1. The scenario is a copy of controls_test with local_player 2 (red).
func test_player_2_selects_orders_tints(profile: String, _test_parameters := PROFILES) -> void:
	var source: ScenarioDef = load(SCENARIO)
	var scenario: ScenarioDef = source.duplicate()
	scenario.local_player = 2
	await _open(profile, scenario)
	assert_int(source.local_player).is_equal(1)  # The shared resource is untouched.
	await _tap(_layer.unit_screen_position(0))  # A blue tank on screen: not ours, nothing selected.
	assert_array(_controller.selection.selected).is_empty()
	_camera.centre_on(Vector2(2208, 672))  # The red tanks 31-34.
	await _double_tap(_layer.unit_screen_position(30))  # All four red tanks are on screen.
	assert_array(_controller.selection.selected).is_equal([31, 32, 33, 34])
	_assert_panel("×4")
	_assert_red_icon()
	await _tap(_layer.unit_screen_position(30) - Vector2(300, 0))  # Ground: it orders as player 2.
	assert_array(_sent).has_size(1)
	assert_int(_sent[0].player_id).is_equal(2)
	assert_array(_sent[0].unit_ids).is_equal([31, 32, 33, 34])
	_press_hud("AllArmy")
	assert_array(_controller.selection.selected).is_equal(range(31, 41))
	_assert_panel("×10")
	_assert_red_icon()
	assert_array(_sent).has_size(1)


func _assert_panel(count: String) -> void:
	assert_bool(_panel.visible).is_true()
	assert_str((_panel.get_node("Rows/Row0/Name") as Label).text).is_equal("Light Tank")
	assert_str((_panel.get_node("Rows/Row0/Count") as Label).text).is_equal(count)


## The panel icon's Team layer wears team_color(2), red, and not team_color(1), blue.
func _assert_red_icon() -> void:
	var tint: Color = (_panel.get_node("Rows/Row0/Icon/Team") as TextureRect).modulate
	assert_that(tint).is_equal(RED)
	assert_that(tint).is_equal(_layer.team_color(2))


func _hud(node_name: String) -> Control:
	return _main.get_node("Hud").find_child(node_name, true, false)


## Fails when a map touch would start off screen or on a HUD Control. The HUD lays out on a frame,
## as on a phone: a panel that just appeared sits at its place, not at the SafeArea's corner.
func _assert_off_hud(at: Vector2) -> void:
	await await_idle_frame()
	var screen: Rect2 = get_viewport().get_visible_rect()
	assert_bool(screen.has_point(at)).override_failure_message("%s is off screen" % at).is_true()
	for node_name: String in ["SelectionPanel", "ArmyBar", "DevButton"]:
		var hud: Control = _hud(node_name)
		var why: String = "%s is on %s %s" % [at, node_name, hud.get_global_rect()]
		var under: bool = hud.is_visible_in_tree() and hud.get_global_rect().has_point(at)
		assert_bool(under).override_failure_message(why).is_false()


## A new main scene on `profile` with the fake clock; Commands and buzzes are caught on their way.
func _open(profile: String, scenario: ScenarioDef = null) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(StringName(profile))
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	var view_width: float = get_viewport().get_visible_rect().size.x
	assert_float(view_width).is_equal_approx(VIEW_WIDTH[profile], 1.0)
	assert_float(UiScale.dp(48.0)).is_greater_equal(84.0)  # The override is in force.
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	if scenario != null:
		_runner.scenario = scenario
	_camera = _main.get_node("Camera")
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	add_child(_main)
	await await_idle_frame()
	_layer = _main.get_node("UnitLayer")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_panel = _main.get_node("Hud/SafeArea/SelectionBand/SelectionPanel")
	_now_ms = 0
	_sent.clear()
	_buzzes.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	for slot: int in range(1, 4):
		(_hud("Group%d" % slot) as HoldButton).clock = func() -> int: return _now_ms
	assert_bool(_controller.command_sink == CommandQueue.submit).is_true()  # What the game ships.
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	await _touch_at(at)
	_now_ms += 1000


func _double_tap(at: Vector2) -> void:
	await _touch_at(at)
	_now_ms += 100
	await _touch_at(at)
	_now_ms += 1000


func _touch_at(at: Vector2) -> void:
	await _assert_off_hud(at)
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)


## Holds 300 ms at `from` (the long-press), drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	await _assert_off_hud(from)
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += _touch.settings.long_press_ms
	_touch._process(0.0)  # The frame that sees the hold.
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000


## One finger drags the map by `by` base px from `from`.
func _drag(from: Vector2, by: Vector2) -> void:
	await _assert_off_hud(from)
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, from + by, by)
	TouchEvents.release(get_viewport(), 0, from + by)
	_now_ms += 1000


## Two fingers `from_half` px either side of `centre` move to `to_half` px, one after the other.
func _pinch(centre: Vector2, from_half: float, to_half: float) -> void:
	var left: Vector2 = centre - Vector2(from_half, 0)
	var right: Vector2 = centre + Vector2(from_half, 0)
	await _assert_off_hud(left)
	await _assert_off_hud(right)
	TouchEvents.press(get_viewport(), 0, left)
	TouchEvents.press(get_viewport(), 1, right)
	var left_to: Vector2 = centre - Vector2(to_half, 0)
	var right_to: Vector2 = centre + Vector2(to_half, 0)
	TouchEvents.drag(get_viewport(), 0, left_to, left_to - left)
	TouchEvents.drag(get_viewport(), 1, right_to, right_to - right)
	TouchEvents.release(get_viewport(), 1, right_to)
	TouchEvents.release(get_viewport(), 0, left_to)
	_now_ms += 1000


## A finger on a HUD button through the real GUI for `held_ms`. A HoldButton sees the hold on a
## frame while the finger rests, which `_process` stands in for.
func _press_hud(node_name: String, held_ms: int = 50) -> void:
	var control: Control = _hud(node_name)
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += held_ms
	if control is HoldButton:
		(control as HoldButton)._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
