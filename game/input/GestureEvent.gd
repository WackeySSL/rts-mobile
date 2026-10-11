class_name GestureEvent
extends RefCounted
## One recognised gesture (ADR 0004 section 2). Positions and sizes are base px. A kind sets only
## the fields named for it. The others keep their defaults.

enum Kind { TAP, DOUBLE_TAP, LONG_PRESS, BOX_UPDATE, BOX_END, BOX_CANCEL, PAN, PINCH, CAMERA_END }

var kind: int = Kind.TAP
var position: Vector2 = Vector2.ZERO  ## TAP, DOUBLE_TAP, LONG_PRESS: the press point.
var rect: Rect2 = Rect2()  ## BOX_UPDATE, BOX_END: normalised.
var delta: Vector2 = Vector2.ZERO  ## PAN, PINCH: screen delta.
var centre: Vector2 = Vector2.ZERO  ## PINCH: centroid of the two fingers.
var scale: float = 1.0  ## PINCH: distance ratio since the previous PINCH.


func _init(p_kind: int = Kind.TAP) -> void:
	kind = p_kind
