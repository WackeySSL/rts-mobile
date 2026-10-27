class_name UnitLayer
extends Node2D
## Draws every unit of the runner's published snapshot as a rig: a Node2D in the `WorldSort` with
## the Sprite2D children Shadow, Hull and, for a type with turret art, Turret, regions of the
## match's one atlas in white (ADR 0023 section 2: the team colour is in the atlas). It
## only reads `runner.snapshot` (ADR 0012 section 3), afresh in every entry point and never kept
## between them: each frame a rig stands at prev + (cur - prev) * runner.alpha() in px, projected
## by `IsoProjection` (ADR 0023 section 1), and the hull turns toward the last direction the unit
## moved in, as a grid angle (east on the grid is 0). A frame is the nearest of 16 (`d06` faces
## grid +x; a squad has the even 8), and a region is written only when its index changes. A
## turret turns on its own toward the unit's
## target (`snapshot.target_row`, computed on the worker, so the layer never searches for a row) as
## the target is drawn, at the bearing between the interpolated positions of the two rigs (ADR 0011
## section 2), in every frame, and stands at the mount of the hull's frame; it follows the hull
## while the unit has no target and stays where it
## is for the ticks in which the target is gone but not yet replaced. A rig without a turret (a
## squad) turns as a whole toward its target instead. The turns are view effects and never touch
## the World. A type with no sheet, or an atlas that did not bake, gets a `Marker` drawn by
## `_draw()` instead of sprites.
## Rigs are the children of the sort node and follow their unit by id: a death frees its rig, a
## new row gets a new one, a new match rebuilds all. A row whose type has a footprint is a
## building: no rig (a null in every per-row list), no ring, no pick, no unit bar.
## A selected unit has a Ring after the Shadow, under the sprites. The Shadow draws at z 2 and the
## Ring at 3, the rest in the sort at 10 (ADR 0023 section 2), so mixed types and owners still
## batch. The layer also keeps, per row, the hp it last saw and the frame clock of the last hp
## drop (`hit_time_ms`), which the health bars read together with `is_ringed`.
## An enemy rig stands on a tile its owner's opponent may not see: the local player's fog hides it
## there (`is_shown`, ADR 0010 section 2) by its `visible` flag alone, so a hidden rig keeps its
## position, heading and frame and still answers `unit_screen_position`. Own rigs are always shown.

const RING_ART: String = "res://assets/art/svg/ui/selection_ring.svg"
## The per-row sprites of `_layers`, at PARTS * row + part; the turret is null for a type without.
const HULL: int = 0
const TURRET: int = 1
const SHADOW: int = 2
const PARTS: int = 3
const PART_NAMES: Array[StringName] = [&"hull", &"turret", &"shadow"]  ## Sheet parts, also nodes.
const DIRECTIONS: int = 16  ## Steps of a full turn in a hull's frames (a squad has every other).
const D_EAST: int = 6  ## The frame `d06` faces grid +x, and each step is 22.5 degrees from it.
const NO_FRAME: int = -1
const RING_PAD_MILLI: int = 50  ## The ring clears the selection radius by this much.
const RING_MIN_DP: float = 18.0
const RING_TEX_RADIUS_PX: float = 72.0  ## The texture's centre-line radius in its px (STYLE.md).
const NEVER_HIT: int = -1  ## What hit_time_ms answers for a unit whose hp has not dropped.

## How fast a hull, a turret or a squad rig turns, in radians per second.
@export var turn_rate: float = 12.0
@export var runner: MatchRunner
@export var camera: RtsCamera
## The sorted world the rigs stand in and the atlas they draw from. A scene shares one with the
## other layers; without one the layer makes its own, as a child.
@export var world_sort: WorldSort
## Shows every enemy rig whatever the fog says: the perf arena, and tests whose subject is not fog.
@export var reveal_enemies: bool = false

## The frame clock in ms that hit times are stamped by (the frame that saw the hp drop). Tests
## replace it.
var clock: Callable = Time.get_ticks_msec

