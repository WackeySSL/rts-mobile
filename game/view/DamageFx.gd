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
## 2 `soot`, a small `fire` and sparks, born where its rig is drawn and left in the world. A
## puff is born when the cycle of its kind turns over, from a phase of its own per building, point
## and kind (`LifeClock.pick`), so a run is the same on every device. Sites, squads and sources
## outside the view rect grown by a tile emit nothing; a blackout does not stop a fire. `reduced`
## keeps smoke, fire and glow and drops the sparks.

## The styles of the ring's puffs (a sprite and how it lives), and the sprite kinds.
enum Style {
	SMOKE,
	SOOT,
	FIRE,
	FIRE_BIG,
	FIRE_CAR,
	JET,
	SPARK,
	GLOW_WEAK,
	GLOW_STRONG,
	GLOW_JET,
	TRAIL,
}
const KINDS: Array[StringName] = [&"smoke", &"soot", &"fire", &"spark", &"jet", &"glow", &"exhaust"]
const K_SMOKE: int = 0
const K_SOOT: int = 1
const K_FIRE: int = 2
const K_SPARK: int = 3
const K_JET: int = 4
const K_GLOW: int = 5
const K_EXHAUST: int = 6
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


func _init() -> void:
	ring.setup(KINDS, Style.size())
	ring.glow_kind = K_GLOW
	_every.resize(Style.size())


## Empties the ring (a new match).
func clear() -> void:
	ring.clear()


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


## The tick-by-tick cycle number of an emitter of `every` ms from `phase` ms (integers only).
@warning_ignore("integer_division")
static func cycle(tick: int, phase: int, every: int) -> int:
	return (tick * 1000 + phase * Sim.TICK_RATE) / (every * Sim.TICK_RATE)


## Takes the rates and the looks of the styles from `life`: the ring's size, each style's sprite,
## life, motion, growth and alpha. Called once a tick.
func read(life: LifeSettings) -> void:
	ring.resize(life.damage_slots)
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
	_style(Style.TRAIL, K_EXHAUST, &"exhaust", Vector2(rise, drift), grown, a, false)
	_style(Style.FIRE, K_FIRE, &"fire", Vector2.ZERO, flame, a, true)
	_style(Style.FIRE_BIG, K_FIRE, &"fire", Vector2.ZERO, flame * big, a, true)
	_style(
		Style.FIRE_CAR,
		K_FIRE,
		&"fire",
		Vector2.ZERO,
		flame * life.damage_vehicle_fire_scale,
		a,
		true
	)
	_style(Style.JET, K_JET, &"jet", Vector2.ZERO, flame, a, true)
	_style(Style.SPARK, K_SPARK, &"spark", Vector2(life.damage_spark_rise_px, drift), one, a, false)
	_style(Style.GLOW_WEAK, K_GLOW, &"fire", Vector2.ZERO, one, life.glow_weak_alpha, true)
	_style(
		Style.GLOW_STRONG, K_GLOW, &"fire", Vector2.ZERO, one * big, life.glow_strong_alpha, true
	)
	_style(Style.GLOW_JET, K_GLOW, &"jet", Vector2.ZERO, one, life.glow_weak_alpha, true)


## One tick `tick`: births at every damaged source the player can see.
func emit(
	snap: MatchSnapshot,
	view: Rect2,
	life: LifeSettings,
	buildings: BuildingLayer,
	units: UnitLayer,
	world_to_local: Transform2D
) -> void:
	var types: PackedInt32Array = snap.type_index
	var ids: PackedInt32Array = snap.unit_id
	var building_lines: PackedInt32Array = life.building_stage_percent
	var vehicle_lines: PackedInt32Array = life.vehicle_stage_percent
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
				if _due(Style.JET, id, kinds + 1, tick):
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


# Sets style `style`: sprite `kind`, the rate and life of `named`, motion = rise and drift px, the
# growth, the alpha, and whether it is a flame (it holds its alpha until the next one is born).
func _style(
	style: int, kind: int, named: StringName, motion: Vector2, grow: Vector2, a: float, flame: bool
) -> void:
	var every: int = _emit_ms.get(named, 0)
	_every[style] = every
	var hold: float = float(every) if flame else 0.0
	ring.set_style(style, kind, float(_life_ms.get(named, 0)), motion.x, motion.y, grow, a, hold)


# Whether the cycle of `style`'s kind turns over in `tick`, from the phase of (`id`, `salt`).
func _due(style: int, id: int, salt: int, tick: int) -> bool:
	var every: int = _every[style]
	if every <= 0:
		return false
	var phase: int = LifeClock.pick(id, SALT_PHASE + salt, every)
	return cycle(tick, phase, every) != cycle(tick - 1, phase, every)


func _cloud(style: int, id: int, spot: Vector2, tick: int, salt: int) -> void:
	if _due(style, id, salt, tick):
		_birth(style, spot, tick, id, -1)


# A fire with the glow under it, born together.
func _flame(style: int, glow: int, id: int, spot: Vector2, tick: int, salt: int) -> void:
	if _due(style, id, salt, tick):
		_birth(style, spot, tick, id, -1)
		_birth(glow, spot, tick, id, 0)


func _birth(style: int, spot: Vector2, tick: int, id: int, flip: int) -> void:
	ring.add(style, spot, LifeClock.tick_ms(tick), LifeClock.mix(id, SALT_LOOK + tick), flip)
