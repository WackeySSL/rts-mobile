extends GdUnitTestSuite
## PlayerController in the main scene (ADR 0004 section 5). Fingers enter as window-px touch events
## with a fake clock, through the real TouchInput and recognizer, and the Commands are caught at
## `command_sink`. Each flow runs at 1280x720 (desktop), 2400x1080 (android_6in, 20:9 phone) and
## 2048x1536 (web_tablet, 4:3). Under the 2:1 projection (P117) the 6 x 5 block of tanks is a
## diamond: tank n is column c = (n - 1) % 6 and row r = (n - 1) / 6, at px x = -320 + 48 (c - r)
## and y = 432 + 24 (c + r), so tank 1 is the top corner and has no unit above it. Red tank 31
## stands at px (768, 720), milli (34500, 10500), the top corner of the red block.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TwoTypeLayer: GDScript = preload("res://tests/input/support/two_type_layer.gd")
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
const CAMERA_START: Vector2 = Vector2(-288, 544)
## Where a pan's finger goes down: left of the build sidebar at every size (its edge is at 1009 or
## more), with room to drag 888 px to the left.
const PAN_FROM_X: float = 900.0
## World px with no unit near it, past the tank block's upper right edge and clear of the build
## sidebar and the selection panel at every size (P85): milli (10000, 15000). The nearest tank is
## 102 px away.
const GROUND: Vector2 = Vector2(-160, 400)
const GROUND_MILLI: Vector2i = Vector2i(10000, 15000)
## The red top-corner tank 31, and the way a tap reaches a top-corner tank alone: straight above it.
const RED_TANK: Vector2 = Vector2(768, 720)

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
		_tap(_layer.unit_screen_position(0) - Vector2(0, UiScale.dp(40)))  # Outside the hit area.
		assert_array(_controller.selection.selected).is_empty()
		_tap(_layer.unit_screen_position(0) - Vector2(0, UiScale.dp(20)))  # Above the top corner.
		assert_array(_controller.selection.selected).is_equal([1])
		assert_array(_changes).has_size(1)
		assert_array(_changes[0]).is_equal([1])
		_tap(_layer.unit_screen_position(1))
		assert_array(_controller.selection.selected).is_equal([2])
		assert_array(_sent).is_empty()  # Selecting orders nothing.


func test_tap_ground_with_a_selection_sends_one_move_and_without_one_nothing() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_tap(_camera.world_to_screen(GROUND))
		assert_array(_sent).is_empty()
		_tap(_layer.unit_screen_position(0))  # Select tank 1, then send it.
		_tap(_camera.world_to_screen(GROUND), 300)  # Held: LONG_PRESS, BOX_CANCEL, then a TAP.
		assert_array(_sent).has_size(1)
		_assert_move(_sent[0], [1], GROUND_MILLI.x, GROUND_MILLI.y)
		assert_array(_controller.selection.selected).is_equal([1])
		_controller.selection.set_ids(PackedInt32Array([30, 2, 9]))
		_tap(_camera.world_to_screen(GROUND))
		assert_array(_sent).has_size(2)
		_assert_move(_sent[1], [2, 9, 30], GROUND_MILLI.x, GROUND_MILLI.y)
		assert_array(_controller.selection.selected).is_equal([2, 9, 30])  # Ordering keeps it.


