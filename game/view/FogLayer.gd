class_name FogLayer
extends Sprite2D
## The fog of war over the map (ADR 0010 section 2, ADR 0023 section 2, assets/art/STYLE.md "Fog and
## terrain"): one RGBA8 texel of black per tile, filtered linearly, so an edge is soft across one
## tile. The layer draws under `IsoProjection.cell_to_px()`, which turns each texel into a tile's
## diamond, so the soft edge runs along the diamonds. A texel's alpha is 255 on a tile the local
## player never saw, `explored_alpha` (140) on one it saw before and 0 on one it sees. The layer
## lies on the ground at z 4: over the terrain, the decals, the shadows and the rings and under
## every object (ADR 0023 section 2's table), which the scene sets. Objects need no fog of their
## own: enemy rigs, bars and projectiles are drawn only where the local player sees them (the
## static helpers below), and own units always stand on seen tiles.
##
## It reads only `runner.snapshot.fog` (ADR 0012 section 3). A new match (`match_serial`, which
## also brings another map size), another local player or explored alpha, an overflowed dirty list
## or a gap in the ticks rebuilds the whole image from `visible` and `explored`; every other change
## patches the cells in the player's dirty list, once for each published tick (`runner.ticked`, so
## no list is skipped when a frame plays several ticks), and only when `version_of(local_player)`
## has changed. `start()` publishes its tick-0 snapshot without `ticked`, and the first update of a
## player empties the list of its initial stamp, so the image is built from the grids at the start
## of a match and not from a list. The patch writes the alpha bytes of a reused array, then uploads
## it (`set_data` and `ImageTexture.update`).
##
## The satellite sweep (P235) lifts or restores the fog of the whole map in one step. When the local
## player's sweep begins, pauses or resumes (`snapshot.reveal` of the local player turning to or
## from ON), the tiles do not jump: for `life.reveal_fade_ms` (data, both
## ways alike) each texel's alpha moves from what the image showed to the new target, and the
## per-tick patches keep writing the target meanwhile. A new match, another player or explored
## alpha, or a gap in the ticks, ends a fade at once.
##
## The CPU-side image is `image()`: tests read it, never the texture, which reads back stale after
## `update()`. The static helpers are the one place that decides what a player sees, for the layers
## that hide what the fog covers (`UnitLayer`, `ProjectileLayer`, `EffectsLayer`, and the picking of
## the input lane): a snapshot with no map, or a player the fog has no grid for, has nothing to hide
## behind, so everything is seen.

const UNEXPLORED_ALPHA: int = 255
const VISIBLE_ALPHA: int = 0
const BYTES_PER_TEXEL: int = 4  ## RGBA8: the colour bytes stay 0 (black) and the alpha is the last.
const ALPHA_BYTE: int = 3

@export var runner: MatchRunner
## The alpha of a tile that was seen and is not now (STYLE.md). One value to change by eye.
@export var explored_alpha: int = 140
@export var life: LifeSettings  ## `reveal_fade_ms`; the data file when unset.

## The microsecond clock that times an update. Tests replace it.
var usec_clock: Callable = Time.get_ticks_usec
## The millisecond clock that times a fade. Tests replace it.
var msec_clock: Callable = Time.get_ticks_msec
## The frame counter that limits a fade to one blend a frame. Tests replace it.
var frame_clock: Callable = Engine.get_process_frames

var _serial: int = -1  ## match_serial of the image.
var _player: int = 0  ## The local player the image shows.
var _shade: int = -1  ## The explored alpha the image was painted with.
var _cols: int = 0
var _rows: int = 0
var _version: int = -1  ## version_of(local player) at the last update.
var _tick: int = -1  ## Tick of the last snapshot looked at.
var _bytes: PackedByteArray = PackedByteArray()  ## RGBA8 of the image, reused by every update.
var _all_cells: PackedInt32Array = PackedInt32Array()  ## 0 .. cells - 1, for a rebuild.
var _image: Image = Image.new()
var _texture: ImageTexture = null
var _uploads: int = 0
var _rebuilds: int = 0
var _update_usec: int = 0
var _on: bool = false  ## The local player's sweep was ON at the last look.
var _fading: bool = false
var _fade_from: PackedByteArray = PackedByteArray()  ## The image's bytes when the fade began.
var _goal: PackedByteArray = PackedByteArray()  ## The bytes the image is fading to.
var _fade_start_ms: int = 0
var _last_blend_frame: int = -1


