class_name GhostLayer
extends Node2D
## The placement ghost (plan P86, ADR 0023 section 3, STYLE.md "Ghosts"), drawn at z 60 while
## `placement.active`: the footprint's cells marked as diamonds on the ground, one tile quad per
## cell from the one texture of `GhostMarks`, and the building's sprite faded over them, the atlas
## regions of the placed building (`BuildingLayer`) on the footprint's centre: its body and, for a
## defence, its head at the sheet's mount, facing east as a new building's. The order is the wash,
## the sprite, the hatch (only where it does not fit), the frame and the reason's glyph, so the
## cells that will be blocked read through the sprite. Green with a solid frame fits; red with the
## hatch and the glyph of `Placement.reason` does not: never colour alone. A ghost the sim refused
## (`placement.blocked`, P86b) is red too, with the glyph of the reason, or the occupied one when
## the snapshot still calls it a fit (something rolled onto it), and the word "Blocked" under it.
## The glyph and the word keep their dp size through any zoom, the quads scale with the map. It
## redraws every frame while the mode is on and once more when it ends. What a frame draws is read
## once, in `refresh`, when the placement changes (the cells, the sprite's regions and rise, the
## glyph, the word): a frame only draws.

const Z_GHOST: int = 60
const PART: StringName = BuildingLayer.BODY  ## The sheet part the ghost draws: a building's body.
const HEAD: StringName = BuildingLayer.HEAD  ## And a defence's head, over it.
const FITS: Color = Color("30A46C")
const DANGER: Color = MoveMarkerLayer.DANGER
const SPRITE_ALPHA: float = 0.7
const WASH_ALPHA: float = 0.3
const HATCH_ALPHA: float = 0.8
const GLYPH_DP: float = 32.0
const GLYPH_ART: String = "res://assets/art/svg/icons/glyph_reason_%s.svg"
const BLOCKED_TEXT: String = "Blocked"
const WORD_DP: float = 18.0  ## The word's size, as the HUD numbers (touch-ui-rules: 18 sp).
const WORD_INK: Color = Color(1.0, 1.0, 1.0)
const WORD_EDGE: Color = Color(0.06, 0.08, 0.11)  ## As `PowerNumber`'s outline.
const WORD_EDGE_DP: float = 3.0

@export var runner: MatchRunner
@export var placement: PlacementController
## The sorted world whose atlas the sprite is cut from, shared with the layers of the live
## buildings. Without one the ghost has no sprite.
@export var world_sort: WorldSort

var draws: int = 0  ## Frames drawn, for the tests.
var refreshes: int = 0  ## Times the ghost was read again, for the tests.
var last_marks: int = 0  ## Tile quads (wash, hatch, frame) the last frame drew, for the tests.
var last_glyph: Texture2D = null  ## The glyph the last frame drew, null for none, for the tests.
var last_glyph_px: float = 0.0  ## Its side on the screen, base px, for the tests.
var last_word: String = ""  ## The word the last frame drew, "" for none, for the tests.
var last_word_px: float = 0.0  ## Its font size on the screen, base px, for the tests.
var last_parts: int = 0  ## Sprite regions (body, head) the last frame drew, for the tests.
## The box the last frame drew the head in, world px, empty for none, for the tests.
var last_head: Rect2 = Rect2()

var _marks: RuntimeAtlas = null  ## Made when the first ghost is drawn.
var _was_on: bool = false
var _cells: Array[Vector2i] = []
var _region: Rect2i = Rect2i()  ## The body's region on the atlas; empty without art.
var _rise: float = 0.0
var _sprite_origin: Vector2 = Vector2.ZERO  ## The sprite's origin in its picture, world px.
var _sprite_size: Vector2 = Vector2.ZERO  ## The picture's size, world px.
var _glyph_art: Texture2D = null  ## The glyph of the verdict; null while the ghost fits.
var _head: Rect2i = Rect2i()  ## The head's region on the atlas; empty for a building with none.
var _head_origin: Vector2 = Vector2.ZERO  ## Its top left from the footprint's centre, world px.
var _head_size: Vector2 = Vector2.ZERO
var _word: String = ""  ## "Blocked" while the sim's refusal stands, else "".
var _dp_px: float = 1.0  ## `UiScale.base_px_per_dp()`, read when the window changes.


