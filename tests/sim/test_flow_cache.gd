extends GdUnitTestSuite
## FlowCache (ADR 0008 section 3, plan P30b) on an 8 x 8 map (64 cells, a padded field of 100
## entries) with 3 move classes. Every number is a literal.

const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED
const UNREACHED: int = FlowField.UNREACHED
const BIG: int = 100000
const CELLS: int = 64


## The World's `move_cost`: 10 for every class, 0 on the `rock` cells.
func _costs(rock: Array[int] = []) -> PackedByteArray:
	var costs: PackedByteArray = PackedByteArray()
	costs.resize(3 * CELLS)
	costs.fill(10)
	for cell: int in rock:
		for move_class: int in 3:
			costs[move_class * CELLS + cell] = 0
	return costs


func _cache(slots: int) -> FlowCache:
	var cache: FlowCache = FlowCache.new()
	cache.configure(8, 8, 3, slots)
	return cache


## The served cost of a lone FlowField for the key.
func _lone(goal: int, move_class: int, costs: PackedByteArray) -> PackedInt32Array:
	var lone: FlowField = FlowField.new()
	lone.begin(goal, move_class, costs, 8, 8)
	lone.advance(BIG)
	return lone.cost


## Every Packed array of the cache, then of each slot's field.
func _arrays(cache: FlowCache) -> Array:
	var arrays: Array = []
	for array_name: StringName in FlowCache.STATE_ARRAYS:
		arrays.append(cache.get(array_name))
	for slot: int in cache.fields.size():
		for array_name: StringName in FlowField.STATE_ARRAYS:
			arrays.append(cache.field(slot).get(array_name))
	return arrays


func test_the_same_key_shares_a_slot_and_any_other_key_takes_its_own() -> void:
	var cache: FlowCache = _cache(5)
	assert_int(cache.acquire(5, FOOT, 0, 1)).is_equal(0)
	assert_int(cache.acquire(5, FOOT, 0, 2)).is_equal(0)
	# Another class, goal and map version are each another key.
	assert_int(cache.acquire(5, TRACKED, 0, 3)).is_equal(1)
	assert_int(cache.acquire(6, FOOT, 0, 4)).is_equal(2)
	assert_int(cache.acquire(5, FOOT, 1, 5)).is_equal(3)
	assert_int(cache.acquire(5, TRACKED, 0, 6)).is_equal(1)
	assert_int(cache.acquire(5, FOOT, 1, 7)).is_equal(3)
	assert_array(cache.last_used).is_equal([2, 6, 4, 7, 0])
	# A goal off the map and a class that is none of the three give -1 and take no slot.
	for key: Vector2i in [Vector2i(-1, 0), Vector2i(CELLS, 0), Vector2i(5, -1), Vector2i(5, 3)]:
		assert_int(cache.acquire(key.x, key.y, 0, 8)).is_equal(-1)
	assert_int(cache.acquire(CELLS - 1, FOOT, 0, 8)).is_equal(4)


func test_recount_derives_every_slots_references_from_the_field_column() -> void:
	var cache: FlowCache = _cache(4)
	var column: PackedInt32Array = [0, 2, -1, 2, 4, 2, -5, 0, 3]
	cache.recount(column, 9)
	assert_array(cache.ref_count).is_equal([2, 0, 3, 1])
	assert_int(cache.refs(2) + cache.refs(-1) + cache.refs(4) + cache.refs(99)).is_equal(3)
	# Only the first `count` rows count, and every recount starts from zero.
	cache.recount(column, 2)
	assert_array(cache.ref_count).is_equal([1, 0, 1, 0])
	cache.recount(column, 100)
	assert_array(cache.ref_count).is_equal([2, 0, 3, 1])
	cache.recount(column, 0)
	assert_array(cache.ref_count).is_equal([0, 0, 0, 0])


