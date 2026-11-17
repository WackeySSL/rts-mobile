extends GdUnitTestSuite
## The menu root's wiring (plan P524b): the default routes are registered before the main menu is
## pushed (How to play is live at the first show), and a screen `MenuFlow` was asked for opens on
## top of the main menu when its route exists.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"

var _quit_on_go_back_before: bool = true
var _menu: Control
var _stack: MenuStack
var _routes: MenuRoutes


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_routes = MenuRoutes.new()


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func test_the_defaults_make_how_to_play_live_and_a_tap_opens_it() -> void:
	await _open(true, &"")
	assert_bool(_routes.has(MenuRoutes.HOW_TO_PLAY)).is_true()
	assert_bool(_routes.has(MenuRoutes.SKIRMISH)).is_false()
	assert_int(_stack.depth()).is_equal(1)
	var main: MainMenu = _stack.current() as MainMenu
	var enabled: Array[String] = []
	for child: Node in main.column.get_children():
		var button: Button = child as Button
		if button != null and not button.disabled:
			enabled.append(button.text)
	assert_array(enabled).is_equal(["HOW TO PLAY"])
	main.column.get_child(_index_of(main, "HOW TO PLAY")).emit_signal("pressed")
	await await_idle_frame()
	assert_object(_stack.current()).is_instanceof(HowToPlayScreen)


func test_a_pending_screen_with_a_route_opens_on_top_of_the_main_menu() -> void:
	_routes.register(&"fake", func() -> MenuScreen: return MenuScreen.new())
	await _open(false, &"fake")
	assert_int(_stack.depth()).is_equal(2)
	assert_bool(_stack.current() is MainMenu).is_false()


func test_a_pending_screen_nobody_registered_is_dropped() -> void:
	await _open(false, &"nothing")
	assert_int(_stack.depth()).is_equal(1)
	assert_bool(_stack.current() is MainMenu).is_true()


func test_register_defaults_off_leaves_the_table_alone() -> void:
	await _open(false, &"")
	assert_bool(_routes.has(MenuRoutes.HOW_TO_PLAY)).is_false()


func _open(defaults: bool, pending: StringName) -> void:
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	var root: MenuRoot = MenuRoot.new()
	root.routes = _routes
	root.register_defaults = defaults
	root.take_pending = func() -> StringName: return pending
	_menu.add_child(root)
	add_child(_menu)
	await await_idle_frame()
	await await_idle_frame()


func _index_of(screen: MenuScreen, text: String) -> int:
	for index: int in range(screen.column.get_child_count()):
		var button: Button = screen.column.get_child(index) as Button
		if button != null and button.text == text:
			return index
	return -1
