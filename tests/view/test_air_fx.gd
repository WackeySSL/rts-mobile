extends GdUnitTestSuite
## `AirFx`, the smoke, steam and flames of the buildings (plan P145, ADR 0027 sections 3, 4, 8 and
## 9): which building emits and which does not, when a puff is born (the cycle of its kind from a
## per-id phase), what a puff does in its life, the quota, `reduced`, and the mirror rule.
## Fixtures: player 1 (local) has a Refinery (id 1: a steam and a flame emitter), two Turbine Halls
## (ids 2 and 3: two smoke stacks each), a Barracks (id 5, no emitter), a Headquarters (id 6: one
## smoke), a strike building (id 7: a launch point only) and a Light Tank (id 8: an exhaust
## point only); player 2 has a Lumen Refinery (id 4: two steam emitters). The test sets the tick
## (`Rig.deliver` publishes it and emits `ticked`) and the layer plans a frame with `_process`.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const REFINERY: int = 1
const HALL: int = 2
const HALL_B: int = 3
const LUMEN: int = 4
const BARRACKS: int = 5
const HQ: int = 6
const STRIKE: int = 7
const TANK: int = 8
const EMITTING: Array[int] = [REFINERY, HALL, HALL_B, LUMEN, HQ]
const SALT: int = 0x60000000  ## The phase's salt, restated.
const SMOKE: int = 0
const STEAM: int = 1
const FLAME: int = 2
const START: int = 100  ## The first tick of a run: any tick after the match's own.
const DATA: LifeSettings = preload("res://data/life_settings.tres")
const TICK_MS: float = 1000.0 / 15.0

var _runner: MatchRunner
var _buildings: BuildingLayer
var _camera: RtsCamera
var _air: AirFx
var _life: LifeSettings


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "refinery", 6, 8),
		Buildings.spawn(1, "power_plant", 10, 8),
		Buildings.spawn(1, "power_plant", 6, 12),
		Buildings.spawn(2, "renew_refinery", 12, 12),
		Buildings.spawn(1, "barracks", 14, 6),
		Buildings.spawn(1, "headquarters", 10, 4),
		Buildings.spawn(1, "fossil_strike", 2, 10),
		Buildings.spawn(1, "light_tank", 3, 3),
	]
	_runner = auto_free(Buildings.runner(Buildings.scenario(spawns)))
	for id: int in [REFINERY, HALL, HALL_B, LUMEN, BARRACKS, HQ, STRIKE, TANK]:
		assert_int(_runner.snapshot.index_of(id)).is_greater_equal(0)
	assert_int(_runner.snapshot.owner[_runner.snapshot.index_of(LUMEN)]).is_equal(2)
	_life = DATA.duplicate() as LifeSettings
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
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
	add_child(_air)
	_air.set_process(false)
	_camera.position = (_centre(REFINERY) + _centre(LUMEN)) * 0.5
	Rig.at(_runner, 0, 0.0)
	_sees_all()


func after_test() -> void:
	CommandQueue.clear()


func test_a_complete_online_shown_building_puffs_at_each_emitter_from_its_sheet() -> void:
	_run(START, START + 45)  # Three seconds.
	for id: int in EMITTING:
		var sheet: IsoSheetDef = _sheet(id)
		for index: int in sheet.emitters.size():
			var spot: Vector2 = _spot(id, index)
			(
				assert_int(_births(spot).size())
				. override_failure_message("building %d emitter %d" % [id, index])
				. is_greater(0)
			)
	assert_int(_births(_centre(BARRACKS)).size()).is_equal(0)
	assert_int(_air.slot_count()).is_greater(0)


func test_an_emitter_puffs_when_the_cycle_of_its_kind_turns_over_from_the_phase_of_its_id() -> void:
	_run(START, START + 60)
	for id: int in [REFINERY, HALL, LUMEN]:
		var sheet: IsoSheetDef = _sheet(id)
		for index: int in sheet.emitters.size():
			var every: int = _emit_ms(sheet.emitters[index])
			var phase: int = LifeClock.mix(id, SALT + index) % every
			var want: Array[int] = []
			for tick: int in range(START, START + 60):
				if _cycle_turns(tick, phase, every):
					want.append(tick)
			assert_int(want.size()).is_greater(2)
			var seen: Array[int] = _births(_spot(id, index))
			assert_array(seen).override_failure_message("%d/%d" % [id, index]).is_equal(want)
			assert_int(AirFx.phase_ms(id, index, every)).is_equal(phase)


