class_name UnitLayer
extends Node2D
## Draws every unit of the runner's published snapshot as a rig: a Node2D with the Sprite2D layers
## Hull, Team and, for a type with turret art, Turret (assets/art/STYLE.md, layer contract). It
## only reads `runner.snapshot` (ADR 0012 section 3), afresh in every entry point and never kept
## between them: each frame a rig stands at prev + (cur - prev) * runner.alpha() in px, and the
## layers turn toward the last direction the unit moved in (the gun follows the hull until a unit
## has a target). The turn is a view effect and never touches the World.
## Rigs are the children of this node in row order, so rig `i` shows unit row `i`, and they follow
## their unit by id: a death frees its rig, a new row gets a new one, a new match rebuilds all.
## A selected unit has a Ring as the first child of its rig, under the layers. Each layer draws at
## one absolute z per batch group (layer_z), so mixed types and owners still batch (ADR 0012
## section 6). The layer also keeps, per row, the hp it last saw and the frame clock of the last hp
## drop (`hit_time_ms`), which the health bars read together with `is_ringed`.

const ART_DIR: String = "res://assets/art/svg/units/"
const RING_ART: String = "res://assets/art/svg/ui/selection_ring.svg"
const LAYER_FILES: Array[String] = ["hull", "team", "turret"]  ## Draw order, also the node names.
const TEAM_LAYER: int = 1  ## Index of "team" in LAYER_FILES.
const TURRET_LAYER: int = 2  ## Index of "turret": a type without that art has no such layer.
const RING_PAD_MILLI: int = 50  ## The ring clears the selection radius by this much.
const RING_MIN_DP: float = 18.0
const RING_TEX_RADIUS_PX: float = 72.0  ## The texture's centre-line radius in its px (STYLE.md).
const Z_RING: int = 1
## The z bands of ADR 0012 section 6, per layer of LAYER_FILES: the first and the last group.
## Hull 10 + type_index, Team 20 + 8 * type_index + owner, Turret 100 + type_index.
const Z_FIRST: PackedInt32Array = [10, 20, 100]
const Z_LAST: PackedInt32Array = [19, 99, 109]
const Z_TYPES: int = 10  ## Type indexes with a group of their own, in every band.
const Z_OWNERS: int = 8  ## Owners with a group of their own, in the Team band.
const NEVER_HIT: int = -1  ## What hit_time_ms answers for a unit whose hp has not dropped.

## Tint of the Team layer by owner id. Index 0 is neutral and also used for any owner past the end.
@export var team_colors: PackedColorArray = PackedColorArray(
	[Color("9AA5B1"), Color("2F80ED"), Color("E5484D")]
)
## How fast a hull turns, in radians per second.
@export var turn_rate: float = 12.0
@export var runner: MatchRunner
@export var camera: RtsCamera

## The frame clock in ms that hit times are stamped by (the frame that saw the hp drop). Tests
## replace it.
var clock: Callable = Time.get_ticks_msec

var _serial: int = -1  ## match_serial the rigs were made for.
var _rows_version: int = -1  ## rows_version the rigs follow.
var _ids: PackedInt32Array = PackedInt32Array()  ## Unit id of rig `i`.
var _rigs: Array[Node2D] = []
## Hull, Team and Turret of rig `i` at 3i, 3i + 1 and 3i + 2; null for a type without a turret.
var _layers: Array[Sprite2D] = []
var _heading: PackedFloat64Array = PackedFloat64Array()  ## Angle the layers show now.
var _aim: PackedFloat64Array = PackedFloat64Array()  ## Last movement direction. East is 0.
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


## The ring texture at `radius` world px: the texture's centre line has RING_TEX_RADIUS_PX, and its
## strokes are baked, so they scale with the ring. `unit` is the world px of one dp.
class Ring:
	extends Sprite2D

	var radius: float = 0.0
	var unit: float = 1.0


func _ready() -> void:
	get_viewport().size_changed.connect(_resize_rings)
	_sync_rigs()


func _process(delta: float) -> void:
	var snap: MatchSnapshot = _sync_rigs()
	if snap != null:
		_update_rigs(snap, delta)
		if not _ringed.is_empty() and camera.zoom.x != _ring_zoom:
			_refresh_rings(snap)


func rig_count() -> int:
	return _rigs.size()


## The absolute z of layer `layer` (an index of LAYER_FILES) for a unit of type `type` and owner
## `owner_id`: one z per batch group. A type past the bands, and for Team an owner past them, takes
## the band's last group (ADR 0012 section 6).
static func layer_z(layer: int, type: int, owner_id: int) -> int:
	if type >= Z_TYPES or (layer == TEAM_LAYER and owner_id >= Z_OWNERS):
		return Z_LAST[layer]
	return Z_FIRST[layer] + (type * Z_OWNERS + owner_id if layer == TEAM_LAYER else type)


