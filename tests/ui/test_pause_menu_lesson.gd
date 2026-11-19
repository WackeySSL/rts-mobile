extends GdUnitTestSuite
## The pause menu in a tutorial lesson (plan row P544): the card reads the lesson's own kicker,
## title and goal from its data (a skirmish keeps its own), Settings is not switched off by a lesson
## (it follows its route), and a button that is off keeps its frame, only greyed.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")


class FlowStub:
	extends Node
	var runner: MatchRunner = null
	var setup: MatchSetup = null

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return setup

	func return_to_menu(_screen: StringName = &"") -> void:
		pass


var _quit_on_go_back_before: bool = true
var _main: Node
var _menu: PauseMenu
var _state: HudState
var _flow: FlowStub


func before_test() -> void:
	MenuRig.begin()
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	MenuRig.end()
	CommandQueue.clear()


func test_a_lesson_card_reads_the_lessons_title_and_goal_not_the_skirmishs() -> void:
	await _open_main()
	await _open_menu()
	assert_str(_menu._kicker.text).is_equal("SKIRMISH")
	assert_str(_menu._objective.text).is_equal(PauseMenu.OBJECTIVE)
	_state.close(HudState.Unfold.PAUSE)
	_flow.setup = MatchSetup.new()
	_flow.setup.lesson_id = &"air"
	await _open_menu()
	var lesson: TutorialLessonDef = TutorialStart.lesson(&"air")
	assert_str(_menu._kicker.text).is_equal("TUTORIAL")
	assert_str(_menu._title.text).is_equal(tr(lesson.title_key).to_upper())
	assert_str(_menu._objective.text).is_equal(tr(lesson.objective_key))
	assert_str(_menu._objective.text).is_not_equal(PauseMenu.OBJECTIVE)
	assert_str(_menu._objective.text).is_not_equal(String(lesson.objective_key))  # Translated.


func test_settings_stays_on_in_a_lesson_and_a_disabled_button_keeps_its_frame() -> void:
	await _open_main()
	_flow.setup = MatchSetup.new()
	_flow.setup.lesson_id = &"basics"
	_menu.routes = MenuRoutes.new()
	_menu.routes.register(MenuRoutes.SETTINGS, MenuScreen.new)
	await _open_menu()
	var settings: Button = _menu.find_child("SettingsButton", true, false) as Button
	assert_bool(settings.disabled).is_false()
	assert_str((_menu.find_child("ExitButton", true, false) as Button).text).is_equal(
		"LEAVE TUTORIAL"
	)
	_state.close(HudState.Unfold.PAUSE)
	_menu.routes = MenuRoutes.new()
	await _open_menu()
	assert_bool(settings.disabled).is_true()
	var framed: StyleBoxFlat = settings.get_theme_stylebox("disabled") as StyleBoxFlat
	var plate: StyleBoxFlat = settings.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(framed).is_not_null()  # A frame, not the bare text of a theme with no style.
	assert_float(framed.bg_color.a).is_greater(0.0)
	assert_bool(framed.bg_color == plate.bg_color).is_true()


func _open_main() -> void:
	_main = auto_free(await MatchRig.open(self))
	_menu = _main.get_node("Hud/PauseMenu")
	_state = (_main.get_node("Hud/HudStateFeed") as HudStateFeed).state
	_flow = auto_free(FlowStub.new())
	add_child(_flow)
	_flow.runner = _main.get_node("MatchRunner")
	_menu.menu_flow = _flow


func _open_menu() -> void:
	_state.open(HudState.Unfold.PAUSE)
	await await_idle_frame()
