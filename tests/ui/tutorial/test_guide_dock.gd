extends GdUnitTestSuite
## `GuideDock.place` on crafted inputs (ADR 0048 section 1, plan P584): every rule at the six sizes
## of ScreenSizes.ALL and every profile of both orientations (read through CornersRig), mirrored
## and not, and the ADR's indicative table pinned within 1 dp.

const CornersRig: GDScript = preload("res://tests/ui/support/corners_rig.gd")
const TOLERANCE: float = 0.01
## ready, aim, bar: none; the Ready chip and the bar; the strike aim; all three.
const EXTRAS: Array[Array] = [
	[false, false, false], [true, false, true], [false, true, false], [true, true, true]
]
const SETTINGS: Dictionary[StringName, float] = {
	&"card_max_width_dp": 560.0,
	&"card_max_height_pct": 45.0,
}


func after_test() -> void:
	UiScale.clear_override()


## The ADR's table, in dp (dp 1), safe rects of the profiles in dp, one group column.
func test_the_adr_table_of_numbers() -> void:
	_pin(Rect2(0, 0, 890, 387), false, false, false, false, Rect2(73, 64, 560, 174))
	_pin(Rect2(0, 0, 890, 331), false, false, false, true, Rect2(64, 64, 498, 149))
	_pin(Rect2(0, 0, 776, 280), false, false, false, false, Rect2(64, 64, 428, 126))
	_pin(Rect2(0, 0, 776, 280), false, false, false, true, Rect2(64, 64, 384, 126))
	_pin(Rect2(0, 0, 336, 676), true, false, false, false, Rect2(64, 120, 272, 304))
	_pin(Rect2(0, 0, 336, 676), true, true, false, false, Rect2(64, 250, 272, 298))
	# The sheet (half of 676 dp) is open: the card ends 8 dp above it, 210 dp high.
	_pin(Rect2(0, 0, 336, 676), true, false, true, false, Rect2(64, 120, 272, 210))


func test_it_does_not_move_when_the_map_opens_landscape_and_drops_under_it_upright() -> void:
	for screen: Dictionary in CornersRig.screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		var portrait: bool = screen["portrait"]
		var closed: Rect2 = _dock(safe, portrait, dp, [false, false, 3, true, false])
		var open: Rect2 = _dock(safe, portrait, dp, [true, false, 3, true, false])
		if portrait:
			assert_float(open.position.y).is_greater(closed.position.y)
		else:
			assert_that(open).override_failure_message(screen["label"]).is_equal(closed)


func test_every_rule_at_every_size_and_profile() -> void:
	var checked: int = 0
	for screen: Dictionary in CornersRig.screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		var portrait: bool = screen["portrait"]
		for map_open: bool in [false, true]:
			for drawer: bool in [false, true]:
				for groups: int in [1, 3, 5]:
					for strike: bool in [false, true]:
						for mirror: bool in [false, true]:
							for extra: Array in EXTRAS:
								var args: Array = [map_open, drawer, groups, strike, mirror]
								args.append_array(extra)
								var why: String = "%s %s" % [screen["label"], args]
								var rects: Dictionary[StringName, Rect2] = _rects(
									safe, portrait, dp, args
								)
								var dock: Rect2 = GuideDock.place(
									safe, portrait, dp, mirror, rects, SETTINGS
								)
								_check(dock, rects, safe, portrait, dp, why)
								checked += 1
	assert_int(checked).is_greater(1000)


func test_mirrored_is_the_flip_of_the_unmirrored_dock() -> void:
	for screen: Dictionary in CornersRig.screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		var portrait: bool = screen["portrait"]
		var plain: Rect2 = _dock(safe, portrait, dp, [false, false, 3, true, false])
		var turned: Rect2 = _dock(safe, portrait, dp, [false, false, 3, true, true])
		var x: float = safe.position.x + safe.end.x - plain.end.x
		assert_float(turned.position.x).override_failure_message(screen["label"]).is_equal_approx(
			x, 0.05
		)
		assert_float(turned.size.x).is_equal_approx(plain.size.x, 0.05)
		assert_float(turned.position.y).is_equal_approx(plain.position.y, 0.05)


