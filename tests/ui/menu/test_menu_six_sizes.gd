extends GdUnitTestSuite
## Every menu screen at the six sizes of ADR 0015 section 6 and at every profile's portrait twin
## (plan P534, P562): the main menu, the map select, Settings, How to play (the list, a real
## section and a long one), Licences (the list and a long text) and the Tutorial screen (pushed
## over the main menu, as MenuRoutes.TUTORIAL does). On each one at each size:
## - every button and slider is 48 dp or more in both directions;
## - the column and the scroll are inside the safe rect, and no control of the column runs past its
##   left or right edge (no horizontal overflow);
## - a screen whose content is taller than its scroll scrolls (the bar has a range, the foot of
##   the content can be brought into view) and one that fits does not.
## Turning the device on each screen (the pairs of ADR 0015 section 6 and the notch design, both
## ways) keeps the MenuStack depth, the screen, its open section or text and the scroll position
## (as far as the turned layout's range allows), and the layout checks hold again after the turn.
## Not covered: the result screen is a modal of the match HUD (`ModalFrame`), not a menu screen;
## its sizes are in test_result_screen.gd.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const UiStateGuard: GDScript = preload("res://tests/support/ui_state_guard.gd")
const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const TOLERANCE_PX: float = 0.5
const TOUCH_DP: float = 48.0
const SETTLE_FRAMES: int = 2
const MAIN: StringName = &"main"
const MAP_SELECT: StringName = &"map_select"
const SETTINGS: StringName = &"settings"
const HOW_LIST: StringName = &"how_to_play_list"
const HOW_REAL_SECTION: StringName = &"how_to_play_real_section"
const HOW_LONG_SECTION: StringName = &"how_to_play_long_section"
const LICENCES_LIST: StringName = &"licences_list"
const LICENCES_TEXT: StringName = &"licences_text"
const TUTORIAL: StringName = &"tutorial"
## The profile whose safe width is narrower than the side row: its names wrap. P607 re-pin: the
## names IRONWARD and FACET are shorter than DERRICK LEAGUE and LUMEN ACCORD, so the row fits at
## every size and none wraps. A later longer name sets it again (the wrap branch below stays).
const WRAPPING_PROFILE: StringName = &""
## Profiles whose row is wider than the asked column but fits the safe width: the column grows.
## P607 re-pin: empty, for the same reason (it was web_phone, web_phone_small, notch_design).
const GROWN_PROFILES: Array[StringName] = []
const LONG_TEXT_ROW: String = "GODOT COPYRIGHT"

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _menu: Control
var _stack: MenuStack
var _screen: MenuScreen
## The screen under the open one when the kind is pushed over the main menu (TUTORIAL), else null.
var _root: MenuScreen = null
var _rank: Node
var _flow: Node
var _save: Node
var _progression: Node
## Set by the store-row tests: the AdService stand-in Settings talks to (null: the autoload).
var _store: CountingPurchaseService = null


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	PrefsRig.begin()
	_rank = FakeRank.new()
	_flow = FakeFlow.new()
	_save = (load(SAVE_SCRIPT) as GDScript).new()
	_save.call("set_path_override", PrefsRig.dir().path_join("six_sizes_save.cfg"))
	_progression = (load(SERVICE_SCRIPT) as GDScript).new()
	_progression.call("bind", _save, null)


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	_close()
	UiStateGuard.restore(get_window(), _window_size_before)
	for node: Node in [_rank, _flow, _progression, _save]:
		if is_instance_valid(node):
			node.free()
	PrefsRig.end()


func test_the_profiles_cover_the_six_sizes_and_their_portrait_twins() -> void:
	var windows: Array[Vector2i] = []
	for profile_name: StringName in _profile_names():
		windows.append(UiProfiles.by_name(profile_name).window_size)
	for size: Vector2i in ScreenSizes.ALL:
		assert_array(windows).override_failure_message(str(size)).contains([size])
	var portrait: int = 0
	for window: Vector2i in windows:
		portrait += 1 if window.y > window.x else 0
	assert_int(portrait).is_greater_equal(ScreenSizes.PORTRAIT.size())


