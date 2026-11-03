extends GdUnitTestSuite
## The fixture and helpers of the squad pose suites (plan P142): test_squad_poses.gd and
## test_squad_pose_rows.gd extend this. A paused runner whose tick and alpha a test sets (match
## time = (tick + alpha) x 1000 / 15 ms), a layer and a camera on the rifle squad, and a
## squad's position moved in the published snapshot by hand: prev = last position, pos = prev +
## step. Unit 1 is a Derrick League rifle squad (speed 67, stride 352, quarter 88), 2 a rocket
## squad, 3 a Lumen Accord rifle squad far away in the fog (speed 73, stride 376) and 4 a light
## tank. Not a test suite.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const RIFLE: int = 1
const ROCKET: int = 2
const ENEMY: int = 3
const TANK: int = 4
const SPEED: int = 67  ## The rifle squad's step, milli per tick.
const QUARTER: int = 88
const STRIDE: int = 352
const FIRST_TICK: int = 30
const SAMPLES: int = 4  ## Frames per tick: 60 fps over 15 Hz.
const FAR: float = 1.0e6
## Where the rifle squad (id 1) shows idle frames, standing from 0 ms (test_squad_pose_life.gd's
## Python restatement): [from, to, frame] three times over.
const WINDOWS: Array[int] = [2874, 3474, 0, 9362, 9962, 1, 15427, 16027, 1]

var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _life: LifeSettings
var _expect: RigLife


func before_test() -> void:
	_runner = auto_free(_fixture())
	_start(LifeSettings.new())


func after_test() -> void:
	CommandQueue.clear()


## The paused fixture runner: two own squads, a hidden Lumen Accord one and an own light tank.
func _fixture() -> MatchRunner:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "rifle_squad", 10, 10),
		Buildings.spawn(1, "rocket_squad", 12, 10),
		Buildings.spawn(2, "renew_rifle", 28, 28),
		Buildings.spawn(1, "light_tank", 14, 10),
	]
	return Buildings.runner(Buildings.scenario(spawns))


## A layer on the fixture runner with the settings `life`, and the `RigLife` that says what a frame
## should show. The camera looks at the rifle squad.
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
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)
	_camera.position = FAR * Vector2.ONE
	_layer._process(0.0)  # Every rig is made, and stands since match time 0.
	_camera.position = _layer.rig(_runner.snapshot.index_of(RIFLE)).position


## A new match and layer, for a test that starts twice.
func _restart(life: LifeSettings) -> void:
	_runner = auto_free(_fixture())
	_start(life)


func _row(id: int) -> int:
	return _runner.snapshot.index_of(id)


func _rig(row: int) -> Node2D:
	return _layer.rig(row)


func _hull(row: int) -> Sprite2D:
	return _rig(row).get_node("Hull") as Sprite2D


## The offset the Hull has for `part` of the unit's sheet, as the dress and the atlas say it.
func _offset(row: int, part: StringName) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var sheet: IsoSheetDef = _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
	return -Vector2(sheet.origin(part)) * _layer.world_sort.atlas.bake_scale()


## What the Hull of `row` shows, read back from the atlas: (pose, frame) of direction `dir`, or
## (-1, -1) when the region is none of the squad's pose frames.
func _shown(row: int, dir: int = UnitLayer.D_EAST) -> Vector2i:
	var snap: MatchSnapshot = _runner.snapshot
	var art: StringName = snap.type_ids[snap.type_index[row]]
	var sheet: IsoSheetDef = _layer.world_sort.sheet(art)
	var slot: int = _layer.world_sort.slot_of(snap.owner[row])
	var region: Rect2i = Rect2i(_hull(row).region_rect)
	for pose: int in RigLife.POSE_PARTS.size():
		var part: StringName = RigLife.POSE_PARTS[pose]
		for frame: int in sheet.frame_count(part):
			if region == _layer.world_sort.atlas.region(art, part, dir, slot, frame):
				return Vector2i(pose, frame)
	return Vector2i(-1, -1)


## `ticks` ticks from tick FIRST_TICK + `from` in which squad `row` moves (dx, dy) milli each, four
## frames to a tick; every frame's (pose, frame).
func _walk(
	row: int, ticks: int, dx: int, dy: int, from: int = 0, read: bool = true
) -> Array[Vector2i]:
	var shown: Array[Vector2i] = []
	var snap: MatchSnapshot = _runner.snapshot
	for tick: int in ticks:
		snap.prev_pos_x[row] = snap.pos_x[row]
		snap.prev_pos_y[row] = snap.pos_y[row]
		snap.pos_x[row] += dx
		snap.pos_y[row] += dy
		for part: int in SAMPLES:
			Rig.at(_runner, FIRST_TICK + from + tick, float(part) / SAMPLES)
			_layer._process(0.0)
			if read:
				shown.append(_shown(row))
	return shown


## One frame of tick `tick` in which squad `row` did not move.
func _still(row: int, tick: int, alpha: float) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_x[row] = snap.pos_x[row]
	snap.prev_pos_y[row] = snap.pos_y[row]
	Rig.at(_runner, tick, alpha)
	_layer._process(0.0)


## One frame at match time `ms`.
func _at_ms(ms: float) -> void:
	var ticks: float = ms * float(Sim.TICK_RATE) / 1000.0
	var tick: int = floori(ticks)
	Rig.at(_runner, tick, ticks - float(tick))
	_layer._process(0.0)


## The walk frames of a squad of the given step, per sample, as the rule says, with plain sums.
func _expected(ticks: int, step: int, phase: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tick: int in ticks:
		for part: int in SAMPLES:
			var travel: int = tick * step + int(float(part) / SAMPLES * float(step))
			out.append(Vector2i(RigLife.POSE_WALK, (travel + phase) / QUARTER % 4))
	return out


## How many times the frame changes along `shown`.
func _changes(shown: Array[Vector2i]) -> int:
	var count: int = 0
	for at: int in range(1, shown.size()):
		if shown[at] != shown[at - 1]:
			count += 1
	return count


## The start of the first idle window of unit `id` after it began to stand, in match ms, by the
## function's own answer in whole ms. The unit must have stood in a frame since it last walked.
func _first_window(id: int) -> int:
	var still: float = (_rig(_row(id)) as UnitLayer.Rig).idle.still_ms
	assert_float(still).is_greater_equal(0.0)
	var now: float = still + 0.5
	while _expect.pose_idle(id, still, now, 2) < 0:
		now += 1.0
	return floori(now)


## A fixed play for the determinism test: a walk, a stand through two windows, a walk back.
func _play() -> Array:
	var row: int = _row(RIFLE)
	var out: Array = _walk(row, 20, SPEED, 0)
	_still(row, FIRST_TICK + 20, 0.0)
	for ms: int in range(3400, 14000, 50):
		_at_ms(float(ms) + 0.5)
		out.append(_shown(row))
		out.append(_hull(row).offset)
	out.append_array(_walk(row, 20, 47, 47, 400))
	return out


## A second of walking and six seconds of standing from tick `tick` (counted from FIRST_TICK):
## the tick it ends on.
func _cycle(row: int, tick: int) -> int:
	_walk(row, 15, SPEED, 0, tick, false)
	_still(row, FIRST_TICK + tick + 15, 0.0)
	for ms: int in range(0, 6000, 100):
		_at_ms(LifeClock.tick_ms(FIRST_TICK + tick + 15) + float(ms) + 0.5)
	return tick + 15 + 90
