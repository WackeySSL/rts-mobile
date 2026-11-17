extends GdUnitTestSuite
## MenuStack.back_enabled (plan P521, ADR 0043 section 4): while the boot intro opens out into the
## menu the stack ignores a go-back request, which every node receives.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"

var _menu: Control
var _stack: MenuStack
var _quit_on_go_back_before: bool = true


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	await await_idle_frame()


func after_test() -> void:
	remove_child(_menu)
	_menu.free()
	get_tree().quit_on_go_back = _quit_on_go_back_before


func test_a_go_back_request_does_nothing_while_back_is_disabled() -> void:
	_stack.back_enabled = false
	_stack.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()  # The stack defers its back().
	assert_bool(_stack.is_asking_to_quit()).is_false()
	_stack.back_enabled = true
	_stack.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_bool(_stack.is_asking_to_quit()).is_true()
