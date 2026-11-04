extends GdUnitTestSuite
## Fixtures of the vehicle damage suites (plan P161): a layer on a 32 x 32 map with the local player
## 1, who has a light tank (id 1, scar 600), a heavy tank (id 2, scar 800) and a rifle squad (id 3),
## a harvester (id 5, no turret: its rig kind is a squad's but for the damage bit) and player 2 a
## Lumen Accord tank (id 4) in the far corner, out of sight. The runner is paused and
## not in the tree, the idle life is off, so a life write is a damage write. Not a test suite of its
## own: the suites extend it.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Recoil: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LIGHT: int = 1
const HEAVY: int = 2
const SQUAD: int = 3
const ENEMY: int = 4
const HARVESTER: int = 5

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer
var _life: LifeSettings


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_open(1.0)


## A fresh match and layer whose sorted world bakes at `bake_scale` (a test may call it again).
func _open(bake_scale: float) -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "light_tank", 4, 4),
		Rig.spawn(1, "heavy_tank", 6, 4),
		Rig.spawn(1, "rifle_squad", 8, 4),
		Rig.spawn(2, "renew_tank", 28, 28),
		Rig.spawn(1, "harvester", 10, 4),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.runner = _runner
	sort.bake_scale = bake_scale
	add_child(sort)
	_life = Recoil.calmed(null)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.life = _life
	_layer.world_sort = sort
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


## Sets the hp of unit `id` to `percent` of its max (at least 1), one tick, one frame.
func _hit(id: int, percent: int) -> void:
	_set_hp(id, percent)
	_runner.run_ticks(1)
	_layer._process(0.0)


func _set_hp(id: int, percent: int) -> void:
	var world: World = _runner.world
	var row: int = world.index_of(id)
	@warning_ignore("integer_division")
	world.hp[row] = maxi(world.type_max_hp[world.type_index[row]] * percent / 100, 1)


func _row(id: int) -> int:
	return _runner.snapshot.index_of(id)


func _rig(id: int) -> UnitLayer.Rig:
	return _layer.rig(_row(id)) as UnitLayer.Rig


func _scar(id: int) -> Sprite2D:
	return _rig(id).damage.scar


func _loose(id: int) -> Sprite2D:
	return _rig(id).damage.loose


func _sheet(id: int) -> IsoSheetDef:
	var snap: MatchSnapshot = _runner.snapshot
	return _layer.world_sort.sheet(snap.type_ids[snap.type_index[_row(id)]])


## Turns the hull of unit `id` to frame `dir` the way a turn does.
func _turn(id: int, dir: int) -> void:
	var row: int = _row(id)
	_layer._heading[row] = float(dir - UnitLayer.D_EAST) * TAU / float(UnitLayer.DIRECTIONS)
	_layer._show_hull(row, _runner.snapshot.owner[row])


## The first hull frame whose hang point is on the right (`right`) or the left of the centre.
func _dir_on(id: int, right: bool) -> int:
	var sheet: IsoSheetDef = _sheet(id)
	var at: int = sheet.emitters.find("hang")
	for dir: int in UnitLayer.DIRECTIONS:
		var x: float = sheet.emitter_point(at, dir).x
		if (x > 0.0) if right else (x < 0.0):
			return dir
	return -1


## The rectangle `sprite` draws, relative to the rig of unit `id`, in world px.
func _rect_of(id: int, sprite: Sprite2D) -> Rect2:
	var local: Rect2 = Rect2(sprite.offset, sprite.region_rect.size)
	var xf: Transform2D = sprite.get_global_transform()
	var low: Vector2 = xf * local.position
	var high: Vector2 = xf * local.end
	var origin: Vector2 = _rig(id).global_position
	return Rect2(low.min(high) - origin, (high - low).abs())


## Produces a unit of `type_name` for player 1 at milli-tiles (x, y); returns its id.
func _spawn(type_name: StringName, x: int, y: int) -> int:
	var type: int = _runner.world.type_ids.find(type_name)
	var id: int = _runner.world.add_unit(1, type, x, y)
	_runner.run_ticks(1)
	_layer._process(0.0)
	return id


## Loses unit `id` in one tick and draws the frame.
func _kill(id: int) -> void:
	_runner.world.hp[_runner.world.index_of(id)] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