func test_two_buildings_of_a_kind_and_the_two_stacks_of_one_puff_out_of_step() -> void:
	var smoke: int = _emit_ms("smoke")
	assert_int(AirFx.phase_ms(HALL, 0, smoke)).is_not_equal(AirFx.phase_ms(HALL_B, 0, smoke))
	assert_int(AirFx.phase_ms(HALL, 0, smoke)).is_not_equal(AirFx.phase_ms(HALL, 1, smoke))
	assert_int(AirFx.phase_ms(HALL, 0, smoke)).is_equal(AirFx.phase_ms(HALL, 0, smoke))
	_run(START, START + 90)
	assert_array(_births(_spot(HALL, 0))).is_not_equal(_births(_spot(HALL_B, 0)))
	assert_array(_births(_spot(HALL, 0))).is_not_equal(_births(_spot(HALL, 1)))


func test_the_rate_never_passes_the_floor_of_500_ms_and_the_life_never_2_seconds() -> void:
	_life.emitter_slots = 400  # Room for every puff of the run.
	_life.emit_ms = {&"smoke": 100, &"steam": 100, &"flare": 100}
	_life.emit_life_ms = {&"smoke": 9000, &"steam": 9000, &"flare": 9000}
	_run(START, START + 120)
	var ticks: Array[int] = _births(_spot(HQ, 0))
	assert_int(ticks.size()).is_between(15, 17)  # 8 s at one every 500 ms.
	for at: int in range(1, ticks.size()):
		assert_int(ticks[at] - ticks[at - 1]).is_greater_equal(7)  # 500 ms is 7.5 ticks.
	_frame(START + 119, 0.0)  # Puffs of 2 s or less: four of one emitter alive at most.
	var alive: int = 0
	for index: int in _air.quad_count():
		var anchor: Vector2 = _spot(HQ, 0)
		alive += 1 if _air.quad_rect(index).get_center().distance_to(anchor) < 60.0 else 0
	assert_int(alive).is_between(1, 4)
	_frame(START + 119 + 31, 0.0)  # Two seconds on with no new tick: every puff is gone.
	assert_int(_air.quad_count()).is_equal(0)


func test_the_kinds_use_their_own_sprite_and_a_flame_is_the_flare() -> void:
	assert_that(LifeRegions.EMITTER_SPRITE).is_equal(
		{&"smoke": &"smoke", &"steam": &"steam", &"flame": &"flare"}
	)
	_run(START, START + 30)
	_frame(START + 29, 0.0)
	var seen: Dictionary[int, bool] = {}
	for index: int in _air.quad_count():
		var kind: int = _air.quad_kind(index)
		seen[kind] = true
		var sprite: StringName = LifeRegions.EMITTER_SPRITE[AirFx.EMITTERS[kind]]
		var first: Rect2i = LifeRegions.FIRST[sprite]
		assert_float(_air.quad_rect(index).size.x).is_less_equal(first.size.x * 1.21)
		assert_int(_air.quad_frame(index)).is_less(LifeRegions.FRAMES[sprite])
		assert_float(_air.quad_alpha(index)).is_between(0.0, 0.851)
	assert_array(seen.keys()).contains_exactly_in_any_order([SMOKE, STEAM, FLAME])
	assert_str(_air.texture().resource_path).is_equal(LifeRegions.LIFE_ART)


func test_a_puff_rises_drifts_east_grows_and_fades_the_way_the_data_says() -> void:
	var born: int = _lone(HQ, 450)  # A life shorter than the 500 ms between puffs: one at a time.
	var spot: Vector2 = _spot(HQ, 0)
	var last_alpha: float = INF
	var last_width: float = 0.0
	for step: int in range(0, 6):  # 0 to 333 ms of the 450.
		_frame(born + step, 0.0)
		assert_int(_air.quad_count()).override_failure_message("step %d" % step).is_equal(1)
		var t: float = float(step) * TICK_MS / 450.0
		var rect: Rect2 = _air.quad_rect(0)
		var grow: float = rect.size.x / LifeRegions.FIRST[&"smoke"].size.x
		var anchor: Vector2 = LifeRegions.ANCHOR[&"smoke"] * grow
		var at: Vector2 = rect.position + anchor
		assert_float(at.y).is_equal_approx(spot.y - 24.0 * t, 0.01)  # emit_rise_px
		assert_float(at.x).is_equal_approx(spot.x + 6.0 * t, 0.01)  # emit_drift_px, east
		assert_float(grow).is_equal_approx(lerpf(0.6, 1.2, t), 0.001)
		assert_float(_air.quad_alpha(0)).is_equal_approx(0.85 * (1.0 - t), 0.001)
		assert_float(_air.quad_alpha(0)).is_less(last_alpha)
		assert_float(rect.size.x).is_greater_equal(last_width)
		last_alpha = _air.quad_alpha(0)
		last_width = rect.size.x
	_frame(born + 7, 0.0)  # 467 ms: older than its life.
	assert_int(_air.quad_count()).is_equal(0)


