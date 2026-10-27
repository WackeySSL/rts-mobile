extends GdUnitTestSuite
## UnitLayer on data/scenarios/controls_test.tres: 40 rigs in World row order, ids 1-30 owned by
## player 1 and 31-40 by player 2. A rig is a Node2D of the sorted world (P114) with the children
## Shadow, Hull and Turret, each a region of the match's one atlas. Under the 2:1 projection (P117)
## tank 1, at ground (8500, 18500) milli, stands at px (-320, 432), tank 2 at (-272, 456) and tank 7
## at (-368, 456). Headings are grid angles: east on the grid is 0 and the frame `d06`, grid south
## (+y) a quarter turn and `d10`.
## The runner is not in the tree, so only the calls here move time: runner._process() moves the
## interpolation clock and layer._process() draws a frame. Rigs that follow deaths and spawns by
## unit id are in test_unit_layer_rows.gd, where turrets and squads aim in test_unit_layer_aim.gd
## and the sorted world's atlas, z and sort in test_world_sort.gd.

const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
const RING_ART: String = "res://assets/art/svg/ui/selection_ellipse.svg"
## The ellipse texture's horizontal centre-line semi-axis in px, typed again from STYLE.md so that a
## wrong UnitLayer.RING_TEX_RX_PX fails (tests/art pins the texture to the same number).
const RING_CENTRE_PX: float = 72.0
const TANK_1: PackedInt32Array = [1]
const TANK_6: PackedInt32Array = [6]  ## Row 5, the east end of the block's first row.
const TANK_30: PackedInt32Array = [30]  ## Row 29, the block's south-east corner.
const SOUTH: float = PI / 2.0  ## Grid south (+y) as a heading.

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


func test_one_rig_per_unit_with_shadow_hull_and_turret_on_the_atlas_in_draw_order() -> void:
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.world_sort.get_child_count()).is_equal(40)  # The rigs stand in the sort.
	for row: int in 40:
		assert_array(_names(_rig(row))).is_equal([&"Shadow", &"Hull", &"Turret"])
		assert_object(_rig(row).get_parent()).is_same(_layer.world_sort)
	assert_str(_rig(0).name).is_equal("Unit1")
	var atlas: IsoAtlas = _layer.world_sort.atlas
	assert_bool(atlas.is_empty()).is_false()
	for row: int in [0, 29, 30, 39]:  # Owners 1 and 2 wear their own triads: other regions.
		var slot: int = 0 if row < 30 else 1
		for part: StringName in [&"shadow", &"hull", &"turret"]:
			var sprite: Sprite2D = _rig(row).get_node(String(part).capitalize())
			assert_object(sprite.texture).is_same(atlas.texture())
			assert_bool(sprite.region_enabled).is_true()
			assert_that(sprite.modulate).is_equal(Color.WHITE)
			assert_bool(sprite.centered).is_false()
			var want: Rect2i = atlas.region(&"light_tank", part, 6, slot)
			assert_bool(want.has_area()).is_true()
			assert_that(sprite.region_rect).is_equal(Rect2(want))
			assert_float(sprite.scale.x).is_equal_approx(0.5 / atlas.bake_scale(), 0.000001)
	# The hulls of the two owners are recoloured copies, the shadows (no key colour) are shared.
	(
		assert_bool(
			atlas.region(&"light_tank", &"hull", 6, 0) != atlas.region(&"light_tank", &"hull", 6, 1)
		)
		. is_true()
	)
	assert_that(atlas.region(&"light_tank", &"shadow", 6, 0)).is_equal(
		atlas.region(&"light_tank", &"shadow", 6, 1)
	)


func test_a_frame_is_placed_by_the_sheets_anchor_and_the_turret_at_its_mount() -> void:
	var sheet: IsoSheetDef = _layer.world_sort.sheet(&"light_tank")
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var rig: Node2D = _rig(0)
	# The sprite's top-left, in the rig's px, lies the anchor (2x art px, half in world px) up
	# and to the left of the ground point: so the anchor is the rig's position.
	for part: StringName in [&"hull", &"turret", &"shadow"]:
		var sprite: Sprite2D = rig.get_node(String(part).capitalize())
		var anchor: Vector2 = Vector2(sheet.anchor(part))
		assert_vector(sprite.offset * sprite.scale).is_equal_approx(
			-anchor * 0.5, Vector2(0.001, 0.001)
		)
	var turret: Sprite2D = rig.get_node("Turret")
	assert_vector(turret.position).is_equal_approx(sheet.mount(6) * 0.5, Vector2(0.001, 0.001))
	assert_bool(atlas.region(&"light_tank", &"turret", 6, 0).size.x > 0).is_true()
	# A new hull frame moves the turret to the mount of that frame.
	CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 21500))
	_runner.run_ticks(1)
	_render(0.5)
	assert_int(Frames.dir(_layer, 0, &"hull")).is_equal(10)
	assert_vector(turret.position).is_equal_approx(sheet.mount(10) * 0.5, Vector2(0.001, 0.001))


