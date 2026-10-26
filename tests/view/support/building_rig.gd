extends RefCounted
## Fixtures of the building layer suites (plan P84, ADR 0022). Not a test suite. The suites run on
## the base match of tests/core/support/base_match.gd (40 x 24 tiles, seed 42): player 1's
## Headquarters (3x3, tile (2, 2)), power plant (2x2, (6, 2)), refinery (3x3, (2, 7)), barracks
## (2x2, (6, 7)), vehicle factory (3x3, (2, 13)) and defence turret (1x1, (9, 5)), ids 1-6; two
## harvesters and three rifle squads, ids 7-11; and player 2's mirror of all that in the east, ids
## 12-17 for the buildings, 18-22 for the units. Player 1 is local and sees only its own corner at
## the start, so every enemy building is hidden until a test lets the fog show it. The layers are
## made outside the scene, not processed by the tree: frames come only from the calls of the suite.

const BaseMatch: GDScript = preload("res://tests/core/support/base_match.gd")
const BUILDING_ART: String = "res://assets/art/svg/buildings/%s_%s.svg"
const SEED: int = 42
const OWN_BUILDINGS: int = 6
const BUILDINGS: int = 12
const MAP_COLS: int = 40
const MAP_ROWS: int = 24
## The reach of a unit sprite from its centre in world px: a rifle squad, a light tank, the
## harvester along an axis and a 128 px canvas corner (ADR 0022 section 2).
const REACHES: Array[float] = [14.0, 26.0, 40.0, 57.0]


## The runner of the base match, started.
static func runner(scenario: ScenarioDef = null) -> MatchRunner:
	var made: MatchRunner = MatchRunner.new()
	made.scenario = scenario if scenario != null else BaseMatch.scenario()
	made.match_seed = SEED
	made.start()
	return made


## The buildings of the base match in row order: `id`, `owner`, `origin` (the top-left tile) and
## `foot` (tiles), as the scenario places them (player 2 mirrored across the map).
static func buildings() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for owner: int in [1, 2]:
		for entry: Array in BaseMatch.BUILDINGS:
			var def: BuildingDef = load(BaseMatch.UNIT_DIR + str(entry[0]) + ".tres") as BuildingDef
			var tile: Vector2i = entry[1]
			if owner == 2:
				tile.x = BaseMatch.COLS - tile.x - def.footprint.x
			list.append({&"id": entry[0], &"owner": owner, &"origin": tile, &"foot": def.footprint})
	return list


## The size of a building layer's imported texture in px (the rise included).
static func texture_size(id: StringName, layer: String = "hull") -> Vector2:
	return (load(BUILDING_ART % [id, layer]) as Texture2D).get_size()


## The footprint of a building of `buildings()` in world px.
static func footprint_rect(building: Dictionary) -> Rect2:
	var origin: Vector2i = building[&"origin"]
	var foot: Vector2i = building[&"foot"]
	return Rect2(Vector2(origin * ViewScale.PX_PER_TILE), Vector2(foot * ViewScale.PX_PER_TILE))


## The index in `buildings()` of the first building of `id` owned by `owner`.
static func find(list: Array[Dictionary], id: StringName, owner: int) -> int:
	for index: int in list.size():
		if list[index][&"id"] == id and list[index][&"owner"] == owner:
			return index
	return -1
