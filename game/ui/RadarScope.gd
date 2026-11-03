class_name RadarScope
extends Control
## The radar scope (ADR 0025 section 7, plan P121): a 56 dp round window at the top right on the
## ground round the camera, a crop of P88's minimap picture (`Minimap.picture()`, one texel per
## cell, the fog's cadence) drawn under the same iso skew as the full map (`cell_to_px`), so
## up on the scope is up on the screen. It is centred on the camera's ground centre and reaches
## `scope_radius_tiles` (`data/input_settings.tres`) to the rim: the rim is where a ground circle of
## that radius meets the screen's horizontal (`IsoProjection.ellipse_px`). The crop is one textured
## polygon of 32 points (the Compatibility renderer, no shader), cut to the map's diamond where the
## camera is near an edge, over the HUD panel's dark disc; the camera's frame is a white rectangle
## clipped to the disc. The camera's centre is the disc's centre, so the frame is always centred.
## It redraws when the camera moves (its centre, its zoom or the view) or the picture is painted
## anew, a resize or a theme change, and never per frame at rest.
## A tap (a press and a release on it by one finger) opens `RADAR` (`HudState`), whose full map is
## `RadarMap`'s. The touch is the scope's own: it never reaches the map. This node takes the scope's
## rect from `HudCorners.place` on `_ready` and on every resize, in both orientations.

const POINTS: int = 32  ## Corners of the disc and of its crop.
const TOKENS: StringName = &"HudTokens"
const RING_DP: float = 2.0  ## The rim's line, the HUD panel's edge colour.
const WEDGE_HALF: float = 0.4  ## Half the cue wedge's spread on the rim (radians).
const WEDGE_DEPTH_DP: float = 10.0  ## How far its tip reaches in from the rim.
const PING_DP: float = 5.0  ## The ping's ring radius when the hit is inside the scope.

@export var feed: HudStateFeed  ## `state.open(RADAR)` on a tap; its settings give the radius.
@export var minimap: Minimap  ## The picture, painted at the fog's cadence.
@export var camera: RtsCamera  ## The centre of the crop and the frame.
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).
@export var cues: AttackCues  ## An attack cue shows as a rim wedge, or a ping inside (section 8).

var _finger: int = -1  ## The index of the finger that pressed on the scope, else -1.
var _view: Rect2 = Rect2()  ## The camera's visible world rect at the last draw.
var _paints: int = -1  ## The picture's `redraw_count()` at the last draw.
var _draws: int = 0
var _wedges: int = 0
var _rings: int = 0


func _ready() -> void:
	add_to_group(TouchInput.CANCEL_GROUP)
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the scope never reaches the map.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # A cell is a crisp diamond.
	resized.connect(queue_redraw)
	if cues != null:
		cues.cue_changed.connect(queue_redraw)
	get_viewport().size_changed.connect(place)
	place()


## The scope's and the full map's rects for the screen in force (`HudCorners.place`, the safe rect
## of `safe_area`), nothing else shown: P121 applies the radar's parts only, the others keep their
## places until their rows. `map` adds the full map's rects.
static func corners(
	viewport: Viewport, safe_area: SafeAreaMargin, map: bool = false
) -> Dictionary[StringName, Rect2]:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.map = map
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(viewport.get_visible_rect(), margin_dp)
	return HudCorners.place(safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown)


## Takes the scope's rect (56 dp, the safe rect's top right corner).
func place() -> void:
	var rect: Rect2 = corners(get_viewport(), safe_area)[HudCorners.SCOPE]
	position = rect.position
	size = rect.size
	queue_redraw()


## How many times the scope was drawn: on a move of the camera or a new picture, never per frame.
func draw_count() -> int:
	return _draws


## World px from the camera's centre to the rim for a ground radius of `tiles`.
static func rim_world_px(tiles: int) -> float:
	return IsoProjection.ellipse_px(tiles * World.MILLI_PER_TILE).x