func _ready() -> void:
	if life == null:
		life = load("res://data/life_settings.tres")
	centered = false
	transform = IsoProjection.cell_to_px()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if runner != null:
		runner.ticked.connect(_on_ticked)
	_sync()


## Looks again, for a match that `start()` began since the last tick: the new match's first
## snapshot comes with no `ticked`.
func _process(_delta: float) -> void:
	var uploads: int = _uploads
	_sync()
	if _fading and _uploads == uploads:  # `_sync` blended it already when it uploaded.
		var began: int = int(usec_clock.call())
		var blended: int = _uploads
		_blend()
		if _uploads != blended:
			_update_usec = int(usec_clock.call()) - began


## The local player the layers hide for: `runner.scenario.local_player`, 1 without a scenario.
static func local_player_of(source: MatchRunner) -> int:
	return source.scenario.local_player if source.scenario != null else 1


## Whether `fog` has a grid for `player` on a map: false for a snapshot with no map (a fresh
## FogGrid has no cells) and for a player the fog was not sized for.
static func covers(fog: FogGrid, player: int) -> bool:
	return fog.cells > 0 and player >= 1 and player <= fog.player_count


## Whether `player` sees the point (x, y), in milli-tiles, in `snap`: the visible count of its
## cell, which comes from `snap.cell_of` and no formula of the caller's. True when the fog does not
## cover the player. For code outside loops; a loop over rows aliases `fog.visible` itself.
static func is_seen(snap: MatchSnapshot, player: int, x: int, y: int) -> bool:
	var fog: FogGrid = snap.fog
	if not covers(fog, player):
		return true
	return fog.visible[(player - 1) * fog.cells + snap.cell_of(x, y)] > 0


## Uploads of the image so far: the first one, every patch and every rebuild.
func upload_count() -> int:
	return _uploads


## Full rebuilds so far (a patch is not one).
func rebuild_count() -> int:
	return _rebuilds


## Microseconds the last update took, a rebuild or a patch (the perf card's fog update). It keeps
## its value until the next update, so a sampler takes one reading per update, on a frame where
## `upload_count()` rose, and not one per frame.
func last_update_usec() -> int:
	return _update_usec


## The CPU-side image that is uploaded: cols x rows, the alpha of each tile in RGBA8.
func image() -> Image:
	return _image


func _on_ticked(_tick_number: int) -> void:
	_sync()


## Brings the image up to `runner.snapshot`: nothing while the local player's version is the one
## the image has, a patch of the dirty list when it changed, a rebuild when a patch cannot be
## trusted.
func _sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	var fog: FogGrid = snap.fog
	var player: int = local_player_of(runner)
	if not covers(fog, player):
		_blank()
		return
	var shade: int = clampi(explored_alpha, 0, 255)
	var version: int = fog.version_of(player)
	var other: bool = snap.match_serial != _serial or player != _player or shade != _shade
	var on: bool = player < snap.reveal.size() and snap.reveal[player] == Reveal.State.ON
	var previous_tick: int = _tick
	_tick = snap.tick
	var flipped: bool = on != _on
	_on = on  # Also when no tile changed: a later patch is no flip.
	if other:
		_fading = false
	if not other and version == _version:
		return
	if not other and flipped and snap.tick == previous_tick + 1:
		_begin_fade()  # The sweep turned on or off in this step: the flip is in the dirty list.
	elif other or snap.tick != previous_tick + 1:
		_fading = false
	var began: int = int(usec_clock.call())
	if other or fog.dirty_overflowed(player) or snap.tick != previous_tick + 1:
		_rebuild(fog, player, shade)
		_serial = snap.match_serial
		_player = player
		_shade = shade
		_rebuilds += 1
	else:
		_paint(fog, player, shade, fog.dirty_cells(player))
	_version = version
	if _fading:
		_blend()
	else:
		_upload()
	_update_usec = int(usec_clock.call()) - began


