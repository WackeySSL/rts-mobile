class_name AirFx
extends Node2D
## The smoke, steam and flames that rise from buildings (ADR 0027 sections 3, 4 and 9, plan P145),
## at absolute z 25 (over every sorted sprite, under the bars and the projectiles). A ring of
## `life.emitter_slots` slots in packed arrays, drawn in one `_draw` from the life atlas; it costs
## no object per puff and allocates nothing per frame. Its quota is its own: no other effect takes
## a slot of it and it takes none of theirs.
## A puff is born in `ticked` at an emitter of the sheet of a building (`smoke`, `steam` and `flame`
## points; `exhaust` and `launch` belong to other layers) when the building is complete (no site),
## online (not blacked out) and shown to the local player (`BuildingLayer.is_shown`: an own one
## always, an enemy one only while its footprint is seen), and its spot is in the view rect grown
## by a tile. An emitter puffs every `emit_ms` of its sprite kind (never faster than
## `MIN_EMIT_MS`, so it has at most four puffs alive) from a phase of its own, `LifeClock.pick` of
## the building's id and the emitter's index, so two Turbine Halls, and the two stacks of one, do
## not puff in step. The cycle is a function of the tick alone, so a run is the same on every
## device. The ring overwrites its oldest puff when full.
## A puff lives `emit_life_ms` of its kind (at most `MAX_LIFE_MS`) of match time (`LifeClock`): it
## rises `emit_rise_px` and drifts `emit_drift_px` east while smoke and steam grow from
## `emit_grow_from` to `emit_grow_to` times their frame. A flame keeps its base on its point (no
## rise, no drift) and changes size from `emit_flame_from` to `emit_flame_to`; with a birth every
## 500 ms and a life of 700 the flames overlap into one steady fire that changes frame at each
## birth. Smoke and steam fade from `emit_alpha` to 0 over their life; a flame holds `emit_alpha`
## and fades only over the overlap at the end of its life (the life beyond the time between
## births), so the fire does not pulse. Which frame a puff shows, and whether a flame is
## mirrored (the only kind that may be, `LifeRegions.mirrorable`), is `LifeClock.mix` of the id and
## the tick.
## The ambient is dropped by `life.reduced`: nothing is born and the ring is emptied on the switch;
## a new match empties it too. An ambient emitter stops from the stage its sheet's `emitter_quiet`
## names (an empty one reads as all zeros: it never stops), when the building is that damaged.
## The hit ring (`HitFx`, ADR 0029 section 7: the flash and chips where a shot hits a shown
## building) is a third ring, planned and drawn with the others.
## The damage ring (`DamageFx`, `FxRing`, ADR 0029 section 6) is a second ring of its own, planned
## and drawn in the same `_draw` from the same texture; every glow of it is drawn before every
## other quad, and a switch to `reduced` leaves its puffs alive.

const DEFAULT_LIFE: LifeSettings = preload("res://data/life_settings.tres")
const Z: int = 25
## The emitter kinds of a sheet this layer draws, in the order of the per-kind arrays.
const EMITTERS: Array[StringName] = [&"smoke", &"steam", &"flame"]
const FLAME: int = 2
## Salt of `LifeClock.pick` for the phase of an emitter and of `mix` for a puff's look: far from
## RigLife's (0x1... to 0x3...), the dust's (0x4...) and the building animations' (0x5...).
const SALT_EMIT: int = 0x60000000
const SALT_LOOK: int = 0x68000000
## An emitter puffs no faster than this and a puff lives no longer than this (ADR 0027 section 3:
## at most four alive from one emitter).
## The latest fraction of a tick the rings are planned at. A tick that is not published yet is never
## shown, since `MatchRunner.alpha()` holds 1.0 while a worker tick is awaited and the glow of a
## flame ends on the next tick. Keep it below `1 - 1 ms / tick_ms(1)` (the glow's 1 ms fade, about
## 0.985).
const MAX_PLAN_ALPHA: float = 0.98
const MIN_EMIT_MS: int = 500
const MAX_LIFE_MS: int = 2000