func test_the_settings_values_narrow_and_shorten_the_dock() -> void:
	var safe: Rect2 = Rect2(0, 0, 890, 387)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, false, 1.0, [false, false, 1, false, false]
	)
	var small: Dictionary[StringName, float] = {
		&"card_max_width_dp": 300.0, &"card_max_height_pct": 20.0
	}
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, small)
	assert_float(dock.size.x).is_equal_approx(300.0, 0.01)
	assert_float(dock.size.y).is_equal_approx(77.4, 0.01)
	assert_float(dock.get_center().x).is_equal_approx(64.0 + (578.0 / 2.0), 0.01)


func test_it_ends_16_dp_above_an_ad_band() -> void:
	var safe: Rect2 = Rect2(0, 0, 336, 676)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, true, 1.0, [false, false, 1, false, false]
	)
	rects[GuideDock.AD_BAND] = Rect2(0, 200, 336, 50)
	var dock: Rect2 = GuideDock.place(safe, true, 1.0, false, rects, SETTINGS)
	assert_float(dock.end.y).is_equal_approx(184.0, 0.01)


func test_it_is_empty_where_no_room_is_left() -> void:
	var safe: Rect2 = Rect2(0, 0, 336, 676)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, true, 1.0, [false, false, 1, false, false]
	)
	rects[GuideDock.AD_BAND] = Rect2(0, 130, 336, 50)
	assert_that(GuideDock.place(safe, true, 1.0, false, rects, SETTINGS).size).is_equal(
		Vector2.ZERO
	)


func test_the_field_point_is_in_the_open_field_under_the_dock() -> void:
	for screen: Dictionary in CornersRig.screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		var portrait: bool = screen["portrait"]
		for drawer: bool in [false, true]:
			for strike: bool in [false, true]:
				var args: Array = [false, drawer, 3, strike, false, true, false, true]
				var rects: Dictionary[StringName, Rect2] = _rects(safe, portrait, dp, args)
				var dock: Rect2 = GuideDock.place(safe, portrait, dp, false, rects, SETTINGS)
				var point: Vector2 = GuideDock.field_point(safe, dock, rects)
				var why: String = "%s %s: %s" % [screen["label"], args, point]
				assert_bool(safe.has_point(point)).override_failure_message(why).is_true()
				assert_float(point.y).override_failure_message(why).is_greater_equal(dock.end.y)
				for key: StringName in rects:
					if key != HudCorners.CARD:
						var inside: bool = rects[key].has_point(point)
						assert_bool(inside).override_failure_message(why + str(key)).is_false()


func test_the_field_point_on_crafted_rects() -> void:
	var safe: Rect2 = Rect2(0, 0, 890, 387)
	var dock: Rect2 = Rect2(64, 64, 500, 36)
	var rects: Dictionary[StringName, Rect2] = {
		HudCorners.BAR: Rect2(0, 300, 200, 64), HudCorners.BUILD: Rect2(800, 320, 64, 64)
	}
	var point: Vector2 = GuideDock.field_point(safe, dock, rects)
	assert_float(point.y).is_equal_approx(200.0, 0.01)
	assert_float(point.x).is_equal_approx(445.0, 0.01)
	rects.erase(HudCorners.BAR)  # BUILD alone: down to y 320.
	assert_float(GuideDock.field_point(safe, dock, rects).y).is_equal_approx(210.0, 0.01)
	rects.erase(HudCorners.BUILD)
	rects[HudCorners.BAR] = Rect2(0, 300, 200, 64)  # BAR alone.
	assert_float(GuideDock.field_point(safe, dock, rects).y).is_equal_approx(200.0, 0.01)
	rects.erase(HudCorners.BAR)
	rects[HudCorners.DRAWER] = Rect2(534, 0, 356, 387)  # The side panel at the right.
	assert_float(GuideDock.field_point(safe, dock, rects).x).is_equal_approx(267.0, 0.01)
	rects[HudCorners.DRAWER] = Rect2(0, 0, 356, 387)  # Mirrored, at the left.
	assert_float(GuideDock.field_point(safe, dock, rects).x).is_equal_approx(623.0, 0.01)
	rects.clear()  # An empty dock: from the safe top.
	assert_float(GuideDock.field_point(safe, Rect2(), rects).y).is_equal_approx(193.5, 0.01)
	assert_float(GuideDock.field_point(safe, dock, rects, 150.0).y).is_equal_approx(268.5, 0.01)


func test_the_field_point_keeps_clear_of_the_strike_button_and_the_sweep_line_upright() -> void:
	var safe: Rect2 = Rect2(0, 0, 336, 676)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, true, 1.0, [false, false, 1, true, false]
	)
	assert_bool(rects.has(HudCorners.REVEAL_LINE)).is_true()
	var dock: Rect2 = GuideDock.place(safe, true, 1.0, false, rects, SETTINGS)
	var point: Vector2 = GuideDock.field_point(safe, dock, rects)
	for key: StringName in rects:
		assert_bool(rects[key].has_point(point)).override_failure_message(str(key)).is_false()


