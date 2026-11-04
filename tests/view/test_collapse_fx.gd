extends "res://tests/view/support/damage_fx_suite.gd"
## The particles of a building's collapse and the crater's smoke (plan P165, ADR 0029 sections 6, 8
## and 9): the flash and fire at the DIED, the dust inside 250 to 900 ms, the debris, the split of
## the ring between the collapses that run, the view gate, `reduced`, and determinism. (The crater
## sources are test_crater_source.gd's.) Fixture: support/damage_fx_suite.gd.

const ROW: Array = [
	[1, 4, 4], [1, 6, 4], [1, 8, 4], [1, 10, 4], [1, 12, 4], [1, 14, 4], [1, 16, 4], [1, 18, 4]
]
const SPARES: Array = [[2, 24, 24], [1, 2, 20]]
const LIFE_MS: Dictionary[int, float] = {
	CollapseFx.Style.FLASH: 250.0, CollapseFx.Style.FIRE: 250.0, CollapseFx.Style.DUST: 450.0
}


func before_test() -> void:
	_start([[1, 4, 4], [2, 24, 24], [1, 2, 20]], true)


## Opens the fixture and runs one tick, so the rings follow the match before anything dies.
func _start(spawns: Array, reveal: bool) -> void:
	_open(spawns, [0, 0, 0, 0, 0], reveal)
	_runner.run_ticks(1)


func _ring() -> FxRing:
	return _air.collapses().ring


## Kills `ids` in one real tick and returns the tick.
func _kill(ids: Array) -> int:
	for id: int in ids:
		_runner.world.hp[_runner.world.index_of(id)] = 0
	_runner.run_ticks(1)
	return _runner.snapshot.tick


## Runs `ticks` real ticks and returns every puff the collapse ring held at any of them, once each
## (keyed by birth, style and spot): `{key: [style, born ms]}`.
func _watch(ticks: int) -> Dictionary:
	var seen: Dictionary = {}
	for tick: int in ticks:
		_runner.run_ticks(1)
		for index: int in _ring().count():
			var born: float = _ring().puff_born(index)
			var style: int = _ring().puff_style(index)
			seen["%f %d %s" % [born, style, _ring().puff_at(index)]] = [style, born]
	return seen


func _of(seen: Dictionary, style: int) -> Array:
	var found: Array = []
	for key: Variant in seen:
		if seen[key][0] == style:
			found.append(seen[key][1])
	return found


func test_the_flash_and_fire_are_born_at_the_died_and_the_dust_inside_250_to_900() -> void:
	var died: int = _kill([1])
	var start: float = LifeClock.tick_ms(died)
	var seen: Dictionary = {}
	for index: int in _ring().count():  # The DIED tick's own births.
		seen[index] = [_ring().puff_style(index), _ring().puff_born(index)]
	assert_int(_of(seen, CollapseFx.Style.FLASH).size()).is_equal(1)
	var fires: int = _of(seen, CollapseFx.Style.FIRE).size()
	assert_bool(fires >= 2 and fires <= 3).is_true()
	for born: float in _of(seen, CollapseFx.Style.FLASH) + _of(seen, CollapseFx.Style.FIRE):
		assert_float(born).is_equal(start)
	seen = _watch(16)
	var dust: Array = _of(seen, CollapseFx.Style.DUST)
	assert_int(dust.size()).is_equal(8)
	for born: float in dust:
		assert_float(born - start).is_greater_equal(250.0)
		assert_float(born - start + float(_life.collapse_dust_life_ms)).is_less_equal(900.0)
	var debris: int = 0
	for key: Variant in seen:
		debris += 1 if seen[key][0] >= CollapseFx.Style.DEBRIS else 0
	assert_bool(debris >= 6 and debris <= 8).is_true()


## Opens `ROW` (ids 1 to 8) and, when `second` is set, a second row (ids 9 to 16) below it.
func _crowd(second: bool) -> void:
	var spawns: Array = ROW.duplicate()
	if second:
		for at: Array in ROW:
			spawns.append([at[0], at[1], 8])
	_start(spawns + SPARES, true)
	_camera.position = _centre(4) + Vector2(0.0, 40.0 if second else 0.0)


func test_eight_collapses_in_one_tick_get_five_dust_puffs_each_and_nothing_else() -> void:
	_crowd(false)
	_kill([1, 2, 3, 4, 5, 6, 7, 8])
	var seen: Dictionary = _watch(16)
	assert_int(_of(seen, CollapseFx.Style.DUST).size()).is_equal(40)  # 40 / 8 = 5 each.
	for key: Variant in seen:
		assert_int(seen[key][0]).is_equal(CollapseFx.Style.DUST)  # No flash, fire or debris.


