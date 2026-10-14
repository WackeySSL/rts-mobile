extends GdUnitTestSuite
## UnitLayer on data/scenarios/controls_test.tres: 40 rigs in World row order, ids 1-30 blue and
## 31-40 red. Tank 1 stands at px (544, 1184), tank 2 at (640, 1184) and tank 7 at (544, 1280).
## The runner is not in the tree, so only the calls here move time: runner._process() moves the
## interpolation clock and layer._process() draws a frame. Rigs that follow deaths and spawns by
## unit id are in test_unit_layer_rows.gd.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const ART: String = "res://assets/art/svg/units/light_tank_%s.svg"
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
const BLUE: Color = Color("2F80ED")
const RED: Color = Color("E5484D")
const RING_ART: String = "res://assets/art/svg/ui/selection_ring.svg"
## The ring texture's centre-line radius in px, typed again from STYLE.md so that a wrong
## UnitLayer.RING_TEX_RADIUS_PX fails (tests/art pins the texture to the same number).
const RING_CENTRE_PX: float = 72.0
const UNITS: String = "res://assets/art/svg/units/"
const TANK_1: PackedInt32Array = [1]
const TANK_6: PackedInt32Array = [6]  ## Row 5, the east end of the block's first row.
const TANK_30: PackedInt32Array = [30]  ## Row 29, the block's south-east corner.

var _window_size_before: Vector2i
var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = BASE_SIZE
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)  # Frames come only from _render().


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_one_rig_per_unit_with_hull_team_and_turret_layers_in_draw_order() -> void:
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.get_child_count()).is_equal(40)
	for row: int in 40:
		var names: Array = _rig(row).get_children().map(func(n: Node) -> StringName: return n.name)
		assert_array(names).is_equal([&"Hull", &"Team", &"Turret"])
	assert_str(_rig(0).name).is_equal("Unit1")
	for layer: String in ["hull", "team", "turret"]:
		var texture: Texture2D = _rig(0).get_node(layer.capitalize()).texture
		assert_str(texture.resource_path).is_equal(ART % layer)


func test_team_layers_are_tinted_by_owner_and_the_other_layers_are_not() -> void:
	for row: int in 40:
		assert_that(_rig(row).get_node("Team").modulate).is_equal(BLUE if row < 30 else RED)
		assert_that(_rig(row).get_node("Hull").modulate).is_equal(Color.WHITE)
		assert_that(_rig(row).get_node("Turret").modulate).is_equal(Color.WHITE)
	assert_array(_layer.team_colors).is_equal(PackedColorArray([Color("9AA5B1"), BLUE, RED]))


func test_rigs_start_on_the_unit_positions_in_px() -> void:
	assert_that(_rig(0).position).is_equal(Vector2(544, 1184))
	assert_that(_rig(1).position).is_equal(Vector2(640, 1184))
	assert_that(_rig(6).position).is_equal(Vector2(544, 1280))
	assert_that(_rig(30).position).is_equal(Vector2(2208, 672))  # Red target, tile (34, 10).
	assert_that(_rig(39).position).is_equal(Vector2(1952, 2592))  # Red target, tile (26, 40).


func test_rig_positions_are_prev_plus_cur_minus_prev_times_alpha() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 11500, 20000))
	_runner.run_ticks(1)  # Tank 1 moves (107, 53) milli: px (544, 1184) -> (550.848, 1187.392).
	_render(0.0)
	var prev: Vector2 = Vector2(544, 1184)
	assert_that(_rig(0).position).is_equal(prev)  # alpha 0 shows the old tick.
	for alpha: float in [0.25, 0.5, 0.75]:
		_runner._process(1.0 / 60.0)
		_render(0.0)
		var expected: Vector2 = prev + (Vector2(550.848, 1187.392) - prev) * alpha
		assert_vector(_rig(0).position).is_equal_approx(expected, Vector2(0.001, 0.001))
		assert_that(_rig(1).position).is_equal(Vector2(640, 1184))  # Tank 2 stands still.


func test_frames_without_ticks_leave_every_world_array_unchanged() -> void:
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array(range(1, 11)), 20000, 30000))
	_runner.run_ticks(3)
	var before: int = _world_hash()
	for _frame: int in 8:
		_runner._process(0.004)  # 32 ms in all: under one tick.
		_layer._process(0.016)  # The hulls turn on these frames.
	assert_float(_runner.alpha()).is_greater(0.0)
	assert_int(_runner.world.tick).is_equal(3)
	assert_int(_world_hash()).is_equal(before)


