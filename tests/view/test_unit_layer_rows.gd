extends GdUnitTestSuite
## UnitLayer's rigs follow the snapshot's rows by unit id (plan P40): a death pools its rig and the
## others keep theirs, a spawn gets a rig at its position (a pooled one when its kind has one,
## P114b; the pool itself is test_rig_pool.gd's), another match gives every row a rig, and calls
## made inside `ticked` right after a change already use the new rows. On
## data/scenarios/controls_test.tres: 40 rigs, ids 1-30 blue and 31-40 red; tank 2 stands still at
## px (-272, 456) under the 2:1 projection (P117) and tank 30 (row 29) can drive out of the block
## to the south, a quarter turn from east on the grid (a hull needs three frames of 0.6 rad; the
## headings are grid angles, P114). The runner is not in the tree: only the calls here move time.
## The other cases of UnitLayer are in test_unit_layer.gd (gdlint allows 20 public methods per
## file).

const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
const TANK_30: PackedInt32Array = [30]
const AIM: float = PI / 2.0  ## The hull's aim after tank 30's drive south, grid (0, +y).

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
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)  # Frames come only from _render().


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_dead_unit_loses_its_rig_and_the_others_keep_their_position_heading_and_ring() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_30, 16000, 27500))
	for _tick: int in 40:  # 25 to arrive: tank 30 then stands still, turned south.
		_runner.run_ticks(1)
		_layer._process(0.05)  # Every tick is drawn, as on the phone.
	var dead: Node2D = _rig(0)
	var still: Node2D = _rig(1)
	var turned: Node2D = _rig(29)
	_layer.set_selected(PackedInt32Array([2, 30]))
	var heading: float = _layer.heading(29)
	assert_float(heading).is_equal_approx(AIM, 0.001)
	_runner.world.hp[0] = 0  # Tank 1 dies in the next tick, and every row after it moves up.
	_runner.run_ticks(1)
	_layer._process(0.0)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(39)
	assert_int(_layer.rig_count()).is_equal(39)
	assert_int(_layer.world_sort.get_child_count()).is_equal(39)
	assert_bool(_rig(0) == still and _rig(28) == turned).is_true()  # The same rigs, one row up.
	for row: int in 39:  # Every rig shows its own unit, at the old tick's position (alpha 0).
		assert_str(_rig(row).name).is_equal("Unit%d" % snap.unit_id[row])
		var at: Vector2 = IsoProjection.ground_to_px(snap.prev_pos_x[row], snap.prev_pos_y[row])
		assert_vector(_rig(row).position).is_equal_approx(at, Vector2(0.001, 0.001))
	assert_that(still.position).is_equal(Vector2(-272, 456))
	assert_float(_layer.heading(28)).is_equal(heading)
	assert_int(Frames.dir(_layer, 28, &"hull")).is_equal(10)  # d10 faces grid south.
	# The heading and the aim moved with the unit: a hull that has nothing to turn to stays put.
	_render(0.5)
	assert_float(_layer.heading(28)).is_equal_approx(heading, 0.001)
	assert_float(_layer.heading(0)).is_equal(0.0)
	# A later order starts from the kept heading and aim: due east is 0.6 rad (12 rad/s * 0.05 s)
	# nearer (the turn is longer than one frame), on the survivor's own frames and on no other
	# rig's. A merge that lost the heading and the aim together would show no turn at all.
	CommandQueue.submit(Command.attack_move(1, TANK_30, 19000, 27500))
	_runner.run_ticks(1)
	_layer._process(0.05)
	assert_float(_layer.heading(28)).is_equal_approx(heading - 0.6, 0.001)
	assert_float(_layer.turret_angle(28)).is_equal(_layer.heading(28))
	assert_float(_layer.heading(27)).is_equal(0.0)  # Tank 29, one row before it.
	assert_array(_ringed_ids()).is_equal([2, 30])
	assert_bool(still.get_child(1).name == &"Ring" and still.get_child(1).visible).is_true()
	assert_int(turned.get_child_count()).is_equal(4)
	_layer.set_selected(PackedInt32Array([1, 2]))  # The dead unit is skipped like any unknown id.
	assert_array(_ringed_ids()).is_equal([2])
	await await_idle_frame()  # The dead rig waits in the pool, off the sort.
	assert_bool(is_instance_valid(dead)).is_true()
	assert_bool(dead.get_parent() == _layer.world_sort).is_false()
	assert_bool(dead.is_visible_in_tree()).is_false()


