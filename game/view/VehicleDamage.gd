class_name VehicleDamage
extends RefCounted
## The damage overlays of a vehicle's rig (ADR 0028 sections 4 and 8, ADR 0029 section 12, plan
## P161), kept out of `UnitLayer`: the `Scar` and `Loose` children of the `Hull`, what a stage
## change and a hull frame change write, and what each costs in sprite writes. All static but the
## per-rig `Parts`. Stage 0 is intact (both hidden), 1 shows the scar (`scar1`), 2 the scar
## (`scar2`) and the loose part. The pictures are the neutral sheet's (`WorldSort.neutral_base`), so
## a damaged vehicle stays in the sorted world's one batch.
## The children sit in the Hull's space, which `WorldSort.dress` has already scaled, so a child's
## scale is its own drawn scale divided by the Hull's per axis and its position is the sheet's point
## times the Hull's texels per px. Both scales are set when a rig is dressed for a type (a rig out
## of the pool may come from another type) and never on a stage change. A mirrored `Loose` takes a
## negative `scale.x`, which mirrors its texels and its offset about the anchor.

const SCAR: StringName = &"Scar"
const LOOSE: StringName = &"Loose"
const SCAR_PARTS: Array[StringName] = [&"scar1", &"scar2"]  ## The picture of stage index + 1.
const LOOSE_PART: StringName = &"loose"
## The loose part's view scale on every vehicle (STYLE.md "Damage overlays", measured by P160
## against the hulls in the gallery); the scar's is the sheet's `scar_milli` (1000: its canvas as
## drawn).
const LOOSE_SCALE: float = 0.8
const SALT_SCAR: int = 0x70000000
const SALT_LOOSE: int = 0x78000000


## What a rig keeps of its overlays: the sprites, the stage they show and the stage wanted, and
## what the follow writes need (the sheet, the hull's frame and texels, which side `Loose` is on).
class Parts:
	extends RefCounted

	var scar: Sprite2D = null
	var loose: Sprite2D = null
	var sheet: IsoSheetDef = null
	var texels: Vector2 = Vector2.ONE  ## The Hull's texels per px of the 2x art.
	var owner_id: int = 0
	var dir: int = UnitLayer.D_EAST  ## The hull frame the positions are for.
	var shown: int = 0
	var want: int = 0
	var queued: bool = false
	var left: bool = false  ## `Loose` is mirrored.
	var damage_at: int = -1  ## The sheet's `damage` and `hang` emitter indices.
	var hang_at: int = -1
	var scar_look: int = 0
	var loose_look: int = 0


## The stage of `hp` of `max_hp` for the vehicles' lines (`LifeSettings.vehicle_stage_percent`).
static func stage_of(hp: int, max_hp: int, percents: PackedInt32Array) -> int:
	return BuildingDamage.stage_of(hp, max_hp, percents)


## The overlays as children of `hull`, after it in the tree (over it, under the Turret), hidden.
static func make(hull: Sprite2D) -> Parts:
	var parts: Parts = Parts.new()
	parts.scar = _child(hull, SCAR)
	parts.loose = _child(hull, LOOSE)
	return parts


## Dresses the overlays of a rig for the vehicle `uid` of `sheet`, whose Hull `hull` is dressed:
## hidden at stage 0, scaled for this type, the looks picked. Writes nothing the stage counts.
static func dress(
	parts: Parts, sort: WorldSort, hull: Sprite2D, sheet: IsoSheetDef, uid: int, owner_id: int
) -> void:
	var neutral: IsoSheetDef = sort.neutral_sheet()
	parts.sheet = sheet
	parts.texels = sort.texels(sheet, &"hull")
	parts.owner_id = owner_id
	parts.dir = UnitLayer.D_EAST
	parts.shown = 0
	parts.want = 0
	parts.left = false
	parts.damage_at = sheet.emitters.find("damage")
	parts.hang_at = sheet.emitters.find("hang")
	parts.scar_look = LifeClock.mix(uid, SALT_SCAR) % neutral.frame_count(SCAR_PARTS[0])
	# The loose part's frames are the track guards, then the wheel fenders: half of them each.
	var kinds: int = neutral.frame_count(LOOSE_PART) / 2
	parts.loose_look = LifeClock.mix(uid, SALT_LOOSE) % kinds
	if sheet.marks != &"tracks":
		parts.loose_look += kinds
	_dress_child(parts.scar, sort, neutral, SCAR_PARTS[0], hull, float(sheet.scar_milli) / 1000.0)
	_dress_child(parts.loose, sort, neutral, LOOSE_PART, hull, LOOSE_SCALE)


