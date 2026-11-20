extends GdUnitTestSuite
## The result screen's PLAY AGAIN while it reads "STARTING…" (P443): a turn of the phone keeps the
## width pin (`DpMinSize` resets the minimum on a resize, then `applied` re-pins it), at the six
## sizes and inside a safe-area inset; a much longer translated STARTING stays whole. Split from
## test_result_screen_menu for gdlint's method cap.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const NoFloorScreen: GDScript = preload("res://tests/ui/support/result_screen_no_floor.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_menu_flow.gd")
const FakeProgression: GDScript = preload("res://tests/ui/support/fake_progression.gd")
const FakeAudio: GDScript = preload("res://tests/ui/support/fake_audio.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
const TABLE: PackedInt32Array = [0, 100, 250, 500]
const LONG_STARTING: String = "STARTING NEXT MATCH…"
## Too long for the phone's portrait row beside BACK: the pin is clamped and the text trimmed.
const OVERFLOW_STARTING: String = "STARTING THE NEXT MATCH, PLEASE WAIT…"
## Too long even for the 720x1280 portrait row, where the dp is larger than on the 20:9 phone.
const WAY_TOO_LONG_STARTING: String = "STARTING THE NEXT MATCH, PLEASE WAIT WHILE WE PREPARE…"

var _window_size_before: Vector2i
var _main: Node
var _flow: FakeFlow
var _progression: FakeProgression
var _audio: FakeAudio
var _xx_table: Translation = null
var _locale_before: String = ""
var _long_text: String = ""  ## Set while a longer STARTING is installed ("" in English).
var _trimmed: int = 0  ## How many checks saw PLAY AGAIN's text wider than its button.
var _trimmed_at: Array[Vector2i] = []  ## The window sizes of those checks.


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	if _xx_table != null:  # A failing test must not leak the "xx" locale into other suites.
		TranslationServer.set_locale(_locale_before)
		TranslationServer.remove_translation(_xx_table)
		_xx_table = null
	_long_text = ""
	_trimmed = 0
	_trimmed_at.clear()
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	_free_fakes()


func _free_fakes() -> void:
	for fake: Object in [_flow, _progression, _audio]:
		if is_instance_valid(fake):
			fake.free()
	_flow = null
	_progression = null
	_audio = null


func test_a_turn_while_starting_keeps_both_rects_and_the_text_unclipped() -> void:
	var sizes: Array[Vector2i] = ScreenSizes.ALL
	for i: int in sizes.size():
		await _turn_while_starting(sizes[i], sizes[(i + 3) % sizes.size()], false)
	assert_int(_trimmed).is_equal(0)  # English: no ellipsis at any size.


## The same with the design's notch insets (a simulated safe area), phone sizes only.
func test_a_turn_while_starting_inside_a_safe_area_inset() -> void:
	await _turn_while_starting(ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0], true)
	await _turn_while_starting(ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0], true)
	assert_int(_trimmed).is_equal(0)


## A longer STARTING than the idle label: the pin is the wider of the two (or the room), so the
## rects are the idle ones, at the six sizes and in the notch profile.
func test_a_long_starting_text_keeps_the_rects_and_is_not_clipped() -> void:
	_install_xx(LONG_STARTING)
	await _walk_sizes()


## A STARTING too long for the portrait phone's row: the pin stops at the room beside BACK, the
## text is trimmed with an ellipsis, and the row stays inside the safe area with the rects of idle.
func test_an_overflowing_starting_text_is_trimmed_and_the_row_stays_inside() -> void:
	_install_xx(OVERFLOW_STARTING)
	await _walk_sizes()
	assert_bool(_trimmed > 0).is_true()
	assert_bool(_trimmed_at.has(ScreenSizes.PORTRAIT[1])).is_true()  # The 20:9 portrait phone.


