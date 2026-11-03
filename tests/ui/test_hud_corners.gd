extends GdUnitTestSuite
## `HudCorners.place` on crafted inputs (ADR 0025 sections 2 and 14, plan P119): ADR 0025 section
## 2's table of numbers row by row on the short screens, then every combination of what shows at
## the six sizes of ScreenSizes.ALL, at every profile of both orientations (also with a cutout and
## with the design's insets) and mirrored and not: every rect is inside the safe rect, no two
## overlap, every rect is at least 48 dp on each side, and the sizes the ADR names hold.

const CardHeights: GDScript = preload("res://tests/support/card_heights.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MARGIN_DP: float = 12.0  ## SafeAreaMargin's gap on every side.
const CUTOUT_PX: int = 100
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
	_assert_rect(lined[HudCorners.BAR], Rect2(0.0, 612.0, 336.0, 64.0))
	_assert_rect(lined[HudCorners.BUILD], Rect2(272.0, 540.0, 64.0, 64.0))  # 8 dp over the bar.
	_assert_rect(lined[HudCorners.STRIKE], Rect2(264.0, 460.0, 72.0, 72.0))
	_assert_rect(lined[HudCorners.MAP], Rect2(76.0, 64.0, 260.0, 178.0))
	assert_int(_column(lined, 5)).is_equal(3)  # 198 dp above the bar: three, then two.
	assert_float(lined[HudCorners.group_key(3)].position.x).is_equal(64.0)
	var top: float = 676.0
	for key: StringName in [HudCorners.BAR, HudCorners.group_key(0), HudCorners.group_key(3)]:
		top = minf(top, lined[key].position.y)
	assert_float(676.0 - top).is_less_equal(floorf(0.4 * 676.0))  # Within 270 dp.


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


func test_the_pill_starts_after_what_stands_at_the_top_left_and_stays_clear_of_the_scope() -> void:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.left_taken = 48.0
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)
	_assert_rect(out[HudCorners.PILL], Rect2(56.0, 0.0, 200.0, 48.0))  # A gap after the button.
	assert_float(out[HudCorners.PILL].end.x).is_less_equal(out[HudCorners.SCOPE].position.x - 8.0)
	shown.pill_width = 290.0  # A wider content takes what is left, no more than the scope allows.
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)
	assert_float(out[HudCorners.PILL].size.x).is_equal(216.0)
	out = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	assert_float(out[HudCorners.PILL].size.x).is_equal(290.0)
	shown.pill_width = 900.0
	out = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	assert_float(out[HudCorners.PILL].size.x).is_equal(HudCorners.PILL_MAX_DP)


func test_the_drawer_is_a_side_panel_of_40_percent_between_312_and_420_dp_or_a_half_sheet() -> void:
	var shown: HudCorners.Shown = _shown(["drawer", "bar", "strike", "ready"], 4)
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 776.0, 280.0), false, shown)
	_assert_rect(out[HudCorners.DRAWER], Rect2(464.0, 0.0, 312.0, 280.0))  # 40 % is 310: the least.
	out = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	_assert_rect(out[HudCorners.DRAWER], Rect2(534.0, 0.0, 356.0, 387.0))
	out = _place(Rect2(0.0, 0.0, 1400.0, 700.0), false, shown)
	assert_float(out[HudCorners.DRAWER].size.x).is_equal(420.0)
	# Beside the panel: the bar and the groups; under it: the right column and the pill.
	assert_array(out.keys()).contains_exactly_in_any_order(
		[
			HudCorners.DRAWER,
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
	assert_array(out.keys()).contains_exactly_in_any_order([HudCorners.DRAWER, HudCorners.SCOPE])
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
	_assert_rect(upright[HudCorners.TOAST], Rect2(0.0, 64.0, 336.0, 48.0))  # Under the scope.
	upright = _place(Rect2(0.0, 0.0, 800.0, 900.0), true, _shown(["toast"]))
	assert_float(upright[HudCorners.TOAST].size.x).is_equal(360.0)
	var open: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, _shown(["toast", "map"])
	)
	assert_bool(open.has(HudCorners.TOAST)).is_false()  # Never beside the full map.
	var panel: Dictionary[StringName, Rect2] = _place(
		Rect2(0.0, 0.0, 890.0, 387.0), false, _shown(["toast", "drawer"])
	)  # No pill, no scope: from the safe edge to the panel.
	assert_float(panel[HudCorners.TOAST].end.x).is_less_equal(
		panel[HudCorners.DRAWER].position.x - 8.0
	)


func test_the_economy_card_hangs_under_the_pill_280_wide() -> void:
	var shown: HudCorners.Shown = _shown(["card"])
	shown.left_taken = 48.0
	shown.card_height = 150.0
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 890.0, 387.0), false, shown)
	_assert_rect(out[HudCorners.CARD], Rect2(56.0, 56.0, 280.0, 150.0))
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), true, shown)  # The safe width at most.
	_assert_rect(out[HudCorners.CARD], Rect2(56.0, 56.0, 280.0, 150.0))
	out = _place(Rect2(0.0, 0.0, 300.0, 676.0), true, shown)
	assert_float(out[HudCorners.CARD].end.x).is_less_equal(300.0)


