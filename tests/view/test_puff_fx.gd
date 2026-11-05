extends GdUnitTestSuite
## The muzzle smoke and the exhaust puffs of `AirFx` (plan P149, ADR 0027 sections 3, 6 and 8): a
## SHOT of a weapon that fires a projectile leaves a grey puff at the flash's point for 500 ms, a
## vehicle that starts to drive puffs from its exhaust once and a standing one every 3 to 5 s of its
## own, all in a ring of 24 slots; `reduced` drops them; the fog and the view rect keep them from
## what the player does not see. Fixture: recoil_rig.gd (a light tank, a heavy tank, a squad, a
## Redoubt, an enemy tank far away).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Effects: GDScript = preload("res://tests/view/support/effects_rig.gd")
const DATA: LifeSettings = preload("res://data/life_settings.tres")
const START: int = 100
const MUZZLE: int = PuffFx.Style.MUZZLE
const EXHAUST: int = PuffFx.Style.EXHAUST
const SALT_EVERY: int = 0x7B000000
const SALT_PHASE: int = 0x7C000000
## The ticks of the idle puffs of the light and the heavy tank over 300 ticks from START, pinned: a
## run is the same on every device.
const LIGHT_IDLE: Array[int] = [123, 168, 214, 260, 305, 351, 397]
const HEAVY_IDLE: Array[int] = [123, 169, 215, 262, 308, 354]

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
	var snap: MatchSnapshot = _runner.snapshot  # The weapons of the test: three that fly, a rifle.
	snap.weapon_ids.clear()
	snap.weapon_ids.append_array([&"tank_cannon", &"rifle", &"rocket", &"artillery_gun"])
	snap.weapon_projectile_speed = PackedInt32Array([600, 0, 300, 300])
	Rig.at(_runner, 0, 0.0)
	_air._process(0.0)  # Follows this match before the first tick.


func after_test() -> void:
	CommandQueue.clear()


func test_the_numbers_are_the_data_files() -> void:
	assert_int(DATA.puff_slots).is_equal(24)
	assert_int(DATA.muzzle_smoke_ms).is_equal(500)
	assert_int(DATA.exhaust_ms).is_equal(500)
	assert_int(DATA.muzzle_smoke_ms).is_less_equal(PuffFx.MAX_LIFE_MS)
	assert_int(DATA.exhaust_ms).is_less_equal(PuffFx.MAX_LIFE_MS)
	assert_vector(Vector2(DATA.puff_idle_ms)).is_equal(Vector2(3000, 5000))
	assert_int(_air.puffs().ring._size).is_equal(0)  # Sized on the first tick.
	_run(START, START + 1)
	assert_int(_air.puffs().ring._size).is_equal(24)


func test_the_muzzle_reach_is_the_flash_reach_of_the_effects_layer() -> void:
	var effects: EffectsLayer = auto_free(EffectsLayer.new())
	assert_dict(DATA.muzzle_reach_px).is_equal(effects.muzzle_px)
	assert_float(DATA.muzzle_reach_default_px).is_equal(EffectsLayer.MUZZLE_DEFAULT_PX)
	for scene: String in ["res://scenes/main.tscn", "res://scenes/dev/perf_arena.tscn"]:
		# A node that tunes the flash's reach would move the flash and leave the puff behind.
		assert_str(FileAccess.get_file_as_string(scene)).not_contains("muzzle_px =")


func test_a_cannon_shot_leaves_one_puff_at_the_flash_point() -> void:
	_fire(&"tank_cannon")
	assert_int(_air.puffs().ring.count()).is_equal(1)
	assert_int(_air.puffs().ring.puff_style(0)).is_equal(MUZZLE)
	assert_float(_air.puffs().ring.puff_born(0)).is_equal(LifeClock.tick_ms(START))
	assert_vector(_air.puffs().ring.puff_at(0)).is_equal_approx(
		_flash_point(&"tank_cannon"), Vector2(0.01, 0.01)
	)


