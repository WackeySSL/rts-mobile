extends GdUnitTestSuite
## Phase 1 controls end to end (plan P20): the main scene on a 6-inch Android phone (2400x1080) and
## a phone browser (2400x932), each held flat and held upright (1080x2400 and 1080x2100, plan P62b).
## Upright the view is 720 base px wide, so a few world points move (the *_PORTRAIT constants).
## Fingers are window-px touches pushed into the viewport, through TouchInput, the
## GestureRecognizer and the PlayerController (HUD buttons through the GUI). Time is
## a fake clock, only run_ticks() moves the sim and Commands go through the real CommandQueue. Tank
## n is row n - 1 of the 6-column block, which the 2:1 projection (P117) shows as a diamond: column
## c = (n - 1) % 6 and row r = (n - 1) / 6 stand at world px x = -320 + 48 (c - r) and
## y = 432 + 24 (c + r). Ids 1-30 are blue (the player's), 31-40 red. No map touch
## starts on the SelectionPanel, the ArmyBar or the Dev button: they keep their touches. Timings,
## buzzes and the formation bound come from the data. The zoom levels and the scenario are pins.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PROFILES: Array = [
	["android_6in"], ["web_phone"], ["android_6in_portrait"], ["web_phone_portrait"]
]
## Base px across the view at each profile: flat the window's aspect ratio at 720 high, upright the
## base width 720 (ADR 0015 section 2).
const VIEW_WIDTH: Dictionary[String, float] = {
	"android_6in": 1600.0,
	"web_phone": 1854.0,
	"android_6in_portrait": 720.0,
	"web_phone_portrait": 720.0,
}
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
## World px with no unit near it, past the tank block's upper right edge: milli (10000, 15000). The
## nearest tank is 102 px away, more than any hit area (49 px at most here), and the point is 128 px
## right of and 144 px above the middle of the view: clear of the build sidebar, the selection panel
## and the army bar at every profile (P85).
const GROUND: Vector2 = Vector2(-160, 400)
const GROUND_MILLI: Vector2i = Vector2i(10000, 15000)
## Where a drag's finger goes down: left of the build sidebar. The map moves 888 px left flat (1015
## on the wide web phone) and 448 px upright, and a finger may leave the screen.
const DRAG_FROM: Vector2 = Vector2(900, 400)
const DRAG_FROM_PORTRAIT: Vector2 = Vector2(660, 400)
## A box with no tank in it, in base px: left of the block flat (it starts at x 576); upright the
## block is at y 688 and lower, so above it.
const EMPTY_BOX: Rect2 = Rect2(80, 300, 220, 200)
const EMPTY_BOX_PORTRAIT: Rect2 = Rect2(80, 200, 220, 200)
## The middle of a pinch, clear of the tanks and the HUD, above the block: the fingers go 170 px
## either side, so flat they stay left of the build sidebar, and upright above the band. The pinch
## keeps the world point under it, so the camera centre follows a zoom (and stays in the map).
const PINCH_CENTRE: Vector2 = Vector2(800, 100)
const PINCH_CENTRE_PORTRAIT: Vector2 = Vector2(360, 300)
## The tanks at the top of the diamond, c + r <= 2 (world y 432 to 480; the next ones are at 504),
## and the world rect that holds exactly them.
const TOP_TANKS: Array[int] = [1, 2, 3, 7, 8, 13]
const TOP_BOX: Rect2 = Rect2(-440, 410, 240, 80)
const CARD: String = "res://assets/art/iso/icons/item_light_tank.svg"
const IDLE: int = World.Order.IDLE

