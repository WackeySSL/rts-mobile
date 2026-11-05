extends GdUnitTestSuite
## `HudCorners.place` on crafted inputs (ADR 0025 sections 2 and 14, plan P119): ADR 0025 section
## 2's table of numbers row by row on the short screens, then every combination of what shows at
## the six sizes of ScreenSizes.ALL, at every profile of both orientations (also with a cutout and
## with the design's insets) and mirrored and not: every rect is inside the safe rect, no two
## overlap, every rect is at least 48 dp on each side, and the sizes the ADR names hold.

const CornersRig: GDScript = preload("res://tests/ui/support/corners_rig.gd")
const CardHeights: GDScript = preload("res://tests/support/card_heights.gd")
const TOLERANCE: float = 0.01
## The unfolds and modes of ADR 0025 section 1: at most one at a time. The card is an overlay on
## the toast, the group column and the command bar, so those pairs are left out of the overlap
## check.
const EXTRAS: Array[String] = ["", "map", "toast", "drawer", "card", "aim"]
const WIDE_BAR_DP: float = 2000.0  ## A bar that asks for more than any screen has.


func after_test() -> void:
	UiScale.clear_override()


## ADR 0025 section 2's table, in dp (dp 1), for the four rows it names.
func test_the_adr_table_of_numbers_row_by_row() -> void:
	# web_phone_small: 800 x 304, safe 776 x 280.
	var small: Rect2 = Rect2(0.0, 0.0, 776.0, 280.0)
	var lined: Dictionary[StringName, Rect2] = _place(small, false, _shown(["bar", "strike"], 4))
	_assert_rect(lined[HudCorners.BUILD], Rect2(712.0, 216.0, 64.0, 64.0))
	_assert_rect(lined[HudCorners.STRIKE], Rect2(704.0, 136.0, 72.0, 72.0))
	assert_int(_column(lined, 4)).is_equal(2)  # 152 dp with the bar: two to a column.
	_assert_rect(lined[HudCorners.group_key(0)], Rect2(0.0, 56.0, 56.0, 56.0))
	_assert_rect(lined[HudCorners.group_key(1)], Rect2(0.0, 120.0, 56.0, 56.0))
	_assert_rect(lined[HudCorners.group_key(2)], Rect2(64.0, 56.0, 56.0, 56.0))
	# The bar, as wide as it asks, ends a gap before BUILD's column (72 dp), before the Ready chip's
	# 120 dp more, and before the open panel (the panel is 312 dp here: 40 % of 776 is less).
	var wide: Dictionary[StringName, Rect2] = _place(small, false, _shown(["bar"], 1, 2000.0))
	assert_float(wide[HudCorners.BAR].end.x).is_equal(776.0 - 72.0)
	wide = _place(small, false, _shown(["bar", "ready"], 1, 2000.0))
	assert_float(wide[HudCorners.BAR].end.x).is_equal(776.0 - 192.0)
	_assert_rect(wide[HudCorners.READY], Rect2(592.0, 224.0, 112.0, 48.0))  # A gap left of BUILD.
	wide = _place(small, false, _shown(["bar", "drawer"], 1, 2000.0))
	assert_float(wide[HudCorners.BAR].end.x).is_equal(wide[HudCorners.DRAWER].position.x - 8.0)
	wide = _place(small, false, _shown(["strike", "aim"]))
	_assert_rect(wide[HudCorners.STRIKE_ROW], Rect2(560.0, 140.0, 136.0, 64.0))  # A gap left of it.
	var map: Dictionary[StringName, Rect2] = _place(small, false, _shown(["strike", "map"]))
	_assert_rect(map[HudCorners.MAP], Rect2(456.0, 0.0, 240.0, 168.0))  # Left of the column.
	_assert_rect(map[HudCorners.MAP_BOX], Rect2(456.0, 48.0, 240.0, 120.0))
	map = _place(small, false, _shown(["map"]))
	_assert_rect(map[HudCorners.MAP], Rect2(584.0, 64.0, 192.0, 144.0))  # Under the scope.
	_assert_rect(map[HudCorners.MAP_BOX], Rect2(584.0, 112.0, 192.0, 96.0))
	assert_int(_column(_place(small, false, _shown([], 6)), 6)).is_equal(3)  # 224 dp: three.
	# web_phone: 914 x 355, safe 890 x 331.
	var phone: Rect2 = Rect2(0.0, 0.0, 890.0, 331.0)
	lined = _place(phone, false, _shown(["bar", "strike"], 6))
	_assert_rect(lined[HudCorners.BUILD], Rect2(826.0, 267.0, 64.0, 64.0))
	_assert_rect(lined[HudCorners.STRIKE], Rect2(818.0, 187.0, 72.0, 72.0))
	assert_int(_column(lined, 6)).is_equal(3)  # 203 dp.
	assert_int(_column(_place(phone, false, _shown([], 6)), 6)).is_equal(4)  # 275 dp.
	map = _place(phone, false, _shown(["bar", "strike", "map"]))
	_assert_rect(map[HudCorners.MAP], Rect2(570.0, 0.0, 240.0, 168.0))  # The strike button blocks.
	map = _place(phone, false, _shown(["bar", "map"]))
	_assert_rect(map[HudCorners.MAP], Rect2(650.0, 64.0, 240.0, 168.0))
	# The 6-inch phone, landscape: 914 x 411, safe 890 x 387.
	var big: Rect2 = Rect2(0.0, 0.0, 890.0, 387.0)
	lined = _place(big, false, _shown(["bar", "strike", "map"], 6))
	_assert_rect(lined[HudCorners.BUILD], Rect2(826.0, 323.0, 64.0, 64.0))
	_assert_rect(lined[HudCorners.STRIKE], Rect2(818.0, 243.0, 72.0, 72.0))
	_assert_rect(lined[HudCorners.MAP], Rect2(650.0, 64.0, 240.0, 168.0))
	assert_int(_column(lined, 6)).is_equal(4)  # 259 dp with the bar.
	# web_phone_portrait: 360 x 700, safe 336 x 676.
	var upright: Rect2 = Rect2(0.0, 0.0, 336.0, 676.0)
	lined = _place(upright, true, _shown(["bar", "strike", "map"], 5))
	# Michael, 2026-11-05: the landscape corners upright too.
	_assert_rect(lined[HudCorners.BAR], Rect2(0.0, 612.0, 120.0, 64.0))  # As wide as its content.
	_assert_rect(lined[HudCorners.BUILD], Rect2(272.0, 612.0, 64.0, 64.0))  # The corner.
	_assert_rect(lined[HudCorners.STRIKE], Rect2(264.0, 532.0, 72.0, 72.0))
	_assert_rect(lined[HudCorners.MAP], Rect2(76.0, 64.0, 260.0, 178.0))
	assert_int(_column(lined, 5)).is_equal(5)  # 548 dp from under the pill to the bar: all five.
	_assert_rect(lined[HudCorners.group_key(0)], Rect2(0.0, 56.0, 56.0, 56.0))


