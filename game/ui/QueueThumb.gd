class_name QueueThumb
extends HoldButton
## One slot of the queue row (`QueueRow`, plan P120b): a `HoldButton` over its picture, its dashed
## frame when empty and the head's progress bar. A finger that moves beyond `slop_dp` makes the
## touch no tap (`moved`). Colours and sizes are set by the row from the theme and the dp scale.

var slop_dp: float = 12.0
var moved: bool = false  ## The finger went beyond the slop since the press.
var offset: Vector2 = Vector2.ZERO
var picture: TextureRect = TextureRect.new()
var type_index: int = -1  ## -1: empty.
var share: float = 0.0  ## The head's progress, 0 to 1; 0 for any other slot.
var head: bool = false
var line: Color
var track: Color
var fill: Color
var dash: Vector2 = Vector2(6.0, 3.0)
var bar: float = 6.0
var line_inset: float = 1.5


func _init() -> void:
	super()
	focus_mode = Control.FOCUS_NONE
	flat = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(picture)


func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed:
		offset = Vector2.ZERO
		moved = false
	elif drag != null and not moved:
		offset += drag.relative
		moved = offset.length() > UiScale.dp(slop_dp)


func _draw() -> void:
	var frame: Rect2 = Rect2(Vector2.ZERO, size).grow(-line_inset)
	if type_index < 0:
		_dashed(frame)
		return
	draw_rect(frame, line, false, 1.0)
	if head:
		var back: Rect2 = Rect2(frame.position.x, frame.end.y - bar, frame.size.x, bar)
		draw_rect(back, track)
		draw_rect(Rect2(back.position, Vector2(back.size.x * share, bar)), fill)


func _dashed(frame: Rect2) -> void:
	var corners: PackedVector2Array = PackedVector2Array(
		[
			frame.position,
			Vector2(frame.end.x, frame.position.y),
			frame.end,
			Vector2(frame.position.x, frame.end.y)
		]
	)
	for side: int in 4:
		var from: Vector2 = corners[side]
		var to: Vector2 = corners[(side + 1) % 4]
		var length: float = from.distance_to(to)
		var step: Vector2 = (to - from) / maxf(length, 1.0)
		var at: float = 0.0
		while at < length:
			var end: float = minf(at + dash.x, length)
			draw_line(from + step * at, from + step * end, line, 1.5)
			at = end + dash.y
