extends GdUnitTestSuite
## What the ground effects and the bars leave to the air layer (plan P243, review S1 and S2): a
## flyer has no rig in `UnitLayer` and stands `fly_px` above its ground point, so a dust puff, an
## exhaust or damage-smoke emitter or a health bar at the ground point would be wrong. Until a row
## draws them at the lifted point, `GroundFx`, `PuffFx`, `DamageFx` and `HealthBarLayer` skip
## flyers; each case has a ground vehicle as its control, so a harness that sees nothing fails.

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const STEP: int = 300  ## Milli-tiles a tick; three ticks pass `dust_every_milli`.
const TANK_ID: int = 1

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: AirLayer


func before_test() -> void:
	_runner = auto_free(Air.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(Air.layer(self, _runner))
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_a_flyer_leaves_no_dust_and_a_tank_does() -> void:
	var dust: GroundFx = auto_free(GroundFx.new())
	dust.runner = _runner
	dust.camera = _camera
	dust.life = LifeSettings.new()
	dust.reveal_enemies = true
	add_child(dust)
	dust.set_process(false)
	_camera.position = IsoProjection.ground_to_px(
		_runner.snapshot.pos_x[2], _runner.snapshot.pos_y[2]
	)
	_drive(Air.FIGHTER_ID, 5)
	assert_int(dust.slot_count()).is_equal(0)
	_camera.position = IsoProjection.ground_to_px(
		_runner.snapshot.pos_x[0], _runner.snapshot.pos_y[0]
	)
	_drive(TANK_ID, 5)
	assert_int(dust.slot_count()).is_greater(0)


func test_a_flyers_sheet_gets_no_exhaust_and_no_damage_emitter() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var sort: WorldSort = _layer.world_sort
	var tank_type: int = snap.type_index[0]
	var flyer_type: int = snap.type_index[2]
	# Both with 16 directions and both emitters: only the layer bit tells them apart.
	for type: int in [tank_type, flyer_type]:
		var sheet: IsoSheetDef = Air.sheet(snap.type_ids[type], &"fossil", true)
		sheet.counts = PackedInt32Array([16, 16])
		sheet.emitters = PackedStringArray([String(PuffFx.EXHAUST_POINT), "damage"])
		sort._sheets[snap.type_ids[type]] = sheet
	var puff: PuffFx = PuffFx.new()
	puff.build(snap, sort)
	assert_int(puff._exhaust[tank_type]).is_equal(0)
	assert_int(puff._exhaust[flyer_type]).is_equal(-1)
	var smoke: DamageFx = DamageFx.new()
	smoke.build(snap, sort)
	assert_int(smoke._veh[tank_type]).is_equal(1)
	assert_int(smoke._veh[flyer_type]).is_equal(-1)


func test_a_hit_flyer_gets_no_health_bar_and_a_hit_tank_does() -> void:
	var units: UnitLayer = auto_free(UnitLayer.new())
	units.runner = _runner
	units.camera = _camera
	add_child(units)
	units.set_process(false)
	var bars: HealthBarLayer = auto_free(HealthBarLayer.new())
	bars.runner = _runner
	bars.unit_layer = units
	add_child(bars)
	bars.set_process(false)
	_runner.world.hp[2] -= 5  # The own fighter.
	_runner.world.hp[0] -= 5  # The own tank.
	_runner.run_ticks(1)
	Buildings.see(_runner.snapshot, 1, [Vector2i(8, 8), Vector2i(4, 4)])
	units.set_selected(PackedInt32Array([Air.FIGHTER_ID]))  # Selected and hit: still no bar.
	units._process(0.0)
	bars._process(0.0)
	var rows: Array[int] = []
	for bar: int in bars.bar_count():
		rows.append(bars.bar_row(bar))
	assert_array(rows).is_equal([0])  # The tank only.


## Moves unit `id` `STEP` a tick east for `ticks` ticks and emits `ticked` for each.
func _drive(id: int, ticks: int) -> void:
	for _i: int in ticks:
		var snap: MatchSnapshot = _runner.snapshot
		snap.prev_pos_x = snap.pos_x.duplicate()
		snap.prev_pos_y = snap.pos_y.duplicate()
		snap.pos_x[snap.index_of(id)] += STEP
		snap.tick += 1
		_runner.ticked.emit(snap.tick)
