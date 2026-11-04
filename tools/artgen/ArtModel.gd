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
## The pose parts that are drawn in their rest order: the figures of a squad.
const REST_ORDER: Array[StringName] = [&"walk", &"idle"]
## The damage poses of a building (ADR 0028 section 3): the body at damage stage 1 and 2, each a
## list of moves (`shift`, `turn`, `hide`, `char`) of the hull's groups, frame 0. Each has one frame
## and no direction, and is a part of its own (`<id>_dmg1.svg`), a patch over the top of the body.
## `ruin` (ADR 0029 section 3) is the third: a whole picture of the rubble, cropped to its ink, with
## no cut; only `mount` may move in it.
const DAMAGE_PARTS: Array[StringName] = [&"dmg1", &"dmg2", &"ruin"]
## The damage parts that are patches over the body, with a cut row (`IsoSheetDef.cuts`).
const PATCH_PARTS: Array[StringName] = [&"dmg1", &"dmg2"]
const RUIN: StringName = &"ruin"
## A hull group no damage move may touch, as the `anim` groups are not: it holds what moves.
const SEATED_GROUP: StringName = &"mount"
const MIN_FRAMES: int = 2
const MAX_FRAMES: int = 16
## What an emitter is (a smoke, steam, flame, exhaust or launch point; `damage`, where a scar sits
## and damage smoke starts; `hang`, a vehicle's bracket, on the camera side) and what a vehicle
## leaves on the ground.
const EMITTER_KINDS: Array[StringName] = [
	&"smoke",
	&"steam",
	&"flame",
	&"exhaust",
	&"launch",
	&"damage",
	&"hang",
	&"dmg_gas",
	&"dmg_spark",
	&"ruin",
]
## The typed damage points of a building (ADR 0029 section 5): fire and smoke, a gas jet, sparks.
const DAMAGE_POINTS: Array[StringName] = [&"damage", &"dmg_gas", &"dmg_spark"]
## The emitters that may name a group (`group=<name>`), the ambient ones a stage can break.
const AMBIENT: Array[StringName] = [&"smoke", &"steam", &"flame"]
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
## A vehicle's damage scar scale, 1000 for the battle tank's hull top (ADR 0028 section 4); 0 none.
@export var scar_milli: int = 0
## What the `anim` element does at KRITISK (ADR 0029 section 3): `run` where its carrier still
## stands in `dmg2`, `hide` where it fell; empty for a model without `anim` or damage.
@export var anim_kritisk: StringName = &""


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
	found.append_array(damage_parts())
	found.append(SHADOW)
	return found


## The damage poses that change the picture: those with a move, or with a primitive that appears at
## that stage or before (the ruin: one tagged for it alone), in the order of `DAMAGE_PARTS`.
func damage_parts() -> Array[StringName]:
	var found: Array[StringName] = []
	for i: int in DAMAGE_PARTS.size():
		var changes: bool = not pose_moves(DAMAGE_PARTS[i], 0).is_empty()
		for prim: ArtPrim in _hull_prims():
			var shown: bool = prim.damage > 0 and prim.damage <= i + 1
			changes = changes or (prim.damage == 3 if i == 2 else shown)
		if changes:
			found.append(DAMAGE_PARTS[i])
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


## The primitives of a squad's pose part at rest, in the order of `frame_prims`: the draw order and
## the tops of its frames follow them (`ArtRender.render`), so a leg that swings or lifts is never
## drawn over its own body. Empty for every other part, and for `anim`, whose element turns round.
func frame_rest(part: StringName) -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	if part in REST_ORDER:
		found = primitives(POSE_SOURCE[part])
	return found


## The valid emitters in file order: [kind, point in tiles, group]. An ambient one (`smoke`,
## `steam`, `flame`) may end in `group=<name>`: the group a stage can move or hide (`ArtDamage`).
func emitter_list() -> Array[Array]:
	var found: Array[Array] = []
	for line: String in emitters:
		var words: PackedStringArray = line.split(" ", false)
		var grouped: bool = words.size() == 5 and words[4].begins_with("group=")
		var ok: bool = (words.size() == 4 or grouped) and StringName(words[0]) in EMITTER_KINDS
		for i: int in range(1, 4 if words.size() > 3 else words.size()):
			ok = ok and words[i].is_valid_float()
		ok = ok and (not grouped or (StringName(words[0]) in AMBIENT))
		var group: String = words[4].trim_prefix("group=") if grouped else ""
		ok = ok and (not grouped or group.is_valid_identifier())
		if ok:
			found.append(
				[
					StringName(words[0]),
					Vector3(words[1].to_float(), words[2].to_float(), words[3].to_float()),
					StringName(group)
				]
			)
	return found


## The valid primitives of `part` that are drawn intact, in the model's order: those tagged
## `damage=K` are left out, they appear in `damage_prims` only.
func primitives(part: StringName) -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for prim: ArtPrim in _parsed():
		if prim.part == part and prim.damage == 0:
			found.append(prim)
	return found


