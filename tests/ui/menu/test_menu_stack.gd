extends GdUnitTestSuite
## The menu stack (plan P522, ADR 0043 sections 3 and 4): push, pop, replace, the back request, the
## quit question at the root, and a cut with reduced effects.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const Greedy: GDScript = preload("res://tests/ui/menu/support/greedy_screen.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _menu: Control
var _stack: MenuStack
var _quit_calls: Array[int] = [0]
var _quit_on_go_back_before: bool = true


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_quit_calls[0] = 0
	_stack.quit_handler = func() -> void: _quit_calls[0] += 1
	await await_idle_frame()


func after_test() -> void:
	remove_child(_menu)
	_menu.free()
	assert_bool(get_tree().quit_on_go_back).is_equal(_quit_on_go_back_before)


func test_the_scene_starts_empty_and_switches_the_engine_quit_off() -> void:
	assert_int(_stack.depth()).is_equal(0)
	assert_object(_stack.current()).is_null()
	assert_bool(get_tree().quit_on_go_back).is_false()


func test_push_puts_the_screen_on_top_and_hides_the_one_under_it() -> void:
	var root: MenuScreen = await _push()
	var next: MenuScreen = await _push()
	assert_int(_stack.depth()).is_equal(2)
	assert_object(_stack.current()).is_same(next)
	assert_bool(next.visible).is_true()
	assert_bool(root.visible).is_false()


func test_pop_frees_the_top_and_shows_the_one_under_it() -> void:
	var root: MenuScreen = await _push()
	var next: MenuScreen = await _push()
	assert_bool(_stack.pop()).is_true()
	await await_idle_frame()
	assert_object(_stack.current()).is_same(root)
	assert_bool(root.visible).is_true()
	assert_bool(is_instance_valid(next)).is_false()
	assert_bool(_stack.pop()).override_failure_message("the root never pops").is_false()
	assert_int(_stack.depth()).is_equal(1)


func test_replace_swaps_the_top_without_getting_deeper() -> void:
	var root: MenuScreen = await _push()
	var other: MenuScreen = MenuScreen.new()
	_stack.replace(other)
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)
	assert_object(_stack.current()).is_same(other)
	assert_bool(is_instance_valid(root)).is_false()


func test_back_pops_a_screen_above_the_root() -> void:
	await _push()
	var next: MenuScreen = await _push()
	_stack.back()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)
	assert_bool(is_instance_valid(next)).is_false()
	assert_bool(_stack.is_asking_to_quit()).is_false()


func test_a_screen_that_uses_back_keeps_its_place() -> void:
	await _push()
	var greedy: MenuScreen = Greedy.new()
	_stack.push(greedy)
	await await_idle_frame()
	_stack.back()
	assert_int(_stack.depth()).is_equal(2)
	assert_int(greedy.get("asked") as int).is_equal(1)


func test_back_at_the_root_asks_to_quit_and_stay_closes_it() -> void:
	await _push()
	_stack.back()
	assert_bool(_stack.is_asking_to_quit()).is_true()
	assert_int(_quit_calls[0]).is_equal(0)
	_stack.back()  # Back closes the question (its cancel).
	assert_bool(_stack.is_asking_to_quit()).is_false()
	assert_int(_quit_calls[0]).is_equal(0)
	assert_int(_stack.depth()).is_equal(1)


func test_yes_to_the_quit_question_quits() -> void:
	await _push()
	_stack.back()
	var yes: Button = _stack.find_child("YesButton", true, false) as Button
	yes.pressed.emit()
	assert_int(_quit_calls[0]).is_equal(1)
	assert_bool(_stack.is_asking_to_quit()).is_false()


func test_the_android_back_notification_reaches_back() -> void:
	await _push()
	await _push()
	_stack.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)
	_stack.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_bool(_stack.is_asking_to_quit()).is_true()


func test_reduced_effects_cut_at_once() -> void:
	_stack.slide_ms = 400
	_stack.reduced = true
	var root: MenuScreen = await _push()
	var next: MenuScreen = MenuScreen.new()
	_stack.push(next)  # No frame: a cut is done when the call returns.
	assert_bool(root.visible).is_false()
	assert_float(next.position.x).is_equal(0.0)
	assert_bool(next.visible).is_true()


func test_a_slide_runs_and_the_next_call_finishes_it() -> void:
	_stack.slide_ms = 5000
	var root: MenuScreen = await _push()
	var next: MenuScreen = await _push()
	await await_idle_frame()
	assert_float(next.position.x).override_failure_message("still sliding in").is_greater(0.0)
	assert_bool(root.visible).is_true()
	assert_bool(_stack.pop()).is_true()  # Settles the push first, then slides out.
	assert_object(_stack.current()).is_same(root)
	assert_bool(root.visible).is_true()


func test_a_turn_keeps_the_stack() -> void:
	var window_before: Vector2i = get_window().size
	await _push()
	var next: MenuScreen = await _push()
	for size: Vector2i in [ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]]:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		assert_int(_stack.depth()).is_equal(2)
		assert_object(_stack.current()).is_same(next)
	get_window().size = window_before


func _push() -> MenuScreen:
	var screen: MenuScreen = MenuScreen.new()
	_stack.push(screen)
	screen.add_button("ONE", func() -> void: pass)  # The column exists once it entered the tree.
	await await_idle_frame()
	return screen
