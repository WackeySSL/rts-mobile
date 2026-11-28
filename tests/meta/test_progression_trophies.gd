extends GdUnitTestSuite
## Progression and the career (ADR 0054 section 6, plan P673c): counters across awards, the
## back-fill on an old save, unknown keys, a bad id, abandoned, lesson replay, `XpAward.trophies`,
## `refresh_trophies`, a read-only save and one flush holding both sections.

const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"

var _dir: String = ""
var _log: Array[String] = []


func before_test() -> void:
	_dir = "user://test_prog_trophies_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_log = []


func after_test() -> void:
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func _sink(text: String) -> void:
	_log.append(text)


func _save() -> Node:
	var save: Node = auto_free(load(SAVE_SCRIPT).new())
	save.call("set_path_override", _dir.path_join("save.cfg"))
	save.set("error_sink", _sink)
	return save


func _service(save: Node, catalog: TrophyCatalog = null) -> Node:
	var service: Node = auto_free(load(SERVICE_SCRIPT).new())
	service.set("error_sink", _sink)
	service.call("bind", save, null, catalog)
	return service


func _sum(
	outcome: StringName = &"win",
	level: StringName = &"normal",
	ticks: int = 100000,
	map_id: StringName = &"kestrel_flats"
) -> MatchSummary:
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = outcome
	summary.level = level
	summary.map_id = map_id
	summary.faction = &"fossil"
	summary.ticks = ticks
	summary.lost_buildings = 2
	return summary


func _award(service: Node, summary: MatchSummary) -> XpAward:
	return service.call("award_match", summary) as XpAward


func _career(save: Node) -> Dictionary:
	return save.call("get_section", &"career")


func test_counters_add_up_across_awards() -> void:
	var service: Node = _service(_save())
	_award(service, _sum(&"win", &"hard", 5000))
	_award(service, _sum(&"loss", &"easy", 3000))
	_award(service, _sum(&"win", &"normal", 4000, &"map_2"))
	var career: Dictionary = service.call("career")
	assert_int(career["finished"]).is_equal(3)
	assert_int(career["wins"]).is_equal(2)
	assert_int(career["play_ticks"]).is_equal(12000)
	assert_int(career["best_win_ticks"]).is_equal(4000)
	assert_dict(career["wins_grid"]).is_equal(
		{"kestrel_flats": {"hard": 1}, "map_2": {"normal": 1}}
	)
	assert_dict(career["wins_faction"]).is_equal({"fossil": 2})


func test_award_trophies_list_exactly_the_new_ones_in_catalog_order() -> void:
	var service: Node = _service(_save())
	var first: XpAward = _award(service, _sum(&"win", &"easy", 1000))
	assert_array(first.trophies).contains_exactly(
		[&"first_sortie", &"ground_won", &"warm_up", &"ironward_honours"]
	)
	var second: XpAward = _award(service, _sum(&"win", &"easy", 1000))
	assert_array(second.trophies).is_empty()
	assert_int(service.call("earned_count")).is_equal(4)
	assert_bool(service.call("is_earned", &"ground_won")).is_true()
	assert_bool(service.call("is_earned", &"iron_nerve")).is_false()


func test_a_loss_earns_only_first_sortie_and_an_abandoned_match_changes_nothing() -> void:
	var save: Node = _save()
	var service: Node = _service(save)
	assert_object(_award(service, _sum(&"abandoned"))).is_null()
	assert_bool(_career(save).is_empty()).is_true()
	assert_int((service.call("career") as Dictionary)["finished"]).is_equal(0)
	var award: XpAward = _award(service, _sum(&"loss"))
	assert_array(award.trophies).contains_exactly([&"first_sortie"])


func test_back_fill_on_an_old_save() -> void:
	var save: Node = _save()
	var old: Dictionary = {"xp": 300, "next_award_id": 26, "awards": [], "lessons": []}
	save.call("set_section", &"progress", old)
	save.call("set_section", &"tutorial", {"done": PackedStringArray(["basics"])})
	var service: Node = _service(save)
	assert_int((service.call("career") as Dictionary)["finished"]).is_equal(25)
	assert_int((service.call("career") as Dictionary)["wins"]).is_equal(0)
	assert_bool(_career(save).is_empty()).is_true()
	assert_bool(service.call("is_earned", &"briefed")).is_false()
	var found: Array[StringName] = service.call("refresh_trophies")
	assert_array(found).contains_exactly([&"briefed", &"first_sortie", &"long_haul"])
	assert_bool(service.call("is_earned", &"ground_won")).is_false()
	assert_int(_career(save)["finished"]).is_equal(25)
	assert_array(service.call("refresh_trophies")).is_empty()


