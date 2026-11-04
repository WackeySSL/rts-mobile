extends "res://tests/view/support/damage_fx_suite.gd"
## The hit feedback of buildings (plan P166, ADR 0029 section 7): which records are a hit, what it
## draws (a flash in the middle of the frame box, a pinned number of chips), the hits that draw
## nothing, the ring of 16 and `reduced`.
## Fixture: support/damage_fx_suite.gd (Barracks 1 to 8 on a crafted sheet, all shown).

const Effects: GDScript = preload("res://tests/view/support/effects_rig.gd")
const SPAWNS: Array = [
	[1, 4, 4], [1, 12, 4], [1, 20, 4], [1, 4, 12], [1, 12, 12], [1, 20, 12], [1, 4, 20], [1, 12, 20]
]
const SHELL: int = 0  ## The weapon table of the test: a shell weapon, then a hitscan one.
const RIFLE: int = 1
const SALT_CHIP: int = 0x73000000
## Chips of a hit for ids 1 to 8 (`3 + LifeClock.pick(id, SALT_CHIP, 3)`), pinned: the same on
## every device and run. A shell's hit id is its projectile id; a rifle's is
## `LifeClock.mix(shooter id, tick)`, here for shooter 1 to 8 at tick START.
const IMPACT_CHIPS: Array[int] = [4, 4, 4, 4, 4, 5, 3, 3]
const SHOT_CHIPS: Array[int] = [3, 3, 5, 4, 3, 5, 4, 3]


func before_test() -> void:
	_open(SPAWNS)
	var snap: MatchSnapshot = _runner.snapshot
	snap.weapon_ids.clear()
	snap.weapon_ids.append(&"tank_cannon")
	snap.weapon_ids.append(&"rifle")
	snap.weapon_projectile_speed = PackedInt32Array([20000, 0])


func _ring() -> FxRing:
	return _air.hits().ring


## An IMPACT of projectile `projectile` on building `target`, at its position.
func _impact(projectile: int, target: int, weapon: int = SHELL) -> PackedInt32Array:
	return Effects.impact(Rig.position_of(_runner, target), weapon, projectile, target)


## A SHOT of `shooter` at building `target`, with the target's position at +6/+7.
func _shot(shooter: int, target: int, weapon: int = RIFLE) -> PackedInt32Array:
	var at: Vector2i = Rig.position_of(_runner, target)
	return Effects.shot(at + Vector2i(3000, 0), at, weapon, shooter, target)


func _hit_at(events: PackedInt32Array, tick: int = START) -> void:
	_ring().clear()
	Rig.deliver(_runner, events, tick)


## Puffs of the ring of style `style` (a `HitFx.Style` value, chips from `HitFx.Style.CHIP`).
func _of(style: int) -> int:
	var found: int = 0
	for slot: int in _ring().count():
		var puff: int = _ring().puff_style(slot)
		found += 1 if (puff == style or (style == HitFx.Style.CHIP and puff >= style)) else 0
	return found


func test_the_numbers_are_the_data_files() -> void:
	assert_int(DATA.hit_slots).is_equal(16)
	assert_int(DATA.hit_flash_ms).is_equal(60)
	assert_int(DATA.hit_flash_box_milli).is_equal(500)
	assert_array(DATA.hit_chips).is_equal(PackedInt32Array([3, 5]))
	assert_int(DATA.hit_chip_ms).is_equal(350)
	assert_int(DATA.hit_chip_fly_px.size()).is_between(1, HitFx.MAX_DIRECTIONS)


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
	_hit_at(Effects.impact(Vector2i(5000, 5000), SHELL, 5, 977))  # A target that is no building.
	assert_int(_ring().count()).is_equal(0)
	_hit_at(Effects.shot(Vector2i(5000, 5000), Vector2i(6000, 5000), RIFLE, 1, 977))  # Not shown.
	assert_int(_ring().count()).is_equal(0)
	_hit_at(_impact(5, 2, 7))  # A weapon the table lacks counts as a shell.
	assert_int(_ring().count()).is_greater(0)


func test_a_building_that_is_gone_has_no_row_and_a_live_one_has_its_row() -> void:
	assert_int(_buildings.row_of(977)).is_equal(-1)
	assert_int(_buildings.row_of(0)).is_equal(-1)
	for id: int in [1, 4, 8]:
		assert_int(_buildings.row_of(id)).is_equal(_runner.snapshot.index_of(id))


func test_an_impact_on_a_hidden_enemy_building_draws_nothing() -> void:
	_open([[1, 4, 4], [2, 20, 20]], [QUIET, 0, 0, 0, 0], false)
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


func test_the_chips_fly_out_along_more_than_one_way() -> void:
	_hit_at(_impact(6, 1))  # Five chips.
	var styles: Dictionary = {}
	for slot: int in _ring().count():
		styles[_ring().puff_style(slot)] = true
	assert_int(styles.size()).is_greater(2)  # The flash and at least two chip directions.


func test_the_ring_holds_sixteen_and_overwrites_its_oldest() -> void:
	_ring().clear()
	for step: int in 8:  # 8 hits, at least 4 puffs each, within 120 ms: nothing has lived out.
		Rig.deliver(_runner, _impact(step + 1, 1), START + step)
	assert_int(_ring().count()).is_equal(DATA.hit_slots)
	var oldest: float = _ring().puff_born(0)
	assert_float(oldest).is_greater(LifeClock.tick_ms(START))
	assert_float(_ring().puff_born(DATA.hit_slots - 1)).is_equal(LifeClock.tick_ms(START + 7))


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
	_frame(START, 0.0)
	assert_int(_ring().planned(FxRing.FLAME)).is_equal(_ring().quad_count())
	assert_int(_ring().planned(FxRing.GLOW)).is_equal(0)
