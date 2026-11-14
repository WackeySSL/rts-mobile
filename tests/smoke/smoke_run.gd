extends RefCounted
## The match behind scripts/run-sim-smoke.sh (plan rows P95 and P186, ADR 0031 sections 1 to 3):
## two computer players play a full match on Kestrel Flats (or a same-faction scenario) to the end
## or to the cap of `--ticks` ticks. Not a test suite; `run_sim_smoke.gd` is the entry point, which
## calls play() once per seed, and `test_smoke_run.gd` pins what a match and the report hold.
##
## The loop is MatchRunner's without the Node: the World comes from the scenario with the sim
## stream of the seed, every controller is `AiFactory.create(def, level, player, DetRandom.create(
## seed, STREAM_AI_BASE + player))`, and each tick is `AiDriver.lagged_tick` and then
## `MatchLoop.step` (ADR 0038 section 1), so the smoke run, the phone and the suites cannot drift.
## The implementation is AUTO: the native kernels when the library loads, else the GDScript twin
## (ADR 0013 section 3). Everything it reports is counted from the World and the controllers: no
## clock and no frame delta, so a seed gives the same record on every machine and every run.
##
## A match record (what play() returns) has these keys, all ints and strings so that it survives
## JSON: `seed`, `scenario`, `ticks` (ticks played), `end` ("victory", "draw" or "timeout"),
## `winner` (the player that won, 0 for none), `match_end_tick` (0 = still running),
## `state_hash` (16 hex digits of `World.state_hash()`), `dropped_commands`, `spawn_refused`,
## `flow_full_ticks` and `players`, one entry per player in player order. A player has `player`,
## `faction`, `seat`, `ai` (the AiDef id), `level`, `credits`, `units` and `buildings` (the rows
## alive at the end), `built`, `lost_units`, `lost_buildings`, `harvested`, `defeated_tick`, the
## per type maps of SmokeCount (`produced`, `free`, `lost`, `kills`, `spent`, `structures`) and the
## controller's counters `waves`, `retreats`, `scouts`, `strikes`, `commands`, `think_work_max`.

const Impls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")

const FLATS: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const FLATS_MIRRORED: String = "res://data/scenarios/skirmish_kestrel_flats_mirrored.tres"
const FOSSIL_MIRROR: String = "res://data/scenarios/skirmish_kestrel_flats_fossil_mirror.tres"
const RENEW_MIRROR: String = "res://data/scenarios/skirmish_kestrel_flats_renew_mirror.tres"
## `--scenarios`: `cross` plays the odd seeds on FLATS and the even ones on FLATS_MIRRORED, so each
## faction holds each seat in half the matches.
const KIND_CROSS: String = "cross"
const KINDS: Array[String] = ["cross", "derrick", "lumen", "fossil-mirror", "renew-mirror"]
## `--levels`: the controller of a player. `dummy` is the faction's dummy AiDef; the others are the
## faction's OpponentDef at that AiDifficultyDef.
const LEVEL_DUMMY: String = "dummy"
const LEVELS: Array[String] = ["easy", "normal", "hard", "dummy"]
const DEFAULT_LEVELS: Array[String] = ["normal", "normal"]
## The seats of players 1 and 2 (the scenarios put player 1 at the top).
const SEATS: Array[String] = ["top", "bottom"]
## Ticks per match: 15 minutes of game at 15 Hz, the longest a match may run (ADR 0031 section 1).
const TICKS: int = 13500
## The report's schema number. 2: the top-level `scenario` moved to `matches[].scenario`, and the
## run's `commit`, `impl`, `seed_start`, `levels` and `scenarios` and the per match counts joined.
const SCHEMA: int = 2
## ADR 0038 section 6: the AI's Commands land one tick after their view, so the sim may drop a few
## that went stale. A match fails when `dropped_commands > STALE_DROP_PERCENT * C / 100` (integer
## division), C the sum of its players' `commands`. Fixed-seed suites pin exact drops instead.
const STALE_DROP_PERCENT: int = 1
const IMPL_NATIVE: String = "native"
const IMPL_GDSCRIPT: String = "gdscript"
## The prefix of every line the run prints: the shell script shows these lines and nothing else.
const PREFIX: String = "run-sim-smoke: "
const END_VICTORY: String = "victory"
const END_DRAW: String = "draw"
const END_TIMEOUT: String = "timeout"


