class_name GuideHintPlan
extends RefCounted
## What the coach mark's gesture hint does this frame (ADR 0048 section 6, plan row P592): which
## gesture, where it stands and how far it moves. One reused object, refilled by `resolve`, so a
## frame allocates nothing. Pure: it reads the step, the ring's box, the camera and the free
## field's point, and touches no node. Base px, except `vector_dp`.
##
## Resolution: a tile off the screen first (below). Else a chain's lead-in step is a TAP on its
## control, and otherwise the beat's own gesture, where `AUTO` gives TAP on a control, a pinch for a
## `ZOOM_LEVEL` beat (out to zoom in, in to zoom out, by the camera's level against the beat's), a
## DRAG for `CAMERA_PANNED`, else NONE. A control or an on-screen tile is played with the fingertip
## on its centre; a beat with no anchor at the free field's point.
##
## A tile off the screen shows a DRAG from the edge where it lies toward the free field, for `AUTO`
## and for any explicit gesture: that pan is what brings the tile into view. An explicit `NONE`
## suppresses it. A `UNIT` anchor (ADR 0048 section 13.5) is a TAP on the unit's point under `AUTO`;
## a unit outside the field (off the screen or under the HUD) gets that same drag, on a lead-in
## too, since a tap on its pinned ring selects nothing; with no unit there is no hand.
##
## Fitting the safe rect: the fingertip is never moved off a control or a tile. The hand hangs off
## the tip flipped (`flip_x`, `flip_y`) to the side that fits, a drag that would leave the screen
## turns round or is cut short, and the press ring's overshoot past the edge is cut from `bounds`.
## Where nothing is aimed at (the field point, the start of the drag toward a tile) the point
## itself is shifted in. A unit's drag starts on free field, never under a card button or a HUD
## part: its start moves to the nearest free point, and with none there is no hand (`_free_start`).

const START_GAP_DP: float = 1.0  ## A free start lies this far past a blocked rect's grown edge.

var kind: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.NONE
var point: Vector2 = Vector2.ZERO  ## Where the fingertip starts.
var vector_dp: Vector2 = Vector2.ZERO  ## The drag's or box's diagonal.
var bounds: Rect2 = Rect2()  ## Everything the hint draws, with its margin (empty: no hint).
var off_screen: bool = false  ## A drag toward a tile outside the screen.
var flip_x: bool = false  ## The hand hangs left of the tip.
var flip_y: bool = false  ## The hand hangs above the tip.

var _edges: Array[Rect2] = []  ## Reused: the rects a drag's start looks along for a free point.


## `field_of` is a Callable returning the free field's point; it is called only when a branch needs
## it. `settings` gives `hint_size_dp`, `hint_margin_dp` and `hint_drag_max_dp`.
func resolve(
	beat: TutorialBeatDef,
	aim: TutorialLeadInDef,
	lead: bool,
	ring: Rect2,
	camera: RtsCamera,
	field_of: Callable,
	safe: Rect2,
	dp: float,
	settings: GuideSettingsDef,
	unit: GuideUnitAnchor = null
) -> void:
	kind = TutorialBeatDef.Gesture.NONE
	bounds = Rect2()
	off_screen = false
	flip_x = false
	flip_y = false
	var on_unit: bool = aim != null and aim.anchor == TutorialBeatDef.Anchor.UNIT
	if beat == null or (on_unit and (unit == null or unit.point == Vector2.INF)):
		return  # No unit: no hand.
	vector_dp = Vector2(beat.gesture_vector_dp)
	if vector_dp == Vector2.ZERO:
		vector_dp = GestureHint.DEFAULT_DRAG_DP
	var anchor: TutorialBeatDef.Anchor = aim.anchor if aim != null else TutorialBeatDef.Anchor.NONE
	var want: TutorialBeatDef.Gesture = beat.gesture
	var shiftable: bool = false  # The point aims at nothing: it may be moved to fit.
	var on_tile: bool = anchor == TutorialBeatDef.Anchor.TILE and camera != null and not lead
	var away: Vector2 = Vector2.ZERO  # Where the aimed tile or unit stands, when it is out of reach.
	if on_tile:
		away = _tile_screen(aim, camera)
	elif on_unit and not unit.in_field:
		away = unit.point
	if (on_tile and not safe.has_point(away)) or (on_unit and not unit.in_field):
		if (aim.gesture if on_unit else want) == TutorialBeatDef.Gesture.NONE:
			return
		want = TutorialBeatDef.Gesture.DRAG
		off_screen = true
		shiftable = true
		point = away.clamp(safe.position, safe.end)
		var way: Vector2 = (field_of.call() - point) / dp
		if way != Vector2.ZERO:
			vector_dp = way.limit_length(settings.hint_drag_max_dp)
		if on_unit and not _free_start(unit, safe, dp, settings):
			return  # No free point to start on: no hand rather than one that presses a button.
	if not off_screen:
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
				point = _tile_screen(aim, camera)
			TutorialBeatDef.Anchor.UNIT:
				point = unit.point
			_:
				point = field_of.call()
				shiftable = true
	kind = want
	if shiftable:
		bounds = _bounds(want, dp, settings, false, false)
		var shift: Vector2 = _inside(bounds, safe)
		point += shift
		bounds.position += shift
	else:
		_fit_travel(want, safe, dp, settings)
		_fit_hand(want, safe, dp, settings)


