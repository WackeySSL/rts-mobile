extends GdUnitTestSuite
## The idle life of vehicles (plan P140, ADR 0027 sections 1, 3, 6 and 8): a vehicle that stood
## still in the last tick with no target, inside the view rect, shakes its Hull and Turret together
## by a half pixel at most, with one new offset per `shake_ms` at the most. A vehicle that moves or
## has a target does not, nor does a squad, a hidden enemy, a rig out of view, or anything with
## `reduced` set. Life moves child sprites only: the rig's node, its picks and its Shadow stay. The
## turret's look is in test_idle_looks.gd. The functions are in
## test_idle_life.gd; this is the layer's use of them. Fixtures: recoil_rig.gd (a paused runner
## whose tick and alpha the test sets, `_process` once for a frame; match time = (tick + alpha) x
## 1000 / 15 ms). The camera starts far away, so every rig is made at rest; a test points it at a
## rig (`_watch`) and the rig rests for one step before it shakes (a rig that has just become idle
## starts at its own next step, which spreads a halting column's first writes over `shake_ms`). The
## light tank (id 1) shakes (0, 0) for its first 166 ms from 2000 ms, by the Python restatement of
## the functions, and the heavy tank (id 2) is held down by a target in the tests of the light one.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const TOL: Vector2 = Vector2(0.001, 0.001)
const FRAMES_PER_TICK: int = 4  ## A 60 fps frame is a quarter of a 15 Hz tick, 16.7 ms.
const FAR: float = 1.0e6

var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _life: LifeSettings
var _expect: RigLife  ## The same numbers, to say what a frame should show.


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_start(LifeSettings.new())


func after_test() -> void:
	CommandQueue.clear()


func test_a_standing_vehicle_shakes_hull_and_turret_together_as_the_function_says() -> void:
	_life.look_ms = 0  # The shake alone.
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	_watch(Rig.LIGHT)
	var off_rule: int = 0
	var apart: int = 0
	var seen: Dictionary[Vector2, bool] = {}
	var changes: int = 0
	var last: Vector2 = Vector2.ZERO
	for frame: int in 300:  # 5 s.
		_frame(frame)
		var want: Vector2 = _expect.shake_offset(Rig.LIGHT, _now())
		if not hull.position.is_equal_approx(want):
			off_rule += 1
		if not (turret.position - mount).is_equal_approx(want):
			apart += 1
		if absf(hull.position.x) > 0.5 or absf(hull.position.y) > 0.5:
			off_rule += 1
		seen[hull.position] = true
		if hull.position != last:
			changes += 1
			last = hull.position
	assert_int(off_rule).is_equal(0)
	assert_int(apart).is_equal(0)  # The Turret rides with the Hull.
	assert_int(seen.size()).is_equal(9)  # It moves over all nine offsets (the restatement).
	# At most one new offset per shake_ms: 5 s hold 62.5 steps of 80 ms, 51 of which change the
	# offset (the restatement). The Hull and the Turret are written together, so two sprite writes
	# for each change.
	assert_int(changes).is_equal(51)
	assert_int(_layer.life_writes()).is_equal(2 * changes)


func test_the_pinned_first_offsets_of_the_light_tank() -> void:
	# The Python restatement: ten frames at rest, then (-0.5, 0) for four, (0.5, 0.5) for five.
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	_watch(Rig.LIGHT)
	var offsets: Array[Vector2] = []
	for frame: int in 20:
		_frame(frame)
		offsets.append(hull.position)
	assert_vector(offsets[0]).is_equal(Vector2.ZERO)
	assert_vector(offsets[9]).is_equal(Vector2.ZERO)
	assert_vector(offsets[10]).is_equal(Vector2(-0.5, 0.0))
	assert_vector(offsets[13]).is_equal(Vector2(-0.5, 0.0))
	assert_vector(offsets[14]).is_equal(Vector2(0.5, 0.5))
	assert_vector(offsets[18]).is_equal(Vector2(0.5, 0.5))
	assert_vector(offsets[19]).is_equal(Vector2(0.0, -0.5))
	assert_int(_layer.life_writes()).is_equal(6)  # Three changes from rest, Hull and Turret each.