@export var runner: MatchRunner
@export var camera: RtsCamera
@export var life: LifeSettings
## Kept for the wiring `LifeFx` gives every layer; unread here: who is shown follows
## `building_layer.is_shown` (which has its own `reveal_enemies`).
@export var reveal_enemies: bool = false
## Says whether a building is shown to the local player, and where its sheet is.
@export var building_layer: BuildingLayer
## Says which units are shown and where their rigs are drawn (the damaged vehicles' smoke).
@export var unit_layer: UnitLayer

var _atlas: Texture2D = null
var _regions: Array[Rect2] = []  ## The frames of every kind, kind after kind.
var _first_region: PackedInt32Array = PackedInt32Array()  ## Per kind: first frame in `_regions`.
var _frames: PackedInt32Array = PackedInt32Array()
var _anchors: PackedVector2Array = PackedVector2Array()
var _mirror: PackedByteArray = PackedByteArray()  ## Per kind: 1 when it may be drawn mirrored.
var _emit_ms: PackedInt32Array = PackedInt32Array()  ## Per kind, from `life` at the last tick.
var _life_ms: PackedInt32Array = PackedInt32Array()
var _serial: int = -1  ## match_serial the ring belongs to.
var _types_serial: int = -1  ## match_serial the emitter table was made for.
## The emitters of each building type, flat: type t has `_type_first[t]` to `_type_first[t + 1]`.
var _type_first: PackedInt32Array = PackedInt32Array()
var _em_kind: PackedByteArray = PackedByteArray()
var _em_index: PackedByteArray = PackedByteArray()  ## The emitter's index in its sheet.
var _em_at: PackedVector2Array = PackedVector2Array()  ## World px from the footprint centre.
## The stage (1 or 2) from which the emitter goes quiet, 0 for never.
var _em_quiet: PackedByteArray = PackedByteArray()
var _dmg: DamageFx = DamageFx.new()
## The other rings, planned and drawn with the ambient one: a ring is added with one line here.
var _hit: HitFx = HitFx.new()
var _rings: Array[FxRing] = [_dmg.ring, _hit.ring]
var _ring_quads: int = 0  ## Quads of the rings' plans.
var _size: int = 0  ## Slots in the ring (`life.emitter_slots` when it was made).
var _head: int = 0
var _count: int = 0
var _born: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()  ## World px of the puff's birth.
var _kind: PackedByteArray = PackedByteArray()
var _frame: PackedByteArray = PackedByteArray()
var _flip: PackedByteArray = PackedByteArray()
## The frame's plan, one quad per live puff: its bounding rect at 4i, kind, frame, flip and alpha.
var _quad_rect: PackedFloat32Array = PackedFloat32Array()
var _quad_kind: PackedByteArray = PackedByteArray()
var _quad_frame: PackedByteArray = PackedByteArray()
var _quad_flip: PackedByteArray = PackedByteArray()
var _quad_alpha: PackedFloat32Array = PackedFloat32Array()
var _quads: int = 0
var _drawn_quads: int = 0


func _init() -> void:
	z_index = Z
	z_as_relative = false


func _ready() -> void:
	if life == null:
		life = DEFAULT_LIFE
	_atlas = load(LifeRegions.texture_path(&"smoke")) as Texture2D
	for kind: StringName in EMITTERS:  # The only place the kinds' names are used.
		var sprite: StringName = LifeRegions.EMITTER_SPRITE[kind]
		_first_region.append(_regions.size())
		_frames.append(LifeRegions.FRAMES[sprite])
		_anchors.append(LifeRegions.ANCHOR[sprite])
		_mirror.append(1 if LifeRegions.mirrorable(sprite) else 0)
		for frame: int in LifeRegions.FRAMES[sprite]:
			_regions.append(Rect2(LifeRegions.region(sprite, frame)))
	_emit_ms.resize(EMITTERS.size())
	_life_ms.resize(EMITTERS.size())
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	var had_plan: bool = _quads > 0 or _ring_quads > 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	_follow_match(snap)
	if life.reduced:
		if _count > 0 or _quads > 0:  # The switch to reduced: nothing stays frozen mid-life.
			_empty()
			had_plan = true
	else:
		_make_ring_if_resized()
		_plan(snap)
	_ring_quads = 0
	var now_ms: float = LifeClock.ms(snap, minf(runner.alpha(), MAX_PLAN_ALPHA))
	for ring: FxRing in _rings:
		ring.plan(now_ms)
		_ring_quads += ring.quad_count()
	if had_plan or _quads > 0 or _ring_quads > 0:
		queue_redraw()