func test_frames_leave_no_new_objects_alive() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 30000))
	_runner.run_ticks(1)
	_layer._process(0.016)  # The first turn.
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame: int in 20:
		_layer._process(0.016)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)


func test_a_restarted_match_gets_new_rigs_with_their_own_tint_and_heading() -> void:
	var south: Callable = func() -> void:
		CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 21500))
		_runner.run_ticks(1)
		_render(0.5)
	south.call()
	_layer.team_colors = PackedColorArray([Color("9AA5B1"), BLUE])  # Owner 2 has no colour.
	_runner.start()
	_layer._process(0.05)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.get_child_count()).is_equal(40)
	assert_that(_rig(0).get_node("Team").modulate).is_equal(BLUE)
	assert_that(_rig(30).get_node("Team").modulate).is_equal(Color("9AA5B1"))  # The neutral one.
	assert_float(_rig(0).get_node("Hull").rotation).is_equal(0.0)  # Neither heading nor aim is kept.
	south.call()
	assert_float(_rig(0).get_node("Hull").rotation).is_equal_approx(PI / 2.0, 0.001)
	await await_idle_frame()  # The old rigs are freed.


func test_the_hull_eases_toward_where_the_tank_moves_and_keeps_its_heading_when_it_stops() -> void:
	var hull: Sprite2D = _rig(29).get_node("Hull")
	# Tank 30 (row 29, at (16000, 24500)) drives 3 tiles (25 ticks) south-east on a 3-4-5 path, then
	# west (127 degrees), then east (180). It stands at the block's south-east corner, so no unit is
	# within 800 milli of the path: separation (P39b) cannot push it.
	var goals: Array[Vector2i] = [Vector2i(17800, 26900), Vector2i(14800, 26900)]
	goals.append(goals[0])
	var headings: Array[float] = [atan2(4.0, 3.0), PI, 0.0]
	for leg: int in 3:
		CommandQueue.submit(Command.attack_move(1, TANK_30, goals[leg].x, goals[leg].y))
		_runner.run_ticks(1)
		var before: float = hull.rotation
		_layer._process(0.05)  # 12 rad/s * 0.05 s = 0.6 rad.
		assert_float(absf(angle_difference(before, hull.rotation))).is_equal_approx(0.6, 0.001)
		_render(0.5)
		assert_float(hull.rotation).is_equal_approx(headings[leg], 0.001)
		_runner.run_ticks(40)
		assert_int(_runner.world.order[29]).is_equal(World.Order.IDLE)
		_render(0.5)
		assert_float(hull.rotation).is_equal_approx(headings[leg], 0.001)
		assert_float(_rig(29).get_node("Team").rotation).is_equal(hull.rotation)
		assert_float(_rig(29).get_node("Turret").rotation).is_equal(hull.rotation)


func test_the_short_last_step_onto_the_goal_does_not_turn_the_hull() -> void:
	# Tank 6 (row 5, at (16000, 18500)) drives 5.5 tiles almost due east over open ground, the same
	# vector as tank 1's Phase 1 drive. Its last tick moves (1, 1) milli, which is 45 degrees.
	CommandQueue.submit(Command.attack_move(1, TANK_6, 21521, 18540))
	for _tick: int in 50:  # 47 to arrive. Every tick is drawn, as on the phone.
		_runner.run_ticks(1)
		_layer._process(0.05)
	assert_int(_runner.world.order[5]).is_equal(World.Order.IDLE)
	assert_float(_rig(5).get_node("Hull").rotation).is_equal_approx(0.0, 0.02)


func test_unit_screen_position_is_the_rig_seen_through_the_camera() -> void:
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	assert_that(_layer.unit_screen_position(0)).is_equal(Vector2(684, 444))  # 640 + 44, 360 + 84
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(2000, 600)
	assert_that(_layer.unit_screen_position(30)).is_equal(Vector2(952, 468))  # 640 + 208 * 1.5, ...
	# The camera sees the rig's global position, so a layer that is not at the origin moves both
	# this answer and the Picker's rows by its offset.
	_layer.position = Vector2(64, 32)  # 96 px and 48 px on the screen.
	assert_that(_layer.unit_screen_position(30)).is_equal(Vector2(1048, 516))
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, 24.0)
	assert_that(pick.screen_pos[30]).is_equal(Vector2(1048, 516))


