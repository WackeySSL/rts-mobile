extends GdUnitTestSuite
## The fixture and helpers of the damage particle suites (plan P148): test_damage_fx.gd,
## test_damage_fx_kinds.gd, test_damage_fx_craters.gd and test_damage_fx_vehicles.gd extend this.
## Crafted Barracks (the damage rig's sheet) with five emitters, in this order: 0 an ambient
## `smoke` (quiet from stage `QUIET`), 1 a `damage` point on the left, 2 a `dmg_gas` on the right,
## 3 a `dmg_gas` on the left, 4 a `dmg_spark`. A runner with the buildings of `spawns`, a
## `BuildingLayer`, a camera on the first building and an `AirFx` that is planned by hand (ticks
## are delivered, frames drawn with `_frame`). Not a test suite.

const Dmg: GDScript = preload("res://tests/view/support/damage_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const DATA: LifeSettings = preload("res://data/life_settings.tres")
const START: int = 100
const TICK_MS: float = 1000.0 / 15.0
const POINT_NAMES: Array[String] = ["smoke", "damage", "dmg_gas", "dmg_gas", "dmg_spark"]
## Art px from the footprint centre; the view halves them.
const POINT_AT: Array[Vector2] = [
	Vector2(0.0, -180.0),
	Vector2(-60.0, -140.0),
	Vector2(100.0, -120.0),
	Vector2(-100.0, -120.0),
	Vector2(20.0, -180.0),
]
const QUIET: int = 2
const S: Dictionary = {  ## The styles of DamageFx, by name.
	"smoke": DamageFx.Style.SMOKE,
	"soot": DamageFx.Style.SOOT,
	"fire": DamageFx.Style.FIRE,
	"fire_big": DamageFx.Style.FIRE_BIG,
	"fire_car": DamageFx.Style.FIRE_CAR,
	"jet": DamageFx.Style.JET,
	"spark": DamageFx.Style.SPARK,
	"ember": DamageFx.Style.EMBER,
	"glow_weak": DamageFx.Style.GLOW_WEAK,
	"glow_strong": DamageFx.Style.GLOW_STRONG,
	"glow_jet": DamageFx.Style.GLOW_JET,
	"glow_faint": DamageFx.Style.GLOW_FAINT,
	"trail": DamageFx.Style.TRAIL,
	"crater": DamageFx.Style.CRATER_SMOKE,
}

var _runner: MatchRunner
var _sort: WorldSort
var _buildings: BuildingLayer
var _camera: RtsCamera
var _air: AirFx
var _life: LifeSettings
var _def: IsoSheetDef


func after_test() -> void:
	CommandQueue.clear()


## Opens the fixture. `spawns` is `[owner, x, y]` of Barracks; `quiet` is the ambient emitter's
## `emitter_quiet` (an empty array: the sheet's list is empty).
func _open(spawns: Array, quiet: Array[int] = [QUIET, 0, 0, 0, 0], reveal: bool = true) -> void:
	_life = DATA.duplicate() as LifeSettings
	_def = Dmg.sheet()
	_def.emitters = PackedStringArray(POINT_NAMES)
	_def.emitter_points = PackedVector2Array(POINT_AT)
	_def.emitter_quiet = PackedInt32Array(quiet)
	_runner = auto_free(Dmg.runner(spawns))
	_sort = auto_free(Dmg.sort(_runner, _def))
	add_child(_sort)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = _sort
	_buildings.camera = _camera
	_buildings.reveal_enemies = reveal
	_buildings.life = _life
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings._process(0.0)
	_air = auto_free(AirFx.new())
	_air.runner = _runner
	_air.camera = _camera
	_air.life = _life
	_air.building_layer = _buildings
	add_child(_air)
	_air.set_process(false)
	_camera.position = _centre(1)
	Rig.at(_runner, 0, 0.0)


func _centre(id: int) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	return IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


## Where point `index` of the sheet is for building `id`, restated from the sheet.
func _spot(id: int, index: int) -> Vector2:
	return _centre(id) + _def.emitter_point(index, -1) * 0.5


## Sets building `id` to `percent` of its hp and ticks once, so the snapshot carries it.
func _hp(id: int, percent: int) -> void:
	Dmg.set_hp(_runner, id, percent)
	_runner.run_ticks(1)
	_air.damage().clear()  # The tick itself emitted: the match's own tick is not the test's.
	_air._empty()


## Delivers ticks `from` up to `to` (not including), each published with `ticked`.
func _run(from: int, to: int) -> void:
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)


## Plans the frame at `tick` and `alpha`.
func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_air._process(0.0)


## The point of building `id` that burns first: `LifeClock.pick` of its id over the four damage
## points of the sheet (indices 1 to 4), restated.
func _first_point(id: int) -> int:
	return 1 + LifeClock.pick(id, DamageFx.SALT_BURN, 4)


## The ring's puffs, slot by slot: [style, spot, born ms].
func _puffs() -> Array:
	var found: Array = []
	var ring: FxRing = _air.damage().ring
	for slot: int in ring.count():
		found.append([ring.puff_style(slot), ring.puff_at(slot), ring.puff_born(slot)])
	return found


## The set of styles (names) of the puffs at `spot` (within a pixel), sorted.
func _styles_at(spot: Vector2) -> Array:
	var found: Array = []
	var names: Dictionary = {}
	for key: String in S:
		names[S[key]] = key
	for puff: Array in _puffs():
		if (puff[1] as Vector2).distance_to(spot) < 1.0 and not found.has(names[puff[0]]):
			found.append(names[puff[0]])
	found.sort()
	return found


## How many puffs of style `style` (a key of `S`) are in the ring.
func _count(style: String) -> int:
	var found: int = 0
	for puff: Array in _puffs():
		found += 1 if puff[0] == S[style] else 0
	return found


## Every building but `id` becomes a site (far from complete), so only `id` can burn.
func _only(id: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		snap.build_left[row] = 0 if snap.unit_id[row] == id else 500
