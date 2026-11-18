class_name MineLayer
extends Node2D
## The mines on the ground (ADR 0037 section 8, plan P293), at absolute z 3 in the tree after
## `DecalLayer` and before `LifeFx`, so the dust, the wrecks and the rings (`GroundFx` is a child of
## `LifeFx`) draw over the marks, and under the fog (4) and every sorted object. Everything is one
## `_draw` from one small texture of its own, so the layer is one draw call (+1 on the forecast):
## - the local player's own mines, always, in its colours, at half alpha until armed;
## - the mines it has found (its records), at full strength with the notched rim. The fog layer
##   above darkens a cell the player does not see now, so a record there is as dim as the ground
##   (and as a building ghost) without a tint of its own; a record that goes is gone at once;
## - the scorch of a blast (`MINE_BLAST`): it stays `SCORCH_MS` and fades in its last
##   `SCORCH_FADE_MS`, only where the local player sees the cell at the event. The burst is
##   `EffectsLayer`'s (z 50), so it draws over the vehicle that set the mine off.
## An unknown enemy mine is never drawn: the marks are read from `MatchSnapshot.mines_for(player)`
## and nothing else of the mine columns, and the radar shows no mines.
##
## The marks are the "Keep File" SVGs of `MineMarkArt`, recoloured to the player's triad with
## `IsoPlayerArt.recolour` (the art `WorldSort` baked), rasterised with `Image.load_svg_from_string`
## at the sorted world's bake scale and packed by `RuntimeAtlas` once per match with the crater art
## of `DecalLayer`, which the scorch is. Only the local player's own mark and the others' known
## marks are baked. A mark is the art with its ground point (`MineMarkArt.ORIGIN_PX`) on the cell's
## centre.
## The plan of the marks is made from `mines_for` on each new tick (and for a new player or match),
## in packed arrays, and compared with the drawn one by value: the layer redraws only when a mark, a
## region or an alpha differs (an own mine arming is an alpha) or a scorch is born or fading. The
## scorches are a ring of `SCORCH_SLOTS` slots,
## the oldest overwritten, so a match makes no object per mine or per blast. The layer redraws only
## when the plan moved or a scorch is fading.

const Z: int = 3
const OWN: int = 0  ## The kind of an own mark (`MineMarkArt.KINDS[OWN]`).
const KNOWN: int = 1  ## The kind of a found enemy mine's mark.
const KINDS_PER_OWNER: int = 2
const UNARMED_ALPHA: float = 0.5
const SCORCH_MS: float = 12000.0
const SCORCH_FADE_MS: float = 4000.0
const SCORCH_SCALE: float = 0.8  ## The scorch's size, of the blast's radius.
const SCORCH_ALPHA: float = 0.85
const SCORCH_SLOTS: int = 24
const ATLAS_WIDTH_PX: int = 512
const FREE: float = -1.0  ## A ring slot's birth when it holds nothing.

@export var runner: MatchRunner
## The sorted world whose art (faction, triad, bake scale) the marks are baked from. Without one
## the layer draws nothing.
@export var world_sort: WorldSort

var bake_ms: float = 0.0  ## What the last bake took, for the card and the tests.

