extends GdUnitTestSuite
## The result screen's Phase 5 parts (plan P532, ADR 0043 sections 6 and 8, ADR 0045): the XP the
## match paid and the rank bar (its math at the rank edges and at the top rank), Back and Play
## again through `MenuFlow` (a fake counts the calls; a second tap while one runs does nothing),
## the victory or defeat sting once (a fake audio service), and the empty `OfferSlot`. The layout
## at the six sizes is checked with the XP block showing. The basic screen is test_result_screen's.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
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


func test_the_bar_math_at_the_rank_edges_and_the_top_rank() -> void:
	# Mid rank: 130 of 250 after +30, rank 2 both times.
	var mid: Dictionary = ResultScreen.xp_view(130, 30, TABLE)
	assert_int(mid["old_rank"]).is_equal(2)
	assert_int(mid["new_rank"]).is_equal(2)
	assert_bool(mid["rank_up"]).is_false()
	assert_array([mid["old"], mid["floor"], mid["next"]]).is_equal([100, 100, 250])
	# Exactly on a threshold gains the rank (old 70 + 30 = 100).
	var edge: Dictionary = ResultScreen.xp_view(100, 30, TABLE)
	assert_bool(edge["rank_up"]).is_true()
	assert_array([edge["old_rank"], edge["new_rank"]]).is_equal([1, 2])
	assert_array([edge["from_floor"], edge["from_next"], edge["floor"], edge["next"]]).is_equal(
		[0, 100, 100, 250]
	)
	# One short of the threshold stays.
	assert_bool(ResultScreen.xp_view(99, 30, TABLE)["rank_up"]).is_false()
	# Several ranks at once: the old range and the final one.
	var jump: Dictionary = ResultScreen.xp_view(300, 300, TABLE)
	assert_array([jump["old_rank"], jump["new_rank"]]).is_equal([1, 3])
	# The top rank: no next, the bar is full; reaching it is a rank-up, leaving it is not.
	var top: Dictionary = ResultScreen.xp_view(560, 40, TABLE)
	assert_bool(top["top"]).is_true()
	assert_bool(top["rank_up"]).is_false()
	assert_array([top["floor"], top["next"]]).is_equal([500, 500])
	assert_bool(ResultScreen.xp_view(510, 40, TABLE)["rank_up"]).is_true()
	# No XP gained, or a total below the gain, never goes negative.
	assert_int(ResultScreen.xp_view(10, 40, TABLE)["old"]).is_equal(0)
	assert_bool(ResultScreen.xp_view(50, 0, TABLE)["rank_up"]).is_false()


func test_the_xp_block_shows_the_gain_and_the_bar_fills_to_the_new_xp() -> void:
	await _open(130, 30)
	MatchRig.end(_main, [2])
	var screen: ResultScreen = _screen()
	var box: Control = screen.find_child("XpBox", true, false)
	var bar: ProgressBar = screen.find_child("XpBar", true, false)
	assert_bool(box.visible).is_true()
	assert_str(_texts(box)[0]).is_equal("+30 XP")
	assert_str(_texts(box)[1]).is_equal("RANK 2  RANK2")
	assert_float(bar.value).is_equal(100.0)  # Starts at the old XP.
	assert_array([bar.min_value, bar.max_value]).is_equal([100.0, 250.0])
	screen.settle()
	assert_float(bar.value).is_equal(130.0)
	assert_bool(screen.find_child("RankUp", true, false).visible).is_false()
	assert_str(_texts(box)[2]).is_equal("130 / 250 XP")


func test_a_rank_up_is_shown_and_the_bar_restarts_in_the_new_rank() -> void:
	await _open(110, 30)  # 80 -> 110: rank 1 -> 2.
	MatchRig.end(_main, [2])
	var screen: ResultScreen = _screen()
	var bar: ProgressBar = screen.find_child("XpBar", true, false)
	assert_array([bar.min_value, bar.max_value, bar.value]).is_equal([0.0, 100.0, 80.0])
	assert_bool(screen.find_child("RankUp", true, false).visible).is_false()
	screen.settle()
	assert_array([bar.min_value, bar.max_value, bar.value]).is_equal([100.0, 250.0, 110.0])
	assert_bool(screen.find_child("RankUp", true, false).visible).is_true()
	assert_str(_texts(screen.find_child("XpBox", true, false))[1]).is_equal("RANK 2  RANK2")


func test_the_top_rank_shows_a_full_bar_and_the_plain_total() -> void:
	await _open(600, 40)
	MatchRig.end(_main, [2])
	var screen: ResultScreen = _screen()
	screen.settle()
	var bar: ProgressBar = screen.find_child("XpBar", true, false)
	assert_float(bar.value).is_equal(bar.max_value)
	assert_str(_texts(screen.find_child("XpBox", true, false))[2]).is_equal("600 XP")


func test_a_match_that_paid_no_xp_shows_no_block() -> void:
	await _open(0, 0)
	_flow.award = null
	MatchRig.end(_main, [2])
	assert_bool(_screen().find_child("XpBox", true, false).visible).is_false()


