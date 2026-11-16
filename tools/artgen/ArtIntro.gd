class_name ArtIntro
extends RefCounted
## The intro art of plan row P520 (ADR 0043 sections 1 and 2): the app icon's two adaptive layers
## split into layer SVGs the intro animates, and the boot splash PNG (the icon on its background
## with the AppCode ApS wordmark small under it). `bash scripts/gen-intro.sh` writes both from the
## committed `icon_foreground.svg`, `icon_background.svg`, `app_icon.svg` and the brand SVGs; it
## never edits any of them. What the splitter cannot handle is reported as a problem, never
## dropped: `split` returns the problems and the generator exits 1 on any.

const FOREGROUND: String = "res://assets/art/svg/icon/icon_foreground.svg"
const BACKGROUND: String = "res://assets/art/svg/icon/icon_background.svg"
const ICON: String = "res://assets/art/svg/icon/app_icon.svg"
const WORDMARK: String = "res://assets/art/brand/appcode_wordmark_white.svg"
const LAYER_DIR: String = "res://assets/art/svg/intro/"
const SPLASH_PATH: String = "res://assets/art/splash/boot_splash.png"

## The foreground's layers back to front: file stem, first and last tag of its one clipped group
## (numbering its tags from its own open tag as 0; a nested group counts by its open and close
## tags), what it holds and its silhouette. Every tag of the group is in exactly one layer, in the
## source's order, so painting the layers in this order is the foreground.
const FOREGROUND_LAYERS: Array[Dictionary] = [
	{
		"name": "shadow",
		"from": 1,
		"to": 9,
		"what": "the ground shadows under the tank and its tracks",
		"shape": "a wide flat dark pool, a smaller pool at each end and thin strokes between",
	},
	{
		"name": "underlay",
		"from": 10,
		"to": 10,
		"what": "the dark underlay of the whole tank's outline",
		"shape": "one dark tank-shaped patch a little larger than the tank itself",
	},
	{
		"name": "track_far",
		"from": 11,
		"to": 13,
		"what": "the far right track's tread band and outer face without its cleats",
		"shape": "a long dark tread band rising to the right with a lit amber outer face",
	},
	{
		"name": "cleats_far",
		"from": 14,
		"to": 22,
		"what": "the far right track's three cleat blocks",
		"shape": "three stepped blocks, each a light top, a dark face and a dark end",
	},
	{
		"name": "hull",
		"from": 23,
		"to": 36,
		"what": "the far track's drive wheel and the hull with its glacis, deck and side face",
		"shape": "a wedge-nosed low box, a sloped front plate, a flat deck, a tall left side",
	},
	{
		"name": "track_near",
		"from": 37,
		"to": 47,
		"what": "the near left track's tread band, outer face and four road wheels",
		"shape": "a long dark tread band running down to the right over four round wheels",
	},
	{
		"name": "cleats_near",
		"from": 48,
		"to": 59,
		"what": "the near left track's four cleat blocks at its front",
		"shape": "four stacked blocks, each a grey top, a dark face and an amber end",
	},
	{
		"name": "hull_deck",
		"from": 60,
		"to": 79,
		"what": "the deck's edge highlights, front idler, lamps and hatches and the turret ring",
		"shape":
		"thin lit edges, a small round idler, two lamps and a hatch round a dark oval ring",
	},
	{
		"name": "turret",
		"from": 80,
		"to": 106,
		"what": "the turret with its broad gun mantlet",
		"shape": "a squat box turret with a sloped front and a wide square mantlet to the right",
	},
	{
		"name": "gun",
		"from": 107,
		"to": 120,
		"what": "the smoothbore gun with its band and stepped muzzle brake",
		"shape": "a long level barrel to the right, one band, a stepped muzzle the nearest shape",
	},
	{
		"name": "rim_light",
		"from": 121,
		"to": 127,
		"what": "the rim light and shading clipped to the tank and the glows on its flanks",
		"shape": "a thin bright line along the tank's outline and a round glow on each flank",
	},
	{
		"name": "clods",
		"from": 128,
		"to": 135,
		"what": "the dirt clods flung from the tracks, warm left and cool right",
		"shape": "four angular lumps with a dark shadow beside each, two at each side",
	},
	{
		"name": "sparks",
		"from": 136,
		"to": 147,
		"what": "the sparks and the four dust streaks behind the clods",
		"shape": "eight tiny round sparks at both sides and four thin pointed streaks",
	},
]