## A dp change (a browser resize, not a turn) with the overflow text: PLAY AGAIN's `applied` fires
## before BACK's own `DpMinSize` resets BACK's minimum, so the clamp must not use BACK's old floor.
## One `size_changed` is emitted by hand and the minimums read at once, before any layout or a
## second emission could hide the order. The dp rises from 0.75 to 1.5 at the 720x1280 window.
func test_a_dp_change_keeps_the_overflow_row_inside_in_the_same_emission() -> void:
	_install_xx(WAY_TOO_LONG_STARTING)
	var size: Vector2i = ScreenSizes.PORTRAIT[0]
	_set_window(size, false)
	await await_idle_frame()
	await _open(110, 30)
	MatchRig.end(_main, [2])
	_screen().settle()
	await await_idle_frame()
	var again: Button = _screen().find_child("PlayAgainButton", true, false)
	var row: Control = again.get_parent() as Control
	again.pressed.emit()
	await await_idle_frame()
	for scale: float in [0.75, 1.5, 0.75, 1.25]:
		UiScale.set_override(UiMetrics.create("Linux", 96, scale, 1.0, size, Rect2i()))
		_screen().get_viewport().size_changed.emit()
		var inner: Rect2 = SafeAreaMargin.rect_inside(
			row.get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var label: String = "dp scale %s" % scale
		var wide: float = row.get_combined_minimum_size().x
		assert_bool(wide <= inner.size.x + TOLERANCE_PX).override_failure_message(label).is_true()
	_flow.release.emit()
	await await_idle_frame()
	_main.free()
	CommandQueue.clear()
	await await_idle_frame()


## The six sizes, then the notch profile both ways.
func _walk_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _turn_while_starting(size, size, false)
	await _turn_while_starting(ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0], true)
	await _turn_while_starting(ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0], true)


## Makes STARTING read `text` through an "xx" table, and fails at once when it does not (so the
## long-text checks cannot pass by reading the English text on both sides).
func _install_xx(text: String) -> void:
	_xx_table = Translation.new()
	_locale_before = TranslationServer.get_locale()  # Before `add_translation` changes anything.
	_xx_table.locale = "xx"
	_xx_table.add_message(MapSelectText.STARTING, text)
	TranslationServer.add_translation(_xx_table)
	TranslationServer.set_locale("xx")
	assert_str(TranslationServer.get_locale()).is_equal("xx")
	assert_str(tr(MapSelectText.STARTING)).is_equal(text)
	_long_text = text


## Opens at `first`, turns to `turned` and records the idle rects, presses PLAY AGAIN, turns
## there and back, and checks the rects are the idle ones. `inset`: the notch profiles.
func _turn_while_starting(first: Vector2i, turned: Vector2i, inset: bool) -> void:
	_set_window(first, inset)
	await await_idle_frame()
	await _open(110, 30)
	MatchRig.end(_main, [2])
	_screen().settle()
	await await_idle_frame()
	var again: Button = _screen().find_child("PlayAgainButton", true, false)
	var back: Button = _screen().find_child("BackButton", true, false)
	var row: Control = again.get_parent() as Control
	_set_window(turned, inset)
	await await_idle_frame()
	await await_idle_frame()
	var label: String = "%s -> %s inset %s" % [first, turned, inset]
	var idle_again: Rect2 = again.get_global_rect()
	var idle_back: Rect2 = back.get_global_rect()
	var idle_row: Rect2 = row.get_global_rect()
	var idle_text: String = again.text
	if _long_text.is_empty():  # English: the idle text is never trimmed.
		(
			assert_bool(_text_width(again, idle_text) <= again.size.x + TOLERANCE_PX)
			. override_failure_message(label)
			. is_true()
		)
	again.pressed.emit()
	await await_idle_frame()
	_set_window(first, inset)  # Turn there and back while it reads STARTING.
	await await_idle_frame()
	await await_idle_frame()
	_assert_row_fits(again, row, label + " (mid-turn)")
	_set_window(turned, inset)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(again.text).is_equal(tr(MapSelectText.STARTING))
	if not _long_text.is_empty():  # `_install_xx` proved the table: the text really is longer.
		assert_str(again.text).override_failure_message(label).is_equal(_long_text)
		assert_bool(_text_width(again, again.text) > _text_width(again, idle_text)).is_true()
	assert_object(again.get_global_rect()).override_failure_message(label).is_equal(idle_again)
	assert_object(back.get_global_rect()).override_failure_message(label).is_equal(idle_back)
	assert_object(row.get_global_rect()).override_failure_message(label).is_equal(idle_row)
	_assert_row_fits(again, row, label)
	_flow.release.emit()
	await await_idle_frame()
	_main.free()
	CommandQueue.clear()
	await await_idle_frame()


## The button's own minimum width for `text`: no pin, no trimming.
func _text_width(button: Button, text: String) -> float:
	var shown: String = button.text
	var pinned: float = button.custom_minimum_size.x
	var overrun: TextServer.OverrunBehavior = button.text_overrun_behavior
	button.text = text
	button.custom_minimum_size.x = 0.0
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var wide: float = button.get_combined_minimum_size().x
	button.text = shown
	button.custom_minimum_size.x = pinned
	button.text_overrun_behavior = overrun
	return wide


