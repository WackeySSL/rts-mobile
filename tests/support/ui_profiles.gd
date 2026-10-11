extends RefCounted
## Device profiles for the dp tests (plan Phase 1, "Test profiles"). Not a test suite. Each
## stretch scale is min(width / 1280, height / 720), what the engine computes at that window size.
## A test sets the override first (see `UiScale.set_override`), then the window to `window_size`,
## and clears both in `after_test`.
## android_6in: a 6-inch phone, 420 dpi. web_phone and web_phone_small: phone browsers with
## 914x355 and 800x304 CSS px viewports. web_tablet: a 4:3 tablet. desktop: the base size.


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


static func by_name(profile_name: StringName) -> UiMetrics:
	return all()[profile_name]


## A copy of `m` with another safe area (window px).
static func with_safe_area(m: UiMetrics, safe_area: Rect2i) -> UiMetrics:
	return UiMetrics.create(
		m.os_name, m.dpi, m.screen_scale, m.stretch_scale, m.window_size, safe_area
	)