## The background's layers back to front, its tags numbered from 0 (it has no group). The radar
## ring and its sweep sit between the sky and the ground, which paints over the ring's lower arc,
## so what is not the ring is two layers, one under it and one over it.
const BACKGROUND_LAYERS: Array[Dictionary] = [
	{
		"name": "sky",
		"from": 0,
		"to": 3,
		"what": "the amber to cyan sky with its top shade, the bright haze and the glow",
		"shape": "an opaque square sky, warm at the left and cool at the right",
	},
	{
		"name": "ring",
		"from": 4,
		"to": 7,
		"what":
		"the radar ring: the dark outer band, the lit ring, the inner ring and twelve ticks",
		"shape":
		"a thin dark circle with a pale ring inside it, a smaller ring and twelve short ticks",
	},
	{
		"name": "sweep",
		"from": 8,
		"to": 16,
		"what": "the radar sweep: seven faint wedges, the bright sweep line and its tip",
		"shape": "a fading fan from the ring's centre to its upper right with a bright edge line",
	},
	{
		"name": "ground",
		"from": 17,
		"to": 47,
		"what": "the ground, the horizon haze, the glows, the flare, the turbine and the vignette",
		"shape": "a warm to cool ground, a flare stack on the left horizon, a turbine on the right",
	},
]

const COMMENT: String = (
	"Intro layer %s of the app icon's %s (%s), made by tools/artgen/ArtIntro.gd "
	+ "(bash scripts/gen-intro.sh) from %s, do not edit; painted in the order "
	+ "of ArtIntro.order() it gives the icon."
)

const SPLASH_SIDE: int = 1024  ## The PNG is a square; the engine fits it to the window.
const SPLASH_ICON_PX: int = 512  ## The icon at its own size, 1:1.
const SPLASH_BG: String = "#06080C"  ## The deepest ink of the palette, behind the icon's square.
const WORDMARK_RATIO: float = 0.30  ## The wordmark's width over the icon's (ADR 0043 note).
const GAP_RATIO: float = 0.08  ## Air between the icon and the wordmark, over the icon's width.
const MIN_WORDMARK_DP: float = 8.0  ## The wordmark's least height on a screen, in dp.

## What P533 sets in project.godot. Godot 4.7.2's `application/boot_splash/stretch_mode` is the
## enum "Disabled,Keep,Keep Width,Keep Height,Cover,Ignore" (the property's own hint, read from
## the editor binary; default 1). `Keep` fits the whole image inside the window and keeps its
## aspect, so `fits` models exactly that, centred; the placement is checked on the phone in P533.
## There is no `fullsize` key in 4.7.2.
const BOOT_SPLASH_STRETCH_KEEP: int = 1
const BOOT_SPLASH_SETTINGS: Dictionary[String, Variant] = {
	"application/boot_splash/image": SPLASH_PATH,
	"application/boot_splash/show_image": true,
	"application/boot_splash/stretch_mode": BOOT_SPLASH_STRETCH_KEEP,
	"application/boot_splash/bg_color": SPLASH_BG,
	"application/boot_splash/use_filter": true,
}


## The layer stems back to front over the whole icon: the background's, then the foreground's.
static func order() -> Array[String]:
	var found: Array[String] = []
	for layer: Dictionary in BACKGROUND_LAYERS + FOREGROUND_LAYERS:
		found.append(layer["name"])
	return found


## The SVG text of every layer by file stem, in `order()`, and the problems found. A source the
## splitter cannot split faithfully gives problems (and no layers for it).
static func generate() -> Dictionary:
	var files: Dictionary[String, String] = {}
	var problems: PackedStringArray = PackedStringArray()
	var sources: Array[Dictionary] = [
		{"path": BACKGROUND, "label": "background", "wrap": false, "layers": BACKGROUND_LAYERS},
		{"path": FOREGROUND, "label": "foreground", "wrap": true, "layers": FOREGROUND_LAYERS},
	]
	for source: Dictionary in sources:
		var done: Dictionary = split(
			FileAccess.get_file_as_string(source["path"]),
			source["layers"],
			source["wrap"],
			source["label"],
			String(source["path"]).get_file()
		)
		problems.append_array(done["problems"])
		files.merge(done["files"])
	return {"files": files, "problems": problems}


