extends GdUnitTestSuite
## The menu root's wiring (plan P524b): the default routes are registered before the main menu is
## pushed (How to play is live at the first show), and a screen `MenuFlow` was asked for opens on
## top of the main menu when its route exists.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _menu: Control
var _stack: MenuStack
var _routes: MenuRoutes


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_routes = MenuRoutes.new()


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func test_the_defaults_make_how_to_play_live_and_a_tap_opens_it_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(true, &"", size)
		_check_defaults()
		_close()
		_routes = MenuRoutes.new()
		UiScale.clear_override()


func _check_defaults() -> void:
	assert_bool(_routes.has(MenuRoutes.HOW_TO_PLAY)).is_true()
	assert_bool(_routes.has(MenuRoutes.SKIRMISH)).is_true()  # P525 registered it.
	assert_int(_stack.depth()).is_equal(1)
	var main: MainMenu = _stack.current() as MainMenu
	var enabled: Array[String] = []
	for child: Node in main.column.get_children():
		var button: Button = child as Button
		if button != null and not button.disabled:
			enabled.append(button.text)
	assert_array(enabled).is_equal(["SKIRMISH", "HOW TO PLAY"])
	main.column.get_child(_index_of(main, "HOW TO PLAY")).emit_signal("pressed")
	assert_object(_stack.current()).is_instanceof(HowToPlayScreen)


func test_a_pending_screen_with_a_route_opens_on_top_of_the_main_menu() -> void:
	_routes.register(&"fake", MenuScreen.new)
	await _open(false, &"fake", ScreenSizes.PORTRAIT[0])
	assert_int(_stack.depth()).is_equal(2)
	assert_bool(_stack.current() is MainMenu).is_false()


func test_a_pending_screen_nobody_registered_is_dropped_with_a_warning() -> void:
	await (
		assert_error(func() -> void: await _open(false, &"nothing", ScreenSizes.LANDSCAPE[0]))
		. is_push_warning("MenuRoot: no screen for the pending route nothing, dropped")
	)
	assert_int(_stack.depth()).is_equal(1)
	assert_bool(_stack.current() is MainMenu).is_true()


func test_the_pending_screen_ends_on_top_while_the_stack_slides() -> void:
	_routes.register(&"fake", MenuScreen.new)
	await _open(false, &"fake", ScreenSizes.LANDSCAPE[0], true)
	await get_tree().create_timer(0.6).timeout
	assert_int(_stack.depth()).is_equal(2)
	assert_bool(_stack.current() is MainMenu).is_false()


func test_a_lambda_factory_is_refused_with_a_warning() -> void:
	(
		assert_error(
			func() -> void: _routes.register(&"lam", func() -> MenuScreen: return MenuScreen.new())
		)
		. is_push_warning("MenuRoutes: route lam needs a standard Callable (X.new), not a lambda")
	)
	assert_bool(_routes.has(&"lam")).is_false()
	_routes.register(&"std", MenuScreen.new)
	assert_bool(_routes.has(&"std")).is_true()


func test_register_defaults_off_leaves_the_table_alone() -> void:
	await _open(false, &"", ScreenSizes.LANDSCAPE[0])
	assert_bool(_routes.has(MenuRoutes.HOW_TO_PLAY)).is_false()


func _open(defaults: bool, pending: StringName, size: Vector2i, slide: bool = false) -> void:
	var profile: UiMetrics = _profile_with_window(size)
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	_stack = _menu.get_node("MenuStack") as MenuStack
	if not slide:
		_stack.slide_ms = 0
	var root: MenuRoot = MenuRoot.new()
	root.routes = _routes
	root.register_defaults = defaults
	root.take_pending = func() -> StringName: return pending
	_menu.add_child(root)
	add_child(_menu)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null


func _index_of(screen: MenuScreen, text: String) -> int:
	for index: int in range(screen.column.get_child_count()):
		var button: Button = screen.column.get_child(index) as Button
		if button != null and button.text == text:
			return index
	return -1


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