## The pinned full map stays open through a strike aim (plan P120c). Under the scope it is clear of
## the row by its height; left of the column on a short screen it ends a gap left of the check mark
## and the X and narrows (2:1, 192 dp wide at the least) to start a gap right of the pill, however
## wide the pill is (to 320 dp here; the cap is 372), down to the width where both fit; with no aim,
## or a row that stands below the map, it is the ADR table's.
func test_the_pinned_map_with_the_aim_keeps_clear_of_the_row_and_the_pill() -> void:
	var plain: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 776.0, 280.0), false, _shown(["strike", "map"])
	)
	_assert_rect(plain[HudCorners.MAP], Rect2(456.0, 0.0, 240.0, 168.0))  # The ADR table's.
	for width: float in [776.0, 760.0, 744.0]:
		for pill: float in [200.0, 260.0, 320.0]:
			var shown: HudCorners.Shown = _shown(["strike", "aim", "map"])
			shown.pill_width = pill
			var out: Dictionary[StringName, Rect2] = _place(
				Rect2(0.0, 0.0, width, 280.0), false, shown
			)
			var why: String = "safe %s, pill %s: %s" % [width, pill, out]
			var map: Rect2 = out[HudCorners.MAP]
			var box: Rect2 = out[HudCorners.MAP_BOX]
			assert_float(box.size.y).override_failure_message(why).is_greater_equal(96.0)
			assert_float(box.size.x).override_failure_message(why).is_equal_approx(
				2.0 * box.size.y, TOLERANCE
			)
			assert_float(box.size.x).override_failure_message(why).is_less_equal(240.0)
			assert_float(out[HudCorners.STRIKE_ROW].position.x - map.end.x).is_greater_equal(8.0)
			(
				assert_float(map.position.x - out[HudCorners.PILL].end.x)
				. override_failure_message(why)
				. is_greater_equal(8.0 - TOLERANCE)
			)
			for key: StringName in [
				HudCorners.PILL,
				HudCorners.SCOPE,
				HudCorners.STRIKE,
				HudCorners.STRIKE_ROW,
				HudCorners.BUILD
			]:
				(
					assert_bool(map.intersects(out[key]))
					. override_failure_message("%s: %s" % [why, key])
					. is_false()
				)
	# Under the scope (a taller screen) the aim changes nothing: the map ends above the button.
	var tall_shown: HudCorners.Shown = _shown(["strike", "aim", "map"])
	var tall: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, tall_shown
	)
	_assert_rect(tall[HudCorners.MAP], Rect2(650.0, 64.0, 240.0, 168.0))
	assert_bool(tall[HudCorners.MAP].intersects(tall[HudCorners.STRIKE_ROW])).is_false()
	# A row that stands below the map's foot leaves it where the table puts it.
	var low: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 776.0, 330.0), false, _shown(["strike", "aim", "map"])
	)
	assert_bool(low[HudCorners.MAP].intersects(low[HudCorners.STRIKE_ROW])).is_false()


