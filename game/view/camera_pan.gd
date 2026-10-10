extends Camera2D
## Phase 0 one-finger pan for the test map. Phase 1 replaces it with the real camera.
##
## Handles only InputEventScreenTouch and InputEventScreenDrag from any device (desktop mouse
## drags arrive as emulated touches) and ignores Mouse events. A touch whose press reaches
## `_unhandled_input` did not start on a GUI control, so its index is a pan touch. Its drags are
## taken in `_input` and marked handled, so a pan that crosses the Dev button keeps panning and
## never presses the button. A touch that starts on a GUI control is never a pan touch, so its
## drags still belong to that control. The camera pans only while exactly one pan touch is
## active; Phase 1 adds pinch and two-finger pan. Camera2D limit_* clamps only the rendered
## view, not `position`, so overscrolling would leave a dead zone. After every move the position
## is clamped to the map rect inset by half the visible size.

@export var map_view: TestMapView

## Touch indices that started on the map and are still down. The values are unused.
var _pan_touches: Dictionary = {}


func _ready() -> void:
	var rect: Rect2i = map_view.map_rect_px()
	limit_left = rect.position.x
	limit_top = rect.position.y
	limit_right = rect.end.x
	limit_bottom = rect.end.y
	position = Rect2(rect).get_center()
	get_viewport().size_changed.connect(_clamp_to_map)
	_clamp_to_map()


func _notification(what: int) -> void:
	# A finger that was down when the app lost focus may never send its release. Forget it,
	# or the stale index would count as a second finger and block the pan.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_pan_touches.clear()


## Runs before the GUI, so a release is never missed and a pan drag never reaches a Control.
func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if not touch.pressed:
			_pan_touches.erase(touch.index)
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag == null or not _pan_touches.has(drag.index):
		return
	if _pan_touches.size() == 1:
		position -= drag.relative / zoom
		_clamp_to_map()
	get_viewport().set_input_as_handled()


## Only presses the GUI did not take get here.
func _unhandled_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_pan_touches[touch.index] = true


func _clamp_to_map() -> void:
	var rect: Rect2 = Rect2(map_view.map_rect_px())
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom
	var low: Vector2 = rect.position + half_view
	var high: Vector2 = rect.end - half_view
	var centre: Vector2 = rect.get_center()
	# Where the view is larger than the map on an axis, centre the map on that axis.
	position.x = centre.x if low.x > high.x else clampf(position.x, low.x, high.x)
	position.y = centre.y if low.y > high.y else clampf(position.y, low.y, high.y)
