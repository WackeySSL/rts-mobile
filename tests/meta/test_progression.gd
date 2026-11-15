extends GdUnitTestSuite
## Progression (ADR 0045, plan P511): the XP table, the per-minute cap, surrender, abandoned,
## lessons once, apply_bonus once and persisted across a SaveService reload, ranks and unlocks.
## Each test uses its own SaveService instance on its own directory, never the device's file.

const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"
const DEF_PATH: String = "res://data/meta/progression.tres"
const TICKS_PER_MINUTE: int = 900

var _dir: String = ""
var _changes: int = 0


func before_test() -> void:
	_dir = "user://test_progression_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_changes = 0


func after_test() -> void:
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func _save() -> Node:
	var save: Node = auto_free(load(SAVE_SCRIPT).new())
	save.call("set_path_override", _dir.path_join("save.cfg"))
	return save


func _progression(save: Node) -> Node:
	var service: Node = auto_free(load(SERVICE_SCRIPT).new())
	service.call("bind", save, null)
	service.connect("xp_changed", func() -> void: _changes += 1)
	return service


func _summary(outcome: StringName, level: StringName, minutes: int) -> MatchSummary:
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = outcome
	summary.level = level
	summary.ticks = minutes * TICKS_PER_MINUTE
	return summary


func _award(service: Node, summary: MatchSummary) -> XpAward:
	return service.call("award_match", summary) as XpAward


func test_data_rises_and_matches() -> void:
	var def: ProgressionDef = load(DEF_PATH)
	assert_int(def.rank_xp[0]).is_equal(0)
	for index: int in range(1, def.rank_xp.size()):
		assert_bool(def.rank_xp[index] > def.rank_xp[index - 1]).is_true()
	assert_int(def.rank_titles.size()).is_equal(def.rank_xp.size())
	for row: Dictionary in def.unlocks:
		assert_bool(int(row[&"rank"]) <= def.rank_xp.size()).is_true()


func test_xp_table_by_outcome_and_level() -> void:
	# No minutes played: outcome_xp * level_percent / 100.
	var expected: Dictionary = {
		[&"win", &"easy"]: 70,
		[&"win", &"normal"]: 100,
		[&"win", &"hard"]: 140,
		[&"loss", &"easy"]: 28,
		[&"loss", &"normal"]: 40,
		[&"loss", &"hard"]: 56,
		[&"draw", &"easy"]: 42,
		[&"draw", &"normal"]: 60,
		[&"draw", &"hard"]: 84,
	}
	for key: Array in expected:
		var service: Node = _progression(_save())
		var award: XpAward = _award(service, _summary(key[0], key[1], 0))
		assert_int(award.base_xp).is_equal(expected[key])
		assert_int(service.call("xp")).is_equal(expected[key])


func test_minute_bonus_and_cap() -> void:
	var service: Node = _progression(_save())
	# 5 minutes * 4 = 20, under the cap of 40.
	assert_int(_award(service, _summary(&"win", &"normal", 5)).base_xp).is_equal(120)
	# 30 minutes would be 120 but the cap is 40.
	assert_int(_award(service, _summary(&"win", &"normal", 30)).base_xp).is_equal(140)
	# A part of a minute does not count.
	var part: MatchSummary = _summary(&"win", &"normal", 0)
	part.ticks = TICKS_PER_MINUTE - 1
	assert_int(_award(service, part).base_xp).is_equal(100)


func test_surrender_counts_as_loss() -> void:
	var service: Node = _progression(_save())
	var award: XpAward = _award(service, _summary(&"surrender", &"normal", 2))
	assert_int(award.base_xp).is_equal(40 + 8)


func test_abandoned_gives_nothing() -> void:
	var service: Node = _progression(_save())
	assert_object(_award(service, _summary(&"abandoned", &"normal", 10))).is_null()
	assert_int(service.call("xp")).is_equal(0)
	assert_int(_changes).is_equal(0)


func test_lesson_pays_once_and_never_takes_a_bonus() -> void:
	var service: Node = _progression(_save())
	var lesson: MatchSummary = _summary(&"win", &"easy", 3)
	lesson.lesson_id = &"lesson_1"
	var first: XpAward = _award(service, lesson)
	assert_int(first.base_xp).is_equal(40)
	assert_bool(service.call("apply_bonus", first.id, 2)).is_false()
	assert_object(_award(service, lesson)).is_null()
	assert_int(service.call("xp")).is_equal(40)
	lesson.lesson_id = &"lesson_2"
	assert_int(_award(service, lesson).base_xp).is_equal(40)
	assert_int(service.call("xp")).is_equal(80)


func test_apply_bonus_once_and_persisted() -> void:
	var save: Node = _save()
	var service: Node = _progression(save)
	var award: XpAward = _award(service, _summary(&"win", &"normal", 0))
	assert_bool(award.id != &"").is_true()
	assert_bool(service.call("apply_bonus", award.id, 2)).is_true()
	assert_int(service.call("xp")).is_equal(200)
	assert_bool(service.call("apply_bonus", award.id, 2)).is_false()
	assert_int(service.call("xp")).is_equal(200)
	assert_int(save.call("flush")).is_equal(OK)
	# A restart: a new SaveService reads the file, a new Progression reads the section.
	var reloaded: Node = _progression(_save())
	assert_int(reloaded.call("xp")).is_equal(200)
	assert_bool(reloaded.call("apply_bonus", award.id, 2)).is_false()
	assert_int(reloaded.call("xp")).is_equal(200)
	# The counter goes on: the next award has a new id.
	var next: XpAward = _award(reloaded, _summary(&"loss", &"normal", 0))
	assert_bool(next.id != award.id).is_true()


