extends GdUnitTestSuite
## The particles of damaged vehicles (plan P148, ADR 0028 section 6): a shown vehicle under half
## its health trails `exhaust` from its hull frame's `damage` point, under a quarter it smokes
## `soot`, burns a small `fire` and throws sparks; the puff is born where the rig is drawn and stays
## in the world; a squad, a hidden enemy and a source out of view emit nothing; `reduced` drops the
## sparks. Fixture: recoil_rig.gd (a light tank, a heavy tank, a squad, a Redoubt, a far tank).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const DATA: LifeSettings = preload("res://data/life_settings.tres")
const START: int = 100
const TRAIL: int = DamageFx.Style.TRAIL
const SOOT: int = DamageFx.Style.SOOT
const FIRE_CAR: int = DamageFx.Style.FIRE_CAR
const SPARK: int = DamageFx.Style.SPARK

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer
var _air: AirFx
var _life: LifeSettings


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_life = Rig.calmed(null)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.life = _life
	_units.camera = _camera
	add_child(_units)
	_units.set_process(false)
	_units._process(0.0)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.life = _life
	_buildings.camera = _camera
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings._process(0.0)
	_air = auto_free(AirFx.new())
	_air.runner = _runner
	_air.camera = _camera
	_air.life = _life
	_air.building_layer = _buildings
	_air.unit_layer = _units
	add_child(_air)
	_air.set_process(false)
	_camera.position = _centre(Rig.LIGHT)
	Rig.at(_runner, 0, 0.0)
	_air._process(0.0)  # Follows this match before the first tick.


func after_test() -> void:
	CommandQueue.clear()


func test_a_vehicle_under_half_its_health_trails_exhaust_from_its_damage_point() -> void:
	_hurt(Rig.LIGHT, 40)
	_run(START, START + 45)
	var spot: Vector2 = _point(Rig.LIGHT)
	assert_array(_styles_at(spot)).is_equal([TRAIL])
	assert_int(_puffs().size()).is_greater(1)
	for puff: Array in _puffs():  # Every puff of the ring is the tank's, at the hull's point.
		assert_vector(puff[1]).is_equal_approx(spot, Vector2(0.01, 0.01))
	var sheet: IsoSheetDef = _units.world_sort.sheet(&"light_tank")
	assert_int(sheet.emitters.find("damage")).is_greater(-1)
	var hull_frame: int = UnitLayer.frame_of(_units.heading(0), sheet.counts[0])
	assert_int(hull_frame).is_equal(UnitLayer.D_EAST)


func test_under_a_quarter_it_smokes_soot_burns_a_small_fire_and_throws_sparks() -> void:
	_hurt(Rig.LIGHT, 20)
	_run(START, START + 60)
	var styles: Array = _styles_at(_point(Rig.LIGHT))
	assert_array(styles).contains_exactly_in_any_order([SOOT, FIRE_CAR, SPARK])
	assert_array(styles).not_contains([TRAIL])


func test_the_puff_stays_where_it_was_born_so_a_moving_vehicle_trails_smoke() -> void:
	var rates: Dictionary[StringName, int] = _life.damage_emit_ms.duplicate()
	rates[&"exhaust"] = 300  # A puff every 4.5 ticks, so both halves of the run have births.
	_life.damage_emit_ms = rates
	_hurt(Rig.LIGHT, 40)
	_run(START, START + 30)
	var home: Vector2 = _point(Rig.LIGHT)
	assert_int(_puffs().size()).is_greater(0)
	_units.rig(0).position += Vector2(80.0, 0.0)  # The rig is drawn elsewhere now.
	_run(START + 30, START + 42)
	var kept: int = 0
	var moved: int = 0
	for puff: Array in _puffs():
		if puff[2] < LifeClock.tick_ms(START + 30):  # Born before the move, left where it was.
			assert_vector(puff[1]).is_equal_approx(home, Vector2(0.01, 0.01))
			kept += 1
		else:
			assert_vector(puff[1]).is_equal_approx(home + Vector2(80.0, 0.0), Vector2(0.01, 0.01))
			moved += 1
	assert_int(kept).is_greater(0)
	assert_int(moved).is_greater(0)


func test_a_vehicle_uses_the_vehicle_lines_not_the_building_lines() -> void:
	# 60 % is intact for a vehicle (the line is 50) but SKADET for a building (67); 30 % is SKADET
	# for a vehicle (the lines are 50 and 25) but KRITISK for a building (34).
	_hurt(Rig.LIGHT, 60)
	_run(START, START + 60)
	assert_int(_puffs().size()).is_equal(0)
	_hurt(Rig.LIGHT, 30)
	_run(START, START + 60)
	assert_array(_styles_at(_point(Rig.LIGHT))).is_equal([TRAIL])
	_hurt(Rig.LIGHT, 24)
	_run(START, START + 60)
	assert_array(_styles_at(_point(Rig.LIGHT))).contains_exactly_in_any_order(
		[SOOT, FIRE_CAR, SPARK]
	)