## No grid to draw: no texture, and a later grid rebuilds from nothing.
func _blank() -> void:
	_serial = -1
	_fading = false
	if _texture != null:
		texture = null
		_texture = null
		_image = Image.new()


## Paints every tile of the player's grid. The size of the image follows the fog's.
func _rebuild(fog: FogGrid, player: int, shade: int) -> void:
	if fog.cols != _cols or fog.rows != _rows:
		_cols = fog.cols
		_rows = fog.rows
		_all_cells = PackedInt32Array(range(fog.cells))
		_bytes.resize(fog.cells * BYTES_PER_TEXEL)  # New bytes are 0: black, alpha set below.
	_paint(fog, player, shade, _all_cells)


## Writes the alpha of each cell of `cells` from the player's visible counts and explored bytes.
func _paint(fog: FogGrid, player: int, shade: int, cells: PackedInt32Array) -> void:
	var base: int = (player - 1) * fog.cells
	var counts: PackedInt32Array = fog.visible
	var seen: PackedByteArray = fog.explored
	var bytes: PackedByteArray = _goal if _fading else _bytes
	for cell: int in cells:
		var alpha: int = UNEXPLORED_ALPHA
		if seen[base + cell] != 0:
			alpha = shade
		if counts[base + cell] > 0:
			alpha = VISIBLE_ALPHA
		bytes[cell * BYTES_PER_TEXEL + ALPHA_BYTE] = alpha


## Starts a fade from what the image shows now; the goal begins equal and the paints move it.
func _begin_fade() -> void:
	var ms: int = 0 if life == null else life.reveal_fade_ms
	if ms <= 0 or _bytes.is_empty():
		_fading = false
		return
	if not _fading:  # A fade already running keeps its goal, which every paint has kept current.
		_goal = _bytes.duplicate()
	_fading = true
	_fade_from = _bytes.duplicate()
	_last_blend_frame = -1
	_fade_start_ms = int(msec_clock.call())


## Writes the image between `_fade_from` and `_goal` for the time that has passed, uploads it, and
## ends the fade on the goal. The texels' alpha bytes only: the colour bytes stay 0.
func _blend() -> void:
	var ms: int = maxi(life.reveal_fade_ms, 1)
	var frame: int = int(frame_clock.call())
	if frame == _last_blend_frame:  # One blend and upload a frame.
		return
	_last_blend_frame = frame
	var now: int = int(msec_clock.call())
	var share: float = clampf(float(now - _fade_start_ms) / ms, 0.0, 1.0)
	if share >= 1.0:
		_bytes = _goal.duplicate()
		_fading = false
	else:
		var bytes: PackedByteArray = _bytes
		var from: PackedByteArray = _fade_from
		var goal: PackedByteArray = _goal
		for at: int in range(ALPHA_BYTE, bytes.size(), BYTES_PER_TEXEL):
			bytes[at] = from[at] + roundi((goal[at] - from[at]) * share)
	_upload()


## True while the image fades (tests).
func is_fading() -> bool:
	return _fading


func _upload() -> void:
	_image.set_data(_cols, _rows, false, Image.FORMAT_RGBA8, _bytes)
	if _texture != null and _texture.get_width() == _cols and _texture.get_height() == _rows:
		_texture.update(_image)
	else:
		_texture = ImageTexture.create_from_image(_image)
		texture = _texture
	_uploads += 1
