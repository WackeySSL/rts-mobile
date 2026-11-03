class_name Minimap
extends Control
## The minimap (ADR 0019 section 4, ADR 0023 section 4, ADR 0025 section 7, plans P88 and P121): the
## map as an isometric diamond in a 2:1 box. Since P121 it is the full radar map: this one node
## stands in the box under the head of `RadarMap`, which shows it while `RADAR` is unfolded (the
## picture goes on painting while it is folded away, for `RadarScope`'s crop). `MinimapImage` paints
## one texel per cell at the fog's cadence, and this node draws that one texture under the fog's
## skew (`IsoProjection.cell_to_px`) scaled to the box, so the map's diamond is inscribed in the box
## and the camera's frame is a plain rectangle on it: the camera's visible world rect through the
## same scale. The frame is a child (`Frame`) that redraws only when it moves, so the texture is
## drawn on a new picture, a resize or a turn and never because the camera moved. The minimap reads
## the snapshot's picture and the camera, and sends nothing to the sim itself.
## A touch that starts on it (the GUI takes it, so it never reaches the map) jumps the camera to the
## ground point under the finger, through the inverse projection (`ground_at`), kept inside the
## map; a drag goes on jumping. A finger that started elsewhere never reaches it.
## A hold (P88b, ADR 0019 section 4) orders: a finger that rests on it for `long_press_ms` within
## `tap_slop_dp` of where it went down asks `controller` to MOVE the selected units to the ground
## point the camera last jumped to for that finger (`clamped_ground_at`: inside the map, so the
## chevrons are on the map and the units go where the view went), once per finger. The point is
## taken at each event of the finger, so a resize during the hold cannot move it. A tap, a finger
## that moves beyond the slop first (a drag), and a hold with no unit selected order nothing; the
## camera jumps in every case. The clock is polled in `_process` while the finger rests, as the
## map's long-press is (`GestureRecognizer.advance`), so a release never turns into a hold. A turn,
## a focus loss, the node leaving the tree or being hidden ends the finger, and a turn never orders
## (ADR 0015 section 3). A HUD control takes the touch, so the hold never reaches the map's
## recognizer and never collapses the build menu (ADR 0024 section 5). All of it is this node's
## own, so it goes wherever the node goes. The look of the frame is the theme's (`Minimap`:
## `frame`, `frame_edge`), its widths dp.

const THEME_TYPE: StringName = &"Minimap"
const PING_DP: float = 8.0  ## The cue ping's ring radius.
const FRAME_DP: float = 1.5  ## The frame's light line; its dark edge is as wide again each side.

## The sim's snapshot, for the picture; the camera, to jump and to frame; MapView, for the terrain
## colours.
@export var runner: MatchRunner
@export var camera: RtsCamera
@export var map_view: MapView
## Sends the hold's MOVE and gives the thresholds (`long_press_ms`, `tap_slop_dp`); without one a
## hold does nothing.
@export var controller: PlayerController
## The attack cue (ADR 0025 section 8): a ping at the hit, drawn with the texture on a cue's change.
@export var cues: AttackCues
## Keep equal to `FogLayer.explored_alpha`. The cadence is the scenario's `fog_period_ticks`.
@export var explored_alpha: int = 140

## Returns the time in ms. Tests replace it.
var clock: Callable = Time.get_ticks_msec

var _picture: MinimapImage = MinimapImage.new()
var _frame: Frame = Frame.new()
var _finger: int = -1  ## The index of the finger that is on the minimap, else -1.
var _pressed_at: Vector2 = Vector2.ZERO  ## Where that finger went down, local.
var _ground: Vector2i = Vector2i.ZERO  ## The map point under it at its last event, milli-tiles.
var _down_ms: int = 0
var _hold_open: bool = false  ## It may still hold: within the slop, and no MOVE asked for yet.
var _default_settings: InputSettings = null
var _portrait: bool = false  ## The window's orientation at the last resize.
var _draws: int = 0
var _frames: int = 0


## The camera's frame: two polylines of one rectangle, the dark edge under the light line.
class Frame:
	extends Control
	var rect: Rect2 = Rect2()

	func _draw() -> void:
		if not rect.has_area():
			return
		var top_right: Vector2 = Vector2(rect.end.x, rect.position.y)
		var bottom_left: Vector2 = Vector2(rect.position.x, rect.end.y)
		var corners: PackedVector2Array = PackedVector2Array(
			[rect.position, top_right, rect.end, bottom_left, rect.position]
		)
		var line: float = UiScale.dp(FRAME_DP)
		draw_polyline(corners, get_theme_color(&"frame_edge", THEME_TYPE), line * 3.0)
		draw_polyline(corners, get_theme_color(&"frame", THEME_TYPE), line)


