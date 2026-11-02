extends GdUnitTestSuite
## PlayerController.move_selected_to, the entry point of the minimap's hold (plan P88b, ADR 0019
## section 4), in the main scene (controls_test: a 48 x 48 map, 30 blue tanks) with the Commands
## caught at `command_sink`. It is the MOVE a ground tap sends, to the point given as it is (the
## minimap gives one inside the map, so its chevrons are on the map), for the selected own units,
## with the ground-tap marker and the buzz of a long-press that the settings allow; with nothing
## selected, or while a strike is aimed or a building placed, it sends nothing and says so. The
## minimap's side (the hold, the thresholds, the six sizes) is tests/ui/test_minimap_hold.gd.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
## World px with no unit near it, clear of the build sidebar and the panels: milli (10000, 15000).
const GROUND: Vector2 = Vector2(-160, 400)
const CAMERA_START: Vector2 = Vector2(-288, 544)
const FAR: Vector2i = Vector2i(-5000, 99000)  ## Beyond the map, on both axes.

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _camera: RtsCamera
var _markers: MoveMarkerLayer
var _sent: Array[Command] = []
var _buzzes: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	(_main.get_node("MatchRunner") as MatchRunner).paused = true
	_camera = _main.get_node("Camera")
	_controller = _main.get_node("PlayerController")
	_markers = _main.get_node("MarkerLayer")
	_camera.centre_on(CAMERA_START)
	_sent.clear()
	_buzzes.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


## The Command of a ground tap at GROUND and the one of the entry point at the same point are the
## same in every field, and both show the chevrons.
func test_it_sends_the_move_a_ground_tap_sends() -> void:
	_controller.selection.set_ids(PackedInt32Array([30, 2, 9]))
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = _camera.world_to_screen(GROUND)
	_controller.handle_gesture(tap)
	assert_array(_sent).has_size(1)
	var by_tap: Command = _sent[0]
	assert_int(by_tap.type).is_equal(Command.Type.MOVE)
	var ground: Vector2i = Vector2i(by_tap.target_x, by_tap.target_y)
	assert_vector(ground).is_equal(Vector2i(10000, 15000))
	assert_array(_shown_marks()).has_size(1)
	_markers.clock = func() -> int: return 1 << 30  # The tap's mark has expired.
	_markers._process(0.0)
	assert_array(_shown_marks()).is_empty()
	_markers.clock = Time.get_ticks_msec
	assert_bool(_controller.move_selected_to(ground)).is_true()
	assert_array(_sent).has_size(2)
	var held: Command = _sent[1]
	assert_int(held.type).is_equal(by_tap.type)
	assert_int(held.player_id).is_equal(by_tap.player_id)
	assert_int(held.tick).is_equal(by_tap.tick)
	assert_int(held.sequence).is_equal(by_tap.sequence)
	assert_array(held.unit_ids).is_equal([2, 9, 30])  # The sorted selection, as the tap's.
	assert_array(held.unit_ids).is_equal(by_tap.unit_ids)
	assert_int(held.target_x).is_equal(by_tap.target_x)
	assert_int(held.target_y).is_equal(by_tap.target_y)
	assert_int(held.target_id).is_equal(by_tap.target_id)
	assert_array(held.payload).is_equal(by_tap.payload)
	var marks: Array[MoveMarkerLayer.Mark] = _shown_marks()
	assert_array(marks).has_size(1)
	assert_bool(marks[0].diamond).is_false()  # The chevrons of a move, not an attack's diamond.
	assert_vector(marks[0].position).is_equal_approx(GROUND, Vector2(0.05, 0.05))
	assert_array(_controller.selection.selected).is_equal([2, 9, 30])  # Ordering keeps it.


## The point is sent as it is, also one beyond the map (the caller keeps it inside; the sim clamps).
func test_the_point_is_sent_as_given_also_beyond_the_map() -> void:
	_controller.selection.set_ids(PackedInt32Array([1]))
	assert_bool(_controller.move_selected_to(FAR)).is_true()
	assert_array(_sent).has_size(1)
	assert_int(_sent[0].target_x).is_equal(FAR.x)
	assert_int(_sent[0].target_y).is_equal(FAR.y)


func test_it_sends_nothing_without_a_selection() -> void:
	assert_bool(_controller.move_selected_to(Vector2i(10000, 15000))).is_false()
	assert_array(_sent).is_empty()
	assert_array(_buzzes).is_empty()
	assert_int(_markers.active_count()).is_equal(0)


## Nothing is ordered while a strike is aimed or a building is placed (the rule of every gesture).
func test_it_sends_nothing_while_placing_or_aiming() -> void:
	_controller.selection.set_ids(PackedInt32Array([1]))
	for mode: Object in [_controller.placement, _controller.strike_aim]:
		mode.set("active", true)
		assert_bool(_controller.move_selected_to(Vector2i(10000, 15000))).is_false()
		mode.set("active", false)
	assert_array(_sent).is_empty()
	assert_array(_buzzes).is_empty()
	assert_int(_markers.active_count()).is_equal(0)
	assert_bool(_controller.move_selected_to(Vector2i(10000, 15000))).is_true()
	assert_array(_sent).has_size(1)


## One buzz of `haptic_ms` per MOVE, none when the player turned haptics off (the MOVE still goes).
func test_the_buzz_is_one_haptic_ms_and_follows_the_setting() -> void:
	var settings: InputSettings = _controller.settings.duplicate() as InputSettings
	_controller.settings = settings
	_controller.selection.set_ids(PackedInt32Array([1]))
	assert_bool(_controller.move_selected_to(Vector2i(10000, 15000))).is_true()
	assert_array(_buzzes).is_equal([settings.haptic_ms])
	settings.haptics_enabled = false
	assert_bool(_controller.move_selected_to(Vector2i(12000, 15000))).is_true()
	assert_array(_buzzes).is_equal([settings.haptic_ms])  # Still the one.
	assert_array(_sent).has_size(2)


func _shown_marks() -> Array[MoveMarkerLayer.Mark]:
	var shown: Array[MoveMarkerLayer.Mark] = []
	for mark: MoveMarkerLayer.Mark in _markers.get_children():
		if mark.visible:
			shown.append(mark)
	return shown