func test_rigs_start_on_the_projected_unit_positions_in_px() -> void:
	assert_that(_rig(0).position).is_equal(Vector2(-320, 432))
	assert_that(_rig(1).position).is_equal(Vector2(-272, 456))
	assert_that(_rig(6).position).is_equal(Vector2(-368, 456))
	assert_that(_rig(30).position).is_equal(Vector2(768, 720))  # Red target, tile (34, 10).
	assert_that(_rig(39).position).is_equal(Vector2(-320, 1136))  # Red target, tile (30, 40).


func test_rig_positions_are_prev_plus_cur_minus_prev_times_alpha() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 11500, 20000))
	_runner.run_ticks(1)  # Tank 1 moves (107, 53) milli: px (-320, 432) -> (-318.272, 434.56).
	_render(0.0)
	var prev: Vector2 = Vector2(-320, 432)
	assert_that(_rig(0).position).is_equal(prev)  # alpha 0 shows the old tick.
	for alpha: float in [0.25, 0.5, 0.75]:
		_runner._process(1.0 / 60.0)
		_render(0.0)
		var expected: Vector2 = prev + (Vector2(-318.272, 434.56) - prev) * alpha
		assert_vector(_rig(0).position).is_equal_approx(expected, Vector2(0.001, 0.001))
		assert_that(_rig(1).position).is_equal(Vector2(-272, 456))  # Tank 2 stands still.


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


func test_a_restarted_match_gets_new_rigs_with_their_own_frames_and_heading() -> void:
	var south: Callable = func() -> void:
		CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 21500))
		_runner.run_ticks(1)
		_render(0.5)
	south.call()
	assert_int(Frames.dir(_layer, 0, &"hull")).is_equal(10)
	var atlas: IsoAtlas = _layer.world_sort.atlas
	_runner.start()
	_layer._process(0.05)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.world_sort.get_child_count()).is_equal(40)
	assert_object(_layer.world_sort.atlas).is_same(atlas)  # The same scenario: nothing is baked.
	assert_float(_layer.heading(0)).is_equal(0.0)  # Neither heading nor aim is kept.
	assert_int(Frames.dir(_layer, 0, &"hull")).is_equal(6)
	south.call()  # Grid south (+y) is down and to the left on the screen.
	assert_float(_layer.heading(0)).is_equal_approx(SOUTH, 0.001)
	assert_int(Frames.dir(_layer, 0, &"hull")).is_equal(10)
	await await_idle_frame()  # The old rigs are freed.


func test_the_hull_eases_toward_where_the_tank_moves_and_keeps_its_heading_when_it_stops() -> void:
	# Tank 30 (row 29, at (16000, 24500)) drives 3 tiles (25 ticks) on a 3-4-5 path, then west
	# (180 degrees), then east; the headings are the grid directions (3, 4), (-3, 0) and (3, 0).
	# It stands at the block's south-east corner, so no unit is within 800 milli of the path:
	# separation (P39b) cannot push it.
	var goals: Array[Vector2i] = [Vector2i(17800, 26900), Vector2i(14800, 26900)]
	goals.append(goals[0])
	var headings: Array[float] = [atan2(4.0, 3.0), PI, 0.0]
	var frames: Array[int] = [8, 14, 6]  # The frames of 53, 180 and 0 degrees.
	for leg: int in 3:
		CommandQueue.submit(Command.attack_move(1, TANK_30, goals[leg].x, goals[leg].y))
		_runner.run_ticks(1)
		var before: float = _layer.heading(29)
		_layer._process(0.05)  # 12 rad/s * 0.05 s = 0.6 rad.
		assert_float(absf(angle_difference(before, _layer.heading(29)))).is_equal_approx(0.6, 0.001)
		_render(0.5)
		assert_float(angle_difference(_layer.heading(29), headings[leg])).is_equal_approx(
			0.0, 0.001
		)
		assert_int(Frames.dir(_layer, 29, &"hull")).is_equal(frames[leg])
		assert_int(Frames.dir(_layer, 29, &"shadow")).is_equal(frames[leg])
		_runner.run_ticks(40)
		assert_int(_runner.world.order[29]).is_equal(World.Order.IDLE)
		_render(0.5)
		assert_float(angle_difference(_layer.heading(29), headings[leg])).is_equal_approx(
			0.0, 0.001
		)
		assert_int(Frames.dir(_layer, 29, &"hull")).is_equal(frames[leg])
		assert_float(_layer.turret_angle(29)).is_equal(_layer.heading(29))
		assert_int(Frames.dir(_layer, 29, &"turret")).is_equal(frames[leg])


