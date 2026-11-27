extends GdUnitTestSuite
## The six beats that point at a unit or at a selection (ADR 0048 section 13.6, plan row
## P593b-2), in `data/tutorial/{basics,air,support}.tres`. A separate suite from
## `test_lesson_data.gd`, which is at gdlint's public-method cap:
## - every `UNIT` anchor, on a beat or a lead-in, carries a selector, and no lesson has a problem;
## - each of the six beats has the lead-ins and the target of the table;
## - the beats keep their ids, conditions and budgets, and `groups` and `home` keep their place and
##   covers;
## - every `trigger_beat` of the scripted enemies names a beat of its lesson.

const LESSON_DIR: String = "res://data/tutorial/"
const LESSONS: Array[StringName] = [&"basics", &"strikes", &"air", &"support"]
const KIND = TutorialConditions.Kind
const ANCHOR = TutorialBeatDef.Anchor
const OWN = TutorialUnitPickDef.Whose.OWN
const ENEMY = TutorialUnitPickDef.Whose.ENEMY
const NEWEST = TutorialUnitPickDef.Pick.NEWEST
const NEAREST = TutorialUnitPickDef.Pick.NEAREST_CAMERA


func test_every_unit_anchor_carries_a_selector_and_the_lessons_have_no_problems() -> void:
	var units: int = 0
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		assert_array(lesson.problems()).override_failure_message(String(id)).is_empty()
		for beat: TutorialBeatDef in lesson.beats:
			var steps: Array = [beat]
			steps.append_array(beat.lead_in)
			for step: Object in steps:
				var label: String = "%s/%s" % [id, beat.id]
				if step.anchor == ANCHOR.UNIT:
					units += 1
					assert_object(step.unit).override_failure_message(label).is_not_null()
				else:
					assert_object(step.unit).override_failure_message(label).is_null()
	# attack, tap-air, home's lead-in, select-truck, mine's lead-in.
	assert_int(units).is_equal(5)


func test_groups_selects_the_whole_army_first() -> void:
	var beat: TutorialBeatDef = _beat(&"basics", &"groups")
	assert_int(beat.anchor).is_equal(ANCHOR.CONTROL)
	assert_str(beat.anchor_control).is_equal("AddGroup")
	assert_int(beat.lead_in.size()).is_equal(1)
	_assert_army_lead(beat.lead_in[0])


func test_attack_aims_at_the_nearest_enemy_after_the_army_lead_in() -> void:
	var beat: TutorialBeatDef = _beat(&"basics", &"attack")
	assert_int(beat.anchor).is_equal(ANCHOR.UNIT)
	assert_int(beat.kind).is_equal(KIND.ENEMY_LOSSES)
	_assert_pick(beat.unit, ENEMY, &"", NEAREST)
	assert_int(beat.lead_in.size()).is_equal(1)
	_assert_army_lead(beat.lead_in[0])


func test_tap_air_and_select_truck_aim_at_the_newest_own_unit() -> void:
	for row: Array in [
		[&"air", &"tap-air", &"fossil_fighter"], [&"support", &"select-truck", &"fossil_shot_truck"]
	]:
		var beat: TutorialBeatDef = _beat(row[0], row[1])
		assert_int(beat.anchor).is_equal(ANCHOR.UNIT)
		assert_int(beat.kind).is_equal(KIND.SELECTED)
		assert_array(beat.lead_in).is_empty()
		_assert_pick(beat.unit, OWN, row[2], NEWEST)


func test_home_and_mine_select_the_unit_before_their_control() -> void:
	for row: Array in [
		[&"air", &"home", &"Home", &"fossil_fighter"],
		[&"support", &"mine", &"Mine", &"fossil_shot_truck"]
	]:
		var beat: TutorialBeatDef = _beat(row[0], row[1])
		assert_int(beat.anchor).is_equal(ANCHOR.CONTROL)
		assert_str(beat.anchor_control).is_equal(row[2])
		assert_int(beat.lead_in.size()).is_equal(1)
		var lead: TutorialLeadInDef = beat.lead_in[0]
		assert_int(lead.anchor).is_equal(ANCHOR.UNIT)
		assert_int(lead.kind).is_equal(KIND.SELECTED)
		assert_str(lead.type_id).is_equal(row[3])
		_assert_pick(lead.unit, OWN, row[3], NEWEST)