var _window_size_before: Vector2i
var _upright: bool = false  ## The profile of `_open` is a portrait window.
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
	await _tap(_camera.world_to_screen(_ground()))
	assert_array(_sent).has_size(1)
	var command: Command = _sent[0]
	var target: Vector2i = _ground_milli()
	assert_int(command.type).is_equal(Command.Type.MOVE)  # P43c: a ground tap moves.
	assert_int(command.player_id).is_equal(1)
	assert_array(command.unit_ids).is_equal(range(1, 31))
	assert_int(command.target_x).is_equal(target.x)
	assert_int(command.target_y).is_equal(target.y)
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
		# The nearest 30 slots of a lattice reach sqrt(10) * spacing, here 3795 milli; the point is
		# near the block, so the last tanks to arrive settle up to about 100 milli further out.
		assert_float(spots[-1].distance_to(Vector2(target))).is_less(spacing * 3.3)
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
	# Drag the map left by the middle of the screen x of tanks 3 and 4: world x -224 and -176, so the
	# left edge of the screen becomes world x -200 and every tank with c - r under 3 leaves it (a
	# tank stands at x = -320 + 48 (c - r)); tanks 4, 5, 6, 11, 12 and 18 stay. That is half the
	# view's width plus 88 px: 888 flat, 1015 on the wide web phone, 448 upright.
	var by: float = (_layer.unit_screen_position(2).x + _layer.unit_screen_position(3).x) * 0.5
	assert_float(by).is_equal_approx(VIEW_WIDTH[profile] * 0.5 + 88.0, 0.5)
	await _drag(DRAG_FROM_PORTRAIT if _upright else DRAG_FROM, Vector2(-by, 0.0))
	assert_float(_layer.unit_screen_position(0).x).is_less(0.0)
	await _double_tap(_layer.unit_screen_position(3))  # Tank 4, column 3 of row 0.
	assert_array(_controller.selection.selected).is_equal([4, 5, 6, 11, 12, 18])
	_assert_panel("×6")
	assert_array(_sent).is_empty()