func test_the_short_last_step_onto_the_goal_does_not_turn_the_hull() -> void:
	# Tank 6 (row 5, at (16000, 18500)) drives 5.5 tiles almost due east over open ground, the same
	# vector as tank 1's Phase 1 drive. Its last tick moves (1, 1) milli, which would turn the hull
	# by a quarter of a turn (45 degrees from the heading).
	CommandQueue.submit(Command.attack_move(1, TANK_6, 21521, 18540))
	for _tick: int in 50:  # 47 to arrive. Every tick is drawn, as on the phone.
		_runner.run_ticks(1)
		_layer._process(0.05)
	assert_int(_runner.world.order[5]).is_equal(World.Order.IDLE)
	assert_float(_layer.heading(5)).is_equal_approx(atan2(40.0, 5521.0), 0.02)
	assert_int(Frames.dir(_layer, 5, &"hull")).is_equal(6)  # Still east.


func test_unit_screen_position_is_the_rig_seen_through_the_camera() -> void:
	_camera.position = Vector2(-300, 400)  # No map is set, so nothing clamps it.
	assert_that(_layer.unit_screen_position(0)).is_equal(Vector2(620, 392))  # 640 - 20, 360 + 32
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(700, 650)
	assert_that(_layer.unit_screen_position(30)).is_equal(Vector2(742, 465))  # 640 + 68 * 1.5, ...
	# The camera sees the rig's global position, so a layer that is not at the origin moves both
	# this answer and the Picker's rows by its offset (the layer's own sort node moves with it).
	_layer.position = Vector2(64, 32)  # 96 px and 48 px on the screen.
	assert_that(_layer.unit_screen_position(30)).is_equal(Vector2(838, 513))
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, 24.0)
	# The Picker's centre is the lifted one: the sheet's pick lift, at the zoom 1.5, above that.
	var lift: float = float((load(IsoIndex.PATH) as IsoIndex).sheet(&"light_tank").pick_lift_px)
	assert_float(lift).is_greater(0.0)
	assert_that(pick.screen_pos[30]).is_equal(Vector2(838, 513.0 - lift * 1.5))


func test_a_type_without_turret_art_has_hull_and_shadow_only_and_still_turns() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	assert_bool(index.sheet(&"rifle_squad").has_part(&"turret")).is_false()
	assert_bool(index.sheet(&"rocket_squad").has_part(&"turret")).is_false()
	assert_bool(index.sheet(&"light_tank").has_part(&"turret")).is_true()
	var spawns: Array[SpawnDef] = [_spawn(1, "light_tank", 5, 5), _spawn(2, "rifle_squad", 8, 5)]
	spawns.append(_spawn(1, "rocket_squad", 5, 8))
	_start(spawns)
	assert_int(_layer.rig_count()).is_equal(3)
	assert_array(_names(_rig(0))).is_equal([&"Shadow", &"Hull", &"Turret"])
	for row: int in [1, 2]:
		assert_array(_names(_rig(row))).is_equal([&"Shadow", &"Hull"])
	var atlas: IsoAtlas = _layer.world_sort.atlas
	assert_that(_rig(1).get_node("Hull").region_rect).is_equal(
		Rect2(atlas.region(&"rifle_squad", &"hull", 6, 1))  # Owner 2 wears the second triad.
	)
	assert_that(_rig(2).get_node("Hull").region_rect).is_equal(
		Rect2(atlas.region(&"rocket_squad", &"hull", 6, 0))
	)
	# Rifle squad 2 (speed 67) drives 4 tiles south: its frames turn, with no turret to turn. A
	# squad has 8 frames, the even ones, so south is d10 as for a tank.
	CommandQueue.submit(Command.attack_move(2, PackedInt32Array([2]), 8500, 9500))
	_runner.run_ticks(1)
	_render(0.5)
	assert_float(_layer.heading(1)).is_equal_approx(SOUTH, 0.001)
	for part: StringName in [&"hull", &"shadow"]:
		assert_int(Frames.dir(_layer, 1, part)).is_equal(10)
	assert_float(_layer.heading(0)).is_equal(0.0)
	assert_int(Frames.dir(_layer, 0, &"hull")).is_equal(6)
	assert_float(_layer.heading(2)).is_equal(0.0)  # The rows after the rifle squad stay put.
	assert_int(Frames.dir(_layer, 2, &"hull")).is_equal(6)
	# Rocket squad 3 (speed 60) drives 4 tiles south-east: a step of (42, 42) milli, 59 long. That
	# turns it (half of its own step is 30) although it is under half a light tank step (60).
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array([3]), 9500, 12500))
	_runner.run_ticks(1)
	_render(0.5)
	assert_float(_layer.heading(2)).is_equal_approx(PI / 4.0, 0.05)  # Down the screen.
	assert_int(Frames.dir(_layer, 2, &"hull")).is_equal(8)
	assert_float(_layer.heading(0)).is_equal(0.0)


