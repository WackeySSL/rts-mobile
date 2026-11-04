extends GdUnitTestSuite
## The fixture and helpers of the building damage suites (plan P159): test_building_damage.gd,
## test_building_damage_flow.gd and test_building_damage_anim.gd extend this. A runner with
## Barracks, a hand-made sorted world around a crafted sheet and a `BuildingLayer` over it. Not a
## test suite.

const Dmg: GDScript = preload("res://tests/view/support/damage_rig.gd")
const BUILDING_LINES: PackedInt32Array = [67, 34]
const VEHICLE_LINES: PackedInt32Array = [50, 25]
const SCALES: Array[float] = [1.0, 0.5, 0.3, IsoAtlas.MIN_SCALE]

var _runner: MatchRunner
var _sort: WorldSort
var _layer: BuildingLayer
var _def: IsoSheetDef
var _camera: RtsCamera
var _life: LifeSettings  ## Set before `_open` to give the layer these numbers.


func after_test() -> void:
	CommandQueue.clear()


func _open(spawns: Array, extras: Dictionary = {}, scale: float = 1.0, reveal: bool = true) -> void:
	_def = Dmg.sheet(extras)
	_runner = auto_free(Dmg.runner(spawns))
	_sort = auto_free(Dmg.sort(_runner, _def, scale))
	add_child(_sort)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	_layer.world_sort = _sort
	_layer.camera = _camera
	_layer.reveal_enemies = reveal
	_layer.life = _life
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func _pair() -> Array:
	return [[1, 4, 4], [2, 14, 14]]


func _body(id: int) -> Sprite2D:
	return _layer.building(id).get_node("Body")


func _patch(id: int) -> Sprite2D:
	return _layer.building(id).get_node_or_null("Damage") as Sprite2D


## Sets building `id` to `percent` of its hp, ticks once and draws a frame.
func _hit(id: int, percent: int) -> void:
	Dmg.hit(_runner, id, percent)
	_layer._process(0.0)


func _region(part: StringName) -> Rect2i:
	return _sort.atlas.region(Dmg.ART_ID, part, -1)


## The body shows from `IsoAtlas.body_cut_row` down and the patch of `stage` its whole region.
func _check_stage(id: int, stage: int) -> void:
	var body: Sprite2D = _body(id)
	var patch: Sprite2D = _patch(id)
	var full: Rect2i = _region(&"hull")
	var cut: int = IsoAtlas.body_cut_row(Dmg.CUTS[stage - 1], Dmg.BODY_PX, full.size.y)
	assert_that(body.region_rect).is_equal(
		Rect2(full.position.x, full.position.y + cut, full.size.x, full.size.y - cut)
	)
	var per_px: Vector2 = _sort.texels(_def, &"hull")
	assert_float(body.offset.y).is_equal_approx(
		-float(_def.origin(&"hull").y) * per_px.y + cut, 0.001
	)
	assert_bool(body.region_filter_clip_enabled).is_true()
	var part: StringName = &"dmg%d" % stage
	assert_bool(patch.visible).is_true()
	assert_that(patch.region_rect).is_equal(Rect2(_region(part)))  # Its whole region.
	assert_vector(patch.position).is_equal(body.position)  # A sibling at the same place.
	assert_object(patch.get_parent()).is_same(body.get_parent())
	assert_bool(patch.region_filter_clip_enabled).is_false()
	var patch_scale: Vector2 = _sort.texels(_def, part)
	assert_vector(patch.scale).is_equal_approx(
		Vector2(WorldSort.ART_SCALE / patch_scale.x, WorldSort.ART_SCALE / patch_scale.y),
		Vector2(1e-4, 1e-4)
	)


func _centre_camera(id: int) -> void:
	_camera.position = _layer.building(id).position


func _grid(count: int) -> Array:
	var spawns: Array = []
	for i: int in count:
		spawns.append([1, 1 + (i % 10) * 3, 1 + (i / 10) * 3])
	return spawns
