class_name BuildingLayer
extends Node2D
## Draws every building of the runner's published snapshot in the sorted world (ADR 0023 sections
## 2 and 3, plan P115). A building is a Node2D in the `WorldSort` at its projected footprint centre,
## which is the sort key that puts a unit east or south of the footprint in front of it and one
## north or west behind it. Its `Body` is one Sprite2D, a region of the match's one atlas in white
## (the team colour is in the atlas) whose origin is the footprint centre; a defence has a `Head`
## child at the sheet's mount that turns in 16 steps toward the building's target as a tank's
## turret does. Its cast shadow is a sprite in the `DecalLayer` at z 1, so the units in front of
## the building stand on it. A building with no sheet, an atlas that did not bake, or a sheet of a
## faction its owner does not wear (the strike test's Blackout Array for a Derrick League player),
## gets a flat diamond of its footprint in its owner's colour instead, so it is never invisible.
## Buildings are static, so a frame compares three integers and nothing more: the nodes are made
## when `rows_version` moves (`redraw_count` counts those merges) by a walk over the ascending unit
## ids, and an enemy building's visibility is written when the local player's fog version moves.
## Only the heads, while they have a target or sweep, change in a frame. An own building is always
## shown, an enemy one where any cell of its footprint is seen now (`is_seen`), whole, with its
## shadow; `reveal_enemies` shows all. A building that leaves the rows while it is shown was
## destroyed in sight and leaves a crater in the decal layer; a hidden one, or a new match, leaves
## none. The hit times of a building's bar are the unit layer's (it notes the hp of every row); the
## bar layer reads `is_shown`, `is_selected`, `frame_box` and `bar_lift_px` from here.
## Life (ADR 0027, P136): a `SHOT` of a defence kicks its `Head` back along the aim (`RigLife`,
## numbers in `life`), on the head sprite only: the node, the Body and the shadow never move. The
## kick is noted in `ticked` for a building the local player sees in that tick's fog and drawn on
## match time (`LifeClock`), so a pause freezes it.
## Idle life (P140): a shown defence that is complete and online and has no target sweeps its head
## a few frames either side of its last aim (`RigLife.sweep_offset`), by the head's region only. A
## target, a site, a blackout and `reduced` put the head back on its aim.
## Animations (P144, `BuildingAnims`): a building whose sheet has an `anim` part gets one `Anim`
## child after its `Body`, at the footprint centre, that loops its frames from a per-id phase on
## two clocks that never go back (the local player's own buildings slow to `life.low_power_rate`
## while it is short of power; an enemy's never depend on its owner's power). A site, a blackout
## and a building not shown or not in the view rect (grown by a tile) are not written; a held loop
## shows frame 0. A region is written only when the frame changes. `reduced` keeps them.
## A tap picks a building on its silhouette (P115b, ADR 0023 section 3): `fill_pick_snapshot` lists
## the shown buildings with the footprint's diamond and the height of the picture above it (the
## top of the Body sprite, so the atlas region and its bake scale), for the `Picker`. A selection
## (`set_selected`, wired to `PlayerController.selection_changed`) is kept as unit ids, so a
## building that dies or leaves the rows leaves it.

const HEAD: StringName = &"head"
const BODY: StringName = &"hull"  ## The sheet part of a building's body.
const SHADOW: StringName = &"shadow"
## The view rect is grown by a tile before the animations ask whether a building is in it.
const ANIM_MARGIN_PX: float = IsoProjection.HALF_W * 2.0
const NO_FRAME: int = -1  ## The `dir` of a frame without a direction, a building's body.
## A crater's ground radius per footprint tile, milli: the circle inside the footprint.
const CRATER_MILLI_PER_TILE: int = 500
## The life numbers when `life` is unset (ADR 0027 section 8).
const DEFAULT_LIFE: LifeSettings = preload("res://data/life_settings.tres")

## How fast a head turns, in radians per second.
@export var turn_rate: float = 12.0
@export var runner: MatchRunner
## The view the animations are written for; without one no building is in view.
@export var camera: RtsCamera
## The sorted world the buildings stand in and the atlas they draw from; a scene shares one with
## the unit layer. Without one the layer makes its own, as a child.
@export var world_sort: WorldSort
## The layer for the cast shadows and the craters; without one the layer makes its own.
@export var decals: DecalLayer
## Shows every enemy building whatever the fog says: the perf arena, and tests whose subject is not
## fog.
@export var reveal_enemies: bool = false
## The numbers of the building life (the head's recoil); `data/life_settings.tres` when unset.
@export var life: LifeSettings

