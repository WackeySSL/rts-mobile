class_name MineLayer
extends Node2D
## The mines on the ground (ADR 0037 section 8, plan P293), at absolute z 3 in the tree after
## `DecalLayer` and before `LifeFx`, so the dust, the wrecks and the rings (`GroundFx` is a child of
## `LifeFx`) draw over the marks, and under the fog (4) and every sorted object. Everything is one
## `_draw` from one small texture of its own, so the layer is one draw call (+1 on the forecast):
## - the local player's own mines, always, in its colours, at half alpha until armed;
## - the mines it has found (its records), at full strength with the notched rim while the cell is
##   seen now and dimmed like a building ghost (`GhostMemoryLayer`, `explored_alpha`) while it is
##   not; a record that goes is gone at once;
## - a blast (`MINE_BLAST`): a burst for `BURST_MS` and a scorch that stays `SCORCH_MS` and fades
##   in its last `SCORCH_FADE_MS`, both only where the local player sees the cell at the event.
## An unknown enemy mine is never drawn: the marks are read from `MatchSnapshot.mines_for(player)`
## and nothing else of the mine columns, and the radar shows no mines.
##
## The marks are the "Keep File" SVGs of `MineMarkArt`, recoloured to each player's triad with
## `IsoPlayerArt.recolour` (the art `WorldSort` baked for it), rasterised with
## `Image.load_svg_from_string` at the sorted world's bake scale and packed by `RuntimeAtlas` once
## per match, together with a burst and a scorch the layer paints itself (`_fx_image`). A mark is
## the art with its ground point (`MineMarkArt.ORIGIN_PX`) on the cell's centre.
## The plan of the marks is made when the snapshot's tick or the local player's fog version moves
## (a frame compares two integers), in packed arrays; the blasts are two rings of slots in packed
## arrays (`BURST_SLOTS`, `SCORCH_SLOTS`, the oldest is overwritten), so a match allocates no object
## per mine or per blast and a frame allocates nothing. The layer redraws only when the plan moved
## or a blast is changing.

const Z: int = 3
const OWN: int = 0  ## The kind of an own mark (`MineMarkArt.KINDS[OWN]`).
const KNOWN: int = 1  ## The kind of a found enemy mine's mark.
const KINDS_PER_OWNER: int = 2
const UNARMED_ALPHA: float = 0.5
const BURST_MS: float = 450.0
const BURST_FROM: float = 0.5  ## The burst's size at birth, of the blast's radius.
const SCORCH_MS: float = 12000.0
const SCORCH_FADE_MS: float = 4000.0
const SCORCH_SCALE: float = 0.8  ## The scorch's size, of the blast's radius.
const SCORCH_ALPHA: float = 0.85
const BURST_SLOTS: int = 12
const SCORCH_SLOTS: int = 24
const FX_PX: Vector2i = Vector2i(128, 64)  ## The painted burst and scorch, texels.
const ATLAS_WIDTH_PX: int = 512
const ALPHA_MAX: int = 255
const FREE: float = -1.0  ## A ring slot's birth when it holds nothing.

@export var runner: MatchRunner
## The sorted world whose art (faction, triad, bake scale) the marks are baked from. Without one
## the layer draws nothing.
@export var world_sort: WorldSort
## The alpha of the black over a cell the player saw and does not see now: keep it equal to
## `FogLayer.explored_alpha`.
@export var explored_alpha: int = 140
## Draws every blast and every found mine as seen (the perf arena's flag of the other layers).
@export var reveal_enemies: bool = false

