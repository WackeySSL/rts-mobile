class_name IsoSheetDef
extends Resource
## The sheet of one art id (ADR 0023 sections 2 and 5): which frames it has and where each lies in
## its canvas, written by `bash scripts/gen-art.sh` next to the frames (`assets/art/iso/<faction>/
## <category>/<art_id>_sheet.tres`, listed in `assets/art/iso/index.tres`). Never edit one by hand.
## Sizes, anchors and mounts are px of the 2x art (a tile on the ground is 128 x 64); the three
## lifts are world px at zoom 1, half of that, which is what the view counts in.
##
## A part is `hull`, `turret` or `head` and `shadow`, each with one canvas and one anchor for all
## its frames. The anchor is where a unit's ground point lies in the canvas; a building's body and
## shadow are anchored at the back corner of the footprint (Spec 03), `origin` gives the footprint's
## centre. A turret's or head's anchor is its pivot, which `mount` puts at its place in the hull.

const ROOT: String = "res://assets/art/iso"

@export var art_id: StringName = &""
@export var faction: StringName = &""  ## `fossil` or `renew`; never shown in the game.
@export var category: StringName = &"veh"  ## `veh`, `inf` or `bld`.
@export var footprint: int = 0  ## n of an n x n building, 0 for a unit.
@export var parts: PackedStringArray = PackedStringArray()  ## In file order, `shadow` last.
@export var counts: PackedInt32Array = PackedInt32Array()  ## Frames per part: 16, 8 or 1.
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


## `res://assets/art/iso/<faction>/<category>/<art_id>_<part>[_d<NN>].svg`; `dir` -1 has no suffix.
static func frame_path(
	faction_id: StringName, category_id: StringName, id: StringName, part: StringName, dir: int
) -> String:
	var suffix: String = "" if dir < 0 else "_d%02d" % dir
	var name: String = "%s_%s%s.svg" % [id, part, suffix]
	return ROOT.path_join(String(faction_id)).path_join(String(category_id)).path_join(name)


func path(part: StringName, dir: int) -> String:
	return frame_path(faction, category, art_id, part, dir)


func has_part(part: StringName) -> bool:
	return parts.has(String(part))


func frame_size(part: StringName) -> Vector2i:
	var at: int = parts.find(String(part))
	return Vector2i(sizes[2 * at], sizes[2 * at + 1]) if at >= 0 else Vector2i.ZERO


func anchor(part: StringName) -> Vector2i:
	var at: int = parts.find(String(part))
	return Vector2i(anchors[2 * at], anchors[2 * at + 1]) if at >= 0 else Vector2i.ZERO


## Where the model's origin lies in the canvas: a unit's ground point, a building's footprint
## centre (32 px per footprint tile below its anchor).
func origin(part: StringName) -> Vector2i:
	var body: bool = footprint > 0 and part in [&"hull", &"shadow"]
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