func test_a_unit_that_is_mid_turn_when_another_dies_keeps_its_heading_and_aim_apart() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_30, 16000, 27500))
	_runner.run_ticks(1)
	var rig: Node2D = _rig(29)
	_layer._process(0.05)  # 12 rad/s * 0.05 s = 0.6 rad of the 1.571 to the aim.
	assert_float(_layer.heading(29)).is_equal_approx(0.6, 0.001)
	_runner.world.hp[0] = 0  # Tank 1 dies in the next tick, and tank 30 moves up to row 28.
	_runner.run_ticks(1)
	_layer._process(0.05)  # The merge keeps the heading 0.6 and the aim 1.849 apart: 0.6 more.
	assert_int(_layer.rig_count()).is_equal(39)
	assert_bool(_rig(28) == rig).is_true()
	# A merge that gave the heading the aim would jump to it at once, and one that gave the aim the
	# heading would write no turn at all: the hull would stay at 0.6 for good.
	assert_float(_layer.heading(28)).is_equal_approx(1.2, 0.001)
	_render(0.5)
	assert_float(_layer.heading(28)).is_equal_approx(AIM, 0.001)
	assert_float(_layer.turret_angle(28)).is_equal(_layer.heading(28))
	assert_int(Frames.dir(_layer, 28, &"hull")).is_equal(10)
	await await_idle_frame()


func test_a_unit_that_stands_still_mid_turn_when_another_dies_still_finishes_the_turn() -> void:
	# One full step, (0, 120) milli: tank 30 arrives in one tick and then stands still, with the
	# hull 0.6 rad into the 1.571 to its aim.
	CommandQueue.submit(Command.attack_move(1, TANK_30, 16000, 24620))
	_runner.run_ticks(1)
	assert_int(_runner.world.order[29]).is_equal(World.Order.IDLE)
	var rig: Node2D = _rig(29)
	_layer._process(0.05)
	assert_float(_layer.heading(29)).is_equal_approx(0.6, 0.001)
	# Tank 1 dies in the next tick, in which tank 30 does not move: the frame cannot take the aim
	# from the snapshot, so the merge has to keep it apart from the heading (0.6).
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)
	_layer._process(0.05)
	assert_int(_layer.rig_count()).is_equal(39)
	assert_bool(_rig(28) == rig).is_true()
	assert_float(_layer.heading(28)).is_equal_approx(1.2, 0.001)  # Still turning.
	_render(0.5)
	assert_float(_layer.heading(28)).is_equal_approx(AIM, 0.001)
	assert_float(_layer.turret_angle(28)).is_equal(_layer.heading(28))
	await await_idle_frame()


func test_a_unit_with_no_speed_that_stands_still_keeps_its_aim() -> void:
	# No type has speed 0 yet. For one that had, "moved at least half a step" holds for any move
	# (4 * moved >= 0), so only the move itself keeps a standing unit from aiming at atan2(0, 0).
	CommandQueue.submit(Command.attack_move(1, TANK_30, 16000, 24620))
	_runner.run_ticks(1)
	_layer._process(0.05)
	assert_float(_layer.heading(29)).is_equal_approx(0.6, 0.001)
	_runner.run_ticks(1)  # Tank 30 stands still in this tick.
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.pos_x[29]).is_equal(snap.prev_pos_x[29])
	snap.type_speed[snap.type_index[29]] = 0  # Test-only: written into the published snapshot.
	_layer._process(0.05)
	_render(0.5)  # It finishes the turn to the aim it had, and does not turn to atan2(0, 0).
	assert_float(_layer.heading(29)).is_equal_approx(AIM, 0.001)
	await await_idle_frame()


