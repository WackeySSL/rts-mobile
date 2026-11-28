class_name GroundLayer
extends TileMapLayer
## The ground (ADR 0023 sections 1, 2 and 5, STYLE.md "Iso ground tiles", plan P116): one 64 x 32
## diamond tile per cell on an isometric `TileMapLayer` from the one page of `GroundAtlas`, the
## terrain's variant `a` or `b` by `(column + row) % 2` (a for 0). The node sits at
## `IsoProjection.TILE_LAYER_OFFSET`, so a tile is its cell's diamond. It fills the map once per
## match and, when `map_version` moves, writes only the cells whose tile changed. Its child
## `FieldLayer` draws the field stages and wellheads from the same page: one texture in all. At z 0
## after `MapView`, which stops drawing its bake while `covers_map()`. While in the tree it sets the
## clear colour to the off-map colour (STYLE.md). It reads `runner.snapshot` and the scenario's
## rules (`ore_cell_max`, which the snapshot does not carry).
##
## With a `kit` (P656d1, ADR 0053 section 7 and amendment A2) two child layers at scale 0.5 draw the
## pre-rendered 128 x 64 pieces from the kit page: `Base`, one flat piece per cell (a hashed
## variant, `TerrainKit`), and `Edge`, at most one blend or shore piece per cell. Nothing rises; no
## rock lip is drawn. A terrain the kit lacks (or a map look it has no kit for) keeps this layer's
## own SVG diamonds, so `covers_map()` holds. A map change rewrites the cells that changed and the
## edge pieces of their 8 neighbours; no frame writes anything.

const OFF_MAP_COLOR: Color = Color("16191D")
const NO_COORDS: Vector2i = Vector2i(-1, -1)  ## What `GroundAtlas.coords` says for no tile.
const CLEAR_COLOR_SETTING: String = "rendering/environment/defaults/default_clear_color"
const KIT_SCALE: Vector2 = Vector2(0.5, 0.5)  ## The kit layers draw 128 x 64 pieces at half size.
const KIT_LOOK_ROOT: String = "res://assets/art/terrain/looks"  ## `<look>/kit.tres` per look.

@export var runner: MatchRunner
## The folder of the map looks; tests point it at a fixture.
@export var look_root: String = GroundAtlas.LOOK_ROOT
## The terrain kit. Empty: the SVG diamonds alone, as before the kit.
@export var kit: TerrainKitDef
## Where a map look's own kit lies (`<look>/kit.tres`); a look without one uses the SVG diamonds.
@export var kit_look_root: String = KIT_LOOK_ROOT

var _art: GroundAtlas
var _ids: Array[StringName] = []  ## The terrain ids `_art` was built for.
var _look: StringName = &""  ## The map's ground look `_art` was built for.
var _used_kit: TerrainKitDef = null  ## The kit `_art` was built with.
var _fields: FieldLayer = FieldLayer.new()
var _base: TileMapLayer = TileMapLayer.new()
var _edge: TileMapLayer = TileMapLayer.new()
var _serial: int = -1  ## match_serial of the fill.
var _version: int = -1  ## map_version of the fill.
var _cols: int = 0
## Per terrain index, a then b: the tile's coordinates, NO_COORDS for missing art.
var _tile_of: Array[Vector2i] = []
var _on_kit: Array[bool] = []  ## Per terrain index: the kit page draws it.
var _mixed: bool = false  ## Some terrains are on the kit and some are not.
var _seen: PackedByteArray = PackedByteArray()  ## The terrain the layers were last written for.
var _writes: int = 0
var _edge_writes: int = 0
var _covered: bool = false


func _init() -> void:
	position = IsoProjection.TILE_LAYER_OFFSET
	_base.name = "Base"
	_edge.name = "Edge"
	_fields.name = "Fields"
	for layer: TileMapLayer in [_base, _edge]:
		layer.scale = KIT_SCALE
		add_child(layer)
	add_child(_fields)


func _enter_tree() -> void:
	RenderingServer.set_default_clear_color(OFF_MAP_COLOR)


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(
		ProjectSettings.get_setting(CLEAR_COLOR_SETTING, Color(0.3, 0.3, 0.3))
	)


func _ready() -> void:
	_sync()


func _process(_delta: float) -> void:
	_sync()


## Whether every cell of the map has its tile, so `MapView`'s bake would be hidden under it: false
## before the first fill, with no map and when a terrain has no art.
func covers_map() -> bool:
	return _covered


## Ground tiles written so far (a kit base piece or an SVG diamond): every cell once per match,
## then the cells a map change touched.
func write_count() -> int:
	return _writes


## Edge pieces (blends and shores) written so far: at most 9 per changed cell after the first fill.
func edge_write_count() -> int:
	return _edge_writes


## The page the ground, the fields and the props draw from.
func atlas() -> GroundAtlas:
	return _art


## The kit's two layers: the flat base pieces, and the blends and shores over them.
func base_layer() -> TileMapLayer:
	return _base


func edge_layer() -> TileMapLayer:
	return _edge


func _sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	if snap.match_serial != _serial:
		_begin(snap)
	elif snap.map_version != _version:
		_fill(snap)
	_fields.update(snap)


## The kit for a map look: the shared one for no look, the look's own when it has one, else none.
func _kit_for(look: StringName) -> TerrainKitDef:
	if kit == null or look == &"":
		return kit
	var path: String = "%s/%s/kit.tres" % [kit_look_root, look]
	return load(path) as TerrainKitDef if ResourceLoader.exists(path) else null


