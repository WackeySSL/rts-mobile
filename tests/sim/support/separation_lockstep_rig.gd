extends RefCounted
## The rig of the SEPARATION lockstep suites (ADR 0013 section 4, plan P39n2): two Worlds built by
## one function, the first running the GDScript phases (the twin) and the second the C++ kernels,
## each stepped by its own MatchLoop with the same orders, and compared after every tick: the
## state hash and the full state of StateDiff (every shape list, every scalar, the helpers). It is
## SEPARATION's: pair() attaches that phase, and the kernels' World runs SEPARATION alone, with
## INTEGRATE, or with every phase the library has (`native_mask`). The INTEGRATE rig
## (lockstep_rig.gd) is left as it is; this one takes its comparison and its id lists.
##
## While it steps, a SeparationTallyProbe on the twin's World counts what the run reached (looks,
## overlaps, rows that stopped at the cap on hits or on looks, fixed pushes, pairs of a moving and
## an idle unit, rows at the edge of the grid), so that a case can assert that it did not pass by
## never reaching a rule; the rig also checks the probe's count of looks against the phase's own
## (`stats[SEP_PAIRS]`) after every tick, so a probe that scans another way than the rule fails
## the case instead of vouching for it. Not a test suite.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const TallyProbe: GDScript = preload("res://tests/sim/support/separation_tally_probe.gd")
const SEPARATION: int = SimProbe.Phase.SEPARATION
const INTEGRATE: int = SimProbe.Phase.INTEGRATE
## The phases that the kernels' World runs in C++: SEPARATION alone (so that a difference can only
## be the SEPARATION kernel's), SEPARATION and INTEGRATE, or ALL (the mask the library reports).
const ONLY: int = 1 << SEPARATION
const WITH_INTEGRATE: int = (1 << SEPARATION) | (1 << INTEGRATE)
const ALL: int = -1

## [the twin's World, the kernels' World].
var worlds: Array[World] = []
var loops: Array[MatchLoop] = []
## What SimImpls.attach found wrong on either World: the test asserts it is empty.
var problems: Array[String] = []
## The probe of the twin's World; its `tally` holds the counts (TallyProbe.NAMES).
var probe: TallyProbe
## The rows the twin's World held when each stepped tick began (step() adds them): the tally's
## `rows` has to equal it, since nothing joins or leaves between the start of a tick and SEPARATION.
var rows_stepped: int = 0
## What stats[SEP_PAIRS] held before the phase that is being checked (0: Sim.step clears it).
var _counted: int = 0


## The pair of `build` (a Callable that returns the same World each call): the twin, and a World
## with the kernels attached that runs `native_mask` in C++. What SimImpls.attach found wrong (no
## library, a wrong mask, SEPARATION not running where it was asked) is added to `found_problems`,
## which the caller has to pass and to assert empty: left out, the native side would run on the
## twin without a word.
static func pair(build: Callable, native_mask: int, found_problems: Array[String]) -> Array[World]:
	var found: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		found_problems.append_array(SimImpls.attach(world, impl, SEPARATION))
		if impl == SimImpls.Impl.NATIVE and native_mask != ALL:
			world.native_phases = native_mask
			if not SimImpls.is_native(world, SEPARATION):
				found_problems.append("SEPARATION is not in the mask %d" % native_mask)
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
	_counted = 0
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


## One SEPARATION phase on both Worlds as they stand, done the way Sim.step does it (the work
## counts cleared, the grid rebuilt from the positions, Separation.run), and compared. The units
## and the tick are not moved, so the same call can follow a change to the rules. With
## `keep_counts` the work counts are left as the builder made them, the phase adds its looks to what
## the tick has counted (stats[SEP_PAIRS] +=), and the probe's count is checked against the sum.
func once(keep_counts: bool = false) -> String:
	_counted = worlds[0].stats[World.Stat.SEP_PAIRS] if keep_counts else 0
	for world: World in worlds:
		if not keep_counts:
			world.stats.fill(0)
		world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
		Separation.run(world)
	probe.last_looks = TallyProbe.count(worlds[0], probe.tally)
	return _checked("the phase")


## "" when the Worlds agree (the same state hash and the same full state), else what differs,
## headed by `where`. A case that drives the phase by hand calls it too.
func compare(where: String) -> String:
	var found: String = LockstepRig.difference(worlds[0], worlds[1])
	return "" if found == "" else "%s: %s" % [where, found]


## compare(), and then whether the probe's count of looks is the phase's own: a probe that scans
## another way than the rule fails the case instead of vouching for it.
func _checked(where: String) -> String:
	var found: String = compare(where)
	var phase_looks: int = worlds[0].stats[World.Stat.SEP_PAIRS] - _counted
	if found == "" and probe.last_looks != phase_looks:
		return (
			"%s: the probe counts %d looks, the phase %d" % [where, probe.last_looks, phase_looks]
		)
	return found
