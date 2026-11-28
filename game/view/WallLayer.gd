class_name WallLayer
extends Node
## The raised rock walls in the sorted world (ADR 0053 section 7, amendment A1 to A6, plan P656d2).
## With `walls_enabled` and a look whose kit has every wall piece, each rock cell is a raised prism:
## up to three sprites (face, top, rim: `WallKit`) of the wall band of `IsoAtlas` on `PAGE_SORTED`,
## drawn with no material, so they batch with the units and the buildings. One `Node2D` per diagonal
## row d = c + r that holds a wall is a child of `WorldSort`, at y = (d + 1) * 16, the centre y of
## every cell on the row; it does not sort its children, which lie in the order face, top, rim.
## So a wall cell sorts as a 1 x 1 footprint does (the centre key, ADR 0023 section 2) and the
## engine sorts at most cols + rows - 1 more items. A cell's pieces stand at its ground centre; the
## prism's rise is inside the piece (`TerrainKitDef.WALL_ORIGIN`).
## Fog (A6): the fog lies under the sorted world, so a wall shows one of three states from the
## local player's fog at its cell: lit, dim (a copy of the pieces baked with the fog's black) or
## hidden. `FogLayer.painted` hands over each cell it paints; a state change is a region write per
## sprite of that cell (at most 3), a cell that is no wall costs one byte read, nothing runs per
## frame. The walls are rebuilt on a new match and when the set of rock cells changes.
## A look without wall pieces (the kit lacks any of them) draws no wall: rock stays flat.
## `walls_enabled` is off in every shipped scene until P656d3 brings the silhouettes: units hidden
## behind a wall need them (plan risk 18).

enum State { HIDDEN, DIM, LIT }

const KIT_PATH: String = "res://assets/art/terrain/kit.tres"
const LOOK_KIT_PATH: String = "res://assets/art/terrain/looks/%s/kit.tres"
const ROCK: StringName = &"rock"

@export var runner: MatchRunner
@export var world_sort: WorldSort
@export var fog: FogLayer  ## The fog whose cells the states follow; all lit without one.
@export var walls_enabled: bool = false
@export var kit: TerrainKitDef  ## The standard kit when unset.
## look -> the wall pieces (piece key -> image); `load_pieces` when unset. Tests replace it.
var loader: Callable = Callable()

var _serial: int = -1
var _version: int = -1
var _cols: int = 0
var _raised: PackedByteArray = PackedByteArray()  ## A byte per cell, 1 for a wall.
var _cover: int = 0  ## Counts the near-wall sets made: a rig reads its cell again when it moves.
var _near: PackedByteArray = PackedByteArray()  ## A byte per cell, 1 near a wall.
var _state: PackedByteArray = PackedByteArray()  ## The State each wall cell shows.
var _first: PackedInt32Array = PackedInt32Array()  ## Cell -> its first sprite in `_sprites`.
var _count: PackedByteArray = PackedByteArray()  ## Cell -> how many sprites it has.
var _sprites: Array[Sprite2D] = []
var _keys: Array[StringName] = []  ## Parallel to `_sprites`: the piece each shows.
var _rows: Dictionary[int, Node2D] = {}  ## Diagonal -> its row node.
var _writes: int = 0
var _atlas: IsoAtlas
var _one_in: int = 0  ## The kit's `boulder_one_in` of rock, as P656d1 reads it.


func _enter_tree() -> void:
	if walls_enabled and world_sort != null:
		world_sort.wall_loader = loader if loader.is_valid() else load_pieces
		world_sort.wall_shade = fog.explored_alpha if fog != null else world_sort.wall_shade


func _ready() -> void:
	if fog != null:
		fog.painted.connect(_on_painted)


func _process(_delta: float) -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if not walls_enabled or snap == null or world_sort == null:
		return
	if snap.match_serial != _serial or snap.map_version != _version:
		_sync(snap)


