extends RefCounted
## The match the replay and determinism tests (P35b) play: the perf arena with its jitter, and six
## commands at fixed ticks. Player 1 owns ids 1-75 (1-30 tanks), player 2 ids 76-150 (76-105
## tanks). Every call to commands_at makes new Command objects, because the loop stamps the ones
## it is given. Not a test suite.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## The ticks of the six commands, in the order commands_at lists them.
const TICKS: Array[int] = [20, 45, 50, 100, 130, 160]


## The arena with the jitter drawn from `match_seed`, the way the runner makes it.
static func world(match_seed: int) -> World:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(match_seed, DetRandom.STREAM_SIM))


## A loop for `world`, with the arena's scenario orders (an attack-move at tick 0 for each side).
static func loop(world: World, match_seed: int) -> MatchLoop:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	return MatchLoop.create(scenario, ARENA_PATH, match_seed, world)


## The commands queued on `tick`: none on most ticks.
## 20 MOVE (player 1, ids 1-10), 45 ATTACK_MOVE (player 2, ids 76-90), 50 STOP (player 1, ids
## 1-5, still walking), 100 ATTACK (player 1's tanks 11-20 on unit 100), 130 a MOVE of player 1
## that names three of player 2's units (Sim.step drops it: no valid id) and 160 an ATTACK_MOVE of
## player 2 with 257 ids (over MAX_UNITS: Sim.step drops it).
static func commands_at(tick: int) -> Array[Command]:
	var out: Array[Command] = []
	match tick:
		20:
			out.append(Command.move(1, PackedInt32Array(range(1, 11)), 30500, 20500))
		45:
			out.append(Command.attack_move(2, PackedInt32Array(range(76, 91)), 10500, 40500))
		50:
			out.append(Command.stop(1, PackedInt32Array(range(1, 6))))
		100:
			out.append(Command.attack(1, PackedInt32Array(range(11, 21)), 100))
		130:
			out.append(Command.move(1, PackedInt32Array([80, 81, 82]), 5500, 5500))
		160:
			out.append(Command.attack_move(2, PackedInt32Array(range(1, 258)), 5500, 5500))
	return out


## Steps `loop` for `ticks` ticks from the world's tick, queueing commands_at(tick) on each.
static func play(world: World, match_loop: MatchLoop, ticks: int) -> void:
	for _step: int in ticks:
		match_loop.step(world, commands_at(world.tick))
