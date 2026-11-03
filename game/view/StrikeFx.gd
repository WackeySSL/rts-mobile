class_name StrikeFx
extends Node2D
## The launch and the fall of the superweapons (ADR 0027 sections 3, 6 and 7, plan P141), at
## absolute z 55 (over the effects, under the ghost and the strike marks). A ring of
## `life.strike_slots` slots in packed arrays, one slot a strike, drawn in one `_draw` from the
## strike atlas (quads, and for the net two `draw_multiline` calls). It costs no object per strike
## and allocates nothing per frame. Each strike is read from the `STRIKE` event of a tick:
## - Launch: at a building the local player is shown (`BuildingLayer.is_shown`) the Deep Bore's
##   lance (kind 1) or the Blackout Array's light seed (kind 2) rises from the building's launch
##   point for `launch_ms` and fades, with a flash; the point is the sheet's `launch` emitter, else
##   the footprint centre lifted by the building's rise.
## - The Deep Bore's lance falls onto the point in the last `fall_ms` before the landing tick, for
##   every player (its warning is public, so it shows nothing new), from above the visible top
##   edge of the view, and is gone at the landing tick, where `EffectsLayer` bursts. A rupture whose
##   delay is shorter than `fall_ms` starts its fall at the event and falls shorter.
## - The Blackout Array's net of light falls onto the point, as large as the firing type's
##   `type_strike_radius`, in `net_land_ms`, then settles for `net_settle_ms`. It shows where the
##   local player sees the point's tile, or fired it. The offline glyphs are not touched.
## The effects of a superweapon tell the player something, so `life.reduced` leaves them. The clock
## is match time (`LifeClock`), held so that it never steps back after a pause; a new match
## empties the ring.

## The parts, in the order of `KINDS`.
enum Part {RING, FLASH, CORE, LANCE_UP, LANCE_DOWN, TRAIL, SHADOW, SEED, SEED_TRAIL, GLINT, HEX_LIT}

const DEFAULT_LIFE: LifeSettings = preload("res://data/life_settings.tres")
const Z: int = 55
## The atlas kinds the layer draws, in the order of `Part`.
const KINDS: Array[StringName] = [
	&"launch_ring",
	&"launch_flash",
	&"core_flash",
	&"lance_up",
	&"lance_down",
	&"trail",
	&"shadow",
	&"seed",
	&"seed_trail",
	&"glint",
	&"hex_lit",
]
## Quads one strike can have at once: a launch (3), a fall (3) or the settle of a net (5).
const QUADS_PER_SLOT: int = 8
const CORNERS: int = 4  ## The glints at the net's four extremes.

@export var runner: MatchRunner
@export var camera: RtsCamera
@export var life: LifeSettings
@export var reveal_enemies: bool = false
## Says whether a building is shown to the local player, and where its picture is.
@export var building_layer: BuildingLayer

var _atlas: Texture2D = null
var _regions: Array[Rect2] = []
var _anchors: PackedVector2Array = PackedVector2Array()
var _serial: int = -1
var _size: int = 0
var _clock: float = 0.0  ## Match time, ms: the largest the frames have seen in this match.
## Per slot: what it holds (`Strike.Kind`, NONE when free), the times (ms of match time) of its
## birth, the start and the end of its fall and of its life, whether its launch is shown and its
## fall is, and the points (world px): where it lands, where it launches and the footprint centre.
var _kind: PackedByteArray = PackedByteArray()
var _born_ms: PackedFloat64Array = PackedFloat64Array()
var _from_ms: PackedFloat64Array = PackedFloat64Array()
var _land_ms: PackedFloat64Array = PackedFloat64Array()
var _end_ms: PackedFloat64Array = PackedFloat64Array()
var _launched: PackedByteArray = PackedByteArray()
var _falls: PackedByteArray = PackedByteArray()
var _point: PackedVector2Array = PackedVector2Array()
var _launch: PackedVector2Array = PackedVector2Array()
var _ground: PackedVector2Array = PackedVector2Array()
var _ellipse: PackedVector2Array = PackedVector2Array()  ## A net's semi-axes, px.
## The net's lines, relative to its centre: segment after segment, built once for a radius.
var _lattice: PackedVector2Array = PackedVector2Array()
var _lattice_axes: Vector2 = Vector2.ZERO
## The frame's plan: quads (dst rect at 4i, part, alpha) and nets (centre, scale, alpha).
var _quad_rect: PackedFloat32Array = PackedFloat32Array()
var _quad_part: PackedByteArray = PackedByteArray()
var _quad_alpha: PackedFloat32Array = PackedFloat32Array()
var _quads: int = 0
var _drawn_quads: int = 0
var _net_at: PackedVector2Array = PackedVector2Array()
var _net_scale: PackedFloat32Array = PackedFloat32Array()
var _net_alpha: PackedFloat32Array = PackedFloat32Array()
var _nets: int = 0