var _serial: int = -1  ## match_serial the rigs were made for.
var _rows_version: int = -1  ## rows_version the rigs follow.
var _ids: PackedInt32Array = PackedInt32Array()  ## Unit id of rig `i`.
var _rigs: Array[Node2D] = []  ## Null for a building.
var _live: int = 0  ## The rigs that are not null.
## Hull, Turret and Shadow of rig `i` at 3i, 3i + 1 and 3i + 2; null for a type without a turret.
var _layers: Array[Sprite2D] = []
var _sheets: Array[IsoSheetDef] = []  ## The sheet of row `i`, null for a type that has none.
## The frame index the hull and the turret of row `i` show, at 2i and 2i + 1 (NO_FRAME: none yet).
var _frames: PackedInt32Array = PackedInt32Array()
## Angles are grid angles: east on the grid is 0, grid +y is a quarter turn.
var _heading: PackedFloat64Array = PackedFloat64Array()  ## Angle the hull shows now.
var _aim: PackedFloat64Array = PackedFloat64Array()  ## Where the hull turns to.
var _turret: PackedFloat64Array = PackedFloat64Array()  ## Angle the turret shows now.
var _rings: Array[Ring] = []  ## Ring of row `i`, made the first time that unit is selected.
var _ringed: PackedInt32Array = PackedInt32Array()  ## Rows whose ring shows.
## hp of row `i` as the layer last saw it, and the clock at which it last fell (NEVER_HIT for
## none). Both follow the rows by unit id like the rigs: rows compact on a death, so a plain
## resize would move a later unit's hit time onto its neighbour.
var _last_hp: PackedInt32Array = PackedInt32Array()
var _hit_ms: PackedInt64Array = PackedInt64Array()
var _hp_tick: int = -1  ## Tick of the snapshot whose hp is in _last_hp, -1 before the first.
var _ring_zoom: float = 1.0  ## Camera zoom the rings are sized for.
var _dp_px: float = 1.0  ## Base px per dp, read when the selection or the window changes.


## The ring texture as a 2:1 ground ellipse (the selection radius, `IsoProjection.ellipse_px`):
## `radius` is its horizontal semi-axis in world px and the vertical one is half of it. The
## texture's centre line has RING_TEX_RADIUS_PX, and its strokes are baked, so they scale with the
## ring. `unit` is the world px of one dp.
class Ring:
	extends Sprite2D

	var radius: float = 0.0
	var unit: float = 1.0


## What stands in for art that is not on the atlas: the unit's ground ellipse in its owner's colour.
class Marker:
	extends Node2D

	var colour: Color = Color.WHITE
	var radius: float = 0.0

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, IsoProjection.GROUND_FLATTEN))
		draw_circle(Vector2.ZERO, radius, colour)


func _ready() -> void:
	if world_sort == null:
		world_sort = WorldSort.new()
		world_sort.runner = runner
		add_child(world_sort)
	get_viewport().size_changed.connect(_resize_rings)
	_sync_rigs()


func _process(delta: float) -> void:
	var snap: MatchSnapshot = _sync_rigs()
	if snap != null:
		_update_rigs(snap, delta)
		if not _ringed.is_empty() and camera.zoom.x != _ring_zoom:
			_refresh_rings(snap)


## The rigs, one for each row that is not a building.
func rig_count() -> int:
	return _live


## The rig of unit row `row`, null for a building or a row out of range. No sync.
func rig(row: int) -> Node2D:
	return _rigs[row] if row >= 0 and row < _rigs.size() else null


## The grid angles (radians, east on the grid 0) that the hull and the turret of row `row` show now:
## the eased ones, whose 16 steps are the frames. No sync.
func heading(row: int) -> float:
	return _heading[row]


func turret_angle(row: int) -> float:
	return _turret[row]


## The rigs shown and inside `view` (world px) now: what the perf card counts as drawn.
func count_in(view: Rect2) -> int:
	var count: int = 0
	for node: Node2D in _rigs:
		if node != null and node.visible and view.has_point(node.position):
			count += 1
	return count


