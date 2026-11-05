extends GdUnitTestSuite
## `HudCorners.place` upright (plan P120g, Michael 2026-11-05): the HUD keeps its landscape corners.
## The group column hangs from a gap under the pill, BUILD stands in the safe rect's bottom right
## corner with or without the bar, the bar ends a gap short of BUILD, the Ready chip stands in the
## right column above the strike button (or BUILD), the toast and the full map clear the column, and
## the column stays above the open sheet where all its buttons fit. At every portrait screen of
## `CornersRig.screens()` (the three sizes of ScreenSizes.PORTRAIT and every portrait profile).

const CornersRig: GDScript = preload("res://tests/ui/support/corners_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TOLERANCE: float = 0.01
const WIDE_BAR_DP: float = 2000.0  ## A bar that asks for more than any screen has.


func after_test() -> void:
	UiScale.clear_override()


## The sheet leaves the group column above it where every button fits there (4 x 64 - 8 = 248 dp
## from 56 to 304 on 336 x 676 dp, a gap above the sheet's top at 338), else it hides: with 40
## buttons (more than the real 5 at most: All army, three groups and "+") nothing fits.
func test_the_sheet_leaves_the_group_column_above_it_where_all_the_buttons_fit() -> void:
	var shown: HudCorners.Shown = _shown(["drawer", "bar", "strike", "ready"], 4)
	var out: Dictionary[StringName, Rect2] = _place(Rect2(0.0, 0.0, 336.0, 676.0), shown)
	assert_array(out.keys()).contains_exactly_in_any_order(
		[
			HudCorners.DRAWER,
			HudCorners.SCOPE,
			HudCorners.PILL,
			HudCorners.group_key(0),
			HudCorners.group_key(1),
			HudCorners.group_key(2),
			HudCorners.group_key(3)
		]
	)
	assert_float(out[HudCorners.group_key(3)].end.y).is_less_equal(338.0 - 8.0)
	shown.groups = 40
	out = _place(Rect2(0.0, 0.0, 336.0, 676.0), shown)
	assert_bool(out.has(HudCorners.group_key(0))).is_false()


## Michael, 2026-11-05: upright the HUD keeps its landscape corners. The group column starts a gap
## under the pill's line, BUILD stands in the safe rect's bottom right corner with or without the
## bar, the bar ends a gap short of BUILD (the Ready chip stands in the right column, above the
## strike button or BUILD), the strike button is 8 dp above BUILD.
func test_upright_the_corners_are_the_landscape_corners_at_every_portrait_screen() -> void:
	var checked: int = 0
	for screen: Dictionary in CornersRig.screens():
		if not screen["portrait"]:
			continue
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		var why: String = str(screen["label"])
		var bare: Dictionary[StringName, Rect2] = HudCorners.place(
			safe, true, dp, false, _shown(["strike"], 5)
		)
		var first: Rect2 = bare[HudCorners.group_key(0)]
		(
			assert_float(first.position.x - safe.position.x)
			. override_failure_message(why)
			. is_equal_approx(0.0, TOLERANCE)
		)
		(
			assert_float(first.position.y - bare[HudCorners.PILL].end.y)
			. override_failure_message(why)
			. is_equal_approx(8.0 * dp, TOLERANCE)
		)
		for chip: bool in [false, true]:
			var names: Array[String] = ["bar", "strike"]
			if chip:
				names.append("ready")
			var with_bar: Dictionary[StringName, Rect2] = HudCorners.place(
				safe, true, dp, false, _shown(names, 5, WIDE_BAR_DP)
			)
			var build: Rect2 = with_bar[HudCorners.BUILD]
			var solo: Array[String] = []
			if chip:
				solo.append("ready")
			var alone: Dictionary[StringName, Rect2] = HudCorners.place(
				safe, true, dp, false, _shown(solo, 5)
			)
			assert_that(build).override_failure_message(why).is_equal(alone[HudCorners.BUILD])
			assert_that(build).override_failure_message(why).is_equal(bare[HudCorners.BUILD])
			assert_float(build.end.y).override_failure_message(why).is_equal_approx(
				safe.end.y, TOLERANCE
			)
			assert_float(build.end.x).override_failure_message(why).is_equal_approx(
				safe.end.x, TOLERANCE
			)
			var bar: Rect2 = with_bar[HudCorners.BAR]
			assert_float(bar.position.x).is_equal_approx(safe.position.x, TOLERANCE)
			# Upright the bar's room is BUILD's only: the Ready chip is in the right column.
			assert_float(bar.end.x).override_failure_message(why).is_equal_approx(
				build.position.x - 8.0 * dp, TOLERANCE
			)
			# The strike button a gap above BUILD, the row to its left at its height.
			var strike: Rect2 = with_bar[HudCorners.STRIKE]
			assert_float(build.position.y - strike.end.y).is_equal_approx(8.0 * dp, TOLERANCE)
			assert_that(strike).override_failure_message(why).is_equal(bare[HudCorners.STRIKE])
			if chip:  # A gap above the strike button, at the column's right edge; nothing moves.
				var ready: Rect2 = with_bar[HudCorners.READY]
				assert_float(ready.end.x).is_equal_approx(safe.end.x, TOLERANCE)
				assert_float(strike.position.y - ready.end.y).is_equal_approx(8.0 * dp, TOLERANCE)
				var lone: Dictionary[StringName, Rect2] = HudCorners.place(
					safe, true, dp, false, _shown(["ready"], 5)
				)
				assert_float(build.position.y - lone[HudCorners.READY].end.y).is_equal_approx(
					8.0 * dp, TOLERANCE
				)
			checked += 1
	assert_int(checked).is_greater_equal(ScreenSizes.PORTRAIT.size() * 2)


## Upright the toast stands right of the group column, the full map clears it, and neither meets
## the strike button or its row, at every portrait screen; the economy card may cover the column.
func test_upright_the_toast_and_the_full_map_clear_the_column_the_strike_button_and_its_row(
) -> void:
	var checked: int = 0
	for screen: Dictionary in CornersRig.screens():
		if not screen["portrait"]:
			continue
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		for groups: int in [1, 5, 8]:
			for extra: String in ["toast", "map"]:
				for aim: bool in [false, true]:
					var names: Array[String] = ["bar", "strike", "ready", extra]
					if aim:
						names.append("aim")
					var out: Dictionary[StringName, Rect2] = HudCorners.place(
						safe, true, dp, false, _shown(names, groups)
					)
					var why: String = (
						"%s, %d groups, %s, aim %s" % [screen["label"], groups, extra, aim]
					)
					CornersRig.assert_parts(self, out, safe, dp, why)
					CornersRig.assert_gaps(self, out, dp, why)
					var key: StringName = HudCorners.TOAST if extra == "toast" else HudCorners.MAP
					for index: int in groups:
						(
							assert_bool(out.has(HudCorners.group_key(index)))
							. override_failure_message(why)
							. is_true()
						)
						var gap: float = CornersRig.gap(out[HudCorners.group_key(index)], out[key])
						assert_float(gap / dp).override_failure_message(why).is_greater_equal(
							8.0 - TOLERANCE
						)
					checked += 1
	assert_int(checked).is_greater_equal(ScreenSizes.PORTRAIT.size() * 12)


## `place` upright for a rect in dp (dp 1), unmirrored.
func _place(safe: Rect2, shown: HudCorners.Shown) -> Dictionary[StringName, Rect2]:
	return HudCorners.place(safe, true, 1.0, false, shown)


## `Shown` with the named parts on (bar, ready, strike, aim, map, toast, card, drawer).
func _shown(names: Array[String], groups: int = 1, bar_width: float = 0.0) -> HudCorners.Shown:
	return CornersRig.shown(names, groups, bar_width)
