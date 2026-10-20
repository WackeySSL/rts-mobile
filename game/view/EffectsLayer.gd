class_name EffectsLayer
extends Node2D
## Combat effects over the runner's published snapshot (assets/art/STYLE.md "Combat effects"): a
## tracer and a muzzle flash for a shot, a puff where a shell lands, a burst where a vehicle dies
## and a fade where infantry does. It reads `runner.snapshot.events` inside `runner.ticked`
## (ADR 0012 section 3). The runner emits `ticked` once per tick, right after it publishes that
## tick's snapshot, also when a frame plays several catch-up ticks, so every tick's events are read
## once and none twice.
##
## The effects live in a fixed ring of `capacity` slots in packed arrays (ADR 0011 section 3): the
## newest overwrites the oldest and an effect costs no object. An effect lives its lifetime on
## `clock`, the frame clock in ms, and is drawn at the event's own positions, which a SHOT carries
## for both units, so a tracer shows after either is gone. Nothing filters by owner or by fog: an
## armed neutral (owner 0) shoots like anyone, and the fog layer (P47) hides what is not seen.
##
## `_process` plans the frame's lines and quads into reused packed arrays and `_draw` paints that
## plan: tracers as straight lines (butt caps: draw_line has no round ones, which STYLE.md asks
## for), everything else as quads of one atlas (ADR 0011 section 3, z 130 in ADR 0012 section 6).
##
## A shell that overflowed the slot pool (P42b) has a SHOT and no IMPACT, and nothing in the
## snapshot tells it from a shell in flight, so it gets what any projectile SHOT gets: the flash and
## no puff. Its damage shows in the health bar. The shipped data keeps that count at 0.

enum Kind { FLASH, TRACER, PUFF, BURST, FADE }

const ATLAS: Texture2D = preload("res://assets/art/svg/fx/effects_atlas.svg")
## Regions of the atlas in px of the imported texture (STYLE.md); a quad is square, drawn at the
## centre of its region.
const BURST: Rect2 = Rect2(0, 0, 80, 80)
const PUFF: Rect2 = Rect2(84, 0, 56, 56)
const FLASH: Rect2 = Rect2(144, 0, 32, 32)
const REGIONS: Array[Rect2] = [BURST, PUFF, FLASH]  ## Indexed by REGION_*.
const REGION_BURST: int = 0
const REGION_PUFF: int = 1
const REGION_FLASH: int = 2

## STYLE.md times in ms on the frame clock: the lifetime of each Kind, then the times inside it.
const LIFETIME_MS: PackedInt32Array = [100, 120, 350, 600, 700]
const FLASH_FULL_MS: int = 40  ## Alpha 1 up to here, then linear to 0 at the lifetime.
const PUFF_FULL_MS: int = 150
const PUFF_GROW_MS: int = 150  ## STYLE.md gives the growth no time: the span of full alpha.
const PUFF_GROW_FROM: float = 0.6  ## Times the size, easing out to 1.
const BURST_FULL_MS: int = 350
const BURST_GROW_MS: int = 150
const BURST_GROW_FROM: float = 0.5
const BURST_PX: float = 80.0  ## Quad sizes in world px: a vehicle's burst and an infantry fade.
const FADE_PX: float = 24.0
const FADE_ALPHA: float = 0.7  ## Linear to 0 over the whole lifetime.
const TRACER_DP: float = 1.5  ## Colour pass; the outline pass is FeedbackStyle.OUTLINE_DP wider.
## What a weapon id that the tables below lack gets.
const FLASH_DEFAULT_PX: float = 24.0
const PUFF_DEFAULT_PX: float = 40.0
const MUZZLE_DEFAULT_PX: float = 13.0
const GEO_STRIDE: int = 5  ## A slot's x, y, end x, end y and size, in world px.

## Ring slots; the setter makes a new, empty ring.
@export var capacity: int = 128:
	set(value):
		capacity = maxi(value, 1)
		_make_ring()
@export var runner: MatchRunner
## The look: palette colours, exports of this world-space layer like the other view layers'.
@export var tracer_color: Color = Color("FFD84D")
@export var edge_color: Color = FeedbackStyle.OUTLINE
## Per weapon id (`weapon_ids[i]`): the flash quad's side, where the shot leaves the barrel
## (px from the shooter towards the target) and the impact puff's side, in world px.
@export var flash_px: Dictionary[StringName, float] = {
	&"tank_cannon": 32.0, &"rocket": 24.0, &"rifle": 16.0
}
@export var muzzle_px: Dictionary[StringName, float] = {
	&"tank_cannon": 31.0, &"rocket": 13.0, &"rifle": 13.0
}
@export var puff_px: Dictionary[StringName, float] = {&"tank_cannon": 40.0, &"rocket": 56.0}

