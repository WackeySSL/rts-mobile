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
	assert_str(text).contains("not Next")
	assert_str(text).contains("'Camera_Pinch' is not <section>-<slug>")
	assert_str(text).contains("'pinch' is not <section>-<slug>")
	assert_str(text).contains("exceed the target")


func test_a_lesson_with_no_beats_is_a_problem() -> void:
	var empty: TutorialLessonDef = Lesson.lesson("none", [])
	assert_int(empty.problems().size()).is_equal(1)


func test_only_a_next_beat_may_pause() -> void:
	# A paused match never ticks: an action beat would never end or stall.
	var lesson: TutorialLessonDef = Lesson.lesson(
		"basics",
		[Lesson.beat("zoom", TutorialConditions.Kind.ZOOM_LEVEL, {"pause": true, "value": 1})]
	)
	assert_str("\n".join(lesson.problems())).contains(
		"zoom: pauses on a condition that is not Next"
	)


func _chain_lesson(step: TutorialLeadInDef) -> TutorialLessonDef:
	var beat: TutorialBeatDef = Lesson.beat("train", TutorialConditions.Kind.NEXT)
	beat.lead_in.append(step)
	return Lesson.lesson("basics", [beat])


func test_a_sound_chain_has_no_problems() -> void:
	var step: TutorialLeadInDef = Lesson.lead_in(
		"BuildButton", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.DRAWER
	)
	assert_array(Array(_chain_lesson(step).problems())).is_empty()


func test_a_lead_in_with_a_tick_kind_or_a_pan_or_next_is_a_problem() -> void:
	for kind: TutorialConditions.Kind in [
		TutorialConditions.Kind.OWN_AT_LEAST,
		TutorialConditions.Kind.STRIKE_PENDING,
		TutorialConditions.Kind.NEXT,
		TutorialConditions.Kind.CAMERA_PANNED,
	]:
		var text: String = "\n".join(_chain_lesson(Lesson.lead_in("BuildButton", kind)).problems())
		assert_str(text).contains("train lead-in 0: kind")


func test_a_lead_in_with_no_anchor_or_no_control_name_is_a_problem() -> void:
	var step: TutorialLeadInDef = Lesson.lead_in("", TutorialConditions.Kind.UNFOLD_OPEN)
	assert_str("\n".join(_chain_lesson(step).problems())).contains("names no control")
	step.anchor = TutorialBeatDef.Anchor.NONE
	assert_str("\n".join(_chain_lesson(step).problems())).contains("has no anchor")
	step.anchor = TutorialBeatDef.Anchor.TILE  # A tile needs no name.
	assert_array(Array(_chain_lesson(step).problems())).is_empty()


func test_a_null_lead_in_is_a_problem() -> void:
	var lesson: TutorialLessonDef = _chain_lesson(null)
	assert_str("\n".join(lesson.problems())).contains("lead-in 0: is empty")


func test_a_gesture_must_fit_its_kind() -> void:
	var beat: TutorialBeatDef = Lesson.beat("zoom", TutorialConditions.Kind.ZOOM_LEVEL)
	beat.gesture = TutorialBeatDef.Gesture.PINCH_OUT
	assert_array(Array(Lesson.lesson("basics", [beat]).problems())).is_empty()
	beat.kind = TutorialConditions.Kind.SELECTED
	assert_str("\n".join(Lesson.lesson("basics", [beat]).problems())).contains("pinch needs")
	beat.gesture = TutorialBeatDef.Gesture.DRAG
	assert_str("\n".join(Lesson.lesson("basics", [beat]).problems())).contains("drag needs")
	beat.gesture_vector_dp = Vector2i(-160, 0)
	assert_array(Array(Lesson.lesson("basics", [beat]).problems())).is_empty()
	beat.kind = TutorialConditions.Kind.CAMERA_PANNED
	beat.gesture_vector_dp = Vector2i.ZERO
	assert_array(Array(Lesson.lesson("basics", [beat]).problems())).is_empty()
	beat.gesture = TutorialBeatDef.Gesture.TAP
	beat.gesture_vector_dp = Vector2i(10, 10)
	assert_str("\n".join(Lesson.lesson("basics", [beat]).problems())).contains("a vector goes")


func test_a_lead_ins_gesture_is_checked_too() -> void:
	var step: TutorialLeadInDef = Lesson.lead_in("BuildButton", TutorialConditions.Kind.UNFOLD_OPEN)
	step.gesture = TutorialBeatDef.Gesture.PINCH_IN
	assert_str("\n".join(_chain_lesson(step).problems())).contains("train lead-in 0: a pinch")
