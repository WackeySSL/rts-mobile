class_name GhostControls
extends Control
## The check mark and the X of placement mode, beside the ghost (plan P86c, ADR 0024 section 10;
## they took the card row's place in P86, and the row no longer holds them). Each is `ACTION_DP`
## across, with the plates and glyphs of the strike's. The check mark is dimmed while the ghost
## does not fit, while a PLACE is pending and while it is "Blocked" (`placement.can_confirm()`) and
## sends the one PLACE; the X sends nothing and works in every state.
## Where: the anchor is the ghost's silhouette box on the screen (`placement.silhouette_rect()`),
## read every frame while the mode is on, so the buttons follow pans, pinches, zoom snaps, edge
## pans and turns. `place` picks the spot: a column right of the box (the check mark over the X),
## else the same on its left, else a row above it (the check mark left of the X), never below (the
## finger of a ghost drag ends below the ghost); each `ghost_grab_dp` + `RING_GAP_DP` away, so the
## buttons never cover the grab ring and a press on the ghost or in its ring means what it did,
## slid along its side to the nearest place inside the allowed rect and clear of the HUD. Where
## none fits, the right column is clamped into the allowed rect and may lie under a HUD control
## (which keeps its touch) or over the ring; the edge pan and a pan move the ghost out of that
## corner. The allowed rect is the safe area down to the build menu's real top (`HudLayout`).
## Hidden while a finger holds the ghost (`placement.dragging`, which also covers its edge pan) and
## shown again, beside the new tile, when it lets go.
## A child of the Hud before `SafeArea`, so a HUD control drawn over a button also wins its touch;
## outside `SafeArea` it has no theme of the HUD's, so the scene gives it the theme file. The dp,
## the safe area and the HUD controls' list are not looked up per frame: the first two are read
## when the window changes (`read_metrics`), the rects go into a scratch array made once.

const ACTION_DP: float = 64.0  ## The check mark and the X: placement's size (touch-ui-rules).
const ICON_DP: float = 32.0
const BETWEEN_DP: float = 16.0  ## From one button to the other.
const RING_GAP_DP: float = 8.0  ## Beyond the grab ring (`ghost_grab_dp`) round the silhouette.
const CONFIRM_VARIATION: StringName = &"StrikeConfirm"
const CANCEL_VARIATION: StringName = &"StrikeButton"
const ICON_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const EPSILON: float = 0.01  ## Base px: a rect that ends where another starts does not overlap it.

@export var placement: PlacementController
## The HUD controls the buttons keep clear of while they are visible: the Dev button, the ArmyBar,
## the SelectionPanel, the strike row, the build menu, the status pill and the minimap's slot.
@export var clear_of: Array[Control] = []

var _confirm: Button = Button.new()
var _cancel: Button = Button.new()
var _dp_px: float = 1.0  ## `UiScale.base_px_per_dp()`, read when the window changes.
var _safe: Rect2 = Rect2()  ## `UiScale.safe_rect_base()`, likewise.
var _rects: Array[Rect2] = []  ## The visible HUD controls' rects of this frame, one slot each.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Only the two buttons take touches.
	_confirm.name = "PlaceConfirm"
	_cancel.name = "PlaceCancel"
	_confirm.pressed.connect(placement.confirm)
	_cancel.pressed.connect(placement.cancel)
	for action: Array in [
		[_confirm, CONFIRM_VARIATION, "check"], [_cancel, CANCEL_VARIATION, "cross"]
	]:
		var button: Button = action[0]
		button.theme_type_variation = action[1]
		button.icon = load(ICON_ART % action[2])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER  # The icon alone, in the plate.
		button.focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
		add_child(button)
	placement.changed.connect(_on_changed)
	get_viewport().size_changed.connect(read_metrics)
	read_metrics()
	_on_changed()


## Reads the dp and the safe area again and sizes the buttons: a resize does it, and a test that
## puts in another `UiScale` override must call it. Not per frame: the engine's metrics are not
## cheap (a new `UiMetrics`, the platform's dpi and safe area).
func read_metrics() -> void:
	_dp_px = UiScale.base_px_per_dp()
	_safe = UiScale.safe_rect_base()
	for button: Button in [_confirm, _cancel]:
		button.add_theme_constant_override("icon_max_width", roundi(ICON_DP * _dp_px))
		button.custom_minimum_size = Vector2.ONE * (ACTION_DP * _dp_px)
		button.size = button.custom_minimum_size  # A plain Control parent never shrinks it.


## The mode began or ended, or the ghost's tile, verdict or answer changed.
func _on_changed() -> void:
	_confirm.disabled = not placement.can_confirm()
	set_process(placement.active)
	_follow()


func _process(_delta: float) -> void:
	_follow()


