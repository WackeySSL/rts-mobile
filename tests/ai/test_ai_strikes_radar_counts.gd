extends "res://tests/ai/support/dusk_suite.gd"
## The Dusk Array's radar diagnostics of `AiStrikes` (plan row P577c): per fire, whether a radar was
## known, whether some producer's ring could cover one, and whether the chosen ring did. They steer
## nothing. The hand-built Worlds are the ones of `test_ai_strikes_radar.gd`.


func test_a_fire_with_no_radar_known_counts_nothing() -> void:
	_flag_radars()
	_cluster()
	_enemy_building("vehicle_factory", 10, 31)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	assert_int(_striker.strikes).is_equal(2)  # `_after_sighting` fires twice.
	assert_array(_counts()).is_equal([0, 0, 0])


func test_a_known_radar_out_of_every_ring_is_known_but_not_coverable() -> void:
	_flag_radars()
	_cluster()
	_enemy_building("vehicle_factory", 10, 31)
	_enemy_building("fossil_radar", 11, 24)  # About 7.5 tiles from the twin, far from the cluster.
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	assert_int(_striker.strikes).is_equal(2)  # `_after_sighting` fires twice.
	assert_array(_counts()).is_equal([2, 0, 0])


func test_a_radar_beside_a_producer_that_loses_is_coverable_but_not_chosen() -> void:
	_striker._radar_bonus = 0
	_rich_and_radar()
	assert_array(_counts()).is_equal([2, 2, 0])
	assert_array(_target()).is_equal([CLUSTER_POINT.x, CLUSTER_POINT.y])


func test_the_bonus_lifts_the_radar_ring_and_all_three_count() -> void:
	_rich_and_radar()
	assert_array(_counts()).is_equal([2, 2, 2])
	assert_array(_target()).is_equal([TWIN_POINT.x, TWIN_POINT.y])


func test_a_remembered_radar_counts_as_known() -> void:
	_flag_radars()
	_cluster()
	_enemy_building("vehicle_factory", 10, 31)
	_ghost(9999, "fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
	assert_int(_counts()[0]).is_equal(2)


## Each case fires twice, so a count of 2 is every fire. The known, coverable, chosen fires.
func _counts() -> Array[int]:
	return [_striker.fires_radar_known, _striker.fires_radar_coverable, _striker.fires_radar_chosen]
