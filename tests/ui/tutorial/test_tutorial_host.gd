extends GdUnitTestSuite
## The host that runs a lesson in its match (plan row P544): a lesson's match gets a director and a
## coach mark wired to the scene, any other match gets nothing, and the end or Skip of the lesson
## returns to the Tutorial screen through the flow.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")


class FlowStub:
	extends Node
	var runner: MatchRunner = null
	var setup: MatchSetup = null
	var left: Array[StringName] = []

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return setup

	func return_to_menu(screen: StringName = &"") -> void:
		left.append(screen)


var _quit_on_go_back_before: bool = true
var _main: Node
var _flow: FlowStub


func before_test() -> void:
	MenuRig.begin()
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	MenuRig.end()
	CommandQueue.clear()


func test_a_match_the_flow_did_not_build_from_a_lesson_gets_no_host() -> void:
	await _open(&"basics", false)
	assert_object(TutorialHost.attach(_main, _flow)).is_null()  # Not the flow's runner.
	_flow.runner = _main.get_node("MatchRunner")
	_flow.setup.lesson_id = &""  # A skirmish.
	assert_object(TutorialHost.attach(_main, _flow)).is_null()
	_flow.setup = null
	assert_object(TutorialHost.attach(_main, _flow)).is_null()
	assert_object(_main.get_node_or_null("TutorialHost")).is_null()


func test_a_lesson_match_gets_a_director_and_a_coach_mark_wired_to_the_scene() -> void:
	await _open(&"basics", true)
	var host: TutorialHost = TutorialHost.attach(_main, _flow)
	assert_object(host).is_not_null()
	var director: TutorialDirector = host.director
	assert_bool(director.running()).is_true()
	assert_str(String(director.lesson.id)).is_equal("basics")
	assert_object(director.camera).is_same(_main.get_node("Camera"))
	assert_object(director.sidebar).is_not_null()
	assert_object(director.placement).is_not_null()
	assert_object(director.strike_aim).is_not_null()
	assert_object(director.selection).is_not_null()
	assert_object(director.hud).is_same((_main.get_node("Hud/HudStateFeed") as HudStateFeed).state)
	assert_object(host.mark.get_parent()).is_same(_main.get_node("Hud"))
	assert_object(host.mark.director).is_same(director)
	director.advance()  # The first beat's prompt shows.
	assert_object(director.current).is_not_null()


func test_skip_and_the_last_beat_return_to_the_tutorial_screen() -> void:
	await _open(&"basics", true)
	var host: TutorialHost = TutorialHost.attach(_main, _flow)
	assert_array(_flow.left).is_empty()
	host.director.advance()
	await await_idle_frame()
	var skip: Button = host.mark.find_child("Skip", true, false) as Button
	assert_bool(skip.is_visible_in_tree()).is_true()  # The first card has Skip (answer 4).
	skip.pressed.emit()
	await await_idle_frame()
	assert_array(_flow.left).is_equal([&"tutorial"])
	host.director.lesson_done.emit(&"basics")
	await await_idle_frame()
	assert_array(_flow.left).is_equal([&"tutorial", &"tutorial"])


func test_a_lesson_without_a_file_warns_and_adds_no_director() -> void:
	await _open(&"nothing", true)
	(
		assert_error(func() -> void: TutorialHost.attach(_main, _flow))
		. is_push_warning("TutorialHost: no lesson file for nothing")
	)
	assert_object(_main.get_node_or_null("TutorialHost/TutorialDirector")).is_null()


func _open(lesson_id: StringName, owned: bool) -> void:
	_main = auto_free(await MatchRig.open(self))
	_flow = auto_free(FlowStub.new())
	add_child(_flow)
	_flow.setup = MatchSetup.new()
	_flow.setup.lesson_id = lesson_id
	if owned:
		_flow.runner = _main.get_node("MatchRunner")
