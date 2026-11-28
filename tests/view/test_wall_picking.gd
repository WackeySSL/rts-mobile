extends GdUnitTestSuite
## Picking with raised rock walls (ADR 0053 amendment A8, plan P656d3) on the main scene with the
## flag on and PLACEHOLDER wall pieces (`wall_rig.gd`): a tap at a hidden unit's centre selects it,
## and a box over a wall selects the hidden own unit (the Picker reads lifted centres, nothing
## else); a ground tap on a wall's top or face is a Command at the wall's cell (move, the strike's
## aim, the rally point); a tap off the walls is the flat inverse as before; placement keeps the
## flat projection and its ghost stays at z 60.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/wall_rig.gd")

var _main: Node2D
var _runner: MatchRunner
var _walls: WallLayer
var _layer: UnitLayer
var _camera: RtsCamera
var _controller: PlayerController
var _sent: Array[Command] = []
var _wall: int = -1  ## A wall cell whose front neighbours are open ground.
var _unit_row: int = 0


func before_test() -> void:
	MenuRig.begin()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_walls = _main.get_node("WallLayer") as WallLayer
	_walls.loader = Callable(self, "_pieces")
	_walls.walls_enabled = true
	add_child(_main)
	await await_idle_frame()
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true
	_layer = _main.get_node("UnitLayer")
	_camera = _main.get_node("Camera")
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_wall = _find_wall()
	assert_int(_wall).is_greater_equal(0)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_the_main_scene_wires_the_walls_into_the_unit_layer_and_the_controller() -> void:
	assert_object(_layer.walls).is_same(_walls)
	assert_object(_controller.walls).is_same(_walls)
	assert_int(_walls.row_count()).is_greater(0)  # The walls stand: the placeholder pieces baked.


func test_a_tap_at_a_hidden_units_centre_selects_it_and_a_box_over_a_wall_takes_it() -> void:
	var row: int = _put_unit_behind_the_wall()
	var snap: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(snap, UiScale.dp(24.0))
	var at: int = snap.ids.find(_runner.snapshot.unit_id[row])
	assert_int(at).is_greater_equal(0)
	var rig: UnitLayer.Rig = _layer.rig(row) as UnitLayer.Rig
	assert_bool(rig.silhouette.on).is_true()  # It shows as a silhouette, and a tap there picks it.
	var owner_id: int = _runner.snapshot.owner[row]
	assert_int(Picker.pick(snap, snap.screen_pos[at], owner_id, false)).is_equal(at)
	var out: PackedInt32Array = PackedInt32Array()
	var box: Rect2 = Rect2(snap.screen_pos[at] - Vector2(20, 20), Vector2(40, 40))
	Picker.own_in_rect(snap, box, owner_id, out)
	assert_array(out).contains([_runner.snapshot.unit_id[row]])


@warning_ignore("integer_division")
func test_a_ground_tap_on_a_wall_top_or_face_moves_to_the_walls_cell() -> void:
	var cell: Vector2i = Vector2i(_wall % _cols(), _wall / _cols())
	var want: Vector2i = Vector2i(cell.x * 1000 + 500, cell.y * 1000 + 500)
	_controller.selection.set_ids(PackedInt32Array([_runner.snapshot.unit_id[_unit_row]]))
	var centre: Vector2 = IsoProjection.cell_centre_px(cell.x, cell.y)
	for world: Vector2 in [centre + Vector2(0.0, -32.0), centre + Vector2(10.0, 5.0)]:
		_sent.clear()
		_controller._ground_tap(_camera.world_to_screen(world))
		assert_int(_sent.size()).is_equal(1)
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		assert_that(Vector2i(_sent[0].target_x, _sent[0].target_y)).is_equal(want)


