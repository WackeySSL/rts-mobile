class_name RadarMap
extends Control
## The full radar map (ADR 0025 section 7, plan P121): P88's `Minimap` node under a 48 dp head, the
## title "RADAR", the pin and the collapse button (48 dp each), on the HUD panel. It shows while
## `HudState` has `RADAR` open (the scope's tap opens it) and is placed by `HudCorners.place`: under
## the scope, right-aligned, or left of the right column on a short screen. The head says no
## "ONLINE": the radar is never offline here.
## The pin is `HudState.pinned`: while it is on no gesture and no timer folds the map, and its
## glyph (`glyph_pin`, else `glyph_pin_off`) shows at every opening. The collapse button closes
## `RADAR` at once. Without a pin the map folds `radar_close_ms` of frame time after the last touch
## on it (`HudState.advance`, run by the `HudStateFeed`): a press on the map or on its head, a lift,
## and every frame a finger stays down on it, even one that sends no event, call `touch_radar`.
## The map's own touches (a tap and a drag jump the camera, a hold with units selected sends MOVE)
## are the `Minimap` node's. This node takes its rect on `_ready` and on every resize.
## Opening the build drawer closes the map and opening the map closes the drawer, even a pinned
## map (one unfold at a time, `HudState`, ADR 0025 section 1). Until P120c moves the strike button,
## where the map stands left of the right column (a short screen, landscape) it ends a gap left of
## the strike row (the button, and its check mark and X while aiming), which stands on the top line
## left of the scope.

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const TITLE: String = "RADAR"
const TAP_DP: float = 48.0  ## The pin and the collapse button, each.
const GLYPH_DP: float = 28.0
const PAD_DP: float = 12.0  ## Before the title.
const PANEL_VARIATION: StringName = &"HudPanel"
const TITLE_VARIATION: StringName = &"CapsTitle"
const TAB_TYPE: StringName = &"SidebarTab"  ## Its grey (`icon_normal_color`) tints the pin off.

@export var feed: HudStateFeed
@export var minimap: Minimap  ## The full map: a child, placed in the box under the head.
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).
@export var strike_row: Control  ## The interim strike row (P112): the map keeps clear of it.

var _panel: Panel = Panel.new()
var _head: HBoxContainer = HBoxContainer.new()
var _title: Label = Label.new()
var _pin: Button = Button.new()
var _collapse: Button = Button.new()
var _fingers: Dictionary[int, bool] = {}  ## The fingers down on the map or its head, by index.


func _ready() -> void:
	add_to_group(TouchInput.CANCEL_GROUP)
	visible = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the map's panel never reaches the ground.
	_panel.name = "MapPanel"
	_panel.theme_type_variation = PANEL_VARIATION
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	move_child(_panel, 0)  # Behind the map and the head.
	_head.name = "MapHead"
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_head)
	var pad: Control = Control.new()
	pad.name = "MapPad"
	_min_dp(pad, Vector2(PAD_DP, 0.0))
	_head.add_child(pad)
	_title.name = "MapTitle"
	_title.text = TITLE
	_title.theme_type_variation = TITLE_VARIATION
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(_title)
	_fill_button(_pin, "MapPin")
	_fill_button(_collapse, "MapCollapse")
	_collapse.icon = load(ICON_ART % "glyph_collapse")
	_pin.pressed.connect(_on_pin_pressed)
	_collapse.pressed.connect(_on_collapse_pressed)
	feed.state.changed.connect(_on_changed)
	if strike_row != null:
		strike_row.item_rect_changed.connect(place)  # The aim widens it; a turn moves it.
		strike_row.visibility_changed.connect(place)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	_sync()


## A modal covers the screen: a finger that went down here is spent (TouchInput.CANCEL_GROUP).
func cancel_gestures() -> void:
	_fingers.clear()
	set_process(false)


## A finger that was down when the app lost focus may never send its release, as in TouchInput.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_gestures()


## Takes the rect `HudCorners.place` gives the full map, its head and its box.
func place() -> void:
	var rects: Dictionary[StringName, Rect2] = RadarScope.corners(get_viewport(), safe_area, true)
	var map: Rect2 = rects[HudCorners.MAP]
	position = map.position + Vector2(_clear_of_strike_row(rects), 0.0)
	size = map.size
	_head.position = rects[HudCorners.MAP_HEAD].position - map.position
	_head.size = rects[HudCorners.MAP_HEAD].size
	if minimap != null:
		minimap.position = rects[HudCorners.MAP_BOX].position - map.position
		minimap.size = rects[HudCorners.MAP_BOX].size


## How far left (a number at most 0, base px) the map must stand to end a gap left of the strike
## row. Only where the map is left of the right column (its top above the scope's foot) and only in
## landscape; elsewhere the row and the map do not meet but for the button's foot (P120c).
func _clear_of_strike_row(rects: Dictionary[StringName, Rect2]) -> float:
	if strike_row == null or not strike_row.is_visible_in_tree() or HudLayout.is_portrait():
		return 0.0
	if rects[HudCorners.MAP].position.y >= rects[HudCorners.SCOPE].end.y:
		return 0.0
	var limit: float = strike_row.get_global_rect().position.x - UiScale.dp(HudCorners.GAP_DP)
	return minf(limit - rects[HudCorners.MAP].end.x, 0.0)


## A press on the map or its head starts a finger's count; its lift starts the count over. The
## touch itself goes on to the control under it. A press drops what the index held before (a lift
## that never came), then counts if it is on the map.
func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null:
		return
	var held: bool = _fingers.erase(touch.index)
	if touch.pressed:
		if is_visible_in_tree() and get_global_rect().has_point(touch.position):
			_fingers[touch.index] = true
			feed.state.touch_radar()
	elif held:
		feed.state.touch_radar()
	set_process(not _fingers.is_empty())


## A finger resting on the map sends no event: its frames are touches.
func _process(_delta: float) -> void:
	if _fingers.is_empty():
		set_process(false)
	else:
		feed.state.touch_radar()


func _on_changed(_previous: HudState.Unfold) -> void:
	_sync()


## Shows the map while `RADAR` is open, and the pin as it is (the pin outlives the opening).
func _sync() -> void:
	var state: HudState = feed.state
	visible = state.is_open(HudState.Unfold.RADAR)
	if not visible:
		_fingers.clear()
		set_process(false)
	_pin.icon = load(ICON_ART % ("glyph_pin" if state.pinned else "glyph_pin_off"))
	_pin.modulate = get_theme_color(
		&"icon_pressed_color" if state.pinned else &"icon_normal_color", TAB_TYPE
	)


func _on_pin_pressed() -> void:
	feed.state.pinned = not feed.state.pinned


func _on_collapse_pressed() -> void:
	feed.state.close(HudState.Unfold.RADAR)


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	_head.add_theme_constant_override("separation", 0)
	for button: Button in [_pin, _collapse]:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(GLYPH_DP)))
	place()  # At once, so the open map does not stand at its old place for a frame.
	place.call_deferred()  # The strike row's band sorts a moment after the resize.


## One head button: flat, its glyph alone and centred, 48 dp each way, no focus ring left behind.
func _fill_button(button: Button, button_name: String) -> void:
	button.name = button_name
	button.flat = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_mode = Control.FOCUS_NONE
	_min_dp(button, Vector2(TAP_DP, TAP_DP))
	_head.add_child(button)


static func _min_dp(control: Control, size_dp: Vector2) -> void:
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = size_dp
	control.add_child(min_size)
