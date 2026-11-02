extends GdUnitTestSuite
## HudState (plan P119c, ADR 0025 section 1) through its API: one unfold at a time, what a gesture
## on the map, a finger down, a mode that begins, a frame and a new match do to each of the four
## unfolds, PAUSE as the modal one, the pin and the full map's timer in stepped frame time. The same
## rules against the real gestures are test_hud_state_feed.gd's.

const FOLDING: Array[HudState.Unfold] = [
	HudState.Unfold.DRAWER, HudState.Unfold.RADAR, HudState.Unfold.ECONOMY
]
const CLOSE_MS: int = 4000

var _state: HudState
var _told: Array[HudState.Unfold] = []  ## The `previous` of each `changed`.


func before_test() -> void:
	_state = HudState.new()
	_told.clear()
	_state.changed.connect(func(previous: HudState.Unfold) -> void: _told.append(previous))


func test_a_new_state_has_nothing_unfolded_and_nothing_pinned() -> void:
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	assert_bool(_state.pinned).is_false()
	assert_int(_state.settings.radar_close_ms).is_equal(CLOSE_MS)  # The table's value.


func test_opening_one_unfold_closes_the_open_one_whichever_pair() -> void:
	for first: HudState.Unfold in FOLDING:
		for second: HudState.Unfold in FOLDING:
			if first == second:
				continue
			var why: String = "%d then %d" % [first, second]
			_state.reset()
			_told.clear()
			assert_bool(_state.open(first)).override_failure_message(why).is_true()
			assert_bool(_state.open(second)).override_failure_message(why).is_true()
			assert_int(_state.current).override_failure_message(why).is_equal(second)
			assert_bool(_state.is_open(first)).override_failure_message(why).is_false()
			assert_array(_told).override_failure_message(why).is_equal(
				[HudState.Unfold.NONE, first]
			)


func test_opening_what_is_open_changes_nothing_and_none_is_not_an_unfold() -> void:
	_state.open(HudState.Unfold.DRAWER)
	_told.clear()
	assert_bool(_state.open(HudState.Unfold.DRAWER)).is_true()
	assert_bool(_state.open(HudState.Unfold.NONE)).is_false()
	assert_int(_state.current).is_equal(HudState.Unfold.DRAWER)
	assert_array(_told).is_empty()


func test_close_folds_only_the_unfold_it_names() -> void:
	_state.open(HudState.Unfold.RADAR)
	_state.open(HudState.Unfold.DRAWER)  # The scope's collapse button comes late.
	_state.close(HudState.Unfold.RADAR)
	assert_int(_state.current).is_equal(HudState.Unfold.DRAWER)
	_state.close(HudState.Unfold.NONE)
	assert_int(_state.current).is_equal(HudState.Unfold.DRAWER)
	_state.close(HudState.Unfold.DRAWER)
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	assert_array(_told).is_equal(
		[HudState.Unfold.NONE, HudState.Unfold.RADAR, HudState.Unfold.DRAWER]
	)


func test_a_gesture_on_the_map_closes_the_drawer_the_card_and_the_unpinned_full_map() -> void:
	for unfold: HudState.Unfold in FOLDING:
		_state.open(unfold)
		_state.map_gesture()
		assert_int(_state.current).override_failure_message(str(unfold)).is_equal(
			HudState.Unfold.NONE
		)


func test_a_pinned_full_map_stays_through_gestures_and_modes() -> void:
	_state.open(HudState.Unfold.RADAR)
	_state.pinned = true
	_state.map_gesture()
	_state.mode_started()
	_state.touch_down()
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
	_state.pinned = false
	_state.map_gesture()
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)


func test_a_mode_that_begins_folds_what_a_gesture_folds() -> void:
	for unfold: HudState.Unfold in FOLDING:
		_state.open(unfold)
		_state.mode_started()
		assert_int(_state.current).override_failure_message(str(unfold)).is_equal(
			HudState.Unfold.NONE
		)


func test_a_finger_down_closes_the_card_and_nothing_else() -> void:
	_state.open(HudState.Unfold.DRAWER)
	_state.touch_down()
	assert_int(_state.current).is_equal(HudState.Unfold.DRAWER)
	_state.open(HudState.Unfold.RADAR)
	_state.touch_down()
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
	_state.open(HudState.Unfold.ECONOMY)
	_state.touch_down()
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)


## The touch that closes the card is a tap on the pill's numbers as well: its release asks to open
## the card, and the card stays shut. The next finger down is a new touch.
func test_the_touch_that_closes_the_card_cannot_open_it_again() -> void:
	_state.open(HudState.Unfold.ECONOMY)
	_state.touch_down()
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_false()
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	assert_bool(_state.open(HudState.Unfold.DRAWER)).is_true()  # Only the card is held back.
	_state.close(HudState.Unfold.DRAWER)
	_state.touch_down()
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_true()
	assert_int(_state.current).is_equal(HudState.Unfold.ECONOMY)


