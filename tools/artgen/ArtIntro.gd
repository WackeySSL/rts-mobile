class_name ArtIntro
extends RefCounted
## The intro art of plan row P520 (ADR 0043 sections 1 and 2): the app icon's foreground split into
## layer SVGs the intro animates, and the boot splash PNG (the icon on its background with the
## AppCode ApS wordmark small under it). `bash scripts/gen-intro.sh` writes both from the committed
## `icon_foreground.svg`, `app_icon.svg` and the brand SVGs; it never edits any of them.

const SOURCE: String = "res://assets/art/svg/icon/icon_foreground.svg"
const ICON: String = "res://assets/art/svg/icon/app_icon.svg"
const WORDMARK: String = "res://assets/art/brand/appcode_wordmark_white.svg"
const LAYER_DIR: String = "res://assets/art/svg/intro/"
const SPLASH_PATH: String = "res://assets/art/splash/boot_splash.png"

## The layers back to front: file stem, first and last tag of the source's one clipped group
## (numbering its tags from its own open tag as 0; a nested group counts by its open and close
## tags), what it holds and its silhouette. Every tag of the group is in exactly one layer, in the
## source's order, so painting the layers in this order is the icon.
const LAYERS: Array[Dictionary] = [
	{
		"name": "shadow",
		"from": 1,
		"to": 9,
		"what": "the ground shadows under the tank and its tracks",
		"shape": "a wide flat dark pool, a smaller pool at each end and thin strokes between",
	},
	{
		"name": "track_far",
		"from": 10,
		"to": 24,
		"what": "the far right track with its cleats over the tank's dark underlay",
		"shape": "a long dark tread band rising to the right, raised cleats along its face",
	},
	{
		"name": "hull",
		"from": 25,
		"to": 36,
		"what": "the hull with its glacis, deck and side face",
		"shape": "a wedge-nosed low box, a sloped front plate, a flat deck, a tall left side",
	},
	{
		"name": "track_near",
		"from": 37,
		"to": 65,
		"what": "the near left track with its cleats and wheels",
		"shape": "a long dark tread band running down to the right, cleats and a round idler",
	},
	{
		"name": "hull_deck",
		"from": 66,
		"to": 79,
		"what": "the deck's lamps and hatches and the dark turret ring",
		"shape": "two small lamps and a hatch around a dark oval ring at the hull's centre",
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
const COMMENT: String = (
	"Intro layer %s of the app icon's foreground (%s), made by tools/artgen/ArtIntro.gd "
	+ "(bash scripts/gen-intro.sh) from icon_foreground.svg, do not edit; painted in the order "
	+ "of ArtIntro.LAYERS over icon_background.svg it gives the icon."
)

const SPLASH_SIDE: int = 1024  ## The PNG is a square; the engine fits it to the window.
const SPLASH_ICON_PX: int = 512  ## The icon at its own size, 1:1.
const SPLASH_BG: String = "#06080C"  ## The deepest ink of the palette, behind the icon's square.
const WORDMARK_RATIO: float = 0.30  ## The wordmark's width over the icon's (ADR 0043 note).
const GAP_RATIO: float = 0.08  ## Air between the icon and the wordmark, over the icon's width.
const SAFE_RATIO: float = 0.8  ## The lockup stays within this share of the short side.
const MIN_WORDMARK_PX: float = 12.0  ## The wordmark's least height on a screen, in px.


## The SVG text of every layer, by file stem.
static func layers() -> Dictionary[String, String]:
	var source: String = FileAccess.get_file_as_string(SOURCE)
	var defs: Dictionary[String, String] = _defs(source)
	var tags: PackedStringArray = _tags(source)
	var found: Dictionary[String, String] = {}
	for layer: Dictionary in LAYERS:
		var body: String = ""
		for i: int in range(layer["from"], layer["to"] + 1):
			body += tags[i]
		found[layer["name"]] = _document(layer, body, defs)
	return found


## The first tag after the last layer when the layers join up from tag 1 without a gap, else -1.
static func covered() -> int:
	var next: int = 1
	for layer: Dictionary in LAYERS:
		if layer["from"] != next:
			return -1
		next = layer["to"] + 1
	return next


## The number of tags of the source's group, its open and close tags included.
static func tag_count() -> int:
	return _tags(FileAccess.get_file_as_string(SOURCE)).size()


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


## Whether the lockup stays within `SAFE_RATIO` of a screen's short side and the wordmark is at
## least `MIN_WORDMARK_PX` high, when the engine fits the square PNG to a screen of `screen` px.
static func fits(rects: Dictionary[String, Rect2i], screen: Vector2i) -> bool:
	var short: int = mini(screen.x, screen.y)
	var scale: float = float(short) / SPLASH_SIDE
	var block: Rect2i = rects["icon"].merge(rects["wordmark"])
	return (
		block.size.y * scale <= SAFE_RATIO * short
		and rects["wordmark"].size.y * scale >= MIN_WORDMARK_PX
	)


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


## The tags of the source's one clipped group, numbered from its own open tag as 0.
static func _tags(source: String) -> PackedStringArray:
	var body: String = source.substr(source.find("</defs>") + 7)
	var found: PackedStringArray = PackedStringArray()
	var tag: RegEx = RegEx.create_from_string("<g[^>]*>|</g>|<[a-z]+[^>]*/>")
	for match: RegExMatch in tag.search_all(body):
		found.append(match.get_string())
	return found


static func _defs(source: String) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	var id: RegEx = RegEx.create_from_string('id="([^"]+)"')
	var item: RegEx = RegEx.create_from_string(
		"(?s)<(linearGradient|radialGradient|clipPath)\\b.*?</\\1>"
	)
	for match: RegExMatch in item.search_all(source.substr(0, source.find("</defs>"))):
		found[id.search(match.get_string()).get_string(1)] = match.get_string()
	return found


static func _document(layer: Dictionary, body: String, defs: Dictionary[String, String]) -> String:
	var used: PackedStringArray = PackedStringArray(["fc"])
	for match: RegExMatch in RegEx.create_from_string("url\\(#([^)]+)\\)").search_all(body):
		if not used.has(match.get_string(1)):
			used.append(match.get_string(1))
	var kept: String = ""
	for id: String in defs:
		if used.has(id):
			kept += defs[id]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("<!-- %s -->" % (COMMENT % [layer["name"], layer["what"]]))
	lines.append("<!-- Silhouette: %s. -->" % layer["shape"])
	lines.append(
		'<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">'
	)
	lines.append("<defs>%s</defs>" % kept)
	lines.append('<g clip-path="url(#fc)">%s</g>' % body)
	lines.append("</svg>")
	return "\n".join(lines) + "\n"
