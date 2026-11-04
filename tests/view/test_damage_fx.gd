extends "res://tests/view/support/damage_fx_suite.gd"
## The particles of damaged buildings (plan P148, ADR 0029 section 6): the burning points that
## `LifeClock.pick` names, what each stage and each type of point emits, the jet's side, who emits
## (a site, a hidden enemy, a source out of view do not; a blackout does not stop it), the ring.
## Fixture: support/damage_fx_suite.gd (Barracks 1 to 4 on a crafted sheet). The kinds of puff in
## the ring and its draw order are in test_damage_fx_kinds.gd.

const IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const SPAWNS: Array = [
	[1, 4, 4], [1, 12, 4], [1, 20, 4], [1, 4, 12], [1, 12, 12], [1, 20, 12], [1, 4, 20], [1, 12, 20]
]
## The point (an emitter index, 1 to 4) that burns first for ids 1 to 8, pinned: the same on every
## device and run (`1 + LifeClock.pick(id, 0x70000000, 4)`). Between them they burn the `damage`
## point (id 8), both gas points and the spark.
const PINNED: Array[int] = [2, 4, 3, 4, 3, 2, 4, 1]
const SECOND: float = 15.0


func before_test() -> void:
	_open(SPAWNS)


func test_the_burning_point_is_the_pick_of_the_id_and_three_buildings_burn_the_pinned_points(
) -> void:
	for index: int in IDS.size():
		var id: int = IDS[index]
		assert_int(_first_point(id)).override_failure_message("id %d" % id).is_equal(PINNED[index])
	for point: int in [1, 2, 3, 4]:  # Between them the eight burn every point.
		assert_bool(PINNED.has(point)).is_true()


func test_at_skadet_one_point_burns_with_smoke_and_the_fire_of_its_type() -> void:
	# `damage`: smoke, a small fire and a weak glow. `dmg_gas`: smoke, a jet and its glow.
	# `dmg_spark`: smoke and sparks, no fire.
	var want: Dictionary = {
		1: ["fire", "glow_weak", "smoke"],
		2: ["glow_jet", "jet", "smoke"],
		3: ["glow_jet", "jet", "smoke"],
		4: ["smoke", "spark"],
	}
	for id: int in IDS:
		_air.damage().clear()
		_only(id)
		_hp(id, 60)
		_only(id)
		_run(START, START + 45)
		var burning: int = _first_point(id)
		(
			assert_array(_styles_at(_spot(id, burning)))
			. override_failure_message("id %d point %d" % [id, burning])
			. is_equal(want[burning])
		)
		assert_int(_air.damage().ring.count()).is_greater(0)
		for puff: Array in _puffs():  # Nothing from any other point.
			assert_vector(puff[1]).is_equal(_spot(id, burning))


func test_at_kritisk_up_to_three_points_burn_from_the_first_with_soot_a_big_fire_and_sparks(
) -> void:
	for id: int in IDS:
		_air.damage().clear()
		_only(id)
		_hp(id, 20)
		_only(id)
		_run(START, START + 60)
		var first: int = _first_point(id)
		for step: int in 4:
			var index: int = 1 + (first - 1 + step) % 4
			var burns: bool = step < 3
			var kind: String = POINT_NAMES[index]
			var styles: Array = _styles_at(_spot(id, index))
			(
				assert_bool(styles.has("soot"))
				. override_failure_message("%d/%d" % [id, index])
				. is_equal(burns)
			)
			(
				assert_bool(styles.has("spark"))
				. override_failure_message("%d/%d" % [id, index])
				. is_equal(burns)
			)
			assert_bool(styles.has("fire_big")).is_equal(burns and kind != "dmg_spark")
			assert_bool(styles.has("glow_strong")).is_equal(burns and kind != "dmg_spark")
			(
				assert_bool(styles.has("jet"))
				. override_failure_message("a jet only at SKADET")
				. is_false()
			)
			assert_bool(styles.has("smoke")).is_false()


func test_a_jet_is_mirrored_when_its_point_lies_left_of_the_footprint_centre() -> void:
	# The jet points away from its building: the point on the right is drawn as it is, the point on
	# the left mirrored. Four buildings burn both gas points between them.
	var seen: Dictionary = {false: 0, true: 0}
	for id: int in IDS:
		_air.damage().clear()
		_only(id)
		_hp(id, 60)
		_only(id)
		_run(START, START + 60)
		var burning: int = _first_point(id)
		if POINT_NAMES[burning] != "dmg_gas":
			continue
		var left: bool = POINT_AT[burning].x < 0.0
		_frame(START + 20, 0.0)
		var ring: FxRing = _air.damage().ring
		var jets: int = 0
		for index: int in ring.quad_count():
			if ring.quad_kind(index) == DamageFx.K_JET:
				jets += 1
				assert_bool(ring.quad_flipped(index)).is_equal(left)
		assert_int(jets).is_greater(0)
		seen[left] += jets
	assert_int(seen[true]).is_greater(0)
	assert_int(seen[false]).is_greater(0)


