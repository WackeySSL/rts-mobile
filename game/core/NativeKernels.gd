class_name NativeKernels
extends RefCounted
## The native sim kernels seen from the Node side (ADR 0013 section 3): create() hands out the
## library's SimKernels when it is loaded and speaks this boundary's ABI, and self_check() is the
## on-device lockstep behind the perf card's self-check line (P50a2's seam, called before the perf
## arena's runner starts, P50b). game/sim never names SimKernels or ClassDB; game/core does it here.
## Static functions for the main thread; self_check() needs the DetRng autoload.

## The class that native/sim_kernels binds.
const CLASS_NAME: StringName = &"SimKernels"
## The boundary's version: equal to SimKernels::ABI_VERSION in
## native/sim_kernels/src/bind/sim_kernels.h, and both change with the boundary. A library that
## reports another version is not used.
const ABI_VERSION: int = 1


## New kernels, or null when the library is not loaded or reports another ABI version. It logs
## nothing: MatchRunner.start() reports a fallback, and the perf card its verdict.
static func create() -> Object:
	return _create(CLASS_NAME)


## create() for the class `kernel_class`: a new instance when ClassDB has the class and the
## instance passes the ABI check, null otherwise. Tests pass engine classes in place of the library.
static func _create(kernel_class: StringName) -> Object:
	if not ClassDB.class_exists(kernel_class):
		return null
	var kernels: Object = ClassDB.instantiate(kernel_class)
	return kernels if abi_matches(kernels) else null


## The ABI check: whether `kernels` answers abi_version() with the int ABI_VERSION. False for null
## and for an object without the method.
static func abi_matches(kernels: Object) -> bool:
	if kernels == null or not kernels.has_method(&"abi_version"):
		return false
	var version: Variant = kernels.call(&"abi_version")
	return typeof(version) == TYPE_INT and version == ABI_VERSION


## The on-device lockstep (ADR 0013 section 3). Two Worlds from `scenario` with the sim stream of
## `seed`: A runs the GDScript twins and B `kernels` on the phases of `mask` (one bit per
## SimProbe.Phase). Each is stepped by its own MatchLoop, inline (SYNC), for `ticks` ticks with the
## scenario's orders and nothing queued. True when state_hash() agrees after every tick; false at
## the first tick where it differs, and for a mask with no kernels. It builds its own Worlds and
## touches no runner, World or snapshot of the match.
@warning_ignore("shadowed_global_identifier")
static func self_check(
	scenario: ScenarioDef, seed: int, ticks: int, kernels: Object, mask: int
) -> bool:
	if mask != 0 and kernels == null:
		return false
	var path: String = scenario.resource_path if scenario != null else ""
	var worlds: Array[World] = []
	var loops: Array[MatchLoop] = []
	for _side: int in 2:
		var world: World = World.from_scenario(scenario, DetRng.create(seed, DetRandom.STREAM_SIM))
		world.prepare()
		loops.append(MatchLoop.create(scenario, path, seed, world))
		worlds.append(world)
	var twin: World = worlds[0]
	var native: World = worlds[1]
	native.kernels = kernels
	native.native_phases = mask
	var none: Array[Command] = []
	for _tick: int in ticks:
		loops[0].step(twin, none)
		loops[1].step(native, none)
		if twin.state_hash() != native.state_hash():
			return false
	return true
