class_name FxRing
extends RefCounted
## A ring of puffs in packed arrays (ADR 0029 section 6, plan P148): the damage ring of `AirFx`,
## and the shape the collapse and hit rings of P165 and P166 take, so each adds its ring with one
## line. A puff is a slot of the arrays (its sprite style, birth, spot and look); a style says which
## sprite it is and how it lives (`set_style`). The ring plans one quad per live puff for a frame
## and paints them into a `CanvasItem` that the owner passes, from the one life atlas. It makes no
## object after `setup`, overwrites its oldest puff when full, and reads only match time, so a run
## is the same on every device. View only.

## The sprite kind (an index of `setup`'s list) that `draw` paints in the glow pass.
var glow_kind: int = -1

var _size: int = 0
var _head: int = 0
var _count: int = 0
var _quads: int = 0
# The sprite kinds: first region, frames, anchor and mirror permission of each.
var _regions: Array[Rect2] = []
var _first: PackedInt32Array = PackedInt32Array()
var _frames: PackedInt32Array = PackedInt32Array()
var _anchors: PackedVector2Array = PackedVector2Array()
var _mirror: PackedByteArray = PackedByteArray()
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
func resize(slots: int) -> void:
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


## The quads of the puffs alive at match time `now_ms`, oldest first. Allocates nothing.
func plan(now_ms: float) -> void:
	_quads = 0
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
		_quads += 1


## Paints the plan into `item` from `atlas`: only the glow kind when `glow` is set, only the other
## kinds when not, so the owner can paint every glow before every other quad.
func draw(item: CanvasItem, atlas: Texture2D, glow: bool) -> void:
	var mirrored: bool = false
	for index: int in _quads:
		if (_q_kind[index] == glow_kind) != glow:
			continue
		var rect: Rect2 = quad_rect(index)
		var color: Color = Color(1.0, 1.0, 1.0, _q_alpha[index])
		var region: Rect2 = _regions[_first[_q_kind[index]] + _q_frame[index]]
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


## Slots of the ring, and the puffs in them (alive or not yet overwritten).
func capacity() -> int:
	return _size


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


func quad_frame(index: int) -> int:
	return _q_frame[index]


func quad_flipped(index: int) -> bool:
	return _q_flip[index] == 1


func quad_alpha(index: int) -> float:
	return _q_alpha[index]


## Puff in slot `slot`: where and when it was born (match ms) and its style.
func puff_at(slot: int) -> Vector2:
	return _at[slot]


func puff_born(slot: int) -> float:
	return _born[slot]


func puff_style(slot: int) -> int:
	return _style[slot]
