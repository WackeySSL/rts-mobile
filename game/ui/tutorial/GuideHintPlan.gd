class_name GuideHintPlan
extends RefCounted
## What the coach mark's gesture hint does this frame (ADR 0048 section 6, plan row P592): which
## gesture, where it stands and how far it moves. One reused object, refilled by `resolve`, so a
## frame allocates nothing. Pure: it reads the step, the ring's box, the camera and the free
## field's point, and touches no node. Base px, except `vector_dp`.
##
## Resolution: a chain's lead-in step is a TAP on its control. Otherwise the beat's own gesture,
## where `AUTO` gives TAP on a control, a pinch for a `ZOOM_LEVEL` beat (out to zoom in, in to zoom
## out, by the camera's level against the beat's), a DRAG for `CAMERA_PANNED`, else NONE. A control
## or an on-screen tile is played at its centre; a beat with no anchor at the free field's point;
## a tile off the screen is a DRAG from the edge where it lies toward the free field, whatever the
## beat's gesture, since that pan is what brings it into view.

const MARGIN_DP: float = 8.0  ## The see-through test's room round the hand and its ring.
const DRAG_MAX_DP: float = 240.0  ## The longest drag toward an off-screen tile.
const RING_EXTRA_DP: float = 16.0  ## Line width and the double tap's second ring.

var kind: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.NONE
var point: Vector2 = Vector2.ZERO  ## Where the fingertip starts.
var vector_dp: Vector2 = Vector2.ZERO  ## The drag's or box's diagonal.
var bounds: Rect2 = Rect2()  ## Everything the hint draws, with its margin (empty: no hint).
var off_screen: bool = false  ## A drag toward a tile outside the screen.


func resolve(
	beat: TutorialBeatDef,
	aim: TutorialLeadInDef,
	lead: bool,
	ring: Rect2,
	camera: RtsCamera,
	field: Vector2,
	safe: Rect2,
	dp: float,
	size_dp: float
) -> void:
	kind = TutorialBeatDef.Gesture.NONE
	bounds = Rect2()
	off_screen = false
	if beat == null:
		return
	vector_dp = Vector2(beat.gesture_vector_dp)
	if vector_dp == Vector2.ZERO:
		vector_dp = GestureHint.DEFAULT_DRAG_DP
	var anchor: TutorialBeatDef.Anchor = aim.anchor if aim != null else TutorialBeatDef.Anchor.NONE
	var want: TutorialBeatDef.Gesture = beat.gesture
	if lead:
		want = TutorialBeatDef.Gesture.TAP
	elif want == TutorialBeatDef.Gesture.AUTO:
		want = _auto(beat, anchor, camera)
	if want == TutorialBeatDef.Gesture.NONE or want == TutorialBeatDef.Gesture.AUTO:
		return
	match anchor:
		TutorialBeatDef.Anchor.CONTROL:
			if not ring.has_area():
				return
			point = ring.get_center()
		TutorialBeatDef.Anchor.TILE:
			if camera == null:
				return
			var world: Vector2 = IsoProjection.cell_centre_px(aim.anchor_tile.x, aim.anchor_tile.y)
			var screen: Vector2 = camera.world_to_screen(world)
			point = screen
			if not safe.has_point(screen):
				want = TutorialBeatDef.Gesture.DRAG
				off_screen = true
				point = screen.clamp(safe.position, safe.end)
				var way: Vector2 = (field - point) / dp
				vector_dp = way.limit_length(DRAG_MAX_DP) if way != Vector2.ZERO else vector_dp
		_:
			point = field
	kind = want
	bounds = _bounds(want, dp, size_dp)
	point += _inside(bounds, safe)
	bounds.position += _inside(bounds, safe)


## The shift that brings `box` into `safe` (zero when it fits already or `safe` is smaller).
static func _inside(box: Rect2, safe: Rect2) -> Vector2:
	var shift: Vector2 = Vector2.ZERO
	for axis: int in 2:
		var low: float = safe.position[axis] - box.position[axis]
		var high: float = safe.end[axis] - box.end[axis]
		shift[axis] = maxf(low, 0.0) if low > 0.0 else minf(high, 0.0)
	return shift


static func _auto(
	beat: TutorialBeatDef, anchor: TutorialBeatDef.Anchor, camera: RtsCamera
) -> TutorialBeatDef.Gesture:
	if anchor == TutorialBeatDef.Anchor.CONTROL:
		return TutorialBeatDef.Gesture.TAP
	if beat.kind == TutorialConditions.Kind.CAMERA_PANNED:
		return TutorialBeatDef.Gesture.DRAG
	if beat.kind == TutorialConditions.Kind.ZOOM_LEVEL and camera != null:
		var level: int = camera.zoom_level_index()  # Levels rise with the zoom.
		if beat.value > level:
			return TutorialBeatDef.Gesture.PINCH_OUT
		if beat.value < level:
			return TutorialBeatDef.Gesture.PINCH_IN
	return TutorialBeatDef.Gesture.NONE


## The box of the hand, the press ring and the fingers' travel, about `point`, with the margin.
func _bounds(want: TutorialBeatDef.Gesture, dp: float, size_dp: float) -> Rect2:
	var side: float = size_dp * dp
	var pinch: bool = (
		want == TutorialBeatDef.Gesture.PINCH_OUT or want == TutorialBeatDef.Gesture.PINCH_IN
	)
	var tip: Vector2 = GestureHint.PINCH_TIP if pinch else GestureHint.POINT_TIP
	var reach: float = side * GestureHint.RING_RADIUS_SHARE + RING_EXTRA_DP * dp
	var box: Rect2 = Rect2(-tip * side, Vector2(side, side))
	box = box.merge(Rect2(Vector2(-reach, -reach), Vector2(reach, reach) * 2.0))
	if pinch:
		var far: Vector2 = GestureHint.PINCH_AXIS * side * GestureHint.SPREAD_FAR_SHARE
		for end: Vector2 in [far, -far]:
			box = box.merge(Rect2(end - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	elif want == TutorialBeatDef.Gesture.DRAG or want == TutorialBeatDef.Gesture.BOX:
		box = box.merge(Rect2(box.position + vector_dp * dp, box.size))
	return Rect2(point + box.position, box.size).grow(MARGIN_DP * dp)
