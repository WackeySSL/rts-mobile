class_name GhostMemoryLayer
extends Node2D
## The enemy buildings the local player has seen and cannot see now (ADR 0023 sections 2 and 3,
## ADR 0010 section 2, plan P115c; P84c's acceptance), drawn at z 5: over the fog on the ground (4),
## under every live object (`WorldSort`, 10), so a unit that walks over a remembered building is
## drawn in front of it. A ghost is the building's body, the same atlas region as the live one,
## in the colour of its owner's side, and the whole layer carries one dim colour (`modulate`, the
## black of the explored fog over the sprite: `1 - explored_alpha / 255` on each channel), so the
## ghosts are one draw call however many there are and no sprite is tinted of its own. A ghost has
## no health bar, no ring and no pick shape: it is a sprite and nothing else, not a row, so the
## bars (`HealthBarLayer`) and the pickers, which walk the snapshot's rows, never meet it.
##
## What is drawn is the local player's block of the snapshot's ghost arrays (never `PlayerView`):
## record i of player p is entry `p * ghost_cap + i` of `ghost_id`, `ghost_type`, `ghost_owner` and
## `ghost_cell`, live below `ghost_count[p]`. `ghost_cap` is not in the snapshot yet, so it is
## `ghost_id.size() / ghost_count.size()`. `ghost_cell` is the tile that holds the footprint centre,
## so the building stands at x = `(cell % cols) * 1000 + (foot_w % 2) * 500` and y =
## `(cell / cols) * 1000 + (foot_h % 2) * 500`, milli-tiles. The sim lists a building it sees now as
## well, so a record is drawn only where no cell of its footprint is seen, the rule that draws a
## live enemy building (`BuildingLayer.any_cell_seen`): at every moment exactly one of the live
## building and its ghost is drawn. A record is made on a tile the player saw, so the ground under
## it is explored. A type with no art on the atlas is not drawn (the live building shows a flat
## diamond then; a ghost has no stand-in).
##
## The sim's memory (`LastSeen`, plan row P77b) follows the same any-cell rule: it makes a record
## when any cell of the footprint is seen, drops it when any cell is seen and the building is gone,
## and drops it as the building falls when the player sees any cell then. So a building seen only
## at its edge has a record to draw, and a glimpse of one cell of a spot that is empty ends the
## record instead of hiding the ghost for as long as the glimpse lasts. A building that falls in
## sight leaves no record, so no ghost stands on its crater. This layer needs no change for it.
##
## Sorting: the layer is flat in z (one z, 5) and `y_sort_enabled`, as `WorldSort` is, so the
## engine orders its sprites by their y, the footprint centre's projected point, which is the sort
## key of the live buildings: two remembered buildings overlap as the live ones do, the one further
## south in front. Without it the order would be the sim's record order, and a tall building behind
## another would be drawn over it.
##
## The sprites are a pool, grown to the most ghosts there have been at once and never freed in a
## match; the layer redraws (`redraw_count`) when the match, the local player's fog version or
## its number of records moves, and a frame compares three integers and nothing else. That is
## enough: a record changes only on a tile the player sees, where its ghost is not drawn, and what
## the player sees changes only with the fog version.

const Z_GHOSTS: int = 5
const PART: StringName = BuildingLayer.BODY  ## The sheet part a ghost draws: a building's body.
const ALPHA_MAX: int = 255

@export var runner: MatchRunner
## The sorted world whose atlas the ghosts draw from, shared with the layers of the live buildings.
## Without one the layer draws nothing.
@export var world_sort: WorldSort
## The alpha of the black that covers a tile the player saw and does not see now: keep it equal to
## `FogLayer.explored_alpha`, so a remembered building is as dark as the ground it stands on.
## Read when the layer enters the tree.
@export var explored_alpha: int = 140
## Draws no ghosts: every enemy building is drawn live, as in the perf arena.
@export var reveal_enemies: bool = false

var _sprites: Array[Sprite2D] = []  ## The pool, in draw slots; the first `_ids.size()` are shown.
var _ids: PackedInt32Array = PackedInt32Array()  ## The building id of each shown ghost, by slot.
var _serial: int = -1  ## match_serial last drawn for.
var _fog_version: int = -3  ## The local player's fog version it was drawn for (-2: no fog for it).
var _remembered: int = -1  ## The local player's record count it was drawn for.
var _redraws: int = 0


func _init() -> void:
	z_index = Z_GHOSTS
	z_as_relative = false
	y_sort_enabled = true


func _ready() -> void:
	modulate = dim_colour()
	_sync()


func _process(_delta: float) -> void:
	_sync()