func test_the_main_menu_fits_at_every_size() -> void:
	await _check_every_size(MAIN, false)


func test_the_map_select_fits_at_every_size() -> void:
	await _check_every_size(MAP_SELECT, false)


func test_settings_fits_at_every_size() -> void:
	await _check_every_size(SETTINGS, false)


func test_the_how_to_play_list_fits_at_every_size() -> void:
	await _check_every_size(HOW_LIST, false)


func test_a_real_how_to_play_section_fits_at_every_size() -> void:
	await _check_every_size(HOW_REAL_SECTION, false)


func test_a_long_how_to_play_section_scrolls_at_every_size() -> void:
	await _check_every_size(HOW_LONG_SECTION, true)


func test_the_licences_list_fits_at_every_size() -> void:
	await _check_every_size(LICENCES_LIST, false)


func test_a_long_licence_text_scrolls_at_every_size() -> void:
	await _check_every_size(LICENCES_TEXT, true)


func test_the_side_names_wrap_only_where_the_row_does_not_fit_and_stay_centred_otherwise() -> void:
	for profile_name: StringName in _profile_names():
		await _open(MAIN, UiProfiles.by_name(profile_name))
		var names: Array[Label] = _side_names()
		var wraps: bool = profile_name == WRAPPING_PROFILE
		for label: Label in names:
			var lines: int = label.get_line_count()
			(
				assert_bool(lines >= 1 and lines <= (2 if wraps else 1))
				. override_failure_message("%s: %s on %d lines" % [profile_name, label.text, lines])
				. is_true()
			)
		if wraps:
			var wrapped: int = 0
			for label: Label in names:
				wrapped += 1 if label.get_line_count() == 2 else 0
			assert_int(wrapped).override_failure_message("nothing wraps").is_greater(0)
		else:
			if GROWN_PROFILES.has(profile_name):
				var grown: Rect2 = _screen.column.get_global_rect()
				var safe: Rect2 = UiScale.safe_rect_base()
				(
					assert_float(grown.size.x)
					. override_failure_message("%s: column did not grow" % profile_name)
					. is_greater(_screen.column.custom_minimum_size.x)
				)
				(
					assert_bool(
						(
							grown.position.x >= safe.position.x - TOLERANCE_PX
							and grown.end.x <= safe.end.x + TOLERANCE_PX
						)
					)
					. override_failure_message(
						"%s: column %s, safe %s" % [profile_name, grown, safe]
					)
					. is_true()
				)
			var row: Control = names[0].get_parent() as Control
			var column: Rect2 = _screen.column.get_global_rect()
			var left: float = row.get_child(0).get_global_rect().position.x - column.position.x
			var right: float = column.end.x - names[1].get_global_rect().end.x
			(
				assert_float(absf(left - right))
				. override_failure_message(
					"%s: slack left %.1f, right %.1f" % [profile_name, left, right]
				)
				. is_less_equal(1.5)
			)
		_close()
		UiScale.clear_override()


func test_a_late_store_answer_or_a_late_unavailable_store_moves_nothing_in_settings() -> void:
	for price: String in ["kr 19,00", ""]:  # An answer, then "unavailable".
		for profile: UiMetrics in _late_answer_profiles():
			await _late_answer(profile, price)


## The six sizes, then the 6-inch phone with the design's safe-area insets, landscape and portrait.
func _late_answer_profiles() -> Array[UiMetrics]:
	var profiles: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		profiles.append(_profile_with_window(size))
	var notch: Dictionary[StringName, UiMetrics] = UiProfiles.notch_design()
	profiles.append(notch[&"notch_design"])
	profiles.append(notch[&"notch_design_portrait"])
	return profiles


