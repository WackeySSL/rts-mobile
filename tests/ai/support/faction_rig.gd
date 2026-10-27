extends RefCounted
## The start of `ai_rig.gd` for either faction (plan row P83d, ADR 0020 section 4, ADR 0023
## sections 6 and 7). Not a test suite.
##
## `start(first, second)` is the same 40 x 40 map, rules, fog, bases and ore as the rig's, with
## player 1 of the faction `first` and player 2 of the faction `second` (`fossil` or `renew`, the
## Derrick League or the Lumen Accord): each player has its faction's Headquarters at the rig's
## tile, two of its faction's rifle squads beside it and the rules' start credits. The scenario
## lists both factions, so the World knows every type of both rosters whatever the pairing, as the
## Skirmish route's will: a dummy that named a type of the other faction would be tried against the
## sim's faction rule. `scenario()` is the same start as a ScenarioDef, for a MatchRunner.
##
## The loop helpers (`tick`, `run`, `count_of`, `ids_of` and the rest) are the rig's, which take any
## World; the dummy's def is the faction's own file in `data/ai/`.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FACTION_DIR: String = "res://data/factions/"
const DEF_DIR: String = "res://data/ai/"
const UNIT_DIR: String = "res://data/units/"
const FACTIONS: Array[String] = ["fossil", "renew"]
## The type ids that the suites name by role, per faction: Headquarters, rifle squad (infantry) and
## scout (the fastest light vehicle, which attacks).
const HQ: Dictionary[String, String] = {"fossil": "headquarters", "renew": "renew_hq"}
const RIFLE: Dictionary[String, String] = {"fossil": "rifle_squad", "renew": "renew_rifle"}
const SCOUT: Dictionary[String, String] = {"fossil": "light_tank", "renew": "renew_scout"}


## The other faction of the two.
static func other(faction: String) -> String:
	return FACTIONS[1 - FACTIONS.find(faction)]


## The faction file of `faction`.
static func faction_def(faction: String) -> FactionDef:
	return load(FACTION_DIR + faction + ".tres") as FactionDef


## The dummy's def of `faction`.
static func def_of(faction: String) -> AiDef:
	return load(DEF_DIR + "dummy_" + faction + ".tres") as AiDef


## A dummy of `player` on the def of `faction`, with its own stream of `seed`.
static func dummy(faction: String, player: int, seed: int = 1) -> DummyAi:
	return Rig.ai_of(def_of(faction), player, seed)


## A prepared World of the start: player 1 of the faction `first`, player 2 of `second`.
static func start(first: String, second: String) -> World:
	return World.from_scenario(scenario(first, second))


## The start as a ScenarioDef (built in code, so its resource_path is empty).
static func scenario(first: String, second: String) -> ScenarioDef:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(Rig.rows())
	map.terrain = load(Rig.TERRAIN_PATH) as TerrainSetDef
	var built: ScenarioDef = ScenarioDef.new()
	built.map = map
	built.player_count = 2
	built.rules = load(Rig.RULES_PATH) as RulesDef
	built.spawns.append(_spawn(1, HQ[first], Rig.HQ_1, 1))
	built.spawns.append(_spawn(1, RIFLE[first], Vector2i(4, 10), 2))
	built.spawns.append(_spawn(2, HQ[second], Rig.HQ_2, 1))
	built.spawns.append(_spawn(2, RIFLE[second], Vector2i(24, 30), 2))
	# Entry 0 is unused (ADR 0023 section 6): entry p is player p's faction.
	var listed: Array[FactionDef] = [null, faction_def(first), faction_def(second)]
	built.factions = listed
	return built


## The faction id of the type `type` of `world` ("" for a type of no faction).
static func faction_of(world: World, type: int) -> String:
	var index: int = world.type_faction[type]
	return String(world.faction_ids[index]) if index >= 0 else ""


## Whether every row of `player` (a unit or a building) is of the faction `faction`.
static func owns_only(world: World, player: int, faction: String) -> bool:
	for row: int in world.unit_count():
		if world.owner[row] == player and faction_of(world, world.type_index[row]) != faction:
			return false
	return true


static func _spawn(owner: int, id: String, tile: Vector2i, count: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner
	spawn.unit = load(UNIT_DIR + id + ".tres") as UnitDef
	spawn.count = count
	spawn.origin_tile = tile
	spawn.columns = 2
	spawn.spacing = 1000
	return spawn
