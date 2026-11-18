extends GdUnitTestSuite
## The Reduced effects switch of the Settings screen reaches the menu stack it sits in at once
## (P526b); the boot and match-start wiring is tested in `test_menu_flow.gd`.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"

var _quit_on_go_back_before: bool = true


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	PrefsRig.begin()


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	PrefsRig.end()


func test_the_reduced_switch_follows_to_the_open_menu_stack_at_once() -> void:
	var menu: Node = auto_free((load(MENU_SCENE) as PackedScene).instantiate())
	add_child(menu)
	var stack: MenuStack = menu.get_node("MenuStack") as MenuStack
	stack.slide_ms = 0
	var screen: SettingsScreen = SettingsScreen.new()
	stack.push(screen)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(stack.reduced).is_false()
	screen.reduced_toggle.button_pressed = true
	assert_bool(stack.reduced).is_true()
	assert_bool(MenuPrefs.reduced_effects()).is_true()
	screen.reduced_toggle.button_pressed = false
	assert_bool(stack.reduced).is_false()
