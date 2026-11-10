extends RefCounted
## One Phase 3 Skirmish played to its end by the scripted player (plan row P94). Not a test suite.
##
## `played(host, faction, impl)` plays the Skirmish route of `faction` (`fossil`: the Derrick
## League on `skirmish_kestrel_flats` against `dummy_renew`; `renew`: the Lumen Accord on
## `skirmish_kestrel_flats_mirrored` against `dummy_fossil`, the routes of P90) through a
## MatchRunner as the dev menu builds it: the scenario, the dummy of the other side as
## `opponents`, seed 42, and the scripted player's Commands through `CommandQueue.submit`, one tick
## at a time, until the match ends. A ResultScreen is on the runner while it plays, so the screen
## that a player would see is the one that is read. What a suite judges is kept on the result:
## the replay (finished), the final World, the published snapshot, the tick-by-tick look at the
## strike (`BaseArena.snap` for each tick from the one before the SUPERWEAPON until its effect has
## ended), the shots that buildings fired and the screen's texts.
##
## A match is played once per (faction, implementation) for the whole run of the suites: the cache
## is static, and no suite writes to what it returns. Counted in ticks and rows, never timed.

const BaseArena: GDScript = preload("res://tests/sim/support/base_arena.gd")
const Player: GDScript = preload("res://tests/e2e/support/skirmish_player.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const THEME_PATH: String = "res://game/ui/theme.tres"
const SEED: int = 42
## No match may run longer than this; the scripted wins end near 8,500 ticks.
const MAX_TICKS: int = 12000
## Per faction id: the scenario, the dummy of the other side and the faction of that dummy.
const ROUTES: Dictionary[String, Dictionary] = {
	"fossil":
	{
		"scenario": DevRoutes.SKIRMISH_DERRICK,
		"dummy": DevRoutes.DUMMY_RENEW,
		"dummy_faction": "renew",
	},
	"renew":
	{
		"scenario": DevRoutes.SKIRMISH_LUMEN,
		"dummy": DevRoutes.DUMMY_FOSSIL,
		"dummy_faction": "fossil",
	},
}

static var _cache: Dictionary = {}


## What a played match left, see the header.
class Played:
	extends RefCounted
	var faction: String = ""
	var impl: int = 0
	var scenario: ScenarioDef
	var player: RefCounted
	var world: World
	var replay: Replay
	var snapshot: MatchSnapshot
	## The winners that `match_ended` announced, in order.
	var winners: Array[int] = []
	## tick -> BaseArena.Snap, for the ticks of the strike (see the header). Untyped, as BaseArena's.
	var snaps: Dictionary = {}
	## Every SHOT by a building: (the World's tick after the step, the shooter's id).
	var building_shots: Array[Vector2i] = []
	## The ResultScreen's texts once the match has ended: the title, the emblem's file, the time and
	## the cells of the table in order.
	var screen_title: String = ""
	var screen_emblem: String = ""
	var screen_time: String = ""
	var screen_cells: Array[String] = []

	## Every Command of `from`'s log, decoded, in the order it was recorded (shared with P193's suite).
	static func log_commands(from: Replay) -> Array[Command]:
		var found: Array[Command] = []
		var at: int = 0
		while at < from.commands.size():
			var command: Command = Command.new()
			at = Command.decode(from.commands, at, command)
			if at <= 0:
				break
			found.append(command)
		return found

	## Every Command of the replay's log, decoded, in the order it was recorded.
	func commands() -> Array[Command]:
		return Played.log_commands(replay)

	## Plays `runner` until its match ends or `MAX_TICKS`: the player thinks on the World the next
	## tick will step, its Commands go through the queue, and one tick is played.
	func run(runner: MatchRunner) -> void:
		var sent: Array[Command] = []
		var window_end: int = -1
		while runner.snapshot.match_end_tick == 0 and runner.world.tick < MAX_TICKS:
			var before: World = runner.world
			sent.clear()
			player.think(before, sent)
			for command: Command in sent:
				CommandQueue.submit(command)
			if player.strike_tick == before.tick and not sent.is_empty():
				snaps[before.tick] = BaseArena.snap(before)
				window_end = before.tick + 2 + _effect_ticks(before)
			runner.run_ticks(1)
			var after: World = runner.world
			if window_end >= 0 and after.tick <= window_end:
				snaps[after.tick] = BaseArena.snap(after)
			_note_building_shots(after)

	## Takes the texts off the screen that heard the end: the title beside the emblem, the time
	## under it and the cells of the table.
	func read(screen: ResultScreen) -> void:
		var emblem: TextureRect = screen.find_children("*", "TextureRect", true, false)[0]
		var grid: GridContainer = screen.find_children("*", "GridContainer", true, false)[0]
		screen_title = (emblem.get_parent().get_child(1) as Label).text
		screen_time = (emblem.get_parent().get_parent().get_child(1) as Label).text
		screen_emblem = emblem.texture.resource_path if emblem.texture != null else ""
		for cell: Node in grid.get_children():
			screen_cells.append((cell as Label).text)

	## The ticks that the effect of the strike building lasts after the SUPERWEAPON's own step: the
	## delay of a rupture, the length of a blackout.
	func _effect_ticks(at: World) -> int:
		var type: int = at.type_index[player.strike_row(at)]
		return maxi(at.type_strike_delay[type], at.type_strike_ticks[type])

	## The SHOTs of the step just played whose shooter is a building (a turret), by id: a row that
	## the step removed is not found and not counted.
	func _note_building_shots(after: World) -> void:
		var events: PackedInt32Array = after.events
		var at: int = 0
		while at < events.size():
			if events[at] == World.Event.SHOT:
				var row: int = after.index_of(events[at + 1])
				if row >= 0 and after.type_foot_w[after.type_index[row]] > 0:
					building_shots.append(Vector2i(after.tick, events[at + 1]))
			at += World.EVENT_STRIDE


## The match of `faction_id` under `implementation` (a `SimImpls.Impl`), played now if no suite has
## played it. `host` is a node of the tree for the ResultScreen to stand in while the match runs.
static func played(host: Node, faction_id: String, implementation: int) -> Played:
	var key: String = "%s/%d" % [faction_id, implementation]
	if not _cache.has(key):
		_cache[key] = _play(host, faction_id, implementation)
	return _cache[key]


## The World of the scenario that `faction_id` plays, as the runner makes it from the seed.
static func fresh_world(faction_id: String) -> World:
	var loaded: ScenarioDef = load(ROUTES[faction_id]["scenario"]) as ScenarioDef
	return World.from_scenario(loaded, DetRandom.create(SEED, DetRandom.STREAM_SIM))


static func _play(host: Node, faction_id: String, implementation: int) -> Played:
	var route: Dictionary = ROUTES[faction_id]
	var found: Played = Played.new()
	found.faction = faction_id
	found.impl = implementation
	found.scenario = load(route["scenario"]) as ScenarioDef
	found.player = Player.new(faction_id)
	var runner: MatchRunner = MatchRunner.new()
	runner.scenario = found.scenario
	runner.match_seed = SEED
	runner.sim_impl = (
		MatchRunner.SimImpl.NATIVE
		if implementation == SimImpls.Impl.NATIVE
		else MatchRunner.SimImpl.GDSCRIPT
	)
	var opponents: Array[AiDef] = [load(route["dummy"]) as AiDef]
	runner.opponents = opponents
	var screen: ResultScreen = ResultScreen.new()
	screen.runner = runner
	screen.theme = load(THEME_PATH) as Theme
	host.add_child(screen)
	var heard: Array[int] = found.winners
	runner.match_ended.connect(func(winner: int) -> void: heard.append(winner))
	runner.start()
	found.run(runner)
	found.world = runner.world
	found.snapshot = runner.snapshot
	found.replay = runner.replay
	found.replay.finish(found.world)
	found.read(screen)
	host.remove_child(screen)
	screen.free()
	runner.free()
	CommandQueue.clear()
	return found
