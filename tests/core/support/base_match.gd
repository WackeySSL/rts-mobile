extends RefCounted
## A base match for the P81 suites (plan row P81, ADR 0017 section 6), built in code as a
## ScenarioDef so a runner loads it like a shipped scenario: 40 x 24 tiles of the standard terrain
## with two ore fields per side and two contested ones in the middle, a rock wall with a gap, water,
## sand and scrub; the shipped rules; two players, each with a Headquarters, a power plant, a
## refinery, a barracks, a vehicle factory and a defence turret, two harvesters and three rifle
## squads. Player 1's base is in the west, player 2's mirrors it in the east, far beyond every
## sight and weapon range, so nobody fights in the first ticks. Not a test suite.

const UNIT_DIR: String = "res://data/units/"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const RULES_PATH: String = "res://data/rules.tres"
const COLS: int = 40
## One string per tile row: '.' grass, ':' sand, '^' scrub, '#' rock, '~' water, 'o' ore.
const ROWS: Array[String] = [
	"..........^^.......##.......^^..........",
	"..........^^.......##.......^^..........",
	"............ooo....##....ooo............",
	"............ooo....##....ooo............",
	"...................##...................",
	"...................##...................",
	"...................##...................",
	"........................................",
	"................~~......................",
	"................~~......................",
	"...................oo...................",
	"...................oo...................",
	"...................oo...................",
	"...................oo...................",
	"......................~~................",
	".........::...........~~.....::.........",
	".........::..................::.........",
	".........::........##........::.........",
	"............ooo....##....ooo............",
	"............ooo....##....ooo............",
	"...................##...................",
	"...................##...................",
	"...................##...................",
	"...................##...................",
]
## Player 1's buildings: the type id and the top-left tile. Player 2's mirror them across the map.
const BUILDINGS: Array[Array] = [
	["headquarters", Vector2i(2, 2)],
	["power_plant", Vector2i(6, 2)],
	["refinery", Vector2i(2, 7)],
	["barracks", Vector2i(6, 7)],
	["vehicle_factory", Vector2i(2, 13)],
	["defence_turret", Vector2i(9, 5)],
]
## Player 1's units: the type id, the count and the origin tile of the row they stand in, one tile
## apart. Player 2's mirror them.
const UNITS: Array[Array] = [["harvester", 2, Vector2i(6, 11)], ["rifle_squad", 3, Vector2i(9, 9)]]


## The scenario. Each call loads the definitions anew; the shipped resources are cached.
static func scenario() -> ScenarioDef:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(ROWS)
	map.terrain = load(TERRAIN_PATH) as TerrainSetDef
	var made: ScenarioDef = ScenarioDef.new()
	made.map_size_tiles = Vector2i(COLS, ROWS.size())
	made.map = map
	made.rules = load(RULES_PATH) as RulesDef
	made.player_count = 2
	for owner: int in [1, 2]:
		for entry: Array in BUILDINGS:
			var def: UnitDef = load(UNIT_DIR + str(entry[0]) + ".tres") as UnitDef
			var tile: Vector2i = entry[1]
			if owner == 2:
				tile.x = COLS - tile.x - (def as BuildingDef).footprint.x
			made.spawns.append(_spawn(owner, def, 1, tile))
		for entry: Array in UNITS:
			var def: UnitDef = load(UNIT_DIR + str(entry[0]) + ".tres") as UnitDef
			var tile: Vector2i = entry[2]
			var count: int = entry[1]
			if owner == 2:
				tile.x = COLS - tile.x - count
			made.spawns.append(_spawn(owner, def, count, tile))
	return made


## `count` of `unit` for `owner` in one row from `tile`, one tile apart.
static func _spawn(owner: int, unit: UnitDef, count: int, tile: Vector2i) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner
	spawn.unit = unit
	spawn.count = count
	spawn.origin_tile = tile
	spawn.columns = count
	spawn.spacing = World.MILLI_PER_TILE
	return spawn