## Settings opens while the store has not answered; then it answers (`price` empty: unavailable).
## The reserved buttons are 48 dp, and the rects, the scroll range and the content height stay.
func _late_answer(profile: UiMetrics, price: String) -> void:
	var label: String = "%s %s -> %s" % [profile.window_size, profile.safe_area, price]
	_store = auto_free(CountingPurchaseService.new())
	_store.answer("")
	_store.state = Purchases.StoreState.UNKNOWN  # The store has not answered yet.
	await _open(SETTINGS, profile)
	var rows: RemoveAdsRows = _store_rows()
	var answering: Array[Rect2] = _rects_from(rows)
	var bar: VScrollBar = _screen.scroll.get_v_scroll_bar()
	var content: Control = _screen.scroll.get_child(0) as Control
	var range_before: float = bar.max_value
	var height_before: float = content.size.y
	assert_bool(rows.visible).override_failure_message(label).is_true()
	for index: int in range(2):
		assert_float(answering[index].size.y).override_failure_message(label).is_greater_equal(
			UiScale.dp(TOUCH_DP) - TOLERANCE_PX
		)
	_store.answer(price)
	rows.refresh()
	await _settle()
	_assert_rects(answering, _rects_from(rows), label)
	assert_float(bar.max_value).override_failure_message(label + " range").is_equal(range_before)
	assert_float(content.size.y).override_failure_message(label + " content").is_equal(
		height_before
	)
	assert_bool(rows.remove_button.flat).is_equal(price.is_empty())
	_close()
	UiScale.clear_override()
	_store = null


func test_a_store_unavailable_at_open_collapses_the_rows_at_every_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_store = auto_free(CountingPurchaseService.new())
		_store.answer("kr 19,00")
		await _open(SETTINGS, _profile_with_window(size))
		var rows: RemoveAdsRows = _store_rows()
		var slot: Control = rows.get_parent() as Control
		var shown: Array[Rect2] = _rects_from(rows)
		var reserved_h: float = slot.size.y
		_close()
		_store.answer("")
		await _open(SETTINGS, _profile_with_window(size))
		rows = _store_rows()
		slot = rows.get_parent() as Control
		var label: String = str(size)
		assert_bool(slot.visible).override_failure_message(label).is_false()
		assert_bool(rows.visible).override_failure_message(label).is_false()
		var collapsed: Array[Rect2] = _rects_from(rows)
		assert_int(collapsed.size()).override_failure_message(label).is_equal(shown.size() - 2)
		var rise: float = reserved_h + roundf(UiScale.dp(MenuScreen.GAP_DP))
		for index: int in collapsed.size():
			var before: Rect2 = shown[index + 2]
			(
				assert_float(before.position.y - collapsed[index].position.y)
				. override_failure_message(label)
				. is_equal_approx(rise, TOLERANCE_PX)
			)
		_close()
		UiScale.clear_override()
		_store = null


func test_turning_the_device_keeps_the_stack_on_every_short_screen() -> void:
	for kind: StringName in [
		MAIN, MAP_SELECT, SETTINGS, HOW_LIST, HOW_REAL_SECTION, LICENCES_LIST, TUTORIAL
	]:
		await _check_turns(kind, false)


func test_turning_the_device_on_a_long_how_to_play_section_keeps_the_scroll() -> void:
	await _check_turns(HOW_LONG_SECTION, true)


func test_turning_the_device_on_a_long_licence_text_keeps_the_scroll() -> void:
	await _check_turns(LICENCES_TEXT, true)


