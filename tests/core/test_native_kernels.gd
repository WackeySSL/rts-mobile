extends GdUnitTestSuite
## NativeKernels (ADR 0013 section 3, plan P54r): the ABI check and the on-device self-check, with
## the library loaded (verify.sh always builds it). The self-check runs the seed-42 perf arena, as
## the perf card does, on the library's kernels and on GDScript spies in their place: one moves
## unit row 0 instead of running FLOW, TARGETING, SEPARATION, INTEGRATE or FOG (the mutated kernel
## of the ADR, once per bit of the mask), one runs the twin and makes the hash differ after a
## single tick: the first, the last, and two neighbours that no checkpoint ends, so a check that
## compares on a stride of 2 or more (at any offset), at the checkpoints or at the end only misses
## one of them.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const HEADER: String = "res://native/sim_kernels/src/bind/sim_kernels.h"
const SEED: int = 42
## The perf card's self-check length.
const TICKS: int = 60
const INTEGRATE_BIT: int = 1 << SimProbe.Phase.INTEGRATE


## Stands in for the library: abi_version() answers `version`.
class AbiKernels:
	extends RefCounted

	var version: Variant = 1

	func abi_version() -> Variant:
		return version


## Stands in for the library on FLOW, TARGETING, SEPARATION, INTEGRATE and FOG: each method moves
## unit row 0 one milli-tile instead of running its phase, and counts its calls per SimProbe.Phase.
class ShiftingKernels:
	extends RefCounted

	var calls: PackedInt32Array = PackedInt32Array()

	func _init() -> void:
		calls.resize(SimProbe.Phase.COUNT)

	func flow(world: World, _budget: int) -> void:
		_shift(world, SimProbe.Phase.FLOW)

	func targeting(world: World) -> void:
		_shift(world, SimProbe.Phase.TARGETING)

	func separation(world: World) -> void:
		_shift(world, SimProbe.Phase.SEPARATION)

	func integrate(world: World) -> void:
		_shift(world, SimProbe.Phase.INTEGRATE)

	func fog(world: World) -> void:
		_shift(world, SimProbe.Phase.FOG)

	func _shift(world: World, phase: int) -> void:
		calls[phase] += 1
		world.pos_x[0] += 1


## Stands in for the library on INTEGRATE: it runs the GDScript twin, and in the step of
## `blip_tick` it raises dropped_commands (a hashed count that no rule reads) by one, which the next
## call takes back, so the two Worlds differ after that tick only. It counts its calls and keeps
## what it saw: the positions at its first call (the spawn positions) and the most rows with an
## order at one call.
class BlipKernels:
	extends RefCounted

	var blip_tick: int = -1
	var calls: int = 0
	var first_pos_x: PackedInt32Array = PackedInt32Array()
	var ordered_max: int = 0

	func integrate(world: World) -> void:
		if calls == 0:
			first_pos_x = world.pos_x.duplicate()
		calls += 1
		var orders: PackedInt32Array = world.order
		ordered_max = maxi(ordered_max, orders.size() - orders.count(World.Order.IDLE))
		var mask: int = world.native_phases
		world.native_phases = 0
		Movement.integrate(world)
		world.native_phases = mask
		if world.tick == blip_tick:
			world.dropped_commands += 1
		elif world.tick == blip_tick + 1:
			world.dropped_commands -= 1


## New kernels of the library on every call, at the ABI of the C++ constant: both sides of the
## boundary hold the same number, read here from sim_kernels.h.
func test_create_gives_new_library_kernels_at_the_abi_of_sim_kernels_h() -> void:
	var kernels: Object = NativeKernels.create()
	assert_object(kernels).is_not_null()
	assert_str(kernels.get_class()).is_equal("SimKernels")
	assert_int(NativeKernels.ABI_VERSION).is_equal(1)
	assert_int(kernels.abi_version()).is_equal(NativeKernels.ABI_VERSION)
	assert_object(NativeKernels.create()).is_not_same(kernels)
	var line: RegEx = RegEx.create_from_string("constexpr int64_t ABI_VERSION = (\\d+);")
	var found: RegExMatch = line.search(FileAccess.get_file_as_string(HEADER))
	assert_object(found).is_not_null()
	assert_int(found.get_string(1).to_int()).is_equal(NativeKernels.ABI_VERSION)


## create() through its class seam: null for a class that ClassDB does not have and for one whose
## instance fails the ABI check (an engine RefCounted has no abi_version()), kernels for the
## library's class.
func test_create_gives_null_for_a_missing_class_or_one_that_fails_the_abi_check() -> void:
	assert_bool(ClassDB.class_exists(&"NoSuchKernels")).is_false()
	assert_object(NativeKernels._create(&"NoSuchKernels")).is_null()
	assert_bool(ClassDB.class_exists(&"RefCounted")).is_true()
	assert_object(NativeKernels._create(&"RefCounted")).is_null()
	assert_str(NativeKernels._create(NativeKernels.CLASS_NAME).get_class()).is_equal("SimKernels")


