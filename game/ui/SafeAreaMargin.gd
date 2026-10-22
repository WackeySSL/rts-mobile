class_name SafeAreaMargin
extends MarginContainer
## A MarginContainer whose margins are the platform safe-area inset (camera cutout, rounded
## corners) plus `margin_dp`, so what sits inside stays clear of both. Everything is in base px
## (ADR 0004 section 3) and is recomputed when the viewport changes size. Both sides of an axis get
## the larger inset: turning the phone 180 degrees moves the cutout to the other side without a
## resize. In portrait the cutout is at the top and the gesture bar at the bottom, so top and
## bottom get the larger of the two (ADR 0015 section 3). Make it a full-rect child of a
## CanvasLayer.

@export var margin_dp: float = 12


func _ready() -> void:
	get_viewport().size_changed.connect(apply)
	apply()


## Sets the margins from the current screen and returns them (x: left and right, y: top and
## bottom). A child that needs the room inside calls this: on a resize it runs before our handler.
func apply() -> Vector2i:
	var full: Rect2 = get_viewport().get_visible_rect()
	var safe: Rect2 = UiScale.safe_rect_base()
	var gap: int = roundi(UiScale.dp(margin_dp))
	var x: int = maxi(_up(safe.position.x), _up(full.end.x - safe.end.x)) + gap
	var y: int = maxi(_up(safe.position.y), _up(full.end.y - safe.end.y)) + gap
	add_theme_constant_override("margin_left", x)
	add_theme_constant_override("margin_right", x)
	add_theme_constant_override("margin_top", y)
	add_theme_constant_override("margin_bottom", y)
	return Vector2i(x, y)


## Whole base px, rounded up so a control never touches the cutout. Float noise is ignored.
func _up(inset: float) -> int:
	return ceili(snappedf(inset, 0.01))
