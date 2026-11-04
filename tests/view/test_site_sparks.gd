extends "res://tests/view/support/damage_fx_suite.gd"
## The sparks of a construction site (plan P150, ADR 0027 sections 3, 6 and 8): a building with
## `build_left` above 0 that the player is shown throws a `spark` every `spark_ms` from a spot of
## its footprint, into the 24-slot ring of the muzzle and exhaust puffs; a finished building, a
## hidden enemy site and a site out of view throw none; `reduced` keeps them while it drops the
## muzzle smoke; a DIED record with the cancel flag draws nothing. Fixture:
## support/damage_fx_suite.gd (Barracks on a crafted sheet).

const SPARK: int = PuffFx.Style.SPARK
const SALT_PHASE: int = 0x7D000000
const SALT_SPOT: int = 0x7E000000


func test_the_numbers_are_the_data_files() -> void:
	assert_int(DATA.spark_ms).is_equal(200)
	assert_int(DATA.spark_life_ms).is_equal(300)
	assert_int(DATA.spark_life_ms).is_less_equal(PuffFx.MAX_LIFE_MS)
	assert_float(DATA.spark_alpha).is_equal(1.0)
	assert_int(DATA.puff_slots).is_equal(24)  # The ring is shared with the muzzle smoke.


func test_a_site_throws_a_spark_every_spark_ms_and_a_finished_building_none() -> void:
	_open([[1, 4, 4], [1, 12, 12]])
	_set_site(1, 500)
	var born: Array[int] = _births(START, START + 60)
	assert_array(born).is_equal(_expected_births(1, START, START + 60))
	assert_int(born.size()).is_between(19, 21)  # Every 200 ms = 3 ticks, 60 ticks.
	assert_int(_expected_births(2, START, START + 60).size()).is_equal(0)  # Building 2 is done.


func test_the_spark_stands_on_the_footprint_lifted_and_is_the_third_kind() -> void:
	_open([[1, 4, 4]])
	_set_site(1, 500)
	_births(START, START + 12)
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(1)
	var wide: int = snap.type_foot_w[snap.type_index[row]]
	var high: int = snap.type_foot_h[snap.type_index[row]]
	assert_int(wide).is_greater(0)
	var ring: FxRing = _ring()
	assert_int(ring.count()).is_greater(0)
	for slot: int in ring.count():
		assert_int(ring.puff_style(slot)).is_equal(SPARK)
		var ground: Vector2i = IsoProjection.px_to_ground(
			ring.puff_at(slot) + Vector2(0.0, _life.spark_lift_px)
		)
		assert_int(absi(ground.x - snap.pos_x[row])).is_less_equal(wide * 500 + 2)
		assert_int(absi(ground.y - snap.pos_y[row])).is_less_equal(high * 500 + 2)
	var spots: Dictionary = {}
	for slot: int in ring.count():
		spots[ring.puff_at(slot)] = true
	assert_int(spots.size()).is_greater(1)  # Not one fixed point.
	assert_int(ring.quad_count()).is_equal(0)  # Planned by the frame, not the tick.


func test_the_spark_flies_up_fades_and_is_drawn_after_the_clouds() -> void:
	_open([[1, 4, 4]])
	_run(START - 1, START)  # The styles are read at the first tick; no site yet.
	var ring: FxRing = _ring()
	ring.add(SPARK, _centre(1), LifeClock.tick_ms(START), 0)
	_frame(START, 0.0)
	var low: Rect2 = ring.quad_rect(0)
	assert_float(ring.quad_alpha(0)).is_equal_approx(DATA.spark_alpha, 0.001)
	_frame(START + 2, 0.0)  # 133 ms of 300.
	assert_float(ring.quad_alpha(0)).is_less(DATA.spark_alpha)
	assert_float(ring.quad_rect(0).position.y).is_less(low.position.y)
	assert_int(ring._pass[PuffFx.K_SPARK]).is_equal(FxRing.FLAME)
	_frame(START + 5, 0.0)  # 333 ms: gone.
	assert_int(ring.quad_count()).is_equal(0)


func test_an_own_site_is_always_shown_an_enemy_one_only_while_seen() -> void:
	_open([[1, 4, 4], [2, 12, 12]], [QUIET, 0, 0, 0, 0], false)
	_set_site(2, 500)
	_camera.position = _centre(2)
	assert_array(_births(START, START + 30)).is_empty()  # In view, in the dark.
	Buildings.see(_runner.snapshot, 1, [Vector2i(12, 12), Vector2i(13, 12), Vector2i(12, 13)])
	assert_array(_births(START + 30, START + 60)).is_not_empty()
	_ring().clear()
	_set_site(1, 500)  # Your own site far from the camera's seen tiles is shown all the same.
	_camera.position = _centre(1)
	assert_array(_births(START + 60, START + 90)).is_not_empty()


