extends GdUnitTestSuite
## The base of the `AiProduction` suites (plan row P178): the shared constants, a fossil World of
## `faction_rig.gd` with a barracks, a vehicle factory and the radar, the manager and the defs
## with this suite's own role weights and counter percents, and the helpers. Not a test suite.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const RICH: int = 100000
const NONE: int = -1
const DRAWS: int = 300
## The roles' fossil types, in `OpponentDef.Role` order.
const ROLE_IDS: Array[String] = ["rifle_squad", "rocket_squad", "heavy_tank", "artillery"]
## The suite's own role weights (`tier * ROLES + role`) and counter percents per level.
const WEIGHTS: Array[int] = [50, 40, 10, 0, 35, 30, 25, 10, 20, 25, 35, 20]
const COUNTER: Dictionary[String, int] = {"easy": 0, "normal": 30, "hard": 60}
const ANTI_INFANTRY: int = OpponentDef.Role.ANTI_INFANTRY
const ANTI_VEHICLE: int = OpponentDef.Role.ANTI_VEHICLE
const TANK: int = OpponentDef.Role.TANK
const ARTILLERY: int = OpponentDef.Role.ARTILLERY


## A fossil start: player 1 owns a barracks and a vehicle factory (and the radar when `radar`),
## `credits`, the fog open.
func _world(credits: int, radar: bool) -> World:
	var world: World = FactionRig.start("fossil", "renew")
	AiRig.explore_all(world)
	AiRig.give(world, 1, "power_plant", 10, 2)
	AiRig.give(world, 1, "barracks", 2, 2)
	AiRig.give(world, 1, "vehicle_factory", 2, 12)
	if radar:
		AiRig.give(world, 1, "fossil_radar", 22, 2)
	Power.run(world)
	world.credits[1] = credits
	return world


func _cost(world: World, id: String) -> int:
	return world.type_cost[AiRig.type_of(world, id)]


## The shipped fossil def with this suite's role weights, so the exact pins are the suite's own.
func _def() -> OpponentDef:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.role_weights = PackedInt32Array(WEIGHTS)
	return def


## The shipped level with this suite's counter percent and its own reaction age.
func _level(level: String) -> AiDifficultyDef:
	var made: AiDifficultyDef = Rig.level_of(level).duplicate() as AiDifficultyDef
	made.counter_percent = COUNTER[level]
	made.reaction_ticks = 30
	return made


func _production(_faction: String, level: String) -> AiProduction:
	return AiProduction.create(_def(), _level(level), 1)


func _memory(faction: String) -> AiMemory:
	return _open(AiMemory.create(Rig.def_of(faction)))


## The memory with a Command budget of 99.
func _open(memory: AiMemory) -> AiMemory:
	memory.commands_left = 99
	return memory


func _stream(seed: int = 1) -> DetRandom:
	return DetRandom.create(seed, DetRandom.STREAM_AI_BASE + 1)


## One production run on a fresh view of `world` for player 1 with seed 1's stream; the memory's
## budget is 99 Commands unless `open` is false (the caller set it).
func _run(
	production: AiProduction, memory: AiMemory, world: World, open: bool = true
) -> Array[Command]:
	if open:
		memory.commands_left = 99
	var out: Array[Command] = []
	production.run(PlayerView.of(world, 1), memory, _stream(), out)
	return out


## The role of each of the 300 first draws of one stream: the unit of the first QUEUE of a run on
## `world` whose queues are emptied again after each run, so each run's first draw is over all
## the roles. Returns the counts per `OpponentDef.Role`.
func _first_draws(production: AiProduction, world: World, memory: AiMemory) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	var stream: DetRandom = _stream()
	for _run_at: int in DRAWS:
		world.queue_count.fill(0)
		var out: Array[Command] = []
		memory.commands_left = 99
		production.run(PlayerView.of(world, 1), memory, stream, out)
		var role: int = ROLE_IDS.find(String(world.type_ids[out[0].payload[0]]))
		assert_int(role).is_greater_equal(0)
		counts[role] += 1
	return counts


## A memory whose sightings are `seen` (type id -> count), all first seen at `first`.
func _seen(world: World, seen: Dictionary[String, int], first: int) -> AiMemory:
	var memory: AiMemory = _memory("fossil")
	var types: int = world.type_cost.size()
	memory.seen_count.resize(types)
	memory.seen_count.fill(0)
	memory.seen_first_tick.resize(types)
	memory.seen_first_tick.fill(NONE)
	memory.seen_last_tick.resize(types)
	memory.seen_last_tick.fill(NONE)
	for id: String in seen:
		var type: int = AiRig.type_of(world, id)
		memory.seen_count[type] = seen[id]
		memory.seen_first_tick[type] = first
	return memory


func _ids(sent: Array[Command], world: World) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


func _in_tab(sent: Array[Command], world: World, tab: int) -> int:
	var found: int = 0
	for command: Command in sent:
		if world.type_tab[command.payload[0]] == tab:
			found += 1
	return found
