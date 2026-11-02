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
## The pose parts (ADR 0027 section 4): several frames per direction, each a model pose. `walk` and
## `idle` pose the hull of a squad; `anim` poses the primitives of part `anim`, the moving element
## of a building. They follow the hull's directions (a building's `anim` has none).
const POSE_PARTS: Array[StringName] = [&"walk", &"idle", &"anim"]
const POSE_SOURCE: Dictionary[StringName, StringName] = {
	&"walk": &"hull", &"idle": &"hull", &"anim": ArtPrim.ANIM
}
const MIN_FRAMES: int = 2
const MAX_FRAMES: int = 16
## What an emitter is (a smoke, steam, flame, exhaust or launch point) and what a vehicle leaves on
## the ground.
const EMITTER_KINDS: Array[StringName] = [&"smoke", &"steam", &"flame", &"exhaust", &"launch"]
const MARKS: Array[StringName] = [&"tracks", &"wheels"]

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
## The poses, one line each: `<part> <frames>` says that a pose part has that many frames per
## direction (2 to 16), `<part> <frame> <group> shift|turn ...` is a move of a group in one frame
## (see `ArtMove`). Frames without a move for a group show it at rest. No pose, no poses.
@export var poses: PackedStringArray = PackedStringArray()
## A squad's ground travel per walk cycle, in milli-tiles (ADR 0027 section 5); 0 without `walk`.
@export var stride_milli: int = 0
## The time of one frame of the `anim` part, ms; 0 without `anim`.
@export var anim_ms: int = 0
## Where things come out, one per entry: `<kind> <x> <y> <z>` in tiles of the model's frame, a kind
## of `EMITTER_KINDS`. The sheet turns each point with every hull frame.
@export var emitters: PackedStringArray = PackedStringArray()
## What a vehicle's running gear leaves on the ground: `tracks`, `wheels` or empty.
@export var marks: StringName = &""


## The parts the model has, in file order: hull, turret, head.
func parts() -> Array[StringName]:
	var found: Array[StringName] = []
	for part: StringName in ArtPrim.PARTS:
		if not primitives(part).is_empty():
			found.append(part)
	return found


## The parts that have frames: the model's own, its pose parts and the cast shadow, last.
func frame_parts() -> Array[StringName]:
	var found: Array[StringName] = parts()
	found.append_array(pose_parts())
	found.append(SHADOW)
	return found


## The pose parts the model has, in the order of `POSE_PARTS`.
func pose_parts() -> Array[StringName]:
	var found: Array[StringName] = []
	for part: StringName in POSE_PARTS:
		if pose_frames(part) > 0:
			found.append(part)
	return found


## The frames per direction a pose part says it has, 0 when it has none.
func pose_frames(part: StringName) -> int:
	for line: String in poses:
		var words: PackedStringArray = line.split(" ", false)
		if words.size() == 2 and StringName(words[0]) == part and words[1].is_valid_int():
			return words[1].to_int()
	return 0


## The frames per direction of a part of `frame_parts`: 1 unless it is a pose part.
func frames(part: StringName) -> int:
	return maxi(pose_frames(part), 1)


## The valid moves of a pose part in `frame`, in the order of their lines.
func pose_moves(part: StringName, frame: int) -> Array[ArtMove]:
	var found: Array[ArtMove] = []
	for line: String in poses:
		var move: ArtMove = ArtMove.parse(line)
		if move != null and move.part == part and move.frame == frame:
			found.append(move)
	return found


## The primitives that draw `frame` of `part`: the part's own, the pose parts' with their moves of
## that frame, the cast shadow's all of them at rest.
func frame_prims(part: StringName, frame: int) -> Array[ArtPrim]:
	if part == SHADOW:
		return shadow_prims()
	if part not in POSE_PARTS:
		return primitives(part)
	var found: Array[ArtPrim] = []
	var by: Array[ArtMove] = pose_moves(part, frame)
	for prim: ArtPrim in primitives(POSE_SOURCE[part]):
		found.append(prim.moved(by))
	return found


