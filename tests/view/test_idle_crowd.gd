extends GdUnitTestSuite
## The idle life of a crowd (plan P140, ADR 0027 sections 3 and 9): 40 heavy and 30 light tanks of
## player 1 stand in view with no target, seen from 1900 ms and played at 60 fps from there, a
## frame every 16.7 ms (`1900 + k x 1000 / 60`). The per-id phases spread the writes: a rig that
## has just become idle, or is seen again after the camera has been elsewhere, rests for the step
## it is in and shakes from the next one, so no frame writes more than a fraction of the 140
## sprites, and the rigs stay inside ADR 0027 section 9's 150 sprite writes a frame and 60 on
## average. The counts are restated in Python from the same functions (a second implementation)
## and match the layer's. Fixtures: building_rig.gd's 32 x 32 map with the crowd of
## `_crowd_scenario`.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const HEAVY_TANKS: int = 40
const LIGHT_TANKS: int = 30
const FAR: float = 1.0e6
const OVER: Vector2 = Vector2(0.0, 240.0)  ## Where the camera sees the whole crowd at zoom 0.5.
## The sprite writes of the first eight frames, with the look off: none in the first, then what the
## tanks whose first step is over write, 38 at the most (a mutant that does not rest writes 132).
const FIRST_FRAMES: Array[int] = [0, 38, 18, 22, 26, 26, 38, 34]
## The same with the look on (the turrets that look aside add one write each).
const FIRST_FRAMES_LOOKING: Array[int] = [12, 39, 18, 22, 26, 26, 39, 34]
## The twelve frames after a camera that was away from frame 240 to 359 is back at frame 360, the
## look on: the tanks rest again for their first step, so the first frame writes only the looks
## and the rest follows as when they were first seen. Without the rest it writes 137 in the first.
const FRAMES_BACK: Array[int] = [15, 40, 24, 22, 24, 24, 38, 34, 15, 30, 28, 31]

var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _life: LifeSettings
var _expect: RigLife  ## The same numbers, to say what a frame should show.


func before_test() -> void:
	_runner = auto_free(Buildings.runner(_crowd_scenario()))
	_life = LifeSettings.new()
	_expect = RigLife.new()
	_expect.setup(_life)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(FAR, FAR)  # Nothing in view, so every rig is made at rest.
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.life = _life
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)
	_camera.position = OVER
	_camera.zoom = Vector2(0.5, 0.5)


func after_test() -> void:
	CommandQueue.clear()


func test_seventy_standing_tanks_write_inside_the_budget_and_each_at_most_once_per_shake_ms(
) -> void:
	# Each tank rests until its own first step is over (the first 80 ms, by its phase) and shakes
	# after; frame 0 writes nothing and the busiest of the first frames, and of the 10 s, are the
	# restatement's. Per tank the Hull changes at most once per 80 ms; over all, at most 60 sprite
	# writes a frame on average and 150 in any frame (ADR 0027 section 9). The shake alone.
	_life.look_ms = 0
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(HEAVY_TANKS + LIGHT_TANKS)
	assert_int(_layer.count_in(_camera.visible_world_rect())).is_equal(HEAVY_TANKS + LIGHT_TANKS)
	var hulls: Array[Sprite2D] = []
	var last: PackedVector2Array = PackedVector2Array()
	var changes: PackedInt32Array = PackedInt32Array()
	var rests_until: PackedFloat64Array = PackedFloat64Array()
	for row: int in snap.unit_count():
		hulls.append(_layer.rig(row).get_node("Hull"))
		last.append(Vector2.ZERO)
		changes.append(0)
		_expect.shake_offset(snap.unit_id[row], 1900.0)
		rests_until.append(_expect.span_to)
	var total: int = 0
	var busiest: int = 0
	var early: int = 0
	var first_frames: Array[int] = []
	var frames: int = 600
	for frame: int in frames:
		var before: int = _layer.life_writes()
		_at_ms(1900.0 + float(frame) * 1000.0 / 60.0)
		var written: int = _layer.life_writes() - before
		total += written
		busiest = maxi(busiest, written)
		if frame < FIRST_FRAMES.size():
			first_frames.append(written)
		for row: int in hulls.size():
			if hulls[row].position != Vector2.ZERO and _now() < rests_until[row]:
				early += 1  # Shaking before its first step is over.
			if hulls[row].position != last[row]:
				changes[row] += 1
				last[row] = hulls[row].position
	var most: int = 0
	var fewest: int = frames
	for row: int in changes.size():
		most = maxi(most, changes[row])
		fewest = mini(fewest, changes[row])
	assert_int(early).is_equal(0)
	assert_array(first_frames).is_equal(FIRST_FRAMES)
	assert_int(busiest).is_equal(46)  # No frame takes every sprite (140): the restatement's.
	assert_int(total).is_equal(15544)  # 7772 changes in 10 s, two sprites for each.
	assert_int(most).is_equal(117)  # 125 steps of 80 ms, one in nine of them repeats the offset.
	assert_int(fewest).is_equal(102)
	assert_float(float(total) / frames).is_less_equal(60.0)
	assert_int(busiest).is_less_equal(150)


