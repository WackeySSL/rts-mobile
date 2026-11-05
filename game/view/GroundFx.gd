class_name GroundFx
extends Node2D
## The effects that lie on the ground, under every sorted object (ADR 0027 section 3, plan P138):
## today the dust behind moving vehicles. A ring of `life.dust_slots` slots in packed arrays, drawn
## in one `_draw` from the life atlas at absolute z 3 (over the unit shadows, under the fog). It
## costs no object per puff and allocates nothing per frame.
## A puff is born in `ticked`, once per tick, for each vehicle (any mobile row that is not
## infantry) that moved in that tick and has travelled another `dust_every_milli` since its last
## puff: `dust_back_milli` behind the position it left, along the way it came. Nothing is born for
## a unit that stands, a squad, a building, a source tile the local player does not see, or a
## puff outside the view rect grown by a tile (the travel still counts, so a vehicle that drives
## into view does not start with a debt). The ring overwrites its oldest puff when full, and
## dust never takes a slot of another kind. With `life.reduced` nothing is born and the ring is
## emptied; a new match empties it too.
## A vehicle or a squad that is made (a SPAWNED record of a mobile type) leaves one puff at its
## factory's exit, the point the record carries, in the same ring and under the same rules (an own
## unit, or a source tile the local player sees; the view rect; `reduced` and `dust_slots` of 0 turn
## it off). A DIED record, cancelled or not, draws nothing here.
## A puff lives `dust_life_ms` of match time (`LifeClock`): it grows from `dust_grow_from` to
## `dust_grow_to` times its frame and fades from `dust_alpha` to 0. Which of the three frames it
## shows is `LifeClock.pick` of the unit id and the tick, so two runs draw the same puffs.

const DEFAULT_LIFE: LifeSettings = preload("res://data/life_settings.tres")
const KIND: StringName = &"dust"
const Z: int = 3
## The salt of `LifeClock.mix` for the dust frame (RigLife's idle salts are 0x1... to 0x3...).
const SALT_DUST: int = 0x40000000
## The frame of the puff at a factory's exit.
const SALT_EXIT: int = 0x41000000
## The view rect is grown by a tile before a puff asks whether it is in it.
const VIEW_MARGIN_PX: float = IsoProjection.HALF_W * 2.0

@export var runner: MatchRunner
@export var camera: RtsCamera
@export var life: LifeSettings
@export var reveal_enemies: bool = false

var _atlas: Texture2D = null
var _regions: Array[Rect2] = []  ## Frame k's region, read from `LifeRegions` once.
var _anchor: Vector2 = Vector2.ZERO
var _serial: int = -1  ## match_serial the ring and the travel table belong to.
var _rows_version: int = -1
var _ids: PackedInt32Array = PackedInt32Array()  ## The unit ids of the rows `_travel` is for.
var _travel: PackedInt32Array = PackedInt32Array()  ## Milli-tiles since the row's last puff.
var _size: int = 0  ## Slots in the ring (`life.dust_slots` when it was made).
var _head: int = 0  ## The slot the next puff takes.
var _count: int = 0  ## Slots in use, up to `_size`.
var _born: PackedInt32Array = PackedInt32Array()  ## Tick of the puff.
var _at: PackedVector2Array = PackedVector2Array()  ## World px of its centre.
var _frame: PackedByteArray = PackedByteArray()
## The frame's plan, one quad per live puff: its dst rect at 4i, its frame and its alpha.
var _quad_rect: PackedFloat32Array = PackedFloat32Array()
var _quad_frame: PackedByteArray = PackedByteArray()
var _quad_alpha: PackedFloat32Array = PackedFloat32Array()
var _quads: int = 0
var _drawn_quads: int = 0


func _init() -> void:
	z_index = Z
	z_as_relative = false


func _ready() -> void:
	if life == null:
		life = DEFAULT_LIFE
	_atlas = load(LifeRegions.texture_path(KIND)) as Texture2D
	_regions.clear()
	for frame: int in LifeRegions.FRAMES[KIND]:  # The only place the kind's name is used.
		_regions.append(Rect2(LifeRegions.region(KIND, frame)))
	_anchor = LifeRegions.ANCHOR[KIND]
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	var had_plan: bool = _quads > 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	_follow_match(snap)
	if life.reduced:
		if _count > 0 or had_plan:  # The switch to reduced: nothing stays frozen mid-life.
			_empty()
			queue_redraw()
		return
	_make_ring_if_resized()
	_plan(snap)
	if had_plan or _quads > 0:
		queue_redraw()