func test_a_flame_stays_on_its_stack_and_shrinks_and_steam_grows() -> void:
	_life.emit_ms = {&"smoke": 700, &"steam": 0, &"flare": 500}  # The Refinery's flame alone.
	var born: int = _lone(REFINERY, 450)
	var spot: Vector2 = _spot(REFINERY, 1)
	_frame(born, 0.0)
	var size_new: Vector2 = _air.quad_rect(0).size
	assert_vector(size_new).is_equal_approx(Vector2(LifeRegions.FIRST[&"flare"].size), Vector2.ONE)
	for age: int in range(0, 6):  # The base is on the emitter point for the whole life.
		_frame(born + age, 0.0)
		assert_int(_air.quad_count()).is_equal(1)
		var rect: Rect2 = _air.quad_rect(0)
		var grow: float = rect.size.x / size_new.x
		var anchor: Vector2 = LifeRegions.ANCHOR[&"flare"] * grow
		var reach: float = rect.size.x - anchor.x if _air.quad_flipped(0) else anchor.x
		assert_float(rect.position.x + reach).is_equal_approx(spot.x, 0.01)
		assert_float(rect.position.y + anchor.y).is_equal_approx(spot.y, 0.01)
		var t: float = float(age) * TICK_MS / 450.0
		assert_float(grow).is_equal_approx(lerpf(1.0, 0.7, t), 0.001)
	# Steam grows.
	_life.emit_ms = {&"smoke": 700, &"steam": 600, &"flare": 0}
	_air._empty()
	var steam: int = _lone(REFINERY, 450)
	_frame(steam, 0.0)
	var small: float = _air.quad_rect(0).size.x
	_frame(steam + 4, 0.0)
	assert_float(_air.quad_rect(0).size.x).is_greater(small)


func test_the_flame_is_a_steady_fire_that_changes_frame_at_each_birth() -> void:
	_life.emit_ms = {&"smoke": 0, &"steam": 0, &"flare": 500}
	var frames: Dictionary[int, bool] = {}
	var overlaps: int = 0
	var base: Vector2 = _spot(REFINERY, 1)
	for tick: int in range(START, START + 200):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for alpha: float in [0.0, 0.5]:
			_frame(tick, alpha)
			var near: int = 0
			var brightest: float = 0.0
			for index: int in _air.quad_count():
				var centre: Vector2 = _air.quad_rect(index).get_center()
				if _air.quad_kind(index) == FLAME and centre.distance_to(base) < 40.0:
					near += 1
					brightest = maxf(brightest, _air.quad_alpha(index))
					frames[_air.quad_frame(index)] = true
			overlaps += 1 if near >= 2 and alpha == 0.0 else 0
			if tick > START + 20:
				var note: String = "tick %d alpha %.1f" % [tick, alpha]
				assert_int(near).override_failure_message(note).is_greater(0)  # Never bare.
				# Steady, not a pulse: the brightest flame stays near the full alpha.
				assert_float(brightest).override_failure_message(note).is_greater_equal(
					0.8 * DATA.emit_alpha
				)
	assert_int(frames.size()).is_greater(2)
	assert_int(overlaps).is_greater(20)


