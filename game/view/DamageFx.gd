class_name DamageFx
extends RefCounted
## The damage particles of `AirFx` (ADR 0029 section 6, ADR 0028 section 6, plan P148): which
## damaged building or vehicle puffs what, into the `FxRing` of 80 slots (`life.damage_slots`). A
## shown, complete building at SKADET burns the one of its damage points that `LifeClock.pick`
## names, with grey `smoke` and by the point's type a small `fire` and a weak `glow` (`damage`), a
## `jet` and a weak `glow` (`dmg_gas`) or sparks and no fire (`dmg_spark`); at KRITISK it burns that
## point and the next ones, up to `damage_burning_points[1]`, with black `soot`, a large `fire` and
## a strong `glow` (`damage`, `dmg_gas`; a `jet` only ever at SKADET) and sparks at every one of
## them. A shown vehicle trails `exhaust` from its hull frame's `damage` point at stage 1, at stage
## 2 `soot`, a small `fire` and sparks, born where its rig is drawn and left in the world. A crater
## (`add_crater`, called by the collapse) smokes and glows with embers where the building stood. A
## puff is born when the cycle of its kind turns over, from a phase of its own per building, point
## and kind (`LifeClock.pick`), so a run is the same on every device. Sites, squads and sources
## outside the view rect grown by a tile emit nothing; a blackout does not stop a fire. `reduced`
## keeps smoke, fire and glow and drops sparks, embers and the crater's smoke. A glow is steady: one
## per burning point, and the flame it lights is born with it: a point has a grid of `span` ticks
## (`ceil(damage_emit_ms[fire] x 15 / 1000)`, 8) with a phase of its own, and on every grid tick the
## fire (or the jet, at a gas point: it takes the fire's cycle at both stages, so the SKADET and the
## KRITISK glow follow each other with no gap and no overlap) and its glow are born together; a glow
## lives exactly `span` ticks and a flame holds its alpha as long. A crater's embers ride the grid
## of the ember's rate with the faint glow.

## The styles of the ring's puffs (a sprite and how it lives), and the sprite kinds.
enum Style {
	SMOKE,
	SOOT,
	FIRE,
	FIRE_BIG,
	FIRE_CAR,
	JET,
	SPARK,
	EMBER,
	GLOW_WEAK,
	GLOW_STRONG,
	GLOW_JET,
	GLOW_FAINT,
	TRAIL,
	CRATER_SMOKE,
}
const KINDS: Array[StringName] = [
	&"smoke", &"soot", &"fire", &"spark", &"jet", &"ember", &"glow", &"exhaust"
]
const K_SMOKE: int = 0
const K_SOOT: int = 1
const K_FIRE: int = 2
const K_SPARK: int = 3
const K_JET: int = 4
const K_EMBER: int = 5
const K_GLOW: int = 6
const K_EXHAUST: int = 7
## The typed damage points of a building's sheet, in the order of the codes.
const POINTS: Array[StringName] = [&"damage", &"dmg_gas", &"dmg_spark"]
const GAS: int = 1
const SPARKS: int = 2
const MAX_POINTS: int = 4  ## Damage points of a building (the generator allows 2 to 4).
const VEHICLE_POINT: StringName = &"damage"
## Salts of `LifeClock`: the burning point, a puff's phase and its look; far
## from the other life layers' (RigLife 0x1.. to 0x3.., dust 0x4.., animations 0x5.., AirFx 0x6..).
const SALT_BURN: int = 0x70000000
const SALT_PHASE: int = 0x71000000
const SALT_LOOK: int = 0x72000000

var ring: FxRing = FxRing.new()
var _first: PackedInt32Array = PackedInt32Array()  ## Per type: its points are _first[t] to [t + 1].
var _p_type: PackedByteArray = PackedByteArray()
var _p_at: PackedVector2Array = PackedVector2Array()  ## World px from the footprint centre.
var _veh: PackedInt32Array = PackedInt32Array()  ## Per type: a vehicle's point (emitter index).
var _sheets: Array[IsoSheetDef] = []
var _every: PackedInt32Array = PackedInt32Array()  ## Per Style: the ms between births.
var _emit_ms: Dictionary[StringName, int] = {}
var _life_ms: Dictionary[StringName, int] = {}
var _glow_ticks: PackedInt32Array = PackedInt32Array()  ## Per Style: ticks a glow lives, 0 if none.
# The crater sources: a ring of `_c_cap` with up to MAX_POINTS ground offsets each.
var _c_cap: int = 0
var _c_next: int = 0  ## The number of the newest source.
var _c_seq: PackedInt32Array = PackedInt32Array()  ## Per slot: the number of its source.
var _c_id: PackedInt32Array = PackedInt32Array()
var _c_start: PackedInt32Array = PackedInt32Array()
var _c_owner: PackedInt32Array = PackedInt32Array()
var _c_foot: PackedInt32Array = PackedInt32Array()  ## x, y, w, h of the footprint, tiles.
var _c_at: PackedVector2Array = PackedVector2Array()
var _c_n: PackedByteArray = PackedByteArray()  ## Points of the source; 0 for a free slot.
var _c_off: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	ring.setup(KINDS, Style.size())
	ring.set_pass(K_GLOW, FxRing.GLOW)
	for kind: int in [K_SMOKE, K_SOOT, K_EXHAUST]:
		ring.set_pass(kind, FxRing.CLOUD)  # Under the fire, which they would otherwise cover.
	_every.resize(Style.size())
	_glow_ticks.resize(Style.size())


