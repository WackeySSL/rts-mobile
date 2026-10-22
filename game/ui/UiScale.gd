class_name UiScale
extends RefCounted
## dp (density-independent pixels) to base canvas px (ADR 0004 section 3). Every function returns
## base px, the unit of Control sizes and input positions under `canvas_items` stretch. Values
## change when the window resizes, so users recompute on the viewport's `size_changed`.
## The override is static state for tests only: a suite that sets one clears it in `after_test`.

const ANDROID_BASE_DPI: float = 160.0  ## Android: 1 dp is 1 px at 160 dpi.
const MIN_WINDOW_PX_PER_DP: float = 0.75
const MAX_WINDOW_PX_PER_DP: float = 4.0

static var _override: UiMetrics = null


## Window px per dp, clamped to [0.75, 4.0]. Android: `dpi / 160`. Everything else:
## `screen_scale`. A value that is not finite or not above 0 counts as 1.0.
static func window_px_per_dp(m: UiMetrics) -> float:
	var raw: float = float(m.dpi) / ANDROID_BASE_DPI if m.os_name == "Android" else m.screen_scale
	return clampf(_positive_or_one(raw), MIN_WINDOW_PX_PER_DP, MAX_WINDOW_PX_PER_DP)


## Window px per dp divided by the stretch scale (1.0 when that is not above 0).
static func base_px_per_dp_for(m: UiMetrics) -> float:
	return window_px_per_dp(m) / _positive_or_one(m.stretch_scale)


## The safe area in base px, clipped to the window. The visible rect when the platform reports
## none, or none inside the window. The fallback can be under 0.5 base px off the engine's
## `get_visible_rect()`, which rounds its width down.
static func safe_rect_base_for(m: UiMetrics) -> Rect2:
	var stretch: float = _positive_or_one(m.stretch_scale)
	var visible_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(m.window_size) / stretch)
	var safe: Rect2i = m.safe_area.intersection(Rect2i(Vector2i.ZERO, m.window_size))
	if not safe.has_area():
		return visible_rect
	return Rect2(Vector2(safe.position) / stretch, Vector2(safe.size) / stretch)


## The one place that tells the orientation of a window (ADR 0015 section 2): portrait is taller
## than wide. Any other window, a square one too, is landscape. No other code compares the sides.
static func is_portrait_size(size: Vector2i) -> bool:
	return size.y > size.x


## The base size the stretch uses for a window of `window_size`: `landscape_base` (the project's
## 1280x720) in a landscape window and its transpose in a portrait one, so the stretch is the same
## number for the same device in both orientations (ADR 0015 section 2).
static func base_size_for(window_size: Vector2i, landscape_base: Vector2i) -> Vector2i:
	if is_portrait_size(window_size):
		return Vector2i(landscape_base.y, landscape_base.x)
	return landscape_base


## The override when one is set, else what the engine reports now.
static func current() -> UiMetrics:
	return _override if _override != null else _engine_metrics()


static func base_px_per_dp() -> float:
	return base_px_per_dp_for(current())


static func dp(value: float) -> float:
	return value * base_px_per_dp()


static func dp_vec(x: float, y: float) -> Vector2:
	var factor: float = base_px_per_dp()
	return Vector2(x * factor, y * factor)


static func safe_rect_base() -> Rect2:
	return safe_rect_base_for(current())


## Tests only. Set it before resizing the window: nothing tells a `DpMinSize` already in the tree.
static func set_override(m: UiMetrics) -> void:
	_override = m


static func clear_override() -> void:
	_override = null


static func has_override() -> bool:
	return _override != null


## The platform reports the safe area in screen px, the metrics hold window px.
static func window_safe_area(screen_safe: Rect2i, window_position: Vector2i) -> Rect2i:
	return Rect2i(screen_safe.position - window_position, screen_safe.size)


static func _positive_or_one(value: float) -> float:
	return 1.0 if is_nan(value) or is_inf(value) or value <= 0.0 else value


static func _engine_metrics() -> UiMetrics:
	var window_size: Vector2i = Vector2i.ZERO
	var stretch: float = 1.0
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		window_size = tree.root.size
		stretch = tree.root.get_stretch_transform().get_scale().x
		safe_area = window_safe_area(safe_area, tree.root.position)
	return UiMetrics.create(
		OS.get_name(),
		DisplayServer.screen_get_dpi(),
		DisplayServer.screen_get_scale(),
		stretch,
		window_size,
		safe_area
	)