var _atlas: RuntimeAtlas = null
var _texture: Texture2D = null
var _regions: Array[Rect2] = []  ## Per (owner - 1) * 2 + kind, then the burst and the scorch.
var _owners: int = 0
var _burst_region: int = 0
var _scorch_region: int = 0
var _serial: int = -1
var _tick: int = -1  ## The snapshot's tick the marks were planned for.
var _fog_version: int = -3  ## The local player's fog version they were planned for.
var _clock: float = 0.0  ## Match time, ms: the largest the frames have seen in this match.
var _animating: bool = false  ## The last frame drew a blast that is still changing.
var _dirty: bool = false  ## A blast was born since the last draw.
var _redraws: int = 0
var _draws: int = 0
## The plan of the marks, in draw order (south last): the point (world px), the region and the alpha
## of each, and whether it is dimmed.
var _marks: int = 0
var _mark_at: PackedVector2Array = PackedVector2Array()
var _mark_region: PackedInt32Array = PackedInt32Array()
var _mark_alpha: PackedFloat32Array = PackedFloat32Array()
var _mark_dim: PackedByteArray = PackedByteArray()
## The rings: the birth of each slot (match ms, FREE for none), its centre and its semi-axes (px).
var _burst_born: PackedFloat64Array = PackedFloat64Array()
var _burst_at: PackedVector2Array = PackedVector2Array()
var _burst_axes: PackedVector2Array = PackedVector2Array()
var _scorch_born: PackedFloat64Array = PackedFloat64Array()
var _scorch_at: PackedVector2Array = PackedVector2Array()
var _scorch_axes: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	z_index = Z
	z_as_relative = false
	_burst_born.resize(BURST_SLOTS)
	_burst_at.resize(BURST_SLOTS)
	_burst_axes.resize(BURST_SLOTS)
	_scorch_born.resize(SCORCH_SLOTS)
	_scorch_at.resize(SCORCH_SLOTS)
	_scorch_axes.resize(SCORCH_SLOTS)
	_burst_born.fill(FREE)
	_scorch_born.fill(FREE)


func _ready() -> void:
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or world_sort == null:
		return
	_follow_match(snap)
	var player: int = FogLayer.local_player_of(runner)
	var version: int = snap.fog.version_of(player) if FogLayer.covers(snap.fog, player) else -2
	var moved: bool = snap.tick != _tick or version != _fog_version
	if moved:
		_tick = snap.tick
		_fog_version = version
		_plan_marks(snap, player)
	_clock = maxf(_clock, LifeClock.ms(snap, runner.alpha()))
	var changing: bool = _expire()
	if moved or _dirty or changing or _animating:
		_redraws += 1
		queue_redraw()
	_animating = changing
	_dirty = false


func _draw() -> void:
	if _texture == null:
		return
	_draws += 1
	for slot: int in SCORCH_SLOTS:
		if _scorch_born[slot] != FREE:
			var age: float = LifeClock.age_ms(_clock, _scorch_born[slot])
			var left: float = clampf((SCORCH_MS - age) / SCORCH_FADE_MS, 0.0, 1.0)
			_stamp(
				_scorch_region,
				_scorch_at[slot],
				_scorch_axes[slot] * SCORCH_SCALE,
				left * SCORCH_ALPHA
			)
	var half: Vector2 = MineMarkArt.ORIGIN_PX * WorldSort.ART_SCALE
	var size: Vector2 = MineMarkArt.SIZE_PX * WorldSort.ART_SCALE
	var keep: float = dim_keep()
	for mark: int in _marks:
		var tint: Color = Color(1.0, 1.0, 1.0, _mark_alpha[mark])
		if _mark_dim[mark] == 1:
			tint = Color(keep, keep, keep, _mark_alpha[mark])
		draw_texture_rect_region(
			_texture, Rect2(_mark_at[mark] - half, size), _regions[_mark_region[mark]], tint
		)
	for slot: int in BURST_SLOTS:
		if _burst_born[slot] != FREE:
			var age: float = LifeClock.age_ms(_clock, _burst_born[slot])
			var u: float = clampf(age / BURST_MS, 0.0, 1.0)
			var grown: float = lerpf(BURST_FROM, 1.0, 1.0 - (1.0 - u) * (1.0 - u))
			_stamp(_burst_region, _burst_at[slot], _burst_axes[slot] * grown, 1.0 - u)


