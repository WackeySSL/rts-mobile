class_name CarryMarkLayer
extends Node2D
## What the Board and Unload aims put on the map (P265), at z 65 with the strike's marks.
## Unload: the
## chevron (`glyph_unload_mark`, tinted amber at run time) standing on the ground point. Board: a
## ring round the ringed carrier's ground point. Each keeps its size in dp through any zoom, and
## the layer redraws only while an aim shows something and once more when it goes.

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

var draws: int = 0  ## Frames drawn, for the tests.

var _drawing: bool = false


func _init() -> void:
	z_index = Z_CARRY
	z_as_relative = false


func _process(_delta: float) -> void:
	var any: bool = aim != null and aim.can_confirm()
	if any or _drawing:
		queue_redraw()
	_drawing = any


func _draw() -> void:
	if aim == null or runner == null or runner.snapshot == null or not aim.can_confirm():
		return
	draws += 1
	var unit: float = UiScale.base_px_per_dp() / get_canvas_transform().get_scale().x
	if aim.mode == CarryAim.Mode.UNLOAD:
		var at: Vector2 = IsoProjection.ground_to_px(aim.point.x, aim.point.y)
		var side: float = MARK_DP * unit
		# The lower chevron's tip is the point (the glyph's anchor): the plate stands above it.
		var box: Rect2 = Rect2(at - MARK_ANCHOR * side, Vector2.ONE * side)
		draw_texture_rect(ART, box, false, TINT)
		return
	var row: int = runner.snapshot.index_of(aim.carrier_id)
	if row < 0:
		return
	var snap: MatchSnapshot = runner.snapshot
	var centre: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
	var ring: PackedVector2Array = PackedVector2Array()
	var half: Vector2 = Vector2(RING_DP, RING_DP * 0.5) * unit
	for step: int in POINTS + 1:
		ring.append(centre + Vector2.from_angle(TAU * step / POINTS) * half)
	draw_polyline(ring, TINT, STROKE_DP * unit)