var _entries: Dictionary[int, Entry] = {}  ## The building of each unit id.
var _selected: PackedInt32Array = PackedInt32Array()  ## Ids of the selected buildings.
var _heads: Array[Entry] = []  ## The buildings that have a head, for the frame.
var _serial: int = -1  ## match_serial the entries were made for.
var _rows_version: int = -1  ## rows_version they follow.
var _fog_version: int = -1  ## The local player's fog version their visibility was written for.
var _redraws: int = 0
var _rig_life: RigLife = RigLife.new()  ## The kicks that run now (P136).
var _shot_check: Callable = _shot_seen  ## What `note_shots` asks, made once.
var _anims: Array[Entry] = []  ## The buildings that have an `Anim`, for the frame.
var _anim_now: float = -1.0  ## The idle clock the animation clocks were last brought to; -1 none.
var _anim_all_ms: float = 0.0  ## The clock of the loops of every building that is not the local
## player's, at full rate.
var _anim_own_ms: float = 0.0  ## The local player's loops' clock: slowed while short of power.
var _anim_reach: float = 0.0  ## The highest `rise` of a building with an `Anim`, world px.


## One building: its row (moved by every merge), the nodes it owns and what its head shows.
class Entry:
	var id: int = 0
	var row: int = -1
	var stamp: int = 0  ## The merge that last found its row.
	var node: Node2D = null
	var shadow: Sprite2D = null
	var head: Sprite2D = null
	var sheet: IsoSheetDef = null
	var foot: int = 1
	var rise: float = 0.0  ## Footprint centre to the picture's top, world px at zoom 1.
	var shown: bool = true
	var head_dir: int = UnitLayer.D_EAST
	var head_angle: float = 0.0  ## Grid angle, east 0, as the unit layer's.
	var head_rest: Vector2 = Vector2.ZERO  ## Where the head stands on its mount.
	var kick: Vector2 = Vector2.ZERO  ## What the head stands off its mount by life now.
	var idle: RigLife.Idle = RigLife.Idle.new()  ## The idle sweep: frames off `head_dir` it shows.
	var anim: Sprite2D = null  ## The moving element (P144); null for a building with none.
	var anim_base: int = -1  ## Its frame 0 in the atlas's region table.
	var anim_frames: int = 1
	var anim_ms: int = 1  ## The time of one frame.
	var anim_phase: int = 0  ## Ms into the loop at clock 0, by id.
	var anim_shown: int = 0  ## The frame its region shows.


## What stands in for art that is not on the atlas: the footprint's diamond in the owner's colour.
class Marker:
	extends Node2D

	var colour: Color = Color.WHITE
	var foot: int = 1

	func _draw() -> void:
		var half: Vector2 = Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * foot
		var points: PackedVector2Array = PackedVector2Array(
			[
				Vector2(0.0, -half.y),
				Vector2(half.x, 0.0),
				Vector2(0.0, half.y),
				Vector2(-half.x, 0.0)
			]
		)
		draw_colored_polygon(points, colour)


func _ready() -> void:
	if world_sort == null:
		world_sort = WorldSort.new()
		world_sort.runner = runner
		add_child(world_sort)
	if decals == null:
		decals = DecalLayer.new()
		add_child(decals)
	if life == null:
		life = DEFAULT_LIFE
	_rig_life.setup(life)
	if runner != null:
		runner.ticked.connect(_on_ticked)
	_sync()


func _process(delta: float) -> void:
	var snap: MatchSnapshot = _sync()
	if snap == null:
		return
	if not _heads.is_empty():
		_turn_heads(snap, delta)
		_sweep_heads(snap)
	_kick_heads(snap)  # Also with no head left: the kicks of the heads that died end.
	if not _anims.is_empty():
		_play_anims(snap)


## The buildings that have a node now: no sync.
func building_count() -> int:
	return _entries.size()


## How many times the layer made its nodes anew: once for each `rows_version` it has seen, and for
## a new match. It moves with nothing else.
func redraw_count() -> int:
	return _redraws


