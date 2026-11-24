extends "res://tests/view/support/hit_fx_suite.gd"
## The overload's sparks (ADR 0047 section 8, plan P575b): a blackout STRIKE record gives each shown
## building in its radius that is not the firer's one flash and chips, the lowest ids first while
## the ring has room, and a building that died that tick shows its collapse instead.

const BLACKOUT: int = 2
const REACH: int = 9000


## Opens a world of Barracks `spawns` (`[owner, x, y]`), the first being the firer, with a radius of
## `REACH` for its type, a blackout at `at` tile.
func _fire(spawns: Array, reveal: bool = true) -> void:
	_open(spawns, [QUIET, 0, 0, 0, 0], reveal)
	_weapons()
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[snap.index_of(1)]
	snap.type_strike_radius.resize(maxi(snap.type_strike_radius.size(), type + 1))
	snap.type_strike_radius[type] = REACH


func _blackout(point_tile: Vector2i, extra: PackedInt32Array = PackedInt32Array()) -> void:
	var owner: int = _runner.snapshot.owner[_runner.snapshot.index_of(1)]
	var at: Vector2i = Rig.centre(point_tile)
	var events: PackedInt32Array = PackedInt32Array(
		[World.Event.STRIKE, 1, at.x, at.y, BLACKOUT, owner, 0, 0]
	)
	events.append_array(extra)
	_hit_at(events)


func _flash_centres() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for slot: int in _ring().count():
		if _ring().puff_style(slot) == HitFx.Style.FLASH:
			found.append(_ring().puff_at(slot))
	return found


func test_a_blackout_sparks_every_shown_non_firer_building_in_the_radius() -> void:
	_fire([[2, 4, 4], [1, 8, 4], [2, 6, 6], [1, 12, 4], [1, 40, 40]])
	_blackout(Vector2i(6, 4))
	assert_int(_of(HitFx.Style.FLASH)).is_equal(2)  # Ids 2 and 4; 3 is the firer's, 5 too far.
	assert_int(_of(HitFx.Style.CHIP)).is_greater_equal(6)


func test_a_building_the_local_player_is_not_shown_gets_no_sparks() -> void:
	_fire([[1, 4, 4], [2, 20, 20]], false)  # The firer is the local player's; the enemy is hidden.
	assert_bool(_buildings.is_shown(_runner.snapshot.index_of(2))).is_false()
	_blackout(Vector2i(20, 20))
	assert_int(_ring().count()).is_equal(0)


func test_reduced_effects_drop_the_chips() -> void:
	_fire([[2, 4, 4], [1, 8, 4], [1, 12, 4]])
	_life.reduced = true
	_blackout(Vector2i(6, 4))
	assert_int(_of(HitFx.Style.FLASH)).is_equal(2)
	assert_int(_of(HitFx.Style.CHIP)).is_equal(0)


func test_a_ring_overflow_takes_the_lowest_ids() -> void:
	_fire(
		[[2, 4, 4], [1, 6, 4], [1, 8, 4], [1, 10, 4], [1, 12, 4], [1, 4, 8], [1, 6, 8], [1, 8, 8]]
	)
	_blackout(Vector2i(8, 6))
	assert_int(_ring().count()).is_equal(DATA.hit_slots)
	var flashes: Array[Vector2] = _flash_centres()
	assert_int(flashes.size()).is_between(1, 6)
	var snap: MatchSnapshot = _runner.snapshot
	for id: int in range(2, 9):
		var centre: Vector2 = _buildings.frame_box(snap.index_of(id)).get_center()
		var shown: bool = false
		for flash: Vector2 in flashes:
			shown = shown or flash.is_equal_approx(centre)
		assert_bool(shown).override_failure_message("id %d" % id).is_equal(id - 2 < flashes.size())


func test_a_kill_shows_the_collapse_not_a_flash() -> void:
	_fire([[2, 4, 4], [1, 8, 4], [1, 10, 4]])
	var at: Vector2i = Rig.position_of(_runner, 2)
	_blackout(Vector2i(8, 4), Effects.died(at, 0, 2, 1))
	assert_int(_of(HitFx.Style.FLASH)).is_equal(1)  # Only id 3's.


func test_a_deep_bore_record_sparks_nothing() -> void:
	_fire([[2, 4, 4], [1, 8, 4]])
	var at: Vector2i = Rig.centre(Vector2i(8, 4))
	_hit_at(PackedInt32Array([World.Event.STRIKE, 1, at.x, at.y, 1, 2, 0, 0]))
	assert_int(_ring().count()).is_equal(0)