## Tutorial scrolls where its column is taller than the window; at least one covered size must
## scroll, or the turn test above would never hold a position.
func test_the_tutorial_screen_fits_at_every_size_and_keeps_its_scroll_through_a_turn() -> void:
	await _check_every_size(TUTORIAL, false)
	# It scrolls only where the window is short: the small landscape phones. A short portrait
	# window (the phone's safe area cut down) gives a second scrolling size for the other way.
	# P605 re-pin: Inter wraps the lesson text into fewer lines than Chakra Petch did, so the column
	# is a little shorter and android_6in (719 dp page) no longer scrolls; notch_design (the same
	# window with the design's insets) still does (73 px), so the turn starts from that one.
	var landscape: UiMetrics = UiProfiles.by_name(&"notch_design")
	var upright: UiMetrics = _profile_with_window(
		Vector2i(landscape.window_size.y, landscape.window_size.x)
	)
	var short: UiMetrics = UiProfiles.with_safe_area(
		upright, Rect2i(0, 0, upright.window_size.x, 460)
	)
	var kept_same: int = await _scroll_through_turn(landscape, short, "landscape -> short")
	var clamped: int = await _scroll_through_turn(short, landscape, "short -> landscape")
	# A scroll that fits both is kept as it was; one that no longer fits is cut to the new range.
	assert_int(kept_same).override_failure_message("landscape -> short").is_greater(0)
	assert_int(clamped).override_failure_message("short -> landscape").is_greater(0)


## Tutorial over the main menu at `from`, scrolled to its foot, turned to `to`: the stack is still
## main menu -> Tutorial and the scroll is the same, or the new maximum when that shrank.
## Returns the position it ended at (the test demands it is not 0: a held one).
func _scroll_through_turn(from: UiMetrics, to: UiMetrics, label: String) -> int:
	await _open(TUTORIAL, from)
	var screen: MenuScreen = _screen
	var scroll: ScrollContainer = _screen.scroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	scroll.scroll_vertical = maxi(floori(bar.max_value - bar.page), 0)
	await await_idle_frame()
	var kept: int = scroll.scroll_vertical
	assert_int(kept).override_failure_message(label + " scrolled").is_greater(0)
	await _turn(to)
	_assert_same_stack(label + " turned", screen, 2, TUTORIAL)
	var expected: int = mini(kept, maxi(floori(bar.max_value - bar.page), 0))
	(
		assert_int(scroll.scroll_vertical)
		. override_failure_message("%s: kept %d, expected %d" % [label, kept, expected])
		. is_equal(expected)
	)
	var ended: int = scroll.scroll_vertical
	_close()
	UiScale.clear_override()
	return ended


## The kind at every profile: the layout checks; `must_scroll` also demands a scroll range.
func _check_every_size(kind: StringName, must_scroll: bool) -> void:
	for profile_name: StringName in _profile_names():
		await _open(kind, UiProfiles.by_name(profile_name))
		var label: String = _label(kind, profile_name)
		assert_int(_stack.depth()).override_failure_message(label).is_equal(_depth_of(kind))
		var scrolls: bool = await _assert_layout(label)
		if must_scroll:
			assert_bool(scrolls).override_failure_message(label + " must scroll").is_true()
		_close()
		UiScale.clear_override()


## The kind turned between each pair of sizes, both ways. `must_hold` demands that at least one
## turn had a scroll position to keep (a long screen), so the check is not vacuous.
func _check_turns(kind: StringName, must_hold: bool) -> void:
	var held: int = 0
	for pair: Array in _turn_pairs():
		for flip: int in range(2):
			var from: UiMetrics = pair[flip]
			var to: UiMetrics = pair[1 - flip]
			var label: String = "%s %s -> %s" % [kind, from.window_size, to.window_size]
			await _open(kind, from)
			var screen: MenuScreen = _screen
			var depth: int = _stack.depth()
			var scroll: ScrollContainer = _screen.scroll
			var bar: VScrollBar = scroll.get_v_scroll_bar()
			scroll.scroll_vertical = floori((bar.max_value - bar.page) / 2.0)
			await await_idle_frame()
			var kept: int = scroll.scroll_vertical
			await _turn(to)
			_assert_same_stack(label + " turned", screen, depth, kind)
			var range_to: int = maxi(floori(bar.max_value - bar.page), 0)
			var expected: int = mini(kept, range_to)
			(
				assert_int(scroll.scroll_vertical)
				. override_failure_message("%s scroll %d, range %d" % [label, kept, range_to])
				. is_equal(expected)
			)
			if kept > 0 and expected > 0:
				held += 1
			await _assert_layout(label + " turned")
			await _turn(from)
			_assert_same_stack(label + " turned back", screen, depth, kind)
			(
				assert_int(scroll.scroll_vertical)
				. override_failure_message(
					(
						"%s scroll back: %d, kept %d, then %d"
						% [label, scroll.scroll_vertical, kept, expected]
					)
				)
				. is_equal(expected)
			)
			_close()
			UiScale.clear_override()
	if must_hold:
		assert_int(held).override_failure_message(kind + " held no scroll").is_greater(0)