func test_refresh_writes_nothing_when_nothing_is_new() -> void:
	var save: Node = _save()
	var service: Node = _service(save)
	assert_array(service.call("refresh_trophies")).is_empty()
	assert_bool(_career(save).is_empty()).is_true()


func test_a_lesson_award_earns_its_trophy_and_a_replay_earns_nothing() -> void:
	var save: Node = _save()
	save.call("set_section", &"tutorial", {"done": PackedStringArray(["basics"])})
	var service: Node = _service(save)
	var lesson: MatchSummary = _sum(&"win", &"easy", 800, &"map_2")
	lesson.lesson_id = &"basics"
	var award: XpAward = _award(service, lesson)
	assert_array(award.trophies).contains_exactly([&"briefed"])
	assert_int((service.call("career") as Dictionary)["finished"]).is_equal(0)
	assert_object(_award(service, lesson)).is_null()
	assert_array(service.call("refresh_trophies")).is_empty()


func test_unknown_career_keys_survive_a_write() -> void:
	var save: Node = _save()
	save.call("set_section", &"career", {"format": 1, "finished": 2, "from_newer": {"a": [1]}})
	var service: Node = _service(save)
	_award(service, _sum())
	assert_dict(_career(save)["from_newer"]).is_equal({"a": [1]})
	assert_int(_career(save)["finished"]).is_equal(3)


func test_a_bad_id_is_refused_without_losing_the_award() -> void:
	var save: Node = _save()
	var service: Node = _service(save)
	var summary: MatchSummary = _sum(&"win", &"hard", 100, &"bad;map")
	summary.faction = &""
	var award: XpAward = _award(service, summary)
	assert_object(award).is_not_null()
	assert_int(service.call("xp")).is_equal(award.base_xp)
	assert_int(_career(save)["wins"]).is_equal(1)
	assert_dict(_career(save)["wins_grid"]).is_empty()


func test_a_bad_earned_id_in_the_save_is_dropped_not_rewritten() -> void:
	var save: Node = _save()
	save.call("set_section", &"career", {"format": 1, "earned": ["ground_won", "x=y"]})
	var service: Node = _service(save)
	_award(service, _sum(&"loss"))
	assert_array(_career(save)["earned"]).contains_exactly(["ground_won", "first_sortie"])


func test_a_read_only_save_changes_nothing() -> void:
	var save: Node = _save()
	var service: Node = _service(save)
	save.set("_read_only", true)
	assert_object(_award(service, _sum())).is_null()
	assert_array(service.call("refresh_trophies")).is_empty()
	assert_bool(_career(save).is_empty()).is_true()


func test_one_flush_holds_both_sections_and_a_reload_keeps_them() -> void:
	var save: Node = _save()
	var service: Node = _service(save)
	_award(service, _sum())
	save.call("flush")
	var reloaded: Node = _save()
	reloaded.call("_load")
	assert_int(_career(reloaded)["wins"]).is_equal(1)
	assert_int((reloaded.call("get_section", &"progress") as Dictionary)["xp"]).is_greater(0)


func test_an_old_builds_progress_rewrite_keeps_career() -> void:
	var save: Node = _save()
	var service: Node = _service(save)
	_award(service, _sum())
	var progress: Dictionary = save.call("get_section", &"progress")
	save.call("set_section", &"progress", progress)
	assert_int(service.call("earned_count")).is_greater(0)
	assert_int((service.call("career") as Dictionary)["wins"]).is_equal(1)


func test_apply_bonus_adds_base_xp_only() -> void:
	var service: Node = _service(_save())
	var award: XpAward = _award(service, _sum(&"win", &"normal", 0))
	assert_bool(award.trophies.is_empty()).is_false()
	var before: int = service.call("xp")
	assert_bool(service.call("apply_bonus", award.id, 2)).is_true()
	assert_int(service.call("xp")).is_equal(before + award.base_xp)


func test_an_unusable_catalog_turns_trophies_off_and_still_pays() -> void:
	var service: Node = _service(_save(), TrophyCatalog.new())
	assert_object(service.call("trophy_catalog")).is_null()
	var award: XpAward = _award(service, _sum())
	assert_object(award).is_not_null()
	assert_array(award.trophies).is_empty()
	assert_int(service.call("earned_count")).is_equal(0)
