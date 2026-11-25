extends GdUnitTestSuite
## The folded tab's slot (ADR 0048 section 1, "No room", plan P588): `GuideDock.tab_slot` in both
## fold states of the ADR, with the pill at its least and at its widest, mirrored, and the empty
## answer where nothing is free.

const GuideDockRig: GDScript = preload("res://tests/ui/tutorial/support/guide_dock_rig.gd")
const SETTINGS: Dictionary[StringName, float] = {
	&"card_max_width_dp": 560.0,
	&"card_max_height_pct": 45.0,
}
const WIDE_PILL_DP: float = 372.0
## The fold states of section 1, by the rig's arguments (map open, drawer, groups, strike, mirror,
## ready, aim, bar, bar_tall): state 1 is five groups with the aim, the Ready chip and the bar at
## either height, with and without a cutout; state 2 the cutout with the drawer open and the tall
## bar.
const STATE_ONE: Array[Array] = [
	[Rect2(0, 0, 776, 280), [false, false, 5, true, false, true, true, true, true]],
	[Rect2(0, 0, 710, 280), [false, false, 5, true, false, true, true, true, true]],
	[Rect2(0, 0, 710, 280), [false, false, 5, true, false, true, true, true, false]],
]
const STATE_TWO: Array[Array] = [
	[Rect2(0, 0, 710, 280), [false, true, 1, false, false, true, false, true, true]],
]


func test_both_fold_states_give_the_tab_a_free_slot_in_the_top_row() -> void:
	for state: Array in STATE_ONE + STATE_TWO:
		var safe: Rect2 = state[0]
		var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(safe, false, 1.0, state[1])
		var label: String = str(state)
		(
			assert_bool(
				GuideDock.has_room(GuideDock.place(safe, false, 1.0, false, rects, SETTINGS), 1.0)
			)
			. override_failure_message(label + ": not a fold state")
			. is_false()
		)
		var slot: Rect2 = GuideDock.tab_slot(safe, 1.0, false, rects)
		_expect_free(slot, safe, rects, label, true)


func test_the_slot_is_the_one_nearest_the_scope() -> void:
	var safe: Rect2 = Rect2(0, 0, 776, 280)
	var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(safe, false, 1.0, STATE_ONE[0][1])
	var slot: Rect2 = GuideDock.tab_slot(safe, 1.0, false, rects)
	# The scope stands at x 720: the slot ends 8 dp short of it.
	assert_float(slot.end.x).is_equal_approx(rects[HudCorners.SCOPE].position.x - 8.0, 0.01)
	# With the drawer open there is no scope: the slot ends 8 dp short of the panel's handle.
	var open: Rect2 = Rect2(0, 0, 710, 280)
	var drawer: Dictionary[StringName, Rect2] = GuideDockRig.rects(
		open, false, 1.0, STATE_TWO[0][1]
	)
	var near: Rect2 = GuideDock.tab_slot(open, 1.0, false, drawer)
	assert_float(near.end.x).is_equal_approx(
		drawer[HudCorners.DRAWER].position.x - HudCorners.CLOSE_DP - 8.0, 0.01
	)


func test_a_mirrored_hud_mirrors_the_slot() -> void:
	for state: Array in STATE_ONE + STATE_TWO:
		var safe: Rect2 = state[0]
		var args: Array = state[1].duplicate()
		args[4] = true
		var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(safe, false, 1.0, args)
		var slot: Rect2 = GuideDock.tab_slot(safe, 1.0, true, rects)
		_expect_free(slot, safe, rects, "mirrored " + str(state), true)
		var plain: Rect2 = GuideDock.tab_slot(
			safe, 1.0, false, GuideDockRig.rects(safe, false, 1.0, state[1])
		)
		assert_float(slot.position.x).is_equal_approx(safe.size.x - plain.end.x, 0.01)


## A wide pill and a toast slot leave no square between them: the tab may then stand on the toast's
## slot (a toast is brief) but on no other part.
func test_a_wide_pill_lets_the_tab_stand_on_the_toast_slot_only() -> void:
	var safe: Rect2 = Rect2(0, 0, 710, 280)
	var shown: HudCorners.Shown = GuideDock.shown_for_dock(
		false, false, false, 5, true, true, true, true, true
	)
	shown.pill_width = WIDE_PILL_DP
	var rects: Dictionary[StringName, Rect2] = GuideDock.hud_for_dock(
		safe, false, 1.0, false, shown
	)
	var slot: Rect2 = GuideDock.tab_slot(safe, 1.0, false, rects)
	_expect_free(slot, safe, rects, "wide pill", false)
	assert_bool(slot.grow(7.99).intersects(rects[HudCorners.TOAST])).is_true()


func test_the_economy_card_is_not_a_reserve() -> void:
	var safe: Rect2 = Rect2(0, 0, 776, 280)
	var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(safe, false, 1.0, STATE_ONE[0][1])
	var plain: Rect2 = GuideDock.tab_slot(safe, 1.0, false, rects)
	rects[HudCorners.CARD] = Rect2(plain.position - Vector2(10, 0), Vector2(280, 120))
	assert_that(GuideDock.tab_slot(safe, 1.0, false, rects)).is_equal(plain)


func test_a_top_row_with_no_free_square_gives_no_slot() -> void:
	var safe: Rect2 = Rect2(0, 0, 400, 280)
	var rects: Dictionary[StringName, Rect2] = {HudCorners.PILL: Rect2(0, 0, 400, 48)}
	assert_that(GuideDock.tab_slot(safe, 1.0, false, rects)).is_equal(Rect2())


func test_a_dp_other_than_one_scales_the_slot() -> void:
	var safe: Rect2 = Rect2(20, 10, 1552, 560)  # 776 x 280 dp at 2 px per dp.
	var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(safe, false, 2.0, STATE_ONE[0][1])
	var slot: Rect2 = GuideDock.tab_slot(safe, 2.0, false, rects)
	assert_vector(slot.size).is_equal_approx(Vector2(96, 96), Vector2.ONE * 0.01)
	_expect_free(slot, safe, rects, "2 px per dp", true, 2.0)


## `slot` is a 48 dp square inside `safe` on its top edge, 8 dp from every part of `rects` (the
## economy card aside), the toast slot included when `with_toast`.
func _expect_free(
	slot: Rect2,
	safe: Rect2,
	rects: Dictionary[StringName, Rect2],
	label: String,
	with_toast: bool,
	dp: float = 1.0
) -> void:
	assert_bool(slot.has_area()).override_failure_message(label + ": no slot").is_true()
	assert_vector(slot.size).is_equal_approx(Vector2(48.0, 48.0) * dp, Vector2.ONE * 0.01)
	assert_bool(safe.grow(0.01).encloses(slot)).override_failure_message(label).is_true()
	assert_float(slot.position.y).is_equal_approx(safe.position.y, 0.01)
	for key: StringName in rects:
		if key == HudCorners.CARD or (key == HudCorners.TOAST and not with_toast):
			continue
		var apart: float = GuideDockRig.gap(slot, rects[key]) / dp
		(
			assert_float(apart)
			. override_failure_message("%s: the slot is %s dp from %s" % [label, apart, key])
			. is_greater_equal(8.0 - 0.01)
		)
	if rects.has(HudCorners.DRAWER):  # The side panel's close handle, a 48 dp strip left of it.
		var handle: Rect2 = rects[HudCorners.DRAWER]
		handle = Rect2(handle.position.x - 48.0 * dp, handle.position.y, 48.0 * dp, handle.size.y)
		assert_float(GuideDockRig.gap(slot, handle) / dp).is_greater_equal(8.0 - 0.01)
