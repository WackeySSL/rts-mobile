extends RefCounted
## Generated units for the Units page of the art gallery (ADR 0023 section 5, plan row P101): a rig
## `Node2D` with the cast shadow, the hull and the turret of an art id, in its default view, drawn
## from the generator's frames (`assets/art/iso/`). The frame is the SVG text with the faction's key
## triad replaced by a player's, as the match-start bake does, and is rasterised at 0.5 x `zoom`
## (the 2x art at zoom 1 is half size), then drawn at 1 / `zoom`, so a rig scaled by `zoom` shows
## one texel per screen px, as the game's atlas does. Until the per-match atlas exists (P113) the
## gallery rasterises the frames itself, once per art id, triad and zoom: one instance holds the
## textures and the frame origins, and the gallery that made it frees them. View-only.

## The players' triads (ADR 0023 section 5), light, mid, dark: player 1 Signal, player 2 Arktisk.
const TRIADS: Array[Array] = [
	["#FF9446", "#E8681F", "#B04B12"],
	["#62D6EE", "#1FA6C8", "#137C99"],
]
const MODEL: String = "res://assets/art/models/fossil/%s.tres"
const BASE_SCALE: float = 0.5  ## 2x art at zoom 1: one tile is 64 px.
## The sprite names of a rig. The turret frame is not called `Turret`: the gallery turns every
## sprite of that name, and a frame cannot turn (the view picks one of 16).
const SHADOW: String = "Shadow"
const HULL: String = "Hull"
const GUN: String = "Gun"

var _origins: Dictionary[String, Vector2] = {}  ## "<art id> <part>": the frame's origin, 2x px.
var _mounts: Dictionary[String, Vector2] = {}  ## art id: where the turret sits, in px at zoom 1.
var _textures: Dictionary[String, ImageTexture] = {}


## A rig of `art_id` (a Derrick League unit) for `triad` (an index into `TRIADS`), named by the id
## in PascalCase, standing on its origin.
func make(art_id: String, triad: int) -> Node2D:
	var unit: Node2D = Node2D.new()
	unit.name = art_id.to_pascal_case()
	fill(unit, art_id, triad, 1.0)
	return unit


## Adds the sprites of `art_id` to `unit`, for a rig that will be scaled by `zoom`.
func fill(unit: Node2D, art_id: String, triad: int, zoom: float) -> void:
	var model: ArtModel = load(MODEL % art_id) as ArtModel
	if not _mounts.has(art_id):
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		for part: StringName in layouts:
			_origins["%s %s" % [art_id, part]] = Vector2(layouts[part].origin)
		_mounts[art_id] = ArtGen.mount_px(model, model.default_dir()) * BASE_SCALE
	unit.add_child(_sprite(model, &"shadow", triad, zoom, SHADOW, Vector2.ZERO))
	unit.add_child(_sprite(model, &"hull", triad, zoom, HULL, Vector2.ZERO))
	if model.parts().has(&"turret"):
		unit.add_child(_sprite(model, &"turret", triad, zoom, GUN, _mounts[art_id]))


func _sprite(
	model: ArtModel, part: StringName, triad: int, zoom: float, sprite_name: String, at: Vector2
) -> Sprite2D:
	var texel: float = BASE_SCALE * zoom
	var key: String = "%s %s %d %s" % [model.art_id, part, triad, zoom]
	if not _textures.has(key):
		var path: String = ArtGen.frame_path(model, part, model.default_dir())
		var text: String = FileAccess.get_file_as_string(path)
		for tone: int in 3:
			text = text.replace(ArtPalette.KEYS[model.faction][tone], TRIADS[triad][tone])
		var image: Image = Image.new()
		image.load_svg_from_string(text, texel)
		_textures[key] = ImageTexture.create_from_image(image)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = _textures[key]
	sprite.centered = false
	sprite.offset = -_origins["%s %s" % [model.art_id, part]] * texel
	sprite.scale = Vector2.ONE / zoom
	sprite.position = at
	return sprite