## The order names the enemy by its id, so the sim follows it when it moves, and the diamond sits on
## the enemy and not on the finger (the tap is 20 dp above it).
func test_tap_an_enemy_with_a_selection_sends_one_attack_and_without_one_does_nothing() -> void:
	var markers: MoveMarkerLayer = _main.get_node("MarkerLayer")
	markers.clock = _touch.clock  # One fake clock: a mark of an earlier profile has expired.
	# The tap on an enemy is the subject, not the fog: red tank 31 is hidden at the start, and a tap
	# on a hidden enemy is a ground tap. Picking under fog is proven in the two hidden-enemy cases
	# below (test_a_tap_on_a_tank_the_fog_hides_... and its local-player-2 twin).
	_layer.reveal_enemies = true
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		markers._process(0.0)
		_camera.centre_on(RED_TANK)
		var off_centre: Vector2 = _layer.unit_screen_position(30) - Vector2(0, UiScale.dp(20))
		_tap(off_centre)
		assert_array(_sent).is_empty()
		assert_array(_controller.selection.selected).is_empty()
		assert_int(markers.active_count()).is_equal(0)
		_controller.selection.set_ids(PackedInt32Array([2, 1]))
		_tap(off_centre)
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], [1, 2], 31)
		assert_array(_controller.selection.selected).is_equal([1, 2])
		var marks: Array[MoveMarkerLayer.Mark] = _shown_marks(markers)
		assert_array(marks).has_size(1)
		assert_bool(marks[0].diamond).is_true()
		assert_vector(marks[0].position).is_equal_approx(RED_TANK, Vector2(0.05, 0.05))
		_double_tap(off_centre)  # An enemy is never selected by type: two taps, two orders.
		assert_array(_sent).has_size(3)
		_assert_attack(_sent[1], [1, 2], 31)
		_assert_attack(_sent[2], [1, 2], 31)
		assert_array(_controller.selection.selected).is_equal([1, 2])


## Red tank 31 starts in the dark: a light tank sees 7 tiles and the nearest blue tank is about 16
## away. A hidden enemy is not pickable (P47p), so a tap within its hit area is a tap on the ground:
## a MOVE to the point tapped with the ground-tap marker (chevrons, no diamond), never an ATTACK. A
## double-tap on it is two such taps. Once a blue tank sees the tank, the same tap attacks it.
func test_a_tap_on_a_tank_the_fog_hides_is_a_ground_tap_until_a_blue_tank_sees_it() -> void:
	await _check_hidden_enemy(1, 31, [2, 1], 31, Vector2i(21000, 24500))  # 5 tiles from tank 30


## The same for the human who plays the red side: blue tank 1 is hidden from red, which sees it only
## when red tank 40 stands 5 tiles from it.
func test_the_same_for_local_player_2_with_a_hidden_blue_tank() -> void:
	var red_side: ScenarioDef = _runner.scenario.duplicate() as ScenarioDef  # Not the shared one.
	red_side.local_player = 2
	_runner.scenario = red_side
	await _check_hidden_enemy(2, 1, [32, 31], 40, Vector2i(8500, 13500))


func test_double_tap_a_tank_selects_all_30_when_all_are_on_screen() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_double_tap(_layer.unit_screen_position(0))
		assert_array(_controller.selection.selected).is_equal(range(1, 31))
		_double_tap(_camera.world_to_screen(GROUND))  # On ground it is a tap, twice.
		assert_array(_sent).has_size(2)
		_assert_move(_sent[1], range(1, 31), GROUND_MILLI.x, GROUND_MILLI.y)


