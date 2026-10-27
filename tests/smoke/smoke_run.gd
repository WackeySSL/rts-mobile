extends RefCounted
## The match behind scripts/run-sim-smoke.sh (plan row P95, ADR 0020 question 2 = ja): the Derrick
## League against the Lumen Accord on Kestrel Flats, each side played by its faction's dummy
## (`data/ai/dummy_fossil.tres` for player 1, `data/ai/dummy_renew.tres` for player 2), for 1,800
## ticks or until the match ends. Not a test suite; `run_sim_smoke.gd` is the entry point, which
## calls play() once per seed, and `test_smoke_run.gd` pins what a match and the report hold.
##
## The loop is MatchRunner's without the Node: the World comes from the scenario with the sim
## stream of the seed, every controller is `DummyAi.create(def, player, DetRandom.create(seed,
## STREAM_AI_BASE + player))`, and each tick is `AiDriver.think_all` and then `MatchLoop.step`
## (ADR 0020 section 3), so the smoke run, the phone and the suites cannot drift. Everything it
## reports is counted from the World: ticks, winner, the final state hash and per-player counts.
## No clock and no frame delta, so a seed gives the same record on every machine and every run.
##
## A match record (what play() returns) has these keys, all ints and strings so that it survives
## JSON: `seed`, `ticks` (ticks played), `winner` (the player that won, 0 for none: no end yet, or
## a draw), `match_end_tick` (0 = still running), `state_hash` (16 hex digits of
## `World.state_hash()`), `dropped_commands`, `spawn_refused` and `players`, one entry per player
## in player order with `player`, `ai` (the AiDef id), `credits`, `units` and `buildings` (the rows
## alive at the end), `built`, `lost_units`, `lost_buildings`, `harvested` and `defeated_tick`.

const SCENARIO_PATH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
## The dummy's def of player 1, 2, ... (index p - 1): the scenario's player 1 is the Derrick League
## and player 2 the Lumen Accord.
const DEF_PATHS: Array[String] = [
	"res://data/ai/dummy_fossil.tres",
	"res://data/ai/dummy_renew.tres",
]
## Ticks per match: 2 minutes of game at 15 Hz.
const TICKS: int = 1800
## The report's schema number. The stub of Phase 0 wrote the same top-level keys with an empty
## `matches` list, so this stays 1 (ADR 0020 question 2: the report schema is unchanged).
const SCHEMA: int = 1
## The prefix of every line the run prints: the shell script shows these lines and nothing else.
const PREFIX: String = "run-sim-smoke: "


## Plays one match from `match_seed` and returns its record. It stops after `ticks` ticks, or at
## the tick that ends the match (`match_end_tick` above 0).
static func play(match_seed: int, ticks: int = TICKS) -> Dictionary:
	var world: World = world_of(match_seed)
	run(world, loop_of(world, match_seed), controllers_of(match_seed), ticks)
	return record_of(world, match_seed, ai_ids())


## The World of the scenario with the sim stream of `match_seed`, as MatchRunner makes it.
static func world_of(match_seed: int) -> World:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(match_seed, DetRandom.STREAM_SIM))


## The loop of `world`, which `world_of(match_seed)` made: it records the scenario, seed and defs.
static func loop_of(world: World, match_seed: int) -> MatchLoop:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	return MatchLoop.create(scenario, scenario.resource_path, match_seed, world)


## The dummies of player 1, 2, ..., each with its own stream of `match_seed`, as MatchRunner makes
## them.
static func controllers_of(match_seed: int) -> Array[AiController]:
	var controllers: Array[AiController] = []
	for index: int in DEF_PATHS.size():
		var player: int = index + 1
		var rng: DetRandom = DetRandom.create(match_seed, DetRandom.STREAM_AI_BASE + player)
		controllers.append(DummyAi.create(load(DEF_PATHS[index]) as AiDef, player, rng))
	return controllers


## The ids of the dummies' defs, player 1 first.
static func ai_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for path: String in DEF_PATHS:
		ids.append((load(path) as AiDef).id)
	return ids