## Brings the rigs, the hp last seen and the hit times up to `runner.snapshot`, the sync that
## every other entry point starts with. Call it once before a loop over
## `hit_time_ms` and `is_ringed`, which do not sync themselves: they answer for the rows as the
## last entry point left them, and a synced accessor would cost 150 syncs a frame for the bars.
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


## Where unit row `index` is on screen, in base px.
func unit_screen_position(index: int) -> Vector2:
	_sync_rigs()
	return camera.world_to_screen(_rigs[index].global_position)


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
		if row < 0:
			continue
		if _rings[row] == null:
			_rings[row] = _new_ring(row)
		_rings[row].visible = true
		_ringed.append(row)
	_dp_px = UiScale.base_px_per_dp()
	_refresh_rings(snap)


## Fills `snap` for the Picker with every unit in row order: id, owner, type, centre on screen (base
## px) and hit radius, the larger of `min_radius_px` and the type's selection radius at the camera
## zoom. The snapshot's arrays are resized in place, so refilling one allocates nothing.
func fill_pick_snapshot(snap: PickSnapshot, min_radius_px: float) -> void:
	var source: MatchSnapshot = _sync_rigs()
	var count: int = 0 if source == null else _rigs.size()
	# Packed arrays are shared, not copied, by an assignment: the writes land in the PickSnapshot.
	var out_ids: PackedInt32Array = snap.ids
	var out_owners: PackedInt32Array = snap.owners
	var out_types: PackedInt32Array = snap.type_index
	var out_pos: PackedVector2Array = snap.screen_pos
	var out_radius: PackedFloat32Array = snap.radius_px
	out_ids.resize(count)
	out_owners.resize(count)
	out_types.resize(count)
	out_pos.resize(count)
	out_radius.resize(count)
	if count == 0:
		return
	var ids: PackedInt32Array = source.unit_id
	var owners: PackedInt32Array = source.owner
	var types: PackedInt32Array = source.type_index
	var radii: PackedInt32Array = source.type_selection_radius
	var rigs: Array[Node2D] = _rigs
	var zoom: float = camera.zoom.x
	for row: int in count:
		var type: int = types[row]
		var art_px: float = ViewScale.milli_to_px(radii[type]) * zoom
		out_ids[row] = ids[row]
		out_owners[row] = owners[row]
		out_types[row] = type
		out_pos[row] = camera.world_to_screen(rigs[row].global_position)
		out_radius[row] = maxf(min_radius_px, art_px)


## Reads `runner.snapshot` afresh and brings the rigs up to it: all new for another match_serial,
## merged by unit id when rows_version changed. Returns the snapshot, null while there is none.
func _sync_rigs() -> MatchSnapshot:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return null
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
	for rig: Node2D in _rigs:
		remove_child(rig)
		rig.queue_free()
	_ids.clear()
	_rigs.clear()
	_layers.clear()
	_rings.clear()
	_ringed.clear()
	_heading.clear()
	_aim.clear()
	_last_hp.clear()
	_hit_ms.clear()
	_hp_tick = -1


## Makes the rigs the rows of `snap` by a merge walk over the ascending ids: a unit that is still
## there keeps its rig (position, heading, ring), one that is gone loses it, and a new one gets a
## rig at its position, with the heading 0, no ring, its hp as the last one seen and no hit.
func _merge(snap: MatchSnapshot) -> void:
	var ids: PackedInt32Array = snap.unit_id
	var types: PackedInt32Array = snap.type_index
	var owners: PackedInt32Array = snap.owner
	var type_ids: Array[StringName] = snap.type_ids
	var count: int = ids.size()
	var old_ids: PackedInt32Array = _ids
	var old_count: int = old_ids.size()
	var rigs: Array[Node2D] = []
	var layers: Array[Sprite2D] = []
	var rings: Array[Ring] = []
	var ringed: PackedInt32Array = PackedInt32Array()
	var heading: PackedFloat64Array = PackedFloat64Array()
	var aim: PackedFloat64Array = PackedFloat64Array()
	var last_hp: PackedInt32Array = PackedInt32Array()
	var hit_ms: PackedInt64Array = PackedInt64Array()
	rings.resize(count)
	heading.resize(count)
	aim.resize(count)
	last_hp.resize(count)
	hit_ms.resize(count)
	var old: int = 0
	for row: int in count:
		while old < old_count and old_ids[old] < ids[row]:
			_drop_rig(old)
			old += 1
		if old < old_count and old_ids[old] == ids[row]:
			rigs.append(_rigs[old])
			for layer: int in LAYER_FILES.size():
				layers.append(_layers[old * LAYER_FILES.size() + layer])
			heading[row] = _heading[old]
			aim[row] = _aim[old]
			rings[row] = _rings[old]
			last_hp[row] = _last_hp[old]
			hit_ms[row] = _hit_ms[old]
			if rings[row] != null and rings[row].visible:
				ringed.append(row)
			old += 1
		else:
			var rig: Node2D = _new_rig(
				ids[row], types[row], type_ids[types[row]], owners[row], layers
			)
			add_child(rig)  # A new id is above every survivor's, so the end of the children is its row.
			rigs.append(rig)
			last_hp[row] = snap.hp[row]
			hit_ms[row] = NEVER_HIT
	while old < old_count:
		_drop_rig(old)
		old += 1
	_ids = ids.duplicate()  # Not the snapshot's own array: _clear_rigs() writes it.
	_rigs = rigs
	_layers = layers
	_rings = rings
	_ringed = ringed
	_heading = heading
	_aim = aim
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
	remove_child(_rigs[old])
	_rigs[old].queue_free()


