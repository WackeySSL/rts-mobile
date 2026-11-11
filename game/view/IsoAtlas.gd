class_name IsoAtlas
extends RefCounted
## The per-match atlas of the sorted world (ADR 0023 sections 2 and 5, plan P113): the frames of
## every player's faction, recoloured to the player's triad (`IsoPlayerArt.recolour`), rasterised
## with `Image.load_svg_from_string` and packed by `RuntimeAtlas` into one page (`texture()`), so
## every sorted sprite batches into one call. `build` is for the main thread at match start.
## The page is 4096 px wide and at most 4096 tall, cells packed tallest raster first (canvas height
## times `part_factor`). The bake scale is the largest `bake_scale * SCALE_STEP ^ k` (k = 0, 1,
## 2, ...), not below MIN_SCALE, whose page fits; the engine rounds a raster per axis, so a
## sprite draws its region at `0.5 / texels` per axis, `texels = raster_size / canvas` (see
## `texels_per_px`). When none fits, or there is no frame, the atlas is empty and the caller
## decides.
## A frame no key colour touches (a shadow) is baked once and shared by the players of a faction.
## A sheet of faction `neutral` is collected for every player, so each of its frames is one slot.
## The CPU page is dropped after the upload unless `keep_image` is set (tests read it).
## Two pages (P237, ADR 0036 section 15): the y-sorted world's frames lie on page 1, so that every
## sorted sprite batches into one call; the cast shadows (part `shadow`, units' and buildings')
## are drawn in unsorted layers (the decal layer at z 1, the rigs' shadow children at z 2) and lie
## on page 2, which frees about 900 rows of page 1 and later takes the flyers. `page_of(part)` says
## which page a part is on and `texture_for(part)` gives its texture; `texture()` is page 1. Region
## keys do not change, and one scale fits both pages.
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
## The hand-written neutral sheet of the damage overlays (ADR 0028 section 4), read from this one
## path and not through the index; the file may not exist yet (row P160), and then there is none.
const NEUTRAL_SHEET: String = "res://assets/art/svg/damage/damage_sheet.tres"
const NEUTRAL: StringName = &"neutral"  ## The faction of a sheet every player's atlas carries.
## The parts of page 2 (unsorted layers only; ADR 0036 section 15's page rule).
const PAGE_TWO_PARTS: Array[StringName] = [&"shadow"]

## The damage patches (`dmg1`, `dmg2`, ADR 0028 section 3, amended 2026-11-03) are rasterised at
## `bake_scale * DAMAGE_SCALE` so that their large frames keep the page in its budget; every other
## part stays at `bake_scale`. A view constant, not balance. `part_factor` is the one place that
## names the parts; `WorldSort.dress` sizes a sprite per axis from the raster, so it is right for
## a patch too. The generator's 4 px art overlap at the cut is 3 texels at bake scale 1.0 and
## under one at MIN_SCALE, so the rule for the Damage child (P159) keeps the body clipped and the
## overlap > 0 at every scale (the drawn position at MIN_SCALE is P159's test). It assumes even
## canvases, as all 80 real parts are: an odd one at 0.25 gives exactly 0 (H=101, cut=97).
## Every row below holds for a patch that is a sibling of the body (same parent, same position);
## under the ghost body (`BuildingAnims.dress_ghost`) the patch is a child with `scale =
## body_texels / patch_texels` and `offset = -origin * patch_texels`, as the ghost's Anim.
## `show_frame` and `show_base` rewrite `region_rect`, so apply the trim again after each one.
## (a) trim the body at T = `body_cut_row(cut, canvas_h, region_h)` texels: `region.position.y +=
## T`, `region.size.y -= T`, `offset.y += T`; (b) set `region_filter_clip_enabled = true` on the
## trimmed body; (c) the patch uses its whole region, through `dress`; (d) invariant, strict:
## `(patch.offset.y + patch region.size.y) * patch.scale.y > body.offset.y * body.scale.y`.
const DAMAGE_SCALE: float = 0.75
const DAMAGE_PARTS: Array[StringName] = [&"dmg1", &"dmg2"]

static var _keys_built: int = 0

var _atlas: RuntimeAtlas = RuntimeAtlas.new()
var _atlas2: RuntimeAtlas = RuntimeAtlas.new()  ## Page 2: the shadows.
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


## The neutral sheet at `path`, null while the file does not exist: no error, no slot, a bake as
## it was before the sheet. A file there that is no neutral `IsoSheetDef` is an error, and null.
static func load_neutral_sheet(path: String) -> IsoSheetDef:
	if not ResourceLoader.exists(path):
		return null
	var sheet: IsoSheetDef = load(path) as IsoSheetDef
	var problem: String = neutral_problem(sheet, path)
	if problem != "":
		push_error(problem)
		return null
	return sheet