## Free slots first, then the oldest unreferenced slot (ties to the lower), never a referenced
## one; a full cache gives -1 but still shares a key, and a share refreshes the tick. An acquire()
## counts as a reference until the next recount(), so each recount below says nobody points at
## the slots handed out so far.
func test_eviction_takes_the_oldest_unreferenced_slot_and_a_full_cache_gives_minus_one() -> void:
	var cache: FlowCache = _cache(3)
	assert_int(cache.acquire(1, FOOT, 0, 5)).is_equal(0)
	assert_int(cache.acquire(2, FOOT, 0, 3)).is_equal(1)
	# Slot 2 is free, so it is taken although slot 1 is older.
	assert_int(cache.acquire(3, FOOT, 0, 3)).is_equal(2)
	cache.recount(PackedInt32Array(), 0)
	# Slots 1 and 2 are oldest (tick 3) and tie: the lower goes.
	assert_int(cache.acquire(4, FOOT, 0, 6)).is_equal(1)
	assert_int(cache.acquire(5, FOOT, 0, 6)).is_equal(2)
	# Slot 0 is used again at tick 7, so slots 1 and 2 (tick 6) tie again.
	assert_int(cache.acquire(1, FOOT, 0, 7)).is_equal(0)
	cache.recount(PackedInt32Array(), 0)
	assert_int(cache.acquire(6, FOOT, 0, 8)).is_equal(1)
	# Slot 2 (tick 6) is the oldest but referenced: slot 0 (tick 7) goes.
	cache.recount(PackedInt32Array([2]), 1)
	assert_int(cache.acquire(7, FOOT, 0, 9)).is_equal(0)
	cache.recount(PackedInt32Array([0, 1, 2]), 3)
	assert_int(cache.acquire(8, FOOT, 0, 10)).is_equal(-1)
	assert_int(cache.acquire(7, FOOT, 0, 10)).is_equal(0)
	assert_array(cache.key_goal).is_equal([7, 6, 5])


func test_advance_serves_one_field_at_a_time_in_request_order() -> void:
	var costs: PackedByteArray = _costs()
	var cache: FlowCache = _cache(3)
	for slot: int in 3:
		cache.acquire([0, 63, 7][slot], FOOT, 0, 3 - slot)
	assert_int(cache.advance(costs, 0) + cache.advance(costs, -4)).is_equal(0)
	assert_int(cache.advance(costs, 40)).is_equal(40)
	assert_array([cache.field(0).complete, cache.field(1).cell_count]).is_equal([false, 0])
	# Field 0 needs 24 more cells; the other 26 go to field 1, and field 2 has not begun.
	assert_int(cache.advance(costs, 50)).is_equal(50)
	assert_array([cache.field(0).complete, cache.field(1).complete]).is_equal([true, false])
	assert_array([cache.field(1).goal_cell, cache.field(2).cell_count]).is_equal([63, 0])
	assert_int(cache.advance(costs, BIG)).is_equal(38 + 64)
	for slot: int in 3:
		assert_array(cache.field(slot).cost).is_equal(_lone(cache.key_goal[slot], FOOT, costs))
	assert_int(cache.advance(costs, BIG)).is_equal(0)
	# The request order is the order of the acquire() calls, not the slot order: the oldest slots
	# (2, then 1) take the new keys, so slot 2 is begun first.
	cache.recount(PackedInt32Array(), 0)
	assert_int(cache.acquire(40, FOOT, 0, 10)).is_equal(2)
	assert_int(cache.acquire(50, FOOT, 0, 11)).is_equal(1)
	assert_int(cache.advance(costs, 10)).is_equal(10)
	assert_array([cache.field(2).goal_cell, cache.field(1).goal_cell]).is_equal([40, 63])


## A key the costs cannot integrate (class 2 against costs of two classes) completes at once with
## everything UNREACHED, and the same call goes on to the next field.
func test_a_key_the_costs_cannot_integrate_completes_at_once_and_does_not_stall_advance() -> void:
	var cache: FlowCache = _cache(2)
	cache.acquire(5, TRACKED, 0, 1)
	cache.acquire(7, FOOT, 0, 1)
	var two_classes: PackedByteArray = _costs().slice(0, 2 * CELLS)
	assert_int(cache.advance(two_classes, 100)).is_equal(64)
	assert_bool(cache.field(0).complete).is_true()
	assert_int(cache.field(0).cost.count(UNREACHED)).is_equal(100)
	assert_array(cache.field(1).cost).is_equal(_lone(7, FOOT, two_classes))
	assert_int(cache.advance(two_classes, 100)).is_equal(0)