func test_a_vehicle_that_has_just_become_idle_rests_for_its_step_before_it_shakes() -> void:
	# A column that halts together would write every sprite in one frame. A rig rests for the step
	# it finds itself in and shakes from the next, which its own phase puts anywhere in 80 ms. The
	# heavy tank would shake (0.5, 0) at 2050 ms, in the step from 2023 to 2103; seen first at that
	# instant it stays at rest to the last ms of the step, and the step after it is (0, 0) too: the
	# first shake is (0.5, -0.5) from 2183 ms.
	_life.look_ms = 0
	_pin_down(Rig.LIGHT)
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	_camera.position = _rig(row).position
	_at_ms(2050.0)
	assert_vector(_expect.shake_offset(Rig.HEAVY, 2050.0)).is_equal(Vector2(0.5, 0.0))
	assert_float(_expect.span_to).is_equal(2103.0)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(0)
	_at_ms(2102.0)  # The last ms of the step it rests for.
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(0)
	_at_ms(2103.5)  # The next step: (0, 0), the rest again, nothing to write.
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(0)
	_at_ms(2190.0)  # And the one after it: (0.5, -0.5).
	assert_vector(hull.position).is_equal(Vector2(0.5, -0.5))
	assert_int(_layer.life_writes()).is_equal(2)


func test_the_node_the_shadow_and_the_picks_never_move() -> void:
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var rig: Node2D = _rig(row)
	var at: Vector2 = rig.position
	var shadow: Vector2 = (rig.get_node("Shadow") as Sprite2D).position
	_watch(Rig.LIGHT)
	var picks: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(picks, 24.0)
	var screen: Vector2 = _layer.unit_screen_position(row)
	var bar: float = _layer.bar_lift_px(row)
	var moved: int = 0
	for frame: int in 120:
		_frame(frame)
		if rig.position != at or (rig.get_node("Shadow") as Sprite2D).position != shadow:
			moved += 1
	assert_int(_layer.life_writes()).is_greater(0)  # It shook.
	assert_int(moved).is_equal(0)
	var during: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(during, 24.0)
	assert_array(during.screen_pos).is_equal(picks.screen_pos)
	assert_array(during.lift_px).is_equal(picks.lift_px)
	assert_vector(_layer.unit_screen_position(row)).is_equal(screen)
	assert_float(_layer.bar_lift_px(row)).is_equal(bar)


func test_a_moving_vehicle_does_not_shake_and_one_that_starts_moving_is_calmed_at_once() -> void:
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	var snap: MatchSnapshot = _runner.snapshot
	_watch(Rig.LIGHT)
	_frame(10)  # Frames 10 to 13 hold (-0.5, 0).
	assert_vector(hull.position).is_equal(Vector2(-0.5, 0.0))
	var before: int = _layer.life_writes()
	snap.prev_pos_x[row] = snap.pos_x[row] - 10  # It moved a hair in the last tick: not standing.
	_frame(11)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	assert_int(_layer.life_writes()).is_equal(before + 2)  # One write each, to rest.
	for later: int in range(12, 70):  # Never again while it moves.
		_frame(later)
		assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(before + 2)
	snap.prev_pos_x[row] = snap.pos_x[row]  # It stands again: rest for a step, then the shake.
	var later: int = 70
	while hull.position == Vector2.ZERO and later < 400:
		_frame(later)
		later += 1
	assert_vector(hull.position).is_not_equal(Vector2.ZERO)
	before = _layer.life_writes()
	snap.prev_pos_y[row] = snap.pos_y[row] - 10  # A move in y alone is a move too.
	_frame(later)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	assert_int(_layer.life_writes()).is_equal(before + 2)


func test_a_vehicle_that_drives_off_while_out_of_view_is_calmed_at_once() -> void:
	# The shaking tank is left as it is when the camera leaves; if it then starts to move with no one
	# looking, the move still takes the shake off it (one write each), and a rig out of view that
	# stands is not written at all.
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	var snap: MatchSnapshot = _runner.snapshot
	_watch(Rig.LIGHT)
	_frame(10)  # Frames 10 to 13 hold (-0.5, 0).
	assert_vector(hull.position).is_equal(Vector2(-0.5, 0.0))
	var before: int = _layer.life_writes()
	_camera.position = Vector2(FAR, FAR)
	_frame(11)
	_frame(12)
	assert_vector(hull.position).is_equal(Vector2(-0.5, 0.0))  # Left as it was.
	assert_int(_layer.life_writes()).is_equal(before)
	snap.prev_pos_x[row] = snap.pos_x[row] - 10  # It drives off, unseen.
	_frame(13)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	assert_int(_layer.life_writes()).is_equal(before + 2)