## The hull primitives at damage `stage` (1 to 3): every hull primitive that is drawn from that
## stage on or before it, placed by the stage's moves, without the hidden ones.
func damage_prims(stage: int) -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	var by: Array[ArtMove] = pose_moves(DAMAGE_PARTS[stage - 1], 0)
	for prim: ArtPrim in _hull_prims():
		if prim.damage <= stage:
			var posed: ArtPrim = _posed(prim, by)
			if not posed.hidden:
				found.append(posed)
	return found


## The pairs of untouched primitives (a posed copy each) that the stage draws in the other order
## than the intact body does (ADR 0028 section 3). The stage is drawn in its own greedy order,
## `ArtRender._order`, so taking away or moving one primitive can swap two others that overlap on
## the screen; the cut must then cover where those two overlap.
func damage_swaps(stage: int) -> Array[Array]:
	var posed: Array[ArtPrim] = damage_prims(stage)
	var intact: Array[ArtPrim] = primitives(&"hull")
	var rank: Dictionary[int, int] = {}
	var seen: Array[int] = ArtRender.draw_order(intact, 0.0)
	for at: int in seen.size():
		rank[intact[seen[at]].index] = at
	var order: Array[int] = ArtRender.draw_order(posed, 0.0)
	var found: Array[Array] = []
	for i: int in order.size():
		for j: int in range(i + 1, order.size()):
			var first: ArtPrim = posed[order[i]]
			var second: ArtPrim = posed[order[j]]
			var untouched: bool = first.damage == 0 and second.damage == 0
			untouched = untouched and first.moves.is_empty() and second.moves.is_empty()
			if untouched and rank[first.index] > rank[second.index]:
				found.append([first, second])
	return found


## The hull primitives that the stage changes, as [intact, posed] pairs: a moved, turned, hidden or
## charred one (the intact one and the posed one, which is null when hidden), an added one (a null
## intact one). A `damage=K` primitive that a move hides is still listed as added, with its posed
## copy, whose outline is then drawn by nothing: the cut stays conservative there. The cut line is
## the lowest of their outlines.
func damage_changes(stage: int) -> Array[Array]:
	var found: Array[Array] = []
	var by: Array[ArtMove] = pose_moves(DAMAGE_PARTS[stage - 1], 0)
	for prim: ArtPrim in _hull_prims():
		if prim.damage > stage:
			continue
		var posed: ArtPrim = _posed(prim, by)
		if prim.damage > 0:
			found.append([null, posed])
		elif posed != prim:
			found.append([prim, null if posed.hidden else posed])
	return found


## The primitive as a stage's moves place it: `blow` turns the panes it takes (the first of the
## group's `glass` primitives in `blow_order`) into `hole`, and nothing else about them.
func _posed(prim: ArtPrim, by: Array[ArtMove]) -> ArtPrim:
	var posed: ArtPrim = prim.moved(by)
	if posed == prim or prim.material != &"glass":
		return posed
	var order: Array[int] = ArtDamage.blow_order(self, prim.group)
	var rank: int = order.find(prim.index)
	for move: ArtMove in posed.moves:
		if move.kind == &"blow" and rank >= 0:
			if rank < roundi(order.size() * move.blow_percent / 100.0):
				posed.material = &"hole"
	return posed


## Every valid hull primitive, also those that appear at a damage stage, in the model's order.
func _hull_prims() -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for prim: ArtPrim in _parsed():
		if prim.part == &"hull":
			found.append(prim)
	return found


## Every valid primitive in the model's order, each with the index of its line.
func _parsed() -> Array[ArtPrim]:
	var found: Array[ArtPrim] = []
	for i: int in prims.size():
		var prim: ArtPrim = ArtPrim.parse(prims[i])
		if prim != null:
			prim.index = i
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
		else (1 if part in DAMAGE_PARTS else TURNING_DIRECTIONS)
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
		elif prim.damage > 0 and (prim.part != &"hull" or category != &"bld"):
			found.append(
				"%s: damage= is for the hull primitives of a building: %s" % [art_id, line]
			)
		elif prim.group != &"" and prim.part in [&"turret", &"head"]:
			found.append(
				"%s: group= is for hull and anim primitives, which poses move: %s" % [art_id, line]
			)
	if primitives(&"hull").is_empty():
		found.append("%s: no hull primitive" % art_id)
	if mount == Vector3.ZERO and parts().size() > 1:
		found.append("%s: a turret or head part needs a mount" % art_id)
	found.append_array(_pose_problems())
	if found.is_empty() and not damage_parts().is_empty():
		found.append_array(ArtGen.damage_problems(self))
	return found


