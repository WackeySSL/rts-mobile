extends RefCounted
## The rig of the FOG lockstep suites (ADR 0013 section 4, plan P46n2): two Worlds built by one
## function, the first running the GDScript phases (the twin) and the second the C++ kernels, each
## stepped by its own MatchLoop with the same orders, and compared after every tick: the state hash
## and the full state of StateDiff (every shape list, every scalar, the helpers: the flow cache,
## both grids and the fog with its visible counts, explored bytes, versions, dirty blocks, counts,
## flags and `listed` marks). It is FOG's: pair() attaches that phase, and the kernels' World runs
## FOG alone, with the other ports (`WITH_PORTED`), or with every phase the library has
## (`native_mask`). The TARGETING rig (targeting_lockstep_rig.gd) and the others are left as they
## are; this one is a sibling.
##
## While it steps, a FogTallyProbe on the twin's World counts what the run reached (moves, overlaps,
## clipped discs, flips, listed cells, overflows, version flips, deaths on a player's turn), so that
## a case can assert that it did not pass by never reaching a rule. The probe works the phase out
## again from its definition, and after every tick the rig holds the twin to it (`last_mismatches`:
## visible, explored, listed, the dirty blocks, counts and flags, versions, `fog_cell` and the cells
## covered), so a probe that works the rule out another way than the rule fails the case instead of
## vouching for it. A case can also switch on `derive_every` (plan P65, ADR 0016): `visible` is not
## in the state hash, so the rig then rebuilds it from the rows of each World (fog_derivation.gd)
## and fails the case when it is not what the rows say, for the twin and for the kernels alike.
## Not a test suite.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const TallyProbe: GDScript = preload("res://tests/sim/support/fog_tally_probe.gd")
const Derivation: GDScript = preload("res://tests/sim/support/fog_derivation.gd")
const FOG: int = SimProbe.Phase.FOG
## The phases that the kernels' World runs in C++: FOG alone (so that a difference can only be the
## FOG kernel's), FOG with the other ports (FLOW, TARGETING, SEPARATION and INTEGRATE: the five that
## have a kernel), or ALL (the mask the library reports: the same as WITH_PORTED until a sixth
## kernel merges).
const ONLY: int = 1 << FOG
const WITH_PORTED: int = (
	(1 << FOG)
	| (1 << SimProbe.Phase.FLOW)
	| (1 << SimProbe.Phase.TARGETING)
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
## The rows the twin's World held when each stepped tick began, after the orders of the case changed
## it (step() and once() add them): the tally's `rows` and `deaths` have to add up to it, since only
## a death takes a row out between that and the FOG phase.
var rows_stepped: int = 0
## Every how many ticks (World.tick) the counts of both Worlds are rebuilt from their rows and
## compared with fog.visible; 0 = never (the default: a rebuild costs the rows times the area of a
## disc). The phase that is driven by hand (once()) checks at every call. A World whose grid is
## not whole (Worlds.bend) has no fog to rebuild, so a case with one leaves it at 0.
var derive_every: int = 0


## The pair of `build` (a Callable that returns the same World each call): the twin, and a World
## with the kernels attached that runs `native_mask` in C++. What SimImpls.attach found wrong (no
## library, a wrong mask, FOG not running where it was asked) is added to `found_problems`, which
## the caller has to pass and to assert empty: left out, the native side would run on the twin
## without a word.
static func pair(build: Callable, native_mask: int, found_problems: Array[String]) -> Array[World]:
	var found: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		found_problems.append_array(SimImpls.attach(world, impl, FOG))
		if impl == SimImpls.Impl.NATIVE and native_mask != ALL:
			world.native_phases = native_mask
			if not SimImpls.is_native(world, FOG):
				found_problems.append("FOG is not in the mask %d" % native_mask)
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
## commands of that tick (it may change the World too, which it does the same way for both): it
## runs once per World, so each gets its own Command objects. Returns "" or the difference.
func step(orders: Callable = Callable()) -> String:
	for index: int in worlds.size():
		var world: World = worlds[index]
		var queued: Array[Command] = []
		if orders.is_valid():
			queued = orders.call(world, world.tick)
		if index == 0:
			rows_stepped += world.unit_count()
		loops[index].step(world, queued, probe if index == 0 else null)
	return _checked("tick %d" % worlds[0].tick)


## Steps `ticks` ticks (see step()); stops at the first difference and returns it, else "".
func run(ticks: int, orders: Callable = Callable()) -> String:
	for _tick: int in ticks:
		var found: String = step(orders)
		if found != "":
			return found
	return ""


## One FOG phase on both Worlds as they stand, done the way Sim.step does it (the dirty lists of the
## players whose turn it is emptied, the removal of the dead, the phase) and compared. The units and
## the tick are not moved, so the same call can follow a change to the rules, the positions or the
## tick. With `keep_counts` the work counts are left as the builder made them, the phase adds its
## cells to what the tick has counted (stats[FOG_CELLS] +=), and the probe's count is checked
## against the sum.
func once(keep_counts: bool = false) -> String:
	for index: int in worlds.size():
		var world: World = worlds[index]
		if not keep_counts:
			world.stats.fill(0)
		world.prepare()
		if index == 0:
			rows_stepped += world.unit_count()
			probe.dying()
		FogUpdate.begin(world)
		world.remove_dead()
		if index == 0:
			probe.before()
		FogUpdate.run(world)
	probe.count()
	return _checked("the phase")


## "" when the Worlds agree (the same state hash and the same full state), else what differs,
## headed by `where`. A case that drives the phase by hand calls it too.
func compare(where: String) -> String:
	var found: String = LockstepRig.difference(worlds[0], worlds[1])
	return "" if found == "" else "%s: %s" % [where, found]


## compare(), and then whether the probe's work is the phase's own: every array the phase writes
## against what the probe says the rule leaves in it, and, with derive_every, whether fog.visible of
## each World is what its rows say.
func _checked(where: String) -> String:
	var found: String = compare(where)
	if found != "":
		return found
	if probe.last_mismatches != 0:
		return (
			"%s: the phase differs from the rule in %d arrays, first: %s"
			% [where, probe.last_mismatches, probe.first_mismatch]
		)
	if derive_every > 0 and worlds[0].tick % derive_every == 0:
		for index: int in worlds.size():
			found = Derivation.mismatch(worlds[index])
			if found != "":
				var side: String = "kernels'" if index == 1 else "twin's"
				return (
					"%s: fog.visible of the %s World is not what its rows say: %s"
					% [where, side, found]
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