func test_every_projectile_weapon_puffs_and_a_rifle_does_not() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	for weapon: int in snap.weapon_ids.size():
		var fires: bool = snap.weapon_projectile_speed[weapon] > 0
		_air.puffs().ring.clear()
		_fire(snap.weapon_ids[weapon])
		(
			assert_int(_air.puffs().ring.count())
			. override_failure_message(String(snap.weapon_ids[weapon]))
			. is_equal(1 if fires else 0)
		)
	assert_int(snap.weapon_ids.size()).is_equal(4)


func test_the_puff_lives_500_ms_grows_and_fades() -> void:
	_fire(&"tank_cannon")
	var ring: FxRing = _air.puffs().ring
	Rig.at(_runner, START, 0.0)  # Just born: the smallest and the clearest.
	_air._process(0.0)
	assert_int(ring.quad_count()).is_equal(1)
	assert_float(ring.quad_alpha(0)).is_equal_approx(DATA.muzzle_smoke_alpha, 0.001)
	var small: float = ring.quad_rect(0).size.x
	Rig.at(_runner, START + 1, 0.5)  # 100 ms.
	_air._process(0.0)
	assert_float(ring.quad_alpha(0)).is_equal_approx(DATA.muzzle_smoke_alpha * 0.8, 0.001)
	assert_float(ring.quad_rect(0).size.x).is_greater(small)
	Rig.at(_runner, START + 8, 0.0)  # 533 ms: gone.
	_air._process(0.0)
	assert_int(ring.quad_count()).is_equal(0)
	assert_int(_air.puffs().ring.count()).is_equal(1)  # Not compacted until the next tick.
	_run(START + 9, START + 10)
	assert_int(_air.puffs().ring.count()).is_equal(0)


func test_the_puffs_are_drawn_in_the_cloud_pass_with_the_smoke() -> void:
	var ring: FxRing = _air.puffs().ring
	assert_int(ring._pass[PuffFx.K_PUFF]).is_equal(FxRing.CLOUD)
	assert_int(ring._pass[PuffFx.K_EXHAUST]).is_equal(FxRing.CLOUD)
	assert_array(_air._rings).contains([ring])


func test_a_shot_out_of_sight_or_out_of_view_leaves_nothing() -> void:
	var far: Vector2i = Rig.centre(Rig.FAR_TILE)
	_camera.position = _centre(Rig.ENEMY_TANK)
	_fire_from(far, &"tank_cannon", Rig.ENEMY_TANK)
	assert_int(_air.puffs().ring.count()).is_equal(0)  # The shooter's tile is dark.
	_air.reveal_enemies = true
	_fire_from(far, &"tank_cannon", Rig.ENEMY_TANK)
	assert_int(_air.puffs().ring.count()).is_equal(1)
	Buildings.see(_runner.snapshot, 1, [Rig.FAR_TILE])
	_air.reveal_enemies = false
	_air.puffs().ring.clear()
	_fire_from(far, &"tank_cannon", Rig.ENEMY_TANK)
	assert_int(_air.puffs().ring.count()).is_equal(1)  # Seen: shown as the flash is.
	_look_away_from(_centre(Rig.ENEMY_TANK))
	_air.puffs().ring.clear()
	_fire_from(far, &"tank_cannon", Rig.ENEMY_TANK)
	assert_int(_air.puffs().ring.count()).is_equal(0)  # Seen, but out of the view rect.


func test_the_ring_holds_24_and_the_newest_survive() -> void:
	var weapon: int = _runner.snapshot.weapon_ids.find(&"tank_cannon")
	var events: PackedInt32Array = PackedInt32Array()
	for shooter: int in 30:
		events.append_array(
			Effects.shot(
				Rig.position_of(_runner, Rig.LIGHT),
				Rig.position_of(_runner, Rig.LIGHT) + Rig.EAST_ON_SCREEN,
				weapon,
				100 + shooter,
				99
			)
		)
	Rig.deliver(_runner, events, START)
	assert_int(_air.puffs().ring.count()).is_equal(24)