func _assert_same_stack(label: String, screen: MenuScreen, depth: int, kind: StringName) -> void:
	assert_int(_stack.depth()).override_failure_message(label + " depth").is_equal(depth)
	assert_bool(_stack.current() == screen).override_failure_message(label + " screen").is_true()
	(
		assert_bool(is_instance_valid(screen) and screen.is_inside_tree())
		. override_failure_message(label + " in tree")
		. is_true()
	)
	if screen is HowToPlayScreen:
		var open: bool = kind == HOW_REAL_SECTION or kind == HOW_LONG_SECTION
		(
			assert_bool((screen as HowToPlayScreen).open_section != null)
			. override_failure_message(label + " section")
			. is_equal(open)
		)
	if kind == TUTORIAL:
		(
			assert_bool(_stack._screens.size() == 2 and _stack._screens[0] == _root)
			. override_failure_message(label + " main menu below")
			. is_true()
		)
		assert_bool(_root is MainMenu).override_failure_message(label + " root").is_true()
		assert_bool(screen is TutorialScreen).override_failure_message(label + " top").is_true()
	if screen is LicencesScreen:
		(
			assert_bool((screen as LicencesScreen).open_entry != null)
			. override_failure_message(label + " text")
			. is_equal(kind == LICENCES_TEXT)
		)


## The layout checks on the open screen. Returns whether its content scrolls.
func _assert_layout(label: String) -> bool:
	var safe: Rect2 = UiScale.safe_rect_base()
	var view: Rect2 = _screen.scroll.get_global_rect()
	var column: Control = _screen.column
	(
		assert_bool(safe.grow(TOLERANCE_PX).encloses(view))
		. override_failure_message("%s: scroll %s outside the safe rect %s" % [label, view, safe])
		. is_true()
	)
	var across: Rect2 = column.get_global_rect().intersection(view)
	(
		assert_bool(safe.grow(TOLERANCE_PX).encloses(across))
		. override_failure_message("%s: column %s outside the safe rect %s" % [label, across, safe])
		. is_true()
	)
	var asked: float = _asked_column_px()
	(
		assert_float(column.size.x)
		. override_failure_message(
			"%s: column %.1f px wide, asked for %.1f" % [label, column.size.x, asked]
		)
		. is_less_equal(asked + TOLERANCE_PX)
	)
	var floor_px: float = UiScale.dp(TOUCH_DP) - TOLERANCE_PX
	var controls: Array[Control] = []
	_collect(column, controls)
	for control: Control in controls:
		var rect: Rect2 = control.get_global_rect()
		var overflow: bool = (
			rect.position.x < safe.position.x - TOLERANCE_PX
			or rect.end.x > safe.end.x + TOLERANCE_PX
		)
		(
			assert_bool(overflow)
			. override_failure_message(
				"%s: %s %s runs past the safe width %s" % [label, control.name, rect, safe]
			)
			. is_false()
		)
		if control is BaseButton or control is Slider:
			var small: bool = rect.size.x < floor_px or rect.size.y < floor_px
			(
				assert_bool(small)
				. override_failure_message(
					(
						"%s: %s %s is under 48 dp (%.1f px)"
						% [label, control.name, rect.size, floor_px]
					)
				)
				. is_false()
			)
	return await _assert_scroll(label, controls)


## The column's asked width: its minimum, or on the main menu the side row's compact width where
## that is wider (the column grows to a row that fits the safe width, never past it).
func _asked_column_px() -> float:
	var asked: float = _screen.column.custom_minimum_size.x
	if _screen is MainMenu:
		for child: Node in _screen.column.get_children():
			if child is HBoxContainer:
				asked = maxf(asked, (child as Control).get_combined_minimum_size().x)
	return asked


