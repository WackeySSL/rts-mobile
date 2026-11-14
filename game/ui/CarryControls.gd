class_name CarryControls
extends Control
## The check mark and the X of the Board and Unload aims (P265, `touch-ui-rules`), beside the aimed
## point by GhostControls' column rule (`GhostControls.place`: right of the anchor, else left, else
## above, never below, inside the safe area and clear of the HUD), each `ACTION_DP` across. The
## anchor is the ringed carrier's pick square (its lifted centre, plus and minus its pick radius,
## at least `PICK_MIN_DP`) for Board, and a `POINT_DP` square round the chevron's ground point for
## Unload; with no carrier ringed or no point set there is no anchor and nothing shows. The check
## mark sends the one LOAD or UNLOAD (`CarryAim.confirm`), the X sends nothing. Read every frame
## while an aim is open, so the buttons follow pans, pinches and the carrier as it moves.
## A child of the Hud before `SafeArea`, as GhostControls is; the scene gives it the theme file.

const ACTION_DP: float = GhostControls.ACTION_DP
const ICON_DP: float = GhostControls.ICON_DP
const BETWEEN_DP: float = GhostControls.BETWEEN_DP
const PICK_MIN_DP: float = 24.0  ## The least half-width of the carrier's pick square.
const POINT_DP: float = 48.0  ## The square round the unload chevron.

@export var aim: CarryAim
@export var camera: RtsCamera
@export var unit_layer: UnitLayer
@export var controller: PlayerController
## The HUD controls the buttons keep clear of (the same list as GhostControls').
@export var clear_of: Array[Control] = []

var _confirm: Button = Button.new()
var _cancel: Button = Button.new()
var _dp_px: float = 1.0
var _safe: Rect2 = Rect2()
var _rects: Array[Rect2] = []
var _pick: PickSnapshot = PickSnapshot.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Only the two buttons take touches.
	add_to_group(TouchInput.CANCEL_GROUP)
	_confirm.name = "CarryConfirm"
	_cancel.name = "CarryCancel"
	_confirm.pressed.connect(aim.confirm)
	_cancel.pressed.connect(aim.cancel)
	for action: Array in [
		[_confirm, GhostControls.CONFIRM_VARIATION, "check"],
		[_cancel, GhostControls.CANCEL_VARIATION, "cross"]
	]:
		var button: Button = action[0]
		button.theme_type_variation = action[1]
		button.icon = load(GhostControls.ICON_ART % action[2])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		add_child(button)
	aim.changed.connect(_follow)
	get_viewport().size_changed.connect(read_metrics)
	read_metrics()
	_follow()


## Reads the dp and the safe area again and sizes the buttons (a resize does it).
func read_metrics() -> void:
	_dp_px = UiScale.base_px_per_dp()
	_safe = UiScale.safe_rect_base()
	for button: Button in [_confirm, _cancel]:
		button.add_theme_constant_override("icon_max_width", roundi(ICON_DP * _dp_px))
		button.custom_minimum_size = Vector2.ONE * (ACTION_DP * _dp_px)
		button.size = button.custom_minimum_size


## A modal covers the screen: a finger that went down on a button before it showed is spent.
func cancel_gestures() -> void:
	_confirm.disabled = true
	_cancel.disabled = true
	_cancel.disabled = false
	_follow()


func _process(_delta: float) -> void:
	_follow()


## The anchor rect on the screen (base px), empty while there is nothing to stand beside.
func anchor() -> Rect2:
	if aim.mode == CarryAim.Mode.UNLOAD and aim.has_point:
		var at: Vector2 = camera.world_to_screen(
			IsoProjection.ground_to_px(aim.point.x, aim.point.y)
		)
		return Rect2(
			at - Vector2.ONE * (POINT_DP * 0.5 * _dp_px), Vector2.ONE * (POINT_DP * _dp_px)
		)
	if aim.mode == CarryAim.Mode.BOARD and aim.carrier_id != 0:
		unit_layer.fill_pick_snapshot(_pick, UiScale.dp(controller.settings.hit_radius_dp))
		var at: int = _pick.ids.find(aim.carrier_id)
		if at >= 0:
			var half: float = maxf(_pick.radius_px[at], PICK_MIN_DP * _dp_px)
			return Rect2(_pick.screen_pos[at] - Vector2.ONE * half, Vector2.ONE * (2.0 * half))
	return Rect2()


func _follow() -> void:
	set_process(aim.is_active())
	var box: Rect2 = anchor() if aim.is_active() else Rect2()
	visible = box.has_area()
	if not visible:
		return
	_confirm.disabled = not aim.can_confirm()
	if _rects.size() != clear_of.size():
		_rects.resize(clear_of.size())
	for index: int in clear_of.size():
		var part: Control = clear_of[index]
		_rects[index] = part.get_global_rect() if part.is_visible_in_tree() else Rect2()
	var bottom: float = maxf(HudLayout.map_bottom_px(_safe), _safe.position.y)
	var allowed: Rect2 = Rect2(_safe.position, Vector2(_safe.size.x, bottom - _safe.position.y))
	var group: Rect2 = GhostControls.place(box, allowed, _rects, _dp_px, 0.0)
	var along: Vector2 = Vector2(0.0, 1.0) if group.size.y > group.size.x else Vector2(1.0, 0.0)
	var cancel_at: Vector2 = group.position + along * ((ACTION_DP + BETWEEN_DP) * _dp_px)
	if _confirm.position != group.position:
		_confirm.position = group.position
	if _cancel.position != cancel_at:
		_cancel.position = cancel_at
