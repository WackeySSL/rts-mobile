extends GdUnitTestSuite
## P432: the Double XP offer inside the result screen's `OfferSlot`. With a loaded ad and a scored
## award the slot shows the offer, otherwise it is hidden and 0 tall; a tap grants through
## Progression in the reward callback and moves the XP bar; a late award shows it then. At the six
## sizes (both orientations) the offer lies inside the panel and its button is at least 48 dp.
## The widget alone is tests/ui/ads/test_double_xp_offer.gd.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_menu_flow.gd")
const FakeAudio: GDScript = preload("res://tests/ui/support/fake_audio.gd")
const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
const GAP_DP: float = 16.0

var _window_size_before: Vector2i
var _main: Node
var _flow: FakeFlow
var _audio: FakeAudio
var _h: AdServiceHarness
var _service: Node
var _progression: ProgressionScript
var _award: XpAward
var _clock: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_h = AdServiceHarness.new()
	_service = auto_free(_h.make(true))
	add_child(_service)
	_progression = auto_free(ProgressionScript.new())
	_progression.bind(_h.save_service(), null)


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	_h.dispose()
	_free_fakes()


func _free_fakes() -> void:
	if is_instance_valid(_flow):
		_flow.free()
	if is_instance_valid(_audio):
		_audio.free()


func _slot() -> OfferSlot:
	return _screen().find_child("OfferSlot", true, false) as OfferSlot


func _screen() -> ResultScreen:
	return _main.get_node("Hud/ResultScreen")


func _button() -> Button:
	return _screen().offer.get_node("OfferButton") as Button


## A main scene whose screen takes a real Progression and the harness's AdService; the flow hands
## out a real award (or none).
func _open(scored: bool = true) -> void:
	_main = auto_free(await MatchRig.open(self))
	var screen: ResultScreen = _screen()
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = MatchSummary.OUTCOME_WIN
	summary.level = &"normal"
	_award = _progression.award_match(summary)
	_free_fakes()
	_flow = FakeFlow.new()
	_flow.runner = _main.get_node("MatchRunner")
	_flow.award = _award if scored else null
	_audio = FakeAudio.new()
	screen.flow = _flow
	screen.progression = _progression
	screen.audio = _audio
	screen.offer.use_service(_service)
	screen.offer.now_ms = func() -> int: return _clock


## A tap after the arm delay.
func _press() -> void:
	_clock += AdsSettingsDef.load_default().reward_arm_ms
	_button().pressed.emit()


func _again_rect() -> Rect2:
	return (_screen().find_child("PlayAgainButton", true, false) as Control).get_global_rect()


func test_the_slot_shows_the_offer_for_a_loaded_ad_and_a_scored_award() -> void:
	await _open()
	assert_bool(_slot().visible).is_false()  # The screen is hidden while the match runs.
	MatchRig.end(_main, [2])
	assert_bool(_screen().offer.is_offered()).is_true()
	assert_bool(_slot().is_visible_in_tree()).is_true()
	assert_float(_slot().get_combined_minimum_size().y).is_greater(0.0)


func test_the_slot_keeps_its_height_without_a_loaded_ad_and_is_0_tall_without_an_award() -> void:
	await _open()
	AdServiceHarness.fake(_service).fill = false
	MatchRig.end(_main, [2])
	assert_bool(_screen().offer.is_offered()).is_false()  # No ad: no button shows,
	assert_bool(_slot().is_visible_in_tree()).is_true()  # but the space is held.
	assert_float(_slot().get_combined_minimum_size().y).is_greater(0.0)
	_main.free()
	CommandQueue.clear()
	AdServiceHarness.fake(_service).fill = true
	await _open(false)  # No award.
	MatchRig.end(_main, [2])
	assert_bool(_slot().is_visible_in_tree()).is_false()
	assert_float(_slot().get_combined_minimum_size().y).is_equal(0.0)


func test_a_tap_grants_through_progression_and_the_bar_follows() -> void:
	await _open()
	MatchRig.end(_main, [2])
	var total: int = _progression.xp()
	var bar: ProgressBar = _screen().find_child("XpBar", true, false)
	_press()
	await AdServiceHarness.frames(3)
	assert_int(_progression.xp()).is_equal(total + _award.base_xp)
	assert_bool(_award.bonus_applied).is_true()
	assert_bool(_slot().is_visible_in_tree()).is_false()
	assert_float(_slot().get_combined_minimum_size().y).is_equal(0.0)
	assert_float(bar.value).is_equal(float(_progression.xp()))
	var gained: Label = _screen().find_child("XpBox", true, false).get_child(0)
	assert_str(gained.text).is_equal("+%d XP" % (_award.base_xp * 2))


