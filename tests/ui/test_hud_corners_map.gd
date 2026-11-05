extends GdUnitTestSuite
## P122: the pinned full map beside the strike aim's row starts at the larger of the pill's end and
## the group column's end. It narrowed from the pill only: on the 800 x 304 dp screen with the
## command bar (and, until P124, the Dev-over-Surrender stack, which made the column one button per
## column), it overlapped the last group button. The column holds at most four items ("All army",
## `SelectionModel.GROUP_COUNT` = 3 groups; "+" shows only while one is free). The map keeps 8 dp
## from every one at every landscape profile (also with a cutout), for a narrow and a wide pill.
## P124 removed the stack; the case stays as the guard of the column against the map.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const CUTOUT_PX: int = 100
const TOLERANCE: float = 0.01


func after_test() -> void:
	UiScale.clear_override()


func test_the_pinned_map_with_the_aim_keeps_clear_of_the_group_column_too() -> void:
	var checked: int = 0
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.notch_design())
	for profile_name: StringName in profiles:
		var metrics: UiMetrics = profiles[profile_name]
		if UiScale.is_portrait_size(metrics.window_size):
			continue
		var cut: Rect2i = Rect2i(
			CUTOUT_PX, 0, metrics.window_size.x - CUTOUT_PX, metrics.window_size.y
		)
		for screen: UiMetrics in [metrics, UiProfiles.with_safe_area(metrics, cut)]:
			UiScale.set_override(screen)
			var dp: float = UiScale.base_px_per_dp()
			var full: Rect2 = Rect2(
				Vector2.ZERO, Vector2(screen.window_size) / screen.stretch_scale
			)
			var safe: Rect2 = SafeAreaMargin.rect_inside(full, 12.0)
			for groups: int in [1, 3, SelectionModel.GROUP_COUNT + 1]:
				for pill: float in [0.0, 320.0]:
					var label: String = "%s, %s" % [profile_name, screen.safe_area]
					checked += _check(safe, dp, groups, pill, label)
	assert_int(checked).is_greater(30)


func _check(safe: Rect2, dp: float, groups: int, pill: float, label: String) -> int:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.bar = true
	shown.strike = true
	shown.aim = true
	shown.map = true
	shown.groups = groups
	shown.pill_width = pill
	var out: Dictionary[StringName, Rect2] = HudCorners.place(safe, false, dp, false, shown)
	var map: Rect2 = out[HudCorners.MAP]
	for index: int in groups:
		var group: Rect2 = out[HudCorners.group_key(index)]
		var across: float = maxf(group.position.x - map.end.x, map.position.x - group.end.x)
		var down: float = maxf(group.position.y - map.end.y, map.position.y - group.end.y)
		var why: String = (
			"%s, %d groups, pill %s: group_%d %s, map %s" % [label, groups, pill, index, group, map]
		)
		assert_float(maxf(across, down) / dp).override_failure_message(why).is_greater_equal(
			8.0 - TOLERANCE
		)
	return 1


## Upright the aim's row stands below the map and the column leaves BUILD its width: the map keeps
## clear of the group column at the portrait sizes too.
func test_upright_the_pinned_map_keeps_clear_of_the_group_column() -> void:
	for size: Vector2i in ScreenSizes.PORTRAIT:
		var turned: Vector2 = Vector2(720.0, 1280.0)
		var metrics: UiMetrics = UiMetrics.create(
			"Linux", 96, 1.0, minf(size.x / turned.x, size.y / turned.y), size, Rect2i()
		)
		UiScale.set_override(metrics)
		var dp: float = UiScale.base_px_per_dp()
		var safe: Rect2 = SafeAreaMargin.rect_inside(Rect2(Vector2.ZERO, turned), 12.0)
		var shown: HudCorners.Shown = HudCorners.Shown.new()
		shown.bar = true
		shown.strike = true
		shown.aim = true
		shown.map = true
		shown.groups = SelectionModel.GROUP_COUNT + 1
		var out: Dictionary[StringName, Rect2] = HudCorners.place(safe, true, dp, false, shown)
		for index: int in shown.groups:
			if not out.has(HudCorners.group_key(index)):
				continue  # The rest scroll during the aim.
			var group: Rect2 = out[HudCorners.group_key(index)]
			(
				assert_bool(out[HudCorners.MAP].intersects(group))
				. override_failure_message("%s: group_%d" % [size, index])
				. is_false()
			)


## On a very short screen the group column wraps into several columns and ends right of the pill:
## the pinned map beside the aim's row then starts a gap right of the column, not of the pill.
## (The `column_end` clause of `HudCorners._map`: no phone profile reaches it, since P124 took the
## Dev stack away, so the case is crafted: 700 x 240 dp of safe rect.)
func test_a_column_that_ends_right_of_the_pill_pushes_the_pinned_map_right() -> void:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.bar = true
	shown.strike = true
	shown.aim = true
	shown.map = true
	shown.groups = 4
	shown.pill_width = 200.0
	var out: Dictionary[StringName, Rect2] = HudCorners.place(
		Rect2(0.0, 0.0, 700.0, 240.0), false, 1.0, false, shown
	)
	var last: Rect2 = out[HudCorners.group_key(3)]
	assert_float(last.end.x).is_greater(out[HudCorners.PILL].end.x + 8.0)  # Right of the pill.
	var map: Rect2 = out[HudCorners.MAP]
	assert_float(map.position.x - last.end.x).is_greater_equal(8.0 - TOLERANCE)
	assert_bool(map.intersects(out[HudCorners.STRIKE_ROW])).is_false()