## What is wrong with `sheet` read from `path` as the neutral sheet, "" when nothing is.
static func neutral_problem(sheet: IsoSheetDef, path: String) -> String:
	if sheet == null or sheet.faction != NEUTRAL:
		return "IsoAtlas: %s is no neutral IsoSheetDef" % path
	for views: int in sheet.counts:
		if views != 1:
			return "IsoAtlas: %s has a neutral part with %d views, not 1" % [path, views]
	return ""


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
	var plan: Plan = _collect(sheets, players, reader if reader.is_valid() else read_text)
	var order: Array[StringName] = _packing_order(plan, 0)
	var order2: Array[StringName] = _packing_order(plan, 1)
	var scale: float = _fit_pages(plan, order, order2, bake_scale)
	if scale > 0.0 and not order.is_empty():
		atlas._bake(plan, order, order2, scale, keep_image)
	atlas._bake_usec = Time.get_ticks_usec() - started
	return atlas


## The page a bake of `sheets` for `players` takes at `scale` itself (no scale is lowered), found
## from the frame files alone: nothing is rasterised. Damage patches count at `part_factor`.
## `tests/view/test_iso_atlas_budget.gd` pins
## the page budget of ADR 0027 section 4 with it.
static func planned_page(
	sheets: Array[IsoSheetDef],
	players: Array[IsoPlayerArt],
	scale: float,
	reader: Callable = Callable()
) -> Vector2i:
	var plan: Plan = _collect(sheets, players, reader if reader.is_valid() else read_text)
	var order: Array[StringName] = _packing_order(plan, 0)
	return page_size(_canvases(plan, order), scale, _factors(plan, order))


## The size of page 2 (the shadows) a bake would take at `scale`, as `planned_page` finds it;
## (0, 0) when no frame is a page 2 frame.
static func planned_page2(
	sheets: Array[IsoSheetDef],
	players: Array[IsoPlayerArt],
	scale: float,
	reader: Callable = Callable()
) -> Vector2i:
	var plan: Plan = _collect(sheets, players, reader if reader.is_valid() else read_text)
	var order: Array[StringName] = _packing_order(plan, 1)
	if order.is_empty():
		return Vector2i.ZERO
	return page_size(_canvases(plan, order), scale, _factors(plan, order))


## Which page `part` is on: 1 for the parts of `PAGE_TWO_PARTS`, else 0 (the sorted world's page).
static func page_of(part: StringName) -> int:
	return 1 if part in PAGE_TWO_PARTS else 0


## The texels per px of the 2x art a canvas of `canvas` px really has at `scale`, per axis: the
## raster is rounded, so this is `raster_size / canvas`, not `scale`. A sprite draws at `0.5 /
## this` and its offset is `-origin * this`. `Vector2.ONE` for a zero canvas.
static func texels_per_px(canvas: Vector2i, scale: float) -> Vector2:
	if canvas.x <= 0 or canvas.y <= 0:
		return Vector2.ONE * scale
	return Vector2(raster_size(canvas, scale)) / Vector2(canvas)


## The size in texels the engine rasterises a canvas of `canvas` px (2x art) to at `scale`.
static func raster_size(canvas: Vector2i, scale: float) -> Vector2i:
	return Vector2i(maxi(1, roundi(canvas.x * scale)), maxi(1, roundi(canvas.y * scale)))


## The page `canvases` (2x art px, in packing order) take at `scale`, gutters included. `factors`
## (parallel to `canvases`, empty for all 1.0) is each canvas's `part_factor`.
static func page_size(
	canvases: Array[Vector2i], scale: float, factors: Array[float] = []
) -> Vector2i:
	assert(factors.is_empty() or factors.size() == canvases.size(), "one factor per canvas")
	var cells: Array[Vector2i] = []
	for at: int in canvases.size():
		var factor: float = factors[at] if at < factors.size() else 1.0
		cells.append(RuntimeAtlas.cell_size(raster_size(canvases[at], scale * factor)))
	var places: Array[Vector2i] = []
	return RuntimeAtlas.layout(cells, PAGE_MAX_PX, places)


## The scale a bake gets when both pages must fit (page 2 may be empty).
static func _fit_pages(
	plan: Plan, order: Array[StringName], order2: Array[StringName], requested: float
) -> float:
	var canvases: Array[Vector2i] = _canvases(plan, order)
	var factors: Array[float] = _factors(plan, order)
	var canvases2: Array[Vector2i] = _canvases(plan, order2)
	var factors2: Array[float] = _factors(plan, order2)
	var scale: float = requested
	while scale >= MIN_SCALE:
		var page: Vector2i = page_size(canvases, scale, factors)
		var page2: Vector2i = (
			page_size(canvases2, scale, factors2) if not order2.is_empty() else Vector2i.ZERO
		)
		if page.y <= PAGE_MAX_PX and page2.y <= PAGE_MAX_PX and page.x <= PAGE_MAX_PX:
			return scale
		scale *= SCALE_STEP
	return 0.0


## The scale a bake of `canvases` gets when `requested`: see the class comment. 0.0 when none.
static func fit_scale(
	canvases: Array[Vector2i], requested: float, factors: Array[float] = []
) -> float:
	assert(factors.is_empty() or factors.size() == canvases.size(), "one factor per canvas")
	var scale: float = requested
	while scale >= MIN_SCALE:
		var page: Vector2i = page_size(canvases, scale, factors)
		if page.x <= PAGE_MAX_PX and page.y <= PAGE_MAX_PX:
			return scale
		scale *= SCALE_STEP
	return 0.0