func test_a_strike_building_and_a_vehicle_leave_their_launch_and_exhaust_points_dark() -> void:
	var launch: Vector2 = _spot(STRIKE, 0)
	assert_str(_sheet(STRIKE).emitters[0]).is_equal("launch")
	var snap: MatchSnapshot = _runner.snapshot
	var tank: Vector2 = _centre(TANK)
	var exhaust: IsoSheetDef = _buildings.world_sort.sheet(
		snap.type_ids[snap.type_index[snap.index_of(TANK)]]
	)
	assert_bool(exhaust.emitters.has("exhaust")).is_true()
	_run(START, START + 60)
	assert_int(_air.slot_count()).is_greater(0)  # The others do puff.
	for slot: int in _air.slot_count():
		assert_float(_air.puff_at(slot).distance_to(launch)).is_greater(30.0)
		for dir: int in 16:  # The exhaust point of every hull facing.
			var point: Vector2 = (
				tank + exhaust.emitter_point(exhaust.emitters.find("exhaust"), dir) * 0.5
			)
			assert_float(_air.puff_at(slot).distance_to(point)).is_greater(2.0)


func test_the_view_margin_is_a_tile_and_a_pan_back_makes_no_catch_up() -> void:
	var margin: float = BuildingLayer.ANIM_MARGIN_PX
	var spot: Vector2 = _spot(HQ, 0)
	_set_camera_for(spot, -margin * 0.5)  # Just outside the view, inside the grown rect.
	assert_bool(_camera.visible_world_rect().has_point(spot)).is_false()
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(spot)).is_true()
	assert_int(_lone(HQ, 450)).is_greater(0)  # Born (it fails when it never puffs).
	_set_camera_for(spot, -margin * 1.5)  # Outside the grown rect too.
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(spot)).is_false()
	_air._empty()
	_run(START, START + 60)
	assert_int(_air.slot_count()).is_equal(0)
	_set_camera_for(spot, 100.0)  # Pan back: the time away is not made up.
	_run(START + 60, START + 61)
	for slot: int in _air.slot_count():
		assert_int(_air.puff_born(slot)).is_greater_equal(START + 60)
	assert_int(_air.slot_count()).is_less_equal(1)


func test_a_site_and_a_blacked_out_building_do_not_puff_and_a_finished_one_starts() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.build_left[snap.index_of(HALL)] = 500
	snap.offline_until[snap.index_of(HALL_B)] = START + 60
	_run(START, START + 45)
	assert_int(_births(_spot(HALL, 0)).size()).is_equal(0)
	assert_int(_births(_spot(HALL_B, 0)).size()).is_equal(0)
	assert_int(_births(_spot(HQ, 0)).size()).is_greater(0)
	snap.build_left[snap.index_of(HALL)] = 0
	_run(START + 45, START + 105)
	assert_int(_births(_spot(HALL, 0)).size()).is_greater(0)  # Done.
	var online_from: int = START + 60
	for tick: int in _births(_spot(HALL_B, 0)):
		assert_int(tick).is_greater_equal(online_from)  # Power back: from the tick it is online.
	assert_int(_births(_spot(HALL_B, 0)).size()).is_greater(0)


func test_an_enemy_building_puffs_only_while_shown_and_an_own_one_always() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Buildings.see(snap, 1, [])  # The local player sees nothing.
	_run(START, START + 45)
	assert_int(_births(_spot(LUMEN, 0)).size()).is_equal(0)
	assert_int(_births(_spot(LUMEN, 1)).size()).is_equal(0)
	assert_int(_births(_spot(HALL, 0)).size()).is_greater(0)  # Own, in the dark.
	_air._empty()
	var foot: Rect2i = BuildingLayer.footprint_of(snap, snap.index_of(LUMEN))
	Buildings.see(snap, 1, [foot.position])  # One corner cell is enough to show it.
	_run(START + 45, START + 90)
	assert_int(_births(_spot(LUMEN, 0)).size()).is_greater(0)
	assert_int(_births(_spot(LUMEN, 1)).size()).is_greater(0)
	_air._empty()
	Buildings.see(snap, 1, [])
	_run(START + 90, START + 135)
	assert_int(_births(_spot(LUMEN, 0)).size()).is_equal(0)  # Out of sight again: none.


