class_name DecalLayer
extends Node2D
## The ground decals at z 1 (ADR 0023 section 2, plan P115): under the unit shadows (2), the rings
## (3) and the fog (4), so a unit standing in front of a building stands on its cast shadow. It
## holds the building shadows, sprites that are regions of the match's one atlas (so all of them are
## one draw call), and the craters that destroyed buildings leave, sprites of one texture
## (`crater_texture`, `decals/crater.svg`, a second call and only once a crater exists). The
## shadows are children of `Shadows` and the craters of `Craters`, in that order, so a shadow that
## is added later never splits the craters' batch. The layer draws nothing itself and does no work
## in a frame: `BuildingLayer` adds and removes the sprites when the rows change.
## A crater is the art's ground circle (radius `CRATER_ART_RADIUS_MILLI`) scaled to the radius it
## is given; the art is centred on the pit. When the art is not in the project (P105 brings it) a
## crater is not drawn, and a texture assigned to `crater_texture` stands in (tests do).

const Z_DECALS: int = 1
const CRATER_ART: String = "res://assets/art/svg/decals/crater.svg"
## The radius of the ground circle that the crater art draws, milli-tiles (STYLE.md "Fields").
const CRATER_ART_RADIUS_MILLI: int = 1500

var crater_texture: Texture2D = null  ## Null: no crater art, so `add_crater` draws nothing.

var _shadows: Node2D = Node2D.new()
var _craters: Node2D = Node2D.new()


func _init() -> void:
	z_index = Z_DECALS
	z_as_relative = false
	_shadows.name = "Shadows"
	_craters.name = "Craters"
	add_child(_shadows)
	add_child(_craters)
	if ResourceLoader.exists(CRATER_ART):
		crater_texture = load(CRATER_ART) as Texture2D


## Takes `shadow`, a building's cast shadow, as a child of the layer.
func add_shadow(shadow: Sprite2D) -> void:
	_shadows.add_child(shadow)


## Gives `shadow` up and frees it.
func remove_shadow(shadow: Sprite2D) -> void:
	_shadows.remove_child(shadow)
	shadow.queue_free()


## The shadows the layer holds.
func shadow_count() -> int:
	return _shadows.get_child_count()


## Leaves a crater of ground radius `radius_milli` at the world px `at`; false, with nothing drawn,
## when there is no crater texture.
func add_crater(at: Vector2, radius_milli: int) -> bool:
	if crater_texture == null:
		return false
	var crater: Sprite2D = Sprite2D.new()
	crater.name = "Crater"
	crater.texture = crater_texture
	crater.position = at
	crater.scale = Vector2.ONE * (float(radius_milli) / CRATER_ART_RADIUS_MILLI)
	_craters.add_child(crater)
	return true


## The craters the layer holds.
func crater_count() -> int:
	return _craters.get_child_count()


## Forgets every shadow and crater (a new match).
func clear() -> void:
	for node: Node2D in [_shadows, _craters]:
		for child: Node in node.get_children():
			node.remove_child(child)
			child.queue_free()
