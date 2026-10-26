class_name BuildingLayer
extends Node2D
## The base parts of the buildings of the runner's published snapshot (ADR 0022 sections 1, 2 and
## 4, plan P84), at z 2: under the selection rings, the unit bands and the fog. It also owns the
## building list that BuildingRoofLayer draws from, so the two always agree.
##
## A building is a row whose type has a footprint (BuildingGeometry). Its sprite stands on the
## footprint and rises above it: the box is the footprint plus the texture's rise, anchored on the
## footprint's south edge. Each building is cut along the middle line of its footprint (`y_mid`):
## the rows of the picture south of it are the base part, drawn here under every unit layer, the
## rows north of it the roof part, drawn by BuildingRoofLayer over them. The parts are defined by
## `y_mid` alone, not by what the art shows.
##
## Every quad of both parts is a region of one runtime atlas (RuntimeAtlas), built when a match
## starts from the hull, team and turret textures of the building types and the last-seen dot tile,
## so each part draws in one call whatever the mix of types, owners and turret heads. The team
## layer is the quad's colour (`UnitLayer.team_color`), and so is the fog: the base part lies under
## the fog layer, which dims it, and the roof part lies over it and carries its footprint's state
## itself, white where the local player sees any cell of the footprint and the explored dim
## (`1 - explored_alpha / 255` per channel) where it does not.
##
## An enemy building is drawn only where the local player sees a cell of its footprint (own
## buildings always; `reveal_enemies` draws all). The layer reads only `runner.snapshot`. It
## rebuilds its list when the rows change (`rows_version`) and its seen flags when the local
## player's fog version, the local player or the explored alpha changed, and redraws only when
## the drawn set or a colour changed (`plan_version`), never on a frame without a published
## change. `draw_count()` is how often `_draw()` ran, which a test pins.

const ART_DIR: String = "res://assets/art/svg/buildings/"
const GHOST_SEEN_ART: String = "res://assets/art/svg/ui/ghost_seen.svg"
const GHOST_SEEN: StringName = &"ghost_seen"  ## Its region in the atlas (P84c draws the dots).
const HULL: int = 0  ## The layers of a building, in drawing order; also its file suffixes.
const TEAM: int = 1
const TURRET: int = 2
const LAYER_FILES: Array[String] = ["hull", "team", "turret"]
const ORDER_SHIFT: int = 16  ## A roof sort key is the south row shifted up, plus the list index.
const ORDER_MASK: int = 0xFFFF

@export var runner: MatchRunner
## Gives the team colours (`team_color`), so one export holds the palette.
@export var unit_layer: UnitLayer
## Gives the explored alpha the roof's dim follows.
@export var fog_layer: FogLayer
## Draws every enemy building whatever the fog says: the perf arena, tests that are not about fog.
@export var reveal_enemies: bool = false
## How fast a turret head turns, in radians per second (the unit layer's turret rate).
@export var turn_rate: float = 12.0

var _serial: int = -1  ## match_serial of the atlas and the list.
var _rows_version: int = -1
var _fog_version: int = -1  ## version_of(local player) the flags were read at, -1 for no grid.
var _player: int = 0
var _shade: int = -1  ## The explored alpha the dim is made of.
var _revealed: bool = false
var _dim: Color = Color.WHITE
var _version: int = 0  ## Moves when the drawn set or a colour changes.
var _drawn_version: int = 0
var _draws: int = 0
var _quads: int = 0
## What the last `paint` drew, base parts and roof parts, as `b * 4 + layer` in drawing order, in
## arrays sized with the list (at most three quads a building); `painted` reads them back.
var _painted_base: PackedInt32Array = PackedInt32Array()
var _painted_roof: PackedInt32Array = PackedInt32Array()
var _base_count: int = 0
var _roof_count: int = 0
var _atlas: RuntimeAtlas = null
## Per type of the snapshot, at 3 x type + layer: the atlas rect of its hull, team and turret
## layers, empty for a layer the type has no art for (a type with no hull art is not drawn).
var _type_rects: Array[Rect2] = []
## Per building `b`, in ascending row (and id) order: the snapshot row, the unit id, the type and
## owner, the sprite box, the cut (px from the top of the box to the middle line), the footprint
## (column, row, width and height in tiles, four ints), the flags and the turret head's angle.
var _rows: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _types: PackedInt32Array = PackedInt32Array()
var _owners: PackedInt32Array = PackedInt32Array()
var _boxes: Array[Rect2] = []
var _cuts: PackedFloat32Array = PackedFloat32Array()
var _foot: PackedInt32Array = PackedInt32Array()
var _shown: PackedByteArray = PackedByteArray()  ## 1: drawn.
var _seen: PackedByteArray = PackedByteArray()  ## 1: a cell of the footprint is visible.
var _head_angle: PackedFloat64Array = PackedFloat64Array()
var _heads: PackedInt32Array = PackedInt32Array()  ## The buildings with a turret head.
var _roof_order: PackedInt32Array = PackedInt32Array()  ## Buildings by ascending south row.