## Shows the buttons while the mode is on and no finger holds the ghost, and puts them beside it.
func _follow() -> void:
	var shown: bool = placement.active and not placement.dragging
	visible = shown
	if not shown:
		return
	if _rects.size() != clear_of.size():
		_rects.resize(clear_of.size())
	for index: int in clear_of.size():
		var part: Control = clear_of[index]
		_rects[index] = part.get_global_rect() if part.is_visible_in_tree() else Rect2()
	var bottom: float = maxf(HudLayout.map_bottom_px(_safe), _safe.position.y)
	var allowed: Rect2 = Rect2(_safe.position, Vector2(_safe.size.x, bottom - _safe.position.y))
	var grab_dp: float = placement.controller.settings.ghost_grab_dp
	var group: Rect2 = place(placement.silhouette_rect(), allowed, _rects, _dp_px, grab_dp)
	var along: Vector2 = Vector2(0.0, 1.0) if group.size.y > group.size.x else Vector2(1.0, 0.0)
	var cancel_at: Vector2 = group.position + along * ((ACTION_DP + BETWEEN_DP) * _dp_px)
	if _confirm.position != group.position:
		_confirm.position = group.position
	if _cancel.position != cancel_at:
		_cancel.position = cancel_at


## The two buttons' group on the screen, base px: a column (`ACTION_DP` wide, two buttons and the
## space between them high) or, above the ghost, a row, the check mark first. `box` is the ghost's
## silhouette box, `allowed` the rect the group must lie in, `hud` the rects to keep clear of (an
## empty one is no HUD) and `grab_dp` the grab ring's width (`ghost_grab_dp`). The candidates, in
## order: right of `box`, then left, then above, each `grab_dp` + `RING_GAP_DP` out and slid along
## its side to the nearest place that fits; if none does, the right column clamped into `allowed`.
## It runs every frame, so it makes no array: only values.
static func place(
	box: Rect2, allowed: Rect2, hud: Array[Rect2], dp_px: float, grab_dp: float
) -> Rect2:
	var button: float = ACTION_DP * dp_px
	var column: Vector2 = Vector2(button, 2.0 * button + BETWEEN_DP * dp_px)
	var gap: float = (grab_dp + RING_GAP_DP) * dp_px
	var centre: Vector2 = box.get_center()
	var right: Rect2 = Rect2(Vector2(box.end.x + gap, centre.y - column.y * 0.5), column)
	var slid: Rect2 = _slid(right, Vector2.AXIS_Y, allowed, hud)
	if slid.has_area():
		return slid
	var left: Rect2 = Rect2(Vector2(box.position.x - gap - column.x, right.position.y), column)
	slid = _slid(left, Vector2.AXIS_Y, allowed, hud)
	if slid.has_area():
		return slid
	var row: Vector2 = Vector2(column.y, column.x)
	var above: Rect2 = Rect2(Vector2(centre.x - row.x * 0.5, box.position.y - gap - row.y), row)
	slid = _slid(above, Vector2.AXIS_X, allowed, hud)
	if slid.has_area():
		return slid
	var room: Vector2 = Vector2(
		maxf(allowed.end.x - column.x, allowed.position.x),
		maxf(allowed.end.y - column.y, allowed.position.y)
	)
	return Rect2(right.position.clamp(allowed.position, room), column)


## `at` moved along `axis` to the nearest place that lies in `allowed` and clear of every rect of
## `hud`, or an empty rect where there is none (also when `at` is out of `allowed` across `axis`).
## The nearest place is `at` itself clamped into `allowed`, else a position that puts `at` against
## the edge of a HUD rect.
static func _slid(at: Rect2, axis: int, allowed: Rect2, hud: Array[Rect2]) -> Rect2:
	var cross: int = 1 - axis
	var low: float = allowed.position[axis]
	var high: float = allowed.end[axis] - at.size[axis]
	if (
		high < low - EPSILON
		or at.position[cross] < allowed.position[cross] - EPSILON
		or at.end[cross] > allowed.end[cross] + EPSILON
	):
		return Rect2()
	var wanted: float = at.position[axis]
	var best: float = clampf(wanted, low, maxf(high, low))
	if _clear(_moved(at, axis, best), hud):
		return _moved(at, axis, best)
	best = INF
	for part: Rect2 in hud:
		if not part.has_area():
			continue
		var before: float = part.position[axis] - at.size[axis]
		if absf(before - wanted) < absf(best - wanted) and _fits(at, axis, before, low, high, hud):
			best = before
		var after: float = part.end[axis]
		if absf(after - wanted) < absf(best - wanted) and _fits(at, axis, after, low, high, hud):
			best = after
	return Rect2() if is_inf(best) else _moved(at, axis, best)


## Whether `at` moved to `value` along `axis` stays within [`low`, `high`] and is clear of `hud`.
static func _fits(
	at: Rect2, axis: int, value: float, low: float, high: float, hud: Array[Rect2]
) -> bool:
	return (
		value >= low - EPSILON and value <= high + EPSILON and _clear(_moved(at, axis, value), hud)
	)


static func _moved(at: Rect2, axis: int, value: float) -> Rect2:
	var position: Vector2 = at.position
	position[axis] = value
	return Rect2(position, at.size)


## Whether `at` overlaps none of the rects of `hud` (an empty one is nothing).
static func _clear(at: Rect2, hud: Array[Rect2]) -> bool:
	for part: Rect2 in hud:
		if (
			part.has_area()
			and at.position.x < part.end.x - EPSILON
			and part.position.x < at.end.x - EPSILON
			and at.position.y < part.end.y - EPSILON
			and part.position.y < at.end.y - EPSILON
		):
			return false
	return true