## Ids, order, conditions, covers and budgets are the lessons' as before; the data changed only by
## the six beats' anchors and lead-ins.
func test_the_beats_keep_their_ids_conditions_and_budgets() -> void:
	var table: Dictionary[String, Array] = {
		"basics/groups": [KIND.GROUP_SAVED, 8],
		"basics/incoming": [KIND.NEXT, 4],
		"basics/attack": [KIND.ENEMY_LOSSES, 15],
		"air/tap-air": [KIND.SELECTED, 6],
		"air/home": [KIND.NEXT, 4],
		"support/select-truck": [KIND.SELECTED, 4],
		"support/mine": [KIND.NEXT, 8],
	}
	for label: String in table:
		var parts: PackedStringArray = label.split("/")
		var beat: TutorialBeatDef = _beat(StringName(parts[0]), StringName(parts[1]))
		assert_int(beat.kind).override_failure_message(label).is_equal(table[label][0])
		assert_int(beat.budget_s).override_failure_message(label).is_equal(table[label][1])
	assert_int(_beat(&"basics", &"groups").value).is_equal(1)
	assert_int(_beat(&"basics", &"groups").count).is_equal(1)


## `groups` and `home` are the beats the scripted enemies wait for: a rename or a move breaks them.
func test_the_trigger_beats_of_the_enemies_exist_and_the_two_unit_beats_hold_their_place() -> void:
	var seen: int = 0
	for id: StringName in LESSONS:
		var enemy: TutorialScriptDef = _lesson(id).enemy
		var ids: Array[StringName] = []
		for beat: TutorialBeatDef in _lesson(id).beats:
			ids.append(beat.id)
		for step: TutorialStepDef in enemy.steps:
			if step.trigger_beat != &"":
				seen += 1
				(
					assert_bool(ids.has(step.trigger_beat))
					. override_failure_message("%s: trigger_beat %s" % [id, step.trigger_beat])
					. is_true()
				)
	assert_int(seen).is_equal(3)  # groups, home, sell-last.
	var groups: TutorialBeatDef = _beat(&"basics", &"groups")
	assert_int(_lesson(&"basics").beats.find(groups)).is_equal(20)
	assert_array(groups.covers).is_equal([&"groups-save", &"groups-overwrite", &"groups-column"])
	var home: TutorialBeatDef = _beat(&"air", &"home")
	assert_int(_lesson(&"air").beats.find(home)).is_equal(5)
	assert_array(home.covers).is_equal([&"orders-home"])


func _assert_army_lead(lead: TutorialLeadInDef) -> void:
	assert_int(lead.anchor).is_equal(ANCHOR.CONTROL)
	assert_str(lead.anchor_control).is_equal("AllArmy")
	assert_int(lead.kind).is_equal(KIND.SELECTED)
	assert_str(lead.type_id).is_equal("rifle_squad")


func _assert_pick(
	pick: TutorialUnitPickDef,
	side: TutorialUnitPickDef.Whose,
	type_id: StringName,
	how: TutorialUnitPickDef.Pick
) -> void:
	assert_object(pick).is_not_null()
	assert_int(pick.side).is_equal(side)
	assert_str(pick.type_id).is_equal(type_id)
	assert_int(pick.pick).is_equal(how)


func _beat(lesson: StringName, id: StringName) -> TutorialBeatDef:
	for beat: TutorialBeatDef in _lesson(lesson).beats:
		if beat.id == id:
			return beat
	fail("no beat %s/%s" % [lesson, id])
	return null


func _lesson(id: StringName) -> TutorialLessonDef:
	return load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
