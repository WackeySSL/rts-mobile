extends GdUnitTestSuite
## HudState's full map (plan P119c, ADR 0025 sections 1 and 7): the timer in stepped frame time
## (`radar_close_ms`, restarted by a touch on the map), the pin and what ends it. The rest of the
## state's rules are test_hud_state.gd's.

const CLOSE_MS: int = 4000

var _state: HudState
var _told: Array[HudState.Unfold] = []  ## The `previous` of each `changed`.


func before_test() -> void:
	_state = HudState.new()
	_told.clear()
	_state.changed.connect(func(previous: HudState.Unfold) -> void: _told.append(previous))


func test_the_full_map_folds_after_radar_close_ms_of_frame_time() -> void:
	_state.open(HudState.Unfold.RADAR)
	for frame: int in 39:
		_state.advance(100.0)  # 3 900 ms.
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
	_state.advance(99.0)
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)  # 3 999 ms.
	_state.advance(1.0)
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)  # 4 000 ms.
	assert_array(_told).is_equal([HudState.Unfold.NONE, HudState.Unfold.RADAR])


func test_a_touch_on_the_full_map_starts_the_count_over() -> void:
	_state.open(HudState.Unfold.RADAR)
	_state.advance(CLOSE_MS - 1.0)
	_state.touch_radar()
	_state.advance(CLOSE_MS - 1.0)
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
	_state.advance(1.0)
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)


func test_the_count_starts_when_the_full_map_opens_and_runs_for_it_alone() -> void:
	_state.advance(10.0 * CLOSE_MS)  # Nothing open.
	_state.open(HudState.Unfold.DRAWER)
	_state.advance(10.0 * CLOSE_MS)  # Not the full map.
	assert_int(_state.current).is_equal(HudState.Unfold.DRAWER)
	_state.open(HudState.Unfold.RADAR)
	_state.advance(CLOSE_MS - 1.0)
	_state.open(HudState.Unfold.DRAWER)  # And the time it spent is not kept for its next opening.
	_state.open(HudState.Unfold.RADAR)
	_state.advance(CLOSE_MS - 1.0)
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)


func test_a_pinned_full_map_never_times_out_and_unpinning_starts_a_fresh_count() -> void:
	_state.open(HudState.Unfold.RADAR)
	_state.advance(CLOSE_MS - 1.0)  # Nearly out of time when the pin goes on.
	_state.pinned = true
	_state.advance(100.0 * CLOSE_MS)
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
	_state.pinned = false
	_state.advance(CLOSE_MS - 1.0)
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
	_state.advance(1.0)
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)


func test_the_pin_survives_the_collapse_button_and_another_unfold() -> void:
	_state.open(HudState.Unfold.RADAR)
	_state.pinned = true
	_state.open(HudState.Unfold.DRAWER)  # Opening another unfold closes even a pinned map.
	assert_int(_state.current).is_equal(HudState.Unfold.DRAWER)
	_state.open(HudState.Unfold.RADAR)
	_state.close(HudState.Unfold.RADAR)  # The collapse button too.
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	assert_bool(_state.pinned).is_true()  # The pin is the match's view state.


func test_the_time_comes_from_the_settings_it_was_given() -> void:
	var quick: InputSettings = InputSettings.new()
	quick.radar_close_ms = 1000
	var state: HudState = HudState.new(quick)
	state.open(HudState.Unfold.RADAR)
	state.advance(999.0)
	assert_int(state.current).is_equal(HudState.Unfold.RADAR)
	state.advance(1.0)
	assert_int(state.current).is_equal(HudState.Unfold.NONE)