## The row is "in the way" of the left-of-column map while it starts above the box's foot plus a
## gap (box foot 168 dp): at a safe height of 312 dp the row starts at 172, 4 dp under the foot,
## and the map steps aside by the gap; at 316 it starts at 176, a gap under it, and the map stays.
func test_the_map_steps_aside_for_a_row_that_is_less_than_a_gap_below_its_foot() -> void:
	for height: float in [312.0, 316.0]:
		var out: Dictionary[StringName, Rect2] = _place(
			Rect2(0.0, 0.0, 776.0, height), false, _shown(["strike", "aim", "map"])
		)
		var map: Rect2 = out[HudCorners.MAP]
		var row: Rect2 = out[HudCorners.STRIKE_ROW]
		var across: float = row.position.x - map.end.x
		var along: float = row.position.y - map.end.y
		assert_float(maxf(across, along)).override_failure_message(str(height)).is_greater_equal(
			8.0
		)
		if height > 314.0:
			assert_float(map.end.x).is_equal(776.0 - 80.0)  # Where the table has it.
		else:
			assert_float(across).is_greater_equal(8.0)
			assert_float(map.end.x).is_less(776.0 - 80.0)


## ADR 0025 section 10: the strike button 8 dp above BUILD at 72 dp, its row to its left, upright
## too (with or without the command bar), on every table profile; the rects the lead checks
## against the group column are these.
func test_the_strike_button_is_8_dp_above_build_and_its_row_left_of_it() -> void:
	for portrait: bool in [false, true]:
		for bar: bool in [false, true]:
			var names: Array[String] = ["strike", "aim"]
			if bar:
				names.append("bar")
			var shown: HudCorners.Shown = _shown(names)
			var safe: Rect2 = (
				Rect2(0.0, 0.0, 336.0, 676.0) if portrait else Rect2(0.0, 0.0, 776.0, 280.0)
			)
			var out: Dictionary[StringName, Rect2] = _place(safe, portrait, shown)
			var why: String = "portrait %s, bar %s" % [portrait, bar]
			var build: Rect2 = out[HudCorners.BUILD]
			var strike: Rect2 = out[HudCorners.STRIKE]
			assert_float(strike.size.x).override_failure_message(why).is_equal(72.0)
			assert_float(strike.end.x).override_failure_message(why).is_equal(build.end.x)
			assert_float(build.position.y - strike.end.y).override_failure_message(why).is_equal(
				8.0
			)
			var row: Rect2 = out[HudCorners.STRIKE_ROW]
			assert_float(strike.position.x - row.end.x).override_failure_message(why).is_equal(8.0)
			assert_float(row.size.x).is_equal(136.0)
			assert_float(row.size.y).is_equal(64.0)
			assert_float(row.get_center().y).is_equal(strike.get_center().y)


