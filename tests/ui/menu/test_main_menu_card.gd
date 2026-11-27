extends GdUnitTestSuite
## The main menu's list and commander card (plan P664, ADR 0052 section 3): the numbered items, the
## card beside the list only where the measured width holds both (never by orientation), the
## card's numbers equal `Progression`'s, the next unlock in words, and no "LEVEL" in the text.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _dir: String = ""
var _menu: Control
var _stack: MenuStack
var _main: MainMenu
var _save: Node
var _progression: Node
var _routes: MenuRoutes
var _resume: Array[bool] = [false]


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_dir = "user://test_main_menu_card_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_save = (load(SAVE_SCRIPT) as GDScript).new()
	_save.call("set_path_override", _dir.path_join("save.cfg"))
	_progression = (load(SERVICE_SCRIPT) as GDScript).new()
	_progression.call("bind", _save, null)
	_routes = MenuRoutes.new()
	_resume[0] = false


func after_test() -> void:
	UiScale.clear_override()
	_close()
	MenuRoutes.shared.clear()
	for node: Node in [_save, _progression]:
		if is_instance_valid(node):
			node.free()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func test_the_items_are_numbered_in_order_and_continue_renumbers() -> void:
	_routes.register(MenuRoutes.SKIRMISH, MenuScreen.new)
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var words: Array[String] = []
	for item: Button in _main.items():
		words.append(item.text)
	assert_array(words).is_equal(["SKIRMISH", "TUTORIAL", "HOW TO PLAY", "SETTINGS"])
	assert_array(_numbers()).is_equal(["01", "02", "03", "04"])
	_resume[0] = true
	_main._refresh()
	assert_array(_numbers()).is_equal(["01", "02", "03", "04", "05"])
	assert_str(_main.items()[0].text).is_equal("CONTINUE")
	assert_str(_main.items()[0].theme_type_variation).is_equal("MenuRowOn")
	assert_str(_main.items()[1].theme_type_variation).is_equal("MenuRow")


func test_the_card_is_beside_the_items_only_where_the_measured_width_holds_both() -> void:
	var beside: int = 0
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var list: Rect2 = _main._list.get_global_rect()
		var card: Rect2 = _main._card.get_global_rect()
		var fits: bool = _main.column_room_px() >= UiScale.dp(MainMenu.TWO_COLUMNS_DP)
		beside += 1 if fits else 0
		if fits:
			assert_float(card.position.x).override_failure_message(str(size)).is_greater_equal(
				list.end.x - TOLERANCE_PX
			)
		else:
			assert_float(card.end.y).override_failure_message(str(size)).is_less_equal(
				list.position.y + TOLERANCE_PX
			)
		# The text sits on the picture's dark side: the left edge (landscape) or the top (portrait).
		assert_float(_main.column.get_global_rect().position.x).is_less_equal(
			UiScale.dp(MenuScreen.GAP_DP) * 2.0
		)
		_close()
		UiScale.clear_override()
	assert_int(beside).is_greater(0)
	assert_int(beside).is_less(ScreenSizes.ALL.size())


func test_the_card_shows_the_numbers_of_progression() -> void:
	_save.call("set_section", &"progress", {"xp": 100})
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_str(_main._rank_label.text).contains("RANK %d" % int(_progression.call("rank")))
	assert_str(_main._rank_label.text).contains(str(_progression.call("title", 2)).to_upper())
	assert_int(_main._insignia.rank).is_equal(int(_progression.call("rank")))
	assert_float(_main._xp_bar.min_value).is_equal(float(_progression.call("rank_floor_xp")))
	assert_float(_main._xp_bar.max_value).is_equal(float(_progression.call("next_rank_xp")))
	assert_str(_main._unlock_label.text).is_equal("Hard opponent at rank 3")


func test_the_next_unlock_names_a_map_then_runs_out() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_str(_main._unlock_label.text).is_equal("Heron Fords at rank 2")
	_save.call("set_section", &"progress", {"xp": 5000})
	_main._refresh()
	assert_str(_main._unlock_label.text).is_equal("Everything is open.")


func test_the_menu_text_never_says_level() -> void:
	_resume[0] = true
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var texts: Array[String] = []
	_collect(_main.column, texts)
	for button: Button in _main.items():
		texts.append(button.text)
	for text: String in texts:
		assert_bool(text.to_upper().contains("LEVEL")).override_failure_message(text).is_false()


func _numbers() -> Array[String]:
	var found: Array[String] = []
	for button: Button in _main.items():
		found.append(_main._numbers[button].text)
	return found


func _open(profile: UiMetrics) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_main = MainMenu.new()
	_main.routes = _routes
	_main.progression = _progression
	_main.resume_check = func() -> bool: return _resume[0]
	_main.take_notice = func() -> StringName: return &""
	_stack.push(_main)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _collect(node: Node, into: Array[String]) -> void:
	if node is Label:
		into.append((node as Label).text)
	for child: Node in node.get_children():
		_collect(child, into)


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
