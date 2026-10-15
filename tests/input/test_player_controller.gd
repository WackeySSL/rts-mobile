extends GdUnitTestSuite
## PlayerController in the main scene (ADR 0004 section 5). Fingers enter as window-px touch events
## with a fake clock, through the real TouchInput and recognizer, and the Commands are caught at
## `command_sink`. Each flow runs at 1280x720 (desktop), 2400x1080 (android_6in, 20:9 phone) and
## 2048x1536 (web_tablet, 4:3). Tank n is row n - 1 of the 6-column block: tank 1 at px (544,
## 1184), 96 px between neighbours. Red tank 31 stands at px (2208, 672), milli (34500, 10500).

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TwoTypeLayer: GDScript = preload("res://tests/input/support/two_type_layer.gd")
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
const CAMERA_START: Vector2 = Vector2(800, 1376)
## World px with no unit near it: milli (20016, 21516), where 20015.625 rounds up.
const GROUND: Vector2 = Vector2(1281, 1377)

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _default_sink: Callable
var _now_ms: int = 0
var _sent: Array[Command] = []
var _changes: Array[PackedInt32Array] = []
var _buzzes: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = Vector2i(1280, 720)
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_layer = _main.get_node("UnitLayer")
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_now_ms = 0
	_sent.clear()
	_changes.clear()
	_buzzes.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	_default_sink = _controller.command_sink
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.selection_changed.connect(func(ids: PackedInt32Array) -> void: _changes.append(ids))


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_the_first_tap_on_a_tank_selects_it() -> void:
	assert_object(_touch.controller).is_same(_controller)
	assert_object(_controller.runner).is_same(_runner)
	assert_object(_controller.unit_layer).is_same(_layer)
	assert_object(_controller.camera).is_same(_camera)
	assert_object(_controller.settings).is_same(load("res://data/input_settings.tres"))
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_tap(_layer.unit_screen_position(0) - Vector2(UiScale.dp(40), 0))  # Outside the hit area.
		assert_array(_controller.selection.selected).is_empty()
		_tap(_layer.unit_screen_position(0) - Vector2(UiScale.dp(20), 0))  # The block's left edge.
		assert_array(_controller.selection.selected).is_equal([1])
		assert_array(_changes).has_size(1)
		assert_array(_changes[0]).is_equal([1])
		_tap(_layer.unit_screen_position(1))
		assert_array(_controller.selection.selected).is_equal([2])
		assert_array(_sent).is_empty()  # Selecting orders nothing.


func test_tap_ground_with_a_selection_sends_one_attack_move_and_without_one_nothing() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_tap(_camera.world_to_screen(GROUND))
		assert_array(_sent).is_empty()
		_tap(_layer.unit_screen_position(0))  # Select tank 1, then send it.
		_tap(_camera.world_to_screen(GROUND), 300)  # Held: LONG_PRESS, BOX_CANCEL, then a TAP.
		assert_array(_sent).has_size(1)
		_assert_attack_move(_sent[0], [1], 20016, 21516)
		assert_array(_controller.selection.selected).is_equal([1])
		_controller.selection.set_ids(PackedInt32Array([30, 2, 9]))
		_tap(_camera.world_to_screen(GROUND))
		assert_array(_sent).has_size(2)
		_assert_attack_move(_sent[1], [2, 9, 30], 20016, 21516)
		assert_array(_controller.selection.selected).is_equal([2, 9, 30])  # Ordering keeps it.


