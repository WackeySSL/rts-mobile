extends Camera2D
## Phase 0 one-finger pan for the test map. Phase 1 replaces it with the real camera.
##
## Handles only InputEventScreenDrag from any device (desktop mouse drags arrive as emulated
## touches) and ignores Mouse events. Camera2D limit_* clamps only the rendered view, not
## `position`, so overscrolling would leave a dead zone. After every move the position is
## clamped to the map rect inset by half the visible size.

@export var map_view: TestMapView


func _ready() -> void:
	var rect: Rect2i = map_view.map_rect_px()
	limit_left = rect.position.x
	limit_top = rect.position.y
	limit_right = rect.end.x
	limit_bottom = rect.end.y
	position = Rect2(rect).get_center()
	get_viewport().size_changed.connect(_clamp_to_map)
	_clamp_to_map()


func _unhandled_input(event: InputEvent) -> void:
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag == null:
		return
	position -= drag.relative / zoom
	_clamp_to_map()
	get_viewport().set_input_as_handled()


func _clamp_to_map() -> void:
	var rect: Rect2 = Rect2(map_view.map_rect_px())
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom
	var low: Vector2 = rect.position + half_view
	var high: Vector2 = rect.end - half_view
	var centre: Vector2 = rect.get_center()
	# Where the view is larger than the map on an axis, centre the map on that axis.
	position.x = centre.x if low.x > high.x else clampf(position.x, low.x, high.x)
	position.y = centre.y if low.y > high.y else clampf(position.y, low.y, high.y)