## Only an int equal to ABI_VERSION passes: not another version, not a float or a String that
## reads the same, not an object without abi_version() and not null.
func test_the_abi_check_takes_only_the_int_abi_version() -> void:
	var spy: AbiKernels = AbiKernels.new()
	var passed: Array[bool] = []
	for version: Variant in [1, 0, 2, -1, 1.0, "1", null]:
		spy.version = version
		passed.append(NativeKernels.abi_matches(spy))
	assert_array(passed).is_equal([true, false, false, false, false, false, false])
	assert_bool(NativeKernels.abi_matches(RefCounted.new())).is_false()
	assert_bool(NativeKernels.abi_matches(null)).is_false()
	assert_bool(NativeKernels.abi_matches(NativeKernels.create())).is_true()


## The perf card's case: 60 arena ticks on every phase the library reports, which holds the five
## ported phases on main (FLOW, TARGETING, SEPARATION, INTEGRATE and FOG).
func test_the_arena_matches_for_60_ticks_on_the_phases_of_the_library() -> void:
	var kernels: Object = NativeKernels.create()
	assert_str(kernels.get_class()).is_equal("SimKernels")
	var mask: int = kernels.phases()
	for phase: int in _ported_phases():
		assert_int((mask >> phase) & 1).override_failure_message("phase %d" % phase).is_equal(1)
	assert_bool(NativeKernels.self_check(_arena(), SEED, TICKS, kernels, mask)).is_true()


## The mutated kernel, on each bit of the mask in turn: the World it runs differs after the first
## tick, and the check stops there, having called that phase's kernel once and no other.
func test_a_kernel_that_moves_a_unit_instead_of_its_phase_is_a_mismatch(
	phase: int, _test_parameters := _ported()
) -> void:
	var spy: ShiftingKernels = ShiftingKernels.new()
	assert_bool(NativeKernels.self_check(_arena(), SEED, TICKS, spy, 1 << phase)).is_false()
	var once: PackedInt32Array = PackedInt32Array()
	once.resize(SimProbe.Phase.COUNT)
	once[phase] = 1
	assert_array(spy.calls).is_equal(once)


## With the mask 0 both Worlds run the twins and the kernels are never called; a mask needs
## kernels, and without them the check fails instead of calling a method on null.
func test_mask_0_matches_without_calling_the_kernels_and_a_mask_needs_kernels() -> void:
	var spy: ShiftingKernels = ShiftingKernels.new()
	assert_bool(NativeKernels.self_check(_arena(), SEED, TICKS, spy, 0)).is_true()
	var none: PackedInt32Array = PackedInt32Array()
	none.resize(SimProbe.Phase.COUNT)
	assert_array(spy.calls).is_equal(none)
	assert_bool(NativeKernels.self_check(_arena(), SEED, 1, null, 0)).is_true()
	assert_bool(NativeKernels.self_check(_arena(), SEED, 1, null, INTEGRATE_BIT)).is_false()


## The hash is compared after every tick: a difference that lasts one tick (the step `blip_tick`,
## World.tick during it) is a mismatch, found after that tick, while the same spy matches over the
## ticks before it. The spy saw the spawn positions of the seed it was given and the arena's orders
## applied, so the check runs the scenario with its seed and its orders.
func test_a_difference_that_lasts_one_tick_is_a_mismatch(
	blip_tick: int, _test_parameters := _blip_ticks()
) -> void:
	var before: BlipKernels = BlipKernels.new()
	before.blip_tick = blip_tick
	(
		assert_bool(NativeKernels.self_check(_arena(), SEED, blip_tick, before, INTEGRATE_BIT))
		. is_true()
	)
	assert_int(before.calls).is_equal(blip_tick)
	var blip: BlipKernels = BlipKernels.new()
	blip.blip_tick = blip_tick
	assert_bool(NativeKernels.self_check(_arena(), SEED, TICKS, blip, INTEGRATE_BIT)).is_false()
	assert_int(blip.calls).is_equal(blip_tick + 1)
	assert_array(blip.first_pos_x).is_equal(_arena_world(SEED).pos_x)
	assert_array(blip.first_pos_x).is_not_equal(_arena_world(SEED + 1).pos_x)
	assert_int(blip.ordered_max).is_greater(0)


## gdUnit4's parameter sets: the five ported phases on main, one case each.
func _ported() -> Array[Array]:
	var cases: Array[Array] = []
	for phase: int in _ported_phases():
		cases.append([phase])
	return cases


## The phases with a kernel on main, in pipeline order.
func _ported_phases() -> Array[int]:
	return [
		SimProbe.Phase.FLOW,
		SimProbe.Phase.TARGETING,
		SimProbe.Phase.SEPARATION,
		SimProbe.Phase.INTEGRATE,
		SimProbe.Phase.FOG
	]


## gdUnit4's parameter sets: the first and the last of the 60 ticks, and two neighbours (after
## them World.tick is 23 and 24, which the checkpoint period does not divide).
func _blip_ticks() -> Array[Array]:
	return [[0], [22], [23], [TICKS - 1]]


func _arena() -> ScenarioDef:
	return load(ARENA_PATH) as ScenarioDef


## The arena at tick 0 with the sim stream of `match_seed`, as self_check builds it.
func _arena_world(match_seed: int) -> World:
	return World.from_scenario(_arena(), DetRandom.create(match_seed, DetRandom.STREAM_SIM))