func test_reduced_drops_the_puffs_at_once_and_births_none() -> void:
	_fire(&"tank_cannon")
	assert_int(_air.puffs().ring.count()).is_equal(1)
	_life.reduced = true
	_air._process(0.0)
	assert_int(_air.puffs().ring.count()).is_equal(0)
	assert_int(_air.puffs().ring.quad_count()).is_equal(0)
	_fire(&"tank_cannon")
	assert_int(_air.puffs().ring.count()).is_equal(0)
	_start_driving(Rig.LIGHT, START + 3)
	assert_int(_air.puffs().ring.count()).is_equal(0)
	_life.reduced = false
	_fire(&"tank_cannon")
	assert_int(_air.puffs().ring.count()).is_equal(1)


func test_a_new_match_empties_the_ring() -> void:
	_fire(&"tank_cannon")
	assert_int(_air.puffs().ring.count()).is_equal(1)
	_runner.snapshot.match_serial += 1
	_air._process(0.0)
	assert_int(_air.puffs().ring.count()).is_equal(0)


func test_a_vehicle_that_starts_to_drive_puffs_once_from_its_exhaust() -> void:
	_start_driving(Rig.LIGHT, START)
	assert_int(_air.puffs().ring.count()).is_equal(1)
	assert_int(_air.puffs().ring.puff_style(0)).is_equal(EXHAUST)
	assert_vector(_air.puffs().ring.puff_at(0)).is_equal_approx(
		_exhaust_point(Rig.LIGHT), Vector2(0.01, 0.01)
	)
	_start_driving(Rig.LIGHT, START + 1)  # Still driving: no second puff.
	_start_driving(Rig.LIGHT, START + 2)
	assert_int(_air.puffs().ring.count()).is_equal(1)
	_stop(Rig.LIGHT, START + 3)
	_start_driving(Rig.LIGHT, START + 4)  # It stopped and started again.
	assert_int(_exhausts_at(_exhaust_point(Rig.LIGHT))).is_equal(2)


func test_the_exhaust_is_born_where_the_rig_is_drawn() -> void:
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	_units.rig(row).position += Vector2(60.0, 0.0)
	_start_driving(Rig.LIGHT, START)
	assert_vector(_air.puffs().ring.puff_at(0)).is_equal_approx(
		_exhaust_point(Rig.LIGHT), Vector2(0.01, 0.01)
	)
	var home: Vector2 = _centre(Rig.LIGHT)
	assert_float(_air.puffs().ring.puff_at(0).x).is_greater(home.x + 30.0)


func test_a_standing_vehicle_puffs_every_three_to_five_seconds_of_its_own() -> void:
	var spots: Array[Vector2] = [_exhaust_point(Rig.LIGHT), _exhaust_point(Rig.HEAVY)]
	var born: Array = _births_of(START, START + 300, spots)  # 20 s.
	assert_array(born[0]).is_equal(LIGHT_IDLE)
	assert_array(born[1]).is_equal(HEAVY_IDLE)
	# Each vehicle's cycle is its own: the births of two tanks are not the same ticks.
	assert_array(LIGHT_IDLE).is_not_equal(HEAVY_IDLE)
	assert_array(_idle_births(Rig.LIGHT, START, START + 300)).is_equal(LIGHT_IDLE)
	assert_array(_idle_births(Rig.HEAVY, START, START + 300)).is_equal(HEAVY_IDLE)


func test_idle_puffs_off_with_an_x_of_zero_and_a_creep_is_not_a_start() -> void:
	_life.puff_idle_ms = Vector2i(0, 0)
	var spots: Array[Vector2] = [_exhaust_point(Rig.LIGHT), _exhaust_point(Rig.HEAVY)]
	assert_array(_births_of(START, START + 300, spots)).is_equal([[], []])
	_life.puff_idle_ms = DATA.puff_idle_ms
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	_runner.snapshot.prev_pos_x[row] = _runner.snapshot.pos_x[row] - 5  # A creep, under half a step.
	Rig.deliver(_runner, PackedInt32Array(), START + 300)
	assert_int(_exhausts_at(spots[0])).is_equal(0)
	_start_driving(Rig.LIGHT, START + 301)  # A real step is a start.
	assert_int(_exhausts_at(spots[0])).is_equal(1)