func test_a_site_out_of_view_throws_nothing() -> void:
	_open([[1, 4, 4], [1, 12, 12]])
	_set_site(1, 500)
	var margin: float = BuildingLayer.ANIM_MARGIN_PX
	_camera.position.x += _centre(1).x + margin * 2.0 - _camera.visible_world_rect().position.x
	assert_bool(_camera.visible_world_rect().grow(margin).has_point(_centre(1))).is_false()
	assert_array(_births(START, START + 30)).is_empty()


func test_reduced_keeps_the_sparks_and_drops_the_muzzle_smoke_and_the_exhaust() -> void:
	_open([[1, 4, 4]])
	_set_site(1, 500)
	_life.reduced = true
	assert_array(_births(START, START + 30)).is_equal(_expected_births(1, START, START + 30))
	assert_int(_ring().count()).is_greater(0)
	_life.reduced = false
	_ring().add(PuffFx.Style.MUZZLE, Vector2.ZERO, LifeClock.tick_ms(START + 30), 0)
	_ring().add(PuffFx.Style.EXHAUST, Vector2.ZERO, LifeClock.tick_ms(START + 30), 0)
	var sparks: int = _sparks_alive()
	assert_int(_ring().count()).is_equal(sparks + 2)
	_life.reduced = true  # The switch: the smoke goes at once, the sparks stay.
	_frame(START + 30, 0.5)
	assert_int(_ring().count()).is_equal(sparks)


func test_a_died_record_with_the_cancel_flag_draws_nothing() -> void:
	_open([[1, 4, 4]])
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(1)
	var gone: PackedInt32Array = PackedInt32Array(
		[World.Event.DIED, 1, snap.pos_x[row], snap.pos_y[row], snap.type_index[row], 1, 1, 0]
	)
	Rig.deliver(_runner, gone, START)  # The site is cancelled: the row is complete here, and dies.
	for ring: FxRing in _air._rings:
		assert_int(ring.count()).is_equal(0)


func test_a_site_that_finishes_stops_and_its_sparks_live_out() -> void:
	_open([[1, 4, 4]])
	_set_site(1, 500)
	_births(START, START + 12)
	assert_int(_ring().count()).is_greater(0)
	_set_site(1, 0)  # Complete.
	assert_array(_births(START + 12, START + 60)).is_empty()
	assert_int(_ring().count()).is_equal(0)  # All lived out (300 ms) and were given back.


func test_a_site_with_sparks_off_throws_none() -> void:
	_open([[1, 4, 4]])
	_set_site(1, 500)
	_life.spark_ms = 0
	assert_array(_births(START, START + 30)).is_empty()
	_life.spark_ms = DATA.spark_ms
	_life.spark_life_ms = 0
	assert_array(_births(START + 30, START + 60)).is_empty()


func _ring() -> FxRing:
	return _air.puffs().ring


func _set_site(id: int, left: int) -> void:
	_runner.snapshot.build_left[_runner.snapshot.index_of(id)] = left


# The sparks alive in the ring.
func _sparks_alive() -> int:
	var found: int = 0
	for slot: int in _ring().count():
		found += 1 if _ring().puff_style(slot) == SPARK else 0
	return found


# Delivers the ticks `from` to `to` (exclusive) and returns the ticks at which a spark was born.
func _births(from: int, to: int) -> Array[int]:
	var found: Array[int] = []
	for tick: int in range(from, to):
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for slot: int in _ring().count():
			if (
				_ring().puff_style(slot) == SPARK
				and is_equal_approx(_ring().puff_born(slot), LifeClock.tick_ms(tick))
			):
				found.append(tick)
	return found


# The ticks in `from` to `to` (exclusive) at which the cycle of site `id` turns over, restated:
# every `spark_ms` from a phase of its own.
@warning_ignore("integer_division")
func _expected_births(id: int, from: int, to: int) -> Array[int]:
	var snap: MatchSnapshot = _runner.snapshot
	var found: Array[int] = []
	if snap.build_left[snap.index_of(id)] <= 0:
		return found
	var every: int = DATA.spark_ms
	var phase: int = LifeClock.pick(id, SALT_PHASE, every)
	for tick: int in range(from, to):
		var now: int = (tick * 1000 + phase * Sim.TICK_RATE) / (every * Sim.TICK_RATE)
		var before: int = ((tick - 1) * 1000 + phase * Sim.TICK_RATE) / (every * Sim.TICK_RATE)
		if now != before:
			found.append(tick)
	return found
