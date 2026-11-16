extends GdUnitTestSuite
## Progression guards (plan P511 review): lessons, get_award, path switches, a read-only save,
## malformed saves, an unusable def, the summary's surrender edges.
## Each test uses its own SaveService instance on its own directory, never the device's file.

const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"
const DEF_PATH: String = "res://data/meta/progression.tres"
const TICKS_PER_MINUTE: int = 900

var _dir: String = ""
var _changes: int = 0
var _messages: Array[String] = []


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
	service.set("error_sink", func(text: String) -> void: _messages.append(text))
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


func test_lesson_pays_only_when_won_and_unpaid_stays_open() -> void:
	var service: Node = _progression(_save())
	for outcome: StringName in [&"abandoned", &"loss", &"surrender", &"draw", &"bogus"]:
		var lesson: MatchSummary = _summary(outcome, &"easy", 3)
		lesson.lesson_id = &"lesson_1"
		assert_object(_award(service, lesson)).is_null()
	assert_int(service.call("xp")).is_equal(0)
	assert_int(_changes).is_equal(0)
	# Not marked paid by the failed tries: the win still pays.
	var won: MatchSummary = _summary(&"win", &"easy", 3)
	won.lesson_id = &"lesson_1"
	assert_int(_award(service, won).base_xp).is_equal(40)


func test_award_is_visible_after_bonus_and_through_get_award() -> void:
	var service: Node = _progression(_save())
	var award: XpAward = _award(service, _summary(&"win", &"normal", 0))
	assert_bool(award.bonus_applied).is_false()
	var before: XpAward = service.call("get_award", award.id)
	assert_bool(before.bonus_applied).is_false()
	assert_bool(service.call("apply_bonus", award.id, 2)).is_true()
	assert_bool(award.bonus_applied).is_true()
	var seen: XpAward = service.call("get_award", award.id)
	assert_bool(seen.bonus_applied).is_true()
	assert_int(seen.base_xp).is_equal(100)
	assert_object(service.call("get_award", &"nope")).is_null()


func test_path_switch_after_bind_never_cross_writes() -> void:
	var save: Node = _save()
	var service: Node = _progression(save)
	_award(service, _summary(&"win", &"normal", 0))
	save.call("flush")
	save.call("set_path_override", _dir.path_join("other.cfg"))
	assert_int(service.call("xp")).is_equal(0)
	_award(service, _summary(&"loss", &"normal", 0))
	save.call("flush")
	assert_int(service.call("xp")).is_equal(40)
	save.call("set_path_override", _dir.path_join("save.cfg"))
	assert_int(service.call("xp")).is_equal(100)


func test_read_only_save_changes_nothing() -> void:
	var save: Node = _save()
	var service: Node = _progression(save)
	var award: XpAward = _award(service, _summary(&"win", &"normal", 0))
	save.set("_read_only", true)
	_changes = 0
	assert_object(_award(service, _summary(&"win", &"normal", 0))).is_null()
	assert_bool(service.call("apply_bonus", award.id, 2)).is_false()
	assert_int(service.call("xp")).is_equal(100)
	assert_bool(award.bonus_applied).is_false()
	assert_int(_changes).is_equal(0)


func test_unknown_level_is_refused_with_an_error() -> void:
	var service: Node = _progression(_save())
	var errors: Array[String] = []
	service.set("error_sink", func(text: String) -> void: errors.append(text))
	assert_object(_award(service, _summary(&"win", &"nightmare", 0))).is_null()
	assert_int(errors.size()).is_equal(1)
	assert_int(service.call("xp")).is_equal(0)


func test_malformed_saved_entries_are_skipped() -> void:
	var save: Node = _save()
	var awards: Array = [
		{"id": "a1", "base_xp": "x", "bonus_applied": false}, {"id": "a2", "base_xp": 50}, 7
	]
	save.call("set_section", &"progress", {"xp": 10, "next_award_id": 3, "awards": awards})
	var service: Node = _progression(save)
	assert_bool(service.call("apply_bonus", &"a1", 2)).is_false()
	assert_bool(service.call("apply_bonus", &"a2", 2)).is_false()
	assert_int(service.call("xp")).is_equal(10)
	assert_int(_award(service, _summary(&"win", &"normal", 0)).base_xp).is_equal(100)


func test_unusable_def_is_refused_on_bind() -> void:
	var service: Node = auto_free(load(SERVICE_SCRIPT).new())
	var errors: Array[String] = []
	service.set("error_sink", func(text: String) -> void: errors.append(text))
	var broken: ProgressionDef = (load(DEF_PATH) as ProgressionDef).duplicate()
	broken.rank_titles = PackedStringArray(["only one"])
	assert_bool(service.call("bind", _save(), broken)).is_false()
	broken = (load(DEF_PATH) as ProgressionDef).duplicate()
	broken.rank_xp = PackedInt32Array()
	assert_bool(service.call("bind", _save(), broken)).is_false()
	broken = (load(DEF_PATH) as ProgressionDef).duplicate()
	broken.xp_per_minute = -1
	assert_bool(service.call("bind", _save(), broken)).is_false()
	assert_int(errors.size()).is_equal(3)
	# Nothing bound: queries answer safely and no award is made.
	assert_int(service.call("rank")).is_equal(1)
	assert_object(_award(service, _summary(&"win", &"normal", 0))).is_null()


func test_summary_surrender_edges() -> void:
	var snapshot: MatchSnapshot = MatchSnapshot.new()
	# Surrender with no end in the sim: abandoned.
	var open: MatchSummary = MatchSummary.from_snapshot(snapshot, &"normal", &"m", 1, true)
	assert_str(open.outcome).is_equal("abandoned")
	# The local side still won: a win stays a win.
	snapshot.match_end_tick = 900
	snapshot.winner = 1
	var won: MatchSummary = MatchSummary.from_snapshot(snapshot, &"normal", &"m", 1, true)
	assert_str(won.outcome).is_equal("win")