## Brings the rigs, the hp last seen and the hit times up to `runner.snapshot`, the sync that
## the frame, `set_selected`, `unit_screen_position` and `fill_pick_snapshot` start with. Call it
## once before a loop over `hit_time_ms` and `is_ringed`, which do not sync themselves: they
## answer for the rows as the last entry point left them, and a synced accessor would cost 150
## syncs a frame for the bars.
func sync_rows() -> void:
	_sync_rigs()


## The frame clock (`clock`, ms) at which unit row `row` last lost hp, as seen between two
## snapshots, or NEVER_HIT. A health bar shows for a few seconds after it (STYLE.md "Health bars").
## No sync (see `sync_rows`): a caller that loops over rows of a snapshot that may be newer than
## the last frame (inside `ticked`, or in a layer that runs before this one) calls it first.
func hit_time_ms(row: int) -> int:
	return _hit_ms[row] if row >= 0 and row < _hit_ms.size() else NEVER_HIT


## Whether unit row `row` is in the selection as last given to `set_selected`.
func is_ringed(row: int) -> bool:
	return row >= 0 and row < _rings.size() and _rings[row] != null and _rings[row].visible


## Whether unit row `row` of `runner.snapshot` is drawn: an own unit always, an enemy one when its
## tile is visible to the local player (the tile from `snapshot.cell_of`, at the unit's position
## in the tick) or `reveal_enemies` is set. Both are read at the call, nothing is cached. Like
## `hit_time_ms` it does not sync, and a row out of range is not shown.
func is_shown(row: int) -> bool:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or row < 0 or row >= snap.owner.size():
		return false
	var player: int = FogLayer.local_player_of(runner)
	return (
		reveal_enemies
		or snap.owner[row] == player
		or FogLayer.is_seen(snap, player, snap.pos_x[row], snap.pos_y[row])
	)


## Where unit row `index` is on screen, in base px; a building's row answers where its position,
## the footprint centre, is.
func unit_screen_position(index: int) -> Vector2:
	_sync_rigs()
	return camera.world_to_screen(_row_position(index))


## Rings exactly the units in `ids` at once. Unknown ids are skipped.
func set_selected(ids: PackedInt32Array) -> void:
	var snap: MatchSnapshot = _sync_rigs()
	if snap == null:
		return
	for row: int in _ringed:
		_rings[row].visible = false
	_ringed.clear()
	for id: int in ids:
		var row: int = snap.index_of(id)
		if row < 0 or _rigs[row] == null:  # An unknown id, or a building: no ring.
			continue
		if _rings[row] == null:
			_rings[row] = _new_ring(row)
		_rings[row].visible = true
		_ringed.append(row)
	_dp_px = UiScale.base_px_per_dp()
	_refresh_rings(snap)