func _init() -> void:
	z_index = Z
	z_as_relative = false


func _ready() -> void:
	if life == null:
		life = DEFAULT_LIFE
	_atlas = load(LifeRegions.texture_path(&"lance_down")) as Texture2D
	for kind: StringName in KINDS:
		_regions.append(Rect2(LifeRegions.region(kind)))
		_anchors.append(LifeRegions.ANCHOR[kind])
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	var had_plan: bool = _quads > 0 or _nets > 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	_follow_match(snap)
	_make_slots_if_resized()
	_plan(snap)
	if had_plan or _quads > 0 or _nets > 0:
		queue_redraw()


func _draw() -> void:
	_drawn_quads = _quads
	for net: int in _nets if _lattice.size() >= 2 else 0:
		var scale_by: float = _net_scale[net]
		draw_set_transform(_net_at[net], 0.0, Vector2(scale_by, scale_by))
		var edge: Color = Color(LifeRegions.NET_EDGE, _net_alpha[net])
		draw_multiline(_lattice, edge, LifeRegions.NET_EDGE_PX / scale_by)
		var light: Color = Color(LifeRegions.NET_LIGHT, _net_alpha[net])
		draw_multiline(_lattice, light, LifeRegions.NET_LIGHT_PX / scale_by)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for index: int in _quads:
		draw_texture_rect_region(
			_atlas,
			quad_rect(index),
			_regions[_quad_part[index]],
			Color(1, 1, 1, _quad_alpha[index])
		)


## Strikes in the ring, alive or not yet freed by a frame.
func slot_count() -> int:
	var live: int = 0
	for slot: int in _size:
		live += 1 if _kind[slot] != Strike.Kind.NONE else 0
	return live


func quad_count() -> int:
	return _quads


func drawn_quads() -> int:
	return _drawn_quads


## Quad `index` of the plan: where it is drawn in world px; `quad_part` is an index of `KINDS`.
func quad_rect(index: int) -> Rect2:
	var at: int = index * 4
	return Rect2(_quad_rect[at], _quad_rect[at + 1], _quad_rect[at + 2], _quad_rect[at + 3])


func quad_part(index: int) -> int:
	return _quad_part[index]


func quad_alpha(index: int) -> float:
	return _quad_alpha[index]


## Nets of the plan, each with its centre, scale and alpha, and the segments of the lattice.
func net_count() -> int:
	return _nets


func net_at(index: int) -> Vector2:
	return _net_at[index]


func net_scale(index: int) -> float:
	return _net_scale[index]


func net_alpha(index: int) -> float:
	return _net_alpha[index]


func lattice_size() -> int:
	return _lattice.size()


## Where slot `slot`'s strike launches and lands (world px), and the ms its fall runs between.
func launch_point(slot: int) -> Vector2:
	return _launch[slot]


func landing_point(slot: int) -> Vector2:
	return _point[slot]


func fall_span(slot: int) -> Vector2:
	return Vector2(_from_ms[slot], _land_ms[slot])


func texture() -> Texture2D:
	return _atlas


