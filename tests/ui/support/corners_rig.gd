extends RefCounted
## What the `HudCorners` suites share (plan P119, P120g): the screens (the six sizes and every
## profile, with a cutout and the design's insets), `Shown`, and the checks every layout must pass:
## each rect inside the safe rect and at least 48 dp, no two overlapping, 8 dp between all parts.
## Not a suite.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MARGIN_DP: float = 12.0  ## SafeAreaMargin's gap on every side.
const CUTOUT_PX: int = 100
const TOLERANCE: float = 0.01


## ADR 0025 section 2: gaps of 8 dp. Every two parts that show are at least 8 dp apart on one axis.
## One exemption: the economy card, which is an overlay (it hangs under the pill over the toast, the
## groups, the command bar and the scope's foot). The strike aim's check mark and X against the
## group column are no exemption.
static func assert_gaps(
	t: GdUnitTestSuite, out: Dictionary[StringName, Rect2], dp: float, why: String
) -> void:
	var keys: Array = out.keys()
	for first: int in keys.size():
		for second: int in range(first + 1, keys.size()):
			var a: StringName = keys[first]
			var b: StringName = keys[second]
			if nested(a, b) or a == HudCorners.CARD or b == HudCorners.CARD:
				continue
			var apart: float = gap(out[a], out[b]) / dp
			var pair: String = "%s: %s and %s are %s dp apart" % [why, a, b, apart]
			t.assert_float(apart).override_failure_message(pair).is_greater_equal(8.0 - TOLERANCE)


## The distance between two rects along the axis that separates them (negative while they overlap).
static func gap(a: Rect2, b: Rect2) -> float:
	var across: float = maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var down: float = maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	return maxf(across, down)


static func assert_parts(
	t: GdUnitTestSuite, out: Dictionary[StringName, Rect2], safe: Rect2, dp: float, why: String
) -> void:
	var keys: Array = out.keys()
	var least: float = 48.0 * dp - TOLERANCE
	for key: StringName in keys:
		var rect: Rect2 = out[key]
		var at: String = "%s: %s %s, safe %s" % [why, key, rect, safe]
		t.assert_bool(safe.grow(TOLERANCE).encloses(rect)).override_failure_message(at).is_true()
		t.assert_float(rect.size.x).override_failure_message(at).is_greater_equal(least)
		t.assert_float(rect.size.y).override_failure_message(at).is_greater_equal(least)
	for first: int in keys.size():
		for second: int in range(first + 1, keys.size()):
			var a: StringName = keys[first]
			var b: StringName = keys[second]
			if nested(a, b) or overlay(a, b):
				continue
			var pair: String = "%s: %s %s and %s %s" % [why, a, out[a], b, out[b]]
			var shrunk: Rect2 = out[a].grow(-TOLERANCE)  # Touching edges are no overlap.
			t.assert_bool(shrunk.intersects(out[b])).override_failure_message(pair).is_false()


## The map's parts are inside the map; the pill's card is the overlay of the toast, the groups and
## the command bar.
static func nested(a: StringName, b: StringName) -> bool:
	var map: Array[StringName] = [HudCorners.MAP, HudCorners.MAP_HEAD, HudCorners.MAP_BOX]
	return map.has(a) and map.has(b)


static func overlay(a: StringName, b: StringName) -> bool:
	return (a == HudCorners.CARD and under_card(b)) or (b == HudCorners.CARD and under_card(a))


## What the card may cover.
static func under_card(key: StringName) -> bool:
	return key == HudCorners.TOAST or key == HudCorners.BAR or str(key).begins_with("group_")


## The six sizes (the engine's own metrics: a dp is a window px) and every profile of both
## orientations, each with a cutout, and the design's insets: {label, safe, dp, portrait}.
static func screens() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	for size: Vector2i in ScreenSizes.ALL:
		var turned: Vector2 = Vector2(base.y, base.x) if UiScale.is_portrait_size(size) else base
		var stretch: float = minf(size.x / turned.x, size.y / turned.y)
		var m: UiMetrics = UiMetrics.create("Linux", 96, 1.0, stretch, size, Rect2i())
		out.append(screen("size %s" % size, m))
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		out.append(screen(str(profile_name), m))
		var w: int = m.window_size.x
		var h: int = m.window_size.y
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, w, h - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, w - CUTOUT_PX, h)
		out.append(screen("%s with a cutout" % profile_name, UiProfiles.with_safe_area(m, cut)))
	return out


static func screen(label: String, metrics: UiMetrics) -> Dictionary:
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
static func shown(
	names: Array[String], groups: int = 1, bar_width: float = 0.0
) -> HudCorners.Shown:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	for part: String in names:
		shown.set(part, true)
	shown.groups = groups
	shown.bar_width = bar_width
	return shown