func test_with_nothing_shown_only_the_four_anchors_and_all_army_are_placed() -> void:
	var out: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, HudCorners.Shown.new()
	)
	assert_array(out.keys()).contains_exactly_in_any_order(
		[HudCorners.PILL, HudCorners.SCOPE, HudCorners.BUILD, HudCorners.group_key(0)]
	)
	_assert_rect(out[HudCorners.SCOPE], Rect2(834.0, 0.0, 56.0, 56.0))
	_assert_rect(out[HudCorners.BUILD], Rect2(826.0, 323.0, 64.0, 64.0))
	_assert_rect(out[HudCorners.PILL], Rect2(0.0, 0.0, 200.0, 48.0))
	var share: float = 0.0
	for key: StringName in [HudCorners.PILL, HudCorners.SCOPE, HudCorners.BUILD]:
		share += out[key].get_area()  # The scope and BUILD are round: less than their squares.
	assert_float(share / (890.0 * 387.0)).is_less(0.07)


func test_the_pill_stands_in_the_corner_and_stays_clear_of_the_scope() -> void:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)
	_assert_rect(out[HudCorners.PILL], Rect2(0.0, 0.0, 200.0, 48.0))  # Nothing stands before it.
	assert_float(out[HudCorners.PILL].end.x).is_less_equal(out[HudCorners.SCOPE].position.x - 8.0)
	shown.pill_width = 290.0  # A wider content takes what is left, no more than the scope allows.
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)
	assert_float(out[HudCorners.PILL].size.x).is_equal(272.0)
	out = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	assert_float(out[HudCorners.PILL].size.x).is_equal(290.0)
	shown.pill_width = 900.0
	out = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	assert_float(out[HudCorners.PILL].size.x).is_equal(HudCorners.PILL_MAX_DP)


func test_the_pill_stays_in_its_corner_with_the_drawer_open_and_ends_short_of_the_panel() -> void:
	var shown: HudCorners.Shown = _shown(["drawer", "toast"], 1)
	shown.pill_width = 900.0
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 776.0, 280.0), false, shown)
	# The panel is at 464: the widest pill (372) ends a gap short of it; the toast, with 76 dp left
	# of the panel, stands under the top line, right of the group column.
	_assert_rect(out[HudCorners.PILL], Rect2(0.0, 0.0, 372.0, 48.0))
	_assert_rect(out[HudCorners.TOAST], Rect2(64.0, 64.0, 280.0, 48.0))
	shown.pill_width = 0.0
	out = _place(Rect2(0.0, 0.0, 776.0, 280.0), false, shown)
	_assert_rect(out[HudCorners.PILL], Rect2(0.0, 0.0, 200.0, 48.0))
	_assert_rect(out[HudCorners.TOAST], Rect2(208.0, 0.0, 248.0, 48.0))  # Between pill and panel.
	shown.pill_width = 900.0
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)
	_assert_rect(out[HudCorners.PILL], Rect2(0.0, 0.0, 272.0, 48.0))  # Short of the scope, as shut.
	assert_bool(out.has(HudCorners.SCOPE)).is_true()  # The scope stays over the sheet.
	assert_bool(out[HudCorners.PILL].intersects(out[HudCorners.DRAWER])).is_false()


## A narrow room left of the panel narrows the pill (never under its 48 dp height) and sends the
## toast to the top line, from the edge or, where the group column stands there, a gap right of it.
func test_a_narrow_room_beside_the_panel_narrows_the_pill_and_sends_the_toast_down() -> void:
	var shown: HudCorners.Shown = _shown(["drawer", "toast"], 1)
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 500.0, 280.0), false, shown)
	assert_float(out[HudCorners.PILL].end.x).is_equal(180.0)  # Panel at 188: a gap short of it.
	_assert_rect(out[HudCorners.TOAST], Rect2(64.0, 64.0, 116.0, 48.0))
	out = _place(Rect2(0.0, 0.0, 900.0, 280.0), false, shown)  # Panel at 540: room for both.
	assert_float(out[HudCorners.TOAST].position.y).is_equal(0.0)
	assert_bool(out[HudCorners.TOAST].intersects(out[HudCorners.PILL])).is_false()
	assert_float(out[HudCorners.TOAST].end.x).is_less_equal(out[HudCorners.DRAWER].position.x - 8.0)


