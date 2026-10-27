extends RefCounted
## Fixtures of the building suites (plan P115). Not a test suite. A building scenario is a 32 x 32
## map with two players, the local one player 1, whose spawns the caller lists; the faction of each
## player is that of its first spawn with a sheet (the Derrick League's `fossil` units and
## buildings for player 1, the Lumen Accord's `renew` ones for player 2).

const RULES: String = "res://data/rules.tres"
const MAP: Vector2i = Vector2i(32, 32)


## A spawn of `unit` (a file of data/units) for `owner_id` with its top-left tile at (x, y).
static func spawn(owner_id: int, unit: String, x: int, y: int) -> SpawnDef:
	var made: SpawnDef = SpawnDef.new()
	made.owner = owner_id
	made.unit = load("res://data/units/%s.tres" % unit)
	made.count = 1
	made.origin_tile = Vector2i(x, y)
	return made


static func scenario(spawns: Array[SpawnDef]) -> ScenarioDef:
	var made: ScenarioDef = ScenarioDef.new()
	made.rules = load(RULES) as RulesDef
	made.spawns = spawns
	made.map_size_tiles = MAP
	made.player_count = 2
	return made


## A paused runner on `scenario`, started. Not in the tree: only the calls of the test move time.
static func runner(scenario_def: ScenarioDef) -> MatchRunner:
	var made: MatchRunner = MatchRunner.new()
	made.scenario = scenario_def
	made.paused = true
	made.start()
	return made


## Makes exactly `tiles` visible to `player` in the published snapshot's fog, the way the sim
## leaves one update: every other tile cleared, the version one higher.
static func see(snap: MatchSnapshot, player: int, tiles: Array) -> void:
	var fog: FogGrid = snap.fog
	var base: int = (player - 1) * fog.cells
	for cell: int in fog.cells:
		fog.visible[base + cell] = 0
	for tile: Vector2i in tiles:
		fog.visible[base + tile.y * fog.cols + tile.x] = 1
	fog.version[player - 1] += 1


## The row of the first unit of type `type_id` in `snap`, -1 for none.
static func row_of(snap: MatchSnapshot, type_id: StringName) -> int:
	for row: int in snap.unit_count():
		if snap.type_ids[snap.type_index[row]] == type_id:
			return row
	return -1


## The cast shadow of building `id` in the layer's decal layer, null for none.
static func shadow(layer: BuildingLayer, id: int) -> Sprite2D:
	return layer.decals.find_child("Shadow%d" % id, true, false) as Sprite2D


## The head of building `id`, null for a building without one.
static func head(layer: BuildingLayer, id: int) -> Sprite2D:
	var node: Node2D = layer.building(id)
	return node.get_node_or_null("Head") as Sprite2D if node != null else null


## The frame index (`d<NN>`) the head of building `id` shows, read back from the atlas: a head's
## region is the region of exactly one frame. -1 for a building without a head, -2 for a region
## that is none of the head's frames.
static func head_frame(layer: BuildingLayer, id: int) -> int:
	var sprite: Sprite2D = head(layer, id)
	var snap: MatchSnapshot = layer.runner.snapshot
	var row: int = snap.index_of(id)
	var art_id: StringName = snap.type_ids[snap.type_index[row]]
	var sheet: IsoSheetDef = layer.world_sort.sheet(art_id)
	if sprite == null or sheet == null:
		return -1
	var slot: int = layer.world_sort.slot_of(snap.owner[row])
	for frame: int in sheet.directions(&"head"):
		if (
			Rect2i(sprite.region_rect)
			== layer.world_sort.atlas.region(art_id, &"head", frame, slot)
		):
			return frame
	return -2
