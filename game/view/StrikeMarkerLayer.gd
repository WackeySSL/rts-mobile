class_name StrikeMarkerLayer
extends Node2D
## What the strike puts on the ground (plan P112, ADR 0023 section 10), at z 65 between the rally
## flags and the order marks. It draws from the published snapshot and `aim`, and only while there
## is something to draw.
## The aim: the strike's circle round the placed point, a 2:1 ellipse flat on the ground
## (`IsoProjection.ellipse_px`), amber with a faint fill.
## The warning: for every player whose rupture is in the air (`strike_tick` above 0) a red circle
## of the rupture's radius at its point, a white ring closing in on the point as the landing comes
## and a warning triangle that blinks, until the snapshot shows the strike gone. Everyone sees it,
## the fog does not hide it (ADR 0023 section 10). The radius is that of the first strike type of
## kind RUPTURE, as `Strike.rupture_type` reads it; the closing ring starts from the time left when
## the warning was first drawn (`_first`), since the snapshot carries no delay.
## Strokes and the triangle keep their size in dp through any zoom; the circles scale with the map.

const Z_STRIKE: int = 65
const STROKE_DP: float = 3.0
const TRIANGLE_DP: float = 16.0
const BLINK_TICKS: float = 4.0  ## One blink, on and off.
const FILL_ALPHA: float = 0.14
const POINTS: int = 48

@export var runner: MatchRunner
@export var aim: StrikeAim

var draws: int = 0  ## Frames drawn, for the tests.

var _unit: PackedVector2Array = PackedVector2Array()  ## The unit circle, closed.
var _ring: PackedVector2Array = PackedVector2Array()  ## A ring's points, reused.
var _first: Dictionary[int, float] = {}  ## A landing tick -> the ticks left when first drawn.
var _drawing: bool = false  ## The last frame drew something.


func _init() -> void:
	z_index = Z_STRIKE
	z_as_relative = false
	for step: int in POINTS + 1:
		_unit.append(Vector2.from_angle(TAU * step / POINTS))
	_ring.resize(POINTS + 1)


## Redraws while there is anything to show, and once more when the last of it goes.
func _process(_delta: float) -> void:
	var any: bool = aim != null and aim.active and aim.has_point
	for landing: int in _landings():
		any = any or landing != 0
	if not any:
		_first.clear()
	if any or _drawing:
		queue_redraw()
	_drawing = any


func _draw() -> void:
	if runner == null or runner.snapshot == null:
		return
	draws += 1
	var unit: float = UiScale.base_px_per_dp() / get_canvas_transform().get_scale().x
	if aim != null and aim.active and aim.has_point:
		_zone(IsoProjection.ground_to_px(aim.point.x, aim.point.y), aim.radius, true, unit)
	var snap: MatchSnapshot = runner.snapshot
	var landings: PackedInt32Array = snap.strike_tick  # Aliased once: no property read per row.
	var xs: PackedInt32Array = snap.strike_x
	var ys: PackedInt32Array = snap.strike_y
	var now: float = snap.tick + runner.alpha()
	var radius: int = StrikeLandings.rupture_radius(snap)  # The first rupture type's.
	for player: int in landings.size():
		var landing: int = landings[player]
		if landing == 0:
			continue
		var at: Vector2 = IsoProjection.ground_to_px(xs[player], ys[player])
		var left: float = float(landing) - now
		var first: float = _first.get_or_add(landing, left)
		_zone(at, radius, false, unit)
		_stroke(at, closing_radius(radius, left, first), Color.WHITE, STROKE_DP * 0.6 * unit)
		if blinks_on(left):
			_triangle(at, unit)


## The closing ring's radius `left` ticks before the landing when `first` were left at the first
## sight: the whole radius then, none at the landing.
static func closing_radius(radius: int, left: float, first: float) -> int:
	return roundi(radius * clampf(left / maxf(first, 1.0), 0.0, 1.0))


## Whether the warning triangle shows `left` ticks before the landing: the first half of each blink.
static func blinks_on(left: float) -> bool:
	return fmod(left, BLINK_TICKS) < BLINK_TICKS * 0.5


## The pending landing ticks of the published snapshot, one per player (none without a snapshot).
func _landings() -> PackedInt32Array:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	return PackedInt32Array() if snap == null else snap.strike_tick


## The ground circle of `radius` milli-tiles at `at`: the faint fill, then the outlined stroke,
## amber for the aim and red for a warning.
func _zone(at: Vector2, radius: int, aiming: bool, unit: float) -> void:
	var color: Color = MoveMarkerLayer.WARNING if aiming else MoveMarkerLayer.DANGER
	draw_set_transform(at, 0.0, Vector2(1.0, IsoProjection.GROUND_FLATTEN))
	draw_circle(Vector2.ZERO, IsoProjection.ellipse_px(radius).x, Color(color, FILL_ALPHA))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_stroke(at, radius, color, STROKE_DP * unit)


## Fills `_ring` with the ground circle of `radius` milli-tiles round `at`, as a 2:1 ellipse.
func _trace(at: Vector2, radius: int) -> void:
	var semi: Vector2 = IsoProjection.ellipse_px(radius)
	for step: int in _unit.size():
		_ring[step] = at + _unit[step] * semi


## An ellipse outline with the dark pass under it.
func _stroke(at: Vector2, radius: int, color: Color, width: float) -> void:
	_trace(at, radius)
	draw_polyline(_ring, FeedbackStyle.OUTLINE, width + FeedbackStyle.OUTLINE_DP * 2.0, true)
	draw_polyline(_ring, color, width, true)


## The warning triangle with its bar and dot, upright on the screen over the point.
func _triangle(at: Vector2, unit: float) -> void:
	var half: float = TRIANGLE_DP * unit
	var top: Vector2 = at + Vector2(0.0, -half)
	var corners: PackedVector2Array = [
		top, at + Vector2(half, half), at + Vector2(-half, half), top
	]
	draw_polyline(corners, FeedbackStyle.OUTLINE, (STROKE_DP + 2.0) * unit, true)
	draw_polyline(corners, MoveMarkerLayer.DANGER, STROKE_DP * unit, true)
	var stem: Vector2 = Vector2(0.0, half * 0.35)
	draw_line(at - stem, at + stem * 0.8, MoveMarkerLayer.DANGER, STROKE_DP * unit)
	draw_circle(at + Vector2(0.0, half * 0.6), STROKE_DP * 0.6 * unit, MoveMarkerLayer.DANGER)
