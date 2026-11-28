class_name RankInsignia
extends Control
## The commander's rank insignia (ADR 0052 section 3, P664): one stacked chevron for each rank held,
## the highest at the top, in the theme's money amber. Drawn, no picture; the rank is set by the
## owner and the stripes are at least one and at most `max_rank`.

const SIZE_DP: Vector2 = Vector2(40.0, 40.0)
const STRIPE_DP: float = 3.0

var rank: int = 1:
	set(value):
		rank = value
		queue_redraw()
var max_rank: int = 7:
	set(value):
		max_rank = maxi(value, 1)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = UiScale.dp_vec(SIZE_DP.x, SIZE_DP.y)


func _draw() -> void:
	if not has_theme_color(&"money", &"HudTokens"):
		return
	var tone: Color = get_theme_color(&"money", &"HudTokens")
	var count: int = clampi(rank, 1, max_rank)
	var step: float = size.y / float(maxi(count + 1, 4))
	var base: float = (size.y + step * float(count)) * 0.5  ## The stack is centred in the square.
	for index: int in range(count):
		var top: float = base - step * float(index + 1)
		var points: PackedVector2Array = [
			Vector2(0.0, top + step * 0.7),
			Vector2(size.x * 0.5, top),
			Vector2(size.x, top + step * 0.7)
		]
		draw_polyline(points, tone, UiScale.dp(STRIPE_DP))
