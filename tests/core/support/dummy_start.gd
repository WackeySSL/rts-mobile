extends RefCounted
## The skirmish-like start of tests/ai/support/ai_rig.gd as a ScenarioDef (plan row P82), so a
## MatchRunner can play it: 40 x 40 tiles of the shipped terrain and rules, two players, each with
## a Headquarters, two rifle squads beside it, the rules' start credits and ore near its base, the
## bases 28 tiles apart. The map, the roster and the bases are the rig's own. Not a test suite.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const UNIT_DIR: String = "res://data/units/"


## A new scenario of the rig's start. Built in code, so its resource_path is empty.
static func scenario() -> ScenarioDef:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(Rig.rows())
	map.terrain = load(Rig.TERRAIN_PATH) as TerrainSetDef
	var built: ScenarioDef = ScenarioDef.new()
	built.map = map
	built.player_count = 2
	built.rules = load(Rig.RULES_PATH) as RulesDef
	built.spawns.append(_spawn(1, "headquarters", Rig.HQ_1, 1))
	built.spawns.append(_spawn(1, "rifle_squad", Vector2i(4, 10), 2))
	built.spawns.append(_spawn(2, "headquarters", Rig.HQ_2, 1))
	built.spawns.append(_spawn(2, "rifle_squad", Vector2i(24, 30), 2))
	for id: String in Rig.ROSTER:
		built.roster.append(load(UNIT_DIR + id + ".tres") as UnitDef)
	return built


## The shipped dummy def.
static func dummy_def() -> AiDef:
	return Rig.dummy_def()


static func _spawn(owner: int, id: String, tile: Vector2i, count: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner
	spawn.unit = load(UNIT_DIR + id + ".tres") as UnitDef
	spawn.count = count
	spawn.origin_tile = tile
	spawn.columns = 2
	spawn.spacing = 1000
	return spawn
