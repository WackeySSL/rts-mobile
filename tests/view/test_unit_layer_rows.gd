extends GdUnitTestSuite
## UnitLayer's rigs follow the snapshot's rows by unit id (plan P40): a death frees its rig and the
## others keep theirs, a spawn gets a rig at its position, another match rebuilds all, and calls
## made inside `ticked` right after a change already use the new rows. On
## data/scenarios/controls_test.tres: 40 rigs, ids 1-30 blue and 31-40 red; tank 2 stands still at
## px (640, 1184) and tank 30 (row 29) can drive out of the block to the south-east. The runner is
## not in the tree: only the calls here move time. The other cases of UnitLayer are in
## test_unit_layer.gd (gdlint allows 20 public methods per file).

const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
const RED: Color = Color("E5484D")
const TANK_30: PackedInt32Array = [30]

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
	CommandQueue.clear()


func test_a_dead_unit_loses_its_rig_and_the_others_keep_their_position_heading_and_ring() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_30, 17800, 26900))
	for _tick: int in 40:  # 25 to arrive: tank 30 then stands still, turned south-east.
		_runner.run_ticks(1)
		_layer._process(0.05)  # Every tick is drawn, as on the phone.
	var dead: Node2D = _rig(0)
	var still: Node2D = _rig(1)
	var turned: Node2D = _rig(29)
	_layer.set_selected(PackedInt32Array([2, 30]))
	var heading: float = turned.get_node("Hull").rotation
	assert_float(heading).is_equal_approx(atan2(4.0, 3.0), 0.001)
	_runner.world.hp[0] = 0  # Tank 1 dies in the next tick, and every row after it moves up.
	_runner.run_ticks(1)
	_layer._process(0.0)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(39)
	assert_int(_layer.rig_count()).is_equal(39)
	assert_int(_layer.get_child_count()).is_equal(39)
	assert_bool(_rig(0) == still and _rig(28) == turned).is_true()  # The same rigs, one row up.
	for row: int in 39:  # Every rig shows its own unit, at the old tick's position (alpha 0).
		assert_str(_rig(row).name).is_equal("Unit%d" % snap.unit_id[row])
		var at: Vector2 = ViewScale.milli_to_px_vec(snap.prev_pos_x[row], snap.prev_pos_y[row])
		assert_vector(_rig(row).position).is_equal_approx(at, Vector2(0.001, 0.001))
	assert_that(still.position).is_equal(Vector2(640, 1184))
	assert_float(turned.get_node("Hull").rotation).is_equal(heading)
	# The heading and the aim moved with the unit: a hull that has nothing to turn to stays put.
	_render(0.5)
	assert_float(turned.get_node("Hull").rotation).is_equal_approx(heading, 0.001)
	assert_float(still.get_node("Hull").rotation).is_equal(0.0)
	# A later order starts from the kept heading and aim: due east is 0.6 rad (12 rad/s * 0.05 s)
	# nearer, on the survivor's own three layers and on no other rig's. A merge that lost the
	# heading and the aim together would show no turn at all, the hull keeping its sprite angle.
	CommandQueue.submit(Command.attack_move(1, TANK_30, 20800, 26900))
	_runner.run_ticks(1)
	_layer._process(0.05)
	var hull: Sprite2D = turned.get_node("Hull")
	assert_float(hull.rotation).is_equal_approx(heading - 0.6, 0.001)
	assert_float(turned.get_node("Team").rotation).is_equal(hull.rotation)
	assert_float(turned.get_node("Turret").rotation).is_equal(hull.rotation)
	assert_float(_rig(27).get_node("Hull").rotation).is_equal(0.0)  # Tank 29, one row before it.
	assert_array(_ringed_ids()).is_equal([2, 30])
	assert_bool(still.get_child(0).name == &"Ring" and still.get_child(0).visible).is_true()
	assert_int(turned.get_child_count()).is_equal(4)
	_layer.set_selected(PackedInt32Array([1, 2]))  # The dead unit is skipped like any unknown id.
	assert_array(_ringed_ids()).is_equal([2])
	await await_idle_frame()  # The dead rig is freed.
	assert_bool(is_instance_valid(dead)).is_false()