## Empties the ring and ends every crater source.
func clear() -> void:
	ring.clear()
	end_craters()


## Ends every crater source (a new match).
func end_craters() -> void:
	_c_n.fill(0)


## The tables of the damage points of every type's sheet: for a building its `damage`, `dmg_gas`
## and `dmg_spark` points, for a vehicle the emitter of its `damage` point.
func build(snap: MatchSnapshot, sort: WorldSort) -> void:
	_first.clear()
	_p_type.clear()
	_p_at.clear()
	_veh.clear()
	_sheets.clear()
	for type: int in snap.type_ids.size():
		_first.append(_p_type.size())
		_veh.append(-1)
		var sheet: IsoSheetDef = sort.sheet(snap.type_ids[type])
		_sheets.append(sheet)
		if sheet == null:
			continue
		if not WorldSort.is_building(snap, type):
			if not sheet.counts.is_empty() and sheet.counts[0] == UnitLayer.DIRECTIONS:
				_veh[type] = sheet.emitters.find(String(VEHICLE_POINT))  # Not a squad.
			continue
		for index: int in sheet.emitters.size():
			var code: int = POINTS.find(StringName(sheet.emitters[index]))
			if code >= 0 and _p_type.size() - _first[type] < MAX_POINTS:
				_p_type.append(code)
				_p_at.append(sheet.emitter_point(index, -1) * WorldSort.ART_SCALE)
	_first.append(_p_type.size())


## Starts a crater source of building `id` at `centre` (world px) from tick `tick`, over the
## footprint `foot` (tiles) of player `owner`, for a building of type index `type`: it smokes for
## `crater_smoke_ms` and glows with embers for `crater_ember_ms` from the type's damage points at
## ground height. A sheet's point is a screen offset from the footprint centre (art px, no height
## of its own), so the ground point keeps its x and takes the footprint centre line (y 0): the
## smoke rises from the crater, not from the air where the walls were. A type without points (or
## none known) uses the centre. At most `crater_sources` live; the oldest ends first. Allocates
## nothing.
func add_crater(
	life: LifeSettings, id: int, centre: Vector2, type: int, foot: Rect2i, owner: int, tick: int
) -> void:
	var slot: int = _take_crater(life, id, centre, foot, owner, tick)
	if slot < 0:
		return
	var from: int = 0
	var points: int = 0
	if type >= 0 and type + 1 < _first.size():
		from = _first[type]
		points = _first[type + 1] - from
	_c_n[slot] = maxi(points, 1)
	for k: int in MAX_POINTS:
		_c_off[slot * MAX_POINTS + k] = (
			Vector2(_p_at[from + k].x, 0.0) if k < points else Vector2.ZERO
		)


## The same with the offsets from `centre` given (none: the centre): a crafted source.
func add_crater_offsets(
	life: LifeSettings,
	id: int,
	centre: Vector2,
	offsets: PackedVector2Array,
	foot: Rect2i,
	owner: int,
	tick: int
) -> void:
	var slot: int = _take_crater(life, id, centre, foot, owner, tick)
	if slot < 0:
		return
	_c_n[slot] = clampi(offsets.size(), 1, MAX_POINTS)
	for k: int in MAX_POINTS:
		_c_off[slot * MAX_POINTS + k] = offsets[k] if k < offsets.size() else Vector2.ZERO


