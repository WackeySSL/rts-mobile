extends GdUnitTestSuite
## The Rank screen's Trophies part (plan P673d, ADR 0054 section 8): the heading count equals
## `earned_count()`, lit rows read EARNED, dim rows read their hint and progress, entering the
## screen stamps a back-filled lesson trophy, rows stay inside the column at the six sizes, are
## `MOUSE_FILTER_PASS`, and a missing glyph draws the frame alone.

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
	_dir = "user://test_rank_trophies_%d" % Time.get_ticks_usec()
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


func test_the_heading_count_equals_earned_count_and_there_is_a_row_per_trophy() -> void:
	_save.call("set_section", &"career", _career(7, 3, ["first_sortie", "ground_won"]))
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	var total: int = TrophyCatalog.load_default().trophies.size()
	assert_int(total).is_equal(16)
	assert_int(int(_progression.call("earned_count"))).is_equal(2)
	assert_array(_label_texts()).contains(["TROPHIES  2 / %d" % total])
	assert_int(_rows().size()).is_equal(total)


func test_lit_rows_read_earned_and_dim_rows_read_their_hint_and_progress() -> void:
	_save.call("set_section", &"career", _career(7, 3, ["first_sortie"]))
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_str(_text(&"first_sortie", &"Status")).is_equal("EARNED")
	assert_str(_text(&"long_haul", &"Hint")).is_equal("Finish 25 skirmishes")
	assert_str(_text(&"long_haul", &"Status")).is_equal("7/25")
	assert_str(_text(&"seasoned", &"Status")).is_equal("3/10")
	# A target of 1 shows no progress line.
	assert_object(_row(&"ironward_honours").get_child(1).get_node_or_null("Status")).is_null()
	assert_object(_row(&"iron_nerve").get_child(1).get_node_or_null("Status")).is_null()
	assert_bool((_row(&"first_sortie").get_child(0) as TrophyBadge).lit).is_true()
	assert_bool((_row(&"long_haul").get_child(0) as TrophyBadge).lit).is_false()


func test_entering_the_screen_stamps_a_back_filled_lesson_trophy() -> void:
	_save.call("set_section", &"tutorial", {"done": ["basics"]})
	assert_bool(bool(_progression.call("is_earned", &"briefed"))).is_false()
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_bool(bool(_progression.call("is_earned", &"briefed"))).is_true()
	assert_str(_text(&"briefed", &"Status")).is_equal("EARNED")


func test_rows_are_read_only_pass_through_and_back_stays_48_dp() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	for row: Node in _rows():
		assert_int((row as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
		assert_int((row.get_child(0) as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	assert_float(_screen.back_link.get_global_rect().size.y).is_greater_equal(
		UiScale.dp(48.0) - TOLERANCE_PX
	)


func test_every_row_is_inside_the_column_and_no_label_is_clipped_at_the_six_sizes() -> void:
	_save.call("set_section", &"career", _career(30, 12, ["first_sortie", "long_haul"]))
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var column: Rect2 = _screen.column.get_global_rect().grow(TOLERANCE_PX)
		for row: Node in _rows():
			(
				assert_bool(column.encloses((row as Control).get_global_rect()))
				. override_failure_message("%s %s" % [size, row.name])
				. is_true()
			)
		for label: Label in _labels(_screen.column):
			var need: float = label.get_minimum_size().y
			(
				assert_float(label.size.y)
				. override_failure_message("%s %s clipped" % [size, label.text])
				. is_greater_equal(need - TOLERANCE_PX)
			)
		_close()
		UiScale.clear_override()


func test_a_missing_glyph_draws_the_frame_alone() -> void:
	var badge: TrophyBadge = auto_free(TrophyBadge.new())
	(
		assert_error(func() -> void: badge.glyph = &"no_such_glyph_p673d")
		. is_push_warning(
			"TrophyBadge: no glyph file res://assets/art/svg/icons/no_such_glyph_p673d.svg; the frame alone"
		)
	)
	assert_object(badge._texture).is_null()
	badge.pips = 9
	assert_int(badge.pips).is_equal(TrophyCatalog.MAX_PIPS)


func test_progress_counts_a_counter_and_the_cells_of_a_grid() -> void:
	var career: CareerStats = CareerStats.new()
	career.finished = 40
	career.wins_grid = {"kestrel_flats": {"easy": 1}}
	var count: TrophyDef = TrophyDef.new()
	count.kind = TrophyDef.Kind.COUNT
	count.counter = &"finished"
	count.count = 25
	assert_vector(RankTrophySection.progress_of(count, career)).is_equal(Vector2i(25, 25))
	var grid: TrophyDef = TrophyDef.new()
	grid.kind = TrophyDef.Kind.WIN_GRID
	grid.map_ids = [&"kestrel_flats", &"heron_fords"]
	assert_vector(RankTrophySection.progress_of(grid, career)).is_equal(Vector2i(1, 2))
	var lessons: TrophyDef = TrophyDef.new()
	lessons.kind = TrophyDef.Kind.LESSONS
	assert_vector(RankTrophySection.progress_of(lessons, career)).is_equal(Vector2i.ZERO)


func _career(finished: int, wins: int, earned: Array) -> Dictionary:
	return {"format": 1, "finished": finished, "wins": wins, "earned": earned}


func _open(profile: UiMetrics) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_stack.push(MenuScreen.new())
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


func _rows() -> Array[Node]:
	var rows: Array[Node] = []
	for child: Node in _screen.column.get_children():
		for section: Node in child.get_children():
			if section is RankTrophySection:
				rows.assign(section.get_children())
	return rows


func _row(id: StringName) -> Node:
	for row: Node in _rows():
		if row.name == String(id):
			return row
	fail("no row %s" % id)
	return null


## The text of the label `label_name` in the row of trophy `id`.
func _text(id: StringName, label_name: StringName) -> String:
	return (_row(id).get_child(1).get_node(String(label_name)) as Label).text


func _label_texts() -> Array[String]:
	var texts: Array[String] = []
	for label: Label in _labels(_screen.column):
		texts.append(label.text)
	return texts


func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	if node is Label:
		found.append(node as Label)
	for child: Node in node.get_children():
		found.append_array(_labels(child))
	return found


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	fail("no profile for %s" % size)
	return null
