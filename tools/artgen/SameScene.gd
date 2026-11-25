class_name SameScene
extends RefCounted
## The same-scene check (ADR 0050 section 8, plan row P629): a headless composer and the measures
## of one look. It loads frames as the bake does (`Image.load_svg_from_string` through
## `IsoPlayerArt.recolour`) and blends with `Image`, no renderer. `sheet` builds the picture a PR
## attaches (`bash scripts/same-scene.sh OUT.png`); `audit` measures every roster sprite at zoom 1.0
## and names the bands it misses. The bands are `same_scene.tres`.

const BANDS_PATH: String = "res://tools/artgen/same_scene.tres"
const ART_SCALE: float = 0.5  ## 2x art at zoom 1.0.
const PARTS: Array[StringName] = [&"hull", &"turret", &"head"]
const PATCH: int = 3  ## Ground tiles on a side under a sprite.
const GAP: int = 8
const SIDE_PX: int = 32
const EDGE_STEP: float = 0.08  ## Luminance jump between neighbours that counts as an edge.
const DARK: float = 0.06
## The marker of the player's own units: Sne (white), the default of ADR 0050 section 3, answer 3;
## `mirror_triad` is the computer's. A frame carries the sentinel key, never shown as it is.
const OWN_TRIAD: Array[String] = ["#FFFFFF", "#DCE2E6", "#A3ACB3"]


## One sprite, ready to blend: its body and cast shadow as images on the same canvas.
class Sprite:
	var id: StringName
	var body: Image
	var shadow: Image
	var ground: Vector2i  ## The ground point in the images.


static func load_bands() -> SameSceneBands:
	return load(BANDS_PATH) as SameSceneBands


## The sprite of `art_id` for a player wearing `triad` (your own Sne when empty).
static func sprite(
	art_id: StringName, bands: SameSceneBands, zoom: float, triad: PackedStringArray = []
) -> Sprite:
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(art_id)
	var own: PackedStringArray = PackedStringArray(OWN_TRIAD)
	var art: IsoPlayerArt = IsoPlayerArt.make(
		sheet.faction,
		PackedStringArray(ArtPalette.KEYS[sheet.faction]),
		own if triad.is_empty() else triad
	)
	var dirs: PackedInt32Array = sheet.directions(&"hull")
	var want: int = bands.wanted_dir.get(sheet.faction, 0)
	var dir: int = want if dirs.has(want) else dirs[0]
	var scale: float = zoom * ART_SCALE
	var layers: Array = []  # [part, offset in art px]
	for part: StringName in [&"shadow"] + PARTS:
		if sheet.has_part(part):
			layers.append(
				[part, Vector2(0, 0) if part in [&"shadow", &"hull"] else sheet.mount(dir)]
			)
	var union: Rect2 = Rect2()
	for layer: Array in layers:
		var rect: Rect2 = Rect2(
			layer[1] - Vector2(sheet.origin(layer[0])), sheet.frame_size(layer[0])
		)
		union = rect if union.size == Vector2.ZERO else union.merge(rect)
	var out: Sprite = Sprite.new()
	out.id = art_id
	var size: Vector2i = Vector2i((union.size * scale).ceil()) + Vector2i.ONE
	out.body = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.shadow = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.ground = Vector2i(-union.position * scale)
	for layer: Array in layers:
		var part: StringName = layer[0]
		var image: Image = _raster(
			art.recolour(
				IsoAtlas.read_text(sheet.path(part, -1 if sheet.directions(part)[0] < 0 else dir))
			),
			scale
		)
		var at: Vector2i = Vector2i(
			(layer[1] - Vector2(sheet.origin(part)) - union.position) * scale
		)
		var target: Image = out.shadow if part == &"shadow" else out.body
		target.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	return out


static func _raster(text: String, scale: float) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text, scale)
	return image


