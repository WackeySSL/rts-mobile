extends GdUnitTestSuite
## The Rank screen (plan P664, ADR 0052 section 3): its content equals `Progression`'s, the next
## unlock in its three forms (a map, a computer opponent, nothing left), the XP bar following
## `xp_changed`, 48 dp targets inside the safe area at the six sizes, and BACK popping the stack.

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
var _screen: RankScreen
var _save: Node
var _progression: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_dir = "user://test_rank_screen_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_save = (load(SAVE_SCRIPT) as GDScript).new()
	_save.call("set_path_override", _dir.path_join("save.cfg"))
	_progression = (load(SERVICE_SCRIPT) as GDScript).new()
	_progression.call("bind", _save, null)


func after_test() -> void:
	UiScale.clear_override()
	_close()
	for node: Node in [_save, _progression]:
		if is_instance_valid(node):
			node.free()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func test_the_content_equals_progressions_numbers() -> void:
	_save.call("set_section", &"progress", {"xp": 100})
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	var texts: Array[String] = _label_texts()
	assert_array(texts).contains(["COMMANDER", "NEXT UNLOCK"])
	var rank: int = int(_progression.call("rank"))
	assert_str(_screen._rank_label.text).is_equal(
		"RANK %d  %s" % [rank, str(_progression.call("title", rank)).to_upper()]
	)
	assert_int(_screen._insignia.rank).is_equal(rank)
	assert_float(_screen._xp_bar.min_value).is_equal(float(_progression.call("rank_floor_xp")))
	assert_float(_screen._xp_bar.max_value).is_equal(float(_progression.call("next_rank_xp")))
	assert_float(_screen._xp_bar.value).is_equal(100.0)
	assert_str(_screen._xp_label.text).is_equal(
		"100 / %d XP" % int(_progression.call("next_rank_xp"))
	)


func test_the_next_unlock_names_a_map_an_opponent_then_runs_out() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_str(_screen._unlock_label.text).is_equal("Heron Fords at rank 2")
	_save.call("set_section", &"progress", {"xp": 100})
	_progression.emit_signal("xp_changed")
	assert_str(_screen._unlock_label.text).is_equal("Hard opponent at rank 3")
	_save.call("set_section", &"progress", {"xp": 5000})
	_progression.emit_signal("xp_changed")
	assert_str(_screen._unlock_label.text).is_equal("Everything is open.")
	assert_str(_screen._xp_label.text).is_equal("5000 XP")
	assert_float(_screen._xp_bar.value).is_equal(_screen._xp_bar.max_value)


func test_the_bar_at_a_rank_floor_is_empty_and_follows_xp_changed() -> void:
	_save.call("set_section", &"progress", {"xp": 250})
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_str(_screen._rank_label.text).contains("RANK 3")
	assert_float(_screen._xp_bar.value).is_equal(_screen._xp_bar.min_value)
	_save.call("set_section", &"progress", {"xp": 300})
	_progression.emit_signal("xp_changed")
	assert_float(_screen._xp_bar.value).is_equal(300.0)


func test_every_target_is_48_dp_and_inside_the_safe_area_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
		(
			assert_bool(safe.encloses(_screen.scroll.get_global_rect()))
			. override_failure_message(str(size))
			. is_true()
		)
		var column: Rect2 = _screen.column.get_global_rect()
		assert_float(column.end.x).override_failure_message(str(size)).is_less_equal(safe.end.x)
		var back: Button = _screen.back_link
		assert_bool(_screen.footer.visible).override_failure_message(str(size)).is_true()
		assert_float(back.get_global_rect().size.y).is_greater_equal(
			UiScale.dp(48.0) - TOLERANCE_PX
		)
		(
			assert_bool(safe.encloses(back.get_global_rect()))
			. override_failure_message(str(size))
			. is_true()
		)
		_close()
		UiScale.clear_override()


func test_the_back_link_pops_the_stack_and_a_section_lands_below_the_block() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	var before: int = _screen.column.get_child_count()
	_screen._add_section(&"MAIN_NEXT")
	assert_int(_screen.column.get_child_count()).is_equal(before + 2)
	assert_str(_screen.back_link.text).starts_with("\u2039 ")
	var depth: int = _stack.depth()
	_screen.back_link.pressed.emit()
	assert_int(_stack.depth()).is_equal(depth - 1)


func _open(profile: UiMetrics) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_stack.push(MenuScreen.new())  # Something below, so BACK has a screen to return to.
	_screen = RankScreen.new()
	_screen.progression = _progression
	_stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _label_texts() -> Array[String]:
	var texts: Array[String] = []
	_collect(_screen.column, texts)
	return texts


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
	fail("no profile for %s" % size)
	return null
