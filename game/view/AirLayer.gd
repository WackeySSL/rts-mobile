class_name AirLayer
extends Node2D
## The aircraft (ADR 0036 section 15, plan P243): one node at absolute z 20, above the sorted world
## (10) and under `AirFx` (25) and the bars (30), whose children the engine sorts by their ground
## y (`y_sort_enabled`), high air and low air together. A flyer's rig stands at its projected
## ground point; its Hull is drawn `fly_px` (a low flyer `low_fly_px`) of its sheet above it, its
## Shadow stays on the ground at z 2, under the rings (3) and the fog (4). Both are regions of the
## atlas's second page (`IsoAtlas.page_of`: a flyer's whole sheet is unsorted), so the hulls are one
## draw call and the shadows another: the +2 of the forecast (`test_air_layer_batch.gd`).
## `UnitLayer` has no rig for a flyer (`WorldSort.is_rigless`); everything about one is here.
## Rules, all view only (rule 1): the sim never reads any of it, and range, sight and a tap use
## the ground point.
## - An own flyer is always drawn, an enemy one only where the local player sees its tile (the tile
##   of its position in the tick, `snapshot.cell_of`) or `reveal_enemies` is set.
## - A flyer hovers (the bob is P243b's) and turns to the direction it moves in, one frame step at a
##   time, and keeps its heading while it hovers.
## - A flyer that dies is gone at once, as a ground unit is: `EffectsLayer` bursts at its DIED point
##   (the fall and the burst at the landing are P243b's).
## - A flyer whose type has no art (P245 draws it) stands in as the `UnitLayer.Marker` ellipse.
## Rigs are pooled; a frame sets properties only.

const Z_AIR: int = 20
const HULL: StringName = &"hull"
const SHADOW: StringName = &"shadow"
const NO_FRAME: int = -1
## What stands in for a sheet's `fly_px` and `low_fly_px`: a type with no art, or a sheet of 0.
const DEFAULT_FLY_PX: float = 28.0
const DEFAULT_LOW_FLY_PX: float = 12.0

@export var runner: MatchRunner
@export var world_sort: WorldSort
@export var reveal_enemies: bool = false
@export var turn_rate: float = 12.0  ## Radians a second a hull turns, as `UnitLayer`'s.

var _serial: int = -1
var _rows_version: int = -1
var _by_id: Dictionary[int, Rig] = {}  ## The rigs of the rows, by unit id.
var _rows: PackedInt32Array = PackedInt32Array()  ## The snapshot rows that are flyers, ascending.
var _rigs: Array[Rig] = []  ## The rig of `_rows[i]`.
var _pool: Array[Rig] = []
var _pool_root: Node2D = null
var _made: int = 0


## A flyer's rig. `hull` and `shadow` are null-free (a rig with no art hides both and shows the
## `marker`).
class Rig:
	extends Node2D

	var id: int = 0
	var owner_id: int = 0
	var sheet: IsoSheetDef = null
	var hull: Sprite2D = null
	var shadow: Sprite2D = null
	var marker: UnitLayer.Marker = null
	var views: int = 16  ## The hull's frames in a full turn.
	var frame: int = NO_FRAME
	var lift: float = 0.0  ## The height of the hover, world px at zoom 1.
	var heading: float = 0.0
	var aim: float = 0.0


func _init() -> void:
	y_sort_enabled = true
	z_index = Z_AIR
	z_as_relative = false


func _ready() -> void:
	if world_sort == null:
		world_sort = WorldSort.new()
		world_sort.runner = runner
		add_child(world_sort)
	_pool_root = Node2D.new()
	_pool_root.name = "Pool"
	_pool_root.visible = false
	add_child(_pool_root)
	_sync()


func _process(delta: float) -> void:
	var snap: MatchSnapshot = _sync()
	if snap != null:
		_place(snap, delta)


## The flyers that have a rig now (those falling not counted).
func rig_count() -> int:
	return _rigs.size()