## The frame clock in ms that effects are born and expire by. Tests replace it.
var clock: Callable = Time.get_ticks_msec

var _serial: int = -1  ## match_serial the ring holds effects of.
var _dp_px: float = 1.0  ## Base px per dp, read when the window changes.
var _size: int = 0  ## Slots in the ring (capacity when it was made).
var _head: int = 0  ## The slot the next effect takes.
var _count: int = 0  ## Slots in use, up to _size: the oldest is at _head - _count.
var _live_until: int = 0  ## Clock ms after which no effect of the ring is alive.
var _kind: PackedInt32Array = PackedInt32Array()
var _born: PackedInt64Array = PackedInt64Array()
var _geo: PackedFloat32Array = PackedFloat32Array()
## The frame's plan. Line `i` has x, y, end x and end y at 4i; a tracer is two lines, the
## outline pass and then the colour pass. Quad `i` has its dst rect at 4i and its region.
var _line_points: PackedFloat32Array = PackedFloat32Array()
var _line_width: PackedFloat32Array = PackedFloat32Array()
var _line_color: PackedColorArray = PackedColorArray()
var _quad_rect: PackedFloat32Array = PackedFloat32Array()
var _quad_region: PackedInt32Array = PackedInt32Array()
var _quad_alpha: PackedFloat32Array = PackedFloat32Array()
var _lines: int = 0
var _quads: int = 0
var _drawn_lines: int = 0
var _drawn_quads: int = 0


func _init() -> void:
	_make_ring()


func _ready() -> void:
	get_viewport().size_changed.connect(_read_dp)
	_read_dp()
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	var had_plan: bool = _lines > 0 or _quads > 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap != null:
		_follow_match(snap)
	_plan()
	if had_plan or _lines > 0 or _quads > 0:
		queue_redraw()


## Effects alive now by `clock`: the ones whose lifetime has not run out.
func active_count() -> int:
	var now: int = int(clock.call())
	if now >= _live_until:
		return 0
	var alive: int = 0
	for slot: int in _count:
		if now - _born[slot] < LIFETIME_MS[_kind[slot]]:
			alive += 1
	return alive


func line_count() -> int:
	return _lines


func quad_count() -> int:
	return _quads


func drawn_lines() -> int:
	return _drawn_lines


func drawn_quads() -> int:
	return _drawn_quads


## Line `index` of the plan: its ends and width in world px, and its colour with the alpha.
func line_from(index: int) -> Vector2:
	return Vector2(_line_points[index * 4], _line_points[index * 4 + 1])


func line_to(index: int) -> Vector2:
	return Vector2(_line_points[index * 4 + 2], _line_points[index * 4 + 3])


func line_width(index: int) -> float:
	return _line_width[index]


func line_color(index: int) -> Color:
	return _line_color[index]


## Quad `index` of the plan: where it is drawn in world px, the region of the atlas it shows
## (BURST, PUFF or FLASH) and its alpha.
func quad_rect(index: int) -> Rect2:
	var at: int = index * 4
	return Rect2(_quad_rect[at], _quad_rect[at + 1], _quad_rect[at + 2], _quad_rect[at + 3])


func quad_region(index: int) -> Rect2:
	return REGIONS[_quad_region[index]]


func quad_alpha(index: int) -> float:
	return _quad_alpha[index]


## 1 until `full_ms`, then linear to 0 at `end_ms`.
static func hold_then_fade(age_ms: int, full_ms: int, end_ms: int) -> float:
	if age_ms <= full_ms:
		return 1.0
	return clampf(float(end_ms - age_ms) / float(end_ms - full_ms), 0.0, 1.0)


func _make_ring() -> void:
	_size = capacity
	_kind.resize(_size)
	_born.resize(_size)
	_geo.resize(_size * GEO_STRIDE)
	_line_points.resize(_size * 8)  # Two lines of four numbers for each slot.
	_line_width.resize(_size * 2)
	_line_color.resize(_size * 2)
	_quad_rect.resize(_size * 4)
	_quad_region.resize(_size)
	_quad_alpha.resize(_size)
	_empty()


