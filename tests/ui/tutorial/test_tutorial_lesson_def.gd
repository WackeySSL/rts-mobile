extends GdUnitTestSuite
## The lesson data (plan row P541): the budgets, the ids a lesson covers and the problems a lesson
## reports before it ships.

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")


func _fixture() -> TutorialLessonDef:
	return (
		Lesson
		. lesson(
			"basics",
			[
				Lesson.beat(
					"pan",
					TutorialConditions.Kind.CAMERA_PANNED,
					{"covers": [&"camera-drag", &"camera-pinch"], "budget_s": 20}
				),
				Lesson.beat(
					"read",
					TutorialConditions.Kind.NEXT,
					{"covers": [&"camera-pinch", &"units-select"], "budget_s": 15, "pause": true}
				),
			],
			60
		)
	)


func test_a_sound_lesson_has_no_problems() -> void:
	assert_array(Array(_fixture().problems())).is_empty()


func test_budget_and_covered_ids() -> void:
	var lesson: TutorialLessonDef = _fixture()
	assert_int(lesson.budget_s()).is_equal(35)
	assert_array(lesson.covered_ids()).is_equal([&"camera-drag", &"camera-pinch", &"units-select"])


func test_problems_name_each_fault() -> void:
	var lesson: TutorialLessonDef = _fixture()
	lesson.target_s = 30
	lesson.beats[1].id = lesson.beats[0].id
	lesson.beats[1].prompt_key = &""
	lesson.beats[1].covers = [&"Camera_Pinch", &"pinch"]
	lesson.beats[0].pause = true  # CAMERA_PANNED needs no ticks: allowed.
	lesson.beats[0].kind = TutorialConditions.Kind.OWN_AT_LEAST  # Needs ticks: not with a pause.
	lesson.beats[0].anchor = TutorialBeatDef.Anchor.CONTROL
	var found: PackedStringArray = lesson.problems()
	var text: String = "\n".join(found)
	assert_str(text).contains("empty or repeated")
	assert_str(text).contains("no prompt key")
	assert_str(text).contains("names no control")
	assert_str(text).contains("needs ticks")
	assert_str(text).contains("'Camera_Pinch' is not <section>-<slug>")
	assert_str(text).contains("'pinch' is not <section>-<slug>")
	assert_str(text).contains("exceed the target")


func test_a_lesson_with_no_beats_is_a_problem() -> void:
	var empty: TutorialLessonDef = Lesson.lesson("none", [])
	assert_int(empty.problems().size()).is_equal(1)