func test_a_unit_spawned_mid_match_appears_at_its_position_with_its_tint_and_no_heading_or_ring(
) -> void:
	var rig_0: Node2D = _rig(0)
	assert_int(_runner.world.add_unit(2, 0, 30500, 12500)).is_equal(41)
	_runner.run_ticks(1)
	# Inside `ticked` a handler may ask at once, before any frame: the rig is already in place.
	assert_that(_layer.unit_screen_position(40)).is_equal(
		_camera.world_to_screen(Vector2(1952, 800))
	)
	for frame: int in 3:  # Alpha 0, 0.25 and 0.5: a new unit does not slide in from anywhere.
		_layer._process(0.05)
		assert_int(_layer.rig_count()).is_equal(41)
		assert_str(_rig(40).name).is_equal("Unit41")
		assert_that(_rig(40).position).is_equal(Vector2(1952, 800))
		_runner._process(1.0 / 60.0)
	var rig: Node2D = _rig(40)
	assert_that(rig.get_node("Team").modulate).is_equal(RED)
	assert_float(rig.get_node("Hull").rotation).is_equal(0.0)
	assert_int(rig.get_child_count()).is_equal(3)  # Hull, Team and Turret: no ring.
	assert_bool(_rig(0) == rig_0).is_true()  # The others are not rebuilt.
	assert_array(_ringed_ids()).is_empty()
	assert_that(_layer.unit_screen_position(40)).is_equal(
		_camera.world_to_screen(Vector2(1952, 800))
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
	assert_int(_layer.get_child_count()).is_equal(40)
	for row: int in 40:  # Units 2-41: every rig shows its own unit.
		assert_str(_rig(row).name).is_equal("Unit%d" % (row + 2))
	assert_bool(_rig(0) == second).is_true()
	assert_that(_rig(39).get_node("Team").modulate).is_equal(RED)
	assert_that(_rig(39).position).is_equal(Vector2(1952, 800))
	await await_idle_frame()
	assert_bool(is_instance_valid(dead)).is_false()


func test_deaths_in_a_row_and_apart_with_a_spawn_keep_every_survivor_rig_and_add_the_new_one_last(
) -> void:
	var before: Array[Node] = _layer.get_children()
	var dead_rows: Array[int] = [0, 1, 20]  # Units 1 and 2 side by side at the head, and unit 21.
	for row: int in dead_rows:
		_runner.world.hp[row] = 0
	_runner.world.add_unit(2, 0, 30500, 12500)
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(38)
	assert_int(_layer.get_child_count()).is_equal(38)
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
	assert_bool(before.has(_rig(37))).is_false()
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
	assert_that(seen[&"first"]).is_equal(_camera.world_to_screen(Vector2(640, 1184)))  # Unit 2.
	assert_int(_layer.rig_count()).is_equal(39)
	_kill_first_and_call(where)
	assert_that(seen[&"last"]).is_equal(_camera.world_to_screen(Vector2(1952, 2592)))  # Unit 40.
	assert_int(_layer.rig_count()).is_equal(38)
	_kill_first_and_call(ring)
	assert_array(_ringed_ids()).is_equal([4])
	assert_int(_layer.rig_count()).is_equal(37)
	assert_int(seen.size()).is_equal(3)
	await await_idle_frame()


func test_another_match_rebuilds_every_rig_even_when_the_rows_version_is_the_same() -> void:
	var before: Array[Node] = _layer.get_children()
	var old_snapshot: MatchSnapshot = _runner.snapshot
	var rows_version: int = old_snapshot.rows_version
	_runner.start()
	assert_int(_runner.snapshot.rows_version).is_equal(rows_version)  # Only match_serial differs.
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.get_child_count()).is_equal(40)
	for rig: Node in _layer.get_children():
		assert_bool(before.has(rig)).is_false()
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
	# A spawn adds a rig and its Hull, Team and Turret (the tick's snapshot replaced the last one).
	# The first Ring also loads the ring texture, `loaded` objects that every later ring shares, so
	# the second adds one. A death frees the rig, its layers and its ring (5). The restart frees the
	# 40 old rigs and the ring of tank 1, the last holder of the texture.
	var loaded: int = counts[2] - counts[1] - 1
	assert_int(loaded).is_greater_equal(0)
	var expected: Array[int] = [base, base + 4, base + 5 + loaded, base + 6 + loaded]
	expected.append_array([base + 1 + loaded, base])
	assert_array(counts).is_equal(expected)


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
	return _layer.get_child(row)


## One frame of zero length, then frames of 50 ms that add up to `seconds`.
func _render(seconds: float) -> void:
	_layer._process(0.0)
	for _frame: int in roundi(seconds / 0.05):
		_layer._process(0.05)


## Unit ids whose ring shows.
func _ringed_ids() -> Array[int]:
	var ids: Array[int] = []
	for rig: Node2D in _layer.get_children():
		if rig.has_node("Ring") and rig.get_node("Ring").visible:
			ids.append(rig.name.trim_prefix("Unit").to_int())
	return ids
