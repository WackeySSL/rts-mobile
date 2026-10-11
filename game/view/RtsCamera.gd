class_name RtsCamera
extends Camera2D
## The RTS camera (ADR 0004 section 6): pan, pinch about a point, three zoom levels and a clamp
## to the map. It reads no input: TouchInput calls these methods in base px (viewport coords).
## For a PINCH gesture call `pan_by_screen(delta)` first, then `pinch(centre, scale)`.
##
## `limit_*` clamps only the rendered view, not `position`, which would leave a dead zone after
## overscrolling. So after every move or zoom `position` is clamped to the map rect inset by half
## the visible size.

@export var settings: InputSettings

var _map_rect: Rect2 = Rect2()
var _anchor: Vector2 = Vector2.ZERO  ## Screen point of the last pinch or step, kept for the snap.
var _snap: Tween = null


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	var start: float = settings.zoom_levels[clampi(settings.zoom_start_index, 0, _last_level())]
	zoom = Vector2(start, start)
	_anchor = _view_size() * 0.5
	get_viewport().size_changed.connect(_clamp_to_map)
	_clamp_to_map()


func set_map_rect(rect: Rect2) -> void:
	_map_rect = rect
	limit_left = floori(rect.position.x)
	limit_top = floori(rect.position.y)
	limit_right = ceili(rect.end.x)
	limit_bottom = ceili(rect.end.y)
	_clamp_to_map()


## The world follows the fingers, so the camera moves by -delta / zoom.
func pan_by_screen(delta: Vector2) -> void:
	position -= delta / zoom
	_clamp_to_map()


## Zooms by `factor` about the screen point `centre`, within the outer levels widened by
## `pinch_overshoot`. A new pinch cancels a snap in flight. A factor that is not a positive number
## (two fingers on the same point) is ignored, as a NaN zoom would break the camera for good.
func pinch(centre: Vector2, factor: float) -> void:
	if is_nan(factor) or factor <= 0.0:
		return
	_stop_snap()
	_anchor = centre
	_zoom_about(zoom.x * factor, centre)


## Fingers up: snap to the nearest level (by ratio), about the last pinch point.
func end_gesture() -> void:
	_snap_to_level(zoom_level_index())


## One level in or out (`direction` is +1 or -1) about `anchor`, stopping at the ends.
func step_zoom(direction: int, anchor: Vector2) -> void:
	_anchor = anchor
	_snap_to_level(clampi(zoom_level_index() + direction, 0, _last_level()))


## Index of the level nearest to the current zoom, by ratio.
func zoom_level_index() -> int:
	var best: int = 0
	var best_gap: float = INF
	for i: int in settings.zoom_levels.size():
		var gap: float = absf(log(zoom.x / settings.zoom_levels[i]))
		if gap < best_gap:
			best = i
			best_gap = gap
	return best


func visible_world_rect() -> Rect2:
	var view: Vector2 = _view_size() / zoom
	return Rect2(position - view * 0.5, view)


func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - _view_size() * 0.5) / zoom


func world_to_screen(p: Vector2) -> Vector2:
	return (p - position) * zoom + _view_size() * 0.5


func centre_on(world_px: Vector2) -> void:
	position = world_px
	_clamp_to_map()


func _view_size() -> Vector2:
	return get_viewport_rect().size


func _last_level() -> int:
	return settings.zoom_levels.size() - 1


func _snap_to_level(index: int) -> void:
	_stop_snap()
	var target: float = settings.zoom_levels[index]
	if is_equal_approx(zoom.x, target):
		return
	if settings.zoom_snap_ms <= 0 or not is_inside_tree():
		_zoom_about(target, _anchor)
		return
	_snap = create_tween()
	_snap.tween_method(_zoom_about.bind(_anchor), zoom.x, target, settings.zoom_snap_ms / 1000.0)


func _stop_snap() -> void:
	if _snap != null:
		_snap.kill()


## Sets the zoom so the world point under screen point `at` stays under it.
func _zoom_about(new_zoom: float, at: Vector2) -> void:
	var world: Vector2 = screen_to_world(at)
	var lowest: float = settings.zoom_levels[0] * (1.0 - settings.pinch_overshoot)
	var highest: float = settings.zoom_levels[_last_level()] * (1.0 + settings.pinch_overshoot)
	var clamped: float = clampf(new_zoom, lowest, highest)
	zoom = Vector2(clamped, clamped)
	position = world - (at - _view_size() * 0.5) / zoom
	_clamp_to_map()


func _clamp_to_map() -> void:
	if not is_inside_tree() or not _map_rect.has_area():
		return
	var half_view: Vector2 = _view_size() * 0.5 / zoom
	var low: Vector2 = _map_rect.position + half_view
	var high: Vector2 = _map_rect.end - half_view
	var centre: Vector2 = _map_rect.get_center()
	# A map smaller than the view on an axis is centred on that axis.
	position.x = centre.x if low.x > high.x else clampf(position.x, low.x, high.x)
	position.y = centre.y if low.y > high.y else clampf(position.y, low.y, high.y)