func test_nothing_is_born_for_a_spot_outside_the_view_and_a_layer_without_a_camera_makes_none(
) -> void:
	_camera.position = _centre(LUMEN) + Vector2(100000.0, 0.0)
	_run(START, START + 45)
	assert_int(_air.slot_count()).is_equal(0)
	_camera.position = (_centre(REFINERY) + _centre(LUMEN)) * 0.5
	_run(START + 45, START + 90)
	assert_int(_air.slot_count()).is_greater(0)
	var bare: AirFx = auto_free(AirFx.new())
	bare.runner = _runner
	bare.life = _life
	bare.building_layer = _buildings
	add_child(bare)
	bare.set_process(false)
	_run(START + 90, START + 135)
	assert_int(bare.slot_count()).is_equal(0)
	var blind: AirFx = auto_free(AirFx.new())
	blind.runner = _runner
	blind.camera = _camera
	blind.life = _life  # No building layer: nothing says who is shown.
	add_child(blind)
	blind.set_process(false)
	_run(START + 135, START + 180)
	assert_int(blind.slot_count()).is_equal(0)


func test_the_ring_is_the_quota_and_the_newest_puff_overwrites_the_oldest() -> void:
	assert_int(_life.emitter_slots).is_equal(80)
	_life.emitter_slots = 3
	_run(START, START + 60)
	assert_int(_air.slot_count()).is_equal(3)
	Rig.at(_runner, START + 59, 0.5)
	_air._process(0.0)
	assert_int(_air.quad_count()).is_less_equal(3)
	var newest: int = 0
	for slot: int in 3:
		newest = maxi(newest, _air.puff_born(slot))
	assert_int(newest).is_equal(START + 59 - _ticks_since_last_birth())
	for slot: int in 3:  # The three newest of the run, none of the first ones.
		assert_int(_air.puff_born(slot)).is_greater(START + 40)


func test_nine_emitters_never_hold_more_than_four_puffs_each_nor_the_quota() -> void:
	var most: int = 0
	for tick: int in range(START, START + 200):
		_run(tick, tick + 1)
		for step: int in 4:
			Rig.at(_runner, tick, 0.25 * float(step))
			_air._process(0.0)
			most = maxi(most, _air.quad_count())
	assert_int(most).is_between(9, 36)
	assert_int(_air.slot_count()).is_less_equal(_life.emitter_slots)


func test_with_reduced_nothing_is_born_the_ring_empties_on_the_switch_and_comes_back() -> void:
	_run(START, START + 45)
	Rig.at(_runner, START + 44, 0.5)
	_air._process(0.0)
	assert_int(_air.quad_count()).is_greater(0)
	_life.reduced = true
	_air._process(0.0)
	assert_int(_air.slot_count()).is_equal(0)
	assert_int(_air.quad_count()).is_equal(0)
	_run(START + 45, START + 120)
	assert_int(_air.slot_count()).is_equal(0)  # Nothing was born, before a frame could empty it.
	_air._process(0.0)
	assert_int(_air.slot_count()).is_equal(0)
	assert_int(_air.quad_count()).is_equal(0)
	_life.reduced = false
	_run(START + 120, START + 165)
	assert_int(_air.slot_count()).is_greater(0)


func test_only_a_flame_is_ever_mirrored_and_both_looks_occur() -> void:
	var flipped: Dictionary[int, int] = {SMOKE: 0, STEAM: 0, FLAME: 0}
	var plain: Dictionary[int, int] = {SMOKE: 0, STEAM: 0, FLAME: 0}
	var frames: Dictionary[int, bool] = {}
	for tick: int in range(START, START + 600):
		_run(tick, tick + 1)
		Rig.at(_runner, tick, 0.0)
		_air._process(0.0)
		for index: int in _air.quad_count():
			var kind: int = _air.quad_kind(index)
			if _air.quad_flipped(index):
				flipped[kind] += 1
			else:
				plain[kind] += 1
			if kind == FLAME:
				frames[_air.quad_frame(index)] = true
	assert_int(flipped[SMOKE]).is_equal(0)
	assert_int(flipped[STEAM]).is_equal(0)
	assert_int(flipped[FLAME]).is_greater(0)
	assert_int(plain[FLAME]).is_greater(0)
	assert_int(frames.size()).is_equal(LifeRegions.FRAMES[&"flare"])
	assert_bool(LifeRegions.mirrorable(&"flare")).is_true()
	assert_bool(LifeRegions.mirrorable(&"smoke")).is_false()