## How much of the bake scale a frame of `part` is rasterised at: DAMAGE_SCALE for a damage patch,
## else 1.0. Frame-path safe: comparisons only.
static func part_factor(part: StringName) -> float:
	return DAMAGE_SCALE if part in DAMAGE_PARTS else 1.0


## The requested texels per px of the 2x art for `part` (`bake_scale * part_factor`); 0.0 for an
## empty atlas. The raster rounds each axis, so a sprite sizes itself per axis from
## `raster_size` (see `WorldSort.dress`), not from this number alone.
func part_scale(part: StringName) -> float:
	return _scale * part_factor(part)


## The first body row, in texels, below a cut `cut` art px down a canvas `canvas_h` art px tall
## whose raster is `region_h` texels tall: the integer ceil of `cut * region_h / canvas_h`.
@warning_ignore("integer_division")
static func body_cut_row(cut: int, canvas_h: int, region_h: int) -> int:
	return (cut * region_h + canvas_h - 1) / canvas_h


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


## The texture of the page `part` is on (`page_of`): page 2's for a shadow; null when it has none.
func texture_for(part: StringName) -> ImageTexture:
	return _atlas2.texture() if page_of(part) == 1 else _atlas.texture()


## Page 2's size in texels, (0, 0) for none.
func page2_px() -> Vector2i:
	var page: ImageTexture = _atlas2.texture()
	return Vector2i(page.get_size()) if page != null else Vector2i.ZERO


## The CPU-side page 2, for tests: empty unless `build` got `keep_image`.
func image2() -> Image:
	return _atlas2.image()


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


## The text of the file at `path`, "" when there is none.
static func read_text(path: String) -> String:
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
			if sheet.faction == art.faction or sheet.faction == NEUTRAL:
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
				plan.parts[slot] = part
				plan.slots.append(slot)


## The slots of `plan`, tallest raster first (ties by name): the order `RuntimeAtlas.layout`
## packs them, for page `page` (`page_of`).
static func _packing_order(plan: Plan, page: int) -> Array[StringName]:
	var order: Array[StringName] = []
	for slot: StringName in plan.sizes:
		if page_of(plan.parts[slot]) == page:
			order.append(slot)
	order.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var ha: float = plan.sizes[a].y * part_factor(plan.parts[a])
			var hb: float = plan.sizes[b].y * part_factor(plan.parts[b])
			return ha > hb or (ha == hb and String(a) < String(b))
	)
	return order


static func _factors(plan: Plan, order: Array[StringName]) -> Array[float]:
	var factors: Array[float] = []
	for slot: StringName in order:
		factors.append(part_factor(plan.parts[slot]))
	return factors


static func _canvases(plan: Plan, order: Array[StringName]) -> Array[Vector2i]:
	var canvases: Array[Vector2i] = []
	for slot: StringName in order:
		canvases.append(plan.sizes[slot])
	return canvases


## Rasterises the slots in `order` at `scale` and packs them; every frame gets its slot's region.
func _bake(
	plan: Plan, order: Array[StringName], order2: Array[StringName], scale: float, keep_image: bool
) -> void:
	_atlas = RuntimeAtlas.build_images(_rasterise(plan, order, scale), PAGE_MAX_PX, keep_image)
	if not order2.is_empty():
		_atlas2 = RuntimeAtlas.build_images(
			_rasterise(plan, order2, scale), PAGE_MAX_PX, keep_image
		)
	_scale = scale if _atlas.texture() != null else 0.0
	var at: int = 0
	for group: int in plan.keys.size():
		var span: int = plan.spans[group]
		_index[plan.keys[group]] = _table.size()
		for frame: int in span:
			_spans.append(span if frame == 0 else 0)
			var slot: StringName = plan.slots[at + frame]
			var on_two: bool = slot != &"" and page_of(plan.parts[slot]) == 1
			_table.append((_atlas2 if on_two else _atlas).region(slot))
		at += span


## The slots of `order` rasterised at `scale` (a failed one is null, which RuntimeAtlas reports).
func _rasterise(
	plan: Plan, order: Array[StringName], scale: float
) -> Dictionary[StringName, Image]:
	var images: Dictionary[StringName, Image] = {}
	for slot: StringName in order:
		var image: Image = Image.new()
		if (
			image.load_svg_from_string(plan.texts[slot], scale * part_factor(plan.parts[slot]))
			!= OK
		):
			image = null
		images[slot] = image
	return images


## The frames of one build: slot (a baked frame) -> its SVG text and its canvas in 2x art px, and
## the groups in the order found, each a key (player, art id, part, direction), its frame count
## and the slot of each of its frames, group after group.
class Plan:
	var texts: Dictionary[StringName, String] = {}
	var sizes: Dictionary[StringName, Vector2i] = {}
	var parts: Dictionary[StringName, StringName] = {}  ## Slot -> the part it is a frame of.
	var keys: Array[StringName] = []
	var spans: PackedInt32Array = PackedInt32Array()
	var slots: Array[StringName] = []
