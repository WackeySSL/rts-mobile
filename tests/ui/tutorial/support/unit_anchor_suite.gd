extends GdUnitTestSuite
## The set-up of the `GuideUnitAnchor` suites (plan P593b-1): controls_test's runner, a camera over
## it, both unit layers and the helpers. Not a test suite.

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const SAFE: Rect2 = Rect2(0.0, 0.0, 1280.0, 720.0)
const NO_RECTS: Dictionary[StringName, Rect2] = {}

var _runner: MatchRunner
var _camera: RtsCamera
var _ground: UnitLayer
var _air: AirLayer
var _anchor: GuideUnitAnchor
var _hud: Dictionary[StringName, Rect2] = {}


func before_test() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_ground = auto_free(UnitLayer.new())
	_ground.runner = _runner
	_ground.camera = _camera
	add_child(_ground)
	_ground.set_process(false)
	_air = auto_free(Air.layer(self, _runner))
	_anchor = GuideUnitAnchor.new()
	_hud = {}
	_see_all()


func after_test() -> void:
	CommandQueue.clear()


func _aim(side: TutorialUnitPickDef.Whose, pick: TutorialUnitPickDef.Pick) -> TutorialLeadInDef:
	var def: TutorialUnitPickDef = TutorialUnitPickDef.new()
	def.side = side
	def.pick = pick
	var step: TutorialLeadInDef = TutorialLeadInDef.new()
	step.anchor = TutorialBeatDef.Anchor.UNIT
	step.unit = def
	return step


func _update(aim: TutorialLeadInDef) -> void:
	_anchor.update(aim, _runner, _camera, _ground, _air, SAFE, 1.0, _hud)


func _tick() -> void:
	_runner.run_ticks(1)
	_see_all()


func _see_all() -> void:
	var fog: FogGrid = _runner.snapshot.fog
	var tiles: Array = []
	for cell: int in fog.cells:
		tiles.append(Vector2i(cell % fog.cols, cell / fog.cols))
	Buildings.see(_runner.snapshot, 1, tiles)


## The camera over unit `id`'s tick position.
func _look_at(id: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	_camera.position = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
