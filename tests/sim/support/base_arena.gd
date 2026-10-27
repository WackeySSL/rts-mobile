extends RefCounted
## Plays the base arena (plan row P80, ADR 0021 section 2, ADR 0023 section 14) through MatchLoop
## and keeps what the base-arena suites judge, counted in rows and events and never in time. Not a
## test suite. `play(impl, ticks, snap_ticks)` runs `data/scenarios/perf_bases.tres` with seed 42 in
## the GDScript phases or in the C++ kernels (SimImpls) and returns a Run:
## - `mobile[t]`: the mobile rows (type speed above 0) alive when the World's tick is t, from t = 0;
## - `min_alive[type]`: the fewest rows of that World type index in any sample, tick 0 included;
## - `spawned[player * World.TABS + tab]`: the units a production queue put on the map (SPAWNED
##   events of the steps, never the setup's);
## - `unloaded[id]`: the first tick a harvester (by id) was in UNLOAD after a step;
## - `snaps[tick]`: a Snap of the rows after the step that made the World's tick `tick`, for each
##   of `snap_ticks`;
## - the replay (finished) and the World itself, left at the last tick.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const PATH: String = "res://data/scenarios/perf_bases.tres"
const SEED: int = 42


## The rows of the World after one step, copied.
class Snap:
	extends RefCounted
	var tick: int = 0
	var ids: PackedInt32Array = PackedInt32Array()
	var owner: PackedInt32Array = PackedInt32Array()
	var type_index: PackedInt32Array = PackedInt32Array()
	var hp: PackedInt32Array = PackedInt32Array()
	var pos_x: PackedInt32Array = PackedInt32Array()
	var pos_y: PackedInt32Array = PackedInt32Array()
	var ready_tick: PackedInt32Array = PackedInt32Array()
	var offline_until: PackedInt32Array = PackedInt32Array()
	## Per player (entry 0 is the neutral player's).
	var strike_tick: PackedInt32Array = PackedInt32Array()
	var power_made: PackedInt32Array = PackedInt32Array()
	var power_used: PackedInt32Array = PackedInt32Array()
	var dropped: int = 0

	## The row of unit `id`, -1 when it has none.
	func row_of(id: int) -> int:
		return ids.find(id)


## What a played arena left, see the header.
class Run:
	extends RefCounted
	var impl: int = 0
	var problems: Array[String] = []
	var world: World
	var replay: Replay
	var mobile: PackedInt32Array = PackedInt32Array()
	var min_alive: PackedInt32Array = PackedInt32Array()
	var spawned: PackedInt32Array = PackedInt32Array()
	var unloaded: Dictionary[int, int] = {}
	var died: int = 0
	## tick -> Snap. Untyped: a typed collection of a script class is avoided in a long-lived holder.
	var snaps: Dictionary = {}


## The arena played for `ticks` steps. `snap_ticks` are World ticks to snapshot after the step that
## reaches them (0 is the setup, before any step).
static func play(impl: int, ticks: int, snap_ticks: Array = []) -> Run:
	var scenario: ScenarioDef = load(PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var run: Run = Run.new()
	run.impl = impl
	run.world = world
	run.problems = SimImpls.use(world, impl)
	var loop: MatchLoop = MatchLoop.create(scenario, PATH, SEED, world)
	run.spawned.resize((world.player_count + 1) * World.TABS)
	run.min_alive.resize(world.type_ids.size())
	run.min_alive.fill(1 << 30)
	var no_commands: Array[Command] = []
	_sample(world, run)
	if snap_ticks.has(0):
		run.snaps[0] = snap(world)
	for _step: int in ticks:
		loop.step(world, no_commands)
		_sample(world, run)
		if snap_ticks.has(world.tick):
			run.snaps[world.tick] = snap(world)
	loop.replay.finish(world)
	run.replay = loop.replay
	return run


## The longest stretch of consecutive entries of `series` that are `at_least` or more.
static func streak(series: PackedInt32Array, at_least: int) -> int:
	var best: int = 0
	var current: int = 0
	for value: int in series:
		current = current + 1 if value >= at_least else 0
		best = maxi(best, current)
	return best


## A copy of the rows and the per-player totals of `world` as they are now.
static func snap(world: World) -> Snap:
	var copy: Snap = Snap.new()
	copy.tick = world.tick
	copy.ids = world.unit_id.duplicate()
	copy.owner = world.owner.duplicate()
	copy.type_index = world.type_index.duplicate()
	copy.hp = world.hp.duplicate()
	copy.pos_x = world.pos_x.duplicate()
	copy.pos_y = world.pos_y.duplicate()
	copy.ready_tick = world.ready_tick.duplicate()
	copy.offline_until = world.offline_until.duplicate()
	copy.strike_tick = world.strike_tick.duplicate()
	copy.power_made = world.power_made.duplicate()
	copy.power_used = world.power_used.duplicate()
	copy.dropped = world.dropped_commands
	return copy


## One look after a step (or before the first): the mobile rows, the fewest rows of each type, the
## units the queues spawned, the harvesters that are unloading and the deaths.
static func _sample(world: World, run: Run) -> void:
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var alive: PackedInt32Array = PackedInt32Array()
	alive.resize(run.min_alive.size())
	var mobile: int = 0
	for row: int in types.size():
		alive[types[row]] += 1
		if speeds[types[row]] > 0:
			mobile += 1
	run.mobile.append(mobile)
	for type: int in alive.size():
		run.min_alive[type] = mini(run.min_alive[type], alive[type])
	var events: PackedInt32Array = world.events
	var tabs: PackedInt32Array = world.type_tab
	var at: int = 0
	while at < events.size():
		if events[at] == World.Event.SPAWNED:
			run.spawned[events[at + 5] * World.TABS + tabs[events[at + 4]]] += 1
		elif events[at] == World.Event.DIED:
			run.died += 1
		at += World.EVENT_STRIDE
	var modes: PackedInt32Array = world.harvest_mode
	var ids: PackedInt32Array = world.unit_id
	for row: int in world.harvester_rows:
		if modes[row] == World.HarvestMode.UNLOAD and not run.unloaded.has(ids[row]):
			run.unloaded[ids[row]] = world.tick
