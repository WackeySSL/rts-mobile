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


func test_the_ring_never_holds_more_than_80_and_a_new_puff_overwrites_the_oldest() -> void:
	for id: int in IDS:
		_hp(id, 10)
	_camera.position = (_centre(1) + _centre(5)) * 0.5
	_life.damage_slots = 80
	_run(START, START + 150)
	var ring: FxRing = _air.damage().ring
	assert_int(ring.count()).is_equal(80)
	var second: float = ring.puff_born(1)
	var newest: float = ring.puff_born(79)
	var born: float = LifeClock.tick_ms(START + 150)
	ring.add(DamageFx.Style.SMOKE, Vector2(7.0, 7.0), born, 0)
	assert_int(ring.count()).is_equal(80)  # Full: one in, the oldest out.
	assert_float(ring.puff_born(0)).is_equal(second)
	assert_float(ring.puff_born(78)).is_equal(newest)
	assert_float(ring.puff_born(79)).is_equal(born)
	assert_vector(ring.puff_at(79)).is_equal(Vector2(7.0, 7.0))
	_frame(START + 149, 0.5)
	assert_int(ring.quad_count()).is_less_equal(80)


func test_a_kritisk_building_holds_three_glows_and_each_burning_point_glows_steadily() -> void:
	_only(1)
	_hp(1, 10)
	_only(1)
	var first: int = _first_point(1)
	var spots: Array[Vector2] = []
	for step: int in 3:
		spots.append(_spot(1, 1 + (first - 1 + step) % 4))
	var ring: FxRing = _air.damage().ring
	var sums: Array[float] = []
	for tick: int in range(START, START + 75):  # 5 s; the glows start within a cycle.
		Rig.deliver(_runner, PackedInt32Array(), tick)
		var glows: int = 0
		for index: int in ring.count():
			var style: int = ring.puff_style(index)
			if style == DamageFx.Style.GLOW_STRONG or style == DamageFx.Style.GLOW_WEAK:
				glows += 1
		assert_int(glows).override_failure_message("tick %d" % tick).is_less_equal(3)
		if tick < START + 45:
			continue
		for alpha: float in [0.0, 0.5, 0.9]:  # Two seconds of frames, three to a tick.
			_frame(tick, alpha)
			var sum: float = 0.0
			for index: int in ring.quad_count():
				sum += ring.quad_alpha(index) if ring.quad_kind(index) == DamageFx.K_GLOW else 0.0
			sums.append(sum)
	assert_int(sums.size()).is_equal(90)
	var most: float = sums.max()
	var least: float = sums.min()
	assert_float(most - least).is_less(0.05)
	# Two of the three points are fire points at most (a spark point has no fire or glow).
	assert_float(most).is_less_equal(3.0 * _life.glow_strong_alpha + 0.001)
	assert_float(least).is_greater(0.0)
	assert_int(spots.size()).is_equal(3)


func test_no_burning_building_has_more_than_15_live_smoke_puffs_with_the_default_numbers() -> void:
	_only(1)
	_hp(1, 10)
	_only(1)
	var most: int = 0
	for tick: int in range(START, START + 150):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		_frame(tick, 0.9)
		var live: int = 0
		var ring: FxRing = _air.damage().ring
		for index: int in ring.quad_count():
			var kind: int = ring.quad_kind(index)
			live += 1 if kind == DamageFx.K_SMOKE or kind == DamageFx.K_SOOT else 0
		most = maxi(most, live)
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