func test_tap_an_enemy_with_a_selection_attack_moves_to_it_and_without_one_does_nothing() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_camera.centre_on(Vector2(2208, 672))
		var off_centre: Vector2 = _layer.unit_screen_position(30) - Vector2(UiScale.dp(20), 0)
		_tap(off_centre)
		assert_array(_sent).is_empty()
		assert_array(_controller.selection.selected).is_empty()
		_controller.selection.set_ids(PackedInt32Array([2, 1]))
		_tap(off_centre)  # Not the tap point: the enemy's own position.
		assert_array(_sent).has_size(1)
		_assert_attack_move(_sent[0], [1, 2], 34500, 10500)
		assert_array(_controller.selection.selected).is_equal([1, 2])
		_double_tap(off_centre)  # An enemy is never selected by type: two taps, two orders.
		assert_array(_sent).has_size(3)
		_assert_attack_move(_sent[2], [1, 2], 34500, 10500)
		assert_array(_controller.selection.selected).is_equal([1, 2])


func test_double_tap_a_tank_selects_all_30_when_all_are_on_screen() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_double_tap(_layer.unit_screen_position(0))
		assert_array(_controller.selection.selected).is_equal(range(1, 31))
		_double_tap(_camera.world_to_screen(GROUND))  # On ground it is a tap, twice.
		assert_array(_sent).has_size(2)
		_assert_attack_move(_sent[1], range(1, 31), 20016, 21516)


func test_double_tap_after_panning_half_the_block_away_selects_only_the_visible_tanks() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		# Pan so the view starts at world x 784: columns 0-2 (x 544, 640, 736) leave, 3-5 stay.
		var view: Vector2 = get_viewport().get_visible_rect().size
		_pan(Vector2(CAMERA_START.x - 784.0 - view.x * 0.5, 0.0))
		_double_tap(_layer.unit_screen_position(3))  # Tank 4, column 3 of row 0.
		var visible_columns: Array = [4, 5, 6, 10, 11, 12, 16, 17, 18, 22, 23, 24, 28, 29, 30]
		assert_array(_controller.selection.selected).is_equal(visible_columns)
		# Pan up so the view ends at world y 1424: block rows 3 and 4 (y 1472, 1568) leave.
		_pan(Vector2(0.0, view.y * 0.5 - 48.0))
		_double_tap(_layer.unit_screen_position(3))
		assert_array(_controller.selection.selected).is_equal([4, 5, 6, 10, 11, 12, 16, 17, 18])


func test_double_tap_selects_own_units_of_the_tapped_type_only() -> void:
	var layer: UnitLayer = auto_free(TwoTypeLayer.new())
	_controller.unit_layer = layer
	var e: GestureEvent = GestureEvent.new(GestureEvent.Kind.DOUBLE_TAP)
	e.position = Vector2(100, 300)
	_controller.handle_gesture(e)
	assert_array(_controller.selection.selected).is_equal([1, 3])  # Not 2 (type 1), not 4 (enemy).
	e.position = Vector2(300, 300)
	_controller.handle_gesture(e)
	assert_array(_controller.selection.selected).is_equal([2])
	e.position = Vector2(2, 300)  # Unit 5, cut by the screen edge: the tapped unit counts.
	_controller.handle_gesture(e)
	assert_array(_controller.selection.selected).is_equal([1, 3, 5])


func test_a_long_press_drag_selects_exactly_the_6_tanks_in_the_box_and_buzzes_once() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_buzzes.clear()
		_controller.selection.set_ids(PackedInt32Array([20]))
		var first_row: Rect2 = Rect2(_layer.unit_screen_position(0), Vector2.ZERO)
		first_row = first_row.expand(_layer.unit_screen_position(5)).grow(30.0)  # Tanks 1-6.
		_box(first_row.position, first_row.end)
		assert_array(_controller.selection.selected).is_equal([1, 2, 3, 4, 5, 6])
		assert_array(_buzzes).is_equal([15])  # Through TouchInput, once.
		assert_array(_sent).is_empty()
		_box(Vector2(80, 300), Vector2(300, 500))  # Left of the block: no tank in it.
		assert_array(_controller.selection.selected).is_empty()
		assert_array(_changes.back()).is_empty()


