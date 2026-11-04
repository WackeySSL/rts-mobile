class_name FxRing
extends RefCounted
## A ring of puffs in packed arrays (ADR 0029 section 6, plan P148): the damage ring of `AirFx`,
## and the shape the collapse and hit rings of P165 and P166 take, so each adds its ring with one
## line. A puff is a slot of the arrays (its sprite style, birth, spot and look); a style says which
## sprite it is and how it lives (`set_style`). The ring plans one quad per live puff for a frame
## and paints them into a `CanvasItem` that the owner passes, from the one life atlas. It makes no
## object after `setup`, and reads only match time, so a run is the same on every device. A tick
## `compact`s the puffs that have lived out away, so a full ring loses its oldest live puff only
## when it holds nothing else. `draw` has three passes (the glow under all, then the clouds, then
## the flames and sparks), each kind of sprite in one of them (`set_pass`). View only.

const GLOW: int = 0  ## The passes of `draw`.
const CLOUD: int = 1
const FLAME: int = 2
const PASSES: int = 3

var _size: int = 0
var _head: int = 0
var _count: int = 0
var _quads: int = 0
var _planned: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## Quads of the plan, per pass.
var _drawn: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## Quads the last `draw` of each.
# The sprite kinds: first region, frames, anchor and mirror permission of each.
var _regions: Array[Rect2] = []
var _first: PackedInt32Array = PackedInt32Array()
var _frames: PackedInt32Array = PackedInt32Array()
var _anchors: PackedVector2Array = PackedVector2Array()
var _mirror: PackedByteArray = PackedByteArray()
var _pass: PackedByteArray = PackedByteArray()  ## The pass each kind is drawn in.
# The styles: sprite kind, life ms, rise and drift px, growth from and to, alpha, hold ms.
var _s_kind: PackedInt32Array = PackedInt32Array()
var _s_life: PackedFloat32Array = PackedFloat32Array()
var _s_rise: PackedFloat32Array = PackedFloat32Array()
var _s_drift: PackedFloat32Array = PackedFloat32Array()
var _s_from: PackedFloat32Array = PackedFloat32Array()
var _s_to: PackedFloat32Array = PackedFloat32Array()
var _s_alpha: PackedFloat32Array = PackedFloat32Array()
var _s_hold: PackedFloat32Array = PackedFloat32Array()
# The puffs.
var _born: PackedFloat64Array = PackedFloat64Array()  ## Match ms.
var _at: PackedVector2Array = PackedVector2Array()
var _style: PackedByteArray = PackedByteArray()
var _frame: PackedByteArray = PackedByteArray()
var _flip: PackedByteArray = PackedByteArray()
# The plan.
var _q_rect: PackedFloat32Array = PackedFloat32Array()
var _q_kind: PackedByteArray = PackedByteArray()
var _q_frame: PackedByteArray = PackedByteArray()
var _q_flip: PackedByteArray = PackedByteArray()
var _q_alpha: PackedFloat32Array = PackedFloat32Array()


## Takes the sprite `kinds` (names of `LifeRegions`) the ring draws and `styles` styles.
func setup(kinds: Array[StringName], styles: int) -> void:
	for kind: StringName in kinds:
		_first.append(_regions.size())
		_frames.append(LifeRegions.FRAMES[kind])
		_anchors.append(LifeRegions.ANCHOR[kind])
		_mirror.append(1 if LifeRegions.mirrorable(kind) else 0)
		_pass.append(FLAME)
		for frame: int in LifeRegions.FRAMES[kind]:
			_regions.append(Rect2(LifeRegions.region(kind, frame)))
	_s_life.resize(styles)
	_s_rise.resize(styles)
	_s_drift.resize(styles)
	_s_from.resize(styles)
	_s_to.resize(styles)
	_s_alpha.resize(styles)
	_s_hold.resize(styles)
	_s_kind.resize(styles)


## Kind `kind` (an index of `setup`'s list) is drawn in pass `pass_of`.
func set_pass(kind: int, pass_of: int) -> void:
	_pass[kind] = pass_of


## Style `style` is sprite `kind`; a puff lives `life_ms`, rises `rise` px and drifts east `drift`
## px, grows from `grow_from` to `grow_to` times its frame and fades from `alpha`: linearly to 0,
## or, with `hold_ms` above 0, holding `alpha` for `hold_ms` and fading over the rest of its life.
func set_style(
	style: int,
	kind: int,
	life_ms: float,
	rise: float,
	drift: float,
	grow: Vector2,
	alpha: float,
	hold_ms: float
) -> void:
	_s_kind[style] = kind
	_s_life[style] = life_ms
	_s_rise[style] = rise
	_s_drift[style] = drift
	_s_from[style] = grow.x
	_s_to[style] = grow.y
	_s_alpha[style] = alpha
	_s_hold[style] = hold_ms


## Sets the slots of the ring (any change empties it).
func size_to(slots: int) -> void:
	slots = maxi(slots, 0)
	if slots == _size:
		return
	_size = slots
	_born.resize(slots)
	_at.resize(slots)
	_style.resize(slots)
	_frame.resize(slots)
	_flip.resize(slots)
	_q_rect.resize(slots * 4)
	_q_kind.resize(slots)
	_q_frame.resize(slots)
	_q_flip.resize(slots)
	_q_alpha.resize(slots)
	clear()


func clear() -> void:
	_head = 0
	_count = 0
	_quads = 0