func test_two_collapses_get_all_their_puffs() -> void:
	_crowd(false)
	_kill([1, 2])
	var seen: Dictionary = _watch(16)
	assert_int(_of(seen, CollapseFx.Style.DUST).size()).is_equal(16)
	assert_int(_of(seen, CollapseFx.Style.FLASH).size()).is_equal(2)


func test_four_collapses_give_the_dust_first_then_the_flash_then_one_fire() -> void:
	_crowd(false)
	_kill([1, 2, 3, 4])  # 40 / 4 = 10 each: dust 8, flash 1, fire 1.
	var seen: Dictionary = _watch(16)
	assert_int(_of(seen, CollapseFx.Style.DUST).size()).is_equal(32)
	assert_int(_of(seen, CollapseFx.Style.FLASH).size()).is_equal(4)
	assert_int(_of(seen, CollapseFx.Style.FIRE).size()).is_equal(4)
	assert_int(seen.size()).is_equal(40)  # No debris.


func test_a_second_wave_shares_the_ring_without_overwriting_the_first() -> void:
	_crowd(true)
	var first: int = _kill([1, 2, 3, 4, 5, 6, 7, 8])
	var start: float = LifeClock.tick_ms(first)
	var known: Dictionary = {}  # Every puff seen: key -> [style, born].
	var wave_dust: int = 0
	for tick: int in 18:
		if tick == 0:
			_kill([9, 10, 11, 12, 13, 14, 15, 16])
		else:
			_runner.run_ticks(1)
		var now: float = LifeClock.tick_ms(_runner.snapshot.tick)
		var alive: Dictionary = {}
		for index: int in _ring().count():
			var key: String = (
				"%f %d %s"
				% [_ring().puff_born(index), _ring().puff_style(index), _ring().puff_at(index)]
			)
			alive[key] = true
			known[key] = [_ring().puff_style(index), _ring().puff_born(index)]
		for key: String in known:  # Nothing is gone while it should still live.
			var style: int = known[key][0]
			var life: float = LIFE_MS.get(style, 450.0)
			if now - known[key][1] < life:
				assert_bool(alive.has(key)).override_failure_message(key).is_true()
		assert_int(_ring().count()).is_less_equal(_life.collapse_slots)
		if tick == 9:  # 667 ms after the first wave: just before its hide at 700 ms.
			for key: String in alive:
				var born: float = known[key][1] - start
				var is_dust: bool = known[key][0] == CollapseFx.Style.DUST
				wave_dust += (
					1
					if is_dust and (is_equal_approx(born, 250.0) or is_equal_approx(born, 450.0))
					else 0
				)
	assert_int(wave_dust).is_greater_equal(8)  # Each of the first eight still has dust round it.


func test_three_collapses_in_three_ticks_ask_no_more_than_the_ring() -> void:
	_crowd(false)
	for id: int in [1, 2, 3]:
		_kill([id])
	var seen: Dictionary = _watch(16)
	assert_int(seen.size()).is_less_equal(_life.collapse_slots)
	assert_int(_of(seen, CollapseFx.Style.DUST).size()).is_greater_equal(24)  # Dust is kept first.


func test_a_collapse_off_screen_runs_but_is_born_no_puffs() -> void:
	_camera.position = _centre(1) + Vector2(20000.0, 0.0)
	_kill([1])
	assert_int(_buildings.collapse().count()).is_equal(1)  # It runs all the same,
	assert_int(_air.collapses().count()).is_equal(1)
	var seen: Dictionary = _watch(16)
	assert_int(seen.size()).is_equal(0)
	_buildings._process(0.0)  # A frame: the sequence is over at 900 ms.
	assert_int(_buildings.collapse().count()).is_equal(0)
	assert_int(_air.collapses().count()).is_equal(0)


func test_a_view_that_scrolls_in_gets_the_dust_but_not_the_flash_or_fire() -> void:
	var near: Vector2 = _camera.position
	_camera.position = near + Vector2(20000.0, 0.0)
	var died: int = _kill([1])
	for tick: int in 3:  # 200 ms: the flash and fire were due at 0 and are lost.
		_runner.run_ticks(1)
	_camera.position = near
	var seen: Dictionary = _watch(14)
	assert_int(_of(seen, CollapseFx.Style.FLASH).size()).is_equal(0)
	assert_int(_of(seen, CollapseFx.Style.FIRE).size()).is_equal(0)
	var dust: Array = _of(seen, CollapseFx.Style.DUST)
	assert_int(dust.size()).is_equal(8)
	for born: float in dust:
		assert_float(born - LifeClock.tick_ms(died)).is_greater_equal(250.0)