func _process(_delta: float) -> void:
	sync()
	if _version != _drawn_version:
		_drawn_version = _version
		queue_redraw()


func _draw() -> void:
	_draws += 1
	_quads = paint(self, false)


## Brings the atlas, the list and the flags up to `runner.snapshot`. A second call in a frame, and
## the one BuildingRoofLayer makes, finds nothing to do.
func sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	var player: int = FogLayer.local_player_of(runner)
	var shade: int = clampi(
		fog_layer.explored_alpha if fog_layer != null else FogLayer.DEFAULT_EXPLORED_ALPHA, 0, 255
	)
	var fog_version: int = snap.fog.version_of(player) if FogLayer.covers(snap.fog, player) else -1
	var new_match: bool = snap.match_serial != _serial
	var rows_changed: bool = new_match or snap.rows_version != _rows_version
	if new_match:
		_serial = snap.match_serial
		_ids.clear()
		_build_atlas(snap)
	if rows_changed:
		_rows_version = snap.rows_version
		_rebuild_rows(snap)
	var dimmed: bool = shade != _shade or reveal_enemies != _revealed
	if not (rows_changed or dimmed or player != _player or fog_version != _fog_version):
		return
	_player = player
	_shade = shade
	_revealed = reveal_enemies
	_fog_version = fog_version
	_dim = Color(1.0 - shade / 255.0, 1.0 - shade / 255.0, 1.0 - shade / 255.0)
	if _refresh_flags(snap, player) or rows_changed or dimmed:
		_version += 1


## Turns the turret heads toward their targets as the unit layer turns its turrets: the bearing
## from the building to its target as drawn now, at `turn_rate` rad/s, and a head with no target
## keeps its angle. Returns whether any head turned this frame, so the roof list is redrawn for
## it. Allocates nothing.
func turn_heads(delta: float) -> bool:
	sync()
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or _heads.is_empty():
		return false
	var alpha: float = runner.alpha()
	var step: float = turn_rate * delta
	var turned: bool = false
	for b: int in _heads:
		var row: int = _rows[b]
		var target: int = snap.target_row[row]
		if target < 0 or _shown[b] == 0:
			continue
		var want: float = atan2(
			lerpf(snap.prev_pos_y[target], snap.pos_y[target], alpha) - snap.pos_y[row],
			lerpf(snap.prev_pos_x[target], snap.pos_x[target], alpha) - snap.pos_x[row]
		)
		if _head_angle[b] == want:
			continue
		var turn: float = angle_difference(_head_angle[b], want)
		_head_angle[b] = want if absf(turn) <= step else _head_angle[b] + signf(turn) * step
		turned = true
	return turned


## Draws the base parts (`roof` false) or the roof parts, each followed by its turret head, of the
## shown buildings onto `canvas`, which must be inside its `_draw()`. Every quad is a region of the
## one atlas, hull then team, the roof parts in ascending south row. Returns the quads drawn.
func paint(canvas: CanvasItem, roof: bool) -> int:
	if _atlas == null or _atlas.texture() == null:
		return 0
	var texture: ImageTexture = _atlas.texture()
	var log: PackedInt32Array = _painted_roof if roof else _painted_base
	var quads: int = 0
	for index: int in _rows.size():
		var b: int = _roof_order[index] if roof else index
		if _shown[b] == 0:
			continue
		var dst: Rect2 = part_dst(b, roof)
		for layer: int in TURRET:
			if _type_rects[_types[b] * 3 + layer].has_area():
				canvas.draw_texture_rect_region(
					texture, dst, part_src(b, layer, roof), part_color(b, layer, roof)
				)
				log[quads] = b * 4 + layer
				quads += 1
		var head: Rect2 = _type_rects[_types[b] * 3 + TURRET]
		if roof and head.has_area():
			canvas.draw_set_transform(head_pivot(b), _head_angle[b], Vector2.ONE)
			var half: float = head.size.x / 2.0
			canvas.draw_texture_rect_region(
				texture,
				Rect2(-half, -half, head.size.x, head.size.y),
				head,
				part_color(b, HULL, true)
			)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			log[quads] = b * 4 + TURRET
			quads += 1
	if roof:
		_roof_count = quads
	else:
		_base_count = quads
	return quads


