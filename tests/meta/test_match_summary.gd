extends GdUnitTestSuite
## MatchSummary's facts for trophies (ADR 0054 section 3, plan P673b): the faction, the local side's
## four stats and the standing type ids, from a hand-built snapshot, plus the lesson summary.


func _snapshot() -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.tick = 900
	snap.match_end_tick = 900
	snap.winner = 1
	snap.type_ids = [&"headquarters", &"rifle_squad", &"power_plant"]
	# Rows: side 1 HQ, side 1 rifle, side 1 rifle (same type), side 1 dead power plant, side 2 HQ.
	snap.owner = PackedInt32Array([1, 1, 1, 1, 2])
	snap.type_index = PackedInt32Array([0, 1, 1, 2, 0])
	snap.hp = PackedInt32Array([500, 10, 20, 0, 900])
	snap.stat_built = PackedInt32Array([0, 7, 3])
	snap.stat_lost_units = PackedInt32Array([0, 4, 1])
	snap.stat_lost_buildings = PackedInt32Array([0, 2, 5])
	snap.stat_harvested = PackedInt32Array([0, 1200, 800])
	return snap


func _summary(side: int = 1) -> MatchSummary:
	return MatchSummary.from_snapshot(
		_snapshot(), &"hard", &"kestrel_flats", side, false, &"", &"fossil"
	)


func test_from_snapshot_copies_the_faction_and_the_local_stats() -> void:
	var summary: MatchSummary = _summary()
	assert_str(summary.faction).is_equal("fossil")
	assert_int(summary.built).is_equal(7)
	assert_int(summary.lost_units).is_equal(4)
	assert_int(summary.lost_buildings).is_equal(2)
	assert_int(summary.harvested).is_equal(1200)


func test_the_stats_follow_the_local_side() -> void:
	var summary: MatchSummary = _summary(2)
	assert_int(summary.built).is_equal(3)
	assert_int(summary.lost_buildings).is_equal(5)


func test_standing_types_are_distinct_and_skip_dead_and_foreign_rows() -> void:
	var standing: Array[StringName] = _summary().standing_types
	assert_array(standing).contains_exactly([&"headquarters", &"rifle_squad"])


func test_a_side_out_of_range_gives_zeros() -> void:
	var summary: MatchSummary = _summary(9)
	assert_int(summary.built).is_equal(0)
	assert_int(summary.lost_units).is_equal(0)
	assert_int(summary.lost_buildings).is_equal(0)
	assert_int(summary.harvested).is_equal(0)
	assert_array(summary.standing_types).is_empty()


func test_an_unknown_faction_stays_empty() -> void:
	var summary: MatchSummary = MatchSummary.from_snapshot(
		_snapshot(), &"normal", &"kestrel_flats", 1, false
	)
	assert_str(summary.faction).is_equal("")


func test_a_fresh_summary_keeps_its_defaults() -> void:
	var summary: MatchSummary = MatchSummary.new()
	assert_str(summary.outcome).is_equal(MatchSummary.OUTCOME_ABANDONED)
	assert_str(summary.faction).is_equal("")
	assert_int(summary.lost_buildings).is_equal(0)
	assert_array(summary.standing_types).is_empty()


func test_for_lesson_fills_the_faction_and_the_facts() -> void:
	var summary: MatchSummary = MatchSummary.for_lesson(
		&"basics", &"easy", &"tutorial_basics", 1, 300, &"fossil", _snapshot()
	)
	assert_str(summary.outcome).is_equal(MatchSummary.OUTCOME_WIN)
	assert_str(summary.faction).is_equal("fossil")
	assert_int(summary.built).is_equal(7)
	assert_int(summary.lost_buildings).is_equal(2)
	assert_array(summary.standing_types).contains_exactly([&"headquarters", &"rifle_squad"])


func test_for_lesson_without_a_snapshot_keeps_zeros() -> void:
	var summary: MatchSummary = MatchSummary.for_lesson(&"basics", &"easy", &"m", 1, 300)
	assert_str(summary.faction).is_equal("")
	assert_int(summary.built).is_equal(0)
	assert_array(summary.standing_types).is_empty()