func test_panning_back_to_parked_vehicles_does_not_write_them_all_in_one_frame() -> void:
	# The crowd is seen for 4 s (frames 0 to 239), the camera is away for 2 s (240 to 359) and
	# comes back (frame 360). Nothing is written while it is away. Rigs that were shaking when it
	# left are seen again as if for the first time: each rests for the step it is in, so the first
	# frame back writes only the looks (15), and the frames after it what the tanks whose step is
	# over write, as when they were first seen (40, 24, 22, ...), 46 sprites at the most. A rig
	# that were not to rest would write 137 in the first frame back, and 150 vehicles ~290.
	var per_frame: Array[int] = []
	for frame: int in 400:
		if frame == 240:
			_camera.position = Vector2(FAR, FAR)
		elif frame == 360:
			_camera.position = OVER
		var before: int = _layer.life_writes()
		_at_ms(1900.0 + float(frame) * 1000.0 / 60.0)
		per_frame.append(_layer.life_writes() - before)
	var in_view: Array[int] = []
	var back: Array[int] = []
	var away: int = 0
	var busiest_in_view: int = 0
	var busiest_back: int = 0
	var total: int = 0
	for frame: int in 400:
		total += per_frame[frame]
		if frame < 240:
			busiest_in_view = maxi(busiest_in_view, per_frame[frame])
		elif frame < 360:
			away += per_frame[frame]
		else:
			busiest_back = maxi(busiest_back, per_frame[frame])
		if frame < FIRST_FRAMES_LOOKING.size():
			in_view.append(per_frame[frame])
		if frame >= 360 and frame < 360 + FRAMES_BACK.size():
			back.append(per_frame[frame])
	assert_array(in_view).is_equal(FIRST_FRAMES_LOOKING)
	assert_int(busiest_in_view).is_equal(46)
	assert_int(away).is_equal(0)
	assert_array(back).is_equal(FRAMES_BACK)
	assert_int(busiest_back).is_equal(46)  # As busy as when they were in view, and no busier.
	assert_int(total).is_equal(7335)


## One frame at match time `ms`.
func _at_ms(ms: float) -> void:
	var ticks: float = ms * float(Sim.TICK_RATE) / 1000.0
	var tick: int = floori(ticks)
	Rig.at(_runner, tick, ticks - float(tick))
	_layer._process(0.0)


## The match time the layer reads, as `LifeClock` gives it.
func _now() -> float:
	return LifeClock.ms(_runner.snapshot, _runner.alpha())


## 40 heavy and 30 light tanks of player 1 in blocks on the 32 x 32 map, none with a target.
func _crowd_scenario() -> ScenarioDef:
	var heavy: SpawnDef = Buildings.spawn(1, "heavy_tank", 2, 2)
	heavy.count = HEAVY_TANKS
	heavy.columns = 8
	heavy.spacing = 1300
	var light: SpawnDef = Buildings.spawn(1, "light_tank", 2, 16)
	light.count = LIGHT_TANKS
	light.columns = 8
	light.spacing = 1300
	var spawns: Array[SpawnDef] = [heavy, light]
	return Buildings.scenario(spawns)