## Moves whenever the drawn set or a colour changed; the layers redraw when it does.
func plan_version() -> int:
	return _version


func atlas() -> RuntimeAtlas:
	return _atlas


## Buildings in the list, shown or not, and the snapshot row, the list index of a row (-1 for a row
## that is no drawable building) and whether the building is drawn now.
func building_count() -> int:
	return _rows.size()


func building_row(b: int) -> int:
	return _rows[b]


func building_of(row: int) -> int:
	return _rows.find(row)


func is_shown(b: int) -> bool:
	return _shown[b] == 1


## The buildings by ascending footprint south row, the order of the roof parts and their heads.
func roof_order() -> PackedInt32Array:
	return _roof_order


## The sprite box of building `b` in world px: the footprint plus the rise.
func sprite_box(b: int) -> Rect2:
	return _boxes[b]


## Where part `roof` (true) or the base part is drawn, in world px: the rows of the box north of
## the middle line, or south of it.
func part_dst(b: int, roof: bool) -> Rect2:
	var box: Rect2 = _boxes[b]
	if roof:
		return Rect2(box.position, Vector2(box.size.x, _cuts[b]))
	return Rect2(box.position.x, box.position.y + _cuts[b], box.size.x, box.size.y - _cuts[b])


## The region of the atlas that layer `layer` (HULL or TEAM) of part `roof` shows: the layer's
## region cut at the same line, so one texel is one world px.
func part_src(b: int, layer: int, roof: bool) -> Rect2:
	var region: Rect2 = _type_rects[_types[b] * 3 + layer]
	if roof:
		return Rect2(region.position, Vector2(region.size.x, _cuts[b]))
	return Rect2(
		region.position.x, region.position.y + _cuts[b], region.size.x, region.size.y - _cuts[b]
	)


## The colour of a quad: white for a hull and the owner's colour for the team layer, times the
## explored dim on a roof part whose footprint the local player does not see.
func part_color(b: int, layer: int, roof: bool) -> Color:
	var tint: Color = Color.WHITE
	if layer == TEAM and unit_layer != null:
		tint = unit_layer.team_color(_owners[b])
	if roof and _seen[b] == 0:
		tint *= _dim
	return tint


## The turret head's pivot in world px: the footprint's centre lifted by the rise, which is
## `tex_w / 2` below the top of the box, and its angle (east is 0).
func head_pivot(b: int) -> Vector2:
	var box: Rect2 = _boxes[b]
	return box.position + Vector2(box.size.x, box.size.x) / 2.0


func head_angle(b: int) -> float:
	return _head_angle[b]


## `_draw()` runs so far; a frame without a change must not add one.
func draw_count() -> int:
	return _draws


## Quads the last `_draw()` painted.
func drawn_quads() -> int:
	return _quads


## The quads the last paint of the base parts (`roof` false) or the roof parts drew, in order, each
## as `building * 4 + layer` (HULL, TEAM or TURRET for a head).
func painted(roof: bool) -> PackedInt32Array:
	var log: PackedInt32Array = _painted_roof if roof else _painted_base
	return log.slice(0, _roof_count if roof else _base_count)