func test_double_tap_after_panning_half_the_block_away_selects_only_the_visible_tanks() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		# Pan so the view starts at world x -200: tanks 1-3 leave, and so does every tank with
		# c - r under 3 (x = -320 + 48 (c - r), so -224 is off and -176 is on): 4, 5, 6, 11, 12, 18 stay.
		var view: Vector2 = get_viewport().get_visible_rect().size
		_pan(Vector2(CAMERA_START.x + 200.0 - view.x * 0.5, 0.0))
		_double_tap(_layer.unit_screen_position(3))  # Tank 4, column 3 of row 0.
		assert_array(_controller.selection.selected).is_equal([4, 5, 6, 11, 12, 18])
		# Pan 48 px more: the view starts at world x -152, so c - r under 4 leaves too, tank 4 among
		# them: 5, 6 and 12 stay, and the tap on tank 6 selects those three.
		_pan(Vector2(-48.0, 0.0))
		_double_tap(_layer.unit_screen_position(5))  # Tank 6.
		assert_array(_controller.selection.selected).is_equal([5, 6, 12])


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
		# The top of the diamond, world (-440, 410) to (-200, 490): the tanks with c + r <= 2, which
		# stand at y 432 to 480 (the next ones are at 504).
		var top_left: Vector2 = _camera.world_to_screen(Vector2(-440, 410))
		var bottom_right: Vector2 = _camera.world_to_screen(Vector2(-200, 490))
		_box(top_left, bottom_right)
		assert_array(_controller.selection.selected).is_equal([1, 2, 3, 7, 8, 13])
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
			# The nearest 30 slots of a 1200 lattice reach sqrt(10) * 1200 = 3795 milli; the point
			# is near the block (P85), so the last tanks to arrive settle up to ~100 milli further out.
			assert_float(Vector2(spots[row]).distance_to(Vector2(GROUND_MILLI))).is_less(3900.0)
		for a: int in 30:
			for b: int in range(a + 1, 30):
				# P39b: separation settles tanks just under their radii sum (800), not on the lattice;
				# the bound is 90% of that sum, 720 milli (ADR 0008 section 4).
				assert_float(Vector2(spots[a]).distance_to(Vector2(spots[b]))).is_greater_equal(
					720.0
				)
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
	assert_int(_runner.world.unit_count()).is_equal(0)
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
	assert_int(_runner.world.unit_count()).is_equal(0)
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


func _assert_attack(command: Command, ids: Array, target_id: int, player: int = 1) -> void:
	assert_int(command.type).is_equal(Command.Type.ATTACK)
	assert_int(command.player_id).is_equal(player)
	assert_int(command.tick).is_equal(-1)  # MatchRunner stamps tick and sequence.
	assert_int(command.sequence).is_equal(0)
	assert_array(command.unit_ids).is_equal(ids)
	assert_int(command.target_id).is_equal(target_id)


func _shown_marks(markers: MoveMarkerLayer) -> Array[MoveMarkerLayer.Mark]:
	var shown: Array[MoveMarkerLayer.Mark] = []
	for mark: MoveMarkerLayer.Mark in markers.get_children():
		if mark.visible:
			shown.append(mark)
	return shown


## Puts the unit with id `id` at `milli` and plays the ticks that settle it: two, so the previous
## position is this one too and the rig stands here at alpha 0, and at least the fog period, so a
## fog update has seen the move.
func _stand_at(id: int, milli: Vector2i) -> void:
	var world: World = _runner.world
	var row: int = world.index_of(id)
	world.pos_x[row] = milli.x
	world.pos_y[row] = milli.y
	_runner.run_ticks(maxi(world.fog_period_ticks, 2))
	_layer._process(0.0)  # Brings the rigs to the snapshot.


func _assert_move(command: Command, ids: Array, x: int, y: int, player: int = 1) -> void:
	assert_int(command.type).is_equal(Command.Type.MOVE)
	assert_int(command.player_id).is_equal(player)
	assert_int(command.tick).is_equal(-1)  # MatchRunner stamps tick and sequence.
	assert_int(command.sequence).is_equal(0)
	assert_array(command.unit_ids).is_equal(ids)
	assert_int(command.target_x).is_equal(x)
	assert_int(command.target_y).is_equal(y)