## A screen taller than its scroll has a range and its foot can be brought into view; a short one
## has none. The scroll goes back to where it was.
func _assert_scroll(label: String, controls: Array[Control]) -> bool:
	var scroll: ScrollContainer = _screen.scroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var was: int = scroll.scroll_vertical
	var content: Control = scroll.get_child(0) as Control
	var taller: bool = content.get_combined_minimum_size().y > scroll.size.y + TOLERANCE_PX
	var has_range: bool = bar.max_value > bar.page + TOLERANCE_PX
	(
		assert_bool(has_range)
		. override_failure_message(
			(
				"%s: content %.1f px in a scroll %.1f px high, bar %.1f of page %.1f"
				% [
					label,
					content.get_combined_minimum_size().y,
					scroll.size.y,
					bar.max_value,
					bar.page
				]
			)
		)
		. is_equal(taller)
	)
	(
		assert_bool(scroll.get_h_scroll_bar().visible)
		. override_failure_message(label + " hbar")
		. is_false()
	)
	if has_range:
		scroll.scroll_vertical = int(ceilf(bar.max_value))
		await await_idle_frame()
		assert_int(scroll.scroll_vertical).override_failure_message(label + " at foot").is_greater(
			0
		)
		var last: Control = controls.back()
		(
			assert_float(last.get_global_rect().end.y)
			. override_failure_message(label + ": the last control is below the view")
			. is_less_equal(scroll.get_global_rect().end.y + TOLERANCE_PX)
		)
		scroll.scroll_vertical = was
		await await_idle_frame()
	return has_range


func _side_names() -> Array[Label]:
	var found: Array[Label] = []
	var controls: Array[Control] = []
	_collect(_screen.column, controls)
	for control: Control in controls:
		if control is Label and String(control.theme_type_variation).begins_with("SideName"):
			found.append(control as Label)
	assert_int(found.size()).is_equal(2)
	return found


func _store_rows() -> RemoveAdsRows:
	return (_screen as SettingsScreen).remove_rows


## The rects of the two rows and then of every visible control below their slot, in column order.
func _rects_from(rows: RemoveAdsRows) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if rows.visible:
		out.append(rows.remove_button.get_global_rect())
		out.append(rows.restore_button.get_global_rect())
	var slot: Node = rows.get_parent()
	var after_slot: bool = false
	for child: Node in slot.get_parent().get_children():
		if child == slot:
			after_slot = true
		elif after_slot and child is Control and (child as Control).visible:
			out.append((child as Control).get_global_rect())
	return out


func _assert_rects(expected: Array[Rect2], actual: Array[Rect2], label: String) -> void:
	assert_int(actual.size()).override_failure_message(label).is_equal(expected.size())
	for index: int in mini(expected.size(), actual.size()):
		(
			assert_bool(actual[index].is_equal_approx(expected[index]))
			. override_failure_message(
				"%s #%d: %s became %s" % [label, index, expected[index], actual[index]]
			)
			. is_true()
		)


