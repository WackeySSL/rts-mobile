class_name UiMetrics
extends RefCounted
## What `UiScale` needs to know about the screen, as a plain value so the formulas can be tested
## with device profiles (ADR 0004 section 3). "window px" are real pixels; "base px" are canvas
## units under `canvas_items` stretch.

var os_name: String = ""  ## `OS.get_name()`.
var dpi: int = 0  ## `screen_get_dpi()`. Android reports its density bucket.
var screen_scale: float = 1.0  ## `screen_get_scale()`. Web: the device pixel ratio.
var stretch_scale: float = 1.0  ## Window px per base px (root `get_stretch_transform()`).
var window_size: Vector2i = Vector2i.ZERO  ## Window px.
var safe_area: Rect2i = Rect2i()  ## Window px. Without area means the platform reports none.


static func create(
	os_name: String,
	dpi: int,
	screen_scale: float,
	stretch_scale: float,
	window_size: Vector2i,
	safe_area: Rect2i
) -> UiMetrics:
	var metrics: UiMetrics = UiMetrics.new()
	metrics.os_name = os_name
	metrics.dpi = dpi
	metrics.screen_scale = screen_scale
	metrics.stretch_scale = stretch_scale
	metrics.window_size = window_size
	metrics.safe_area = safe_area
	return metrics