## What is wrong with the poses, the tags and the emitters.
func _pose_problems() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var headers: Dictionary[StringName, int] = {}
	for line: String in poses:
		var move: ArtMove = ArtMove.parse(line)
		var words: PackedStringArray = line.split(" ", false)
		var header: bool = words.size() == 2 and StringName(words[0]) in POSE_PARTS
		if move != null and move.part in DAMAGE_PARTS:
			found.append_array(_damage_problems(move, line))
		elif move != null:
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
	if scar_milli < 0 or (scar_milli > 0 and category != &"veh"):
		found.append("%s: scar_milli is 0 or above, and a vehicle's" % art_id)
	var staged: Array[StringName] = damage_parts()
	if staged.has(&"dmg1") and not staged.has(&"dmg2"):
		found.append("%s: dmg1 without dmg2 (a building has both stages, or dmg2 alone)" % art_id)
	if staged.has(RUIN) and not staged.has(&"dmg2"):
		found.append("%s: a ruin needs dmg2 (the stage before it)" % art_id)
	found.append_array(_anim_kritisk_problems(staged))
	var kinds: Array[StringName] = []
	for emitter: Array in emitter_list():
		kinds.append(emitter[0])
	if category != &"inf" and kinds.count(&"hang") > (1 if category == &"veh" else 0):
		found.append("%s: hang is a vehicle's, one at most" % art_id)
	found.append_array(_point_problems(kinds))
	var hull_groups: PackedStringArray = PackedStringArray()
	for prim: ArtPrim in _hull_prims():
		hull_groups.append(prim.group)
	for emitter: Array in emitter_list():
		if emitter[2] != &"" and not hull_groups.has(emitter[2]):
			found.append(
				"%s: an emitter names a group no hull primitive has: %s" % [art_id, emitter]
			)
	if marks != &"" and (marks not in MARKS or category != &"veh"):
		found.append("%s: marks are tracks or wheels, of a vehicle" % art_id)
	return found


## What is wrong with the counts of the damage, `dmg_gas`, `dmg_spark` and `ruin` points: a vehicle
## has one `damage`, a squad none, a building two at most; a building that uses generator v5
## (`is_v5`) with damage poses has 2 to 4 typed ones and, with a ruin, 1 to 3 `ruin` points.
func _point_problems(kinds: Array[StringName]) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var typed: int = 0
	for kind: StringName in DAMAGE_POINTS:
		typed += kinds.count(kind)
	var ruins: int = kinds.count(RUIN)
	if category != &"bld" and (typed > kinds.count(&"damage") or ruins > 0):
		found.append("%s: dmg_gas, dmg_spark and ruin points are a building's" % art_id)
	elif category == &"inf" and (typed > 0 or kinds.has(&"hang")):
		found.append("%s: damage and hang points are for buildings and vehicles" % art_id)
	elif not ArtDamage.is_v5(self):
		if typed > (1 if category == &"veh" else 2):
			found.append("%s: a vehicle has one damage point, a building two at most" % art_id)
	else:
		var least: int = 2 if not damage_parts().is_empty() else 0
		if typed < least or typed > 4:
			found.append("%s: a building with damage poses has 2 to 4 damage points" % art_id)
		var want: int = 1 if damage_parts().has(RUIN) else 0
		if ruins < want or ruins > (3 if want > 0 else 0):
			found.append("%s: a ruin has 1 to 3 ruin points, no ruin none" % art_id)
	return found


## What is wrong with `anim_kritisk`: a word that is not `run` or `hide`, or one on a model without
## an `anim` element and a `dmg2`. (That `run` has ink under it is `ArtGen.damage_problems`.)
func _anim_kritisk_problems(staged: Array[StringName]) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if anim_kritisk == &"":
		return found
	if anim_kritisk not in [&"run", &"hide"]:
		found.append("%s: anim_kritisk is run or hide" % art_id)
	elif primitives(ArtPrim.ANIM).is_empty() or not staged.has(&"dmg2"):
		found.append("%s: anim_kritisk is for a building with an anim and a dmg2" % art_id)
	return found


## What is wrong with a move of a damage pose: not a building, not frame 0, not a group of the hull,
## or a group that holds the moving element (an `anim` group or the group `mount`), which must stay
## seated (ADR 0028 section 3).
func _damage_problems(move: ArtMove, line: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if category != &"bld" or move.frame != 0:
		found.append("%s: a damage pose is a building's, frame 0: %s" % [art_id, line])
	var hull_groups: PackedStringArray = PackedStringArray()
	for prim: ArtPrim in _hull_prims():
		hull_groups.append(prim.group)
		# A charred team face must leave the key band (ADR 0029 section 5).
		if move.kind == &"char" and prim.group == move.group and prim.material == ArtPalette.TEAM:
			if not ArtPalette.char_leaves_band(faction, move.char_percent):
				found.append("%s: a charred team face stays in the key band: %s" % [art_id, line])
	if move.kind == ArtMove.SOOT:
		return found
	var seated: bool = move.group == SEATED_GROUP and move.part != RUIN  # the ruin may move it
	if not hull_groups.has(move.group):
		found.append("%s: no such hull group: %s" % [art_id, line])
	elif seated or _groups(ArtPrim.ANIM).has(move.group):
		found.append(
			"%s: a damage move may not touch the moving element or mount: %s" % [art_id, line]
		)
	return found


## The groups the primitives of a pose part carry.
func _groups(part: StringName) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for prim: ArtPrim in primitives(POSE_SOURCE[part]):
		found.append(prim.group)
	return found
