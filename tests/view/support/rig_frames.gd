extends RefCounted
## What a rig shows, read back from the atlas it draws from (plan P114): a sprite's region is the
## region of exactly one frame, so the frame index `d<NN>` of a part is found by comparing it with
## the regions the atlas holds for the part's directions. Not a test suite.


## The frame index the part (`hull`, `turret` or `shadow`) of row `row` shows, -2 when its region is
## none of the part's frames and -3 when the row has no such sprite.
static func dir(layer: UnitLayer, row: int, part: StringName) -> int:
	var node: Node = layer.rig(row).get_node_or_null(String(part).capitalize())
	var snap: MatchSnapshot = layer.runner.snapshot
	var art_id: StringName = snap.type_ids[snap.type_index[row]]
	var sheet: IsoSheetDef = layer.world_sort.sheet(art_id)
	if node == null or sheet == null:
		return -3
	var slot: int = layer.world_sort.slot_of(snap.owner[row])
	for frame: int in sheet.directions(part):
		var region: Rect2i = layer.world_sort.atlas.region(art_id, part, frame, slot)
		if Rect2i(node.region_rect) == region:
			return frame
	return -2


## The frame index of grid angle `angle` among 16 (or among 8, a squad's), as the layer picks it: a
## second, plain statement of the rule, `d06` east on the grid and 22.5 degrees a step.
@warning_ignore("integer_division")
static func of_angle(angle: float, counts: int = 16) -> int:
	var step: float = TAU / counts
	return posmod(roundi(angle / step) * (16 / counts) + 6, 16)