func test_a_ground_tap_off_the_walls_is_the_flat_inverse_as_before() -> void:
	_controller.selection.set_ids(PackedInt32Array([_runner.snapshot.unit_id[_unit_row]]))
	var open: Vector2 = _open_ground()
	_controller._ground_tap(_camera.world_to_screen(open))
	assert_int(_sent.size()).is_equal(1)
	var flat: Vector2i = IsoProjection.px_to_ground(open)
	assert_that(Vector2i(_sent[0].target_x, _sent[0].target_y)).is_equal(flat)


@warning_ignore("integer_division")
func test_the_strikes_aim_takes_a_wall_top_as_the_walls_cell() -> void:
	var aim: StrikeAim = _main.get_node("StrikeAim") as StrikeAim
	aim.active = true
	var cell: Vector2i = Vector2i(_wall % _cols(), _wall / _cols())
	var top: Vector2 = IsoProjection.cell_centre_px(cell.x, cell.y) + Vector2(0.0, -32.0)
	var tap: GestureEvent = GestureEvent.new()
	tap.kind = GestureEvent.Kind.TAP
	tap.position = _camera.world_to_screen(top)
	_controller.handle_gesture(tap)
	assert_that(aim.point).is_equal(Vector2i(cell.x * 1000 + 500, cell.y * 1000 + 500))


func test_placement_keeps_the_flat_projection_and_its_ghost_stays_at_z_60() -> void:
	var source: String = FileAccess.get_file_as_string("res://game/input/PlacementController.gd")
	assert_str(source).contains("IsoProjection.px_to_ground(world)")
	assert_str(source).not_contains("WallLayer")
	assert_str(source).not_contains("ground_at")
	assert_int((_main.get_node("GhostLayer") as Node2D).z_index).is_equal(60)


## Cells of the wall layer's map, wide.
func _cols() -> int:
	return _runner.snapshot.map_cols


## A wall cell with open ground in front (its two front neighbours are not walls) on the map.
func _find_wall() -> int:
	var cols: int = _cols()
	for cell: int in _runner.snapshot.terrain.size():
		if (
			_walls.is_wall(cell)
			and cell % cols > 0
			and cell % cols < cols - 2
			and not _walls.is_wall(cell + 1)
			and not _walls.is_wall(cell + cols)
			and not _walls.is_wall(cell + cols + 1)
		):
			return cell
	return -1


## A world px on open ground three cells from every wall, in the middle of the map's diamond.
@warning_ignore("integer_division")
func _open_ground() -> Vector2:
	var cols: int = _cols()
	for cell: int in _runner.snapshot.terrain.size():
		var col: int = cell % cols
		var row: int = cell / cols
		if col < 4 or row < 4 or col > cols - 5 or row > _runner.snapshot.map_rows - 5:
			continue
		var clear: bool = true
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				clear = clear and not _walls.is_wall(cell + dy * cols + dx)
		if clear:
			return IsoProjection.cell_centre_px(col, row)
	return Vector2.ZERO


## Moves the first own unit to stand just behind the wall (its cell up and left by one) and runs a
## frame, so the silhouette reads the cell. Returns its row.
@warning_ignore("integer_division")
func _put_unit_behind_the_wall() -> int:
	var snap: MatchSnapshot = _runner.snapshot
	var cols: int = _cols()
	var player: int = FogLayer.local_player_of(_runner)
	for row: int in snap.owner.size():
		if snap.owner[row] == player and _layer.rig(row) != null:
			_unit_row = row
			break
	var behind: Vector2i = Vector2i(_wall % cols - 1, _wall / cols)
	snap.pos_x[_unit_row] = behind.x * 1000 + 500
	snap.pos_y[_unit_row] = behind.y * 1000 + 500
	snap.prev_pos_x[_unit_row] = snap.pos_x[_unit_row]
	snap.prev_pos_y[_unit_row] = snap.pos_y[_unit_row]
	snap.tick += 1
	_layer._process(0.0)
	return _unit_row


func _pieces(_look: StringName) -> Dictionary[StringName, Image]:
	return Rig.pieces()