func test_a_vehicle_with_a_target_does_not_shake_and_is_calmed_when_it_gets_one() -> void:
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	var snap: MatchSnapshot = _runner.snapshot
	_watch(Rig.LIGHT)
	_frame(10)
	assert_vector(hull.position).is_not_equal(Vector2.ZERO)
	snap.target[row] = Rig.ENEMY_TANK  # A target it holds, as the sim writes it.
	snap.target_row[row] = snap.index_of(Rig.ENEMY_TANK)
	var shook: int = 0
	for frame: int in range(11, 130):
		_frame(frame)
		if hull.position != Vector2.ZERO or not turret.position.is_equal_approx(mount):
			shook += 1
	assert_int(shook).is_equal(0)
	snap.target[row] = 99999  # A target that is gone but still held also counts as one.
	snap.target_row[row] = -1
	for frame: int in range(130, 200):
		_frame(frame)
		assert_vector(hull.position).is_equal(Vector2.ZERO)
	snap.target[row] = 0  # And with none it shakes again.
	var again: bool = false
	for frame: int in range(200, 260):
		_frame(frame)
		again = again or hull.position != Vector2.ZERO
	assert_bool(again).is_true()


func test_a_vehicle_out_of_the_view_rect_does_not_shake_and_one_inside_it_does() -> void:
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var tank: Vector2 = _rig(row).position
	var half: float = _camera.visible_world_rect().size.x * 0.5
	var reach: float = half + UnitLayer.IDLE_MARGIN_PX  # The rect grown by a tile, to the east.
	_camera.position = tank + Vector2(reach + 8.0, 0.0)  # 8 px beyond the grown rect.
	for frame: int in range(0, 130):
		_frame(frame)
	assert_int(_layer.life_writes()).is_equal(0)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	_camera.position = tank + Vector2(reach - 8.0, 0.0)  # 8 px inside it.
	for frame: int in range(130, 200):
		_frame(frame)
	assert_int(_layer.life_writes()).is_greater(0)


func test_a_hidden_enemy_vehicle_neither_shakes_nor_looks_and_a_seen_one_does_both() -> void:
	# The enemy tank (id 5) looks west from 9563 to 10463 ms and east from 15101 to 16001 (the
	# restatement). Hidden, it shows nothing of the first window; seen from 11000 ms, it looks east
	# in the second (samples every 100 ms: from 15200 to 16000) and shakes, 54 times in all, so 108
	# writes and two for the look.
	_pin_down(Rig.HEAVY)  # The own tanks in view are held down: only the enemy is left to write.
	_pin_down(Rig.LIGHT)
	var row: int = _runner.snapshot.index_of(Rig.ENEMY_TANK)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	_camera.position = _rig(row).position  # In view, but the fog hides it.
	assert_bool(_layer.is_shown(row)).is_false()
	var shown: int = 0
	for ms: int in range(9000, 11000, 100):
		_at_ms(float(ms))
		if Frames.dir(_layer, row, &"turret") != UnitLayer.D_EAST or hull.position != Vector2.ZERO:
			shown += 1
	assert_int(shown).is_equal(0)
	assert_int(_layer.life_writes()).is_equal(0)
	Buildings.see(_runner.snapshot, 1, [Rig.FAR_TILE])
	assert_bool(_layer.is_shown(row)).is_true()
	var dirs: Array[int] = []
	var times: Array[int] = []
	for ms: int in range(11000, 17000, 100):
		_at_ms(float(ms))
		var dir: int = Frames.dir(_layer, row, &"turret")
		if dirs.is_empty() or dirs[-1] != dir:
			dirs.append(dir)
			times.append(ms)
	assert_array(dirs).is_equal([6, 7, 6])
	assert_array(times).is_equal([11000, 15200, 16100])
	assert_int(_layer.life_writes()).is_equal(110)