## The valid emitters in file order: [kind, point in tiles].
func emitter_list() -> Array[Array]:
	var found: Array[Array] = []
	for line: String in emitters:
		var words: PackedStringArray = line.split(" ", false)
		var ok: bool = words.size() == 4 and StringName(words[0]) in EMITTER_KINDS
		for i: int in range(1, words.size()):
			ok = ok and words[i].is_valid_float()
		if ok:
			found.append(
				[
					StringName(words[0]),
					Vector3(words[1].to_float(), words[2].to_float(), words[3].to_float())
				]
			)
	return found


## The valid primitives of `part`, in the model's order.
func primitives(part: StringName) -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for line: String in prims:
		var prim: ArtPrim = ArtPrim.parse(line)
		if prim != null and prim.part == part:
			found.append(prim)
	return found


## Every primitive in the hull's frame, a turret's or head's moved to its mount (straight ahead)
## and the `anim` element at rest: what casts the shadow.
func shadow_prims() -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for part: StringName in ArtPrim.ALL_PARTS:
		for prim: ArtPrim in primitives(part):
			if part in [&"turret", &"head"]:
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
## building body. A squad has the even ones. The shadow and the pose parts have the hull's.
func directions(part: StringName) -> Array[int]:
	var count: int = (
		HULL_DIRECTIONS.get(category, 1)
		if part in [&"hull", SHADOW] or part in POSE_PARTS
		else TURNING_DIRECTIONS
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
		elif prim.group != &"" and prim.part in [&"turret", &"head"]:
			found.append(
				"%s: group= is for hull and anim primitives, which poses move: %s" % [art_id, line]
			)
	if primitives(&"hull").is_empty():
		found.append("%s: no hull primitive" % art_id)
	if mount == Vector3.ZERO and parts().size() > 1:
		found.append("%s: a turret or head part needs a mount" % art_id)
	found.append_array(_pose_problems())
	return found


## What is wrong with the poses, the tags and the emitters.
func _pose_problems() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var headers: Dictionary[StringName, int] = {}
	for line: String in poses:
		var move: ArtMove = ArtMove.parse(line)
		var words: PackedStringArray = line.split(" ", false)
		var header: bool = words.size() == 2 and StringName(words[0]) in POSE_PARTS
		if move != null:
			if move.frame >= pose_frames(move.part) or not _groups(move.part).has(move.group):
				found.append("%s: no such frame or group: %s" % [art_id, line])
		elif (
			header
			and words[1].is_valid_int()
			and words[1].to_int() in range(MIN_FRAMES, MAX_FRAMES + 1)
		):
			headers[StringName(words[0])] = headers.get(StringName(words[0]), 0) + 1
		else:
			found.append("%s: not a header (2 to 16 frames) or a move: %s" % [art_id, line])
	for part: StringName in headers:
		if headers[part] > 1:
			found.append("%s: more than one %s header" % [art_id, part])
		if (part == ArtPrim.ANIM) == (category == &"inf"):
			found.append(
				"%s: walk and idle are a squad's, anim a building's or a vehicle's" % art_id
			)
	if (pose_frames(ArtPrim.ANIM) > 0) == primitives(ArtPrim.ANIM).is_empty():
		found.append("%s: anim primitives and an anim pose go together" % art_id)
	if stride_milli < 0 or (stride_milli != 0) != (pose_frames(&"walk") > 0):
		found.append("%s: stride_milli is above 0 with a walk pose, and 0 without" % art_id)
	if anim_ms < 0 or (anim_ms != 0) != (pose_frames(ArtPrim.ANIM) > 0):
		found.append("%s: anim_ms is above 0 with an anim pose, and 0 without" % art_id)
	if emitter_list().size() != emitters.size():
		found.append("%s: an emitter is a kind of %s and three numbers" % [art_id, EMITTER_KINDS])
	if marks != &"" and (marks not in MARKS or category != &"veh"):
		found.append("%s: marks are tracks or wheels, of a vehicle" % art_id)
	return found


## The groups the primitives of a pose part carry.
func _groups(part: StringName) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for prim: ArtPrim in primitives(POSE_SOURCE[part]):
		found.append(prim.group)
	return found