var _atlas: RuntimeAtlas = null
var _texture: Texture2D = null
var _regions: Array[Rect2] = []  ## Per (owner - 1) * 2 + kind, then the scorch.
var _owners: int = 0
var _scorch_region: int = -1
var _serial: int = -1
var _tick: int = -1  ## The snapshot's tick the marks were planned for.
var _player: int = -1  ## The local player they were planned for.
var _clock: float = 0.0  ## Match time, ms: the largest the frames have seen in this match.
var _fading: bool = false  ## The last frame had a scorch in its fade.
var _dirty: bool = false  ## A blast was born since the last draw.
var _redraws: int = 0
var _draws: int = 0
## The plan of the marks, in draw order (south last): the point (world px) and the region of each,
## and its alpha.
var _marks: int = 0
var _mark_at: PackedVector2Array = PackedVector2Array()
var _mark_region: PackedInt32Array = PackedInt32Array()
var _mark_alpha: PackedFloat32Array = PackedFloat32Array()
## The plan being made (swapped with the drawn one when it differs, so a tick allocates no plan).
var _next_marks: int = 0
var _next_at: PackedVector2Array = PackedVector2Array()
var _next_region: PackedInt32Array = PackedInt32Array()
var _next_alpha: PackedFloat32Array = PackedFloat32Array()
## The scorch ring: the birth of each slot (match ms, FREE for none), its centre and its size, as
## a factor of the crater art.
var _scorch_born: PackedFloat64Array = PackedFloat64Array()
var _scorch_at: PackedVector2Array = PackedVector2Array()
var _scorch_size: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	z_index = Z
	z_as_relative = false
	_scorch_born.resize(SCORCH_SLOTS)
	_scorch_at.resize(SCORCH_SLOTS)
	_scorch_size.resize(SCORCH_SLOTS)
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
	var moved: bool = false
	if snap.tick != _tick or player != _player:
		_tick = snap.tick
		_player = player
		moved = _plan_marks(snap, player)  # True when the marks differ from the drawn ones.
	_clock = maxf(_clock, LifeClock.ms(snap, runner.alpha()))
	var fading: bool = _expire()
	if moved or _dirty or fading or _fading:
		_redraws += 1
		queue_redraw()
	_fading = fading
	_dirty = false


func _draw() -> void:
	if _texture == null:
		return
	_draws += 1
	for slot: int in SCORCH_SLOTS:
		if _scorch_born[slot] != FREE:
			var scorch: Vector2 = scorch_size(slot)
			draw_texture_rect_region(
				_texture,
				Rect2(_scorch_at[slot] - scorch * 0.5, scorch),
				_regions[_scorch_region],
				Color(1.0, 1.0, 1.0, scorch_alpha(slot))
			)
	var ground_origin: Vector2 = MineMarkArt.ORIGIN_PX * WorldSort.ART_SCALE
	var size: Vector2 = MineMarkArt.SIZE_PX * WorldSort.ART_SCALE
	for mark: int in _marks:
		draw_texture_rect_region(
			_texture,
			Rect2(_mark_at[mark] - ground_origin, size),
			_regions[_mark_region[mark]],
			Color(1.0, 1.0, 1.0, _mark_alpha[mark])
		)


## Marks on the plan now. No sync.
func mark_count() -> int:
	return _marks


## The ground point (world px of the layer) of mark `index` of the plan.
func mark_at(index: int) -> Vector2:
	return _mark_at[index]


## The alpha of mark `index`: `UNARMED_ALPHA` for an own mine not yet armed, else 1.
func mark_alpha(index: int) -> float:
	return _mark_alpha[index]


## The region of mark `index`: `(owner - 1) * KINDS_PER_OWNER + kind`.
func mark_region(index: int) -> int:
	return _mark_region[index]


## Scorches in the ring.
func scorch_count() -> int:
	var live: int = 0
	for slot: int in SCORCH_SLOTS:
		live += 1 if _scorch_born[slot] != FREE else 0
	return live


## The centre (world px) of the scorch in ring slot `slot`; Vector2.INF for a free slot.
func scorch_at(slot: int) -> Vector2:
	return _scorch_at[slot] if _scorch_born[slot] != FREE else Vector2.INF


## The alpha the scorch in ring slot `slot` is drawn with at the clock: `SCORCH_ALPHA`, falling to
## 0 over its last `SCORCH_FADE_MS`.
func scorch_alpha(slot: int) -> float:
	var age: float = LifeClock.age_ms(_clock, _scorch_born[slot])
	return clampf((SCORCH_MS - age) / SCORCH_FADE_MS, 0.0, 1.0) * SCORCH_ALPHA


## The size (world px) the scorch in ring slot `slot` is drawn at: the crater art scaled to
## `SCORCH_SCALE` of the blast's radius.
func scorch_size(slot: int) -> Vector2:
	return _regions[_scorch_region].size * _scorch_size[slot]


## The size of the scorch's art in the atlas, texels.
func scorch_art_size() -> Vector2:
	return _regions[_scorch_region].size


## Frames drawn and redraws asked for, for the tests.
func draw_count() -> int:
	return _draws


func redraw_count() -> int:
	return _redraws


