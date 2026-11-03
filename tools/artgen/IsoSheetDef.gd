class_name IsoSheetDef
extends Resource
## The sheet of one art id (ADR 0023 sections 2 and 5): which frames it has and where each lies in
## its canvas, written by `bash scripts/gen-art.sh` next to the frames (`assets/art/iso/<faction>/
## <category>/<art_id>_sheet.tres`, listed in `assets/art/iso/index.tres`). Never edit a generated
## one by hand; the one hand-written sheet is the neutral damage overlays' (`root` set, ADR 0028
## section 4).
## Sizes, anchors and mounts are px of the 2x art (a tile on the ground is 128 x 64); the three
## lifts are world px at zoom 1, half of that, which is what the view counts in.
##
## A part is `hull`, `turret` or `head`, a pose part (`walk`, `idle` or `anim`, ADR 0027 section
## 4), a building's damage patch (`dmg1` or `dmg2`, ADR 0028 section 3) and `shadow`, each with
## one canvas and one anchor for all its frames. The anchor is where a
## unit's ground point lies in the canvas; a building's body and shadow are anchored at the back
## corner of the footprint (Spec 03), `origin` gives the footprint's centre. A turret's or head's
## anchor is its pivot, which `mount` puts at its place in the hull. A pose part is anchored at the
## ground point (a building's `anim` at the footprint's centre: `origin` and `anchor` are the same).
## A damage patch is anchored like the body (the footprint's back corner), in a canvas of its own.

const ROOT: String = "res://assets/art/iso"

@export var art_id: StringName = &""
## `fossil` or `renew`, never shown in the game; `neutral` for the damage overlays' sheet.
@export var faction: StringName = &""
@export var category: StringName = &"veh"  ## `veh`, `inf` or `bld`; a neutral sheet's is `dmg`.
@export var footprint: int = 0  ## n of an n x n building, 0 for a unit.
@export var parts: PackedStringArray = PackedStringArray()  ## In file order, `shadow` last.
@export var counts: PackedInt32Array = PackedInt32Array()  ## Directions per part: 16, 8 or 1.
## Frames per direction of each part, in the order of `parts`: 1 except a pose part's 2 to 16. The
## file of a part with more than one is `..._f<K>.svg`. A sheet written before the frame axis (and
## every sheet with no pose part) has none of this array; read it through `frame_count`.
@export var frames: PackedInt32Array = PackedInt32Array()
@export var sizes: PackedInt32Array = PackedInt32Array()  ## Canvas x and y per part.
@export var anchors: PackedInt32Array = PackedInt32Array()  ## Anchor x and y per part.
## The turret's or head's pivot from the hull's ground point (a building's footprint centre), for
## each hull frame (one for a building); empty without a turret or head.
@export var mounts: PackedVector2Array = PackedVector2Array()
## Where a health bar stands above the ground point: the top of the pose that three of four hull
## frames stay under (the turret or head straight ahead), so it clears most poses and covers only
## a taller one (a long hull, a barrel that points up the screen). Not the top of every frame.
@export var bar_lift_px: int = 0
@export var pick_lift_px: int = 0  ## Half of that: a tap picks the unit round this height.
@export var muzzle_lift_px: int = 0  ## Where shots leave; 0 for a building without a head.
@export var icon: String = ""  ## The item card, a texture.
## A squad's ground travel per walk cycle in milli-tiles (the walk frame advances every quarter of
## it, ADR 0027 section 5); 0 without a `walk` part.
@export var stride_milli: int = 0
@export var anim_ms: int = 0  ## The time of one frame of the `anim` part, ms; 0 without one.
## The kinds of the places things come out of (`smoke`, `steam`, `flame`, `exhaust`, `launch`,
## `damage` for where a scar sits and damage smoke starts, `hang` for a vehicle's bracket, mirrored
## to the side that faces the camera in every hull frame), one for each emitter. `emitter_points`
## has the point of each: px of the 2x art from the hull's
## ground point (a building's footprint centre), for each hull frame, emitter after emitter (one
## point for a building), so `emitter_point` finds it. Both empty without an emitter.
@export var emitters: PackedStringArray = PackedStringArray()
@export var emitter_points: PackedVector2Array = PackedVector2Array()
## What a vehicle's running gear leaves on the ground: `tracks`, `wheels` or empty (none).
@export var marks: StringName = &""
## The cut row of each damage stage in the body's canvas (ADR 0028 section 3), `[stage 1, stage 2]`:
## the first row that is intact, so the view shows the body from this row down and the patch over
## it (the patch reaches `ArtGen.CUT_OVERLAP_PX` rows below the cut). 0 for a stage with no patch;
## empty for a sheet without damage parts (`dmg1`, `dmg2`).
@export var cuts: PackedInt32Array = PackedInt32Array()
## A vehicle's damage scar scale, 1000 for the battle tank's hull top; 0 for a sheet without one.
@export var scar_milli: int = 0
## The folder the frames are in. Empty is `ROOT/<faction>/<category>/`, which every generated sheet
## has; a hand-written sheet (the neutral damage overlays, ADR 0028 section 4) sets it.
@export var root: String = ""