func _init() -> void:
	z_index = Z_GHOST
	z_as_relative = false


func _ready() -> void:
	get_viewport().size_changed.connect(_read_dp)
	_read_dp()
	if placement != null:
		placement.changed.connect(refresh)


func _process(_delta: float) -> void:
	var on: bool = placement != null and placement.active
	if on or _was_on:
		queue_redraw()
	_was_on = on


## Reads the ghost again (it runs when the placement changes): the cells of the footprint at the
## ghost's tile, the sprite's region, rise and size, and the glyph of the verdict. All empty while
## the mode is off.
func refresh() -> void:
	refreshes += 1
	_cells.clear()
	_region = Rect2i()
	_head = Rect2i()
	_rise = 0.0
	_glyph_art = null
	_word = ""
	if placement == null or not placement.active:
		return
	var origin: Vector2i = placement.origin()
	for row: int in placement.foot.y:
		for col: int in placement.foot.x:
			_cells.append(origin + Vector2i(col, row))
	var sheet: IsoSheetDef = _sheet()
	if sheet != null and not world_sort.atlas.is_empty():
		_read_sprite(sheet)
	if not placement.fits():
		var shown: int = placement.reason
		if shown == Placement.Reason.OK:  # Refused though it fits: something got in the way.
			shown = Placement.Reason.OCCUPIED
		var key: String = String(Placement.Reason.find_key(shown)).to_lower()
		_glyph_art = load(GLYPH_ART % key) as Texture2D
	if placement.blocked:
		_word = BLOCKED_TEXT


## Reads where the body and the head are on the atlas, and the picture's size and rise.
func _read_sprite(sheet: IsoSheetDef) -> void:
	var atlas: IsoAtlas = world_sort.atlas
	var slot: int = world_sort.slot_of(runner.scenario.local_player)
	_region = atlas.region(sheet.art_id, PART, BuildingLayer.NO_FRAME, slot)
	if not _region.has_area():
		return
	var per_px: float = WorldSort.ART_SCALE / atlas.bake_scale()
	_sprite_origin = Vector2(sheet.origin(PART)) * WorldSort.ART_SCALE
	_sprite_size = Vector2(_region.size) * per_px
	_rise = _sprite_origin.y
	if sheet.has_part(HEAD):
		_head = atlas.region(sheet.art_id, HEAD, UnitLayer.D_EAST, slot)
		var mount: Vector2 = sheet.mount(UnitLayer.D_EAST) - Vector2(sheet.origin(HEAD))
		_head_origin = mount * WorldSort.ART_SCALE
		_head_size = Vector2(_head.size) * per_px


## The cells the diamonds mark: the footprint at the ghost's tile, (column, row), none while the
## mode is off.
func cells() -> Array[Vector2i]:
	return _cells


## The colour of the wash and the frame: green where the building fits, danger red where not (or
## where the sim just refused it).
func tint() -> Color:
	return FITS if placement != null and placement.fits() else DANGER


## The atlas region the sprite is cut from, the building's body for the local player; empty for a
## type with no art on the atlas (the ghost is then the marks alone).
func body_region() -> Rect2i:
	return _region


## The atlas region of the head, facing east; empty for a building with none (and for no art).
func head_region() -> Rect2i:
	return _head


## How far the picture rises above the footprint's centre, world px at zoom 1; 0 without a sprite.
func rise_px() -> float:
	return _rise


## The quad of `cell` in world px: its diamond's box, `margin` px wider on each side.
static func quad_rect(cell: Vector2i, margin: int) -> Rect2:
	var reach: Vector2 = Vector2(GhostMarks.TILE) * 0.5 + Vector2.ONE * margin
	return Rect2(IsoProjection.cell_centre_px(cell.x, cell.y) - reach, reach * 2.0)