static func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## The numbers the bands judge, for one sprite at zoom 1.0. Light from the north-west puts more
## luminance in the upper and the left half of a body than in the lower and the right half.
static func measure(s: Sprite) -> Dictionary:
	var box: Rect2i = s.body.get_used_rect()
	var halves: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])  # up, down, left, right
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var value: float = 0.0
	var sat: float = 0.0
	var area: int = 0
	var rim: int = 0
	var rim_dark: int = 0
	var edges: int = 0
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var c: Color = s.body.get_pixel(x, y)
			if c.a < 0.9:
				continue
			var l: float = _luma(c)
			area += 1
			value += c.v
			sat += c.s
			for i: int in [0 if y < box.get_center().y else 1, 2 if x < box.get_center().x else 3]:
				halves[i] += l
				counts[i] += 1
			if _on_rim(s.body, x, y):
				rim += 1
				rim_dark += 1 if l < DARK else 0
			if x + 1 < s.body.get_width() and y + 1 < s.body.get_height():
				var d: float = absf(l - _luma(s.body.get_pixel(x + 1, y)))
				d += absf(l - _luma(s.body.get_pixel(x, y + 1)))
				edges += 1 if d > EDGE_STEP else 0
	var half: Callable = func(i: int) -> float: return halves[i] / maxi(counts[i], 1)
	return {
		&"up_down": half.call(0) - half.call(1),
		&"left_right": half.call(2) - half.call(3),
		&"shadow_dx": (_centre(s.shadow).x - _centre(s.body).x) / maxf(box.size.x, 1.0),
		&"value": value / maxi(area, 1),
		&"sat": sat / maxi(area, 1),
		&"black_edge": float(rim_dark) / maxi(rim, 1),
		&"density": 100.0 * edges / maxi(area, 1),
		&"shadow_alpha": _peak_alpha(s.shadow),
		&"spread": _spread(s.body),
	}