func _ready() -> void:
	add_to_group(TouchInput.CANCEL_GROUP)
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the minimap never reaches the map.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # A cell is a crisp diamond.
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	resized.connect(queue_redraw)
	if cues != null:
		cues.cue_changed.connect(queue_redraw)
	_portrait = UiScale.is_portrait_size(get_tree().root.size)
	get_viewport().size_changed.connect(_on_size_changed)
	if runner != null:
		runner.ticked.connect(_on_ticked)
	_sync()


## A finger that was down when the node left the tree (a turn moves it) is over.
func _exit_tree() -> void:
	_end_finger()


func _process(_delta: float) -> void:
	_poll_hold()
	_sync()
	var rect: Rect2 = frame_rect()
	if rect != _frame.rect:
		_frame.rect = rect
		_frame.queue_redraw()
		_frames += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_frame.queue_redraw()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_finger()  # A finger that was down may never send its release, as in TouchInput.
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_end_finger()  # A finger on a minimap that is folded away or hidden is nobody's.


## How many times the picture was painted: at the fog's cadence, not per frame.
func redraw_count() -> int:
	return _picture.redraw_count()


## How many times this node drew its texture (a new picture, a resize or a turn): one textured quad
## each time, and none for a frame that only moved the camera.
func draw_count() -> int:
	return _draws


## How many times the camera's frame moved.
func frame_count() -> int:
	return _frames


## The picture, for tests: its CPU-side image and texture.
func picture() -> MinimapImage:
	return _picture


## The largest 2:1 box that fits the control, centred: the map's diamond is inscribed in it.
func box_rect() -> Rect2:
	var width: float = minf(size.x, size.y * 2.0)
	var box: Vector2 = Vector2(width, width / 2.0)
	return Rect2((size - box) / 2.0, box)


## The point of the control that world px `world` (the iso screen space of `IsoProjection`) is at.
func world_to_local(world: Vector2) -> Vector2:
	var bounds: Rect2 = IsoProjection.map_bounds(_picture.cols(), _picture.rows())
	return box_rect().position + (world - bounds.position) * _scale()


## The world px at the control's point `local`: the inverse of `world_to_local`.
func local_to_world(local: Vector2) -> Vector2:
	var bounds: Rect2 = IsoProjection.map_bounds(_picture.cols(), _picture.rows())
	return bounds.position + (local - box_rect().position) / maxf(_scale(), 0.000001)


## The ground point (milli-tiles) under the control's point `local`, by the inverse projection. It
## may lie outside the map, in a corner of the box: `clamped_ground_at` keeps it inside.
func ground_at(local: Vector2) -> Vector2i:
	return IsoProjection.px_to_ground(local_to_world(local))


## `ground_at`, each axis clamped into the map (`[0, cols] x [0, rows]` tiles), so a touch beside
## the diamond lands on its nearest edge. The camera centres on it and a hold orders it. Zero
## without a map.
func clamped_ground_at(local: Vector2) -> Vector2i:
	if _picture.cols() <= 0:
		return Vector2i.ZERO
	var ground: Vector2i = ground_at(local)
	return Vector2i(
		clampi(ground.x, 0, _picture.cols() * World.MILLI_PER_TILE),
		clampi(ground.y, 0, _picture.rows() * World.MILLI_PER_TILE)
	)


## The camera's visible rect on the minimap, within the box; empty without a camera or a map.
func frame_rect() -> Rect2:
	if camera == null or _picture.cols() <= 0:
		return Rect2()
	var view: Rect2 = camera.visible_world_rect()
	var from: Vector2 = world_to_local(view.position)
	return Rect2(from, world_to_local(view.end) - from).intersection(box_rect())


## The world px the camera is centred on for a touch at `local`: `clamped_ground_at` projected
## back, so a touch beside the diamond lands on its nearest edge. Zero without a map.
func centre_for(local: Vector2) -> Vector2:
	if _picture.cols() <= 0:
		return Vector2.ZERO
	var ground: Vector2i = clamped_ground_at(local)
	return IsoProjection.ground_to_px(ground.x, ground.y)


## Centres the camera on the ground point under `local` (`centre_for`).
func jump_to(local: Vector2) -> void:
	if camera != null and _picture.cols() > 0:
		camera.centre_on(centre_for(local))