func test_a_squad_has_no_idle_life() -> void:
	var squad_row: int = _runner.snapshot.index_of(Rig.SQUAD)
	var squad: Node2D = _rig(squad_row)
	var tank: Node2D = _rig(_runner.snapshot.index_of(Rig.LIGHT))
	_camera.position = (squad.position + tank.position) * 0.5  # Both inside the view.
	_at_ms(1900.0)
	for frame: int in 240:
		_frame(frame)
		assert_vector((squad.get_node("Hull") as Sprite2D).position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_greater(0)  # The tank beside it did shake.


func test_reduced_drops_the_shake_and_the_look_and_switching_to_it_calms_the_rig() -> void:
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	_life.reduced = true
	_watch(Rig.LIGHT)
	for frame: int in 240:
		_frame(frame)
	assert_int(_layer.life_writes()).is_equal(0)
	_life.reduced = false
	var frame: int = 240
	while hull.position == Vector2.ZERO and frame < 600:  # On: it shakes within a few steps.
		_frame(frame)
		frame += 1
	assert_vector(hull.position).is_not_equal(Vector2.ZERO)
	var written: int = _layer.life_writes()
	_life.reduced = true  # Switched on mid-shake: one write each to rest, and then none.
	_frame(frame)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	assert_int(_layer.life_writes()).is_equal(written + 2)
	for later: int in range(frame + 1, frame + 60):
		_frame(later)
	assert_int(_layer.life_writes()).is_equal(written + 2)


func test_a_pause_freezes_the_shake_with_the_match() -> void:
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	_watch(Rig.LIGHT)
	_frame(14)  # (0.5, 0.5).
	assert_vector(hull.position).is_equal(Vector2(0.5, 0.5))
	var writes: int = _layer.life_writes()
	_runner.paused = true
	for _frame_index: int in 120:  # Seconds of real frames; the match does not move.
		_runner._process(0.5)
		_layer._process(0.05)
	assert_vector(hull.position).is_equal(Vector2(0.5, 0.5))
	assert_int(_layer.life_writes()).is_equal(writes)


func test_the_shake_rides_on_top_of_the_recoil_and_both_go_home() -> void:
	# The heavy tank stands with no target when its shell is fired (the target died): the Hull is
	# at the rock (-1, 0) plus the shake (0.5, 0) of that instant, the Turret at its mount plus the
	# recoil (-5, 0) plus the same shake; 200 ms later the kick is over and the shake stays.
	_life.look_ms = 0
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	_watch(Rig.HEAVY)
	var from: Vector2i = Rig.position_of(_runner, Rig.HEAVY)
	Rig.deliver(
		_runner,
		Rig.shot(_runner, Rig.HEAVY, from, Rig.EAST_ON_SCREEN, &"heavy_cannon"),
		Rig.SHOT_TICK
	)
	Rig.at(_runner, Rig.SHOT_TICK, 0.75)  # 50 ms into the kick, match time 2050 ms.
	_layer._process(0.0)
	assert_vector(_expect.shake_offset(Rig.HEAVY, 2050.0)).is_equal(Vector2(0.5, 0.0))
	assert_vector(hull.position).is_equal_approx(Vector2(-0.5, 0.0), TOL)
	assert_vector(turret.position - mount).is_equal_approx(Vector2(-4.5, 0.0), TOL)
	Rig.at(_runner, 34, 0.0)  # 266.7 ms: the kick is over.
	_layer._process(0.0)
	var shake: Vector2 = _expect.shake_offset(Rig.HEAVY, _now())
	assert_vector(hull.position).is_equal_approx(shake, TOL)
	assert_vector(turret.position - mount).is_equal_approx(shake, TOL)


func test_a_hull_turn_keeps_the_shake_on_the_new_mount() -> void:
	_life.look_ms = 0
	_pin_down(Rig.LIGHT)
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var snap: MatchSnapshot = _runner.snapshot
	_watch(Rig.HEAVY)
	snap.prev_pos_y[row] = snap.pos_y[row] - snap.type_speed[snap.type_index[row]]
	_layer._process(1.0)  # It drove south in the last tick: the hull turns, the mount moves.
	snap.prev_pos_y[row] = snap.pos_y[row]  # And stands again.
	var dir: int = Frames.dir(_layer, row, &"hull")
	assert_int(dir).is_not_equal(UnitLayer.D_EAST)
	var sheet: IsoSheetDef = _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
	var mount: Vector2 = sheet.mount(dir) * WorldSort.ART_SCALE
	var frame: int = 0
	_frame(frame)  # Rests for its first step...
	while hull.position == Vector2.ZERO and frame < 300:  # ... then shakes, on the new mount.
		frame += 1
		_frame(frame)
	assert_vector(hull.position).is_not_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount + hull.position, TOL)


