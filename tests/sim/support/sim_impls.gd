extends RefCounted
## The two implementations of the simulation (ADR 0013 section 3), for the tests of a module that
## has a native kernel: `use(world, impl)` makes a World run the GDScript phases or the C++ ones,
## and a test loops over IMPLS. Not a test suite. A port PR adds its phase to EXPECTED_PHASES and
## its line to native/sim_kernels/src/bind/kernel_list.h; FLOW (P30n) is the first,
## INTEGRATE (P37n) the second, SEPARATION (P39n) the third.

enum Impl { GDSCRIPT = 0, NATIVE = 1 }

const IMPLS: Array[int] = [Impl.GDSCRIPT, Impl.NATIVE]
## gdUnit4's parameter sets for a test that runs under both implementations, one case each. gdUnit4
## calls a method of the suite by name for the parameter sets of a test, and it writes into the sets
## it gets (so they must not be constants): a suite has
## `func _both() -> Array[Array]: return SimImpls.CASES.duplicate(true)` and its tests are
## `func test_x(impl: int, _test_parameters := _both())`, which gdformat may wrap.
const CASES: Array[Array] = [[Impl.GDSCRIPT], [Impl.NATIVE]]
## The SimProbe.Phase ids the library must report (FLOW, SEPARATION and INTEGRATE until the next
## port). The ids are fixed (SimProbe), and test_kernel_abi.gd checks the C++ mirrors of them.
const EXPECTED_PHASES: Array[int] = [
	SimProbe.Phase.FLOW, SimProbe.Phase.SEPARATION, SimProbe.Phase.INTEGRATE
]


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
## are no SimKernels. With no library nothing is attached (the World is not even prepared); in the
## other two cases the kernels are attached all the same. So a caller asserts the result is empty;
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


## `use(world, impl)` and the checks of a module's native pass in one call: the kernels attached
## and `phase` really running in the implementation asked for (and not in the other). The
## problems, empty when it worked; a test asserts that.
static func attach(world: World, impl: int, phase: int) -> Array[String]:
	var problems: Array[String] = use(world, impl)
	if is_native(world, phase) != (impl == Impl.NATIVE):
		problems.append("phase %d does not run in the implementation asked for" % phase)
	return problems


## Whether `phase` really runs in C++ on `world`: the kernels are a SimKernels and the bit is set.
## A module's native pass asserts this, so that it cannot pass on the GDScript twin. It reads the
## World's two fields only; that the phase's entry (FlowCache.run, Movement.integrate) hands the
## call to the kernel at all is guarded by the spy case of tests/sim/test_kernel_dispatch.gd (each
## port adds its own).
static func is_native(world: World, phase: int) -> bool:
	var kernels: Object = world.kernels
	return (
		kernels != null
		and kernels.get_class() == "SimKernels"
		and ((world.native_phases >> phase) & 1) == 1
	)