## The wall pieces of `look` from its kit (the look's own `kit.tres` when it has one, else the
## standard one): every key of `WallKit.all_keys`, each a `WALL_CANVAS` image. Empty when any is
## missing or of another size, so a kit without walls (or only some) leaves rock flat.
func load_pieces(look: StringName) -> Dictionary[StringName, Image]:
	var pieces: Dictionary[StringName, Image] = {}
	var def: TerrainKitDef = kit_for(look)
	for key: StringName in WallKit.all_keys():
		var path: String = def.dir.path_join(def.pieces.get(key, "")) if def.pieces.has(key) else ""
		var image: Image = null
		if path != "" and ResourceLoader.exists(path):
			var texture: Texture2D = load(path) as Texture2D
			image = texture.get_image() if texture != null else null
		if image == null or Vector2i(image.get_size()) != TerrainKitDef.WALL_CANVAS:
			return {}
		pieces[key] = image
	return pieces


## The kit of `look`: the look's own `kit.tres` when it has one, else the standard one.
func kit_for(look: StringName) -> TerrainKitDef:
	if kit != null:
		return kit
	var look_kit: String = LOOK_KIT_PATH % look
	return load(look_kit if look != &"" and ResourceLoader.exists(look_kit) else KIT_PATH)


## Wall nodes alive (row nodes): 0 with the flag off and for a look without pieces.
func row_count() -> int:
	return _rows.size()


## The row node of diagonal `d`, null when it holds no wall.
func row_node(d: int) -> Node2D:
	return _rows.get(d)


## Sprites written (a state change of a cell) since the last `rebuild`: the write bound's reading.
func write_count() -> int:
	return _writes


## The state cell `cell` shows; HIDDEN for a cell that is no wall.
func state_of(cell: int) -> int:
	return (
		_state[cell] if cell >= 0 and cell < _state.size() and _raised[cell] != 0 else State.HIDDEN
	)


## The sprites of cell `cell` in draw order (face, top, rim; a missing piece leaves none).
func sprites_of(cell: int) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	if cell >= 0 and cell < _first.size() and _first[cell] >= 0:
		found.assign(_sprites.slice(_first[cell], _first[cell] + _count[cell]))
	return found


## Which near-wall set `is_near` answers from: it changes when the walls are rebuilt.
func cover_version() -> int:
	return _cover


## Whether a unit standing in cell `cell` may be hidden by a wall: the near-wall byte (A7).
func is_near(cell: int) -> bool:
	return cell >= 0 and cell < _near.size() and _near[cell] != 0


## The ground point, in milli-tiles, that a tap at the world px `p` means (A8): a wall's cell
## centre where `p` is on a wall's top or face, else the flat ground (`WallCover.ground_at`).
func ground_at(p: Vector2) -> Vector2i:
	return WallCover.ground_at(_raised, _cols, p)


## Whether cell `cell` is a wall.
func is_wall(cell: int) -> bool:
	return cell >= 0 and cell < _raised.size() and _raised[cell] != 0


func _sync(snap: MatchSnapshot) -> void:
	var serial_new: bool = snap.match_serial != _serial
	_serial = snap.match_serial
	_version = snap.map_version
	world_sort.sync()
	_atlas = world_sort.atlas
	var raised: PackedByteArray = PackedByteArray()
	var rock: int = snap.terrain_ids.find(ROCK)
	if rock >= 0 and _atlas.wall_band_rows() > 0:
		raised.resize(snap.terrain.size())
		for cell: int in snap.terrain.size():
			raised[cell] = 1 if snap.terrain[cell] == rock else 0
	if not serial_new and raised == _raised and snap.map_cols == _cols:
		return  # A building changed the map version, not the rock.
	_clear()
	var map: MapDef = runner.scenario.map if runner.scenario != null else null
	_one_in = kit_for(map.ground_look if map != null else &"").boulder_one_in.get(ROCK, 0)
	_cols = snap.map_cols
	_raised = raised
	_publish_cover(snap.map_rows)
	if raised.is_empty():
		return
	_build(snap.map_rows)