func _draw() -> void:
	_drawn_quads = _quads
	for index: int in _quads:
		draw_texture_rect_region(
			_atlas,
			quad_rect(index),
			_regions[_quad_frame[index]],
			Color(1.0, 1.0, 1.0, _quad_alpha[index])
		)


## Puffs in the ring, alive or not yet overwritten.
func slot_count() -> int:
	return _count


## Quads of the last frame's plan (the puffs alive), at most `life.dust_slots`.
func quad_count() -> int:
	return _quads


## Quads the last `_draw` painted: the plan, one for one.
func drawn_quads() -> int:
	return _drawn_quads


## Quad `index` of the plan: where it is drawn in world px, the frame of the atlas and its alpha.
func quad_rect(index: int) -> Rect2:
	var at: int = index * 4
	return Rect2(_quad_rect[at], _quad_rect[at + 1], _quad_rect[at + 2], _quad_rect[at + 3])


func quad_frame(index: int) -> int:
	return _quad_frame[index]


func quad_alpha(index: int) -> float:
	return _quad_alpha[index]


## Where the puff in slot `slot` lies (world px, its centre) and the tick it was born in.
func puff_at(slot: int) -> Vector2:
	return _at[slot]


func puff_born(slot: int) -> int:
	return _born[slot]


## The texture a `_draw` paints from: the only one of this layer.
func texture() -> Texture2D:
	return _atlas


## Empties the ring when `snap` is of another match than the one it holds.
func _follow_match(snap: MatchSnapshot) -> void:
	if snap.match_serial != _serial:
		_serial = snap.match_serial
		_rows_version = -1
		_ids = PackedInt32Array()
		_travel = PackedInt32Array()
		_empty()


func _empty() -> void:
	_head = 0
	_count = 0
	_quads = 0


func _make_ring_if_resized() -> void:
	var want: int = maxi(life.dust_slots, 0)
	if want == _size:
		return
	_size = want
	_born.resize(_size)
	_at.resize(_size)
	_frame.resize(_size)
	_quad_rect.resize(_size * 4)
	_quad_frame.resize(_size)
	_quad_alpha.resize(_size)
	_empty()


## One tick: the travel of every vehicle that moved, and a puff for each that has gone another
## `dust_every_milli` and is where the player can see it.
@warning_ignore("integer_division")
func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or life == null:
		return
	_follow_match(snap)
	if life.reduced:
		return
	_make_ring_if_resized()
	var player: int = FogLayer.local_player_of(runner)
	var view: Rect2 = Rect2()  # Without a camera nothing is in view.
	if camera != null:
		view = camera.visible_world_rect().grow(VIEW_MARGIN_PX)
	_exit_puffs(snap, view, player)
	if life.dust_every_milli <= 0:
		return
	_sync_rows(snap)
	var every: int = life.dust_every_milli
	var back: int = life.dust_back_milli
	var tick: int = snap.tick
	var types: PackedInt32Array = snap.type_index
	var speeds: PackedInt32Array = snap.type_speed
	var armours: PackedInt32Array = snap.type_armour
	var prev_x: PackedInt32Array = snap.prev_pos_x
	var prev_y: PackedInt32Array = snap.prev_pos_y
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var owners: PackedInt32Array = snap.owner
	var ids: PackedInt32Array = snap.unit_id
	for row: int in ids.size():
		var type: int = types[row]
		if speeds[type] <= 0 or armours[type] == World.Armour.INFANTRY:
			continue  # A building or a squad.
		var dx: int = cur_x[row] - prev_x[row]
		var dy: int = cur_y[row] - prev_y[row]
		var moved: int = dx * dx + dy * dy
		if moved == 0:
			continue  # It stood: no dust, no travel.
		var dist: int = maxi(int(sqrt(float(moved))), 1)
		var travelled: int = _travel[row] + dist
		if travelled < every:
			_travel[row] = travelled
			continue
		# At most one puff a tick: a vehicle goes about 147 milli a tick against 700 a puff, and a
		# longer step would drop its extra debt here.
		_travel[row] = travelled % every
		if (
			not reveal_enemies
			and owners[row] != player
			and not FogLayer.is_seen(snap, player, cur_x[row], cur_y[row])
		):
			continue
		var spot: Vector2 = IsoProjection.ground_to_px(
			prev_x[row] - dx * back / dist, prev_y[row] - dy * back / dist
		)
		if view.has_point(spot):
			_add(spot, tick, LifeClock.pick(ids[row], SALT_DUST + tick, _regions.size()))