## Marks drawn on the plan now. No sync.
func mark_count() -> int:
	return _marks


## The ground point (world px of the layer) of mark `index` of the plan.
func mark_at(index: int) -> Vector2:
	return _mark_at[index]


## The alpha of mark `index`: `UNARMED_ALPHA` for an own mine not yet armed, else 1.
func mark_alpha(index: int) -> float:
	return _mark_alpha[index]


## Whether mark `index` is a record of a cell the player does not see now, drawn dimmed.
func mark_dimmed(index: int) -> bool:
	return _mark_dim[index] == 1


## The kind (`OWN` or `KNOWN`) and the owner of mark `index`.
func mark_kind(index: int) -> int:
	return _mark_region[index] % KINDS_PER_OWNER


@warning_ignore("integer_division")
func mark_owner(index: int) -> int:
	return _mark_region[index] / KINDS_PER_OWNER + 1


## Blasts alive: bursts and scorches in the rings.
func burst_count() -> int:
	return _live(_burst_born)


func scorch_count() -> int:
	return _live(_scorch_born)


## The centre (world px) of the `slot`th live scorch, in slot order; Vector2.INF past the last.
func scorch_at(index: int) -> Vector2:
	var seen: int = 0
	for slot: int in SCORCH_SLOTS:
		if _scorch_born[slot] != FREE:
			if seen == index:
				return _scorch_at[slot]
			seen += 1
	return Vector2.INF


## Frames drawn and redraws asked for, for the tests.
func draw_count() -> int:
	return _draws


func redraw_count() -> int:
	return _redraws


## The atlas texture the layer draws from; null before the first bake.
func texture() -> Texture2D:
	return _texture


## The region of the atlas of the mark of `kind` of `owner` (texels); an empty Rect2 for none.
func region_of(owner: int, kind: int) -> Rect2:
	var at: int = (owner - 1) * KINDS_PER_OWNER + kind
	return _regions[at] if owner >= 1 and owner <= _owners else Rect2()


## The factor the explored fog's black leaves of a colour: `1 - explored_alpha / 255`.
func dim_keep() -> float:
	return 1.0 - float(clampi(explored_alpha, 0, ALPHA_MAX)) / float(ALPHA_MAX)


## A snapshot of another match empties the layer and bakes the new match's marks.
func _follow_match(snap: MatchSnapshot) -> void:
	if snap.match_serial == _serial:
		return
	_serial = snap.match_serial
	_tick = -1
	_fog_version = -3
	_clock = 0.0
	_marks = 0
	_burst_born.fill(FREE)
	_scorch_born.fill(FREE)
	world_sort.sync()  # The art of the match, before the marks are baked from it.
	_bake()


## Rasterises each player's own and known marks and paints the burst and the scorch, and packs
## them into one image. A mark whose art cannot be read has an empty region and is not drawn.
func _bake() -> void:
	_owners = world_sort.art_count()
	var sources: Dictionary[StringName, Image] = {}
	for owner: int in range(1, _owners + 1):
		for kind: int in KINDS_PER_OWNER:
			sources[_key(owner, kind)] = _raster(world_sort.art_of(owner), MineMarkArt.KINDS[kind])
	sources[&"burst"] = _fx_image(true)
	sources[&"scorch"] = _fx_image(false)
	_atlas = RuntimeAtlas.build_images(sources, ATLAS_WIDTH_PX, false)
	_texture = _atlas.texture()
	_regions.clear()
	for owner: int in range(1, _owners + 1):
		for kind: int in KINDS_PER_OWNER:
			_regions.append(Rect2(_atlas.region(_key(owner, kind))))
	_burst_region = _regions.size()
	_regions.append(Rect2(_atlas.region(&"burst")))
	_scorch_region = _regions.size()
	_regions.append(Rect2(_atlas.region(&"scorch")))


static func _key(owner: int, kind: int) -> StringName:
	return StringName("mine_%d_%d" % [owner, kind])


