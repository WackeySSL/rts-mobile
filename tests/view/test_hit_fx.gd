extends "res://tests/view/support/hit_fx_suite.gd"
## The hit feedback of buildings (plan P166, ADR 0029 section 7): which records are a hit,
## what it draws (a pinned number of chips), the hits that draw nothing, the ring of 16 and
## `reduced`.
## Fixture: support/hit_fx_suite.gd (Barracks 1 to 8 on a crafted sheet, all shown).


func test_the_numbers_are_the_data_files() -> void:
	assert_int(DATA.hit_slots).is_equal(16)
	assert_int(DATA.hit_flash_ms).is_equal(60)
	assert_int(DATA.hit_flash_box_milli).is_equal(500)
	assert_array(DATA.hit_chips).is_equal(PackedInt32Array([3, 5]))
	assert_int(DATA.hit_chip_ms).is_equal(350)
	assert_float(DATA.hit_alpha).is_equal(1.0)
	assert_vector(DATA.hit_flash_grow).is_equal(Vector2(0.7, 1.2))
	assert_int(DATA.hit_chip_fly_px.size()).is_between(1, HitFx.MAX_DIRECTIONS)
	assert_int(DATA.hit_chips[1]).is_less_equal(DATA.hit_chip_fly_px.size())  # A way per chip.
	assert_int(HitFx.MAX_DIRECTIONS).is_greater_equal(DATA.hit_chips[1])
	assert_array(DATA.hit_chip_fly_px).is_equal(
		PackedVector2Array(
			[
				Vector2(-14.0, 10.0),
				Vector2(-6.0, 18.0),
				Vector2(0.0, 22.0),
				Vector2(6.0, 18.0),
				Vector2(14.0, 10.0)
			]
		)
	)


func test_an_impact_on_a_shown_building_draws_one_flash_and_the_pinned_chips() -> void:
	for index: int in IMPACT_CHIPS.size():
		var id: int = index + 1
		_hit_at(_impact(id, id))
		assert_int(_of(HitFx.Style.FLASH)).override_failure_message("flash %d" % id).is_equal(1)
		assert_int(_of(HitFx.Style.CHIP)).override_failure_message("chips %d" % id).is_equal(
			IMPACT_CHIPS[index]
		)


func test_a_hit_id_picks_the_chip_count_from_the_data() -> void:
	for id: int in [1, 2, 3, 7, 50, 51, 52, 977]:
		var want: int = 3 + LifeClock.pick(id, SALT_CHIP, 3)
		_hit_at(_impact(id, 1))
		assert_int(_of(HitFx.Style.CHIP)).override_failure_message("id %d" % id).is_equal(want)


func test_a_rifle_shot_is_a_hit_with_the_mix_of_the_shooter_and_the_tick() -> void:
	for index: int in SHOT_CHIPS.size():
		var shooter: int = index + 1
		_hit_at(_shot(shooter, 2))
		assert_int(_of(HitFx.Style.FLASH)).is_equal(1)
		assert_int(LifeClock.pick(LifeClock.mix(shooter, START), SALT_CHIP, 3) + 3).is_equal(
			SHOT_CHIPS[index]
		)
		assert_int(_of(HitFx.Style.CHIP)).is_equal(SHOT_CHIPS[index])


func test_the_hits_that_draw_nothing() -> void:
	_hit_at(_shot(1, 2, SHELL))  # The SHOT of a shell weapon: its IMPACT is the hit.
	assert_int(_ring().count()).is_equal(0)
	_hit_at(_impact(5, 0))  # No target.
	assert_int(_ring().count()).is_equal(0)
	_hit_at(Effects.impact(Vector2i(5000, 5000), SHELL, 5, 977))  # An id that is nothing.
	assert_int(_ring().count()).is_equal(0)
	_hit_at(Effects.shot(Vector2i(5000, 5000), Vector2i(6000, 5000), RIFLE, 1, 977))
	assert_int(_ring().count()).is_equal(0)
	_hit_at(_impact(5, 2, 7))  # An IMPACT of a weapon the table lacks is still a hit.
	assert_int(_ring().count()).is_greater(0)