func test_a_layer_without_a_runner_or_on_a_runner_without_a_snapshot_draws_nothing() -> void:
	var waiting: MatchRunner = auto_free(MatchRunner.new())  # Not started: no snapshot yet.
	waiting.scenario = load(SCENARIO)
	var layers: Array[UnitLayer] = [auto_free(UnitLayer.new()), auto_free(UnitLayer.new())]
	layers[1].runner = waiting  # The first has no runner at all.
	for layer: UnitLayer in layers:
		layer.camera = _camera
		add_child(layer)  # _ready()
		layer.set_process(false)
		layer._process(0.05)
		layer.set_selected(PackedInt32Array([1, 2]))
		var pick: PickSnapshot = PickSnapshot.new()
		layer.fill_pick_snapshot(pick, 24.0)
		assert_int(pick.ids.size()).is_equal(0)
		assert_int(layer.rig_count()).is_equal(0)
		assert_int(layer.world_sort.get_child_count()).is_equal(0)
	waiting.start()  # The rigs come with the first snapshot.
	layers[1]._process(0.0)
	assert_int(layers[1].rig_count()).is_equal(40)
	assert_int(layers[1].world_sort.get_child_count()).is_equal(40)
	assert_int(layers[0].rig_count()).is_equal(0)
	assert_array(layers[1]._ringed).is_empty()  # The selection made before the snapshot is lost.
	await await_idle_frame()


func test_the_ringed_rows_are_the_last_selection_and_follow_their_units_through_a_death() -> void:
	for _repeat: int in 3:  # The same selection again is not added to the list again.
		_layer.set_selected(PackedInt32Array([2, 30]))
	assert_array(_layer._ringed).is_equal(PackedInt32Array([1, 29]))
	_layer.set_selected(PackedInt32Array([3]))  # The rings of 2 and 30 stay, hidden.
	assert_array(_layer._ringed).is_equal(PackedInt32Array([2]))
	_runner.world.hp[0] = 0  # Tank 1 dies: unit 3 moves up to row 1.
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_array(_layer._ringed).is_equal(PackedInt32Array([1]))  # Not the hidden rings.
	assert_array(_ringed_ids()).is_equal([3])
	_layer.set_selected(PackedInt32Array([2, 30]))
	assert_array(_layer._ringed).is_equal(PackedInt32Array([0, 28]))
	_layer.set_selected(PackedInt32Array())
	assert_array(_layer._ringed).is_empty()
	_runner.world.hp[0] = 0  # Unit 2 dies, with its ring hidden: it leaves nothing behind.
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(38)
	assert_array(_layer._ringed).is_empty()
	await await_idle_frame()


func test_a_unit_spawned_mid_match_appears_at_its_position_with_its_tint_and_no_heading_or_ring(
) -> void:
	var rig_0: Node2D = _rig(0)
	assert_int(_layer.rigs_made()).is_equal(40)
	assert_int(_runner.world.add_unit(2, 0, 30500, 12500)).is_equal(41)
	_runner.run_ticks(1)
	# Inside `ticked` a handler may ask at once, before any frame: the rig is already in place.
	assert_that(_layer.unit_screen_position(40)).is_equal(
		_camera.world_to_screen(Vector2(576, 688))
	)
	assert_int(_layer.rigs_made()).is_equal(41)  # Forty at the start, and a spawn finds no pooled one.
	for frame: int in 3:  # Alpha 0, 0.25 and 0.5: a new unit does not slide in from anywhere.
		_layer._process(0.05)
		assert_int(_layer.rig_count()).is_equal(41)
		assert_str(_rig(40).name).is_equal("Unit41")
		assert_that(_rig(40).position).is_equal(Vector2(576, 688))
		_runner._process(1.0 / 60.0)
	var rig: Node2D = _rig(40)
	assert_int(Frames.dir(_layer, 40, &"hull")).is_equal(6)  # Owner 2's frame, facing east.
	assert_float(_layer.heading(40)).is_equal(0.0)
	assert_int(rig.get_child_count()).is_equal(3)  # Shadow, Hull and Turret: no ring.
	assert_bool(_rig(0) == rig_0).is_true()  # The others are not rebuilt.
	assert_array(_ringed_ids()).is_empty()
	assert_that(_layer.unit_screen_position(40)).is_equal(
		_camera.world_to_screen(Vector2(576, 688))
	)