## The life sprite writes so far: one for each head position the recoil or the idle sweep set and
## each `Anim` region a new frame set (ADR 0027 section 9).
func life_writes() -> int:
	return _rig_life.writes


## The kicks that run now, the heads that are off their mount (a test hook). No sync.
func kick_count() -> int:
	return _rig_life.count()


## The node of the building with unit id `id`, null for an id that is no building. No sync.
func building(id: int) -> Node2D:
	return _entries[id].node if _entries.has(id) else null


## Brings the nodes up to `runner.snapshot`: the sync a frame starts with, and the one a layer that
## reads `is_shown` and `bar_lift_px` calls first.
func sync_rows() -> void:
	_sync()


## Whether the building in row `row` of `runner.snapshot` is drawn: an own one always, an enemy one
## when a cell of its footprint is seen by the local player now, or `reveal_enemies` is set. Read at
## the call. A row that is no building, or out of range, is not shown.
func is_shown(row: int) -> bool:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or row < 0 or row >= snap.owner.size():
		return false
	if not WorldSort.is_building(snap, snap.type_index[row]):
		return false
	var player: int = FogLayer.local_player_of(runner)
	return reveal_enemies or snap.owner[row] == player or is_seen(snap, player, row)


## Where a building's bar stands above its footprint centre: the sheet's `bar_lift_px`, world px at
## zoom 1; 0 for a building with no sheet, whose diamond lies flat. No sync.
func bar_lift_px(row: int) -> float:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or row < 0 or row >= snap.type_index.size() or world_sort == null:
		return 0.0
	var sheet: IsoSheetDef = world_sort.sheet(snap.type_ids[snap.type_index[row]])
	return float(sheet.bar_lift_px) if sheet != null else 0.0


## Makes exactly the buildings among `ids` (unit ids; units and unknown ids are skipped) the
## selected ones: each gets a frame and a bar (`HealthBarLayer`).
func set_selected(ids: PackedInt32Array) -> void:
	_sync()
	_selected.clear()
	for id: int in ids:
		if _entries.has(id):
			_selected.append(id)


## The ids of the selected buildings. No sync.
func selected_ids() -> PackedInt32Array:
	return _selected


## Whether building row `row` of `runner.snapshot` is selected. No sync.
func is_selected(row: int) -> bool:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if _selected.is_empty() or snap == null or row < 0 or row >= snap.unit_id.size():
		return false
	return _selected.has(snap.unit_id[row])


## The box round the silhouette of building row `row`, world px: the footprint's width, from the
## top of the picture down to the diamond's bottom corner. An empty rect for a row that is no
## building. No sync.
func frame_box(row: int) -> Rect2:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or row < 0 or row >= snap.unit_id.size():
		return Rect2()
	var entry: Entry = _entries.get(snap.unit_id[row])
	if entry == null:
		return Rect2()
	var half: Vector2 = Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * entry.foot
	var at: Vector2 = entry.node.position
	return Rect2(at.x - half.x, at.y - entry.rise, 2.0 * half.x, entry.rise + half.y)


## Fills the building arrays of `out` for the `Picker` with the shown buildings, on the screen of
## `view_camera` (centre, diamond, height of the picture, sort key and whether an attack on it is
## taken; see `PickSnapshot`). The unit arrays are left alone. A building the fog hides is left
## out, so no tap reaches it. One shown for a corner cell alone is listed, but not targetable: the
## sim sees an enemy building at the cell under its position (`Targeting.sees`, as `UnitLayer`'s
## `pickable`).
func fill_pick_snapshot(out: PickSnapshot, view_camera: RtsCamera) -> void:
	var snap: MatchSnapshot = _sync()
	out.building_ids.clear()
	out.building_owners.clear()
	out.building_centres.clear()
	out.building_half.clear()
	out.building_rise.clear()
	out.building_keys.clear()
	out.building_targetable.clear()
	if snap == null:
		return
	var zoom: float = view_camera.zoom.x
	var owners: PackedInt32Array = snap.owner
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var player: int = FogLayer.local_player_of(runner)
	var fog: FogGrid = snap.fog
	var all: bool = reveal_enemies or not FogLayer.covers(fog, player)
	var counts: PackedInt32Array = fog.visible
	var base: int = (player - 1) * fog.cells
	for entry: Entry in _entries.values():
		if not entry.shown:
			continue
		var row: int = entry.row
		out.building_ids.append(entry.id)
		out.building_owners.append(owners[row])
		out.building_centres.append(view_camera.world_to_screen(entry.node.position))
		out.building_half.append(
			Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * (entry.foot * zoom)
		)
		out.building_rise.append(entry.rise * zoom)
		out.building_keys.append(entry.node.position.y)
		var targetable: bool = all or owners[row] == player
		if not targetable:
			targetable = counts[base + snap.cell_of(cur_x[row], cur_y[row])] > 0
		out.building_targetable.append(1 if targetable else 0)