func test_a_squad_and_a_hidden_enemy_and_a_site_emit_nothing_and_a_seen_enemy_does() -> void:
	_hurt(Rig.SQUAD, 5)
	_hurt(Rig.ENEMY_TANK, 5)
	_run(START, START + 45)
	assert_int(_puffs().size()).is_equal(0)  # The squad has no damage point; the enemy is hidden.
	var far: Vector2i = Rig.FAR_TILE
	_camera.position = _centre(Rig.ENEMY_TANK)
	Buildings.see(_runner.snapshot, 1, [far, far + Vector2i(1, 0), far + Vector2i(0, 1)])
	_run(START + 45, START + 105)
	assert_int(_puffs().size()).is_greater(0)
	var row: int = _runner.snapshot.index_of(Rig.ENEMY_TANK)
	_air.damage().clear()
	_runner.snapshot.build_left[row] = 500  # Not complete: nothing.
	_run(START + 105, START + 150)
	assert_int(_puffs().size()).is_equal(0)


func test_a_vehicle_outside_the_view_and_a_layer_without_units_emit_nothing() -> void:
	_hurt(Rig.LIGHT, 20)
	var margin: float = BuildingLayer.ANIM_MARGIN_PX
	_camera.position.x += (
		_point(Rig.LIGHT).x + margin * 1.5 - _camera.visible_world_rect().position.x
	)
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(_point(Rig.LIGHT))).is_false()
	_run(START, START + 45)
	assert_int(_puffs().size()).is_equal(0)
	_camera.position = _centre(Rig.LIGHT)
	_air.unit_layer = null
	_run(START, START + 45)
	assert_int(_puffs().size()).is_equal(0)


func test_the_vehicle_fire_has_its_own_scale_and_reduced_drops_only_the_sparks() -> void:
	_hurt(Rig.LIGHT, 20)
	_run(START, START + 60)
	var wide: float = _fire_width()
	_life.damage_vehicle_fire_scale = DATA.damage_vehicle_fire_scale * 0.5
	_air.damage().clear()
	_run(START, START + 60)
	assert_float(_fire_width()).is_equal_approx(wide * 0.5, 0.01)
	_air.damage().clear()
	_life.reduced = true
	_run(START, START + 60)
	assert_array(_styles_at(_point(Rig.LIGHT))).contains_exactly_in_any_order([SOOT, FIRE_CAR])
	_hurt(Rig.LIGHT, 40)
	_life.reduced = true
	_run(START, START + 45)
	assert_array(_styles_at(_point(Rig.LIGHT))).is_equal([TRAIL])


func _hurt(id: int, percent: int) -> void:
	var world: World = _runner.world
	var row: int = world.index_of(id)
	@warning_ignore("integer_division")
	world.hp[row] = maxi(world.type_max_hp[world.type_index[row]] * percent / 100, 1)
	_runner.run_ticks(1)
	_units._process(0.0)
	_air.damage().clear()
	_air._empty()


func _run(from: int, to: int) -> void:
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)


func _centre(id: int) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	return IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


## Where the damage point of the tank `id` is, restated: its rig's place and its hull frame's point.
func _point(id: int) -> Vector2:
	var row: int = _runner.snapshot.index_of(id)
	var sheet: IsoSheetDef = _units.world_sort.sheet(&"light_tank")
	var dir: int = UnitLayer.frame_of(_units.heading(row), sheet.counts[0])
	var at: int = sheet.emitters.find("damage")
	return _units.rig(row).global_position + sheet.emitter_point(at, dir) * 0.5


func _puffs() -> Array:
	var found: Array = []
	var ring: FxRing = _air.damage().ring
	for slot: int in ring.count():
		found.append([ring.puff_style(slot), ring.puff_at(slot), ring.puff_born(slot)])
	return found


func _styles_at(spot: Vector2) -> Array:
	var found: Array = []
	for puff: Array in _puffs():
		if (puff[1] as Vector2).distance_to(spot) < 1.0 and not found.has(puff[0]):
			found.append(puff[0])
	found.sort()
	return found


## The width of the newest planned fire quad, in the frame 200 ms after the newest birth.
func _fire_width() -> float:
	var ring: FxRing = _air.damage().ring
	var newest: float = 0.0
	for puff: Array in _puffs():
		if puff[0] == FIRE_CAR:
			newest = maxf(newest, puff[2])
	Rig.at(_runner, roundi(newest / (1000.0 / 15.0)) + 3, 0.0)
	_air._process(0.0)
	for index: int in ring.quad_count():
		if ring.quad_kind(index) == DamageFx.K_FIRE:
			return ring.quad_rect(index).size.x
	fail("no fire quad")
	return 0.0