## The atlas of this match: the hull, team and turret textures of every building type with art and
## the last-seen dot tile, and the rects of each type's layers in it. None without a building type.
func _build_atlas(snap: MatchSnapshot) -> void:
	_atlas = null
	_type_rects.clear()
	var sources: Dictionary[StringName, Texture2D] = {}
	for type: int in snap.type_ids.size():
		if not BuildingGeometry.is_building(snap, type):
			continue
		for layer: int in LAYER_FILES.size():
			var path: String = "%s%s_%s.svg" % [ART_DIR, snap.type_ids[type], LAYER_FILES[layer]]
			if ResourceLoader.exists(path):
				sources[_key(snap.type_ids[type], layer)] = load(path)
	if sources.is_empty():
		return
	if ResourceLoader.exists(GHOST_SEEN_ART):
		sources[GHOST_SEEN] = load(GHOST_SEEN_ART)
	_atlas = RuntimeAtlas.build(sources)
	for type: int in snap.type_ids.size():
		for layer: int in LAYER_FILES.size():
			_type_rects.append(Rect2(_atlas.region(_key(snap.type_ids[type], layer))))


static func _key(type_id: StringName, layer: int) -> StringName:
	return StringName("%s_%s" % [type_id, LAYER_FILES[layer]])


## The list of drawable buildings of `snap` (a building type with hull art), their boxes, cuts and
## footprints, the roof order and the heads. A building that was in the list keeps its head angle.
func _rebuild_rows(snap: MatchSnapshot) -> void:
	var old_ids: PackedInt32Array = _ids.duplicate()
	var old_angle: PackedFloat64Array = _head_angle.duplicate()
	_rows.clear()
	_ids.clear()
	_types.clear()
	_owners.clear()
	_boxes.clear()
	_cuts.clear()
	_foot.clear()
	_head_angle.clear()
	_heads.clear()
	var keys: PackedInt32Array = PackedInt32Array()
	if _atlas != null:
		for row: int in snap.unit_id.size():
			var type: int = snap.type_index[row]
			if not BuildingGeometry.is_building(snap, type):
				continue
			var hull: Rect2 = _type_rects[type * 3 + HULL]
			if not hull.has_area():
				continue
			var b: int = _rows.size()
			var foot: Vector2i = BuildingGeometry.footprint(snap, type)
			var origin: Vector2i = BuildingGeometry.origin_tile(snap, row)
			var box: Rect2 = BuildingGeometry.sprite_box(origin, foot, hull.size.y)
			_rows.append(row)
			_ids.append(snap.unit_id[row])
			_types.append(type)
			_owners.append(snap.owner[row])
			_boxes.append(box)
			_cuts.append(BuildingGeometry.middle_line(origin, foot) - box.position.y)
			_foot.append_array([origin.x, origin.y, foot.x, foot.y])
			var at: int = old_ids.bsearch(snap.unit_id[row])
			var kept: bool = at < old_ids.size() and old_ids[at] == snap.unit_id[row]
			_head_angle.append(old_angle[at] if kept else 0.0)
			if _type_rects[type * 3 + TURRET].has_area():
				_heads.append(b)
			keys.append(((origin.y + foot.y) << ORDER_SHIFT) | b)
	keys.sort()
	_roof_order.resize(keys.size())
	for index: int in keys.size():
		_roof_order[index] = keys[index] & ORDER_MASK
	_shown.resize(_rows.size())
	_seen.resize(_rows.size())
	_painted_base.resize(_rows.size() * 3)
	_painted_roof.resize(_rows.size() * 3)


## Reads each building's flags from the local player's fog and returns whether any changed. A
## building is seen when a cell of its footprint is visible; an own building is always shown and an
## enemy one when seen. `reveal_enemies` and a player the fog has no grid for see everything.
func _refresh_flags(snap: MatchSnapshot, player: int) -> bool:
	var fog: FogGrid = snap.fog
	var fogged: bool = not reveal_enemies and FogLayer.covers(fog, player)
	var changed: bool = false
	for b: int in _rows.size():
		var seen: int = 1
		if fogged:
			seen = 1 if _footprint_seen(fog, player, b) else 0
		var shown: int = 1 if seen == 1 or not fogged or _owners[b] == player else 0
		if shown != _shown[b] or seen != _seen[b]:
			changed = true
			_shown[b] = shown
			_seen[b] = seen
	return changed


func _footprint_seen(fog: FogGrid, player: int, b: int) -> bool:
	var at: int = b * 4
	var cells: PackedInt32Array = fog.visible
	for line: int in _foot[at + 3]:
		var first: int = (player - 1) * fog.cells + (_foot[at + 1] + line) * fog.cols + _foot[at]
		for column: int in _foot[at + 2]:
			if cells[first + column] > 0:
				return true
	return false
