class_name IsoAtlas
extends RefCounted
## The per-match atlas of the sorted world (ADR 0023 sections 2 and 5, plan P113): the frames of
## every player's faction, recoloured to the player's triad (`IsoPlayerArt.recolour`), rasterised
## with `Image.load_svg_from_string` and packed by `RuntimeAtlas` into pages (`texture(page)`): the
## y-sorted world is page `PAGE_SORTED`, one texture, so every sorted sprite batches into one call.
## `build` is for the main thread at match start.
## Each page is 4096 px wide and at most 4096 tall, cells packed tallest raster first (canvas height
## times `part_factor`). The bake scale is the largest `bake_scale * SCALE_STEP ^ k` (k = 0, 1,
## 2, ...), not below MIN_SCALE, whose page fits; the engine rounds a raster per axis, so a
## sprite draws its region at `0.5 / texels` per axis, `texels = raster_size / canvas` (see
## `texels_per_px`). When none fits, or there is no frame, the atlas is empty and the caller
## decides.
## A frame no key colour touches (a shadow) is baked once and shared by the players of a faction.
## A sheet of faction `neutral` is collected for every player, so each of its frames is one slot.
## The CPU page is dropped after the upload unless `keep_image` is set (tests read it).
## Two pages (P237, ADR 0036 section 15): the y-sorted world's frames lie on `PAGE_SORTED`; the cast
## shadows (part `shadow`, units' and buildings') are drawn in unsorted layers (the decal layer at
## z 1, the rigs' shadow children at z 2) and lie on `PAGE_UNSORTED`, which frees about 900 rows of
## the sorted page and later takes the flyers. A region lies in the texels of ITS page: take the
## texture with `texture_at(base)` (what `WorldSort.show_base` does) or `texture_for(part)`, never
## `texture()` for a part that may be on the other page. `page_of(part)` is keyed by the part only
## (P243 re-keys it for the flyers' hulls). Region keys do not change, and one scale fits both pages
## (the lower of the two `fit_scale` answers).
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
## The pages: the y-sorted world's, and the unsorted layers' (ADR 0036 section 15's page rule).
const PAGE_SORTED: int = 0
const PAGE_UNSORTED: int = 1
const PAGES: int = 2
## The parts of `PAGE_UNSORTED`: only parts drawn outside the y-sort.
const UNSORTED_PARTS: Array[StringName] = [&"shadow"]

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

var _pages: Array[RuntimeAtlas] = [RuntimeAtlas.new(), RuntimeAtlas.new()]  ## By page.
var _table_page: PackedByteArray = PackedByteArray()  ## Parallel to `_table`: the entry's page.
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
	var scale: float = _fit_pages(plan, bake_scale)
	if scale > 0.0 and not _packing_order(plan, PAGE_SORTED).is_empty():
		atlas._bake(plan, scale, keep_image)
	atlas._bake_usec = Time.get_ticks_usec() - started
	return atlas


## Page `page` (`PAGE_SORTED` unless given) of a bake of `sheets` for `players` at `scale` itself
## (no scale is lowered), found from the frame files alone: nothing is rasterised. Damage patches
## count at `part_factor`. (0, 0) for a page past the first that has no frame.
## `tests/view/test_iso_atlas_budget.gd` pins the page budget of ADR 0027 section 4 with it.
static func planned_page(
	sheets: Array[IsoSheetDef],
	players: Array[IsoPlayerArt],
	scale: float,
	reader: Callable = Callable(),
	page: int = PAGE_SORTED
) -> Vector2i:
	var plan: Plan = _collect(sheets, players, reader if reader.is_valid() else read_text)
	var order: Array[StringName] = _packing_order(plan, page)
	if order.is_empty() and page != PAGE_SORTED:
		return Vector2i.ZERO
	return page_size(_canvases(plan, order), scale, _factors(plan, order))


## Which page `part` is on: `PAGE_UNSORTED` for the parts of `UNSORTED_PARTS`, else `PAGE_SORTED`.
static func page_of(part: StringName) -> int:
	return PAGE_UNSORTED if part in UNSORTED_PARTS else PAGE_SORTED


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


