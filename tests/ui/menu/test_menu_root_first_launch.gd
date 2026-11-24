extends GdUnitTestSuite
## The first launch (plan row P544, ADR 0044 section 2): the menu root starts Basics once, after the
## intro has handed the menu over, and only where `offer_first_launch` is set (main_menu.tscn).

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const MAIN_MENU: String = "res://scenes/menu/main_menu.tscn"
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")

const FLOW: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")


## An ads service whose settle never returns: the start waits there for good.
class StuckAds:
	extends Node
	signal never

	func take_start_credits_bonus() -> int:
		return 0

	func settle_fullscreen() -> void:
		await never


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


## The scene the intro hands over to (`main_menu.tscn`, its own MenuRoot with the switch set) offers
## Basics on a fresh save, at the hand-over: the offer a menu test with no play history would start
## for real, here counted by a stub that loads no match.
func test_the_real_main_menu_scene_offers_basics_at_the_hand_over_on_a_fresh_save() -> void:
	var profile: UiMetrics = _profile
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MAIN_MENU) as PackedScene).instantiate()
	var root: MenuRoot = _menu.get_node("MenuRoot") as MenuRoot
	assert_bool(root.offer_first_launch).is_true()
	root.start_lesson = func(id: StringName) -> Error:
		_started.append(id)
		return OK
	(_menu.get_node("MenuStack") as MenuStack).back_enabled = false  # The intro's doing.
	add_child(_menu)
	await await_idle_frame()
	assert_int(_started.size()).is_equal(0)
	await _hand_over()
	assert_array(_started).is_equal([&"basics"])
	_close()
	MenuRoutes.shared.clear()  # The menu registered the app's routes in the shared table.


## P450: through the real MenuRoot path, the DeployCard is up as soon as the intro hands over,
## though the ads settle never returns.
func test_the_deploy_card_shows_at_the_hand_over_whatever_the_ads_settle_does() -> void:
	UiScale.set_override(_profile)
	get_window().size = _profile.window_size
	await await_idle_frame()
	var ads: StuckAds = auto_free(StuckAds.new())
	add_child(ads)
	var flow: Node = auto_free(FLOW.new())
	add_child(flow)
	flow.ads = ads
	var card: DeployCard = auto_free(DeployCard.new())
	add_child(card)
	card.attach(flow)
	_menu = (load(MAIN_MENU) as PackedScene).instantiate()
	var root: MenuRoot = _menu.get_node("MenuRoot") as MenuRoot
	root.start_lesson = func(id: StringName) -> Error: return await TutorialStart.start(flow, id)
	(_menu.get_node("MenuStack") as MenuStack).back_enabled = false
	add_child(_menu)
	await await_idle_frame()
	assert_bool(card.is_showing()).override_failure_message("before the hand-over").is_false()
	await _hand_over()
	assert_bool(card.is_showing()).override_failure_message("after the hand-over").is_true()
	_close()
	MenuRoutes.shared.clear()


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