func test_the_gas_point_to_the_right_and_the_left_are_both_in_the_crafted_sheet() -> void:
	assert_bool(POINT_AT[2].x > 0.0 and POINT_AT[3].x < 0.0).is_true()
	assert_bool(LifeRegions.mirrorable(&"jet")).is_true()


func test_an_intact_building_a_site_and_a_hidden_enemy_emit_nothing() -> void:
	_hp(1, 100)
	_run(START, START + 45)
	assert_int(_air.damage().ring.count()).is_equal(0)
	_hp(1, 20)  # A site never burns, whatever its hp.
	_runner.snapshot.build_left[_runner.snapshot.index_of(1)] = 500
	_only(2)
	_runner.snapshot.build_left[_runner.snapshot.index_of(2)] = 500
	_only(3)
	_runner.snapshot.build_left[_runner.snapshot.index_of(3)] = 500
	_runner.snapshot.build_left[_runner.snapshot.index_of(4)] = 500
	_run(START, START + 45)
	assert_int(_air.damage().ring.count()).is_equal(0)
	# An enemy building the player does not see.
	_open([[1, 4, 4], [2, 12, 4]], [QUIET, 0, 0, 0, 0], false)
	_camera.position = _centre(2)
	Buildings.see(_runner.snapshot, 1, [])
	_hp(2, 20)
	_run(START, START + 45)
	assert_int(_air.damage().ring.count()).is_equal(0)
	var tiles: Array[Vector2i] = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)
	_run(START + 45, START + 90)
	assert_int(_air.damage().ring.count()).is_greater(0)


func test_a_source_outside_the_view_grown_by_a_tile_emits_nothing_and_a_blackout_does_not_stop_it(
) -> void:
	_only(1)
	_hp(1, 20)
	_only(1)
	var spot: Vector2 = _spot(1, _first_point(1))
	var margin: float = BuildingLayer.ANIM_MARGIN_PX
	_camera.position.x += spot.x + margin * 1.5 - _camera.visible_world_rect().position.x
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(spot)).is_false()
	_run(START, START + 45)
	assert_int(_air.damage().ring.count()).is_equal(0)
	_camera.position = _centre(1)
	_runner.snapshot.offline_until[_runner.snapshot.index_of(1)] = START + 1000  # A blackout.
	_run(START, START + 45)
	assert_int(_air.damage().ring.count()).is_greater(0)


func test_the_ring_never_holds_more_than_80_and_overwrites_its_oldest() -> void:
	for id: int in IDS:
		_hp(id, 10)
	_camera.position = (_centre(1) + _centre(5)) * 0.5
	_life.damage_slots = 80
	var oldest: float = INF
	_run(START, START + 150)
	var ring: FxRing = _air.damage().ring
	assert_int(ring.capacity()).is_equal(80)
	assert_int(ring.count()).is_equal(80)
	for puff: Array in _puffs():
		oldest = minf(oldest, puff[2])
	assert_float(oldest).is_greater(LifeClock.tick_ms(START))  # The first births are gone.
	_frame(START + 149, 0.5)
	assert_int(ring.quad_count()).is_less_equal(80)


func test_no_burning_building_has_more_than_15_live_smoke_puffs_with_the_default_numbers() -> void:
	_only(1)
	_hp(1, 10)
	_only(1)
	var most: int = 0
	var first: float = 0.0
	for tick: int in range(START, START + 150):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		_frame(tick, 0.9)
		var live: int = 0
		var ring: FxRing = _air.damage().ring
		for index: int in ring.quad_count():
			var kind: int = ring.quad_kind(index)
			live += 1 if kind == DamageFx.K_SMOKE or kind == DamageFx.K_SOOT else 0
		most = maxi(most, live)
		first = maxf(first, 0.0)
	assert_int(most).is_greater(0)
	assert_int(most).is_less_equal(15)


func test_a_new_match_and_the_same_run_twice() -> void:
	_only(2)
	_hp(2, 20)
	_only(2)
	_run(START, START + 60)
	var first: Array = _puffs()
	assert_int(first.size()).is_greater(0)
	_air.damage().clear()
	_run(START, START + 60)
	assert_array(_puffs()).is_equal(first)  # Same ticks, same puffs.
	_runner.snapshot.match_serial += 1  # Another match.
	_frame(START + 59, 0.0)
	assert_int(_air.damage().ring.count()).is_equal(0)
	assert_int(_air.slot_count()).is_equal(0)