## Slots 0 and 1 are unreferenced, 2 and 3 referenced. A new map version drops the first two (the
## next new key takes slot 0, not the oldest unreferenced slot 1) and re-integrates the others,
## which serve the old costs until the swap and are then shared under the new version. Slot 3 has
## not completed its first integration (10 cells in), so it starts over.
func test_invalidate_re_integrates_referenced_slots_and_drops_the_others() -> void:
	var cache: FlowCache = _cache(4)
	for slot: int in 4:
		cache.acquire([0, 63, 7, 56][slot], FOOT, 0, [9, 3, 8, 7][slot])
	cache.advance(_costs(), 3 * CELLS + 10)
	cache.recount(PackedInt32Array([2, 3]), 2)
	var old: PackedInt32Array = cache.field(2).cost.duplicate()
	var rock: PackedByteArray = _costs([3, 11, 19, 27, 35, 43, 51])
	cache.invalidate(1)
	assert_array(cache.status).is_equal([0, 0, 1, 1])
	assert_int(cache.acquire(20, FOOT, 1, 20)).is_equal(0)
	assert_int(cache.advance(rock, 5)).is_equal(5)
	assert_array(cache.field(2).cost).is_equal(old)
	cache.advance(rock, BIG)
	assert_array(cache.field(2).cost).is_equal(_lone(7, FOOT, rock))
	assert_array(cache.field(3).cost).is_equal(_lone(56, FOOT, rock))
	assert_array(cache.field(0).cost).is_equal(_lone(20, FOOT, rock))
	assert_bool(cache.field(2).cost == old).is_false()
	assert_int(cache.acquire(7, FOOT, 1, 30)).is_equal(2)
	# The same version again changes nothing.
	cache.invalidate(1)
	assert_int(cache.advance(rock, BIG)).is_equal(0)


## FlowField cannot see map_version, so a slot recycled for the same key on another version must
## not keep serving its finished costs (rock now closes the goal in).
func test_a_slot_recycled_for_the_same_key_on_another_map_version_serves_nothing() -> void:
	var cache: FlowCache = _cache(1)
	cache.acquire(0, FOOT, 0, 1)
	cache.advance(_costs(), BIG)
	cache.recount(PackedInt32Array(), 0)
	assert_int(cache.acquire(0, FOOT, 1, 2)).is_equal(0)
	assert_bool(cache.field(0).complete).is_false()
	assert_int(cache.field(0).cost.count(UNREACHED)).is_equal(100)
	assert_int(cache.field(0).best_neighbour(9)).is_equal(-1)
	var closed: PackedByteArray = _costs([1, 8, 9])
	cache.advance(closed, BIG)
	assert_array(cache.field(0).cost).is_equal(_lone(0, FOOT, closed))


## The plan's path: a slot dropped by invalidate (FREE) and re-acquired for its old key on the new
## map version must not serve the old map's finished costs.
func test_a_slot_dropped_by_invalidate_and_re_acquired_for_its_old_key_serves_nothing() -> void:
	var cache: FlowCache = _cache(2)
	cache.acquire(0, FOOT, 0, 1)
	cache.advance(_costs(), BIG)
	assert_bool(cache.field(0).complete).is_true()
	cache.recount(PackedInt32Array(), 0)
	cache.invalidate(1)
	assert_int(cache.status[0]).is_equal(FlowCache.Status.FREE)
	assert_int(cache.acquire(0, FOOT, 1, 2)).is_equal(0)
	assert_bool(cache.field(0).complete).is_false()
	assert_int(cache.field(0).cost.count(UNREACHED)).is_equal(100)
	assert_int(cache.field(0).best_neighbour(9)).is_equal(-1)
	var closed: PackedByteArray = _costs([1, 8, 9])
	cache.advance(closed, BIG)
	assert_array(cache.field(0).cost).is_equal(_lone(0, FOOT, closed))


