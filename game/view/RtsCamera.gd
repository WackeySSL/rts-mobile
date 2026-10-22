class_name RtsCamera
extends Camera2D
## The RTS camera (ADR 0004 section 6): pan, pinch about a point, three zoom levels and a clamp
## to the map. It reads no input: TouchInput calls these methods in base px (viewport coords).
## For a PINCH gesture call `pan_by_screen(delta)` first, then `pinch(centre, scale)`.
##
## `limit_*` clamps only the rendered view, not `position`, which would leave a dead zone after
## overscrolling. So after every move or zoom `position` is clamped to the map rect inset by half
## the visible size.
##
## A turn of the phone (ADR 0015 section 4) keeps the world point at the centre and the world size
## per dp: the camera remembers the window's orientation and `UiScale.base_px_per_dp()` from its
## last `size_changed`, and when the orientation differs it stops the snap, rescales the zoom by
## the ratio of the two and puts the snap anchor at the new view centre.

## A ratio of base px per dp this close to 1 is the engine rounding the expanded axis of the
## stretch to whole base px (ADR 0015 section 2), not another screen: the zoom stays on its level.
const TURN_ROUNDING: float = 0.001

@export var settings: InputSettings

var _map_rect: Rect2 = Rect2()
var _anchor: Vector2 = Vector2.ZERO  ## Screen point of the last pinch or step, kept for the snap.
var _snap: Tween = null
var _snap_level: int = -1  ## Level the snap in flight heads for, else -1.
var _portrait: bool = false  ## The window's orientation at the last size_changed.
var _bppd: float = 1.0  ## `UiScale.base_px_per_dp()` at the last size_changed.


func _ready() -> void:
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	var start: float = settings.zoom_levels[clampi(settings.zoom_start_index, 0, _last_level())]
	zoom = Vector2(start, start)
	_anchor = _view_size() * 0.5
	_portrait = UiScale.is_portrait_size(get_tree().root.size)
	_bppd = UiScale.base_px_per_dp()
	get_viewport().size_changed.connect(_on_size_changed)
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
	_snap_to_level(_target_level())


## One level in or out (`direction` is +1 or -1) about `anchor`, stopping at the ends.
func step_zoom(direction: int, anchor: Vector2) -> void:
	_anchor = anchor
	_snap_to_level(clampi(_target_level() + direction, 0, _last_level()))


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


## Every resize: a turn first (the orientation differs from the last one seen), then the clamp.
## The orientation and base px per dp are refreshed on a same-orientation resize too, so the next
## turn compares with the metrics just before it. A flip runs this twice; the second run only
## clamps and refreshes the same values.
func _on_size_changed() -> void:
	var portrait: bool = UiScale.is_portrait_size(get_tree().root.size)
	var bppd: float = UiScale.base_px_per_dp()
	if portrait != _portrait:
		_turn(bppd / _bppd)
	_portrait = portrait
	_bppd = bppd
	_clamp_to_map()


## The turn rule of ADR 0015 section 4. `position`, the world point at the centre, is not touched
## and the clamp that follows moves it only as far as the new view needs. A turn does not snap to
## a level: the next gesture end or wheel step does.
func _turn(bppd_ratio: float) -> void:
	_stop_snap()
	if absf(bppd_ratio - 1.0) >= TURN_ROUNDING:
		var turned: float = _bounded_zoom(zoom.x * bppd_ratio)
		zoom = Vector2(turned, turned)
	_anchor = _view_size() * 0.5


func _last_level() -> int:
	return settings.zoom_levels.size() - 1


## The level a snap in flight heads for, else the nearest one: half way, the nearest is the old one.
func _target_level() -> int:
	return _snap_level if _snap_level >= 0 and _snap.is_valid() else zoom_level_index()


func _snap_to_level(index: int) -> void:
	_stop_snap()
	var target: float = settings.zoom_levels[index]
	if is_equal_approx(zoom.x, target):
		return
	if settings.zoom_snap_ms <= 0 or not is_inside_tree():
		_zoom_about(target, _anchor)
		return
	_snap = create_tween()
	_snap_level = index
	_snap.tween_method(_zoom_about.bind(_anchor), zoom.x, target, settings.zoom_snap_ms / 1000.0)


func _stop_snap() -> void:
	_snap_level = -1
	if _snap != null:
		_snap.kill()


## Sets the zoom so the world point under screen point `at` stays under it.
func _zoom_about(new_zoom: float, at: Vector2) -> void:
	var world: Vector2 = screen_to_world(at)
	var clamped: float = _bounded_zoom(new_zoom)
	zoom = Vector2(clamped, clamped)
	position = world - (at - _view_size() * 0.5) / zoom
	_clamp_to_map()


## `value` within the outer levels widened by `pinch_overshoot`: the bounds of a pinch.
func _bounded_zoom(value: float) -> float:
	var lowest: float = settings.zoom_levels[0] * (1.0 - settings.pinch_overshoot)
	var highest: float = settings.zoom_levels[_last_level()] * (1.0 + settings.pinch_overshoot)
	return clampf(value, lowest, highest)


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