## Ends every live crater source whose footprint meets `foot` (tiles): a building was placed on it.
## Their puffs live out. Births stop from the call on: P165 calls it before `AirFx` emits for the
## tick (before its `ticked` handler), so a source stops in that tick.
func end_craters_on(foot: Rect2i) -> void:
	for slot: int in _c_cap:
		var at: int = slot * 4
		var theirs: Rect2i = Rect2i(_c_foot[at], _c_foot[at + 1], _c_foot[at + 2], _c_foot[at + 3])
		if _c_n[slot] > 0 and theirs.intersects(foot):
			_c_n[slot] = 0


# The slot of a new source, the oldest's when full; -1 without slots.
func _take_crater(
	life: LifeSettings, id: int, centre: Vector2, foot: Rect2i, owner: int, tick: int
) -> int:
	_make_craters_if_resized(life)
	if _c_cap == 0:
		return -1
	var slot: int = 0  # A free slot, else the oldest source's (the lowest number).
	for at: int in _c_cap:
		if _c_n[at] == 0:
			slot = at
			break
		if _c_seq[at] < _c_seq[slot]:
			slot = at
	_c_next += 1
	_c_seq[slot] = _c_next
	_c_id[slot] = id
	_c_start[slot] = tick
	_c_owner[slot] = owner
	_c_foot[slot * 4] = foot.position.x
	_c_foot[slot * 4 + 1] = foot.position.y
	_c_foot[slot * 4 + 2] = foot.size.x
	_c_foot[slot * 4 + 3] = foot.size.y
	_c_at[slot] = centre
	return slot


## The crater sources alive.
func crater_count() -> int:
	var found: int = 0
	for slot: int in _c_cap:
		found += 1 if _c_n[slot] > 0 else 0
	return found


## Takes the rates and the looks of the styles from `life`: the ring's size, each style's sprite,
## life, motion, growth and alpha. Called once a tick.
func read(life: LifeSettings) -> void:
	ring.size_to(life.damage_slots)
	_emit_ms = life.damage_emit_ms
	_life_ms = life.damage_life_ms
	var grown: Vector2 = Vector2(life.emit_grow_from, life.emit_grow_to)
	var flame: Vector2 = Vector2(life.emit_flame_from, life.emit_flame_to)
	var a: float = life.emit_alpha
	var rise: float = life.damage_rise_px
	var drift: float = life.emit_drift_px
	var big: float = life.damage_fire_scale
	var one: Vector2 = Vector2.ONE
	_style(Style.SMOKE, K_SMOKE, &"smoke", Vector2(rise, drift), grown, a, false)
	_style(Style.SOOT, K_SOOT, &"soot", Vector2(rise, drift), grown, a, false)
	_style(Style.CRATER_SMOKE, K_SMOKE, &"crater_smoke", Vector2(rise, drift), grown, a, false)
	_style(Style.TRAIL, K_EXHAUST, &"exhaust", Vector2(rise, drift), grown, a, false)
	_style(Style.FIRE, K_FIRE, &"fire", Vector2.ZERO, flame, a, true, &"fire")
	_style(Style.FIRE_BIG, K_FIRE, &"fire", Vector2.ZERO, flame * big, a, true, &"fire")
	_style(
		Style.FIRE_CAR,
		K_FIRE,
		&"fire",
		Vector2.ZERO,
		flame * life.damage_vehicle_fire_scale,
		a,
		true
	)
	_style(Style.JET, K_JET, &"jet", Vector2.ZERO, flame, a, true, &"fire")
	_style(Style.SPARK, K_SPARK, &"spark", Vector2(life.damage_spark_rise_px, drift), one, a, false)
	_style(Style.EMBER, K_EMBER, &"ember", Vector2.ZERO, one, a, false)
	_glow(Style.GLOW_WEAK, &"fire", one, life.glow_weak_alpha)
	_glow(Style.GLOW_STRONG, &"fire", one * big, life.glow_strong_alpha)
	_glow(Style.GLOW_JET, &"fire", one, life.glow_weak_alpha)
	_glow(Style.GLOW_FAINT, &"ember", one, life.glow_faint_alpha)


## One tick `tick`: births at every damaged source the player can see.
func emit(
	snap: MatchSnapshot,
	view: Rect2,
	life: LifeSettings,
	buildings: BuildingLayer,
	units: UnitLayer,
	world_to_local: Transform2D,
	local: int
) -> void:
	var types: PackedInt32Array = snap.type_index
	var ids: PackedInt32Array = snap.unit_id
	var building_lines: PackedInt32Array = life.building_stage_percent
	var vehicle_lines: PackedInt32Array = life.vehicle_stage_percent
	ring.compact(LifeClock.tick_ms(snap.tick))  # The puffs that lived out give their slots back.
	if units != null:
		units.sync_rows()
	for row: int in ids.size():
		var type: int = types[row]
		var first: int = _first[type]
		var points: int = _first[type + 1] - first
		if (points == 0 and (_veh[type] < 0 or units == null)) or snap.build_left[row] != 0:
			continue
		var stage: int = BuildingDamage.stage_of(
			snap.hp[row], snap.type_max_hp[type], building_lines if points > 0 else vehicle_lines
		)
		if stage == 0:
			continue
		if points > 0:
			if buildings.is_shown(row):
				var centre: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
				_burn(ids[row], centre, first, points, stage, life, view, snap.tick)
		elif units.is_shown(row):
			_drive(snap, row, type, stage, life, view, world_to_local, units)
	_craters(snap, life, view, buildings, local)