## A slot acquire() handed out counts as referenced until the next recount() rewrites the counts
## from the `field` column, so a unit that stored it never finds another goal's field there.
func test_a_slot_handed_out_since_the_last_recount_is_never_given_to_another_key() -> void:
	var cache: FlowCache = _cache(3)
	var column: PackedInt32Array = [cache.acquire(10, FOOT, 0, 1)]
	cache.recount(column, 1)
	assert_int(cache.refs(0)).is_equal(1)
	# Slots 1 and 2 are free; a new key in the same recount gap finds none to evict.
	assert_int(cache.acquire(20, FOOT, 0, 5)).is_equal(1)
	assert_int(cache.acquire(30, FOOT, 0, 5)).is_equal(2)
	assert_int(cache.acquire(40, FOOT, 0, 5)).is_equal(-1)
	assert_array(cache.key_goal).is_equal([10, 20, 30])
	# A share counts too, and the recount starts from the column again.
	assert_int(cache.acquire(20, FOOT, 0, 6)).is_equal(1)
	assert_array(cache.ref_count).is_equal([1, 2, 1])
	cache.recount(column, 1)
	assert_array(cache.ref_count).is_equal([1, 0, 0])


## Two new keys in one recount gap and one evictable slot: the first takes it, the second gets -1
## and the first unit's slot still holds the first key.
func test_two_new_keys_in_one_recount_gap_cannot_share_the_one_evictable_slot() -> void:
	var cache: FlowCache = _cache(2)
	cache.acquire(10, FOOT, 0, 1)
	cache.acquire(20, FOOT, 0, 2)
	cache.recount(PackedInt32Array([1]), 1)
	var first: int = cache.acquire(30, FOOT, 0, 5)
	var second: int = cache.acquire(40, FOOT, 0, 5)
	assert_array([first, second]).is_equal([0, -1])
	assert_array(cache.key_goal).is_equal([30, 20])
	# The next recount sees the unit that stored `first`.
	cache.recount(PackedInt32Array([1, first]), 2)
	assert_int(cache.acquire(40, FOOT, 0, 6)).is_equal(-1)


## invalidate() reads the same counts: a slot handed out since the last recount re-integrates
## instead of being dropped under the unit that stored it.
func test_invalidate_keeps_a_slot_handed_out_since_the_last_recount() -> void:
	var cache: FlowCache = _cache(2)
	cache.acquire(10, FOOT, 0, 1)
	cache.advance(_costs(), BIG)
	cache.recount(PackedInt32Array(), 0)
	assert_int(cache.acquire(20, FOOT, 0, 2)).is_equal(1)
	cache.invalidate(1)
	assert_array(cache.status).is_equal([FlowCache.Status.FREE, FlowCache.Status.WAITING])
	assert_array([cache.key_goal[1], cache.key_version[1]]).is_equal([20, 1])


## A dropped slot whose integration was under way takes no more of advance()'s budget.
func test_a_dropped_slot_that_was_still_integrating_takes_no_more_budget() -> void:
	var costs: PackedByteArray = _costs()
	var cache: FlowCache = _cache(2)
	cache.acquire(5, FOOT, 0, 1)
	cache.acquire(7, FOOT, 0, 1)
	assert_int(cache.advance(costs, 20)).is_equal(20)
	assert_bool(cache.field(0).pending > 0).is_true()
	cache.recount(PackedInt32Array(), 0)
	cache.invalidate(1)
	assert_array(cache.status).is_equal([FlowCache.Status.FREE, FlowCache.Status.FREE])
	assert_int(cache.advance(costs, BIG)).is_equal(0)


## A re-integration takes the next request number like a new key, in slot order, whatever order
## the slots were first requested in: slot 0 was re-keyed after slot 1 here.
func test_invalidate_re_requests_referenced_slots_in_slot_order() -> void:
	var costs: PackedByteArray = _costs()
	var cache: FlowCache = _cache(2)
	cache.acquire(1, FOOT, 0, 1)
	cache.acquire(2, FOOT, 0, 2)
	cache.advance(costs, BIG)
	cache.recount(PackedInt32Array(), 0)
	assert_int(cache.acquire(3, FOOT, 0, 3)).is_equal(0)
	cache.recount(PackedInt32Array([0, 1]), 2)
	assert_array(cache.requested).is_equal([3, 2])
	cache.invalidate(1)
	assert_array(cache.requested).is_equal([4, 5])
	assert_int(cache.requests).is_equal(5)
	cache.advance(costs, 5)
	assert_array(cache.status).is_equal([FlowCache.Status.ACTIVE, FlowCache.Status.WAITING])