## No effect and no plan, as at the start of a match.
func _empty() -> void:
	_head = 0
	_count = 0
	_live_until = 0
	_lines = 0
	_quads = 0


func _read_dp() -> void:  # dp changes with the window.
	_dp_px = UiScale.base_px_per_dp()


## Empties the ring when `snap` is of another match than the one it holds.
func _follow_match(snap: MatchSnapshot) -> void:
	if snap.match_serial != _serial:
		_serial = snap.match_serial
		_empty()


## One tick's events: a SHOT, an IMPACT or a DIED each add effects at the positions they carry.
## They are born at the clock read here, once per tick: a frame's earlier ticks start older.
func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null:
		return
	_follow_match(snap)
	var events: PackedInt32Array = snap.events
	var now: int = int(clock.call())
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		var kind: int = events[at]
		if kind == World.Event.SHOT:
			_add_shot(snap, at, now)
		elif kind == World.Event.IMPACT:
			_add_impact(snap, at, now)
		elif kind == World.Event.DIED:
			_add_death(snap, at, now)


## [SHOT, shooter id, shooter x, shooter y, target id, weapon, target x, target y]: a flash at
## the muzzle, which is on the way to the target and no farther than it, and for a hitscan weapon
## a tracer from there to the target's position. The ends are the event's, not the rows'.
func _add_shot(snap: MatchSnapshot, at: int, now: int) -> void:
	var events: PackedInt32Array = snap.events
	var weapon: int = events[at + 5]
	var weapon_id: StringName = _weapon_id(snap, weapon)
	var shooter: Vector2 = ViewScale.milli_to_px_vec(events[at + 2], events[at + 3])
	var target: Vector2 = ViewScale.milli_to_px_vec(events[at + 6], events[at + 7])
	var reach: float = muzzle_px.get(weapon_id, MUZZLE_DEFAULT_PX)
	var muzzle: Vector2 = shooter + (target - shooter).limit_length(reach)
	var speeds: PackedInt32Array = snap.weapon_projectile_speed
	if weapon >= 0 and weapon < speeds.size() and speeds[weapon] == 0:
		_push(Kind.TRACER, now, muzzle, target, 0.0)
	_push(Kind.FLASH, now, muzzle, Vector2.ZERO, flash_px.get(weapon_id, FLASH_DEFAULT_PX))


## [IMPACT, projectile id, x, y, target id or 0, weapon, 0, 0]: a puff where the shell came down.
func _add_impact(snap: MatchSnapshot, at: int, now: int) -> void:
	var events: PackedInt32Array = snap.events
	var weapon_id: StringName = _weapon_id(snap, events[at + 5])
	var landing: Vector2 = ViewScale.milli_to_px_vec(events[at + 2], events[at + 3])
	_push(Kind.PUFF, now, landing, Vector2.ZERO, puff_px.get(weapon_id, PUFF_DEFAULT_PX))


## [DIED, unit id, x, y, type index, owner, 0, 0]: a burst for a vehicle (any armour but
## infantry, a building too) and a fade for infantry.
func _add_death(snap: MatchSnapshot, at: int, now: int) -> void:
	var events: PackedInt32Array = snap.events
	var type: int = events[at + 4]
	var armours: PackedInt32Array = snap.type_armour
	var infantry: bool = (
		type >= 0 and type < armours.size() and armours[type] == World.Armour.INFANTRY
	)
	var place: Vector2 = ViewScale.milli_to_px_vec(events[at + 2], events[at + 3])
	if infantry:
		_push(Kind.FADE, now, place, Vector2.ZERO, FADE_PX)
	else:
		_push(Kind.BURST, now, place, Vector2.ZERO, BURST_PX)


## The id of weapon index `weapon`, or an empty name for one the snapshot has no table row for.
static func _weapon_id(snap: MatchSnapshot, weapon: int) -> StringName:
	if weapon >= 0 and weapon < snap.weapon_ids.size():
		return snap.weapon_ids[weapon]
	return &""


## Takes the next slot of the ring, the oldest once it is full.
func _push(kind: int, now: int, from: Vector2, to: Vector2, size: float) -> void:
	var slot: int = _head
	_head = slot + 1 if slot + 1 < _size else 0
	_count = mini(_count + 1, _size)
	_kind[slot] = kind
	_born[slot] = now
	var at: int = slot * GEO_STRIDE
	_geo[at] = from.x
	_geo[at + 1] = from.y
	_geo[at + 2] = to.x
	_geo[at + 3] = to.y
	_geo[at + 4] = size
	_live_until = maxi(_live_until, now + LIFETIME_MS[kind])


