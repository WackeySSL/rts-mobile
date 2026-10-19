class_name BoxOverlay
extends Control
## The long-press anchor and the selection box, in screen space (STYLE.md "Feedback markers").
## PlayerController shows the anchor on LONG_PRESS and the rect on BOX_UPDATE, and hides both on
## BOX_END and BOX_CANCEL. The anchor ring shrinks from 48 to 32 dp as it appears, then stays.
## Its three colours are the theme's `BoxOverlay` type (`game/ui/theme.tres`), read when it draws.

const ANCHOR_DP: Vector2 = Vector2(48.0, 32.0)  ## Radius when it appears, and at rest.
const ANCHOR_MS: float = 150.0
const BOX_DP: float = 2.0  ## Stroke of the box. Its centre line is 1 dp inside the rect.
const THEME_TYPE: StringName = &"BoxOverlay"
const COLOR_ITEMS: Array[StringName] = [&"fill", &"outline", &"stroke"]

var clock: Callable = Time.get_ticks_msec  ## Returns ms. Tests replace it.
var anchor: Vector2 = Vector2.ZERO
var rect: Rect2 = Rect2()  ## Zero size while there is no box.
var _anchor_ms: int = -1  ## When the anchor appeared, or -1.
var _dp_px: float = 1.0  ## Base px per dp, read when the overlay opens.


func show_anchor(pos: Vector2) -> void:
	_open()
	anchor = pos
	_anchor_ms = clock.call()


func show_rect(box: Rect2) -> void:
	_open()
	rect = box


func hide_all() -> void:
	_anchor_ms = -1
	rect = Rect2()
	visible = false


func is_showing() -> bool:
	return visible


## The anchor ring's radius now, in base px.
func anchor_radius() -> float:
	var t: float = (clock.call() - _anchor_ms) / ANCHOR_MS
	return lerpf(ANCHOR_DP.x, ANCHOR_DP.y, FeedbackStyle.ease_out(t)) * _dp_px


## The colours `_draw` draws with, by theme item: `fill` (the anchor and the box), `outline` (the
## dark pass under a stroke) and `stroke`. Tests read them here: pixels cannot be read headless.
func draw_colors() -> Dictionary[StringName, Color]:
	var colors: Dictionary[StringName, Color] = {}
	for item: StringName in COLOR_ITEMS:
		colors[item] = get_theme_color(item, THEME_TYPE)
	return colors


func _open() -> void:
	if not visible:
		_dp_px = UiScale.base_px_per_dp()
		visible = true


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var stroke: float = FeedbackStyle.STROKE_DP * _dp_px
	var edge: float = FeedbackStyle.OUTLINE_DP * _dp_px
	var colors: Dictionary[StringName, Color] = draw_colors()
	if _anchor_ms >= 0:
		var radius: float = anchor_radius()
		draw_circle(anchor, radius, colors[&"fill"])
		draw_circle(anchor, radius, colors[&"outline"], false, stroke + edge, true)
		draw_circle(anchor, radius, colors[&"stroke"], false, stroke, true)
	if rect.has_area():
		var line: Rect2 = rect.grow(-_dp_px)
		draw_rect(rect, colors[&"fill"])
		draw_rect(line, colors[&"outline"], false, BOX_DP * _dp_px + edge, true)
		draw_rect(line, colors[&"stroke"], false, BOX_DP * _dp_px, true)