func _draw() -> void:
	last_marks = 0
	last_parts = 0
	last_head = Rect2()
	last_glyph = null
	last_glyph_px = 0.0
	last_word = ""
	last_word_px = 0.0
	if placement == null or not placement.active:
		return
	draws += 1
	if _marks == null:
		_marks = GhostMarks.build()
	var fits: bool = placement.fits()
	var accent: Color = tint()
	for cell: Vector2i in _cells:
		_tile(cell, GhostMarks.WASH, Color(accent, WASH_ALPHA), 0)
	_sprite()
	if not fits:
		for cell: Vector2i in _cells:
			_tile(cell, GhostMarks.hatch_for(cell), Color(DANGER, HATCH_ALPHA), 0)
	for cell: Vector2i in _cells:
		_tile(cell, GhostMarks.FRAME, accent, GhostMarks.FRAME_MARGIN)
	if not fits:
		_glyph()
	if not _word.is_empty():
		_say_word()


## The quad of `cell` from region `mark` of the marks, `margin` px wider than the tile on each side.
func _tile(cell: Vector2i, mark: StringName, tint: Color, margin: int) -> void:
	var region: Rect2i = _marks.region(mark)
	if not region.has_area():
		return
	last_marks += 1
	draw_texture_rect_region(_marks.texture(), quad_rect(cell, margin), Rect2(region), tint)


## The building's body and, for a defence, its head, faded, with the body's origin on the
## footprint's centre. The two are drawn one over the other at the same alpha, so the body shows
## through the head a little: a group fade would need a CanvasGroup.
func _sprite() -> void:
	if not _region.has_area():
		return
	var ground: Vector2i = placement.centre_ground()
	var centre: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
	var fade: Color = Color(1.0, 1.0, 1.0, SPRITE_ALPHA)
	var texture: Texture2D = world_sort.atlas.texture()
	draw_texture_rect_region(
		texture, Rect2(centre - _sprite_origin, _sprite_size), Rect2(_region), fade
	)
	last_parts = 1
	if _head.has_area():
		last_head = Rect2(centre + _head_origin, _head_size)
		draw_texture_rect_region(texture, last_head, Rect2(_head), fade)
		last_parts = 2


## The reason's glyph over the footprint's centre, danger red, GLYPH_DP across whatever the zoom.
func _glyph() -> void:
	if _glyph_art == null:
		return
	var zoom: float = get_canvas_transform().get_scale().x
	var side: float = GLYPH_DP * _dp_px / zoom
	var ground: Vector2i = placement.centre_ground()
	var at: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y) - Vector2.ONE * side * 0.5
	draw_texture_rect(_glyph_art, Rect2(at, Vector2.ONE * side), false, DANGER)
	last_glyph = _glyph_art
	last_glyph_px = side * zoom


## The word under the glyph, WORD_DP high whatever the zoom: white with a dark edge, so it reads on
## the red hatch.
func _say_word() -> void:
	var font: Font = ThemeDB.fallback_font
	var zoom: float = get_canvas_transform().get_scale().x
	var size: int = roundi(WORD_DP * _dp_px / zoom)
	var width: float = font.get_string_size(_word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var ground: Vector2i = placement.centre_ground()
	var glyph: float = GLYPH_DP * _dp_px / zoom
	var at: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
	at += Vector2(-width * 0.5, glyph * 0.5 + font.get_ascent(size))
	var edge: int = roundi(WORD_EDGE_DP * _dp_px / zoom)
	draw_string_outline(font, at, _word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, edge, WORD_EDGE)
	draw_string(font, at, _word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, WORD_INK)
	last_word = _word
	last_word_px = size * zoom


func _read_dp() -> void:  # dp changes with the window.
	_dp_px = UiScale.base_px_per_dp()


## The sheet of the type being placed, after the atlas is baked for the match; null without one.
func _sheet() -> IsoSheetDef:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or world_sort == null or placement == null or placement.type_index < 0:
		return null
	world_sort.sync()
	return world_sort.sheet(snap.type_ids[placement.type_index])
