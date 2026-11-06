extends RefCounted
## The opponent AI's defs and controllers for the suites (plan row P175, ADR 0030). Not a test
## suite. The Worlds are `faction_rig.gd`'s (the frozen defs of `data/dev/arena/`); the AI's own
## defs are the shipped files of `data/ai/`.

const DEF_DIR: String = "res://data/ai/"
const LEVELS: Array[String] = ["easy", "normal", "hard"]
const FACTIONS: Array[String] = ["fossil", "renew"]


static func def_of(faction: String) -> OpponentDef:
	return load(DEF_DIR + "opponent_" + faction + ".tres") as OpponentDef


static func level_of(level: String) -> AiDifficultyDef:
	return load(DEF_DIR + "difficulty/" + level + ".tres") as AiDifficultyDef


## An opponent of `player` on `faction` at `level` with its own stream of `seed`.
static func opponent(faction: String, level: String, player: int, seed: int = 1) -> OpponentAi:
	var stream: DetRandom = DetRandom.create(seed, DetRandom.STREAM_AI_BASE + player)
	return OpponentAi.create(def_of(faction), level_of(level), player, stream)