## The sprite writes that taking stage `from` to `to` costs (ADR 0028 section 8): the scar's region,
## visibility and position (3) when it appears, its region (1) between stages, its visibility (1)
## when it goes; the loose part's region, visibility, position and flip (4) when it appears, its
## visibility (1) when it goes, nothing with `loose_on` off.
static func cost(from: int, to: int, loose_on: bool) -> int:
	var writes: int = 1 if to == 0 else (3 if from == 0 else 1)
	if loose_on:
		writes += 4 if to == 2 else (1 if from == 2 else 0)
	return writes


## Shows stage `to` on `parts` (it shows `parts.shown`) at the hull frame `parts.dir`; returns the
## writes made, `cost(from, to, loose_on)`.
static func apply(parts: Parts, sort: WorldSort, to: int, loose_on: bool) -> int:
	var writes: int = cost(parts.shown, to, loose_on)
	if to == 0:
		parts.scar.visible = false
	else:
		var scar_base: int = sort.neutral_base(SCAR_PARTS[to - 1], parts.owner_id)
		sort.show_base(parts.scar, scar_base, parts.scar_look)
		if parts.shown == 0:
			parts.scar.position = _point(parts, parts.damage_at)
	if loose_on:
		if to == 2:
			var loose_base: int = sort.neutral_base(LOOSE_PART, parts.owner_id)
			sort.show_base(parts.loose, loose_base, parts.loose_look)
			_place_loose(parts, true)
		elif parts.shown == 2:
			parts.loose.visible = false
	parts.shown = to
	return writes


## The hull turned to frame `dir`: the shown overlays follow it. Returns the writes: the positions
## (1 at stage 1, 2 at stage 2) and the flip when the hang point changed side. Nothing at stage 0.
## A hidden rig (`seen` false) writes none: it forgets its stage (both overlays hidden, `shown` 0)
## and is placed afresh by the stage-of-now write when it is seen again.
static func follow(parts: Parts, dir: int, loose_on: bool, seen: bool) -> int:
	parts.dir = dir
	if parts.shown == 0:
		return 0
	if not seen:
		parts.shown = 0
		parts.scar.visible = false
		parts.loose.visible = false
		return 0
	parts.scar.position = _point(parts, parts.damage_at)
	if parts.shown == 2 and loose_on:
		return 2 + (1 if _place_loose(parts, false) else 0)
	return 1


## Positions `Loose` at the hang point of `parts.dir` and mirrors it (a negative `scale.x`) when
## that is left of the centre. The mirror is written when the side changed, or with `force` (a part
## that appears); returns whether it was.
static func _place_loose(parts: Parts, force: bool) -> bool:
	var at: Vector2 = parts.sheet.emitter_point(parts.hang_at, parts.dir)
	parts.loose.position = at * parts.texels
	var left: bool = at.x < 0.0
	if left == parts.left and not force:
		return false
	parts.left = left
	parts.loose.scale.x = -absf(parts.loose.scale.x) if left else absf(parts.loose.scale.x)
	return true


static func _point(parts: Parts, index: int) -> Vector2:
	return parts.sheet.emitter_point(index, parts.dir) * parts.texels


static func _child(hull: Sprite2D, name: StringName) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = name
	sprite.visible = false
	hull.add_child(sprite)
	return sprite


## Dresses `sprite` for the neutral `part` at `mult` of its canvas as drawn, in the space of `hull`.
static func _dress_child(
	sprite: Sprite2D,
	sort: WorldSort,
	neutral: IsoSheetDef,
	part: StringName,
	hull: Sprite2D,
	mult: float
) -> void:
	sort.dress(sprite, neutral, part)
	sprite.visible = false
	sprite.scale = Vector2(
		sprite.scale.x * mult / hull.scale.x, sprite.scale.y * mult / hull.scale.y
	)
