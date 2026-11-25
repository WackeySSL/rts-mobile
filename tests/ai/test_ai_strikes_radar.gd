extends "res://tests/ai/support/dusk_suite.gd"
## The Dusk Array's radar rules of `AiStrikes` (plan rows P576 and P576b, ADR 0047 section 9): of
## equal rings the one over a seen or remembered enemy radar wins, and `strike_radar_bonus` lets it
## beat a slightly richer ring. The base `dusk_suite.gd` holds the hand-built Worlds.


## Two equal clusters: a lone factory at CLUSTER_POINT and another at TWIN_POINT (1,800 each). The
## wave has no goal, so both are candidates; with no radar the earlier anchor of the ranking, the
## first, wins. A radar of the League stands in a sector of its own, 2.5 tiles from the twin, so it
## does not change the ranking (a radar in the twin's sector would rank the twin first).
func test_with_no_radar_the_tie_goes_to_the_earlier_anchor() -> void:
	_twins()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_of_equal_clusters_the_ring_that_covers_a_seen_radar_wins() -> void:
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_the_radar_of_a_remembered_building_breaks_the_tie_too() -> void:
	_twins()
	_ghost(9999, "fossil_radar", RADAR_TILE.x, RADAR_TILE.y)  # No row shows it: a record only.
	_after_sighting()
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_a_radar_out_of_the_ring_or_not_yet_known_does_not_break_the_tie() -> void:
	_twins()
	# 5.5 tiles from the twin's centre: outside the ring of 4,000.
	_enemy_building("fossil_radar", 11, 24)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])
	# A radar in the ring whose type was sighted one run ago: not yet old enough to count.
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_memory.seen_first_tick[_world.type_ids.find(&"fossil_radar")] = AiMemory.NONE
	_memory.strike_wave = 0
	_fire(KNOWN + 60)
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_a_ring_that_already_covers_a_radar_keeps_its_place_against_another_that_does() -> void:
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_enemy_building("fossil_radar", 33, 28)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_a_cap_that_leaves_no_room_for_the_radar_check_leaves_the_tie_alone() -> void:
	# Three things, three anchors, nine tests: the cap of nine has no room for one more.
	_arm_strikes("normal", 1, _side(), MIN, 9)
	_striker._radar_bonus = 0
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])
	assert_int(_striker.tests).is_equal(9)


func test_a_radar_does_not_outweigh_a_richer_cluster() -> void:
	# The lone factory (1,800) against the far barracks pair (800) with a radar beside it.
	_flag_radars()
	_producers()
	_enemy_building("fossil_radar", 9, 30)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_the_radar_check_is_counted_and_capped() -> void:
	_twins()
	var base: int = _striker.tests
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_int(_striker.tests).is_greater(base)
	assert_int(_striker.passes).is_equal(0)
	assert_int(_striker.tests).is_less_equal(TESTS)


## The radar bonus (P576b): ring A is the factory and barracks at CLUSTER_POINT (2,200), ring B the
## twin factory (1,800) with the radar beside it. B is 400 poorer: the shipped bonus (800) lifts it
## over A, a bonus of 0 leaves A first.
func test_a_ring_over_a_radar_beats_a_slightly_richer_ring() -> void:
	_rich_and_radar()
	assert_int(_striker._radar_bonus).is_equal(800)
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_without_the_bonus_the_richer_ring_wins() -> void:
	_striker._radar_bonus = 0
	_rich_and_radar()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_the_bonus_equal_to_the_gap_is_a_tie_that_the_radar_ring_wins() -> void:
	_striker._radar_bonus = 400
	_rich_and_radar()
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_a_bonus_below_the_gap_does_not_lift_the_poorer_ring() -> void:
	_striker._radar_bonus = 399
	_rich_and_radar()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_an_exact_tie_still_goes_to_the_radar_ring_with_no_bonus() -> void:
	_striker._radar_bonus = 0
	_twins()
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_after_sighting()
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_the_bonus_does_not_outweigh_a_whole_production_cluster() -> void:
	# Two factories and a barracks (4,000) against one factory (1,800) with a radar.
	_flag_radars()
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("vehicle_factory", 30, 33)
	_enemy_building("barracks", 29, 36)
	_enemy_building("vehicle_factory", 10, 31)
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	var point: Array[int] = _target()
	assert_bool(point[1] > 30000).is_true()


func test_a_cap_with_no_room_for_the_radar_check_gives_no_bonus() -> void:
	# Three things, one anchor's sum is three tests: the cap of three leaves the radar unasked.
	_arm_strikes("normal", 1, _side(), MIN, 3)
	_rich_and_radar()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])
	assert_int(_striker.tests).is_equal(3)


func test_the_counted_tests_stay_within_the_cap_with_the_bonus() -> void:
	# Room for one anchor and one radar check (4), none for a second anchor.
	_arm_strikes("normal", 1, _side(), MIN, 4)
	_rich_and_radar()
	assert_int(_striker.tests).is_equal(4)
	assert_int(_striker.passes).is_equal(0)


func test_a_radar_alone_is_no_ring_and_does_not_fire() -> void:
	_striker._radar_bonus = 100000
	_flag_radars()
	_enemy_building("fossil_radar", 30, 30)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	assert_array(_shots()).is_empty()


func test_a_huge_bonus_does_not_move_the_shot_off_a_lone_cluster() -> void:
	# The Dusk Array asks for a raw value of 1 (`strike_min_value` is the Deep Bore's); a radar-less
	# cluster fires on its own point, whatever the bonus.
	_striker._radar_bonus = 100000
	_flag_radars()
	_cluster()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_a_ring_the_bonus_cannot_lift_costs_no_radar_test() -> void:
	# Bonus 100: ring B (1,800) cannot reach ring A (2,200), so only the anchors of A ask: four
	# things, four anchors of four tests, and two radar checks of one.
	_striker._radar_bonus = 100
	_rich_and_radar()
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])
	assert_int(_striker.tests).is_equal(18)