func test_the_shake_stays_on_the_turret_through_every_step_of_a_kick() -> void:
	# The light tank (3 px of recoil) stands and shakes when it fires, at tick 33 (2200 ms), where it
	# shakes (-0.5, 0) until 2233 ms and (0.5, 0.5) from then to 2313. The kick moves every 25 ms
	# sample, the shake once in 80 ms: at each sample the Turret is at its mount plus the pinned
	# recoil plus the shake of that instant, and the Hull at the shake alone (no rock). Samples in
	# the middle of a shake step are the ones that tell: only the kick moves there.
	_life.look_ms = 0
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	_watch(Rig.LIGHT)
	var from: Vector2i = Rig.position_of(_runner, Rig.LIGHT)
	Rig.deliver(
		_runner,
		Rig.shot(_runner, Rig.LIGHT, from, Rig.EAST_ON_SCREEN, &"tank_cannon"),
		Rig.SHOT_TICK + 3
	)
	var wrong: int = 0
	var shaken: int = 0
	for index: int in Rig.SAMPLES.size():
		Rig.at(_runner, int(Rig.SAMPLES[index].x) + 3, Rig.SAMPLES[index].y)
		_layer._process(0.0)
		var shake: Vector2 = _expect.shake_offset(Rig.LIGHT, _now())
		var back: Vector2 = Vector2(-Rig.TANK_CANNON_BACK[index], 0.0)
		if not (turret.position - mount).is_equal_approx(back + shake):
			wrong += 1
		if not hull.position.is_equal_approx(shake):
			wrong += 1
		shaken += 1 if shake != Vector2.ZERO else 0
	assert_int(wrong).is_equal(0)
	assert_int(shaken).is_equal(9)  # By the restatement, the shake is off rest at all nine.


func test_a_hull_that_is_still_turning_when_it_stops_keeps_the_shake_on_every_new_mount() -> void:
	# The heavy tank drives one step west and stops: its heading takes 16 frames to swing round,
	# and it is idle, and shaking, for most of them. Each frame the Turret is at the mount of the
	# hull frame it shows plus the shake.
	_life.look_ms = 0
	_pin_down(Rig.LIGHT)
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	var snap: MatchSnapshot = _runner.snapshot
	var hull: Sprite2D = _rig(row).get_node("Hull")
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var sheet: IsoSheetDef = _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
	_watch(Rig.HEAVY)
	snap.prev_pos_x[row] = snap.pos_x[row] + snap.type_speed[snap.type_index[row]]
	Rig.at(_runner, 30, 0.0)
	_layer._process(1.0 / 60.0)  # It moved west a full step in the last tick.
	snap.prev_pos_x[row] = snap.pos_x[row]  # And stands: the swing goes on.
	var wrong: int = 0
	var turning_and_shaking: int = 0
	var last_dir: int = Frames.dir(_layer, row, &"hull")
	for index: int in range(1, 40):
		Rig.at(_runner, 30 + index / FRAMES_PER_TICK, float(index % FRAMES_PER_TICK) / 4.0)
		_layer._process(1.0 / 60.0)
		var dir: int = Frames.dir(_layer, row, &"hull")
		var mount: Vector2 = sheet.mount(dir) * WorldSort.ART_SCALE
		if not (turret.position - mount).is_equal_approx(hull.position):
			wrong += 1
		if dir != last_dir and hull.position != Vector2.ZERO:
			turning_and_shaking += 1
		last_dir = dir
	assert_int(last_dir).is_not_equal(UnitLayer.D_EAST)  # It did turn, and a long way.
	assert_int(wrong).is_equal(0)
	assert_int(turning_and_shaking).is_greater_equal(2)


