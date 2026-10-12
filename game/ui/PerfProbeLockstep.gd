class_name PerfProbeLockstep
extends RefCounted
## Spike P26n: plays the GDScript mock tick and its C++ port (the GDExtension class
## ProbeTickNative) in lockstep and names the first difference. Used by the probe's mode 5 (a
## 60-tick self-check before the measurement) and by tests/perf/test_probe_tick_native.gd. The C++
## object is passed as a RefCounted because the class exists only when the library was built and
## loaded; check `ClassDB.class_exists(NATIVE_CLASS)` first.

const NATIVE_CLASS: String = "ProbeTickNative"
const SCALARS: Array[String] = ["tick", "dirty_count", "slice_cells"]
const ARRAYS: Array[String] = ["x", "y", "target", "seen", "dirty", "flow_cost"]


## "" when every compared field is equal, else the first difference as "name" for a scalar or
## "name[index]" for an array, followed by both values. The probe's fog patch consumes `dirty` and
## `dirty_count` on the C++ object while the run goes on (as it does on `sim`), so a run that
## published ticks compares with `with_dirty` false.
static func difference(gd: PerfProbeTick, cpp: RefCounted, with_dirty: bool = true) -> String:
	for name: String in SCALARS:
		if name == "dirty_count" and not with_dirty:
			continue
		var left: int = gd.get(name)
		var right: int = cpp.get(name)
		if left != right:
			return "%s: GDScript %d, C++ %d" % [name, left, right]
	for name: String in ARRAYS:
		if name == "dirty" and not with_dirty:
			continue
		var left: PackedInt32Array = gd.get(name)
		var right: PackedInt32Array = cpp.get(name)
		if left == right:
			continue
		if left.size() != right.size():
			return "%s: size GDScript %d, C++ %d" % [name, left.size(), right.size()]
		for i: int in left.size():
			if left[i] != right[i]:
				return "%s[%d]: GDScript %d, C++ %d" % [name, i, left[i], right[i]]
	return ""


## The name of the array or scalar in a `difference()` result: "seen" for "seen[417]: ...".
static func field_of(found: String) -> String:
	return found.split(":")[0].split("[")[0]


## Plays `ticks` ticks of both, the flow slice (`flow_cells`) on every 15th as the probe does, and
## compares everything after the start and after every call. Returns "" when they never differ, else
## "tick N: <difference>" for the first one (N is the GDScript tick of the call). Both
## objects must be fresh (the same start) and are advanced.
static func play(gd: PerfProbeTick, cpp: RefCounted, ticks: int, flow_cells: int) -> String:
	var found: String = difference(gd, cpp)
	if found != "":
		return "tick %d (start): %s" % [gd.tick, found]
	for _i: int in ticks:
		gd.step()
		cpp.step()
		found = difference(gd, cpp)
		if found != "":
			return "tick %d (step): %s" % [gd.tick, found]
		if gd.tick % 15 == 0:
			gd.flow_slice(flow_cells)
			cpp.flow_slice(flow_cells)
			found = difference(gd, cpp)
			if found != "":
				return "tick %d (flow_slice): %s" % [gd.tick, found]
	return ""