## The footprint's cells of building row `row`: its origin tile (the position minus half the
## footprint) and its side, tiles.
static func footprint_of(snap: MatchSnapshot, row: int) -> Rect2i:
	var type: int = snap.type_index[row]
	return footprint_at(
		snap.pos_x[row], snap.pos_y[row], snap.type_foot_w[type], snap.type_foot_h[type]
	)


## Whether `player` sees any cell of the footprint of building row `row` in `snap`; true when its
## fog does not cover the player (the same rule as `FogLayer.is_seen`). For code outside loops: a
## loop over buildings aliases the arrays itself and calls `footprint_at` and `any_cell_seen`.
static func is_seen(snap: MatchSnapshot, player: int, row: int) -> bool:
	return footprint_seen(snap, player, footprint_of(snap, row))


## Whether `player` sees any cell of the footprint `foot` (tiles) in `snap`, a building's or a last-
## seen record's (`GhostMemoryLayer` draws a ghost exactly where this is false); true when the fog
## does not cover the player. For code outside loops: a loop uses `any_cell_seen`.
static func footprint_seen(snap: MatchSnapshot, player: int, foot: Rect2i) -> bool:
	var fog: FogGrid = snap.fog
	if not FogLayer.covers(fog, player):
		return true
	return any_cell_seen(fog.visible, (player - 1) * fog.cells, fog.cols, foot)


