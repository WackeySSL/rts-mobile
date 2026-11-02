extends RefCounted
## Device profiles for the dp tests (plan Phase 1, "Test profiles"). Not a test suite. Each
## stretch scale is what the engine computes at that window size: min(width / 1280, height / 720)
## in a landscape window and min(width / 720, height / 1280) in a portrait one, because the
## UiOrientation autoload turns the base size with the window (ADR 0015 section 2).
## A test sets the override first (see `UiScale.set_override`), then the window to `window_size`,
## and clears both in `after_test`.
## android_6in: a 6-inch phone, 420 dpi. web_phone and web_phone_small: phone browsers with
## 914x355 and 800x304 CSS px viewports. web_tablet: a 4:3 tablet. desktop: the base size.
## `all()` is landscape only. `portrait()` holds the portrait twins (ADR 0015 section 6), which a
## suite joins in its own row; `by_name` finds both and `notch_design()`'s too.
## `notch_design()` is the 6-inch phone with the insets of Michael's HUD design (ADR 0025 section
## 2, plan HUD v2): landscape 59 dp at the sides and 21 at the bottom, portrait 59 at the top and 34
## at the bottom. It is a profile of its own, so the suites that walk `all()` are unchanged.


## Fresh metrics for every profile: profile name -> UiMetrics.
static func all() -> Dictionary[StringName, UiMetrics]:
	return {
		&"android_6in": UiMetrics.create("Android", 420, 1.0, 1.5, Vector2i(2400, 1080), Rect2i()),
		&"web_phone":
		UiMetrics.create("Web", 252, 2.625, 932.0 / 720.0, Vector2i(2400, 932), Rect2i()),
		&"web_phone_small":
		UiMetrics.create("Web", 288, 3.0, 912.0 / 720.0, Vector2i(2400, 912), Rect2i()),
		&"web_tablet": UiMetrics.create("Web", 192, 2.0, 1.6, Vector2i(2048, 1536), Rect2i()),
		&"desktop": UiMetrics.create("Linux", 96, 1.0, 1.0, Vector2i(1280, 720), Rect2i()),
	}


## Fresh metrics for the portrait profiles. The first three are the transposes of their landscape
## twins and give the same dp(48); web_phone_portrait is a phone browser held upright (360x700 CSS
## px at 3.0: 1080x2100, stretch 1.5, dp(48) 96 base px).
static func portrait() -> Dictionary[StringName, UiMetrics]:
	return {
		&"android_6in_portrait":
		UiMetrics.create("Android", 420, 1.0, 1.5, Vector2i(1080, 2400), Rect2i()),
		&"web_tablet_portrait":
		UiMetrics.create("Web", 192, 2.0, 1.6, Vector2i(1536, 2048), Rect2i()),
		&"desktop_portrait": UiMetrics.create("Linux", 96, 1.0, 1.0, Vector2i(720, 1280), Rect2i()),
		&"web_phone_portrait":
		UiMetrics.create("Web", 288, 3.0, 1.5, Vector2i(1080, 2100), Rect2i()),
	}


## The 6-inch phone, both ways, with the design's insets (dp turned to window px).
static func notch_design() -> Dictionary[StringName, UiMetrics]:
	var land: UiMetrics = all()[&"android_6in"]
	var upright: UiMetrics = portrait()[&"android_6in_portrait"]
	var px: float = UiScale.window_px_per_dp(land)
	var side: int = roundi(59.0 * px)
	var land_safe: Rect2i = Rect2i(
		side, 0, land.window_size.x - 2 * side, land.window_size.y - roundi(21.0 * px)
	)
	var top: int = roundi(59.0 * px)
	var port_safe: Rect2i = Rect2i(
		0, top, upright.window_size.x, upright.window_size.y - top - roundi(34.0 * px)
	)
	return {
		&"notch_design": with_safe_area(land, land_safe),
		&"notch_design_portrait": with_safe_area(upright, port_safe),
	}


static func by_name(profile_name: StringName) -> UiMetrics:
	var landscape: Dictionary[StringName, UiMetrics] = all()
	if landscape.has(profile_name):
		return landscape[profile_name]
	var upright: Dictionary[StringName, UiMetrics] = portrait()
	return upright[profile_name] if upright.has(profile_name) else notch_design()[profile_name]


## A copy of `m` with another safe area (window px).
static func with_safe_area(m: UiMetrics, safe_area: Rect2i) -> UiMetrics:
	return UiMetrics.create(
		m.os_name, m.dpi, m.screen_scale, m.stretch_scale, m.window_size, safe_area
	)
