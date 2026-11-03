extends GdUnitTestSuite
## The idle look of a turreted vehicle (plan P140, ADR 0027 sections 1, 3 and 8): with no target and
## standing in view it turns its turret one frame aside (d05 or d07 off the d06 it faces) for
## `look_ms` in each cycle of 6 to 10 s, by the turret's region only. A move, a target and `reduced`
## put it back on its aim, a squad never looks, and the look is a frame off the aim the turret has
## now. The function is in test_idle_life.gd; the rumble is in test_idle_units.gd. Fixtures:
## recoil_rig.gd; the light tank (id 1) looks west for 900 ms from 2192, 10160 and 15321 ms, east
## from 21730 and west from 26998 (the Python restatement of the function).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const TOL: Vector2 = Vector2(0.001, 0.001)
const FAR: float = 1.0e6

var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _life: LifeSettings


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_life = LifeSettings.new()
	_life.idle_ms = 0  # The squad's idle pose is a life write too (test_squad_poses.gd).
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.life = _life
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(FAR, FAR)  # Nothing in view, so every rig is made at rest.
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_a_turreted_vehicle_looks_one_frame_aside_in_the_pinned_windows() -> void:
	# The light tank (id 1) over 30 s, a frame every 100 ms, standing: its
	# turret shows the hull's frame d06, and one frame aside (d05 or d07) for 900 ms in each of the
	# windows the Python restatement gives: 2192 (west), 10160, 15321, 21730 (east) and 26998 ms.
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	_watch(Rig.LIGHT)
	var shown: Array[int] = []
	var times: Array[int] = []
	var hull_moved: int = 0
	for ms: int in range(0, 30000, 100):
		_at_ms(float(ms) + 0.5)
		var dir: int = Frames.dir(_layer, row, &"turret")
		if shown.is_empty() or shown[-1] != dir:
			shown.append(dir)
			times.append(ms)
		if Frames.dir(_layer, row, &"hull") != UnitLayer.D_EAST:
			hull_moved += 1
	assert_int(hull_moved).is_equal(0)
	assert_array(shown).is_equal([6, 5, 6, 5, 6, 5, 6, 7, 6, 5, 6])
	# Sampled every 100 ms: a window shows from the first sample at or after its start to the last
	# one before its end.
	assert_array(times).is_equal(
		[0, 2200, 3100, 10200, 11100, 15400, 16300, 21800, 22700, 27000, 27900]
	)
	assert_int(_layer.life_writes()).is_equal(10)  # Two region writes for each window, no other.
	assert_vector(turret.position).is_equal_approx(mount, TOL)  # The look is a region, not a move.


func test_a_look_ends_when_the_vehicle_moves_or_fires_and_reduced_has_none() -> void:
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var snap: MatchSnapshot = _runner.snapshot
	_watch(Rig.LIGHT)
	_at_ms(2500.0)  # In the first window (2192 to 3092), looking west.
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(5)
	snap.prev_pos_x[row] = snap.pos_x[row] - 10  # It moved a hair: not idle, so back on its aim.
	_at_ms(2600.0)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(6)
	snap.prev_pos_x[row] = snap.pos_x[row]
	_at_ms(2700.0)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(5)
	snap.target[row] = 99999  # A held target.
	_at_ms(2800.0)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(6)
	snap.target[row] = 0
	_at_ms(2900.0)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(5)
	assert_int(_layer.life_writes()).is_equal(5)  # Aside, back, aside, back, aside: one each.
	_life.reduced = true
	_at_ms(3000.0)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(6)
	assert_int(_layer.life_writes()).is_equal(6)  # `reduced` puts it back on its aim: one write.
	_at_ms(10300.0)  # The second window (10160 to 11060): nothing with `reduced`.
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(6)
	assert_int(_layer.life_writes()).is_equal(6)
	_life.reduced = false
	_at_ms(10400.0)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(5)
	assert_int(_layer.life_writes()).is_equal(7)


func test_a_look_is_one_frame_off_the_aim_the_turret_has_and_a_squad_never_looks() -> void:
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var snap: MatchSnapshot = _runner.snapshot
	_watch(Rig.LIGHT)
	snap.prev_pos_y[row] = snap.pos_y[row] - snap.type_speed[snap.type_index[row]]
	_layer._process(1.0)  # It drove south on the grid: the hull and, with no target, the turret turn.
	snap.prev_pos_y[row] = snap.pos_y[row]
	_layer._process(1.0)
	var aim: int = Frames.dir(_layer, row, &"hull")
	assert_int(aim).is_not_equal(UnitLayer.D_EAST)
	assert_int(Frames.dir(_layer, row, &"turret")).is_equal(aim)
	_at_ms(2500.0)  # In its window: one frame off the aim it has now.
	assert_int(absi(posmod(Frames.dir(_layer, row, &"turret") - aim + 8, 16) - 8)).is_equal(1)
	var squad: int = snap.index_of(Rig.SQUAD)
	assert_int(Frames.dir(_layer, squad, &"hull")).is_equal(UnitLayer.D_EAST)