## Moves the drag's start (`point`) to the nearest free point of the field, keeping the vector: the
## start itself when it is free, else a point past each side of a button or HUD rect grown by the
## band, each with the hand's box brought into `safe`. A drag that starts on a card button would
## press it, and the map would not pan (plan row P593b-4). What the hint draws at the start must be
## clear too (plan row P593b-5): each candidate lies the drawn hint's reach past the grown rect (the
## press ring's `ring_reach_dp` or the hand's side, the larger, on that side), and one whose ring
## square or hand box meets a button or HUD rect is dropped. False when none is free.
@warning_ignore("integer_division")
func _free_start(unit: GuideUnitAnchor, safe: Rect2, dp: float, settings: GuideSettingsDef) -> bool:
	var home: Vector2 = point
	var best: float = INF
	var pick: Vector2 = Vector2.INF
	var gap: float = START_GAP_DP * dp
	var side: float = settings.hint_size_dp * dp
	var reach: float = GestureHint.ring_reach_dp(settings.hint_size_dp, 1) * dp
	var tip: Vector2 = GestureHint.POINT_TIP
	var left: float = maxf(reach, tip.x * side) + gap  # How far the drawn hint hangs each side.
	var right: float = maxf(reach, (1.0 - tip.x) * side) + gap
	var above: float = maxf(reach, tip.y * side) + gap
	var below: float = maxf(reach, (1.0 - tip.y) * side) + gap
	_edges.clear()
	unit.edge_rects(_edges)
	for turn: int in 1 + _edges.size() * 4:
		var at: Vector2 = home
		if turn > 0:
			var edge: Rect2 = _edges[(turn - 1) / 4]
			match (turn - 1) % 4:
				0:
					at.x = edge.position.x - right
				1:
					at.x = edge.end.x + left
				2:
					at.y = edge.position.y - below
				_:
					at.y = edge.end.y + above
		point = at
		at += _inside(_bounds(TutorialBeatDef.Gesture.DRAG, dp, settings, false, false), safe)
		var away: float = at.distance_squared_to(unit.point)
		var ring: Rect2 = Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
		var hand: Rect2 = Rect2(at - tip * side, Vector2(side, side))
		var free: bool = unit.clear_at(at) and unit.clear_box(ring) and unit.clear_box(hand)
		if away < best and free:
			best = away
			pick = at
	point = pick if pick != Vector2.INF else home
	return pick != Vector2.INF