func test_shown_for_dock_is_the_contract_of_what_it_reserves() -> void:
	var closed: HudCorners.Shown = GuideDock.shown_for_dock(true, false, false, 2, false)
	assert_bool(closed.toast).is_true()
	assert_bool(closed.map).is_false()
	var open: HudCorners.Shown = GuideDock.shown_for_dock(true, true, false, 2, false)
	assert_bool(open.map).is_true()
	assert_bool(open.toast).is_false()
	for map_open: bool in [false, true]:
		var wide: HudCorners.Shown = GuideDock.shown_for_dock(false, map_open, false, 2, false)
		assert_bool(wide.map).is_true()
		assert_bool(wide.toast).is_false()
	var all: HudCorners.Shown = GuideDock.shown_for_dock(
		true, false, true, 4, false, true, true, true
	)
	assert_bool(all.ready and all.aim and all.bar and all.drawer).is_true()
	assert_bool(all.strike).is_true()  # The aim implies the strike button.
	assert_int(all.groups).is_equal(4)


func test_the_ready_chip_is_reserved_upright() -> void:
	var safe: Rect2 = Rect2(0, 0, 336, 676)
	for strike: bool in [false, true]:
		var args: Array = [true, false, 1, strike, false, true]
		var rects: Dictionary[StringName, Rect2] = _rects(safe, true, 1.0, args)
		var dock: Rect2 = GuideDock.place(safe, true, 1.0, false, rects, SETTINGS)
		assert_float(dock.size.x).is_greater(0.0)
		assert_float(CornersRig.gap(dock, rects[HudCorners.READY])).is_greater_equal(
			8.0 - TOLERANCE
		)


func test_the_sweep_line_is_reserved_landscape() -> void:
	var safe: Rect2 = Rect2(0, 0, 890, 387)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, false, 1.0, [false, false, 1, true, false]
	)
	assert_bool(rects.has(HudCorners.REVEAL_LINE)).is_true()
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, SETTINGS)
	assert_float(CornersRig.gap(dock, rects[HudCorners.REVEAL_LINE])).is_greater_equal(
		8.0 - TOLERANCE
	)
	assert_float(dock.end.x).is_less_equal(rects[HudCorners.REVEAL_LINE].position.x - 8.0)


func test_the_strike_aim_row_and_the_moved_map_are_reserved() -> void:
	var safe: Rect2 = Rect2(0, 0, 776, 280)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, false, 1.0, [true, false, 1, true, false, false, true]
	)
	assert_bool(rects.has(HudCorners.STRIKE_ROW)).is_true()
	assert_float(rects[HudCorners.MAP].position.x).is_less(448.0)  # The map moved left.
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, SETTINGS)
	assert_float(dock.end.x).is_less_equal(rects[HudCorners.MAP].position.x - 8.0)
	assert_float(dock.end.x).is_less_equal(rects[HudCorners.STRIKE_ROW].position.x - 8.0)


func test_the_fallback_toast_beside_the_open_panel_is_reserved() -> void:
	var safe: Rect2 = Rect2(0, 0, 776, 280)
	var shown: HudCorners.Shown = GuideDock.shown_for_dock(false, false, true, 1, false)
	shown.pill_width = 320.0  # A wide pill beside the panel: the toast stands under the top line.
	var rects: Dictionary[StringName, Rect2] = GuideDock.hud_for_dock(
		safe, false, 1.0, false, shown
	)
	assert_float(rects[HudCorners.TOAST].position.y).is_equal_approx(64.0, 0.01)
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, SETTINGS)
	assert_float(dock.position.y).is_greater_equal(rects[HudCorners.TOAST].end.y + 8.0 - TOLERANCE)


func test_the_close_handle_of_the_side_panel_is_cleared() -> void:
	var safe: Rect2 = Rect2(0, 0, 890, 387)
	var rects: Dictionary[StringName, Rect2] = {HudCorners.DRAWER: Rect2(534, 0, 356, 387)}
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, SETTINGS)
	assert_float(dock.end.x).is_equal_approx(478.0, 0.01)  # 534 - 48 - 8.