func test_a_type_without_turret_art_has_hull_and_team_only_and_still_turns() -> void:
	assert_bool(ResourceLoader.exists(UNITS + "rifle_squad_turret.svg")).is_false()
	assert_bool(ResourceLoader.exists(UNITS + "rocket_squad_turret.svg")).is_false()
	assert_bool(ResourceLoader.exists(UNITS + "light_tank_turret.svg")).is_true()
	var spawns: Array[SpawnDef] = [_spawn(1, "light_tank", 5, 5), _spawn(2, "rifle_squad", 8, 5)]
	spawns.append(_spawn(1, "rocket_squad", 5, 8))
	_start(spawns)
	assert_int(_layer.rig_count()).is_equal(3)
	assert_array(_names(_rig(0))).is_equal([&"Hull", &"Team", &"Turret"])
	for row: int in [1, 2]:
		assert_array(_names(_rig(row))).is_equal([&"Hull", &"Team"])
	assert_str(_rig(1).get_node("Hull").texture.resource_path).is_equal(
		UNITS + "rifle_squad_hull.svg"
	)
	assert_str(_rig(2).get_node("Team").texture.resource_path).is_equal(
		UNITS + "rocket_squad_team.svg"
	)
	assert_that(_rig(1).get_node("Team").modulate).is_equal(RED)  # Owner 2.
	assert_that(_rig(2).get_node("Team").modulate).is_equal(BLUE)
	# Rifle squad 2 (speed 67) drives 4 tiles south: both its layers turn, with no turret to turn.
	CommandQueue.submit(Command.attack_move(2, PackedInt32Array([2]), 8500, 9500))
	_runner.run_ticks(1)
	_render(0.5)
	assert_float(_rig(1).get_node("Hull").rotation).is_equal_approx(PI / 2.0, 0.001)
	assert_float(_rig(1).get_node("Team").rotation).is_equal(_rig(1).get_node("Hull").rotation)
	assert_float(_rig(0).get_node("Hull").rotation).is_equal(0.0)
	for layer: String in ["Hull", "Team"]:  # The layers of the rows after the rifle squad stay put.
		assert_float(_rig(2).get_node(layer).rotation).is_equal(0.0)
	# Rocket squad 3 (speed 60) drives 4 tiles south-east: a step of (42, 42) milli, 59 long. That
	# turns it (half of its own step is 30) although it is under half a light tank step (60).
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array([3]), 9500, 12500))
	_runner.run_ticks(1)
	_render(0.5)
	assert_float(_rig(2).get_node("Hull").rotation).is_equal_approx(PI / 4.0, 0.05)
	assert_float(_rig(2).get_node("Team").rotation).is_equal(_rig(2).get_node("Hull").rotation)
	assert_float(_rig(0).get_node("Hull").rotation).is_equal(0.0)


func test_a_ring_is_the_sprite_subclass_with_the_ring_texture_made_at_the_first_selection() -> void:
	for row: int in 40:
		assert_array(_names(_rig(row))).is_equal([&"Hull", &"Team", &"Turret"])  # No ring yet.
	_layer.set_selected(TANK_1)
	var ring: Sprite2D = _rig(0).get_child(0)
	assert_str(ring.name).is_equal("Ring")
	assert_array(_names(_rig(0))).is_equal([&"Ring", &"Hull", &"Team", &"Turret"])
	assert_str(ring.get_class()).is_equal("Sprite2D")
	assert_str(ring.get_script().get_instance_base_type()).is_equal("Sprite2D")
	assert_str(ring.texture.resource_path).is_equal(RING_ART)
	assert_int(ring.z_index).is_equal(1)
	assert_bool(ring.z_as_relative).is_false()
	assert_that(ring.position).is_equal(Vector2.ZERO)
	assert_bool(ring.centered).is_true()  # The texture's centre is the unit's centre.
	assert_that(ring.offset).is_equal(Vector2.ZERO)
	assert_that(ring.modulate).is_equal(Color.WHITE)  # The baked white and dark are not tinted.
	assert_float(ring.rotation).is_equal(0.0)
	assert_float(ring.radius).is_greater(0.0)
	assert_float(UnitLayer.RING_TEX_RADIUS_PX).is_equal(RING_CENTRE_PX)
	assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(ring.radius, 0.001)
	for row: int in range(1, 40):
		assert_int(_rig(row).get_child_count()).is_equal(3)
	_layer.set_selected(PackedInt32Array())  # Hidden, and kept for the next selection.
	assert_bool(ring.visible).is_false()
	_layer.set_selected(TANK_1)
	assert_bool(_rig(0).get_child(0) == ring and ring.visible).is_true()
	assert_int(_rig(0).get_child_count()).is_equal(4)


