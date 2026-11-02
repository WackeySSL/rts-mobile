class_name IsoAtlas
extends RefCounted
## The per-match atlas of the sorted world (ADR 0023 sections 2 and 5, plan P113): the frames of
## every player's faction, recoloured to the player's triad (`IsoPlayerArt.recolour`), rasterised
## with `Image.load_svg_from_string` and packed by `RuntimeAtlas` into one page (`texture()`), so
## every sorted sprite batches into one call. `build` is for the main thread at match start.
## The page is 4096 px wide and at most 4096 tall, cells packed tallest first. The bake scale is
## the largest `bake_scale * SCALE_STEP ^ k` (k = 0, 1, 2, ...), not below MIN_SCALE, whose page
## fits; a texel is a px of the 2x art times it, so a sprite draws its region at `0.5 /
## bake_scale()`. When none fits, or there is no frame, the atlas is empty and the caller decides.
## A frame no key colour touches (a shadow) is baked once and shared by the players of a faction.
## The CPU page is dropped after the upload unless `keep_image` is set (tests read it).
## The frame axis (ADR 0027 section 4): a part may have several frames per direction
## (`IsoSheetDef.frame_count`), each its own file and slot. The regions of all frames lie in one
## packed table, a group of `frame_count` entries per (player, art id, part, direction), frame 0
## first. `base` finds a group's first index with one key built from strings, which a caller asks
## when a sprite is dressed or turns; a frame change after it is `frame_region(base, frame)`, a
## table read that builds no string (`keys_built` is the test hook that proves it), and
## `frame_count_at(base)` is the group's own length, for a caller that wraps its frames.

const PAGE_MAX_PX: int = 4096
const SCALE_STEP: float = 0.875  ## A step of 7/8 keeps scale times a canvas exact in a float.
const MIN_SCALE: float = 0.25

static var _keys_built: int = 0

var _atlas: RuntimeAtlas = RuntimeAtlas.new()
var _index: Dictionary[StringName, int] = {}  ## Frame group key -> its base in `_table`.
var _table: Array[Rect2i] = []  ## One region per baked frame, a group's frames side by side.
var _spans: PackedInt32Array = PackedInt32Array()  ## Parallel to `_table`: frames at a base.
var _scale: float = 0.0
var _bake_usec: int = 0


## Every sheet of `res://assets/art/iso/index.tres`, as P99b wrote them; empty, with an error,
## when the index is not there.
static func load_sheets() -> Array[IsoSheetDef]:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	if index == null:
		push_error("IsoAtlas: no sheet index at %s" % IsoIndex.PATH)
		return []
	return index.sheets.duplicate()


## The atlas of `players` (index = player slot, see `region`) over `sheets`, requesting
## `bake_scale`. `reader` (path -> SVG text) replaces the file read; tests craft frames with it.
static func build(
	sheets: Array[IsoSheetDef],
	players: Array[IsoPlayerArt],
	bake_scale: float,
	keep_image: bool = false,
	reader: Callable = Callable()
) -> IsoAtlas:
	var started: int = Time.get_ticks_usec()
	var atlas: IsoAtlas = IsoAtlas.new()
	var plan: Plan = _collect(sheets, players, reader if reader.is_valid() else _read_text)
	var order: Array[StringName] = _packing_order(plan)
	var scale: float = fit_scale(_canvases(plan, order), bake_scale)
	if scale > 0.0 and not order.is_empty():
		atlas._bake(plan, order, scale, keep_image)
	atlas._bake_usec = Time.get_ticks_usec() - started
	return atlas


## The page a bake of `sheets` for `players` takes at `scale` itself (no scale is lowered), found
## from the frame files alone: nothing is rasterised. `tests/view/test_iso_atlas_budget.gd` pins
## the page budget of ADR 0027 section 4 with it.
static func planned_page(
	sheets: Array[IsoSheetDef],
	players: Array[IsoPlayerArt],
	scale: float,
	reader: Callable = Callable()
) -> Vector2i:
	var plan: Plan = _collect(sheets, players, reader if reader.is_valid() else _read_text)
	return page_size(_canvases(plan, _packing_order(plan)), scale)