func test_a_death_and_a_spawn_in_one_tick_keep_the_row_count_and_still_remap_the_rigs() -> void:
	var dead: Node2D = _rig(0)
	var second: Node2D = _rig(1)
	_runner.world.hp[0] = 0
	assert_int(_runner.world.add_unit(2, 0, 30500, 12500)).is_equal(41)
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_runner.snapshot.unit_count()).is_equal(40)  # As many rows as before the tick.
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.world_sort.get_child_count()).is_equal(40)
	for row: int in 40:  # Units 2-41: every rig shows its own unit.
		assert_str(_rig(row).name).is_equal("Unit%d" % (row + 2))
	assert_bool(_rig(0) == second).is_true()
	assert_int(Frames.dir(_layer, 39, &"hull")).is_equal(6)  # Owner 2's frame.
	assert_that(_rig(39).position).is_equal(Vector2(576, 688))
	assert_bool(_rig(39) == dead).is_true()  # The unit that died left its rig to the new one.
	assert_int(_layer.rigs_made()).is_equal(40)
	assert_bool(is_instance_valid(dead) and dead.get_parent() == _layer.world_sort).is_true()
	await await_idle_frame()


func test_deaths_in_a_row_and_apart_with_a_spawn_keep_every_survivor_rig_and_add_the_new_one_last(
) -> void:
	var before: Array[Node] = _layer.world_sort.get_children()
	var dead_rows: Array[int] = [0, 1, 20]  # Units 1 and 2 side by side at the head, and unit 21.
	for row: int in dead_rows:
		_runner.world.hp[row] = 0
	_runner.world.add_unit(2, 0, 30500, 12500)
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(38)
	assert_int(_layer.world_sort.get_child_count()).is_equal(38)
	var row: int = 0
	for old_row: int in 40:
		if not dead_rows.has(old_row):
			(
				assert_bool(_rig(row) == before[old_row])
				. override_failure_message("old row %d" % old_row)
				. is_true()
			)
			row += 1
	assert_str(_rig(37).name).is_equal("Unit41")
	var left: Array[Node] = [before[0], before[1], before[20]]  # The rigs the three left behind.
	assert_bool(left.has(_rig(37))).is_true()  # The new one is one of them, not a fourth rig.
	assert_int(_layer.rigs_made()).is_equal(40)
	await await_idle_frame()


func test_each_entry_point_alone_uses_the_new_rows_inside_ticked_right_after_a_death() -> void:
	var seen: Dictionary[StringName, Variant] = {}
	# Unit 1 dies, then unit 2, then unit 3: each time the first call after the tick is one entry
	# point on its own, before any frame, so each one has to bring the rigs up to the snapshot.
	var pick: Callable = func() -> void:
		var snap: PickSnapshot = PickSnapshot.new()
		_layer.fill_pick_snapshot(snap, 24.0)
		seen[&"ids"] = snap.ids.duplicate()
		seen[&"first"] = snap.screen_pos[0]
	# After the second death the last row is 37, unit 40; unit 2 is the one that has just died.
	var where: Callable = func() -> void: seen[&"last"] = _layer.unit_screen_position(37)
	var ring: Callable = func() -> void: _layer.set_selected(PackedInt32Array([3, 4]))
	_kill_first_and_call(pick)
	assert_array(seen[&"ids"]).is_equal(PackedInt32Array(range(2, 41)))
	# Unit 2, its lifted centre: the ground point raised by the light tank's pick lift (zoom 1).
	var lift: float = float((load(IsoIndex.PATH) as IsoIndex).sheet(&"light_tank").pick_lift_px)
	assert_that(seen[&"first"]).is_equal(_camera.world_to_screen(Vector2(-272, 456 - lift)))
	assert_int(_layer.rig_count()).is_equal(39)
	_kill_first_and_call(where)
	assert_that(seen[&"last"]).is_equal(_camera.world_to_screen(Vector2(-320, 1136)))  # Unit 40.
	assert_int(_layer.rig_count()).is_equal(38)
	_kill_first_and_call(ring)
	assert_array(_ringed_ids()).is_equal([4])
	assert_int(_layer.rig_count()).is_equal(37)
	assert_int(seen.size()).is_equal(3)
	await await_idle_frame()


func test_a_resize_between_a_death_and_the_next_frame_sizes_the_rings_of_the_new_rows() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")  # 1 dp is 1.75 px.
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # 1 dp is 1 px.
	_layer.set_selected(PackedInt32Array([2, 40]))  # Rows 1 and 39.
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)  # 39 rows now, and no frame has brought the rigs up to them.
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()  # size_changed: the rings are sized for the rows of the snapshot.
	assert_int(_layer.rig_count()).is_equal(39)
	assert_array(_layer._ringed).is_equal(PackedInt32Array([0, 38]))
	for row: int in [0, 38]:
		var ring: Sprite2D = _rig(row).get_node("Ring")
		assert_float(ring.unit).is_equal_approx(1.75, 0.0001)
		assert_float(ring.radius).is_equal_approx(31.5, 0.001)  # 18 dp, over the art's 24.89 px.
	assert_array(_ringed_ids()).is_equal([2, 40])