func _follow_match(snap: MatchSnapshot) -> void:
	if snap.match_serial != _serial:
		_serial = snap.match_serial
		_clock = 0.0
		_empty()


func _empty() -> void:
	_kind.fill(Strike.Kind.NONE)
	_quads = 0
	_nets = 0


func _make_slots_if_resized() -> void:
	var want: int = maxi(life.strike_slots, 0)
	if want == _size:
		return
	_size = want
	_kind.resize(want)
	_born_ms.resize(want)
	_from_ms.resize(want)
	_land_ms.resize(want)
	_end_ms.resize(want)
	_launched.resize(want)
	_falls.resize(want)
	_point.resize(want)
	_launch.resize(want)
	_ground.resize(want)
	_ellipse.resize(want)
	_quad_rect.resize(want * QUADS_PER_SLOT * 4)
	_quad_part.resize(want * QUADS_PER_SLOT)
	_quad_alpha.resize(want * QUADS_PER_SLOT)
	_net_at.resize(want)
	_net_scale.resize(want)
	_net_alpha.resize(want)
	_empty()


## One tick: a strike for each `STRIKE` record.
func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or life == null:
		return
	_follow_match(snap)
	_make_slots_if_resized()
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.STRIKE:
			_add_strike(snap, at)


## The record at `at`: `[STRIKE, building id, x, y, kind, owner, landing tick, 0]`. A strike with
## nothing to show (a launch at a building out of sight and a net on a dark tile) takes no slot.
func _add_strike(snap: MatchSnapshot, at: int) -> void:
	var events: PackedInt32Array = snap.events
	var kind: int = events[at + 4]
	if _size == 0 or (kind != Strike.Kind.RUPTURE and kind != Strike.Kind.BLACKOUT):
		return
	var row: int = snap.index_of(events[at + 1])
	var launched: bool = row >= 0 and building_layer != null and building_layer.is_shown(row)
	var born: float = LifeClock.tick_ms(snap.tick)
	var land: float = born
	var from: float = born
	var falls: bool = true
	var axes: Vector2 = Vector2.ZERO
	if kind == Strike.Kind.RUPTURE:
		land = LifeClock.tick_ms(events[at + 6])
		from = maxf(land - float(life.fall_ms), born)  # Never earlier than the event.
	else:
		land = born + float(life.net_land_ms)
		var seen: bool = (
			reveal_enemies
			or events[at + 5] == FogLayer.local_player_of(runner)
			or FogLayer.is_seen(
				snap, FogLayer.local_player_of(runner), events[at + 2], events[at + 3]
			)
		)
		falls = seen
		axes = IsoProjection.ellipse_px(_radius_of(snap, row))
	if not launched and not falls:
		return
	var slot: int = _take_slot()
	var ground: Vector2 = IsoProjection.ground_to_px(events[at + 2], events[at + 3])
	_kind[slot] = kind
	_born_ms[slot] = born
	_from_ms[slot] = from
	_land_ms[slot] = land
	_launched[slot] = 1 if launched else 0
	_falls[slot] = 1 if falls else 0
	_point[slot] = ground
	_ellipse[slot] = axes
	var end: float = land + (float(life.net_settle_ms) if kind == Strike.Kind.BLACKOUT else 0.0)
	if launched:
		_launch[slot] = _launch_point(snap, row)
		_ground[slot] = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		end = maxf(end, born + float(life.launch_ms))
	_end_ms[slot] = end
	if axes.x > 0.0 and falls and axes != _lattice_axes:
		_build_lattice(axes)


## The first free slot, else the one whose strike is oldest.
func _take_slot() -> int:
	var oldest: int = 0
	for slot: int in _size:
		if _kind[slot] == Strike.Kind.NONE:
			return slot
		if _born_ms[slot] < _born_ms[oldest]:
			oldest = slot
	return oldest


## The radius of the firing building's type, else of the first type of the blackout kind.
func _radius_of(snap: MatchSnapshot, row: int) -> int:
	if row >= 0:
		return snap.type_strike_radius[snap.type_index[row]]
	for type: int in snap.type_strike_kind.size():
		if snap.type_strike_kind[type] == Strike.Kind.BLACKOUT:
			return snap.type_strike_radius[type]
	return 0