## Without a `DpMinSize` on PLAY AGAIN the warning is reported and the button still turns both off.
func test_without_a_dp_min_size_pressing_play_again_still_disables_both_buttons() -> void:
	await _open(110, 30, true)
	MatchRig.end(_main, [2])
	_screen().settle()
	await await_idle_frame()
	var again: Button = _screen().find_child("PlayAgainButton", true, false)
	var back: Button = _screen().find_child("BackButton", true, false)
	# Guards the `_pin_again()` call in `_ready`: no `applied` ever fires here.
	assert_bool(again.custom_minimum_size.x >= UiScale.dp(ModalFrame.BUTTON_DP.x)).is_true()
	again.pressed.emit()
	await await_idle_frame()
	assert_bool(again.disabled).is_true()
	assert_bool(back.disabled).is_true()
	_flow.release.emit()
	await await_idle_frame()


## The window at `size`; with `inset` the notch profile of its orientation (and its safe area).
func _set_window(size: Vector2i, inset: bool) -> void:
	if inset:
		var notch: Dictionary[StringName, UiMetrics] = UiProfiles.notch_design()
		var profile: UiMetrics = (
			notch[&"notch_design_portrait"]
			if UiScale.is_portrait_size(size)
			else notch[&"notch_design"]
		)
		UiScale.set_override(profile)
		size = profile.window_size
	get_window().size = size


## The label whole or, when wider than the button, trimmed with an ellipsis; the 48 dp heights kept
## (BACK at its minimum width too); the row at least its own minimum and inside the safe rect.
func _assert_row_fits(again: Button, row: Control, label: String) -> void:
	var back: Button = row.get_child(1) as Button
	assert_int(again.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	if _text_width(again, again.text) > again.size.x + TOLERANCE_PX:
		_trimmed += 1
		_trimmed_at.append(get_window().size)
	var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
	assert_bool(again.size.y >= floor_px).override_failure_message(label).is_true()
	assert_bool(back.size.y >= floor_px).override_failure_message(label).is_true()
	var back_wide: bool = back.get_combined_minimum_size().x <= back.size.x + TOLERANCE_PX
	assert_bool(back_wide).override_failure_message(label).is_true()
	var row_wide: bool = row.get_combined_minimum_size().x <= row.size.x + TOLERANCE_PX
	assert_bool(row_wide).override_failure_message(label).is_true()
	# The inner rect the clamp uses (the 12 dp inset), not the bare safe rect.
	var inner: Rect2 = SafeAreaMargin.rect_inside(
		row.get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	(
		assert_bool(inner.grow(TOLERANCE_PX).encloses(row.get_global_rect()))
		. override_failure_message(label)
		. is_true()
	)
	var scroll: ScrollContainer = _screen().find_children("*", "ScrollContainer", true, false)[0]
	# The panel never scrolls here (its content is shorter than the shortest size), so `room` has no
	# scrollbar to pay for; `_pin_again` still subtracts it if one ever shows.
	assert_bool(scroll.get_v_scroll_bar().visible).override_failure_message(label).is_false()


## The main scene with PLAY AGAIN's `DpMinSize` left out.
func _open_floorless() -> void:
	_main = auto_free(await MatchRig.open(self, MatchRig.DERRICK, 1, _swap_screen))


func _swap_screen(main: Node) -> void:
	var screen: Control = main.get_node("Hud/ResultScreen")
	var kept: Dictionary[String, Variant] = {}  # A new script drops the scene's script variables.
	for info: Dictionary in screen.get_property_list():
		if (info["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			kept[info["name"] as String] = screen.get(info["name"] as String)
	screen.set_script(NoFloorScreen)
	for key: String in kept:
		screen.set(key, kept[key])


## A main scene whose screen takes the fakes: the player at `total` XP after `gained`, owned by the
## fake flow.
func _open(total: int, gained: int, drop_floor: bool = false) -> void:
	if drop_floor:  # The warning is expected, once, from `_ready`.
		await assert_error(_open_floorless).is_push_warning(
			"ResultScreen: PLAY AGAIN has 0 DpMinSize nodes, not 1"
		)
	else:
		_main = auto_free(await MatchRig.open(self))
	var screen: ResultScreen = _screen()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	_free_fakes()
	_flow = FakeFlow.new()
	_flow.runner = runner
	_flow.award = XpAward.new()
	_flow.award.base_xp = gained
	_progression = FakeProgression.new()
	_progression.total = total
	_audio = FakeAudio.new()
	screen.flow = _flow
	screen.progression = _progression
	screen.audio = _audio
	screen.rank_xp = TABLE


func _screen() -> ResultScreen:
	return _main.get_node("Hud/ResultScreen")