## The visible controls under `node` in tree order; a freed-later child is left out.
func _collect(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var control: Control = child as Control
		if control != null:
			if not control.visible:
				continue
			into.append(control)
		_collect(child, into)


## A menu with the kind's screen on top (on a plain screen, except the main menu, the root).
func _open(kind: StringName, profile: UiMetrics) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_root = null
	if kind == TUTORIAL:
		_root = _make_screen(MAIN)  # The tutorial opens over the main menu.
		_stack.push(_root)
		await await_idle_frame()
	elif kind != MAIN:
		_stack.push(MenuScreen.new())
		await await_idle_frame()
	_screen = _make_screen(kind)
	_stack.push(_screen)
	await _settle()
	if kind == HOW_REAL_SECTION or kind == HOW_LONG_SECTION:
		_press_first_button()
	elif kind == LICENCES_TEXT:
		_press(LONG_TEXT_ROW)
	await _settle()


func _make_screen(kind: StringName) -> MenuScreen:
	match kind:
		MAIN:
			var main: MainMenu = MainMenu.new()
			main.progression = _progression
			main.resume_check = func() -> bool: return true  # Continue shows: the tallest column.
			return main
		MAP_SELECT:
			var maps: MapSelect = MapSelect.new()
			maps.progression = _rank
			maps.flow = _flow
			maps.catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
			return maps
		SETTINGS:
			var settings: SettingsScreen = SettingsScreen.new()
			settings.routes = MenuRoutes.new()
			settings.dev_enabled = func() -> bool: return true  # The longest column.
			if _store != null:
				settings.ad_service = _store
			return settings
		HOW_LIST, HOW_REAL_SECTION, HOW_LONG_SECTION:
			var how: HowToPlayScreen = HowToPlayScreen.new()  # No help: the real data.
			if kind == HOW_LONG_SECTION:
				how.help = _long_help(60)
			return how
	if kind == TUTORIAL:
		var tutorial: TutorialScreen = TutorialScreen.new()
		tutorial.flow = _flow
		return tutorial
	return LicencesScreen.new()  # No catalog: the build's own.


func _depth_of(kind: StringName) -> int:
	return 1 if kind == MAIN else 2


## The profile with the same screen turned: the portrait twin of a landscape one and back.
func _portrait_twin(profile: UiMetrics) -> UiMetrics:
	return _profile_with_window(Vector2i(profile.window_size.y, profile.window_size.x))


func _press_first_button() -> void:
	for child: Node in _screen.column.get_children():
		if child is Button and not child.is_queued_for_deletion():
			(child as Button).pressed.emit()
			return
	fail("no button on the screen")


func _press(text: String) -> void:
	for child: Node in _screen.column.get_children():
		if (
			child is Button
			and (child as Button).text == text
			and not child.is_queued_for_deletion()
		):
			(child as Button).pressed.emit()
			return
	fail("no button " + text)


func _turn(to: UiMetrics) -> void:
	UiScale.set_override(to)
	get_window().size = to.window_size
	await _settle()


func _settle() -> void:
	for _frame: int in range(SETTLE_FRAMES):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


## One section with `count` entries of a long body.
func _long_help(count: int) -> HelpDef:
	var section: HelpSectionDef = HelpSectionDef.new()
	section.id = &"long"
	section.title = "Long"
	for i: int in count:
		var entry: HelpEntryDef = HelpEntryDef.new()
		entry.id = StringName("long-%d" % i)
		entry.title = "Entry %d" % i
		entry.body = "A line of help text that has to wrap on a narrow screen. ".repeat(8)
		section.entries.append(entry)
	var help: HelpDef = HelpDef.new()
	help.sections.append(section)
	return help


func _label(kind: StringName, profile_name: StringName) -> String:
	return "%s @ %s %s" % [kind, profile_name, UiProfiles.by_name(profile_name).window_size]


## Every profile: the landscape ones, the portrait twins and the notch design's pair.
func _profile_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for group: Dictionary[StringName, UiMetrics] in [
		UiProfiles.all(), UiProfiles.portrait(), UiProfiles.notch_design()
	]:
		for profile_name: StringName in group:
			names.append(profile_name)
	return names


## A device turned: each of the six sizes' landscape and portrait pair (read off the shared list),
## and the 6-inch phone with the design's insets.
func _turn_pairs() -> Array[Array]:
	var pairs: Array[Array] = []
	for index: int in ScreenSizes.LANDSCAPE.size():
		pairs.append(
			[
				_profile_with_window(ScreenSizes.LANDSCAPE[index]),
				_profile_with_window(ScreenSizes.PORTRAIT[index])
			]
		)
	var notch: Dictionary[StringName, UiMetrics] = UiProfiles.notch_design()
	pairs.append([notch[&"notch_design"], notch[&"notch_design_portrait"]])
	return pairs


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profile_name: StringName in _profile_names():
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		if profile.window_size == size:
			return profile
	return null