func test_a_change_of_rows_keeps_the_flag_of_a_vehicle_that_drives_on() -> void:
	_start_driving(Rig.LIGHT, START)
	for round: int in 2:
		_runner.snapshot.rows_version += 1  # A unit was made or died elsewhere; the tank stays.
		_start_driving(Rig.LIGHT, START + 1 + round)
		assert_int(_air.puffs().ring.count()).is_equal(1)  # Still the one start.


func test_the_switch_to_reduced_drops_the_exhaust_too() -> void:
	_start_driving(Rig.LIGHT, START)
	_fire(&"tank_cannon")
	assert_int(_air.puffs().ring.count()).is_equal(2)
	_life.reduced = true
	_air._process(0.0)
	assert_int(_air.puffs().ring.count()).is_equal(0)


func test_a_driving_vehicle_does_not_idle_puff_and_a_squad_and_a_hidden_enemy_never() -> void:
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var born: Array[int] = []
	for tick: int in range(START, START + 300):  # It drives on, from its first tick.
		_runner.snapshot.prev_pos_x[row] = _runner.snapshot.pos_x[row] - 100
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for puff: Array in _puffs():
			var here: bool = (puff[1] as Vector2).distance_to(_exhaust_point(Rig.LIGHT)) < 1.0
			if here and puff[2] == LifeClock.tick_ms(tick):
				born.append(tick)
	assert_array(born).is_equal([START])  # The start, nothing else.
	var squad: Vector2 = _centre(Rig.SQUAD)
	for puff: Array in _puffs():
		assert_float((puff[1] as Vector2).distance_to(squad)).is_greater(20.0)
	_stop(Rig.LIGHT, START + 300)
	_air.puffs().ring.clear()
	_camera.position = _centre(Rig.ENEMY_TANK)
	assert_array(_births(START + 301, START + 600, _centre(Rig.ENEMY_TANK), 400.0)).is_empty()
	_air.unit_layer.reveal_enemies = true  # Shown now: it stands in the dark, puffing.
	assert_array(_births(START + 600, START + 900, _centre(Rig.ENEMY_TANK), 400.0)).is_not_empty()


func test_a_vehicle_out_of_view_and_a_layer_without_units_puff_nothing() -> void:
	_look_away_from(_centre(Rig.LIGHT))
	_start_driving(Rig.LIGHT, START)
	assert_int(_air.puffs().ring.count()).is_equal(0)
	_camera.position = _centre(Rig.LIGHT)
	_air.unit_layer = null
	_start_driving(Rig.HEAVY, START + 1)
	assert_int(_air.puffs().ring.count()).is_equal(0)


func _fire(weapon_id: StringName) -> void:
	_fire_from(Rig.position_of(_runner, Rig.LIGHT), weapon_id, Rig.LIGHT)


# Delivers the SHOT of `shooter` standing at `from` with weapon `weapon_id` at tick START.
func _fire_from(from: Vector2i, weapon_id: StringName, shooter: int) -> void:
	var weapon: int = _runner.snapshot.weapon_ids.find(weapon_id)
	assert_int(weapon).is_greater(-1)
	Rig.deliver(_runner, Effects.shot(from, from + Rig.EAST_ON_SCREEN, weapon, shooter, 99), START)


# Where the flash of a `weapon_id` SHOT of the light tank is, restated: the weapon's reach from the
# shooter towards the target, at the muzzle's height.
func _flash_point(weapon_id: StringName) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var weapon: int = snap.weapon_ids.find(weapon_id)
	var lift: float = SpriteLift.muzzle_lift_px(
		snap.weapon_ids, weapon, _buildings.world_sort.muzzle_px(weapon)
	)
	var from: Vector2i = Rig.position_of(_runner, Rig.LIGHT)
	var to: Vector2i = from + Rig.EAST_ON_SCREEN
	var shooter: Vector2 = IsoProjection.ground_to_px(from.x, from.y) - Vector2(0.0, lift)
	var target: Vector2 = IsoProjection.ground_to_px(to.x, to.y) - Vector2(0.0, lift)
	return shooter.lerp(target, DATA.muzzle_reach_px[weapon_id] / shooter.distance_to(target))


# Tank `id` moved in tick `tick`, by a tenth of a tile east of its position.
func _start_driving(id: int, tick: int) -> void:
	var row: int = _runner.snapshot.index_of(id)
	_runner.snapshot.prev_pos_x[row] = _runner.snapshot.pos_x[row] - 100
	Rig.deliver(_runner, PackedInt32Array(), tick)


