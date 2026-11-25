extends RefCounted
## What the detail renderer suites share (plan row P631): the three fixture models of
## `tests/art/fixtures/detail/` (a tank hull at detail 1, 2 and 3, each with a number, a hazard
## patch and a vent), their frames built in memory, and a same-scene sprite made from them. Not a
## test suite (no GdUnitTestSuite base).

const DIR: String = "res://tests/art/fixtures/detail/p631_l%d.tres"
const VIEW_DIR: int = 6  ## The default view of a fossil unit (same_scene.tres).

static var _built: Dictionary[int, Dictionary] = {}


static func model(level: int) -> ArtModel:
	return load(DIR % level) as ArtModel


## Every file of the fixture at `level`, as `ArtGen.build` gives them (built once).
static func files(level: int) -> Dictionary[String, String]:
	if not _built.has(level):
		_built[level] = ArtGen.build(model(level))
	var found: Dictionary[String, String] = {}
	found.assign(_built[level])
	return found


## The frame files (`.svg`) of the fixture's body parts, the shadow too, without the item card.
static func frames(level: int) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	var all: Dictionary[String, String] = files(level)
	for path: String in all:
		if path.ends_with(".svg") and not path.contains("/icons/"):
			found[path] = all[path]
	return found


## The fixture at `level` as a same-scene sprite at `zoom`, its parts rasterised from `frames`.
static func sprite(level: int, zoom: float = 1.0) -> SameScene.Sprite:
	var m: ArtModel = model(level)
	var keys: PackedStringArray = PackedStringArray(ArtPalette.KEYS[m.faction])
	var art: IsoPlayerArt = IsoPlayerArt.make(m.faction, keys, keys)
	var scale: float = zoom * SameScene.ART_SCALE
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(m)
	var layers: Array = []
	var union: Rect2 = Rect2()
	for part: StringName in [&"shadow", &"hull", &"turret"]:
		var at: Vector2 = ArtGen.mount_px(m, VIEW_DIR) if part == &"turret" else Vector2.ZERO
		var rect: Rect2 = Rect2(at - Vector2(layouts[part].origin), Vector2(layouts[part].size))
		union = rect if layers.is_empty() else union.merge(rect)
		layers.append([part, at])
	var out: SameScene.Sprite = SameScene.Sprite.new()
	out.id = m.art_id
	var size: Vector2i = Vector2i((union.size * scale).ceil()) + Vector2i.ONE
	out.body = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.shadow = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.ground = Vector2i(-union.position * scale)
	for layer: Array in layers:
		var part: StringName = layer[0]
		var path: String = ArtGen.frame_path(m, part, VIEW_DIR)
		var image: Image = SameScene._raster(art.recolour(files(level)[path]), scale)
		var at: Vector2i = Vector2i(
			(layer[1] - Vector2(layouts[part].origin) - union.position) * scale
		)
		(out.shadow if part == &"shadow" else out.body).blend_rect(
			image, Rect2i(Vector2i.ZERO, image.get_size()), at
		)
	return out
