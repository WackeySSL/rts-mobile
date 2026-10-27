class_name ArtModel
extends Resource
## One art id as simple 3D primitives (ADR 0023 section 5): the source of its SVG frames.
## `assets/art/models/<faction>/<type_id>.tres`; `bash scripts/gen-art.sh` turns it into
## `assets/art/iso/<faction>/<category>/<type_id>_<part>_d<NN>.svg`. Edit the model, never a frame.

const CATEGORIES: Array[StringName] = [&"veh", &"inf", &"bld", &"fx"]
## The directions of the hull by category: a vehicle has 16, a squad 8, a building none (one view).
const HULL_DIRECTIONS: Dictionary[StringName, int] = {&"veh": 16, &"inf": 8, &"bld": 1, &"fx": 1}
const TURNING_DIRECTIONS: int = 16  ## A turret and a head turn in 16 steps.
## The cast shadow is a frame set of its own (P99b): one frame per hull frame, never authored.
const SHADOW: StringName = &"shadow"

@export var art_id: StringName = &""  ## The unit or building type id; the file name too.
@export var faction: StringName = &""  ## `fossil` or `renew`; never shown in the game.
@export var category: StringName = &"veh"
@export var footprint: int = 0  ## n of an n x n building; 0 for a unit.
## The silhouette in one line (svg-art-style: describe it in words before you model it).
@export var silhouette: String = ""
## The pivot of the turret or head part, in the hull's frame: the part's own origin sits there.
@export var mount: Vector3 = Vector3.ZERO
## One primitive per entry, see `ArtPrim`.
@export var prims: PackedStringArray = PackedStringArray()


## The parts the model has, in file order: hull, turret, head.
func parts() -> Array[StringName]:
	var found: Array[StringName] = []
	for part: StringName in ArtPrim.PARTS:
		if not primitives(part).is_empty():
			found.append(part)
	return found


## The parts that have frames: the model's own and the cast shadow, last.
func frame_parts() -> Array[StringName]:
	var found: Array[StringName] = parts()
	found.append(SHADOW)
	return found


## The valid primitives of `part`, in the model's order.
func primitives(part: StringName) -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for line: String in prims:
		var prim: ArtPrim = ArtPrim.parse(line)
		if prim != null and prim.part == part:
			found.append(prim)
	return found


## Every primitive in the hull's frame, a turret's or head's moved to its mount (straight ahead):
## what casts the shadow.
func shadow_prims() -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for part: StringName in ArtPrim.PARTS:
		for prim: ArtPrim in primitives(part):
			if part != &"hull":
				prim.centre += Vector2(mount.x, mount.y)
				prim.z0 += mount.z
			found.append(prim)
	return found


## The height of the muzzle above the ground, in tiles: the centre height of the primitive of the
## firing part (the turret or head; a squad's or a gun-less vehicle's hull) that reaches farthest
## along +x. 0 for a building without a head.
func muzzle_z() -> float:
	var part: StringName = &"hull"
	for turning: StringName in [&"turret", &"head"]:
		if not primitives(turning).is_empty():
			part = turning
	var forward: ArtPrim = null
	for prim: ArtPrim in primitives(part):
		if forward == null or prim.aabb().end.x > forward.aabb().end.x:
			forward = prim
	if forward == null or (part == &"hull" and category == &"bld"):
		return 0.0
	return forward.aabb().get_center().z + (0.0 if part == &"hull" else mount.z)


## The direction of the default view (Spec 04): `d06` for the Derrick League, `d10` for the Lumen
## Accord.
func default_dir() -> int:
	return 6 if faction == &"fossil" else 10


## The direction indices of a part's frames (0 to 15 as `d00` to `d15`); `[-1]` is the one view of a
## building body. A squad has the even ones. The shadow has the hull's.
func directions(part: StringName) -> Array[int]:
	var count: int = (
		HULL_DIRECTIONS.get(category, 1) if part in [&"hull", SHADOW] else TURNING_DIRECTIONS
	)
	var found: Array[int] = []
	for i: int in count:
		found.append(i * roundi(16.0 / count) if count > 1 else -1)
	return found


## What is wrong with the model, one text per problem; empty when it is fine to generate.
func problems() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if art_id == &"" or not ArtPalette.KEYS.has(faction) or category not in CATEGORIES:
		found.append("%s: art_id, faction or category is not valid" % art_id)
	if (footprint > 0) != (category == &"bld") or footprint > 3:
		found.append("%s: only a building has a footprint, 1 to 3" % art_id)
	for line: String in prims:
		var prim: ArtPrim = ArtPrim.parse(line)
		if prim == null or not ArtPalette.has_material(faction, prim.material):
			found.append("%s: not a primitive or an unknown material: %s" % [art_id, line])
	if primitives(&"hull").is_empty():
		found.append("%s: no hull primitive" % art_id)
	if mount == Vector3.ZERO and parts().size() > 1:
		found.append("%s: a turret or head part needs a mount" % art_id)
	return found
