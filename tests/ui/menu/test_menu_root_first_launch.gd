extends GdUnitTestSuite
## The first launch (plan row P544, ADR 0044 section 2): the menu root starts Basics once, after the
## intro has handed the menu over, and only where `offer_first_launch` is set (main_menu.tscn).

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = false
var _menu: Control
var _profile: UiMetrics
var _started: Array[StringName] = []
var _result: Error = OK


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_profile = UiProfiles.all()[&"desktop"]
	PrefsRig.begin()
	_started.clear()
	_result = OK
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	UiScale.clear_override()
	PrefsRig.end()


func test_a_first_launch_starts_basics_after_the_intro_and_offers_it_again_until_it_is_dealt_with(
) -> void:
	await _open(true)
	assert_int(_started.size()).is_equal(0)  # The intro still owns the screen.
	await _hand_over()
	assert_array(_started).is_equal([&"basics"])
	assert_bool(TutorialStart.first_launch_due()).is_true()  # Started is not spent: a kill restarts.
	_close()
	await _open(true)  # The next launch, after the app was killed during Basics.
	await _hand_over()
	assert_int(_started.size()).is_equal(2)
	TutorialStart.note_left(&"basics")  # Skip lesson or Leave tutorial.
	_close()
	await _open(true)
	await _hand_over()
	assert_int(_started.size()).is_equal(2)


func test_a_refused_start_warns_and_the_offer_stays() -> void:
	_result = ERR_BUSY
	await _open(true)
	await (
		assert_error(func() -> void: await _hand_over())
		. is_push_warning("MenuRoot: Basics did not start (Busy)")
	)
	assert_int(_started.size()).is_equal(1)
	assert_bool(TutorialStart.first_launch_due()).is_true()


func test_a_player_who_updated_the_app_gets_no_lesson() -> void:
	SaveService.set_section(&"progress", {"xp": 120})  # A save from before the tutorial existed.
	await _open(true)
	await _hand_over()
	assert_int(_started.size()).is_equal(0)


func test_the_first_launch_starts_basics_upright_too() -> void:
	_profile = UiProfiles.portrait()[&"desktop_portrait"]
	await _open(true)
	await _hand_over()
	assert_array(_started).is_equal([&"basics"])


func test_a_menu_the_intro_did_not_make_starts_nothing() -> void:
	await _open(true, true)  # Loaded after a match: its stack is not waiting for an intro.
	await await_idle_frame()
	assert_int(_started.size()).is_equal(0)
	assert_bool(TutorialStart.first_launch_due()).is_true()


func test_a_menu_without_the_switch_or_with_progress_starts_nothing() -> void:
	await _open(false)
	await _hand_over()
	assert_int(_started.size()).is_equal(0)
	assert_bool(TutorialStart.first_launch_due()).is_true()
	_close()
	TutorialDirector.mark_done(&"basics")
	await _open(true)
	await _hand_over()
	assert_int(_started.size()).is_equal(0)


func test_a_pending_screen_means_no_first_launch_start() -> void:
	await _open(true, false, &"fake")
	await _hand_over()
	assert_int(_started.size()).is_equal(0)


func _hand_over() -> void:
	(_menu.get_node("MenuStack") as MenuStack).back_enabled = true
	await await_idle_frame()
	await await_idle_frame()


func _open(offer: bool, handed_over: bool = false, pending: StringName = &"") -> void:
	var profile: UiMetrics = _profile  # The banner's slot needs a known screen.
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
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
		return _result
	_menu.add_child(root)
	add_child(_menu)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null