func _draw() -> void:
	_drawn_quads = _quads
	for ring: FxRing in _rings:  # The glow pass, under every other quad.
		ring.draw(self, _atlas, FxRing.GLOW)
	var mirrored: bool = false
	for index: int in _quads:
		var rect: Rect2 = quad_rect(index)
		var color: Color = Color(1.0, 1.0, 1.0, _quad_alpha[index])
		var region: Rect2 = _regions[_first_region[_quad_kind[index]] + _quad_frame[index]]
		if _quad_flip[index] == 1:
			# Mirrored about the vertical edge of its box: the box's right edge is the origin.
			draw_set_transform(Vector2(rect.end.x, rect.position.y), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect_region(_atlas, Rect2(Vector2.ZERO, rect.size), region, color)
			mirrored = true
		else:
			if mirrored:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				mirrored = false
			draw_texture_rect_region(_atlas, rect, region, color)
	if mirrored:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for pass_of: int in range(FxRing.CLOUD, FxRing.PASSES):  # Clouds, then the flames over them.
		for ring: FxRing in _rings:
			ring.draw(self, _atlas, pass_of)


## The damage particles (a test hook); their ring is the first of `_rings`.
func damage() -> DamageFx:
	return _dmg


## Starts a crater source: smoke and embers over the spot of a building of type index `type` that
## fell (ADR 0029 section 6; P165's collapse calls it when it ends). `centre` is the footprint
## centre in world px, `foot` the footprint in tiles, `owner_id` its player, `tick` the tick the
## smoke starts in. The damage points at ground height come from the type's sheet (`DamageFx`).
## Named apart from `DecalLayer.add_crater`, which lays the crater itself.
func add_crater_source(
	id: int, centre: Vector2, type: int, foot: Rect2i, owner_id: int, tick: int
) -> void:
	_dmg.add_crater(life, id, centre, type, foot, owner_id, tick)


## Ends the crater sources over `foot` (tiles): a building was placed there. Their puffs live out.
func end_crater_sources_on(foot: Rect2i) -> void:
	_dmg.end_craters_on(foot)


## The hit feedback (a test hook); its ring is the second of `_rings`.
func hits() -> HitFx:
	return _hit


## Puffs in the ring, alive or not yet overwritten.
func slot_count() -> int:
	return _count


## Quads of the last frame's plan (the puffs alive), at most `life.emitter_slots`.
func quad_count() -> int:
	return _quads


## Quads the last `_draw` painted: the plan, one for one.
func drawn_quads() -> int:
	return _drawn_quads


## Quad `index` of the plan: the box it is drawn in (world px), its kind (an index of `EMITTERS`),
## its frame, whether it is mirrored in x, and its alpha.
func quad_rect(index: int) -> Rect2:
	var at: int = index * 4
	return Rect2(_quad_rect[at], _quad_rect[at + 1], _quad_rect[at + 2], _quad_rect[at + 3])


func quad_kind(index: int) -> int:
	return _quad_kind[index]


func quad_frame(index: int) -> int:
	return _quad_frame[index]


func quad_flipped(index: int) -> bool:
	return _quad_flip[index] == 1


func quad_alpha(index: int) -> float:
	return _quad_alpha[index]


## Where the puff in slot `slot` was born (world px) and the tick it was born in.
func puff_at(slot: int) -> Vector2:
	return _at[slot]


func puff_born(slot: int) -> int:
	return _born[slot]


## The texture a `_draw` paints from: the only one of this layer.
func texture() -> Texture2D:
	return _atlas


## The tick at which an emitter of `every` ms from `phase` ms puffs: the cycle number of the match
## time `tick`, integers only (a tick lasts 1000 / TICK_RATE ms).
@warning_ignore("integer_division")
static func cycle(tick: int, phase: int, every: int) -> int:
	return (tick * 1000 + phase * Sim.TICK_RATE) / (every * Sim.TICK_RATE)


## The ms an emitter of `every` ms waits before its first puff: `LifeClock.pick` of the building's
## id and the emitter's index.
static func phase_ms(id: int, index: int, every: int) -> int:
	return LifeClock.pick(id, SALT_EMIT + index, every)


func _follow_match(snap: MatchSnapshot) -> void:
	if snap.match_serial != _serial:
		_serial = snap.match_serial
		_empty()
		for ring: FxRing in _rings:
			ring.clear()
		_dmg.end_craters()


func _empty() -> void:
	_head = 0
	_count = 0
	_quads = 0


func _make_ring_if_resized() -> void:
	var want: int = maxi(life.emitter_slots, 0)
	if want == _size:
		return
	_size = want
	_born.resize(_size)
	_at.resize(_size)
	_kind.resize(_size)
	_frame.resize(_size)
	_flip.resize(_size)
	_quad_rect.resize(_size * 4)
	_quad_kind.resize(_size)
	_quad_frame.resize(_size)
	_quad_flip.resize(_size)
	_quad_alpha.resize(_size)
	_empty()


## Reads the rate and the life of each kind from `life`, held to the rules of ADR 0027 section 3.
func _read_numbers() -> void:
	for kind: int in EMITTERS.size():
		var sprite: StringName = LifeRegions.EMITTER_SPRITE[EMITTERS[kind]]
		var every: int = life.emit_ms.get(sprite, 0)
		_emit_ms[kind] = maxi(every, MIN_EMIT_MS) if every > 0 else 0
		_life_ms[kind] = clampi(life.emit_life_ms.get(sprite, 0), 0, MAX_LIFE_MS)


## Makes the table of the emitters of each building type, once a match: the sheet's `smoke`,
## `steam` and `flame` points, at the art scale, and the damage points (`DamageFx.build`). False
## while the layer has no sheets yet.
func _sync_types(snap: MatchSnapshot) -> bool:
	if _types_serial == snap.match_serial:
		return true
	var sort: WorldSort = building_layer.world_sort
	if sort == null:
		return false
	sort.sync()  # The sheets of this match's baked atlas, whichever layer ticked first.
	_types_serial = snap.match_serial
	_type_first.clear()
	_em_kind.clear()
	_em_index.clear()
	_em_at.clear()
	_em_quiet.clear()
	for type: int in snap.type_ids.size():
		_type_first.append(_em_kind.size())
		var sheet: IsoSheetDef = sort.sheet(snap.type_ids[type])
		if sheet == null or not WorldSort.is_building(snap, type):
			continue
		for index: int in sheet.emitters.size():
			var kind: int = _emitter_kind(sheet.emitters[index])
			if kind >= 0:
				_em_kind.append(kind)
				_em_index.append(index)
				_em_at.append(sheet.emitter_point(index, -1) * WorldSort.ART_SCALE)
				_em_quiet.append(
					sheet.emitter_quiet[index] if index < sheet.emitter_quiet.size() else 0
				)
	_type_first.append(_em_kind.size())
	_dmg.build(snap, sort)
	return true


## The index in `EMITTERS` of the sheet's emitter name, -1 for one this layer does not draw.
func _emitter_kind(named: String) -> int:
	for kind: int in EMITTERS.size():
		if String(EMITTERS[kind]) == named:
			return kind
	return -1


## One tick: a puff at each ambient emitter whose cycle turned over (`_emit_ambient`) and the
## damage particles of the damaged buildings and vehicles in view (`DamageFx`).
func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or life == null:
		return
	_follow_match(snap)
	if building_layer == null:
		return
	_make_ring_if_resized()
	if not _sync_types(snap):
		return
	var view: Rect2 = Rect2()  # Without a camera nothing is in view.
	if camera != null:
		view = camera.visible_world_rect().grow(BuildingLayer.ANIM_MARGIN_PX)
	if _size > 0 and not life.reduced:
		_read_numbers()
		_emit_ambient(snap, view)
	_dmg.read(life)
	_dmg.emit(
		snap,
		view,
		life,
		building_layer,
		unit_layer,
		get_global_transform().affine_inverse(),
		FogLayer.local_player_of(runner)
	)
	_hit.read(life)
	_hit.emit(snap, life, building_layer, view)


## A puff at each ambient emitter whose cycle turned over, of a building the player can see that is
## complete and online, and not so damaged that its sheet has the emitter go quiet.
func _emit_ambient(snap: MatchSnapshot, view: Rect2) -> void:
	var tick: int = snap.tick
	var types: PackedInt32Array = snap.type_index
	var building: PackedInt32Array = snap.build_left
	var offline: PackedInt32Array = snap.offline_until
	var ids: PackedInt32Array = snap.unit_id
	for row: int in ids.size():
		var first: int = _type_first[types[row]]
		var last: int = _type_first[types[row] + 1]
		if first == last or building[row] != 0 or offline[row] > tick:
			continue
		if not building_layer.is_shown(row):
			continue
		var centre: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		var stage: int = -1  # Read when an emitter of the row can go quiet.
		for em: int in range(first, last):
			var kind: int = _em_kind[em]
			var every: int = _emit_ms[kind]
			if every <= 0:
				continue
			if _em_quiet[em] > 0:
				if stage < 0:
					stage = _stage_of(snap, row)
				if stage >= _em_quiet[em]:
					continue
			var phase: int = phase_ms(ids[row], _em_index[em], every)
			if cycle(tick, phase, every) == cycle(tick - 1, phase, every):
				continue
			var spot: Vector2 = centre + _em_at[em]
			if view.has_point(spot):
				_add(spot, tick, kind, LifeClock.mix(ids[row], SALT_LOOK + tick + em))


## The damage stage of building row `row` (`BuildingDamage.stage_of` with the building lines).
func _stage_of(snap: MatchSnapshot, row: int) -> int:
	var max_hp: int = snap.type_max_hp[snap.type_index[row]]
	return BuildingDamage.stage_of(snap.hp[row], max_hp, life.building_stage_percent)


## The newest puff takes the next slot, which holds the oldest once the ring is full. `look` picks
## the frame and the mirroring.
func _add(spot: Vector2, tick: int, kind: int, look: int) -> void:
	_born[_head] = tick
	_at[_head] = spot
	_kind[_head] = kind
	_frame[_head] = look % _frames[kind]
	_flip[_head] = (look >> 16) & _mirror[kind]
	_head = (_head + 1) % _size
	_count = mini(_count + 1, _size)


## The quads of the puffs that are alive at the frame's match time. Allocates nothing.
func _plan(snap: MatchSnapshot) -> void:
	_quads = 0
	if _count == 0:
		return
	var now_ms: float = LifeClock.ms(snap, runner.alpha())
	var rise: float = life.emit_rise_px
	var drift: float = life.emit_drift_px
	var grow_from: float = life.emit_grow_from
	var grow_to: float = life.emit_grow_to
	var flame_from: float = life.emit_flame_from
	var flame_to: float = life.emit_flame_to
	var alpha: float = life.emit_alpha
	var oldest: int = _head - _count + _size  # Oldest first, so a newer puff lands over an older.
	for step: int in _count:
		var slot: int = (oldest + step) % _size
		var kind: int = _kind[slot]
		var span: float = float(_life_ms[kind])
		var age: float = LifeClock.age_ms(now_ms, LifeClock.tick_ms(_born[slot]))
		if age >= span:
			continue
		var t: float = age / span
		var grow: float = (
			lerpf(flame_from, flame_to, t) if kind == FLAME else lerpf(grow_from, grow_to, t)
		)
		var anchor: Vector2 = _anchors[kind]
		var size: Vector2 = _regions[_first_region[kind] + _frame[slot]].size * grow
		var moved: float = 0.0 if kind == FLAME else t  # A flame stays on its stack.
		var at: Vector2 = _at[slot] + Vector2(drift * moved, -rise * moved)
		var reach: float = anchor.x * grow
		var left: float = at.x - ((size.x - reach) if _flip[slot] == 1 else reach)
		var out: int = _quads * 4
		_quad_rect[out] = left
		_quad_rect[out + 1] = at.y - anchor.y * grow
		_quad_rect[out + 2] = size.x
		_quad_rect[out + 3] = size.y
		_quad_kind[_quads] = kind
		_quad_frame[_quads] = _frame[slot]
		_quad_flip[_quads] = _flip[slot]
		var fade: float = 1.0 - t
		if kind == FLAME:
			fade = clampf((span - age) / maxf(span - float(_emit_ms[kind]), 1.0), 0.0, 1.0)
		_quad_alpha[_quads] = alpha * fade
		_quads += 1
