extends GdUnitTestSuite
## The enemy tap of PlayerController (P43b) in the main scene, beyond the basic ATTACK of
## test_player_controller: it reads the snapshot and never the World, names the enemy by its id and
## not its row, uses the local player's number, and reaches the sim through the real CommandQueue.
## Fingers enter as window-px touch events through the real TouchInput with a fake clock, at
## 1280x720 (desktop), 2400x1080 (android_6in, 20:9 phone) and 2048x1536 (web_tablet, 4:3). Blue
## tank n is row n - 1 at px (544 + 96 * ((n - 1) % 6), 1184 + 96 * ((n - 1) / 6)), and red tank
## 31 stands at px (2208, 672).

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
const RED_31: Vector2 = Vector2(2208, 672)
const BLUE_1: Vector2 = Vector2(544, 1184)
const TOL: Vector2 = Vector2(0.05, 0.05)

var _window_size_before: Vector2i
var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _markers: MoveMarkerLayer
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = Vector2i(1280, 720)
	await await_idle_frame()
	var main: Node2D = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(main)
	await await_idle_frame()
	_runner = main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_layer = main.get_node("UnitLayer")
	_camera = main.get_node("Camera")
	_touch = main.get_node("TouchInput")
	_controller = main.get_node("PlayerController")
	_markers = main.get_node("MarkerLayer")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_markers.clock = _touch.clock  # One fake clock: a mark of an earlier profile has expired.


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


## After a tick the World is swapped for an empty one, so a read of it gives rows that are not
## there. The Command and the diamond must come from the snapshot and the drawn rigs alone.
func test_the_enemy_tap_reads_the_snapshot_and_never_the_world() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_runner.run_ticks(1)
		_runner.world = World.new()  # Test-only: an empty World where the match's was.
		_controller.selection.set_ids(PackedInt32Array([4, 2]))
		_camera.centre_on(RED_31)
		_tap(_off_centre(30))
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], 1, [2, 4], 31)
		_assert_one_diamond_at(RED_31)


## Ids are never reused, so once a tank dies the rows after it move up: the order must carry the
## id the snapshot names, not the row the Picker returned.
func test_the_attack_names_the_enemy_by_its_id_after_a_death_moved_its_row() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_runner.world.hp[2] = 0  # Tank 3 dies in the next tick.
		_runner.run_ticks(1)
		assert_int(_runner.snapshot.unit_id[29]).is_equal(31)  # Red tank 31 is now row 29.
		_controller.selection.set_ids(PackedInt32Array([1, 2]))
		_camera.centre_on(RED_31)
		_tap(_off_centre(29))
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], 1, [1, 2], 31)
		_assert_one_diamond_at(RED_31)


## The human can play the red side: the order carries that player's number, and the blue tank is
## the enemy.
func test_the_attack_carries_the_number_of_the_local_player() -> void:
	var red_side: ScenarioDef = _runner.scenario.duplicate() as ScenarioDef  # Not the shared one.
	red_side.local_player = 2
	_runner.scenario = red_side
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_controller.selection.set_ids(PackedInt32Array([32, 31]))
		_camera.centre_on(BLUE_1)
		_tap(_off_centre(0))
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], 2, [31, 32], 1)
		_assert_one_diamond_at(BLUE_1)
		assert_array(_controller.selection.selected).is_equal([31, 32])  # Blue 1 is not selected.


## Through the real queue and the sim: the ATTACK is applied (not dropped) and the tank drives at
## the red tank, which stands about 24 tiles away.
func test_the_attack_reaches_the_sim_and_the_tank_drives_at_the_enemy() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_controller.command_sink = CommandQueue.submit  # The sink the game ships with.
		_controller.selection.set_ids(PackedInt32Array([1]))
		_camera.centre_on(RED_31)
		_tap(_off_centre(30))
		assert_int(CommandQueue.pending()).is_equal(1)
		var before: float = _distance_milli(_runner.world, 0, 30)
		_runner.run_ticks(60)
		var world: World = _runner.world
		assert_int(world.dropped_commands).is_equal(0)
		assert_int(world.order[0]).is_equal(World.Order.ATTACK)
		assert_int(world.order_target[0]).is_equal(31)
		assert_float(_distance_milli(world, 0, 30)).is_less(before - 2000.0)
		assert_int(world.order[1]).is_equal(World.Order.IDLE)  # Only the selected tank was sent.


func _assert_attack(command: Command, player: int, ids: Array, target_id: int) -> void:
	assert_int(command.type).is_equal(Command.Type.ATTACK)
	assert_int(command.player_id).is_equal(player)
	assert_array(command.unit_ids).is_equal(ids)
	assert_int(command.target_id).is_equal(target_id)


## Exactly one mark shows, it is the diamond, and it stands on `world_px`.
func _assert_one_diamond_at(world_px: Vector2) -> void:
	var shown: Array[MoveMarkerLayer.Mark] = []
	for mark: MoveMarkerLayer.Mark in _markers.get_children():
		if mark.visible:
			shown.append(mark)
	assert_array(shown).has_size(1)
	assert_bool(shown[0].diamond).is_true()
	assert_vector(shown[0].position).is_equal_approx(world_px, TOL)


func _distance_milli(world: World, row_a: int, row_b: int) -> float:
	var a: Vector2 = Vector2(world.pos_x[row_a], world.pos_y[row_a])
	return a.distance_to(Vector2(world.pos_x[row_b], world.pos_y[row_b]))


## A new match at `profile`'s screen size, with nothing selected, sent or marked.
func _fresh_match(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	_runner.start()
	await await_idle_frame()  # The layer builds the new rigs, TouchInput reads the new dp.
	_controller.selection.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_sent.clear()
	_markers._process(0.0)  # A mark of the last profile is older than its lifetime by now.


## 20 dp left of the centre of row `row`: the tap point is not the enemy's own position.
func _off_centre(row: int) -> Vector2:
	return _layer.unit_screen_position(row) - Vector2(UiScale.dp(20), 0)


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	_touch._process(0.0)  # The frame that sees a hold.
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