## Where the strike leaves building row `row`, world px: the sheet's `launch` emitter, else the
## top of its picture over the footprint centre (the centre lifted by the building's rise).
func _launch_point(snap: MatchSnapshot, row: int) -> Vector2:
	var centre: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
	var sheet: IsoSheetDef = building_layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
	var index: int = sheet.emitters.find("launch") if sheet != null else -1
	if index >= 0:
		return centre + sheet.emitter_point(index, -1) * WorldSort.ART_SCALE
	var box: Rect2 = building_layer.frame_box(row)
	return centre - Vector2(0.0, centre.y - box.position.y if box.size != Vector2.ZERO else 0.0)


## The lines of a net of semi-axes `axes`: flat-topped hexagons on `LifeRegions`' lattice whose
## centre lies in the ellipse, three edges of each (the top and the two on the left; the others
## belong to the neighbours). Built when the radius changes, never in a frame.
func _build_lattice(axes: Vector2) -> void:
	_lattice_axes = axes
	_lattice.clear()
	var high: float = LifeRegions.NET_SHIFT_PX  # Half the hexagon's height.
	var cols: int = int(axes.x / LifeRegions.NET_COLUMN_PX) + 1
	var rows: int = int(axes.y / LifeRegions.NET_ROW_PX) + 1
	for col: int in range(-cols, cols + 1):
		var x: float = float(col) * LifeRegions.NET_COLUMN_PX
		var shift: float = LifeRegions.NET_SHIFT_PX if (col & 1) == 1 else 0.0
		for row: int in range(-rows, rows + 1):
			var y: float = float(row) * LifeRegions.NET_ROW_PX + shift
			if (x * x) / (axes.x * axes.x) + (y * y) / (axes.y * axes.y) > 1.0:
				continue
			var upper_left: Vector2 = Vector2(x - 8.0, y - high)
			var upper_right: Vector2 = Vector2(x + 8.0, y - high)
			var left: Vector2 = Vector2(x - 16.0, y)
			(
				_lattice
				. append_array(
					PackedVector2Array(
						[
							upper_left,
							upper_right,
							left,
							upper_left,
							left,
							Vector2(x - 8.0, y + high),
						]
					)
				)
			)


## The quads and nets of the strikes alive at the frame's match time. Allocates nothing.
func _plan(snap: MatchSnapshot) -> void:
	_quads = 0
	_nets = 0
	_clock = maxf(_clock, LifeClock.ms(snap, runner.alpha()))
	var top: float = camera.visible_world_rect().position.y if camera != null else 0.0
	for slot: int in _size:
		if _kind[slot] == Strike.Kind.NONE:
			continue
		if _clock >= _end_ms[slot]:
			_kind[slot] = Strike.Kind.NONE
			continue
		if _launched[slot] == 1:
			_plan_launch(slot)
		if _falls[slot] == 1:
			_plan_fall(slot, top)


## The rise at the building: the lance (or the seed) goes up and fades, a flash at the launch
## point and, for the lance, a ring of dust on the ground.
func _plan_launch(slot: int) -> void:
	var age: float = LifeClock.age_ms(_clock, _born_ms[slot])
	var span: float = float(life.launch_ms)
	if span <= 0.0 or age >= span:
		return
	var u: float = age / span
	var fade: float = 1.0 - u * u
	var flash: float = clampf(1.0 - age / float(maxi(life.launch_flash_ms, 1)), 0.0, 1.0)
	var at: Vector2 = _launch[slot]
	var tip: Vector2 = at - Vector2(0.0, life.strike_rise_px * (1.0 - (1.0 - u) * (1.0 - u)))
	if _kind[slot] == Strike.Kind.RUPTURE:
		_quad(Part.RING, _ground[slot], Vector2.ONE * (1.0 + u), 1.0 - u)
		_quad(Part.FLASH, at, Vector2.ONE, flash)
		_quad(Part.LANCE_UP, tip, Vector2.ONE, fade)
	else:
		_quad(Part.CORE, at, Vector2.ONE, flash)
		var stretch: float = lerpf(1.0, LifeRegions.MAX_STRETCH[&"seed_trail"], u)
		_quad(Part.SEED_TRAIL, tip, Vector2(1.0, stretch), fade)
		_quad(Part.SEED, tip, Vector2.ONE, fade)