func test_a_ring_is_the_sprite_subclass_with_the_ring_texture_made_at_the_first_selection() -> void:
	for row: int in 40:
		assert_array(_names(_rig(row))).is_equal([&"Shadow", &"Hull", &"Turret"])  # No ring yet.
	_layer.set_selected(TANK_1)
	var ring: Sprite2D = _rig(0).get_node("Ring")
	assert_int(ring.get_index()).is_equal(1)  # After the Shadow and under the sprites.
	assert_array(_names(_rig(0))).is_equal([&"Shadow", &"Ring", &"Hull", &"Turret"])
	assert_str(ring.get_class()).is_equal("Sprite2D")
	assert_str(ring.get_script().get_instance_base_type()).is_equal("Sprite2D")
	assert_str(ring.texture.resource_path).is_equal(RING_ART)
	assert_int(ring.z_index).is_equal(3)
	assert_bool(ring.z_as_relative).is_false()
	assert_that(ring.position).is_equal(Vector2.ZERO)
	assert_bool(ring.centered).is_true()  # The texture's centre is the unit's centre.
	assert_that(ring.offset).is_equal(Vector2.ZERO)
	assert_that(ring.modulate).is_equal(Color.WHITE)  # The baked white and dark are not tinted.
	assert_float(ring.rotation).is_equal(0.0)
	assert_float(ring.radius).is_greater(0.0)
	assert_float(UnitLayer.RING_TEX_RX_PX).is_equal(RING_CENTRE_PX)
	assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(ring.radius, 0.001)
	assert_float(ring.scale.y).is_equal(ring.scale.x)  # The texture is the 2:1 shape itself.
	assert_vector(ring.texture.get_size()).is_equal(Vector2(168, 96))
	assert_float(36.0 * ring.scale.y).is_equal_approx(ring.radius * 0.5, 0.001)  # Half as high.
	for row: int in range(1, 40):
		assert_int(_rig(row).get_child_count()).is_equal(3)
	_layer.set_selected(PackedInt32Array())  # Hidden, and kept for the next selection.
	assert_bool(ring.visible).is_false()
	_layer.set_selected(TANK_1)
	assert_bool(_rig(0).get_node("Ring") == ring and ring.visible).is_true()
	assert_int(_rig(0).get_child_count()).is_equal(4)


func test_a_ring_is_sized_for_the_selection_radius_of_its_own_unit_type() -> void:
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # 1 dp is 1 px: 18 dp is under both rings.
	var spawns: Array[SpawnDef] = [_spawn(1, "light_tank", 5, 5), _spawn(1, "rifle_squad", 8, 5)]
	_start(spawns)
	_layer.set_selected(PackedInt32Array([1, 2]))
	# Selection radius 500 and 350 milli, 50 more: the ground ellipse's horizontal semi-axis is
	# r * 32 * sqrt(2) / 1000 px (24.89 and 18.10), the vertical one half of it.
	for want: Array in [[0, 24.8901], [1, 18.1019]]:
		var ring: Sprite2D = _rig(want[0]).get_node("Ring")
		assert_float(ring.radius).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.y).is_equal(ring.scale.x)  # One scale: the texture is 2:1.
	# A selection reads the dp again, also when no resize came in between: 1.75 px per dp, so both
	# rings are under the 18 dp minimum (31.5 px) and grow to it, the shape kept (2:1).
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_layer.set_selected(PackedInt32Array([1, 2]))
	for want: Array in [[0, 31.5], [1, 31.5]]:
		var ring: Sprite2D = _rig(want[0]).get_node("Ring")
		assert_float(ring.unit).is_equal_approx(1.75, 0.0001)
		assert_float(ring.radius).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(want[1], 0.001)
		assert_float(ring.scale.y).is_equal(ring.scale.x)  # One scale: the texture is 2:1.


