extends "res://tests/view/support/damage_fx_suite.gd"
## What becomes of a building by the flag of its DIED (plan P272, ADR 0037 section 3):
## `BuildingCollapse.died_flag` reads it, 1 (a cancelled site) plays nothing, 3 (a sale) packs up
## (the sink and the dust, with no flash, no fire, no crater and no crater smoke) and 0 plays all of
## it. Fixture: support/damage_fx_suite.gd, Barracks 1 and 2 of player 1 and a spare of player 2.

const SPAWNS: Array = [[1, 4, 4], [1, 8, 4], [1, 12, 4], [2, 20, 20]]  # Id 3 keeps the match on.


func before_test() -> void:
	_open(SPAWNS)
	_runner.run_ticks(1)
	_buildings.decals.crater_texture = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)


func _ring() -> FxRing:
	return _air.collapses().ring


## Takes building `id` out of the world with `pending` as its `build_left` (what REMOVE turns into
## the DIED flag), in one real tick.
func _remove(id: int, pending: int) -> void:
	var row: int = _runner.world.index_of(id)
	_runner.world.build_left[row] = pending
	_runner.world.hp[row] = 0
	_runner.run_ticks(1)
	_buildings._process(0.0)


## Every puff the collapse ring held over `ticks` ticks, once each: key -> style.
func _seen(ticks: int) -> Dictionary:
	var seen: Dictionary = {}
	_note(seen)
	for tick: int in ticks:
		_runner.run_ticks(1)
		_note(seen)
	return seen


func _note(seen: Dictionary) -> void:
	for index: int in _ring().count():
		var key: String = (
			"%f %d %s"
			% [_ring().puff_born(index), _ring().puff_style(index), _ring().puff_at(index)]
		)
		seen[key] = _ring().puff_style(index)


## The styles of the puffs of `seen`, with how many of each.
func _styles(seen: Dictionary) -> Dictionary:
	var styles: Dictionary = {}
	for key: Variant in seen:
		styles[seen[key]] = styles.get(seen[key], 0) + 1
	return styles


func test_the_flag_of_a_died_is_read_from_the_events() -> void:
	_remove(1, Production.SOLD)
	assert_int(BuildingCollapse.died_flag(_runner.snapshot, 1)).is_equal(Removal.FLAG_SOLD)
	assert_int(BuildingCollapse.died_flag(_runner.snapshot, 2)).is_equal(0)  # No DIED for it.
	_remove(2, Production.CANCELLED)
	assert_int(BuildingCollapse.died_flag(_runner.snapshot, 2)).is_equal(Removal.FLAG_CANCELLED)
	assert_int(Removal.FLAG_SOLD).is_equal(3)  # The values the sim writes, restated.
	assert_int(Removal.FLAG_CANCELLED).is_equal(1)


func test_a_sale_packs_up_with_dust_and_no_flash_no_fire_and_no_crater() -> void:
	_remove(1, Production.SOLD)
	assert_int(_buildings.collapse().count()).is_equal(1)  # The sink runs.
	assert_int(_buildings.decals.crater_count()).is_equal(0)
	var styles: Dictionary = _styles(_seen(16))
	assert_bool(styles.has(CollapseFx.Style.DUST)).is_true()
	assert_bool(styles.has(CollapseFx.Style.FLASH)).is_false()
	assert_bool(styles.has(CollapseFx.Style.FIRE)).is_false()
	assert_int(_buildings.decals.crater_count()).is_equal(0)  # And none by the end.


## The control: the same building, destroyed (flag 0), flashes, burns and leaves its crater.
func test_a_destroyed_building_flashes_burns_and_leaves_a_crater() -> void:
	_remove(1, 0)
	assert_int(_buildings.decals.crater_count()).is_equal(1)
	var styles: Dictionary = _styles(_seen(16))
	assert_bool(styles.has(CollapseFx.Style.FLASH)).is_true()
	assert_bool(styles.has(CollapseFx.Style.FIRE)).is_true()
	assert_bool(styles.has(CollapseFx.Style.DUST)).is_true()


## A sale and a destruction in the same tick: each keeps its own look.
func test_a_sale_and_a_destruction_in_one_tick_each_keep_their_look() -> void:
	var sold: int = _runner.world.index_of(1)
	_runner.world.build_left[sold] = Production.SOLD
	_runner.world.hp[sold] = 0
	_runner.world.hp[_runner.world.index_of(2)] = 0
	_runner.run_ticks(1)
	_buildings._process(0.0)
	assert_int(_buildings.collapse().count()).is_equal(2)
	assert_int(_buildings.decals.crater_count()).is_equal(1)  # Only the destroyed one's.
	var seen: Dictionary = _seen(16)
	var styles: Dictionary = _styles(seen)
	assert_int(styles.get(CollapseFx.Style.FLASH, 0)).is_equal(1)  # Not the sale's.
	assert_int(styles.get(CollapseFx.Style.FIRE, 0)).is_greater_equal(2)
	assert_int(styles.get(CollapseFx.Style.DUST, 0)).is_greater(0)


## Four sales in one tick share the ring of 40 without overrunning it: dust only.
func test_four_sales_in_one_tick_stay_inside_the_ring_with_dust_only() -> void:
	_open([[1, 4, 4], [1, 8, 4], [1, 12, 4], [1, 16, 4], [1, 20, 4], [2, 24, 24]])
	_runner.run_ticks(1)
	for id: int in [1, 2, 3, 4]:
		var row: int = _runner.world.index_of(id)
		_runner.world.build_left[row] = Production.SOLD
		_runner.world.hp[row] = 0
	_runner.run_ticks(1)
	_buildings._process(0.0)
	var seen: Dictionary = _seen(16)
	assert_int(seen.size()).is_less_equal(40)
	var styles: Dictionary = _styles(seen)
	assert_int(styles.get(CollapseFx.Style.DUST, 0)).is_equal(4 * _life.collapse_dust_puffs)
	for style: int in styles:
		assert_int(style).is_equal(CollapseFx.Style.DUST)  # No flash, fire or debris.


## The quiet mark goes with the collapse: the slot a sale used plays a later destruction in full.
func test_a_slot_that_played_a_sale_gives_the_next_destruction_its_flash_and_fire() -> void:
	_remove(1, Production.SOLD)
	_seen(20)  # Past collapse_end_ms: the slot is free again.
	_remove(2, 0)
	var styles: Dictionary = _styles(_seen(16))
	assert_int(styles.get(CollapseFx.Style.FLASH, 0)).is_equal(1)
	assert_int(styles.get(CollapseFx.Style.FIRE, 0)).is_greater_equal(2)
