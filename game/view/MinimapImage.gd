class_name MinimapImage
extends RefCounted
## The minimap's one picture (ADR 0019 section 4, ADR 0023 section 4, plan P88): an RGBA8 image of
## one texel per map cell, which `Minimap` draws under the fog's skew (`IsoProjection.cell_to_px`),
## so the map is a diamond in a 2:1 box. It shows only what the local player may see: the terrain
## as MapView's colours, black where the player never was and dimmed (`explored_alpha`, the fog's
## own) where it was and is not now, the player's own rows, an enemy row only where the player sees
## it now (a unit by its cell, a building by any cell of its footprint, the view's rule), and a
## last-seen record dimmed where no cell of its footprint is seen (`GhostMemoryLayer`'s rule). A
## hidden enemy is never written. Rows take the mid and light tone of their owner's triad
## (`WorldSort.TRIADS`): a building fills its footprint, a unit is one cell.
## `update` is called every frame and tick and does something only at the fog's cadence: the fog
## part of the picture (`_ground`) is patched from the player's dirty list when its fog version
## moved, as `FogLayer` does, and the rows are painted over a copy of it and uploaded when the
## fog moved or `period_ticks` ticks (the fog's `fog_period_ticks`, 3) passed since the last paint.
## So a redraw costs the rows and the dirty cells, never the map, and at most one comes in
## `period_ticks` ticks. The CPU-side `image()` is what tests read, never the texture.

const BYTES_PER_TEXEL: int = 4  ## RGBA8; the alpha stays 255.
const ALPHA_MAX: int = 255
const MILLI: int = World.MILLI_PER_TILE
const HALF: int = World.TILE_CENTRE
const UNEXPLORED: Color = Color("0B0D10")
const MISSING: Color = Color.MAGENTA  ## A terrain id the palette lacks.
## The tones of a team in `_team`: units, buildings, and a building remembered.
const LIGHT: int = 0
const MID: int = 1
const GHOST: int = 2

## The terrain colours by terrain id: `MapView.colors`.
var terrain_colours: Dictionary[StringName, Color] = {}
## The alpha of the black over a tile seen before and not now: keep it equal to the fog's.
var explored_alpha: int = 140
## Ticks between two paints when the fog did not move.
var period_ticks: int = 3

var _serial: int = -1  ## match_serial of the picture.
var _map_version: int = -1
var _player: int = -1
var _cols: int = 0
var _rows: int = 0
var _version: int = -1  ## The player's fog version at the last update (-1: no fog for it).
var _tick: int = -1  ## Tick of the last snapshot looked at.
var _drawn: int = 0  ## Tick of the last paint.
var _lit: PackedByteArray = PackedByteArray()  ## RGB per terrain index, in full light.
var _dim: PackedByteArray = PackedByteArray()  ## The same, under the explored shade.
var _team: PackedByteArray = PackedByteArray()  ## RGB per owner slot and tone.
var _terrain: PackedByteArray = PackedByteArray()  ## The snapshot's terrain index per cell.
var _ground: PackedByteArray = PackedByteArray()  ## RGBA of the terrain under the fog, per cell.
var _bytes: PackedByteArray = PackedByteArray()  ## `_ground` with the rows on it: what is shown.
var _counts: PackedInt32Array = PackedInt32Array()  ## The snapshot's visible counts, all players.
var _explored: PackedByteArray = PackedByteArray()
var _from: int = 0  ## Where the player's block starts in `_counts` and `_explored`.
var _all_seen: bool = true  ## The fog has no grid for the player: nothing is hidden.
var _image: Image = Image.new()
var _texture: ImageTexture = null
var _redraws: int = 0
var _shaded: int = 0  ## Cells the last update gave a ground colour: the dirty list, or all.


func cols() -> int:
	return _cols


func rows() -> int:
	return _rows


## The CPU-side picture, cols x rows. Empty before the first snapshot with a map.
func image() -> Image:
	return _image


## The texture of the picture; null until the first paint, and for a match with no map.
func texture() -> ImageTexture:
	return _texture


## How many times the picture was painted and uploaded: at the fog's cadence, never per frame.
func redraw_count() -> int:
	return _redraws