func test_the_drawer_is_a_side_panel_of_40_percent_between_312_and_420_dp_or_a_half_sheet() -> void:
	var shown: HudCorners.Shown = _shown(["drawer", "bar", "strike", "ready"], 4)
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 776.0, 280.0), false, shown)
	_assert_rect(out[HudCorners.DRAWER], Rect2(464.0, 0.0, 312.0, 280.0))  # 40 % is 310: the least.
	out = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	_assert_rect(out[HudCorners.DRAWER], Rect2(534.0, 0.0, 356.0, 387.0))
	out = _place(Rect2(0.0, 0.0, 1400.0, 700.0), false, shown)
	assert_float(out[HudCorners.DRAWER].size.x).is_equal(420.0)
	# Beside the panel: the pill, the bar and the groups; under it: the right column.
	assert_array(out.keys()).contains_exactly_in_any_order(
		[
			HudCorners.DRAWER,
			HudCorners.PILL,
			HudCorners.BAR,
			HudCorners.group_key(0),
			HudCorners.group_key(1),
			HudCorners.group_key(2),
			HudCorners.group_key(3)
		]
	)
	assert_float(out[HudCorners.BAR].end.x).is_less_equal(out[HudCorners.DRAWER].position.x - 8.0)
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)  # The sheet: the scope stays.
	_assert_rect(out[HudCorners.DRAWER], Rect2(0.0, 338.0, 336.0, 338.0))
	assert_bool(out.has(HudCorners.SCOPE)).is_true()
	assert_bool(out.has(HudCorners.BUILD)).is_false()  # BUILD, the bar and the chip are covered.
	assert_bool(out.has(HudCorners.BAR)).is_false()
	out = _place(Rect2(0.0, 0.0, 776.0, 300.0), true, shown)  # Half of 300 is under 312.
	assert_float(out[HudCorners.DRAWER].size.y).is_equal(300.0)


func test_the_toast_sits_between_the_pill_and_the_scope_or_under_the_pill() -> void:
	var land: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, _shown(["toast"])
	)
	_assert_rect(land[HudCorners.TOAST], Rect2(377.0, 0.0, 280.0, 48.0))  # Centred in 208..826.
	var upright: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 336.0, 676.0), true, _shown(["toast"])
	)
	# Under the scope, right of the column.
	_assert_rect(upright[HudCorners.TOAST], Rect2(64.0, 64.0, 272.0, 48.0))
	upright = _place(Rect2(0.0, 0.0, 800.0, 900.0), true, _shown(["toast"]))
	assert_float(upright[HudCorners.TOAST].size.x).is_equal(360.0)
	var open: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, _shown(["toast", "map"])
	)
	assert_bool(open.has(HudCorners.TOAST)).is_false()  # Never beside the full map.
	var panel: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, _shown(["toast", "drawer"])
	)  # The pill at the edge, no scope: the toast stands between the pill and the panel.
	assert_float(panel[HudCorners.TOAST].end.x).is_less_equal(
		panel[HudCorners.DRAWER].position.x - 8.0
	)


func test_the_economy_card_hangs_under_the_pill_280_wide() -> void:
	var shown: HudCorners.Shown = _shown(["card"])
	shown.card_height = 150.0
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	_assert_rect(out[HudCorners.CARD], Rect2(0.0, 56.0, 280.0, 150.0))
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)  # The safe width at most.
	_assert_rect(out[HudCorners.CARD], Rect2(0.0, 56.0, 280.0, 150.0))
	out = _place(Rect2(0.0, 0.0, 300.0, 676.0), true, shown)
	assert_float(out[HudCorners.CARD].end.x).is_less_equal(300.0)


## The economy card at its tallest (six kinds of consumer and the low-power line, `CardHeights`;
## test_economy_card.gd measures the real one against that number) under the pill, with every
## combination of the other parts, at every screen, mirrored and not: inside the
## safe rect, and clear of every part but the three it may cover (the toast, the groups and, on the
## short landscape screens, the command bar).
func test_the_tallest_economy_card_stays_inside_and_covers_only_its_overlay() -> void:
	var checked: int = 0
	var covered_bar: int = 0
	for screen: Dictionary in _screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		for shown: HudCorners.Shown in _combinations():
			if not shown.card:
				continue
			shown.card_height = CardHeights.TALLEST_DP
			for mirror: bool in [false, true]:
				var out: Dictionary[StringName, Rect2] = HudCorners.place(
					safe, screen["portrait"], dp, mirror, shown
				)
				var why: String = "%s, mirror %s, %s" % [screen["label"], mirror, _describe(shown)]
				_assert_parts(out, safe, dp, why)
				var card: Rect2 = out[HudCorners.CARD]
				assert_float(card.size.y / dp).override_failure_message(why).is_equal_approx(
					CardHeights.TALLEST_DP, TOLERANCE
				)
				if out.has(HudCorners.BAR) and card.intersects(out[HudCorners.BAR]):
					covered_bar += 1
				checked += 1
	assert_int(checked).is_greater(200)
	assert_int(covered_bar).is_greater(0)  # The short screens: the card does cover the bar.