## Plays one match from `match_seed` and returns its record. It stops after `ticks` ticks, or at
## the tick that ends the match (`match_end_tick` above 0). When a Command was dropped,
## `drops[match_seed]` is the tick of the first drop (outside the record, which keeps the schema's
## keys).
static func play(
	match_seed: int,
	ticks: int = TICKS,
	kind: String = KIND_CROSS,
	levels: Array[String] = DEFAULT_LEVELS,
	drops: Dictionary[int, int] = {}
) -> Dictionary:
	var match_setup: Dictionary = start(match_seed, kind, levels)
	var world: World = match_setup["world"]
	var counter: SmokeCount = match_setup["counter"]
	var controllers: Array[AiController] = match_setup["controllers"]
	run(world, match_setup["loop"], controllers, ticks, counter)
	if counter.first_drop_tick >= 0:
		drops[match_seed] = counter.first_drop_tick
	return record_of(
		world, match_seed, match_setup["path"], match_setup["seats"], controllers, counter
	)


## The match of `match_seed` ready to run: `path`, `world` (on the implementation AUTO picks, a
## problem of the library is a push_error, which the script's error scan fails), `loop`, `seats`,
## `controllers` and a `counter` that has read the scenario's rows.
static func start(match_seed: int, kind: String, levels: Array[String]) -> Dictionary:
	var path: String = scenario_path(kind, match_seed)
	var world: World = world_of(match_seed, path)
	seat_income(world, levels)
	var problems: Array[String] = attach_impl(world)
	if not problems.is_empty():
		push_error("run-sim-smoke: the native library is wrong: %s" % "; ".join(problems))
	var seats: Array[Dictionary] = seats_of(path, levels)
	var counter: SmokeCount = SmokeCount.new(seats.size())
	counter.start(world)
	return {
		"path": path,
		"world": world,
		"loop": loop_of(world, match_seed, path),
		"seats": seats,
		"controllers": controllers_of(match_seed, path, levels),
		"counter": counter,
	}


## The scenario file that seed `match_seed` plays under the scenario kind `kind`.
static func scenario_path(kind: String, match_seed: int) -> String:
	match kind:
		"derrick":
			return FLATS
		"lumen":
			return FLATS_MIRRORED
		"fossil-mirror":
			return FOSSIL_MIRROR
		"renew-mirror":
			return RENEW_MIRROR
		_:
			return FLATS if match_seed % 2 == 1 else FLATS_MIRRORED


## The implementation AUTO picks: native when the library loads, else GDScript.
static func impl_name() -> String:
	return IMPL_NATIVE if Impls.create_kernels() != null else IMPL_GDSCRIPT


## What is wrong with the native library when it is loaded (a kernels object that is no SimKernels
## or reports other phases than SimImpls.EXPECTED_PHASES); empty for GDScript and for a good
## library.
static func impl_problems() -> Array[String]:
	var problems: Array[String] = []
	var kernels: Object = Impls.create_kernels()
	if kernels == null:
		return problems
	if kernels.get_class() != "SimKernels":
		problems.append("the kernels are a %s, not a SimKernels" % kernels.get_class())
	elif kernels.phases() != Impls.expected_mask():
		problems.append(
			"the library reports phases %d, not %d" % [kernels.phases(), Impls.expected_mask()]
		)
	return problems


## Makes `world` run `impl` (default: `impl_name()`); the problems of a bad library, empty when it
## worked (the entry checks `impl_problems()` once before the first match).
static func attach_impl(world: World, impl: String = "") -> Array[String]:
	if (impl_name() if impl.is_empty() else impl) == IMPL_GDSCRIPT:
		return Impls.use(world, Impls.Impl.GDSCRIPT)
	return Impls.use(world, Impls.Impl.NATIVE)


## The World of the scenario at `path` with the sim stream of `match_seed`, as MatchRunner makes it.
static func world_of(match_seed: int, path: String = FLATS) -> World:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(match_seed, DetRandom.STREAM_SIM))


## Gives player 1, 2, ... the `income_percent` of the level's file, as MatchRunner does for an
## OpponentDef (the dummy keeps 100). Before `loop_of`, which records it in the replay.
## `dir` is where the level files are (a test points it at a temporary one).
static func seat_income(
	world: World, levels: Array[String], dir: String = "res://data/ai/difficulty"
) -> void:
	for index: int in levels.size():
		if levels[index] != LEVEL_DUMMY:
			var level: AiDifficultyDef = (
				load("%s/%s.tres" % [dir, levels[index]]) as AiDifficultyDef
			)
			WorldLoad.set_income(world, index + 1, level.income_percent)


## The loop of `world`, which `world_of(match_seed, path)` made: it records the scenario, seed and
## defs.
static func loop_of(world: World, match_seed: int, path: String = FLATS) -> MatchLoop:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	return MatchLoop.create(scenario, scenario.resource_path, match_seed, world)