## The mark of `kind` in `art`'s faction and triad, null when the art is missing or unreadable.
func _raster(art: IsoPlayerArt, kind: String) -> Image:
	if art == null:
		return null
	var text: String = MineMarkArt.text(art.faction, kind)
	if text.is_empty():
		return null
	var image: Image = Image.new()
	if image.load_svg_from_string(art.recolour(text), world_sort.bake_scale) != OK:
		return null
	return image


## The painted burst (a hot disc with a bright rim) or scorch (a dark soft disc), a 2:1 ellipse
## that fills `FX_PX`: drawn at the blast's ground ellipse by `ellipse_px`.
static func _fx_image(burst: bool) -> Image:
	var image: Image = Image.create_empty(FX_PX.x, FX_PX.y, false, Image.FORMAT_RGBA8)
	for y: int in FX_PX.y:
		for x: int in FX_PX.x:
			var dx: float = (float(x) + 0.5) / FX_PX.x * 2.0 - 1.0
			var dy: float = (float(y) + 0.5) / FX_PX.y * 2.0 - 1.0
			var r: float = sqrt(dx * dx + dy * dy)
			if r >= 1.0:
				continue
			if burst:
				var core: float = pow(1.0 - r, 1.5)
				var rim: float = exp(-pow((r - 0.85) / 0.1, 2.0))
				var hot: Color = Color(1.0, 0.55, 0.2).lerp(Color(1.0, 0.92, 0.65), core)
				hot.a = clampf(core * 0.7 + rim * 0.8, 0.0, 1.0)
				image.set_pixel(x, y, hot)
			else:
				image.set_pixel(x, y, Color(0.07, 0.05, 0.04, pow(1.0 - r, 0.6)))
	return image


## Makes the plan of the marks from the local player's mines: its own, then its records, south last.
func _plan_marks(snap: MatchSnapshot, player: int) -> void:
	_marks = 0
	if _texture == null or player < 1 or player > _owners:
		return
	var mines: Dictionary = snap.mines_for(player)
	var cols: int = snap.map_cols
	if cols < 1:
		return
	var own_cell: PackedInt32Array = mines[&"own_cell"]
	var own_armed: PackedInt32Array = mines[&"own_armed"]
	var known_cell: PackedInt32Array = mines[&"known_cell"]
	var known_owner: PackedInt32Array = mines[&"known_owner"]
	_reserve(own_cell.size() + known_cell.size())
	var own_region: int = (player - 1) * KINDS_PER_OWNER + OWN
	for index: int in own_cell.size():
		var armed: bool = own_armed[index] <= snap.tick
		_add_mark(own_cell[index], cols, own_region, 1.0 if armed else UNARMED_ALPHA, false)
	var fog: FogGrid = snap.fog
	var covered: bool = FogLayer.covers(fog, player)
	for index: int in known_cell.size():
		var owner: int = known_owner[index]
		if owner < 1 or owner > _owners:
			continue
		var cell: int = known_cell[index]
		var seen: bool = (
			reveal_enemies or not covered or fog.visible[(player - 1) * fog.cells + cell] > 0
		)
		_add_mark(cell, cols, (owner - 1) * KINDS_PER_OWNER + KNOWN, 1.0, not seen)


## Appends one mark of the cell `cell` of a map `cols` wide, in order of y (insertion), and skips a
## region the bake could not make.
@warning_ignore("integer_division")
func _add_mark(cell: int, cols: int, region: int, alpha: float, dim: bool) -> void:
	if _regions[region].size == Vector2.ZERO:
		return
	var at: Vector2 = IsoProjection.ground_to_px(
		(cell % cols) * World.MILLI_PER_TILE + World.TILE_CENTRE,
		(cell / cols) * World.MILLI_PER_TILE + World.TILE_CENTRE
	)
	var slot: int = _marks
	while slot > 0 and _mark_at[slot - 1].y > at.y:
		_mark_at[slot] = _mark_at[slot - 1]
		_mark_region[slot] = _mark_region[slot - 1]
		_mark_alpha[slot] = _mark_alpha[slot - 1]
		_mark_dim[slot] = _mark_dim[slot - 1]
		slot -= 1
	_mark_at[slot] = at
	_mark_region[slot] = region
	_mark_alpha[slot] = alpha
	_mark_dim[slot] = 1 if dim else 0
	_marks += 1