## A puff of `style` born at `born_ms` of match time at `spot` (world px, the sprite's anchor).
## `look` picks the frame, and the mirroring when `flip` is -1 and the sprite may be mirrored; a
## `flip` of 0 or 1 sets it (for a sprite that may be mirrored). The newest puff takes the next
## slot, which holds the oldest once the ring is full.
func add(style: int, spot: Vector2, born_ms: float, look: int, flip: int = -1) -> void:
	if _size == 0:
		return
	var kind: int = _s_kind[style]
	_born[_head] = born_ms
	_at[_head] = spot
	_style[_head] = style
	_frame[_head] = look % _frames[kind]
	_flip[_head] = ((look >> 16) if flip < 0 else flip) & _mirror[kind] & 1
	_head = (_head + 1) % _size
	_count = mini(_count + 1, _size)


## Drops the puffs that have lived out by match time `now_ms`, keeping the others in order: call it
## once a tick, at the tick's time, before the tick's births. Allocates nothing.
func compact(now_ms: float) -> void:
	if _count == 0:
		return
	var oldest: int = (_head - _count + _size) % _size
	var kept: int = 0
	for step: int in _count:
		var from: int = (oldest + step) % _size
		var style: int = _style[from]
		if LifeClock.age_ms(now_ms, _born[from]) >= _s_life[style]:
			continue
		var to: int = (oldest + kept) % _size
		if to != from:
			_born[to] = _born[from]
			_at[to] = _at[from]
			_style[to] = style
			_frame[to] = _frame[from]
			_flip[to] = _flip[from]
		kept += 1
	_count = kept
	_head = (oldest + kept) % _size


## The quads of the puffs alive at match time `now_ms`, oldest first. Allocates nothing.
func plan(now_ms: float) -> void:
	_quads = 0
	_planned.fill(0)
	var oldest: int = _head - _count + _size
	for step: int in _count:
		var slot: int = (oldest + step) % _size
		var style: int = _style[slot]
		var span: float = _s_life[style]
		var age: float = LifeClock.age_ms(now_ms, _born[slot])
		if age >= span:
			continue
		var t: float = age / span
		var kind: int = _s_kind[style]
		var grow: float = lerpf(_s_from[style], _s_to[style], t)
		var anchor: Vector2 = _anchors[kind]
		var size: Vector2 = _regions[_first[kind] + _frame[slot]].size * grow
		var at: Vector2 = _at[slot] + Vector2(_s_drift[style] * t, -_s_rise[style] * t)
		var reach: float = anchor.x * grow
		var out: int = _quads * 4
		_q_rect[out] = at.x - ((size.x - reach) if _flip[slot] == 1 else reach)
		_q_rect[out + 1] = at.y - anchor.y * grow
		_q_rect[out + 2] = size.x
		_q_rect[out + 3] = size.y
		_q_kind[_quads] = kind
		_q_frame[_quads] = _frame[slot]
		_q_flip[_quads] = _flip[slot]
		var hold: float = _s_hold[style]
		var fade: float = 1.0 - t
		if hold > 0.0:
			fade = clampf((span - age) / maxf(span - hold, 1.0), 0.0, 1.0)
		_q_alpha[_quads] = _s_alpha[style] * fade
		_planned[_pass[kind]] += 1
		_quads += 1


## Paints the quads of the plan whose sprite is drawn in pass `pass_of` into `item` from `atlas`,
## so the owner can paint every glow before every cloud and every cloud before every flame.
func draw(item: CanvasItem, atlas: Texture2D, pass_of: int) -> void:
	var mirrored: bool = false
	var painted: int = 0
	for index: int in _quads:
		if _pass[_q_kind[index]] != pass_of:
			continue
		var rect: Rect2 = quad_rect(index)
		var color: Color = Color(1.0, 1.0, 1.0, _q_alpha[index])
		var region: Rect2 = _regions[_first[_q_kind[index]] + _q_frame[index]]
		painted += 1
		if _q_flip[index] == 1:  # About the vertical edge of its box: the right edge is the origin.
			item.draw_set_transform(Vector2(rect.end.x, rect.position.y), 0.0, Vector2(-1.0, 1.0))
			item.draw_texture_rect_region(atlas, Rect2(Vector2.ZERO, rect.size), region, color)
			mirrored = true
		else:
			if mirrored:
				item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				mirrored = false
			item.draw_texture_rect_region(atlas, rect, region, color)
	if mirrored:
		item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_drawn[pass_of] = painted


## The puffs in the ring (alive, or not yet compacted away).
func count() -> int:
	return _count


## Quads of the last plan, and quad `index`: its box in world px, sprite kind, frame, mirroring
## and alpha.
func quad_count() -> int:
	return _quads


func quad_rect(index: int) -> Rect2:
	var at: int = index * 4
	return Rect2(_q_rect[at], _q_rect[at + 1], _q_rect[at + 2], _q_rect[at + 3])


func quad_kind(index: int) -> int:
	return _q_kind[index]


## Quads of the last plan in pass `pass_of`, and quads the last `draw` of it painted.
func planned(pass_of: int) -> int:
	return _planned[pass_of]


func drawn(pass_of: int) -> int:
	return _drawn[pass_of]


func quad_flipped(index: int) -> bool:
	return _q_flip[index] == 1


func quad_alpha(index: int) -> float:
	return _q_alpha[index]


## Puff number `index`, oldest first: where and when it was born (match ms) and its style.
func puff_at(index: int) -> Vector2:
	return _at[_slot(index)]


func puff_born(index: int) -> float:
	return _born[_slot(index)]


func puff_style(index: int) -> int:
	return _style[_slot(index)]


func _slot(index: int) -> int:
	return (_head - _count + _size + index) % _size