## A puff at the exit of each factory that made a vehicle or a squad in this tick: the SPAWNED
## record of a mobile type, `[SPAWNED, id, x, y, type index, owner]`.
func _exit_puffs(snap: MatchSnapshot, view: Rect2, player: int) -> void:
	var events: PackedInt32Array = snap.events
	var speeds: PackedInt32Array = snap.type_speed
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] != World.Event.SPAWNED:
			continue
		var type: int = events[at + 4]
		if type < 0 or type >= speeds.size() or speeds[type] <= 0:
			continue  # A building or a site: it has no exit.
		var x: int = events[at + 2]
		var y: int = events[at + 3]
		if (
			not reveal_enemies
			and events[at + 5] != player
			and not FogLayer.is_seen(snap, player, x, y)
		):
			continue
		var spot: Vector2 = IsoProjection.ground_to_px(x, y)
		if view.has_point(spot):
			_add(
				spot,
				snap.tick,
				LifeClock.pick(events[at + 1], SALT_EXIT + snap.tick, _regions.size())
			)


## Keeps `_travel` aligned with the snapshot's rows: when the rows change, each unit that is still
## there keeps its travel and a new one starts at 0. Allocates only then.
func _sync_rows(snap: MatchSnapshot) -> void:
	var ids: PackedInt32Array = snap.unit_id
	if snap.rows_version == _rows_version and ids.size() == _travel.size():
		return
	var next: PackedInt32Array = PackedInt32Array()
	next.resize(ids.size())
	for row: int in ids.size():
		var old: int = _ids.bsearch(ids[row])
		if old < _ids.size() and _ids[old] == ids[row]:
			next[row] = _travel[old]
	_travel = next
	_ids = ids  # An alias: published snapshots are never written, so it cannot change under us.
	_rows_version = snap.rows_version


## The newest puff takes the next slot, which holds the oldest once the ring is full.
func _add(spot: Vector2, tick: int, frame: int) -> void:
	if _size == 0:
		return
	_born[_head] = tick
	_at[_head] = spot
	_frame[_head] = frame
	_head = (_head + 1) % _size
	_count = mini(_count + 1, _size)


## The quads of the puffs that are alive at the frame's match time. Allocates nothing.
func _plan(snap: MatchSnapshot) -> void:
	_quads = 0
	if _count == 0 or life.dust_life_ms <= 0:
		return
	var now_ms: float = LifeClock.ms(snap, runner.alpha())
	var span: float = float(life.dust_life_ms)
	var size: Vector2 = _regions[0].size
	var grow_from: float = life.dust_grow_from
	var grow_to: float = life.dust_grow_to
	var alpha: float = life.dust_alpha
	var oldest: int = _head - _count + _size  # Oldest first, so a newer puff lands over an older.
	for step: int in _count:
		var slot: int = (oldest + step) % _size
		var age: float = LifeClock.age_ms(now_ms, LifeClock.tick_ms(_born[slot]))
		if age >= span:
			continue
		var t: float = age / span
		var grow: float = lerpf(grow_from, grow_to, t)
		var corner: Vector2 = _at[slot] - _anchor * grow
		var out: int = _quads * 4
		_quad_rect[out] = corner.x
		_quad_rect[out + 1] = corner.y
		_quad_rect[out + 2] = size.x * grow
		_quad_rect[out + 3] = size.y * grow
		_quad_frame[_quads] = _frame[slot]
		_quad_alpha[_quads] = alpha * (1.0 - t)
		_quads += 1