func test_a_cancel_grants_nothing_and_the_slot_stays() -> void:
	await _open()
	MatchRig.end(_main, [2])
	var total: int = _progression.xp()
	AdServiceHarness.fake(_service).grant_reward = false
	_press()
	await AdServiceHarness.frames(3)
	assert_int(_progression.xp()).is_equal(total)
	assert_bool(_slot().is_visible_in_tree()).is_true()


func test_a_late_award_shows_the_offer_when_the_score_lands() -> void:
	await _open(false)
	MatchRig.end(_main, [2])
	assert_bool(_slot().is_visible_in_tree()).is_false()
	_flow.award = _award
	_flow.match_scored.emit(null, _award)
	assert_bool(_slot().is_visible_in_tree()).is_true()
	_flow.match_scored.emit(null, _award)  # A second score changes nothing.
	assert_bool(_slot().is_visible_in_tree()).is_true()


func _let_the_ad_load() -> void:
	AdServiceHarness.fake(_service).fill = true
	_h.clock_ms += 60000
	_screen().offer.refresh()  # What the recheck timer does a second later.
	await await_idle_frame()


func test_an_ad_that_loads_late_moves_nothing_under_the_finger() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		_h.dispose()
		_h = AdServiceHarness.new()
		_service = auto_free(_h.make(true))
		add_child(_service)
		_progression.bind(_h.save_service(), null)
		await _open()
		AdServiceHarness.fake(_service).fill = false
		MatchRig.end(_main, [2])
		_screen().settle()
		await await_idle_frame()
		var before: Rect2 = _again_rect()
		assert_bool(_screen().offer.is_offered()).is_false()
		await _let_the_ad_load()
		assert_bool(_screen().offer.is_offered()).override_failure_message(str(size)).is_true()
		assert_that(_again_rect()).override_failure_message(str(size)).is_equal(before)
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()


func test_a_late_award_and_then_a_late_ad_move_nothing() -> void:
	await _open(false)
	AdServiceHarness.fake(_service).fill = false
	MatchRig.end(_main, [2])
	_flow.award = _award
	_flow.match_scored.emit(null, _award)
	_screen().settle()
	await await_idle_frame()
	var before: Rect2 = _again_rect()
	await _let_the_ad_load()
	assert_bool(_screen().offer.is_offered()).is_true()
	assert_that(_again_rect()).is_equal(before)


func test_the_grant_collapses_the_slot_at_once() -> void:
	await _open()
	MatchRig.end(_main, [2])
	_press()
	await AdServiceHarness.frames(3)
	assert_bool(_slot().is_visible_in_tree()).is_false()


func test_the_offer_fits_the_panel_with_a_48_dp_button_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		_h.dispose()
		_h = AdServiceHarness.new()
		_service = auto_free(_h.make(true))
		add_child(_service)
		_progression.bind(_h.save_service(), null)
		await _open()
		MatchRig.end(_main, [2])
		_screen().settle()
		await await_idle_frame()
		var panel: Rect2 = _screen().column.get_parent().get_global_rect()
		var slot: Rect2 = _slot().get_global_rect()
		var button: Rect2 = _button().get_global_rect()
		var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		var label: String = str(size)
		assert_bool(_slot().is_visible_in_tree()).override_failure_message(label).is_true()
		assert_bool(panel.encloses(slot)).override_failure_message("%s slot" % label).is_true()
		assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		for button_name: String in ["PlayAgainButton", "BackButton"]:
			var other: Rect2 = (
				(_screen().find_child(button_name, true, false) as Control).get_global_rect()
			)
			assert_bool(panel.encloses(other)).override_failure_message(label).is_true()
			assert_bool(other.intersects(slot)).override_failure_message(label).is_false()
			var air: float = other.position.y - button.end.y
			(
				assert_bool(air >= UiScale.dp(GAP_DP) - TOLERANCE_PX)
				. override_failure_message("%s gap %s" % [label, air])
				. is_true()
			)
		assert_bool(UiScale.safe_rect_base().encloses(panel)).is_true()
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()
