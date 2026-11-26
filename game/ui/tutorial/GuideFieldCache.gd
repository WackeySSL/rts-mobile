class_name GuideFieldCache
extends RefCounted
## `GuideDock.field_point` kept while its inputs hold (the dock's layout and the card's foot), so a
## frame that asks again allocates and scans nothing (ADR 0048 section 6, plan row P592).

var _point: Vector2 = Vector2.ZERO
var _foot: float = -2.0  ## The foot `_point` was made for; -2: stale.


## Call when the dock or the HUD rects were made again.
func stale() -> void:
	_foot = -2.0


func point(
	safe: Rect2, dock: Rect2, hud_rects: Dictionary[StringName, Rect2], foot: float
) -> Vector2:
	if foot != _foot:
		_foot = foot
		_point = GuideDock.field_point(safe, dock, hud_rects, foot)
	return _point