func test_empty_settings_take_the_defaults() -> void:
	var safe: Rect2 = Rect2(0, 0, 890, 387)
	var rects: Dictionary[StringName, Rect2] = {}
	var none: Dictionary[StringName, float] = {}
	var dock: Rect2 = GuideDock.place(safe, false, 1.0, false, rects, none)
	assert_float(dock.size.x).is_equal_approx(560.0, 0.01)
	assert_float(dock.size.y).is_equal_approx(387.0 * 0.45, 0.01)


func test_the_ad_band_is_cleared_at_a_phone_dp_and_landscape() -> void:
	var dp: float = 2.625
	var safe: Rect2 = Rect2(10, 20, 336 * dp, 676 * dp)
	var rects: Dictionary[StringName, Rect2] = _rects(
		safe, true, dp, [false, false, 1, false, false]
	)
	rects[GuideDock.AD_BAND] = Rect2(safe.position.x, safe.position.y + 300 * dp, 336 * dp, 50 * dp)
	var dock: Rect2 = GuideDock.place(safe, true, dp, false, rects, SETTINGS)
	assert_float(dock.end.y).is_equal_approx(safe.position.y + 284.0 * dp, 0.05)
	var wide: Rect2 = Rect2(0, 0, 890, 387)
	var land: Dictionary[StringName, Rect2] = _rects(
		wide, false, 1.0, [false, false, 1, false, false]
	)
	land[GuideDock.AD_BAND] = Rect2(0, 180, 890, 50)
	assert_float(GuideDock.place(wide, false, 1.0, false, land, SETTINGS).end.y).is_equal_approx(
		164.0, 0.01
	)


func _check(
	dock: Rect2,
	rects: Dictionary[StringName, Rect2],
	safe: Rect2,
	portrait: bool,
	dp: float,
	why: String
) -> void:
	assert_float(dock.size.x).override_failure_message(why).is_greater(0.0)
	assert_bool(safe.grow(TOLERANCE).encloses(dock)).override_failure_message(why).is_true()
	assert_float(dock.size.x).override_failure_message(why).is_less_equal(560.0 * dp + TOLERANCE)
	assert_float(dock.size.y).override_failure_message(why).is_less_equal(
		safe.size.y * 0.45 + TOLERANCE
	)
	var map_end: float = rects[HudCorners.MAP].end.y if rects.has(HudCorners.MAP) else 0.0
	var top_row: float = rects[HudCorners.TOAST].end.y if rects.has(HudCorners.TOAST) else 0.0
	if portrait:
		var least: float = maxf(top_row, map_end) + 8.0 * dp - TOLERANCE
		assert_float(dock.position.y).override_failure_message(why).is_greater_equal(least)
	for key: StringName in rects:
		if key == HudCorners.CARD:
			continue
		var apart: float = CornersRig.gap(dock, rects[key])
		var at: String = "%s: %s %s is %s px from the dock %s" % [why, key, rects[key], apart, dock]
		assert_float(apart).override_failure_message(at).is_greater_equal(8.0 * dp - TOLERANCE)


func _pin(
	safe: Rect2, portrait: bool, map_open: bool, drawer: bool, strike: bool, expected: Rect2
) -> void:
	var dock: Rect2 = _dock(safe, portrait, 1.0, [map_open, drawer, 1, strike, false])
	var at: String = "%s, expected %s" % [dock, expected]
	for pair: Array in [
		[dock.position.x, expected.position.x],
		[dock.position.y, expected.position.y],
		[dock.size.x, expected.size.x],
		[dock.size.y, expected.size.y],
	]:
		assert_float(pair[0]).override_failure_message(at).is_equal_approx(pair[1], 1.0)


## `args`: map_open, drawer, groups, strike, mirror, then optionally ready, aim, bar.
func _rects(safe: Rect2, portrait: bool, dp: float, args: Array) -> Dictionary[StringName, Rect2]:
	var extra: Array = args.slice(5)
	extra.resize(3)
	var shown: HudCorners.Shown = GuideDock.shown_for_dock(
		portrait,
		args[0],
		args[1],
		args[2],
		args[3],
		extra[0] == true,
		extra[1] == true,
		extra[2] == true
	)
	return GuideDock.hud_for_dock(safe, portrait, dp, args[4], shown)


func _dock(safe: Rect2, portrait: bool, dp: float, args: Array) -> Rect2:
	var rects: Dictionary[StringName, Rect2] = _rects(safe, portrait, dp, args)
	return GuideDock.place(safe, portrait, dp, args[4], rects, SETTINGS)