## The atlas texture the layer draws from; null before the first bake.
func texture() -> Texture2D:
	return _texture


## The region of the atlas of the mark of `kind` of `owner` (texels); an empty Rect2 when it was
## not baked (the local player's known marks and the others' own).
func region_of(owner: int, kind: int) -> Rect2:
	if owner < 1 or owner > _owners:
		return Rect2()
	return _regions[(owner - 1) * KINDS_PER_OWNER + kind]


## A snapshot of another match empties the layer and bakes the new match's marks.
func _follow_match(snap: MatchSnapshot) -> void:
	if snap.match_serial == _serial:
		return
	_serial = snap.match_serial
	_tick = -1
	_clock = 0.0
	_marks = 0
	_scorch_born.fill(FREE)
	world_sort.sync()  # The art of the match, before the marks are baked from it.
	_bake(FogLayer.local_player_of(runner))


## Rasterises the local player's own mark and the others' known marks, takes the crater art for the
## scorch, and packs them into one image. A mark whose art cannot be read has an empty region.
func _bake(local: int) -> void:
	var started: int = Time.get_ticks_usec()
	_owners = world_sort.art_count()
	var sources: Dictionary[StringName, Image] = {}
	for owner: int in range(1, _owners + 1):
		var kind: int = OWN if owner == local else KNOWN
		sources[_key(owner, kind)] = _raster(world_sort.art_of(owner), MineMarkArt.KINDS[kind])
	var crater: Texture2D = DecalLayer.crater_art()
	sources[&"scorch"] = crater.get_image() if crater != null else null
	_atlas = RuntimeAtlas.build_images(sources, ATLAS_WIDTH_PX, false)
	_texture = _atlas.texture()
	_regions.clear()
	for owner: int in range(1, _owners + 1):
		for kind: int in KINDS_PER_OWNER:
			_regions.append(Rect2(_atlas.region(_key(owner, kind))))
	_scorch_region = _regions.size()
	_regions.append(Rect2(_atlas.region(&"scorch")))
	bake_ms = float(Time.get_ticks_usec() - started) / 1000.0


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


## Makes the plan of the marks from the local player's mines: its own, then its records, south last.
func _plan_marks(snap: MatchSnapshot, player: int) -> bool:
	_next_marks = 0
	if _texture != null and player >= 1 and player <= _owners and snap.map_cols >= 1:
		_collect(snap, player)
	var same: bool = _next_marks == _marks
	for index: int in _next_marks if same else 0:
		same = (
			same
			and _next_at[index] == _mark_at[index]
			and _next_region[index] == _mark_region[index]
			and _next_alpha[index] == _mark_alpha[index]
		)
	if not same:  # The new plan is the drawn one; the old arrays are next time's scratch.
		var at: PackedVector2Array = _mark_at
		var region: PackedInt32Array = _mark_region
		var alpha: PackedFloat32Array = _mark_alpha
		_mark_at = _next_at
		_mark_region = _next_region
		_mark_alpha = _next_alpha
		_next_at = at
		_next_region = region
		_next_alpha = alpha
		_marks = _next_marks
	return not same


## Collects the marks of `player`'s own mines and records into the scratch plan.
func _collect(snap: MatchSnapshot, player: int) -> void:
	var mines: Dictionary = snap.mines_for(player)
	var own_cell: PackedInt32Array = mines[&"own_cell"]
	var own_armed: PackedInt32Array = mines[&"own_armed"]
	var known_cell: PackedInt32Array = mines[&"known_cell"]
	var known_owner: PackedInt32Array = mines[&"known_owner"]
	var count: int = own_cell.size() + known_cell.size()
	if _next_at.size() < count:
		_next_at.resize(count)
		_next_region.resize(count)
		_next_alpha.resize(count)
	var own_region: int = (player - 1) * KINDS_PER_OWNER + OWN
	for index: int in own_cell.size():
		var alpha: float = 1.0 if own_armed[index] <= snap.tick else UNARMED_ALPHA
		_add_mark(own_cell[index], snap.map_cols, own_region, alpha)
	for index: int in known_cell.size():
		var owner: int = known_owner[index]
		if owner >= 1 and owner <= _owners and owner != player:
			var region: int = (owner - 1) * KINDS_PER_OWNER + KNOWN
			_add_mark(known_cell[index], snap.map_cols, region, 1.0)