## How many cells the last update gave a ground colour: the player's dirty cells for a patch, every
## cell for a start or a rebuild, 0 for an update that only painted the rows.
func shaded_count() -> int:
	return _shaded


## Brings the picture up to `snap` for `player`. Returns true when it was painted anew (the
## texture has new texels), false when the snapshot called for nothing.
func update(snap: MatchSnapshot, player: int) -> bool:
	var fog: FogGrid = snap.fog
	var covered: bool = FogLayer.covers(fog, player)
	var fresh: bool = (
		snap.match_serial != _serial
		or snap.map_version != _map_version
		or player != _player
		or snap.map_cols != _cols
		or snap.map_rows != _rows
		or covered == _all_seen
	)  # The fog gained or lost its grid for the player.
	_all_seen = not covered
	_counts = fog.visible
	_explored = fog.explored
	_from = (player - 1) * fog.cells
	var version: int = fog.version_of(player) if covered else -1
	var previous: int = _tick
	_tick = snap.tick
	_shaded = 0
	if fresh:
		if not _begin(snap, player):
			return false
	elif _cols <= 0:
		return false
	elif version != _version:
		if fog.dirty_overflowed(player) or snap.tick != previous + 1:
			_shade(PackedInt32Array(range(_cols * _rows)))
		else:
			_shade(fog.dirty_cells(player))
	elif snap.tick - _drawn < period_ticks and snap.tick >= _drawn:
		return false
	_version = version
	_drawn = snap.tick
	_paint(snap, player)
	_redraws += 1
	return true


## Starts a picture for the match and player of `snap`: the palettes and the whole ground. False
## for a map with no area or no terrain, which has nothing to show.
func _begin(snap: MatchSnapshot, player: int) -> bool:
	_serial = snap.match_serial
	_map_version = snap.map_version
	_player = player
	_cols = snap.map_cols
	_rows = snap.map_rows
	if _cols <= 0 or _rows <= 0 or snap.terrain.size() < _cols * _rows:
		_cols = 0  # A map with no area or no terrain has nothing to show.
		_rows = 0
		_image = Image.new()
		_texture = null
		return false
	var keep: int = ALPHA_MAX - clampi(explored_alpha, 0, ALPHA_MAX)
	_lit.clear()
	_dim.clear()
	for id: StringName in snap.terrain_ids:
		var colour: Color = terrain_colours.get(id, MISSING)
		_add_rgb(_lit, colour, ALPHA_MAX)
		_add_rgb(_dim, colour, keep)
	_team.clear()
	for triad: Array in WorldSort.TRIADS:
		_add_rgb(_team, Color(triad[0]), ALPHA_MAX)  # LIGHT
		_add_rgb(_team, Color(triad[1]), ALPHA_MAX)  # MID
		_add_rgb(_team, Color(triad[1]), keep)  # GHOST
	_terrain = snap.terrain
	_ground.resize(_cols * _rows * BYTES_PER_TEXEL)
	_ground.fill(ALPHA_MAX)  # The colours are written below; the alpha stays.
	_shade(PackedInt32Array(range(_cols * _rows)))
	return true


## Appends the three bytes of `colour` times `share` / 255 to `into`.
@warning_ignore("integer_division")
static func _add_rgb(into: PackedByteArray, colour: Color, share: int) -> void:
	into.append(colour.r8 * share / ALPHA_MAX)
	into.append(colour.g8 * share / ALPHA_MAX)
	into.append(colour.b8 * share / ALPHA_MAX)


## Writes the ground colour of each cell of `cells` from the player's fog.
func _shade(cells: PackedInt32Array) -> void:
	_shaded = cells.size()
	var counts: PackedInt32Array = _counts
	var seen: PackedByteArray = _explored
	var terrain: PackedByteArray = _terrain
	var ground: PackedByteArray = _ground
	var lit: PackedByteArray = _lit
	var dim: PackedByteArray = _dim
	for cell: int in cells:
		var at: int = cell * BYTES_PER_TEXEL
		var kind: int = terrain[cell] * 3
		if _all_seen or counts[_from + cell] > 0:
			ground[at] = lit[kind]
			ground[at + 1] = lit[kind + 1]
			ground[at + 2] = lit[kind + 2]
		elif seen[_from + cell] != 0:
			ground[at] = dim[kind]
			ground[at + 1] = dim[kind + 1]
			ground[at + 2] = dim[kind + 2]
		else:
			ground[at] = UNEXPLORED.r8
			ground[at + 1] = UNEXPLORED.g8
			ground[at + 2] = UNEXPLORED.b8


