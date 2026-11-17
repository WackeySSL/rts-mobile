class_name MatchSetup
extends RefCounted
## Everything a menu start decides about a match (plan P513, ADR 0042): the scenario, the seed, the
## local seat and side, the computer opponents with their levels, the starting-credits bonus, the
## map and the lesson. `apply(runner)` writes the fields of a new MatchRunner before it enters the
## tree (what `DevRoutes.open_main_with` wrote before); `to_dict` and `from_dict` carry it into the
## resume file. Not sim state: the sim reads none of it, and the seed only reaches it through the
## runner's `match_seed` (DetRng streams, never randi/randf).

const VERSION: int = 1
const KEY_VERSION: String = "version"
const KEY_SCENARIO: String = "scenario"
const KEY_SEED: String = "seed"
const KEY_SEAT: String = "local_seat"
const KEY_SIDE: String = "local_side"
const KEY_OPPONENTS: String = "opponents"
const KEY_LEVELS: String = "levels"
const KEY_FIRST: String = "first_opponent"
const KEY_BONUS: String = "bonus_starting_credits"
const KEY_MAP: String = "map_id"
const KEY_LESSON: String = "lesson_id"
## The bound of every saved int: a corrupt file cannot hold a huge value.
const LIMIT: int = 1000000000
## Only project files load from a saved path (a resume file is data, not a way to reach `user://`).
const PATH_PREFIX: String = "res://"

var scenario_path: String = "":
	set(value):
		scenario_path = value
		_scenario = null
var match_seed: int = 1
## Local player id; 0 keeps the scenario's own `local_player`. The runner reads the seat from the
## scenario, so `apply` refuses any other value until a later row supports other seats.
var local_seat: int = 0
## The side the player plays; 0 when the scenario decides. `apply` refuses any other value until a
## later row supports choosing a side.
var local_side: int = 0
## Entries may be null (a seat the computer leaves empty), as `MatchRunner.opponents` allows.
var opponents: Array[AiDef] = []
var opponent_levels: Array[AiDifficultyDef] = []
var first_opponent: int = MatchRunner.FIRST_OPPONENT
## Credits added at the start by the Phase 6 offer, carried and saved here; `apply` hands it to the
## runner, and the sim clamps it to `RulesDef.bonus_credits_max` (plan P512).
var bonus_starting_credits: int = 0
var map_id: StringName = &""
var lesson_id: StringName = &""

var _scenario: ScenarioDef


## The scenario of `scenario_path`, loaded once per path; null when the path names no ScenarioDef.
func scenario() -> ScenarioDef:
	if _scenario == null and ResourceLoader.exists(scenario_path):
		_scenario = load(scenario_path) as ScenarioDef
	return _scenario


## Writes the runner's fields (the arrays are copies); the runner starts its match in its own
## `_ready`, so this runs before the scene enters the tree. Nothing is written and an error comes
## back when the scenario is missing (ERR_FILE_NOT_FOUND) or a seat or side other than the
## scenario's is asked for (ERR_UNAVAILABLE).
func apply(runner: MatchRunner) -> Error:
	var loaded: ScenarioDef = scenario()
	if loaded == null:
		return ERR_FILE_NOT_FOUND
	if (local_seat != 0 and local_seat != loaded.local_player) or local_side != 0:
		return ERR_UNAVAILABLE
	runner.scenario = loaded
	runner.match_seed = match_seed
	runner.opponents = opponents.duplicate()
	runner.opponent_levels = opponent_levels.duplicate()
	runner.first_opponent = first_opponent
	runner.bonus_credits = bonus_starting_credits
	runner.bonus_seat = local_seat if local_seat != 0 else loaded.local_player
	return OK


func to_dict() -> Dictionary:
	var opponent_paths: Array[String] = []
	for def: AiDef in opponents:
		opponent_paths.append(def.resource_path if def != null else "")
	var level_paths: Array[String] = []
	for level: AiDifficultyDef in opponent_levels:
		level_paths.append(level.resource_path if level != null else "")
	return {
		KEY_VERSION: VERSION,
		KEY_SCENARIO: scenario_path,
		KEY_SEED: match_seed,
		KEY_SEAT: local_seat,
		KEY_SIDE: local_side,
		KEY_OPPONENTS: opponent_paths,
		KEY_LEVELS: level_paths,
		KEY_FIRST: first_opponent,
		KEY_BONUS: bonus_starting_credits,
		KEY_MAP: String(map_id),
		KEY_LESSON: String(lesson_id),
	}