## Steps `world` through `loop` for at most `ticks` ticks, each one `AiDriver.think_all` and then
## `MatchLoop.step`, and stops after the tick that ends the match.
static func run(
	world: World, loop: MatchLoop, controllers: Array[AiController], ticks: int
) -> void:
	var commands: Array[Command] = []
	while world.tick < ticks and world.match_end_tick == 0:
		AiDriver.think_all(world, controllers, commands)
		loop.step(world, commands)
		commands.clear()


## The record of `world` as it stands: `ai_ids[p - 1]` names the AiDef of player p.
static func record_of(world: World, match_seed: int, ai_ids: Array[StringName]) -> Dictionary:
	var players: Array[Dictionary] = []
	for index: int in ai_ids.size():
		players.append(_player(world, index + 1, ai_ids[index]))
	return {
		"seed": match_seed,
		"ticks": world.tick,
		"winner": world.winner,
		"match_end_tick": world.match_end_tick,
		"state_hash": World.hash_hex(world.state_hash()),
		"dropped_commands": world.dropped_commands,
		"spawn_refused": world.spawn_refused,
		"players": players,
	}


## The report JSON's content for the `records` of one run, in seed order. Its `status` is "failed"
## when failures() names a problem.
static func report(records: Array[Dictionary], requested: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"status": "ok" if failures(records).is_empty() else "failed",
		"scenario": SCENARIO_PATH,
		"ticks_per_match": TICKS,
		"matches_requested": requested,
		"matches": records,
	}


## The text of the report file: the JSON of `report` with sorted keys, indented, and a newline at
## the end. Equal reports give equal text.
static func report_text(report_data: Dictionary) -> String:
	return JSON.stringify(report_data, "  ") + "\n"


## Writes the report text to the file `path` (a path on the file system); false when the file
## cannot be opened.
static func write_report(path: String, report_data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(report_text(report_data))
	file.close()
	return true


## What is wrong with the `records` of a run, one text per problem. A dummy never sends a Command
## the sim drops (ADR 0020 section 5), so a dropped Command is a bug in the AI, the sim or the loop.
static func failures(records: Array[Dictionary]) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for record: Dictionary in records:
		if int(record["dropped_commands"]) != 0:
			var dropped: int = int(record["dropped_commands"])
			found.append("seed %d: dropped commands %d" % [int(record["seed"]), dropped])
	return found


## The last line of a run of `matches` matches that ended with the problems `failed`.
static func summary(matches: int, failed: PackedStringArray) -> String:
	if not failed.is_empty():
		return "%sFAILED, %s" % [PREFIX, "; ".join(failed)]
	return "%sOK, %d matches of %d ticks, no dropped commands" % [PREFIX, matches, TICKS]


## The line that the run prints for the match `number` of `total`.
static func line(record: Dictionary, number: int, total: int) -> String:
	var winner: String = "none" if int(record["winner"]) == 0 else str(record["winner"])
	var text: String = (
		"%smatch %d of %d: seed %d, %d ticks, winner %s, hash %s, dropped %d"
		% [
			PREFIX,
			number,
			total,
			record["seed"],
			record["ticks"],
			winner,
			record["state_hash"],
			record["dropped_commands"],
		]
	)
	for player: Dictionary in record["players"]:
		text += (
			"; player %d %s: %d units, %d buildings, %d credits, built %d, lost %d+%d"
			% [
				player["player"],
				player["ai"],
				player["units"],
				player["buildings"],
				player["credits"],
				player["built"],
				player["lost_units"],
				player["lost_buildings"],
			]
		)
	return text


static func _player(world: World, player: int, ai_id: StringName) -> Dictionary:
	var units: int = 0
	var buildings: int = 0
	for row: int in world.unit_count():
		if world.owner[row] != player:
			continue
		if world.type_foot_w[world.type_index[row]] > 0:
			buildings += 1
		else:
			units += 1
	return {
		"player": player,
		"ai": String(ai_id),
		"credits": world.credits[player],
		"units": units,
		"buildings": buildings,
		"built": world.stat_built[player],
		"lost_units": world.stat_lost_units[player],
		"lost_buildings": world.stat_lost_buildings[player],
		"harvested": world.stat_harvested[player],
		"defeated_tick": world.defeated_tick[player],
	}