## Room for `count` marks; the arrays only grow.
func _reserve(count: int) -> void:
	if _mark_at.size() < count:
		_mark_at.resize(count)
		_mark_region.resize(count)
		_mark_alpha.resize(count)
		_mark_dim.resize(count)


## A blast per `MINE_BLAST` record of the tick, where the local player sees the cell.
func _on_ticked(_tick_no: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or world_sort == null:
		return
	_follow_match(snap)
	var player: int = FogLayer.local_player_of(runner)
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.MINE_BLAST:
			_add_blast(snap, at, player)


## The record at `at`: `[MINE_BLAST, mine id, x, y, weapon, owner, 0, 0]`. A blast on a cell the
## player does not see leaves nothing, and neither does a weapon with no blast radius.
func _add_blast(snap: MatchSnapshot, at: int, player: int) -> void:
	var events: PackedInt32Array = snap.events
	var weapon: int = events[at + 4]
	var radius: int = (
		snap.weapon_blast_milli[weapon]
		if weapon >= 0 and weapon < snap.weapon_blast_milli.size()
		else 0
	)
	if _texture == null or radius < 1:
		return
	if not (reveal_enemies or FogLayer.is_seen(snap, player, events[at + 2], events[at + 3])):
		return
	var born: float = LifeClock.tick_ms(snap.tick)
	var point: Vector2 = IsoProjection.ground_to_px(events[at + 2], events[at + 3])
	var axes: Vector2 = IsoProjection.ellipse_px(radius)
	var burst: int = _take(_burst_born)
	_burst_born[burst] = born
	_burst_at[burst] = point
	_burst_axes[burst] = axes
	var scorch: int = _take(_scorch_born)
	_scorch_born[scorch] = born
	_scorch_at[scorch] = point
	_scorch_axes[scorch] = axes
	_dirty = true


## The first free slot of a ring, else the oldest.
static func _take(born: PackedFloat64Array) -> int:
	var oldest: int = 0
	for slot: int in born.size():
		if born[slot] == FREE:
			return slot
		if born[slot] < born[oldest]:
			oldest = slot
	return oldest


## Frees the slots that ran out at the clock; true while a blast is still changing on screen (a
## burst, or a scorch in its fade). A scorch before its fade is as still as a mark.
func _expire() -> bool:
	var changing: bool = false
	for slot: int in BURST_SLOTS:
		if _burst_born[slot] == FREE:
			continue
		if LifeClock.age_ms(_clock, _burst_born[slot]) >= BURST_MS:
			_burst_born[slot] = FREE
			changing = true  # One more draw, without it.
		else:
			changing = true
	for slot: int in SCORCH_SLOTS:
		if _scorch_born[slot] == FREE:
			continue
		var age: float = LifeClock.age_ms(_clock, _scorch_born[slot])
		if age >= SCORCH_MS:
			_scorch_born[slot] = FREE
			changing = true
		elif age >= SCORCH_MS - SCORCH_FADE_MS:
			changing = true
	return changing


static func _live(born: PackedFloat64Array) -> int:
	var live: int = 0
	for slot: int in born.size():
		live += 1 if born[slot] != FREE else 0
	return live


## One quad of `region` centred on `at`, `axes` the semi-axes of the ground ellipse it covers.
func _stamp(region: int, at: Vector2, axes: Vector2, alpha: float) -> void:
	if alpha <= 0.0 or _regions[region].size == Vector2.ZERO:
		return
	draw_texture_rect_region(
		_texture, Rect2(at - axes, axes * 2.0), _regions[region], Color(1.0, 1.0, 1.0, alpha)
	)
