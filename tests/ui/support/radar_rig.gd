extends RefCounted
## Fixtures of the radar suites (plan P121, ADR 0025 sections 2 and 7). Not a test suite. A suite
## that builds the main scene calls `MenuRig.begin()` and `MenuRig.end()` itself
## (tests/project/test_menu_rig_scan.gd).

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const CUTOUT_PX: int = 100


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}: the
## six sizes of ScreenSizes.ALL, then every profile of both orientations (the design's insets,
## `notch_design`, among them) twice, the second time with a cutout of 100 px on the side where a
## phone has its camera (the left in landscape, the top in portrait). `portrait`: only that
## orientation (true or false), or both (null).
static func screens(portrait: Variant = null) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())  # The design's insets, both ways.
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, m.window_size.x - CUTOUT_PX, m.window_size.y)
		all.append({"label": str(profile_name), "size": m.window_size, "metrics": m})
		var with_cutout: UiMetrics = UiProfiles.with_safe_area(m, cut)
		all.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": with_cutout
			}
		)
	var out: Array[Dictionary] = []
	for screen: Dictionary in all:
		if portrait == null or UiScale.is_portrait_size(screen["size"]) == portrait:
			out.append(screen)
	return out


## A phone browser held sideways with a screen shorter than web_phone_small's 304 dp (269 dp safe
## height): there the full map no longer holds the head and a 96 dp box under the scope.
static func short_landscape() -> UiMetrics:
	return UiMetrics.create("Web", 288, 3.0, 880.0 / 720.0, Vector2i(2400, 880), Rect2i())


## A narrower short landscape screen than `short_landscape` (the plan's second case): 720 dp by
## 293, 696 dp of safe width (728 and 704 before P124 put the pill in the corner).
## There the pinned map, the aim's row and the pill fit side by side only because the map narrows
## (`HudCorners._map`: about 234 dp instead of 240, and 192 dp when low power widens the pill).
static func narrow_short_landscape() -> UiMetrics:
	return UiMetrics.create("Web", 288, 3.0, 880.0 / 720.0, Vector2i(2160, 880), Rect2i())


## Narrower still: 660 dp by 293, 636 dp of safe width (P124 put the pill in the corner, so the
## fold is at about 654 dp of safe width now), where the pinned map cannot fit beside the
## pill and the aim's row even at its least width, so it folds when the aim begins.
static func tiny_short_landscape() -> UiMetrics:
	return UiMetrics.create("Web", 288, 3.0, 880.0 / 720.0, Vector2i(1980, 880), Rect2i())


## The rects `HudCorners.place` gives for the screen in force (the safe rect of the viewport, the
## engine's orientation and dp), with the full map shown or not and nothing else.
static func rects(viewport: Viewport, map: bool) -> Dictionary[StringName, Rect2]:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.map = map
	var safe: Rect2 = SafeAreaMargin.rect_inside(
		viewport.get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	return HudCorners.place(safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown)