## The seats of the scenario at `path`, player 1 first: `player`, `faction` (the id of the player's
## FactionDef), `seat`, `ai` (the AiDef id the level gives that faction) and `level`.
static func seats_of(path: String, levels: Array[String]) -> Array[Dictionary]:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	var seats: Array[Dictionary] = []
	for index: int in levels.size():
		var faction: String = String(scenario.factions[index + 1].id)
		(
			seats
			. append(
				{
					"player": index + 1,
					"faction": faction,
					"seat": SEATS[index],
					"ai": String((load(def_path(faction, levels[index])) as AiDef).id),
					"level": levels[index],
				}
			)
		)
	return seats


## The AiDef file of a computer player of `faction` at `level`.
static func def_path(faction: String, level: String) -> String:
	var kind: String = "dummy" if level == LEVEL_DUMMY else "opponent"
	return "res://data/ai/%s_%s.tres" % [kind, faction]


## The controllers of player 1, 2, ..., each with its own stream of `match_seed`, as MatchRunner
## builds them: `AiFactory.create` with the level's AiDifficultyDef (none for the dummy).
static func controllers_of(
	match_seed: int, path: String, levels: Array[String]
) -> Array[AiController]:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	var controllers: Array[AiController] = []
	for index: int in levels.size():
		var player: int = index + 1
		var rng: DetRandom = DetRandom.create(match_seed, DetRandom.STREAM_AI_BASE + player)
		var faction: String = String(scenario.factions[player].id)
		var level: AiDifficultyDef = null
		if levels[index] != LEVEL_DUMMY:
			level = load("res://data/ai/difficulty/%s.tres" % levels[index]) as AiDifficultyDef
		var def: AiDef = load(def_path(faction, levels[index])) as AiDef
		controllers.append(AiFactory.create(def, level, player, rng))
	return controllers


## Steps `world` through `loop` for at most `ticks` ticks, each one `AiDriver.lagged_tick` (the AI's
## Commands of the tick before, then the thinks on this tick's views) and then `MatchLoop.step`
## (ADR 0038 section 1), and stops after the tick that ends the match. A `counter` (made and started
## by the caller) reads each step.
static func run(
	world: World,
	loop: MatchLoop,
	controllers: Array[AiController],
	ticks: int,
	counter: SmokeCount = null
) -> void:
	var commands: Array[Command] = []
	var batch: AiBatch = AiBatch.new()
	while world.tick < ticks and world.match_end_tick == 0:
		AiDriver.lagged_tick(world, controllers, commands, batch)
		loop.step(world, commands)
		commands.clear()
		if counter != null:
			counter.after_step(world)


## How a match ended: a winner is a "victory", an end without one a "draw", no end a "timeout".
static func end_of(world: World) -> String:
	if world.match_end_tick == 0:
		return END_TIMEOUT
	return END_VICTORY if world.winner != 0 else END_DRAW


## The record of `world` as it stands: `seats` is seats_of(path, levels), `controllers` the ones
## that played and `counter` the one that read every step.
static func record_of(
	world: World,
	match_seed: int,
	path: String,
	seats: Array[Dictionary],
	controllers: Array[AiController],
	counter: SmokeCount
) -> Dictionary:
	var players: Array[Dictionary] = []
	for index: int in seats.size():
		players.append(_player(world, seats[index], controllers[index], counter))
	return {
		"seed": match_seed,
		"scenario": path,
		"ticks": world.tick,
		"end": end_of(world),
		"winner": world.winner,
		"match_end_tick": world.match_end_tick,
		"state_hash": World.hash_hex(world.state_hash()),
		"dropped_commands": world.dropped_commands,
		"spawn_refused": world.spawn_refused,
		"flow_full_ticks": counter.flow_full_ticks,
		"players": players,
	}


