extends GdUnitTestSuite
## The enemy sweep's badge and its warning line in `HudCorners.place` (plan P235, ADR 0025
## section 10, ADR 0036 section 12), at every screen of `CornersRig.screens()` (the six sizes of
## ScreenSizes and every profile, both orientations): the badge is 48 dp, right-aligned in the right
## column a gap above its topmost part (the Ready chip upright, else the strike button, else BUILD),
## the line stands left of it on the same line, right of the group column, and neither shows with
## the drawer or the full map open. With them on, every rect is inside the safe rect, at least
## 48 dp and 8 dp from every other part.

const CornersRig: GDScript = preload("res://tests/ui/support/corners_rig.gd")
const TOLERANCE: float = 0.01
## The combinations of the other parts that stand by the badge.
const SETS: Array[Array] = [
	[],
	["strike"],
	["strike", "aim", "bar", "toast"],
	["ready", "strike", "bar"],
	["ready", "bar", "toast"],
]


func after_test() -> void:
	UiScale.clear_override()


func test_the_badge_and_its_line_keep_the_corners_at_every_screen() -> void:
	var checked: int = 0
	for screen: Dictionary in CornersRig.screens():
		var safe: Rect2 = screen["safe"]
		var dp: float = screen["dp"]
		var portrait: bool = screen["portrait"]
		for others: Array in SETS:
			var names: Array[String] = ["reveal", "reveal_line"]
			names.append_array(others)
			var why: String = "%s %s" % [screen["label"], names]
			var out: Dictionary[StringName, Rect2] = HudCorners.place(
				safe, portrait, dp, false, CornersRig.shown(names, 5, 160.0)
			)
			CornersRig.assert_parts(self, out, safe, dp, why)
			CornersRig.assert_gaps(self, out, dp, why)
			var badge: Rect2 = out[HudCorners.REVEAL]
			assert_float(badge.size.x / dp).override_failure_message(why).is_equal_approx(48.0, 0.1)
			assert_float(badge.end.x).override_failure_message(why).is_equal_approx(
				safe.end.x, TOLERANCE
			)
			assert_bool(out.has(HudCorners.REVEAL_LINE)).override_failure_message(why).is_true()
			var line: Rect2 = out[HudCorners.REVEAL_LINE]
			assert_float(line.position.y).override_failure_message(why).is_equal_approx(
				badge.position.y, TOLERANCE
			)
			assert_float(line.size.x / dp).override_failure_message(why).is_between(
				152.0 - TOLERANCE, 220.0 + TOLERANCE
			)
			# Above the topmost part of the right column.
			var column: Array[StringName] = [HudCorners.BUILD, HudCorners.STRIKE, HudCorners.READY]
			for key: StringName in column:
				if out.has(key) and not (landscape_chip(key, portrait)):
					assert_float(badge.end.y).override_failure_message(why).is_less_equal(
						out[key].position.y - 8.0 * dp + TOLERANCE
					)
			checked += 1
	assert_int(checked).is_greater_equal(5 * 6)


## Sideways the Ready chip stands left of BUILD, not in the right column.
func landscape_chip(key: StringName, portrait: bool) -> bool:
	return key == HudCorners.READY and not portrait


func test_nothing_shows_with_the_drawer_or_the_full_map_open_and_no_line_without_one() -> void:
	for screen: Dictionary in CornersRig.screens():
		var safe: Rect2 = screen["safe"]
		var why: String = str(screen["label"])
		for covering: String in ["drawer", "map"]:
			var covered: Dictionary[StringName, Rect2] = HudCorners.place(
				safe,
				screen["portrait"],
				screen["dp"],
				false,
				CornersRig.shown(_names(["reveal", "reveal_line", "strike", covering]), 3)
			)
			assert_bool(covered.has(HudCorners.REVEAL)).override_failure_message(why).is_false()
			(
				assert_bool(covered.has(HudCorners.REVEAL_LINE))
				. override_failure_message(why)
				. is_false()
			)
		var alone: Dictionary[StringName, Rect2] = HudCorners.place(
			safe, screen["portrait"], screen["dp"], false, CornersRig.shown(_names(["reveal"]), 1)
		)
		assert_bool(alone.has(HudCorners.REVEAL)).override_failure_message(why).is_true()
		assert_bool(alone.has(HudCorners.REVEAL_LINE)).override_failure_message(why).is_false()


func test_the_line_is_left_out_below_152_dp_and_kept_at_152() -> void:
	var shown: HudCorners.Shown = CornersRig.shown(_names(["reveal", "reveal_line", "strike"]), 1)
	# One group column (56 dp), the badge (48) and two gaps (16) leave `width - 120` for the line.
	for width: float in [271.0, 272.0, 500.0]:
		var out: Dictionary[StringName, Rect2] = HudCorners.place(
			Rect2(0.0, 0.0, width, 600.0), true, 1.0, false, shown
		)
		assert_bool(out.has(HudCorners.REVEAL)).is_true()
		var room: float = width - 120.0
		assert_bool(out.has(HudCorners.REVEAL_LINE)).override_failure_message(str(width)).is_equal(
			room >= 152.0
		)
		if room >= 152.0:
			assert_float(out[HudCorners.REVEAL_LINE].size.x).is_equal(minf(room, 220.0))


func _names(list: Array) -> Array[String]:
	var typed: Array[String] = []
	typed.assign(list)
	return typed
