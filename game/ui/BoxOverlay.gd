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
var painter: Callable = _paint  ## Paints one `Step` in a `Color`. Tests record the calls.
var anchor: Vector2 = Vector2.ZERO
var rect: Rect2 = Rect2()  ## Zero size while there is no box.
var _anchor_ms: int = -1  ## When the anchor appeared, or -1.
var _dp_px: float = 1.0  ## Base px per dp, read when the overlay opens.


## One shape of `_draw`: a `circle` (at `center`, of `radius`) or a `rect` (`area`), in the theme
## colour `item`. `width` is the stroke in base px, and -1.0 fills the shape.
class Step:
	var shape: StringName
	var item: StringName
	var width: float
	var center: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var area: Rect2 = Rect2()

	func _init(p_shape: StringName, p_item: StringName, p_width: float) -> void:
		shape = p_shape
		item = p_item
		width = p_width


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
## dark pass under a stroke) and `stroke`. Tests read them here, and read what `_draw` hands the
## `painter`: pixels cannot be read headless.
func draw_colors() -> Dictionary[StringName, Color]:
	var colors: Dictionary[StringName, Color] = {}
	for item: StringName in COLOR_ITEMS:
		colors[item] = get_theme_color(item, THEME_TYPE)
	return colors


## The shapes `_draw` paints now, in the order it paints them: the anchor's fill, dark pass and
## stroke, then the box's. `_draw` does nothing else, so tests read which colour each shape gets
## and how wide it is here, as pixels cannot be read headless.
func draw_plan() -> Array[Step]:
	var steps: Array[Step] = []
	var stroke: float = FeedbackStyle.STROKE_DP * _dp_px
	var edge: float = FeedbackStyle.OUTLINE_DP * _dp_px
	if _anchor_ms >= 0:
		var radius: float = anchor_radius()
		steps.append(_ring(&"fill", -1.0, radius))
		steps.append(_ring(&"outline", stroke + edge, radius))
		steps.append(_ring(&"stroke", stroke, radius))
	if rect.has_area():
		var line: Rect2 = rect.grow(-_dp_px)
		var box_stroke: float = BOX_DP * _dp_px
		steps.append(_box(&"fill", -1.0, rect))
		steps.append(_box(&"outline", box_stroke + edge, line))
		steps.append(_box(&"stroke", box_stroke, line))
	return steps


func _ring(item: StringName, width: float, radius: float) -> Step:
	var step: Step = Step.new(&"circle", item, width)
	step.center = anchor
	step.radius = radius
	return step


func _box(item: StringName, width: float, area: Rect2) -> Step:
	var step: Step = Step.new(&"rect", item, width)
	step.area = area
	return step


func _open() -> void:
	if not visible:
		_dp_px = UiScale.base_px_per_dp()
		visible = true


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var colors: Dictionary[StringName, Color] = draw_colors()
	for step: Step in draw_plan():
		painter.call(step, colors[step.item])


func _paint(step: Step, color: Color) -> void:
	var filled: bool = step.width < 0.0
	if step.shape == &"circle":
		draw_circle(step.center, step.radius, color, filled, step.width, not filled)
	else:
		draw_rect(step.area, color, filled, step.width, not filled)