func test_apply_bonus_refuses_unknown_old_and_weak() -> void:
	var service: Node = _progression(_save())
	assert_bool(service.call("apply_bonus", &"nope", 2)).is_false()
	assert_bool(service.call("apply_bonus", &"", 2)).is_false()
	var first: XpAward = _award(service, _summary(&"win", &"normal", 0))
	assert_bool(service.call("apply_bonus", first.id, 1)).is_false()
	assert_bool(service.call("apply_bonus", first.id, 0)).is_false()
	# Eight more awards push the first out of the kept window.
	for _i: int in range(8):
		_award(service, _summary(&"loss", &"easy", 0))
	assert_bool(service.call("apply_bonus", first.id, 2)).is_false()
	# The newest still works, with a larger multiplier.
	var last: XpAward = _award(service, _summary(&"win", &"hard", 0))
	var before: int = service.call("xp")
	assert_bool(service.call("apply_bonus", last.id, 3)).is_true()
	assert_int(service.call("xp") - before).is_equal(280)


func test_rank_thresholds_and_titles() -> void:
	var def: ProgressionDef = load(DEF_PATH)
	var save: Node = _save()
	var service: Node = _progression(save)
	assert_int(service.call("rank")).is_equal(1)
	for index: int in range(def.rank_xp.size()):
		save.call("set_section", &"progress", {"xp": def.rank_xp[index]})
		service.call("bind", save, null)
		assert_int(service.call("rank")).is_equal(index + 1)
		assert_str(service.call("title", index + 1)).is_equal(def.rank_titles[index])
		if index > 0:
			save.call("set_section", &"progress", {"xp": def.rank_xp[index] - 1})
			service.call("bind", save, null)
			assert_int(service.call("rank")).is_equal(index)
	assert_int(service.call("max_rank")).is_equal(def.rank_xp.size())


func test_unlocks_follow_rank() -> void:
	var save: Node = _save()
	var service: Node = _progression(save)
	assert_bool(service.call("is_unlocked", &"map", &"kestrel_flats")).is_true()
	assert_bool(service.call("is_unlocked", &"level", &"normal")).is_true()
	assert_bool(service.call("is_unlocked", &"map", &"map_2")).is_false()
	assert_bool(service.call("is_unlocked", &"level", &"hard")).is_false()
	var cases: Array = [[100, &"map", &"map_2"], [250, &"level", &"hard"], [500, &"map", &"map_3"]]
	for row: Array in cases:
		save.call("set_section", &"progress", {"xp": row[0] - 1})
		service.call("bind", save, null)
		assert_bool(service.call("is_unlocked", row[1], row[2])).is_false()
		save.call("set_section", &"progress", {"xp": row[0]})
		service.call("bind", save, null)
		assert_bool(service.call("is_unlocked", row[1], row[2])).is_true()


func test_everything_unlocks_without_ads() -> void:
	# About five Normal matches at a 50% win rate reach the last unlock; no bonus is used.
	var service: Node = _progression(_save())
	for index: int in range(5):
		var outcome: StringName = &"win" if index % 2 == 0 else &"loss"
		_award(service, _summary(outcome, &"normal", 9))
	assert_bool(service.call("is_unlocked", &"map", &"map_3")).is_true()
	assert_bool(service.call("is_unlocked", &"level", &"hard")).is_true()


func test_xp_changed_fires_on_award_and_bonus() -> void:
	var service: Node = _progression(_save())
	var award: XpAward = _award(service, _summary(&"win", &"normal", 0))
	assert_int(_changes).is_equal(1)
	service.call("apply_bonus", award.id, 2)
	assert_int(_changes).is_equal(2)
	service.call("apply_bonus", award.id, 2)
	service.call("apply_bonus", &"nope", 2)
	assert_int(_changes).is_equal(2)


func test_summary_from_snapshot() -> void:
	var snapshot: MatchSnapshot = MatchSnapshot.new()
	snapshot.tick = 1800
	var running: MatchSummary = MatchSummary.from_snapshot(snapshot, &"hard", &"m", 1, false)
	assert_str(running.outcome).is_equal("abandoned")
	assert_int(running.ticks).is_equal(1800)
	snapshot.match_end_tick = 1800
	snapshot.winner = 1
	assert_str(MatchSummary.from_snapshot(snapshot, &"hard", &"m", 1, false).outcome).is_equal(
		"win"
	)
	assert_str(MatchSummary.from_snapshot(snapshot, &"hard", &"m", 2, false).outcome).is_equal(
		"loss"
	)
	snapshot.winner = 0
	assert_str(MatchSummary.from_snapshot(snapshot, &"hard", &"m", 1, false).outcome).is_equal(
		"draw"
	)
	assert_str(MatchSummary.from_snapshot(snapshot, &"hard", &"m", 1, true).outcome).is_equal(
		"surrender"
	)
