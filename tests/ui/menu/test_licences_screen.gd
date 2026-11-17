extends GdUnitTestSuite
## The Licences screen (plan P529, ADR 0043 section 7): the rows the build decides, the texts, and
## at the six sizes of ADR 0015 section 6 the column inside the safe rect with 48 dp buttons, a long
## text scrolling, back from a text to the list and from the list popping, no banner.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = false
var _menu: Control
var _stack: MenuStack
var _screen: LicencesScreen


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func test_the_catalog_lists_the_engine_the_fonts_the_assets_and_the_plugins() -> void:
	var titles: Array[String] = _titles(_catalog(false, false))
	for expected: String in [
		"Game art and audio",
		"Asset credits (CC BY)",
		"Godot Engine",
		"Godot copyright",
		"Big Shoulders font",
		"Chakra Petch font",
		"Poing AdMob plugin",
	]:
		assert_array(titles).contains([expected])
	# Every text the engine reports is a row.
	for license_name: String in Engine.get_license_info():
		assert_array(titles).contains([license_name])


func test_the_play_billing_row_shows_only_once_its_text_file_exists() -> void:
	# TODO P411: when the file lands this flips; then assert the row and its text instead.
	var file: String = LicenceCatalog.LICENCES_DIR + LicenceCatalog.PLAY_BILLING
	var shown: bool = _titles(_catalog(false, false)).has("Google Play Billing plugin")
	assert_bool(shown).is_equal(FileAccess.file_exists(file))


func test_the_engine_texts_are_the_engines_own() -> void:
	var rows: Array[LicenceEntry] = _catalog(false, false).build()
	assert_str(_row(rows, "Godot Engine").text).is_equal(Engine.get_license_text())
	assert_str(_row(rows, "Godot copyright").text).contains("Copyright:")


func test_libcxx_shows_on_android_only() -> void:
	assert_array(_titles(_catalog(false, false))).not_contains(["LLVM libc++"])
	var rows: Array[LicenceEntry] = _catalog(true, false).build()
	assert_str(_row(rows, "LLVM libc++").text).contains("LLVM Exceptions")


func test_godot_cpp_shows_exactly_when_the_build_has_the_kernels() -> void:
	assert_array(_titles(_catalog(false, false))).not_contains(["godot-cpp"])
	var rows: Array[LicenceEntry] = _catalog(false, true).build()
	assert_str(_row(rows, "godot-cpp").text).contains("MIT")
	# Whether the library loads is not asked: the row follows the build fact only.
	assert_array(_titles(_catalog(true, true))).contains(["godot-cpp"])


func test_the_build_facts_come_from_the_feature_tags_and_the_editor() -> void:
	var from_build: LicenceCatalog = LicenceCatalog.from_build()
	assert_bool(from_build.android).is_equal(OS.has_feature("android"))
	var kernels: bool = OS.has_feature("sim_kernels") or OS.has_feature("editor")
	assert_bool(from_build.kernels).is_equal(kernels)


func test_both_ofl_texts_and_the_poing_text_are_real() -> void:
	var rows: Array[LicenceEntry] = _catalog(false, false).build()
	for font: String in ["Big Shoulders font", "Chakra Petch font"]:
		assert_str(_row(rows, font).text).contains("SIL Open Font License")
	assert_str(_row(rows, "Poing AdMob plugin").text).contains("MIT")


func test_the_asset_licence_and_the_cc_by_credits() -> void:
	var rows: Array[LicenceEntry] = _catalog(false, false).build()
	assert_str(_row(rows, "Game art and audio").text).contains("All rights reserved")
	var table: String = (
		"| File | Author | Source | Licence | Notes |\n| --- | --- | --- | --- | --- |\n"
		+ "| a.ogg | Ann | https://x | CC BY 4.0 | n |\n| b.ogg | Bob | https://y | CC0 | n |\n"
	)
	var credits: String = _catalog(false, false).credit_lines(table)
	assert_str(credits).contains("a.ogg")
	assert_str(credits).contains("Ann")
	assert_str(credits).not_contains("b.ogg")
	assert_str(_catalog(false, false).credit_lines("")).is_equal(LicenceCatalog.NO_CREDITS)
	# The real CREDITS.md lists the engine logo, which is CC BY 4.0.
	assert_str(_row(rows, "Asset credits (CC BY)").text).contains("Andrea Calabr")


