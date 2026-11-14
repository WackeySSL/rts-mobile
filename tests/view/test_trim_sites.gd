extends GdUnitTestSuite
## The atlas trim at its sites (plan P306): the sites that change a directional frame, driven
## through the real layers, draw the box the untrimmed frame drew, at bake scale 1.0 and 0.875
## (`trim_check.gd`): a vehicle hull and turret turning (`WorldSort.show_frame`), a defence's head
## sweeping, turning to a target and kicking (`BuildingLayer`). The static frames are in
## test_iso_atlas_trim.gd, the ghost's head in test_ghost_layer.gd and the squads' poses in
## test_squad_poses.gd. Fixtures: recoil_rig.gd.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Trim: GDScript = preload("res://tests/view/support/trim_check.gd")
const SCALES: Array[float] = [1.0, 0.875]

var _runner: MatchRunner
var _layer: BuildingLayer
var _bake: float = 1.0


func before_test() -> void:
	_runner = auto_free(Rig.runner())


func after_test() -> void:
	CommandQueue.clear()


func test_a_vehicle_hull_and_turret_turned_through_every_direction_draw_the_same_box() -> void:
	for bake: float in SCALES:
		var sort: WorldSort = _sort(bake)
		var layer: UnitLayer = auto_free(UnitLayer.new())
		layer.runner = _runner
		layer.world_sort = sort
		layer.life = Rig.calmed(null)
		var camera: RtsCamera = auto_free(RtsCamera.new())
		add_child(camera)
		layer.camera = camera
		add_child(layer)
		layer.set_process(false)
		layer._process(0.0)
		var row: int = _runner.snapshot.index_of(Rig.LIGHT)
		var sheet: IsoSheetDef = sort.sheet(&"light_tank")
		var rig: Node2D = layer.rig(row)
		var checked: int = 0
		for part: StringName in [&"hull", &"turret"]:
			var sprite: Sprite2D = rig.get_node(String(part).capitalize())
			for dir: int in sheet.directions(part):
				sort.show_frame(sprite, sheet, part, dir, 1)
				var problem: String = Trim.problem(sprite, sheet, part, dir, 0, bake)
				(
					assert_str(problem)
					. override_failure_message("%s at %s" % [problem, bake])
					. is_empty()
				)
				checked += 1
		assert_int(checked).is_greater(16)


func test_a_defences_head_sweeping_draws_the_box_of_each_frame() -> void:
	for bake: float in SCALES:
		_layer = _make_layer(LifeSettings.new(), bake)
		var seen: Dictionary[int, bool] = {}
		for ms: int in range(0, 6000, 100):
			_at_ms(float(ms))
			seen[Buildings.head_frame(_layer, Rig.REDOUBT)] = true
			_assert_head(bake)
		assert_int(seen.size()).is_greater(2)  # It really swept.


func test_a_defences_head_turning_to_a_target_draws_the_box_of_its_new_frame() -> void:
	for bake: float in SCALES:
		_layer = _make_layer(LifeSettings.new(), bake)
		var snap: MatchSnapshot = _runner.snapshot
		var row: int = snap.index_of(Rig.REDOUBT)
		_at_ms(1000.0)
		var before: int = Buildings.head_frame(_layer, Rig.REDOUBT)
		snap.target_row[row] = snap.index_of(Rig.ENEMY_TANK)  # Far to the south east.
		Buildings.see(snap, 1, [Rig.FAR_TILE])
		_layer._process(1.0)  # A long frame: the head turns all the way.
		assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_not_equal(before)
		_assert_head(bake)


func test_a_defences_head_kicking_keeps_the_box_of_its_frame() -> void:
	for bake: float in SCALES:
		_layer = _make_layer(Rig.calmed(null), bake)
		var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
		var from: Vector2i = Rig.position_of(_runner, Rig.REDOUBT)
		var events: PackedInt32Array = Rig.shot(
			_runner, Rig.REDOUBT, from, Rig.EAST_ON_SCREEN, &"redoubt_gun"
		)
		Rig.deliver(_runner, events, Rig.SHOT_TICK)
		var mount: Vector2 = head.position
		var moved: bool = false
		for sample: Vector2 in Rig.SAMPLES:
			Rig.at(_runner, int(sample.x), sample.y)
			_layer._process(0.0)
			moved = moved or head.position != mount
			_assert_head(bake)
		assert_bool(moved).is_true()


## The head of the Redoubt draws the untrimmed box of the frame it shows.
func _assert_head(bake: float) -> void:
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var sheet: IsoSheetDef = _layer.world_sort.sheet(&"defence_turret")
	var dir: int = Buildings.head_frame(_layer, Rig.REDOUBT)
	assert_int(dir).is_greater_equal(0)
	var problem: String = Trim.problem(head, sheet, &"head", dir, 0, bake)
	assert_str(problem).override_failure_message("%s at %s" % [problem, bake]).is_empty()


## A sorted world baked at `bake` for the fixture match.
func _sort(bake: float) -> WorldSort:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.bake_scale = bake
	sort.runner = _runner
	add_child(sort)
	return sort


func _make_layer(life: LifeSettings, bake: float) -> BuildingLayer:
	if is_instance_valid(_layer):
		_layer.free()
	var layer: BuildingLayer = auto_free(BuildingLayer.new())
	layer.runner = _runner
	layer.life = life
	Rig.at(_runner, 0, 0.0)  # A new layer starts at the start of the match.
	layer.world_sort = _sort(bake)
	add_child(layer)
	layer.set_process(false)
	layer._process(0.0)
	assert_float(layer.world_sort.atlas.bake_scale()).is_equal(bake)
	return layer


func _at_ms(ms: float) -> void:
	var ticks: float = ms * float(Sim.TICK_RATE) / 1000.0
	var tick: int = floori(ticks)
	Rig.at(_runner, tick, ticks - float(tick))
	_layer._process(0.0)