func test_a_standing_vehicle_never_shakes_and_still_looks_with_its_gun() -> void:
	# Over 60 s of a stand, with no target and in view, neither tank's Hull or Turret moves by a
	# pixel: the writes are the looks alone, which change the Turret's region (the light tank looks
	# west at 2192 ms, d05 off its d06).
	var light: int = _runner.snapshot.index_of(Rig.LIGHT)
	var heavy: int = _runner.snapshot.index_of(Rig.HEAVY)
	var parts: Array[Node2D] = [_rig(light), _rig(heavy)]
	var rest: Array[Vector2] = []
	for rig: Node2D in parts:
		rest.append((rig.get_node("Hull") as Sprite2D).position)
		rest.append((rig.get_node("Turret") as Sprite2D).position)
	_camera.position = (parts[0].position + parts[1].position) * 0.5
	_at_ms(1900.0)
	var moved: int = 0
	var looked: bool = false
	for ms: int in range(1900, 61900, 50):
		_at_ms(float(ms))
		for index: int in parts.size():
			var hull: Sprite2D = parts[index].get_node("Hull")
			var turret: Sprite2D = parts[index].get_node("Turret")
			if not hull.position.is_equal_approx(rest[2 * index]):
				moved += 1
			if not turret.position.is_equal_approx(rest[2 * index + 1]):
				moved += 1
		looked = looked or Frames.dir(_layer, light, &"turret") != UnitLayer.D_EAST
	assert_int(moved).is_equal(0)
	assert_bool(looked).is_true()  # The impatient look of the gun is still there.
	assert_int(_layer.life_writes()).is_greater(0)


func test_a_standing_vehicle_with_the_look_off_writes_nothing_over_a_long_stand() -> void:
	_life.look_ms = 0
	_watch(Rig.LIGHT)
	for ms: int in range(1900, 91900, 50):
		_at_ms(float(ms))
	assert_int(_layer.life_writes()).is_equal(0)


func test_a_creep_under_half_a_step_neither_rumbles_nor_looks() -> void:
	# The separation pushes a unit that has arrived by a few milli a tick for a while: not a drive
	# (no rumble), and not a stand (no look either). Over 12 s, which hold the light tank's
	# windows at 2192 and 10160 ms, with a creep of 1 to 5 milli in each tick the Hull never
	# moves, the turret never looks, and nothing is written.
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var snap: MatchSnapshot = _runner.snapshot
	_pin_down(Rig.HEAVY)
	snap.order[row] = World.Order.MOVE  # Even on an order: a slow final approach is no drive.
	var hull: Sprite2D = _rig(row).get_node("Hull")
	_watch(Rig.LIGHT)
	var wrong: int = 0
	for creep: int in range(1, 6):
		snap.prev_pos_x[row] = snap.pos_x[row] - creep
		for ms: int in range(2000, 12000, 100):
			_at_ms(float(ms))
			wrong += 0 if hull.position == Vector2.ZERO else 1
			wrong += 0 if Frames.dir(_layer, row, &"turret") == UnitLayer.D_EAST else 1
	assert_int(wrong).is_equal(0)
	assert_int(_layer.life_writes()).is_equal(0)


## Points the camera at the rig of unit `id`, and lets the rig settle with a frame at 1900 ms.
func _watch(id: int) -> void:
	_camera.position = _layer.rig(_runner.snapshot.index_of(id)).position
	_at_ms(1900.0)


## Gives unit `id` a target it holds, as the sim writes it, so it is not idle.
func _pin_down(id: int) -> void:
	_runner.snapshot.target[_runner.snapshot.index_of(id)] = 99999


## One frame at match time `ms`.
func _at_ms(ms: float) -> void:
	var ticks: float = ms * float(Sim.TICK_RATE) / 1000.0
	var tick: int = floori(ticks)
	Rig.at(_runner, tick, ticks - float(tick))
	_layer._process(0.0)


func _rig(row: int) -> Node2D:
	return _layer.rig(row)