## The tip stays; a drag or box that would leave the screen turns round, or is cut short.
func _fit_travel(
	want: TutorialBeatDef.Gesture, safe: Rect2, dp: float, settings: GuideSettingsDef
) -> void:
	if want != TutorialBeatDef.Gesture.DRAG and want != TutorialBeatDef.Gesture.BOX:
		return
	var reach: float = GestureHint.ring_reach_dp(settings.hint_size_dp, 1) * dp
	var inner: Rect2 = safe.grow(-reach)
	if inner.has_point(point + vector_dp * dp):
		return
	if inner.has_point(point - vector_dp * dp):
		vector_dp = -vector_dp
		return
	var end: Vector2 = (point + vector_dp * dp).clamp(inner.position, inner.end)
	vector_dp = (end - point) / dp


## The flip of the hand that leaves least of the hint outside `safe`; the box is cut to `safe`.
func _fit_hand(
	want: TutorialBeatDef.Gesture, safe: Rect2, dp: float, settings: GuideSettingsDef
) -> void:
	var best: float = -1.0
	var box: Rect2 = Rect2()
	for turn: int in 4:
		var across: bool = turn & 1 == 1
		var down: bool = turn & 2 == 2
		var seen: Rect2 = _bounds(want, dp, settings, across, down)
		var area: float = seen.intersection(safe).get_area()
		if area > best + 0.01:
			best = area
			box = seen
			flip_x = across
			flip_y = down
	bounds = box.intersection(safe)


## The shift that brings `box` into `safe` (zero when it fits already or `safe` is smaller).
static func _inside(box: Rect2, safe: Rect2) -> Vector2:
	var shift: Vector2 = Vector2.ZERO
	for axis: int in 2:
		var low: float = safe.position[axis] - box.position[axis]
		var high: float = safe.end[axis] - box.end[axis]
		shift[axis] = maxf(low, 0.0) if low > 0.0 else minf(high, 0.0)
	return shift


static func _tile_screen(aim: TutorialLeadInDef, camera: RtsCamera) -> Vector2:
	return camera.world_to_screen(
		IsoProjection.cell_centre_px(aim.anchor_tile.x, aim.anchor_tile.y)
	)


static func _auto(
	beat: TutorialBeatDef, anchor: TutorialBeatDef.Anchor, camera: RtsCamera
) -> TutorialBeatDef.Gesture:
	if anchor == TutorialBeatDef.Anchor.CONTROL or anchor == TutorialBeatDef.Anchor.UNIT:
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


## The box of the hand (hung off the tip by the flips), the press ring and the fingers' travel,
## about `point`, with the margin.
func _bounds(
	want: TutorialBeatDef.Gesture, dp: float, settings: GuideSettingsDef, across: bool, down: bool
) -> Rect2:
	var side: float = settings.hint_size_dp * dp
	var pinch: bool = (
		want == TutorialBeatDef.Gesture.PINCH_OUT or want == TutorialBeatDef.Gesture.PINCH_IN
	)
	var tip: Vector2 = GestureHint.PINCH_TIP if pinch else GestureHint.POINT_TIP
	if across:
		tip.x = 1.0 - tip.x
	if down:
		tip.y = 1.0 - tip.y
	var rings: int = 2 if want == TutorialBeatDef.Gesture.DOUBLE_TAP else 1
	var reach: float = GestureHint.ring_reach_dp(settings.hint_size_dp, rings) * dp
	var box: Rect2 = Rect2(-tip * side, Vector2(side, side))
	box = box.merge(Rect2(Vector2(-reach, -reach), Vector2(reach, reach) * 2.0))
	if pinch:
		var far: Vector2 = GestureHint.PINCH_AXIS * side * GestureHint.SPREAD_FAR_SHARE
		for end: Vector2 in [far, -far]:
			box = box.merge(Rect2(end - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	elif want == TutorialBeatDef.Gesture.DRAG or want == TutorialBeatDef.Gesture.BOX:
		box = box.merge(Rect2(box.position + vector_dp * dp, box.size))
	return Rect2(point + box.position, box.size).grow(settings.hint_margin_dp * dp)