func test_a_ring_is_sized_for_the_selection_radius_of_its_own_unit_type() -> void:
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # 1 dp is 1 px: 18 dp is under both rings.
	var spawns: Array[SpawnDef] = [_spawn(1, "light_tank", 5, 5), _spawn(1, "rifle_squad", 8, 5)]
	_start(spawns)
	_layer.set_selected(PackedInt32Array([1, 2]))
	# Selection radius 500 and 350 milli, 50 more, at 64 px per tile.
	for want: Array in [[0, 35.2], [1, 25.6]]:
		var ring: Sprite2D = _rig(want[0]).get_node("Ring")
		assert_float(ring.radius).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.y).is_equal(ring.scale.x)
	# A selection reads the dp again, also when no resize came in between: 1.75 px per dp, so the
	# rifle squad's ring is at the 18 dp minimum (31.5 px) and the tank's keeps its art.
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_layer.set_selected(PackedInt32Array([1, 2]))
	for want: Array in [[0, 35.2], [1, 31.5]]:
		var ring: Sprite2D = _rig(want[0]).get_node("Ring")
		assert_float(ring.unit).is_equal_approx(1.75, 0.0001)
		assert_float(ring.radius).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(want[1], 0.001)


func test_every_layer_draws_at_the_z_of_its_batch_group_and_all_are_absolute() -> void:
	# Rows alternate types and owners: tank/1, rifle/2, rifle/1, tank/2, tank/1, rifle/2.
	var spawns: Array[SpawnDef] = [_spawn(1, "light_tank", 5, 5), _spawn(2, "rifle_squad", 8, 5)]
	spawns.append_array([_spawn(1, "rifle_squad", 5, 8), _spawn(2, "light_tank", 8, 8)])
	spawns.append_array([_spawn(1, "light_tank", 5, 11), _spawn(2, "rifle_squad", 8, 11)])
	_start(spawns)
	var snap: MatchSnapshot = _runner.snapshot
	assert_array(snap.type_index).is_equal(PackedInt32Array([0, 1, 1, 0, 0, 1]))
	assert_array(snap.owner).is_equal(PackedInt32Array([1, 2, 1, 2, 1, 2]))
	for row: int in 6:
		var type: int = snap.type_index[row]
		var owner_id: int = snap.owner[row]
		assert_int(_rig(row).get_node("Hull").z_index).is_equal(10 + type)
		assert_int(_rig(row).get_node("Team").z_index).is_equal(20 + 8 * type + owner_id)
		assert_bool(_rig(row).has_node("Turret")).is_equal(type == 0)
		if type == 0:
			assert_int(_rig(row).get_node("Turret").z_index).is_equal(100 + type)
		for sprite: Sprite2D in _rig(row).get_children():
			assert_bool(sprite.z_as_relative).override_failure_message(str(sprite.name)).is_false()
	_layer.set_selected(PackedInt32Array([1, 2]))  # A ring is at 1 under every unit layer.
	assert_int(_rig(0).get_child(0).z_index).is_equal(1)
	# Beyond the bands (the published snapshot is edited, which SYNC allows, and a layer built
	# from it): owner 9 and type index 12 take the last group of their band, owner 8 too.
	snap.type_ids.resize(13)
	snap.type_speed.resize(13)
	snap.type_selection_radius.resize(13)
	for type: int in range(2, 13):
		snap.type_ids[type] = &"light_tank"
	snap.owner[2] = 9  # Rifle squad: Hull 11, Team 99.
	snap.type_index[3] = 12  # Tank of owner 2: Hull 19, Team 99, Turret 109.
	snap.owner[4] = 8  # Tank of type 0: Hull 10, Team 99, Turret 100.
	snap.type_index[5] = 9  # Owner 2, the last type with a group: Hull 19, Team 94, Turret 109.
	var late: UnitLayer = _extra_layer()
	# Per row: Hull, Team and Turret z (-1: no turret).
	var expected: Array[Array] = [
		[2, 11, 99, -1], [3, 19, 99, 109], [4, 10, 99, 100], [5, 19, 94, 109]
	]
	for want: Array in expected:
		var rig: Node2D = late.get_child(want[0])
		assert_int(rig.get_node("Hull").z_index).is_equal(want[1])
		assert_int(rig.get_node("Team").z_index).is_equal(want[2])
		assert_int(rig.get_node("Turret").z_index if want[3] >= 0 else -1).is_equal(want[3])
	assert_int(late.get_child(0).get_node("Team").z_index).is_equal(21)  # Row 0 is unchanged.
	# The thresholds themselves: type 9 and owner 7 are the last with a group of their own, type 10
	# and owner 8 the first without. Hull, Team and Turret are layers 0, 1 and 2.
	var groups: Array[Array] = [  # layer, type, owner, z
		[0, 9, 0, 19],
		[0, 10, 1, 19],
		[2, 9, 0, 109],
		[2, 10, 1, 109],
		[1, 0, 7, 27],
		[1, 1, 7, 35],
		[1, 9, 7, 99],
		[1, 0, 8, 99],
		[1, 10, 0, 99],
		[1, 0, 0, 20],
	]
	for group: Array in groups:
		(
			assert_int(UnitLayer.layer_z(group[0], group[1], group[2]))
			. override_failure_message(str(group))
			. is_equal(group[3])
		)