## The story of one hidden enemy at the three screen sizes. `enemy_id` starts outside the sight of
## `player`'s units; `ids` is the selection. A tap 20 dp above the enemy's centre is a MOVE to
## that ground point, with chevrons only; so is a double-tap (two MOVEs); with nothing selected it
## does nothing. Then the unit `mover_id` (the enemy itself, or a unit of the other side) is stood
## at `mover_milli`, 5 tiles from its opponent, and the fog is played until the real mask lets
## `player` see the enemy: the same tap sends one ATTACK and shows the diamond on the enemy.
func _check_hidden_enemy(
	player: int, enemy_id: int, ids: Array[int], mover_id: int, mover_milli: Vector2i
) -> void:
	var markers: MoveMarkerLayer = _main.get_node("MarkerLayer")
	markers.clock = _touch.clock  # One fake clock: a mark of an earlier profile has expired.
	var sorted_ids: Array[int] = ids.duplicate()
	sorted_ids.sort()
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		markers._process(0.0)
		var world: World = _runner.world
		var row: int = world.index_of(enemy_id)
		var rig: Node2D = _layer.rig(row)
		assert_bool(_layer.is_shown(row)).is_false()
		_camera.centre_on(rig.global_position)
		var off_centre: Vector2 = _layer.unit_screen_position(row) - Vector2(0, UiScale.dp(20))
		# The point tapped in world px and milli, from the tap and the camera alone.
		var ground: Vector2 = rig.global_position - Vector2(0.0, UiScale.dp(20) / _camera.zoom.x)
		var at_x: int = IsoProjection.px_to_ground(ground).x
		var at_y: int = IsoProjection.px_to_ground(ground).y
		_tap(off_centre)  # Nothing selected: a tap on nothing.
		assert_array(_sent).is_empty()
		assert_int(markers.active_count()).is_equal(0)
		_controller.selection.set_ids(PackedInt32Array(ids))
		_changes.clear()
		_tap(off_centre)
		assert_array(_sent).has_size(1)
		_assert_move(_sent[0], sorted_ids, at_x, at_y, player)
		var marks: Array[MoveMarkerLayer.Mark] = _shown_marks(markers)
		assert_array(marks).has_size(1)
		assert_bool(marks[0].diamond).is_false()  # Chevrons: the ground-tap marker.
		assert_bool(marks[0].get_child(0).visible).is_true()
		assert_vector(marks[0].position).is_equal_approx(ground, Vector2(0.1, 0.1))
		_double_tap(off_centre)  # Nothing to select by type here: two ground taps, two moves.
		assert_array(_sent).has_size(3)
		_assert_move(_sent[1], sorted_ids, at_x, at_y, player)
		_assert_move(_sent[2], sorted_ids, at_x, at_y, player)
		assert_array(_controller.selection.selected).is_equal(sorted_ids)
		assert_array(_changes).is_empty()  # No tap changed the selection.
		# The two sides come within 7 tiles of each other; the fog is the sim's own.
		_stand_at(mover_id, mover_milli)
		var snap: MatchSnapshot = _runner.snapshot
		var cell: int = snap.cell_of(snap.pos_x[row], snap.pos_y[row])
		assert_bool(snap.fog.is_visible(player, cell)).is_true()
		assert_bool(_layer.is_shown(row)).is_true()
		_sent.clear()
		markers._process(0.0)  # The chevrons are old by now.
		assert_int(markers.active_count()).is_equal(0)
		_camera.centre_on(rig.global_position)
		_tap(_layer.unit_screen_position(row) - Vector2(0, UiScale.dp(20)))
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], sorted_ids, enemy_id, player)
		marks = _shown_marks(markers)
		assert_array(marks).has_size(1)
		assert_bool(marks[0].diamond).is_true()
		assert_vector(marks[0].position).is_equal_approx(rig.global_position, Vector2(0.05, 0.05))


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
	var from: Vector2 = Vector2(PAN_FROM_X, 400.0)
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, from + by, by)
	TouchEvents.release(get_viewport(), 0, from + by)


## The ids of the rigs whose Ring shows, in row order.
func _ringed_ids() -> Array[int]:
	var ids: Array[int] = []
	for rig: Node in _layer.world_sort.get_children():
		var ring: Node2D = rig.get_node_or_null("Ring")
		if ring != null and ring.visible:
			ids.append(int(String(rig.name).trim_prefix("Unit")))
	return ids