## The economy card at its tallest (six kinds of consumer and the low-power line, `CardHeights`;
## test_economy_card.gd measures the real one against that number) under the pill after the Dev
## button, with every combination of the other parts, at every screen, mirrored and not: inside the
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
			shown.left_taken = 48.0  # The Dev button.
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
				_assert_gaps(out, dp, why, str(screen["label"]).begins_with("web_phone_portrait"))
				if screen["portrait"] and shown.bar:
					_assert_stack_within_40_percent(out, safe, dp, why, shown)
				checked += 1
	assert_int(checked).is_greater(2000)


## The top-left stack's height (Dev over Surrender, until P124) moves the upright toast under it:
## with the stack at 48, 104 and 160 dp, at every screen and set of parts, mirrored or not, every
## part is inside and clear of the others, and the toast is clear of the stack's rect.
func test_the_toast_stands_clear_of_a_top_left_stack_of_any_height() -> void:
	var checked: int = 0
	for screen: Dictionary in _screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		for shown: HudCorners.Shown in _combinations():
			if not shown.toast or shown.map:
				continue
			shown.left_taken = 77.0
			for height: float in [48.0, 104.0, 160.0]:
				shown.left_height = height
				for mirror: bool in [false, true]:
					var out: Dictionary[StringName, Rect2] = HudCorners.place(
						safe, screen["portrait"], dp, mirror, shown
					)
					var why: String = (
						"%s, stack %s dp, mirror %s, %s"
						% [screen["label"], height, mirror, _describe(shown)]
					)
					_assert_parts(out, safe, dp, why)
					_assert_gaps(
						out, dp, why, str(screen["label"]).begins_with("web_phone_portrait")
					)
					var stack: Rect2 = Rect2(Vector2.ZERO, Vector2(77.0, height) * dp)
					stack.position = safe.position
					if mirror:
						stack.position.x = safe.end.x - stack.size.x
					(
						assert_bool(out[HudCorners.TOAST].intersects(stack))
						. override_failure_message(why)
						. is_false()
					)
					checked += 1
	assert_int(checked).is_greater(200)


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
		# The portrait stack (the bar, BUILD lifted over it, the strike button) is 216 dp high.
		if screen["portrait"]:
			var rise: float = (out[HudCorners.BAR].end.y - out[HudCorners.STRIKE].position.y) / dp
			assert_float(rise).override_failure_message(why).is_equal_approx(216.0, TOLERANCE)


## ADR 0015 section 5: the bottom stack (the bar and the group column) is at most 40 % of the safe
## height, whole dp. With the Ready chip the column leaves BUILD's column and the chip their width,
## so it has as many columns as that leaves and as many to a column as those need: the real bound
## there is the taller of the 40 % line and that column (declared in the PR).
func _assert_stack_within_40_percent(
	out: Dictionary[StringName, Rect2], safe: Rect2, dp: float, why: String, shown: HudCorners.Shown
) -> void:
	var top: float = safe.end.y
	for key: StringName in out:
		if key == HudCorners.BAR or str(key).begins_with("group_"):
			top = minf(top, out[key].position.y)
	var stack: float = (safe.end.y - top) / dp
	var limit: float = floorf(HudLayout.STACK_SHARE * safe.size.y / dp)
	if shown.ready:
		var right: float = HudCorners.BUILD_DP + HudCorners.GAP_DP + HudCorners.READY_DP.x + 8.0
		var columns: int = maxi(floori((safe.size.x / dp - right) / 64.0), 1)
		var rows: int = ceili(float(shown.groups) / columns)
		limit = maxf(limit, HudCorners.BAR_DP.y + HudCorners.GAP_DP + rows * 64.0 - 8.0)
	var message: String = "%s: stack %s dp of at most %s" % [why, stack, limit]
	assert_float(stack).override_failure_message(message).is_less_equal(limit + TOLERANCE)