## The fall from the sky onto the point, then (a net) its settling. The fall starts above `top`,
## the visible top edge, and ends at the landing time, when it is gone.
func _plan_fall(slot: int, top: float) -> void:
	var land: float = _land_ms[slot]
	var from: float = _from_ms[slot]
	var point: Vector2 = _point[slot]
	if _clock >= land:
		if _kind[slot] == Strike.Kind.BLACKOUT:
			_plan_settle(slot, (_clock - land) / float(maxi(life.net_settle_ms, 1)))
		return
	if _clock < from:
		return
	var t: float = (_clock - from) / (land - from)
	var eased: float = t * t  # It falls faster as it comes.
	if _kind[slot] == Strike.Kind.RUPTURE:
		var below: float = _regions[Part.LANCE_DOWN].size.y - _anchors[Part.LANCE_DOWN].y
		var tip: Vector2 = Vector2(point.x, lerpf(minf(top, point.y) - below, point.y, eased))
		var join: Vector2 = tip + LifeRegions.JOIN[&"lance_down"] - _anchors[Part.LANCE_DOWN]
		var stretch: float = lerpf(1.0, LifeRegions.MAX_STRETCH[&"trail"], t)
		_quad(
			Part.SHADOW, point, Vector2.ONE * lerpf(life.shadow_from, 1.0, t), life.shadow_alpha * t
		)
		_quad(Part.TRAIL, join, Vector2(1.0, stretch), 1.0)
		_quad(Part.LANCE_DOWN, tip, Vector2.ONE, 1.0)
	else:
		var big: float = life.net_scale_from
		var reach: float = _ellipse[slot].y * big + LifeRegions.NET_ROW_PX
		var centre: Vector2 = Vector2(point.x, lerpf(minf(top, point.y) - reach, point.y, eased))
		_net(centre, lerpf(big, 1.0, eased), life.net_alpha * t)


## The net after it landed: it fades where it lies, with the landing flash and a glint at each of
## its four extremes.
func _plan_settle(slot: int, s: float) -> void:
	if s >= 1.0:
		return
	var point: Vector2 = _point[slot]
	var axes: Vector2 = _ellipse[slot]
	var left: float = 1.0 - s
	_net(point, 1.0, life.net_alpha * left)
	_quad(Part.HEX_LIT, point, Vector2.ONE, left)
	for corner: int in CORNERS:
		var sign_of: float = 1.0 if corner % 2 == 0 else -1.0
		var off: Vector2 = (
			Vector2(axes.x * sign_of, 0.0) if corner < 2 else Vector2(0.0, axes.y * sign_of)
		)
		_quad(Part.GLINT, point + off, Vector2.ONE, left)


func _net(at: Vector2, scale_by: float, alpha: float) -> void:
	_net_at[_nets] = at
	_net_scale[_nets] = scale_by
	_net_alpha[_nets] = alpha
	_nets += 1


## One quad of part `part` with its anchor on `at`, its size scaled by `scale_by`.
func _quad(part: int, at: Vector2, scale_by: Vector2, alpha: float) -> void:
	if _quads >= _size * QUADS_PER_SLOT:
		return
	var corner: Vector2 = at - _anchors[part] * scale_by
	var size: Vector2 = _regions[part].size * scale_by
	var out: int = _quads * 4
	_quad_rect[out] = corner.x
	_quad_rect[out + 1] = corner.y
	_quad_rect[out + 2] = size.x
	_quad_rect[out + 3] = size.y
	_quad_part[_quads] = part
	_quad_alpha[_quads] = alpha
	_quads += 1
