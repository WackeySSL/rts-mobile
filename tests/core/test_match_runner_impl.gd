extends GdUnitTestSuite
## MatchRunner.sim_impl (ADR 0013 section 3, plan P54r): resolve_impl() and fallback_log() as
## tables over every implementation, library state and OS name (passed in, so no case logs the
## Android error), start()'s seam _use_impl() with the kernels and the OS name passed in (the
## warning and the silent fallback; the errors stay in the table, as verify.sh rejects ERROR:
## lines), and runners on the seed-42 perf arena with the library loaded (verify.sh always builds
## it): GDSCRIPT by default with no kernels, NATIVE and AUTO with the library's kernels and mask,
## and the same hashes as a GDSCRIPT runner. A suite of its own: test_match_runner.gd holds
## gdlint's 20 public methods.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42
const TICKS: int = 45
const G: int = MatchRunner.SimImpl.GDSCRIPT
const N: int = MatchRunner.SimImpl.NATIVE
const A: int = MatchRunner.SimImpl.AUTO
const NONE: int = MatchRunner.ImplLog.NONE
const WARN: int = MatchRunner.ImplLog.WARNING
const ERROR: int = MatchRunner.ImplLog.ERROR
const OS_NAMES: Array[String] = ["Android", "Linux", "Windows", "macOS", "Web"]
## resolve_impl per OS name, for GDSCRIPT, NATIVE and AUTO in turn, each without and with the
## library. The same on every OS: AUTO means NATIVE whenever the class exists (ADR 0013 section 3);
## the web runs the twins because its export packs no library (section 7).
const RESOLVED: Dictionary[String, Array] = {
	"Android": [G, G, G, N, G, N],
	"Linux": [G, G, G, N, G, N],
	"Windows": [G, G, G, N, G, N],
	"macOS": [G, G, G, N, G, N],
	"Web": [G, G, G, N, G, N],
}
## fallback_log per OS name, for GDSCRIPT, NATIVE and AUTO asked in turn, each resolved to GDSCRIPT
## and to NATIVE: NATIVE without the library is an error everywhere, AUTO's fallback an error on
## Android, nothing on the web and a warning elsewhere.
const LOGGED: Dictionary[String, Array] = {
	"Android": [NONE, NONE, ERROR, NONE, ERROR, NONE],
	"Linux": [NONE, NONE, ERROR, NONE, WARN, NONE],
	"Windows": [NONE, NONE, ERROR, NONE, WARN, NONE],
	"macOS": [NONE, NONE, ERROR, NONE, WARN, NONE],
	"Web": [NONE, NONE, ERROR, NONE, NONE, NONE],
}
## What _use_impl() pushes for AUTO without the library on Linux.
const AUTO_LINUX_WARNING: String = (
	"MatchRunner: sim_impl AUTO runs the GDScript twins on Linux: "
	+ "no SimKernels library of ABI 1"
)


func after_test() -> void:
	CommandQueue.clear()


func test_the_impl_values_and_the_default_runner_runs_the_twins() -> void:
	assert_array([G, N, A]).is_equal([0, 1, 2])
	assert_array([NONE, WARN, ERROR]).is_equal([0, 1, 2])
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(runner.sim_impl).is_equal(G)
	var stored: bool = false
	for property: Dictionary in runner.get_property_list():
		if property["name"] == "sim_impl":
			stored = (property["usage"] & PROPERTY_USAGE_STORAGE) != 0
	assert_bool(stored).is_true()  # So a scene can set AUTO (P50b).
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.start()
	assert_object(runner.world.kernels).is_null()
	assert_int(runner.world.native_phases).is_equal(0)


func test_resolve_impl_for_every_impl_library_and_os() -> void:
	assert_array(RESOLVED.keys()).is_equal(OS_NAMES)
	for os_name: String in OS_NAMES:
		var found: Array[int] = []
		for impl: int in [G, N, A]:
			for has_library: bool in [false, true]:
				found.append(MatchRunner.resolve_impl(impl, has_library, os_name))
		assert_array(found).override_failure_message(os_name).is_equal(RESOLVED[os_name])
	# A value outside the enum asks for nothing native.
	for impl: int in [-1, 3]:
		assert_int(MatchRunner.resolve_impl(impl, true, "Linux")).is_equal(G)


func test_fallback_log_for_every_impl_resolution_and_os() -> void:
	assert_array(LOGGED.keys()).is_equal(OS_NAMES)
	for os_name: String in OS_NAMES:
		var found: Array[int] = []
		for impl: int in [G, N, A]:
			for resolved: int in [G, N]:
				found.append(MatchRunner.fallback_log(impl, resolved, os_name))
		assert_array(found).override_failure_message(os_name).is_equal(LOGGED[os_name])
		# The level for each request without the library, through both functions (what start()
		# pushes for it: the _use_impl cases below).
		var missing: Array[int] = []
		for impl: int in [G, N, A]:
			var resolved: int = MatchRunner.resolve_impl(impl, false, os_name)
			missing.append(MatchRunner.fallback_log(impl, resolved, os_name))
		var expected: Array = [LOGGED[os_name][0], LOGGED[os_name][2], LOGGED[os_name][4]]
		assert_array(missing).override_failure_message(os_name).is_equal(expected)
	assert_int(MatchRunner.fallback_log(3, G, "Android")).is_equal(NONE)