## Plans the lines and the quads of the frame from the ring, oldest effect first so a newer one
## is painted over an older one. Allocates nothing: the plan arrays are sized by the ring.
func _plan() -> void:
	_lines = 0
	_quads = 0
	if _count == 0:
		return
	var now: int = int(clock.call())
	if now >= _live_until:
		_empty()  # Nothing is left alive; later frames skip the scan.
		return
	var unit: float = _dp_px / get_canvas_transform().get_scale().x  # World px per dp.
	var slot: int = _head - _count
	if slot < 0:
		slot += _size
	for _step: int in _count:
		var kind: int = _kind[slot]
		var age: int = maxi(now - _born[slot], 0)
		if age < LIFETIME_MS[kind]:
			_plan_effect(slot, kind, age, unit)
		slot += 1
		if slot == _size:
			slot = 0


## Adds the lines or the quad of the effect in `slot`, `age` ms old, to the plan.
func _plan_effect(slot: int, kind: int, age: int, unit: float) -> void:
	var at: int = slot * GEO_STRIDE
	var x: float = _geo[at]
	var y: float = _geo[at + 1]
	var size: float = _geo[at + 4]
	if kind == Kind.TRACER:
		var fade: float = 1.0 - float(age) / float(LIFETIME_MS[Kind.TRACER])
		var end_x: float = _geo[at + 2]
		var end_y: float = _geo[at + 3]
		var outline: float = (TRACER_DP + FeedbackStyle.OUTLINE_DP) * unit
		_add_line(x, y, end_x, end_y, outline, Color(edge_color, fade * fade))
		_add_line(x, y, end_x, end_y, TRACER_DP * unit, Color(tracer_color, fade))
	elif kind == Kind.FLASH:
		var alpha: float = hold_then_fade(age, FLASH_FULL_MS, LIFETIME_MS[Kind.FLASH])
		_add_quad(REGION_FLASH, x, y, size, alpha)
	elif kind == Kind.PUFF:
		var grow: float = FeedbackStyle.ease_out(float(age) / float(PUFF_GROW_MS))
		var alpha: float = hold_then_fade(age, PUFF_FULL_MS, LIFETIME_MS[Kind.PUFF])
		_add_quad(REGION_PUFF, x, y, size * lerpf(PUFF_GROW_FROM, 1.0, grow), alpha)
	elif kind == Kind.BURST:
		var grow: float = FeedbackStyle.ease_out(float(age) / float(BURST_GROW_MS))
		var alpha: float = hold_then_fade(age, BURST_FULL_MS, LIFETIME_MS[Kind.BURST])
		_add_quad(REGION_BURST, x, y, size * lerpf(BURST_GROW_FROM, 1.0, grow), alpha)
	else:
		var left: float = 1.0 - float(age) / float(LIFETIME_MS[Kind.FADE])
		_add_quad(REGION_PUFF, x, y, size, FADE_ALPHA * left)


func _add_line(x: float, y: float, end_x: float, end_y: float, width: float, color: Color) -> void:
	var at: int = _lines * 4
	_line_points[at] = x
	_line_points[at + 1] = y
	_line_points[at + 2] = end_x
	_line_points[at + 3] = end_y
	_line_width[_lines] = width
	_line_color[_lines] = color
	_lines += 1


## A square quad of side `size` centred on (x, y).
func _add_quad(region: int, x: float, y: float, size: float, alpha: float) -> void:
	var at: int = _quads * 4
	_quad_rect[at] = x - 0.5 * size
	_quad_rect[at + 1] = y - 0.5 * size
	_quad_rect[at + 2] = size
	_quad_rect[at + 3] = size
	_quad_region[_quads] = region
	_quad_alpha[_quads] = alpha
	_quads += 1


func _draw() -> void:
	_drawn_lines = 0
	_drawn_quads = 0
	for index: int in _lines:
		draw_line(line_from(index), line_to(index), line_color(index), line_width(index), true)
		_drawn_lines += 1
	for index: int in _quads:
		var tint: Color = Color(1.0, 1.0, 1.0, _quad_alpha[index])
		draw_texture_rect_region(ATLAS, quad_rect(index), quad_region(index), tint)
		_drawn_quads += 1
