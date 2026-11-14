class_name CarryMarkLayer
extends Node2D
## What the Board and Unload aims put on the map (P265b), at z 65 with the strike's marks.
## Unload: the chevron (`glyph_unload_mark`, tinted amber at run time) with the tip of its lower
## chevron on the ground point. Board: a ring round the ringed carrier, at its drawn place (its
## rig, `unit_layer`; the snapshot's ground point where it has none). Each keeps its size in dp
## through any zoom, and the layer redraws only while an aim shows something and once more when it
## goes. The unit circle is made once and the ring's points reuse one buffer (`StrikeMarkerLayer`).

const Z_CARRY: int = 65
const ART: Texture2D = preload("res://assets/art/svg/icons/glyph_unload_mark.svg")
const TINT: Color = Color("F5A524")
const MARK_DP: float = 40.0
const MARK_ANCHOR: Vector2 = Vector2(64.0, 102.0) / 128.0  ## The lower chevron's tip, of the glyph.
const RING_DP: float = 28.0
const STROKE_DP: float = 3.0
const POINTS: int = 32

@export var runner: MatchRunner
@export var aim: CarryAim
@export var unit_layer: UnitLayer  ## The carrier's drawn place; without it the snapshot's point.

var draws: int = 0  ## Frames drawn, for the tests.

var _unit: PackedVector2Array = PackedVector2Array()  ## The unit circle, closed.
var _ring: PackedVector2Array = PackedVector2Array()  ## A ring's points, reused.
var _drawing: bool = false  ## The last frame drew something.


func _init() -> void:
	z_index = Z_CARRY
	z_as_relative = false
	for step: int in POINTS + 1:
		_unit.append(Vector2.from_angle(TAU * step / POINTS))
	_ring.resize(POINTS + 1)


## What the aim shows: 0 nothing (no aim, no ring or point yet), 1 the chevron or the ring.
func marks() -> int:
	return 1 if aim != null and aim.can_confirm() else 0


## The chevron's box for ground point `at` (world px) with `unit` world px to the dp: its anchor,
## the lower chevron's tip, lies on `at`.
static func chevron_rect(at: Vector2, unit: float) -> Rect2:
	var side: float = MARK_DP * unit
	return Rect2(at - MARK_ANCHOR * side, Vector2.ONE * side)


## Where the Board ring is centred, in this node's coordinates: the carrier's rig, else its
## snapshot point; Vector2.INF when no carrier is ringed.
func ring_centre() -> Vector2:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var row: int = -1 if snap == null or aim == null else snap.index_of(aim.carrier_id)
	if row < 0 or aim.mode != CarryAim.Mode.BOARD:
		return Vector2.INF
	if unit_layer != null and unit_layer.rig(row) != null:
		return to_local(unit_layer.rig(row).global_position)
	return IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


func _process(_delta: float) -> void:
	var any: bool = marks() > 0
	if any or _drawing:
		queue_redraw()
	_drawing = any


func _draw() -> void:
	if marks() == 0 or runner == null or runner.snapshot == null:
		return
	draws += 1
	var unit: float = UiScale.base_px_per_dp() / get_canvas_transform().get_scale().x
	if aim.mode == CarryAim.Mode.UNLOAD:
		var at: Vector2 = IsoProjection.ground_to_px(aim.point.x, aim.point.y)
		draw_texture_rect(ART, chevron_rect(at, unit), false, TINT)
		return
	var centre: Vector2 = ring_centre()
	if centre == Vector2.INF:
		return
	var half: Vector2 = Vector2(RING_DP, RING_DP * 0.5) * unit
	for step: int in POINTS + 1:
		_ring[step] = centre + _unit[step] * half
	draw_polyline(_ring, TINT, STROKE_DP * unit)