func test_the_ordered_tanks_stand_idle_on_distinct_slots_around_the_point_after_450_ticks() -> void:
	assert_bool(_default_sink == CommandQueue.submit).is_true()  # The sink the game ships with.
	_controller.command_sink = _default_sink
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_double_tap(_layer.unit_screen_position(0))
		_tap(_camera.world_to_screen(GROUND))
		_runner.run_ticks(450)
		var world: World = _runner.world
		var spots: Array[Vector2i] = []
		for row: int in 30:
			assert_int(world.order[row]).is_equal(World.Order.IDLE)
			spots.append(Vector2i(world.pos_x[row], world.pos_y[row]))
			# The nearest 30 slots of a 1200 lattice reach sqrt(10) * 1200 = 3795 milli.
			assert_float(Vector2(spots[row]).distance_to(Vector2(20016, 21516))).is_less(3800.0)
		for a: int in 30:
			for b: int in range(a + 1, 30):
				assert_float(Vector2(spots[a]).distance_to(Vector2(spots[b]))).is_greater(1199.0)
		assert_int(world.pos_x[30]).is_equal(34500)  # The red tanks were not ordered.
		assert_int(world.order[30]).is_equal(World.Order.IDLE)


func test_a_selected_tank_that_dies_leaves_the_selection_and_the_rings_in_the_same_frame() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_controller.selection.set_ids(PackedInt32Array([3, 5, 7]))
		assert_array(_ringed_ids()).is_equal([3, 5, 7])
		_changes.clear()
		_runner.world.hp[2] = 0  # Tank 3 dies in the next tick.
		_runner.run_ticks(1)  # No frame runs after it: the handler works inside `ticked`.
		assert_array(_controller.selection.selected).is_equal([5, 7])
		assert_array(_changes).has_size(1)  # One change for the removal, not one per consumer.
		assert_array(_changes[0]).is_equal([5, 7])
		assert_int(_layer.rig_count()).is_equal(39)
		assert_array(_ringed_ids()).is_equal([5, 7])
		_controller.selection.assign_group(1)
		_runner.world.hp[3] = 0  # Tank 5 is now row 3.
		_runner.run_ticks(1)
		assert_array(_controller.selection.selected).is_equal([7])
		assert_array(_controller.selection.group(1)).is_equal([7])
		assert_array(_ringed_ids()).is_equal([7])
		assert_array(_sent).is_empty()  # A death orders nothing.


## Only DIED records count, and they are read from the published snapshot: the World is swapped for
## an empty one and the events are written into the snapshot (SYNC allows both in a test).
func test_the_death_handling_reads_the_died_records_of_the_snapshot_and_not_the_world() -> void:
	await _fresh_match(&"desktop")
	_runner.run_ticks(1)
	_controller.selection.set_ids(PackedInt32Array([3, 5, 7]))
	_runner.world = World.new()
	var records: PackedInt32Array = PackedInt32Array()
	for record: Array in [
		[World.Event.DIED, 5],
		[World.Event.SHOT, 7],  # A shot names a unit too, and kills nothing.
		[World.Event.DIED, 3],
		[World.Event.SPAWNED, 7],
	]:
		records.append_array(PackedInt32Array(record + [0, 0, 0, 1, 0, 0]))
	assert_int(records.size()).is_equal(4 * World.EVENT_STRIDE)
	_runner.snapshot.events = records
	_changes.clear()
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_array(_controller.selection.selected).is_equal([7])
	assert_array(_changes).has_size(1)
	_runner.snapshot.events = PackedInt32Array()
	_runner.ticked.emit(_runner.snapshot.tick)  # A tick with no events changes nothing.
	assert_array(_controller.selection.selected).is_equal([7])
	assert_array(_changes).has_size(1)
	_controller.selection.set_ids(PackedInt32Array([3, 7]))  # Unit 3 died in an earlier tick.
	_runner.ticked.emit(_runner.snapshot.tick)  # Only this tick's events count.
	assert_array(_controller.selection.selected).is_equal([3, 7])


