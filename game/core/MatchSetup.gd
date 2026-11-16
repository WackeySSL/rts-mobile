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
const SEED_MAX: int = 0x7FFFFFFF

var scenario_path: String = ""
var match_seed: int = 1
## Local player id; 0 keeps the scenario's own `local_player`. The runner reads the seat from the
## scenario, so a consumer that wants another seat duplicates the scenario (as the e2e rig does).
var local_seat: int = 0
## The side the player plays, as `Side` of the scenario's player; 0 when the scenario decides.
var local_side: int = 0
var opponents: Array[AiDef] = []
var opponent_levels: Array[AiDifficultyDef] = []
var first_opponent: int = MatchRunner.FIRST_OPPONENT
## Credits added at the start by the Phase 6 offer, carried and saved here; the sim applies it from
## plan P512 on, and nothing reads it before.
var bonus_starting_credits: int = 0
var map_id: StringName = &""
var lesson_id: StringName = &""

var _scenario: ScenarioDef


## The scenario of `scenario_path`, loaded once; null when the path names no ScenarioDef.
func scenario() -> ScenarioDef:
	if _scenario == null and ResourceLoader.exists(scenario_path):
		_scenario = load(scenario_path) as ScenarioDef
	return _scenario


## Writes the runner's fields; the runner starts its match in its own `_ready`, so this runs before
## the scene enters the tree. ERR_FILE_NOT_FOUND (nothing written) when the scenario is missing.
func apply(runner: MatchRunner) -> Error:
	var loaded: ScenarioDef = scenario()
	if loaded == null:
		return ERR_FILE_NOT_FOUND
	runner.scenario = loaded
	runner.match_seed = match_seed
	runner.opponents = opponents
	runner.opponent_levels = opponent_levels
	runner.first_opponent = first_opponent
	return OK


func to_dict() -> Dictionary:
	var opponent_paths: Array[String] = []
	for def: AiDef in opponents:
		opponent_paths.append(def.resource_path)
	var level_paths: Array[String] = []
	for level: AiDifficultyDef in opponent_levels:
		level_paths.append(level.resource_path)
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
## or wrongly typed key, an out-of-range int, or a path that is not a scenario, an AI def or a
## level. Whole numbers that came back as floats are accepted.
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
	var version: int = _int_in(dict[KEY_VERSION], 0, LIMIT)
	var seed_value: int = _int_in(dict[KEY_SEED], 0, SEED_MAX)
	var seat: int = _int_in(dict[KEY_SEAT], 0, LIMIT)
	var side: int = _int_in(dict[KEY_SIDE], 0, LIMIT)
	var first: int = _int_in(dict[KEY_FIRST], 1, LIMIT)
	var bonus: int = _int_in(dict[KEY_BONUS], 0, LIMIT)
	if [version, seed_value, seat, side, first, bonus].has(-1) or version != VERSION:
		return null
	if not (dict[KEY_SCENARIO] is String and dict[KEY_MAP] is String):
		return null
	if not (dict[KEY_LESSON] is String and dict[KEY_OPPONENTS] is Array):
		return null
	if not (dict[KEY_LEVELS] is Array):
		return null
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = dict[KEY_SCENARIO]
	if setup.scenario() == null:
		return null
	setup.match_seed = seed_value
	setup.local_seat = seat
	setup.local_side = side
	setup.first_opponent = first
	setup.bonus_starting_credits = bonus
	setup.map_id = StringName(dict[KEY_MAP] as String)
	setup.lesson_id = StringName(dict[KEY_LESSON] as String)
	for path: Variant in dict[KEY_OPPONENTS] as Array:
		var def: AiDef = _load_as(path) as AiDef
		if def == null:
			return null
		setup.opponents.append(def)
	for path: Variant in dict[KEY_LEVELS] as Array:
		var level: AiDifficultyDef = _load_as(path) as AiDifficultyDef
		if level == null:
			return null
		setup.opponent_levels.append(level)
	return setup


## `value` as an int within [low, high] (a whole float counts), else -1.
static func _int_in(value: Variant, low: int, high: int) -> int:
	var number: int = -1
	if value is int:
		number = value
	elif value is float and is_finite(value) and value == floorf(value):
		number = int(value)
	return number if number >= low and number <= high else -1


static func _load_as(path: Variant) -> Resource:
	if not (path is String) or not ResourceLoader.exists(path as String):
		return null
	return load(path as String)
