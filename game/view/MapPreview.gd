class_name MapPreview
extends RefCounted
## The map select's picture of a map (P666b), built from the scenario's data alone, with no sim: a
## top-down image of the map's terrain cells in the minimap's colours (`TerrainPalette`, the table
## behind `MapView.colors`), and each player's start (its first spawn) marked in the team colour
## of the scenario's `team_triads`. Presentation only: it reads a `ScenarioDef` and never touches
## `game/sim` state. Marks differ in shape as well as colour (touch-ui-rules: never colour alone):
## player 1 is a square, every other player a plus, both with a one-cell ink outline.
## One picture is built per scenario file and kept (`texture_for`), so switching maps is instant.
## It lives in game/view beside `MinimapImage`: it draws a picture of the map, whose colours are
## the map's and the teams' (not the menu theme's), so `game/ui`'s theme-only rule does not apply.

const PX_PER_CELL: int = 4  ## Texels per map cell.
const MARK_RADIUS: int = 3  ## Cells from the start cell to the edge of a mark.
const OUTLINE: int = 1  ## Cells of ink round a mark.
const INK: Color = Color("0B0D10")
const FIRST_PLAYER: int = 1

static var _images: Dictionary[String, Image] = {}
static var _textures: Dictionary[String, ImageTexture] = {}


## The kept image of the scenario file at `path` (built on first ask), null when the file has no
## map to show.
static func image_for(path: String) -> Image:
	if not _images.has(path):
		var scenario: ScenarioDef = (
			(load(path) as ScenarioDef) if ResourceLoader.exists(path) else null
		)
		var image: Image = build(scenario) if scenario != null else null
		if image == null:
			return null
		_images[path] = image
	return _images[path]


## The kept texture of the scenario file at `path`, null when it has no map to show.
static func texture_for(path: String) -> ImageTexture:
	if not _textures.has(path):
		var image: Image = image_for(path)
		if image == null:
			return null
		_textures[path] = ImageTexture.create_from_image(image)
	return _textures[path]


## Drops the kept pictures (tests).
static func forget() -> void:
	_images.clear()
	_textures.clear()


## The picture of `scenario`: PX_PER_CELL texels per cell, null for a scenario with no map rows or
## no terrain set.
static func build(scenario: ScenarioDef) -> Image:
	var map: MapDef = scenario.map
	if map == null or map.terrain == null:
		return null
	var size: Vector2i = map.size_tiles()
	if size.x <= 0 or size.y <= 0:
		return null
	var by_symbol: Dictionary[String, Color] = {}
	for def: TerrainDef in map.terrain.terrains:
		by_symbol[def.symbol] = TerrainPalette.colour(def.id)
	var image: Image = Image.create(
		size.x * PX_PER_CELL, size.y * PX_PER_CELL, false, Image.FORMAT_RGBA8
	)
	for y: int in size.y:
		var row: String = map.rows[y]
		for x: int in mini(row.length(), size.x):
			var colour: Color = by_symbol.get(row[x], TerrainPalette.MISSING)
			image.fill_rect(
				Rect2i(x * PX_PER_CELL, y * PX_PER_CELL, PX_PER_CELL, PX_PER_CELL), colour
			)
	var marked: Dictionary[int, bool] = {}
	for spawn: SpawnDef in scenario.spawns:
		if spawn.owner < FIRST_PLAYER or marked.has(spawn.owner):
			continue
		marked[spawn.owner] = true
		_mark(image, spawn.origin_tile, spawn.owner, mark_colour(scenario, spawn.owner))
	return image


## The mid tone of the triad player `owner` wears in `scenario` (the minimap's own rule).
static func mark_colour(scenario: ScenarioDef, owner: int) -> Color:
	var triad: Array = WorldSort.TRIADS[WorldSort.triad_index(scenario.team_triads, owner)]
	return Color(triad[1])


## The start cell of every player the picture marks: owner to its cell.
static func starts(scenario: ScenarioDef) -> Dictionary[int, Vector2i]:
	var found: Dictionary[int, Vector2i] = {}
	for spawn: SpawnDef in scenario.spawns:
		if spawn.owner >= FIRST_PLAYER and not found.has(spawn.owner):
			found[spawn.owner] = spawn.origin_tile
	return found


static func _mark(image: Image, cell: Vector2i, owner: int, colour: Color) -> void:
	var reach: int = MARK_RADIUS + OUTLINE
	_shape(image, cell, reach, owner, INK)
	_shape(image, cell, MARK_RADIUS, owner, colour)


## A square (player 1) or a plus (the others) of `reach` cells round `cell`.
static func _shape(image: Image, cell: Vector2i, reach: int, owner: int, colour: Color) -> void:
	var px: int = PX_PER_CELL
	var middle: Vector2i = cell * px
	var full: int = (reach * 2 + 1) * px
	if owner == FIRST_PLAYER:
		image.fill_rect(Rect2i(middle - Vector2i.ONE * reach * px, Vector2i.ONE * full), colour)
		return
	var arm: int = px * (1 + (reach - MARK_RADIUS))  # The plus is 3 cells thick, 5 with outline.
	image.fill_rect(
		Rect2i(middle + Vector2i(-reach * px, -arm), Vector2i(full, arm * 2 + px)), colour
	)
	image.fill_rect(
		Rect2i(middle + Vector2i(-arm, -reach * px), Vector2i(arm * 2 + px, full)), colour
	)