# A building: the burning points of its stage.
func _burn(
	id: int,
	centre: Vector2,
	first: int,
	points: int,
	stage: int,
	life: LifeSettings,
	view: Rect2,
	tick: int
) -> void:
	var start: int = LifeClock.pick(id, SALT_BURN, points)
	var burning: int = mini(life.damage_burning_points[stage - 1], points)
	var reduced: bool = life.reduced
	for k: int in burning:
		var point: int = (start + k) % points
		var spot: Vector2 = centre + _p_at[first + point]
		if not view.has_point(spot):
			continue
		var code: int = _p_type[first + point]
		var kinds: int = point * 8
		if stage == 1:
			_cloud(Style.SMOKE, id, spot, tick, kinds)
			if code == GAS:
				var side: int = 1 if _p_at[first + point].x < 0.0 else 0  # Points away from the wall.
				if _on_grid(Style.GLOW_JET, id, tick, kinds + 1):
					_birth(Style.JET, spot, tick, id, side)
					_birth(Style.GLOW_JET, spot, tick, id, 0)
			elif code != SPARKS:
				_flame(Style.FIRE, Style.GLOW_WEAK, id, spot, tick, kinds + 1)
		else:
			_cloud(Style.SOOT, id, spot, tick, kinds)
			if code != SPARKS:
				_flame(Style.FIRE_BIG, Style.GLOW_STRONG, id, spot, tick, kinds + 1)
		if (stage == 2 or code == SPARKS) and not reduced:
			_cloud(Style.SPARK, id, spot, tick, kinds + 2)


# A vehicle: its hull frame's damage point, at the rig's drawn place.
func _drive(
	snap: MatchSnapshot,
	row: int,
	type: int,
	stage: int,
	life: LifeSettings,
	view: Rect2,
	world_to_local: Transform2D,
	units: UnitLayer
) -> void:
	var sheet: IsoSheetDef = _sheets[type]
	var rig: Node2D = units.rig(row)
	var base: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
	if rig != null:
		base = world_to_local * rig.global_position
	var dir: int = UnitLayer.frame_of(units.heading(row), sheet.counts[0])
	var spot: Vector2 = base + sheet.emitter_point(_veh[type], dir) * WorldSort.ART_SCALE
	if not view.has_point(spot):
		return
	var id: int = snap.unit_id[row]
	if stage == 1:
		_cloud(Style.TRAIL, id, spot, snap.tick, 0)
		return
	_cloud(Style.SOOT, id, spot, snap.tick, 0)
	if _due(Style.FIRE, id, 1, snap.tick):
		_birth(Style.FIRE_CAR, spot, snap.tick, id, -1)
	if not life.reduced:
		_cloud(Style.SPARK, id, spot, snap.tick, 2)


# The whole ticks of a cycle of `every` ms, rounded up; 0 for no cycle.
@warning_ignore("integer_division")
func _ticks(every: int) -> int:
	return (every * Sim.TICK_RATE + 999) / 1000 if every > 0 else 0


# Sets glow style `style`: a steady glow of `named`'s rate, living the whole ticks of one cycle.
func _glow(style: int, named: StringName, grow: Vector2, a: float) -> void:
	var span: int = _ticks(_emit_ms.get(named, 0))
	_glow_ticks[style] = span
	var life_ms: float = LifeClock.tick_ms(span) - 0.01  # Gone in the tick the next one is born.
	ring.set_style(style, K_GLOW, life_ms, 0.0, 0.0, grow, a, life_ms - 1.0)