## The setup of `data`, or null when it is malformed: not a dictionary, another version, a missing
## or wrongly typed key, an out-of-range int (the seat and the first opponent against the scenario's
## players), more levels than opponents, or a path that is not a `res://` scenario, AI def or level
## ("" or null in a list is a null entry). Whole numbers that came back as floats are accepted.
static func from_dict(data: Variant) -> MatchSetup:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	for key: String in [
		KEY_VERSION,
		KEY_SCENARIO,
		KEY_SEED,
		KEY_SEAT,
		KEY_SIDE,
		KEY_OPPONENTS,
		KEY_LEVELS,
		KEY_FIRST,
		KEY_BONUS,
		KEY_MAP,
		KEY_LESSON
	]:
		if not dict.has(key):
			return null
	var numbers: Array[int] = [
		_int_in(dict[KEY_VERSION], 0, LIMIT),
		_int_in(dict[KEY_SEED], 0, DetRandom.SEED_MASK),
		_int_in(dict[KEY_SEAT], 0, LIMIT),
		_int_in(dict[KEY_SIDE], 0, LIMIT),
		_int_in(dict[KEY_FIRST], 1, LIMIT),
		_int_in(dict[KEY_BONUS], 0, LIMIT),
	]
	if numbers.has(-1) or numbers[0] != VERSION:
		return null
	for key: String in [KEY_SCENARIO, KEY_MAP, KEY_LESSON]:
		if not dict[key] is String:
			return null
	if not (dict[KEY_OPPONENTS] is Array and dict[KEY_LEVELS] is Array):
		return null
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = dict[KEY_SCENARIO]
	if not setup.scenario_path.begins_with(PATH_PREFIX) or setup.scenario() == null:
		return null
	var players: int = _player_count(setup.scenario())
	if numbers[2] > players or numbers[4] > players:
		return null
	if (dict[KEY_LEVELS] as Array).size() > (dict[KEY_OPPONENTS] as Array).size():
		return null
	setup.match_seed = numbers[1]
	setup.local_seat = numbers[2]
	setup.local_side = numbers[3]
	setup.first_opponent = numbers[4]
	setup.bonus_starting_credits = numbers[5]
	setup.map_id = StringName(dict[KEY_MAP] as String)
	setup.lesson_id = StringName(dict[KEY_LESSON] as String)
	for path: Variant in dict[KEY_OPPONENTS] as Array:
		var def: Resource = _load_entry(path)
		if def == null and not _is_empty(path):
			return null
		if def != null and not def is AiDef:
			return null
		setup.opponents.append(def as AiDef)
	for path: Variant in dict[KEY_LEVELS] as Array:
		var level: Resource = _load_entry(path)
		if level == null and not _is_empty(path):
			return null
		if level != null and not level is AiDifficultyDef:
			return null
		setup.opponent_levels.append(level as AiDifficultyDef)
	return setup


## The players of a scenario: `player_count`, or its highest spawn owner when that is 0.
static func _player_count(scenario_def: ScenarioDef) -> int:
	var highest: int = scenario_def.player_count
	if highest <= 0:
		for spawn: SpawnDef in scenario_def.spawns:
			highest = maxi(highest, spawn.owner)
	return maxi(highest, scenario_def.local_player)


## `value` as an int within [low, high] (a whole float counts), else -1.
static func _int_in(value: Variant, low: int, high: int) -> int:
	var number: int = -1
	if value is int:
		number = value
	elif value is float and is_finite(value) and value == floorf(value):
		number = int(value)
	return number if number >= low and number <= high else -1


static func _is_empty(path: Variant) -> bool:
	return path == null or (path is String and (path as String).is_empty())


## The resource at a `res://` path that exists, else null.
static func _load_entry(path: Variant) -> Resource:
	if not (path is String) or not (path as String).begins_with(PATH_PREFIX):
		return null
	if not ResourceLoader.exists(path as String, "Resource"):
		return null
	return ResourceLoader.load(path as String, "Resource")
