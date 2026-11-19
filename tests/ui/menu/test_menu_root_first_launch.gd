extends GdUnitTestSuite
## The first launch (plan row P544, ADR 0044 section 2): the menu root starts Basics once, after the
## intro has handed the menu over, and only where `offer_first_launch` is set (main_menu.tscn).

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")

var _quit_on_go_back_before: bool = false
var _menu: Control
var _started: Array[StringName] = []


func before_test() -> void:
	PrefsRig.begin()
	_started.clear()
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	PrefsRig.end()


func test_a_first_launch_starts_basics_once_and_remembers_the_offer() -> void:
	await _open(true)
	assert_array(_started).is_equal([&"basics"])
	assert_bool(TutorialStart.first_launch_due()).is_false()
	_close()
	await _open(true)  # The next launch.
	assert_int(_started.size()).is_equal(1)


func test_it_waits_while_the_intro_owns_the_screen() -> void:
	await _open(true, false)
	assert_int(_started.size()).is_equal(0)
	(_menu.get_node("MenuStack") as MenuStack).back_enabled = true
	await await_idle_frame()
	await await_idle_frame()
	assert_array(_started).is_equal([&"basics"])


func test_a_menu_without_the_switch_or_with_progress_starts_nothing() -> void:
	await _open(false)
	assert_int(_started.size()).is_equal(0)
	assert_bool(TutorialStart.first_launch_due()).is_true()
	_close()
	TutorialDirector.mark_done(&"basics")
	await _open(true)
	assert_int(_started.size()).is_equal(0)


func test_a_pending_screen_means_no_first_launch_start() -> void:
	await _open(true, true, &"fake")
	assert_int(_started.size()).is_equal(0)


func _open(offer: bool, handed_over: bool = true, pending: StringName = &"") -> void:
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	var stack: MenuStack = _menu.get_node("MenuStack") as MenuStack
	stack.slide_ms = 0
	stack.back_enabled = handed_over
	var routes: MenuRoutes = MenuRoutes.new()
	routes.register(&"fake", MenuScreen.new)
	var root: MenuRoot = MenuRoot.new()
	root.routes = routes
	root.register_defaults = false
	root.offer_first_launch = offer
	root.take_pending = func() -> StringName: return pending
	root.start_lesson = func(id: StringName) -> Error:
		_started.append(id)
		return OK
	_menu.add_child(root)
	add_child(_menu)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null
