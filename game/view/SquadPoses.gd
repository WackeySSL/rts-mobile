class_name SquadPoses
extends RefCounted
## The sprite side of a squad's poses (P142, ADR 0027 sections 3 to 5): `UnitLayer` decides which
## pose and frame a squad shows (`RigLife`), this writes it to the Hull. The Hull draws the standing
## `hull` frame, a `walk` frame or an `idle` frame of the same atlas page; the poses' anchors differ
## by a pixel or two, and `WorldSort.show_base` writes only the region, so a change of pose writes
## the sprite's offset too (`RigLife.Pose.offsets`, read from the sheet when the rig is dressed). A
## frame change is a table read of the base kept in the pose record: a string key is built when the
## pose or the direction changes, never for a frame. Nothing is allocated.

var world_sort: WorldSort  ## The sorted world whose atlas the Hull draws from.
var rig_life: RigLife  ## Its `writes` counts the sprite writes of the poses.


func _init(sort: WorldSort, life: RigLife) -> void:
	world_sort = sort
	rig_life = life


## Gives a rig of `sheet` its `pose` record when it is dressed: the hull standing at `hull_base`,
## and the poses when the sheet has them and the atlas holds the walk and idle frames of the
## owner's faction at the east direction (else the squad keeps its hull). The sheet's part names
## are converted here, once, never in a frame.
func dress(pose: RigLife.Pose, sheet: IsoSheetDef, hull_base: int, owner_id: int) -> void:
	pose.reset(hull_base)
	if sheet == null or world_sort.atlas.is_empty():
		return
	if not pose.dress(sheet, world_sort.atlas.bake_scale()):
		return
	for part: int in [RigLife.POSE_WALK, RigLife.POSE_IDLE]:
		var base: int = world_sort.base_of(
			sheet, RigLife.POSE_PARTS[part], UnitLayer.D_EAST, owner_id
		)
		if world_sort.frame_count_at(base) != pose.frames[part]:
			pose.quarter = 0


## Shows frame `frame` of pose `want` on `hull`, facing `dir` (`d<NN>`), when that is not what it
## shows: a new pose writes the offset and the region, a new frame the region only.
func show(
	pose: RigLife.Pose,
	hull: Sprite2D,
	sheet: IsoSheetDef,
	want: int,
	frame: int,
	dir: int,
	owner_id: int
) -> void:
	if want == pose.shown and frame == pose.frame:
		return
	if want != pose.shown:
		pose.shown = want
		hull.offset = pose.offsets[want]
		pose.base = world_sort.base_of(sheet, RigLife.POSE_PARTS[want], dir, owner_id)
	pose.frame = frame
	world_sort.show_base(hull, pose.base, frame)
	rig_life.writes += 1


## Turns the pose the Hull is in to the new direction `dir`: the same frame of the part's frames
## for that direction (the first of the hull's, when it stands).
func turn(pose: RigLife.Pose, hull: Sprite2D, sheet: IsoSheetDef, dir: int, owner_id: int) -> void:
	pose.base = world_sort.base_of(sheet, RigLife.POSE_PARTS[pose.shown], dir, owner_id)
	world_sort.show_base(hull, pose.base, pose.frame)
