extends GdUnitTestSuite
## The Rank screen's PROGRESS section (plan P673e, ADR 0054 section 8): the wins grid equals the
## career numbers, a locked cell shows the lock and its rank, the stat lines equal the career, the
## two sections sit side by side exactly where the measured width fits (never by orientation), and
## nothing is clipped or past the safe area at the six sizes in both orientations.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5
const TICKS_PER_SECOND: int = 15

var _window_size_before: Vector2i
var _dir: String = ""
var _menu: Control
var _stack: MenuStack
var _screen: RankScreen
var _save: Node
var _progression: Node
var _maps: MapCatalog


func before() -> void:
	_window_size_before = get_window().size
	_maps = load(MapCatalog.DEFAULT_PATH) as MapCatalog


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_dir = "user://test_rank_progress_%d" % Time.get_ticks_usec()
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


func test_the_grid_cells_equal_the_career_and_a_locked_cell_shows_the_lock_and_its_rank() -> void:
	_save.call("set_section", &"progress", {"xp": 5000, "next_award_id": 8})
	(
		_save
		. call(
			"set_section",
			&"career",
			{
				"format": 1,
				"finished": 7,
				"wins": 5,
				"wins_grid": {"kestrel_flats": {"easy": 3, "hard": 1}, "map_2": {"normal": 1}},
			}
		)
	)
	var section: RankProgressSection = await _section(PackedStringArray())
	assert_str(_value(section, "Cell_kestrel_flats_easy")).is_equal("3")
	assert_str(_value(section, "Cell_kestrel_flats_normal")).is_equal("0")
	assert_str(_value(section, "Cell_kestrel_flats_hard")).is_equal("1")
	assert_str(_value(section, "Cell_map_2_normal")).is_equal("1")
	assert_bool(section.find_child("Lock", true, false) == null).is_true()
	# Back at rank 1 the second map (rank 2), the Hard level (rank 3) and the third map (rank 4)
	# are locked, and a cell shows the larger of its two ranks.
	_save.call("set_section", &"progress", {"xp": 0, "next_award_id": 8})
	section.refresh(_progression, _maps, PackedStringArray())
	await await_idle_frame()
	assert_str(_value(section, "Cell_kestrel_flats_easy")).is_equal("3")
	assert_str(_value(section, "Cell_kestrel_flats_hard")).is_equal("RANK\n3")
	assert_str(_value(section, "Cell_map_2_easy")).is_equal("RANK\n2")
	assert_str(_value(section, "Cell_map_2_hard")).is_equal("RANK\n3")
	var cell: Control = section.find_child("Cell_map_2_easy", true, false) as Control
	assert_object(cell.find_child("Lock", true, false)).is_not_null()
	assert_str(String(cell.theme_type_variation)).is_equal("MenuMapCardLocked")
	var open: Control = section.find_child("Cell_kestrel_flats_easy", true, false) as Control
	assert_str(String(open.theme_type_variation)).is_equal("MenuMapCardOn")
	assert_bool(open.find_child("Lock", true, false) == null).is_true()


func test_the_stat_lines_equal_the_career_and_the_lessons_come_from_the_save() -> void:
	(
		_save
		. call(
			"set_section",
			&"career",
			{
				"format": 1,
				"finished": 12,
				"wins": 5,
				"play_ticks": (3600 + 5 * 60) * TICKS_PER_SECOND,
				"best_win_ticks": (7 * 60 + 5) * TICKS_PER_SECOND,
			}
		)
	)
	var section: RankProgressSection = await _section(PackedStringArray(["basics", "air"]))
	assert_str(_stat(section, RankText.LESSONS)).is_equal("2 / 4")
	assert_str(_stat(section, RankText.MATCHES)).is_equal("12")
	assert_str(_stat(section, RankText.WINS)).is_equal("5")
	assert_str(_stat(section, RankText.TIME_PLAYED)).is_equal("1 h 05 min")
	assert_str(_stat(section, RankText.FASTEST_WIN)).is_equal("7:05")


func test_a_new_career_reads_zero_and_none_yet() -> void:
	var section: RankProgressSection = await _section(PackedStringArray())
	assert_str(_stat(section, RankText.LESSONS)).is_equal("0 / 4")
	assert_str(_stat(section, RankText.MATCHES)).is_equal("0")
	assert_str(_stat(section, RankText.WINS)).is_equal("0")
	assert_str(_stat(section, RankText.TIME_PLAYED)).is_equal("0 min 00 s")
	assert_str(_stat(section, RankText.FASTEST_WIN)).is_equal("None yet")
	assert_str(RankProgressSection.time_text(95 * TICKS_PER_SECOND)).is_equal("1 min 35 s")
	assert_str(RankProgressSection.fastest_text(59 * TICKS_PER_SECOND)).is_equal("0:59")


