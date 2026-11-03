extends GdUnitTestSuite
## The idle life across a WORKER resume (plan P140, ADR 0027 section 2, "Resume"): after a pause or
## a background the runner restarts alpha at 0 in its first frame, so the match time (tick + alpha)
## can step back by up to one tick, and nothing may play backwards. The idle functions are functions
## of match time, so each layer reads them at an idle clock that never goes back in a match
## (`RigLife.idle_clock`) and starts again with the next one. A frame that steps back changes no
## region and no offset and writes nothing, in the unit layer (shake and look) and in the building
## layer (sweep). Fixtures: recoil_rig.gd. By the restatement of the functions: the light tank
## (id 1) at tick 32 and alpha 0.9 (2193.3 ms) is at (-0.5, 0) and looking west (d05), at tick 32
## and alpha 0 (2133.3 ms) it would be at rest and straight, at tick 33 (2200 ms) it is as at
## 2193.3 again; the Redoubt (id 4) at tick 14 and alpha 0.9 (993.3 ms) is one frame off its aim,
## at tick 14 and alpha 0 (933.3 ms) it would be on it, at tick 15 (1000 ms) one frame off again.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const FAR: float = 1.0e6
const AIM: int = 6

var _runner: MatchRunner
var _units: UnitLayer
var _heads: BuildingLayer
var _camera: RtsCamera


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(FAR, FAR)  # Nothing in view until a test looks at a tank.
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	add_child(_units)
	_units.set_process(false)
	_units._process(0.0)
	_heads = auto_free(BuildingLayer.new())
	_heads.runner = _runner
	add_child(_heads)
	_heads.set_process(false)
	_heads._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_a_resume_plays_the_vehicles_shake_and_look_no_pose_backwards() -> void:
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _units.rig(row).get_node("Hull")
	_camera.position = _units.rig(row).position
	_frame(28, 0.5)  # 1900 ms: seen, at rest.
	_frame(32, 0.9)  # 2193.3 ms: shaking (-0.5, 0) and looking west.
	assert_vector(hull.position).is_equal(Vector2(-0.5, 0.0))
	assert_int(Frames.dir(_units, row, &"turret")).is_equal(5)
	var writes: int = _units.life_writes()
	assert_int(writes).is_equal(3)  # Hull, Turret and the look.
	_frame(32, 0.0)  # The resume: alpha restarts at 0, a pose 60 ms back.
	assert_vector(hull.position).is_equal(Vector2(-0.5, 0.0))
	assert_int(Frames.dir(_units, row, &"turret")).is_equal(5)
	assert_int(_units.life_writes()).is_equal(writes)
	_frame(33, 0.0)  # And the tick after it, back at the pose it had.
	assert_vector(hull.position).is_equal(Vector2(-0.5, 0.0))
	assert_int(Frames.dir(_units, row, &"turret")).is_equal(5)
	assert_int(_units.life_writes()).is_equal(writes)
	_frame(34, 0.5)  # 2300 ms: on, forward again, (0.5, 0.5) in the same window.
	assert_vector(hull.position).is_equal(Vector2(0.5, 0.5))
	assert_int(_units.life_writes()).is_equal(writes + 2)


func test_a_resume_plays_the_defences_sweep_no_frame_backwards() -> void:
	_frame(14, 0.9)  # 993.3 ms: one frame off the aim.
	assert_int(Buildings.head_frame(_heads, Rig.REDOUBT)).is_equal(AIM + 1)
	var writes: int = _heads.life_writes()
	_frame(14, 0.0)  # The resume: 60 ms back, where it was on its aim.
	assert_int(Buildings.head_frame(_heads, Rig.REDOUBT)).is_equal(AIM + 1)
	assert_int(_heads.life_writes()).is_equal(writes)
	_frame(15, 0.0)
	assert_int(Buildings.head_frame(_heads, Rig.REDOUBT)).is_equal(AIM + 1)
	assert_int(_heads.life_writes()).is_equal(writes)
	_frame(20, 0.0)  # 1333 ms, still in the hold from 945 ms: no write.
	assert_int(_heads.life_writes()).is_equal(writes)
	_frame(25, 0.0)  # 1667 ms: the next hold, two frames off the aim.
	assert_int(Buildings.head_frame(_heads, Rig.REDOUBT)).is_equal(AIM + 2)
	assert_int(_heads.life_writes()).is_equal(writes + 1)


func test_a_new_match_starts_the_idle_clock_again() -> void:
	# A clock that never goes back must not carry one match into the next: after 5 s of the old one,
	# the new match's 1.3 s is where the sweep is one frame off its aim, not where it stood at 5 s
	# (two frames off, the other way), and the light tank's window to the west at 2193 ms opens.
	_frame(75, 0.0)  # 5000 ms.
	_frame(75, 0.5)
	assert_int(Buildings.head_frame(_heads, Rig.REDOUBT)).is_equal(AIM - 2)
	_runner.start()
	_frame(0, 0.0)  # The first frame of the new match: its rigs are made.
	_pin_down(Rig.HEAVY)
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	_camera.position = _units.rig(row).position
	_frame(20, 0.0)  # 1333 ms of the new match.
	assert_int(Buildings.head_frame(_heads, Rig.REDOUBT)).is_equal(AIM + 1)
	_frame(28, 0.5)  # 1900 ms: the light tank is seen at rest.
	_frame(32, 0.9)  # 2193.3 ms: it looks west.
	assert_int(Frames.dir(_units, row, &"turret")).is_equal(5)


## Gives unit `id` a target it holds, as the sim writes it, so it is not idle.
func _pin_down(id: int) -> void:
	_runner.snapshot.target[_runner.snapshot.index_of(id)] = 99999


## One frame of both layers at tick `tick` and alpha `alpha`.
func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_units._process(0.0)
	_heads._process(0.0)