## `res://assets/art/iso/<faction>/<category>/<art_id>_<part>[_d<NN>][_f<K>].svg`; `dir` -1 and
## `frame` -1 have no suffix.
static func frame_path(
	faction_id: StringName,
	category_id: StringName,
	id: StringName,
	part: StringName,
	dir: int,
	frame: int = -1
) -> String:
	var suffix: String = ("" if dir < 0 else "_d%02d" % dir) + ("" if frame < 0 else "_f%d" % frame)
	var name: String = "%s_%s%s.svg" % [id, part, suffix]
	return ROOT.path_join(String(faction_id)).path_join(String(category_id)).path_join(name)


## The file of frame `frame` of a part in direction `dir`; a part with one frame has no `_f<K>`.
func path(part: StringName, dir: int, frame: int = 0) -> String:
	var found: String = frame_path(
		faction, category, art_id, part, dir, frame if frame_count(part) > 1 else -1
	)
	return found if root == "" else root.path_join(found.get_file())


## The frames per direction of a part: 1, also for a sheet that has no `frames`.
func frame_count(part: StringName) -> int:
	var at: int = parts.find(String(part))
	return frames[at] if at >= 0 and at < frames.size() else 1


func has_part(part: StringName) -> bool:
	return parts.has(String(part))


func frame_size(part: StringName) -> Vector2i:
	var at: int = parts.find(String(part))
	return Vector2i(sizes[2 * at], sizes[2 * at + 1]) if at >= 0 else Vector2i.ZERO


func anchor(part: StringName) -> Vector2i:
	var at: int = parts.find(String(part))
	return Vector2i(anchors[2 * at], anchors[2 * at + 1]) if at >= 0 else Vector2i.ZERO


## Where the model's origin lies in the canvas: a unit's ground point, a building's footprint
## centre (32 px per footprint tile below its anchor); a damage patch is anchored like the body.
func origin(part: StringName) -> Vector2i:
	var body: bool = footprint > 0 and part in [&"hull", &"shadow", &"dmg1", &"dmg2"]
	return anchor(part) + (Vector2i(0, 32 * footprint) if body else Vector2i.ZERO)


## The directions of a part's frames, as in `d<NN>`; `[-1]` is the one view of a building body.
func directions(part: StringName) -> PackedInt32Array:
	var at: int = parts.find(String(part))
	var found: PackedInt32Array = PackedInt32Array()
	if at < 0:
		return found
	for i: int in counts[at]:
		found.append(i * (16 / counts[at]) if counts[at] > 1 else -1)
	return found


## The mount for the hull facing `dir` (`d<NN>`); any `dir` for a building.
func mount(dir: int) -> Vector2:
	if mounts.is_empty():
		return Vector2.ZERO
	return mounts[0] if mounts.size() == 1 else mounts[dir * mounts.size() / 16]


## Where emitter `index` lies for the hull facing `dir` (`d<NN>`, 0 to 15 for a unit; any for a
## building), px of the 2x art from the hull's ground point. (0, 0) for an index the sheet lacks.
func emitter_point(index: int, dir: int) -> Vector2:
	if index < 0 or index >= emitters.size():
		return Vector2.ZERO
	var per: int = emitter_points.size() / emitters.size()
	return emitter_points[index * per + (0 if per == 1 else clampi(dir, 0, 15) * per / 16)]