func test_every_child_of_a_rig_draws_at_the_z_of_the_table_for_every_mix_of_types_and_owners(
) -> void:
	# Rows alternate types and owners: tank/1, rifle/2, rifle/1, tank/2, tank/1, rifle/2.
	var spawns: Array[SpawnDef] = [_spawn(1, "light_tank", 5, 5), _spawn(2, "rifle_squad", 8, 5)]
	spawns.append_array([_spawn(1, "rifle_squad", 5, 8), _spawn(2, "light_tank", 8, 8)])
	spawns.append_array([_spawn(1, "light_tank", 5, 11), _spawn(2, "rifle_squad", 8, 11)])
	_start(spawns)
	var snap: MatchSnapshot = _runner.snapshot
	assert_array(snap.type_index).is_equal(PackedInt32Array([0, 1, 1, 0, 0, 1]))
	assert_array(snap.owner).is_equal(PackedInt32Array([1, 2, 1, 2, 1, 2]))
	_layer.set_selected(PackedInt32Array([1, 2]))
	for row: int in 6:
		var rig: Node2D = _rig(row)
		assert_int(_absolute_z(rig)).is_equal(WorldSort.Z_SORT)
		assert_int(_absolute_z(rig.get_node("Shadow"))).is_equal(2)  # -8 under the sort's 10.
		assert_int(rig.get_node("Shadow").z_index).is_equal(-8)
		assert_bool(rig.get_node("Shadow").z_as_relative).is_true()
		assert_int(_absolute_z(rig.get_node("Hull"))).is_equal(10)
		assert_bool(rig.has_node("Turret")).is_equal(snap.type_index[row] == 0)
		if snap.type_index[row] == 0:
			assert_int(_absolute_z(rig.get_node("Turret"))).is_equal(10)
		assert_bool(rig.has_node("Ring")).is_equal(row < 2)
		if row < 2:
			assert_int(_absolute_z(rig.get_node("Ring"))).is_equal(3)  # Absolute: the ring.
			assert_bool(rig.get_node("Ring").z_as_relative).is_false()
	assert_int(WorldSort.Z_SHADOW).is_less(WorldSort.Z_RING)
	assert_int(WorldSort.Z_RING).is_less(WorldSort.Z_SORT)


func test_the_layer_draws_from_the_published_snapshot_and_never_reads_the_world() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 11500, 20000))
	_runner.run_ticks(1)
	_camera.position = Vector2(-300, 400)
	_runner.world = World.new()  # Test-only: an empty World where the match's was.
	assert_int(_runner.world.unit_count()).is_equal(0)
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_that(_rig(0).position).is_equal(Vector2(-320, 432))  # Alpha 0 shows the old tick.
	_layer.set_selected(TANK_1)
	assert_that(_rig(0).get_child(1).name).is_equal(&"Ring")
	assert_float(_rig(0).get_child(1).radius).is_equal_approx(24.8901, 0.001)
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, 24.0)
	assert_array(pick.ids).is_equal(PackedInt32Array(range(1, 41)))
	assert_int(pick.owners.count(2)).is_equal(10)
	assert_that(_layer.unit_screen_position(0)).is_equal(Vector2(620, 392))
	assert_int(_extra_layer().rig_count()).is_equal(40)  # A layer made after the swap.


func _rig(row: int) -> Node2D:
	return _layer.rig(row)


## The z a canvas item draws at: its own, plus its parents' while it is relative to them.
func _absolute_z(item: CanvasItem) -> int:
	var z: int = item.z_index
	var node: Node = item
	while node is CanvasItem and (node as CanvasItem).z_as_relative:
		node = node.get_parent()
		if node is CanvasItem:
			z += (node as CanvasItem).z_index
	return z


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