## The disc's `count` corners, clockwise from the right, `radius` from `centre`.
static func disc_points(centre: Vector2, radius: float, count: int = POINTS) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(count)
	for index: int in count:
		out[index] = centre + Vector2.from_angle(TAU * index / count) * radius
	return out


## The texture coordinate of world px `world` on a picture of `cols` x `rows` cells: the inverse of
## the cell skew (a cell north-east of another, the grid's -y, is up and right on the screen).
static func uv_of(world: Vector2, cols: int, rows: int) -> Vector2:
	var cell: Vector2 = IsoProjection.cell_to_px().affine_inverse() * world
	return Vector2(cell.x / maxf(cols, 1), cell.y / maxf(rows, 1))


## Scope px per world px: the rim is `scope_radius_tiles` away.
func world_scale() -> float:
	return _radius() / rim_world_px(_tiles())


## The point of the scope that world px `world` is at, the camera's centre being its middle.
func world_to_local(world: Vector2) -> Vector2:
	return size * 0.5 + (world - _centre()) * world_scale()


## The world px at the scope's point `local`: the inverse of `world_to_local`.
func local_to_world(local: Vector2) -> Vector2:
	return _centre() + (local - size * 0.5) / world_scale()


## The point of the scope that cell (`col`, `row`) of the picture has its top corner at.
func cell_to_local(col: float, row: float) -> Vector2:
	return world_to_local(IsoProjection.cell_to_px() * Vector2(col, row))


## The camera's frame on the scope, unclipped: the visible world rect scaled about the middle.
func frame_rect() -> Rect2:
	if camera == null:
		return Rect2()
	var view: Rect2 = camera.visible_world_rect()
	return Rect2(world_to_local(view.position), view.size * world_scale())


## The pieces of the textured crop: the disc cut to the map's diamond. One piece of 32 points while
## the disc is inside the map, a cut one near an edge, none without a picture.
func crop_pieces() -> Array[PackedVector2Array]:
	var picture: MinimapImage = null if minimap == null else minimap.picture()
	if picture == null or picture.texture() == null or camera == null:
		return []
	var disc: PackedVector2Array = disc_points(size * 0.5, _radius())
	var diamond: PackedVector2Array = IsoProjection.map_diamond(picture.cols(), picture.rows())
	for index: int in diamond.size():
		diamond[index] = world_to_local(diamond[index])
	var pieces: Array[PackedVector2Array] = []
	pieces.assign(Geometry2D.intersect_polygons(disc, diamond))
	return pieces


## A press on the scope and its release by the same finger, still on it, is a tap.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_finger = touch.index
	elif touch.index == _finger:
		_finger = -1
		if not touch.canceled and Rect2(Vector2.ZERO, size).has_point(touch.position):
			if feed != null:
				feed.state.open(HudState.Unfold.RADAR)


## A modal covers the screen: a finger that went down here is spent (TouchInput.CANCEL_GROUP).
func cancel_gestures() -> void:
	_finger = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


## Draws again when the camera moved or the picture is new; at rest this is a few comparisons.
func _process(_delta: float) -> void:
	if camera == null:
		return
	var view: Rect2 = camera.visible_world_rect()
	var paints: int = -1 if minimap == null else minimap.redraw_count()
	if view != _view or paints != _paints:
		queue_redraw()


func _draw() -> void:
	_draws += 1
	_view = camera.visible_world_rect() if camera != null else Rect2()
	_paints = -1 if minimap == null else minimap.redraw_count()
	var centre: Vector2 = size * 0.5
	var disc: PackedVector2Array = disc_points(centre, _radius())
	draw_colored_polygon(disc, get_theme_color(&"panel", TOKENS))
	var texture: ImageTexture = null if minimap == null else minimap.picture().texture()
	if texture != null:
		var cols: int = minimap.picture().cols()
		var rows: int = minimap.picture().rows()
		for piece: PackedVector2Array in crop_pieces():
			var uvs: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in piece:
				uvs.append(uv_of(local_to_world(point), cols, rows))
			draw_colored_polygon(
				piece, get_theme_color(&"picture", Minimap.THEME_TYPE), uvs, texture
			)
	_draw_frame(disc)
	_draw_cue()
	var ring: PackedVector2Array = disc.duplicate()
	ring.append(disc[0])
	draw_polyline(ring, get_theme_color(&"border", TOKENS), UiScale.dp(RING_DP))


