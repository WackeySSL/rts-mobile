extends RefCounted
## Generated units for the Units page of the art gallery (ADR 0023 section 5, plan rows P101 and
## P102): a rig `Node2D` with the cast shadow, the hull and the turret of an art id (a Derrick
## League unit or a Lumen Accord one), in its default view (`d06` or `d10`), drawn from the
## generator's frames (`assets/art/iso/`). The frame is the SVG text with the faction's key triad
## replaced by a player's, as the match-start bake does, and is rasterised at 0.5 x `zoom`
## (the 2x art at zoom 1 is half size), then drawn at 1 / `zoom`, so a rig scaled by `zoom` shows
## one texel per screen px, as the game's atlas does. Until the per-match atlas exists (P113) the
## gallery rasterises the frames itself, once per art id, triad and zoom: one instance holds the
## textures and the frame origins, and the gallery that made it frees them. A squad also plays its
## poses (plan row P139): its `Hull` sprite stands, walks, stands and fidgets in turn in the same
## default view (`advance`), so that a phone shows how the three figures step. View-only.

## The players' triads (ADR 0023 section 5), light, mid, dark: player 1 Signal, player 2 Arktisk.
const TRIADS: Array[Array] = [
	["#FF9446", "#E8681F", "#B04B12"],
	["#62D6EE", "#1FA6C8", "#137C99"],
]
const MODEL: String = "res://assets/art/models/%s/%s.tres"
## The Lumen Accord's art ids start with this; the Derrick League's have no prefix.
const ACCORD_PREFIX: String = "renew_"
const BASE_SCALE: float = 0.5  ## 2x art at zoom 1: one tile is 64 px.
## The sprite names of a rig. The turret frame is not called `Turret`: the gallery turns every
## sprite of that name, and a frame cannot turn (the view picks one of 16).
const SHADOW: String = "Shadow"
const HULL: String = "Hull"
const GUN: String = "Gun"
## A squad's script in seconds, as the game will show it (P142): the standing frame, the walk, the
## standing frame, idle 0, the standing frame, idle 1. A walk frame lasts about a quarter of a real
## walk cycle (2 to 3 a second), an idle frame a window of its own.
const STAND_S: float = 1.0
const WALK_S: float = 2.4
const IDLE_S: float = 1.3
const WALK_FRAME_S: float = 0.1
const POSE_CYCLE_S: float = 3.0 * STAND_S + WALK_S + 2.0 * IDLE_S
const POSE_PHASE_S: float = 0.9  ## Each squad starts this much after the one made before it.


## A squad that plays its poses: the frames its hull sprite can show (the standing one, the walk,
## then the idle) and the one it shows, written to the sprite only when it changes.
class Squad:
	extends RefCounted
	var hull: Sprite2D = null
	var textures: Array[ImageTexture] = []
	var offsets: PackedVector2Array = PackedVector2Array()
	var walk_frames: int = 0
	var phase: float = 0.0  ## Seconds further on in the script than the gallery's clock.
	var shown: int = 0

	## The frame (an index of `textures`) `t` seconds into the script.
	func frame_at(t: float) -> int:
		if t >= STAND_S and t < STAND_S + WALK_S:
			return 1 + int((t - STAND_S) / WALK_FRAME_S) % walk_frames
		var idle_at: float = t - 2.0 * STAND_S - WALK_S
		if idle_at >= 0.0 and idle_at < IDLE_S:
			return 1 + walk_frames
		return 2 + walk_frames if idle_at >= IDLE_S + STAND_S else 0

	func play(t: float) -> void:
		var index: int = frame_at(t)
		if index != shown:
			shown = index
			hull.texture = textures[index]
			hull.offset = offsets[index]


var _origins: Dictionary[String, Vector2] = {}  ## "<art id> <part>": the frame's origin, 2x px.
var _mounts: Dictionary[String, Vector2] = {}  ## art id: where the turret sits, in px at zoom 1.
var _textures: Dictionary[String, ImageTexture] = {}
var _squads: Array[Squad] = []  ## The squads that play poses.
var _clock: float = 0.0


## A rig of `art_id` (a unit of either faction) for `triad` (an index into `TRIADS`), named by the
## id in PascalCase, standing on its origin.
func make(art_id: String, triad: int) -> Node2D:
	var unit: Node2D = Node2D.new()
	unit.name = art_id.to_pascal_case()
	fill(unit, art_id, triad, 1.0)
	return unit


## Adds the sprites of `art_id` to `unit`, for a rig that will be scaled by `zoom`.
func fill(unit: Node2D, art_id: String, triad: int, zoom: float) -> void:
	var faction: String = "renew" if art_id.begins_with(ACCORD_PREFIX) else "fossil"
	var model: ArtModel = load(MODEL % [faction, art_id]) as ArtModel
	if not _mounts.has(art_id):
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		for part: StringName in layouts:
			_origins["%s %s" % [art_id, part]] = Vector2(layouts[part].origin)
		_mounts[art_id] = ArtGen.mount_px(model, model.default_dir()) * BASE_SCALE
	unit.add_child(_sprite(model, &"shadow", triad, zoom, SHADOW, Vector2.ZERO))
	unit.add_child(_sprite(model, &"hull", triad, zoom, HULL, Vector2.ZERO))
	if model.pose_frames(&"walk") > 0:
		_add_squad(model, unit.get_node(HULL) as Sprite2D, triad, zoom)
	if model.parts().has(&"turret"):
		unit.add_child(_sprite(model, &"turret", triad, zoom, GUN, _mounts[art_id]))


## Where in the script the squads are `delta` seconds later: a squad a little behind the one made
## before it.
func advance(delta: float) -> void:
	_clock += delta
	for squad: Squad in _squads:
		squad.play(fposmod(_clock + squad.phase, POSE_CYCLE_S))


func _add_squad(model: ArtModel, hull: Sprite2D, triad: int, zoom: float) -> void:
	var squad: Squad = Squad.new()
	squad.hull = hull
	squad.phase = _squads.size() * POSE_PHASE_S
	squad.walk_frames = model.frames(&"walk")
	squad.textures.append(hull.texture as ImageTexture)
	squad.offsets.append(hull.offset)
	for part: StringName in [&"walk", &"idle"]:
		var origin: Vector2 = _origins["%s %s" % [model.art_id, part]]
		for frame: int in model.frames(part):
			squad.textures.append(_texture(model, part, triad, zoom, frame))
			squad.offsets.append(-origin * BASE_SCALE * zoom)
	_squads.append(squad)


func _sprite(
	model: ArtModel, part: StringName, triad: int, zoom: float, sprite_name: String, at: Vector2
) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = _texture(model, part, triad, zoom)
	sprite.centered = false
	sprite.offset = -_origins["%s %s" % [model.art_id, part]] * BASE_SCALE * zoom
	sprite.scale = Vector2.ONE / zoom
	sprite.position = at
	return sprite


## The texture of a frame in the default view (`frame` -1: the part has one), made once.
func _texture(
	model: ArtModel, part: StringName, triad: int, zoom: float, frame: int = -1
) -> ImageTexture:
	var key: String = "%s %s %d %s %d" % [model.art_id, part, triad, zoom, frame]
	if not _textures.has(key):
		var path: String = ArtGen.frame_path(model, part, model.default_dir(), frame)
		var text: String = FileAccess.get_file_as_string(path)
		for tone: int in 3:
			text = text.replace(ArtPalette.KEYS[model.faction][tone], TRIADS[triad][tone])
		var image: Image = Image.new()
		image.load_svg_from_string(text, BASE_SCALE * zoom)
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]
