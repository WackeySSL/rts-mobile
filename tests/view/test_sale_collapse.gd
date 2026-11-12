extends "res://tests/view/support/damage_fx_suite.gd"
## What becomes of a building by the flag of its DIED (plan P272, ADR 0037 section 3):
## `BuildingCollapse.died_flag` reads it, 1 (a cancelled site) plays nothing, 3 (a sale) packs up
## (the sink and the dust, with no flash, no fire, no crater and no crater smoke) and 0 plays all of
## it. Fixture: support/damage_fx_suite.gd, Barracks 1 and 2 of player 1 and a spare of player 2.

const SPAWNS: Array = [[1, 4, 4], [1, 8, 4], [2, 20, 20]]


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


## The styles of every puff the collapse ring held over `ticks` ticks.
func _styles(ticks: int) -> Dictionary:
	var styles: Dictionary = {}
	for index: int in _ring().count():
		styles[_ring().puff_style(index)] = true
	for tick: int in ticks:
		_runner.run_ticks(1)
		for index: int in _ring().count():
			styles[_ring().puff_style(index)] = true
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
	var styles: Dictionary = _styles(16)
	assert_bool(styles.has(CollapseFx.Style.DUST)).is_true()
	assert_bool(styles.has(CollapseFx.Style.FLASH)).is_false()
	assert_bool(styles.has(CollapseFx.Style.FIRE)).is_false()
	assert_int(_buildings.decals.crater_count()).is_equal(0)  # And none by the end.


## The control: the same building, destroyed (flag 0), flashes, burns and leaves its crater.
func test_a_destroyed_building_flashes_burns_and_leaves_a_crater() -> void:
	_remove(1, 0)
	assert_int(_buildings.decals.crater_count()).is_equal(1)
	var styles: Dictionary = _styles(16)
	assert_bool(styles.has(CollapseFx.Style.FLASH)).is_true()
	assert_bool(styles.has(CollapseFx.Style.FIRE)).is_true()
	assert_bool(styles.has(CollapseFx.Style.DUST)).is_true()


func test_a_cancelled_site_plays_nothing_and_leaves_no_crater() -> void:
	_remove(1, Production.CANCELLED)
	assert_int(_buildings.collapse().count()).is_equal(0)
	assert_int(_buildings.decals.crater_count()).is_equal(0)
	assert_int(_styles(16).size()).is_equal(0)


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
	var styles: Dictionary = _styles(16)
	assert_int(_count_of(styles, CollapseFx.Style.FLASH)).is_equal(1)


func _count_of(styles: Dictionary, style: int) -> int:
	return 1 if styles.has(style) else 0
