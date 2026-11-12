class_name SweepMark
extends RefCounted
## The satellite mark and the pause mark of the sweep (ADR 0036 section 11, plan P235), drawn from
## primitives so the badge and the owner's strike button share one look and need no art file: a
## square body turned 45 degrees, a panel each side and a dish arc on top. The pause mark is two
## bars; paused is never shown by colour alone (the badge also dims). Pure drawing: the caller
## gives the canvas item, the rect and the colour (a HudTokens colour).

const TOKENS: StringName = &"HudTokens"
const PANEL_SPAN: float = 0.34  ## A panel's share of the rect's side, each side of the body.
const BODY_SPAN: float = 0.22  ## The body's half-diagonal share of the side.
const DISH_POINTS: int = 12


## The satellite, centred in `rect`, with the colour `tint`.
static func satellite(canvas: CanvasItem, rect: Rect2, tint: Color) -> void:
	var side: float = minf(rect.size.x, rect.size.y)
	var middle: Vector2 = rect.get_center()
	var body: float = side * BODY_SPAN
	var panel: Vector2 = Vector2(side * PANEL_SPAN, side * 0.16)
	canvas.draw_set_transform(middle, -PI * 0.25)  # The whole craft stands at 45 degrees.
	canvas.draw_rect(Rect2(-Vector2.ONE * body * 0.5, Vector2.ONE * body), tint)
	for sign: float in [-1.0, 1.0]:
		var start: float = (body * 0.5 + side * 0.04) * sign
		var left: float = start if sign > 0.0 else start - panel.x
		canvas.draw_rect(Rect2(Vector2(left, -panel.y * 0.5), panel), tint)
	canvas.draw_arc(
		Vector2(0.0, -body * 0.5), side * 0.17, PI, TAU, DISH_POINTS, tint, maxf(side * 0.06, 1.0)
	)
	canvas.draw_set_transform(Vector2.ZERO, 0.0)


## The pause mark: two bars, centred in `rect`, `tint`, over a dark `plate` disc so it reads on
## any card.
static func pause(canvas: CanvasItem, rect: Rect2, tint: Color, plate: Color) -> void:
	var side: float = minf(rect.size.x, rect.size.y)
	var middle: Vector2 = rect.get_center()
	canvas.draw_circle(middle, side * 0.5, plate)
	var bar: Vector2 = Vector2(side * 0.14, side * 0.46)
	var gap: float = side * 0.1
	for sign: float in [-1.0, 1.0]:
		var x: float = middle.x + sign * (gap * 0.5 + bar.x * 0.5) - bar.x * 0.5
		canvas.draw_rect(Rect2(Vector2(x, middle.y - bar.y * 0.5), bar), tint)