func test_the_list_and_a_text_stay_in_the_safe_area_with_big_targets_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), _catalog(true, true))
		_assert_fits(str(size) + " list")
		assert_bool(_screen.slot.has_band()).is_false()
		assert_float(_screen.slot.size.y).is_equal_approx(0.0, 0.01)
		_buttons()[0].pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		assert_object(_screen.open_entry).is_not_null()
		_assert_fits(str(size) + " text")
		_close()
		UiScale.clear_override()


func test_a_long_text_scrolls_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), _catalog(true, true))
		_open_row("Godot copyright")
		await await_idle_frame()
		await await_idle_frame()
		var bar: VScrollBar = _screen.scroll.get_v_scroll_bar()
		var label: String = str(size)
		assert_float(bar.max_value).override_failure_message(label).is_greater(bar.page)
		_screen.scroll.scroll_vertical = int(bar.max_value)
		await await_idle_frame()
		assert_int(_screen.scroll.scroll_vertical).override_failure_message(label).is_greater(0)
		_close()
		UiScale.clear_override()


func test_back_leaves_a_text_for_the_list_and_the_list_for_the_menu_below() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), _catalog(false, false))
	assert_int(_stack.depth()).is_equal(2)
	_buttons()[0].pressed.emit()
	await await_idle_frame()
	assert_object(_screen.open_entry).is_not_null()
	_stack.back()
	await await_idle_frame()
	assert_object(_screen.open_entry).is_null()
	assert_int(_stack.depth()).is_equal(2)
	_stack.back()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)


func test_the_back_button_of_the_list_pops() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), _catalog(false, false))
	_buttons().back().pressed.emit()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)


func test_a_text_is_cut_into_chunks_that_keep_every_character() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]), _catalog(false, false))
	var paragraph: String = "x".repeat(900)
	var text: String = "\n\n".join(PackedStringArray([paragraph, paragraph, paragraph, "end"]))
	var chunks: PackedStringArray = _screen._chunks(text)
	assert_int(chunks.size()).is_equal(2)
	assert_str("\n\n".join(chunks)).is_equal(text)


func test_one_paragraph_longer_than_a_chunk_stays_whole_on_its_own() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]), _catalog(false, false))
	var long_paragraph: String = "y".repeat(LicencesScreen.CHUNK_CHARS + 500)
	var chunks: PackedStringArray = _screen._chunks("a\n\n" + long_paragraph + "\n\nb")
	assert_int(chunks.size()).is_equal(3)
	assert_str(chunks[1]).is_equal(long_paragraph)


func _catalog(android: bool, kernels: bool) -> LicenceCatalog:
	var catalog: LicenceCatalog = LicenceCatalog.new()
	catalog.android = android
	catalog.kernels = kernels
	return catalog


func _titles(catalog: LicenceCatalog) -> Array[String]:
	var titles: Array[String] = []
	for row: LicenceEntry in catalog.build():
		titles.append(row.title)
	return titles


func _row(rows: Array[LicenceEntry], title: String) -> LicenceEntry:
	for row: LicenceEntry in rows:
		if row.title == title:
			return row
	return LicenceEntry.new()


## Presses the list button of the row with `title`.
func _open_row(title: String) -> void:
	for button: Button in _buttons():
		if button.text == title.to_upper():
			button.pressed.emit()
			return


func _column_across(column: Control) -> Rect2:
	return column.get_global_rect().intersection(_screen.scroll.get_global_rect())


func _assert_fits(label: String) -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	(
		assert_bool(safe.grow(TOLERANCE_PX).encloses(_column_across(_screen.column)))
		. override_failure_message(label)
		. is_true()
	)
	(
		assert_bool(safe.grow(TOLERANCE_PX).encloses(_screen.scroll.get_global_rect()))
		. override_failure_message(label + " scroll")
		. is_true()
	)
	var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
	for button: Button in _buttons():
		(
			assert_float(button.get_global_rect().size.y)
			. override_failure_message(label)
			. is_greater_equal(floor_px)
		)
	for child: Node in _screen.column.get_children():
		(
			assert_float((child as Control).get_global_rect().size.x)
			. override_failure_message(label)
			. is_less_equal(safe.size.x + TOLERANCE_PX)
		)


func _buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in _screen.column.get_children():
		if child is Button and not child.is_queued_for_deletion():
			found.append(child as Button)
	return found


func _open(profile: UiMetrics, catalog: LicenceCatalog) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_stack.push(MenuScreen.new())
	await await_idle_frame()
	_screen = LicencesScreen.new()
	_screen.catalog = catalog
	_stack.push(_screen)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