func test_the_kritisk_fire_and_glow_are_larger_and_stronger_than_the_skadet_ones() -> void:
	# Building 8 burns its `damage` point first: a small fire and a weak glow at SKADET, a big fire
	# (`damage_fire_scale`) and a strong glow (`glow_strong_alpha`, the same scale) at KRITISK. At the
	# tick of the newest fire's birth that puff is the widest and the most opaque of its kind.
	_camera.position = _centre(8)
	var weak: Array = _peak_fire(8, 60)
	var strong: Array = _peak_fire(8, 10)
	assert_float(weak[0]).is_equal_approx(
		float(LifeRegions.region(&"fire").size.x) * _life.emit_flame_from, 0.01
	)
	assert_float(strong[0] / weak[0]).is_equal_approx(_life.damage_fire_scale, 0.001)
	assert_float(weak[1]).is_equal_approx(_life.glow_weak_alpha, 0.0001)
	assert_float(strong[1]).is_equal_approx(_life.glow_strong_alpha, 0.0001)
	assert_float(strong[2] / weak[2]).is_equal_approx(_life.damage_fire_scale, 0.001)
	assert_float(_life.damage_fire_scale).is_greater(1.0)
	assert_float(_life.glow_strong_alpha).is_greater(_life.glow_weak_alpha)


func test_the_pinned_ids_1_2_3_at_kritisk_keep_every_soot_puff_and_four_lose_the_oldest() -> void:
	var three: Array[int] = [1, 2, 3]
	var kept: Array = _soot_log(three, 80)
	var room: Array = _soot_log(three, 2000)  # With room for all.
	for tick: int in kept.size():
		assert_array(kept[tick][0]).override_failure_message("tick %d" % tick).is_equal(
			room[tick][0]
		)
	var four: Array[int] = [1, 2, 3, 4]
	var all: Array = _soot_log(four, 2000)
	var some: Array = _soot_log(four, 80)
	var lost: int = 0
	for tick: int in all.size():
		for key: Array in all[tick][0]:
			if not (some[tick][0] as Array).has(key):
				lost += 1
				# Only what is older than everything the full ring still holds goes.
				assert_float(key[0]).is_less_equal(some[tick][1])
	assert_int(lost).is_greater(0)


## The widest fire quad, the strongest glow quad's alpha and its width, at the tick of the newest
## fire's birth, for building `id` at `percent` of its hp.
func _peak_fire(id: int, percent: int) -> Array:
	_only(id)
	_hp(id, percent)
	_only(id)
	_run(START, START + 60)
	var newest: float = 0.0
	for puff: Array in _puffs():
		if puff[0] == DamageFx.Style.FIRE or puff[0] == DamageFx.Style.FIRE_BIG:
			newest = maxf(newest, puff[2])
	_frame(roundi(newest / TICK_MS), 0.0)
	var ring: FxRing = _air.damage().ring
	var width: float = 0.0
	var alpha: float = 0.0
	var glow_width: float = 0.0
	for index: int in ring.quad_count():
		var rect: Rect2 = ring.quad_rect(index)
		if ring.quad_kind(index) == DamageFx.K_FIRE:
			width = maxf(width, rect.size.x)
		if ring.quad_kind(index) == DamageFx.K_GLOW and ring.quad_alpha(index) > alpha:
			alpha = ring.quad_alpha(index)
			glow_width = rect.size.x
	return [width, alpha, glow_width]


## For each tick of a run, [the live soot puffs as [born ms, spot], the born ms of the oldest puff
## of the ring] with a ring of `slots`, the buildings `ids` at KRITISK and the others intact.
func _soot_log(ids: Array[int], slots: int) -> Array:
	_life.damage_slots = slots
	for id: int in IDS:
		_hp(id, 10 if ids.has(id) else 100)
	_camera.position = (_centre(1) + _centre(5)) * 0.5
	var log: Array = []
	for tick: int in range(START, START + 120):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		var ring: FxRing = _air.damage().ring
		var live: Array = []
		var oldest: float = INF
		for index: int in ring.count():
			oldest = minf(oldest, ring.puff_born(index))
			var age: float = LifeClock.tick_ms(tick) - ring.puff_born(index)
			if (
				ring.puff_style(index) == DamageFx.Style.SOOT
				and age < float(_life.damage_life_ms[&"soot"])
			):
				live.append([ring.puff_born(index), ring.puff_at(index)])
		log.append([live, oldest])
	return log
