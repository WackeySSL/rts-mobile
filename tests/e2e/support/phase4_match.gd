extends RefCounted
## One Phase 4 Skirmish played by the scripted player of P94 against the computer (plan row P193).
## Not a test suite.
##
## `played(faction)` plays the Skirmish route of `faction` (`fossil`: the Derrick League on
## `skirmish_kestrel_flats` against `opponent_renew`; `renew`: the Lumen Accord on
## `skirmish_kestrel_flats_mirrored` against `opponent_fossil`, the routes of P183) at Normal,
## seed 42, through a MatchRunner built the way `DevRoutes.open_skirmish` builds it: the scripted
## player's Commands go through `CommandQueue.submit`, one tick at a time, until the match ends or
## `MAX_TICKS`. The end itself is not asserted by any suite. Counted in ticks, never timed. A match
## is played once per faction for the whole run of the suite: the cache is static, and no suite
## writes to it.

const Player: GDScript = preload("res://tests/e2e/support/skirmish_player.gd")
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
	var faction: String = ""
	var scenario_path: String = ""
	var player: RefCounted
	var world: World
	var replay: Replay

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


## The World of the route that `faction_id` plays, as the runner makes it from the seed, with the
## income of the computer's level set as the runner sets it (`Replay.apply_setup`).
static func fresh_world(faction_id: String, replay: Replay) -> World:
	var loaded: ScenarioDef = load(ROUTES[faction_id]["scenario"]) as ScenarioDef
	var world: World = World.from_scenario(loaded, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	replay.apply_setup(world)
	return world


static func _play(faction_id: String) -> Played:
	var route: Dictionary = ROUTES[faction_id]
	var found: Played = Played.new()
	found.faction = faction_id
	found.scenario_path = route["scenario"]
	found.player = Player.new(faction_id)
	var runner: MatchRunner = MatchRunner.new()
	runner.scenario = load(route["scenario"]) as ScenarioDef
	runner.match_seed = SEED
	runner.sim_impl = MatchRunner.SimImpl.GDSCRIPT
	var opponents: Array[AiDef] = [load(route["opponent"]) as AiDef]
	var levels: Array[AiDifficultyDef] = [load(route["level"]) as AiDifficultyDef]
	runner.opponents = opponents
	runner.opponent_levels = levels
	runner.start()
	found.run(runner)
	found.world = runner.world
	found.replay = runner.replay
	found.replay.finish(found.world)
	runner.free()
	CommandQueue.clear()
	return found