## Fills `snap` for the Picker with every unit in row order: id, owner, type, centre on screen (base
## px) and hit radius, the larger of `min_radius_px` and the horizontal semi-axis of the type's
## selection ellipse at the camera zoom. The centre is the rig's ground point (the lift of ADR 0023
## section 3 comes with P114b). An enemy that `is_shown` would not draw is filled like
## any other row, with its `pickable` entry 0, so the Picker skips it (P47p). The snapshot's arrays
## are resized in place, so refilling one allocates nothing.
func fill_pick_snapshot(snap: PickSnapshot, min_radius_px: float) -> void:
	var source: MatchSnapshot = _sync_rigs()
	var count: int = 0 if source == null else _rigs.size()
	# Packed arrays are shared, not copied, by an assignment: the writes land in the PickSnapshot.
	var out_ids: PackedInt32Array = snap.ids
	var out_owners: PackedInt32Array = snap.owners
	var out_types: PackedInt32Array = snap.type_index
	var out_pos: PackedVector2Array = snap.screen_pos
	var out_radius: PackedFloat32Array = snap.radius_px
	var out_pickable: PackedByteArray = snap.pickable
	out_ids.resize(count)
	out_owners.resize(count)
	out_types.resize(count)
	out_pos.resize(count)
	out_radius.resize(count)
	out_pickable.resize(count)
	if count == 0:
		return
	var ids: PackedInt32Array = source.unit_id
	var owners: PackedInt32Array = source.owner
	var types: PackedInt32Array = source.type_index
	var radii: PackedInt32Array = source.type_selection_radius
	var rigs: Array[Node2D] = _rigs
	var zoom: float = camera.zoom.x
	# is_shown's rule with the arrays aliased: an enemy is hidden when the tile of its position in
	# this tick (`snapshot.cell_of`) is not visible to the local player.
	var pos_x: PackedInt32Array = source.pos_x
	var pos_y: PackedInt32Array = source.pos_y
	var player: int = FogLayer.local_player_of(runner)
	var fog: FogGrid = source.fog
	var fogged: bool = not reveal_enemies and FogLayer.covers(fog, player)
	var counts: PackedInt32Array = fog.visible
	var counts_at: int = (player - 1) * fog.cells
	for row: int in count:
		var type: int = types[row]
		var art_px: float = IsoProjection.ellipse_px(radii[type]).x * zoom
		out_ids[row] = ids[row]
		out_owners[row] = owners[row]
		out_types[row] = type
		out_pos[row] = camera.world_to_screen(_row_position(row))
		out_radius[row] = maxf(min_radius_px, art_px)
		var seen: bool = not fogged or owners[row] == player
		if not seen:
			seen = counts[counts_at + source.cell_of(pos_x[row], pos_y[row])] > 0
		out_pickable[row] = 1 if seen and rigs[row] != null else 0  # A building: P115b picks it.


## Reads `runner.snapshot` afresh and brings the rigs up to it: all new for another match_serial,
## merged by unit id when rows_version changed. Returns the snapshot, null while there is none.
func _sync_rigs() -> MatchSnapshot:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return null
	world_sort.sync()  # The atlas of the match, before any rig is dressed from it.
	var new_match: bool = snap.match_serial != _serial
	if new_match or snap.rows_version != _rows_version:
		if new_match:
			_clear_rigs()
		_serial = snap.match_serial
		_rows_version = snap.rows_version
		_merge(snap)
	if snap.tick != _hp_tick:
		_note_hits(snap)
	return snap


func _clear_rigs() -> void:
	for node: Node2D in _rigs:
		if node != null:
			world_sort.remove_child(node)
			node.queue_free()
	_ids.clear()
	_rigs.clear()
	_live = 0
	_layers.clear()
	_sheets.clear()
	_frames.clear()
	_rings.clear()
	_ringed.clear()
	_heading.clear()
	_aim.clear()
	_turret.clear()
	_last_hp.clear()
	_hit_ms.clear()
	_hp_tick = -1