func test_reduced_keeps_the_flash_fire_and_dust_and_drops_the_debris() -> void:
	_life.reduced = true
	_kill([1])
	var seen: Dictionary = _watch(16)
	assert_int(_of(seen, CollapseFx.Style.FLASH).size()).is_equal(1)
	assert_int(_of(seen, CollapseFx.Style.FIRE).size()).is_greater_equal(2)
	assert_int(_of(seen, CollapseFx.Style.DUST).size()).is_equal(8)
	for key: Variant in seen:
		assert_int(seen[key][0]).is_less(CollapseFx.Style.DEBRIS)


func test_reduced_turned_on_in_the_middle_of_a_collapse_drops_the_debris_still_to_come() -> void:
	_kill([1])
	_runner.run_ticks(1)  # About 67 ms in; the debris is born at 250 ms.
	_life.reduced = true
	var seen: Dictionary = _watch(16)
	for key: Variant in seen:
		assert_int(seen[key][0]).is_less(CollapseFx.Style.DEBRIS)
	assert_int(_of(seen, CollapseFx.Style.DUST).size()).is_equal(8)


## The puffs of a fresh run of one collapse over 16 ticks: [style, born, spot] per tick.
func _log() -> Array:
	_start([[1, 4, 4], [2, 24, 24], [1, 2, 20]], true)
	_kill([1])
	var log: Array = []
	for tick: int in 16:
		_runner.run_ticks(1)
		for index: int in _ring().count():
			log.append(
				[_ring().puff_style(index), _ring().puff_born(index), _ring().puff_at(index)]
			)
		log.append(tick)
	return log


func test_two_runs_give_the_same_puffs() -> void:
	var first: Array = _log()
	var second: Array = _log()
	assert_int(first.size()).is_greater(30)
	assert_array(first).is_equal(second)


func test_planning_twice_at_a_frozen_clock_gives_the_same_quads() -> void:
	var died: int = _kill([1])
	for tick: int in 8:
		_runner.run_ticks(1)
	Rig.at(_runner, died + 8, 0.5)  # A pause: the clock stays here.
	_air._process(0.0)
	var count: int = _ring().quad_count()
	assert_int(count).is_greater(0)
	var rects: Array[Rect2] = []
	var alphas: Array[float] = []
	for index: int in count:
		rects.append(_ring().quad_rect(index))
		alphas.append(_ring().quad_alpha(index))
	_air._process(0.0)
	assert_int(_ring().quad_count()).is_equal(count)
	for index: int in count:
		assert_that(_ring().quad_rect(index)).is_equal(rects[index])
		assert_float(_ring().quad_alpha(index)).is_equal(alphas[index])


## Plays a first wave of `first` collapses, `gap` ticks later one more, and checks that no puff is
## gone while it should still live.
func _late_one(first: Array, gap: int) -> void:
	_crowd(true)
	_kill(first)
	var known: Dictionary = {}
	for tick: int in 20:
		if tick == gap:
			_kill([9])
		else:
			_runner.run_ticks(1)
		var now: float = LifeClock.tick_ms(_runner.snapshot.tick)
		var alive: Dictionary = {}
		for index: int in _ring().count():
			var key: String = (
				"%f %d %s"
				% [_ring().puff_born(index), _ring().puff_style(index), _ring().puff_at(index)]
			)
			alive[key] = true
			known[key] = [_ring().puff_style(index), _ring().puff_born(index)]
		for key: String in known:
			var life: float = LIFE_MS.get(known[key][0], 450.0)
			if now - known[key][1] < life:
				assert_bool(alive.has(key)).override_failure_message(key).is_true()


func test_a_late_collapse_takes_only_what_the_dust_already_born_leaves() -> void:
	for gap: int in range(3, 10):  # Five at once, building 9 some 200 to 600 ms later.
		_late_one([1, 2, 3, 4, 5], gap)


func test_a_late_collapse_after_eight_loses_no_live_puff() -> void:
	_late_one([1, 2, 3, 4, 5, 6, 7, 8], 5)
