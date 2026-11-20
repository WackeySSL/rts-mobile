extends GdUnitTestSuite
## The lesson host's coach mark against real touches (plan row P544, review round 1): the mark is
## the HUD's last child, above the pause menu and the result screen, so the touches below go through
## the viewport, not a parent check. On Basics' first beat (a card about the pill, not the menu)
## with the pause menu open: a tap on RESUME closes the menu and the lesson goes on, a tap on LEAVE
## TUTORIAL (and its question) lands on the Tutorial screen, and the result screen's button takes
## its tap. Landscape and upright.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Sizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const Touch: GDScript = preload("res://tests/support/touch_events.gd")


class FlowStub:
	extends Node
	var runner: MatchRunner = null
	var setup: MatchSetup = null
	var left: Array[StringName] = []

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return setup

	func mark_surrendered() -> void:
		pass

	func return_to_menu(screen: StringName = &"") -> void:
		left.append(screen)


## A flow whose Back counts and changes no scene.
class ResultFlow:
	extends "res://game/ui/menu/menu_flow_service.gd"
	var leaves: int = 0
	var owned: MatchRunner = null

	func current_runner() -> MatchRunner:
		return owned

	func leave_match(_screen: StringName = &"") -> void:
		leaves += 1


var _window_before: Vector2i = Vector2i.ZERO
var _main: Node
var _flow: FlowStub
var _host: TutorialHost
var _hud: Node
var _state: HudState


func before_test() -> void:
	_window_before = get_window().size
	MenuRig.begin()
	CommandQueue.clear()


func after_test() -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	CommandQueue.clear()
	MenuRig.end()
	UiScale.clear_override()
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:  # A button that left the match changes the scene.
		tree.current_scene.free()
		tree.current_scene = null
	get_window().size = _window_before


func test_a_tap_on_resume_closes_the_menu_and_the_lesson_goes_on() -> void:
	for size: Vector2i in [Sizes.LANDSCAPE[0], Sizes.PORTRAIT[0]]:
		await _stage(size)
		var label: String = str(size)
		assert_bool(_host.mark.visible).override_failure_message(label + " mark").is_false()
		_tap(_center(&"ResumeButton"))
		await await_idle_frame()
		(
			assert_bool(_state.is_open(HudState.Unfold.PAUSE))
			. override_failure_message(label)
			. is_false()
		)
		assert_bool(_host.director.running()).override_failure_message(label).is_true()
		assert_array(_flow.left).override_failure_message(label).is_empty()
		_free_stage()


func test_a_tap_on_leave_tutorial_lands_on_the_tutorial_screen_and_ends_the_offer() -> void:
	for size: Vector2i in [Sizes.LANDSCAPE[0], Sizes.PORTRAIT[0]]:
		SaveService.set_section(TutorialDirector.SECTION, {})
		await _stage(size)
		var label: String = str(size)
		var exit: Button = _hud.find_child("ExitButton", true, false) as Button
		assert_str(exit.text).is_equal("LEAVE TUTORIAL")
		_tap(_center(&"ExitButton"))
		await await_idle_frame()
		_tap(_visible_yes().get_global_rect().get_center())
		await await_idle_frame()
		assert_array(_flow.left).override_failure_message(label).is_equal([&"tutorial"])
		assert_bool(TutorialStart.first_launch_due()).override_failure_message(label).is_false()
		_free_stage()


func test_the_result_screen_button_takes_its_tap_over_the_lessons_card() -> void:
	for size: Vector2i in [Sizes.LANDSCAPE[0], Sizes.PORTRAIT[0]]:
		await _stage(size, false)
		var result: Control = _hud.get_node("ResultScreen")
		var results: ResultFlow = auto_free(ResultFlow.new())
		results.owned = _flow.runner  # The flow owns the match, so Back leaves through it.
		add_child(results)
		result.flow = results
		result.call("_on_match_ended", 2)
		for _frame: int in 6:
			await await_idle_frame()
		var back: Button = result.find_child("BackButton", true, false) as Button
		_tap(back.get_global_rect().get_center())
		await await_idle_frame()
		assert_int(results.leaves).override_failure_message(str(size)).is_equal(1)
		assert_array(_flow.left).override_failure_message(str(size)).is_empty()  # Not Skip's.
		assert_object(get_tree().current_scene).override_failure_message(str(size)).is_null()
		_free_stage()
		remove_child(results)


## The Sell question over a beat: its Sell button takes the tap, and the card stands down.
func test_the_sell_question_takes_its_tap_over_the_lessons_card() -> void:
	for size: Vector2i in [Sizes.LANDSCAPE[0], Sizes.PORTRAIT[0]]:
		await _stage(size, false)
		var label: String = str(size)
		assert_bool(_host.mark.visible).override_failure_message(label + " before").is_true()
		var card: ConfirmDialog = _hud.find_child("SellCard", true, false) as ConfirmDialog
		var sold: Array[int] = [0]
		card.confirmed.connect(func() -> void: sold[0] += 1)
		card.open()
		for _frame: int in 4:
			await await_idle_frame()
		assert_bool(card.visible).override_failure_message(label).is_true()
		assert_bool(_host.mark.visible).override_failure_message(label + " mark").is_false()
		_tap(card.find_child("YesButton", true, false).get_global_rect().get_center())
		await await_idle_frame()
		assert_int(sold[0]).override_failure_message(label + " tap").is_equal(1)
		assert_bool(card.visible).override_failure_message(label + " closed").is_false()
		assert_array(_flow.left).override_failure_message(label).is_empty()  # Not Skip's.
		assert_object(get_tree().current_scene).override_failure_message(label).is_null()
		_free_stage()


func _tap(at: Vector2) -> void:
	Touch.press(get_viewport(), 0, at)
	Touch.release(get_viewport(), 0, at)


## The Yes button of the question that is open.
func _visible_yes() -> Control:
	for dialog: Node in _hud.find_children("*", "ConfirmDialog", true, false):
		if (dialog as ConfirmDialog).visible:
			return dialog.find_child("YesButton", true, false) as Control
	return null


func _center(button_name: StringName) -> Vector2:
	return (_hud.find_child(button_name, true, false) as Control).get_global_rect().get_center()


## The main scene at `size` with a lesson host on Basics (its first beat up), and the pause menu
## open when `menu_open`.
func _stage(size: Vector2i, menu_open: bool = true) -> void:
	get_window().size = size
	await await_idle_frame()
	_main = await MatchRig.open(self)
	_hud = _main.get_node("Hud")
	_state = (_hud.get_node("HudStateFeed") as HudStateFeed).state
	_flow = auto_free(FlowStub.new())
	add_child(_flow)
	_flow.runner = _main.get_node("MatchRunner")
	_flow.setup = MatchSetup.new()
	_flow.setup.lesson_id = &"basics"
	(_hud.get_node("PauseMenu") as PauseMenu).menu_flow = _flow
	_host = TutorialHost.attach(_main, _flow)
	assert_object(_host).is_not_null()
	_host.director.advance()
	await await_idle_frame()
	if menu_open:
		_hud.get_node("EconomyPill").menu_pressed.emit()
	for _frame: int in 8:
		await await_idle_frame()


func _free_stage() -> void:
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null
