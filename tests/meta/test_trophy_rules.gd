extends GdUnitTestSuite
## TrophyRules (ADR 0054 sections 2 and 6, plan P673c): each of the 16 data trophies, one case that
## earns it and one that just misses, on summaries built the way MatchSummary builds them. Every
## threshold is read from the catalog, never typed here.

const MAPS: Array[StringName] = [&"kestrel_flats", &"map_2", &"map_3"]

var _catalog: TrophyCatalog = TrophyCatalog.load_default()
var _checked: Array[StringName] = []


func before_test() -> void:
	_checked = []


func _noop(_text: String) -> void:
	pass


## A summary from a hand-built end snapshot, like `MatchSummary.from_snapshot` does.
func _sum(
	outcome: StringName = &"win",
	level: StringName = &"normal",
	map_id: StringName = &"kestrel_flats",
	faction: StringName = &"fossil",
	ticks: int = 100000,
	lost_buildings: int = 3,
	hq_stands: bool = true
) -> MatchSummary:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.tick = ticks
	snap.match_end_tick = ticks
	snap.winner = 1 if outcome == &"win" else 2
	snap.type_ids = [_catalog.hq_type_ids[0], &"rifle_squad"]
	snap.owner = PackedInt32Array([1, 1])
	snap.type_index = PackedInt32Array([0, 1])
	snap.hp = PackedInt32Array([500 if hq_stands else 0, 10])
	snap.stat_lost_buildings = PackedInt32Array([0, lost_buildings])
	snap.stat_built = PackedInt32Array([0, 1])
	snap.stat_lost_units = PackedInt32Array([0, 1])
	snap.stat_harvested = PackedInt32Array([0, 1])
	var summary: MatchSummary = MatchSummary.from_snapshot(
		snap, level, map_id, 1, false, &"", faction
	)
	summary.outcome = outcome
	return summary


## True when trophy `id` is earned by `played` (the last one is the match being awarded).
func _earns(id: StringName, played: Array[MatchSummary], lessons: Array[String]) -> bool:
	var career: CareerStats = CareerStats.read({}, 1, _noop)
	for summary: MatchSummary in played:
		career.record(summary, _noop)
	var last: MatchSummary = played.back() if not played.is_empty() else null
	var found: Array[StringName] = TrophyRules.newly_earned(
		_catalog, career, PackedStringArray(lessons), last
	)
	return found.has(id)


func _check(
	id: StringName,
	earns: Array[MatchSummary],
	misses: Array[MatchSummary],
	earn_lessons: Array[String] = [],
	miss_lessons: Array[String] = []
) -> void:
	_checked.append(id)
	(
		assert_bool(_earns(id, earns, earn_lessons))
		. override_failure_message("%s should be earned" % id)
		. is_true()
	)
	(
		assert_bool(_earns(id, misses, miss_lessons))
		. override_failure_message("%s should be missed" % id)
		. is_false()
	)


func _wins(level: StringName, maps: Array[StringName]) -> Array[MatchSummary]:
	var played: Array[MatchSummary] = []
	for map_id: StringName in maps:
		played.append(_sum(&"win", level, map_id))
	return played


func _repeat(outcome: StringName, times: int) -> Array[MatchSummary]:
	var played: Array[MatchSummary] = []
	for _i: int in times:
		played.append(_sum(outcome))
	return played


func test_lesson_trophies() -> void:
	var none: Array[MatchSummary] = []
	_check(&"briefed", none, none, ["basics"], ["strikes"])
	var all: Array[String] = []
	all.assign(_catalog.find(&"fully_drilled").lesson_ids)
	_check(&"fully_drilled", none, none, all, all.slice(1))


func test_count_trophies() -> void:
	var none: Array[MatchSummary] = []
	_check(&"first_sortie", [_sum(&"loss")], none)
	_check(&"first_sortie", [_sum(&"draw")], none)
	_check(&"ground_won", [_sum()], [_sum(&"loss")])
	var seasoned: int = _catalog.find(&"seasoned").count
	_check(&"seasoned", _repeat(&"win", seasoned), _repeat(&"win", seasoned - 1))
	var haul: int = _catalog.find(&"long_haul").count
	_check(&"long_haul", _repeat(&"loss", haul), _repeat(&"loss", haul - 1))
	_check(
		&"ironward_honours",
		[_sum(&"win", &"easy", MAPS[0], &"fossil")],
		[_sum(&"win", &"easy", MAPS[0], &"renew")]
	)
	_check(
		&"facet_honours",
		[_sum(&"win", &"easy", MAPS[0], &"renew")],
		[_sum(&"win", &"easy", MAPS[0], &"fossil")]
	)