# Tank `id` did not move in tick `tick`.
func _stop(id: int, tick: int) -> void:
	var row: int = _runner.snapshot.index_of(id)
	_runner.snapshot.prev_pos_x[row] = _runner.snapshot.pos_x[row]
	Rig.deliver(_runner, PackedInt32Array(), tick)


# Moves the camera so that `spot` (world px) is outside the view rect grown by the layer's margin.
func _look_away_from(spot: Vector2) -> void:
	var margin: float = BuildingLayer.ANIM_MARGIN_PX
	_camera.position.x += spot.x + margin * 1.5 - _camera.visible_world_rect().position.x
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(spot)).is_false()


# The births of exhaust puffs at each of `spots`: a list of ticks for each, over `from` to `to`.
func _births_of(from: int, to: int, spots: Array[Vector2]) -> Array:
	var found: Array = []
	for spot: Vector2 in spots:
		found.append([] as Array[int])
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for puff: Array in _puffs():
			if puff[0] != EXHAUST or puff[2] != LifeClock.tick_ms(tick):
				continue
			for at: int in spots.size():
				if (puff[1] as Vector2).distance_to(spots[at]) < 1.0:
					found[at].append(tick)
	return found


# The ticks in `from` to `to` (exclusive), in order, at which an exhaust puff was born within
# `radius` px of `spot`, nothing moving.
func _births(from: int, to: int, spot: Vector2, radius: float = 1.0) -> Array[int]:
	var found: Array[int] = []
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for puff: Array in _puffs():
			if (
				puff[0] == EXHAUST
				and puff[2] == LifeClock.tick_ms(tick)
				and (puff[1] as Vector2).distance_to(spot) <= radius
			):
				found.append(tick)
	return found


func _run(from: int, to: int) -> void:
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)


func _centre(id: int) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	return IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


# Where the exhaust point of the light or heavy tank `id` is, restated: its rig's place and its
# hull frame's `exhaust` point.
func _exhaust_point(id: int) -> Vector2:
	var row: int = _runner.snapshot.index_of(id)
	var sheet: IsoSheetDef = _units.world_sort.sheet(_runner.snapshot.type_ids[_type(id)])
	var dir: int = UnitLayer.frame_of(_units.heading(row), sheet.counts[0])
	var at: int = sheet.emitters.find("exhaust")
	assert_int(at).is_greater(-1)
	return _units.rig(row).global_position + sheet.emitter_point(at, dir) * 0.5


func _type(id: int) -> int:
	return _runner.snapshot.type_index[_runner.snapshot.index_of(id)]


func _puffs() -> Array:
	var found: Array = []
	var ring: FxRing = _air.puffs().ring
	for slot: int in ring.count():
		found.append([ring.puff_style(slot), ring.puff_at(slot), ring.puff_born(slot)])
	return found


# The exhaust puffs of the ring at `spot`.
func _exhausts_at(spot: Vector2) -> int:
	var found: int = 0
	for puff: Array in _puffs():
		if puff[0] == EXHAUST and (puff[1] as Vector2).distance_to(spot) < 1.0:
			found += 1
	return found


func _phase(id: int, every: int) -> int:
	return LifeClock.pick(id, SALT_PHASE, every)


# The ticks in `from` to `to` (exclusive) at which the idle cycle of vehicle `id` turns over,
# restated from the ADR: every 3000 + pick ms, from a phase of its own.
@warning_ignore("integer_division")
func _idle_births(id: int, from: int, to: int) -> Array[int]:
	var every: int = 3000 + LifeClock.pick(id, SALT_EVERY, 2001)
	var phase: int = _phase(id, every)
	var births: Array[int] = []
	for tick: int in range(from, to):
		var now: int = (tick * 1000 + phase * Sim.TICK_RATE) / (every * Sim.TICK_RATE)
		var before: int = ((tick - 1) * 1000 + phase * Sim.TICK_RATE) / (every * Sim.TICK_RATE)
		if now != before:
			births.append(tick)
	return births