func test_z_25_off_switches_a_new_match_and_a_pause_gap() -> void:
	assert_int(_air.z_index).is_equal(25)
	assert_bool(_air.z_as_relative).is_false()
	_life.emitter_slots = 0
	_run(START, START + 45)
	assert_int(_air.slot_count()).is_equal(0)
	_life.emitter_slots = 80
	_life.emit_ms = {&"smoke": 0, &"steam": 0, &"flare": 0}
	_run(START + 45, START + 90)
	assert_int(_air.slot_count()).is_equal(0)
	_life.emit_ms = DATA.emit_ms
	_run(START + 90, START + 93)
	var before: int = _air.slot_count()
	_run(START + 600, START + 601)  # A gap of 500 ticks (a pause), then one tick: no burst.
	assert_int(_air.slot_count() - before).is_less_equal(EMITTING.size() * 2)
	assert_int(_air.slot_count()).is_greater(0)
	_runner.start()  # A new match empties the ring.
	_air._process(0.0)
	assert_int(_air.slot_count()).is_equal(0)
	assert_int(_air.quad_count()).is_equal(0)


func _sees_all() -> void:
	var tiles: Array[Vector2i] = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)


## Delivers ticks `from` up to (not including) `to`, each published with `ticked`; no frame.
func _run(from: int, to: int) -> void:
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)


func _sheet(id: int) -> IsoSheetDef:
	var snap: MatchSnapshot = _runner.snapshot
	return _buildings.world_sort.sheet(snap.type_ids[snap.type_index[snap.index_of(id)]])


func _centre(id: int) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	return IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


## Where emitter `index` of building `id` puffs, restated from the sheet: its point is in px of the
## 2x art, half of that in world px.
func _spot(id: int, index: int) -> Vector2:
	return _centre(id) + _sheet(id).emitter_point(index, -1) * 0.5


## The ms between puffs of a sheet emitter kind, from the data file's sprite-kind table.
func _emit_ms(kind: String) -> int:
	var sprite: StringName = &"flare" if kind == "flame" else StringName(kind)
	return maxi(DATA.emit_ms[sprite], 500)


## The ticks of the births at `spot` still in the ring, oldest first.
func _births(spot: Vector2) -> Array[int]:
	var found: Array[int] = []
	for slot: int in _air.slot_count():
		if _air.puff_at(slot).distance_to(spot) < 0.01:
			found.append(_air.puff_born(slot))
	found.sort()
	return found


## The quad of the plan whose puff was born at `spot` (its anchor, before the rise), -1 for none.
func _quad_at(spot: Vector2) -> int:
	var best: int = -1
	var near: float = 40.0
	for index: int in _air.quad_count():
		var rect: Rect2 = _air.quad_rect(index)
		var away: float = rect.get_center().distance_to(spot)
		if away < near:
			near = away
			best = index
	return best


## Whether an emitter of `every` ms from `phase` ms has a puff due in tick `tick`: a multiple of
## `every` lies in the 1/15 s up to the tick's match time (all in fifteenths of a ms).
func _cycle_turns(tick: int, phase: int, every: int) -> bool:
	var low: int = (tick - 1) * 1000 + 15 * phase
	var high: int = tick * 1000 + 15 * phase
	var k: int = maxi(low / (15 * every) - 1, 0)
	while 15 * k * every <= high:
		if 15 * k * every > low:
			return true
		k += 1
	return false


func _ticks_since_last_birth() -> int:
	var newest: int = 0
	for slot: int in _air.slot_count():
		newest = maxi(newest, _air.puff_born(slot))
	return START + 59 - newest


## One tick-delivered run until the first puff of building `id` is born, with every other emitter
## off (the other buildings are sites) and every puff living `life_ms`; returns its birth tick.
func _lone(id: int, life_ms: int) -> int:
	_life.emit_life_ms = {&"smoke": life_ms, &"steam": life_ms, &"flare": life_ms}
	var snap: MatchSnapshot = _runner.snapshot
	for other: int in EMITTING:
		snap.build_left[snap.index_of(other)] = 0 if other == id else 500
	_air._empty()
	for tick: int in range(START, START + 60):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		if _air.slot_count() > 0:
			return _air.puff_born(0)
	fail("building %d never puffed" % id)
	return -1


## Plans the frame at `tick` and `alpha`.
func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_air._process(0.0)


## Puts the camera so that `spot` is `inside` px inside the left edge of the view rect (negative:
## outside it), whatever the camera's size.
func _set_camera_for(spot: Vector2, inside: float) -> void:
	_camera.position.x += spot.x - inside - _camera.visible_world_rect().position.x
