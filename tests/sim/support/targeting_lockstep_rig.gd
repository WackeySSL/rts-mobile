extends RefCounted
## The rig of the TARGETING lockstep suites (ADR 0013 section 4, plan P41n2): two Worlds built by
## one function, the first running the GDScript phases (the twin) and the second the C++ kernels,
## each stepped by its own MatchLoop with the same orders, and compared after every tick: the
## state hash and the full state of StateDiff (every shape list, every scalar, the helpers: the
## flow cache, both grids and the fog). It is TARGETING's: pair() attaches that phase, and the
## kernels' World runs TARGETING alone, with the other phases that have kernels (`WITH_PORTED`), or
## with every phase the library has (`native_mask`). The INTEGRATE rig (lockstep_rig.gd) and the
## SEPARATION rig (separation_lockstep_rig.gd) are left as they are; this one is a sibling.
##
## While it steps, a TargetingTallyProbe on the twin's World counts what the run reached (rows
## scanned, ties, fallbacks, holds, chases, line tests, long segments), so that a case can assert
## that it did not pass by never reaching a rule; the rig also checks the probe's count of the rows
## looked at and of the line tests against the phase's own (`stats[TARGET_CANDIDATES]` and
## `stats[LINE_CHECKS]`) after every tick, so a probe that works the rule out another way than the
## rule fails the case instead of vouching for it. P46b adds a vision rule to both Targeting
## versions and re-runs these suites: it changes the probe's count() the same way, and everything
## else here, the fog included, is compared already. Not a test suite.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const TallyProbe: GDScript = preload("res://tests/sim/support/targeting_tally_probe.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
## The phases that the kernels' World runs in C++: TARGETING alone (so that a difference can only
## be the TARGETING kernel's), TARGETING with the other ports that have merged (FLOW, SEPARATION and
## INTEGRATE; a later port is in ALL), or ALL (the mask the library reports).
const ONLY: int = 1 << TARGETING
const WITH_PORTED: int = (
	(1 << TARGETING)
	| (1 << SimProbe.Phase.FLOW)
	| (1 << SimProbe.Phase.SEPARATION)
	| (1 << SimProbe.Phase.INTEGRATE)
)
const ALL: int = -1

## [the twin's World, the kernels' World].
var worlds: Array[World] = []
var loops: Array[MatchLoop] = []
## What SimImpls.attach found wrong on either World: the test asserts it is empty.
var problems: Array[String] = []
## The probe of the twin's World; its `tally` holds the counts (TallyProbe.NAMES).
var probe: TallyProbe
## The rows the twin's World held when each stepped tick began (step() adds them): the tally's
## `rows` has to equal it, since nothing joins or leaves between the start of a tick and TARGETING.
var rows_stepped: int = 0
## What the work counts held before the phase that is being checked (0: Sim.step clears them).
var _looks_before: int = 0
var _checks_before: int = 0


## The pair of `build` (a Callable that returns the same World each call): the twin, and a World
## with the kernels attached that runs `native_mask` in C++. What SimImpls.attach found wrong (no
## library, a wrong mask, TARGETING not running where it was asked) is added to `found_problems`,
## which the caller has to pass and to assert empty: left out, the native side would run on the
## twin without a word.
static func pair(build: Callable, native_mask: int, found_problems: Array[String]) -> Array[World]:
	var found: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		found_problems.append_array(SimImpls.attach(world, impl, TARGETING))
		if impl == SimImpls.Impl.NATIVE and native_mask != ALL:
			world.native_phases = native_mask
			if not SimImpls.is_native(world, TARGETING):
				found_problems.append("TARGETING is not in the mask %d" % native_mask)
		found.append(world)
	return found


## A rig over the pair of `build`; see pair(). Returns self.
func setup(build: Callable, native_mask: int = ONLY) -> RefCounted:
	worlds = pair(build, native_mask, problems)
	for world: World in worlds:
		loops.append(MatchLoop.create(null, "", 0, world))
	probe = TallyProbe.new(worlds[0])
	return self


## The counts of the twin's side, by TallyProbe.NAMES.
func tally() -> Dictionary[StringName, int]:
	return probe.tally


## Steps both Worlds one tick. `orders` is a Callable (world, tick) -> Array[Command] that makes the
## commands of that tick (it runs once per World, so each gets its own Command objects). Returns ""
## or the difference.
func step(orders: Callable = Callable()) -> String:
	_looks_before = 0
	_checks_before = 0
	rows_stepped += worlds[0].unit_count()
	for index: int in worlds.size():
		var world: World = worlds[index]
		var queued: Array[Command] = []
		if orders.is_valid():
			queued = orders.call(world, world.tick)
		loops[index].step(world, queued, probe if index == 0 else null)
	return _checked("tick %d" % worlds[0].tick)


## Steps `ticks` ticks (see step()); stops at the first difference and returns it, else "".
func run(ticks: int, orders: Callable = Callable()) -> String:
	for _tick: int in ticks:
		var found: String = step(orders)
		if found != "":
			return found
	return ""


## One TARGETING phase on both Worlds as they stand, done the way Sim.step does it (the work counts
## cleared, the grid rebuilt from the positions, Targeting.run), and compared. The units and the
## tick are not moved, so the same call can follow a change to the rules or to the grid. With
## `keep_counts` the work counts are left as the builder made them, the phase adds its looks and its
## line tests to what the tick has counted (`stats[...] +=`), and the probe's counts are checked
## against the sums. With `keep_grid` the grid is left as the builder made it (a grid that
## SpatialGrid.configure never makes, or lists the builder wrote by hand).
func once(keep_counts: bool = false, keep_grid: bool = false) -> String:
	var counts: PackedInt32Array = worlds[0].stats
	_looks_before = counts[World.Stat.TARGET_CANDIDATES] if keep_counts else 0
	_checks_before = counts[World.Stat.LINE_CHECKS] if keep_counts else 0
	probe.before()
	for world: World in worlds:
		if not keep_counts:
			world.stats.fill(0)
		world.prepare()
		if not keep_grid:
			world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
		Targeting.run(world)
	probe.count()
	rows_stepped += worlds[0].unit_count()
	return _checked("the phase")


## "" when the Worlds agree (the same state hash and the same full state), else what differs,
## headed by `where`. A case that drives the phase by hand calls it too.
func compare(where: String) -> String:
	var found: String = LockstepRig.difference(worlds[0], worlds[1])
	return "" if found == "" else "%s: %s" % [where, found]


## compare(), and then whether the probe's counts are the phase's own: a probe that works the rule
## out another way fails the case instead of vouching for it. The phase's counts are the ones the
## probe read at the TARGETING mark (INTENTS adds its own line tests to the second one later).
func _checked(where: String) -> String:
	var found: String = compare(where)
	if found != "":
		return found
	var looks: int = probe.phase_looks - _looks_before
	var checks: int = probe.phase_checks - _checks_before
	if probe.last_looks != looks:
		return (
			"%s: the probe counts %d rows looked at, the phase %d"
			% [where, probe.last_looks, looks]
		)
	if probe.last_checks != checks:
		return (
			"%s: the probe counts %d line tests, the phase %d" % [where, probe.last_checks, checks]
		)
	return ""


## A tally with every count at 0, for a suite that adds the tallies of several runs.
static func empty_tally() -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for name: StringName in TallyProbe.NAMES:
		total[name] = 0
	return total


## Adds the counts of `tally` to `total` (see empty_tally()).
static func add_to(total: Dictionary[StringName, int], tally: Dictionary[StringName, int]) -> void:
	for name: StringName in TallyProbe.NAMES:
		total[name] += tally[name]
