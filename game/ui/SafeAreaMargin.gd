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
	var inset: Vector2i = inset_px(get_viewport().get_visible_rect(), margin_dp)
	add_theme_constant_override("margin_left", inset.x)
	add_theme_constant_override("margin_right", inset.x)
	add_theme_constant_override("margin_top", inset.y)
	add_theme_constant_override("margin_bottom", inset.y)
	return inset


## The margins for a screen of `full` base px under the metrics in force (x: left and right, y: top
## and bottom). Static so that a part placed by `HudCorners.place` finds the same rect.
static func inset_px(full: Rect2, margin_dp: float) -> Vector2i:
	var safe: Rect2 = UiScale.safe_rect_base()
	var gap: int = roundi(UiScale.dp(margin_dp))
	var x: int = maxi(_up(safe.position.x), _up(full.end.x - safe.end.x)) + gap
	var y: int = maxi(_up(safe.position.y), _up(full.end.y - safe.end.y)) + gap
	return Vector2i(x, y)


## The rect inside those margins: ADR 0025 section 2's safe rect.
static func rect_inside(full: Rect2, margin_dp: float) -> Rect2:
	var inset: Vector2 = Vector2(inset_px(full, margin_dp))
	return Rect2(full.position + inset, full.size - 2.0 * inset)


## Whole base px, rounded up so a control never touches the cutout. Float noise is ignored.
static func _up(inset: float) -> int:
	return ceili(snappedf(inset, 0.01))