func test_every_control_of_the_section_lets_a_drag_through() -> void:
	var section: RankProgressSection = await _section(PackedStringArray())
	var seen: Array[Control] = []
	_controls(section, seen)
	assert_int(seen.size()).is_greater(20)
	for control: Control in seen:
		assert_int(control.mouse_filter).override_failure_message(str(control.name)).is_equal(
			Control.MOUSE_FILTER_PASS
		)


func test_the_sections_share_a_row_exactly_where_the_width_fits_at_the_six_sizes() -> void:
	var sides: Dictionary[bool, int] = {true: 0, false: 0}
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var pair: BoxContainer = _screen.find_child("Pair", true, false) as BoxContainer
		assert_object(pair).override_failure_message(label).is_not_null()
		var fits: bool = _fits()
		assert_bool(pair.vertical).override_failure_message(label).is_equal(not fits)
		sides[fits] += 1
		var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
		var column: Rect2 = _screen.column.get_global_rect()
		var room: float = _screen.column_room_px()
		assert_float(column.size.x).override_failure_message(label).is_less_equal(
			maxf(room, _screen.column.custom_minimum_size.x) + TOLERANCE_PX
		)
		var seen: Array[Control] = []
		_controls(_screen._progress, seen)
		for control: Control in seen:
			var rect: Rect2 = control.get_global_rect()
			var inside: bool = (
				rect.position.x >= column.position.x - TOLERANCE_PX
				and rect.end.x <= column.end.x + TOLERANCE_PX
				and rect.end.x <= safe.end.x
			)
			(
				assert_bool(inside)
				. override_failure_message(
					"%s: %s %s outside the column" % [label, control.name, rect]
				)
				. is_true()
			)
			if control is Label:
				var text: Label = control as Label
				(
					assert_float(text.size.x)
					. override_failure_message("%s: %s clipped" % [label, text.text])
					. is_greater_equal(text.get_combined_minimum_size().x - TOLERANCE_PX)
				)
		if fits:
			var left: Rect2 = (pair.get_child(0) as Control).get_global_rect()
			var right: Rect2 = (pair.get_child(1) as Control).get_global_rect()
			assert_float(left.end.x).override_failure_message(label).is_less_equal(
				right.position.x + TOLERANCE_PX
			)
		_close()
		UiScale.clear_override()
	assert_int(sides[true]).is_greater(0)
	assert_int(sides[false]).is_greater(0)


func test_the_pair_follows_the_window_as_it_turns_between_the_sizes() -> void:
	await _open(_profile_with_window(ScreenSizes.ALL[0]))
	var pair: BoxContainer = _screen.find_child("Pair", true, false) as BoxContainer
	var seen: Dictionary[bool, int] = {true: 0, false: 0}
	for size: Vector2i in ScreenSizes.ALL:
		var profile: UiMetrics = _profile_with_window(size)
		UiScale.set_override(profile)
		get_window().size = profile.window_size
		for _frame: int in range(3):
			await await_idle_frame()
		assert_bool(pair.vertical).override_failure_message(str(size)).is_equal(not _fits())
		seen[_fits()] += 1
	assert_int(seen[true]).is_greater(0)
	assert_int(seen[false]).is_greater(0)


## True where the safe width holds two sections and the gap (the screen's own rule).
func _fits() -> bool:
	return (
		_screen.column_room_px()
		>= 2.0 * UiScale.dp(RankScreen.SECTION_DP) + UiScale.dp(RankScreen.GAP_DP)
	)


func _section(lessons: PackedStringArray) -> RankProgressSection:
	var section: RankProgressSection = RankProgressSection.new()
	add_child(section)
	auto_free(section)
	section.refresh(_progression, _maps, lessons)
	await await_idle_frame()
	return section


func _value(section: Node, cell: String) -> String:
	var node: Node = section.find_child(cell, true, false)
	assert_object(node).override_failure_message(cell).is_not_null()
	return (node.find_child("Value", true, false) as Label).text


func _stat(section: Node, key: StringName) -> String:
	var node: Node = section.find_child("Stat_" + String(key), true, false)
	assert_object(node).override_failure_message(str(key)).is_not_null()
	return (node.find_child("Value", true, false) as Label).text


func _controls(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Control:
			into.append(child as Control)
		_controls(child, into)


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
	await await_idle_frame()
	# The trophies section (P673d) is the other half of the pair; a stand-in until it is merged.
	_screen._add_section(&"MAIN_NEXT", true)
	_screen._apply()
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	fail("no profile for %s" % size)
	return null