## Where the shown cue is on the scope, from its middle (the screen's directions); zero for none.
func cue_offset() -> Vector2:
	if cues == null or not cues.active:
		return Vector2.ZERO
	return world_to_local(cues.point) - size * 0.5


## Whether the shown cue lies beyond the scope, so that it is a wedge on the rim, not a ping.
func cue_on_rim() -> bool:
	return cue_offset().length() > _radius() - UiScale.dp(PING_DP)


## The cue's wedge on the rim, tip first (the tip is inside, toward the middle), in the scope's own
## px: it points the way the hit lies from the camera's centre. Empty for no cue or a hit inside
## the scope (that one is a ring).
func cue_wedge() -> PackedVector2Array:
	var wedge: PackedVector2Array = PackedVector2Array()
	if not cue_on_rim():
		return wedge
	var angle: float = cue_offset().angle()
	var radius: float = _radius()
	wedge.append(size * 0.5 + Vector2.from_angle(angle) * (radius - UiScale.dp(WEDGE_DEPTH_DP)))
	for step: int in 5:
		var spread: float = lerpf(-WEDGE_HALF, WEDGE_HALF, step / 4.0)
		wedge.append(size * 0.5 + Vector2.from_angle(angle + spread) * radius)
	return wedge


## How many wedges and rings the scope drew for a cue (a seam for the tests).
func cue_draws() -> Vector2i:
	return Vector2i(_wedges, _rings)


## The attack cue: a red wedge on the rim toward the hit (a shape, not colour alone), or, when the
## hit lies inside the scope's radius, a red ring at its place.
func _draw_cue() -> void:
	if cues == null or not cues.active:
		return
	var danger: Color = get_theme_color(&"danger", TOKENS)
	if cue_on_rim():
		draw_colored_polygon(cue_wedge(), danger)
		_wedges += 1
		return
	var ping: float = UiScale.dp(PING_DP)
	var at: Vector2 = size * 0.5 + cue_offset()
	draw_arc(at, ping, 0.0, TAU, 16, get_theme_color(&"frame_edge", Minimap.THEME_TYPE), ping)
	draw_arc(at, ping, 0.0, TAU, 16, danger, UiScale.dp(RING_DP))
	_rings += 1


## The camera's frame, a dark edge under a light line, cut to the disc.
func _draw_frame(disc: PackedVector2Array) -> void:
	var frame: Rect2 = frame_rect()
	if not frame.has_area():
		return
	var corners_px: PackedVector2Array = PackedVector2Array(
		[
			frame.position,
			Vector2(frame.end.x, frame.position.y),
			frame.end,
			Vector2(frame.position.x, frame.end.y)
		]
	)
	var line: float = UiScale.dp(Minimap.FRAME_DP)
	for shape: PackedVector2Array in Geometry2D.intersect_polygons(corners_px, disc):
		var closed: PackedVector2Array = shape.duplicate()
		closed.append(shape[0])
		draw_polyline(closed, get_theme_color(&"frame_edge", Minimap.THEME_TYPE), line * 3.0)
		draw_polyline(closed, get_theme_color(&"frame", Minimap.THEME_TYPE), line)


func _radius() -> float:
	return minf(size.x, size.y) * 0.5


## The ground circle's radius in tiles, from the state's settings (the file's table).
func _tiles() -> int:
	if feed == null:
		return InputSettings.new().scope_radius_tiles
	return maxi(feed.state.settings.scope_radius_tiles, 1)


func _centre() -> Vector2:
	return Vector2.ZERO if camera == null else camera.position
