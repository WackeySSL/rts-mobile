class_name Minimap
extends Control
## The minimap (ADR 0019 section 4, ADR 0023 sections 4 and 12, plan P88): the map as an isometric
## diamond in a 2:1 box, in the floating panel at the top right sideways and at the right end of
## the build band upright (`BuildSidebar` moves the one node between them). `MinimapImage` paints
## one texel per cell at the fog's cadence, and this node draws that one texture under the fog's
## skew (`IsoProjection.cell_to_px`) scaled to the box, so the map's diamond is inscribed in the box
## and the camera's frame is a plain rectangle on it: the camera's visible world rect through the
## same scale. The frame is a child (`Frame`) that redraws only when it moves, so the texture is
## drawn on a new picture, a resize or a turn and never because the camera moved. The minimap reads
## the snapshot's picture and the camera, and sends nothing to the sim.
## A touch that starts on it (the GUI takes it, so it never reaches the map) jumps the camera to the
## ground point under the finger, through the inverse projection (`ground_at`), kept inside the
## map; a drag goes on jumping. A finger that started elsewhere never reaches it. The look of the
## frame is the theme's (`Minimap`: `frame`, `frame_edge`), its widths dp.

const THEME_TYPE: StringName = &"Minimap"
const FRAME_DP: float = 1.5  ## The frame's light line; its dark edge is as wide again each side.

## The sim's snapshot, for the picture; the camera, to jump and to frame; MapView, for the terrain
## colours.
@export var runner: MatchRunner
@export var camera: RtsCamera
@export var map_view: MapView
## Keep equal to `FogLayer.explored_alpha` and the sim's `fog_period_ticks`.
@export var explored_alpha: int = 140
@export var period_ticks: int = 3

var _picture: MinimapImage = MinimapImage.new()
var _frame: Frame = Frame.new()
var _finger: int = -1  ## The index of the finger that is on the minimap, else -1.
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
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the minimap never reaches the map.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # A cell is a crisp diamond.
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	resized.connect(queue_redraw)
	if runner != null:
		runner.ticked.connect(_on_ticked)
	_sync()


## A finger that was down when the node left the tree (a turn moves it) is over.
func _exit_tree() -> void:
	_finger = -1


func _process(_delta: float) -> void:
	_sync()
	var rect: Rect2 = frame_rect()
	if rect != _frame.rect:
		_frame.rect = rect
		_frame.queue_redraw()
		_frames += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_frame.queue_redraw()


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
## may lie outside the map, in a corner of the box: a Command's target is clamped by the sim.
func ground_at(local: Vector2) -> Vector2i:
	return IsoProjection.px_to_ground(local_to_world(local))


## The camera's visible rect on the minimap, within the box; empty without a camera or a map.
func frame_rect() -> Rect2:
	if camera == null or _picture.cols() <= 0:
		return Rect2()
	var view: Rect2 = camera.visible_world_rect()
	var from: Vector2 = world_to_local(view.position)
	return Rect2(from, world_to_local(view.end) - from).intersection(box_rect())


## Centres the camera on the ground point under `local`, kept inside the map (the diamond clamp).
func jump_to(local: Vector2) -> void:
	if camera == null or _picture.cols() <= 0:
		return
	var ground: Vector2i = ground_at(local)
	var x: int = clampi(ground.x, 0, _picture.cols() * World.MILLI_PER_TILE)
	var y: int = clampi(ground.y, 0, _picture.rows() * World.MILLI_PER_TILE)
	camera.centre_on(IsoProjection.ground_to_px(x, y))


## A press jumps and a drag of that finger goes on jumping; the release ends it. Only the first
## finger counts, and one that started elsewhere never gets here.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed and _finger < 0:
		_finger = touch.index
		jump_to(touch.position)
	elif touch != null and not touch.pressed and touch.index == _finger:
		_finger = -1
	elif drag != null and drag.index == _finger:
		jump_to(drag.position)


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
	_picture.period_ticks = period_ticks
	if _picture.update(snap, FogLayer.local_player_of(runner)):
		queue_redraw()


## The picture's cells as diamonds in the box: the fog's transform, scaled, with the map's top
## corner at the box's top edge and `rows` half-tiles from its left.
func _draw() -> void:
	var texture: ImageTexture = _picture.texture()
	if texture == null:
		return
	var s: float = _scale()
	var top: Vector2 = (
		box_rect().position + Vector2(_picture.rows() * IsoProjection.HALF_W * s, 0.0)
	)
	var skew: Transform2D = IsoProjection.cell_to_px()
	draw_set_transform_matrix(Transform2D(skew.x * s, skew.y * s, top))
	draw_texture_rect(texture, Rect2(0.0, 0.0, _picture.cols(), _picture.rows()), false)
	_draws += 1