## NATIVE attaches the library's kernels with the mask it reports, and the run keeps the hashes of
## a GDSCRIPT runner after every tick and at every checkpoint. A restart keeps the implementation
## on the new World, and a restart after switching to GDSCRIPT drops it.
func test_a_native_runner_keeps_the_hashes_of_a_gdscript_runner() -> void:
	var twin: MatchRunner = _runner(G)
	var native: MatchRunner = _runner(N)
	_assert_native(native)
	assert_object(twin.world.kernels).is_null()
	var differs: Array[int] = []
	for _tick: int in TICKS:
		twin.run_ticks(1)
		native.run_ticks(1)
		if native.world.state_hash() != twin.world.state_hash():
			differs.append(native.world.tick)
	assert_array(differs).is_empty()
	assert_array(native.replay.checkpoint_ticks).is_equal(PackedInt32Array([15, 30, 45]))
	assert_array(native.replay.checkpoint_hashes).is_equal(twin.replay.checkpoint_hashes)
	assert_int(native.last_hash).is_equal(twin.last_hash)
	var first: Object = native.world.kernels
	native.start()
	_assert_native(native)
	assert_object(native.world.kernels).is_not_same(first)
	native.sim_impl = MatchRunner.SimImpl.GDSCRIPT
	native.start()
	assert_object(native.world.kernels).is_null()
	assert_int(native.world.native_phases).is_equal(0)


## AUTO runs native wherever the library is loaded (headless Linux here).
func test_an_auto_runner_with_the_library_runs_native() -> void:
	var twin: MatchRunner = _runner(G)
	var auto_runner: MatchRunner = _runner(A)
	_assert_native(auto_runner)
	twin.run_ticks(15)
	auto_runner.run_ticks(15)
	assert_int(auto_runner.last_hash).is_not_equal(0)
	assert_int(auto_runner.last_hash).is_equal(twin.last_hash)


## start()'s seam without the library: AUTO falls back to the twins with one warning on a desktop
## and silently on the web, and so does GDSCRIPT on Android; the World keeps no kernels and the
## mask 0. gdUnit4 fails a case on a push it does not expect, so the silent ones push nothing.
func test_use_impl_without_the_library_warns_on_a_desktop_only() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.sim_impl = MatchRunner.SimImpl.AUTO
	var desktop: World = _world()
	await (
		assert_error(func() -> void: runner._use_impl(desktop, null, "Linux"))
		. is_push_warning(AUTO_LINUX_WARNING)
	)
	var web: World = _world()
	await assert_error(func() -> void: runner._use_impl(web, null, "Web")).is_success()
	runner.sim_impl = MatchRunner.SimImpl.GDSCRIPT
	var android: World = _world()
	await assert_error(func() -> void: runner._use_impl(android, null, "Android")).is_success()
	for world: World in [desktop, web, android]:
		assert_object(world.kernels).is_null()
		assert_int(world.native_phases).is_equal(0)


## start()'s seam with the library: AUTO and NATIVE attach the kernels and their mask silently on
## every OS, the web included; GDSCRIPT attaches nothing.
func test_use_impl_with_the_library_runs_native_on_every_os() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	for impl: int in [A, N, G]:
		runner.sim_impl = impl
		for os_name: String in OS_NAMES:
			var world: World = _world()
			var kernels: Object = NativeKernels.create()
			await (
				assert_error(func() -> void: runner._use_impl(world, kernels, os_name)).is_success()
			)
			var native: bool = impl != G
			assert_object(world.kernels).is_same(kernels if native else null)
			assert_int(world.native_phases).is_equal(SimImpls.expected_mask() if native else 0)


## A started runner on the seed-42 arena with `impl`.
func _runner(impl: int) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = SEED
	runner.sim_impl = impl
	runner.start()
	return runner


## The seed-42 arena at tick 0, as start() builds it, for the seam cases.
func _world() -> World:
	var arena: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	return World.from_scenario(arena, DetRandom.create(SEED, DetRandom.STREAM_SIM))


## The runner's World holds SimKernels with the mask the library reports, which is
## EXPECTED_PHASES', and the four ported phases run in C++.
func _assert_native(runner: MatchRunner) -> void:
	var world: World = runner.world
	assert_object(world.kernels).is_not_null()
	assert_str(world.kernels.get_class()).is_equal("SimKernels")
	assert_int(world.native_phases).is_equal(world.kernels.phases())
	assert_int(world.native_phases).is_equal(SimImpls.expected_mask())
	for phase: int in [SimProbe.Phase.FLOW, SimProbe.Phase.SEPARATION, SimProbe.Phase.INTEGRATE]:
		(
			assert_bool(SimImpls.is_native(world, phase))
			. override_failure_message("%d" % phase)
			. is_true()
		)