func test_a_pooled_rig_starts_a_new_match_at_rest() -> void:
	# The light tank's rig is shaking and looking west (2300 ms: offset (0.5, 0.5), d05) when the
	# match restarts. The pool hands it to another unit, the enemy tank (id 5, the last rig out is
	# the first one back in). Seen at 9800 ms, inside that tank's own window to the west (9563 to
	# 10463), it must start from rest like a new rig: the look is set at once (the pooled rig's old
	# look is the same side, so a stale one would write nothing and leave it straight), the shake
	# only from its second step, and from then on it shows what the function says.
	_pin_down(Rig.HEAVY)
	var shaken: Node2D = _rig(_runner.snapshot.index_of(Rig.LIGHT))
	_watch(Rig.LIGHT)
	_at_ms(2300.0)
	assert_vector((shaken.get_node("Hull") as Sprite2D).position).is_equal(Vector2(0.5, 0.5))
	var made: int = _layer.rigs_made()
	_runner.start()  # Another match of the same scenario: the rigs come out of the pool.
	var snap: MatchSnapshot = _runner.snapshot
	_pin_down(Rig.HEAVY)
	_pin_down(Rig.LIGHT)
	Buildings.see(snap, 1, [Rig.FAR_TILE])
	_camera.position = Vector2(FAR, FAR)  # Nothing in view until the enemy tank is looked at.
	Rig.at(_runner, 0, 0.0)
	_layer._process(0.0)
	assert_int(_layer.rigs_made()).is_equal(made)
	var row: int = snap.index_of(Rig.ENEMY_TANK)
	assert_object(_rig(row)).is_same(shaken)  # The shaken rig is the enemy tank's now.
	var hull: Sprite2D = shaken.get_node("Hull")
	var turret: Sprite2D = shaken.get_node("Turret")
	var sheet: IsoSheetDef = _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
	var mount: Vector2 = sheet.mount(UnitLayer.D_EAST) * WorldSort.ART_SCALE
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	_camera.position = shaken.position
	var writes: int = _layer.life_writes()  # The old match's two shake writes and its look.
	_at_ms(9800.0)
	assert_vector(_expect.shake_offset(Rig.ENEMY_TANK, 9800.0)).is_not_equal(Vector2.ZERO)
	var rests_until: float = _expect.span_to
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(5)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(writes + 1)  # The look, from rest.
	_at_ms(rests_until - 1.0)
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(writes + 1)
	var wrong: int = 0
	var frame_ms: float = rests_until
	for _frame_index: int in 120:  # Two seconds on, the look's end among them.
		_at_ms(frame_ms)
		var want: Vector2 = _expect.shake_offset(Rig.ENEMY_TANK, _now())
		var side: int = _expect.look_side(Rig.ENEMY_TANK, _now())
		if not hull.position.is_equal_approx(want):
			wrong += 1
		if not turret.position.is_equal_approx(mount + want):
			wrong += 1
		if Frames.dir(_layer, row, &"turret") != UnitLayer.D_EAST + side:
			wrong += 1
		frame_ms += 1000.0 / 60.0
	assert_int(wrong).is_equal(0)


func test_frames_of_idle_life_leave_no_object_or_node_behind() -> void:
	# Over 25 s the light tank looks to both sides and shakes throughout.
	_watch(Rig.LIGHT)
	for frame: int in 1500:
		_frame(frame)
	var objects: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var writes: int = _layer.life_writes()
	for frame: int in range(1500, 2500):
		_frame(frame)
	var objects_after: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes_after: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	assert_int(_layer.life_writes()).is_greater(writes)
	assert_int(objects_after).is_equal(objects)  # Read before the asserts, which make objects.
	assert_int(nodes_after).is_equal(nodes)


## A layer on the fixture runner with the settings `life`, and the `RigLife` that says what a frame
## should show.
func _start(life: LifeSettings) -> void:
	if is_instance_valid(_layer):
		_layer.free()
	_life = life
	_expect = RigLife.new()
	_expect.setup(_life)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.life = _life
	if not is_instance_valid(_camera):
		_camera = auto_free(RtsCamera.new())
		add_child(_camera)
	_camera.position = Vector2(FAR, FAR)  # Nothing in view, so every rig is made at rest.
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


## Points the camera at the rig of unit `id`, and lets the rig settle: a rig that has just become
## idle rests for the step it is in and shakes from the next one, so a frame 100 ms before the
## play (match time 1900 ms, the play starts at 2000) comes first.
func _watch(id: int) -> void:
	_camera.position = _rig(_runner.snapshot.index_of(id)).position
	_at_ms(1900.0)


## Gives unit `id` a target it holds, as the sim writes it, so it is not idle.
func _pin_down(id: int) -> void:
	_runner.snapshot.target[_runner.snapshot.index_of(id)] = 99999


## Frame `index` of a 60 fps play from tick 30: four frames to a tick.
func _frame(index: int) -> void:
	Rig.at(_runner, 30 + index / FRAMES_PER_TICK, float(index % FRAMES_PER_TICK) / FRAMES_PER_TICK)
	_layer._process(0.0)


## One frame at match time `ms`.
func _at_ms(ms: float) -> void:
	var ticks: float = ms * float(Sim.TICK_RATE) / 1000.0
	var tick: int = floori(ticks)
	Rig.at(_runner, tick, ticks - float(tick))
	_layer._process(0.0)


## The match time the layer reads, as `LifeClock` gives it.
func _now() -> float:
	return LifeClock.ms(_runner.snapshot, _runner.alpha())


func _rig(row: int) -> Node2D:
	return _layer.rig(row)