## The report JSON's content for the `records` of one run, in seed order, as scripts/
## run-sim-smoke.sh was asked for it. Its `status` is "failed" when failures() names a problem.
## `summary` (ADR 0031 section 4) is the merge script's, not the smoke's.
static func report(
	records: Array[Dictionary],
	requested: int,
	ticks: int = TICKS,
	seed_start: int = 1,
	levels: Array[String] = DEFAULT_LEVELS,
	kind: String = KIND_CROSS
) -> Dictionary:
	var commit: String = OS.get_environment("GITHUB_SHA")
	return {
		"schema": SCHEMA,
		"status": "ok" if failures(records).is_empty() else "failed",
		"commit": "local" if commit.is_empty() else commit,
		"impl": impl_name(),
		"ticks_per_match": ticks,
		"seed_start": seed_start,
		"matches_requested": requested,
		"levels": levels,
		"scenarios": kind,
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


## The most Commands a match may have dropped (ADR 0038 section 6): STALE_DROP_PERCENT of the
## Commands its players sent, by integer division, so a match of under 100 Commands allows none.
static func drop_limit(record: Dictionary) -> int:
	return STALE_DROP_PERCENT * _sent(record) / 100


## What is wrong with the `records` of a run, one text per problem. A match that dropped more than
## drop_limit() Commands fails: the AI's Commands are one tick stale (ADR 0038 section 6), so a few
## drops are expected and many mean an AI bug. A timeout is no failure: the gate judges it (ADR
## 0031 section 2).
static func failures(
	records: Array[Dictionary], drops: Dictionary[int, int] = {}
) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for record: Dictionary in records:
		var dropped: int = int(record["dropped_commands"])
		if dropped > drop_limit(record):
			found.append(
				(
					"seed %d: dropped commands %d of %d%s"
					% [
						int(record["seed"]),
						dropped,
						_sent(record),
						_drop_text(drops, int(record["seed"]))
					]
				)
			)
	return found


## The last line of a run of `matches` matches of at most `ticks` ticks on `impl` that ended with
## the problems `failed`.
static func summary(
	records: Array[Dictionary], ticks: int, impl: String, failed: PackedStringArray
) -> String:
	if not failed.is_empty():
		return "%sFAILED, %s" % [PREFIX, "; ".join(failed)]
	var timeouts: int = 0
	for record: Dictionary in records:
		if record["end"] == END_TIMEOUT:
			timeouts += 1
	return (
		"%sOK, %d matches of at most %d ticks, impl %s, %d timeouts, stale drops within the bound"
		% [PREFIX, records.size(), ticks, impl, timeouts]
	)


## The line that the run prints for the match `number` of `total`.
static func line(
	record: Dictionary, number: int, total: int, drops: Dictionary[int, int] = {}
) -> String:
	var winner: String = "none" if int(record["winner"]) == 0 else str(record["winner"])
	var text: String = (
		"%smatch %d of %d: seed %d, %s, %d ticks, %s, winner %s, hash %s, dropped %d%s, flow full %d"
		% [
			PREFIX,
			number,
			total,
			record["seed"],
			String(record["scenario"]).get_file().get_basename(),
			record["ticks"],
			record["end"],
			winner,
			record["state_hash"],
			record["dropped_commands"],
			_drop_text(drops, int(record["seed"])),
			record["flow_full_ticks"],
		]
	)
	for player: Dictionary in record["players"]:
		text += (
			"; player %d %s %s: %d units, %d buildings, %d credits, built %d, lost %d+%d"
			% [
				player["player"],
				player["ai"],
				player["level"],
				player["units"],
				player["buildings"],
				player["credits"],
				player["built"],
				player["lost_units"],
				player["lost_buildings"],
			]
		)
	return text


## ", the first in tick T" for a match whose first drop is in `drops`, else nothing.
static func _sent(record: Dictionary) -> int:
	var sent: int = 0
	for player: Dictionary in record["players"]:
		sent += int(player["commands"])
	return sent


static func _drop_text(drops: Dictionary[int, int], match_seed: int) -> String:
	return ", the first in tick %d" % drops[match_seed] if drops.has(match_seed) else ""


static func _player(
	world: World, seat: Dictionary, controller: AiController, counter: SmokeCount
) -> Dictionary:
	var player: int = seat["player"]
	var units: int = 0
	var buildings: int = 0
	for row: int in world.unit_count():
		if world.owner[row] != player:
			continue
		if world.type_foot_w[world.type_index[row]] > 0:
			buildings += 1
		else:
			units += 1
	var data: Dictionary = {
		"player": player,
		"faction": seat["faction"],
		"seat": seat["seat"],
		"ai": seat["ai"],
		"level": seat["level"],
		"credits": world.credits[player],
		"units": units,
		"buildings": buildings,
		"built": world.stat_built[player],
		"lost_units": world.stat_lost_units[player],
		"lost_buildings": world.stat_lost_buildings[player],
		"harvested": world.stat_harvested[player],
		"defeated_tick": world.defeated_tick[player],
		"waves": controller.waves,
		"retreats": controller.retreats,
		"scouts": controller.scouts,
		"strikes": controller.strikes,
		"commands": controller.commands,
		"think_work_max": controller.work_max,
	}
	data.merge(counter.player_counts(world, player))
	return data