## Makes the rigs the rows of `snap` by a merge walk over the ascending ids: a unit that is still
## there keeps its rig (position, heading, ring), one that is gone loses it, and a new one gets a
## rig at its position, with the heading 0, no ring, its hp as the last one seen and no hit.
func _merge(snap: MatchSnapshot) -> void:
	var ids: PackedInt32Array = snap.unit_id
	var types: PackedInt32Array = snap.type_index
	var count: int = ids.size()
	var old_ids: PackedInt32Array = _ids
	var old_count: int = old_ids.size()
	var rigs: Array[Node2D] = []
	var layers: Array[Sprite2D] = []
	var sheets: Array[IsoSheetDef] = []
	var frames: PackedInt32Array = PackedInt32Array()
	var rings: Array[Ring] = []
	var ringed: PackedInt32Array = PackedInt32Array()
	var heading: PackedFloat64Array = PackedFloat64Array()
	var aim: PackedFloat64Array = PackedFloat64Array()
	var turret: PackedFloat64Array = PackedFloat64Array()
	var last_hp: PackedInt32Array = PackedInt32Array()
	var hit_ms: PackedInt64Array = PackedInt64Array()
	rings.resize(count)
	heading.resize(count)
	aim.resize(count)
	turret.resize(count)
	last_hp.resize(count)
	hit_ms.resize(count)
	var old: int = 0
	for row: int in count:
		while old < old_count and old_ids[old] < ids[row]:
			_drop_rig(old)
			old += 1
		if old < old_count and old_ids[old] == ids[row]:
			rigs.append(_rigs[old])
			for part: int in PARTS:
				layers.append(_layers[old * PARTS + part])
			sheets.append(_sheets[old])
			frames.append_array(_frames.slice(old * 2, old * 2 + 2))
			heading[row] = _heading[old]
			aim[row] = _aim[old]
			turret[row] = _turret[old]
			rings[row] = _rings[old]
			last_hp[row] = _last_hp[old]
			hit_ms[row] = _hit_ms[old]
			if rings[row] != null and rings[row].visible:
				ringed.append(row)
			old += 1
		else:
			var node: Node2D = null  # A building has no rig, but keeps the per-row stride.
			if WorldSort.is_building(snap, types[row]):
				layers.resize(layers.size() + PARTS)
				sheets.append(null)
				frames.append_array([NO_FRAME, NO_FRAME])
			else:
				node = _new_rig(snap, row, layers, sheets, frames)
				world_sort.add_child(node)  # Other nodes of the sort stand beside it.
			rigs.append(node)
			last_hp[row] = snap.hp[row]
			hit_ms[row] = NEVER_HIT
	while old < old_count:
		_drop_rig(old)
		old += 1
	_ids = ids.duplicate()  # Not the snapshot's own array: _clear_rigs() writes it.
	_rigs = rigs
	_live = rigs.size() - rigs.count(null)
	_layers = layers
	_sheets = sheets
	_frames = frames
	_rings = rings
	_ringed = ringed
	_heading = heading
	_aim = aim
	_turret = turret
	_last_hp = last_hp
	_hit_ms = hit_ms
	_update_rigs(snap, 0.0)


## Stamps the clock on every row whose hp is lower than the layer last saw it, and remembers the
## new hp. A drop between two snapshots is the hit: it covers every tick since the last frame, and
## damage from any source (a hitscan shot now, a shell that lands later).
func _note_hits(snap: MatchSnapshot) -> void:
	_hp_tick = snap.tick
	var hp: PackedInt32Array = snap.hp
	var last_hp: PackedInt32Array = _last_hp
	var hit_ms: PackedInt64Array = _hit_ms
	var now: int = NEVER_HIT
	for row: int in hp.size():
		if hp[row] < last_hp[row]:
			if now == NEVER_HIT:
				now = clock.call()
			hit_ms[row] = now
		last_hp[row] = hp[row]


func _drop_rig(old: int) -> void:
	if _rigs[old] != null:
		world_sort.remove_child(_rigs[old])
		_rigs[old].queue_free()


## Where row `row` is in world px: its rig's place, or its position for a row with no rig.
func _row_position(row: int) -> Vector2:
	if _rigs[row] != null:
		return _rigs[row].global_position
	var snap: MatchSnapshot = runner.snapshot
	return to_global(IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]))


## The rig of unit row `row` of `snap`, facing east (`d06`): the children Shadow, Hull and Turret on
## the atlas, where the sheet has the part, and a Marker where there is no art. It appends the
## sprites (null for a missing part) to `layers`, its sheet to `sheets` and its frames to `frames`.
## The Shadow draws at z 2, under the rings and the fog, and the rest at the sort's z.
func _new_rig(
	snap: MatchSnapshot,
	row: int,
	layers: Array[Sprite2D],
	sheets: Array[IsoSheetDef],
	frames: PackedInt32Array
) -> Node2D:
	var type: int = snap.type_index[row]
	var owner_id: int = snap.owner[row]
	var sheet: IsoSheetDef = world_sort.sheet(snap.type_ids[type])
	var node: Node2D = Node2D.new()
	node.name = "Unit%d" % snap.unit_id[row]
	var sprites: Array[Sprite2D] = [null, null, null]
	for part: int in [SHADOW, HULL, TURRET]:  # The draw order, which is also the node order.
		if sheet != null and sheet.has_part(PART_NAMES[part]):
			sprites[part] = Sprite2D.new()
			sprites[part].name = String(PART_NAMES[part]).capitalize()
			world_sort.dress(sprites[part], sheet, PART_NAMES[part])
			world_sort.show_frame(sprites[part], sheet, PART_NAMES[part], D_EAST, owner_id)
			node.add_child(sprites[part])
	if sprites[SHADOW] != null:
		sprites[SHADOW].z_index = WorldSort.Z_SHADOW - WorldSort.Z_SORT
	if sprites[TURRET] != null:
		sprites[TURRET].position = sheet.mount(D_EAST) * WorldSort.ART_SCALE
	if sheet == null or world_sort.atlas.is_empty():
		var marker: Marker = Marker.new()
		marker.name = "Marker"
		marker.colour = world_sort.mid_colour(owner_id)
		marker.radius = IsoProjection.ellipse_px(snap.type_selection_radius[type]).x
		node.add_child(marker)
	layers.append_array(sprites)
	sheets.append(sheet)
	frames.append_array([D_EAST, D_EAST])
	return node