## A rig with its layers in order, which it appends to `layers`: a null for a type without turret
## art. The team layer carries the owner's tint, and every layer its batch group's z.
func _new_rig(
	id: int, type: int, type_id: StringName, owner_id: int, layers: Array[Sprite2D]
) -> Node2D:
	var rig: Node2D = Node2D.new()
	rig.name = "Unit%d" % id
	for layer: int in LAYER_FILES.size():
		var path: String = "%s%s_%s.svg" % [ART_DIR, type_id, LAYER_FILES[layer]]
		var sprite: Sprite2D = null
		if layer != TURRET_LAYER or ResourceLoader.exists(path):
			sprite = Sprite2D.new()
			sprite.name = LAYER_FILES[layer].capitalize()
			sprite.texture = load(path)
			sprite.z_index = layer_z(layer, type, owner_id)
			sprite.z_as_relative = false
			if layer == TEAM_LAYER:
				sprite.modulate = team_color(owner_id)
			rig.add_child(sprite)
		layers.append(sprite)
	return rig


## The Ring of row `row`, its rig's first child (under the layers), at z 1 for every ring.
func _new_ring(row: int) -> Ring:
	var ring: Ring = Ring.new()
	ring.name = "Ring"
	ring.texture = load(RING_ART)
	ring.z_index = Z_RING
	ring.z_as_relative = false
	_rigs[row].add_child(ring)
	_rigs[row].move_child(ring, 0)
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
		ring.radius = maxf(
			ViewScale.milli_to_px(radii[types[row]] + RING_PAD_MILLI), RING_MIN_DP * unit
		)
		ring.unit = unit
		ring.scale = Vector2.ONE * ring.radius / RING_TEX_RADIUS_PX


## The Team layer tint of `owner_id`: index 0 (neutral) for an owner with no colour.
func team_color(owner_id: int) -> Color:
	var known: bool = owner_id >= 0 and owner_id < team_colors.size()
	return team_colors[owner_id if known else 0]


## Places the rigs and turns the layers. Allocates nothing: it only sets properties.
func _update_rigs(snap: MatchSnapshot, delta: float) -> void:
	var alpha: float = runner.alpha()
	var step: float = turn_rate * delta
	var prev_x: PackedInt32Array = snap.prev_pos_x
	var prev_y: PackedInt32Array = snap.prev_pos_y
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var types: PackedInt32Array = snap.type_index
	var speeds: PackedInt32Array = snap.type_speed
	var rigs: Array[Node2D] = _rigs
	var layers: Array[Sprite2D] = _layers
	for row: int in rigs.size():
		var from: Vector2 = ViewScale.milli_to_px_vec(prev_x[row], prev_y[row])
		var to: Vector2 = ViewScale.milli_to_px_vec(cur_x[row], cur_y[row])
		var at: Vector2 = from.lerp(to, alpha)
		if rigs[row].position != at:
			rigs[row].position = at
		# A unit that stood still last tick keeps its heading. So does one that moved under half a
		# full step: the step onto its goal is an integer remainder and can point anywhere.
		var moved_x: int = cur_x[row] - prev_x[row]
		var moved_y: int = cur_y[row] - prev_y[row]
		var moved: int = moved_x * moved_x + moved_y * moved_y
		var speed: int = speeds[types[row]]
		if moved > 0 and 4 * moved >= speed * speed:
			_aim[row] = atan2(float(moved_y), float(moved_x))
		if _heading[row] != _aim[row]:
			# Not rotate_toward: after a turn through +-PI it ends at the aim +- TAU, never equal.
			var turn: float = angle_difference(_heading[row], _aim[row])
			_heading[row] = _aim[row] if absf(turn) <= step else _heading[row] + signf(turn) * step
			for layer: int in LAYER_FILES.size():
				var sprite: Sprite2D = layers[row * LAYER_FILES.size() + layer]
				if sprite != null:
					sprite.rotation = _heading[row]