# Sets style `style`: sprite `kind`, the rate and life of `named`, motion = rise and drift px, the
# growth, the alpha, and whether it is a flame (it holds its alpha for a cycle: of `cycle_of`'s grid
# if that is given, else of its own rate).
func _style(
	style: int,
	kind: int,
	named: StringName,
	motion: Vector2,
	grow: Vector2,
	a: float,
	flame: bool,
	cycle_of: StringName = &""
) -> void:
	var every: int = _emit_ms.get(named, 0)
	_every[style] = every
	var hold: float = 0.0
	if flame:  # Holds its alpha for one cycle: the grid's (the glow's life), else its own rate.
		hold = float(every)
		if cycle_of != &"":
			hold = LifeClock.tick_ms(_ticks(_emit_ms.get(cycle_of, 0)))
	ring.set_style(style, kind, float(_life_ms.get(named, 0)), motion.x, motion.y, grow, a, hold)


# Whether the cycle of `style`'s kind turns over in `tick`, from the phase of (`id`, `salt`).
func _due(style: int, id: int, salt: int, tick: int) -> bool:
	var every: int = _every[style]
	if every <= 0:
		return false
	var phase: int = LifeClock.pick(id, SALT_PHASE + salt, every)
	return AirFx.cycle(tick, phase, every) != AirFx.cycle(tick - 1, phase, every)


func _cloud(style: int, id: int, spot: Vector2, tick: int, salt: int) -> void:
	if _due(style, id, salt, tick):
		_birth(style, spot, tick, id, -1)


# A fire with the glow under it, born together on the point's grid.
func _flame(style: int, glow: int, id: int, spot: Vector2, tick: int, salt: int) -> void:
	if _on_grid(glow, id, tick, salt):
		_birth(style, spot, tick, id, -1)
		_birth(glow, spot, tick, id, 0)


# Whether `tick` is on the grid of glow style `glow` for the source (`id`, `salt`): every `span`
# ticks from a phase of its own.
func _on_grid(glow: int, id: int, tick: int, salt: int) -> bool:
	var span: int = _glow_ticks[glow]
	return span > 0 and (tick + LifeClock.pick(id, SALT_PHASE + salt, span)) % span == 0


func _birth(style: int, spot: Vector2, tick: int, id: int, flip: int) -> void:
	ring.add(style, spot, LifeClock.tick_ms(tick), LifeClock.mix(id, SALT_LOOK + tick), flip)


# The crater sources: smoke and embers over the footprint of a building that fell.
@warning_ignore("integer_division")
func _craters(
	snap: MatchSnapshot, life: LifeSettings, view: Rect2, buildings: BuildingLayer, local: int
) -> void:
	_make_craters_if_resized(life)
	var tick: int = snap.tick
	for slot: int in _c_cap:
		if _c_n[slot] == 0:
			continue
		var age: int = (tick - _c_start[slot]) * 1000 / Sim.TICK_RATE
		if age >= maxi(life.crater_smoke_ms, life.crater_ember_ms):
			_c_n[slot] = 0
			continue
		if age < 0 or not _seen(snap, slot, local, buildings):
			continue
		var id: int = _c_id[slot]
		for k: int in _c_n[slot]:
			var spot: Vector2 = _c_at[slot] + _c_off[slot * MAX_POINTS + k]
			if not view.has_point(spot):
				continue
			var kinds: int = 64 + k * 8
			if age < life.crater_smoke_ms and not life.reduced:
				_cloud(Style.CRATER_SMOKE, id, spot, tick, kinds)
			if age < life.crater_ember_ms and _on_grid(Style.GLOW_FAINT, id, tick, kinds + 1):
				_birth(Style.GLOW_FAINT, spot, tick, id, 0)
				if not life.reduced:
					_birth(Style.EMBER, spot, tick, id, -1)


# A crater smokes while the player sees its footprint: an own building's always.
func _seen(snap: MatchSnapshot, slot: int, local: int, buildings: BuildingLayer) -> bool:
	if _c_owner[slot] == local or buildings.reveal_enemies:
		return true
	var at: int = slot * 4
	var foot: Rect2i = Rect2i(_c_foot[at], _c_foot[at + 1], _c_foot[at + 2], _c_foot[at + 3])
	return BuildingLayer.footprint_seen(snap, local, foot)


func _make_craters_if_resized(life: LifeSettings) -> void:
	var want: int = maxi(life.crater_sources, 0)
	if want != _c_cap:
		_resize_craters(want)


## Makes the arrays for `want` sources (any change ends them all).
func _resize_craters(want: int) -> void:
	_c_cap = want
	_c_next = 0
	_c_seq.resize(want)
	_c_seq.fill(0)
	_c_id.resize(want)
	_c_start.resize(want)
	_c_owner.resize(want)
	_c_foot.resize(want * 4)
	_c_at.resize(want)
	_c_n.resize(want)
	_c_n.fill(0)
	_c_off.resize(want * MAX_POINTS)