## Splits one icon layer's SVG `text`: `layers` are runs of tags (see FOREGROUND_LAYERS), `wrap`
## says the body is one group whose open tag is tag 0 and close tag the last. Returns `files`
## (stem -> text) and `problems`; anything it cannot carry over faithfully is a problem: text it
## does not tokenise (an element that is not self-closing, anything but `g`), a layer that starts
## or ends inside a nested group, layers that leave a gap, a def it cannot copy (it refers to
## another by `href` or `url(`) or cannot find, and a def block that is not a gradient or clip.
static func split(
	text: String, layers: Array[Dictionary], wrap: bool, label: String, file: String
) -> Dictionary:
	var problems: PackedStringArray = PackedStringArray()
	var files: Dictionary[String, String] = {}
	var cut: int = text.find("</defs>")
	if cut < 0:
		problems.append("%s: no </defs>" % file)
		return {"files": files, "problems": problems}
	var defs: Dictionary[String, String] = _defs(text.substr(0, cut), problems, file)
	var body: String = text.substr(cut + 7).replace("</svg>", "").strip_edges()
	var tags: PackedStringArray = PackedStringArray()
	var tag: RegEx = RegEx.create_from_string("<g[^>]*>|</g>|<[a-zA-Z]+[^>]*/>")
	var rest: String = body
	for match: RegExMatch in tag.search_all(body):
		tags.append(match.get_string())
		rest = rest.replace(match.get_string(), "")
	if not rest.strip_edges().is_empty():
		problems.append("%s: cannot tokenise: %s" % [file, rest.strip_edges().left(80)])
	var depth: PackedInt32Array = PackedInt32Array()
	var open: int = 0
	for t: String in tags:
		if t == "</g>":
			open -= 1
		depth.append(open)
		if t.begins_with("<g"):
			open += 1
	if open != 0:
		problems.append("%s: groups do not close" % file)
	var base: int = 1 if wrap else 0
	var first: int = 1 if wrap else 0
	var last: int = tags.size() - 2 if wrap else tags.size() - 1
	if wrap and (tags.size() < 2 or not tags[0].begins_with("<g") or tags[-1] != "</g>"):
		problems.append("%s: the body is not one group" % file)
	var next: int = first
	for layer: Dictionary in layers:
		var from: int = layer["from"]
		var to: int = layer["to"]
		if from != next or to < from or to > last:
			problems.append("%s: layer %s breaks the run at tag %d" % [file, layer["name"], next])
			continue
		next = to + 1
		# A layer is whole groups only: it starts and ends at the base depth.
		var closing: int = depth[to] + (1 if tags[to].begins_with("<g") else 0)
		if depth[from] != base or closing != base:
			problems.append("%s: layer %s starts or ends inside a group" % [file, layer["name"]])
	if next != last + 1:
		problems.append("%s: the layers end at tag %d of %d" % [file, next - 1, last])
	if not problems.is_empty():
		return {"files": {}, "problems": problems}
	for layer: Dictionary in layers:
		var chunk: String = ""
		for i: int in range(layer["from"], layer["to"] + 1):
			chunk += tags[i]
		var made: String = _document(layer, chunk, defs, wrap, label, file, problems)
		files[layer["name"]] = made
	if not problems.is_empty():
		return {"files": {}, "problems": problems}
	return {"files": files, "problems": problems}


## The lockup's rects in PNG px, `icon` and `wordmark`, centred as one block in the square.
static func lockup(wordmark_size: Vector2i) -> Dictionary[String, Rect2i]:
	var gap: int = roundi(SPLASH_ICON_PX * GAP_RATIO)
	var height: int = SPLASH_ICON_PX + gap + wordmark_size.y
	var top: int = (SPLASH_SIDE - height) / 2
	var rects: Dictionary[String, Rect2i] = {}
	rects["icon"] = Rect2i((SPLASH_SIDE - SPLASH_ICON_PX) / 2, top, SPLASH_ICON_PX, SPLASH_ICON_PX)
	rects["wordmark"] = Rect2i(
		(SPLASH_SIDE - wordmark_size.x) / 2,
		top + SPLASH_ICON_PX + gap,
		wordmark_size.x,
		wordmark_size.y
	)
	return rects


## The size the wordmark has in the PNG.
static func wordmark_size() -> Vector2i:
	return _raster(WORDMARK, _wordmark_scale()).get_size()


## The lockup's rects in the px of a window of `screen` px when the engine shows the PNG with
## `stretch_mode` Keep: scaled by min(width, height) / side and centred.
static func placed(
	rects: Dictionary[String, Rect2i], screen: Vector2i
) -> Dictionary[String, Rect2]:
	var scale: float = minf(float(screen.x), float(screen.y)) / SPLASH_SIDE
	var offset: Vector2 = (Vector2(screen) - Vector2.ONE * SPLASH_SIDE * scale) / 2.0
	var found: Dictionary[String, Rect2] = {}
	for part: String in rects:
		var rect: Rect2i = rects[part]
		found[part] = Rect2(offset + Vector2(rect.position) * scale, Vector2(rect.size) * scale)
	return found