## The Ring of row `row`, its rig's child after the Shadow and under the sprites, at z 3.
func _new_ring(row: int) -> Ring:
	var ring: Ring = Ring.new()
	ring.name = "Ring"
	ring.texture = load(RING_ART)
	ring.z_index = WorldSort.Z_RING
	ring.z_as_relative = false
	_rigs[row].add_child(ring)
	_rigs[row].move_child(ring, mini(1, _rigs[row].get_child_count() - 1))
	return ring


func _resize_rings() -> void:  # dp changes with the window.
	_dp_px = UiScale.base_px_per_dp()
	var snap: MatchSnapshot = _sync_rigs()
	if snap != null:
		_refresh_rings(snap)


## A dp size divided by the zoom is world px, so rings are sized again when the zoom changes.
func _refresh_rings(snap: MatchSnapshot) -> void:
	if _ringed.is_empty():
		return
	_ring_zoom = camera.zoom.x
	var unit: float = _dp_px / _ring_zoom
	var types: PackedInt32Array = snap.type_index
	var radii: PackedInt32Array = snap.type_selection_radius
	for row: int in _ringed:
		var ring: Ring = _rings[row]
		var semi: Vector2 = IsoProjection.ellipse_px(radii[types[row]] + RING_PAD_MILLI)
		var grow: float = maxf(1.0, RING_MIN_DP * unit / semi.x)  # The smallest ring: RING_MIN_DP.
		ring.radius = semi.x * grow
		ring.unit = unit
		ring.scale = semi * grow / RING_TEX_RADIUS_PX


## The frame index (`d<NN>`) of grid angle `angle` among the `counts` frames of a part: `d06` faces
## angle 0 and each step is a full turn over 16 (a squad's 8 frames are the even ones).
@warning_ignore("integer_division")
static func frame_of(angle: float, counts: int) -> int:
	return posmod(roundi(angle * counts / TAU) * (DIRECTIONS / counts) + D_EAST, DIRECTIONS)


