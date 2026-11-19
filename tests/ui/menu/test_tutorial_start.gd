extends GdUnitTestSuite
## The tutorial's shared start helpers (plan row P544, ADR 0044 sections 1 and 2): the lessons in
## order, a lesson's setup from its file alone, the next lesson and the first-launch flag in the
## save (next to the director's `done`).

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")


func before_test() -> void:
	PrefsRig.begin()


func after_test() -> void:
	PrefsRig.end()


func test_every_listed_lesson_has_a_file_and_a_setup_that_starts_from_it_alone() -> void:
	for id: StringName in TutorialStart.ORDER:
		var def: TutorialLessonDef = TutorialStart.lesson(id)
		assert_object(def).override_failure_message(String(id)).is_not_null()
		assert_str(String(def.id)).is_equal(String(id))
		var setup: MatchSetup = TutorialStart.setup_for(def)
		assert_object(setup).is_not_null()
		assert_str(String(setup.lesson_id)).is_equal(String(id))
		assert_str(setup.scenario_path).is_equal(def.scenario.resource_path)
		assert_int(setup.match_seed).is_equal(def.match_seed)
		assert_int(setup.opponents.size()).is_equal(1)
		assert_object(setup.opponents[0]).is_same(def.enemy)
		var runner: MatchRunner = auto_free(MatchRunner.new())
		assert_int(setup.apply(runner)).is_equal(OK)


func test_the_order_is_the_four_lessons_with_basics_first() -> void:
	assert_array(TutorialStart.ORDER).is_equal([&"basics", &"strikes", &"air", &"support"])
	assert_object(TutorialStart.lesson(&"nothing")).is_null()
	assert_object(TutorialStart.setup_for(null)).is_null()


func test_the_next_lesson_is_the_first_one_not_done() -> void:
	assert_str(String(TutorialStart.next_lesson())).is_equal("basics")
	TutorialDirector.mark_done(&"basics")
	TutorialDirector.mark_done(&"air")
	assert_str(String(TutorialStart.next_lesson())).is_equal("strikes")
	TutorialDirector.mark_done(&"strikes")
	TutorialDirector.mark_done(&"support")
	assert_str(String(TutorialStart.next_lesson())).is_equal("")


func test_the_first_launch_is_due_once_and_a_finished_lesson_ends_it() -> void:
	assert_bool(TutorialStart.first_launch_due()).is_true()
	assert_bool(TutorialStart.mark_offered()).is_true()
	assert_bool(TutorialStart.first_launch_due()).is_false()
	assert_bool(SaveService.get_section(TutorialDirector.SECTION).get("offered")).is_true()
	SaveService.set_section(TutorialDirector.SECTION, {})
	assert_bool(TutorialStart.first_launch_due()).is_true()
	TutorialDirector.mark_done(&"basics")  # An old save with progress and no flag.
	assert_bool(TutorialStart.first_launch_due()).is_false()


func test_offering_keeps_the_done_marks() -> void:
	TutorialDirector.mark_done(&"air")
	TutorialStart.mark_offered()
	assert_bool(TutorialDirector.is_done(&"air")).is_true()


func test_start_hands_the_lessons_setup_to_the_flow_and_a_missing_lesson_warns() -> void:
	var flow: Node = auto_free(FakeFlow.new())
	add_child(flow)
	flow.refuse = ERR_BUSY
	assert_int(await TutorialStart.start(flow, &"strikes")).is_equal(ERR_BUSY)
	assert_int(flow.started.size()).is_equal(1)
	assert_str(String(flow.started[0].lesson_id)).is_equal("strikes")
	(
		assert_error(func() -> void: await TutorialStart.start(flow, &"nothing"))
		. is_push_warning("TutorialStart: lesson nothing has no scenario or enemy")
	)
	assert_int(flow.started.size()).is_equal(1)
