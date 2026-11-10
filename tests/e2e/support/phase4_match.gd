extends RefCounted
## One Phase 4 Skirmish played by the scripted player of P94 against the computer (plan row P193).
## Not a test suite.
##
## `played(faction)` plays the Skirmish route of `faction` (`fossil`: the Derrick League on
## `skirmish_kestrel_flats` against `opponent_renew`; `renew`: the Lumen Accord on
## `skirmish_kestrel_flats_mirrored` against `opponent_fossil`, the routes of P183) at Normal,
## seed 42, through a MatchRunner given the fields that `DevRoutes.open_skirmish` gives the main
## scene's runner (no scene is built). It runs `SimImpl.AUTO` as the scene does: the kernels where
## the library loads (`native_expected()`), the twins otherwise. The scripted player's Commands go
## through `CommandQueue.submit`, one tick at a time, until the match ends or `MAX_TICKS`. The end
## itself is not asserted by any suite. Counted in ticks, never timed. A match is played once per
## faction until `forget()`: the cache is static, and no suite writes to it.

const Player: GDScript = preload("res://tests/e2e/support/skirmish_player.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const SEED: int = 42
## No match may run longer than this (15 minutes of match time).
const MAX_TICKS: int = 13500
## Per faction id: the scenario, the computer of the other side and its level.
const ROUTES: Dictionary[String, Dictionary] = {
	"fossil":
	{
		"scenario": DevRoutes.SKIRMISH_DERRICK,
		"opponent": DevRoutes.OPPONENT_RENEW,
		"level": DevRoutes.LEVEL_NORMAL,
	},
	"renew":
	{
		"scenario": DevRoutes.SKIRMISH_LUMEN,
		"opponent": DevRoutes.OPPONENT_FOSSIL,
		"level": DevRoutes.LEVEL_NORMAL,
	},
}

static var _cache: Dictionary[String, Played] = {}


## What a played match left, see the header.
class Played:
	extends RefCounted
	var player: RefCounted
	var world: World
	var replay: Replay
	## The computer of player 2 that the runner built, kept after the runner is freed.
	var computer: OpponentAi

	## Plays `runner` until its match ends or `MAX_TICKS`: the player thinks on the World the next
	## tick will step, its Commands go through the queue, and one tick is played.
	func run(runner: MatchRunner) -> void:
		var sent: Array[Command] = []
		while runner.snapshot.match_end_tick == 0 and runner.world.tick < MAX_TICKS:
			sent.clear()
			player.think(runner.world, sent)
			for command: Command in sent:
				CommandQueue.submit(command)
			runner.run_ticks(1)


## The match of `faction_id`, played now if no test has played it.
static func played(faction_id: String) -> Played:
	if not _cache.has(faction_id):
		_cache[faction_id] = _play(faction_id)
	return _cache[faction_id]


## Drops the played matches, so that a finished suite holds no World or Replay.
static func forget() -> void:
	_cache.clear()


## Whether the native library loads here, so that `SimImpl.AUTO` runs the kernels (as
## tests/ai/test_ai_determinism.gd decides it).
static func native_expected() -> bool:
	return SimImpls.create_kernels() != null


## The World of `replay`'s header (its scenario and seed), as the runner makes it, with the replay's
## income setup applied.
static func fresh_world(replay: Replay) -> World:
	var loaded: ScenarioDef = load(replay.scenario_path) as ScenarioDef
	var world: World = World.from_scenario(loaded, DetRng.create(replay.seed, DetRandom.STREAM_SIM))
	replay.apply_setup(world)
	return world


static func _play(faction_id: String) -> Played:
	var route: Dictionary = ROUTES[faction_id]
	var found: Played = Played.new()
	found.player = Player.new(faction_id)
	var runner: MatchRunner = MatchRunner.new()
	runner.scenario = load(route["scenario"]) as ScenarioDef
	runner.match_seed = SEED
	runner.sim_impl = MatchRunner.SimImpl.AUTO
	var opponents: Array[AiDef] = [load(route["opponent"]) as AiDef]
	var levels: Array[AiDifficultyDef] = [load(route["level"]) as AiDifficultyDef]
	runner.opponents = opponents
	runner.opponent_levels = levels
	runner.start()
	found.computer = runner._job.controllers[0] as OpponentAi
	found.run(runner)
	found.world = runner.world
	found.replay = runner.replay
	found.replay.finish(found.world)
	runner.free()
	CommandQueue.clear()
	return found