## The size in texels the engine rasterises a canvas of `canvas` px (2x art) to at `scale`.
static func raster_size(canvas: Vector2i, scale: float) -> Vector2i:
	return Vector2i(maxi(1, roundi(canvas.x * scale)), maxi(1, roundi(canvas.y * scale)))


## The page `canvases` (2x art px, in packing order) take at `scale`, gutters included.
static func page_size(canvases: Array[Vector2i], scale: float) -> Vector2i:
	var cells: Array[Vector2i] = []
	for canvas: Vector2i in canvases:
		cells.append(RuntimeAtlas.cell_size(raster_size(canvas, scale)))
	var places: Array[Vector2i] = []
	return RuntimeAtlas.layout(cells, PAGE_MAX_PX, places)


## The scale a bake of `canvases` gets when `requested`: see the class comment. 0.0 when none.
static func fit_scale(canvases: Array[Vector2i], requested: float) -> float:
	var scale: float = requested
	while scale >= MIN_SCALE:
		var page: Vector2i = page_size(canvases, scale)
		if page.x <= PAGE_MAX_PX and page.y <= PAGE_MAX_PX:
			return scale
		scale *= SCALE_STEP
	return 0.0


## The region of frame `frame` of a part, in texels of `texture()`: `dir` is the frame's `d<NN>`
## number as `IsoSheetDef.directions()` lists it (-1 for a building's body or `anim`), `player` the
## index of the player in the array given to `build`. An empty Rect2i for a frame the player's
## faction lacks and for a `frame` the part does not have. Builds a key: not for a frame change.
func region(
	art_id: StringName, part: StringName, dir: int, player: int = 0, frame: int = 0
) -> Rect2i:
	return frame_region(base(art_id, part, dir, player), frame)


## The index of frame 0 of (`art_id`, `part`, `dir`) for `player` in the region table, -1 for a
## frame the player's faction lacks. Builds one key, so a caller asks when a sprite is dressed or
## its direction changes and keeps the number. A base belongs to the atlas it came from: a new
## bake (`WorldSort.sync`) makes a new atlas, so a caller asks again when it dresses its sprites.
func base(art_id: StringName, part: StringName, dir: int, player: int = 0) -> int:
	return _index.get(_key(player, art_id, part, dir), -1)


## How many frames the group at `base_index` has: what a caller wraps its frame number by. 0 for
## no base (-1) and for an index that is no base.
func frame_count_at(base_index: int) -> int:
	return _spans[base_index] if base_index >= 0 and base_index < _spans.size() else 0


## The region of frame `frame` of the group at `base_index` (see `base`): one table read, no
## string. An empty Rect2i for no base (-1) and for a frame the group does not have.
func frame_region(base_index: int, frame: int) -> Rect2i:
	if frame < 0 or frame >= frame_count_at(base_index):
		return Rect2i()
	return _table[base_index + frame]


## The one page every region lies on; null for an empty atlas.
func texture() -> ImageTexture:
	return _atlas.texture()


## The CPU-side page, for tests: empty unless `build` got `keep_image`.
func image() -> Image:
	return _atlas.image()


## The scale the match got, 0.0 for an empty atlas.
func bake_scale() -> float:
	return _scale


## The size of the page in texels, (0, 0) for an empty atlas.
func page_px() -> Vector2i:
	var page: ImageTexture = _atlas.texture()
	return Vector2i(page.get_size()) if page != null else Vector2i.ZERO


## How long `build` took, ms (the phone card's `atlas_bake_ms`).
func bake_ms() -> float:
	return _bake_usec / 1000.0


func is_empty() -> bool:
	return _atlas.texture() == null


## The bake in one console line, `atlas_bake_ms 312.4 | page 4096x2682 at 1.000` (the perf arena
## prints the same shape), for the log of CI and the console of the web preview.
func report() -> String:
	var page: Vector2i = page_px()
	var shape: String = "none" if is_empty() else "%dx%d at %.3f" % [page.x, page.y, _scale]
	return "atlas_bake_ms %.1f | page %s" % [bake_ms(), shape]


## How many frame keys (strings) the class has built: the hook behind the test that a frame change
## builds none.
static func keys_built() -> int:
	return _keys_built


