extends GdUnitTestSuite
## Plan row P674 (ADR 0045 section 2, question 15): finishing a tutorial lesson pays `lesson_xp`
## once per lesson through the same award path a finished match uses (`MenuFlow` scores the end,
## `Progression.award_match`). The lesson ends at its last beat, not at a sim win, so the host hands
## the finish to the flow.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const LESSON: StringName = &"basics"

var _flow: Node
var _main: Node
var _menus: int = 0


class FakeAds:
	extends Node

	func take_start_credits_bonus() -> int:
		return 0

	func note_match_completed(_seconds: int) -> void:
		pass

	func settle_fullscreen() -> void:
		pass

	func maybe_show_interstitial(_placement: StringName) -> bool:
		return false


func before_test() -> void:
	MenuRig.begin()
	CommandQueue.clear()
	_menus = 0
	var ads: Node = auto_free(FakeAds.new())
	add_child(ads)
	var script: GDScript = load("res://game/ui/menu/menu_flow_service.gd")
	_flow = auto_free(script.new())
	add_child(_flow)
	_flow.ads = ads
	_flow.switch_to_main = func(main: Node) -> Error:
		_main = main
		add_child(main)
		return OK
	_flow.switch_to_menu = func() -> Error:
		_menus += 1
		return OK


func after_test() -> void:
	_flow.return_to_menu()
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	CommandQueue.clear()
	MenuRig.end()


func test_finishing_a_lesson_pays_its_xp_once() -> void:
	var before: int = Progression.xp()
	var paid: int = _lesson_xp()
	assert_int(paid).is_greater(0)
	await _finish_lesson()
	assert_int(Progression.xp()).is_equal(before + paid)
	assert_int(_menus).is_equal(1)
	assert_str(_flow.take_pending_screen()).is_equal("tutorial")
	# A replayed lesson pays nothing more.
	await _finish_lesson()
	assert_int(Progression.xp()).is_equal(before + paid)


func test_skipping_a_lesson_pays_nothing() -> void:
	var before: int = Progression.xp()
	var host: TutorialHost = await _start_lesson()
	host.director.lesson_skipped.emit(LESSON)
	await await_idle_frame()
	assert_int(Progression.xp()).is_equal(before)
	assert_int(_menus).is_equal(1)


func _lesson_xp() -> int:
	return (load("res://data/meta/progression.tres") as ProgressionDef).lesson_xp


func _start_lesson() -> TutorialHost:
	var def: TutorialLessonDef = TutorialStart.lesson(LESSON)
	assert_int(await _flow.start_match(TutorialStart.setup_for(def))).is_equal(OK)
	await await_idle_frame()
	return TutorialHost.attach(_main, _flow)


func _finish_lesson() -> TutorialHost:
	var host: TutorialHost = await _start_lesson()
	host.director.lesson_done.emit(LESSON)
	await await_idle_frame()
	await await_idle_frame()
	return host