func test_all_army_reads_the_snapshot_and_never_the_world() -> void:
	await _fresh_match(&"android_6in")
	_runner.run_ticks(1)
	_runner.world = World.new()  # Test-only: an empty World where the match's was.
	_controller.select_all_army()
	assert_array(_controller.selection.selected).is_equal(range(1, 31))
	_runner.snapshot.type_speed[0] = 0  # Every tank becomes a wall in the snapshot alone.
	_controller.select_all_army()
	assert_array(_controller.selection.selected).is_empty()


## Unit ids are ascending and never reused, so after a death a row number is no longer the id: "All
## army" must take the ids from the snapshot's unit_id column.
func test_all_army_after_a_death_selects_the_surviving_ids_and_not_the_row_numbers() -> void:
	await _fresh_match(&"android_6in")
	_runner.world.hp[2] = 0  # Tank 3 dies in the next tick; the tanks after it move up one row.
	_runner.run_ticks(1)
	_controller.select_all_army()
	var survivors: Array[int] = []
	for id: int in range(1, 31):
		if id != 3:
			survivors.append(id)
	assert_array(_controller.selection.selected).has_size(29)
	assert_array(_controller.selection.selected).is_equal(survivors)


## A restart publishes a new snapshot without `ticked`, so a snapshot kept from the last tick is
## already the old match's.
func test_all_army_reads_the_snapshot_of_a_restarted_match_before_its_first_tick() -> void:
	await _fresh_match(&"desktop")
	_runner.run_ticks(1)
	_runner.start()
	_runner.snapshot.type_speed[0] = 0  # Only the restart's snapshot says every tank is a wall.
	_controller.select_all_army()
	assert_array(_controller.selection.selected).is_empty()


func _assert_attack_move(command: Command, ids: Array, x: int, y: int) -> void:
	assert_int(command.type).is_equal(Command.Type.ATTACK_MOVE)
	assert_int(command.player_id).is_equal(1)
	assert_int(command.tick).is_equal(-1)  # MatchRunner stamps tick and sequence.
	assert_int(command.sequence).is_equal(0)
	assert_array(command.unit_ids).is_equal(ids)
	assert_int(command.target_x).is_equal(x)
	assert_int(command.target_y).is_equal(y)


## A new match at `profile`'s screen size: tanks in their block, camera at the start, nothing
## selected or sent.
func _fresh_match(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	_runner.start()
	await await_idle_frame()  # The layer builds the new rigs, TouchInput reads the new dp.
	_camera.centre_on(CAMERA_START)
	_controller.selection.clear()
	_sent.clear()
	_changes.clear()


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2, hold_ms: int = 50) -> void:
	_touch_at(at, hold_ms)
	_now_ms += 1000


func _double_tap(at: Vector2) -> void:
	_touch_at(at)
	_now_ms += 100
	_touch_at(at)
	_now_ms += 1000


func _touch_at(at: Vector2, hold_ms: int = 50) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += hold_ms
	_touch._process(0.0)  # The frame that sees a hold.
	TouchEvents.release(get_viewport(), 0, at)


## Holds 300 ms at `from` (the long-press), drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += 300
	_touch._process(0.0)  # The frame that sees the hold.
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000


## One finger drags the map by `by` base px, which moves the camera the other way.
func _pan(by: Vector2) -> void:
	var from: Vector2 = Vector2(get_viewport().get_visible_rect().size.x - 60.0, 400.0)
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, from + by, by)
	TouchEvents.release(get_viewport(), 0, from + by)


## The ids of the rigs whose Ring shows, in row order.
func _ringed_ids() -> Array[int]:
	var ids: Array[int] = []
	for rig: Node in _layer.get_children():
		var ring: Node2D = rig.get_node_or_null("Ring")
		if ring != null and ring.visible:
			ids.append(int(String(rig.name).trim_prefix("Unit")))
	return ids