## Appends one mark of the cell `cell` of a map `cols` wide, in order of y (insertion), and skips a
## region the bake could not make.
@warning_ignore("integer_division")
func _add_mark(cell: int, cols: int, region: int, alpha: float) -> void:
	if _regions[region].size == Vector2.ZERO:
		return
	var at: Vector2 = IsoProjection.ground_to_px(
		(cell % cols) * World.MILLI_PER_TILE + World.TILE_CENTRE,
		(cell / cols) * World.MILLI_PER_TILE + World.TILE_CENTRE
	)
	var slot: int = _next_marks
	while slot > 0 and _next_at[slot - 1].y > at.y:
		_next_at[slot] = _next_at[slot - 1]
		_next_region[slot] = _next_region[slot - 1]
		_next_alpha[slot] = _next_alpha[slot - 1]
		slot -= 1
	_next_at[slot] = at
	_next_region[slot] = region
	_next_alpha[slot] = alpha
	_next_marks += 1


## A scorch per `MINE_BLAST` record of the tick, where the local player sees the cell.
func _on_ticked(_tick_no: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or world_sort == null:
		return
	_follow_match(snap)
	var player: int = FogLayer.local_player_of(runner)
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.MINE_BLAST:
			_add_scorch(snap, at, player)


## Whether this tick's events hold a DIED record of a unit of `player` within `radius` milli-tiles
## of (x, y): the blast that killed it was seen, though the unit's sight went with it in the same
## tick (`Removal`), the rule of an own death in `EffectsLayer` and of `StrikeLandings.was_seen`.
## `EffectsLayer`'s burst asks it too.
static func own_unit_died_in(snap: MatchSnapshot, x: int, y: int, radius: int, player: int) -> bool:
	var events: PackedInt32Array = snap.events
	var reach: int = radius * radius
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED and events[at + 5] == player:
			var dx: int = events[at + 2] - x
			var dy: int = events[at + 3] - y
			if dx * dx + dy * dy <= reach:
				return true
	return false


## The record at `at`: `[MINE_BLAST, mine id, x, y, weapon, owner, 0, 0]`. A blast on a cell the
## player does not see leaves nothing, and neither does a weapon with no blast radius.
func _add_scorch(snap: MatchSnapshot, at: int, player: int) -> void:
	var events: PackedInt32Array = snap.events
	var weapon: int = events[at + 4]
	var blast: PackedInt32Array = snap.weapon_blast_milli
	var radius: int = blast[weapon] if weapon >= 0 and weapon < blast.size() else 0
	if _scorch_region < 0 or radius < 1 or _regions[_scorch_region].size == Vector2.ZERO:
		return
	var seen: bool = FogLayer.is_seen(snap, player, events[at + 2], events[at + 3])
	if not (seen or own_unit_died_in(snap, events[at + 2], events[at + 3], radius, player)):
		return
	var slot: int = 0  # The first free slot, else the oldest.
	for index: int in SCORCH_SLOTS:
		if _scorch_born[index] == FREE:
			slot = index
			break
		if _scorch_born[index] < _scorch_born[slot]:
			slot = index
	_scorch_born[slot] = LifeClock.tick_ms(snap.tick)
	_scorch_at[slot] = IsoProjection.ground_to_px(events[at + 2], events[at + 3])
	_scorch_size[slot] = SCORCH_SCALE * float(radius) / DecalLayer.CRATER_ART_RADIUS_MILLI
	_dirty = true


## Frees the scorches that ran out at the clock; true while one is fading (a scorch before its
## fade is as still as a mark).
func _expire() -> bool:
	var fading: bool = false
	for slot: int in SCORCH_SLOTS:
		if _scorch_born[slot] == FREE:
			continue
		var age: float = LifeClock.age_ms(_clock, _scorch_born[slot])
		if age >= SCORCH_MS:
			_scorch_born[slot] = FREE
			fading = true  # One more draw, without it.
		elif age >= SCORCH_MS - SCORCH_FADE_MS:
			fading = true
	return fading