func test_mirrored_every_rect_is_the_other_side_of_the_safe_rect() -> void:
	var safe: Rect2 = Rect2(24.0, 12.0, 890.0, 387.0)
	var shown: HudCorners.Shown = _shown(["bar", "ready", "strike", "toast"], 3)
	var plain: Dictionary[StringName, Rect2] = HudCorners.place(safe, false, 1.0, false, shown)
	var flipped: Dictionary[StringName, Rect2] = HudCorners.place(safe, false, 1.0, true, shown)
	assert_array(flipped.keys()).contains_exactly_in_any_order(plain.keys())
	for key: StringName in plain:
		var rect: Rect2 = plain[key]
		var want_x: float = safe.position.x + safe.end.x - rect.end.x
		assert_float(flipped[key].position.x).override_failure_message(str(key)).is_equal_approx(
			want_x, TOLERANCE
		)
		assert_float(flipped[key].position.y).is_equal(rect.position.y)
		assert_that(flipped[key].size).is_equal(rect.size)


## The rects scale with the dp and move with the safe rect's corner.
func test_the_result_is_in_base_px_from_the_safe_rects_corner() -> void:
	var shown: HudCorners.Shown = _shown(["bar", "strike"], 2)
	var unit: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 776.0, 280.0), false, shown)
	var scaled: Dictionary[StringName, Rect2] = HudCorners.place(
		Rect2(30.0, 20.0, 1552.0, 560.0), false, 2.0, false, shown
	)
	for key: StringName in unit:
		var want: Rect2 = Rect2(
			Vector2(30.0, 20.0) + unit[key].position * 2.0, unit[key].size * 2.0
		)
		assert_that(scaled[key]).override_failure_message(str(key)).is_equal(want)


## Every combination, every screen, mirrored and not.
func test_every_part_is_inside_the_safe_rect_48_dp_and_clear_of_the_others() -> void:
	var checked: int = 0
	for screen: Dictionary in _screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		for shown: HudCorners.Shown in _combinations():
			for mirror: bool in [false, true]:
				var out: Dictionary[StringName, Rect2] = HudCorners.place(
					safe, screen["portrait"], dp, mirror, shown
				)
				var why: String = "%s, mirror %s, %s" % [screen["label"], mirror, _describe(shown)]
				_assert_parts(out, safe, dp, why)
				_assert_gaps(out, dp, why)
				checked += 1
	assert_int(checked).is_greater(2000)


func test_the_sizes_the_adr_names_hold_at_every_screen() -> void:
	for screen: Dictionary in _screens():
		var dp: float = screen["dp"]
		var shown: HudCorners.Shown = _shown(["bar", "ready", "strike", "aim"], 5)
		var out: Dictionary[StringName, Rect2] = HudCorners.place(
			screen["safe"], screen["portrait"], dp, false, shown
		)
		var why: String = str(screen["label"])
		var sizes: Dictionary[StringName, Vector2] = {
			HudCorners.BUILD: Vector2(64.0, 64.0),
			HudCorners.STRIKE: Vector2(72.0, 72.0),
			HudCorners.SCOPE: Vector2(56.0, 56.0),
			HudCorners.group_key(0): Vector2(56.0, 56.0),
			HudCorners.READY: Vector2(112.0, 48.0),
		}
		for key: StringName in sizes:
			var size: Vector2 = out[key].size / dp
			assert_float(size.x).override_failure_message("%s %s" % [why, key]).is_equal_approx(
				sizes[key].x, TOLERANCE
			)
			assert_float(size.y).override_failure_message("%s %s" % [why, key]).is_equal_approx(
				sizes[key].y, TOLERANCE
			)
		assert_float(out[HudCorners.PILL].size.y / dp).is_equal_approx(48.0, TOLERANCE)
		assert_float(out[HudCorners.BAR].size.y / dp).is_equal_approx(64.0, TOLERANCE)
		assert_float(out[HudCorners.STRIKE_ROW].size.y / dp).is_equal_approx(64.0, TOLERANCE)


