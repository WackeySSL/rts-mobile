extends GdUnitTestSuite
## The enemy tap of PlayerController (P43b) in the main scene, beyond the basic ATTACK of
## test_player_controller: it reads the snapshot and never the World, names the enemy by its id and
## not its row, uses the local player's number, marks the enemy where it is drawn, and reaches the
## sim through the real CommandQueue.
## Fingers enter as window-px touch events through the real TouchInput with a fake clock, at
## 1280x720 (desktop), 2400x1080 (android_6in, 20:9 phone) and 2048x1536 (web_tablet, 4:3). Under
## the 2:1 projection (P117) blue tank n is row n - 1 at px (-320 + 48 (c - r), 432 + 24 (c + r)),
## c = (n - 1) % 6 and r = (n - 1) / 6, so tank 1 is the top corner of the block and a tap straight
## above a top-corner tank reaches it alone.
## Fog (authoring rule of P46b and P47p): red tank 31 starts at milli (34500, 10500), far outside
## every blue sight disc, where a later fog rule would drop an order on it and leave a tap on it
## unpicked. So each case first stands the unit it taps inside the sight of a unit of the other
## side (`_stand_at`, checked with the real FogGrid mask by `_assert_sees`), and needs no
## `reveal_enemies`.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
## Where the cases stand red tank 31: 5 tiles east of blue tank 30 (milli (16000, 24500)) and about
## 14 tiles from blue tank 1. Its px are the projection of its milli.
const RED_31_MILLI: Vector2i = Vector2i(21000, 24500)
const RED_31: Vector2 = Vector2(-112, 728)
## Where the local-player-2 case stands red tank 40: 5 tiles north of blue tank 1.
const RED_40_MILLI: Vector2i = Vector2i(8500, 13500)
const BLUE_1: Vector2 = Vector2(-320, 432)
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


## The World is swapped for an empty one after the last tick, so a read of it gives rows that are
## not there. The Command and the diamond must come from the snapshot and the drawn rigs alone.
func test_the_enemy_tap_reads_the_snapshot_and_never_the_world() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_stand_at(31, RED_31_MILLI)
		_assert_sees(30, 31)
		_runner.world = World.new()  # Test-only: an empty World where the match's was.
		assert_int(_runner.world.unit_count()).is_equal(0)
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
		_runner.world.hp[2] = 0  # Tank 3 dies in the first tick of the move below.
		_stand_at(31, RED_31_MILLI)
		_assert_sees(30, 31)
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
		_stand_at(40, RED_40_MILLI)
		_assert_sees(40, 1)  # Red tank 40 sees blue tank 1, the tapped enemy.
		_controller.selection.set_ids(PackedInt32Array([32, 31]))
		_camera.centre_on(BLUE_1)
		_tap(_off_centre(0))
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], 2, [31, 32], 1)
		_assert_one_diamond_at(BLUE_1)
		assert_array(_controller.selection.selected).is_equal([31, 32])  # Blue 1 is not selected.


## Through the real queue and the sim: the ATTACK is applied (not dropped) and the tank drives at
## the red tank, which stands about 14 tiles away. A blue tank beside it (not the one ordered) sees
## it, so the order stays valid once the sim needs vision for an ATTACK (P46b).
func test_the_attack_reaches_the_sim_and_the_tank_drives_at_the_enemy() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_stand_at(31, RED_31_MILLI)
		_assert_sees(30, 31)
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


## The diamond marks the unit where it is drawn. The paused runner leaves alpha at 0, so a rig
## stands where the unit was one tick ago: a moving enemy is drawn a step behind the position the
## snapshot holds, and a diamond at that position would sit off the tank the player tapped.
func test_the_diamond_marks_a_moving_enemy_where_it_is_drawn_and_not_where_the_sim_holds_it(
) -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		_stand_at(31, RED_31_MILLI)
		CommandQueue.submit(Command.move(2, PackedInt32Array([31]), 26000, 24500))  # Red drives east.
		_runner.run_ticks(6)
		_layer._process(0.0)
		_assert_sees(30, 31)  # Still seen after the move.
		var snap: MatchSnapshot = _runner.snapshot
		var held_px: Vector2 = IsoProjection.ground_to_px(snap.pos_x[30], snap.pos_y[30])
		var drawn_px: Vector2 = _camera.screen_to_world(_layer.unit_screen_position(30))
		assert_float(held_px.x).is_greater(RED_31.x + 5.0)  # It drove east, 5 px at least.
		assert_float(held_px.distance_to(drawn_px)).is_greater(1.0)  # A step, well above TOL.
		_controller.selection.set_ids(PackedInt32Array([1]))
		_camera.centre_on(drawn_px)
		_tap(_off_centre(30))
		assert_array(_sent).has_size(1)
		_assert_attack(_sent[0], 1, [1], 31)
		_assert_one_diamond_at(drawn_px)


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


## Puts the unit with id `id`, which has no order, at `milli` and plays the ticks that settle it:
## two, so the snapshot's previous position is this one too and the rig stands here at alpha 0, and
## at least the fog period, so a fog update of either side has seen the move. A write to the World
## made before the call (the hit points of case 2) takes effect in the first of these ticks.
func _stand_at(id: int, milli: Vector2i) -> void:
	var world: World = _runner.world
	var row: int = world.index_of(id)
	world.pos_x[row] = milli.x
	world.pos_y[row] = milli.y
	_runner.run_ticks(maxi(world.fog_period_ticks, 2))
	_layer._process(0.0)  # Brings the rigs to the snapshot.


## The authoring rule of the fog (P46b): the unit `seen_id` stands inside the sight disc of the unit
## `viewer_id`, of the other side, as FogGrid stamps it (tile centre to tile centre). It reads the
## ids in the World as the last tick left it.
func _assert_sees(viewer_id: int, seen_id: int) -> void:
	var world: World = _runner.world
	var viewer: int = world.index_of(viewer_id)
	var seen: int = world.index_of(seen_id)
	var player: int = world.owner[viewer]
	assert_int(world.owner[seen]).is_not_equal(player)
	var grid: FogGrid = FogGrid.new()
	grid.configure(world.map_cols, world.map_rows, world.player_count)
	var mask: int = grid.add_mask(world.type_sight[world.type_index[viewer]])
	grid.stamp(player, _cell_of(world, viewer), mask, 1)
	assert_bool(grid.is_visible(player, _cell_of(world, seen))).is_true()


@warning_ignore("integer_division")
func _cell_of(world: World, row: int) -> int:
	var tile_x: int = world.pos_x[row] / World.MILLI_PER_TILE
	var tile_y: int = world.pos_y[row] / World.MILLI_PER_TILE
	return tile_y * world.map_cols + tile_x


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


## 20 dp above the centre of row `row`: the tap point is not the enemy's own position, and no
## other unit is near it (a top-corner tank has none above it).
func _off_centre(row: int) -> Vector2:
	return _layer.unit_screen_position(row) - Vector2(0, UiScale.dp(20))


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	_touch._process(0.0)  # The frame that sees a hold.
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