func test_another_match_rebuilds_every_rig_even_when_the_rows_version_is_the_same() -> void:
	var before: Array[Node] = _layer.world_sort.get_children()
	var old_snapshot: MatchSnapshot = _runner.snapshot
	var rows_version: int = old_snapshot.rows_version
	_runner.start()
	assert_int(_runner.snapshot.rows_version).is_equal(rows_version)  # Only match_serial differs.
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.world_sort.get_child_count()).is_equal(40)
	assert_int(_layer.rigs_made()).is_equal(40)  # The 40 rigs of the match that ended are reused.
	for row: int in 40:  # None of them is the unit's own: every one is named and placed anew.
		assert_bool(before.has(_rig(row))).is_true()
		assert_str(_rig(row).name).is_equal("Unit%d" % _runner.snapshot.unit_id[row])
		assert_float(_layer.heading(row)).is_equal(0.0)
	# The layer never writes a snapshot, also not the one of the match it is leaving.
	assert_int(old_snapshot.unit_count()).is_equal(40)
	assert_int(old_snapshot.unit_id[0]).is_equal(1)
	await await_idle_frame()


func test_deaths_spawns_rings_and_restarts_leave_no_objects_behind() -> void:
	_runner.run_ticks(1)  # The first tick makes the sim's own objects.
	_layer._process(0.0)
	await await_idle_frame()
	await await_idle_frame()  # The first idle frame leaves an object of the test runner behind.
	# Counts are read between the steps and asserted at the end: an assertion is an object too.
	var counts: Array[int] = []
	counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_runner.world.add_unit(2, 0, 30500, 12500)
	_runner.run_ticks(1)
	_layer._process(0.0)
	await await_idle_frame()
	counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_layer.set_selected(PackedInt32Array([41]))
	counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_layer.set_selected(PackedInt32Array([41, 1]))
	counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_runner.world.hp[40] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	await await_idle_frame()
	counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_runner.start()  # All 40 rigs are replaced, not added to.
	_runner.run_ticks(1)  # The sim's own objects are made by the first tick of a match.
	_layer._process(0.0)
	await await_idle_frame()
	counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	var base: int = counts[0]
	# A spawn adds a rig and its Shadow, Hull and Turret (the tick's snapshot replaced the last one).
	# The first Ring also loads the ring texture, `loaded` objects that every later ring shares, so
	# the second adds one. A death frees nothing: the rig and its ring wait in the pool (P114b),
	# and the restart pools the 40 old rigs, which the 40 rows of the new match take: nothing is
	# made or freed, so a rig is never made twice for want of the pool.
	var loaded: int = counts[2] - counts[1] - 1
	assert_int(loaded).is_greater_equal(0)
	var expected: Array[int] = [base, base + 4, base + 5 + loaded, base + 6 + loaded]
	expected.append_array([base + 6 + loaded, base + 6 + loaded])
	assert_array(counts).is_equal(expected)
	assert_int(_layer.rigs_made()).is_equal(41)


## Tank 1, 2 or 3 (whichever is the first row) dies in a tick, and `entry` is the first call the
## layer gets, inside `ticked`. The layer has drawn the frame before, as on the phone, so anything
## it kept from that frame is a tick old by then.
func _kill_first_and_call(entry: Callable) -> void:
	_layer._process(0.0)
	var handler: Callable = func(_tick: int) -> void: entry.call()
	_runner.ticked.connect(handler)
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)
	_runner.ticked.disconnect(handler)


func _rig(row: int) -> Node2D:
	return _layer.rig(row)


## One frame of zero length, then frames of 50 ms that add up to `seconds`.
func _render(seconds: float) -> void:
	_layer._process(0.0)
	for _frame: int in roundi(seconds / 0.05):
		_layer._process(0.05)


## Unit ids whose ring shows.
func _ringed_ids() -> Array[int]:
	var ids: Array[int] = []
	for rig: Node2D in _layer.world_sort.get_children():
		if rig.has_node("Ring") and rig.get_node("Ring").visible:
			ids.append(rig.name.trim_prefix("Unit").to_int())
	return ids
