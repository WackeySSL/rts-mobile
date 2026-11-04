extends "res://tests/view/support/damage_fx_suite.gd"
## The crater sources of `AirFx` (plan P148, ADR 0029 sections 6 and 9; the collapse of P165 adds
## them with `add_crater`): thin smoke for `crater_smoke_ms`, embers and a faint glow for
## `crater_ember_ms` from the damage points at ground height, at most `crater_sources` at once and
## the oldest out first, and only while the footprint is seen (an own building's always).
## Fixture: support/damage_fx_suite.gd (crafted here: sources added by hand, no building burns).

const FOOT: Rect2i = Rect2i(3, 3, 2, 2)
const SMOKE_TICKS: int = 120  ## 8000 ms.
const EMBER_TICKS: int = 225  ## 15000 ms.


func before_test() -> void:
	_open([[1, 4, 4], [2, 20, 20]], [0, 0, 0, 0, 0], false)
	_camera.position = _centre(1)
	var tiles: Array[Vector2i] = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)
	_frame(START, 0.0)  # The layer follows this match before a source is added.


func _crater(id: int, offsets: PackedVector2Array, owner: int = 1, tick: int = START) -> Vector2:
	var centre: Vector2 = _centre(1) + Vector2(float(id) * 4.0, 0.0)
	_air.add_crater(id, centre, offsets, FOOT, owner, tick)
	return centre


## Runs ticks `from` to `to` and returns the newest birth tick of each style (a key of `S`) seen.
func _births(from: int, to: int) -> Dictionary:
	var newest: Dictionary = {}
	for tick: int in range(from, to):
		_run(tick, tick + 1)
		for puff: Array in _puffs():
			for key: String in S:
				if puff[0] == S[key]:
					newest[key] = maxi(newest.get(key, -1), roundi(puff[2] / TICK_MS))
	return newest


func test_a_crater_smokes_for_8_seconds_and_glows_with_embers_for_15() -> void:
	var one: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0)])
	_crater(1, one)
	var newest: Dictionary = _births(START, START + EMBER_TICKS + 30)
	assert_int(newest["crater"]).is_greater_equal(START + SMOKE_TICKS - 15)
	assert_int(newest["crater"]).is_less(START + SMOKE_TICKS)
	assert_int(newest["ember"]).is_greater_equal(START + EMBER_TICKS - 14)
	assert_int(newest["ember"]).is_less(START + EMBER_TICKS)
	# The glow is born again each time the last one ends, up to the embers' end.
	assert_int(newest["glow_faint"]).is_greater_equal(START + EMBER_TICKS - 14)
	assert_int(newest["glow_faint"]).is_less(START + EMBER_TICKS)
	assert_int(_air.damage().crater_count()).is_equal(0)  # Over: the slot is free.


func test_a_crater_point_is_the_sheets_x_on_the_footprint_centre_line_and_nothing_higher() -> void:
	# A sheet's point is a screen offset from the footprint centre (art px, a Vector2, no height or
	# model z), so the ground point keeps x and takes y 0; the ambient `smoke` is no damage point.
	assert_int(typeof(_def.emitter_points)).is_equal(TYPE_PACKED_VECTOR2_ARRAY)
	var found: PackedVector2Array = DamageFx.ground_points(_def)
	assert_int(found.size()).is_equal(4)
	for index: int in 4:
		assert_vector(found[index]).is_equal(
			Vector2(POINT_AT[index + 1].x * WorldSort.ART_SCALE, 0.0)
		)
	var lone: IsoSheetDef = IsoSheetDef.new()
	assert_int(DamageFx.ground_points(lone).size()).is_equal(0)  # None: the centre is used.


func test_the_puffs_rise_from_ground_height_at_the_points_x_or_from_the_centre_without_points(
) -> void:
	var two: PackedVector2Array = PackedVector2Array([Vector2(-30.0, 0.0), Vector2(25.0, 0.0)])
	var centre: Vector2 = _crater(1, two)
	var plain: Vector2 = _crater(2, PackedVector2Array())
	_run(START, START + 60)
	var spots: Array[Vector2] = [centre + two[0], centre + two[1], plain]
	for puff: Array in _puffs():
		assert_bool(spots.has(puff[1])).is_true()  # y is the centre line: no height.
	assert_int(_styles_at(plain).size()).is_greater(0)
	assert_int(_styles_at(centre + two[1]).size()).is_greater(0)
	assert_int(_styles_at(centre + two[0]).size()).is_greater(0)


func test_at_most_16_sources_live_and_the_oldest_ends_first() -> void:
	var first: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var centres: Array[Vector2] = []
	for id: int in 20:
		centres.append(_crater(id + 1, first, 1, START))
	assert_int(_air.damage().crater_count()).is_equal(16)
	_run(START, START + 30)
	for id: int in 4:  # The first four were pushed out.
		assert_int(_styles_at(centres[id]).size()).override_failure_message("%d" % id).is_equal(0)
	for id: int in range(4, 20):
		(
			assert_bool(_styles_at(centres[id]).size() > 0 or _air.damage().ring.count() >= 80)
			. is_true()
		)


func test_only_while_its_footprint_is_seen_and_an_own_building_always() -> void:
	var one: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var enemy: Vector2 = _crater(1, one, 2)
	var own: Vector2 = _crater(2, one, 1)
	Buildings.see(_runner.snapshot, 1, [Vector2i(10, 10)])  # The footprint at (3, 3) is dark.
	_run(START, START + 30)
	assert_int(_styles_at(enemy).size()).is_equal(0)
	assert_int(_styles_at(own).size()).is_greater(0)
	Buildings.see(_runner.snapshot, 1, [Vector2i(4, 4)])  # A cell of it is seen again.
	_run(START + 30, START + 60)
	assert_int(_styles_at(enemy).size()).is_greater(0)


func test_a_source_born_in_the_future_waits_and_one_outside_the_view_puffs_nothing() -> void:
	var one: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	_crater(1, one, 1, START + 30)
	_run(START, START + 30)
	assert_int(_air.damage().ring.count()).is_equal(0)
	_run(START + 30, START + 60)
	assert_int(_air.damage().ring.count()).is_greater(0)
	_air.damage().clear()
	_air.add_crater(2, _centre(1) + Vector2(5000.0, 0.0), one, FOOT, 1, START + 60)
	_air.damage().clear()
	_run(START + 60, START + 62)
	_run(START + 62, START + 120)
	for puff: Array in _puffs():
		assert_float((puff[1] as Vector2).x).is_less(1000.0)  # Only source 1's.


func test_reduced_drops_the_crater_smoke_and_the_embers_and_keeps_a_faint_glow() -> void:
	var one: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	_crater(1, one)
	_life.reduced = true
	_run(START, START + 60)
	assert_int(_count("crater")).is_equal(0)
	assert_int(_count("ember")).is_equal(0)
	assert_int(_count("glow_faint")).is_greater(0)
	_life.reduced = false
	_run(START + 60, START + 90)
	assert_int(_count("crater")).is_greater(0)
	assert_int(_count("ember")).is_greater(0)


func test_a_new_match_ends_every_source() -> void:
	_crater(1, PackedVector2Array([Vector2.ZERO]))
	_run(START, START + 20)
	assert_int(_air.damage().ring.count()).is_greater(0)
	_runner.snapshot.match_serial += 1
	_frame(START + 20, 0.0)
	assert_int(_air.damage().ring.count()).is_equal(0)
	assert_int(_air.damage().crater_count()).is_equal(0)