## Makes the near-wall bytes and gives the silhouettes' material the wall mask: one byte per cell,
## 255 for a wall (a 1 x 1 empty mask when there is none, so the shader covers nothing).
func _publish_cover(map_rows: int) -> void:
	_cover += 1
	_near = WallCover.near_bytes(_raised, _cols)
	var size: Vector2i = Vector2i(_cols, map_rows) if not _raised.is_empty() else Vector2i.ONE
	var bytes: PackedByteArray = PackedByteArray([0])
	if not _raised.is_empty():
		bytes = _raised.duplicate()
		for at: int in bytes.size():
			bytes[at] = 255 if bytes[at] != 0 else 0
	var image: Image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, bytes)
	var material: ShaderMaterial = world_sort.silhouette_material()
	material.set_shader_parameter("wall_mask", ImageTexture.create_from_image(image))
	material.set_shader_parameter("grid_size", size)


func _clear() -> void:
	for row: Node2D in _rows.values():
		row.get_parent().remove_child(row)
		row.queue_free()
	_rows.clear()
	_sprites.clear()
	_keys.clear()
	_raised = PackedByteArray()
	_writes = 0


func _build(map_rows: int) -> void:
	_state.resize(_raised.size())
	_first.resize(_raised.size())
	_first.fill(-1)
	_count.resize(_raised.size())
	_count.fill(0)
	for d: int in _cols + map_rows - 1:
		for col: int in range(maxi(0, d - map_rows + 1), mini(d, _cols - 1) + 1):
			var cell: int = (d - col) * _cols + col
			if _raised[cell] != 0:
				_add_cell(cell, col, d - col, d)
	for cell: int in _raised.size():  # The first state: from the fog as it is.
		if _raised[cell] != 0:
			_state[cell] = 255  # Unset, so the first write happens.
			_set_state(cell, _fog_state(cell))
	_writes = 0


func _add_cell(cell: int, col: int, row: int, d: int) -> void:
	if not _rows.has(d):
		var node: Node2D = Node2D.new()
		node.name = "Row%d" % d
		node.position = Vector2(0.0, float((d + 1) * IsoProjection.HALF_H))
		world_sort.add_child(node)
		_rows[d] = node
	var centre: Vector2 = IsoProjection.cell_centre_px(col, row) - _rows[d].position
	_first[cell] = _sprites.size()
	for key: StringName in WallKit.pieces(_raised, _cols, col, row, _one_in):
		if key == &"":
			continue
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _atlas.texture()
		sprite.region_enabled = true
		sprite.centered = false
		sprite.scale = Vector2(WorldSort.ART_SCALE, WorldSort.ART_SCALE)
		sprite.offset = -Vector2(TerrainKitDef.WALL_ORIGIN)
		sprite.position = centre
		_rows[d].add_child(sprite)
		_sprites.append(sprite)
		_keys.append(key)
		_count[cell] += 1


func _fog_state(cell: int) -> int:
	if fog == null:
		return State.LIT
	var alpha: int = fog.target_alpha(cell)
	if alpha == 0:
		return State.LIT
	return State.HIDDEN if alpha >= FogLayer.UNEXPLORED_ALPHA else State.DIM


## Shows `state` on the sprites of `cell`: a region write each, none when it already shows it.
func _set_state(cell: int, state: int) -> void:
	if _state[cell] == state:
		return
	_state[cell] = state
	for at: int in range(_first[cell], _first[cell] + _count[cell]):
		var sprite: Sprite2D = _sprites[at]
		sprite.visible = state != State.HIDDEN
		if state != State.HIDDEN:
			sprite.region_rect = Rect2(_atlas.wall_region(_keys[at], state == State.DIM))
		_writes += 1


func _on_painted(cells: PackedInt32Array) -> void:
	if _raised.is_empty():
		return  # The build reads the fog itself.
	for cell: int in cells:
		if cell < _raised.size() and _raised[cell] != 0:
			_set_state(cell, _fog_state(cell))