## Rigs made so far, which are the pool's misses.
func rigs_made() -> int:
	return _made


## The rig of unit `id`, null for none (a flyer that is gone, a ground unit).
func rig_of(id: int) -> Rig:
	return _by_id.get(id)


## How high above its ground point the hull of type `type` of `snap` hovers, world px at zoom 1:
## the sheet's `fly_px` (`low_fly_px` for a LOW_AIR type), the default without art. What a tap picks
## the aircraft at (P244). A ground type answers 0.
func lift_of_type(snap: MatchSnapshot, type: int) -> float:
	if not WorldSort.is_flyer(snap, type):
		return 0.0
	var low: bool = snap.type_layer_bit[type] == World.Layer.LOW_AIR
	var sheet: IsoSheetDef = world_sort.sheet(snap.type_ids[type])
	var px: int = 0
	if sheet != null:
		px = sheet.low_fly_px if low else sheet.fly_px
	return float(px) if px > 0 else (DEFAULT_LOW_FLY_PX if low else DEFAULT_FLY_PX)


## Brings the rigs up to `runner.snapshot`: all new for another match, merged by unit id when
## `rows_version` moved. Returns the snapshot, null while there is none.
func _sync() -> MatchSnapshot:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return null
	world_sort.sync()  # The atlas of the match, before any rig is dressed from it.
	var new_match: bool = snap.match_serial != _serial
	if new_match or snap.rows_version != _rows_version:
		if new_match:
			_clear()
		_serial = snap.match_serial
		_rows_version = snap.rows_version
		_merge(snap)
	return snap


func _clear() -> void:
	for rig: Rig in _by_id.values():
		_pool_rig(rig)
	_by_id.clear()
	_rows.clear()
	_rigs.clear()


## The rigs the flyer rows of `snap` stand for, by a walk over its rows: a flyer that is still there
## keeps its rig (heading, phase), a new one takes one from the pool, one that is gone is pooled.
func _merge(snap: MatchSnapshot) -> void:
	var old: Dictionary[int, Rig] = _by_id
	var fresh: Dictionary[int, Rig] = {}
	_rows = PackedInt32Array()
	_rigs = []
	for row: int in snap.unit_id.size():
		if not WorldSort.is_flyer(snap, snap.type_index[row]):
			continue
		var id: int = snap.unit_id[row]
		var rig: Rig = old.get(id)
		if rig != null:
			old.erase(id)
		else:
			rig = _new_rig(snap, row)
		fresh[id] = rig
		_rows.append(row)
		_rigs.append(rig)
	for gone: Rig in old.values():
		_pool_rig(gone)
	_by_id = fresh


## A rig for row `row`, dressed and facing east, under this node.
func _new_rig(snap: MatchSnapshot, row: int) -> Rig:
	var type: int = snap.type_index[row]
	var rig: Rig = _pool.pop_back() if not _pool.is_empty() else _make_rig()
	if rig.get_parent() == _pool_root:
		_pool_root.remove_child(rig)
	var sheet: IsoSheetDef = world_sort.sheet(snap.type_ids[type])
	var art: bool = (
		sheet != null and sheet.has_part(HULL) and sheet.flies() and not world_sort.atlas.is_empty()
	)
	rig.name = "Air%d" % snap.unit_id[row]
	rig.id = snap.unit_id[row]
	rig.owner_id = snap.owner[row]
	rig.sheet = sheet if art else null
	rig.lift = lift_of_type(snap, type)
	rig.heading = 0.0
	rig.aim = 0.0
	rig.frame = NO_FRAME
	rig.hull.visible = art
	rig.shadow.visible = art
	rig.marker.visible = not art
	if art:
		rig.views = sheet.counts[sheet.parts.find(String(HULL))]
		world_sort.dress(rig.hull, sheet, HULL)
		if sheet.has_part(SHADOW):
			world_sort.dress(rig.shadow, sheet, SHADOW)
		_turn(rig)
	else:
		rig.marker.colour = world_sort.mid_colour(rig.owner_id)
		rig.marker.radius = IsoProjection.ellipse_px(snap.type_selection_radius[type]).x
		rig.marker.queue_redraw()
	_lift(rig, rig.lift)
	add_child(rig)
	return rig