static func _on_rim(image: Image, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at: Vector2i = Vector2i(x, y) + step
		if (
			at.x < 0
			or at.y < 0
			or at.x >= image.get_width()
			or at.y >= image.get_height()
			or image.get_pixelv(at).a < 0.5
		):
			return true
	return false


static func _centre(image: Image) -> Vector2:
	var box: Rect2i = image.get_used_rect()
	return Vector2(box.get_center())


static func _peak_alpha(image: Image) -> float:
	var peak: float = 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			peak = maxf(peak, image.get_pixel(x, y).a)
	return peak


static func _spread(image: Image) -> float:
	var box: Rect2i = image.get_used_rect()
	var small: Image = image.get_region(box)
	var factor: float = float(SIDE_PX) / maxi(box.size.x, box.size.y)
	small.resize(
		maxi(1, roundi(box.size.x * factor)),
		maxi(1, roundi(box.size.y * factor)),
		Image.INTERPOLATE_LANCZOS
	)
	var grey: Array[float] = []
	for y: int in small.get_height():
		for x: int in small.get_width():
			if small.get_pixel(x, y).a > 0.9:
				grey.append(_luma(small.get_pixel(x, y)) * 255.0)
	grey.sort()
	return 0.0 if grey.size() < 2 else grey[int(grey.size() * 0.95)] - grey[int(grey.size() * 0.05)]


## The bands `m` (from `measure`) misses, each a line naming the sprite `label`.
static func problems(label: String, m: Dictionary, b: SameSceneBands) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var low: Dictionary = {
		&"up_down": b.light_up_min,
		&"left_right": b.light_left_min,
		&"shadow_dx": b.shadow_dx_min,
		&"spread": b.spread_min
	}
	var span: Dictionary = {
		&"value": b.tone_value,
		&"sat": b.tone_sat,
		&"density": b.density,
		&"shadow_alpha": b.shadow_alpha
	}
	for key: StringName in low:
		if key == &"up_down" and b.exempt_up.has(StringName(label)):
			continue
		if m[key] < low[key]:
			out.append("%s %s %.3f below %.3f" % [label, key, m[key], low[key]])
	for key: StringName in span:
		if key == &"sat" and b.exempt_sat.has(StringName(label)):
			continue
		if m[key] < span[key].x or m[key] > span[key].y:
			out.append("%s %s %.3f outside %s" % [label, key, m[key], span[key]])
	if m[&"black_edge"] > b.black_edge_max:
		out.append("%s black_edge %.3f above %.3f" % [label, m[&"black_edge"], b.black_edge_max])
	return out


## Every roster sprite at zoom 1.0 against the bands: the problems, empty when the look holds.
static func audit(b: SameSceneBands) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in b.roster:
		out.append_array(problems(id, measure(sprite(StringName(id), b, 1.0)), b))
	return out


static func _patch(terrain: String, zoom: float) -> Image:
	var tile: Image = _raster(
		IsoAtlas.read_text(GroundAtlas.GROUND_PATH % [terrain, "a"]), zoom * ART_SCALE
	)
	var tw: int = tile.get_width()
	var th: int = tile.get_height()
	var patch: Image = Image.create_empty(PATCH * tw, PATCH * th, false, Image.FORMAT_RGBA8)
	for i: int in PATCH:
		for j: int in PATCH:
			patch.blend_rect(
				tile,
				Rect2i(Vector2i.ZERO, tile.get_size()),
				Vector2i((PATCH - 1 + i - j) * tw / 2, (i + j) * th / 2)
			)
	return patch


## Sprites on ground patches in a row at `y`; draws go to `ops` as [image, position].
static func _row(
	ops: Array, sprites: Array[Sprite], b: SameSceneBands, zoom: float, y: int, first: int
) -> int:
	var x: int = 0
	var height: int = 0
	for i: int in sprites.size():
		var s: Sprite = sprites[i]
		var patch: Image = _patch(b.terrains[(first + i) % b.terrains.size()], zoom)
		var centre: Vector2i = patch.get_size() / 2
		var rect: Rect2i = Rect2i(Vector2i.ZERO, patch.get_size()).merge(
			Rect2i(centre - s.ground, s.body.get_size())
		)
		var at: Vector2i = Vector2i(x, y) - rect.position
		ops.append_array(
			[[patch, at], [s.shadow, at + centre - s.ground], [s.body, at + centre - s.ground]]
		)
		x += rect.size.x + GAP
		height = maxi(height, rect.size.y)
	return height + GAP


static func _canvas(ops: Array, bg: Color) -> Image:
	var size: Vector2i = Vector2i.ZERO
	for op: Array in ops:
		size = size.max(op[1] + (op[0] as Image).get_size())
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(bg)
	for op: Array in ops:
		image.blend_rect(op[0], Rect2i(Vector2i.ZERO, (op[0] as Image).get_size()), op[1])
	return image


static func _plain(image: Image) -> Sprite:
	var s: Sprite = Sprite.new()
	s.body = image
	s.shadow = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	s.ground = image.get_size() / 2
	return s


## The sheet: the scene's four sprites on every zoom, a mirror row (the same unit and the same
## building in your own Sne and the computer's Karmin, so that only the marker differs), the
## effects, all graded as the world is, then the item cards and glyphs as the HUD draws them.
static func sheet(b: SameSceneBands) -> Image:
	var world: Array = []
	var y: int = 0
	for zoom_at: int in b.zooms.size():
		var row: Array[Sprite] = []
		for id: String in b.scene:
			row.append(sprite(StringName(id), b, b.zooms[zoom_at]))
		y += _row(world, row, b, b.zooms[zoom_at], y, zoom_at)
	var mirror: Array[Sprite] = []
	for at: int in [0, 2]:
		mirror.append(sprite(StringName(b.scene[at]), b, 1.0))
		mirror.append(sprite(StringName(b.scene[at]), b, 1.0, b.mirror_triad))
	y += _row(world, mirror, b, 1.0, y, 0)
	var atlas: Image = _raster(
		IsoAtlas.read_text("res://assets/art/svg/fx/effects_atlas.svg"), ART_SCALE
	)
	var puffs: Array[Sprite] = []
	for region: Rect2i in b.effects.values():
		puffs.append(_plain(atlas.get_region(region)))
	_row(world, puffs, b, 1.0, y, 1)
	var picture: Image = _canvas(world, Color(0.07, 0.08, 0.09))
	var grade: Image = Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	grade.set_pixel(0, 0, b.grade_warm)
	grade.set_pixel(1, 1, b.grade_cool)
	grade.set_pixel(1, 0, b.grade_warm.lerp(b.grade_cool, 0.5))
	grade.set_pixel(0, 1, b.grade_warm.lerp(b.grade_cool, 0.5))
	grade.resize(picture.get_width(), picture.get_height(), Image.INTERPOLATE_BILINEAR)
	picture.blend_rect(grade, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
	var hud: Array = []
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	var paths: PackedStringArray = PackedStringArray()
	for id: String in b.scene:
		paths.append(index.sheet(StringName(id)).icon)
	paths.append_array(b.glyphs)
	for at: int in paths.size():
		hud.append(
			[_raster(IsoAtlas.read_text(paths[at]), ART_SCALE), Vector2i(at * (64 + GAP), 0)]
		)
	var strip: Image = _canvas(hud, Color(0.12, 0.13, 0.15))
	var full: Image = Image.create_empty(
		maxi(picture.get_width(), strip.get_width()),
		picture.get_height() + strip.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	full.blit_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
	full.blit_rect(
		strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i(0, picture.get_height())
	)
	return full
