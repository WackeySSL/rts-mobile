extends RefCounted
## Fixtures of the ground suites (plan P116). Not a test suite. An 8 x 6 map of the six terrains of
## `data/terrain/standard.tres` with four fields of ore (`o`), by cell number (row * 8 + column):
## a 2 x 2 field (10, 11, 18, 19), a lone cell (15), a lone cell that touches the 2 x 2 field and
## the line only at a corner (28), and a line of three (33, 34, 35). A corner is not an edge, so
## they are four fields, not one. The ore indexes (into `ore_cell` and `ore_amount`) are 0 to 8 in
## the order of the cells: 10, 11, 15, 18, 19, 28, 33, 34, 35.

const TERRAIN: String = "res://data/terrain/standard.tres"
const RULES: String = "res://data/rules.tres"
const COLS: int = 8
const ROW_COUNT: int = 6
const ROWS: PackedStringArray = [
	".:^#~...",
	"..oo...o",
	"..oo....",
	"....o...",
	".ooo....",
	"........",
]
const ORE_CELLS: Array[int] = [10, 11, 15, 18, 19, 28, 33, 34, 35]
## The ore indexes of each field, in the order of their lowest cells, and the cell each wellhead
## stands on: the cell nearest the field's middle (the lowest of equal ones).
const FIELDS: Array[Array] = [[0, 1, 3, 4], [2], [5], [6, 7, 8]]
const WELLHEADS: Array[int] = [10, 15, 28, 34]
## The index of each terrain in the set, for `World.set_terrain`.
const GRASS: int = 0
const ROCK: int = 3
const WATER: int = 4


## A scenario on `rows`, with the standard terrain. `most` -1 gives it the shipped rules, 0 none
## (the script defaults then apply) and a larger number a copy of them with that `ore_cell_max`.
static func scenario(rows: PackedStringArray = ROWS, most: int = -1) -> ScenarioDef:
	var map: MapDef = MapDef.new()
	map.rows = rows
	map.terrain = load(TERRAIN)
	var result: ScenarioDef = ScenarioDef.new()
	result.map = map
	if most != 0:
		result.rules = load(RULES)
		if most > 0:
			result.rules = (result.rules as RulesDef).duplicate()
			(result.rules as RulesDef).ore_cell_max = most
	return result


## A runner with `scenario`, started.
static func runner(scenario_def: ScenarioDef) -> MatchRunner:
	var result: MatchRunner = MatchRunner.new()
	result.scenario = scenario_def
	result.start()
	return result


## The keys of the tiles on the page: both variants of the six terrains and the six field stages.
static func tile_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for id: String in ["grass", "sand", "scrub", "rock", "water", "ore"]:
		keys.append(StringName("%s_a" % id))
		keys.append(StringName("%s_b" % id))
	for kind: StringName in GroundAtlas.KINDS:
		for stage: StringName in GroundAtlas.STAGES:
			keys.append(StringName("%s_%s" % [kind, stage]))
	return keys


## The key of the tile on cell (`col`, `row`) of `layer`, an empty name for none.
static func key_at(layer: TileMapLayer, atlas: GroundAtlas, col: int, row: int) -> StringName:
	var coords: Vector2i = layer.get_cell_atlas_coords(Vector2i(col, row))
	for key: StringName in tile_keys():
		if atlas.coords(key) == coords:
			return key
	return &""