## ADR 0025 section 2: gaps of 8 dp. Every two parts that show are at least 8 dp apart on one axis.
## Two exemptions, each for a reason: the economy card, which is an overlay (it hangs under the pill
## over the toast, the groups, the command bar and the scope's foot); and the strike button's check
## mark and X against the group column at 360 x 700 dp with five group items, where the ADR's own
## numbers (a 120 dp column, the 136 dp row, 8 dp, the 72 dp button: 336 dp) leave no gap, which
## the lead takes to the architect before P120c and P122b.
func _assert_gaps(out: Dictionary[StringName, Rect2], dp: float, why: String, narrow: bool) -> void:
	var keys: Array = out.keys()
	for first: int in keys.size():
		for second: int in range(first + 1, keys.size()):
			var a: StringName = keys[first]
			var b: StringName = keys[second]
			if _nested(a, b) or a == HudCorners.CARD or b == HudCorners.CARD:
				continue
			var row_and_column: bool = (
				narrow
				and (
					(a == HudCorners.STRIKE_ROW and str(b).begins_with("group_"))
					or (b == HudCorners.STRIKE_ROW and str(a).begins_with("group_"))
				)
			)
			if row_and_column:
				continue
			var gap: float = _gap(out[a], out[b]) / dp
			var pair: String = "%s: %s and %s are %s dp apart" % [why, a, b, gap]
			assert_float(gap).override_failure_message(pair).is_greater_equal(8.0 - TOLERANCE)


## The distance between two rects along the axis that separates them (negative while they overlap).
static func _gap(a: Rect2, b: Rect2) -> float:
	var across: float = maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var down: float = maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	return maxf(across, down)


func _assert_parts(out: Dictionary[StringName, Rect2], safe: Rect2, dp: float, why: String) -> void:
	var keys: Array = out.keys()
	var least: float = 48.0 * dp - TOLERANCE
	for key: StringName in keys:
		var rect: Rect2 = out[key]
		var at: String = "%s: %s %s, safe %s" % [why, key, rect, safe]
		assert_bool(safe.grow(TOLERANCE).encloses(rect)).override_failure_message(at).is_true()
		assert_float(rect.size.x).override_failure_message(at).is_greater_equal(least)
		assert_float(rect.size.y).override_failure_message(at).is_greater_equal(least)
	for first: int in keys.size():
		for second: int in range(first + 1, keys.size()):
			var a: StringName = keys[first]
			var b: StringName = keys[second]
			if _nested(a, b) or _overlay(a, b):
				continue
			var pair: String = "%s: %s %s and %s %s" % [why, a, out[a], b, out[b]]
			var shrunk: Rect2 = out[a].grow(-TOLERANCE)  # Touching edges are no overlap.
			assert_bool(shrunk.intersects(out[b])).override_failure_message(pair).is_false()


## The map's parts are inside the map; the pill's card is the overlay of the toast, the groups and
## the command bar.
static func _nested(a: StringName, b: StringName) -> bool:
	var map: Array[StringName] = [HudCorners.MAP, HudCorners.MAP_HEAD, HudCorners.MAP_BOX]
	return map.has(a) and map.has(b)


static func _overlay(a: StringName, b: StringName) -> bool:
	return (a == HudCorners.CARD and _under_card(b)) or (b == HudCorners.CARD and _under_card(a))


## What the card may cover.
static func _under_card(key: StringName) -> bool:
	return key == HudCorners.TOAST or key == HudCorners.BAR or str(key).begins_with("group_")


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


## The six sizes (the engine's own metrics: a dp is a window px) and every profile of both
## orientations, each with a cutout, and the design's insets: {label, safe, dp, portrait}.
func _screens() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	for size: Vector2i in ScreenSizes.ALL:
		var turned: Vector2 = Vector2(base.y, base.x) if UiScale.is_portrait_size(size) else base
		var stretch: float = minf(size.x / turned.x, size.y / turned.y)
		var m: UiMetrics = UiMetrics.create("Linux", 96, 1.0, stretch, size, Rect2i())
		out.append(_screen("size %s" % size, m))
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		out.append(_screen(str(profile_name), m))
		var w: int = m.window_size.x
		var h: int = m.window_size.y
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, w, h - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, w - CUTOUT_PX, h)
		out.append(_screen("%s with a cutout" % profile_name, UiProfiles.with_safe_area(m, cut)))
	return out


func _screen(label: String, metrics: UiMetrics) -> Dictionary:
	UiScale.set_override(metrics)
	var stretch: float = metrics.stretch_scale
	var full: Rect2 = Rect2(Vector2.ZERO, Vector2(metrics.window_size) / stretch)
	return {
		"label": label,
		"safe": SafeAreaMargin.rect_inside(full, MARGIN_DP),
		"dp": UiScale.base_px_per_dp(),
		"portrait": UiScale.is_portrait_size(metrics.window_size),
	}


## `Shown` with the named parts on (bar, ready, strike, aim, map, toast, card, drawer).
func _shown(names: Array[String], groups: int = 1, bar_width: float = 0.0) -> HudCorners.Shown:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	for part: String in names:
		shown.set(part, true)
	shown.groups = groups
	shown.bar_width = bar_width
	return shown


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