## A new match: the page for its terrains (kept while they are the same), an empty layer, a full
## fill and its fields.
func _begin(snap: MatchSnapshot) -> void:
	_serial = snap.match_serial
	var map: MapDef = runner.scenario.map if runner.scenario != null else null
	var look: StringName = map.ground_look if map != null else &""
	var chosen: TerrainKitDef = _kit_for(look)
	if _art == null or _ids != snap.terrain_ids or _look != look or _used_kit != chosen:
		_ids = snap.terrain_ids.duplicate()
		_look = look
		_used_kit = chosen
		_art = GroundAtlas.build(_ids, look, look_root, chosen)
	tile_set = _art.tile_set
	_base.tile_set = _art.kit_tile_set
	_edge.tile_set = _art.kit_tile_set
	clear()
	_base.clear()
	_edge.clear()
	_seen = PackedByteArray()
	_cols = snap.map_cols
	_tile_of.clear()
	_on_kit.clear()
	_covered = not snap.terrain.is_empty()
	for id: StringName in _ids:
		var pair: Array[Vector2i] = []
		for variant: String in ["a", "b"]:
			pair.append(_art.coords(StringName("%s_%s" % [id, variant])))
		_tile_of.append_array(pair)
		_on_kit.append(_art.kit_covers(id))
		_covered = _covered and (_on_kit[-1] or not pair.has(NO_COORDS))
	_mixed = _on_kit.has(true) and _on_kit.has(false)
	_fill(snap)
	var rules: RulesDef = runner.scenario.rules if runner.scenario != null else null
	_fields.begin(snap, _art, (rules if rules != null else RulesDef.new()).ore_cell_max)


## Writes the cells whose tile differs from the one their terrain calls for: all of them at the
## first fill, then the cells whose terrain changed and, for the edge layer, their 8 neighbours.
@warning_ignore("integer_division")
func _fill(snap: MatchSnapshot) -> void:
	_version = snap.map_version
	var terrain: PackedByteArray = snap.terrain
	var first: bool = _seen.size() != terrain.size()
	var touched: Array[int] = []
	for cell: int in terrain.size():
		if first or terrain[cell] != _seen[cell]:
			touched.append(cell)
			_put_base(terrain, Vector2i(cell % _cols, cell / _cols))
	if _used_kit != null:
		var rows: int = terrain.size() / _cols
		var near: Dictionary[int, bool] = {}
		for cell: int in touched:
			var at: Vector2i = Vector2i(cell % _cols, cell / _cols)
			for side: Vector2i in _around(at, rows):
				near[side.y * _cols + side.x] = true
		for cell: int in near:
			var at: Vector2i = Vector2i(cell % _cols, cell / _cols)
			if _put(_edge, at, _edge_coords(terrain, at)):
				_edge_writes += 1
	_seen = terrain.duplicate()


## The cell and its 8 neighbours that lie on a map of `rows` rows.
func _around(at: Vector2i, rows: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var side: Vector2i = at + Vector2i(dx, dy)
			if side.x >= 0 and side.x < _cols and side.y >= 0 and side.y < rows:
				found.append(side)
	return found


## The ground tile of a cell: the kit's hashed base piece, or its SVG diamond.
func _put_base(terrain: PackedByteArray, at: Vector2i) -> void:
	var index: int = terrain[at.y * _cols + at.x]
	if _on_kit[index]:
		var key: StringName = TerrainKit.base_key(_used_kit, _ids[index], at.x, at.y)
		if _put(_base, at, _art.kit_coords(key)):
			_writes += 1
		if _mixed:
			_put(self, at, NO_COORDS)
	else:
		if _put(self, at, _tile_of[index * 2 + ((at.x + at.y) & 1)]):
			_writes += 1
		if _mixed:
			_put(_base, at, NO_COORDS)


## The edge piece of a cell: a blend or a shore, NO_COORDS for none. A cell whose eight neighbours
## are its own terrain has none, so the common cell is a few byte compares.
func _edge_coords(terrain: PackedByteArray, at: Vector2i) -> Vector2i:
	var own: int = terrain[at.y * _cols + at.x]
	if not _on_kit[own]:
		return NO_COORDS
	var edges: Array[StringName] = []
	var diagonals: Array[StringName] = []
	var differs: bool = false
	for step: Vector2i in TerrainKit.EDGE_STEPS:
		edges.append(_id_at(terrain, at + step))
	for step: Vector2i in TerrainKit.DIAGONAL_STEPS:
		diagonals.append(_id_at(terrain, at + step))
	for id: StringName in edges + diagonals:
		differs = differs or (id != &"" and id != _ids[own])
	if not differs:
		return NO_COORDS
	return _art.kit_coords(TerrainKit.edge_key(_used_kit, _ids[own], edges, diagonals))


## The terrain id on a cell, "" off the map.
func _id_at(terrain: PackedByteArray, at: Vector2i) -> StringName:
	if at.x < 0 or at.x >= _cols or at.y < 0 or at.y * _cols >= terrain.size():
		return &""
	return _ids[terrain[at.y * _cols + at.x]]


## Sets `at` of `layer` to the tile `coords` (NO_COORDS erases); false when it already was.
func _put(layer: TileMapLayer, at: Vector2i, coords: Vector2i) -> bool:
	if coords == layer.get_cell_atlas_coords(at):
		return false
	if coords == NO_COORDS:
		layer.erase_cell(at)
	else:
		layer.set_cell(at, 0, coords)
	return true