## The scale a bake gets when every page must fit: the lowest of `fit_scale` of each page (an empty
## page fits at the requested scale), so the rule the tests pin is the one a match runs.
static func _fit_pages(plan: Plan, requested: float) -> float:
	var scale: float = requested
	for page: int in PAGES:
		var order: Array[StringName] = _packing_order(plan, page)
		scale = minf(scale, fit_scale(_canvases(plan, order), requested, _factors(plan, order)))
	return scale


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


## The texture of page `page` (`PAGE_SORTED` unless given); null for a page with no frame. A region
## lies in the texels of its own page: see the class comment.
func texture(page: int = PAGE_SORTED) -> ImageTexture:
	return _pages[page].texture()


## The texture of the page `part` is on (`page_of`).
func texture_for(part: StringName) -> ImageTexture:
	return texture(page_of(part))


## The texture of the page the frame group at `base_index` (see `base`) is on: what a sprite showing
## a region of that group must draw from. The sorted page's for no base (-1).
func texture_at(base_index: int) -> ImageTexture:
	if base_index < 0 or base_index >= _table_page.size():
		return texture()
	return texture(_table_page[base_index])


## The textures of the pages that have a frame.
func textures() -> Array[Texture2D]:
	var found: Array[Texture2D] = []
	for page: int in PAGES:
		if texture(page) != null:
			found.append(texture(page))
	return found


## The CPU-side page `page`, for tests: empty unless `build` got `keep_image`.
func image(page: int = PAGE_SORTED) -> Image:
	return _pages[page].image()


## The scale the match got, 0.0 for an empty atlas.
func bake_scale() -> float:
	return _scale


## The size of page `page` in texels, (0, 0) for a page with no frame.
func page_px(page: int = PAGE_SORTED) -> Vector2i:
	var texture_of: ImageTexture = texture(page)
	return Vector2i(texture_of.get_size()) if texture_of != null else Vector2i.ZERO


## How long `build` took, ms (the phone card's `atlas_bake_ms`).
func bake_ms() -> float:
	return _bake_usec / 1000.0


func is_empty() -> bool:
	return texture() == null


## The pages' sizes as one text, `4096x2659 + 4096x1040`: the pages in order, those with a frame
## only. "none" for an empty atlas.
func pages_text() -> String:
	var sizes: Array[String] = []
	for page: int in PAGES:
		if texture(page) != null:
			sizes.append("%dx%d" % [page_px(page).x, page_px(page).y])
	return " + ".join(sizes) if not sizes.is_empty() else "none"


## The bake in one console line, `atlas_bake_ms 312.4 | page 4096x2659 + 4096x1040 at 1.000` (the
## perf arena prints the same shape), for the log of CI and the console of the web preview.
func report() -> String:
	var shape: String = "none" if is_empty() else "%s at %.3f" % [pages_text(), _scale]
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


## Rasterises every page's slots at `scale` and packs them; every frame gets its slot's region and
## its page (`_table_page`).
func _bake(plan: Plan, scale: float, keep_image: bool) -> void:
	for page: int in PAGES:
		var order: Array[StringName] = _packing_order(plan, page)
		if not order.is_empty():
			_pages[page] = RuntimeAtlas.build_images(
				_rasterise(plan, order, scale), PAGE_MAX_PX, keep_image
			)
	_scale = scale if texture() != null else 0.0
	var at: int = 0
	for group: int in plan.keys.size():
		var span: int = plan.spans[group]
		_index[plan.keys[group]] = _table.size()
		for frame: int in span:
			_spans.append(span if frame == 0 else 0)
			var slot: StringName = plan.slots[at + frame]
			var page: int = page_of(plan.parts[slot]) if slot != &"" else PAGE_SORTED
			_table_page.append(page)
			_table.append(_pages[page].region(slot))
		at += span


## The slots of `order` rasterised at `scale` (a failed one is null, which RuntimeAtlas reports).
static func _rasterise(
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