## ADR 0025 section 2: gaps of 8 dp (see the rig).
func _assert_gaps(out: Dictionary[StringName, Rect2], dp: float, why: String) -> void:
	CornersRig.assert_gaps(self, out, dp, why)


static func _gap(a: Rect2, b: Rect2) -> float:
	return CornersRig.gap(a, b)


func _assert_parts(out: Dictionary[StringName, Rect2], safe: Rect2, dp: float, why: String) -> void:
	CornersRig.assert_parts(self, out, safe, dp, why)


## Every set of the optional parts: the bar (at its least and as wide as it can ask), the Ready chip
## and the strike button each way, with one of the unfolds and modes (or none) and one group count.
func _combinations() -> Array[HudCorners.Shown]:
	var out: Array[HudCorners.Shown] = []
	for bits: int in 8:
		for extra: String in EXTRAS:
			for groups: int in [1, 5]:
				for bar_width: float in [0.0, WIDE_BAR_DP]:
					if bar_width > 0.0 and not bits & 1:
						continue
					var names: Array[String] = []
					for index: int in 3:
						if bits & (1 << index):
							names.append(["bar", "ready", "strike"][index])
					if extra != "":
						names.append(extra)
					if extra == "aim" and not names.has("strike"):
						continue
					out.append(_shown(names, groups, bar_width))
	return out


func _describe(shown: HudCorners.Shown) -> String:
	var parts: Array[String] = []
	for property: String in ["bar", "ready", "strike", "aim", "map", "toast", "card", "drawer"]:
		if shown.get(property):
			parts.append(property)
	return "%s, %d groups, bar %s dp" % [parts, shown.groups, shown.bar_width]


func _screens() -> Array[Dictionary]:
	return CornersRig.screens()


func _shown(names: Array[String], groups: int = 1, bar_width: float = 0.0) -> HudCorners.Shown:
	return CornersRig.shown(names, groups, bar_width)


## `place` for a rect in dp (dp 1), unmirrored.
func _place(safe: Rect2, portrait: bool, shown: HudCorners.Shown) -> Dictionary[StringName, Rect2]:
	return HudCorners.place(safe, portrait, 1.0, false, shown)


## The most group buttons one column holds: the buttons that share the first one's x.
func _column(out: Dictionary[StringName, Rect2], count: int) -> int:
	var x: float = out[HudCorners.group_key(0)].position.x
	var per: int = 0
	for index: int in count:
		if is_equal_approx(out[HudCorners.group_key(index)].position.x, x):
			per += 1
	return per


func _assert_rect(actual: Rect2, expected: Rect2) -> void:
	assert_that(actual).override_failure_message("%s, expected %s" % [actual, expected]).is_equal(
		expected
	)


## The column starts under the pill sideways, and the toast, when it stands under the top line,
## starts right of the column: at every screen, a wide pill beside the open drawer, one to five
## group items.
func test_sideways_the_column_stands_under_the_pill_and_the_short_toast_clear_of_it() -> void:
	var checked: int = 0
	for screen: Dictionary in _screens():
		if screen["portrait"]:
			continue
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		for groups: int in [1, 3, 5]:
			var shown: HudCorners.Shown = _shown(["toast", "drawer"], groups)
			shown.pill_width = 320.0
			var out: Dictionary[StringName, Rect2] = HudCorners.place(safe, false, dp, false, shown)
			var why: String = "%s, %d groups" % [screen["label"], groups]
			var first: Rect2 = out[HudCorners.group_key(0)]
			(
				assert_float(first.position.y - safe.position.y)
				. override_failure_message(why)
				. is_greater_equal(48.0 * dp + 8.0 * dp - TOLERANCE)
			)
			for index: int in groups:
				var rect: Rect2 = out[HudCorners.group_key(index)]
				var toast: Rect2 = out[HudCorners.TOAST]
				assert_bool(rect.intersects(toast)).override_failure_message(why).is_false()
				(
					assert_bool(rect.intersects(out[HudCorners.PILL]))
					. override_failure_message(why)
					. is_false()
				)
			checked += 1
	assert_int(checked).is_greater(10)
