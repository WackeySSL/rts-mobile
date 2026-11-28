extends GdUnitTestSuite
## CareerStats (ADR 0054 sections 4 and 5, plan P673c): record, clamp, malformed entries, unknown
## keys and the back-fill. A bad id is skipped, never kept, so SaveService can take the section.

var _warnings: Array[String] = []


func before_test() -> void:
	_warnings = []


func _warn(text: String) -> void:
	_warnings.append(text)


func _read(raw: Dictionary = {}, next_id: int = 1) -> CareerStats:
	return CareerStats.read(raw, next_id, _warn)


func _sum(outcome: StringName, ticks: int = 100, map_id: StringName = &"map_2") -> MatchSummary:
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = outcome
	summary.level = &"hard"
	summary.map_id = map_id
	summary.faction = &"renew"
	summary.ticks = ticks
	return summary


func test_win_loss_draw_and_surrender_record() -> void:
	var stats: CareerStats = _read()
	stats.record(_sum(&"win", 500), _warn)
	stats.record(_sum(&"loss", 300), _warn)
	stats.record(_sum(&"draw", 200), _warn)
	stats.record(_sum(&"surrender", 100), _warn)
	assert_int(stats.finished).is_equal(4)
	assert_int(stats.wins).is_equal(1)
	assert_int(stats.play_ticks).is_equal(1100)
	assert_int(stats.wins_on(&"map_2", &"hard")).is_equal(1)
	assert_int(stats.counter(&"wins_faction", &"renew")).is_equal(1)


func test_abandoned_and_lesson_summaries_change_nothing() -> void:
	var stats: CareerStats = _read()
	var before: Dictionary = stats.to_section()
	stats.record(_sum(&"abandoned"), _warn)
	var lesson: MatchSummary = _sum(&"win")
	lesson.lesson_id = &"basics"
	stats.record(lesson, _warn)
	assert_dict(stats.to_section()).is_equal(before)


func test_best_win_keeps_the_minimum_and_a_zero_tick_win_counts() -> void:
	var stats: CareerStats = _read()
	stats.record(_sum(&"win", 800), _warn)
	stats.record(_sum(&"win", 900), _warn)
	assert_int(stats.best_win_ticks).is_equal(800)
	stats.record(_sum(&"win", 0), _warn)
	assert_int(stats.best_win_ticks).is_equal(1)


func test_ints_are_clamped_on_read() -> void:
	var stats: CareerStats = _read({"format": 1, "finished": -5, "wins": MatchSetup.LIMIT * 3})
	assert_int(stats.finished).is_equal(0)
	assert_int(stats.wins).is_equal(MatchSetup.LIMIT)


func test_malformed_entries_are_dropped_with_a_warning() -> void:
	var stats: CareerStats = _read(
		{
			"format": 1,
			"wins_grid": {"map_2": {"hard": "x", "easy": 2}, "bad=key": {"hard": 1}, "m": 7},
			"wins_faction": {"renew": 3, "": 1, "fossil": 1.5},
			"earned": ["ground_won", "bad;id", "", 5, "ground_won"],
		}
	)
	assert_int(stats.wins_on(&"map_2", &"easy")).is_equal(2)
	assert_int(stats.wins_on(&"map_2", &"hard")).is_equal(0)
	assert_bool(stats.wins_grid.has("bad=key")).is_false()
	assert_dict(stats.wins_faction).is_equal({"renew": 3})
	assert_array(stats.earned).contains_exactly(["ground_won"])
	assert_bool(_warnings.is_empty()).is_false()


func test_a_refused_id_skips_only_its_cell_and_the_counters_still_count() -> void:
	var stats: CareerStats = _read()
	var win: MatchSummary = _sum(&"win")
	win.map_id = &""
	win.faction = &"re;new"
	stats.record(win, _warn)
	assert_int(stats.wins).is_equal(1)
	assert_dict(stats.wins_grid).is_empty()
	assert_dict(stats.wins_faction).is_empty()
	assert_bool(_warnings.is_empty()).is_false()


func test_unknown_keys_survive_to_section() -> void:
	var stats: CareerStats = _read({"format": 2, "wins": 4, "future_key": [1, 2], "x": {"y": 1}})
	var section: Dictionary = stats.to_section()
	assert_array(section["future_key"]).contains_exactly([1, 2])
	assert_dict(section["x"]).is_equal({"y": 1})
	assert_int(section["format"]).is_equal(2)
	assert_int(section["wins"]).is_equal(4)


func test_back_fill_takes_finished_from_the_award_counter() -> void:
	var stats: CareerStats = _read({"junk": 1}, 8)
	assert_bool(stats.saved).is_false()
	assert_int(stats.finished).is_equal(7)
	assert_int(stats.wins).is_equal(0)
	assert_int(stats.play_ticks).is_equal(0)
	assert_int(stats.earned.size()).is_equal(0)
	assert_int(_read({}, 1).finished).is_equal(0)
	assert_int(stats.to_section()["format"]).is_equal(CareerStats.FORMAT)
