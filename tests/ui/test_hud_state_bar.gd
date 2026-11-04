extends GdUnitTestSuite
## The command bar's slot and width in `HudState` (plan P122): `set_bar` tells `changed` once per
## real change, with the open unfold unchanged; `fill_bar` hands `HudCorners.place` the two entries;
## `fill` leaves them alone.

var _state: HudState
var _told: Array[HudState.Unfold] = []


func before_test() -> void:
	_state = HudState.new()
	_told.clear()
	_state.changed.connect(func(previous: HudState.Unfold) -> void: _told.append(previous))


func test_set_bar_tells_changed_once_per_real_change_with_the_open_unfold() -> void:
	_state.set_bar(true, 200.0)
	assert_int(_told.size()).is_equal(1)
	assert_int(_told[0]).is_equal(HudState.Unfold.NONE)
	_state.set_bar(true, 200.0)
	assert_int(_told.size()).is_equal(1)
	_state.open(HudState.Unfold.RADAR)
	_told.clear()
	_state.set_bar(true, 260.0)
	assert_array(_told).is_equal([HudState.Unfold.RADAR])
	_state.set_bar(false, 260.0)
	assert_int(_told.size()).is_equal(2)


func test_fill_bar_sets_the_two_entries_and_fill_leaves_them() -> void:
	_state.set_bar(true, 222.0)
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	_state.fill(shown)
	assert_bool(shown.bar).is_false()
	assert_float(shown.bar_width).is_equal(0.0)
	_state.fill_bar(shown)
	assert_bool(shown.bar).is_true()
	assert_float(shown.bar_width).is_equal(222.0)
	_state.set_bar(false, 0.0)
	_state.fill_bar(shown)
	assert_bool(shown.bar).is_false()