func test_long_press_box_selects_its_tanks(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	_controller.selection.set_ids(PackedInt32Array([20]))
	await _box(_top_box().position, _top_box().end)  # The six tanks at the top of the diamond.
	assert_array(_controller.selection.selected).is_equal(TOP_TANKS)
	_assert_panel("×6")
	assert_array(_buzzes).is_equal([_touch.settings.haptic_ms])  # The long-press, once.
	var empty: Rect2 = EMPTY_BOX_PORTRAIT if _upright else EMPTY_BOX
	await _box(empty.position, empty.end)  # Clear of the block: no tank in it.
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
	await _box(_top_box().position, _top_box().end)
	_press_hud("Group2", hold)  # Tanks 1, 2, 3, 7, 8 and 13.
	await _tap(_layer.unit_screen_position(2))
	_press_hud("Group3", hold)  # Tank 3.
	for label: Array in [["Group1", "1\n30"], ["Group2", "2\n6"], ["Group3", "3\n1"]]:
		assert_str((_hud(label[0]) as Button).text).is_equal(label[1])
	var buzz: int = _touch.settings.haptic_ms
	assert_array(_buzzes).is_equal([buzz, buzz, buzz, buzz])  # Three assigns, the box's long-press.
	var recalled: Array = [[range(1, 31), "×30"], [TOP_TANKS, "×6"], [[3], "×1"]]
	for slot: int in [1, 2, 3, 2]:  # A tap recalls, whatever is selected now.
		_press_hud("Group%d" % slot)
		assert_array(_controller.selection.selected).is_equal(recalled[slot - 1][0])
		_assert_panel(recalled[slot - 1][1])
	assert_array(_sent).is_empty()  # Neither selecting nor recalling orders.


func test_pinch_levels_then_tap_at_0_75(profile: String, _test_parameters := PROFILES) -> void:
	await _open(profile)
	await _tap(_layer.unit_screen_position(0))
	assert_float(_camera.zoom.x).is_equal(1.0)
	var middle: Vector2 = PINCH_CENTRE_PORTRAIT if _upright else PINCH_CENTRE
	# Finger half-distances before and after, and the level the lift snaps to: x1.7 is 1.7, then
	# 0.997 and 0.7 on the way down. None is a level, so only the snap puts the zoom on one.
	for step: Array in [[100.0, 170.0, 1.5, 2], [170.0, 113.0, 1.0, 1], [100.0, 70.0, 0.75, 0]]:
		await _pinch(middle, step[0], step[1])
		assert_float(_camera.zoom.x).override_failure_message(str(step)).is_equal(step[2])
		assert_int(_camera.zoom_level_index()).override_failure_message(str(step)).is_equal(step[3])
	await _tap(_layer.unit_screen_position(1))  # Tank 2 at 0.75.
	assert_array(_controller.selection.selected).is_equal([2])
	_assert_panel("×1")
	await _tap(_camera.world_to_screen(_ground()))  # The same world point as at zoom 1.0.
	assert_array(_sent).has_size(1)
	assert_array(_sent[0].unit_ids).is_equal([2])
	assert_int(_sent[0].target_x).is_equal(_ground_milli().x)
	assert_int(_sent[0].target_y).is_equal(_ground_milli().y)


## The case deferred from the P15 and P21 reviews: nothing in the input path, the order or the panel
## may assume the player is 1. The scenario is a copy of controls_test with local_player 2 (red).
func test_player_2_selects_orders_shows_its_card(
	profile: String, _test_parameters := PROFILES
) -> void:
	var source: ScenarioDef = load(SCENARIO)
	var scenario: ScenarioDef = source.duplicate()
	scenario.local_player = 2
	await _open(profile, scenario)
	assert_int(source.local_player).is_equal(1)  # The shared resource is untouched.
	await _tap(_layer.unit_screen_position(0))  # A blue tank on screen: not ours, nothing selected.
	assert_array(_controller.selection.selected).is_empty()
	_camera.centre_on(Vector2(768, 640))  # The red tanks 31-34, a little below the middle.
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


## The suite runs two phones, each held flat and held upright: the name of a profile, its window
## and its view width agree.
func test_the_profiles_are_two_phones_each_flat_and_upright() -> void:
	assert_int(PROFILES.size()).is_equal(4)
	for row: Array in PROFILES:
		var profile: String = row[0]
		var upright: bool = profile.ends_with("_portrait")
		var metrics: UiMetrics = UiProfiles.by_name(StringName(profile))
		assert_bool(UiProfiles.portrait().has(StringName(profile))).is_equal(upright)
		assert_bool(UiScale.is_portrait_size(metrics.window_size)).is_equal(upright)
		assert_bool(VIEW_WIDTH.has(profile)).is_true()


## The screen rect of TOP_BOX, from the camera as it is now.
func _top_box() -> Rect2:
	var top_left: Vector2 = _camera.world_to_screen(TOP_BOX.position)
	return Rect2(top_left, _camera.world_to_screen(TOP_BOX.end) - top_left)


func _assert_panel(count: String) -> void:
	assert_bool(_panel.visible).is_true()
	assert_str((_panel.get_node("Rows/Row0/Name") as Label).text).is_equal("Flarejack")
	assert_str((_panel.get_node("Rows/Row0/Count") as Label).text).is_equal(count)


## The panel icon is the tank's item card, whose colours are its own: no tint of the owner's.
func _assert_red_icon() -> void:
	var card: TextureRect = _panel.get_node("Rows/Row0/Icon/Card")
	assert_str(card.texture.resource_path).is_equal(CARD)
	assert_that(card.modulate).is_equal(Color.WHITE)


func _hud(node_name: String) -> Control:
	return _main.get_node("Hud").find_child(node_name, true, false)


## Fails when a map touch would start off screen or on a HUD Control. The HUD lays out on a frame,
## as on a phone: a panel that just appeared sits at its place, not at the SafeArea's corner.
func _assert_off_hud(at: Vector2) -> void:
	await await_idle_frame()
	var screen: Rect2 = get_viewport().get_visible_rect()
	assert_bool(screen.has_point(at)).override_failure_message("%s is off screen" % at).is_true()
	for node_name: String in ["SelectionPanel", "ArmyBar", "DevButton", "BuildSidebar"]:
		var hud: Control = _hud(node_name)
		var why: String = "%s is on %s %s" % [at, node_name, hud.get_global_rect()]
		var under: bool = hud.is_visible_in_tree() and hud.get_global_rect().has_point(at)
		assert_bool(under).override_failure_message(why).is_false()


## The ground point that a case taps, and the milli target that its MOVE must carry.
func _ground() -> Vector2:
	return GROUND


func _ground_milli() -> Vector2i:
	return GROUND_MILLI


## A new main scene on `profile` with the fake clock; Commands and buzzes are caught on their way.
func _open(profile: String, scenario: ScenarioDef = null) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(StringName(profile))
	_upright = UiScale.is_portrait_size(metrics.window_size)
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