func test_an_impact_or_a_rifle_shot_on_a_unit_draws_nothing() -> void:
	_open(SPAWNS + [[1, 2, 2, "light_tank"]])
	_weapons()
	var snap: MatchSnapshot = _runner.snapshot
	var unit: int = 0
	for row: int in snap.unit_count():
		if not WorldSort.is_building(snap, snap.type_index[row]):
			unit = snap.unit_id[row]
	assert_int(unit).is_greater(0)
	assert_int(snap.index_of(unit)).is_greater_equal(0)  # A real row, which is no building's.
	assert_int(_buildings.row_of(unit)).is_equal(-1)
	var at: Vector2i = Rig.position_of(_runner, unit)
	_hit_at(Effects.impact(at, SHELL, 5, unit))
	assert_int(_ring().count()).is_equal(0)
	_hit_at(Effects.shot(at + Vector2i(2000, 0), at, RIFLE, 1, unit))
	assert_int(_ring().count()).is_equal(0)
	_hit_at(_impact(5, 1))  # A building beside it is hit as ever.
	assert_int(_of(HitFx.Style.FLASH)).is_equal(1)


func test_a_building_that_is_gone_has_no_row_and_a_live_one_has_its_row() -> void:
	assert_int(_buildings.row_of(977)).is_equal(-1)
	assert_int(_buildings.row_of(0)).is_equal(-1)
	for id: int in [1, 4, 8]:
		assert_int(_buildings.row_of(id)).is_equal(_runner.snapshot.index_of(id))


func test_an_impact_on_a_hidden_enemy_building_draws_nothing() -> void:
	_open([[1, 4, 4], [2, 20, 20]], [QUIET, 0, 0, 0, 0], false)
	_weapons()
	var row: int = _runner.snapshot.index_of(2)
	assert_bool(_buildings.is_shown(row)).is_false()
	_ring().clear()
	var events: PackedInt32Array = Effects.impact(Rig.position_of(_runner, 2), 0, 3, 2)
	Rig.deliver(_runner, events, START)
	assert_int(_ring().count()).is_equal(0)
	Rig.deliver(_runner, Effects.impact(Rig.position_of(_runner, 1), 0, 3, 1), START + 1)
	assert_int(_ring().count()).is_greater(0)  # Your own is always shown.


func test_a_hit_whose_target_died_in_the_same_tick_draws_nothing() -> void:
	var at: Vector2i = Rig.position_of(_runner, 3)
	var killing: PackedInt32Array = _impact(3, 3)
	killing.append_array(Effects.died(at, 0, 3, 1))
	_hit_at(killing)
	assert_int(_ring().count()).is_equal(0)
	var rifle: PackedInt32Array = _shot(1, 3)
	rifle.append_array(Effects.died(at, 0, 3, 1))
	_hit_at(rifle)
	assert_int(_ring().count()).is_equal(0)
	var other: PackedInt32Array = _impact(3, 3)  # Another unit's death does not stop it.
	other.append_array(Effects.died(at, 0, 4, 1))
	_hit_at(other)
	assert_int(_of(HitFx.Style.FLASH)).is_equal(1)
	var first: PackedInt32Array = _impact(3, 3)  # The target's DIED first, another unit's after it.
	first.append_array(Effects.died(at, 0, 3, 1))
	first.append_array(Effects.died(at, 0, 4, 1))
	_hit_at(first)
	assert_int(_ring().count()).is_equal(0)


func test_the_flash_lies_inside_the_middle_half_of_the_frame_box() -> void:
	var spots: Dictionary = {}
	for index: int in IMPACT_CHIPS.size():
		var id: int = index + 1
		_hit_at(_impact(id, id))
		var box: Rect2 = _buildings.frame_box(_runner.snapshot.index_of(id))
		var inner: Rect2 = Rect2(box.get_center() - box.size * 0.25, box.size * 0.5)
		for slot: int in _ring().count():
			var spot: Vector2 = _ring().puff_at(slot)
			(
				assert_bool(inner.grow(0.01).has_point(spot))
				. override_failure_message("id %d at %s in %s" % [id, spot, inner])
				. is_true()
			)
			if _ring().puff_style(slot) == HitFx.Style.FLASH:
				spots[spot] = true
	assert_int(spots.size()).override_failure_message("the hash moves the spot").is_greater(3)


