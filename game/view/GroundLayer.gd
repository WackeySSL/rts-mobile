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

const OFF_MAP_COLOR: Color = Color("16191D")
const NO_COORDS: Vector2i = Vector2i(-1, -1)  ## What `GroundAtlas.coords` says for no tile.
const CLEAR_COLOR_SETTING: String = "rendering/environment/defaults/default_clear_color"

@export var runner: MatchRunner

var _art: GroundAtlas
var _ids: Array[StringName] = []  ## The terrain ids `_art` was built for.
var _fields: FieldLayer = FieldLayer.new()
var _serial: int = -1  ## match_serial of the fill.
var _version: int = -1  ## map_version of the fill.
var _cols: int = 0
## Per terrain index, a then b: the tile's coordinates, NO_COORDS for missing art.
var _tile_of: Array[Vector2i] = []
var _writes: int = 0
var _covered: bool = false


func _init() -> void:
	position = IsoProjection.TILE_LAYER_OFFSET
	_fields.name = "Fields"
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


## Tiles written so far: every cell once per match, then the cells a map change touched.
func write_count() -> int:
	return _writes


## The page the ground, the fields and the props draw from.
func atlas() -> GroundAtlas:
	return _art


func _sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	if snap.match_serial != _serial:
		_begin(snap)
	elif snap.map_version != _version:
		_fill(snap)
	_fields.update(snap)


## A new match: the page for its terrains (kept while they are the same), an empty layer, a full
## fill and its fields.
func _begin(snap: MatchSnapshot) -> void:
	_serial = snap.match_serial
	if _art == null or _ids != snap.terrain_ids:
		_ids = snap.terrain_ids.duplicate()
		_art = GroundAtlas.build(_ids)
	tile_set = _art.tile_set
	clear()
	_cols = snap.map_cols
	_tile_of.clear()
	for id: StringName in _ids:
		for variant: String in ["a", "b"]:
			_tile_of.append(_art.coords(StringName("%s_%s" % [id, variant])))
	_covered = not snap.terrain.is_empty() and not _tile_of.has(NO_COORDS)
	_fill(snap)
	var rules: RulesDef = runner.scenario.rules if runner.scenario != null else null
	_fields.begin(snap, _art, (rules if rules != null else RulesDef.new()).ore_cell_max)


## Writes the cells whose tile differs from the one their terrain calls for.
@warning_ignore("integer_division")
func _fill(snap: MatchSnapshot) -> void:
	_version = snap.map_version
	for cell: int in snap.terrain.size():
		var at: Vector2i = Vector2i(cell % _cols, cell / _cols)
		var coords: Vector2i = _tile_of[snap.terrain[cell] * 2 + ((at.x + at.y) & 1)]
		if coords == get_cell_atlas_coords(at):
			continue
		_writes += 1
		if coords == NO_COORDS:
			erase_cell(at)
		else:
			set_cell(at, 0, coords)
