class_name SquadPoses
extends RefCounted
## The squads' poses (P142, ADR 0027 sections 3 to 5). A squad that moved at least half a step in
## the last tick shows its `walk` frame on the Hull, `floor((travel + phase) / quarter) mod 4` of
## the ground it covered (`RigLife.travel_step`, the straight-line length, in the layer's per-row
## walk table), so the cadence follows its speed and the feet stop with it; one that has stood
## `idle_after_ms` with no target shows an `idle` frame in a window of each cycle
## (`RigLife.pose_step`); else the standing hull. `UnitLayer` calls `begin` once a frame and `step`
## for each squad with poses, and `turn` when a hull turns. Only a rig inside the view rect is
## written; `reduced` keeps both poses.
## The Hull draws the standing `hull` frame, a `walk` frame or an `idle` frame of the same atlas
## page. Their anchors differ by a pixel or two and `WorldSort.show_base` writes only the region, so
## a change of pose writes the sprite's offset too (`RigLife.Pose.offsets`, read from the sheet when
## the rig is dressed). The three bases for the hull's direction are resolved when the rig is
## dressed and when it turns, so a change of pose or frame is a table read and builds no string key.

var world_sort: WorldSort  ## The sorted world whose atlas the Hull draws from.
var rig_life: RigLife  ## Its `writes` counts the sprite writes of the poses.

# What `begin` leaves for the frame's `step` calls: arrays are shared, not copied.
var _walk: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _targets: PackedInt32Array = PackedInt32Array()
var _tick: int = 0
var _tick_ms: float = 0.0
var _alpha: float = 0.0
var _now_ms: float = 0.0


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
	_resolve(pose, sheet, UnitLayer.D_EAST, owner_id)
	for part: int in [RigLife.POSE_WALK, RigLife.POSE_IDLE]:
		if world_sort.frame_count_at(pose.bases[part]) != pose.frames[part]:
			pose.quarter = 0
			pose.stride = 0


## Starts a frame: snapshot tick `tick` at `alpha` into it, the idle clock `now_ms`, the layer's
## walk table and the unit ids and targets of the snapshot.
func begin(
	tick: int,
	alpha: float,
	now_ms: float,
	walk: PackedInt32Array,
	ids: PackedInt32Array,
	targets: PackedInt32Array
) -> void:
	_tick = tick
	_tick_ms = LifeClock.tick_ms(tick)
	_alpha = alpha
	_now_ms = now_ms
	_walk = walk
	_ids = ids
	_targets = targets


## Brings squad row `row` (its pose record, idle record and Hull) to its pose: the walk table to
## this tick (`moved` is the squared milli it moved, `walking` whether that is half a step or
## more), the idle record to the idle clock and, for a rig inside the view rect (`in_view`), the
## Hull to the walk frame of the ground covered, an idle frame or the standing hull. It is written
## only when the pose or frame changes: a new pose writes the offset and the region, a new frame
## the region.
func step(
	row: int,
	pose: RigLife.Pose,
	idle: RigLife.Idle,
	hull: Sprite2D,
	moved: int,
	walking: bool,
	in_view: bool
) -> void:
	var at: int = row * RigLife.WALK_INTS
	RigLife.travel_step(_walk, at, _tick, moved, walking, pose.stride)
	var idle_frame: int = rig_life.pose_step(
		idle,
		_ids[row],
		_now_ms,
		_tick_ms,
		not walking and _targets[row] == 0,
		pose.frames[RigLife.POSE_IDLE]
	)
	if not in_view:
		return
	var want: int = RigLife.POSE_HULL
	var frame: int = 0
	if walking:
		want = RigLife.POSE_WALK
		frame = RigLife.walk_frame(_walk, at, _alpha, pose.quarter, pose.frames[RigLife.POSE_WALK])
	elif idle_frame >= 0:
		want = RigLife.POSE_IDLE
		frame = idle_frame
	if want == pose.shown and frame == pose.frame:
		return
	if want != pose.shown:
		pose.shown = want
		hull.offset = pose.offsets[want]
	pose.frame = frame
	world_sort.show_base(hull, pose.bases[want], frame)
	rig_life.writes += 1


## Turns the Hull to the new direction `dir` (`d<NN>`): the bases of the poses for it, and the frame
## it shows in the pose it is in.
func turn(pose: RigLife.Pose, hull: Sprite2D, sheet: IsoSheetDef, dir: int, owner_id: int) -> void:
	_resolve(pose, sheet, dir, owner_id)
	world_sort.show_base(hull, pose.bases[pose.shown], pose.frame)


## The bases of the hull, and of the walk and idle where the rig has poses, for direction `dir`.
func _resolve(pose: RigLife.Pose, sheet: IsoSheetDef, dir: int, owner_id: int) -> void:
	pose.bases[RigLife.POSE_HULL] = world_sort.base_of(sheet, RigLife.POSE_PARTS[0], dir, owner_id)
	if pose.stride > 0:
		pose.bases[RigLife.POSE_WALK] = world_sort.base_of(
			sheet, RigLife.POSE_PARTS[1], dir, owner_id
		)
		pose.bases[RigLife.POSE_IDLE] = world_sort.base_of(
			sheet, RigLife.POSE_PARTS[2], dir, owner_id
		)
