extends GdUnitTestSuite
## The menu stack (plan P522, ADR 0043 sections 3 and 4): push, pop, replace, covered screens out of
## the tree, the input block during a slide, the back request, the quit question at the root, focus
## restore, and a cut with reduced effects.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const Greedy: GDScript = preload("res://tests/ui/menu/support/greedy_screen.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _menu: Control
var _stack: MenuStack
var _quit_calls: Array[int] = [0]
var _quit_on_go_back_before: bool = false


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
	# The project keeps quit_on_go_back off (ADR 0043 section 4); this suite puts back what it found.
	assert_bool(get_tree().quit_on_go_back).is_false()
	get_tree().quit_on_go_back = _quit_on_go_back_before


func test_the_scene_starts_empty_and_switches_the_engine_quit_off() -> void:
	assert_int(_stack.depth()).is_equal(0)
	assert_object(_stack.current()).is_null()
	assert_bool(get_tree().quit_on_go_back).is_false()


func test_push_puts_the_screen_on_top_and_takes_the_one_under_it_out_of_the_tree() -> void:
	var root: MenuScreen = await _push()
	var next: MenuScreen = await _push()
	assert_int(_stack.depth()).is_equal(2)
	assert_object(_stack.current()).is_same(next)
	assert_bool(next.is_inside_tree()).is_true()
	assert_bool(root.is_inside_tree()).is_false()
	assert_bool(is_instance_valid(root)).is_true()  # Kept, not freed.


func test_pop_frees_the_top_and_puts_the_one_under_it_back() -> void:
	var root: MenuScreen = await _push()
	var next: MenuScreen = await _push()
	assert_bool(_stack.pop()).is_true()
	await await_idle_frame()
	assert_object(_stack.current()).is_same(root)
	assert_bool(root.is_inside_tree()).is_true()
	assert_bool(is_instance_valid(next)).is_false()
	assert_bool(_stack.pop()).override_failure_message("the root never pops").is_false()
	assert_int(_stack.depth()).is_equal(1)


func test_a_band_on_a_covered_screen_leaves_the_tree_and_comes_back_on_pop() -> void:
	var root: MenuScreen = await _push()
	var band: Control = Control.new()
	assert_bool(root.slot.host(band)).is_true()
	assert_bool(band.is_inside_tree()).is_true()
	await _push()
	await await_idle_frame()
	assert_bool(band.is_inside_tree()).override_failure_message("covered: out of tree").is_false()
	assert_bool(root.slot.has_band()).override_failure_message("still hosted").is_true()
	_stack.pop()
	await await_idle_frame()
	assert_bool(band.is_inside_tree()).is_true()


func test_replace_swaps_the_top_without_getting_deeper() -> void:
	var root: MenuScreen = await _push()
	var other: MenuScreen = MenuScreen.new()
	assert_bool(_stack.replace(other)).is_true()
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


func test_back_at_the_root_asks_to_quit_and_back_again_closes_it() -> void:
	await _push()
	_stack.back()
	assert_bool(_stack.is_asking_to_quit()).is_true()
	assert_int(_quit_calls[0]).is_equal(0)
	_stack.back()  # Back closes the question (its cancel).
	assert_bool(_stack.is_asking_to_quit()).is_false()
	assert_int(_quit_calls[0]).is_equal(0)
	assert_int(_stack.depth()).is_equal(1)


func test_the_quit_question_reads_its_words_from_the_english_table() -> void:
	var dialog: ConfirmDialog = _stack.find_child("QuitQuestion", true, false) as ConfirmDialog
	assert_str(dialog.question).is_equal("QUIT TREADLINE?")
	assert_str(dialog.yes_text).is_equal("QUIT")
	assert_str(dialog.no_text).is_equal("STAY")
	for key: StringName in MenuText.ENGLISH:
		assert_str(tr(key)).is_equal(MenuText.ENGLISH[key])


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
	assert_bool(_stack.is_sliding()).is_false()
	assert_bool(root.is_inside_tree()).is_false()
	assert_float(next.position.x).is_equal(0.0)


func test_a_slide_blocks_input_and_ignores_a_second_push_pop_and_back() -> void:
	_stack.slide_ms = 2000
	await _push()
	var next: MenuScreen = await _push()
	var blocker: Control = _stack.find_child("Blocker", true, false) as Control
	assert_bool(_stack.is_sliding()).is_true()
	assert_bool(blocker.visible).is_true()
	assert_int(blocker.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(next.get_index() < blocker.get_index()).is_true()  # The blocker is above it.
	assert_float(next.position.x).override_failure_message("sliding in").is_greater(0.0)
	assert_bool(_stack.push(MenuScreen.new())).is_false()
	assert_bool(_stack.replace(MenuScreen.new())).is_false()
	assert_bool(_stack.pop()).is_false()
	_stack.back()
	assert_int(_stack.depth()).is_equal(2)
	assert_object(_stack.current()).is_same(next)
	assert_bool(_stack.is_asking_to_quit()).is_false()


func test_a_finished_slide_unblocks_and_takes_the_covered_screen_out() -> void:
	_stack.slide_ms = 60
	var root: MenuScreen = await _push()
	var next: MenuScreen = await _push()
	await await_millis(400)
	assert_bool(_stack.is_sliding()).is_false()
	assert_bool((_stack.find_child("Blocker", true, false) as Control).visible).is_false()
	assert_bool(root.is_inside_tree()).is_false()
	assert_float(next.position.x).is_equal(0.0)
	assert_bool(_stack.pop()).is_true()  # A pop slides too.
	assert_bool(_stack.is_sliding()).is_true()
	await await_millis(400)
	assert_object(_stack.current()).is_same(root)
	assert_bool(root.is_inside_tree()).is_true()


func test_the_focus_comes_back_after_a_pop() -> void:
	var root: MenuScreen = await _push()
	var second: Button = root.column.get_child(1) as Button
	second.grab_focus()
	assert_bool(second.has_focus()).is_true()
	await _push()
	_stack.pop()
	await await_idle_frame()
	assert_bool(second.has_focus()).is_true()


func test_a_focus_owner_freed_while_covered_is_skipped() -> void:
	var root: MenuScreen = await _push()
	var second: Button = root.column.get_child(1) as Button
	second.grab_focus()
	await _push()
	root.column.remove_child(second)
	second.free()
	_stack.pop()
	await await_idle_frame()
	assert_object(_stack.current()).is_same(root)


func test_the_focus_comes_back_after_the_quit_question_closes() -> void:
	var root: MenuScreen = await _push()
	var second: Button = root.column.get_child(1) as Button
	second.grab_focus()
	_stack.back()
	assert_bool(_stack.is_asking_to_quit()).is_true()
	assert_bool(second.has_focus()).override_failure_message("the question took it").is_false()
	_stack.back()
	assert_bool(second.has_focus()).override_failure_message("closed by back").is_true()
	second.release_focus()
	_stack.back()
	(_stack.find_child("NoButton", true, false) as Button).pressed.emit()
	assert_bool(second.has_focus()).override_failure_message("closed by Stay").is_true()


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
	# The column exists once the screen entered the tree.
	screen.add_button("ONE", func() -> void: pass)
	screen.add_button("TWO", func() -> void: pass)
	await await_idle_frame()
	return screen
