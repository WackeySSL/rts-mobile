class_name GhostLayer
extends Node2D
## The placement ghost (plan P86, ADR 0023 section 3, STYLE.md "Ghosts"), drawn at z 60 while
## `placement.active`: the footprint's cells marked as diamonds on the ground, one tile quad per
## cell from the one texture of `GhostMarks`, and the building's sprite faded over them, the atlas
## region of the placed building (`BuildingLayer`) on the footprint's centre. The order is the wash,
## the sprite, the hatch (only where it does not fit), the frame and the reason's glyph, so the
## cells that will be blocked read through the sprite. Green with a solid frame fits; red with the
## hatch and the glyph of `Placement.reason` does not: never colour alone. The glyph keeps its dp
## size through any zoom, the quads scale with the map. It redraws every frame while the mode is
## on and once more when it ends.

const Z_GHOST: int = 60
const PART: StringName = BuildingLayer.BODY  ## The sheet part the ghost draws: a building's body.
const FITS: Color = Color("30A46C")
const DANGER: Color = MoveMarkerLayer.DANGER
const SPRITE_ALPHA: float = 0.7
const WASH_ALPHA: float = 0.3
const HATCH_ALPHA: float = 0.8
const GLYPH_DP: float = 32.0
const GLYPH_ART: String = "res://assets/art/svg/icons/glyph_reason_%s.svg"

@export var runner: MatchRunner
@export var placement: PlacementController
## The sorted world whose atlas the sprite is cut from, shared with the layers of the live
## buildings. Without one the ghost has no sprite.
@export var world_sort: WorldSort

var draws: int = 0  ## Frames drawn, for the tests.

var _marks: RuntimeAtlas = null  ## Made when the first ghost is drawn.
var _was_on: bool = false


func _init() -> void:
	z_index = Z_GHOST
	z_as_relative = false


func _process(_delta: float) -> void:
	var on: bool = placement != null and placement.active
	if on or _was_on:
		queue_redraw()
	_was_on = on


## The cells the diamonds mark: the footprint at the ghost's tile, (column, row), none while the
## mode is off.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if placement == null or not placement.active:
		return out
	var origin: Vector2i = placement.origin()
	for row: int in placement.foot.y:
		for col: int in placement.foot.x:
			out.append(origin + Vector2i(col, row))
	return out


## The colour of the wash and the frame: green where the building fits, danger red where not.
func tint() -> Color:
	return FITS if placement != null and placement.reason == Placement.Reason.OK else DANGER


## The atlas region the sprite is cut from, the building's body for the local player; empty for a
## type with no art on the atlas (the ghost is then the marks alone).
func body_region() -> Rect2i:
	var sheet: IsoSheetDef = _sheet()
	if sheet == null or world_sort.atlas.is_empty():
		return Rect2i()
	var owner_id: int = runner.scenario.local_player
	var slot: int = world_sort.slot_of(owner_id)
	return world_sort.atlas.region(sheet.art_id, PART, BuildingLayer.NO_FRAME, slot)


## How far the picture rises above the footprint's centre, world px at zoom 1; 0 without a sprite.
func rise_px() -> float:
	var sheet: IsoSheetDef = _sheet()
	if sheet == null or not body_region().has_area():
		return 0.0
	return sheet.origin(PART).y * WorldSort.ART_SCALE


func _draw() -> void:
	if placement == null or not placement.active:
		return
	draws += 1
	if _marks == null:
		_marks = GhostMarks.build()
	var fits: bool = placement.reason == Placement.Reason.OK
	var accent: Color = tint()
	var mine: Array[Vector2i] = cells()
	for cell: Vector2i in mine:
		_tile(cell, GhostMarks.WASH, Color(accent, WASH_ALPHA), 0)
	_sprite()
	if not fits:
		for cell: Vector2i in mine:
			_tile(cell, GhostMarks.HATCH, Color(DANGER, HATCH_ALPHA), 0)
	for cell: Vector2i in mine:
		_tile(cell, GhostMarks.FRAME, accent, GhostMarks.FRAME_MARGIN)
	if not fits:
		_glyph()


## The quad of `cell` from region `mark` of the marks, `margin` px wider than the tile on each side.
func _tile(cell: Vector2i, mark: StringName, tint: Color, margin: int) -> void:
	var region: Rect2i = _marks.region(mark)
	if not region.has_area():
		return
	var reach: Vector2 = Vector2(GhostMarks.TILE) * 0.5 + Vector2.ONE * margin
	var at: Vector2 = IsoProjection.cell_centre_px(cell.x, cell.y)
	draw_texture_rect_region(_marks.texture(), Rect2(at - reach, reach * 2.0), Rect2(region), tint)


## The building's body, faded, with its origin on the footprint's centre.
func _sprite() -> void:
	var region: Rect2i = body_region()
	if not region.has_area():
		return
	var ground: Vector2i = placement.centre_ground()
	var origin: Vector2 = Vector2(_sheet().origin(PART)) * WorldSort.ART_SCALE
	var size: Vector2 = Vector2(region.size) * (WorldSort.ART_SCALE / world_sort.atlas.bake_scale())
	var top_left: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y) - origin
	draw_texture_rect_region(
		world_sort.atlas.texture(),
		Rect2(top_left, size),
		Rect2(region),
		Color(1.0, 1.0, 1.0, SPRITE_ALPHA)
	)


## The reason's glyph over the footprint's centre, danger red, GLYPH_DP across whatever the zoom.
func _glyph() -> void:
	var key: String = String(Placement.Reason.find_key(placement.reason)).to_lower()
	var glyph: Texture2D = load(GLYPH_ART % key) as Texture2D
	var side: float = GLYPH_DP * UiScale.base_px_per_dp() / get_canvas_transform().get_scale().x
	var ground: Vector2i = placement.centre_ground()
	var at: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y) - Vector2.ONE * side * 0.5
	draw_texture_rect(glyph, Rect2(at, Vector2.ONE * side), false, DANGER)


## The sheet of the type being placed, after the atlas is baked for the match; null without one.
func _sheet() -> IsoSheetDef:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or world_sort == null or placement == null or placement.type_index < 0:
		return null
	world_sort.sync()
	return world_sort.sheet(snap.type_ids[placement.type_index])