func _make_rig() -> Rig:
	_made += 1
	var rig: Rig = Rig.new()
	rig.shadow = Sprite2D.new()
	rig.shadow.name = "Shadow"
	rig.shadow.z_index = WorldSort.Z_SHADOW - Z_AIR  # Absolute 2, on the ground.
	rig.add_child(rig.shadow)
	rig.hull = Sprite2D.new()
	rig.hull.name = "Hull"
	rig.add_child(rig.hull)
	rig.marker = UnitLayer.Marker.new()
	rig.marker.name = "Marker"
	rig.add_child(rig.marker)
	return rig


## Takes `rig` out of the tree into the hidden pool, without a texture of the match's pages.
func _pool_rig(rig: Rig) -> void:
	if rig.get_parent() != null:
		rig.get_parent().remove_child(rig)
	rig.hull.texture = null
	rig.shadow.texture = null
	rig.sheet = null
	_pool_root.add_child(rig)
	_pool.append(rig)


## Shows the hull frame (and its shadow's) of the rig's heading: a region is written only when the
## frame index changed.
func _turn(rig: Rig) -> void:
	var dir: int = UnitLayer.frame_of(rig.heading, rig.views)
	if rig.sheet == null or dir == rig.frame:
		return
	rig.frame = dir
	world_sort.show_frame(rig.hull, rig.sheet, HULL, dir, rig.owner_id)
	if rig.sheet.has_part(SHADOW):
		world_sort.show_frame(rig.shadow, rig.sheet, SHADOW, dir, rig.owner_id)


## Raises the hull, or the marker, `px` above the rig's ground point; the shadow stays on it.
func _lift(rig: Rig, px: float) -> void:
	rig.hull.position.y = -px
	rig.marker.position.y = -px


## Places the flyers' rigs at the point the sim interpolates to, hides an enemy on a tile the local
## player does not see, turns the rest to where they move, and sets the hover and the bob.
func _place(snap: MatchSnapshot, delta: float) -> void:
	var alpha: float = runner.alpha()
	var step: float = turn_rate * delta
	var player: int = FogLayer.local_player_of(runner)
	var fog: FogGrid = snap.fog
	var fogged: bool = not reveal_enemies and FogLayer.covers(fog, player)
	var counts_at: int = (player - 1) * fog.cells
	for at: int in _rows.size():
		var row: int = _rows[at]
		var rig: Rig = _rigs[at]
		var shown: bool = true
		if fogged and rig.owner_id != player:
			shown = fog.visible[counts_at + snap.cell_of(snap.pos_x[row], snap.pos_y[row])] > 0
		rig.visible = shown
		if not shown:
			continue
		var from: Vector2 = IsoProjection.ground_to_px(snap.prev_pos_x[row], snap.prev_pos_y[row])
		var to: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		rig.position = from.lerp(to, alpha)
		# As `UnitLayer`: a flyer that moved under half a step in the tick keeps its heading.
		var dx: int = snap.pos_x[row] - snap.prev_pos_x[row]
		var dy: int = snap.pos_y[row] - snap.prev_pos_y[row]
		var speed: int = snap.type_speed[snap.type_index[row]]
		if dx * dx + dy * dy > 0 and 4 * (dx * dx + dy * dy) >= speed * speed:
			rig.aim = atan2(float(dy), float(dx))
		if rig.heading != rig.aim:
			var turn: float = angle_difference(rig.heading, rig.aim)
			rig.heading = rig.aim if absf(turn) <= step else rig.heading + signf(turn) * step
			_turn(rig)