func test_a_flash_lives_hit_flash_ms_and_a_chip_hit_chip_ms_of_match_time() -> void:
	_hit_at(_impact(1, 1))
	var chips: int = IMPACT_CHIPS[0]
	_frame(START, 0.0)
	assert_int(_ring().quad_count()).is_equal(1 + chips)
	_frame(START, 0.8)  # 53 ms: the flash is alive.
	assert_int(_ring().quad_count()).is_equal(1 + chips)
	_frame(START + 1, 0.0)  # 67 ms.
	assert_int(_ring().quad_count()).is_equal(chips)
	for index: int in _ring().quad_count():
		assert_int(_ring().quad_kind(index)).is_equal(HitFx.K_CHIP)
	_frame(START + 5, 0.0)  # 333 ms.
	assert_int(_ring().quad_count()).is_equal(chips)
	_frame(START + 6, 0.0)  # 400 ms.
	assert_int(_ring().quad_count()).is_equal(0)


func test_the_chips_fly_out_in_at_least_two_directions() -> void:
	_hit_at(_impact(6, 1))  # Five chips.
	_frame(START, 0.0)
	var from: Array[Vector2] = []
	for index: int in _ring().quad_count():
		if _ring().quad_kind(index) == HitFx.K_CHIP:
			from.append(_ring().quad_rect(index).position)
	assert_int(from.size()).is_equal(5)
	_frame(START + 3, 0.0)  # 200 ms: the flash is gone, the chips are on their way.
	assert_int(_ring().quad_count()).is_equal(5)
	var ways: Dictionary = {}
	var ends: Dictionary = {}  # Five chips, five different ways.
	for index: int in 5:
		var moved: Vector2 = _ring().quad_rect(index).position - from[index]
		assert_float(moved.y).is_less(0.0)  # Up.
		ways[signf(moved.x)] = true
		ends[moved] = true
	assert_int(ways.size()).is_greater_equal(2)
	assert_int(ends.size()).is_equal(5)


func test_the_ring_holds_sixteen_and_overwrites_its_oldest() -> void:
	_ring().clear()
	var events: PackedInt32Array = PackedInt32Array()
	for id: int in [1, 2, 3, 4]:  # Four hits of at least four puffs each: 16 or more.
		events.append_array(_impact(id, 1))
	Rig.deliver(_runner, events, START)
	assert_int(_ring().count()).is_equal(DATA.hit_slots)
	Rig.deliver(_runner, _impact(5, 1), START + 1)  # START's flashes (60 ms) are gone
	assert_int(_ring().count()).is_equal(DATA.hit_slots)
	assert_float(_ring().puff_born(DATA.hit_slots - 1)).is_equal(LifeClock.tick_ms(START + 1))
	assert_float(_ring().puff_born(0)).is_equal(LifeClock.tick_ms(START))


func test_a_new_match_empties_the_ring() -> void:
	_hit_at(_impact(1, 1))
	assert_int(_ring().count()).is_greater(0)
	_runner.snapshot.match_serial += 1
	Rig.deliver(_runner, PackedInt32Array(), START + 1)
	assert_int(_ring().count()).is_equal(0)


func test_reduced_keeps_the_flash_and_drops_the_chips() -> void:
	_life.reduced = true
	_hit_at(_impact(1, 1))
	assert_int(_of(HitFx.Style.FLASH)).is_equal(1)
	assert_int(_of(HitFx.Style.CHIP)).is_equal(0)
	_frame(START, 0.0)
	assert_int(_ring().quad_count()).is_equal(1)


func test_a_hit_moves_no_camera() -> void:
	var before: Vector2 = _camera.position
	_hit_at(_impact(1, 1))
	_frame(START, 0.5)
	assert_vector(_camera.position).is_equal(before)


func test_the_flash_and_the_chips_are_drawn_in_the_last_pass() -> void:
	_hit_at(_impact(1, 1))
	Rig.at(_runner, START, 0.0)
	_air.set_process(true)  # The engine's own frame plans and draws.
	await await_idle_frame()
	_air.set_process(false)
	var quads: int = _ring().quad_count()
	assert_int(quads).is_greater(1)
	assert_int(_ring().drawn(FxRing.FLAME)).is_equal(quads)
	assert_int(_ring().drawn(FxRing.GLOW)).is_equal(0)
	assert_int(_ring().drawn(FxRing.CLOUD)).is_equal(0)