## The footprint of `w` x `h` tiles whose centre is (`x`, `y`) in milli-tiles: its origin tile and
## side.
@warning_ignore("integer_division")
static func footprint_at(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(
		(x - w * World.TILE_CENTRE) / World.MILLI_PER_TILE,
		(y - h * World.TILE_CENTRE) / World.MILLI_PER_TILE,
		w,
		h
	)


## Whether a cell of `foot` has a visible count above 0 in `counts`, a fog block of lines `cols`
## cells wide that starts at `base`. The form for a loop, which reads `fog.visible` into a local
## once (`GhostMemoryLayer` and `_refresh_shown` do).
static func any_cell_seen(counts: PackedInt32Array, base: int, cols: int, foot: Rect2i) -> bool:
	for line: int in range(foot.position.y, foot.end.y):
		for col: int in range(foot.position.x, foot.end.x):
			if counts[base + line * cols + col] > 0:
				return true
	return false


## Reads `runner.snapshot` afresh: all new for another match_serial, merged by unit id when
## rows_version moved, only the visibility when the local player's fog version did. Returns the
## snapshot, null while there is none.
func _sync() -> MatchSnapshot:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return null
	world_sort.sync()  # The atlas of the match, before any node is dressed from it.
	var new_match: bool = snap.match_serial != _serial
	if new_match or snap.rows_version != _rows_version:
		if new_match:
			_clear()
		_serial = snap.match_serial
		_rows_version = snap.rows_version
		_merge(snap)
	elif _fog_version != _version_of(snap):
		_refresh_shown(snap)
	return snap


func _clear() -> void:
	for entry: Entry in _entries.values():
		world_sort.remove_child(entry.node)
		entry.node.queue_free()
	_entries.clear()
	_selected.clear()
	_heads.clear()
	_anims.clear()
	_anim_now = -1.0
	_anim_all_ms = 0.0
	_anim_own_ms = 0.0
	_anim_reach = 0.0
	decals.clear()
	_fog_version = -1


## Makes the nodes the buildings of `snap`: a building that is still there keeps its nodes, a new
## one gets them, and one that is gone loses them, with a crater if it was shown.
func _merge(snap: MatchSnapshot) -> void:
	_redraws += 1
	var types: PackedInt32Array = snap.type_index
	var ids: PackedInt32Array = snap.unit_id
	for row: int in ids.size():
		if not WorldSort.is_building(snap, types[row]):
			continue
		var entry: Entry = _entries.get(ids[row])
		if entry == null:
			entry = _make(snap, row)
			_entries[entry.id] = entry
		entry.row = row
		entry.stamp = _redraws
	for entry: Entry in _entries.values():
		if entry.stamp != _redraws:
			_drop(entry)
	_refresh_shown(snap)


## The entry of building row `row`: the node in the sort at the footprint centre with its Body (and
## Head), the shadow in the decal layer, or a Marker where there is no art.
func _make(snap: MatchSnapshot, row: int) -> Entry:
	var type: int = snap.type_index[row]
	var owner_id: int = snap.owner[row]
	var entry: Entry = Entry.new()
	entry.id = snap.unit_id[row]
	entry.foot = snap.type_foot_w[type]
	entry.sheet = world_sort.sheet(snap.type_ids[type])
	entry.node = Node2D.new()
	entry.node.name = "Building%d" % entry.id
	entry.node.position = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
	var sheet: IsoSheetDef = entry.sheet
	var drawn: bool = false  # Whether the atlas has a body frame for this owner's faction.
	entry.rise = float(entry.foot * IsoProjection.HALF_H)  # A flat diamond until a picture says more.
	if sheet != null:
		var body: Sprite2D = _sprite(entry.node, sheet, BODY, NO_FRAME, owner_id)
		body.name = "Body"
		drawn = body.visible
		if drawn:  # The top of the region as it is drawn: offset and scale of the atlas.
			entry.rise = maxf(entry.rise, -body.get_rect().position.y * body.scale.y)
			_dress_anim(entry, sheet, owner_id)
		entry.shadow = _sprite(null, sheet, SHADOW, NO_FRAME, owner_id)
		entry.shadow.name = "Shadow%d" % entry.id
		entry.shadow.position = entry.node.position
		decals.add_shadow(entry.shadow)
		if sheet.has_part(HEAD):
			entry.head = _sprite(entry.node, sheet, HEAD, UnitLayer.D_EAST, owner_id)
			entry.head.name = "Head"
			entry.head_rest = sheet.mount(UnitLayer.D_EAST) * WorldSort.ART_SCALE
			entry.head.position = entry.head_rest
			_heads.append(entry)
	if not drawn:  # No sheet, no atlas, or a sheet of a faction the owner's art does not carry.
		var marker: Marker = Marker.new()
		marker.name = "Marker"
		marker.colour = world_sort.mid_colour(owner_id)
		marker.foot = entry.foot
		entry.node.add_child(marker)
	world_sort.add_child(entry.node)
	return entry


## Gives the entry its `Anim` child when the sheet has an `anim` part the owner's faction has on the
## atlas, showing frame 0, and raises `rise` to its top. The names are resolved here, once.
func _dress_anim(entry: Entry, sheet: IsoSheetDef, owner_id: int) -> void:
	if not sheet.has_part(BuildingAnims.ANIM):
		return
	var base: int = world_sort.base_of(sheet, BuildingAnims.ANIM, NO_FRAME, owner_id)
	var frames: int = world_sort.frame_count_at(base)
	if frames < 1:
		return
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Anim"
	world_sort.dress(sprite, sheet, BuildingAnims.ANIM)
	world_sort.show_base(sprite, base, BuildingAnims.REST)
	entry.node.add_child(sprite)
	entry.anim = sprite
	entry.anim_base = base
	entry.anim_frames = frames
	entry.anim_ms = maxi(sheet.anim_ms, 1)
	entry.anim_phase = BuildingAnims.phase_ms(entry.id, frames, entry.anim_ms)
	entry.rise = maxf(entry.rise, -sprite.get_rect().position.y * sprite.scale.y)
	_anim_reach = maxf(_anim_reach, entry.rise)
	_anims.append(entry)


## A sprite of `part` of `sheet` showing frame `dir` for `owner_id`, a child of `parent` if given.
func _sprite(
	parent: Node2D, sheet: IsoSheetDef, part: StringName, dir: int, owner_id: int
) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	world_sort.dress(sprite, sheet, part)
	world_sort.show_frame(sprite, sheet, part, dir, owner_id)
	if parent != null:
		parent.add_child(sprite)
	return sprite


## Takes a building that left the rows out of the sort, and leaves a crater where it stood if it was
## shown.
func _drop(entry: Entry) -> void:
	if entry.shown:
		var radius: int = entry.foot * CRATER_MILLI_PER_TILE
		decals.add_crater(entry.node.position, radius)
	if entry.shadow != null:
		decals.remove_shadow(entry.shadow)
	_heads.erase(entry)
	_anims.erase(entry)
	var chosen: int = _selected.find(entry.id)
	if chosen >= 0:
		_selected.remove_at(chosen)
	world_sort.remove_child(entry.node)
	entry.node.queue_free()
	_entries.erase(entry.id)


## Writes whether each enemy building is shown, from the fog of `snap`, and remembers the fog
## version it did it for. The snapshot's arrays are read into locals once, before the loop.
func _refresh_shown(snap: MatchSnapshot) -> void:
	_fog_version = _version_of(snap)
	var player: int = FogLayer.local_player_of(runner)
	var owners: PackedInt32Array = snap.owner
	var types: PackedInt32Array = snap.type_index
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var foot_w: PackedInt32Array = snap.type_foot_w
	var foot_h: PackedInt32Array = snap.type_foot_h
	var fog: FogGrid = snap.fog
	var counts: PackedInt32Array = fog.visible
	var base: int = (player - 1) * fog.cells
	var cols: int = fog.cols
	var all: bool = reveal_enemies or not FogLayer.covers(fog, player)
	for entry: Entry in _entries.values():
		var row: int = entry.row
		var shown: bool = all or owners[row] == player
		if not shown:
			var type: int = types[row]
			shown = any_cell_seen(
				counts, base, cols, footprint_at(cur_x[row], cur_y[row], foot_w[type], foot_h[type])
			)
		if shown != entry.shown:
			entry.shown = shown
			entry.node.visible = shown
			if entry.shadow != null:
				entry.shadow.visible = shown and entry.shadow.region_rect.has_area()


## The local player's fog version in `snap`, -2 when its fog does not cover the player.
func _version_of(snap: MatchSnapshot) -> int:
	var player: int = FogLayer.local_player_of(runner)
	return snap.fog.version_of(player) if FogLayer.covers(snap.fog, player) else -2


## Turns the heads toward their targets: the angle eases at `turn_rate` toward the bearing to the
## target as drawn, from the building to the target's interpolated position (`snapshot.target_row`),
## and stays where it is while there is none. A region is written only when the frame index changes.
func _turn_heads(snap: MatchSnapshot, delta: float) -> void:
	var step: float = turn_rate * delta
	var alpha: float = runner.alpha()
	var target_rows: PackedInt32Array = snap.target_row
	var prev_x: PackedInt32Array = snap.prev_pos_x
	var prev_y: PackedInt32Array = snap.prev_pos_y
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var owners: PackedInt32Array = snap.owner
	for entry: Entry in _heads:
		var row: int = entry.row
		var seen: int = target_rows[row]
		if seen < 0 or not entry.shown:
			continue
		var bearing: float = atan2(
			lerpf(prev_y[seen], cur_y[seen], alpha) - cur_y[row],
			lerpf(prev_x[seen], cur_x[seen], alpha) - cur_x[row]
		)
		if entry.head_angle == bearing:
			continue
		var turn: float = angle_difference(entry.head_angle, bearing)
		entry.head_angle = bearing if absf(turn) <= step else entry.head_angle + signf(turn) * step
		var dir: int = UnitLayer.frame_of(entry.head_angle, 16)
		if dir != entry.head_dir:
			entry.head_dir = dir
			entry.idle.sweep = 0  # The head shows its aim, not a frame off it.
			world_sort.show_frame(entry.head, entry.sheet, HEAD, dir, owners[row])


## Notes the kicks of one tick's SHOT records, once per tick (`ticked`): a defence that the local
## player owns or sees in this tick's fog (a cell of its footprint, as `is_shown` says). A hidden
## enemy defence's shot kicks nothing. A defence has no hull to rock: only its head kicks.
func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null:
		return
	_rig_life.note_shots(snap, false, _shot_check)


## [SHOT, shooter id, ...]: whether it kicks, when the shooter is a building with a head that is
## seen.
func _shot_seen(snap: MatchSnapshot, at: int) -> bool:
	var id: int = snap.events[at + 1]
	var entry: Entry = _entries.get(id)
	var row: int = snap.index_of(id)
	if entry == null or entry.head == null or row < 0:
		return false
	var player: int = FogLayer.local_player_of(runner)
	return reveal_enemies or snap.owner[row] == player or is_seen(snap, player, row)


## Draws the kicks at match time (`LifeClock`, which a pause stops): the head's offset from its
## mount, written only when it changed. A kick whose building is gone ends.
func _kick_heads(snap: MatchSnapshot) -> void:
	_rig_life.follow(snap.match_serial)
	if _rig_life.count() == 0:
		return
	var live: int = _rig_life.advance(LifeClock.ms(snap, runner.alpha()))
	for slot: int in live:
		var entry: Entry = _entries.get(_rig_life.id_at(slot))
		if entry == null or entry.head == null:
			_rig_life.end(slot)
			continue
		var offset: Vector2 = _rig_life.turret_offset(slot)
		if offset != entry.kick:
			entry.kick = offset
			entry.head.position = entry.head_rest + offset
			_rig_life.writes += 1
	_rig_life.sweep()


## Idle life of the heads, once a frame: a shown head whose building has no target, is complete
## (`build_left` 0) and is not in a blackout sweeps for the idle clock (it never goes back, so a
## resume does not sweep backwards); any other shown head shows its aim. A region is written only
## when the sweep's frame changed. A hidden head is left as it is.
func _sweep_heads(snap: MatchSnapshot) -> void:
	var now_ms: float = _rig_life.idle_clock(snap, runner.alpha())
	var targets: PackedInt32Array = snap.target_row
	var building: PackedInt32Array = snap.build_left
	var offline: PackedInt32Array = snap.offline_until
	for entry: Entry in _heads:
		var row: int = entry.row
		var active: bool = (
			not life.reduced
			and targets[row] < 0
			and building[row] == 0
			and offline[row] <= snap.tick
		)
		if entry.shown and _rig_life.sweep_step(entry.idle, entry.id, now_ms, active):
			var dir: int = posmod(entry.head_dir + entry.idle.sweep, UnitLayer.DIRECTIONS)
			world_sort.show_frame(entry.head, entry.sheet, HEAD, dir, snap.owner[row])
			_rig_life.writes += 1


## Plays the loops once a frame, while a building with an `Anim` exists. The two clocks go on by
## the match time that passed since the last such frame (the idle clock never goes back, so a
## resume after a pause does not play a frame backwards); the local player's own is scaled by
## `low_power_rate` while it is short of power. A shown building whose centre is in the view rect
## grown by a tile (and at the bottom by the tallest picture, whose moving part stands above the
## centre) shows frame 0 while it is a site or offline, else the frame of its clock; a region is
## written only when that frame is not the one shown.
func _play_anims(snap: MatchSnapshot) -> void:
	var now: float = _rig_life.idle_clock(snap, runner.alpha())
	var player: int = FogLayer.local_player_of(runner)
	if _anim_now < 0.0:  # The first frame of a match: both clocks start at the match time.
		_anim_all_ms = now
		_anim_own_ms = now
	else:
		var step: float = maxf(now - _anim_now, 0.0)
		_anim_all_ms += step
		_anim_own_ms += (
			step * (life.low_power_rate if BuildingAnims.low_power(snap, player) else 1.0)
		)
	_anim_now = now
	var view: Rect2 = Rect2()  # Without a camera nothing is in view.
	if camera != null:
		var m: float = ANIM_MARGIN_PX
		view = camera.visible_world_rect().grow_individual(m, m, m, m + _anim_reach)
	var tick: int = snap.tick
	var owners: PackedInt32Array = snap.owner
	var building: PackedInt32Array = snap.build_left
	var offline: PackedInt32Array = snap.offline_until
	for entry: Entry in _anims:
		if not entry.shown or not view.has_point(entry.node.position):
			continue
		var row: int = entry.row
		var frame: int = BuildingAnims.REST
		if building[row] == 0 and offline[row] <= tick:
			var clock: float = _anim_own_ms if owners[row] == player else _anim_all_ms
			frame = BuildingAnims.frame_at(
				entry.anim_phase, clock, entry.anim_frames, entry.anim_ms
			)
		if frame != entry.anim_shown:
			entry.anim_shown = frame
			world_sort.show_base(entry.anim, entry.anim_base, frame)
			_rig_life.writes += 1