## The ground with the memory, the buildings and the units on it, uploaded.
@warning_ignore("integer_division")
func _paint(snap: MatchSnapshot, player: int) -> void:
	_bytes = _ground.duplicate()
	var foot_w: PackedInt32Array = snap.type_foot_w
	var foot_h: PackedInt32Array = snap.type_foot_h
	var owners: PackedInt32Array = snap.owner
	var types: PackedInt32Array = snap.type_index
	var xs: PackedInt32Array = snap.pos_x
	var ys: PackedInt32Array = snap.pos_y
	_remember(snap, player)
	for row: int in owners.size():
		var w: int = foot_w[types[row]]
		if w < 1:
			continue
		var foot: Rect2i = BuildingLayer.footprint_at(xs[row], ys[row], w, foot_h[types[row]])
		if owners[row] == player or _seen_foot(foot):
			_fill(foot, owners[row], MID)
	for row: int in owners.size():
		if foot_w[types[row]] > 0:
			continue
		var cell: Rect2i = Rect2i(
			clampi(xs[row] / MILLI, 0, _cols - 1), clampi(ys[row] / MILLI, 0, _rows - 1), 1, 1
		)
		if owners[row] == player or _seen_foot(cell):
			_fill(cell, owners[row], LIGHT)
	_image.set_data(_cols, _rows, false, Image.FORMAT_RGBA8, _bytes)
	if _texture != null and _texture.get_width() == _cols and _texture.get_height() == _rows:
		_texture.update(_image)
	else:
		_texture = ImageTexture.create_from_image(_image)


## The player's last-seen records whose footprint no cell of is seen now, dimmed, as the ghosts
## are drawn (`GhostMemoryLayer`): record i of player p is entry `p * cap + i` of the four arrays.
@warning_ignore("integer_division")
func _remember(snap: MatchSnapshot, player: int) -> void:
	var counts: PackedInt32Array = snap.ghost_count
	if _all_seen or player < 1 or player >= counts.size():
		return
	var cap: int = snap.ghost_id.size() / counts.size()
	for entry: int in range(player * cap, player * cap + mini(counts[player], cap)):
		var type: int = snap.ghost_type[entry]
		if type < 0 or type >= snap.type_foot_w.size() or snap.type_foot_w[type] < 1:
			continue
		var w: int = snap.type_foot_w[type]
		var h: int = snap.type_foot_h[type]
		var x: int = (snap.ghost_cell[entry] % _cols) * MILLI + (w % 2) * HALF
		var y: int = (snap.ghost_cell[entry] / _cols) * MILLI + (h % 2) * HALF
		var foot: Rect2i = BuildingLayer.footprint_at(x, y, w, h)
		if not _seen_foot(foot):
			_fill(foot, snap.ghost_owner[entry], GHOST)


## Whether the player sees any cell of `foot` now (everything, with no fog grid for it).
func _seen_foot(foot: Rect2i) -> bool:
	return _all_seen or BuildingLayer.any_cell_seen(_counts, _from, _cols, foot)


## Writes the tone of `owner`'s team over the cells of `foot` that lie on the map.
func _fill(foot: Rect2i, owner_id: int, tone: int) -> void:
	var at: int = (clampi(owner_id - 1, 0, WorldSort.TRIADS.size() - 1) * 3 + tone) * 3
	var bytes: PackedByteArray = _bytes
	for line: int in range(maxi(foot.position.y, 0), mini(foot.end.y, _rows)):
		for col: int in range(maxi(foot.position.x, 0), mini(foot.end.x, _cols)):
			var texel: int = (line * _cols + col) * BYTES_PER_TEXEL
			bytes[texel] = _team[at]
			bytes[texel + 1] = _team[at + 1]
			bytes[texel + 2] = _team[at + 2]