static func _key(player: int, art_id: StringName, part: StringName, dir: int) -> StringName:
	_keys_built += 1
	return StringName("%d/%s/%s/%d" % [player, art_id, part, dir])


static func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## What to rasterise, found before anything is: a slot per distinct baked frame.
static func _collect(
	sheets: Array[IsoSheetDef], players: Array[IsoPlayerArt], read: Callable
) -> Plan:
	var plan: Plan = Plan.new()
	for player: int in players.size():
		var art: IsoPlayerArt = players[player]
		if art == null or not art.is_valid():
			push_error("IsoAtlas: player %d has no valid art (a faction and two triads)" % player)
			continue
		for sheet: IsoSheetDef in sheets:
			if sheet.faction == art.faction:
				_collect_sheet(plan, sheet, art, player, read)
	return plan


## Every frame of every part and direction of `sheet`: a slot per frame of a group, `&""` for a
## frame with no text, so the group keeps its length and its later frames their index.
static func _collect_sheet(
	plan: Plan, sheet: IsoSheetDef, art: IsoPlayerArt, player: int, read: Callable
) -> void:
	for part_name: String in sheet.parts:
		var part: StringName = StringName(part_name)
		var count: int = maxi(sheet.frame_count(part), 1)  # A sheet that says 0 has the one frame.
		for dir: int in sheet.directions(part):
			plan.keys.append(_key(player, sheet.art_id, part, dir))
			plan.spans.append(count)
			for frame: int in count:
				var path: String = sheet.path(part, dir, frame)
				var text: String = read.call(path)
				if text.is_empty():
					push_error("IsoAtlas: no SVG text at %s" % path)
					plan.slots.append(&"")
					continue
				var baked: String = art.recolour(text)
				# What no key colour touches is the same for every player: one slot for all.
				var slot: StringName = StringName(
					path if baked == text else "%d:%s" % [player, path]
				)
				plan.texts[slot] = baked
				plan.sizes[slot] = sheet.frame_size(part)
				plan.slots.append(slot)


## The slots of `plan`, tallest first (ties by name): the order `RuntimeAtlas.layout` packs them.
static func _packing_order(plan: Plan) -> Array[StringName]:
	var order: Array[StringName] = []
	for slot: StringName in plan.sizes:
		order.append(slot)
	order.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var ha: int = plan.sizes[a].y
			var hb: int = plan.sizes[b].y
			return ha > hb or (ha == hb and String(a) < String(b))
	)
	return order


static func _canvases(plan: Plan, order: Array[StringName]) -> Array[Vector2i]:
	var canvases: Array[Vector2i] = []
	for slot: StringName in order:
		canvases.append(plan.sizes[slot])
	return canvases


## Rasterises the slots in `order` at `scale` and packs them; every frame gets its slot's region.
func _bake(plan: Plan, order: Array[StringName], scale: float, keep_image: bool) -> void:
	var images: Dictionary[StringName, Image] = {}
	for slot: StringName in order:
		var image: Image = Image.new()
		if image.load_svg_from_string(plan.texts[slot], scale) != OK:
			image = null  # RuntimeAtlas reports it by name.
		images[slot] = image
	_atlas = RuntimeAtlas.build_images(images, PAGE_MAX_PX, keep_image)
	_scale = scale if _atlas.texture() != null else 0.0
	var at: int = 0
	for group: int in plan.keys.size():
		var span: int = plan.spans[group]
		_index[plan.keys[group]] = _table.size()
		for frame: int in span:
			_spans.append(span if frame == 0 else 0)
			_table.append(_atlas.region(plan.slots[at + frame]))
		at += span


## The frames of one build: slot (a baked frame) -> its SVG text and its canvas in 2x art px, and
## the groups in the order found, each a key (player, art id, part, direction), its frame count
## and the slot of each of its frames, group after group.
class Plan:
	var texts: Dictionary[StringName, String] = {}
	var sizes: Dictionary[StringName, Vector2i] = {}
	var keys: Array[StringName] = []
	var spans: PackedInt32Array = PackedInt32Array()
	var slots: Array[StringName] = []