## Places the rigs and turns what they show. Allocates nothing: it only sets properties.
func _update_rigs(snap: MatchSnapshot, delta: float) -> void:
	var alpha: float = runner.alpha()
	var step: float = turn_rate * delta
	var prev_x: PackedInt32Array = snap.prev_pos_x
	var prev_y: PackedInt32Array = snap.prev_pos_y
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var types: PackedInt32Array = snap.type_index
	var speeds: PackedInt32Array = snap.type_speed
	var targets: PackedInt32Array = snap.target
	var target_rows: PackedInt32Array = snap.target_row
	var rigs: Array[Node2D] = _rigs
	var layers: Array[Sprite2D] = _layers
	# The fog hides an enemy rig on a tile the local player does not see. The tile is the one of
	# the unit's position in this tick (`snapshot.cell_of`), so the flag changes per tick.
	var owners: PackedInt32Array = snap.owner
	var player: int = FogLayer.local_player_of(runner)
	var fog: FogGrid = snap.fog
	var fogged: bool = not reveal_enemies and FogLayer.covers(fog, player)
	var counts: PackedInt32Array = fog.visible
	var counts_at: int = (player - 1) * fog.cells
	for row: int in rigs.size():
		if rigs[row] == null:
			continue  # A building: P115 draws it.
		var from: Vector2 = IsoProjection.ground_to_px(prev_x[row], prev_y[row])
		var to: Vector2 = IsoProjection.ground_to_px(cur_x[row], cur_y[row])
		var at: Vector2 = from.lerp(to, alpha)
		if rigs[row].position != at:
			rigs[row].position = at
		var shown: bool = true
		if fogged and owners[row] != player:
			shown = counts[counts_at + snap.cell_of(cur_x[row], cur_y[row])] > 0
		if rigs[row].visible != shown:
			rigs[row].visible = shown
		# A unit that stood still last tick keeps its heading. So does one that moved under half a
		# full step: the step onto its goal is an integer remainder and can point anywhere.
		var moved_x: int = cur_x[row] - prev_x[row]
		var moved_y: int = cur_y[row] - prev_y[row]
		var moved: int = moved_x * moved_x + moved_y * moved_y
		var speed: int = speeds[types[row]]
		if moved > 0 and 4 * moved >= speed * speed:
			_aim[row] = atan2(float(moved_y), float(moved_x))
		var seen: int = target_rows[row]
		var turret: Sprite2D = layers[row * PARTS + TURRET]
		var bearing: float = 0.0  # To the target as drawn, from rig to rig, on the grid.
		if seen >= 0:
			bearing = atan2(
				lerpf(prev_y[seen], cur_y[seen], alpha) - lerpf(prev_y[row], cur_y[row], alpha),
				lerpf(prev_x[seen], cur_x[seen], alpha) - lerpf(prev_x[row], cur_x[row], alpha)
			)
			if turret == null:
				_aim[row] = bearing  # No turret to swing: the whole rig faces its target.
		if _heading[row] != _aim[row]:
			# Not rotate_toward: after a turn through +-PI it ends at the aim +- TAU, never equal.
			var turn: float = angle_difference(_heading[row], _aim[row])
			_heading[row] = _aim[row] if absf(turn) <= step else _heading[row] + signf(turn) * step
			_show_hull(row, owners[row])
		if turret == null:
			continue
		# The turret follows the hull while there is no target, and eases to the bearing of one.
		# A target that is gone but still held (`target` not yet replaced by the sim) leaves it.
		var want: float = _heading[row]
		if seen >= 0:
			want = bearing
		elif targets[row] != 0:
			want = _turret[row]
		if _turret[row] != want:
			var swing: float = angle_difference(_turret[row], want)
			_turret[row] = want if absf(swing) <= step else _turret[row] + signf(swing) * step
			_show_turret(row, owners[row])


## Shows the hull frame (and its shadow's) of row `row`'s heading, and the turret at that frame's
## mount. A region is written only when the frame index changed.
func _show_hull(row: int, owner_id: int) -> void:
	var sheet: IsoSheetDef = _sheets[row]
	if sheet == null:
		return
	var dir: int = frame_of(_heading[row], sheet.counts[HULL])  # The hull is the first part.
	if dir == _frames[row * 2]:
		return
	_frames[row * 2] = dir
	var at: int = row * PARTS
	world_sort.show_frame(_layers[at + HULL], sheet, PART_NAMES[HULL], dir, owner_id)
	world_sort.show_frame(_layers[at + SHADOW], sheet, PART_NAMES[SHADOW], dir, owner_id)
	if _layers[at + TURRET] != null:
		_layers[at + TURRET].position = sheet.mount(dir) * WorldSort.ART_SCALE


## Shows the turret frame of row `row`'s turret angle, written only when the frame index changed.
func _show_turret(row: int, owner_id: int) -> void:
	var sheet: IsoSheetDef = _sheets[row]
	if sheet == null:
		return
	var dir: int = frame_of(_turret[row], sheet.counts[TURRET])  # The turret is the second part.
	if dir == _frames[row * 2 + 1]:
		return
	_frames[row * 2 + 1] = dir
	world_sort.show_frame(_layers[row * PARTS + TURRET], sheet, PART_NAMES[TURRET], dir, owner_id)
