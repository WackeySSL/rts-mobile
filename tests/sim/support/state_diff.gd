extends RefCounted
## The full state of two Worlds, for the lockstep tests of the native kernels (ADR 0013 section 4):
## every shape-list array, every hashed and unhashed scalar, and each helper object (fog, the flow
## cache and its slots, both grids) by its own lists, so a missed or misnamed `set` of a kernel
## shows. `native_phases` and the NON_STATE_MEMBERS are not state. Not a test suite.


## "" when the Worlds agree, else the name of the first member that differs ("flow.fields[3].next").
static func first(a: World, b: World) -> String:
	var lists: Array = World.ROW_ARRAYS + World.TYPE_ARRAYS + World.WEAPON_ARRAYS
	lists += World.PROJECTILE_ARRAYS + World.MAP_ARRAYS + World.SCRATCH_ARRAYS
	lists += World.RUNTIME_ARRAYS + World.HASHED_SCALARS + World.UNHASHED_SCALARS
	for member: StringName in lists:
		if member != &"native_phases" and a.get(member) != b.get(member):
			return String(member)
	if a.rng.state() != b.rng.state():
		return "rng"
	var helpers: Dictionary[StringName, Array] = {&"flow": FlowCache.UNHASHED}
	helpers[&"fog"] = FogGrid.HASHED + FogGrid.UNHASHED
	helpers[&"sep_grid"] = SpatialGrid.UNHASHED
	helpers[&"target_grid"] = SpatialGrid.UNHASHED
	for helper: StringName in helpers:
		for member: StringName in helpers[helper]:
			if a.get(helper).get(member) != b.get(helper).get(member):
				return "%s.%s" % [helper, member]
	if a.flow.fields.size() != b.flow.fields.size():
		return "flow.fields"
	for slot: int in a.flow.fields.size():
		for member: StringName in FlowField.UNHASHED:
			if a.flow.fields[slot].get(member) != b.flow.fields[slot].get(member):
				return "flow.fields[%d].%s" % [slot, member]
	return ""