func test_back_and_play_again_call_the_flow_once_and_a_second_tap_does_nothing() -> void:
	await _open(130, 30)
	MatchRig.end(_main, [2])
	var screen: ResultScreen = _screen()
	var back: Button = screen.find_child("BackButton", true, false)
	var again: Button = screen.find_child("PlayAgainButton", true, false)
	back.pressed.emit()
	back.pressed.emit()
	again.pressed.emit()
	assert_array([_flow.leaves, _flow.restarts]).is_equal([1, 0])
	_flow.release.emit()
	await await_idle_frame()
	again.pressed.emit()
	again.pressed.emit()
	assert_array([_flow.leaves, _flow.restarts]).is_equal([1, 1])
	_flow.release.emit()


func test_the_sting_plays_once_per_match_by_outcome() -> void:
	await _open(130, 30)
	MatchRig.end(_main, [2])
	_screen().settle()
	assert_array(_audio.played).is_equal([&"victory"])
	_main.free()
	CommandQueue.clear()
	await _open(130, 30)
	MatchRig.end(_main, [1])
	assert_array(_audio.played).is_equal([&"defeat"])
	_main.free()
	CommandQueue.clear()
	await _open(130, 30)
	MatchRig.end(_main, [1, 2])
	assert_array(_audio.played).is_equal([&"defeat"])  # A draw is not a win.


func test_the_xp_shows_when_the_score_lands_before_the_end() -> void:
	await _open(130, 30)  # The real order on main: MenuFlow scores first, then the screen shows.
	_flow.match_scored.emit(null, _flow.award)
	var box: Control = _screen().find_child("XpBox", true, false)
	assert_bool(box.visible).is_false()  # Still hidden: the match has not ended for the screen.
	MatchRig.end(_main, [2])
	assert_bool(box.visible).is_true()
	assert_str(_texts(box)[0]).is_equal("+30 XP")


func test_the_xp_shows_when_the_award_arrives_after_the_screen() -> void:
	await _open(130, 30)
	var award: XpAward = _flow.award
	_flow.award = null
	MatchRig.end(_main, [2])
	var box: Control = _screen().find_child("XpBox", true, false)
	assert_bool(box.visible).is_false()
	_flow.award = award
	_flow.match_scored.emit(null, award)
	assert_bool(box.visible).is_true()
	assert_str(_texts(box)[0]).is_equal("+30 XP")
	_flow.match_scored.emit(null, award)  # A second score does not restart the fill.
	assert_bool(box.visible).is_true()


func test_a_refused_call_leaves_the_buttons_live_for_the_next_tap() -> void:
	await _open(130, 30)
	MatchRig.end(_main, [2])
	var screen: ResultScreen = _screen()
	var back: Button = screen.find_child("BackButton", true, false)
	var again: Button = screen.find_child("PlayAgainButton", true, false)
	_flow.refuse = ERR_BUSY
	await (
		assert_error(func() -> void: again.pressed.emit())
		. is_push_warning("ResultScreen: restart refused (Busy)")
	)
	assert_int(_flow.restarts).is_equal(1)
	back.pressed.emit()
	await await_idle_frame()
	assert_int(_flow.leaves).is_equal(1)
	_flow.refuse = OK  # Both calls were refused at once, so these taps go through.
	again.pressed.emit()
	assert_int(_flow.restarts).is_equal(2)
	_flow.release.emit()
	await await_idle_frame()
	back.pressed.emit()
	assert_int(_flow.leaves).is_equal(2)
	_flow.release.emit()


func test_the_offer_slot_exists_empty_and_0_tall_until_something_is_put_in() -> void:
	await _open(130, 30)
	MatchRig.end(_main, [2])
	var slot: OfferSlot = _screen().find_child("OfferSlot", true, false) as OfferSlot
	assert_object(slot).is_not_null()
	assert_object(slot.owner).is_same(_screen())
	assert_int(slot.get_child_count()).is_equal(0)
	assert_float(slot.get_combined_minimum_size().y).is_equal(0.0)
	assert_bool(slot.is_visible_in_tree()).is_false()
	var probe: Control = Control.new()
	probe.custom_minimum_size = Vector2(10, 40)
	slot.add_child(probe)
	assert_bool(slot.visible).is_true()
	assert_float(slot.get_combined_minimum_size().y).is_equal(40.0)
	slot.remove_child(probe)
	probe.free()
	assert_bool(slot.visible).is_false()


func test_the_layout_with_the_xp_block_fits_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		await _open(110, 30)
		MatchRig.end(_main, [2])
		_screen().settle()
		await await_idle_frame()
		var safe: Rect2 = UiScale.safe_rect_base()
		var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		var panel: Rect2 = _screen().column.get_parent().get_global_rect()
		(
			assert_bool(safe.encloses(panel))
			. override_failure_message("%s %s" % [size, panel])
			. is_true()
		)
		for button_name: String in ["PlayAgainButton", "BackButton"]:
			var button: Button = _screen().find_child(button_name, true, false)
			var rect: Rect2 = button.get_global_rect()
			assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px).is_true()
			assert_bool(panel.encloses(rect)).override_failure_message(str(size)).is_true()
		var xp: Rect2 = (_screen().find_child("XpBox", true, false) as Control).get_global_rect()
		assert_bool(panel.encloses(xp)).override_failure_message("%s xp %s" % [size, xp]).is_true()
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()


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


## The text of every visible label directly in `box`, in order.
func _texts(box: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in box.get_children():
		if child is Label and (child as Label).visible:
			out.append((child as Label).text)
	return out