func test_the_layer_draws_from_the_published_snapshot_and_never_reads_the_world() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 11500, 20000))
	_runner.run_ticks(1)
	_camera.position = Vector2(500, 1100)
	_runner.world = World.new()  # Test-only: an empty World where the match's was.
	assert_int(_runner.world.unit_count()).is_equal(0)
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_that(_rig(0).position).is_equal(Vector2(544, 1184))  # Alpha 0 shows the old tick.
	_layer.set_selected(TANK_1)
	assert_that(_rig(0).get_child(0).name).is_equal(&"Ring")
	assert_float(_rig(0).get_child(0).radius).is_equal_approx(35.2, 0.001)
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, 24.0)
	assert_array(pick.ids).is_equal(PackedInt32Array(range(1, 41)))
	assert_int(pick.owners.count(2)).is_equal(10)
	assert_that(_layer.unit_screen_position(0)).is_equal(Vector2(684, 444))
	assert_int(_extra_layer().rig_count()).is_equal(40)  # A layer made after the swap.


func _rig(row: int) -> Node2D:
	return _layer.get_child(row)


## One frame of zero length, then frames of 50 ms that add up to `seconds`.
func _render(seconds: float) -> void:
	_layer._process(0.0)
	for _frame: int in roundi(seconds / 0.05):
		_layer._process(0.05)


## A hash of everything in the World and the runner's prev arrays that a view could damage.
func _world_hash() -> int:
	var w: World = _runner.world
	var state: Array = [w.tick, w.next_id, w.dropped_commands, w.unit_id, w.owner, w.type_index]
	state.append_array([w.map_w, w.map_h, w.type_ids, w.type_speed, w.type_radius])
	state.append_array([w.type_selection_radius, w.type_spacing])
	state.append_array([w.pos_x, w.pos_y, w.goal_x, w.goal_y, w.order])
	state.append_array([_runner.prev_pos_x, _runner.prev_pos_y])
	return hash(state)


func _names(rig: Node2D) -> Array:
	return rig.get_children().map(func(n: Node) -> StringName: return n.name)


## One unit of `unit` (a file of data/units) for `owner_id` on tile (x, y).
func _spawn(owner_id: int, unit: String, x: int, y: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner_id
	spawn.unit = load("res://data/units/%s.tres" % unit)
	spawn.count = 1
	spawn.origin_tile = Vector2i(x, y)
	return spawn


## A new match of `spawns` on open grass, drawn by the layer at once.
func _start(spawns: Array[SpawnDef]) -> void:
	_runner.scenario = ScenarioDef.new()
	_runner.scenario.spawns = spawns
	_runner.start()
	_layer._process(0.0)


## A second layer on the same runner, built from the snapshot as it is now.
func _extra_layer() -> UnitLayer:
	var layer: UnitLayer = auto_free(UnitLayer.new())
	layer.runner = _runner
	layer.camera = _camera
	add_child(layer)
	layer.set_process(false)
	return layer