## A map with more columns than rows (6 x 4, 24 cells): the cache hands its own cols and rows to
## every integration and bounds a goal by cols * rows.
func test_a_map_with_more_columns_than_rows_is_bounded_and_integrated_with_both() -> void:
	var cache: FlowCache = FlowCache.new()
	cache.configure(6, 4, 3, 2)
	assert_array([cache.cols, cache.rows]).is_equal([6, 4])
	assert_array([cache.acquire(23, FOOT, 0, 1), cache.acquire(24, FOOT, 0, 1)]).is_equal([0, -1])
	assert_int(cache.acquire(0, TRACKED, 0, 1)).is_equal(1)
	var costs: PackedByteArray = PackedByteArray()
	costs.resize(3 * 24)
	costs.fill(10)
	costs[8] = 0
	costs[9] = 0
	costs[2 * 24 + 14] = 0
	# Rock cells settle nothing: 22 cells for the FOOT field, 23 for the TRACKED one.
	assert_int(cache.advance(costs, BIG)).is_equal(22 + 23)
	for slot: int in 2:
		var lone: FlowField = FlowField.new()
		lone.begin(cache.key_goal[slot], cache.key_class[slot], costs, 6, 4)
		lone.advance(BIG)
		assert_array(cache.field(slot).cost).is_equal(lone.cost)
		assert_int(cache.field(slot).cost.size()).is_equal(48)


## A number that is no slot has no field, also on a cache that has slots: GDScript would read
## Array[-1] from the end, and acquire() answers -1 when it finds no slot.
func test_field_of_a_number_that_is_no_slot_is_null() -> void:
	var cache: FlowCache = _cache(2)
	assert_object(cache.field(-1)).is_null()
	assert_object(cache.field(2)).is_null()
	assert_object(cache.field(1)).is_not_null()


func test_configure_sizes_every_slot_and_resets_the_cache() -> void:
	var cache: FlowCache = _cache(2)
	cache.acquire(3, FOOT, 0, 1)
	cache.configure(4, 4, 1, 3)
	assert_array(cache.status).is_equal([0, 0, 0])
	assert_int(cache.requests).is_equal(0)
	assert_array([cache.fields.size(), cache.field(2).cost.size()]).is_equal([3, 36])
	assert_array([cache.acquire(16, 0, 0, 1), cache.acquire(3, TRACKED, 0, 1)]).is_equal([-1, -1])
	for slots: int in [0, -2]:
		cache.configure(8, 8, 3, slots)
		cache.recount(PackedInt32Array([0, 1]), 2)
		assert_array([cache.acquire(0, 0, 0, 1), cache.advance(_costs(), 9)]).is_equal([-1, 0])
		assert_array([cache.refs(0), cache.field(0)]).is_equal([0, null])


## configure() allocates every array of every slot; acquire, advance (slices, swaps, an unusable
## key), recount and invalidate then change no size, and no array is replaced (cost and next may
## trade places).
func test_no_array_changes_size_or_identity_after_configure() -> void:
	var cache: FlowCache = _cache(2)
	var before: Array = _arrays(cache)
	var size_of: Callable = func(array: Variant) -> int: return array.size()
	var field_sizes: Array = [100, 100, 100, 512, 100, 100]
	var sizes: Array = [2, 2, 2, 2, 2, 2, 2] + field_sizes + field_sizes
	assert_array(before.map(size_of)).is_equal(sizes)
	var short_costs: PackedByteArray = _costs().slice(0, 2 * CELLS)
	for version: int in 3:
		var costs: PackedByteArray = _costs([version + 1, 20])
		for step: int in 6:
			cache.acquire((version * 7 + step * 5) % CELLS, step % 3, version, step)
			cache.recount(PackedInt32Array([0, step % 2]), 2)
			cache.advance(short_costs if step % 3 == 2 else costs, 30 * step)
		cache.invalidate(version + 1)
		cache.advance(costs, BIG)
	var after: Array = _arrays(cache)
	assert_array(after.map(size_of)).is_equal(sizes)
	for array: Variant in before:
		var kept: bool = after.any(func(other: Variant) -> bool: return is_same(other, array))
		assert_bool(kept).is_true()
