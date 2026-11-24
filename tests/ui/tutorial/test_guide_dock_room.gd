extends GdUnitTestSuite
## `GuideDock.has_room` and the fold to the tab (ADR 0048 section 1, plan P584).

const GuideDockRig: GDScript = preload("res://tests/ui/tutorial/support/guide_dock_rig.gd")
const SETTINGS: Dictionary[StringName, float] = {
	&"card_max_width_dp": 560.0,
	&"card_max_height_pct": 45.0,
}


func test_every_table_profile_has_room() -> void:
	var cases: Array[Array] = [
		[Rect2(0, 0, 890, 387), false, false, false, false],
		[Rect2(0, 0, 890, 331), false, false, false, true],
		[Rect2(0, 0, 776, 280), false, false, false, false],
		[Rect2(0, 0, 776, 280), false, false, false, true],
		[Rect2(0, 0, 336, 676), true, false, false, false],
		[Rect2(0, 0, 336, 676), true, true, false, false],
		[Rect2(0, 0, 336, 676), true, false, true, false],
	]
	for c: Array in cases:
		var dock: Rect2 = _dock(c[0], c[1], [c[2], c[3], 1, c[4], false])
		assert_bool(GuideDock.has_room(dock, 1.0)).override_failure_message(str(c)).is_true()


## The P581 state (bar 106 dp high): 776x280, five group buttons in one row, the map at x 320.
func test_no_room_folds_the_card_to_its_tab() -> void:
	var safe: Rect2 = Rect2(0, 0, 776, 280)
	var rects: Dictionary[StringName, Rect2] = {
		HudCorners.BAR: Rect2(0, 174, 120, 106),
		HudCorners.READY: Rect2(592, 224, 112, 48),
		HudCorners.STRIKE_ROW: Rect2(560, 140, 136, 64),
		HudCorners.STRIKE: Rect2(704, 136, 72, 72),
		HudCorners.BUILD: Rect2(712, 216, 64, 64),
		HudCorners.MAP: Rect2(320, 0, 232, 164),
		HudCorners.REVEAL_LINE: Rect2(500, 80, 220, 48),
		HudCorners.REVEAL: Rect2(728, 80, 48, 48),
		HudCorners.SCOPE: Rect2(720, 0, 56, 56),
	}
	for index: int in 5:
		rects[HudCorners.group_key(index)] = Rect2(64.0 * index, 56, 56, 56)
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, SETTINGS)
	assert_that(dock).is_equal(Rect2())
	assert_bool(GuideDock.has_room(dock, 1.0)).is_false()
	assert_bool(GuideDockRig.free_rect(rects, safe, 1.0)).is_false()


func test_a_group_button_below_the_dock_does_not_narrow_it() -> void:
	var safe: Rect2 = Rect2(0, 0, 890, 387)
	var near: Dictionary[StringName, Rect2] = {HudCorners.group_key(0): Rect2(0, 56, 56, 56)}
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, near, SETTINGS)
	var far: Dictionary[StringName, Rect2] = near.duplicate()
	far[HudCorners.group_key(1)] = Rect2(64, 330, 56, 56)  # Under the dock's foot (238).
	assert_that(GuideDock.place(safe, false, 1.0, false, far, SETTINGS)).is_equal(dock)
	far[HudCorners.group_key(1)] = Rect2(64, 200, 56, 56)  # In the dock's rows.
	var narrowed: Rect2 = GuideDock.place(safe, false, 1.0, false, far, SETTINGS)
	assert_float(narrowed.position.x).is_greater_equal(128.0)


func _dock(safe: Rect2, portrait: bool, args: Array) -> Rect2:
	var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(safe, portrait, 1.0, args)
	return GuideDock.place(safe, portrait, 1.0, false, rects, SETTINGS)
