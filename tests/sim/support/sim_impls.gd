extends RefCounted
## The two implementations of the simulation (ADR 0013 section 3), for the tests of a module that
## has a native kernel: `use(world, impl)` makes a World run the GDScript phases or the C++ ones,
## and a test loops over IMPLS. Not a test suite. A port PR adds its phase to EXPECTED_PHASES and
## its line to native/sim_kernels/src/bind/kernel_list.h; FLOW (P30n) is the first.

enum Impl { GDSCRIPT = 0, NATIVE = 1 }

const IMPLS: Array[int] = [Impl.GDSCRIPT, Impl.NATIVE]
## The SimProbe.Phase ids the library must report, one per line (SimProbe arrives with P33).
## The ids are fixed: FLOW 1, TARGETING 3, SEPARATION 5, INTEGRATE 6, FOG 10.
const EXPECTED_PHASES: Array[int] = [1]


## One bit per entry of `phases` (EXPECTED_PHASES), the mask the library has to report.
static func expected_mask(phases: Array[int] = EXPECTED_PHASES) -> int:
	var mask: int = 0
	for phase: int in phases:
		mask |= 1 << phase
	return mask


## New kernels, or null when the library is not loaded (verify.sh always builds it).
static func create_kernels() -> Object:
	if not ClassDB.class_exists(&"SimKernels"):
		return null
	return ClassDB.instantiate(&"SimKernels")


## Makes `world` run `impl`: NATIVE prepares it and attaches `kernels` (default: fresh ones) with
## `kernels.phases()` as the mask (a hand-built World too); GDSCRIPT detaches both. Returns the
## problems, empty when it worked: no library, a mask other than EXPECTED_PHASES, or kernels that
## are no SimKernels. They are attached either way, so a caller asserts the result is empty;
## ignoring it runs the native pass on the GDScript twin.
static func use(world: World, impl: int, kernels: Object = null) -> Array[String]:
	var problems: Array[String] = []
	world.kernels = null
	world.native_phases = 0
	if impl == Impl.GDSCRIPT:
		return problems
	if kernels == null:
		kernels = create_kernels()
	if kernels == null:
		problems.append("SimKernels is not loaded: run bash scripts/build-native.sh")
		return problems
	world.prepare()
	if kernels.get_class() != "SimKernels":
		problems.append("the kernels are a %s, not a SimKernels" % kernels.get_class())
	var mask: int = kernels.phases()
	if mask != expected_mask():
		problems.append("the library reports phases %d, not %d" % [mask, expected_mask()])
	world.kernels = kernels
	world.native_phases = mask
	return problems


## Whether `phase` really runs in C++ on `world`: the kernels are a SimKernels and the bit is set.
## A module's native pass asserts this, so that it cannot pass on the GDScript twin.
static func is_native(world: World, phase: int) -> bool:
	var kernels: Object = world.kernels
	return (
		kernels != null
		and kernels.get_class() == "SimKernels"
		and ((world.native_phases >> phase) & 1) == 1
	)