## The one colour the layer is multiplied by: black at `explored_alpha` over a pixel is the pixel
## times `1 - explored_alpha / 255`.
func dim_colour() -> Color:
	var keep: float = 1.0 - float(clampi(explored_alpha, 0, ALPHA_MAX)) / float(ALPHA_MAX)
	return Color(keep, keep, keep, 1.0)


## How many ghosts are drawn now. No sync.
func ghost_count() -> int:
	return _ids.size()


## The building ids of the ghosts drawn now, in draw slots. No sync.
func ghost_ids() -> PackedInt32Array:
	return _ids.duplicate()


## The sprite of the ghost of building `id`, null when none is drawn for it. No sync.
func ghost(id: int) -> Sprite2D:
	var slot: int = _ids.find(id)
	return _sprites[slot] if slot >= 0 else null


## How many times the layer drew its ghosts anew; it moves only with the match, the local player's
## fog version and its number of records.
func redraw_count() -> int:
	return _redraws


## Reads `runner.snapshot` afresh when the match, the local player's fog version or its record
## count differs from what the ghosts were drawn for.
func _sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or world_sort == null:
		return
	world_sort.sync()  # The atlas of the match, before any sprite is dressed from it.
	var player: int = FogLayer.local_player_of(runner)
	var version: int = snap.fog.version_of(player) if FogLayer.covers(snap.fog, player) else -2
	var counts: PackedInt32Array = snap.ghost_count
	var remembered: int = counts[player] if player >= 0 and player < counts.size() else 0
	if snap.match_serial == _serial and version == _fog_version and remembered == _remembered:
		return
	_serial = snap.match_serial
	_fog_version = version
	_remembered = remembered
	_redraws += 1
	_ids.clear()
	var drawn: int = 0 if reveal_enemies else _place(snap, player)
	for slot: int in range(drawn, _sprites.size()):
		_sprites[slot].visible = false


## Dresses a sprite for each record of `player` that no cell of its footprint is seen for, in the
## record order, and returns how many. The snapshot's record arrays, its type tables and the fog's
## visible counts are read into locals once, before the loop, and a record's footprint is looked up
## in those counts (`BuildingLayer.any_cell_seen`), so the loop reads no property of the snapshot or
## the fog. A fog that does not cover the player draws no ghost: it hides nothing
## (`BuildingLayer.footprint_seen` sees everything then).
@warning_ignore("integer_division")
func _place(snap: MatchSnapshot, player: int) -> int:
	var counts: PackedInt32Array = snap.ghost_count
	var fog: FogGrid = snap.fog
	var cols: int = fog.cols
	if cols < 1 or player < 1 or player >= counts.size() or not FogLayer.covers(fog, player):
		return 0
	var visible: PackedInt32Array = fog.visible
	var base: int = (player - 1) * fog.cells
	var type_ids: Array[StringName] = snap.type_ids
	var ids: PackedInt32Array = snap.ghost_id
	var cap: int = ids.size() / counts.size()
	var types: PackedInt32Array = snap.ghost_type
	var owners: PackedInt32Array = snap.ghost_owner
	var cells: PackedInt32Array = snap.ghost_cell
	var foot_w: PackedInt32Array = snap.type_foot_w
	var foot_h: PackedInt32Array = snap.type_foot_h
	var first: int = player * cap
	var drawn: int = 0
	for entry: int in range(first, first + mini(counts[player], cap)):
		var type: int = types[entry]
		if type < 0 or type >= foot_w.size() or foot_w[type] < 1:
			continue
		var w: int = foot_w[type]
		var h: int = foot_h[type]
		var x: int = (cells[entry] % cols) * World.MILLI_PER_TILE + (w % 2) * World.TILE_CENTRE
		var y: int = (cells[entry] / cols) * World.MILLI_PER_TILE + (h % 2) * World.TILE_CENTRE
		if BuildingLayer.any_cell_seen(visible, base, cols, BuildingLayer.footprint_at(x, y, w, h)):
			continue
		var sheet: IsoSheetDef = world_sort.sheet(type_ids[type])
		if sheet == null:
			continue
		var sprite: Sprite2D = _slot(drawn)
		sprite.position = IsoProjection.ground_to_px(x, y)
		world_sort.dress(sprite, sheet, PART)
		world_sort.show_frame(sprite, sheet, PART, BuildingLayer.NO_FRAME, owners[entry])
		if sprite.visible:  # A frame the owner's faction has not hides it, and its slot is reused.
			_ids.append(ids[entry])
			drawn += 1
	return drawn


## The sprite in draw slot `slot`, made when the pool is one short of it.
func _slot(slot: int) -> Sprite2D:
	if slot == _sprites.size():
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "Ghost%d" % slot
		_sprites.append(sprite)
		add_child(sprite)
	return _sprites[slot]