func test_win_grid_trophies() -> void:
	_check(&"warm_up", _wins(&"easy", [MAPS[1]]), _wins(&"normal", [MAPS[1]]))
	_check(&"even_footing", _wins(&"normal", [MAPS[1]]), _wins(&"easy", [MAPS[1]]))
	_check(&"iron_nerve", _wins(&"hard", [MAPS[2]]), _wins(&"normal", [MAPS[2]]))
	_check(&"flats_fords_crags", _wins(&"easy", MAPS), _wins(&"easy", [MAPS[0], MAPS[1], MAPS[1]]))
	_check(
		&"no_easy_ground",
		_wins(&"hard", MAPS),
		_wins(&"hard", [MAPS[0], MAPS[1]]) + _wins(&"normal", [MAPS[2]])
	)


func test_match_trophies() -> void:
	var limit: int = _catalog.find(&"short_work").max_ticks
	_check(
		&"short_work",
		[_sum(&"win", &"normal", MAPS[0], &"fossil", limit)],
		[_sum(&"win", &"normal", MAPS[0], &"fossil", limit + 1)]
	)
	_check(
		&"unbroken",
		[_sum(&"win", &"hard", MAPS[0], &"fossil", 100000, 3, true)],
		[_sum(&"win", &"hard", MAPS[0], &"fossil", 100000, 3, false)]
	)
	_check(
		&"clean_sheet",
		[_sum(&"win", &"easy", MAPS[0], &"fossil", 100000, 0)],
		[_sum(&"win", &"easy", MAPS[0], &"fossil", 100000, 1)]
	)


func test_every_data_trophy_was_checked() -> void:
	test_lesson_trophies()
	test_count_trophies()
	test_win_grid_trophies()
	test_match_trophies()
	assert_array(_checked).contains_exactly_in_any_order(_catalog.ids())


func test_a_lesson_or_a_loss_never_earns_a_match_trophy() -> void:
	var lesson: MatchSummary = _sum(&"win", &"hard", MAPS[0], &"fossil", 10, 0)
	lesson.lesson_id = &"basics"
	var def: TrophyDef = _catalog.find(&"clean_sheet")
	assert_bool(TrophyRules.match_met(def, lesson, _catalog.hq_type_ids)).is_false()
	var lost: MatchSummary = _sum(&"loss", &"hard", MAPS[0], &"fossil", 10, 0)
	assert_bool(TrophyRules.match_met(def, lost, _catalog.hq_type_ids)).is_false()
	assert_bool(TrophyRules.match_met(def, null, _catalog.hq_type_ids)).is_false()


func test_a_match_trophy_is_never_met_by_state_alone() -> void:
	var career: CareerStats = CareerStats.read({}, 1, _noop)
	career.record(_sum(&"win", &"hard", MAPS[0], &"fossil", 10, 0), _noop)
	var def: TrophyDef = _catalog.find(&"clean_sheet")
	assert_bool(TrophyRules.state_met(def, career, PackedStringArray())).is_false()


func test_an_earned_trophy_is_not_found_again_and_the_order_is_the_catalogs() -> void:
	var career: CareerStats = CareerStats.read({}, 1, _noop)
	var win: MatchSummary = _sum(&"win", &"easy", MAPS[0], &"fossil", 100000, 0)
	career.record(win, _noop)
	var none: PackedStringArray = PackedStringArray()
	var first: Array[StringName] = TrophyRules.newly_earned(_catalog, career, none, win)
	assert_array(first).contains_exactly(
		[&"first_sortie", &"ground_won", &"warm_up", &"ironward_honours", &"clean_sheet"]
	)
	for id: StringName in first:
		career.earned.append(String(id))
	assert_array(TrophyRules.newly_earned(_catalog, career, none, win)).is_empty()
