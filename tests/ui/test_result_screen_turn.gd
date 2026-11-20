extends GdUnitTestSuite
## The result screen's PLAY AGAIN while it reads "STARTING…" (P443): a turn of the phone keeps the
## width pin (`DpMinSize` resets the minimum on a resize, then `applied` re-pins it), at the six
## sizes and inside a safe-area inset; a much longer translated STARTING stays whole. Split from
## test_result_screen_menu for gdlint's method cap.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_menu_flow.gd")
const FakeProgression: GDScript = preload("res://tests/ui/support/fake_progression.gd")
const FakeAudio: GDScript = preload("res://tests/ui/support/fake_audio.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
const TABLE: PackedInt32Array = [0, 100, 250, 500]

var _window_size_before: Vector2i
var _main: Node
var _flow: FakeFlow
var _progression: FakeProgression
var _audio: FakeAudio


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
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


## The same with the design's notch insets (a simulated safe area), phone sizes only.
func test_a_turn_while_starting_inside_a_safe_area_inset() -> void:
	await _turn_while_starting(ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0], true)
	await _turn_while_starting(ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0], true)


## A much longer STARTING than the idle label: the pin is only a floor, so the button grows past
## it (its rect moves, which the idle width bounding the real text avoids), but the text stays
## whole and the row stays inside the safe area and fits its own minimum.
func test_a_long_starting_text_is_not_clipped_and_the_row_stays_inside() -> void:
	var table: Translation = Translation.new()
	table.locale = "xx"
	table.add_message(MapSelectText.STARTING, "STARTING THE NEXT MATCH, PLEASE WAIT…")
	TranslationServer.add_translation(table)
	var locale_before: String = TranslationServer.get_locale()
	TranslationServer.set_locale("xx")
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open(110, 30)
		MatchRig.end(_main, [2])
		_screen().settle()
		await await_idle_frame()
		var again: Button = _screen().find_child("PlayAgainButton", true, false)
		again.pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		assert_str(again.text).is_equal(tr(MapSelectText.STARTING))
		_assert_row_fits(again, again.get_parent() as Control, str(size))
		_flow.release.emit()
		await await_idle_frame()
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()
	TranslationServer.set_locale(locale_before)
	TranslationServer.remove_translation(table)


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
	var idle_again: Rect2 = again.get_global_rect()
	var idle_back: Rect2 = back.get_global_rect()
	var idle_row: Rect2 = row.get_global_rect()
	again.pressed.emit()
	await await_idle_frame()
	_set_window(first, inset)  # Turn there and back while it reads STARTING.
	await await_idle_frame()
	await await_idle_frame()
	var label: String = "%s -> %s inset %s" % [first, turned, inset]
	_assert_row_fits(again, row, label + " (mid-turn)")
	_set_window(turned, inset)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(again.text).is_equal(tr(MapSelectText.STARTING))
	assert_object(again.get_global_rect()).override_failure_message(label).is_equal(idle_again)
	assert_object(back.get_global_rect()).override_failure_message(label).is_equal(idle_back)
	assert_object(row.get_global_rect()).override_failure_message(label).is_equal(idle_row)
	_assert_row_fits(again, row, label)
	_flow.release.emit()
	await await_idle_frame()
	_main.free()
	CommandQueue.clear()
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


## The label whole, the 48 dp height kept, the row at least its own minimum and inside the safe
## rect.
func _assert_row_fits(again: Button, row: Control, label: String) -> void:
	var clipped: bool = again.get_combined_minimum_size().x > again.size.x + TOLERANCE_PX
	assert_bool(clipped).override_failure_message(label).is_false()
	var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
	assert_bool(again.size.y >= floor_px).override_failure_message(label).is_true()
	var row_wide: bool = row.get_combined_minimum_size().x <= row.size.x + TOLERANCE_PX
	assert_bool(row_wide).override_failure_message(label).is_true()
	var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
	assert_bool(safe.encloses(row.get_global_rect())).override_failure_message(label).is_true()


## A main scene whose screen takes the fakes: the player at `total` XP after `gained`, owned by the
## fake flow.
func _open(total: int, gained: int) -> void:
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