## The transform that turns a cell of the picture into its diamond on this control: the fog's
## skew scaled to the box, with the map's top corner, ground (0, 0), where `world_to_local` puts it.
## `_draw` draws the texture under it, so the picture and every touch and frame share one mapping.
func cell_transform() -> Transform2D:
	var skew: Transform2D = IsoProjection.cell_to_px()
	var s: float = _scale()
	return Transform2D(skew.x * s, skew.y * s, world_to_local(IsoProjection.ground_to_px(0, 0)))


## A press jumps and a drag of that finger goes on jumping; the release ends it. Only the first
## finger counts, and one that started elsewhere never gets here. A press for the finger that is
## down already is a release that was lost, and starts again. The press also starts the hold
## (`_poll_hold`), and a drag beyond the slop ends its chance.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed and (_finger < 0 or touch.index == _finger):
		_finger = touch.index
		_pressed_at = touch.position
		_ground = clamped_ground_at(touch.position)
		_down_ms = clock.call()
		_hold_open = controller != null
		jump_to(touch.position)
	elif touch != null and not touch.pressed and touch.index == _finger:
		_end_finger()
	elif drag != null and drag.index == _finger:
		_ground = clamped_ground_at(drag.position)
		if _hold_open:  # Beyond the slop it is a drag, and never a hold.
			var slop: float = UiScale.dp(_input_settings().tap_slop_dp)
			_hold_open = drag.position.distance_to(_pressed_at) <= slop
		jump_to(drag.position)


## A modal covers the screen: the finger on the minimap is nobody's (TouchInput.CANCEL_GROUP).
func cancel_gestures() -> void:
	_end_finger()


## The finger is up, or gone: nothing of it is left.
func _end_finger() -> void:
	_finger = -1
	_hold_open = false


## A turn (another orientation than at the last resize) ends the finger, as it ends every gesture
## (ADR 0015 section 3): its place belongs to the old layout, and a turn never issues a Command.
## The node does not rely on being moved between homes for it.
func _on_size_changed() -> void:
	var portrait: bool = UiScale.is_portrait_size(get_tree().root.size)
	if portrait != _portrait:
		_portrait = portrait
		_end_finger()


## Once the finger has rested for `long_press_ms` without leaving the slop, asks the controller for
## the MOVE (it sends none without units selected). It asks once: the hold is spent either way.
func _poll_hold() -> void:
	if not _hold_open:
		return
	var now_ms: int = clock.call()
	if now_ms - _down_ms < _input_settings().long_press_ms:
		return
	_hold_open = false
	controller.move_selected_to(_ground)


## The thresholds: the controller's, or the ADR table as PlayerController has it.
func _input_settings() -> InputSettings:
	if controller != null and controller.settings != null:
		return controller.settings
	if _default_settings == null:
		_default_settings = InputSettings.new()
	return _default_settings


func _on_ticked(_tick: int) -> void:
	_sync()


## Minimap px per world px: the box is as wide as the diamond's bounding rect.
func _scale() -> float:
	var span: float = float(_picture.cols() + _picture.rows()) * IsoProjection.HALF_W
	return box_rect().size.x / span if span > 0.0 else 0.0


func _sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	if map_view != null:
		_picture.terrain_colours = map_view.colors
	_picture.explored_alpha = explored_alpha
	if runner.scenario != null:
		_picture.team_triads = runner.scenario.team_triads
	if runner.scenario != null and runner.scenario.rules != null:
		_picture.period_ticks = runner.scenario.rules.fog_period_ticks
	if _picture.update(snap, FogLayer.local_player_of(runner)):
		queue_redraw()


## The picture's cells as diamonds in the box, under `cell_transform`.
func _draw() -> void:
	var texture: ImageTexture = _picture.texture()
	if texture == null:
		return
	draw_set_transform_matrix(cell_transform())
	draw_texture_rect(texture, Rect2(0.0, 0.0, _picture.cols(), _picture.rows()), false)
	_draws += 1
	if cues != null and cues.active:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var at: Vector2 = world_to_local(cues.point)
		var radius: float = UiScale.dp(PING_DP)
		var danger: Color = get_theme_color(&"danger", &"HudTokens")
		draw_arc(at, radius, 0.0, TAU, 24, get_theme_color(&"frame_edge", THEME_TYPE), radius * 0.6)
		draw_arc(at, radius, 0.0, TAU, 24, danger, UiScale.dp(FRAME_DP) * 2.0)