## Whether the lockup, placed as above on a window of `screen` px with `px_per_dp` window px to
## the dp, lies inside `safe` (the whole window when it has no area) and the wordmark is at least
## `MIN_WORDMARK_DP` high.
static func fits(
	rects: Dictionary[String, Rect2i], screen: Vector2i, px_per_dp: float, safe: Rect2i = Rect2i()
) -> bool:
	var area: Rect2 = Rect2(safe) if safe.has_area() else Rect2(Vector2.ZERO, Vector2(screen))
	var on_screen: Dictionary[String, Rect2] = placed(rects, screen)
	var block: Rect2 = on_screen["icon"].merge(on_screen["wordmark"])
	return area.encloses(block) and on_screen["wordmark"].size.y / px_per_dp >= MIN_WORDMARK_DP


## The splash: the background, the icon rendered 1:1 and the wordmark at 30 % of its width.
static func splash() -> Image:
	var word: Image = _raster(WORDMARK, _wordmark_scale())
	var icon: Image = _raster(ICON, 1.0)
	var rects: Dictionary[String, Rect2i] = lockup(word.get_size())
	var image: Image = Image.create(SPLASH_SIDE, SPLASH_SIDE, false, Image.FORMAT_RGBA8)
	image.fill(Color.html(SPLASH_BG))
	image.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), rects["icon"].position)
	image.blend_rect(word, Rect2i(Vector2i.ZERO, word.get_size()), rects["wordmark"].position)
	image.convert(Image.FORMAT_RGB8)
	return image


## An SVG text rasterised on the CPU at `scale`, as RGBA8.
static func raster_text(text: String, scale: float) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text, scale)
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _wordmark_scale() -> float:
	var canvas: RegExMatch = RegEx.create_from_string('<svg[^>]* width="([0-9.]+)"').search(
		FileAccess.get_file_as_string(WORDMARK)
	)
	return SPLASH_ICON_PX * WORDMARK_RATIO / canvas.get_string(1).to_float()


static func _raster(path: String, scale: float) -> Image:
	return raster_text(FileAccess.get_file_as_string(path), scale)


## The gradients and clip paths of a `<defs>` block by id. Anything else in it is a problem.
static func _defs(
	head: String, problems: PackedStringArray, file: String
) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	var id: RegEx = RegEx.create_from_string('id="([^"]+)"')
	var item: RegEx = RegEx.create_from_string(
		"(?s)<(linearGradient|radialGradient|clipPath)\\b.*?</\\1>"
	)
	var rest: String = head.substr(head.find("<defs>") + 6) if head.contains("<defs>") else ""
	for match: RegExMatch in item.search_all(head):
		var def: String = match.get_string()
		var named: RegExMatch = id.search(def)
		if named == null:
			problems.append("%s: a def without an id" % file)
			continue
		found[named.get_string(1)] = def
		rest = rest.replace(def, "")
	if not rest.strip_edges().is_empty():
		problems.append("%s: a def that is no gradient or clip path: %s" % [file, rest.left(60)])
	return found


static func _document(
	layer: Dictionary,
	chunk: String,
	defs: Dictionary[String, String],
	wrap: bool,
	label: String,
	file: String,
	problems: PackedStringArray
) -> String:
	var used: PackedStringArray = PackedStringArray()
	if wrap:
		used.append("fc")
	for match: RegExMatch in RegEx.create_from_string("url\\(#([^)]+)\\)").search_all(chunk):
		if not used.has(match.get_string(1)):
			used.append(match.get_string(1))
	var kept: String = ""
	for id: String in used:
		if not defs.has(id):
			problems.append("%s: layer %s uses the missing def %s" % [file, layer["name"], id])
			continue
		if defs[id].contains("href") or defs[id].contains("url("):
			problems.append("%s: def %s refers to another def" % [file, id])
	for id: String in defs:
		if used.has(id):
			kept += defs[id]
	var lines: PackedStringArray = PackedStringArray()
	var comment: String = COMMENT % [layer["name"], label, layer["what"], file]
	lines.append("<!-- %s -->" % comment)
	lines.append("<!-- Silhouette: %s. -->" % layer["shape"])
	lines.append(
		'<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">'
	)
	lines.append("<defs>%s</defs>" % kept)
	lines.append('<g clip-path="url(#fc)">%s</g>' % chunk if wrap else chunk)
	lines.append("</svg>")
	return "\n".join(lines) + "\n"