## Only a first finger down (no other finger was down) makes a touch new: a second finger neither
## clears the guard of the touch that closed the card nor can be undone by it.
func test_only_a_first_finger_clears_the_cards_guard() -> void:
	_state.open(HudState.Unfold.ECONOMY)
	_state.touch_down(true)  # The first finger closes the card.
	_state.touch_down(false)  # A second finger goes down while the first still holds.
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_false()  # The first one's release.
	_state.touch_down(true)  # Both are up; a new touch.
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_true()
	_state.touch_down(false)  # A second finger closes the card too, and guards it.
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_false()


func test_pause_takes_every_touch_and_nothing_opens_behind_it() -> void:
	_state.open(HudState.Unfold.DRAWER)
	assert_bool(_state.open(HudState.Unfold.PAUSE)).is_true()  # Opening it closes the drawer.
	assert_int(_state.current).is_equal(HudState.Unfold.PAUSE)
	_state.map_gesture()
	_state.mode_started()
	_state.touch_down()
	_state.touch_radar()
	_state.advance(10.0 * CLOSE_MS)
	_state.close(HudState.Unfold.DRAWER)
	for refused: HudState.Unfold in FOLDING:
		assert_bool(_state.open(refused)).override_failure_message(str(refused)).is_false()
	assert_int(_state.current).is_equal(HudState.Unfold.PAUSE)
	_state.close(HudState.Unfold.PAUSE)  # Resume.
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	assert_bool(_state.open(HudState.Unfold.DRAWER)).is_true()


func test_a_new_match_starts_with_nothing_unfolded_and_nothing_pinned() -> void:
	for unfold: HudState.Unfold in [
		HudState.Unfold.DRAWER,
		HudState.Unfold.RADAR,
		HudState.Unfold.ECONOMY,
		HudState.Unfold.PAUSE,
	]:
		_state.open(unfold)
		_state.pinned = true
		_state.reset()
		assert_int(_state.current).override_failure_message(str(unfold)).is_equal(
			HudState.Unfold.NONE
		)
		assert_bool(_state.pinned).override_failure_message(str(unfold)).is_false()
	_state.open(HudState.Unfold.ECONOMY)
	_state.touch_down()
	_state.reset()  # The finger of the old match is forgotten too.
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_true()


func test_changed_tells_every_change_once_and_the_pin_with_the_unfold_that_stays() -> void:
	_state.open(HudState.Unfold.DRAWER)
	_state.open(HudState.Unfold.DRAWER)
	_state.close(HudState.Unfold.PAUSE)  # Not open.
	_state.map_gesture()
	_state.map_gesture()  # Nothing left to close.
	assert_array(_told).is_equal([HudState.Unfold.NONE, HudState.Unfold.DRAWER])
	_told.clear()
	_state.open(HudState.Unfold.RADAR)
	_state.pinned = true
	_state.pinned = true
	_state.pinned = false
	assert_array(_told).is_equal(
		[HudState.Unfold.NONE, HudState.Unfold.RADAR, HudState.Unfold.RADAR]
	)


func test_a_new_match_tells_changed_once_and_only_when_something_was_unfolded_or_pinned() -> void:
	_state.reset()
	assert_array(_told).is_empty()
	_state.open(HudState.Unfold.RADAR)
	_state.pinned = true
	_told.clear()
	_state.reset()
	assert_array(_told).is_equal([HudState.Unfold.RADAR])
	_state.pinned = true  # A pin alone is state too.
	_told.clear()
	_state.reset()
	assert_array(_told).is_equal([HudState.Unfold.NONE])


## The three entries the unfolds decide in the layout's `Shown`, and the rects they bring.
func test_fill_sets_the_drawer_the_map_and_the_card_entries_and_nothing_else() -> void:
	var expected: Dictionary[HudState.Unfold, Array] = {
		HudState.Unfold.NONE: [false, false, false],
		HudState.Unfold.DRAWER: [true, false, false],
		HudState.Unfold.RADAR: [false, true, false],
		HudState.Unfold.ECONOMY: [false, false, true],
		HudState.Unfold.PAUSE: [false, false, false],
	}
	for unfold: HudState.Unfold in expected:
		_state.reset()
		if unfold != HudState.Unfold.NONE:
			_state.open(unfold)
		var shown: HudCorners.Shown = HudCorners.Shown.new()
		shown.bar = true
		shown.groups = 3
		shown.drawer = unfold != HudState.Unfold.DRAWER  # Overwritten both ways.
		_state.fill(shown)
		(
			assert_array([shown.drawer, shown.map, shown.card])
			. override_failure_message(str(unfold))
			. is_equal(expected[unfold])
		)
		assert_bool(shown.bar).is_true()  # What the selection decides stays.
		assert_int(shown.groups).is_equal(3)
		var rects: Dictionary[StringName, Rect2] = HudCorners.place(
			Rect2(0.0, 0.0, 1280.0, 720.0), false, 1.0, false, shown
		)
		assert_bool(rects.has(HudCorners.DRAWER)).is_equal(expected[unfold][0])
		assert_bool(rects.has(HudCorners.MAP)).is_equal(expected[unfold][1])
		assert_bool(rects.has(HudCorners.CARD)).is_equal(expected[unfold][2])
